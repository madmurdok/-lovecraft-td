class_name SimNoTreeLoop
extends MainLoop
## LT-34/S2: a MainLoop (not a SceneTree) that plays one seeded bot game through Simulation
## alone and prints its digest. `godot --headless --script res://tests/sim_no_tree_loop.gd`
## proves the sim needs no SceneTree; sim_boundary_test compares the printed digest with the
## same run() inside gdUnit. Not a test suite (no _test suffix).

const MARKER := "SIM_NO_TREE_DIGEST="
const MAX_TICKS := 40000
const BUILDS := ["rifleman", "harpooner", "elder_sign", "rifleman", "necronomicon_reader"]


## One bot game, to its outcome or MAX_TICKS; returns a digest of the final state.
static func run(run_seed := 5) -> String:
	var r := ConfigLoader.load_dir("res://data")
	if not r.ok:
		return "CONFIG ERROR: %s" % "\n".join(r.errors)
	return digest(play(r.config, run_seed))


## The game run() plays, on `config`. `sink` (LT-73 golden replay), when valid, gets
## (sim, events) for every drain, the last one after the final step included.
static func play(config: GameConfig, run_seed: int, sink := Callable()) -> Simulation:
	var sim := Simulation.new(config, run_seed)
	sim.set_spawner(WaveDirector.new(config.waves))
	var cells: Array[Vector2i] = []
	for y in sim.state.map.height:
		for x in sim.state.map.width:
			if sim.state.map.is_buildable(Vector2i(x, y)):
				cells.append(Vector2i(x, y))
	sim.debug_set_sanity(80.0)
	var next_build := 0
	while sim.state.outcome == SimState.Outcome.NONE and sim.state.tick < MAX_TICKS:
		if sim.state.tick % 90 == 0 and next_build < BUILDS.size():
			if sim.build_tower(BUILDS[next_build], cells[next_build * 7 % cells.size()]) \
					== SimCommand.CommandResult.OK:
				next_build += 1
		var events := sim.drain_events()
		if sink.is_valid():
			sink.call(sim, events)
		sim.step()
	var last := sim.drain_events()
	if sink.is_valid():
		sink.call(sim, last)
	return sim


static func digest(sim: Simulation) -> String:
	var s := sim.state
	return "tick=%d gold=%d sanity=%s hp=%d outcome=%d wave=%d next_id=%d towers=%d log=%d" % [
		s.tick, s.gold, s.sanity, s.lighthouse_hp, s.outcome, s.wave_index, s.next_id,
		s.towers.size(), s.command_log.size()]


func _initialize() -> void:
	print(MARKER + run())


func _process(_delta: float) -> bool:
	return true  # quit after the first iteration
