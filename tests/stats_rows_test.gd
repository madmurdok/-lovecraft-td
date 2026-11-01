class_name StatsRowsTest
extends GdUnitTestSuite
## LT-53 (LT-43 §1, §5, Q3, Q4): the unified table's cells as TowerInfo builds them. Every
## expectation is computed here from the loaded config (TowerDef / SanityConfig /
## EconomyConfig.beam) by the rule the design note states, never copied from the code:
## the row set and its order, the dash rule, the DPS formulas (summon_dps x summon_max, the
## Resonator range), the beam percent, the lit values with "*", the lit effects and status
## line, the picker's Special cell and the upgrade path.

const DASH := "—"
const STAR := "*"
const MINUS := "−"

var _cfg: GameConfig


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_cfg = r.config


func _n(v: float) -> String:
	return TowerInfo.num(v)


## One decimal at most (LT-43 §1 DPS), formatted like every other table number.
func _d1(v: float) -> String:
	return _n(roundf(v * 10.0) / 10.0)


func _def(id: String) -> TowerDef:
	return _cfg.towers[id]


## [label, level] for L1, L2 and each branch of `def`.
func _states(def: TowerDef) -> Array:
	var out := [["L1", def.levels[0]], ["L2", def.levels[1]]]
	for b: String in def.branches:
		out.append([b.to_upper(), def.branches[b]])
	return out


func _e(s: TowerDef.Level, key: String) -> float:
	return float(s.effects.get(key, 0.0))


## LT-43 §1 DPS, from config: damage / interval x foes per cast; a circle summon_dps x
## summon_max; 0 for none.
func _dps(s: TowerDef.Level) -> float:
	if _e(s, "summon_max") > 0.0:
		return _e(s, "summon_dps") * _e(s, "summon_max")
	if s.damage <= 0.0:
		return 0.0
	return s.damage / s.fire_interval * maxf(1.0, _e(s, "banish_targets"))


# --- §1: the row set ------------------------------------------------------------------------

func test_rows_are_the_ten_rows_of_the_note_in_order() -> void:
	var keys := []
	var labels := []
	for row: Array in TowerInfo.ROWS:
		keys.append(row[0])
		labels.append(row[1])
	assert_array(labels).is_equal(["Attack", "Damage", "Every, s", "DPS", "Range", "Hits",
		"Sanity/kill", "Reserve", "In beam", "Special"])
	for id: String in _cfg.towers:
		for st: Array in _states(_def(id)):
			var v := TowerInfo.row_values(_def(id), st[1], _cfg)
			assert_array(v.keys()).override_failure_message("%s %s" % [id, st[0]]) \
				.contains_exactly_in_any_order(keys)
			for k: String in keys:
				assert_str(v[k]).override_failure_message("%s %s %s empty" % [id, st[0], k]) \
					.is_not_empty()


## §1 "Not applicable -> —", every tower, level and branch: no damage (aura, plain banish),
## no action (aura: Every), no DPS, kill only for a damaging mundane tower, reserve only when
## reserved, the beam row "—" only for a mundane support tower. Never "0".
func test_dash_rule_for_every_tower_level_and_branch() -> void:
	var kill := "+" + _n(_cfg.sanity.regen_mundane_kill)
	assert_float(_cfg.sanity.regen_mundane_kill).is_greater(0.0)
	for id: String in _cfg.towers:
		var def := _def(id)
		for st: Array in _states(def):
			var s: TowerDef.Level = st[1]
			var tag := "%s %s" % [id, st[0]]
			var v := TowerInfo.row_values(def, s, _cfg)
			var summon := _e(s, "summon_max") > 0.0
			var acts := s.damage > 0.0 or _e(s, "banish_cells") > 0.0 or summon
			if s.damage <= 0.0 and not summon:
				_eq(v["damage"], DASH, tag + " damage")
			else:
				assert_str(v["damage"]).override_failure_message(tag).is_not_equal(DASH)
			_eq(v["every"], _n(s.fire_interval) if acts else DASH, tag + " every")
			if _dps(s) > 0.0:
				assert_str(v["dps"]).override_failure_message(tag).is_not_equal(DASH)
			else:
				_eq(v["dps"], DASH, tag + " dps")
			var mundane_shooter := def.kind == "mundane" and s.damage > 0.0
			_eq(v["kill"], kill if mundane_shooter else DASH, tag + " kill")
			_eq(v["reserve"], _n(s.sanity_reserve) if s.sanity_reserve > 0.0 else DASH,
				tag + " reserve")
			if def.kind == "mundane" and s.damage <= 0.0:
				_eq(v["beam"], DASH, tag + " beam")
			else:
				assert_str(v["beam"]).override_failure_message(tag).is_not_equal(DASH)
			for k: String in v:
				assert_str(v[k]).override_failure_message("%s %s reads 0" % [tag, k]) \
					.is_not_equal("0")
	# The shipped cases the note names.
	for id: String in ["elder_sign", "searchlight"]:
		var v := TowerInfo.row_values(_def(id), _def(id).levels[0], _cfg)
		assert_array([v["damage"], v["every"], v["dps"]]).is_equal([DASH, DASH, DASH])
	assert_str(TowerInfo.row_values(_def("searchlight"), _def("searchlight").levels[0], _cfg)
		["beam"]).is_equal(DASH)
	var key := TowerInfo.row_values(_def("silver_key"), _def("silver_key").levels[0], _cfg)
	assert_array([key["damage"], key["dps"]]).is_equal([DASH, DASH])


func _eq(got: String, want: String, tag: String) -> void:
	assert_str(got).override_failure_message("%s: '%s' != '%s'" % [tag, got, want]).is_equal(want)


## §1 Attack (Q2), first match from config fields: Summon, Banish, Aura, Beam, Burst, Line,
## Blast, Single.
func test_attack_shape_follows_the_first_match_order() -> void:
	for id: String in _cfg.towers:
		for st: Array in _states(_def(id)):
			var s: TowerDef.Level = st[1]
			var want := "Single"
			if _e(s, "summon_max") > 0.0:
				want = "Summon"
			elif _e(s, "banish_cells") > 0.0:
				want = "Banish"
			elif s.damage <= 0.0:
				want = "Aura"
			elif _e(s, "sanity_scaling") > 0.0:
				want = "Beam"
			elif _e(s, "burst_targets") > 0.0:
				want = "Burst"
			elif _e(s, "pierce") > 0.0:
				want = "Line"
			elif _e(s, "aoe_radius") > 0.0:
				want = "Blast"
			_eq(TowerInfo.row_values(_def(id), s, _cfg)["attack"], want, "%s %s" % [id, st[0]])


# --- §1 DPS, Range, Hits ----------------------------------------------------------------------

## DPS: damage / interval x banish_targets (1 decimal); a circle summon_dps x summon_max
## and Damage "N/s"; a sanity-scaled level the range "lo–hi" (picker) from full sanity to 0.
func test_dps_formulas_for_every_tower_level_and_branch() -> void:
	var top := _cfg.sanity.max_sanity
	for id: String in _cfg.towers:
		for st: Array in _states(_def(id)):
			var s: TowerDef.Level = st[1]
			var v := TowerInfo.row_values(_def(id), s, _cfg)
			var tag := "%s %s" % [id, st[0]]
			var dps := _dps(s)
			if dps <= 0.0:
				continue
			var k := _e(s, "sanity_scaling")
			if k > 0.0:
				_eq(v["dps"], "%s–%s" % [_d1(dps), _d1(dps * (1.0 + k))], tag + " dps")
			else:
				_eq(v["dps"], _d1(dps), tag + " dps")
			if _e(s, "summon_max") > 0.0:
				_eq(v["damage"], "%s/s" % _n(_e(s, "summon_dps")), tag + " damage")
	# The circle's L2 keeps more than one unit, so its DPS is not the unit's.
	var c2 := _def("summoning_circle").levels[1]
	assert_float(_e(c2, "summon_max")).is_greater(1.0)
	_eq(TowerInfo.row_values(_def("summoning_circle"), c2, _cfg)["dps"],
		_d1(_e(c2, "summon_dps") * _e(c2, "summon_max")), "circle L2")
	# Live sanity (the panel, Q3): the value at that sanity, factor 1 + k (1 - s / max).
	var r1 := _def("resonator").levels[0]
	for sanity: float in [0.0, 37.0, 80.0, top]:
		var f := 1.0 + _e(r1, "sanity_scaling") * (1.0 - sanity / top)
		_eq(TowerInfo.row_values(_def("resonator"), r1, _cfg, sanity)["dps"],
			_d1(r1.damage / r1.fire_interval * f), "resonator at %s" % sanity)


func test_range_shows_the_dead_zone_and_hits_follow_targets_or_flying_units() -> void:
	for id: String in _cfg.towers:
		var def := _def(id)
		for st: Array in _states(def):
			var s: TowerDef.Level = st[1]
			var v := TowerInfo.row_values(def, s, _cfg)
			var tag := "%s %s" % [id, st[0]]
			_eq(v["range"], ("%s–%s" % [_n(s.min_range), _n(s.range_cells)]) if s.min_range > 0.0
				else _n(s.range_cells), tag + " range")
			var hits := "Ground" if def.targets == "ground" else "All"
			if _e(s, "summon_max") > 0.0:
				hits = "All" if _e(s, "summon_flying") > 0.0 else "Ground"
			_eq(v["hits"], hits, tag + " hits")
	assert_float(_def("coast_battery").levels[0].min_range).is_greater(0.0)


# --- §1 In beam, §5 lit ---------------------------------------------------------------------

## "+25%" = 1 / fire_interval_mult - 1 for a mundane shooter, "−30%" = power_mult - 1 for
## every occult tower (the circle included); a config edit changes it.
func test_beam_row_comes_from_the_beam_config_and_follows_an_edit() -> void:
	var b := _cfg.economy.beam
	var up := "+%s%%" % _n(roundf((1.0 / b.mundane_fire_interval_mult - 1.0) * 100.0))
	var down := MINUS + "%s%%" % _n(roundf((1.0 - b.occult_power_mult) * 100.0))
	for id: String in _cfg.towers:
		var def := _def(id)
		var s := def.levels[0]
		var want := DASH
		if def.kind == "occult":
			want = down
		elif s.damage > 0.0:
			want = up
		_eq(TowerInfo.row_values(def, s, _cfg)["beam"], want, id)
	b.occult_power_mult = 0.5
	b.mundane_fire_interval_mult = 0.5
	_eq(TowerInfo.row_values(_def("necronomicon_reader"), _def("necronomicon_reader").levels[0],
		_cfg)["beam"], MINUS + "50%", "edited occult")
	_eq(TowerInfo.row_values(_def("rifleman"), _def("rifleman").levels[0], _cfg)["beam"],
		"+100%", "edited mundane")


## §5: lit mundane Every x fire_interval_mult, DPS / it ("0.56*", "25*" at Rifleman L2).
func test_lit_mundane_shooter_every_and_dps_carry_the_mark() -> void:
	var m := _cfg.economy.beam.mundane_fire_interval_mult
	for id: String in _cfg.towers:
		var def := _def(id)
		if def.kind != "mundane":
			continue
		for st: Array in _states(def):
			var s: TowerDef.Level = st[1]
			var lit := TowerInfo.lit_values(def, s, _cfg)
			var tag := "%s %s" % [id, st[0]]
			if s.damage <= 0.0:
				assert_dict(lit).override_failure_message(tag).is_empty()
				continue
			assert_array(lit.keys()).override_failure_message(tag) \
				.contains_exactly_in_any_order(["every", "dps"])
			_eq(lit["every"], _n(s.fire_interval * m) + STAR, tag + " every")
			_eq(lit["dps"], _d1(_dps(s) / m) + STAR, tag + " dps")
	var r2 := _def("rifleman").levels[1]
	assert_str(TowerInfo.lit_values(_def("rifleman"), r2, _cfg)["every"]) \
		.is_equal(_n(r2.fire_interval * m) + STAR)


## §5: lit occult Damage and DPS x power_mult with "*"; an aura has neither; a circle's unit
## DPS and DPS (LT-53/S8: units summoned while lit bite at x power_mult); power_mult 1 -> {}.
func test_lit_occult_damage_and_dps_scale_by_power_mult() -> void:
	var pm := _cfg.economy.beam.occult_power_mult
	assert_float(pm).is_not_equal(1.0)
	for id: String in _cfg.towers:
		var def := _def(id)
		if def.kind != "occult":
			continue
		for st: Array in _states(def):
			var s: TowerDef.Level = st[1]
			var lit := TowerInfo.lit_values(def, s, _cfg, _cfg.sanity.max_sanity)
			var tag := "%s %s" % [id, st[0]]
			if _e(s, "summon_max") > 0.0:
				_eq(lit.get("damage", ""), _d1(_e(s, "summon_dps") * pm) + STAR, tag + " unit")
				_eq(lit.get("dps", ""), _d1(_dps(s) * pm) + STAR, tag + " dps")
			elif s.damage > 0.0:
				_eq(lit.get("damage", ""), _n(s.damage * pm) + STAR, tag + " damage")
				_eq(lit.get("dps", ""), _d1(_dps(s) * pm) + STAR, tag + " dps")
				assert_bool(lit.has("every")).override_failure_message(tag).is_false()
			else:
				assert_dict(lit).override_failure_message(tag).is_empty()
	var circle := _def("summoning_circle")
	_cfg.economy.beam.occult_power_mult = 1.0
	assert_dict(TowerInfo.lit_values(circle, circle.levels[1], _cfg)).is_empty()
	_cfg.economy.beam.occult_power_mult = 0.5
	_eq(TowerInfo.lit_values(circle, circle.levels[1], _cfg)["dps"],
		_d1(_dps(circle.levels[1]) * 0.5) + STAR, "circle at 0.5")


## A lit Resonator in the panel: its live DPS at that sanity x power_mult.
func test_lit_resonator_dps_is_the_live_value_times_power_mult() -> void:
	var def := _def("resonator")
	var s := def.levels[0]
	var pm := _cfg.economy.beam.occult_power_mult
	var top := _cfg.sanity.max_sanity
	var f := 1.0 + _e(s, "sanity_scaling") * (1.0 - 37.0 / top)
	_eq(TowerInfo.lit_values(def, s, _cfg, 37.0)["dps"], _d1(_dps(s) * f * pm) + STAR, "37")


## §5: an occult aura / gate / circle's effects while lit, as Simulation applies them;
## {} for a shooter and for every mundane tower.
func test_lit_effects_scale_the_aura_gate_and_circle_effects() -> void:
	var pm := _cfg.economy.beam.occult_power_mult
	var sign := _def("elder_sign")
	for st: Array in _states(sign):
		var s: TowerDef.Level = st[1]
		var fx := TowerInfo.lit_effects(sign, s, _cfg)
		assert_dict(fx).override_failure_message(st[0]).is_not_empty()
		for key: String in ["slow", "strip_armor"]:
			if s.effects.has(key):
				assert_float(fx[key]).is_equal_approx(_e(s, key) * pm, 1e-6)
		if s.effects.has("damage_taken_multiplier"):
			assert_float(fx["damage_taken_multiplier"]).is_equal_approx(
				1.0 + (_e(s, "damage_taken_multiplier") - 1.0) * pm, 1e-6)
	var key := _def("silver_key")
	var k1 := key.levels[0]
	var kfx := TowerInfo.lit_effects(key, k1, _cfg)
	assert_float(kfx["banish_cells"]).is_equal_approx(_e(k1, "banish_cells") * pm, 1e-6)
	assert_float(kfx["banish_max_hp"]).is_equal(_e(k1, "banish_max_hp"))
	var circle := _def("summoning_circle")
	var c2 := circle.levels[1]
	var cfx := TowerInfo.lit_effects(circle, c2, _cfg)
	assert_float(cfx["summon_dps"]).is_equal_approx(_e(c2, "summon_dps") * pm, 1e-6)
	for k: String in ["summon_hp", "summon_max", "summon_lifetime"]:
		assert_float(cfx[k]).is_equal(_e(c2, k))
	for id: String in ["necronomicon_reader", "resonator", "rifleman", "searchlight"]:
		assert_dict(TowerInfo.lit_effects(_def(id), _def(id).levels[0], _cfg)) \
			.override_failure_message(id).is_empty()


## §5 status line: mundane "fire +25%, no misses" (ignore_miss), occult "−30% power" (the
## circle too), "" for a mundane support tower.
func test_lit_line_per_kind() -> void:
	var b := _cfg.economy.beam
	var fire := "* In the beam now: fire +%s%%" % _n(roundf((1.0 / b.mundane_fire_interval_mult
		- 1.0) * 100.0))
	var power := "* In the beam now: %s%s%% power" % [MINUS, _n(roundf((1.0 - b.occult_power_mult)
		* 100.0))]
	assert_bool(b.mundane_ignore_miss).is_true()
	_eq(TowerInfo.lit_line(_def("rifleman"), _def("rifleman").levels[0], _cfg),
		fire + ", no misses", "rifleman")
	for id: String in ["necronomicon_reader", "elder_sign", "summoning_circle", "silver_key"]:
		_eq(TowerInfo.lit_line(_def(id), _def(id).levels[0], _cfg), power, id)
	_eq(TowerInfo.lit_line(_def("searchlight"), _def("searchlight").levels[0], _cfg), "",
		"searchlight")
	b.mundane_ignore_miss = false
	_eq(TowerInfo.lit_line(_def("rifleman"), _def("rifleman").levels[0], _cfg), fire, "no ignore")
	# The kind line of a lit mundane shooter (§5).
	assert_array(Array(TowerInfo.kind_lines(_def("rifleman"), _def("rifleman").levels[0],
		_cfg.sanity, true))).is_equal([TowerInfo.NO_MISSES_LIT])


# --- §1 Special, §3 upgrade path ------------------------------------------------------------

func test_special_cell_says_what_no_row_says() -> void:
	var dyn := _def("dynamite_crew").levels[0]
	_eq(TowerInfo.row_values(_def("dynamite_crew"), dyn, _cfg)["special"],
		"r %s, fuse %s s" % [_n(_e(dyn, "aoe_radius")), _n(_e(dyn, "fuse_seconds"))], "dynamite")
	var sign := _def("elder_sign").levels[0]
	_eq(TowerInfo.special_short(sign), "Slow %s%%, +%s%% taken" % [_n(_e(sign, "slow") * 100.0),
		_n((_e(sign, "damage_taken_multiplier") - 1.0) * 100.0)], "elder sign")
	var res := _def("resonator").levels[0]
	_eq(TowerInfo.special_short(res), "No armor, ×%s at 0 sanity" % _n(1.0
		+ _e(res, "sanity_scaling")), "resonator")
	var key := _def("silver_key").levels[0]
	_eq(TowerInfo.special_short(key), "Back %s cells, ≤%s HP" % [_n(_e(key, "banish_cells")),
		_n(_e(key, "banish_max_hp"))], "silver key")
	var c1 := _def("summoning_circle").levels[0]
	assert_float(_e(c1, "summon_max")).is_equal(1.0)
	_eq(TowerInfo.special_short(c1), "1 unit, %s HP" % _n(_e(c1, "summon_hp")), "circle L1")
	_eq(TowerInfo.special_short(_def("rifleman").levels[0]), DASH, "rifleman")
	# A row already says pierce (Line): the Harpooner L1 has nothing else.
	assert_dict(_def("harpooner").levels[0].effects).is_equal({"pierce": 1.0})
	_eq(TowerInfo.special_short(_def("harpooner").levels[0]), DASH, "harpooner")


func test_upgrade_path_names_the_l2_price_and_both_branches() -> void:
	for id: String in _cfg.towers:
		var def := _def(id)
		_eq(TowerInfo.upgrade_path_text(def), "L2 $%d · then A %s or B %s" % [
			def.levels[1].upgrade_cost, def.branches["a"].name, def.branches["b"].name], id)
