class_name TowerInfoTest
extends GdUnitTestSuite
## LT-24 §3 TowerInfo: info lines built from config (stats, drains, effects in
## EFFECT_GROUPS order, kind lines last), "(coming soon)" for PENDING keys (none since LT-29:
## every shipped effect is wired), number and cost formatting, and the upgrade delta lines. Text formats come from the design note; the
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


func test_harpooner_shows_the_line_shot_barbed_bleed_and_the_chain_pull() -> void:
	var h := _def("harpooner")
	var l1 := h.levels[0]
	var line := "Pierce: %s-cell-wide line" % _n(l1.effects["pierce"])
	assert_array(_lines("harpooner", l1)).is_equal(_attack(l1) + [line] + _mundane_kind())
	var b := h.branches["a"]
	var bleed := "Bleed %s/s for %s s" % [_n(b.effects["bleed_dps"]), _n(b.effects["bleed_seconds"])]
	assert_array(_lines("harpooner", b)).is_equal(_attack(b)
		+ ["Pierce: %s-cell-wide line" % _n(b.effects["pierce"]),
			bleed] + _mundane_kind())
	var c := h.branches["b"]
	var e: Dictionary = c.effects
	assert_array(_lines("harpooner", c)).contains(["Pull %sc, ≤%s HP, %ss" % [
		_n(e["pull_cells"]), _n(e["pull_max_hp"]), _n(e["pull_immune_seconds"])]])
	# LT-29 S3 spec example at today's config.
	if e["pull_cells"] == 1.5 and e["pull_max_hp"] == 500.0 and e["pull_immune_seconds"] == 3.0:
		assert_array(_lines("harpooner", c)).contains(["Pull 1.5c, ≤500 HP, 3s"])


## LT-47: a ground-only tower says it cannot hit flyers right after its range; the fuse
## line follows the blast radius (EFFECT_GROUPS order).
func test_dynamite_shows_ground_only_the_blast_and_the_fuse() -> void:
	var d := _def("dynamite_crew")
	var l1 := d.levels[0]
	var e: Dictionary = l1.effects
	assert_array(_lines("dynamite_crew", l1)).is_equal(_attack(l1) + [TowerInfo.GROUND_ONLY,
		"Blast radius %s cells" % _n(e["aoe_radius"]),
		"Fuse %s s, thrown ahead" % _n(e["fuse_seconds"])] + _mundane_kind())
	assert_str(TowerInfo.GROUND_ONLY).is_equal("Cannot hit flyers")
	# Spec example at today's config.
	if e["fuse_seconds"] == 1.0:
		assert_array(_lines("dynamite_crew", l1)).contains(["Fuse 1 s, thrown ahead"])
	for id: String in ["rifleman", "harpooner", "necronomicon_reader"]:
		assert_array(_lines(id, _def(id).levels[0])).not_contains([TowerInfo.GROUND_ONLY])


func test_elder_sign_is_support_with_aura_and_effects_and_no_kind_line() -> void:
	var l1 := _def("elder_sign").levels[0]
	assert_array(_lines("elder_sign", l1)).is_equal([
		"Support (no damage)",
		"Aura radius %s cells" % _n(l1.range_cells),
		"Reserves %s sanity" % _n(l1.sanity_reserve),
		"Slows enemies %s%%" % _n(l1.effects["slow"] * 100.0),
		"Foes take +%s%% damage" % _n((l1.effects["damage_taken_multiplier"] - 1.0) * 100.0),
	])


## LT-23: the Seal's drain line became its reserve line; LT-29 wired the strip (no suffix).
func test_corrupted_seal_shows_its_reserve_and_armor_strip() -> void:
	var seal := _def("elder_sign").branches["b"]
	var got := _lines("elder_sign", seal)
	var reserve := "Reserves %s sanity" % _n(seal.sanity_reserve)
	assert_array(got).contains([reserve,
		"Foes lose %s armor" % _n(seal.effects["strip_armor"])])
	assert_bool(got.any(func(x: String) -> bool: return x.contains("sanity/s"))).is_false()
	# The reserve comes before effects; the strip is the last effect group.
	assert_int(got.find(reserve)) \
		.is_less(got.find("Slows enemies %s%%" % _n(seal.effects["slow"] * 100.0)))
	assert_str(got[got.size() - 1]).is_equal(
		"Foes lose %s armor" % _n(seal.effects["strip_armor"]))


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


## LT-29: Gangsters (burst_targets) replaced Militia (shooters); DPS stays damage over
## interval (the burst spreads it, crits do not count).
func test_dps_is_damage_over_interval_only_for_gangsters_and_marksman() -> void:
	var m := _def("rifleman").branches["b"]
	var got := _lines("rifleman", m)
	assert_str(got[0]).is_equal(_attack(m)[0])
	if is_equal_approx(m.damage, 7.0) and is_equal_approx(m.fire_interval, 0.2):
		assert_str(got[0]).contains("(35 DPS)")
	assert_array(got).contains(["Spreads fire over %s foes" % _n(m.effects["burst_targets"])])
	if m.effects["burst_targets"] == 3.0:
		assert_array(got).contains(["Spreads fire over 3 foes"])
	assert_bool(m.effects.has("shooters")).is_false()
	var mk := _def("rifleman").branches["a"]
	var gk := _lines("rifleman", mk)
	assert_str(gk[0]).is_equal(_attack(mk)[0])
	assert_array(gk).contains(["%s%% crit, x%s damage" % [
		_n(mk.effects["crit_chance"] * 100.0), _n(mk.effects["crit_multiplier"])]])


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


## LT-29: nothing shipped is pending, so no line anywhere says "(coming soon)".
func test_every_tower_level_and_branch_gets_lines_and_none_is_coming_soon() -> void:
	for id: String in _cfg.towers:
		var def := _def(id)
		var all: Array = def.levels.duplicate()
		for b: String in TowerDef.BRANCH_IDS:
			all.append(def.branches[b])
		for s: TowerDef.Level in all:
			var got := _lines(id, s)
			assert_array(got).is_not_empty()
			var first: String = got[0]
			# LT-51: a gate without damage leads with its cast timer.
			# LT-52: a circle leads with its summon timer.
			assert_bool(first.begins_with("Damage ") or first == "Support (no damage)"
				or first.begins_with("Casts every ") or first.begins_with("Summons every ")) \
				.override_failure_message("%s: %s" % [id, first]).is_true()
			var soon := got.filter(func(x: String) -> bool: return x.ends_with(CS))
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
		"%s%% crit, x%s damage" % [_n(b.effects["crit_chance"] * 100.0),
			_n(b.effects["crit_multiplier"])]])


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
		"Bleed %s/s for %s s" % [_n(b.effects["bleed_dps"]), _n(b.effects["bleed_seconds"])]])


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


## A removed effect loses its old line without " (coming soon)"; a whole pair group shows
## once. LT-29: no key is pending any more (crit was the pending example).
func test_a_removed_effect_pair_shows_once_without_coming_soon() -> void:
	var from := _level({"crit_chance": 0.5, "crit_multiplier": 3.0})
	for key: String in TowerDef.Level.EFFECTS:
		assert_bool(TowerInfo.is_pending(key)).override_failure_message(key).is_false()
	assert_array(Array(TowerInfo.delta_lines(from, _level({})))) \
		.is_equal([TowerInfo.REMOVED + "50% crit, x3 damage"])


# --- LT-48: the Coast battery's dead zone and AP / HE shells ---------------------------------

func test_battery_shows_its_dead_zone_after_the_range_and_its_shell_effects() -> void:
	var d := _def("coast_battery")
	var l1 := d.levels[0]
	assert_array(_lines("coast_battery", l1)).is_equal(_attack(l1)
		+ ["Dead zone: %s cells" % _n(l1.min_range)] + _mundane_kind())
	# Spec example at today's config.
	if l1.range_cells == 7.0 and l1.min_range == 2.0:
		var got := _lines("coast_battery", l1)
		assert_array(got.slice(1, 3)).is_equal(["Range 7 cells", "Dead zone: 2 cells"])
	assert_array(_lines("coast_battery", d.branches["a"])).contains(["Ignores armor"])
	assert_array(_lines("coast_battery", d.branches["b"])).contains(["Blast radius 1 cells"])
	assert_array(_lines("coast_battery", d.branches["b"])).not_contains(["Ignores armor"])
	for id: String in ["rifleman", "harpooner", "dynamite_crew"]:
		for line: String in _lines(id, _def(id).levels[0]):
			assert_bool(line.begins_with("Dead zone")).override_failure_message(id).is_false()


func _shell(min_range: float) -> TowerDef.Level:
	var l := TowerDef.Level.new()
	l.range_cells = 7.0
	l.min_range = min_range
	l.damage = 70.0
	l.fire_interval = 3.0
	return l


func test_delta_shows_the_dead_zone_only_when_it_changes() -> void:
	assert_array(Array(TowerInfo.delta_lines(_shell(2.0), _shell(3.0)))) \
		.is_equal([_arrow("Dead zone", 2.0, 3.0)])
	assert_array(Array(TowerInfo.delta_lines(_shell(2.0), _shell(2.0)))).is_empty()
	var d := _def("coast_battery")
	for line: String in TowerInfo.delta_lines(d.levels[0], d.levels[1]):
		assert_bool(line.contains("Dead zone")).override_failure_message(line).is_false()


# --- LT-49: Searchlight ----------------------------------------------------------------------

func test_searchlight_is_support_that_reveals_and_slows_with_no_mundane_kind_line() -> void:
	var d := _def("searchlight")
	var l1 := d.levels[0]
	assert_array(_lines("searchlight", l1)).is_equal([
		"Support (no damage)",
		"Aura radius %s cells" % _n(l1.range_cells),
		"Reveals fakes",
		"Slows enemies %s%%" % _n(l1.effects["slow"] * 100.0),
	])
	var b := d.branches["b"]
	assert_array(_lines("searchlight", b)).contains(["Reveals fakes",
		"Foes take +%s%% damage" % _n((b.effects["damage_taken_multiplier"] - 1.0) * 100.0)])
	# It never shoots: no Fraying miss line and no kill regen line on any level.
	assert_float(_cfg.sanity.thresholds["fraying"].miss_chance).is_greater(0.0)
	for l: TowerDef.Level in [d.levels[0], d.levels[1], d.branches["a"], b]:
		assert_array(Array(TowerInfo.kind_lines(d, l, _cfg.sanity))).is_empty()


## LT-50 (§5 "x1.6 at current sanity", §7 Q2): the Resonator's effect line reads the most it
## multiplies by (1 + sanity_scaling, at sanity 0); with the live sanity passed, a line with
## the factor now (on the full bar); the picker passes none, so no such line.
func test_resonator_reads_its_scaling_and_the_factor_at_current_sanity() -> void:
	var d := _def("resonator")
	var l1 := d.levels[0]
	assert_array(_lines("resonator", l1)).is_equal(_attack(l1) + [
		"Reserves %s sanity" % _n(l1.sanity_reserve),
		"Ignores armor",
		"Up to x3 at low sanity",
		"Madness: x%s, astray" % _n(_cfg.sanity.madness.damage_multiplier)])
	assert_array(Array(TowerInfo.lines(d, l1, _cfg.sanity, 40.0))).is_equal(_attack(l1) + [
		"Reserves %s sanity" % _n(l1.sanity_reserve),
		"Ignores armor",
		"Up to x3 at low sanity",
		"x2.2 at current sanity",
		"Madness: x%s, astray" % _n(_cfg.sanity.madness.damage_multiplier)])
	assert_array(Array(TowerInfo.lines(d, l1, _cfg.sanity, 92.0))) \
		.contains(["x1.2 at current sanity"])
	assert_array(Array(TowerInfo.lines(d, l1, _cfg.sanity, 100.0))) \
		.contains(["x1.0 at current sanity"])
	assert_array(_lines("resonator", d.branches["a"])) \
		.contains(["Up to x2 at low sanity", "Reveals fakes", "Unaffected by madness"])
	assert_array(_lines("resonator", d.branches["b"])).contains(["Up to x5 at low sanity"])
	# Only a sanity-scaled level gets the live line.
	var rifle := _def("rifleman")
	var got := Array(TowerInfo.lines(rifle, rifle.levels[0], _cfg.sanity, 40.0))
	assert_bool(got.any(func(s: String) -> bool: return s.ends_with("at current sanity"))) \
		.is_false()
