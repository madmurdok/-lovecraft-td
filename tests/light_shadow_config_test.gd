class_name LightShadowConfigTest
extends ConfigTestBase
## LT-70 §3, §8 item 11: the `shadow` economy block and the casts_light / casts_shadow
## effect flags are validated at load time.

const E := "economy.json"
const T := "towers.json"


func _shadow(fn: Callable) -> ConfigLoadResult:
	return load_json_edit(E, func(d: Dictionary) -> void: fn.call(d["shadow"]))


func _lvl0(id: String, fn: Callable) -> ConfigLoadResult:
	return load_json_edit(T, func(d: Dictionary) -> void:
		fn.call(d["towers"][id]["levels"][0]))


func _mentions(r: ConfigLoadResult, key: String) -> void:
	assert_bool(r.ok).is_false()
	assert_bool(r.errors.any(func(e: String) -> bool: return e.contains(key))) \
		.override_failure_message("no error naming %s:\n%s" % [key, "\n".join(r.errors)]) \
		.is_true()


func test_the_shipped_shadow_block_loads_with_the_design_numbers() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).is_true()
	var s := r.config.economy.shadow
	assert_float(s.mundane_fire_interval_mult).is_equal(1.25)
	assert_float(s.mundane_miss_chance_add).is_equal(0.1)
	assert_float(s.occult_power_mult).is_equal(1.15)


func test_an_absent_shadow_block_loads_as_null() -> void:
	var r := load_json_edit(E, func(d: Dictionary) -> void: d.erase("shadow"))
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_object(r.config.economy.shadow).is_null()


func test_bad_shadow_numbers_and_keys_are_rejected() -> void:
	assert_rejected(_shadow(func(s: Dictionary) -> void: s["occult"]["power_mult"] = 0),
		E, "shadow.occult.power_mult")
	assert_rejected(_shadow(func(s: Dictionary) -> void:
		s["mundane"]["fire_interval_mult"] = 0), E, "shadow.mundane.fire_interval_mult")
	assert_rejected(_shadow(func(s: Dictionary) -> void:
		s["mundane"]["miss_chance_add"] = 1.5), E, "shadow.mundane.miss_chance_add")
	assert_rejected(_shadow(func(s: Dictionary) -> void: s["bogus"] = 1), E, "shadow.bogus")
	assert_rejected(_shadow(func(s: Dictionary) -> void: s["mundane"]["bogus"] = 1),
		E, "shadow.mundane.bogus")
	assert_rejected(_shadow(func(s: Dictionary) -> void: s["occult"]["bogus"] = 1),
		E, "shadow.occult.bogus")
	# Control: in-range values load.
	var ok := _shadow(func(s: Dictionary) -> void:
		s["mundane"]["miss_chance_add"] = 1.0
		s["occult"]["power_mult"] = 2.0)
	assert_bool(ok.ok).override_failure_message("\n".join(ok.errors)).is_true()


func test_casts_light_on_a_damage_level_is_rejected() -> void:
	var r := _lvl0("rifleman", func(l: Dictionary) -> void:
		l["effects"] = {"casts_light": 1})
	assert_rejected(r, T, "towers.rifleman.levels[0].effects.casts_light")
	var s := _lvl0("rifleman", func(l: Dictionary) -> void:
		l["effects"] = {"casts_shadow": 1})
	assert_rejected(s, T, "towers.rifleman.levels[0].effects.casts_shadow")


func test_both_flags_on_one_level_are_rejected() -> void:
	var r := _lvl0("searchlight", func(l: Dictionary) -> void:
		l["effects"]["casts_shadow"] = 1)
	assert_rejected(r, T, "towers.searchlight.levels[0].effects.casts_shadow")


func test_a_flag_value_of_2_is_rejected_and_0_and_1_load() -> void:
	var two := _lvl0("searchlight", func(l: Dictionary) -> void: l["effects"]["casts_light"] = 2)
	assert_rejected(two, T, "towers.searchlight.levels[0].effects.casts_light")
	var off := _lvl0("searchlight", func(l: Dictionary) -> void: l["effects"]["casts_light"] = 0)
	assert_bool(off.ok).override_failure_message("\n".join(off.errors)).is_true()


func test_casts_flags_cannot_combine_with_banish_or_summon() -> void:
	_mentions(_lvl0("silver_key", func(l: Dictionary) -> void:
		l["effects"]["casts_light"] = 1), "casts_light")
	_mentions(_lvl0("summoning_circle", func(l: Dictionary) -> void:
		l["effects"]["casts_shadow"] = 1), "casts_shadow")
