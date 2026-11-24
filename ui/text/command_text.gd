class_name CommandText
extends RefCounted
## LT-75 (LT-65 B3): the one table of player-facing text for a refused Simulation command.
## Presentation only; static, no nodes. Results without their own wording read GENERIC.

const GENERIC := "unavailable"

## Short lowercase text, read inside a sentence or parentheses ("Rifleman (cell occupied)").
const TEXT := {
	SimCommand.CommandResult.OK: GENERIC,
	SimCommand.CommandResult.OUTCOME_REACHED: "run over",
	SimCommand.CommandResult.UNKNOWN_TOWER: "unknown tower",
	SimCommand.CommandResult.NOT_AVAILABLE: "not available yet",
	SimCommand.CommandResult.NOT_BUILDABLE: "cannot build here",
	SimCommand.CommandResult.OCCUPIED: "cell occupied",
	SimCommand.CommandResult.NOT_ENOUGH_GOLD: "not enough money",
	SimCommand.CommandResult.NO_SUCH_TOWER: "tower is gone",
	SimCommand.CommandResult.NOT_BUILD_PHASE: "only by day",
	SimCommand.CommandResult.NO_BUYOUT: GENERIC,
	SimCommand.CommandResult.NOT_IN_MADNESS: GENERIC,
	SimCommand.CommandResult.MAX_LEVEL: "max level",
	SimCommand.CommandResult.NEED_BRANCH: "choose a branch",
	SimCommand.CommandResult.BAD_BRANCH: "unknown branch",
	SimCommand.CommandResult.NO_TARGETING: "no target to pick",
	SimCommand.CommandResult.BAD_PRIORITY: "unknown priority",
	SimCommand.CommandResult.NO_SANITY_ROOM: GENERIC,
	SimCommand.CommandResult.NO_RELICS: GENERIC,
	SimCommand.CommandResult.UNKNOWN_COMMAND: GENERIC,
	SimCommand.CommandResult.BAD_ARGS: GENERIC,
	SimCommand.CommandResult.NOT_NIGHT: GENERIC,
	SimCommand.CommandResult.ON_COOLDOWN: GENERIC,
	SimCommand.CommandResult.NO_FLARE: GENERIC,
	SimCommand.CommandResult.NO_OIL: GENERIC,
	SimCommand.CommandResult.OIL_FULL: "tank full",
	SimCommand.CommandResult.NO_CREW: "no crew for this",
	SimCommand.CommandResult.RESERVE_SHORT: "not enough crew",
	SimCommand.CommandResult.NOT_A_TOWER: "a post, not a tower",
}

## LT-107: per-command overrides of TEXT, {Simulation.COMMANDS[cmd].text: {CommandResult: text}}.
## Empty for the older commands (every shown string is TEXT's); LT-32 adds "deploy" / "hire".
const BY_COMMAND: Dictionary = {
	"deploy": {SimCommand.CommandResult.NOT_NIGHT: "only at night"},
	"hire": {SimCommand.CommandResult.NOT_BUILD_PHASE: "hire by day"},
}

## Results the lighthouse panel names on its own button line (owner on LT-75: one table, the
## panel capitalises). Any other result shows no reason line there.
const PANEL_RESULTS: Array[SimCommand.CommandResult] = [
	SimCommand.CommandResult.MAX_LEVEL,
	SimCommand.CommandResult.NOT_BUILD_PHASE,
	SimCommand.CommandResult.NOT_ENOUGH_GOLD,
	SimCommand.CommandResult.OIL_FULL,
]


## The inline reason text for a refused command; GENERIC for an unmapped result. With `cmd`
## (a Simulation.COMMANDS name), its BY_COMMAND override wins when it maps `r`.
static func reason(r: SimCommand.CommandResult, cmd := "") -> String:
	var key: String = Simulation.COMMANDS[cmd].text if Simulation.COMMANDS.has(cmd) else ""
	return _reason_in(r, key, BY_COMMAND)


## reason() over a given override table (tests plant one; the const BY_COMMAND is read-only).
## The override for text key `key` wins when it maps `r`; key "" has none.
static func _reason_in(r: SimCommand.CommandResult, key: String, by_command: Dictionary) -> String:
	if key != "":
		var own: Dictionary = by_command.get(key, {})
		if own.has(r):
			return own[r]
	return TEXT.get(r, GENERIC)


## The lighthouse panel's reason line, or "" when it shows none for this result.
static func panel_reason(r: SimCommand.CommandResult) -> String:
	if not PANEL_RESULTS.has(r):
		return ""
	var text := reason(r)
	return text.left(1).to_upper() + text.substr(1)
