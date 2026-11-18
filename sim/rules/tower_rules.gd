class_name TowerRules
extends RefCounted
## LT-76 (LT-65 §3.2): config-derived tower rules, pure static, one source for the sim, the
## UI and the bot. They take a tower's kind / level and its net light state, so they work
## for a tower that is not built yet (picker card, stats table). Every float expression
## keeps the operand order the sim used before LT-76 (the golden replay pins it).
##
## `cfg` may be null in the UI-facing functions (light_effect, effective): then the light is
## neutral. The sim always passes its config.


## LT-30 §2, LT-70 §2.3: an occult tower's damage / aura / banish / summon multiplier from
## its net state: beam.occult_power_mult lit, shadow.occult_power_mult shadowed (1.0 without
## a shadow block), else 1.0. Mundane towers: 1.0.
static func power_mult(kind: String, cfg: GameConfig, lit: bool, shadowed: bool) -> float:
	if kind != "occult" or cfg == null or cfg.economy == null:
		return 1.0
	if lit:
		return cfg.economy.beam.occult_power_mult
	if shadowed and cfg.economy.shadow != null:
		return cfg.economy.shadow.occult_power_mult
	return 1.0


## LT-30 §2, LT-70 §2.3: a mundane tower's fire interval multiplier from its net state:
## beam.mundane_fire_interval_mult lit, shadow.mundane_fire_interval_mult shadowed (1.0
## without a shadow block), else 1.0. Occult towers: 1.0.
static func interval_mult(kind: String, cfg: GameConfig, lit: bool, shadowed: bool) -> float:
	if kind != "mundane" or cfg == null or cfg.economy == null:
		return 1.0
	if lit:
		return cfg.economy.beam.mundane_fire_interval_mult
	if shadowed and cfg.economy.shadow != null:
		return cfg.economy.shadow.mundane_fire_interval_mult
	return 1.0


## LT-30: a lit mundane tower with beam.mundane_ignore_miss never misses.
static func ignore_miss(kind: String, cfg: GameConfig, lit: bool) -> bool:
	if kind != "mundane" or cfg == null or cfg.economy == null:
		return false
	return lit and cfg.economy.beam.mundane_ignore_miss


## LT-70 §2.3: what a shadowed mundane tower adds to its miss chance
## (shadow.mundane_miss_chance_add; 0 without a shadow block, unshadowed or occult).
static func miss_add(kind: String, cfg: GameConfig, shadowed: bool) -> float:
	if kind != "mundane" or cfg == null or cfg.economy == null:
		return 0.0
	if shadowed and cfg.economy.shadow != null:
		return cfg.economy.shadow.mundane_miss_chance_add
	return 0.0


## LT-65 §3.2: every light / shadow effect on a tower of `def` (null: neutral) in the net
## state (lit, shadowed): {power_mult, interval_mult, ignore_miss, miss_add}.
static func light_effect(def: TowerDef, cfg: GameConfig, lit: bool, shadowed: bool) -> Dictionary:
	var kind := def.kind if def != null else ""
	return {
		"power_mult": power_mult(kind, cfg, lit, shadowed),
		"interval_mult": interval_mult(kind, cfg, lit, shadowed),
		"ignore_miss": ignore_miss(kind, cfg, lit),
		"miss_add": miss_add(kind, cfg, shadowed),
	}


## LT-50 (§7 Q2): the damage factor of level `s` at `sanity` (TowerDef.Level.sanity_factor
## on the config's full bar).
static func sanity_factor(s: TowerDef.Level, cfg: GameConfig, sanity: float) -> float:
	return s.sanity_factor(sanity, cfg.sanity.max_sanity)


## One shot's damage before madness, crits and armor: damage x sanity factor x power mult
## (LT-50, then LT-30 / LT-70 lit x0.7 / shadowed x1.15). A banish cast passes factor 1.0.
static func shot_damage(s: TowerDef.Level, factor: float, power: float) -> float:
	return s.damage * factor * power


## LT-30 / LT-70 §2.3: the fire interval in seconds, x the light interval multiplier.
static func fire_interval(s: TowerDef.Level, interval_mult_: float) -> float:
	return s.fire_interval * interval_mult_


## The cooldown a shot, cast or summon of `interval_s` seconds sets: whole ticks, at least 1.
static func cooldown_ticks(interval_s: float) -> int:
	return maxi(1, SimTime.ticks(interval_s))


## LT-52: a summoned unit's DPS, summon_dps x the circle's power mult at summon time.
static func unit_dps(s: TowerDef.Level, power: float) -> float:
	return s.effects.get("summon_dps", 0.0) * power


## LT-30 §2 / LT-29 §2: an occult aura's damage_taken_multiplier at power mult `power`
## (only its bonus above 1 scales).
static func powered_taken_mult(taken_mult: float, power: float) -> float:
	return 1.0 + (taken_mult - 1.0) * power


## Damage per second (per fire_interval second, no madness, crits or bleed): a circle's
## unit_dps x summon_max; else shot damage / interval x the foes one cast hits
## (banish_targets); 0 for a level that deals none. effective() calls it with the base
## numbers (s.damage, s.fire_interval, summon_dps) and scales the result.
static func dps(s: TowerDef.Level, damage: float, interval_s: float, unit: float) -> float:
	if s.is_summon():
		return unit * s.summon_max()
	if s.damage <= 0.0 or interval_s <= 0.0:
		return 0.0
	return damage / interval_s * (s.banish_targets() if s.is_banish() else 1)


## LT-65 §3.2: the effective numbers of level `s` of `def` (null: neutral light) in the net
## state (lit, shadowed) at `sanity` (< 0: no sanity scaling, the factor is 1):
## {damage, interval, interval_ticks, dps, unit_dps, factor}. As the sim fires: a shooter's
## shot damage is damage x factor x power; a banish cast's damage x power (no sanity
## factor); a circle's unit gets summon_dps x power. `damage` is per shot, `interval` in
## seconds. `dps` is the stats table's per-second figure: the base dps x factor x power /
## interval_mult, in that order (the order the UI used before LT-76; per-shot order would
## move ties such as 43.75 across a rounding edge). It counts seconds, not the sim's whole
## cooldown ticks (LT-33 #18 stays open: a lit Rifleman reads 43.8, the sim fires at 42).
static func effective(def: TowerDef, s: TowerDef.Level, cfg: GameConfig, lit := false,
		shadowed := false, sanity := -1.0) -> Dictionary:
	var fx := light_effect(def, cfg, lit, shadowed)
	var power: float = fx["power_mult"]
	var factor := 1.0
	if sanity >= 0.0 and cfg != null and not s.is_banish() and not s.is_summon():
		factor = sanity_factor(s, cfg, sanity)
	var im: float = fx["interval_mult"]
	var interval := fire_interval(s, im)
	var base := dps(s, s.damage, s.fire_interval, s.effects.get("summon_dps", 0.0))
	return {
		"damage": shot_damage(s, factor, power),
		"interval": interval,
		"interval_ticks": cooldown_ticks(interval),
		"dps": base * factor * power / im,
		"unit_dps": unit_dps(s, power),
		"factor": factor,
	}


## LT-48 (P4): the dead-zone radius of level `s` in cells (min_range; 0: none).
static func dead_zone(s: TowerDef.Level) -> float:
	return s.min_range


## LT-48 (P4): whether the point p is inside the dead zone of radius `min_range` around the
## tower centre c: strictly closer than min_range. Never with no dead zone.
static func in_dead_zone(c: Vector2, min_range: float, p: Vector2) -> bool:
	if min_range <= 0.0:
		return false
	var dx := float(p.x) - float(c.x)
	var dy := float(p.y) - float(c.y)
	return dx * dx + dy * dy < min_range * min_range
