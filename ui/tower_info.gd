class_name TowerInfo
extends RefCounted
## Player-facing tower text built from config (LT-24 §3): stat, effect and kind lines,
## upgrade deltas, cost text and refusal reasons. Pure and static (no nodes); every number
## comes from TowerDef / SanityConfig. The role line is not part of lines(): the panels
## print def.role / the branch role first.

const CURRENCY := "gold"  ## the one currency word (LT-27 renames it here)
const COMING_SOON := " (coming soon)"  ## appended to lines whose key is in Level.PENDING
const MINUS := "−"  ## U+2212, for sanity drains

## Player-facing text for a refused build or upgrade (presentation only).
const REASONS := {
	Simulation.CommandResult.OUTCOME_REACHED: "run over",
	Simulation.CommandResult.UNKNOWN_TOWER: "unknown tower",
	Simulation.CommandResult.NOT_AVAILABLE: "not available yet",
	Simulation.CommandResult.NOT_BUILDABLE: "cannot build here",
	Simulation.CommandResult.OCCUPIED: "cell occupied",
	Simulation.CommandResult.NOT_ENOUGH_GOLD: "not enough " + CURRENCY,
	Simulation.CommandResult.NO_SUCH_TOWER: "tower is gone",
	Simulation.CommandResult.NOT_BUILD_PHASE: "wave in progress",
	Simulation.CommandResult.MAX_LEVEL: "max level",
	Simulation.CommandResult.NEED_BRANCH: "choose a branch",
	Simulation.CommandResult.BAD_BRANCH: "unknown branch",
}

## Effect lines in display order: the keys one line reads (a pair shares a line).
const EFFECT_GROUPS := [
	["pierce"], ["aoe_radius"], ["slow"], ["damage_taken_multiplier"],
	["crit_chance", "crit_multiplier"], ["shooters"], ["bleed_dps", "bleed_seconds"],
	["pull_cells"], ["strip_armor"],
]


## Up to 2 decimals, trailing zeros dropped: 3.5, 82.5, 0.2, 12.
static func num(v: float) -> String:
	var s := "%.2f" % v
	s = s.rstrip("0").rstrip(".")
	return "0" if s == "-0" else s


## "40 gold" (sanity is reserved, not paid: LT-23).
static func cost_text(gold: int) -> String:
	return "%d %s" % [gold, CURRENCY]


## The reason text for a refused command; a generic word for an unmapped result.
static func reason(r: Simulation.CommandResult) -> String:
	return REASONS.get(r, "unavailable")


static func is_pending(key: String) -> bool:
	return TowerDef.Level.PENDING.has(key)


## Stat, effect and kind lines of one level/branch of `def` (no role line).
static func lines(def: TowerDef, s: TowerDef.Level, sanity: SanityConfig) -> PackedStringArray:
	var out := PackedStringArray()
	if s.damage > 0.0:
		out.append(_damage_text(s))
		out.append("Range %s cells" % num(s.range_cells))
	else:
		out.append("Support (no damage)")
		out.append("Aura radius %s cells" % num(s.range_cells))
	if s.sanity_reserve > 0.0:
		out.append("Reserves %s sanity" % num(s.sanity_reserve))
	out.append_array(effect_lines(s.effects))
	out.append_array(kind_lines(def, s, sanity))
	return out


## One line per effect group present (non-zero) in `effects`, then `key: value` for any
## key no group reads; pending keys get COMING_SOON.
static func effect_lines(effects: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for group: Array in EFFECT_GROUPS:
		var present := false
		var pending := false
		for key: String in group:
			seen[key] = true
			if effects.get(key, 0.0) != 0.0:
				present = true
			if is_pending(key):
				pending = true
		if present:
			out.append(_effect_text(group[0], effects) + (COMING_SOON if pending else ""))
	for key: String in effects:
		if not seen.has(key) and effects[key] != 0.0:
			out.append("%s: %s" % [key, num(effects[key])] + (COMING_SOON if is_pending(key) else ""))
	return out


## Kind lines (mundane: kill regen, Fraying misses; occult: madness behaviour).
static func kind_lines(def: TowerDef, s: TowerDef.Level, sanity: SanityConfig) -> PackedStringArray:
	var out := PackedStringArray()
	if def.kind == "mundane":
		if sanity == null:
			return out
		if s.damage > 0.0 and sanity.regen_mundane_kill > 0.0:
			out.append("Kills restore %s sanity" % num(sanity.regen_mundane_kill))
		var fraying: SanityConfig.Threshold = sanity.thresholds.get("fraying")
		if fraying != null and fraying.miss_chance > 0.0:
			out.append("May miss while Fraying (%s%%)" % num(fraying.miss_chance * 100.0))
	elif s.damage > 0.0:
		# Madness changes shots only (x damage, astray); an aura has none.
		if s.madness_affected:
			var mult := sanity.madness.damage_multiplier if sanity != null else 0.0
			out.append("In madness: x%s damage, shots go astray" % num(mult))
		else:
			out.append("Unaffected by madness")
	return out


## What changes from `from` to `to`: one "Stat a → b · ..." line for changed stats, then
## the effect lines that are new or changed, then a madness line if that flag flips.
static func delta_lines(from: TowerDef.Level, to: TowerDef.Level) -> PackedStringArray:
	var out := PackedStringArray()
	var stats := PackedStringArray()
	var support := to.damage <= 0.0
	_delta(stats, "Aura radius" if support else "Range", from.range_cells, to.range_cells)
	_delta(stats, "Damage", from.damage, to.damage)
	if not support:
		_delta(stats, "Interval", from.fire_interval, to.fire_interval, " s")
		_delta(stats, "DPS", _dps(from), _dps(to))
	if not stats.is_empty():
		out.append(" · ".join(stats))
	var reserve := to.sanity_reserve - from.sanity_reserve
	if reserve != 0.0:
		out.append("Reserve %s%s" % ["+" if reserve > 0.0 else MINUS, num(absf(reserve))])
	var changed := {}
	for key: String in to.effects:
		if to.effects[key] != from.effects.get(key, 0.0):
			changed[key] = to.effects[key]
	# Whole groups: a pair line needs both values even if only one of them changed.
	var shown := changed.duplicate()
	for group: Array in EFFECT_GROUPS:
		if group.any(func(k: String) -> bool: return changed.has(k)):
			for key: String in group:
				if to.effects.has(key):
					shown[key] = to.effects[key]
	out.append_array(effect_lines(shown))
	if from.madness_affected != to.madness_affected and to.damage > 0.0:
		out.append("Affected by madness" if to.madness_affected else "Unaffected by madness")
	return out


static func _damage_text(s: TowerDef.Level) -> String:
	return "Damage %s every %s s (%s DPS)" % [num(s.damage), num(s.fire_interval), num(_dps(s))]


## Damage per second from damage and fire_interval only (pending effects such as a second
## shooter do not count).
static func _dps(s: TowerDef.Level) -> float:
	return s.damage / s.fire_interval if s.damage > 0.0 and s.fire_interval > 0.0 else 0.0


static func _delta(out: PackedStringArray, label: String, a: float, b: float, unit := "") -> void:
	if a != b:
		out.append("%s %s → %s%s" % [label, num(a), num(b), unit])


static func _effect_text(first_key: String, e: Dictionary) -> String:
	match first_key:
		"pierce":
			return "Line shot: hits every enemy on a %s-cell-wide line" % num(e.get("pierce", 0.0))
		"aoe_radius":
			return "Blast: hits all enemies within %s cells of the target" % num(e.get("aoe_radius", 0.0))
		"slow":
			return "Slows enemies inside by %s%%" % num(e.get("slow", 0.0) * 100.0)
		"damage_taken_multiplier":
			return "Enemies inside take +%s%% damage" \
				% num((e.get("damage_taken_multiplier", 1.0) - 1.0) * 100.0)
		"crit_chance":
			return "%s%% chance to deal x%s damage" \
				% [num(e.get("crit_chance", 0.0) * 100.0), num(e.get("crit_multiplier", 0.0))]
		"shooters":
			return "%s shooters" % num(e.get("shooters", 0.0))
		"bleed_dps":
			return "Bleed: %s damage/s for %s s" \
				% [num(e.get("bleed_dps", 0.0)), num(e.get("bleed_seconds", 0.0))]
		"pull_cells":
			return "Pulls the target %s cells back along the path" % num(e.get("pull_cells", 0.0))
		"strip_armor":
			return "Enemies inside lose %s armor" % num(e.get("strip_armor", 0.0))
	return "%s: %s" % [first_key, num(e.get(first_key, 0.0))]
