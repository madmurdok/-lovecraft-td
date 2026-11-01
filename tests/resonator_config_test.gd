class_name ResonatorConfigTest
extends ConfigTestBase
## LT-50 config (docs/design/LT-46-tower-roster.md §2.2 "Tillinghast Resonator", §2.3): the
## shipped Resonator (occult, glyph T, cost 130, the §2.2 table: ignore_armor and
## sanity_scaling 2/2/1/4 on every level, reveal_fakes and madness_affected false on Pure);
## `effects.sanity_scaling` needs a level with damage; `reveal_fakes` may sit on a level with
## damage (the on-hit reveal) but not with fuse_seconds.

const T := "towers.json"
const RP := "towers.resonator"


func _rs(fn: Callable) -> ConfigLoadResult:
	return load_json_edit(T, func(d: Dictionary) -> void: fn.call(d["towers"]["resonator"]))


func _ok(r: ConfigLoadResult) -> void:
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()


## [range, damage, fire_interval, sanity_reserve, upgrade_cost] of `l`.
func _row(l: TowerDef.Level) -> Array:
	return [l.range_cells, l.damage, l.fire_interval, l.sanity_reserve, l.upgrade_cost]


func test_shipped_resonator_matches_the_design_table() -> void:
	var r := GameConfig.load_from_dir("res://data")
	_ok(r)
	var rs: TowerDef = r.config.towers["resonator"]
	assert_str(rs.name).is_equal("Tillinghast Resonator")
	assert_str(rs.kind).is_equal("occult")
	assert_str(rs.glyph).is_equal("T")
	assert_int(rs.cost).is_equal(130)
	assert_int(rs.levels.size()).is_equal(2)
	var a: TowerDef.Level = rs.branches["a"]
	var b: TowerDef.Level = rs.branches["b"]
	assert_array(_row(rs.levels[0])).is_equal([3.0, 3.0, 0.2, 8.0, 0])
	assert_array(_row(rs.levels[1])).is_equal([3.5, 4.0, 0.2, 14.0, 100])
	assert_array(_row(a)).is_equal([3.5, 6.0, 0.2, 20.0, 160])
	assert_array(_row(b)).is_equal([3.5, 4.5, 0.2, 45.0, 160])
	assert_str(a.name).is_equal("Tuned Resonator")
	assert_str(a.role).is_equal("Steady; shows fakes")
	assert_str(b.name).is_equal("Open Resonator")
	assert_str(b.role).is_equal("Feeds on lost sanity")
	assert_dict(rs.levels[0].effects).is_equal({"ignore_armor": 1.0, "sanity_scaling": 2.0})
	assert_dict(rs.levels[1].effects).is_equal({"ignore_armor": 1.0, "sanity_scaling": 2.0})
	assert_dict(a.effects).is_equal(
		{"ignore_armor": 1.0, "sanity_scaling": 1.0, "reveal_fakes": 1.0})
	assert_dict(b.effects).is_equal({"ignore_armor": 1.0, "sanity_scaling": 4.0})
	assert_bool(rs.levels[0].madness_affected).is_true()
	assert_bool(rs.levels[1].madness_affected).is_true()
	assert_bool(a.madness_affected).is_false()
	assert_bool(b.madness_affected).is_true()


func test_sanity_scaling_on_a_level_without_damage_is_rejected() -> void:
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["elder_sign"]["levels"][0]["effects"]["sanity_scaling"] = 2)
	assert_rejected(r, T, "towers.elder_sign.levels[0].effects.sanity_scaling",
		"needs damage > 0")
	# On any level with damage it loads.
	var ok := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["rifleman"]["levels"][0]["effects"] = {"sanity_scaling": 3})
	_ok(ok)
	assert_float(ok.config.towers["rifleman"].levels[0].effects["sanity_scaling"]).is_equal(3.0)


func test_reveal_fakes_on_a_damage_level_loads_and_with_a_fuse_is_rejected() -> void:
	var on := _rs(func(t: Dictionary) -> void: t["levels"][0]["effects"]["reveal_fakes"] = 1)
	_ok(on)
	assert_float(on.config.towers["resonator"].levels[0].effects["reveal_fakes"]).is_equal(1.0)
	var fused := _rs(func(t: Dictionary) -> void:
		t["branches"]["a"]["effects"]["fuse_seconds"] = 1)
	assert_rejected(fused, T, RP + ".branches.a.effects.reveal_fakes",
		"cannot combine with fuse_seconds")


func test_sanity_factor_reads_the_full_bar_clamped_and_is_one_without_scaling() -> void:
	var r := GameConfig.load_from_dir("res://data")
	_ok(r)
	var max_s := r.config.sanity.max_sanity
	assert_float(max_s).is_equal(100.0)
	var rs: TowerDef = r.config.towers["resonator"]
	var l1 := rs.levels[0]
	assert_bool(l1.is_beam()).is_true()
	assert_float(l1.sanity_factor(40.0, max_s)).is_equal_approx(2.2, 1e-9)
	assert_float(l1.sanity_factor(max_s, max_s)).is_equal(1.0)
	assert_float(l1.sanity_factor(0.0, max_s)).is_equal_approx(3.0, 1e-9)
	# Q2: the full bar, not the cap: 92 (cap after L1's own reserve 8) is not 1.0.
	assert_float(l1.sanity_factor(92.0, max_s)).is_equal_approx(1.16, 1e-9)
	assert_float(l1.sanity_factor(-10.0, max_s)).is_equal_approx(3.0, 1e-9)
	assert_float(l1.sanity_factor(150.0, max_s)).is_equal(1.0)
	assert_float(rs.branches["a"].sanity_factor(0.0, max_s)).is_equal_approx(2.0, 1e-9)
	assert_float(rs.branches["b"].sanity_factor(0.0, max_s)).is_equal_approx(5.0, 1e-9)
	var rifle: TowerDef.Level = r.config.towers["rifleman"].levels[0]
	assert_bool(rifle.is_beam()).is_false()
	assert_float(rifle.sanity_factor(0.0, max_s)).is_equal(1.0)
