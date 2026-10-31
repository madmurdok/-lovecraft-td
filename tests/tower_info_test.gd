class_name TowerInfoTest
extends GdUnitTestSuite
## LT-24 §3 TowerInfo: info lines built from config (stats, drains, effects in
## EFFECT_GROUPS order, kind lines last), "(coming soon)" for PENDING keys, number and cost
## formatting, and the upgrade delta lines. Text formats come from the design note; the
## numbers in them are read from config.

const CS := " (coming soon)"

var _cfg: GameConfig


func before() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_cfg = r.config


func _n(v: float) -> String:
	return TowerInfo.num(v)


func _def(id: String) -> TowerDef:
	return _cfg.towers[id]


func _lines(id: String, s: TowerDef.Level) -> Array:
	return Array(TowerInfo.lines(_def(id), s, _cfg.sanity))


func _mundane_kind() -> Array:
	return ["Kills restore %s sanity" % _n(_cfg.sanity.regen_mundane_kill),
		"May miss while Fraying (%s%%)" % _n(_cfg.sanity.thresholds["fraying"].miss_chance * 100.0)]


func _attack(s: TowerDef.Level) -> Array:
	return ["Damage %s every %s s (%s DPS)" % [_n(s.damage), _n(s.fire_interval),
		_n(s.damage / s.fire_interval)], "Range %s cells" % _n(s.range_cells)]


# --- 15: lines from config ------------------------------------------------------------------

func test_rifleman_l1_reads_damage_range_then_mundane_kind_lines() -> void:
	var l1 := _def("rifleman").levels[0]
	assert_array(_lines("rifleman", l1)).is_equal(_attack(l1) + _mundane_kind())
	# Spec example at today's config.
	if is_equal_approx(l1.damage, 10.0) and is_equal_approx(l1.fire_interval, 0.8):
		assert_str(_lines("rifleman", l1)[0]).is_equal("Damage 10 every 0.8 s (12.5 DPS)")


func test_harpooner_shows_the_line_shot_and_barbed_the_pending_bleed() -> void:
	var h := _def("harpooner")
	var l1 := h.levels[0]
	var line := "Line shot: hits every enemy on a %s-cell-wide line" % _n(l1.effects["pierce"])
	assert_array(_lines("harpooner", l1)).is_equal(_attack(l1) + [line] + _mundane_kind())
	var b := h.branches["a"]
	var bleed := "Bleed: %s damage/s for %s s" % [_n(b.effects["bleed_dps"]), _n(b.effects["bleed_seconds"])]
	assert_array(_lines("harpooner", b)).is_equal(_attack(b)
		+ ["Line shot: hits every enemy on a %s-cell-wide line" % _n(b.effects["pierce"]),
			bleed + CS] + _mundane_kind())
	var c := h.branches["b"]
	assert_array(_lines("harpooner", c)).contains(
		["Pulls the target %s cells back along the path%s" % [_n(c.effects["pull_cells"]), CS]])


func test_elder_sign_is_support_with_aura_and_effects_and_no_kind_line() -> void:
	var l1 := _def("elder_sign").levels[0]
	assert_array(_lines("elder_sign", l1)).is_equal([
		"Support (no damage)",
		"Aura radius %s cells" % _n(l1.range_cells),
		"Slows enemies inside by %s%%" % _n(l1.effects["slow"] * 100.0),
		"Enemies inside take +%s%% damage" % _n((l1.effects["damage_taken_multiplier"] - 1.0) * 100.0),
	])


func test_corrupted_seal_shows_its_pending_drain_and_armor_strip() -> void:
	var seal := _def("elder_sign").branches["b"]
	var got := _lines("elder_sign", seal)
	assert_array(got).contains([
		"−%s sanity/s while on the board%s" % [_n(seal.sanity_per_second), CS],
		"Enemies inside lose %s armor%s" % [_n(seal.effects["strip_armor"]), CS]])
	# Drains come before effects; the strip is the last effect group.
	assert_int(got.find("−%s sanity/s while on the board%s" % [_n(seal.sanity_per_second), CS])) \
		.is_less(got.find("Slows enemies inside by %s%%" % _n(seal.effects["slow"] * 100.0)))
	assert_str(got[got.size() - 1]).is_equal(
		"Enemies inside lose %s armor%s" % [_n(seal.effects["strip_armor"]), CS])


func test_necronomicon_lines_and_the_madness_kind_line() -> void:
	var n := _def("necronomicon_reader")
	var l1 := n.levels[0]
	assert_array(_lines("necronomicon_reader", l1)).is_equal(_attack(l1) + [
		"−%s sanity per cast" % _n(l1.sanity_per_cast),
		"Blast: hits all enemies within %s cells of the target" % _n(l1.effects["aoe_radius"]),
		"In madness: x%s damage, shots go astray" % _n(_cfg.sanity.madness.damage_multiplier)])
	var rite := n.branches["a"]
	var got := _lines("necronomicon_reader", rite)
	assert_str(got[got.size() - 1]).is_equal("Unaffected by madness")
	assert_bool(got.any(func(s: String) -> bool: return s.begins_with("In madness"))).is_false()


func test_dps_is_damage_over_interval_only_militia_ignores_its_pending_shooters() -> void:
	var m := _def("rifleman").branches["b"]
	var got := _lines("rifleman", m)
	assert_str(got[0]).is_equal(_attack(m)[0])
	if is_equal_approx(m.damage, 12.0) and is_equal_approx(m.fire_interval, 0.5):
		assert_str(got[0]).contains("(24 DPS)")
	assert_array(got).contains(["%s shooters%s" % [_n(m.effects["shooters"]), CS]])
	var mk := _def("rifleman").branches["a"]
	assert_array(_lines("rifleman", mk)).contains(["%s%% chance to deal x%s damage%s" % [
		_n(mk.effects["crit_chance"] * 100.0), _n(mk.effects["crit_multiplier"]), CS]])


func test_a_config_edit_changes_the_text() -> void:
	var r := GameConfig.load_from_dir("res://data")
	var def: TowerDef = r.config.towers["rifleman"]
	var l := def.levels[0]
	l.damage = 33.0
	l.fire_interval = 1.5
	l.range_cells = 4.25
	var got := TowerInfo.lines(def, l, r.config.sanity)
	assert_str(got[0]).is_equal("Damage 33 every 1.5 s (22 DPS)")
	assert_str(got[1]).is_equal("Range 4.25 cells")


func test_every_tower_level_and_branch_gets_lines_and_coming_soon_iff_pending() -> void:
	for id: String in _cfg.towers:
		var def := _def(id)
		var all: Array = def.levels.duplicate()
		for b: String in TowerDef.BRANCH_IDS:
			all.append(def.branches[b])
		for s: TowerDef.Level in all:
			var got := _lines(id, s)
			assert_array(got).is_not_empty()
			var first: String = got[0]
			assert_bool(first.begins_with("Damage ") or first == "Support (no damage)") \
				.override_failure_message("%s: %s" % [id, first]).is_true()
			var soon := got.filter(func(x: String) -> bool: return x.ends_with(CS))
			assert_bool(not soon.is_empty()).override_failure_message("%s %s" % [id, got]) \
				.is_equal(s.has_pending())


# --- 16: effect order, pending and unknown keys ---------------------------------------------

func test_effect_lines_follow_effect_groups_order_and_pairs_share_a_line() -> void:
	var got := Array(TowerInfo.effect_lines({"strip_armor": 1.0, "crit_multiplier": 3.0,
		"pierce": 2.0, "crit_chance": 0.5, "slow": 0.1}))
	assert_array(got).is_equal([
		"Line shot: hits every enemy on a 2-cell-wide line",
		"Slows enemies inside by 10%",
		"50% chance to deal x3 damage" + CS,
		"Enemies inside lose 1 armor" + CS,
	])


func test_non_pending_effects_have_no_suffix() -> void:
	for key: String in ["pierce", "aoe_radius", "slow", "damage_taken_multiplier"]:
		assert_bool(TowerDef.Level.PENDING.has(key)).is_false()
		var got := TowerInfo.effect_lines({key: 1.5})
		assert_int(got.size()).is_equal(1)
		assert_bool(got[0].ends_with(CS)).override_failure_message(got[0]).is_false()


func test_an_unknown_effect_key_renders_as_key_and_value() -> void:
	var got := TowerInfo.effect_lines({"slow": 0.5, "frost_aura": 2.5})
	assert_array(Array(got)).is_equal(["Slows enemies inside by 50%", "frost_aura: 2.5"])


# --- 17: kind lines ------------------------------------------------------------------------

func test_kind_lines_per_tower_kind() -> void:
	var s := _cfg.sanity
	assert_array(Array(TowerInfo.kind_lines(_def("rifleman"), _def("rifleman").levels[1], s))) \
		.is_equal(_mundane_kind())
	var n := _def("necronomicon_reader")
	assert_array(Array(TowerInfo.kind_lines(n, n.levels[1], s))) \
		.is_equal(["In madness: x%s damage, shots go astray" % _n(s.madness.damage_multiplier)])
	assert_array(Array(TowerInfo.kind_lines(n, n.branches["a"], s))).is_equal(["Unaffected by madness"])
	var sign := _def("elder_sign")
	for l: TowerDef.Level in [sign.levels[0], sign.levels[1], sign.branches["a"], sign.branches["b"]]:
		assert_array(Array(TowerInfo.kind_lines(sign, l, s))).is_empty()


# --- 18: numbers and costs -----------------------------------------------------------------

func test_num_prints_up_to_two_decimals_without_trailing_zeros() -> void:
	var cases := [[3.5, "3.5"], [82.5, "82.5"], [0.2, "0.2"], [12.0, "12"], [18.0 / 0.7, "25.71"],
		[0.0, "0"], [1.25, "1.25"], [100.0, "100"]]
	for c: Array in cases:
		assert_str(TowerInfo.num(c[0])).override_failure_message(str(c)).is_equal(c[1])


func test_cost_text_and_the_currency_word() -> void:
	assert_str(TowerInfo.CURRENCY).is_equal("gold")
	assert_str(TowerInfo.cost_text(80, 8.0)).is_equal("80 gold + 8 sanity")
	assert_str(TowerInfo.cost_text(40, 0.0)).is_equal("40 gold")
	assert_str(TowerInfo.cost_text(140, 2.5)).is_equal("140 gold + 2.5 sanity")


# --- 19: delta lines -----------------------------------------------------------------------

func _arrow(label: String, a: float, b: float, unit := "") -> String:
	return "%s %s → %s%s" % [label, _n(a), _n(b), unit]


func test_rifleman_l1_to_l2_delta_is_one_line_of_changed_stats() -> void:
	var r := _def("rifleman")
	var a := r.levels[0]
	var b := r.levels[1]
	assert_array(Array(TowerInfo.delta_lines(a, b))).is_equal([" · ".join([
		_arrow("Range", a.range_cells, b.range_cells),
		_arrow("Damage", a.damage, b.damage),
		_arrow("Interval", a.fire_interval, b.fire_interval, " s"),
		_arrow("DPS", a.damage / a.fire_interval, b.damage / b.fire_interval)])])


func test_marksman_delta_skips_the_unchanged_interval_and_adds_the_new_effect() -> void:
	var r := _def("rifleman")
	var a := r.levels[1]
	var b := r.branches["a"]
	assert_float(a.fire_interval).is_equal(b.fire_interval)
	assert_array(Array(TowerInfo.delta_lines(a, b))).is_equal([
		" · ".join([_arrow("Range", a.range_cells, b.range_cells),
			_arrow("Damage", a.damage, b.damage),
			_arrow("DPS", a.damage / a.fire_interval, b.damage / b.fire_interval)]),
		"%s%% chance to deal x%s damage%s" % [_n(b.effects["crit_chance"] * 100.0),
			_n(b.effects["crit_multiplier"]), CS]])


func test_support_delta_uses_aura_radius_and_unchanged_effects_are_left_out() -> void:
	var s := _def("elder_sign")
	var a := s.levels[1]
	var b := s.branches["a"]
	assert_array(Array(TowerInfo.delta_lines(a, b))) \
		.is_equal([_arrow("Aura radius", a.range_cells, b.range_cells)])


func test_same_stats_give_only_the_new_effect_line() -> void:
	var h := _def("harpooner")
	var a := h.levels[1]
	var b := h.branches["a"]
	assert_array(Array(TowerInfo.delta_lines(a, b))).is_equal([
		"Bleed: %s damage/s for %s s%s" % [_n(b.effects["bleed_dps"]), _n(b.effects["bleed_seconds"]), CS]])


func test_pure_rite_delta_ends_with_unaffected_by_madness() -> void:
	var n := _def("necronomicon_reader")
	var got := Array(TowerInfo.delta_lines(n.levels[1], n.branches["a"]))
	assert_int(got.size()).is_equal(2)
	assert_str(got[1]).is_equal("Unaffected by madness")
	assert_array(Array(TowerInfo.delta_lines(n.levels[1], n.branches["b"]))) \
		.not_contains(["Unaffected by madness"])


func test_identical_levels_give_no_delta() -> void:
	for id: String in _cfg.towers:
		var l := _def(id).levels[1]
		assert_array(Array(TowerInfo.delta_lines(l, l))).is_empty()
