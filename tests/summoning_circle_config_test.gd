class_name SummoningCircleConfigTest
extends ConfigTestBase
## LT-52 config (docs/design/LT-46-tower-roster.md §2.2 table, §3 effect keys; owner Q3
## "HP + contact damage"): the shipped Summoning Circle (occult, glyph C, cost 160, the §2.2
## levels and branches), the enemies' optional contact_dps (default leak_damage x 10, an
## explicit value wins, a negative one is refused) and what the validator refuses on a
## summoning level (accepted choice D4).

const T := "towers.json"
const E := "enemies.json"
const SCP := "towers.summoning_circle"


func _sc(fn: Callable) -> ConfigLoadResult:
	return load_json_edit(T, func(d: Dictionary) -> void: fn.call(d["towers"]["summoning_circle"]))


func _ok(r: ConfigLoadResult) -> void:
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()


## [range, damage, fire_interval, upgrade_cost, sanity_reserve] of `l`.
func _row(l: TowerDef.Level) -> Array:
	return [l.range_cells, l.damage, l.fire_interval, l.upgrade_cost, l.sanity_reserve]


func _fx(n: float, hp: float, dps: float, speed := 1.5) -> Dictionary:
	return {"summon_max": n, "summon_hp": hp, "summon_dps": dps, "summon_lifetime": 20.0,
		"summon_speed": speed}


func test_shipped_summoning_circle_matches_the_design_table() -> void:
	var r := GameConfig.load_from_dir("res://data")
	_ok(r)
	var sc: TowerDef = r.config.towers["summoning_circle"]
	assert_str(sc.name).is_equal("Summoning Circle")
	assert_str(sc.kind).is_equal("occult")
	assert_str(sc.glyph).is_equal("C")
	assert_int(sc.cost).is_equal(160)
	assert_int(sc.levels.size()).is_equal(2)
	var a: TowerDef.Level = sc.branches["a"]
	var b: TowerDef.Level = sc.branches["b"]
	assert_array(_row(sc.levels[0])).is_equal([2.5, 0.0, 10.0, 0, 12.0])
	assert_array(_row(sc.levels[1])).is_equal([3.0, 0.0, 9.0, 120, 20.0])
	assert_array(_row(a)).is_equal([3.0, 0.0, 8.0, 180, 26.0])
	assert_array(_row(b)).is_equal([4.0, 0.0, 10.0, 180, 45.0])
	assert_str(a.name).is_equal("Bound ghouls")
	assert_str(a.role).is_equal("Three sturdier ghouls")
	assert_str(b.name).is_equal("Byakhee")
	assert_str(b.role).is_equal("Winged, hits flyers")
	assert_dict(sc.levels[0].effects).is_equal(_fx(1.0, 120.0, 15.0))
	assert_dict(sc.levels[1].effects).is_equal(_fx(2.0, 150.0, 18.0))
	assert_dict(a.effects).is_equal(_fx(3.0, 200.0, 20.0))
	assert_dict(b.effects).is_equal(_fx(1.0, 150.0, 45.0, 3.0).merged({"summon_flying": 1.0}))


func test_every_circle_level_summons_and_only_byakhee_flies() -> void:
	var r := GameConfig.load_from_dir("res://data")
	_ok(r)
	var sc: TowerDef = r.config.towers["summoning_circle"]
	var levels: Array[TowerDef.Level] = [sc.levels[0], sc.levels[1], sc.branches["a"],
		sc.branches["b"]]
	var maxes: Array = []
	var flies: Array = []
	for l in levels:
		assert_bool(l.is_summon()).is_true()
		assert_bool(l.acts()).is_true()
		assert_bool(l.madness_affected).is_true()
		maxes.append(l.summon_max())
		flies.append(l.summon_flying())
	assert_array(maxes).is_equal([1, 2, 3, 1])
	assert_array(flies).is_equal([false, false, false, true])
	assert_bool(r.config.towers["rifleman"].levels[0].is_summon()).is_false()


# --- contact_dps (Q3) ----------------------------------------------------------------------

func test_contact_dps_defaults_to_ten_times_leak_damage() -> void:
	var r := GameConfig.load_from_dir("res://data")
	_ok(r)
	assert_float(r.config.enemies["cultist"].contact_dps).is_equal(10.0)
	assert_float(r.config.enemies["shoggoth"].contact_dps).is_equal(50.0)
	for id: String in r.config.enemies:
		var e: EnemyDef = r.config.enemies[id]
		assert_float(e.contact_dps).override_failure_message(id) \
			.is_equal(e.leak_damage * 10.0)


func test_an_explicit_contact_dps_overrides_the_default() -> void:
	for v: float in [7.0, 0.0]:
		var r := load_json_edit(E, func(d: Dictionary) -> void:
			d["enemies"]["shoggoth"]["contact_dps"] = v)
		_ok(r)
		assert_float(r.config.enemies["shoggoth"].contact_dps).is_equal(v)
		assert_float(r.config.enemies["cultist"].contact_dps).is_equal(10.0)


func test_a_negative_contact_dps_is_rejected() -> void:
	var r := load_json_edit(E, func(d: Dictionary) -> void:
		d["enemies"]["cultist"]["contact_dps"] = -1)
	assert_rejected(r, E, "enemies.cultist.contact_dps")


# --- validator (D4) ------------------------------------------------------------------------

func test_summon_keys_without_summon_max_are_rejected() -> void:
	for key: String in ["summon_hp", "summon_dps", "summon_lifetime", "summon_speed",
			"summon_flying"]:
		var r := load_json_edit(T, func(d: Dictionary) -> void:
			d["towers"]["rifleman"]["levels"][0]["effects"] = {key: 1})
		assert_rejected(r, T, "towers.rifleman.levels[0].effects." + key, "needs summon_max")


func test_summon_max_must_be_a_whole_number() -> void:
	var r := _sc(func(t: Dictionary) -> void: t["levels"][1]["effects"]["summon_max"] = 1.5)
	assert_rejected(r, T, SCP + ".levels[1].effects.summon_max", "whole number")


func test_a_summoning_level_needs_unit_hp_lifetime_and_speed() -> void:
	for key: String in ["summon_hp", "summon_lifetime", "summon_speed"]:
		var r := _sc(func(t: Dictionary) -> void: t["levels"][0]["effects"].erase(key))
		assert_rejected(r, T, SCP + ".levels[0].effects.summon_max", "needs %s" % key)


func test_a_summoning_level_has_no_damage_or_shot_shape_of_its_own() -> void:
	var dmg := _sc(func(t: Dictionary) -> void: t["levels"][0]["damage"] = 10)
	assert_rejected(dmg, T, SCP + ".levels[0].damage", "cannot combine with summon_max")
	for key: String in ["pierce", "aoe_radius", "banish_cells"]:
		var r := _sc(func(t: Dictionary) -> void: t["branches"]["a"]["effects"][key] = 1)
		assert_rejected(r, T, SCP + ".branches.a.effects." + key,
			"cannot combine with summon_max")


func test_a_circle_without_fire_interval_is_rejected() -> void:
	var r := _sc(func(t: Dictionary) -> void: t["levels"][0]["fire_interval"] = 0)
	assert_rejected(r, T, SCP + ".levels[0].fire_interval")


func test_summon_flying_is_a_flag() -> void:
	for v: float in [0.5, 2.0]:
		var r := _sc(func(t: Dictionary) -> void:
			t["branches"]["b"]["effects"]["summon_flying"] = v)
		assert_rejected(r, T, SCP + ".branches.b.effects.summon_flying")
