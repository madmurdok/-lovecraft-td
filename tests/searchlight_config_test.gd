class_name SearchlightConfigTest
extends ConfigTestBase
## LT-49 config (docs/design/LT-46-tower-roster.md §2.2 Q1 B, §2.3): the shipped Coast Guard
## searchlight (mundane, glyph S, cost 80, damage 0, the §2.2 table, reveal_fakes 1 on every
## level); `effects.reveal_fakes` is a 0/1 flag and only a support level (damage 0) may carry
## it (the on-hit reveal is LT-50's).

const T := "towers.json"
const SLP := "towers.searchlight"


func _sl(fn: Callable) -> ConfigLoadResult:
	return load_json_edit(T, func(d: Dictionary) -> void: fn.call(d["towers"]["searchlight"]))


func _ok(r: ConfigLoadResult) -> void:
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()


## [range, damage, upgrade_cost] of `l`.
func _row(l: TowerDef.Level) -> Array:
	return [l.range_cells, l.damage, l.upgrade_cost]


func test_shipped_searchlight_matches_the_design_table() -> void:
	var r := GameConfig.load_from_dir("res://data")
	_ok(r)
	var sl: TowerDef = r.config.towers["searchlight"]
	assert_str(sl.name).is_equal("Searchlight")
	assert_str(sl.kind).is_equal("mundane")
	assert_str(sl.glyph).is_equal("S")
	assert_int(sl.cost).is_equal(80)
	assert_int(sl.levels.size()).is_equal(2)
	var a: TowerDef.Level = sl.branches["a"]
	var b: TowerDef.Level = sl.branches["b"]
	assert_array(_row(sl.levels[0])).is_equal([3.0, 0.0, 0])
	assert_array(_row(sl.levels[1])).is_equal([3.5, 0.0, 60])
	assert_array(_row(a)).is_equal([5.0, 0.0, 100])
	assert_array(_row(b)).is_equal([3.5, 0.0, 100])
	assert_str(a.name).is_equal("Signal lamp")
	assert_str(a.role).is_equal("Wide reveal")
	assert_str(b.name).is_equal("Blinding beam")
	assert_str(b.role).is_equal("Slows hard, marks foes")
	assert_dict(sl.levels[0].effects).is_equal({"reveal_fakes": 1.0, "slow": 0.2})
	assert_dict(sl.levels[1].effects).is_equal({"reveal_fakes": 1.0, "slow": 0.25})
	assert_dict(a.effects).is_equal({"reveal_fakes": 1.0, "slow": 0.25})
	assert_dict(b.effects).is_equal(
		{"reveal_fakes": 1.0, "slow": 0.4, "damage_taken_multiplier": 1.2})


func test_reveal_fakes_is_a_zero_or_one_flag() -> void:
	for v: float in [0.0, 1.0]:
		var r := _sl(func(t: Dictionary) -> void: t["levels"][0]["effects"]["reveal_fakes"] = v)
		_ok(r)
		assert_float(r.config.towers["searchlight"].levels[0].effects["reveal_fakes"]) \
			.is_equal(v)
	var half := _sl(func(t: Dictionary) -> void:
		t["levels"][0]["effects"]["reveal_fakes"] = 0.5)
	assert_rejected(half, T, SLP + ".levels[0].effects.reveal_fakes", "must be 0 or 1")
	var two := _sl(func(t: Dictionary) -> void: t["branches"]["a"]["effects"]["reveal_fakes"] = 2)
	assert_rejected(two, T, SLP + ".branches.a.effects.reveal_fakes")


func test_reveal_fakes_on_a_level_with_damage_is_rejected() -> void:
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["rifleman"]["levels"][0]["effects"] = {"reveal_fakes": 1})
	assert_rejected(r, T, "towers.rifleman.levels[0].effects.reveal_fakes",
		"only support towers (damage 0) reveal fakes")
	# 0 is "no flag": allowed anywhere.
	var off := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["rifleman"]["levels"][0]["effects"] = {"reveal_fakes": 0})
	_ok(off)
