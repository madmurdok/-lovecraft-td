class_name CommandText
extends RefCounted
## LT-75 (LT-65 B3): the one table of player-facing text for a refused Simulation command.
## Presentation only; static, no nodes. Results without their own wording read GENERIC.

const GENERIC := "unavailable"

## Short lowercase text, read inside a sentence or parentheses ("Rifleman (cell occupied)").
const TEXT := {
	Simulation.CommandResult.OK: GENERIC,
	Simulation.CommandResult.OUTCOME_REACHED: "run over",
	Simulation.CommandResult.UNKNOWN_TOWER: "unknown tower",
	Simulation.CommandResult.NOT_AVAILABLE: "not available yet",
	Simulation.CommandResult.NOT_BUILDABLE: "cannot build here",
	Simulation.CommandResult.OCCUPIED: "cell occupied",
	Simulation.CommandResult.NOT_ENOUGH_GOLD: "not enough money",
	Simulation.CommandResult.NO_SUCH_TOWER: "tower is gone",
	Simulation.CommandResult.NOT_BUILD_PHASE: "only by day",
	Simulation.CommandResult.NO_BUYOUT: GENERIC,
	Simulation.CommandResult.NOT_IN_MADNESS: GENERIC,
	Simulation.CommandResult.MAX_LEVEL: "max level",
	Simulation.CommandResult.NEED_BRANCH: "choose a branch",
	Simulation.CommandResult.BAD_BRANCH: "unknown branch",
	Simulation.CommandResult.NO_TARGETING: "no target to pick",
	Simulation.CommandResult.BAD_PRIORITY: "unknown priority",
	Simulation.CommandResult.NO_SANITY_ROOM: GENERIC,
	Simulation.CommandResult.NO_RELICS: GENERIC,
	Simulation.CommandResult.UNKNOWN_COMMAND: GENERIC,
	Simulation.CommandResult.BAD_ARGS: GENERIC,
	Simulation.CommandResult.NOT_NIGHT: GENERIC,
	Simulation.CommandResult.ON_COOLDOWN: GENERIC,
	Simulation.CommandResult.NO_FLARE: GENERIC,
	Simulation.CommandResult.NO_OIL: GENERIC,
	Simulation.CommandResult.OIL_FULL: GENERIC,
}

## Capitalised wording the lighthouse panel shows on its own button line; a result missing
## here shows no reason line there. Where it differs from TEXT the panel keeps its own string.
const PANEL_TEXT := {
	Simulation.CommandResult.MAX_LEVEL: "Max level",
	Simulation.CommandResult.NOT_BUILD_PHASE: "By day only",
	Simulation.CommandResult.NOT_ENOUGH_GOLD: "Not enough money",
	Simulation.CommandResult.OIL_FULL: "Tank full",
}


## The inline reason text for a refused command; GENERIC for an unmapped result.
static func reason(r: Simulation.CommandResult) -> String:
	return TEXT.get(r, GENERIC)


## The lighthouse panel's reason line, or "" when it shows none for this result.
static func panel_reason(r: Simulation.CommandResult) -> String:
	return PANEL_TEXT.get(r, "")
