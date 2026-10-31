class_name SimBoundaryTest
extends SimTestBase
## LT-34/S2: the sim / presentation boundary guard (docs/design/LT-33-sim-presentation-boundary.md,
## "Proposed automated guard"). Static scans of the sources found by path under res://:
##  1. sim/ uses only its own types and a pinned engine allowlist (no Node, Tween, Engine, OS,
##     Time, Input, Color, ...), none of the forbidden tokens (signal, await, get_tree, frame
##     callbacks, global RNG, scene loads);
##  2. scenes/, ui/ and tools/ never reach a private Simulation member (`sim._x`, or any
##     `_name` declared in simulation.gd) or write sim.state / sim.config fields;
##  3. is_fake stays out of presentation (render_isolation_test is the main guard and must stay);
## and two runtime proofs: the sim plays a whole game without a SceneTree, and a Game driven
## by uneven frames ends in the state a bare Simulation reaches by stepping the same commands.

const SIM_DIR := "res://sim"
const PRESENTATION_DIRS := ["res://scenes", "res://ui", "res://tools"]
const SIMULATION := "res://sim/core/simulation.gd"
## Engine types sim/ may name today (computed from the code once and pinned, LT-34/S2).
const ENGINE_ALLOWLIST := [
	"Array", "Callable", "Dictionary", "FileAccess", "PackedByteArray", "PackedInt64Array",
	"PackedStringArray", "RandomNumberGenerator", "RefCounted", "RegEx", "String", "Variant",
	"Vector2", "Vector2i",
]
## Matched on the code of a sim file with comments and string literals blanked.
const SIM_FORBIDDEN_CODE := [
	"\\bsignal\\b",
	"\\bawait\\b",
	"\\bpreload\\b",
	"\\bget_tree\\b",
	"\\bget_node\\b",
	"\\bget_parent\\b",
	"\\bcreate_tween\\b",
	"\\bqueue_free\\b",
	"\\$[A-Za-z_]",
	"func\\s+_(process|physics_process|input|unhandled_input|unhandled_key_input|ready|draw|enter_tree|exit_tree|notification)\\b",
	"(?<![.\\w])(randf|randi|randf_range|randi_range|randfn|randomize|seed|rand_from_seed)\\s*\\(",
]
## Matched on the code with comments removed but string literals kept.
const SIM_FORBIDDEN_WITH_STRINGS := [
	"\\bload\\s*\\(\\s*\"res://(scenes|ui|shaders|assets|tools)",
	"\"res://(scenes|ui|shaders|assets)/",
]
const WRITE_PATTERNS := [
	"\\.state\\.\\w+(\\[[^\\]]*\\])?\\s*(=(?!=)|\\+=|-=|\\*=|/=)",
	"\\.config\\.\\w+(\\.\\w+)*\\s*(=(?!=)|\\+=|-=|\\*=|/=)",
]
const STEPS_AFTER_FRAMES := 3000

var _vp: SubViewport


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null


# --- scanning helpers ------------------------------------------------------------------

## Every .gd file below `dir` (a res:// path), sorted.
func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		if not sub.begins_with("."):
			out.append_array(_gd_files(dir.path_join(sub)))
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	out.sort()
	return out


## `line` without its `#` comment; string literals are blanked ("") unless `keep_strings`.
func _code_of(line: String, keep_strings := false) -> String:
	var out := ""
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				if keep_strings:
					out += line.substr(i, 2)
				i += 2
				continue
			if c == quote:
				quote = ""
				out += c
			elif keep_strings:
				out += c
			i += 1
			continue
		if c == "#":
			break
		if c == "\"" or c == "'":
			quote = c
		out += c
		i += 1
	return out


## [line number, code] pairs of a source text.
func _code_lines(text: String, keep_strings := false) -> Array:
	var out := []
	var lines := text.split("\n")
	for i in lines.size():
		out.append([i + 1, _code_of(lines[i], keep_strings)])
	return out


## `file:line: match` for every hit of `pattern` in the code lines.
func _find(file: String, code_lines: Array, pattern: String) -> Array[String]:
	var re := RegEx.create_from_string(pattern)
	var out: Array[String] = []
	for entry: Array in code_lines:
		for m in re.search_all(entry[1]):
			out.append("%s:%d: %s" % [file, entry[0], m.get_string()])
	return out


## Own type names: every class_name, `class X` and `enum X` declared under sim/.
func _own_types(files: Array[String]) -> Dictionary:
	var re := RegEx.create_from_string("(?m)^\\s*(?:class_name|class|enum)\\s+([A-Z]\\w*)")
	var own := {}
	for f in files:
		for m in re.search_all(FileAccess.get_file_as_string(f)):
			own[m.get_string(1)] = true
	return own


## PascalCase identifiers (a capital, then at least one lower-case letter somewhere; ALL_CAPS
## constants are not types) that are neither own types nor on the engine allowlist.
func _foreign_types(file: String, text: String, own: Dictionary) -> Array[String]:
	var re := RegEx.create_from_string("\\b[A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*\\b")
	var out: Array[String] = []
	for entry: Array in _code_lines(text):
		for m in re.search_all(entry[1]):
			var name := m.get_string()
			if not own.has(name) and not ENGINE_ALLOWLIST.has(name):
				out.append("%s:%d: %s" % [file, entry[0], name])
	return out


func _private_members_of_simulation() -> Array[String]:
	var re := RegEx.create_from_string("(?m)^(?:func|var|const)\\s+(_[a-z]\\w*)")
	var out: Array[String] = []
	for m in re.search_all(FileAccess.get_file_as_string(SIMULATION)):
		var name := m.get_string(1)
		if name != "_init" and not out.has(name):
			out.append(name)
	return out


func _presentation_files() -> Array[String]:
	var out: Array[String] = []
	for dir: String in PRESENTATION_DIRS:
		out.append_array(_gd_files(dir))
	return out


# --- the scanner itself (so a silent scanner cannot pass the scans) ----------------------

func test_the_scanner_blanks_comments_and_strings_and_flags_engine_types() -> void:
	var own := {"Simulation": true, "Type": true}
	var text := "var a: Simulation\nvar t: Tween  ## Node in a comment\nvar s := \"Control # x\" # Input\n" \
		+ "var c := Color(1, 0, 0)\nvar o := Type.SHOT\nvar v: Vector2i\nvar q := 'it\\'s Node'\n"
	var hits := _foreign_types("f.gd", text, own)
	assert_array(hits).is_equal(["f.gd:2: Tween", "f.gd:4: Color"])
	assert_array(_find("f.gd", _code_lines("var x = get_tree() # signal"), "\\bsignal\\b")).is_empty()
	assert_array(_find("f.gd", _code_lines("var x = get_tree()"), "\\bget_tree\\b")).has_size(1)
	assert_array(_find("f.gd", _code_lines("var x = r.randf()"), SIM_FORBIDDEN_CODE[10])).is_empty()
	assert_array(_find("f.gd", _code_lines("var x = randf()"), SIM_FORBIDDEN_CODE[10])).has_size(1)
	assert_array(_find("f.gd", _code_lines("var s = load(\"res://ui/hud.gd\")", true),
		SIM_FORBIDDEN_WITH_STRINGS[0])).has_size(1)
	assert_array(_find("f.gd", _code_lines("game.sim._add_sanity(1)"), "\\bsim\\._\\w+")).has_size(1)
	assert_array(_find("f.gd", _code_lines("g.state.gold += 5"), WRITE_PATTERNS[0])).has_size(1)
	assert_array(_find("f.gd", _code_lines("if g.state.gold == 5:"), WRITE_PATTERNS[0])).is_empty()
	assert_array(_find("f.gd", _code_lines("g.config.sanity.max = 1"), WRITE_PATTERNS[1])).has_size(1)


func test_the_scans_cover_the_expected_files() -> void:
	var sim_files := _gd_files(SIM_DIR)
	assert_array(sim_files).contains([SIMULATION, "res://sim/config.gd",
		"res://sim/core/sim_state.gd", "res://sim/defs/tower_def.gd"])
	var pres := _presentation_files()
	assert_array(pres).contains(["res://scenes/game.gd", "res://scenes/board.gd",
		"res://ui/hud.gd", "res://ui/tower_panel.gd", "res://tools/bot_runs.gd"])
	for f in pres:
		assert_bool(f.begins_with("res://sim/") or f.begins_with("res://tests/")).is_false()
	assert_array(_private_members_of_simulation()).contains(["_add_sanity", "_spawner",
		"_change_reserve", "_reserve_drives_mad"])
	assert_dict(_own_types(sim_files)).contains_keys(["Simulation", "GameConfig", "CommandResult",
		"Phase", "SanityState"])


# --- 1: what sim/ may use ----------------------------------------------------------------

func test_sim_names_only_own_types_and_allowlisted_engine_types() -> void:
	var files := _gd_files(SIM_DIR)
	var own := _own_types(files)
	var bad: Array[String] = []
	for f in files:
		bad.append_array(_foreign_types(f, FileAccess.get_file_as_string(f), own))
	assert_array(bad).override_failure_message(
		"sim/ names types outside its own classes and the allowlist:\n" + "\n".join(bad)).is_empty()


func test_the_engine_allowlist_is_not_stale() -> void:
	# Every allowlisted engine type is still used somewhere in sim/ (shrink the list when not).
	var files := _gd_files(SIM_DIR)
	var used := {}
	var re := RegEx.create_from_string("\\b[A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*\\b")
	for f in files:
		for entry: Array in _code_lines(FileAccess.get_file_as_string(f)):
			for m in re.search_all(entry[1]):
				used[m.get_string()] = true
	for t: String in ENGINE_ALLOWLIST:
		assert_bool(used.has(t)).override_failure_message("%s is allowlisted but unused" % t).is_true()


func test_sim_uses_no_forbidden_tokens() -> void:
	var bad: Array[String] = []
	for f in _gd_files(SIM_DIR):
		var text := FileAccess.get_file_as_string(f)
		var code := _code_lines(text)
		var with_strings := _code_lines(text, true)
		for p: String in SIM_FORBIDDEN_CODE:
			bad.append_array(_find(f, code, p))
		for p: String in SIM_FORBIDDEN_WITH_STRINGS:
			bad.append_array(_find(f, with_strings, p))
	assert_array(bad).override_failure_message(
		"sim/ uses presentation or engine-runtime constructs:\n" + "\n".join(bad)).is_empty()


# --- 2: what scenes/, ui/ and tools/ may touch -------------------------------------------

func test_presentation_calls_no_private_simulation_member() -> void:
	var private := _private_members_of_simulation()
	var by_name := "\\.(%s)\\b" % "|".join(private)
	var bad: Array[String] = []
	for f in _presentation_files():
		var code := _code_lines(FileAccess.get_file_as_string(f))
		bad.append_array(_find(f, code, "\\bsim\\._\\w+"))
		bad.append_array(_find(f, code, by_name))
	assert_array(bad).override_failure_message(
		"presentation reaches a private Simulation member (use a public command/query):\n"
		+ "\n".join(bad)).is_empty()


func test_presentation_writes_no_sim_state_or_config() -> void:
	var bad: Array[String] = []
	for f in _presentation_files():
		var code := _code_lines(FileAccess.get_file_as_string(f))
		for p: String in WRITE_PATTERNS:
			bad.append_array(_find(f, code, p))
	assert_array(bad).override_failure_message(
		"presentation writes sim.state / config fields:\n" + "\n".join(bad)).is_empty()


# --- 3: the is_fake leak guard stays ------------------------------------------------------

func test_the_is_fake_leak_guard_is_kept_and_presentation_is_clean() -> void:
	var guard := FileAccess.get_file_as_string("res://tests/render_isolation_test.gd")
	assert_str(guard).contains("test_no_script_outside_sim_and_tests_can_tell_a_fake")
	assert_str(guard).contains("\"\\\\bis_fake\\\\b\"")
	var bad: Array[String] = []
	for f in _presentation_files():
		bad.append_array(_find(f, _code_lines(FileAccess.get_file_as_string(f)), "\\bis_fake\\b"))
	assert_array(bad).is_empty()


# --- 4: the sim needs no SceneTree ---------------------------------------------------------

func test_a_whole_game_runs_without_a_scene_tree() -> void:
	var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var in_process := SimNoTreeLoop.run()
	assert_float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)).is_equal(nodes_before)
	assert_str(in_process).contains("outcome=")
	assert_bool(in_process.contains("outcome=0")).override_failure_message(
		"the bot game reached no outcome: " + in_process).is_false()
	assert_bool(in_process.begins_with("CONFIG ERROR")).is_false()
	# The same game in a process whose main loop is a plain MainLoop (no SceneTree at all).
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", "res://tests/sim_no_tree_loop.gd"],
		out, true)
	var text := "\n".join(PackedStringArray(out))
	assert_int(code).override_failure_message("exit %d:\n%s" % [code, text]).is_equal(0)
	var digest := ""
	for line in text.split("\n"):
		if line.begins_with(SimNoTreeLoop.MARKER):
			digest = line.trim_prefix(SimNoTreeLoop.MARKER).strip_edges()
	assert_str(digest).override_failure_message("no digest in:\n" + text).is_equal(in_process)


# --- 5: a frame-driven run equals direct stepping ------------------------------------------

## [tick, command, args...] issued through Game once sim.state.tick has reached `tick`.
## Builds name a buildable-cell index (see _cells); upgrade / priority name the def built.
const PLAN := [
	[0, "build", "rifleman", 0],
	[0, "build", "harpooner", 3],
	[200, "upgrade", "rifleman", ""],
	[400, "call_wave"],
	[700, "set_target_priority", "harpooner", "strongest"],
]

var _cells: Array[Vector2i] = []


## Buildable cells of the real map, row-major.
func _load_cells(config: GameConfig) -> void:
	var sim := Simulation.new(config, 7)
	_cells.clear()
	for y in sim.state.map.height:
		for x in sim.state.map.width:
			if sim.state.map.is_buildable(Vector2i(x, y)):
				_cells.append(Vector2i(x, y))


func _tower_of(game: Game, def_id: String) -> int:
	for c: Array in PLAN:
		if c[1] == "build" and c[2] == def_id:
			return game.sim.state.tower_at[_cells[int(c[3])]]
	return -1


func _dispatch(game: Game, c: Array) -> int:
	match c[1]:
		"build": return game.build(c[2], _cells[int(c[3])])
		"upgrade": return game.upgrade(_tower_of(game, c[2]), c[3])
		"set_target_priority": return game.set_target_priority(_tower_of(game, c[2]), c[3])
		"call_wave": return game.call_wave()
	return -1


func _frame_run(config: GameConfig, frame_seed: int) -> Game:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1152, 648)
	add_child(_vp)
	var game := Game.new()
	game.setup(config, 7)
	_vp.add_child(game)
	game.set_process(false)  # advance() below is the body of Game._process
	await get_tree().process_frame
	_load_cells(config)
	game.sim.debug_set_sanity(70.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = frame_seed
	var next := 0
	var shadow := SimClock.new()  # grants the ticks a frame owes; Game must step exactly that many
	var expected := 0
	for frame in STEPS_AFTER_FRAMES:
		while next < PLAN.size() and game.sim.state.tick >= int(PLAN[next][0]):
			var r := _dispatch(game, PLAN[next])
			assert_int(r).override_failure_message("%s -> %d" % [PLAN[next], r]).is_equal(0)
			next += 1
		if frame == 50:
			game.toggle_pause()
		elif frame == 70:
			game.toggle_pause()
		elif frame == 150 or frame == 600:
			game.toggle_speed()
		# Uneven frames: fast, slow, hitches (the clock caps catch-up at 8 steps).
		var delta: float = [1.0 / 144.0, 1.0 / 30.0, 0.2, 1.0 / 60.0][rng.randi() % 4] \
			* rng.randf_range(0.5, 1.5)
		shadow.speed = game.clock.speed
		expected += shadow.advance(delta)
		game.advance(delta)
		if game.sim.state.outcome == SimState.Outcome.NONE:
			assert_int(game.sim.state.tick).override_failure_message(
				"frame %d: Game stepped %d ticks, the clock granted %d" % [frame,
				game.sim.state.tick, expected]).is_equal(expected)
		if game.sim.state.tick >= 1800 or game.sim.state.outcome != SimState.Outcome.NONE:
			break
	return game


func _state_digest(sim: Simulation) -> String:
	var parts: Array[String] = [SimNoTreeLoop.digest(sim), "cap=%s st=%d phase=%d relics=%s" % [
		sim.state.sanity_cap, sim.state.sanity_state, sim.state.phase, str(sim.state.relics)]]
	for e in sim.state.enemies:
		parts.append("e%d:%s:%s:%d" % [e.id, e.def.id, e.hp, e.distance])
	for t in sim.state.towers:
		parts.append("t%d:%s:%d:%s:%s" % [t.id, t.def.id, t.level, t.target_priority, t.cell])
	return "\n".join(parts)


func test_a_frame_driven_game_equals_direct_stepping() -> void:
	var config := real_config()
	var game: Game = await _frame_run(config, 1234)
	var sim := game.sim
	var log: Array = sim.state.command_log
	var names: Array = log.map(func(c: Array) -> String: return c[1])
	assert_array(names).contains(["debug_set_sanity", "build", "upgrade", "call_wave",
		"set_target_priority"])
	assert_int(sim.state.tick).is_greater(700)  # the run really advanced through its plan
	assert_int(sim.state.towers.size()).is_equal(2)
	# The same log on a bare sim: step to each entry's tick, apply it, step to the end.
	var bare := Simulation.new(config, 7)
	bare.set_spawner(WaveDirector.new(config.waves))
	for entry: Array in log:
		while bare.state.tick < int(entry[0]):
			bare.step()
		assert_int(bare.replay_command(entry)).is_equal(Simulation.CommandResult.OK)
	while bare.state.tick < sim.state.tick:
		bare.step()
	assert_array(bare.state.command_log).is_equal(log)
	assert_str(_state_digest(bare)).is_equal(_state_digest(sim))


func test_each_frame_pattern_equals_the_replay_of_its_own_command_log() -> void:
	# Different frame jitter lands a command on a different tick; each run must equal its replay.
	var config := real_config()
	for frame_seed in [1, 99]:
		var game: Game = await _frame_run(config, frame_seed)
		var bare := Simulation.new(config, 7)
		bare.set_spawner(WaveDirector.new(config.waves))
		for entry: Array in game.sim.state.command_log:
			while bare.state.tick < int(entry[0]):
				bare.step()
			bare.replay_command(entry)
		while bare.state.tick < game.sim.state.tick:
			bare.step()
		assert_str(_state_digest(bare)).override_failure_message("frame seed %d" % frame_seed) \
			.is_equal(_state_digest(game.sim))
		_vp.queue_free()
		_vp = null
