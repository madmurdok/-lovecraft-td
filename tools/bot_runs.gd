extends SceneTree
## Headless bot harness for the playtest baseline (LT-15). Run:
##   $GODOT --headless --path . -s res://tools/bot_runs.gd -- [--seeds=10] [--out=<file>]
##   [--data=<dir>] (a config directory other than res://data, e.g. a tuning variant)
## For each strategy x seed it plays one full run on data/ with a fresh Simulation +
## WaveDirector and prints one "RUN {json}" line per run, then a "SUMMARY {json}" line.
##
## Strategies (build orders; the bot builds the next item as soon as it can pay for it):
##   mundane  : rifleman, rifleman, harpooner repeated. Never builds occult.
##   occult   : rifleman, then elder_sign / necronomicon_reader alternating. Sanity guard:
##              an occult item that would leave sanity < 25 is replaced by a rifleman;
##              tries buy_sanity() in madness (refused under the "permanent" exit rule).
##   madness  : necronomicon_reader / elder_sign alternating, no guard, never buys sanity.
## Placement (greedy): the free buildable cell with the most path cells whose centre is
## within the tower's L1 range; ties go to the lowest row-major cell. No upgrades or sells
## (the sim has no upgrade command). Timing: in BUILD, spend what the next item allows then
## call_wave() at once (waiting earns nothing but a smaller early-call bonus); during a
## wave, re-check every second. A run is capped at 30 simulated minutes (outcome "timeout").

const STRATEGIES := ["mundane", "occult", "madness"]
const MAX_TICKS := 30 * 60 * 30
const SANITY_GUARD := 25.0

var _cfg: GameConfig
var _score_cache := {}  ## def id -> Array of [score, cell] sorted best first


func _init() -> void:
	var seeds := 10
	var out := ""
	var data_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--data="):
			data_dir = a.substr(7)
	var res := GameConfig.load_from_dir(data_dir) if data_dir != "" else GameConfig.load_from_dir()
	if not res.ok:
		printerr("config errors: ", res.errors)
		quit(1)
		return
	_cfg = res.config
	var runs: Array = []
	for strat in STRATEGIES:
		for s in seeds:
			var r := _play(strat, 1000 + s)
			runs.append(r)
			print("RUN ", JSON.stringify(r))
	var summary := JSON.stringify(runs)
	print("SUMMARY ", summary)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(summary)
		f.close()
	quit(0)


func _play(strat: String, run_seed: int) -> Dictionary:
	var sim := Simulation.new(_cfg, run_seed)
	sim.set_spawner(WaveDirector.new(_cfg.waves))
	# Fakes are counted via the debug accessor: the render isolation test bans the raw flag.
	sim.debug_reveal_fakes = OS.is_debug_build()
	if not sim.debug_reveal_fakes:
		push_warning("release build: fakes are not counted")
	var st := sim.state
	var idx := 0
	var ticks_in_state := [0, 0, 0, 0]
	var wave_end_sanity: Array = []
	var fakes := 0
	var last_fake_id := 0
	var astray := 0
	var missed := 0
	var shots := 0
	var built := {}
	while st.outcome == SimState.Outcome.NONE and st.tick < MAX_TICKS:
		if st.tick % 30 == 0:
			idx = _act(sim, strat, idx, built)
		sim.step()
		ticks_in_state[st.sanity_state] += 1
		for e in st.enemies:
			if sim.debug_is_fake(e) and e.id > last_fake_id:
				last_fake_id = e.id
				fakes += 1
		for ev in sim.drain_events():
			if ev.type == SimEvent.Type.WAVE_CLEARED:
				wave_end_sanity.append(snappedf(st.sanity, 0.1))
			elif ev.type == SimEvent.Type.SHOT:
				shots += 1
				if ev.data.get("miss", false):
					missed += 1
				if ev.data.get("astray", false):
					astray += 1
	var outcome := "timeout"
	if st.outcome == SimState.Outcome.WON:
		outcome = "won"
	elif st.outcome == SimState.Outcome.LOST:
		outcome = "lost"
	var waves_survived := wave_end_sanity.size()
	return {
		"strategy": strat, "seed": run_seed, "outcome": outcome,
		"waves_survived": waves_survived, "gold": st.gold,
		"final_sanity": snappedf(st.sanity, 0.1), "wave_end_sanity": wave_end_sanity,
		"seconds": {
			"lucid": ticks_in_state[0] / 30.0, "whispers": ticks_in_state[1] / 30.0,
			"fraying": ticks_in_state[2] / 30.0, "madness": ticks_in_state[3] / 30.0},
		"fakes": fakes, "astray": astray, "missed": missed, "shots": shots,
		"towers": built, "lighthouse_hp": st.lighthouse_hp, "ticks": st.tick,
	}


func _order(strat: String, i: int, sim: Simulation) -> String:
	match strat:
		"mundane":
			return "harpooner" if i % 3 == 2 else "rifleman"
		"occult":
			if i == 0:
				return "rifleman"
			var d := "elder_sign" if i % 2 == 1 else "necronomicon_reader"
			if sim.state.sanity - _cfg.towers[d].sanity_cost < SANITY_GUARD:
				return "rifleman"
			return d
		_:
			return "necronomicon_reader" if i % 2 == 0 else "elder_sign"


## Builds as many items as affordable; in BUILD then calls the wave. Returns the new index.
func _act(sim: Simulation, strat: String, idx: int, built: Dictionary) -> int:
	if strat == "occult":
		sim.buy_sanity()  # refused unless exit_rule is "buyout" and state is MADNESS
	while true:
		var id := _order(strat, idx, sim)
		var cell := _best_cell(sim, id)
		if cell.x < 0 or sim.build_tower(id, cell) != Simulation.CommandResult.OK:
			break
		built[id] = built.get(id, 0) + 1
		idx += 1
	if sim.state.phase == SimState.Phase.BUILD:
		sim.call_wave()
	return idx


func _best_cell(sim: Simulation, id: String) -> Vector2i:
	if not _score_cache.has(id):
		var rng_cells: float = _cfg.towers[id].levels[0].range_cells
		var m := _cfg.map
		var list: Array = []
		for y in m.height:
			for x in m.width:
				var c := Vector2i(x, y)
				if not m.is_buildable(c):
					continue
				var score := 0
				for p in m.path:
					if Vector2(c - p).length() <= rng_cells:
						score += 1
				if score > 0:
					list.append([score, c])
		list.sort_custom(func(a, b): return a[0] > b[0])  # stable enough: row-major kept
		_score_cache[id] = list
	for e in _score_cache[id]:
		if not sim.state.tower_at.has(e[1]):
			return e[1]
	return Vector2i(-1, -1)
