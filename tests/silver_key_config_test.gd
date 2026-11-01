class_name SilverKeyConfigTest
extends ConfigTestBase
## LT-51 config (docs/design/LT-46-tower-roster.md §2.2, §5; owner Q4 "HP cap per level"):
## the shipped Silver Key Gate (occult, glyph K, cost 140, the §2.2 table) and what the
## validator refuses: a banishing level without its HP cap (Dagon is never banished, so there
## is no "no cap"), a banish_targets that is not a whole number >= 1, the other banish keys
## without banish_cells, banish_cells beside another shot shape, and a gate with no
## fire_interval. P9: every gate level acts; Elder Sign and Searchlight levels do not.

const T := "towers.json"
const SKP := "towers.silver_key"


func _sk(fn: Callable) -> ConfigLoadResult:
	return load_json_edit(T, func(d: Dictionary) -> void: fn.call(d["towers"]["silver_key"]))


func _ok(r: ConfigLoadResult) -> void:
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()


## [range, damage, fire_interval, upgrade_cost, sanity_reserve] of `l`.
func _row(l: TowerDef.Level) -> Array:
	return [l.range_cells, l.damage, l.fire_interval, l.upgrade_cost, l.sanity_reserve]


func _all_levels(t: TowerDef) -> Array[TowerDef.Level]:
	var out: Array[TowerDef.Level] = []
	out.append_array(t.levels)
	for b: String in t.branches:
		out.append(t.branches[b])
	return out


func test_shipped_silver_key_matches_the_design_table() -> void:
	var r := GameConfig.load_from_dir("res://data")
	_ok(r)
	var sk: TowerDef = r.config.towers["silver_key"]
	assert_str(sk.name).is_equal("Silver Key Gate")
	assert_str(sk.kind).is_equal("occult")
	assert_str(sk.glyph).is_equal("K")
	assert_int(sk.cost).is_equal(140)
	assert_int(sk.levels.size()).is_equal(2)
	var a: TowerDef.Level = sk.branches["a"]
	var b: TowerDef.Level = sk.branches["b"]
	assert_array(_row(sk.levels[0])).is_equal([3.0, 0.0, 6.0, 0, 10.0])
	assert_array(_row(sk.levels[1])).is_equal([3.5, 0.0, 5.0, 110, 16.0])
	assert_array(_row(a)).is_equal([3.5, 0.0, 5.0, 180, 22.0])
	assert_array(_row(b)).is_equal([3.5, 60.0, 5.0, 180, 45.0])
	assert_str(a.name).is_equal("Gate of Slumber")
	assert_str(b.name).is_equal("Ultimate Gate")
	var base := {"banish_max_hp": 500.0, "banish_immune_seconds": 8.0}
	assert_dict(sk.levels[0].effects).is_equal(base.merged({"banish_cells": 4.0}))
	assert_dict(sk.levels[1].effects).is_equal(base.merged({"banish_cells": 5.0}))
	assert_dict(a.effects).is_equal(base.merged({"banish_cells": 5.0, "banish_targets": 3.0}))
	assert_dict(b.effects).is_equal(
		{"banish_cells": 8.0, "banish_max_hp": 4000.0, "banish_immune_seconds": 8.0})
	assert_int(sk.levels[0].banish_targets()).is_equal(1)
	assert_int(a.banish_targets()).is_equal(3)


func test_every_gate_level_acts_and_no_aura_level_does() -> void:
	var r := GameConfig.load_from_dir("res://data")
	_ok(r)
	for l in _all_levels(r.config.towers["silver_key"]):
		assert_bool(l.acts()).is_true()
		assert_bool(l.is_banish()).is_true()
	for id: String in ["elder_sign", "searchlight"]:
		for l in _all_levels(r.config.towers[id]):
			assert_bool(l.acts()).override_failure_message(id).is_false()
	assert_bool(r.config.towers["rifleman"].levels[0].acts()).is_true()


func test_banish_cells_without_an_hp_cap_is_rejected() -> void:
	var r := _sk(func(t: Dictionary) -> void:
		t["levels"][0]["effects"].erase("banish_max_hp"))
	assert_rejected(r, T, SKP + ".levels[0].effects.banish_cells", "needs banish_max_hp")
	var zero := _sk(func(t: Dictionary) -> void:
		t["branches"]["b"]["effects"]["banish_max_hp"] = 0)
	assert_rejected(zero, T, SKP + ".branches.b.effects.banish_cells", "needs banish_max_hp")


func test_banish_targets_must_be_a_whole_number_of_at_least_one() -> void:
	for v: float in [0.5, 1.5]:
		var r := _sk(func(t: Dictionary) -> void:
			t["branches"]["a"]["effects"]["banish_targets"] = v)
		assert_rejected(r, T, SKP + ".branches.a.effects.banish_targets", "whole number")
	for v: float in [1.0, 2.0]:
		var ok := _sk(func(t: Dictionary) -> void:
			t["branches"]["a"]["effects"]["banish_targets"] = v)
		_ok(ok)


func test_banish_keys_without_banish_cells_are_rejected() -> void:
	for key: String in ["banish_targets", "banish_max_hp", "banish_immune_seconds"]:
		var r := load_json_edit(T, func(d: Dictionary) -> void:
			d["towers"]["rifleman"]["levels"][0]["effects"] = {key: 2})
		assert_rejected(r, T, "towers.rifleman.levels[0].effects." + key,
			"needs banish_cells")


func test_banish_cells_with_another_shot_shape_is_rejected() -> void:
	for key: String in ["pierce", "aoe_radius", "pull_cells", "slow", "reveal_fakes"]:
		var r := _sk(func(t: Dictionary) -> void: t["levels"][0]["effects"][key] = 1)
		assert_rejected(r, T, SKP + ".levels[0].effects." + key,
			"cannot combine with banish_cells")


func test_a_gate_without_fire_interval_is_rejected() -> void:
	var r := _sk(func(t: Dictionary) -> void: t["levels"][0].erase("fire_interval"))
	assert_rejected(r, T, SKP + ".levels[0].fire_interval")
