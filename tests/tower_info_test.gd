class_name TowerInfoTest
extends GdUnitTestSuite
## LT-24 §3, LT-43 TowerInfo: the stats table cells (row_values) and the special, kind and
## upgrade lines built from config (effects in EFFECT_GROUPS order), "(coming soon)" for
## PENDING keys (none since LT-29: every shipped effect is wired), number and cost formatting. Text formats come from the design note; the
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


func _row(id: String, s: TowerDef.Level, sanity_now := -1.0) -> Dictionary:
	return TowerInfo.row_values(_def(id), s, _cfg, sanity_now)


func _special(s: TowerDef.Level) -> Array:
	return Array(TowerInfo.special_lines(s))


func _mundane_kind() -> Array:
	return ["May miss while Fraying (%s%%)" % _n(_cfg.sanity.thresholds["fraying"].miss_chance * 100.0)]


## The shooter cells of `s` (LT-43 §1): damage, interval, DPS (one decimal), range.
func _attack(s: TowerDef.Level) -> Dictionary:
	return {"damage": _n(s.damage), "every": _n(s.fire_interval),
		"dps": TowerInfo.one_decimal(s.damage / s.fire_interval), "range": _n(s.range_cells)}


func _assert_cells(got: Dictionary, want: Dictionary) -> void:
	for k: String in want:
		assert_str(got[k]).override_failure_message("%s: %s != %s" % [k, got[k], want[k]]) \
			.is_equal(want[k])


# --- 15: lines from config ------------------------------------------------------------------

func test_rifleman_l1_reads_damage_range_then_mundane_kind_lines() -> void:
	var l1 := _def("rifleman").levels[0]
	var got := _row("rifleman", l1)
	_assert_cells(got, _attack(l1))
	_assert_cells(got, {"attack": "Single", "hits": "All", "reserve": TowerInfo.CELL_DASH,
		"kill": "+" + _n(_cfg.sanity.regen_mundane_kill), "special": TowerInfo.CELL_DASH})
	assert_array(Array(TowerInfo.kind_lines(_def("rifleman"), l1, _cfg.sanity))) \
		.is_equal(_mundane_kind())
	# Spec example at today's config.
	if is_equal_approx(l1.damage, 10.0) and is_equal_approx(l1.fire_interval, 0.8):
		_assert_cells(got, {"damage": "10", "every": "0.8", "dps": "12.5"})


func test_harpooner_shows_the_line_shot_barbed_bleed_and_the_chain_pull() -> void:
	var h := _def("harpooner")
	var l1 := h.levels[0]
	# LT-43 §1: the pierce is the Attack row "Line", not a special line.
	_assert_cells(_row("harpooner", l1), _attack(l1))
	assert_str(_row("harpooner", l1)["attack"]).is_equal("Line")
	assert_array(_special(l1)).is_empty()
	var b := h.branches["a"]
	var bleed := "Bleed %s/s for %s s" % [_n(b.effects["bleed_dps"]), _n(b.effects["bleed_seconds"])]
	assert_array(_special(b)).is_equal([bleed])
	var c := h.branches["b"]
	var e: Dictionary = c.effects
	assert_array(_special(c)).contains(["Pull %sc, ≤%s HP, %ss" % [
		_n(e["pull_cells"]), _n(e["pull_max_hp"]), _n(e["pull_immune_seconds"])]])
	# LT-29 S3 spec example at today's config.
	if e["pull_cells"] == 1.5 and e["pull_max_hp"] == 500.0 and e["pull_immune_seconds"] == 3.0:
		assert_array(_special(c)).contains(["Pull 1.5c, ≤500 HP, 3s"])


## LT-47: a ground-only tower says it cannot hit flyers right after its range; the fuse
## line follows the blast radius (EFFECT_GROUPS order).
func test_dynamite_shows_ground_only_the_blast_and_the_fuse() -> void:
	var d := _def("dynamite_crew")
	var l1 := d.levels[0]
	var e: Dictionary = l1.effects
	_assert_cells(_row("dynamite_crew", l1), {"attack": "Blast", "hits": "Ground"})
	assert_array(_special(l1)).is_equal(["Blast radius " + TowerInfo.cells_text(_n(e["aoe_radius"])),
		"Fuse %s s, thrown ahead" % _n(e["fuse_seconds"])])
	# Spec example at today's config.
	if e["fuse_seconds"] == 1.0:
		assert_array(_special(l1)).contains(["Fuse 1 s, thrown ahead"])
	for id: String in ["rifleman", "harpooner", "necronomicon_reader"]:
		assert_str(_row(id, _def(id).levels[0])["hits"]).is_equal("All")


func test_elder_sign_is_support_with_aura_and_effects_and_no_kind_line() -> void:
	var l1 := _def("elder_sign").levels[0]
	var dash := TowerInfo.CELL_DASH
	_assert_cells(_row("elder_sign", l1), {"attack": "Aura", "damage": dash, "every": dash,
		"dps": dash, "range": _n(l1.range_cells), "reserve": _n(l1.sanity_reserve),
		"kill": dash})
	assert_array(_special(l1)).is_equal([
		"Slows enemies %s%%" % _n(l1.effects["slow"] * 100.0),
		"Foes take +%s%% damage" % _n((l1.effects["damage_taken_multiplier"] - 1.0) * 100.0),
	])
	assert_array(Array(TowerInfo.kind_lines(_def("elder_sign"), l1, _cfg.sanity))).is_empty()


## LT-23: the Seal's drain line became its reserve line; LT-29 wired the strip (no suffix).
func test_corrupted_seal_shows_its_reserve_and_armor_strip() -> void:
	var seal := _def("elder_sign").branches["b"]
	assert_str(_row("elder_sign", seal)["reserve"]).is_equal(_n(seal.sanity_reserve))
	var got := _special(seal)
	assert_bool(got.any(func(x: String) -> bool: return x.contains("sanity/s"))).is_false()
	# The strip is the last effect group.
	assert_str(got[got.size() - 1]).is_equal(
		"Foes lose %s armor" % _n(seal.effects["strip_armor"]))


func test_necronomicon_lines_and_the_madness_kind_line() -> void:
	var n := _def("necronomicon_reader")
	var l1 := n.levels[0]
	_assert_cells(_row("necronomicon_reader", l1), _attack(l1))
	_assert_cells(_row("necronomicon_reader", l1), {"attack": "Blast",
		"reserve": _n(l1.sanity_reserve), "kill": TowerInfo.CELL_DASH})
	assert_array(_special(l1)).is_equal(["Blast radius " + TowerInfo.cells_text(_n(l1.effects["aoe_radius"]))])
	assert_array(Array(TowerInfo.kind_lines(n, l1, _cfg.sanity))).is_equal([
		"Madness: x%s, astray" % _n(_cfg.sanity.madness.damage_multiplier)])
	var got := Array(TowerInfo.kind_lines(n, n.branches["a"], _cfg.sanity))
	assert_array(got).is_equal(["Unaffected by madness"])


## LT-29: Gangsters (burst_targets) replaced Militia (shooters); DPS stays damage over
## interval (the burst spreads it, crits do not count).
func test_dps_is_damage_over_interval_only_for_gangsters_and_marksman() -> void:
	var m := _def("rifleman").branches["b"]
	var got := _row("rifleman", m)
	assert_str(got["dps"]).is_equal(_attack(m)["dps"])
	assert_str(got["attack"]).is_equal("Burst")
	if is_equal_approx(m.damage, 7.0) and is_equal_approx(m.fire_interval, 0.2):
		assert_str(got["dps"]).is_equal("35")
	assert_array(_special(m)).contains(["Spreads fire over %s foes" % _n(m.effects["burst_targets"])])
	if m.effects["burst_targets"] == 3.0:
		assert_array(_special(m)).contains(["Spreads fire over 3 foes"])
	assert_bool(m.effects.has("shooters")).is_false()
	var mk := _def("rifleman").branches["a"]
	assert_str(_row("rifleman", mk)["dps"]).is_equal(_attack(mk)["dps"])
	assert_array(_special(mk)).contains(["%s%% crit, x%s damage" % [
		_n(mk.effects["crit_chance"] * 100.0), _n(mk.effects["crit_multiplier"])]])


func test_a_config_edit_changes_the_text() -> void:
	var r := GameConfig.load_from_dir("res://data")
	var def: TowerDef = r.config.towers["rifleman"]
	var l := def.levels[0]
	l.damage = 33.0
	l.fire_interval = 1.5
	l.range_cells = 4.25
	_assert_cells(TowerInfo.row_values(def, l, r.config),
		{"damage": "33", "every": "1.5", "dps": "22", "range": "4.25"})


## LT-29: nothing shipped is pending, so no line anywhere says "(coming soon)".
func test_every_tower_level_and_branch_gets_lines_and_none_is_coming_soon() -> void:
	var shapes := ["Single", "Line", "Blast", "Burst", "Beam", "Aura", "Banish", "Summon"]
	for id: String in _cfg.towers:
		var def := _def(id)
		var all: Array = def.levels.duplicate()
		for b: String in TowerDef.BRANCH_IDS:
			all.append(def.branches[b])
		for s: TowerDef.Level in all:
			var got := _row(id, s)
			for row: Array in TowerInfo.ROWS:
				assert_str(got.get(row[0], "")).override_failure_message("%s %s" % [id, row[0]]) \
					.is_not_empty()
			assert_array(shapes).contains([got["attack"]])
			var soon := _special(s).filter(func(x: String) -> bool: return x.ends_with(CS))
			assert_bool(s.has_pending()).override_failure_message("%s %s" % [id, got]).is_false()
			assert_array(soon).override_failure_message("%s %s" % [id, got]).is_empty()


# --- 16: effect order, pending and unknown keys ---------------------------------------------

func test_effect_lines_follow_effect_groups_order_and_pairs_share_a_line() -> void:
	var got := Array(TowerInfo.effect_lines({"strip_armor": 1.0, "crit_multiplier": 3.0,
		"pierce": 2.0, "crit_chance": 0.5, "slow": 0.1}))
	assert_array(got).is_equal([
		"Pierce: 2-cell-wide line",
		"Slows enemies 10%",
		"50% crit, x3 damage",
		"Foes lose 1 armor",
	])


## LT-29: every schema effect key is wired, so none carries the suffix.
func test_non_pending_effects_have_no_suffix() -> void:
	assert_array(Array(TowerDef.Level.PENDING)).is_empty()
	for key: String in TowerDef.Level.EFFECTS:
		assert_bool(TowerDef.Level.PENDING.has(key)).is_false()
		var got := TowerInfo.effect_lines({key: 1.5})
		assert_int(got.size()).is_equal(1)
		assert_bool(got[0].ends_with(CS)).override_failure_message(got[0]).is_false()


func test_an_unknown_effect_key_renders_as_key_and_value() -> void:
	var got := TowerInfo.effect_lines({"slow": 0.5, "frost_aura": 2.5})
	assert_array(Array(got)).is_equal(["Slows enemies 50%", "frost_aura: 2.5"])


# --- LT-37: Tier B lines fit one panel line and keep their numbers ---------------------------

const LINE_MAX := 24

## The number strings the line of effect `key` must contain, read from the level effects `e`.
func _numbers_for(key: String, e: Dictionary) -> Array:
	match key:
		"pierce": return [_n(e["pierce"])]
		"aoe_radius": return [_n(e["aoe_radius"])]
		"slow": return [_n(e["slow"] * 100.0) + "%"]
		"damage_taken_multiplier": return ["+" + _n((e["damage_taken_multiplier"] - 1.0) * 100.0) + "%"]
		"crit_chance": return [_n(e["crit_chance"] * 100.0) + "%", "x" + _n(e["crit_multiplier"])]
		"bleed_dps": return [_n(e["bleed_dps"]) + "/s", _n(e["bleed_seconds"]) + " s"]
		"burst_targets": return [_n(e["burst_targets"])]
		"pull_cells": return [_n(e["pull_cells"]) + "c", "≤" + _n(e["pull_max_hp"]),
			_n(e["pull_immune_seconds"]) + "s"]
		"strip_armor": return [_n(e["strip_armor"])]
		"fuse_seconds": return [_n(e["fuse_seconds"]) + " s"]
	return []


func test_shipped_effect_lines_fit_24_chars_and_keep_their_numbers() -> void:
	var covered := {}
	for id: String in _cfg.towers:
		var def := _def(id)
		var all: Array = def.levels.duplicate()
		for b: String in TowerDef.BRANCH_IDS:
			all.append(def.branches[b])
		for s: TowerDef.Level in all:
			var lines := TowerInfo.effect_lines(s.effects, false)
			for line: String in lines:
				assert_int(line.length()).override_failure_message("%s '%s'" % [id, line]) \
					.is_less_equal(LINE_MAX)
			for key: String in ["pierce", "aoe_radius", "slow", "damage_taken_multiplier",
					"crit_chance", "burst_targets", "bleed_dps", "pull_cells", "strip_armor",
			"fuse_seconds"]:
				if not TowerInfo.is_active(s.effects, key):
					continue
				var text := "|".join(lines)
				for n: String in _numbers_for(key, s.effects):
					assert_bool(text.contains(n)).override_failure_message(
						"%s %s lacks '%s'" % [id, lines, n]).is_true()
				covered[key] = true
	# every Tier B template was actually exercised by the shipped data
	for key: String in ["pierce", "aoe_radius", "slow", "damage_taken_multiplier",
			"crit_chance", "burst_targets", "bleed_dps", "pull_cells", "strip_armor",
			"fuse_seconds"]:
		assert_bool(covered.has(key)).override_failure_message("not in shipped data: " + key).is_true()


func test_shipped_madness_line_fits_24_chars_and_keeps_the_multiplier() -> void:
	var seen := 0
	for id: String in _cfg.towers:
		var def := _def(id)
		if def.kind == "mundane":
			continue
		var all: Array = def.levels.duplicate()
		for b: String in TowerDef.BRANCH_IDS:
			all.append(def.branches[b])
		for s: TowerDef.Level in all:
			for line: String in TowerInfo.kind_lines(def, s, _cfg.sanity):
				if not line.begins_with("Madness"):
					continue
				seen += 1
				assert_int(line.length()).override_failure_message(line).is_less_equal(LINE_MAX)
				# LT-51: a gate without damage only goes astray (LT-52: a circle's units deal
				# x the multiplier, checked below).
				if s.damage <= 0.0 and not s.is_summon():
					assert_str(line).is_equal("Madness: astray")
					continue
				assert_str(line).contains("x" + _n(_cfg.sanity.madness.damage_multiplier))
	assert_int(seen).is_greater(0)


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
			var got: String = _row(id, s)["reserve"]
			assert_str(got).override_failure_message(id).is_equal(
				_n(s.sanity_reserve) if s.sanity_reserve > 0.0 else TowerInfo.CELL_DASH)
			assert_bool(_special(s).any(func(x: String) -> bool:
				return x.contains("per cast") or x.contains("sanity/s"))).is_false()


# --- 19: delta lines -----------------------------------------------------------------------

## LT-43 §2: stats are table cells now, so a stats-only upgrade has no special line.
func test_rifleman_l1_to_l2_delta_is_one_line_of_changed_stats() -> void:
	var r := _def("rifleman")
	assert_array(Array(TowerInfo.special_delta_lines(r.levels[0], r.levels[1]))).is_empty()


func test_marksman_delta_skips_the_unchanged_interval_and_adds_the_new_effect() -> void:
	var r := _def("rifleman")
	var a := r.levels[1]
	var b := r.branches["a"]
	assert_array(Array(TowerInfo.special_delta_lines(a, b))).is_equal([
		"%s%% crit, x%s damage" % [_n(b.effects["crit_chance"] * 100.0),
			_n(b.effects["crit_multiplier"])]])


func test_support_delta_uses_aura_radius_and_unchanged_effects_are_left_out() -> void:
	var s := _def("elder_sign")
	assert_array(Array(TowerInfo.special_delta_lines(s.levels[1], s.branches["a"]))).is_empty()


func test_same_stats_give_only_the_new_effect_line() -> void:
	var h := _def("harpooner")
	var a := h.levels[1]
	var b := h.branches["a"]
	assert_array(Array(TowerInfo.special_delta_lines(a, b))).is_equal([
		"Bleed %s/s for %s s" % [_n(b.effects["bleed_dps"]), _n(b.effects["bleed_seconds"])]])


func test_pure_rite_delta_ends_with_unaffected_by_madness() -> void:
	var n := _def("necronomicon_reader")
	var got := Array(TowerInfo.special_delta_lines(n.levels[1], n.branches["a"]))
	assert_array(got).is_equal(["Unaffected by madness"])
	assert_array(Array(TowerInfo.special_delta_lines(n.levels[1], n.branches["b"]))) \
		.not_contains(["Unaffected by madness"])


func test_identical_levels_give_no_delta() -> void:
	for id: String in _cfg.towers:
		var l := _def(id).levels[1]
		assert_array(Array(TowerInfo.special_delta_lines(l, l))).is_empty()


## LT-43 §2: the reserve is a table cell, so a reserve change prints no special line.
func test_reserve_delta_line_signs_and_absence() -> void:
	var a := TowerDef.Level.new()
	var b := TowerDef.Level.new()
	a.sanity_reserve = 10.0
	b.sanity_reserve = 15.0
	assert_array(Array(TowerInfo.special_delta_lines(a, b))).is_empty()
	assert_array(Array(TowerInfo.special_delta_lines(b, a))).is_empty()


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
	assert_array(Array(TowerInfo.special_delta_lines(from, _level({"slow": 0.35})))).is_equal(want)
	assert_array(Array(TowerInfo.special_delta_lines(from,
		_level({"slow": 0.35, "damage_taken_multiplier": 1.0})))).is_equal(want)
	# An unknown key dropped reads the same way.
	assert_array(Array(TowerInfo.special_delta_lines(_level({"frost_aura": 2.5}), _level({})))) \
		.is_equal([TowerInfo.REMOVED + "frost_aura: 2.5"])


## A removed effect loses its old line without " (coming soon)"; a whole pair group shows
## once. LT-29: no key is pending any more (crit was the pending example).
func test_a_removed_effect_pair_shows_once_without_coming_soon() -> void:
	var from := _level({"crit_chance": 0.5, "crit_multiplier": 3.0})
	for key: String in TowerDef.Level.EFFECTS:
		assert_bool(TowerInfo.is_pending(key)).override_failure_message(key).is_false()
	assert_array(Array(TowerInfo.special_delta_lines(from, _level({})))) \
		.is_equal([TowerInfo.REMOVED + "50% crit, x3 damage"])


# --- LT-48: the Coast battery's dead zone and AP / HE shells ---------------------------------

func test_battery_shows_its_dead_zone_after_the_range_and_its_shell_effects() -> void:
	var d := _def("coast_battery")
	var l1 := d.levels[0]
	assert_str(_row("coast_battery", l1)["range"]).is_equal(
		"%s–%s" % [_n(l1.min_range), _n(l1.range_cells)])
	# Spec example at today's config.
	if l1.range_cells == 7.0 and l1.min_range == 2.0:
		assert_str(_row("coast_battery", l1)["range"]).is_equal("2–7")
	assert_array(_special(d.branches["a"])).contains(["Ignores armor"])
	assert_array(_special(d.branches["b"])).contains(["Blast radius 1 cell"])
	assert_array(_special(d.branches["b"])).not_contains(["Ignores armor"])
	for id: String in ["rifleman", "harpooner", "dynamite_crew"]:
		assert_str(_row(id, _def(id).levels[0])["range"]).not_contains("–")


func _shell(min_range: float) -> TowerDef.Level:
	var l := TowerDef.Level.new()
	l.range_cells = 7.0
	l.min_range = min_range
	l.damage = 70.0
	l.fire_interval = 3.0
	return l


## LT-43 §2: the dead zone is the Range cell ("2–7"), so it never prints a special line.
func test_delta_shows_the_dead_zone_only_when_it_changes() -> void:
	assert_array(Array(TowerInfo.special_delta_lines(_shell(2.0), _shell(3.0)))).is_empty()
	assert_str(TowerInfo.range_text(_shell(3.0))).is_equal("3–7")


# --- LT-49: Searchlight ----------------------------------------------------------------------

func test_searchlight_is_support_that_reveals_and_slows_with_no_mundane_kind_line() -> void:
	var d := _def("searchlight")
	var l1 := d.levels[0]
	_assert_cells(_row("searchlight", l1), {"attack": "Aura", "range": _n(l1.range_cells),
		"kill": TowerInfo.CELL_DASH, "beam": TowerInfo.CELL_DASH})
	assert_array(_special(l1)).is_equal([
		"Reveals fakes",
		"Slows enemies %s%%" % _n(l1.effects["slow"] * 100.0),
	])
	var b := d.branches["b"]
	assert_array(_special(b)).contains(["Reveals fakes",
		"Foes take +%s%% damage" % _n((b.effects["damage_taken_multiplier"] - 1.0) * 100.0)])
	# It never shoots: no Fraying miss line and no kill regen on any level.
	assert_float(_cfg.sanity.thresholds["fraying"].miss_chance).is_greater(0.0)
	for l: TowerDef.Level in [d.levels[0], d.levels[1], d.branches["a"], b]:
		assert_array(Array(TowerInfo.kind_lines(d, l, _cfg.sanity))).is_empty()
		assert_str(_row("searchlight", l)["kill"]).is_equal(TowerInfo.CELL_DASH)


## LT-50, LT-43 Q3: the Resonator's effect line reads the most it multiplies by (1 +
## sanity_scaling, at sanity 0); its DPS cell is the range "lo–hi" without a live sanity
## (the picker) and the value at that sanity with one (the panel).
func test_resonator_reads_its_scaling_and_the_factor_at_current_sanity() -> void:
	var d := _def("resonator")
	var l1 := d.levels[0]
	assert_array(_special(l1)).is_equal(["Ignores armor", "Up to x3 at low sanity"])
	var base := l1.damage / l1.fire_interval
	assert_str(_row("resonator", l1)["dps"]).is_equal("%s–%s" % [TowerInfo.one_decimal(base),
		TowerInfo.one_decimal(base * 3.0)])
	assert_str(_row("resonator", l1)["attack"]).is_equal("Beam")
	var top := _cfg.sanity.max_sanity
	for sanity: float in [40.0, 92.0, top]:
		assert_str(_row("resonator", l1, sanity)["dps"]).is_equal(
			TowerInfo.one_decimal(base * l1.sanity_factor(sanity, top)))
	assert_array(_special(d.branches["a"])).contains(["Up to x2 at low sanity", "Reveals fakes"])
	assert_array(Array(TowerInfo.kind_lines(d, d.branches["a"], _cfg.sanity))) \
		.is_equal(["Unaffected by madness"])
	assert_array(_special(d.branches["b"])).contains(["Up to x5 at low sanity"])
	# Only a sanity-scaled level's DPS depends on the live sanity.
	var rifle := _def("rifleman")
	assert_str(TowerInfo.row_values(rifle, rifle.levels[0], _cfg, 40.0)["dps"]) \
		.is_equal(_row("rifleman", rifle.levels[0])["dps"])


# --- LT-61 §2: the build list's Trait cell ---------------------------------------------------

## trait_text for each shipped tower's L1, the numbers read from config: an occult reserve
## "Res N" first, then Ground, Blind N (min_range), Line (pierce), Reveal, else the dash.
func test_trait_text_of_every_shipped_tower() -> void:
	var want := {
		"rifleman": TowerInfo.CELL_DASH,
		"harpooner": "Line",
		"elder_sign": "Res " + _n(_def("elder_sign").levels[0].sanity_reserve),
		"necronomicon_reader": "Res " + _n(_def("necronomicon_reader").levels[0].sanity_reserve),
		"dynamite_crew": "Ground",
		"coast_battery": "Blind " + _n(_def("coast_battery").levels[0].min_range),
		"searchlight": "Reveal",
		"resonator": "Res " + _n(_def("resonator").levels[0].sanity_reserve),
		"silver_key": "Res " + _n(_def("silver_key").levels[0].sanity_reserve),
		"summoning_circle": "Res " + _n(_def("summoning_circle").levels[0].sanity_reserve),
	}
	assert_array(_cfg.towers.keys()).contains_exactly_in_any_order(want.keys())
	for id: String in want:
		assert_str(TowerInfo.trait_text(_def(id), _def(id).levels[0])).override_failure_message(id) \
			.is_equal(want[id])


## The rule order on synthetic levels: a reserve beats Ground beats Blind beats Line beats
## Reveal beats Blast; a mundane reserve is no "Res"; a level with none of them is the dash.
func test_trait_text_rule_order_blast_and_dash_fallbacks() -> void:
	var occult := TowerDef.new()
	occult.kind = "occult"
	var mundane := TowerDef.new()
	mundane.kind = "mundane"
	var ground := TowerDef.new()
	ground.kind = "mundane"
	ground.targets = "ground"
	var l := TowerDef.Level.new()
	l.effects = {"aoe_radius": 1.5}
	assert_str(TowerInfo.trait_text(mundane, l)).is_equal("Blast")
	l.effects = {"aoe_radius": 1.5, "reveal_fakes": 1}
	assert_str(TowerInfo.trait_text(mundane, l)).is_equal("Reveal")
	l.effects = {"aoe_radius": 1.5, "reveal_fakes": 1, "pierce": 1}
	assert_str(TowerInfo.trait_text(mundane, l)).is_equal("Line")
	l.min_range = 2.5
	assert_str(TowerInfo.trait_text(mundane, l)).is_equal("Blind 2.5")
	assert_str(TowerInfo.trait_text(ground, l)).is_equal("Ground")
	l.sanity_reserve = 7.0
	assert_str(TowerInfo.trait_text(ground, l)).is_equal("Ground")  # mundane: no "Res"
	assert_str(TowerInfo.trait_text(occult, l)).is_equal("Res 7")
	var plain := TowerDef.Level.new()
	assert_str(TowerInfo.trait_text(mundane, plain)).is_equal(TowerInfo.CELL_DASH)
	assert_str(TowerInfo.trait_text(occult, plain)).is_equal(TowerInfo.CELL_DASH)  # reserve 0
