class_name SimCommand
extends RefCounted
## LT-80 (Q5): the result of a player command, moved out of Simulation so sim systems can
## return it without naming Simulation (G4a).

## Result of a player command (build/sell/upgrade/set_target_priority). OK = applied; anything else = rejected
## and nothing changed (no gold, no event, no command_log entry).
enum CommandResult {
	OK,
	OUTCOME_REACHED,  ## the run is over; every command is refused
	UNKNOWN_TOWER,  ## no such tower def
	NOT_AVAILABLE,  ## reserved: no tower kind is refused since LT-11 (kept so values never shift)
	NOT_BUILDABLE,  ## path, water, the lighthouse or out of bounds
	OCCUPIED,  ## another tower stands on the cell
	NOT_ENOUGH_GOLD,
	NO_SUCH_TOWER,  ## sell/upgrade/set_target_priority: unknown or already sold tower id
	## call_wave: not in the build phase (or no WaveDirector); build, sell, upgrade,
	## sell_relics: at night (during a wave, _day_only)
	NOT_BUILD_PHASE,
	NO_BUYOUT,  ## buy_sanity: madness.exit_rule is not "buyout"
	NOT_IN_MADNESS,  ## buy_sanity: sanity state is not MADNESS
	MAX_LEVEL,  ## upgrade: the tower is at L3
	NEED_BRANCH,  ## upgrade: L2 -> L3 needs branch "a" or "b"
	BAD_BRANCH,  ## upgrade: branch is not ""/"a"/"b", or non-empty for L1 -> L2
	NO_TARGETING,  ## set_target_priority: the tower picks no target (aura, Elder Sign)
	BAD_PRIORITY,  ## set_target_priority: mode is not one of SimTower.TARGET_PRIORITIES
	NO_SANITY_ROOM,  ## buy_sanity: the sanity cap is 0, a buyout would restore nothing (LT-23)
	NO_RELICS,  ## sell_relics: unknown kind or nothing of it in the stash (LT-27)
	UNKNOWN_COMMAND,  ## replay_command: the entry names no command (LT-34)
	BAD_ARGS,  ## replay_command: a known command with missing, extra or wrong-typed args (LT-36)
	NOT_NIGHT,  ## fire_flare: by day (phase BUILD) or after the last wave (DONE) (LT-30)
	ON_COOLDOWN,  ## fire_flare: the previous flare's cooldown is still running (LT-30)
	NO_FLARE,  ## fire_flare / buy_oil: no lighthouse.flare / lighthouse.oil block (LT-30)
	NO_OIL,  ## fire_flare: less oil in stock than flare.cost_oil (LT-30)
	OIL_FULL,  ## buy_oil: the stock is at oil.cap (LT-30)
}
