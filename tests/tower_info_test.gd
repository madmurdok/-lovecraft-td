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
	var line := "Pierce: %s-cell-wide line" % _n(l1.effects["pierce"])
	assert_array(_lines("harpooner", l1)).is_equal(_attack(l1) + [line] + _mundane_kind())
	var b := h.branches["a"]
	var bleed := "Bleed %s/s for %s s" % [_n(b.effects["bleed_dps"]), _n(b.effects["bleed_seconds"])]
	assert_array(_lines("harpooner", b)).is_equal(_attack(b)
		+ ["Pierce: %s-cell-wide line" % _n(b.effects["pierce"]),
			bleed + CS] + _mundane_kind())
	var c := h.branches["b"]
	assert_array(_lines("harpooner", c)).contains(
		["Pulls back %s cells%s" % [_n(c.effects["pull_cells"]), CS]])


func test_elder_sign_is_support_with_aura_and_effects_and_no_kind_line() -> void:
	var l1 := _def("elder_sign").levels[0]
	assert_array(_lines("elder_sign", l1)).is_equal([
		"Support (no damage)",
		"Aura radius %s cells" % _n(l1.range_cells),
		"Reserves %s sanity" % _n(l1.sanity_reserve),
		"Slows enemies %s%%" % _n(l1.effects["slow"] * 100.0),
		"Foes take +%s%% damage" % _n((l1.effects["damage_taken_multiplier"] - 1.0) * 100.0),
	])


## LT-23: the Seal's drain line became its reserve line; the strip stays pending.
func test_corrupted_seal_shows_its_reserve_and_pending_armor_strip() -> void:
	var seal := _def("elder_sign").branches["b"]
	var got := _lines("elder_sign", seal)
	var reserve := "Reserves %s sanity" % _n(seal.sanity_reserve)
	assert_array(got).contains([reserve,
		"Foes lose %s armor%s" % [_n(seal.effects["strip_armor"]), CS]])
	assert_bool(got.any(func(x: String) -> bool: return x.contains("sanity/s"))).is_false()
	# The reserve comes before effects; the strip is the last effect group.
	assert_int(got.find(reserve)) \
		.is_less(got.find("Slows enemies %s%%" % _n(seal.effects["slow"] * 100.0)))
	assert_str(got[got.size() - 1]).is_equal(
		"Foes lose %s armor%s" % [_n(seal.effects["strip_armor"]), CS])


func test_necronomicon_lines_and_the_madness_kind_line() -> void:
	var n := _def("necronomicon_reader")
	var l1 := n.levels[0]
	assert_array(_lines("necronomicon_reader", l1)).is_equal(_attack(l1) + [
		"Reserves %s sanity" % _n(l1.sanity_reserve),
		"Blast radius %s cells" % _n(l1.effects["aoe_radius"]),
		"Madness: x%s, astray" % _n(_cfg.sanity.madness.damage_multiplier)])
	var rite := n.branches["a"]
	var got := _lines("necronomicon_reader", rite)
	assert_str(got[got.size() - 1]).is_equal("Unaffected by madness")
	assert_bool(got.any(func(s: String) -> bool: return s.begins_with("Madness"))).is_false()


func test_dps_is_damage_over_interval_only_militia_ignores_its_pending_shooters() -> void:
	var m := _def("rifleman").branches["b"]
	var got := _lines("rifleman", m)
	assert_str(got[0]).is_equal(_attack(m)[0])
	if is_equal_approx(m.damage, 12.0) and is_equal_approx(m.fire_interval, 0.5):
		assert_str(got[0]).contains("(24 DPS)")
	assert_array(got).contains(["%s shooters%s" % [_n(m.effects["shooters"]), CS]])
	var mk := _def("rifleman").branches["a"]
	assert_array(_lines("rifleman", mk)).contains(["%s%% crit, x%s damage%s" % [
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
		"Pierce: 2-cell-wide line",
		"Slows enemies 10%",
		"50% crit, x3 damage" + CS,
		"Foes lose 1 armor" + CS,
	])


func test_non_pending_effects_have_no_suffix() -> void:
	for key: String in ["pierce", "aoe_radius", "slow", "damage_taken_multiplier"]:
		assert_bool(TowerDef.Level.PENDING.has(key)).is_false()
		var got := TowerInfo.effect_lines({key: 1.5})
		assert_int(got.size()).is_equal(1)
		assert_bool(got[0].ends_with(CS)).override_failure_message(got[0]).is_false()


func test_an_unknown_effect_key_renders_as_key_and_value() -> void:
	var got := TowerInfo.effect_lines({"slow": 0.5, "frost_aura": 2.5})
	assert_array(Array(got)).is_equal(["Slows enemies 50%", "frost_aura: 2.5"])


# --- 17: kind lines ------------------------------------------------------------------------

func test_kind_lines_per_tower_kind() -> void:
	var s := _cfg.sanity
	assert_array(Array(TowerInfo.kind_lines(_def("rifleman"), _def("rifleman").levels[1], s))) \
		.is_equal(_mundane_kind())
	var n := _def("necronomicon_reader")
	assert_array(Array(TowerInfo.kind_lines(n, n.levels[1], s))) \
		.is_equal(["Madness: x%s, astray" % _n(s.madness.damage_multiplier)])
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
	# LT-27 §2: money is shown as "$" ("gold" stays the internal name).
	assert_str(TowerInfo.CURRENCY).is_equal("$")
	# LT-23 Q5: sanity is reserved, never paid, so a cost is money only.
	assert_str(TowerInfo.cost_text(80)).is_equal("$80")
	assert_str(TowerInfo.cost_text(40)).is_equal("$40")
	assert_str(TowerInfo.cost_text(0)).is_equal("$0")


## LT-23 §1.4: a level without a reserve has no reserve line, and no line names a per-cast
## or per-second sanity cost any more.
func test_reserve_line_iff_the_level_reserves_and_no_cost_lines() -> void:
	for id: String in _cfg.towers:
		var def := _def(id)
		var all: Array = def.levels.duplicate()
		for b: String in TowerDef.BRANCH_IDS:
			all.append(def.branches[b])
		for s: TowerDef.Level in all:
			var got := _lines(id, s)
			var want := "Reserves %s sanity" % _n(s.sanity_reserve)
			assert_bool(got.has(want)).override_failure_message("%s %s" % [id, got]) \
				.is_equal(s.sanity_reserve > 0.0)
			assert_bool(got.any(func(x: String) -> bool:
				return x.contains("per cast") or x.contains("sanity/s"))).is_false()


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
		"%s%% crit, x%s damage%s" % [_n(b.effects["crit_chance"] * 100.0),
			_n(b.effects["crit_multiplier"]), CS]])


func test_support_delta_uses_aura_radius_and_unchanged_effects_are_left_out() -> void:
	var s := _def("elder_sign")
	var a := s.levels[1]
	var b := s.branches["a"]
	assert_array(Array(TowerInfo.delta_lines(a, b))).is_equal([
		_arrow("Aura radius", a.range_cells, b.range_cells),
		"Reserve +%s" % _n(b.sanity_reserve - a.sanity_reserve)])


func test_same_stats_give_only_the_new_effect_line() -> void:
	var h := _def("harpooner")
	var a := h.levels[1]
	var b := h.branches["a"]
	assert_array(Array(TowerInfo.delta_lines(a, b))).is_equal([
		"Bleed %s/s for %s s%s" % [_n(b.effects["bleed_dps"]), _n(b.effects["bleed_seconds"]), CS]])


func test_pure_rite_delta_ends_with_unaffected_by_madness() -> void:
	var n := _def("necronomicon_reader")
	var got := Array(TowerInfo.delta_lines(n.levels[1], n.branches["a"]))
	assert_int(got.size()).is_equal(3)
	assert_str(got[1]).is_equal("Reserve +%s" % _n(n.branches["a"].sanity_reserve
		- n.levels[1].sanity_reserve))
	assert_str(got[2]).is_equal("Unaffected by madness")
	assert_array(Array(TowerInfo.delta_lines(n.levels[1], n.branches["b"]))) \
		.not_contains(["Unaffected by madness"])


func test_identical_levels_give_no_delta() -> void:
	for id: String in _cfg.towers:
		var l := _def(id).levels[1]
		assert_array(Array(TowerInfo.delta_lines(l, l))).is_empty()


## LT-23 §1.4: the reserve delta line, with the sign; none when the reserve is the same.
func test_reserve_delta_line_signs_and_absence() -> void:
	var a := TowerDef.Level.new()
	var b := TowerDef.Level.new()
	a.sanity_reserve = 10.0
	b.sanity_reserve = 15.0
	assert_array(Array(TowerInfo.delta_lines(a, b))).is_equal(["Reserve +5"])
	assert_array(Array(TowerInfo.delta_lines(b, a))).is_equal(["Reserve %s5" % TowerInfo.MINUS])
	b.sanity_reserve = 10.0
	assert_array(Array(TowerInfo.delta_lines(a, b))).is_empty()


## LT-23 Q3: the warning text. The rule itself moved to Simulation.would_drive_mad_build /
## would_drive_mad_upgrade (LT-34) and is pinned in the sim tests.
func test_madness_warning_text() -> void:
	assert_str(TowerInfo.MADNESS_WARNING).is_equal(" (drives you mad!)")


# --- LT-31 ---------------------------------------------------------------------------

func test_target_priority_refusals_and_mode_names_have_texts() -> void:
	assert_str(TowerInfo.REASONS.get(Simulation.CommandResult.NO_TARGETING, "")).is_not_empty()
	assert_str(TowerInfo.REASONS.get(Simulation.CommandResult.BAD_PRIORITY, "")).is_not_empty()
	assert_str(TowerInfo.reason(Simulation.CommandResult.NO_TARGETING)).is_not_equal("unavailable")
	assert_str(TowerInfo.reason(Simulation.CommandResult.BAD_PRIORITY)).is_not_equal("unavailable")
	assert_str(TowerInfo.reason(Simulation.CommandResult.NO_TARGETING)).is_not_equal(TowerInfo.reason(Simulation.CommandResult.BAD_PRIORITY))
	assert_dict(TowerInfo.PRIORITY_NAMES).is_equal({"first": "Closest to the lighthouse",
		"strongest": "Strongest", "fastest": "Fastest"})
	for mode: String in SimTower.TARGET_PRIORITIES:
		assert_bool(TowerInfo.PRIORITY_NAMES.has(mode)).override_failure_message(mode).is_true()


# --- LT-28: neutral multipliers and removed effects ----------------------------------------

func _level(effects: Dictionary) -> TowerDef.Level:
	var l := TowerDef.Level.new()
	l.effects = effects
	return l


## A x1 multiplier changes nothing, so it prints no line (known group or unknown key); any
## other value still does.
func test_a_x1_multiplier_prints_no_effect_line() -> void:
	assert_array(Array(TowerInfo.effect_lines({"damage_taken_multiplier": 1.0}))).is_empty()
	assert_array(Array(TowerInfo.effect_lines({"frost_multiplier": 1.0}))).is_empty()
	assert_array(Array(TowerInfo.effect_lines({"slow": 0.35, "damage_taken_multiplier": 1.0}))) \
		.is_equal(["Slows enemies 35%"])
	assert_array(Array(TowerInfo.effect_lines({"damage_taken_multiplier": 1.5}))) \
		.is_equal(["Foes take +50% damage"])
	assert_array(Array(TowerInfo.effect_lines({"frost_multiplier": 2.0}))) \
		.is_equal(["frost_multiplier: 2"])


## An effect the next level drops (absent, or back at x1) reads "Loses: <old line>"; the
## kept effect is not repeated.
func test_a_removed_effect_prints_loses_and_its_old_line() -> void:
	var from := _level({"slow": 0.35, "damage_taken_multiplier": 1.5})
	var want := [TowerInfo.REMOVED + "Foes take +50% damage"]
	assert_str(TowerInfo.REMOVED).is_equal("Loses: ")
	assert_array(Array(TowerInfo.delta_lines(from, _level({"slow": 0.35})))).is_equal(want)
	assert_array(Array(TowerInfo.delta_lines(from,
		_level({"slow": 0.35, "damage_taken_multiplier": 1.0})))).is_equal(want)
	# An unknown key dropped reads the same way.
	assert_array(Array(TowerInfo.delta_lines(_level({"frost_aura": 2.5}), _level({})))) \
		.is_equal([TowerInfo.REMOVED + "frost_aura: 2.5"])


## A removed pending effect loses its old line without " (coming soon)"; a whole pair group
## shows once.
func test_a_removed_pending_effect_has_no_coming_soon() -> void:
	var from := _level({"crit_chance": 0.5, "crit_multiplier": 3.0})
	assert_bool(TowerInfo.is_pending("crit_chance")).is_true()
	assert_array(Array(TowerInfo.delta_lines(from, _level({})))) \
		.is_equal([TowerInfo.REMOVED + "50% crit, x3 damage"])
