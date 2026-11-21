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


## LT-50: the sanity factor of one attack of level `s`: sanity_factor for a shooter, 1.0 for
## a banish cast or a summon (the sim never scales those by sanity; shooter-only, F5).
static func shot_factor(s: TowerDef.Level, cfg: GameConfig, sanity: float) -> float:
	if s.is_banish() or s.is_summon():
		return 1.0
	return sanity_factor(s, cfg, sanity)


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


## LT-89: the cooldown ticks a shot, cast or summon of level `s` sets at the interval
## multiplier `interval_mult_` (SimTower.interval_mult): a shooter's fire_interval x it; a
## gate's cast or a circle's summon ignores it (LT-105 Q4). CombatSystem sets every tower
## cooldown with it, and effective()'s dps divides by it, so the two cannot drift.
static func shot_ticks(s: TowerDef.Level, interval_mult_: float) -> int:
	if s.is_banish() or s.is_summon():
		return cooldown_ticks(s.fire_interval)
	return cooldown_ticks(fire_interval(s, interval_mult_))


## LT-89: the seconds between two shots as the sim fires them: shot_ticks / TICK_RATE.
static func shot_period(s: TowerDef.Level, interval_mult_: float) -> float:
	return shot_ticks(s, interval_mult_) / float(SimTime.TICK_RATE)


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
## seconds. `dps` is the stats table's per-second figure as the sim deals it (LT-89):
## dps() over shot_period (whole cooldown ticks, so a lit Rifleman reads 42, not 43.8)
## x factor x power. A level whose interval is whole ticks gets the same bits as
## damage / fire_interval (n / 30.0 is the nearest double to the decimal interval).
## `interval` is shot_period and `interval_ticks` shot_ticks (LT-89: the sim's period, so
## a lit 0.2 s Rifleman L3b reads 0.1667 s, 5 ticks, not 0.16).
static func effective(def: TowerDef, s: TowerDef.Level, cfg: GameConfig, lit := false,
		shadowed := false, sanity := -1.0) -> Dictionary:
	return effective_with(s, cfg, light_effect(def, cfg, lit, shadowed), sanity)


## LT-105 D7: effective() at the modifiers `fx` (power_mult, interval_mult read; a tower's
## channel, SimTower.modifiers, or a light_effect), so the panel shows the numbers the sim
## fires with. `disabled` is not shown here.
static func effective_with(s: TowerDef.Level, cfg: GameConfig, fx: Dictionary,
		sanity := -1.0) -> Dictionary:
	var power: float = fx["power_mult"]
	var factor := 1.0
	if sanity >= 0.0 and cfg != null:
		factor = shot_factor(s, cfg, sanity)
	var im: float = fx["interval_mult"]
	var base := dps(s, s.damage, shot_period(s, im), s.effects.get("summon_dps", 0.0))
	return {
		"damage": shot_damage(s, factor, power),
		"interval": shot_period(s, im),
		"interval_ticks": shot_ticks(s, im),
		"dps": base * factor * power,
		"unit_dps": unit_dps(s, power),
		"factor": factor,
	}


## LT-30 §2 / LT-70 §2.3: the effects of level `s` at power mult `power` on an occult aura,
## gate or circle (Simulation._apply_auras, _cast_banish, _summon): a copy of s.effects with
## the EffectCatalog rows of power "mult" x power and those of power "taken" by
## powered_taken_mult; for a shooter (acts, neither banish nor summon) an unchanged copy
## (a shooter's power scales its damage only).
static func powered_effects(s: TowerDef.Level, power: float) -> Dictionary:
	var e := s.effects.duplicate()
	if s.acts() and not s.is_banish() and not s.is_summon():
		return e
	for key: String in EffectCatalog.power_keys("mult"):
		if e.has(key):
			e[key] = e[key] * power
	for key: String in EffectCatalog.power_keys("taken"):
		if e.has(key):
			e[key] = powered_taken_mult(e[key], power)
	return e


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
