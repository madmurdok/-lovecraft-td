class_name GameCommands
extends RefCounted
## LT-78: the player commands. Each forwards to the sim, then calls `after` (Game's
## _after_command: drain events, redraw). No rule logic lives here.

var sim: Simulation
var debug: DebugArgs
var after: Callable


func _init(p_sim: Simulation, p_debug: DebugArgs, p_after: Callable) -> void:
	sim = p_sim
	debug = p_debug
	after = p_after


## LT-67 (sandbox only): by day lights the lamp (call_wave), at night ends the night
## (sim debug_end_night). Refused (NOT_BUILD_PHASE) outside a sandbox run.
func skip_ahead() -> Simulation.CommandResult:
	if not debug.sandbox:
		return Simulation.CommandResult.NOT_BUILD_PHASE
	if sim.state.phase == SimState.Phase.WAVE:
		var r := sim.debug_end_night()
		after.call()
		return r
	return call_wave()


func build(def_id: String, cell: Vector2i) -> Simulation.CommandResult:
	var r := sim.build_tower(def_id, cell)
	after.call()
	return r


func sell(tower_id: int) -> Simulation.CommandResult:
	var r := sim.sell_tower(tower_id)
	after.call()
	return r


## LT-24: branch "" for L1 -> L2, "a"/"b" for L2 -> L3.
func upgrade(tower_id: int, branch := "") -> Simulation.CommandResult:
	var r := sim.upgrade_tower(tower_id, branch)
	after.call()
	return r


## LT-31: mode is one of SimTower.TARGET_PRIORITIES; allowed in any phase.
func set_target_priority(tower_id: int, mode: String) -> Simulation.CommandResult:
	var r := sim.set_target_priority(tower_id, mode)
	after.call()
	return r


func call_wave() -> Simulation.CommandResult:
	var r := sim.call_wave()
	after.call()
	return r


## LT-27 §1.4: sells the whole stash (by day only).
func sell_relics() -> Simulation.CommandResult:
	var r := sim.sell_relics()
	after.call()
	return r


func buy_sanity() -> Simulation.CommandResult:
	var r := sim.buy_sanity()
	after.call()
	return r


## LT-30: lighthouse level, by day, paid in money.
func upgrade_lighthouse() -> Simulation.CommandResult:
	var r := sim.upgrade_lighthouse()
	after.call()
	return r


## LT-30: one unit of lamp oil, by day.
func buy_oil() -> Simulation.CommandResult:
	var r := sim.buy_oil()
	after.call()
	return r


## LT-57 §4: oil for one flare, by day: buys one unit at a time (each a logged sim
## buy_oil) up to sim.oil_for_flare() units, stopping at the first refusal. Returns OK when
## at least one unit was bought, else the refusal.
func buy_flare_oil() -> Simulation.CommandResult:
	var r := Simulation.CommandResult.OK
	var bought := 0
	for i in sim.oil_for_flare():
		r = sim.buy_oil()
		if r != Simulation.CommandResult.OK:
			break
		bought += 1
	if bought == 0 and r == Simulation.CommandResult.OK:
		r = sim.can_buy_oil()
	after.call()
	return Simulation.CommandResult.OK if bought > 0 else r


## LT-30: the night flare, paid with oil.
func fire_flare() -> Simulation.CommandResult:
	var r := sim.fire_flare()
	after.call()
	return r
