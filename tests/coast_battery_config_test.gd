class_name CoastBatteryConfigTest
extends ConfigTestBase
## LT-48 config (docs/design/LT-46-tower-roster.md §2.2, §2.3): the shipped Coast battery
## (mundane, glyph B, cost 120, hits flyers, the §2.2 table); `min_range` (optional, default
## 0, >= 0, < range, only on levels with damage); `effects.ignore_armor` (a 0/1 flag).

const T := "towers.json"
const CB := "towers.coast_battery"


func _cb(fn: Callable) -> ConfigLoadResult:
	return load_json_edit(T, func(d: Dictionary) -> void: fn.call(d["towers"]["coast_battery"]))


func _ok(r: ConfigLoadResult) -> void:
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()


## [range, min_range, damage, fire_interval, upgrade_cost] of `l`.
func _row(l: TowerDef.Level) -> Array:
	return [l.range_cells, l.min_range, l.damage, l.fire_interval, l.upgrade_cost]


func test_shipped_battery_matches_the_design_table() -> void:
	var r := GameConfig.load_from_dir("res://data")
	_ok(r)
	var cb: TowerDef = r.config.towers["coast_battery"]
	assert_str(cb.name).is_equal("Coast battery")
	assert_str(cb.kind).is_equal("mundane")
	assert_str(cb.glyph).is_equal("B")
	assert_int(cb.cost).is_equal(120)
	assert_str(cb.targets).is_equal("all")
	assert_bool(cb.ground_only()).is_false()
	assert_int(cb.levels.size()).is_equal(2)
	assert_array(_row(cb.levels[0])).is_equal([7.0, 2.0, 70.0, 3.0, 0])
	assert_array(_row(cb.levels[1])).is_equal([8.0, 2.0, 95.0, 3.0, 90])
	var a: TowerDef.Level = cb.branches["a"]
	var b: TowerDef.Level = cb.branches["b"]
	assert_array(_row(a)).is_equal([8.0, 2.0, 140.0, 3.2, 150])
	assert_array(_row(b)).is_equal([7.0, 2.0, 100.0, 3.0, 150])
	assert_str(a.name).is_equal("AP shells")
	assert_str(a.role).is_equal("Ignores armor")
	assert_str(b.name).is_equal("HE shells")
	assert_str(b.role).is_equal("Shells splash")
	assert_dict(cb.levels[0].effects).is_empty()
	assert_dict(cb.levels[1].effects).is_empty()
	assert_dict(a.effects).is_equal({"ignore_armor": 1.0})
	assert_dict(b.effects).is_equal({"aoe_radius": 1.0})


func test_min_range_is_optional_and_defaults_to_zero() -> void:
	var r := _cb(func(t: Dictionary) -> void: t["levels"][0].erase("min_range"))
	_ok(r)
	assert_float(r.config.towers["coast_battery"].levels[0].min_range).is_equal(0.0)
	assert_float(r.config.towers["rifleman"].levels[0].min_range).is_equal(0.0)


func test_a_negative_min_range_is_rejected() -> void:
	assert_rejected(_cb(func(t: Dictionary) -> void: t["levels"][0]["min_range"] = -1),
		T, CB + ".levels[0].min_range")


func test_min_range_must_be_less_than_range() -> void:
	for v: float in [7.0, 9.0]:  # L1 range 7: equal and above
		var r := _cb(func(t: Dictionary) -> void: t["levels"][0]["min_range"] = v)
		assert_rejected(r, T, CB + ".levels[0].min_range", "must be less than range")
	var r2 := _cb(func(t: Dictionary) -> void: t["branches"]["b"]["min_range"] = 6.9)
	_ok(r2)
	assert_float(r2.config.towers["coast_battery"].branches["b"].min_range).is_equal(6.9)


func test_a_dead_zone_on_a_support_level_is_rejected() -> void:
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["elder_sign"]["levels"][0]["min_range"] = 1)
	assert_rejected(r, T, "towers.elder_sign.levels[0].min_range",
		"only towers with damage have a dead zone")


func test_ignore_armor_is_a_zero_or_one_flag() -> void:
	for v: float in [0.0, 1.0]:
		var r := _cb(func(t: Dictionary) -> void: t["levels"][0]["effects"] = {"ignore_armor": v})
		_ok(r)
		assert_float(r.config.towers["coast_battery"].levels[0].effects["ignore_armor"]) \
			.is_equal(v)
	var half := _cb(func(t: Dictionary) -> void:
		t["levels"][0]["effects"] = {"ignore_armor": 0.5})
	assert_rejected(half, T, CB + ".levels[0].effects.ignore_armor", "must be 0 or 1")
	var two := _cb(func(t: Dictionary) -> void: t["levels"][0]["effects"] = {"ignore_armor": 2})
	assert_rejected(two, T, CB + ".levels[0].effects.ignore_armor")
