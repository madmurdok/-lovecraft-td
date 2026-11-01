class_name TowerInfo
extends RefCounted
## Player-facing tower text built from config (LT-24 §3): stat, effect and kind lines,
## upgrade deltas, cost text and refusal reasons. Pure and static (no nodes); every number
## comes from TowerDef / SanityConfig. The role line is not part of lines(): the panels
## print def.role / the branch role first.

const CURRENCY := "$"  ## the money sign (LT-27 §2: "gold" internally, "$" on screen)
const DASH := " — "  ## between a name and its cost: "Rifleman — $50"
const COMING_SOON := " (coming soon)"  ## appended to lines whose key is in Level.PENDING
const MINUS := "−"  ## U+2212, for sanity drains
const MADNESS_WARNING := " (drives you mad!)"  ## LT-23 Q3: build/upgrade takes the cap to 0
const REMOVED := "Loses: "  ## LT-28: before the old line of an effect an upgrade removes
const GROUND_ONLY := "Cannot hit flyers"  ## LT-47: a tower with targets "ground"

## Player-facing text for a refused build or upgrade (presentation only).
const REASONS := {
	Simulation.CommandResult.OUTCOME_REACHED: "run over",
	Simulation.CommandResult.UNKNOWN_TOWER: "unknown tower",
	Simulation.CommandResult.NOT_AVAILABLE: "not available yet",
	Simulation.CommandResult.NOT_BUILDABLE: "cannot build here",
	Simulation.CommandResult.OCCUPIED: "cell occupied",
	Simulation.CommandResult.NOT_ENOUGH_GOLD: "not enough money",
	Simulation.CommandResult.NO_SUCH_TOWER: "tower is gone",
	Simulation.CommandResult.NOT_BUILD_PHASE: "only by day",
	Simulation.CommandResult.MAX_LEVEL: "max level",
	Simulation.CommandResult.NEED_BRANCH: "choose a branch",
	Simulation.CommandResult.BAD_BRANCH: "unknown branch",
	Simulation.CommandResult.NO_TARGETING: "no target to pick",
	Simulation.CommandResult.BAD_PRIORITY: "unknown priority",
}

## Player-facing names of SimTower.TARGET_PRIORITIES (LT-31).
const PRIORITY_NAMES := {
	"first": "Closest to the lighthouse",
	"strongest": "Strongest",
	"fastest": "Fastest",
}

## Effect lines in display order: the keys one line reads (a pair shares a line).
const EFFECT_GROUPS := [
	["pierce"], ["aoe_radius"], ["fuse_seconds"], ["ignore_armor"], ["sanity_scaling"],
	["reveal_fakes"], ["slow"], ["damage_taken_multiplier"],
	["crit_chance", "crit_multiplier"], ["burst_targets"], ["bleed_dps", "bleed_seconds"],
	["pull_cells", "pull_max_hp", "pull_immune_seconds"], ["strip_armor"],
]


## Up to 2 decimals, trailing zeros dropped: 3.5, 82.5, 0.2, 12.
static func num(v: float) -> String:
	var s := "%.2f" % v
	s = s.rstrip("0").rstrip(".")
	return "0" if s == "-0" else s


## "$40" (sanity is reserved, not paid: LT-23).
static func cost_text(gold: int) -> String:
	return money(gold)


## LT-27 §2: money as shown on screen, "$240"; a negative amount reads "−$5".
static func money(amount: int) -> String:
	return ("%s%s%d" % [MINUS if amount < 0 else "", CURRENCY, absi(amount)])


## The reason text for a refused command; a generic word for an unmapped result.
static func reason(r: Simulation.CommandResult) -> String:
	return REASONS.get(r, "unavailable")


static func is_pending(key: String) -> bool:
	return TowerDef.Level.PENDING.has(key)


## Stat, effect and kind lines of one level/branch of `def` (no role line).
## LT-50: with the live `current_sanity` (not NAN) a sanity-scaled level also reads its
## damage factor now ("x1.6 at current sanity"); the picker passes none.
static func lines(def: TowerDef, s: TowerDef.Level, sanity: SanityConfig,
		current_sanity := NAN) -> PackedStringArray:
	var out := PackedStringArray()
	if s.damage > 0.0:
		out.append(_damage_text(s))
		out.append("Range %s cells" % num(s.range_cells))
		if s.min_range > 0.0:
			out.append(dead_zone_text(s.min_range))
		if def.ground_only():
			out.append(GROUND_ONLY)
	else:
		out.append("Support (no damage)")
		out.append("Aura radius %s cells" % num(s.range_cells))
	if s.sanity_reserve > 0.0:
		out.append("Reserves %s sanity" % num(s.sanity_reserve))
	out.append_array(effect_lines(s.effects))
	if s.is_beam() and sanity != null and not is_nan(current_sanity):
		out.append(sanity_factor_text(s.sanity_factor(current_sanity, sanity.max_sanity)))
	out.append_array(kind_lines(def, s, sanity))
	return out


## LT-50: the live line of a sanity-scaled level.
static func sanity_factor_text(factor: float) -> String:
	return "x%s at current sanity" % ("%.1f" % factor)


## The value of an effect key that means "no effect": 1 for a multiplier, 0 otherwise.
static func neutral(key: String) -> float:
	return 1.0 if key.ends_with("_multiplier") else 0.0


## LT-28: an effect key with a value other than its neutral one (a x1 multiplier does nothing).
static func is_active(effects: Dictionary, key: String) -> bool:
	return effects.has(key) and effects[key] != neutral(key)


## One line per effect group present (a key off its neutral value) in `effects`, then
## `key: value` for any key no group reads; pending keys get COMING_SOON unless `suffix`
## is false.
static func effect_lines(effects: Dictionary, suffix := true) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for group: Array in EFFECT_GROUPS:
		var present := false
		var pending := false
		for key: String in group:
			seen[key] = true
			if is_active(effects, key):
				present = true
			if is_pending(key):
				pending = true
		if present:
			out.append(_effect_text(group[0], effects) + (COMING_SOON if pending and suffix else ""))
	for key: String in effects:
		if not seen.has(key) and is_active(effects, key):
			out.append("%s: %s" % [key, num(effects[key])]
				+ (COMING_SOON if is_pending(key) and suffix else ""))
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
		# LT-49: a mundane support tower (Searchlight) never shoots, so it never misses.
		if s.damage > 0.0 and fraying != null and fraying.miss_chance > 0.0:
			out.append("May miss while Fraying (%s%%)" % num(fraying.miss_chance * 100.0))
	elif s.damage > 0.0:
		# Madness changes shots only (x damage, astray); an aura has none.
		if s.madness_affected:
			var mult := sanity.madness.damage_multiplier if sanity != null else 0.0
			out.append("Madness: x%s, astray" % num(mult))
		else:
			out.append("Unaffected by madness")
	return out


## What changes from `from` to `to`: one "Stat a → b · ..." line for changed stats, then
## the effect lines that are new or changed, then REMOVED + the old line for each effect
## `to` no longer has (LT-28), then a madness line if that flag flips.
static func delta_lines(from: TowerDef.Level, to: TowerDef.Level) -> PackedStringArray:
	var out := PackedStringArray()
	var stats := PackedStringArray()
	var support := to.damage <= 0.0
	_delta(stats, "Aura radius" if support else "Range", from.range_cells, to.range_cells)
	if not support:
		_delta(stats, "Dead zone", from.min_range, to.min_range)
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
	for key: String in to.effects.keys() + from.effects.keys():
		if to.effects.get(key, neutral(key)) != from.effects.get(key, neutral(key)):
			changed[key] = true
	# Whole groups: a pair line needs both values even if only one of them changed. A group
	# still active in `to` shows its new line; one active only in `from` was removed.
	var shown := {}
	var removed := {}
	var grouped := {}
	for group: Array in EFFECT_GROUPS:
		grouped.merge(_keys_dict(group))
		if not group.any(func(k: String) -> bool: return changed.has(k)):
			continue
		if group.any(func(k: String) -> bool: return is_active(to.effects, k)):
			for key: String in group:
				if to.effects.has(key):
					shown[key] = to.effects[key]
		elif group.any(func(k: String) -> bool: return is_active(from.effects, k)):
			for key: String in group:
				if from.effects.has(key):
					removed[key] = from.effects[key]
	for key: String in changed:
		if grouped.has(key):
			continue
		if is_active(to.effects, key):
			shown[key] = to.effects[key]
		elif is_active(from.effects, key):
			removed[key] = from.effects[key]
	out.append_array(effect_lines(shown))
	for line in effect_lines(removed, false):
		out.append(REMOVED + line)
	if from.madness_affected != to.madness_affected and to.damage > 0.0:
		out.append("Affected by madness" if to.madness_affected else "Unaffected by madness")
	return out


static func _keys_dict(keys: Array) -> Dictionary:
	var d := {}
	for k: String in keys:
		d[k] = true
	return d


## LT-48: the line for a tower's dead zone (`min_range` cells).
static func dead_zone_text(cells: float) -> String:
	return "Dead zone: %s cells" % num(cells)


static func _damage_text(s: TowerDef.Level) -> String:
	return "Damage %s every %s s (%s DPS)" % [num(s.damage), num(s.fire_interval), num(_dps(s))]


## Damage per second from damage and fire_interval only (crits, bleed and the like do not
## count).
static func _dps(s: TowerDef.Level) -> float:
	return s.damage / s.fire_interval if s.damage > 0.0 and s.fire_interval > 0.0 else 0.0


static func _delta(out: PackedStringArray, label: String, a: float, b: float, unit := "") -> void:
	if a != b:
		out.append("%s %s → %s%s" % [label, num(a), num(b), unit])


static func _effect_text(first_key: String, e: Dictionary) -> String:
	match first_key:
		"pierce":
			return "Pierce: %s-cell-wide line" % num(e.get("pierce", 0.0))
		"aoe_radius":
			return "Blast radius %s cells" % num(e.get("aoe_radius", 0.0))
		"fuse_seconds":
			return "Fuse %s s, thrown ahead" % num(e.get("fuse_seconds", 0.0))
		"ignore_armor":
			return "Ignores armor"
		"sanity_scaling":
			return "Up to x%s at low sanity" % num(1.0 + e.get("sanity_scaling", 0.0))
		"reveal_fakes":
			return "Reveals fakes"
		"slow":
			return "Slows enemies %s%%" % num(e.get("slow", 0.0) * 100.0)
		"damage_taken_multiplier":
			return "Foes take +%s%% damage" \
				% num((e.get("damage_taken_multiplier", 1.0) - 1.0) * 100.0)
		"crit_chance":
			return "%s%% crit, x%s damage" \
				% [num(e.get("crit_chance", 0.0) * 100.0), num(e.get("crit_multiplier", 0.0))]
		"burst_targets":
			return "Spreads fire over %s foes" % num(e.get("burst_targets", 0.0))
		"bleed_dps":
			return "Bleed %s/s for %s s" \
				% [num(e.get("bleed_dps", 0.0)), num(e.get("bleed_seconds", 0.0))]
		"pull_cells":
			return "Pull %sc, ≤%s HP, %ss" % [num(e.get("pull_cells", 0.0)),
				num(e.get("pull_max_hp", 0.0)), num(e.get("pull_immune_seconds", 0.0))]
		"strip_armor":
			return "Foes lose %s armor" % num(e.get("strip_armor", 0.0))
	return "%s: %s" % [first_key, num(e.get(first_key, 0.0))]
