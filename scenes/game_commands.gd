class_name GameCommands
extends RefCounted
## LT-78: the player commands. Each forwards to the sim, then calls `after` (Game's
## _after_command: drain events, redraw). No rule logic lives here. LT-107: the named
## table commands are one-liners over issue(); skip_ahead and buy_flare_oil are composites.

var sim: Simulation
var debug: DebugArgs
var after: Callable


func _init(p_sim: Simulation, p_debug: DebugArgs, p_after: Callable) -> void:
	sim = p_sim
	debug = p_debug
	after = p_after


## LT-107: runs the Simulation.COMMANDS entry `name` with `args` (sim.issue), then calls
## `after` once, OK or refused. Returns the sim result.
func issue(name: String, args: Array) -> SimCommand.CommandResult:
	var r := sim.issue(name, args)
	after.call()
	return r


## LT-67 (sandbox only): by day lights the lamp (call_wave), at night ends the night
## (sim debug_end_night). Refused (NOT_BUILD_PHASE) outside a sandbox run.
func skip_ahead() -> SimCommand.CommandResult:
	if not debug.sandbox:
		return SimCommand.CommandResult.NOT_BUILD_PHASE
	if sim.state.phase == SimState.Phase.WAVE:
		var r := sim.debug_end_night()
		after.call()
		return r
	return call_wave()


func build(def_id: String, cell: Vector2i) -> SimCommand.CommandResult:
	return issue("build", [def_id, cell])


func sell(tower_id: int) -> SimCommand.CommandResult:
	return issue("sell", [tower_id])


## LT-24: branch "" for L1 -> L2, "a"/"b" for L2 -> L3.
func upgrade(tower_id: int, branch := "") -> SimCommand.CommandResult:
	return issue("upgrade", [tower_id, branch])


## LT-31: mode is one of SimTower.TARGET_PRIORITIES; allowed in any phase.
func set_target_priority(tower_id: int, mode: String) -> SimCommand.CommandResult:
	return issue("set_target_priority", [tower_id, mode])


func call_wave() -> SimCommand.CommandResult:
	return issue("call_wave", [])


## LT-27 §1.4: sells the whole stash (by day only).
func sell_relics() -> SimCommand.CommandResult:
	return issue("sell_relics", [""])


func buy_sanity() -> SimCommand.CommandResult:
	return issue("buy_sanity", [])


## LT-30: lighthouse level, by day, paid in money.
func upgrade_lighthouse() -> SimCommand.CommandResult:
	return issue("upgrade_lighthouse", [])


## LT-30: one unit of lamp oil, by day.
func buy_oil() -> SimCommand.CommandResult:
	return issue("buy_oil", [])


## LT-57 §4: oil for one flare, by day: buys one unit at a time (each a logged sim
## buy_oil) up to sim.oil_for_flare() units, stopping at the first refusal. Returns OK when
## at least one unit was bought, else the refusal.
func buy_flare_oil() -> SimCommand.CommandResult:
	var r := SimCommand.CommandResult.OK
	var bought := 0
	for i in sim.oil_for_flare():
		r = sim.buy_oil()
		if r != SimCommand.CommandResult.OK:
			break
		bought += 1
	if bought == 0 and r == SimCommand.CommandResult.OK:
		r = sim.can_buy_oil()
	after.call()
	return SimCommand.CommandResult.OK if bought > 0 else r


## LT-30: the night flare, paid with oil.
func fire_flare() -> SimCommand.CommandResult:
	return issue("fire_flare", [])
