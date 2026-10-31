class_name RenderIsolationTest
extends SimTestBase
## LT-12 §1 and §7 behaviour 13 (plus review finding 1): nothing outside sim/ and tests/
## may tell a fake apart. A source scan forbids `is_fake` as a word (so `debug_is_fake`
## stays allowed) and the sim-only bypasses (`live_fakes_in_range`, `spawn_fake`, the
## hallucination system); `debug_reveal_fakes` may only be set behind OS.is_debug_build().

const SKIP_DIRS := ["sim", "tests", "addons", ".godot"]
const FORBIDDEN := [
	"\\bis_fake\\b",
	"\\blive_fakes_in_range\\b",
	"\\bspawn_fake\\b",
	"\\b_hallucinations\\b",
	"\\bHallucinationSystem\\b",
	"\\b_ghost_tokens\\b",  # LT-27 §1.3: which relic tokens are ghosts
	"\\bGHOST_LOOT\\b",
]
const REVEAL_SET := "\\bdebug_reveal_fakes\\s*=(?!=)"


## Every .gd / .tscn below `dir`, skipping SKIP_DIRS at the project root.
func _sources(dir := "res://") -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		if dir == "res://" and (sub in SKIP_DIRS or sub.begins_with(".")):
			continue
		out.append_array(_sources(dir.path_join(sub)))
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	return out


func _hits(pattern: String, text: String) -> Array[String]:
	var out: Array[String] = []
	for m in RegEx.create_from_string(pattern).search_all(text):
		out.append(m.get_string())
	return out


func test_the_patterns_tell_a_fake_reference_from_the_debug_accessor() -> void:
	assert_array(_hits(FORBIDDEN[0], "if e.is_fake:")).has_size(1)
	assert_array(_hits(FORBIDDEN[0], "e.get(\"is_fake\")")).has_size(1)
	assert_array(_hits(FORBIDDEN[0], "game.sim.debug_is_fake(e)")).is_empty()
	assert_array(_hits(FORBIDDEN[2], "h.spawn_fake(sim, id)")).has_size(1)
	assert_array(_hits(REVEAL_SET, "sim.debug_reveal_fakes = true")).has_size(1)
	assert_array(_hits(REVEAL_SET, "if sim.debug_reveal_fakes == x:")).is_empty()


func test_the_scan_covers_scenes_and_ui() -> void:
	var files := _sources()
	assert_array(files).contains(["res://scenes/board.gd", "res://scenes/game.gd",
		"res://ui/hud.gd"])
	for f in files:
		assert_bool(f.begins_with("res://sim/") or f.begins_with("res://tests/")).is_false()


func test_no_script_outside_sim_and_tests_can_tell_a_fake() -> void:
	for f in _sources():
		var text := FileAccess.get_file_as_string(f)
		for p: String in FORBIDDEN:
			assert_array(_hits(p, text)).override_failure_message(
				"%s names %s" % [f, p]).is_empty()


func test_reveal_fakes_is_only_set_behind_a_debug_build_check() -> void:
	var sets := 0
	for f in _sources():
		var lines := FileAccess.get_file_as_string(f).split("\n")
		var re := RegEx.create_from_string(REVEAL_SET)
		for i in lines.size():
			if re.search(lines[i]) == null:
				continue
			sets += 1
			# The whole statement: this line plus its backslash continuations.
			var stmt := lines[i]
			var j := i
			while stmt.strip_edges().ends_with("\\") and j + 1 < lines.size():
				j += 1
				stmt += lines[j]
			assert_str(stmt).override_failure_message(
				"%s:%d sets debug_reveal_fakes without OS.is_debug_build()" % [f, i + 1]) \
				.contains("OS.is_debug_build()")
	assert_int(sets).is_greater(0)


func test_a_game_started_without_the_flag_does_not_reveal_fakes() -> void:
	var game := Game.new()
	game.setup(real_config(), 7)
	assert_bool(OS.get_cmdline_user_args().has(Game.REVEAL_FAKES_ARG)).is_false()
	assert_bool(game.sim.debug_reveal_fakes).is_false()
	game.free()
