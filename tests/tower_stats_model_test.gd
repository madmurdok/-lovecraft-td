class_name TowerStatsModelTest
extends GdUnitTestSuite
## LT-79 (LT-65 §3.6): TowerStatsModel's numbers against TowerRules called directly (expected
## values come from the rules, never from the model), and the model / text split guards
## (no TowerInfo symbol, TowerText names no rule class, the model builds no display text).

const EPS := 1e-9

var _cfg: GameConfig


func before() -> void:
	_cfg = _load()


func _load() -> GameConfig:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	return r.config


func _def(id: String) -> TowerDef:
	return _cfg.towers[id]


func _rows(id: String, s: TowerDef.Level, sanity_now := -1.0) -> Dictionary:
	return TowerStatsModel.row_numbers(_def(id), s, _cfg, sanity_now)


## The per-second figure by the rules: TowerRules.dps on the base numbers, neutral light.
func _dps(s: TowerDef.Level) -> float:
	return TowerRules.dps(s, s.damage, s.fire_interval, s.effects.get("summon_dps", 0.0))


func _pct_mundane(mult: float) -> float:
	return (1.0 / mult - 1.0) * 100.0


func _near(got: float, want: float, what: String) -> void:
	assert_float(got).override_failure_message("%s: %s != %s" % [what, got, want]) \
		.is_equal_approx(want, EPS)


# --- row_numbers: two kinds, a level-up, branches ----------------------------------------------

func test_mundane_shooter_rows_follow_the_rules_and_change_on_a_level_up() -> void:
	var def := _def("rifleman")
	var im_lit := TowerRules.interval_mult("mundane", _cfg, true, false)
	var im_sh := TowerRules.interval_mult("mundane", _cfg, false, true)
	var seen: Array[float] = []
	for s: TowerDef.Level in def.levels:
		var got := _rows("rifleman", s)
		_near(got["damage"], s.damage, "damage")
		_near(got["every"], TowerRules.fire_interval(s, 1.0), "every")
		_near(got["dps"], _dps(s), "dps")
		_near(got["range"], s.range_cells, "range")
		_near(got["kill"], _cfg.sanity.regen_mundane_kill, "kill")
		_near(got["beam"], _pct_mundane(im_lit), "beam")
		_near(got["shadow"], _pct_mundane(im_sh), "shadow")
		assert_bool(got.has("reserve") or got.has("min_range") or got.has("dps_to")).is_false()
		seen.append(got["dps"])
	assert_float(seen[1]).is_not_equal(seen[0])  # level 2 is not level 1's value


func test_branches_carry_their_own_numbers() -> void:
	var a := _def("rifleman").branches["a"]
	var got := _rows("rifleman", a)
	_near(got["damage"], a.damage, "marksman damage")
	_near(got["range"], a.range_cells, "marksman range")
	_near(got["dps"], _dps(a), "marksman dps")
	var cb := _def("coast_battery").branches["a"]
	var cg := _rows("coast_battery", cb)
	assert_float(cb.min_range).is_greater(0.0)
	_near(cg["min_range"], cb.min_range, "min_range")
	_near(cg["range"], cb.range_cells, "range")
	# a level with no dead zone has no min_range number
	var rl := _def("rifleman").levels[0]
	assert_float(rl.min_range).is_equal(0.0)
	assert_bool(_rows("rifleman", rl).has("min_range")).is_false()


func test_occult_shooter_rows_have_reserve_no_kill_regen_and_the_occult_light_numbers() -> void:
	var pm_lit := TowerRules.power_mult("occult", _cfg, true, false)
	var pm_sh := TowerRules.power_mult("occult", _cfg, false, true)
	var s: TowerDef.Level = _def("necronomicon_reader").branches["b"]
	var got := _rows("necronomicon_reader", s)
	_near(got["damage"], s.damage, "damage")
	_near(got["every"], s.fire_interval, "every")
	_near(got["dps"], _dps(s), "dps")
	_near(got["reserve"], s.sanity_reserve, "reserve")
	assert_bool(got.has("kill")).is_false()
	_near(got["beam"], (pm_lit - 1.0) * 100.0, "beam")
	_near(got["shadow"], (pm_sh - 1.0) * 100.0, "shadow")
	assert_float(got["beam"]).is_not_equal(got["shadow"])


func test_support_tower_has_no_damage_rows_and_a_mundane_support_has_no_light_numbers() -> void:
	var es := _def("elder_sign").levels[1]
	var got := _rows("elder_sign", es)
	for k: String in ["damage", "every", "dps", "kill"]:
		assert_bool(got.has(k)).override_failure_message("elder_sign has " + k).is_false()
	_near(got["reserve"], es.sanity_reserve, "reserve")
	var sl := _def("searchlight").levels[0]
	var sg := _rows("searchlight", sl)
	assert_bool(sg.has("damage") or sg.has("dps") or sg.has("kill")).is_false()
	_near(sg["beam"], 0.0, "mundane support beam")
	_near(sg["shadow"], 0.0, "mundane support shadow")
	assert_dict(TowerStatsModel.lit_numbers(_def("searchlight"), sl, _cfg)).is_empty()


func test_circle_damage_is_its_unit_dps_and_dps_counts_every_unit() -> void:
	var def := _def("summoning_circle")
	for s: TowerDef.Level in [def.levels[0], def.levels[1], def.branches["a"]]:
		var got := _rows("summoning_circle", s)
		_near(got["damage"], s.effects["summon_dps"], "unit dps")
		_near(got["dps"], TowerRules.unit_dps(s, 1.0) * s.summon_max(), "dps")
		_near(got["dps"], _dps(s), "dps rule")


func test_banish_dps_counts_the_foes_one_cast_hits() -> void:
	var s: TowerDef.Level = _def("silver_key").branches["b"]
	_near(TowerStatsModel.dps_value(s), _dps(s), "dps_value")
	assert_dict(TowerStatsModel.dps_numbers(_def("silver_key").levels[0], _cfg)).is_empty()


# --- dps_numbers: beam (sanity-scaled) vs not -----------------------------------------------------

func test_sanity_scaled_dps_gives_a_range_in_the_picker_and_one_value_in_the_panel() -> void:
	var s := _def("resonator").levels[0]
	assert_bool(s.is_beam()).is_true()
	var max_s := _cfg.sanity.max_sanity
	var base := _dps(s)
	var pick := TowerStatsModel.dps_numbers(s, _cfg)
	_near(pick["dps"], base, "picker dps")
	_near(pick["dps_to"], base * TowerRules.sanity_factor(s, _cfg, 0.0), "dps at sanity 0")
	assert_float(pick["dps_to"]).is_not_equal(pick["dps"])
	var now := max_s * 0.4
	var panel := TowerStatsModel.dps_numbers(s, _cfg, now)
	assert_bool(panel.has("dps_to")).is_false()
	_near(panel["dps"], base * TowerRules.sanity_factor(s, _cfg, now), "dps at 40%")
	_near(TowerStatsModel.dps_numbers(s, _cfg, max_s)["dps"], base, "dps at full sanity")
	# no cfg: no scaling, no range
	var plain := TowerStatsModel.dps_numbers(s, null)
	_near(plain["dps"], base, "no cfg")
	assert_bool(plain.has("dps_to")).is_false()
	# a non-beam level ignores sanity_now
	var rf := _def("rifleman").levels[0]
	var r1 := TowerStatsModel.dps_numbers(rf, _cfg, 10.0)
	_near(r1["dps"], _dps(rf), "rifleman dps")
	assert_bool(r1.has("dps_to")).is_false()


# --- lit / shadow ---------------------------------------------------------------------------------

func test_lit_numbers_of_a_mundane_shooter_are_the_rules_lit_and_shadowed_values() -> void:
	var def := _def("rifleman")
	var s := def.levels[1]
	var lit := TowerRules.effective(def, s, _cfg, true, false)
	var sh := TowerRules.effective(def, s, _cfg, false, true)
	var got := TowerStatsModel.lit_numbers(def, s, _cfg)
	_near(got["every"], lit["interval"], "lit every")
	_near(got["dps"], lit["dps"], "lit dps")
	var gs := TowerStatsModel.lit_numbers(def, s, _cfg, -1.0, true)
	_near(gs["every"], sh["interval"], "shadow every")
	_near(gs["dps"], sh["dps"], "shadow dps")
	assert_float(got["every"]).is_not_equal(gs["every"])  # lit and shadow are not swapped
	assert_bool(got.has("damage")).is_false()
	assert_array(got.keys()).is_equal(["every", "dps"])


func test_lit_numbers_of_an_occult_shooter_and_a_circle() -> void:
	var rd := _def("necronomicon_reader")
	var s := rd.levels[0]
	var lit := TowerRules.effective(rd, s, _cfg, true, false)
	var got := TowerStatsModel.lit_numbers(rd, s, _cfg)
	_near(got["damage"], TowerRules.shot_damage(s, 1.0, TowerRules.power_mult("occult", _cfg, true, false)), "lit damage")
	_near(got["dps"], lit["dps"], "lit dps")
	assert_bool(got.has("every")).is_false()
	var sh := TowerRules.effective(rd, s, _cfg, false, true)
	var gs := TowerStatsModel.lit_numbers(rd, s, _cfg, -1.0, true)
	_near(gs["dps"], sh["dps"], "shadow dps")
	assert_float(got["dps"]).is_not_equal(gs["dps"])
	var cd := _def("summoning_circle")
	var cs := cd.levels[1]
	var cl := TowerStatsModel.lit_numbers(cd, cs, _cfg)
	_near(cl["damage"], TowerRules.unit_dps(cs, TowerRules.power_mult("occult", _cfg, true, false)), "unit dps lit")
	_near(cl["dps"], TowerRules.effective(cd, cs, _cfg, true, false)["dps"], "circle lit dps")


func test_lit_numbers_with_sanity_use_the_scaled_rules_value() -> void:
	var def := _def("resonator")
	var s := def.levels[0]
	var now := _cfg.sanity.max_sanity * 0.25
	var got := TowerStatsModel.lit_numbers(def, s, _cfg, now)
	_near(got["dps"], TowerRules.effective(def, s, _cfg, true, false, now)["dps"], "lit dps at sanity")
	var plain := TowerStatsModel.lit_numbers(def, s, _cfg)
	assert_float(got["dps"]).is_not_equal(plain["dps"])


func test_lit_effects_are_the_rules_powered_effects_of_an_occult_tower() -> void:
	var def := _def("elder_sign")
	var s := def.levels[0]
	var pm := TowerRules.power_mult("occult", _cfg, true, false)
	assert_dict(TowerStatsModel.lit_effects(def, s, _cfg)).is_equal(TowerRules.powered_effects(s, pm))
	var psh := TowerRules.power_mult("occult", _cfg, false, true)
	assert_dict(TowerStatsModel.lit_effects(def, s, _cfg, true)).is_equal(TowerRules.powered_effects(s, psh))
	assert_dict(TowerStatsModel.lit_effects(_def("rifleman"), _def("rifleman").levels[0], _cfg)).is_empty()


func test_state_effect_is_the_rules_light_effect_lit_or_shadowed() -> void:
	var def := _def("rifleman")
	assert_dict(TowerStatsModel.state_effect(def, _cfg)).is_equal(TowerRules.light_effect(def, _cfg, true, false))
	assert_dict(TowerStatsModel.state_effect(def, _cfg, true)).is_equal(TowerRules.light_effect(def, _cfg, false, true))


# --- absent beam / shadow / cfg --------------------------------------------------------------------

func test_without_a_shadow_block_the_shadow_numbers_are_empty_but_the_beam_stays() -> void:
	var cfg := _load()
	cfg.economy.shadow = null
	var def := cfg.towers["rifleman"]
	var s := def.levels[0]
	assert_dict(TowerStatsModel.state_effect(def, cfg, true)).is_empty()
	_near(TowerStatsModel.beam_percent(def, s, cfg, true), 0.0, "shadow percent")
	assert_dict(TowerStatsModel.lit_numbers(def, s, cfg, -1.0, true)).is_empty()
	var got := TowerStatsModel.row_numbers(def, s, cfg)
	_near(got["shadow"], 0.0, "shadow row")
	_near(got["beam"], _pct_mundane(TowerRules.interval_mult("mundane", cfg, true, false)), "beam row")
	assert_bool(TowerStatsModel.lit_numbers(def, s, cfg).is_empty()).is_false()


func test_without_a_beam_block_or_a_config_the_light_numbers_are_empty() -> void:
	var cfg := _load()
	cfg.economy.beam = null
	var def := cfg.towers["rifleman"]
	var s := def.levels[0]
	assert_dict(TowerStatsModel.state_effect(def, cfg)).is_empty()
	_near(TowerStatsModel.beam_percent(def, s, cfg), 0.0, "beam percent")
	assert_dict(TowerStatsModel.lit_numbers(def, s, cfg)).is_empty()
	assert_dict(TowerStatsModel.lit_effects(cfg.towers["elder_sign"], cfg.towers["elder_sign"].levels[0], cfg)).is_empty()
	# cfg null: numbers without light or kill regen
	var got := TowerStatsModel.row_numbers(def, s, null)
	_near(got["beam"], 0.0, "beam, no cfg")
	_near(got["shadow"], 0.0, "shadow, no cfg")
	assert_bool(got.has("kill")).is_false()
	_near(got["dps"], _dps(s), "dps, no cfg")
	assert_dict(TowerStatsModel.lit_numbers(def, s, null)).is_empty()


func test_kill_regen_is_for_a_damaging_mundane_tower_only() -> void:
	var regen := _cfg.sanity.regen_mundane_kill
	assert_float(regen).is_greater(0.0)
	_near(TowerStatsModel.kill_regen(_def("rifleman"), _def("rifleman").levels[0], _cfg), regen, "rifleman")
	_near(TowerStatsModel.kill_regen(_def("necronomicon_reader"), _def("necronomicon_reader").levels[0], _cfg), 0.0, "occult")
	_near(TowerStatsModel.kill_regen(_def("searchlight"), _def("searchlight").levels[0], _cfg), 0.0, "support")
	_near(TowerStatsModel.kill_regen(_def("rifleman"), _def("rifleman").levels[0], null), 0.0, "no cfg")


func test_effect_key_neutrals() -> void:
	assert_float(TowerStatsModel.neutral("damage_taken_multiplier")).is_equal(1.0)
	assert_float(TowerStatsModel.neutral("slow")).is_equal(0.0)
	assert_bool(TowerStatsModel.is_active({"slow": 0.2}, "slow")).is_true()
	assert_bool(TowerStatsModel.is_active({"damage_taken_multiplier": 1.0}, "damage_taken_multiplier")).is_false()
	assert_bool(TowerStatsModel.is_active({}, "slow")).is_false()


# --- guards: the model / text split ----------------------------------------------------------------

const GUARD_DIRS := ["res://ui", "res://scenes", "res://tools", "res://tests"]
const TEXT_FILE := "res://ui/text/tower_text.gd"
const MODEL_FILE := "res://ui/model/tower_stats_model.gd"
const RULE_CLASS := "\\b(TowerRules|LightRules)\\b"
## A `%` format operator (`"..." % x`, `% [`) or str() building text.
const FORMAT_USE := "(?<![\\w)\\]])\\s%\\s*[\\[\\w(\"]|\\bstr\\(|\\bString\\.num|\\.pad_|\\bsnapped\\("


func _code(file: String, scan: SimBoundaryTest) -> Array:
	return scan._code_lines(FileAccess.get_file_as_string(file))


func test_no_tower_info_symbol_is_left() -> void:
	var scan := SimBoundaryTest.new()
	var hits: Array[String] = []
	var scanned := 0
	for dir: String in GUARD_DIRS:
		for f in scan._gd_files(dir):
			scanned += 1
			hits.append_array(scan._find(f, _code(f, scan), "\\bTowerInfo\\b"))
	var probe := scan._find("probe.gd", scan._code_lines("var x := TowerInfo.reason(r)"), "\\bTowerInfo\\b")
	var near := scan._find("near.gd", scan._code_lines("var x := TowerText.num(1)"), "\\bTowerInfo\\b")
	scan.free()
	assert_int(scanned).is_greater(20)
	assert_int(probe.size()).is_equal(1)
	assert_array(near).is_empty()
	assert_array(hits).override_failure_message(
		"TowerInfo is gone (LT-79): " + ", ".join(hits)).is_empty()


func test_tower_text_names_no_rule_class() -> void:
	var scan := SimBoundaryTest.new()
	var hits := scan._find(TEXT_FILE, _code(TEXT_FILE, scan), RULE_CLASS)
	var probe := scan._find("probe.gd", scan._code_lines("var d := TowerRules.shot_damage(s, 1.0, p)"), RULE_CLASS)
	var probe2 := scan._find("probe.gd", scan._code_lines("var e := LightRules.mult(x)"), RULE_CLASS)
	scan.free()
	assert_int(probe.size() + probe2.size()).is_equal(2)
	assert_array(hits).override_failure_message(
		"TowerText only formats: ask TowerStatsModel for numbers, not the rules: "
		+ ", ".join(hits)).is_empty()


func test_tower_stats_model_builds_no_display_text() -> void:
	var scan := SimBoundaryTest.new()
	var hits := scan._find(MODEL_FILE, _code(MODEL_FILE, scan), FORMAT_USE)
	var probes := ["var t := \"%s%%\" % x", "var t := \"a %d\" % [n]", "var t := str(v) + \"/s\"",
		"var t := String.num(v, 1)"]
	var probe_hits := 0
	for p: String in probes:
		probe_hits += scan._find("probe.gd", scan._code_lines(p), FORMAT_USE).size()
	var near := scan._find("near.gd", scan._code_lines("var m := a % 2\nvar n := (a + b) % 3"), FORMAT_USE)
	scan.free()
	assert_int(probe_hits).is_equal(probes.size())  # each formatting form is caught
	assert_array(near).is_empty()  # a modulo is not
	assert_array(hits).override_failure_message(
		"TowerStatsModel makes numbers, TowerText makes strings: " + ", ".join(hits)).is_empty()
