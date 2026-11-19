class_name GoldenRuns
extends RefCounted
## LT-73 (B0 of docs/design/LT-65-architecture-review.md, guard G5): the golden replay runs.
## Plays fixed runs on the frozen config in GOLDEN_DATA and turns each into a digest of every
## drained event (type, tick, id, data with sorted keys, floats as their exact bits) and of the
## final state. tools/golden/regen.gd writes the digests to PINNED; tests/golden_replay_test.gd
## recomputes them and compares. Not a test suite (no _test suffix). See tests/fixtures/README.md.
##
## Runs: every tools/bot_runs.gd strategy x SEEDS (bot behaviour unchanged, events taken from
## its drain through `_event_sink`), the SimNoTreeLoop game, and the LT-34 frame-driven Game
## run (its PLAN and frame pattern mirror sim_boundary_test; the Game consumes its own
## events, so the digest is its command log, the bare replay of that log, events included,
## and the final state of both).

const GOLDEN_DATA := "res://tests/fixtures/golden_data"
const PINNED := "res://tests/fixtures/golden_digests.json"
const BOT_PATH := "res://tools/bot_runs.gd"
const BOT_MAX_TICKS := "const MAX_TICKS := 30 * 60 * 30"
## Bot seed -> tick cap of its runs (0: the bot's own 30-minute cap, i.e. the whole game).
## Seed 1000 plays every strategy's whole game (late waves, madness, lighthouse levels,
## flares). LT-73 verify: 900-tick cuts of seeds 1001/1002 gave the same event stream as
## seed 1000's first bucket for 9 of 10 strategies (wave 1 draws no seed-dependent RNG the
## bots see), so they were dropped; a second whole-game seed would add ~50 s.
const SEEDS := {1000: 0}
const NO_TREE_SEED := 5
const FRAME_SEED := 1234
const SIM_SEED := 7  ## the Game / bare sim seed of the frame run (as in sim_boundary_test)
const BUCKET_TICKS := 900  ## per-bucket event hashes name the first differing 30 s window
const FRAME_STEPS := 4000  ## frame budget; the run stops at tick 1800 or its outcome
const FRAME_STOP_TICK := 1800
## [tick, command, args...] issued through Game once sim.state.tick has reached `tick`; builds
## name a buildable-cell index, upgrade / priority the def built (sim_boundary_test PLAN).
const PLAN := [
	[0, "build", "rifleman", 0],
	[0, "build", "harpooner", 3],
	[200, "upgrade", "rifleman", ""],
	[400, "call_wave"],
	[700, "set_target_priority", "harpooner", "strongest"],
]


## Accumulates one run's events: a running SHA-256 of all of them, one per BUCKET_TICKS.
class Recorder:
	var sim: Simulation
	var count := 0
	var _all := HashingContext.new()
	var _bucket := HashingContext.new()
	var _bucket_index := 0
	var buckets: Array[String] = []

	func _init() -> void:
		_all.start(HashingContext.HASH_SHA256)
		_bucket.start(HashingContext.HASH_SHA256)

	func sink(p_sim: Simulation, events: Array[SimEvent]) -> void:
		sim = p_sim
		for ev in events:
			var b := ev.tick / BUCKET_TICKS
			while _bucket_index < b:
				_close_bucket()
			var line := (GoldenRuns.event_line(ev) + "\n").to_utf8_buffer()
			_all.update(line)
			_bucket.update(line)
			count += 1

	func _close_bucket() -> void:
		buckets.append(_bucket.finish().hex_encode().substr(0, 16))
		_bucket = HashingContext.new()
		_bucket.start(HashingContext.HASH_SHA256)
		_bucket_index += 1

	func result(extra := "") -> Dictionary:
		_close_bucket()
		var state := GoldenRuns.state_text(sim) + extra
		return {"events": count, "events_sha": _all.finish().hex_encode(),
			"buckets": buckets, "final": SimNoTreeLoop.digest(sim),
			"final_sha": GoldenRuns.sha(state)}


static func golden_config() -> GameConfig:
	var r := GameConfig.load_from_dir(GOLDEN_DATA)
	assert(r.ok, "golden data: %s" % "\n".join(r.errors))
	return r.config if r.ok else null


static func sha(text: String) -> String:
	return text.sha256_text()


## One event as a canonical line: TYPE|tick|id|data.
static func event_line(ev: SimEvent) -> String:
	return "%s|%d|%d|%s" % [SimEvent.Type.keys()[ev.type], ev.tick, ev.id, canon(ev.data)]


## A value as stable text: dictionaries with sorted keys, floats as their exact 64-bit
## pattern (no rounding, no locale), every scalar tagged with its type.
static func canon(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys: Array[String] = []
			var by_key := {}
			for k in d:
				var ks := canon(k)
				keys.append(ks)
				by_key[ks] = d[k]
			keys.sort()
			var parts: Array[String] = []
			for ks in keys:
				parts.append("%s:%s" % [ks, canon(by_key[ks])])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
				TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, \
				TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY:
			var parts: Array[String] = []
			for x in v:
				parts.append(canon(x))
			return "[%s]" % ",".join(parts)
		TYPE_FLOAT:
			return "f" + PackedFloat64Array([v]).to_byte_array().hex_encode()
		TYPE_VECTOR2:
			return "v2(%s,%s)" % [canon(v.x), canon(v.y)]
		TYPE_INT:
			return "i%d" % v
		TYPE_BOOL:
			return "b%s" % v
		TYPE_STRING, TYPE_STRING_NAME:
			return "s" + JSON.stringify(String(v))
		TYPE_NIL:
			return "nil"
	return "%s:%s" % [type_string(typeof(v)), var_to_str(v)]


## The final state as text: the SimNoTreeLoop digest plus every entity and RNG stream.
static func state_text(sim: Simulation) -> String:
	var s := sim.state
	var parts: Array[String] = [SimNoTreeLoop.digest(sim), "cap=%s st=%d phase=%d luck=%s" % [
		canon(s.sanity_cap), s.sanity_state, s.phase, canon(s.night_luck)],
		"sanity=%s lh=%d oil=%d flare=%d/%d build_left=%d tokens=%d blasts=%d" % [
		canon(s.sanity), s.lighthouse_level, s.oil, s.flare_ticks_left, s.flare_cooldown_ticks,
		s.build_ticks_left, s.next_token_id, s.next_blast_id],
		"beam=%s" % canon([s.beam_dx, s.beam_dy, s.prev_beam_dx, s.prev_beam_dy, s.beam_sign]),
		"relics=%s" % canon(s.relics), "log=%s" % canon(s.command_log)]
	for stream in SimRng.Stream.values():
		parts.append("rng%d=%d" % [stream, sim.rng(stream).state])
	for e in s.enemies:
		parts.append("e%d:%s:%s:%d:%s:%s" % [e.id, e.def.id, canon(e.hp), e.distance,
			canon([e.dead, e.leaked, e.dissolved, e.revealed, e.lit, e.speed_mult]),
			canon(e.status)])
	for t in s.towers:
		parts.append("t%d:%s:%d:%s:%s:%s:%d:%s:%s" % [t.id, t.def.id, t.level, t.branch,
			t.target_priority, t.cell, t.cooldown_ticks, canon([t.lit, t.shadowed, t.spent]),
			canon(t.status)])
	parts.append("allies=%d" % s.allies.size())
	return "\n".join(parts)


# --- the runs -------------------------------------------------------------------------------

## A tools/bot_runs.gd instance whose constructor does nothing (its _init plays every run and
## quits; the same trick as bot_upgrade_test), its runs cut at `max_ticks` (0: not cut). The
## caller frees it.
static func make_bot(config: GameConfig, max_ticks := 0) -> Object:
	var src := FileAccess.get_file_as_string(BOT_PATH)
	assert(src.contains("func _init() -> void:"), "bot_runs.gd has no _init to rename")
	assert(src.contains(BOT_MAX_TICKS), "bot_runs.gd has no '%s' to cut" % BOT_MAX_TICKS)
	src = src.replace("func _init() -> void:", "func _unused_init() -> void:")
	if max_ticks > 0:
		src = src.replace(BOT_MAX_TICKS, "const MAX_TICKS := %d" % max_ticks)
	var script := GDScript.new()
	script.source_code = src
	var err := script.reload()
	assert(err == OK, "bot_runs.gd copy does not compile: %d" % err)
	var bot: Object = script.new()
	bot.set("_cfg", config)
	return bot


static func strategies() -> Array:
	return load(BOT_PATH).get_script_constant_map()["STRATEGIES"]


## One bot run, digested; "run" is its RUN dictionary (not pinned, for messages).
static func bot_run(bot: Object, strat: String, run_seed: int) -> Dictionary:
	var rec := Recorder.new()
	bot.set("_event_sink", rec.sink)
	var _run: Dictionary = bot.call("_play", strat, run_seed)
	return rec.result()


static func no_tree_run(config: GameConfig) -> Dictionary:
	var rec := Recorder.new()
	SimNoTreeLoop.play(config, NO_TREE_SEED, rec.sink)
	return rec.result()


## The LT-34 frame-driven run under `parent` (a node in the tree), then the bare replay of its
## command log with the events recorded. Frees what it adds.
static func frame_run(parent: Node, config: GameConfig) -> Dictionary:
	var vp := GameFixture.make_viewport(parent, Vector2i(1200, 675))
	# make_game adds the Game to vp with _process off: advance() below is its body.
	var game := GameFixture.make_game(vp, config, SIM_SEED)
	await parent.get_tree().process_frame
	var cells: Array[Vector2i] = []
	for c in game.sim.state.map.grid.cells():
		if game.sim.state.map.is_buildable(c):
			cells.append(c)
	game.sim.debug_set_sanity(70.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = FRAME_SEED
	var next := 0
	var refused: Array = []
	for frame in FRAME_STEPS:
		while next < PLAN.size() and game.sim.state.tick >= int(PLAN[next][0]):
			var r := _dispatch(game, PLAN[next], cells)
			if r != Simulation.CommandResult.OK:
				refused.append([PLAN[next], r])
			next += 1
		if frame == 50 or frame == 70:
			game.toggle_pause()
		elif frame == 150 or frame == 600:
			game.toggle_speed()
		var delta: float = [1.0 / 144.0, 1.0 / 30.0, 0.2, 1.0 / 60.0][rng.randi() % 4] \
			* rng.randf_range(0.5, 1.5)
		game.advance(delta)
		if game.sim.state.tick >= FRAME_STOP_TICK \
				or game.sim.state.outcome != SimState.Outcome.NONE:
			break
	var game_state := state_text(game.sim)
	var rec := Recorder.new()
	var bare := Simulation.new(config, SIM_SEED)
	bare.set_spawner(WaveDirector.new(config.waves))
	for entry: Array in game.sim.state.command_log:
		while bare.state.tick < int(entry[0]):
			bare.step()
			rec.sink(bare, bare.drain_events())
		bare.replay_command(entry)
		rec.sink(bare, bare.drain_events())
	while bare.state.tick < game.sim.state.tick:
		bare.step()
		rec.sink(bare, bare.drain_events())
	rec.sim = bare
	vp.queue_free()
	var out := rec.result("\nrefused=%s" % canon(refused))
	out["game_final_sha"] = sha(game_state + "\nrefused=%s" % canon(refused))
	return out


static func _dispatch(game: Game, c: Array, cells: Array[Vector2i]) -> int:
	match c[1]:
		"build": return game.commands.build(c[2], cells[int(c[3])])
		"upgrade": return game.commands.upgrade(_tower_of(game, c[2], cells), c[3])
		"set_target_priority":
			return game.commands.set_target_priority(_tower_of(game, c[2], cells), c[3])
		"call_wave": return game.commands.call_wave()
	return -1


static func _tower_of(game: Game, def_id: String, cells: Array[Vector2i]) -> int:
	for c: Array in PLAN:
		if c[1] == "build" and c[2] == def_id:
			return game.sim.state.tower_at[cells[int(c[3])]]
	return -1


## Every pinned run: name -> digest dictionary. Awaitable (the frame run waits one frame).
static func compute_all(parent: Node, verbose := false) -> Dictionary:
	var config := golden_config()
	var runs := {}
	var bots := {}
	for s: int in SEEDS:
		if not bots.has(SEEDS[s]):
			bots[SEEDS[s]] = make_bot(config, SEEDS[s])
	for strat: String in strategies():
		for s: int in SEEDS:
			var t0 := Time.get_ticks_msec()
			runs["bot/%s/%d" % [strat, s]] = bot_run(bots[SEEDS[s]], strat, s)
			if verbose:
				print("golden %s/%d: %d ms" % [strat, s, Time.get_ticks_msec() - t0])
	for b: Object in bots.values():
		b.free()
	runs["no_tree_loop/%d" % NO_TREE_SEED] = no_tree_run(config)
	runs["frame_path/%d" % FRAME_SEED] = await frame_run(parent, config)
	return runs


## "" when `got` equals `want`, else one line per differing run naming the first differing
## event bucket (its tick window).
static func diff(want: Dictionary, got: Dictionary) -> String:
	var lines: Array[String] = []
	for name: String in want:
		if not got.has(name):
			lines.append("%s: not computed any more" % name)
	for name: String in got:
		if not want.has(name):
			lines.append("%s: not pinned" % name)
			continue
		var w: Dictionary = want[name]
		var g: Dictionary = got[name]
		var what: Array[String] = []
		if w.get("events_sha") != g.get("events_sha") or w.get("events") != g.get("events"):
			var wb: Array = w.get("buckets", [])
			var gb: Array = g["buckets"]
			var first := -1
			for i in maxi(wb.size(), gb.size()):
				if i >= wb.size() or i >= gb.size() or wb[i] != gb[i]:
					first = i
					break
			what.append("events %s -> %d, first difference in ticks [%d, %d)" % [
				w.get("events"), g["events"], first * BUCKET_TICKS, (first + 1) * BUCKET_TICKS])
		for k in ["final_sha", "game_final_sha"]:
			if w.get(k) != g.get(k):
				what.append("%s differs (final %s -> %s)" % [k, w.get("final"), g["final"]])
		if not what.is_empty():
			lines.append("%s: %s" % [name, "; ".join(what)])
	return "\n".join(lines)
