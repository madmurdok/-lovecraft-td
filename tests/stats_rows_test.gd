class_name StatsRowsTest
extends GdUnitTestSuite
## LT-53 (LT-43 §1, §5, Q3, Q4): the unified table's cells as TowerText builds them. Every
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
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_cfg = r.config


func _n(v: float) -> String:
	return TowerText.num(v)


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


## LT-89: the cooldown the sim sets for `interval_s` seconds: whole ticks (the interval x
## TICK_RATE rounded, at least 1).
func _ticks(interval_s: float) -> int:
	return maxi(1, roundi(interval_s * SimTime.TICK_RATE))


## LT-89: the Every cell for `interval_s`: its whole ticks in seconds.
func _every(interval_s: float) -> String:
	return TowerText.every_text(_ticks(interval_s) / float(SimTime.TICK_RATE))


## LT-89: a mundane fire-rate percent at multiplier `m`: base ticks / ticks at m - 1.
func _rate(interval_s: float, m: float) -> float:
	return (float(_ticks(interval_s)) / _ticks(interval_s * m) - 1.0) * 100.0


## LT-89: a shooter's DPS at fire interval multiplier `m` as the sim deals it.
func _ticked_dps(s: TowerDef.Level, m: float) -> float:
	return s.damage / (_ticks(s.fire_interval * m) / float(SimTime.TICK_RATE))


# --- §1: the row set ------------------------------------------------------------------------

func test_rows_are_the_ten_rows_of_the_note_in_order() -> void:
	var keys := []
	var labels := []
	for row: Array in TowerText.ROWS:
		keys.append(row[0])
		labels.append(row[1])
	assert_array(labels).is_equal(["Attack", "Damage", "Every, s", "DPS", "Range", "Hits",
		"Sanity/kill", "Reserve", "In light", "In shadow", "Special"])
	for id: String in _cfg.towers:
		for st: Array in _states(_def(id)):
			var v := TowerText.row_values(_def(id), st[1], _cfg)
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
			var v := TowerText.row_values(def, s, _cfg)
			var summon := _e(s, "summon_max") > 0.0
			var acts := s.damage > 0.0 or _e(s, "banish_cells") > 0.0 or summon
			if s.damage <= 0.0 and not summon:
				_eq(v["damage"], DASH, tag + " damage")
			else:
				assert_str(v["damage"]).override_failure_message(tag).is_not_equal(DASH)
			_eq(v["every"], _every(s.fire_interval) if acts else DASH, tag + " every")
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
		var v := TowerText.row_values(_def(id), _def(id).levels[0], _cfg)
		assert_array([v["damage"], v["every"], v["dps"]]).is_equal([DASH, DASH, DASH])
	assert_str(TowerText.row_values(_def("searchlight"), _def("searchlight").levels[0], _cfg)
		["beam"]).is_equal(DASH)
	var key := TowerText.row_values(_def("silver_key"), _def("silver_key").levels[0], _cfg)
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
			_eq(TowerText.row_values(_def(id), s, _cfg)["attack"], want, "%s %s" % [id, st[0]])


# --- §1 DPS, Range, Hits ----------------------------------------------------------------------

## DPS: damage / interval x banish_targets (1 decimal); a circle summon_dps x summon_max
## and Damage "N/s"; a sanity-scaled level the range "lo–hi" (picker) from full sanity to 0.
func test_dps_formulas_for_every_tower_level_and_branch() -> void:
	var top := _cfg.sanity.max_sanity
	for id: String in _cfg.towers:
		for st: Array in _states(_def(id)):
			var s: TowerDef.Level = st[1]
			var v := TowerText.row_values(_def(id), s, _cfg)
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
	_eq(TowerText.row_values(_def("summoning_circle"), c2, _cfg)["dps"],
		_d1(_e(c2, "summon_dps") * _e(c2, "summon_max")), "circle L2")
	# Live sanity (the panel, Q3): the value at that sanity, factor 1 + k (1 - s / max).
	var r1 := _def("resonator").levels[0]
	for sanity: float in [0.0, 37.0, 80.0, top]:
		var f := 1.0 + _e(r1, "sanity_scaling") * (1.0 - sanity / top)
		_eq(TowerText.row_values(_def("resonator"), r1, _cfg, sanity)["dps"],
			_d1(r1.damage / r1.fire_interval * f), "resonator at %s" % sanity)


func test_range_shows_the_dead_zone_and_hits_follow_targets_or_flying_units() -> void:
	for id: String in _cfg.towers:
		var def := _def(id)
		for st: Array in _states(def):
			var s: TowerDef.Level = st[1]
			var v := TowerText.row_values(def, s, _cfg)
			var tag := "%s %s" % [id, st[0]]
			_eq(v["range"], ("%s–%s" % [_n(s.min_range), _n(s.range_cells)]) if s.min_range > 0.0
				else _n(s.range_cells), tag + " range")
			var hits := "Ground" if def.targets == "ground" else "All"
			if _e(s, "summon_max") > 0.0:
				hits = "All" if _e(s, "summon_flying") > 0.0 else "Ground"
			_eq(v["hits"], hits, tag + " hits")
	assert_float(_def("coast_battery").levels[0].min_range).is_greater(0.0)


# --- §1 In beam, §5 lit ---------------------------------------------------------------------

## "+25%" = base ticks / ticks at fire_interval_mult - 1 for a mundane shooter (LT-89),
## "−30%" = power_mult - 1 for every occult tower (the circle included); a config edit
## changes it.
func test_beam_row_comes_from_the_beam_config_and_follows_an_edit() -> void:
	var b := _cfg.economy.beam
	var down := MINUS + "%s%%" % _n(roundf((1.0 - b.occult_power_mult) * 100.0))
	for id: String in _cfg.towers:
		var def := _def(id)
		var s := def.levels[0]
		var want := DASH
		if def.kind == "occult":
			want = down
		elif s.damage > 0.0:
			want = "+%s%%" % _n(roundf(_rate(s.fire_interval, b.mundane_fire_interval_mult)))
		_eq(TowerText.row_values(def, s, _cfg)["beam"], want, id)
	b.occult_power_mult = 0.5
	b.mundane_fire_interval_mult = 0.5
	_eq(TowerText.row_values(_def("necronomicon_reader"), _def("necronomicon_reader").levels[0],
		_cfg)["beam"], MINUS + "50%", "edited occult")
	_eq(TowerText.row_values(_def("rifleman"), _def("rifleman").levels[0], _cfg)["beam"],
		"+100%", "edited mundane")


## §5: lit mundane Every and DPS at fire_interval_mult over its whole ticks (LT-89: 0.56 s
## fires every 17 ticks, "0.5666*" and "24.7*" at Rifleman L2).
func test_lit_mundane_shooter_every_and_dps_carry_the_mark() -> void:
	var m := _cfg.economy.beam.mundane_fire_interval_mult
	for id: String in _cfg.towers:
		var def := _def(id)
		if def.kind != "mundane":
			continue
		for st: Array in _states(def):
			var s: TowerDef.Level = st[1]
			var lit := TowerText.lit_values(def, s, _cfg)
			var tag := "%s %s" % [id, st[0]]
			if s.damage <= 0.0:
				assert_dict(lit).override_failure_message(tag).is_empty()
				continue
			assert_array(lit.keys()).override_failure_message(tag) \
				.contains_exactly_in_any_order(["every", "dps"])
			_eq(lit["every"], _every(s.fire_interval * m) + STAR, tag + " every")
			_eq(lit["dps"], _d1(_ticked_dps(s, m)) + STAR, tag + " dps")
	var r2 := _def("rifleman").levels[1]
	assert_str(TowerText.lit_values(_def("rifleman"), r2, _cfg)["every"]) \
		.is_equal(_every(r2.fire_interval * m) + STAR)


## LT-89: a table cell's number without the "*" mark.
func _cell_float(text: String, tag: String) -> float:
	var t := text.trim_suffix(STAR)
	assert_bool(t.is_valid_float()).override_failure_message("%s: '%s'" % [tag, text]).is_true()
	return t.to_float()


## LT-89 (owner: "4 знака, отбрасывание"): for every shooter cell (tower x level x branch,
## neutral, lit and shadowed; a gate and a circle excluded: their DPS counts targets / units)
## the shown Damage / the shown Every rounds (one decimal) to the shown DPS, because Every is
## cut, not rounded (Rifleman L3b shadowed: 7 / 0.2666 -> 26.3, the exact 26.25 tie).
func test_damage_over_every_rounds_to_the_dps_cell_for_every_shooter_cell() -> void:
	var full := _cfg.sanity.max_sanity  # a Resonator's DPS cell is one number at a given sanity
	var checked := 0
	for id: String in _cfg.towers:
		var def := _def(id)
		for st: Array in _states(def):
			var s: TowerDef.Level = st[1]
			if s.damage <= 0.0 or s.is_banish() or s.is_summon():
				continue
			var row := TowerText.row_values(def, s, _cfg, full)
			for arm: Array in [["neutral", {}], ["lit", TowerText.lit_values(def, s, _cfg, full)],
					["shadow", TowerText.lit_values(def, s, _cfg, full, true)]]:
				var tag := "%s %s %s" % [id, st[0], arm[0]]
				var v: Dictionary = row.merged(arm[1], true)
				var damage := _cell_float(v["damage"], tag + " damage")
				var every := _cell_float(v["every"], tag + " every")
				var dps := v["dps"].trim_suffix(STAR) as String
				_eq(_d1(damage / every), dps, "%s: %s / %s" % [tag, v["damage"], v["every"]])
				# Every has at most 4 decimals.
				assert_float(every * 10000.0).override_failure_message(tag) \
					.is_equal_approx(roundf(every * 10000.0), 1e-6)
				checked += 1
	assert_int(checked).is_greater(40)


## LT-89: Every is the sim's period cut (not rounded) to 4 decimals, trailing zeros dropped.
func test_every_text_cuts_the_period_to_four_decimals() -> void:
	var rate := float(SimTime.TICK_RATE)
	_eq(TowerText.every_text(17 / rate), "0.5666", "17 ticks")
	_eq(TowerText.every_text(5 / rate), "0.1666", "5 ticks")
	_eq(TowerText.every_text(8 / rate), "0.2666", "8 ticks")
	_eq(TowerText.every_text(20 / rate), "0.6666", "20 ticks, not 0.6667")
	_eq(TowerText.every_text(19 / rate), "0.6333", "19 ticks")
	_eq(TowerText.every_text(1 / rate), "0.0333", "1 tick")
	_eq(TowerText.every_text(24 / rate), "0.8", "24 ticks")
	_eq(TowerText.every_text(90 / rate), "3", "90 ticks")
	# Live data (LT-89 owner example): a lit 0.7 s Rifleman L2 fires every 17 ticks.
	var rifle := _def("rifleman")
	_eq(TowerText.lit_values(rifle, rifle.levels[1], _cfg)["every"], "0.5666" + STAR, "rifle L2 lit")
	_eq(TowerText.row_values(rifle, rifle.levels[1], _cfg)["every"], "0.7", "rifle L2")


## LT-89: the In light / In shadow fire-rate percent is base ticks / ticks at the multiplier
## - 1 (Rifleman L3b, 0.2 s = 6 ticks: lit 5 ticks +20%, shadowed 8 ticks −25%; the decimal
## 1 / 0.8 - 1 would read +25% and 1 / 1.25 - 1 −20%), in the rows and the status lines.
func test_rifleman_l3b_fire_rate_percent_comes_from_ticks() -> void:
	var rifle := _def("rifleman")
	var b := rifle.branches["b"]
	var v := TowerText.row_values(rifle, b, _cfg)
	_eq(v["beam"], "+20%", "In light")
	_eq(v["shadow"], MINUS + "25%", "In shadow")
	assert_str(TowerText.lit_line(rifle, b, _cfg)).contains("fire +20%")
	assert_str(TowerText.lit_line(rifle, b, _cfg, true)).contains("fire %s25%%" % MINUS)


## LT-89 / LT-105 Q4: an interval_mult on a gate's or a circle's channel changes neither its
## Every nor its DPS (the cast / summon cooldown ignores it); a shooter's does change.
func test_an_interval_mult_modifier_leaves_gate_and_circle_every_and_dps() -> void:
	for id: String in ["silver_key", "summoning_circle"]:
		var def := _def(id)
		for st: Array in _states(def):
			var s: TowerDef.Level = st[1]
			for m: float in [0.5, 2.0]:
				var tag := "%s %s x%s" % [id, st[0], m]
				var fx := {"power_mult": 1.0, "interval_mult": m, "miss_add": 0.0,
					"ignore_miss": false, "disabled": false}
				var got := TowerStatsModel.lit_numbers(def, s, _cfg, -1.0, false, fx)
				assert_bool(got.has("every") or got.has("dps")).override_failure_message(tag) \
					.is_false()
				var now := TowerRules.effective_with(s, _cfg, fx)
				var plain := TowerRules.effective(def, s, _cfg)
				assert_float(now["interval"]).override_failure_message(tag) \
					.is_equal(plain["interval"])
				assert_float(now["dps"]).override_failure_message(tag).is_equal(plain["dps"])
				_eq(TowerText.row_values(def, s, _cfg)["every"], _n(s.fire_interval), tag + " every")
	var rifle := _def("rifleman")
	var fx2 := {"power_mult": 1.0, "interval_mult": 2.0, "miss_add": 0.0, "ignore_miss": false,
		"disabled": false}
	assert_bool(TowerStatsModel.lit_numbers(rifle, rifle.levels[0], _cfg, -1.0, false, fx2) \
		.has("every")).is_true()


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
			var lit := TowerText.lit_values(def, s, _cfg, _cfg.sanity.max_sanity)
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
	assert_dict(TowerText.lit_values(circle, circle.levels[1], _cfg)).is_empty()
	_cfg.economy.beam.occult_power_mult = 0.5
	_eq(TowerText.lit_values(circle, circle.levels[1], _cfg)["dps"],
		_d1(_dps(circle.levels[1]) * 0.5) + STAR, "circle at 0.5")


## A lit Resonator in the panel: its live DPS at that sanity x power_mult.
func test_lit_resonator_dps_is_the_live_value_times_power_mult() -> void:
	var def := _def("resonator")
	var s := def.levels[0]
	var pm := _cfg.economy.beam.occult_power_mult
	var top := _cfg.sanity.max_sanity
	var f := 1.0 + _e(s, "sanity_scaling") * (1.0 - 37.0 / top)
	_eq(TowerText.lit_values(def, s, _cfg, 37.0)["dps"], _d1(_dps(s) * f * pm) + STAR, "37")


## §5: an occult aura / gate / circle's effects while lit, as Simulation applies them;
## {} for a shooter and for every mundane tower.
func test_lit_effects_scale_the_aura_gate_and_circle_effects() -> void:
	var pm := _cfg.economy.beam.occult_power_mult
	var sign := _def("elder_sign")
	for st: Array in _states(sign):
		var s: TowerDef.Level = st[1]
		var fx := TowerStatsModel.lit_effects(sign, s, _cfg)
		assert_dict(fx).override_failure_message(st[0]).is_not_empty()
		for key: String in ["slow", "strip_armor"]:
			if s.effects.has(key):
				assert_float(fx[key]).is_equal_approx(_e(s, key) * pm, 1e-6)
		if s.effects.has("damage_taken_multiplier"):
			assert_float(fx["damage_taken_multiplier"]).is_equal_approx(
				1.0 + (_e(s, "damage_taken_multiplier") - 1.0) * pm, 1e-6)
	var key := _def("silver_key")
	var k1 := key.levels[0]
	var kfx := TowerStatsModel.lit_effects(key, k1, _cfg)
	assert_float(kfx["banish_cells"]).is_equal_approx(_e(k1, "banish_cells") * pm, 1e-6)
	assert_float(kfx["banish_max_hp"]).is_equal(_e(k1, "banish_max_hp"))
	var circle := _def("summoning_circle")
	var c2 := circle.levels[1]
	var cfx := TowerStatsModel.lit_effects(circle, c2, _cfg)
	assert_float(cfx["summon_dps"]).is_equal_approx(_e(c2, "summon_dps") * pm, 1e-6)
	for k: String in ["summon_hp", "summon_max", "summon_lifetime"]:
		assert_float(cfx[k]).is_equal(_e(c2, k))
	for id: String in ["necronomicon_reader", "resonator", "rifleman", "searchlight"]:
		assert_dict(TowerStatsModel.lit_effects(_def(id), _def(id).levels[0], _cfg)) \
			.override_failure_message(id).is_empty()


## §5 status line: mundane "fire +25%, no misses" (ignore_miss), occult "−30% power" (the
## circle too), "" for a mundane support tower.
func test_lit_line_per_kind() -> void:
	var b := _cfg.economy.beam
	var fire := "* In the beam now: fire +%s%%" % _n(roundf(_rate(
		_def("rifleman").levels[0].fire_interval, b.mundane_fire_interval_mult)))
	var power := "* In the beam now: %s%s%% power" % [MINUS, _n(roundf((1.0 - b.occult_power_mult)
		* 100.0))]
	assert_bool(b.mundane_ignore_miss).is_true()
	_eq(TowerText.lit_line(_def("rifleman"), _def("rifleman").levels[0], _cfg),
		fire + ", no misses", "rifleman")
	for id: String in ["necronomicon_reader", "elder_sign", "summoning_circle", "silver_key"]:
		_eq(TowerText.lit_line(_def(id), _def(id).levels[0], _cfg), power, id)
	_eq(TowerText.lit_line(_def("searchlight"), _def("searchlight").levels[0], _cfg), "",
		"searchlight")
	b.mundane_ignore_miss = false
	_eq(TowerText.lit_line(_def("rifleman"), _def("rifleman").levels[0], _cfg), fire, "no ignore")
	# The kind line of a lit mundane shooter (§5).
	assert_array(Array(TowerText.kind_lines(_def("rifleman"), _def("rifleman").levels[0],
		_cfg.sanity, true))).is_equal([TowerText.NO_MISSES_LIT])


# --- §1 Special, §3 upgrade path ------------------------------------------------------------

func test_special_cell_says_what_no_row_says() -> void:
	var dyn := _def("dynamite_crew").levels[0]
	_eq(TowerText.row_values(_def("dynamite_crew"), dyn, _cfg)["special"],
		"r %s, fuse %s s" % [_n(_e(dyn, "aoe_radius")), _n(_e(dyn, "fuse_seconds"))], "dynamite")
	var sign := _def("elder_sign").levels[0]
	_eq(TowerText.special_short(sign), "Slow %s%%, +%s%% taken, shadows" % [_n(_e(sign, "slow") * 100.0),
		_n((_e(sign, "damage_taken_multiplier") - 1.0) * 100.0)], "elder sign")
	var res := _def("resonator").levels[0]
	_eq(TowerText.special_short(res), "No armor, ×%s at 0 sanity" % _n(1.0
		+ _e(res, "sanity_scaling")), "resonator")
	var key := _def("silver_key").levels[0]
	_eq(TowerText.special_short(key), "Back %s cells, ≤%s HP" % [_n(_e(key, "banish_cells")),
		_n(_e(key, "banish_max_hp"))], "silver key")
	var c1 := _def("summoning_circle").levels[0]
	assert_float(_e(c1, "summon_max")).is_equal(1.0)
	_eq(TowerText.special_short(c1), "1 unit, %s HP" % _n(_e(c1, "summon_hp")), "circle L1")
	_eq(TowerText.special_short(_def("rifleman").levels[0]), DASH, "rifleman")
	# A row already says pierce (Line): the Harpooner L1 has nothing else.
	assert_dict(_def("harpooner").levels[0].effects).is_equal({"pierce": 1.0})
	_eq(TowerText.special_short(_def("harpooner").levels[0]), DASH, "harpooner")


func test_upgrade_path_names_the_l2_price_and_both_branches() -> void:
	for id: String in _cfg.towers:
		var def := _def(id)
		_eq(TowerText.upgrade_path_text(def), "L2 $%d · then A %s or B %s" % [
			def.levels[1].upgrade_cost, def.branches["a"].name, def.branches["b"].name], id)


# --- LT-70 §5: the "In shadow" row and the shadowed state ----------------------------------

func test_the_shadow_row_reads_the_shadow_block() -> void:
	var sh := _cfg.economy.shadow
	var rifle := _def("rifleman")
	var fire := "%s%s%%" % [MINUS, _n(roundf(absf(_rate(rifle.levels[0].fire_interval,
		sh.mundane_fire_interval_mult))))]
	var power := "+%s%%" % _n(roundf((sh.occult_power_mult - 1.0) * 100.0))
	assert_str(TowerText.row_values(rifle, rifle.levels[0], _cfg)["shadow"]).is_equal(fire)
	var necro := _def("necronomicon_reader")
	assert_str(TowerText.row_values(necro, necro.levels[0], _cfg)["shadow"]).is_equal(power)
	var sl := _def("searchlight")
	assert_str(TowerText.row_values(sl, sl.levels[0], _cfg)["shadow"]).is_equal(DASH)
	# Follows a config edit; the row is a dash with no shadow block.
	sh.occult_power_mult = 2.0
	assert_str(TowerText.row_values(necro, necro.levels[0], _cfg)["shadow"]).is_equal("+100%")
	_cfg.economy.shadow = null
	assert_str(TowerText.row_values(necro, necro.levels[0], _cfg)["shadow"]).is_equal(DASH)
	assert_str(TowerText.row_values(rifle, rifle.levels[0], _cfg)["shadow"]).is_equal(DASH)


func test_shadowed_values_use_the_shadow_multipliers_with_the_mark() -> void:
	var sh := _cfg.economy.shadow
	var rifle := _def("rifleman")
	var s := rifle.levels[0]
	var v := TowerText.lit_values(rifle, s, _cfg, -1.0, true)
	_eq(v["every"], _every(s.fire_interval * sh.mundane_fire_interval_mult) + STAR, "every")
	_eq(v["dps"], _d1(_ticked_dps(s, sh.mundane_fire_interval_mult)) + STAR, "dps")
	var necro := _def("necronomicon_reader")
	var n := necro.levels[0]
	var nv := TowerText.lit_values(necro, n, _cfg, _cfg.sanity.max_sanity, true)
	_eq(nv["damage"], _n(n.damage * sh.occult_power_mult) + STAR, "damage")
	_eq(nv["dps"], _d1(_dps(n) * sh.occult_power_mult) + STAR, "dps")
	var circle := _def("summoning_circle")
	var c := circle.levels[1]
	_eq(TowerText.lit_values(circle, c, _cfg, -1.0, true)["damage"],
		_d1(_e(c, "summon_dps") * sh.occult_power_mult) + STAR, "unit dps")
	assert_dict(TowerText.lit_values(_def("searchlight"), _def("searchlight").levels[0], _cfg,
		-1.0, true)).is_empty()


func test_shadowed_effects_and_status_line_per_kind() -> void:
	var sh := _cfg.economy.shadow
	var sign := _def("elder_sign")
	var s := sign.levels[0]
	var fx := TowerStatsModel.lit_effects(sign, s, _cfg, true)
	assert_float(fx["slow"]).is_equal_approx(_e(s, "slow") * sh.occult_power_mult, 1e-6)
	assert_float(fx["damage_taken_multiplier"]).is_equal_approx(
		1.0 + (_e(s, "damage_taken_multiplier") - 1.0) * sh.occult_power_mult, 1e-6)
	var rifle := _def("rifleman")
	assert_dict(TowerStatsModel.lit_effects(rifle, rifle.levels[0], _cfg, true)).is_empty()
	var fire := "* In shadow now: fire %s%s%%, +%s%% misses" % [MINUS,
		_n(roundf((1.0 - 1.0 / sh.mundane_fire_interval_mult) * 100.0)),
		_n(sh.mundane_miss_chance_add * 100.0)]
	_eq(TowerText.lit_line(rifle, rifle.levels[0], _cfg, true), fire, "rifle")
	_eq(TowerText.lit_line(sign, s, _cfg, true), "* In shadow now: +%s%% power"
		% _n(roundf((sh.occult_power_mult - 1.0) * 100.0)), "sign")
	_eq(TowerText.lit_line(_def("searchlight"), _def("searchlight").levels[0], _cfg, true), "",
		"searchlight")


func test_kind_lines_add_the_shadow_miss_line_for_a_shooter_only() -> void:
	var rifle := _def("rifleman")
	var lines := Array(TowerText.kind_lines(rifle, rifle.levels[0], _cfg.sanity, false, 0.1))
	assert_array(lines).contains(["+10% misses in shadow"])
	assert_array(Array(TowerText.kind_lines(rifle, rifle.levels[0], _cfg.sanity, false, 0.0))) \
		.not_contains(["+10% misses in shadow"])
	for id: String in ["necronomicon_reader", "searchlight"]:
		var d := _def(id)
		assert_array(Array(TowerText.kind_lines(d, d.levels[0], _cfg.sanity, false, 0.1))) \
			.not_contains(["+10% misses in shadow"])


func test_effect_lines_and_special_short_name_the_casters() -> void:
	var sl := _def("searchlight")
	var sign := _def("elder_sign")
	assert_array(Array(TowerText.effect_lines(sl.levels[0].effects))) \
		.contains(["Lights towers and foes"])
	assert_array(Array(TowerText.effect_lines(sign.levels[0].effects))) \
		.contains(["Shadows towers at night"])
	assert_str(TowerText.special_short(sl.levels[0])).contains("lights")
	assert_str(TowerText.special_short(sign.levels[0])).contains("shadows")
