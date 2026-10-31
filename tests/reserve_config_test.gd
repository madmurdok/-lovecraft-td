class_name ReserveConfigTest
extends ConfigTestBase
## LT-23 §5.3 config validation (design note §6, pin 11): sanity_reserve only on occult
## towers and never negative, the removed sanity cost keys are unknown fields, the madness
## enemy multipliers are optional numbers > 0 that default to 1.0, and the total reserve is
## not checked against sanity.max.

const T := "towers.json"
const S := "sanity.json"


func test_a_positive_reserve_on_a_mundane_level_or_branch_is_rejected() -> void:
	var cases := [
		["towers.rifleman.levels[0].sanity_reserve",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["levels"][0]["sanity_reserve"] = 5],
		["towers.harpooner.levels[1].sanity_reserve",
			func(d: Dictionary) -> void: d["towers"]["harpooner"]["levels"][1]["sanity_reserve"] = 1],
		["towers.rifleman.branches.a.sanity_reserve",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["branches"]["a"]["sanity_reserve"] = 0.5],
	]
	for c: Array in cases:
		assert_rejected(load_json_edit(T, c[1]), T, c[0], "only occult towers reserve sanity")


func test_a_zero_reserve_on_a_mundane_tower_is_accepted() -> void:
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["rifleman"]["levels"][0]["sanity_reserve"] = 0)
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_float(r.config.towers["rifleman"].levels[0].sanity_reserve).is_equal(0.0)


func test_a_negative_reserve_on_a_branch_is_rejected() -> void:
	assert_rejected(load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["necronomicon_reader"]["branches"]["b"]["sanity_reserve"] = -0.5),
		T, "towers.necronomicon_reader.branches.b.sanity_reserve", "must be")


func test_the_removed_sanity_cost_keys_are_unknown_fields() -> void:
	var cases := [
		["towers.elder_sign.sanity_cost",
			func(d: Dictionary) -> void: d["towers"]["elder_sign"]["sanity_cost"] = 8],
		["towers.elder_sign.levels[1].upgrade_sanity_cost",
			func(d: Dictionary) -> void: d["towers"]["elder_sign"]["levels"][1]["upgrade_sanity_cost"] = 8],
		["towers.elder_sign.branches.a.upgrade_sanity_cost",
			func(d: Dictionary) -> void: d["towers"]["elder_sign"]["branches"]["a"]["upgrade_sanity_cost"] = 8],
		["towers.necronomicon_reader.levels[0].sanity_per_cast",
			func(d: Dictionary) -> void: d["towers"]["necronomicon_reader"]["levels"][0]["sanity_per_cast"] = 2],
		["towers.necronomicon_reader.branches.b.sanity_per_cast",
			func(d: Dictionary) -> void: d["towers"]["necronomicon_reader"]["branches"]["b"]["sanity_per_cast"] = 4],
		["towers.elder_sign.branches.b.sanity_per_second",
			func(d: Dictionary) -> void: d["towers"]["elder_sign"]["branches"]["b"]["sanity_per_second"] = 0.2],
	]
	for c: Array in cases:
		assert_rejected(load_json_edit(T, c[1]), T, c[0], "unknown field")


func test_madness_enemy_multipliers_must_be_above_zero() -> void:
	for key: String in ["enemy_speed_multiplier", "enemy_damage_taken_multiplier"]:
		for v: float in [0.0, -0.5]:
			assert_rejected(load_json_edit(S, func(d: Dictionary) -> void: d["madness"][key] = v),
				S, "madness." + key, "must be")


func test_absent_madness_enemy_multipliers_default_to_one() -> void:
	var r := load_json_edit(S, func(d: Dictionary) -> void:
		d["madness"].erase("enemy_speed_multiplier")
		d["madness"].erase("enemy_damage_taken_multiplier"))
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_float(r.config.sanity.madness.enemy_speed_multiplier).is_equal(1.0)
	assert_float(r.config.sanity.madness.enemy_damage_taken_multiplier).is_equal(1.0)


func test_small_positive_multipliers_are_accepted() -> void:
	var r := load_json_edit(S, func(d: Dictionary) -> void:
		d["madness"]["enemy_speed_multiplier"] = 0.01
		d["madness"]["enemy_damage_taken_multiplier"] = 3)
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_float(r.config.sanity.madness.enemy_damage_taken_multiplier).is_equal(3.0)


func test_total_reserve_above_sanity_max_is_not_checked() -> void:
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		var n: Dictionary = d["towers"]["necronomicon_reader"]
		n["levels"][0]["sanity_reserve"] = 150
		n["levels"][1]["sanity_reserve"] = 200
		n["branches"]["a"]["sanity_reserve"] = 250
		n["branches"]["b"]["sanity_reserve"] = 300)
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_float(r.config.towers["necronomicon_reader"].branches["b"].sanity_reserve) \
		.is_equal(300.0)
