class_name ConfigValidTest
extends ConfigTestBase
## LT-3: valid config loads into typed structures (GDD §5-§8, §10).


func _real() -> GameConfig:
	var result := ConfigLoader.load_dir("res://data")
	assert_array(result.errors).is_empty()
	assert_bool(result.ok).is_true()
	assert_object(result.config).is_not_null()
	return result.config


## LT-98: the shipped roster (ids, wave count) is pinned in roster_snapshot_test.gd only;
## here the real data loads and every def in it obeys the invariants below.
func test_real_data_loads_and_is_not_empty() -> void:
	var c := _real()
	assert_dict(c.towers).is_not_empty()
	assert_dict(c.enemies).is_not_empty()
	assert_array(c.waves.waves).is_not_empty()


func test_default_dir_is_res_data() -> void:
	var result := ConfigLoader.load_dir()
	assert_bool(result.ok).is_true()
	var c := _real()
	assert_array(result.config.towers.keys()).contains_exactly_in_any_order(c.towers.keys())
	assert_array(result.config.enemies.keys()).contains_exactly_in_any_order(c.enemies.keys())
	assert_int(result.config.waves.waves.size()).is_equal(c.waves.waves.size())


func test_economy_fields() -> void:
	var e := _real().economy
	assert_int(e.starting_gold).is_equal(300)
	assert_int(e.wave_bonus_base).is_equal(50)
	assert_int(e.wave_bonus_per_wave).is_equal(10)
	assert_float(e.sell_refund_ratio).is_equal(0.7)
	assert_array(Array(e.relic_ids())).is_equal(["bone", "amber", "idol", "star_stone"])
	var prices: Array = e.relics.map(func(k: EconomyConfig.RelicKind) -> int: return k.price)
	assert_array(prices).is_equal([5, 15, 50, 200])
	assert_float(e.token_fly_seconds).is_equal(2.0)
	assert_float(e.ghost_vanish_seconds).is_equal(1.0)
	assert_float(e.early_night_luck_per_second).is_equal(0.02)
	assert_int(e.lighthouse_hp).is_equal(20)


func test_enemy_stats() -> void:
	var en := _real().enemies
	# hp is a tuned balance number (LT-23 S10): read it from the raw JSON, not pinned here.
	var raw: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/enemies.json"))["enemies"]
	# id: [hp, speed, armor, leak_damage, drops (LT-27 §1.1: bone, amber, idol, star_stone)]
	var expected := {
		"cultist": [0.0, 1.0, 0.0, 1, [999, 0, 0, 1]],
		"hybrid": [0.0, 0.9, 2.0, 1, [699, 250, 50, 1]],
		"deep_one": [0.0, 1.6, 0.0, 1, [749, 250, 0, 1]],
		"night_gaunt": [0.0, 1.3, 0.0, 2, [399, 500, 100, 1]],
		"shoggoth": [0.0, 0.5, 5.0, 5, [0, 0, 999, 1]],
	}
	for id: String in expected:
		var e: EnemyDef = en[id]
		var x: Array = expected[id]
		assert_str(e.id).is_equal(id)
		assert_float(e.hp).is_equal(float(raw[id]["hp"]))
		assert_float(e.hp).is_greater(0.0)
		assert_float(e.speed).is_equal(x[1])
		assert_float(e.armor).is_equal(x[2])
		assert_int(e.leak_damage).is_equal(x[3])
		assert_array(e.drops.keys()).is_equal(["bone", "amber", "idol", "star_stone"])
		assert_array(e.drops.values()).is_equal(x[4])


func test_enemy_defaults_and_traits() -> void:
	var en := _real().enemies
	assert_bool(en["night_gaunt"].flying).is_true()
	for id in ["cultist", "hybrid", "deep_one", "shoggoth"]:
		assert_bool(en[id].flying).is_false()
	assert_float(en["shoggoth"].horror_drain).is_equal(2.5)  # LT-45 difficulty pass (was 0.5)
	for id in ["cultist", "hybrid", "deep_one", "night_gaunt"]:
		assert_float(en[id].horror_drain).is_equal(0.0)
	assert_dict(en["deep_one"].traits).contains_keys(["pack"])
	assert_float(en["deep_one"].traits["pack"]["min"]).is_equal(4.0)
	assert_float(en["deep_one"].traits["pack"]["max"]).is_equal(6.0)
	assert_dict(en["hybrid"].traits).is_empty()


func test_tower_structure() -> void:
	var t := _real().towers
	var kinds := {"rifleman": "mundane", "harpooner": "mundane",
		"elder_sign": "occult", "necronomicon_reader": "occult"}
	var costs := {"rifleman": 50, "harpooner": 70, "elder_sign": 100, "necronomicon_reader": 150}
	for id: String in kinds:
		var td: TowerDef = t[id]
		assert_str(td.kind).is_equal(kinds[id])
		assert_int(td.cost).is_equal(costs[id])
	# Level/branch structure of every tower: test_every_tower_def_is_well_formed.


## LT-61 §4: `short` is the build list's name; a tower without it shows its full name, and
## the value is stripped.
func test_short_name_comes_from_json_short_and_defaults_to_the_name() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/towers.json"))["towers"]
	var t := _real().towers
	var with_short := 0
	for id: String in raw:
		var obj: Dictionary = raw[id]
		var want: String = obj["short"] if obj.has("short") else obj["name"]
		assert_str(t[id].short_name).override_failure_message(id).is_equal(want)
		with_short += 1 if obj.has("short") else 0
	assert_int(with_short).is_greater(0)
	assert_int(with_short).is_less(raw.size())  # both the explicit and the default arm are hit
	var r := load_json_edit("towers.json", func(d: Dictionary) -> void:
		d["towers"]["rifleman"]["short"] = "  Rifle  ")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_str(r.config.towers["rifleman"].short_name).is_equal("Rifle")
	assert_str(r.config.towers["rifleman"].name).is_equal(t["rifleman"].name)


## LT-23 §2: the total reserve per level/branch; mundane towers reserve nothing.
func test_tower_sanity_reserve_default_and_explicit() -> void:
	var t := _real().towers
	for id in ["rifleman", "harpooner"]:
		for lv: TowerDef.Level in t[id].levels + t[id].branches.values():
			assert_float(lv.sanity_reserve).is_equal(0.0)
	# The reserves are tuned balance numbers (LT-23 S10): read from the raw JSON.
	var raw: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/towers.json"))["towers"]
	var expected := {}
	for id in ["elder_sign", "necronomicon_reader"]:
		var rt: Dictionary = raw[id]
		expected[id] = [float(rt["levels"][0]["sanity_reserve"]),
			float(rt["levels"][1]["sanity_reserve"]),
			float(rt["branches"]["a"]["sanity_reserve"]),
			float(rt["branches"]["b"]["sanity_reserve"])]
	for id: String in expected:
		var td: TowerDef = t[id]
		var got := [td.levels[0].sanity_reserve, td.levels[1].sanity_reserve,
			td.branches["a"].sanity_reserve, td.branches["b"].sanity_reserve]
		assert_array(got).is_equal(expected[id])


# --- LT-23 S15: ordering pins (design intent; the exact numbers are tuned, these must hold) ---

func test_an_upgrade_never_lowers_damage() -> void:
	var t := _real().towers
	for id: String in t:
		var td: TowerDef = t[id]
		var l1 := td.levels[0]
		var l2 := td.levels[1]
		assert_float(l2.damage).is_greater_equal(l1.damage)
		if l2.damage > 0.0:
			assert_float(l2.damage / l2.fire_interval).is_greater_equal(l1.damage / l1.fire_interval)
		for b: String in td.branches:
			var l3 := td.branches[b]
			# A branch that fires at least as fast must not lose DPS (Gangsters hit softer but
			# faster); a slower one must still hit harder per shot (Pure Rite trades speed
			# for madness immunity).
			if l3.damage > 0.0 and l3.fire_interval <= l2.fire_interval:
				assert_float(l3.damage / l3.fire_interval).is_greater_equal(
					l2.damage / l2.fire_interval)
			else:
				assert_float(l3.damage).is_greater_equal(l2.damage)


func test_corrupted_branches_reserve_more_sanity_than_pure_ones() -> void:
	var t := _real().towers
	assert_float(t["necronomicon_reader"].branches["b"].sanity_reserve).is_greater(
		t["necronomicon_reader"].branches["a"].sanity_reserve)
	assert_float(t["elder_sign"].branches["b"].sanity_reserve).is_greater(
		t["elder_sign"].branches["a"].sanity_reserve)


func test_madness_multipliers_are_a_buff_for_enemies() -> void:
	var m := _real().sanity.madness
	assert_float(m.enemy_speed_multiplier).is_greater(1.0)
	assert_float(m.enemy_damage_taken_multiplier).is_less(1.0)


func test_level_range_comes_from_json_range_key() -> void:
	var t := _real().towers
	assert_float(t["rifleman"].levels[0].range_cells).is_equal(3.0)
	assert_float(t["rifleman"].levels[1].range_cells).is_equal(3.5)
	assert_float(t["rifleman"].branches["a"].range_cells).is_equal(5.0)


## LT-29 (LT-46 §2.2): Gangsters replaced Militia: 7 damage every 0.2 s over 3 targets.
func test_gangsters_fire_faster_than_level_two() -> void:
	var rifle: TowerDef = _real().towers["rifleman"]
	var g := rifle.branches["b"]
	assert_str(g.name).is_equal("Gangsters")
	assert_float(g.fire_interval).is_equal(0.2)
	assert_float(g.damage).is_equal(7.0)
	assert_float(g.range_cells).is_equal(3.0)
	assert_float(rifle.levels[1].fire_interval).is_equal(0.7)
	assert_float(g.fire_interval).is_less(rifle.levels[1].fire_interval)


func test_tower_effects_maps() -> void:
	var t := _real().towers
	assert_float(t["rifleman"].branches["a"].effects["crit_chance"]).is_equal(0.2)
	assert_dict(t["rifleman"].branches["b"].effects).is_equal({"burst_targets": 3.0})
	var chain: Dictionary = t["harpooner"].branches["b"].effects
	assert_float(chain["pull_max_hp"]).is_equal(500.0)
	assert_float(chain["pull_immune_seconds"]).is_equal(3.0)
	assert_dict(t["rifleman"].levels[0].effects).is_empty()
	assert_float(t["elder_sign"].levels[0].effects["slow"]).is_equal(0.2)  # LT-70


func test_madness_affected_defaults_to_occult_kind() -> void:
	var t := _real().towers
	for lv: TowerDef.Level in t["rifleman"].levels + t["harpooner"].levels:
		assert_bool(lv.madness_affected).is_false()
	for b in ["a", "b"]:
		assert_bool(t["rifleman"].branches[b].madness_affected).is_false()
	for lv: TowerDef.Level in t["elder_sign"].levels + t["necronomicon_reader"].levels:
		assert_bool(lv.madness_affected).is_true()
	assert_bool(t["necronomicon_reader"].branches["a"].madness_affected).is_false()  # Pure Rite
	assert_bool(t["necronomicon_reader"].branches["b"].madness_affected).is_true()


func test_occult_tower_may_opt_out_of_madness() -> void:
	var r := load_json_edit("towers.json", func(d: Dictionary) -> void:
		d["towers"]["elder_sign"]["levels"][0]["madness_affected"] = false)
	assert_array(r.errors).is_empty()
	assert_bool(r.config.towers["elder_sign"].levels[0].madness_affected).is_false()


func test_waves() -> void:
	var w := _real().waves
	assert_float(w.build_phase_seconds).is_equal(40.0)
	var g0: WavesConfig.SpawnGroup = w.waves[0].groups[0]
	assert_str(g0.enemy_id).is_equal("cultist")
	assert_int(g0.count).is_equal(8)
	assert_float(g0.interval).is_equal(1.2)
	assert_float(g0.delay).is_equal(0.0)  # default
	var g1: WavesConfig.SpawnGroup = w.waves[1].groups[1]
	assert_str(g1.enemy_id).is_equal("deep_one")
	assert_float(g1.delay).is_equal(8.0)
	# Every wave's groups: test_every_wave_is_well_formed.


## LT-111: the shipped waves carry no multipliers (absent = 1.0); 10 (the bound) and a
## fraction load as given, on their own wave only.
func test_wave_multipliers_default_to_one_and_load_up_to_ten() -> void:
	var real := _real().waves.waves
	for i in real.size():  # LT-72: waves 4-10 ship a tuned hp_mult, waves 1-3 default to 1 (hp)
		if i < 3:
			assert_float(real[i].hp_mult).is_equal(1.0)
		else:
			assert_float(real[i].hp_mult).is_between(0.1, 5.0)
		assert_float(real[i].speed_mult).is_between(0.1, 5.0)
	var r := load_json_edit("waves.json", func(d: Dictionary) -> void:
		d["waves"][1]["hp_mult"] = 10
		d["waves"][1]["speed_mult"] = 0.25
		d["waves"][2]["hp_mult"] = 1.0)
	assert_array(r.errors).is_empty()
	var waves := r.config.waves.waves
	assert_float(waves[1].hp_mult).is_equal(10.0)
	assert_float(waves[1].speed_mult).is_equal(0.25)
	assert_float(waves[2].hp_mult).is_equal(1.0)
	assert_float(waves[0].hp_mult).is_equal(1.0)
	assert_float(waves[0].speed_mult).is_equal(1.0)


func test_sanity() -> void:
	var s := _real().sanity
	assert_float(s.max_sanity).is_equal(100.0)
	assert_float(s.start).is_equal(100.0)
	assert_float(s.regen_between_waves).is_equal(12.0)
	assert_float(s.regen_mundane_kill).is_equal(0.5)
	assert_float(s.horror_radius_cells).is_equal(3.0)
	assert_array(s.thresholds.keys()).contains_exactly_in_any_order(
		["lucid", "whispers", "fraying", "madness"])
	assert_float(s.thresholds["lucid"].min_sanity).is_equal(70.0)
	assert_float(s.thresholds["whispers"].min_sanity).is_equal(40.0)
	assert_float(s.thresholds["whispers"].fake_spawn_interval).is_equal(15.0)
	assert_float(s.thresholds["fraying"].min_sanity).is_equal(1.0)
	assert_float(s.thresholds["fraying"].miss_chance).is_equal(0.15)
	assert_float(s.thresholds["madness"].min_sanity).is_equal(0.0)


func test_madness_rules() -> void:
	var m := _real().sanity.madness
	assert_float(m.damage_multiplier).is_equal(2.0)
	assert_float(m.shot_real).is_equal(0.4)
	assert_float(m.shot_fake).is_equal(0.35)
	assert_float(m.shot_empty).is_equal(0.25)
	assert_str(m.exit_rule).is_equal("permanent")
	assert_float(m.restore_sanity).is_equal(30.0)
	assert_int(m.buyout_cost).is_equal(150)
	# The multipliers are tuned numbers (LT-23 S10): the file's value, and a buff by sign.
	var raw: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/sanity.json"))["madness"]
	assert_float(m.enemy_speed_multiplier).is_equal(float(raw["enemy_speed_multiplier"]))
	assert_float(m.enemy_damage_taken_multiplier).is_equal(
		float(raw["enemy_damage_taken_multiplier"]))
	assert_float(m.enemy_speed_multiplier).is_greater(1.0)
	assert_float(m.enemy_damage_taken_multiplier).is_between(0.0, 1.0)


func test_custom_dir_is_read_via_user_and_absolute_paths() -> void:
	var dir := make_dir()
	edit(dir, "economy.json", func(d: Dictionary) -> void: d["starting_gold"] = 999)
	var r := ConfigLoader.load_dir(dir)
	assert_array(r.errors).is_empty()
	assert_int(r.config.economy.starting_gold).is_equal(999)
	var abs_r := ConfigLoader.load_dir(ProjectSettings.globalize_path(dir))
	assert_array(abs_r.errors).is_empty()
	assert_int(abs_r.config.economy.starting_gold).is_equal(999)
	# the real data is untouched
	assert_int(_real().economy.starting_gold).is_equal(300)


# --- LT-98: invariants over every def (adding content must not break these; extend here) ---

func test_every_tower_def_is_well_formed() -> void:
	var t := _real().towers
	for id: String in t:
		var td: TowerDef = t[id]
		assert_str(td.id).override_failure_message(id).is_equal(id)
		assert_str(td.name.strip_edges()).override_failure_message(id).is_not_empty()
		assert_str(td.short_name).override_failure_message(id).is_not_empty()
		assert_int(td.role.length()).override_failure_message(id) \
			.is_less_equal(TowerDef.ROLE_MAX_CHARS)
		assert_bool(TowerDef.KINDS.has(td.kind)).override_failure_message(id).is_true()
		assert_bool(TowerDef.TARGETS.has(td.targets)).override_failure_message(id).is_true()
		assert_int(td.glyph.length()).override_failure_message(id).is_equal(1)
		assert_int(td.cost).override_failure_message(id + ": every tower costs gold").is_greater(0)
		assert_int(td.levels.size()).override_failure_message(id).is_equal(TowerDef.LEVEL_COUNT)
		assert_array(td.branches.keys()).override_failure_message(id) \
			.contains_exactly_in_any_order(Array(TowerDef.BRANCH_IDS))
		assert_int(td.levels[0].upgrade_cost).override_failure_message(id).is_equal(0)
		for i in range(1, td.levels.size()):
			assert_int(td.levels[i].upgrade_cost).override_failure_message(id).is_greater(0)
		for b: String in td.branches:
			assert_int(td.branches[b].upgrade_cost).override_failure_message(id + "." + b) \
				.is_greater(0)
			assert_str(td.branches[b].name.strip_edges()).override_failure_message(id + "." + b) \
				.is_not_empty()


func test_every_tower_level_is_well_formed() -> void:
	var t := _real().towers
	for id: String in t:
		var td: TowerDef = t[id]
		var named := {}
		for i in td.levels.size():
			named["%s.levels[%d]" % [id, i]] = td.levels[i]
		for b: String in td.branches:
			named["%s.branches.%s" % [id, b]] = td.branches[b]
		for where: String in named:
			var lv: TowerDef.Level = named[where]
			assert_float(lv.range_cells).override_failure_message(where).is_greater(0.0)
			assert_float(lv.damage).override_failure_message(where).is_greater_equal(0.0)
			if lv.damage > 0.0:
				assert_float(lv.fire_interval).override_failure_message(where).is_greater(0.0)
			assert_float(lv.sanity_reserve).override_failure_message(where).is_greater_equal(0.0)
			if td.kind == "mundane":  # LT-23 §2: mundane towers reserve nothing, never go mad
				assert_float(lv.sanity_reserve).override_failure_message(where).is_equal(0.0)
				assert_bool(lv.madness_affected).override_failure_message(where).is_false()
			for key: String in lv.effects:
				var at := where + ".effects." + key
				assert_bool(EffectCatalog.has(key)).override_failure_message(at).is_true()
				assert_bool(EffectCatalog.is_pending(key)).override_failure_message(at).is_false()
				var v: float = lv.effects[key]
				assert_float(v).override_failure_message(at).is_greater_equal(0.0)
				assert_float(v).override_failure_message(at) \
					.is_less_equal(EffectCatalog.max_of(key) if EffectCatalog.has(key) else -1.0)


func test_tower_glyphs_are_unique() -> void:
	var seen := {}
	var t := _real().towers
	for id: String in t:
		var g: String = t[id].glyph
		assert_bool(seen.has(g)).override_failure_message(
			"%s and %s share glyph %s" % [id, seen.get(g, ""), g]).is_false()
		seen[g] = id


func test_every_enemy_def_is_well_formed() -> void:
	var c := _real()
	var relics := Array(c.economy.relic_ids())
	for id: String in c.enemies:
		var e: EnemyDef = c.enemies[id]
		assert_str(e.id).override_failure_message(id).is_equal(id)
		assert_str(e.name.strip_edges()).override_failure_message(id).is_not_empty()
		assert_float(e.hp).override_failure_message(id).is_greater(0.0)
		assert_float(e.speed).override_failure_message(id).is_greater(0.0)
		assert_float(e.armor).override_failure_message(id).is_greater_equal(0.0)
		assert_int(e.leak_damage).override_failure_message(id).is_greater_equal(0)
		assert_float(e.horror_drain).override_failure_message(id).is_greater_equal(0.0)
		assert_array(e.drops.keys()).override_failure_message(id).is_equal(relics)
		var total := 0
		for kind: String in e.drops:
			assert_int(e.drops[kind]).override_failure_message(id + "." + kind) \
				.is_greater_equal(0)
			total += e.drops[kind]
		assert_int(total).override_failure_message(id + ": drops sum to 0").is_greater(0)
		for trait_id: String in e.traits:
			assert_bool(TraitCatalog.has(trait_id)).override_failure_message(
				id + ".traits." + trait_id).is_true()


func test_every_wave_is_well_formed() -> void:
	var c := _real()
	assert_float(c.waves.build_phase_seconds).is_greater(0.0)
	for i in c.waves.waves.size():
		var wave: WavesConfig.Wave = c.waves.waves[i]
		assert_array(wave.groups).override_failure_message("waves[%d]" % i).is_not_empty()
		for j in wave.groups.size():
			var g: WavesConfig.SpawnGroup = wave.groups[j]
			var at := "waves[%d].groups[%d]" % [i, j]
			assert_bool(c.enemies.has(g.enemy_id)).override_failure_message(
				at + ": unknown enemy " + g.enemy_id).is_true()
			assert_int(g.count).override_failure_message(at).is_greater_equal(1)
			assert_float(g.interval).override_failure_message(at).is_greater_equal(0.0)
			assert_float(g.delay).override_failure_message(at).is_greater_equal(0.0)
