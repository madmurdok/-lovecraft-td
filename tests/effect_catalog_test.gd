class_name EffectCatalogTest
extends GdUnitTestSuite
## LT-103 §2.1 / §2.5: EffectCatalog rows. Catalog sanity (rows name catalog keys, flags
## cap at 1, one row per Mode), equivalence with the key lists it replaced (frozen below from
## TowerDef.Level / TowerRules at 6c4d5b7, plus the two owner-Q2 summon rows), the power
## scaling key set (TowerRules.powered_effects) and the flag pairs (_check_flag_pairs).

## TowerDef.Level.EFFECTS (key -> max) before LT-103, plus owner Q2's summon_contact/leash.
const OLD_EFFECTS := {
	"crit_chance": 1.0, "crit_multiplier": INF, "burst_targets": INF, "pierce": INF,
	"bleed_dps": INF, "bleed_seconds": INF, "pull_cells": INF, "pull_max_hp": INF,
	"pull_immune_seconds": INF, "slow": 1.0, "damage_taken_multiplier": INF,
	"strip_armor": INF, "aoe_radius": INF, "fuse_seconds": INF,
	"ignore_armor": 1.0, "reveal_fakes": 1.0, "sanity_scaling": INF,
	"banish_cells": INF, "banish_targets": INF, "banish_max_hp": INF,
	"banish_immune_seconds": INF,
	"summon_max": INF, "summon_hp": INF, "summon_dps": INF, "summon_lifetime": INF,
	"summon_speed": INF, "summon_flying": 1.0,
	"casts_light": 1.0, "casts_shadow": 1.0,
	"summon_contact": INF, "summon_leash": INF,
}
const OLD_FLAGS := ["ignore_armor", "reveal_fakes", "summon_flying", "casts_light",
	"casts_shadow"]
const OLD_BANISH_KEYS := ["banish_targets", "banish_max_hp", "banish_immune_seconds"]
const OLD_NOT_WITH_BANISH := ["pierce", "aoe_radius", "fuse_seconds", "burst_targets",
	"pull_cells", "sanity_scaling", "slow", "damage_taken_multiplier", "strip_armor",
	"reveal_fakes", "casts_light", "casts_shadow"]
const OLD_SUMMON_KEYS := ["summon_hp", "summon_dps", "summon_lifetime", "summon_speed",
	"summon_flying", "summon_contact", "summon_leash"]
const OLD_SUMMON_REQUIRED := ["summon_hp", "summon_lifetime", "summon_speed"]
const OLD_NOT_WITH_SUMMON := ["pierce", "aoe_radius", "fuse_seconds", "burst_targets",
	"pull_cells", "sanity_scaling", "slow", "damage_taken_multiplier", "strip_armor",
	"reveal_fakes", "crit_chance", "bleed_dps", "ignore_armor", "banish_cells", "casts_light",
	"casts_shadow"]
## TowerRules.POWER_SCALED_EFFECTS before LT-103; damage_taken_multiplier by
## powered_taken_mult.
const OLD_POWER_MULT := ["slow", "strip_armor", "banish_cells", "summon_dps"]


static func _sorted(a: Array) -> Array:
	var c := a.duplicate()
	c.sort()
	return c


static func _parse(effects: Dictionary, damage: float) -> Array:
	var obj := {"range": 3.0, "damage": damage, "effects": effects}
	if damage > 0.0:
		obj["fire_interval"] = 1.0
	var r := ConfigReader.new("towers.json")
	var l := TowerDef.Level.parse(r, obj, "towers.x.levels[0]", false, "occult", false)
	return [l, r.errors]


# --- catalog sanity ---------------------------------------------------------------------

func test_rows_name_catalog_keys_and_flags_cap_at_one() -> void:
	for key: String in EffectCatalog.keys():
		for q: String in EffectCatalog.requires_of(key) + EffectCatalog.not_with_of(key):
			assert_bool(EffectCatalog.has(q)).override_failure_message("%s -> %s" % [key, q]) \
				.is_true()
		if EffectCatalog.is_flag(key):
			assert_float(EffectCatalog.max_of(key)).override_failure_message(key).is_equal(1.0)


func test_each_mode_but_aura_and_single_is_on_exactly_one_row() -> void:
	var count := {}
	for key: String in EffectCatalog.keys():
		var m := EffectCatalog.mode_of(key)
		if m >= 0:
			count[m] = count.get(m, 0) + 1
	for m: int in EffectCatalog.Mode.values():
		var want := 0 if m in [EffectCatalog.Mode.AURA, EffectCatalog.Mode.SINGLE] else 1
		assert_int(count.get(m, 0)).override_failure_message(EffectCatalog.Mode.find_key(m)) \
			.is_equal(want)
	# mode_order is the Mode order (the precedence).
	var modes := EffectCatalog.mode_order().map(func(k: String) -> int:
		return EffectCatalog.mode_of(k))
	assert_array(modes).is_equal(_sorted(modes))
	assert_array(EffectCatalog.mode_order()).is_equal(["banish_cells", "summon_max",
		"sanity_scaling", "burst_targets", "pierce", "fuse_seconds", "aoe_radius"])


# --- equivalence with the deleted lists -----------------------------------------------------

func test_catalog_equals_the_key_lists_it_replaced() -> void:
	assert_array(_sorted(EffectCatalog.keys())).is_equal(_sorted(OLD_EFFECTS.keys()))
	for key: String in OLD_EFFECTS:
		assert_float(EffectCatalog.max_of(key)).override_failure_message(key) \
			.is_equal(OLD_EFFECTS[key])
	assert_array(_sorted(EffectCatalog.flag_keys())).is_equal(_sorted(OLD_FLAGS))
	assert_array(_sorted(EffectCatalog.keys_requiring("banish_cells"))) \
		.is_equal(_sorted(OLD_BANISH_KEYS))
	assert_array(_sorted(EffectCatalog.keys_not_with("banish_cells"))) \
		.is_equal(_sorted(OLD_NOT_WITH_BANISH))
	assert_array(_sorted(EffectCatalog.keys_requiring("summon_max"))) \
		.is_equal(_sorted(OLD_SUMMON_KEYS))
	assert_array(_sorted(EffectCatalog.requires_of("summon_max"))) \
		.is_equal(_sorted(OLD_SUMMON_REQUIRED))
	assert_array(_sorted(EffectCatalog.keys_not_with("summon_max"))) \
		.is_equal(_sorted(OLD_NOT_WITH_SUMMON))
	assert_float(EffectCatalog.neutral("crit_multiplier")).is_equal(1.0)
	assert_float(EffectCatalog.neutral("damage_taken_multiplier")).is_equal(1.0)
	assert_float(EffectCatalog.neutral("slow")).is_equal(0.0)
	# An unknown key keeps the old suffix rule.
	assert_float(EffectCatalog.neutral("frost_multiplier")).is_equal(1.0)
	assert_float(EffectCatalog.neutral("frost_aura")).is_equal(0.0)


# --- 4. power scaling -------------------------------------------------------------------

func test_power_keys_are_the_old_power_scaled_set() -> void:
	assert_array(_sorted(EffectCatalog.power_keys("mult"))).is_equal(_sorted(OLD_POWER_MULT))
	assert_array(EffectCatalog.power_keys("taken")).is_equal(["damage_taken_multiplier"])


func test_powered_effects_scale_auras_gates_and_circles_but_not_shooters() -> void:
	var aura := TowerDef.Level.new()
	aura.effects = {"slow": 0.2, "strip_armor": 2.0, "damage_taken_multiplier": 1.5,
		"casts_shadow": 1.0}
	var a := TowerRules.powered_effects(aura, 0.5)
	assert_float(a["slow"]).is_equal_approx(0.1, 1e-9)
	assert_float(a["strip_armor"]).is_equal_approx(1.0, 1e-9)
	assert_float(a["damage_taken_multiplier"]).is_equal_approx(1.25, 1e-9)
	assert_float(a["casts_shadow"]).is_equal(1.0)
	var gate := TowerDef.Level.new()
	gate.effects = {"banish_cells": 4.0, "banish_max_hp": 500.0}
	var g := TowerRules.powered_effects(gate, 0.5)
	assert_float(g["banish_cells"]).is_equal_approx(2.0, 1e-9)
	assert_float(g["banish_max_hp"]).is_equal(500.0)
	var circle := TowerDef.Level.new()
	circle.effects = {"summon_max": 2.0, "summon_hp": 150.0, "summon_dps": 18.0,
		"summon_speed": 1.5, "summon_contact": 1.0, "summon_leash": 4.0}
	var c := TowerRules.powered_effects(circle, 0.5)
	assert_float(c["summon_dps"]).is_equal_approx(9.0, 1e-9)
	for key: String in ["summon_max", "summon_hp", "summon_speed", "summon_contact",
			"summon_leash"]:
		assert_float(c[key]).override_failure_message(key).is_equal(circle.effects[key])
	var shooter := TowerDef.Level.new()
	shooter.damage = 10.0
	shooter.effects = {"slow": 0.2, "aoe_radius": 1.0}
	assert_dict(TowerRules.powered_effects(shooter, 0.5)).is_equal(shooter.effects)


# --- 6. flag pairs ------------------------------------------------------------------------

func test_reveal_fakes_with_a_fuse_errors_once_and_is_cleared() -> void:
	var p := _parse({"reveal_fakes": 1.0, "fuse_seconds": 1.0, "aoe_radius": 1.0}, 10.0)
	assert_array(p[1]).is_equal(["towers.json: towers.x.levels[0].effects.reveal_fakes: "
		+ "cannot combine with fuse_seconds"])
	var l: TowerDef.Level = p[0]
	assert_float(l.effects["reveal_fakes"]).is_equal(0.0)
	assert_float(l.effects["fuse_seconds"]).is_equal(1.0)


func test_casts_shadow_with_casts_light_errors_once_and_is_cleared() -> void:
	var p := _parse({"casts_light": 1.0, "casts_shadow": 1.0}, 0.0)
	assert_array(p[1]).is_equal(["towers.json: towers.x.levels[0].effects.casts_shadow: "
		+ "cannot combine with casts_light"])
	var l: TowerDef.Level = p[0]
	assert_float(l.effects["casts_shadow"]).is_equal(0.0)
	assert_float(l.effects["casts_light"]).is_equal(1.0)
	assert_bool(l.casts_shadow()).is_false()
	assert_bool(l.casts_light()).is_true()
