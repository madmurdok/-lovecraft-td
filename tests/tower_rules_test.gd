class_name TowerRulesTest
extends GdUnitTestSuite
## LT-76 (LT-65 §3.2): TowerRules values on small hand-checked cases. The light / shadow
## multipliers are set on the loaded config to distinct round numbers, so every arm (lit,
## shadowed, neither) reads a different value and the arithmetic is checkable by hand.
## Levels are built in code; DPS from whole cooldown ticks is LT-89, not pinned here.

const LIT_POWER := 0.5
const SHADOW_POWER := 3.0
const LIT_INTERVAL := 0.5
const SHADOW_INTERVAL := 2.0
const SHADOW_MISS := 0.25

var _cfg: GameConfig


func before_test() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_cfg = r.config
	var beam := _cfg.economy.beam
	beam.occult_power_mult = LIT_POWER
	beam.mundane_fire_interval_mult = LIT_INTERVAL
	beam.mundane_ignore_miss = true
	var shadow := _cfg.economy.shadow
	shadow.occult_power_mult = SHADOW_POWER
	shadow.mundane_fire_interval_mult = SHADOW_INTERVAL
	shadow.mundane_miss_chance_add = SHADOW_MISS


func _lvl(damage: float, interval: float, effects := {}) -> TowerDef.Level:
	var l := TowerDef.Level.new()
	l.damage = damage
	l.fire_interval = interval
	l.effects = effects
	return l


# --- light / shadow multipliers ---------------------------------------------------------

func test_power_mult_is_occult_only_lit_or_shadowed() -> void:
	assert_float(TowerRules.power_mult("occult", _cfg, true, false)).is_equal(LIT_POWER)
	assert_float(TowerRules.power_mult("occult", _cfg, false, true)).is_equal(SHADOW_POWER)
	assert_float(TowerRules.power_mult("occult", _cfg, false, false)).is_equal(1.0)
	assert_float(TowerRules.power_mult("mundane", _cfg, true, false)).is_equal(1.0)
	assert_float(TowerRules.power_mult("mundane", _cfg, false, true)).is_equal(1.0)
	_cfg.economy.shadow = null  # no shadow block: shadowed is neutral
	assert_float(TowerRules.power_mult("occult", _cfg, false, true)).is_equal(1.0)
	assert_float(TowerRules.power_mult("occult", null, true, false)).is_equal(1.0)


func test_interval_mult_is_mundane_only_lit_or_shadowed() -> void:
	assert_float(TowerRules.interval_mult("mundane", _cfg, true, false)).is_equal(LIT_INTERVAL)
	assert_float(TowerRules.interval_mult("mundane", _cfg, false, true)).is_equal(SHADOW_INTERVAL)
	assert_float(TowerRules.interval_mult("mundane", _cfg, false, false)).is_equal(1.0)
	assert_float(TowerRules.interval_mult("occult", _cfg, true, false)).is_equal(1.0)
	assert_float(TowerRules.interval_mult("occult", _cfg, false, true)).is_equal(1.0)
	_cfg.economy.shadow = null
	assert_float(TowerRules.interval_mult("mundane", _cfg, false, true)).is_equal(1.0)


func test_no_miss_when_lit_and_miss_add_when_shadowed() -> void:
	assert_bool(TowerRules.ignore_miss("mundane", _cfg, true)).is_true()
	assert_bool(TowerRules.ignore_miss("mundane", _cfg, false)).is_false()
	assert_bool(TowerRules.ignore_miss("occult", _cfg, true)).is_false()
	_cfg.economy.beam.mundane_ignore_miss = false
	assert_bool(TowerRules.ignore_miss("mundane", _cfg, true)).is_false()
	assert_float(TowerRules.miss_add("mundane", _cfg, true)).is_equal(SHADOW_MISS)
	assert_float(TowerRules.miss_add("mundane", _cfg, false)).is_equal(0.0)
	assert_float(TowerRules.miss_add("occult", _cfg, true)).is_equal(0.0)
	_cfg.economy.shadow = null
	assert_float(TowerRules.miss_add("mundane", _cfg, true)).is_equal(0.0)


func test_light_effect_bundles_the_four_rules_and_null_is_neutral() -> void:
	var rifle: TowerDef = _cfg.towers["rifleman"]
	var neutral := {"power_mult": 1.0, "interval_mult": 1.0, "ignore_miss": false,
		"miss_add": 0.0}
	assert_dict(TowerRules.light_effect(rifle, _cfg, true, false)).is_equal(
		{"power_mult": 1.0, "interval_mult": LIT_INTERVAL, "ignore_miss": true, "miss_add": 0.0})
	assert_dict(TowerRules.light_effect(rifle, _cfg, false, true)).is_equal(
		{"power_mult": 1.0, "interval_mult": SHADOW_INTERVAL, "ignore_miss": false,
			"miss_add": SHADOW_MISS})
	var occult: TowerDef = _cfg.towers["resonator"]
	assert_dict(TowerRules.light_effect(occult, _cfg, true, false)).is_equal(
		{"power_mult": LIT_POWER, "interval_mult": 1.0, "ignore_miss": false, "miss_add": 0.0})
	assert_dict(TowerRules.light_effect(null, _cfg, true, false)).is_equal(neutral)
	assert_dict(TowerRules.light_effect(rifle, null, true, false)).is_equal(neutral)
	# Neither flag set: neutral, whatever the config says (light and shadow cancel upstream).
	assert_dict(TowerRules.light_effect(rifle, _cfg, false, false)).is_equal(neutral)


# --- sanity factor, shot arithmetic -----------------------------------------------------

func test_sanity_factor_is_shooter_only_in_shot_factor() -> void:
	var beam := _lvl(3.0, 0.2, {"sanity_scaling": 2.0})
	assert_float(TowerRules.sanity_factor(beam, _cfg, 100.0)).is_equal(1.0)
	assert_float(TowerRules.sanity_factor(beam, _cfg, 50.0)).is_equal(2.0)  # 1 + 2 x 0.5
	assert_float(TowerRules.sanity_factor(beam, _cfg, 0.0)).is_equal(3.0)
	assert_float(TowerRules.shot_factor(beam, _cfg, 50.0)).is_equal(2.0)
	var banish := _lvl(0.0, 5.0, {"banish_cells": 4.0, "sanity_scaling": 2.0})
	var summon := _lvl(0.0, 5.0, {"summon_max": 1.0, "summon_dps": 10.0, "sanity_scaling": 2.0})
	assert_float(TowerRules.sanity_factor(banish, _cfg, 0.0)).is_equal(3.0)
	assert_float(TowerRules.shot_factor(banish, _cfg, 0.0)).is_equal(1.0)
	assert_float(TowerRules.shot_factor(summon, _cfg, 0.0)).is_equal(1.0)
	assert_float(TowerRules.shot_factor(_lvl(10.0, 1.0), _cfg, 0.0)).is_equal(1.0)


func test_shot_damage_interval_cooldown_and_unit_dps() -> void:
	var s := _lvl(10.0, 0.8)
	assert_float(TowerRules.shot_damage(s, 2.0, 1.5)).is_equal(30.0)
	assert_float(TowerRules.fire_interval(s, 1.25)).is_equal_approx(1.0, 1e-9)
	assert_int(TowerRules.cooldown_ticks(1.0)).is_equal(SimTime.TICK_RATE)
	assert_int(TowerRules.cooldown_ticks(0.0)).is_equal(1)  # never below one tick
	assert_int(TowerRules.cooldown_ticks(0.001)).is_equal(1)
	var circle := _lvl(0.0, 10.0, {"summon_max": 2.0, "summon_dps": 15.0})
	assert_float(TowerRules.unit_dps(circle, 0.5)).is_equal(7.5)
	assert_float(TowerRules.unit_dps(s, 0.5)).is_equal(0.0)


func test_powered_taken_mult_scales_only_the_bonus() -> void:
	assert_float(TowerRules.powered_taken_mult(1.5, 1.0)).is_equal(1.5)
	assert_float(TowerRules.powered_taken_mult(1.5, 0.5)).is_equal(1.25)
	assert_float(TowerRules.powered_taken_mult(1.5, 0.0)).is_equal(1.0)
	assert_float(TowerRules.powered_taken_mult(1.0, 3.0)).is_equal(1.0)


func test_powered_effects_scale_the_aura_keys_and_leave_a_shooter_alone() -> void:
	var aura := _lvl(0.0, 0.0, {"slow": 0.2, "strip_armor": 1.0,
		"damage_taken_multiplier": 1.5, "casts_shadow": 1.0})
	var e := TowerRules.powered_effects(aura, 0.5)
	assert_float(e["slow"]).is_equal(0.1)
	assert_float(e["strip_armor"]).is_equal(0.5)
	assert_float(e["damage_taken_multiplier"]).is_equal(1.25)
	assert_float(e["casts_shadow"]).is_equal(1.0)  # not a power-scaled key
	assert_float(aura.effects["slow"]).is_equal(0.2)  # a copy, the level is untouched
	var circle := _lvl(0.0, 10.0, {"summon_max": 2.0, "summon_dps": 10.0})
	assert_float(TowerRules.powered_effects(circle, 0.5)["summon_dps"]).is_equal(5.0)
	var banish := _lvl(0.0, 5.0, {"banish_cells": 4.0})
	assert_float(TowerRules.powered_effects(banish, 0.5)["banish_cells"]).is_equal(2.0)
	# A shooter's power scales its damage only: the effects come back unchanged.
	var shooter := _lvl(10.0, 1.0, {"slow": 0.2})
	assert_dict(TowerRules.powered_effects(shooter, 0.5)).is_equal({"slow": 0.2})


func test_dps_by_attack_kind() -> void:
	assert_float(TowerRules.dps(_lvl(10.0, 2.0), 10.0, 2.0, 0.0)).is_equal(5.0)
	var gate := _lvl(6.0, 2.0, {"banish_cells": 4.0, "banish_targets": 3.0})
	assert_float(TowerRules.dps(gate, 6.0, 2.0, 0.0)).is_equal(9.0)  # 6 / 2 x 3 targets
	var circle := _lvl(0.0, 10.0, {"summon_max": 2.0, "summon_dps": 10.0})
	assert_float(TowerRules.dps(circle, 0.0, 10.0, 10.0)).is_equal(20.0)  # unit x summon_max
	assert_float(TowerRules.dps(_lvl(0.0, 2.0), 0.0, 2.0, 0.0)).is_equal(0.0)  # no damage
	assert_float(TowerRules.dps(_lvl(10.0, 0.0), 10.0, 0.0, 0.0)).is_equal(0.0)  # no interval


# --- effective ---------------------------------------------------------------------------

func test_effective_mundane_lit_shadowed_and_plain() -> void:
	var def: TowerDef = _cfg.towers["rifleman"]
	var s := _lvl(10.0, 2.0)
	var plain := TowerRules.effective(def, s, _cfg)
	assert_float(plain["damage"]).is_equal(10.0)
	assert_float(plain["interval"]).is_equal(2.0)
	assert_float(plain["dps"]).is_equal(5.0)
	assert_float(plain["factor"]).is_equal(1.0)
	var lit := TowerRules.effective(def, s, _cfg, true, false)
	assert_float(lit["interval"]).is_equal(1.0)  # 2 x 0.5
	assert_int(lit["interval_ticks"]).is_equal(SimTime.TICK_RATE)
	assert_float(lit["dps"]).is_equal(10.0)  # 5 / 0.5
	assert_float(lit["damage"]).is_equal(10.0)  # a mundane tower's power stays 1
	var dark := TowerRules.effective(def, s, _cfg, false, true)
	assert_float(dark["interval"]).is_equal(4.0)  # 2 x 2
	assert_float(dark["dps"]).is_equal(2.5)
	var neutral := TowerRules.effective(null, s, _cfg, true, true)  # null def: neutral light
	assert_float(neutral["dps"]).is_equal(5.0)


func test_effective_occult_power_and_sanity_factor() -> void:
	var def: TowerDef = _cfg.towers["resonator"]
	var s := _lvl(3.0, 0.2, {"sanity_scaling": 2.0})
	var lit := TowerRules.effective(def, s, _cfg, true, false, 50.0)
	assert_float(lit["factor"]).is_equal(2.0)
	assert_float(lit["damage"]).is_equal(3.0)  # 3 x 2 x 0.5
	assert_float(lit["interval"]).is_equal_approx(0.2, 1e-9)  # occult: interval untouched
	assert_float(lit["dps"]).is_equal_approx(15.0, 1e-9)  # (3 / 0.2) x 2 x 0.5
	var shadowed := TowerRules.effective(def, s, _cfg, false, true, 50.0)
	assert_float(shadowed["damage"]).is_equal(18.0)  # 3 x 2 x 3
	# Sanity < 0 means "no sanity scaling": factor 1.
	var flat := TowerRules.effective(def, s, _cfg, false, false, -1.0)
	assert_float(flat["factor"]).is_equal(1.0)
	assert_float(flat["damage"]).is_equal(3.0)


func test_effective_circle_unit_dps_takes_the_power_mult() -> void:
	var def: TowerDef = _cfg.towers["summoning_circle"]
	var s := _lvl(0.0, 10.0, {"summon_max": 2.0, "summon_dps": 10.0})
	var lit := TowerRules.effective(def, s, _cfg, true, false)
	assert_float(lit["unit_dps"]).is_equal(5.0)
	assert_float(lit["dps"]).is_equal(10.0)  # (10 x 2) x 0.5
	var plain := TowerRules.effective(def, s, _cfg)
	assert_float(plain["unit_dps"]).is_equal(10.0)
	assert_float(plain["dps"]).is_equal(20.0)


# --- dead zone ----------------------------------------------------------------------------

func test_dead_zone_is_strictly_inside_the_min_range() -> void:
	var c := Vector2(3.5, 1.5)
	assert_bool(TowerRules.in_dead_zone(c, 2.0, Vector2(5.0, 1.5))).is_true()  # 1.5 away
	assert_bool(TowerRules.in_dead_zone(c, 2.0, Vector2(5.49, 1.5))).is_true()
	assert_bool(TowerRules.in_dead_zone(c, 2.0, Vector2(5.5, 1.5))).is_false()  # exactly 2
	assert_bool(TowerRules.in_dead_zone(c, 2.0, Vector2(7.5, 1.5))).is_false()
	assert_bool(TowerRules.in_dead_zone(c, 0.0, c)).is_false()  # no dead zone, even on top
	var battery: TowerDef = _cfg.towers["coast_battery"]
	assert_float(TowerRules.dead_zone(battery.levels[0])).is_equal(battery.levels[0].min_range)
	assert_float(TowerRules.dead_zone(_lvl(1.0, 1.0))).is_equal(0.0)
