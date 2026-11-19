class_name SimContext
extends RefCounted
## LT-80 (LT-65 §3.1, B5): the plumbing every sim system shares: state, config, the RNG
## streams, the one event buffer, the command log and the day-only rule. Holds no system
## (systems get their peers through their constructors), so nothing forms a cycle.

var state: SimState
var config: GameConfig
## The one event buffer (LT-65 §3.1 invariant 3); the facade's drain_events swaps it.
var events: Array[SimEvent] = []
var _rng: SimRng


func _init(p_config: GameConfig, run_seed: int) -> void:
	config = p_config
	_rng = SimRng.new(run_seed)
	state = SimState.new()


func rng(stream: SimRng.Stream) -> RandomNumberGenerator:
	return _rng.stream(stream)


func emit(type: SimEvent.Type, id: int, data: Dictionary) -> void:
	events.append(SimEvent.new(type, state.tick, id, data))


## The one writer of state.command_log: each command appends its entry here, at the same
## statement as before LT-80.
func log_command(entry: Array) -> void:
	state.command_log.append(entry)


## LT-27 §3: NOT_BUILD_PHASE at night (phase WAVE), else OK. Not `!= BUILD`, so a sim
## without a WaveDirector (phase NONE) allows everything. The one seam for day-only rules
## (build, sell tower, upgrade, sell relics; later the crew layer, §7).
func day_only() -> SimCommand.CommandResult:
	if state.phase == SimState.Phase.WAVE:
		return SimCommand.CommandResult.NOT_BUILD_PHASE
	return SimCommand.CommandResult.OK
