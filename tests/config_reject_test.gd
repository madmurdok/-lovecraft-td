class_name ConfigRejectTest
extends ConfigTestBase
## LT-3: malformed configs are rejected loudly (ok=false, config null, error names file + path).

const T := "towers.json"
const E := "enemies.json"
const W := "waves.json"
const EC := "economy.json"
const S := "sanity.json"


# --- file level -------------------------------------------------------------

func test_missing_file_each_of_five() -> void:
	for f: String in FILES:
		var dir := make_dir()
		DirAccess.remove_absolute(dir.path_join(f))
		var r := GameConfig.load_from_dir(dir)
		assert_rejected(r, f, "", "not found")
		assert_int(r.errors.size()).is_equal(1)


func test_missing_dir_rejects_all_files() -> void:
	var r := GameConfig.load_from_dir("user://config_tests/does_not_exist")
	assert_bool(r.ok).is_false()
	assert_object(r.config).is_null()
	for f: String in FILES:
		assert_bool(has_error(r, f, "", "not found")).is_true()


func test_bad_json() -> void:
	var r := load_edited(func(dir: String) -> void:
		write_file(dir, T, "{\n  \"towers\": {\n  \"a\": ,\n}\n}"))
	assert_rejected(r, T, "", "invalid JSON")


func test_empty_file_is_bad_json() -> void:
	var r := load_edited(func(dir: String) -> void: write_file(dir, S, ""))
	assert_rejected(r, S, "", "invalid JSON")


func test_root_must_be_object() -> void:
	for f: String in FILES:
		var r := load_edited(func(dir: String) -> void: write_file(dir, f, "[1, 2]"))
		assert_rejected(r, f, "", "root must be an object")


func test_unreadable_enemies_does_not_cascade_into_waves() -> void:
	var r := load_edited(func(dir: String) -> void: write_file(dir, E, "nope"))
	assert_rejected(r, E, "", "invalid JSON")
	assert_int(r.errors.size()).is_equal(1)
	for e in r.errors:
		assert_bool(e.contains("unknown enemy")).is_false()


# --- required fields / types ------------------------------------------------

func test_missing_required_field() -> void:
	var cases := [
		[E, "enemies.cultist.hp", func(d: Dictionary) -> void: d["enemies"]["cultist"].erase("hp")],
		[E, "enemies.cultist.name", func(d: Dictionary) -> void: d["enemies"]["cultist"].erase("name")],
		[T, "towers.rifleman.kind", func(d: Dictionary) -> void: d["towers"]["rifleman"].erase("kind")],
		[T, "towers.rifleman.levels[0].range",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["levels"][0].erase("range")],
		[W, "waves[0].groups[0].count",
			func(d: Dictionary) -> void: d["waves"][0]["groups"][0].erase("count")],
		[W, "build_phase_seconds", func(d: Dictionary) -> void: d.erase("build_phase_seconds")],
		[EC, "starting_gold", func(d: Dictionary) -> void: d.erase("starting_gold")],
		[EC, "lighthouse.hp", func(d: Dictionary) -> void: d["lighthouse"].erase("hp")],
		[S, "madness.exit_rule", func(d: Dictionary) -> void: d["madness"].erase("exit_rule")],
		[S, "regen.between_waves", func(d: Dictionary) -> void: d["regen"].erase("between_waves")],
	]
	for c: Array in cases:
		assert_rejected(load_json_edit(c[0], c[2]), c[0], c[1], "missing required field")


func test_wrong_type() -> void:
	var cases := [
		[E, "enemies.cultist.hp", "expected number",
			func(d: Dictionary) -> void: d["enemies"]["cultist"]["hp"] = "60"],
		[E, "enemies.cultist.name", "expected string",
			func(d: Dictionary) -> void: d["enemies"]["cultist"]["name"] = 5],
		[E, "enemies.night_gaunt.flying", "expected boolean",
			func(d: Dictionary) -> void: d["enemies"]["night_gaunt"]["flying"] = "yes"],
		[E, "enemies.cultist.traits", "expected object",
			func(d: Dictionary) -> void: d["enemies"]["cultist"]["traits"] = []],
		[E, "enemies.cultist", "expected object",
			func(d: Dictionary) -> void: d["enemies"]["cultist"] = 7],
		[W, "waves", "expected array", func(d: Dictionary) -> void: d["waves"] = {}],
		[W, "waves[0]", "expected object", func(d: Dictionary) -> void: d["waves"][0] = "x"],
		[T, "towers.rifleman.levels", "expected array",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["levels"] = {}],
		[EC, "wave_bonus", "expected object", func(d: Dictionary) -> void: d["wave_bonus"] = 3],
		[S, "thresholds.lucid.min", "expected number",
			func(d: Dictionary) -> void: d["thresholds"]["lucid"]["min"] = null],
	]
	for c: Array in cases:
		assert_rejected(load_json_edit(c[0], c[3]), c[0], c[1], c[2])


func test_non_integer_where_integer_expected() -> void:
	var cases := [
		[W, "waves[0].groups[0].count",
			func(d: Dictionary) -> void: d["waves"][0]["groups"][0]["count"] = 1.5],
		[T, "towers.rifleman.cost",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["cost"] = 50.5],
		[E, "enemies.cultist.reward",
			func(d: Dictionary) -> void: d["enemies"]["cultist"]["reward"] = 5.5],
		[E, "enemies.cultist.leak_damage",
			func(d: Dictionary) -> void: d["enemies"]["cultist"]["leak_damage"] = 0.5],
		[EC, "starting_gold", func(d: Dictionary) -> void: d["starting_gold"] = 200.25],
	]
	var file_of := [W, T, E, E, EC]
	for i in cases.size():
		assert_rejected(load_json_edit(file_of[i], cases[i][2]), file_of[i], cases[i][1],
			"expected integer")


# --- ranges -----------------------------------------------------------------

func test_integer_beyond_2_pow_53_is_rejected_not_wrapped() -> void:
	# F2: 1e20 and 9.3e18 exceed int64 / 2^53; a plain int() cast would wrap or clamp.
	for literal in ["1e20", "9.3e18", "9007199254740993000"]:
		var r := load_text_edit(EC, "\"starting_gold\": 200", "\"starting_gold\": " + literal)
		assert_rejected(r, EC, "starting_gold", "must be <=")
	var r2 := load_text_edit(E, "\"reward\": 5,", "\"reward\": 1e20,")
	assert_rejected(r2, E, "enemies.cultist.reward")
	var r3 := load_text_edit(W, "\"count\": 8", "\"count\": 1e20")
	assert_rejected(r3, W, "waves[0].groups[0].count")


func test_negative_huge_integer_is_rejected() -> void:
	# Every config int has min >= 0, so the lower safe-int bound is only reachable directly.
	var reader := ConfigReader.new("economy.json")
	reader.as_int(-1e20, "starting_gold")
	assert_int(reader.errors.size()).is_equal(1)
	assert_str(reader.errors[0]).starts_with("economy.json: starting_gold: ")


func test_range_must_be_positive() -> void:
	var cases := [
		[E, "enemies.cultist.hp", func(d: Dictionary) -> void: d["enemies"]["cultist"]["hp"] = 0],
		[E, "enemies.cultist.speed", func(d: Dictionary) -> void: d["enemies"]["cultist"]["speed"] = 0],
		[T, "towers.rifleman.levels[0].range",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["levels"][0]["range"] = 0],
		[T, "towers.rifleman.levels[0].fire_interval",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["levels"][0]["fire_interval"] = 0],
		[W, "build_phase_seconds", func(d: Dictionary) -> void: d["build_phase_seconds"] = 0],
		[S, "max", func(d: Dictionary) -> void: d["max"] = 0],
		[S, "madness.damage_multiplier",
			func(d: Dictionary) -> void: d["madness"]["damage_multiplier"] = 0],
		[EC, "lighthouse.hp", func(d: Dictionary) -> void: d["lighthouse"]["hp"] = 0],
	]
	for c: Array in cases:
		assert_rejected(load_json_edit(c[0], c[2]), c[0], c[1], "must be")


func test_range_must_not_be_negative() -> void:
	var cases := [
		[T, "towers.rifleman.cost", func(d: Dictionary) -> void: d["towers"]["rifleman"]["cost"] = -5],
		[T, "towers.elder_sign.levels[0].sanity_reserve",
			func(d: Dictionary) -> void: d["towers"]["elder_sign"]["levels"][0]["sanity_reserve"] = -1],
		[E, "enemies.hybrid.armor", func(d: Dictionary) -> void: d["enemies"]["hybrid"]["armor"] = -5],
		[E, "enemies.shoggoth.horror_drain",
			func(d: Dictionary) -> void: d["enemies"]["shoggoth"]["horror_drain"] = -0.1],
		[W, "waves[0].groups[0].interval",
			func(d: Dictionary) -> void: d["waves"][0]["groups"][0]["interval"] = -1],
		[W, "waves[1].groups[1].delay",
			func(d: Dictionary) -> void: d["waves"][1]["groups"][1]["delay"] = -1],
		[EC, "wave_bonus.base", func(d: Dictionary) -> void: d["wave_bonus"]["base"] = -1],
		[S, "madness.buyout_cost", func(d: Dictionary) -> void: d["madness"]["buyout_cost"] = -1],
	]
	for c: Array in cases:
		assert_rejected(load_json_edit(c[0], c[2]), c[0], c[1], ">= 0")


func test_waves_count_must_be_at_least_one() -> void:
	var r := load_json_edit(W, func(d: Dictionary) -> void: d["waves"][0]["groups"][0]["count"] = 0)
	assert_rejected(r, W, "waves[0].groups[0].count")


func test_upper_bounds() -> void:
	var cases := [
		[EC, "sell_refund_ratio", func(d: Dictionary) -> void: d["sell_refund_ratio"] = 1.5],
		[S, "thresholds.fraying.miss_chance",
			func(d: Dictionary) -> void: d["thresholds"]["fraying"]["miss_chance"] = 2],
		[S, "madness.shot_split.real",
			func(d: Dictionary) -> void: d["madness"]["shot_split"]["real"] = 1.5],
		[S, "start", func(d: Dictionary) -> void: d["start"] = 150],
		[S, "thresholds.lucid.min", func(d: Dictionary) -> void: d["thresholds"]["lucid"]["min"] = 150],
		[S, "madness.restore_sanity", func(d: Dictionary) -> void: d["madness"]["restore_sanity"] = 150],
	]
	for c: Array in cases:
		assert_rejected(load_json_edit(c[0], c[2]), c[0], c[1], "must be <=")


func test_enum_values() -> void:
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["rifleman"]["kind"] = "magic")
	assert_rejected(r, T, "towers.rifleman.kind", "magic")
	var r2 := load_json_edit(S, func(d: Dictionary) -> void: d["madness"]["exit_rule"] = "magic")
	assert_rejected(r2, S, "madness.exit_rule", "magic")


func test_empty_values() -> void:
	assert_rejected(load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["rifleman"]["name"] = ""), T, "towers.rifleman.name", "must not be empty")
	assert_rejected(load_json_edit(W, func(d: Dictionary) -> void: d["waves"] = []),
		W, "waves", "must not be empty")
	assert_rejected(load_json_edit(W, func(d: Dictionary) -> void: d["waves"][0]["groups"] = []),
		W, "waves[0].groups", "must not be empty")
	assert_rejected(load_json_edit(T, func(d: Dictionary) -> void: d["towers"] = {}),
		T, "towers", "must not be empty")
	assert_rejected(load_json_edit(E, func(d: Dictionary) -> void: d["enemies"] = {}),
		E, "enemies", "must not be empty")


# --- unknown fields, ids, references ----------------------------------------

func test_unknown_fields_in_fixed_schema_objects() -> void:
	var cases := [
		[EC, "bonus_gold", func(d: Dictionary) -> void: d["bonus_gold"] = 1],
		[EC, "lighthouse.armor", func(d: Dictionary) -> void: d["lighthouse"]["armor"] = 1],
		[E, "enemies.cultist.hp_max", func(d: Dictionary) -> void: d["enemies"]["cultist"]["hp_max"] = 1],
		[E, "extra", func(d: Dictionary) -> void: d["extra"] = 1],
		[T, "towers.rifleman.levels[0].rnge",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["levels"][0]["rnge"] = 1],
		[T, "towers.rifleman.cost2", func(d: Dictionary) -> void: d["towers"]["rifleman"]["cost2"] = 1],
		[W, "waves[0].groups[0].typ",
			func(d: Dictionary) -> void: d["waves"][0]["groups"][0]["typ"] = "cultist"],
		[W, "waves[0].extra", func(d: Dictionary) -> void: d["waves"][0]["extra"] = 1],
		[S, "thresholds.lucid.mn", func(d: Dictionary) -> void: d["thresholds"]["lucid"]["mn"] = 1],
		[S, "madness.shot_split.other",
			func(d: Dictionary) -> void: d["madness"]["shot_split"]["other"] = 0],
	]
	for c: Array in cases:
		assert_rejected(load_json_edit(c[0], c[2]), c[0], c[1], "unknown field")


func test_invalid_ids() -> void:
	var r := load_json_edit(E, func(d: Dictionary) -> void:
		d["enemies"]["Bad-Id"] = d["enemies"]["cultist"].duplicate(true))
	assert_rejected(r, E, "enemies.Bad-Id", "invalid id")
	var r2 := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["1tower"] = d["towers"]["rifleman"].duplicate(true))
	assert_rejected(r2, T, "towers.1tower", "invalid id")


func test_unknown_enemy_reference_in_waves() -> void:
	var r := load_json_edit(W, func(d: Dictionary) -> void: d["waves"][2]["groups"][0]["type"] = "foo")
	assert_rejected(r, W, "waves[2].groups[0].type", "unknown enemy")
	assert_bool(has_error(r, W, "waves[2].groups[0].type", "foo")).is_true()


func test_reference_to_enemy_that_failed_validation_still_resolves_by_id() -> void:
	# an enemy with a bad field is still a known id: only its own error is reported
	var r := load_json_edit(E, func(d: Dictionary) -> void: d["enemies"]["cultist"]["hp"] = 0)
	assert_rejected(r, E, "enemies.cultist.hp")
	for e in r.errors:
		assert_bool(e.contains("unknown enemy")).is_false()


# --- tower structure --------------------------------------------------------

func test_tower_structure_errors() -> void:
	var cases := [
		[T, "towers.rifleman.levels", "expected 2 levels",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["levels"].pop_back()],
		[T, "towers.rifleman.levels", "expected 2 levels",
			func(d: Dictionary) -> void:
				d["towers"]["rifleman"]["levels"].append(d["towers"]["rifleman"]["levels"][1])],
		[T, "towers.rifleman.levels[0].upgrade_cost", "not allowed on L1",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["levels"][0]["upgrade_cost"] = 10],
		[T, "towers.elder_sign.levels[0].upgrade_sanity_cost", "unknown field",
			func(d: Dictionary) -> void: d["towers"]["elder_sign"]["levels"][0]["upgrade_sanity_cost"] = 1],
		[T, "towers.rifleman.levels[1].upgrade_cost", "missing required field",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["levels"][1].erase("upgrade_cost")],
		[T, "towers.rifleman.branches.a.upgrade_cost", "missing required field",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["branches"]["a"].erase("upgrade_cost")],
		[T, "towers.rifleman.branches.b", "missing required field",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["branches"].erase("b")],
		[T, "towers.rifleman.branches.c", "unknown field",
			func(d: Dictionary) -> void:
				d["towers"]["rifleman"]["branches"]["c"] = d["towers"]["rifleman"]["branches"]["a"]],
		[T, "towers.rifleman.levels[0].fire_interval", "missing required field",
			func(d: Dictionary) -> void: d["towers"]["rifleman"]["levels"][0].erase("fire_interval")],
	]
	for c: Array in cases:
		assert_rejected(load_json_edit(c[0], c[3]), c[0], c[1], c[2])


func test_support_tower_needs_no_fire_interval() -> void:
	# elder_sign has damage 0 and no fire_interval: valid
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).is_true()
	assert_float(r.config.towers["elder_sign"].levels[0].damage).is_equal(0.0)


# --- F3: madness_affected ---------------------------------------------------

func test_mundane_tower_cannot_set_madness_affected_true() -> void:
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["rifleman"]["levels"][0]["madness_affected"] = true)
	assert_rejected(r, T, "towers.rifleman.levels[0].madness_affected", "occult")
	var r2 := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["harpooner"]["branches"]["a"]["madness_affected"] = true)
	assert_rejected(r2, T, "towers.harpooner.branches.a.madness_affected", "occult")


func test_mundane_tower_may_set_madness_affected_false() -> void:
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["rifleman"]["levels"][0]["madness_affected"] = false)
	assert_array(r.errors).is_empty()
	assert_bool(r.config.towers["rifleman"].levels[0].madness_affected).is_false()


# --- F4: traits and effects -------------------------------------------------

func test_unknown_trait_id() -> void:
	var r := load_json_edit(E, func(d: Dictionary) -> void:
		d["enemies"]["deep_one"]["traits"]["pakc"] = {"min": 4, "max": 6})
	assert_rejected(r, E, "enemies.deep_one.traits.pakc", "unknown field")


func test_unknown_trait_param() -> void:
	var r := load_json_edit(E, func(d: Dictionary) -> void:
		d["enemies"]["cultist"]["traits"]["tower_harass"]["stop_secs"] = 2)
	assert_rejected(r, E, "enemies.cultist.traits.tower_harass.stop_secs", "unknown field")


func test_missing_trait_param() -> void:
	var r := load_json_edit(E, func(d: Dictionary) -> void:
		d["enemies"]["cultist"]["traits"]["tower_harass"].erase("stop_seconds"))
	assert_rejected(r, E, "enemies.cultist.traits.tower_harass.stop_seconds", "missing required field")


func test_trait_param_must_be_non_negative_number() -> void:
	var r := load_json_edit(E, func(d: Dictionary) -> void:
		d["enemies"]["cultist"]["traits"]["tower_harass"]["debuff_seconds"] = -1)
	assert_rejected(r, E, "enemies.cultist.traits.tower_harass.debuff_seconds", ">= 0")
	var r2 := load_json_edit(E, func(d: Dictionary) -> void:
		d["enemies"]["cultist"]["traits"]["tower_harass"]["debuff_seconds"] = "5")
	assert_rejected(r2, E, "enemies.cultist.traits.tower_harass.debuff_seconds", "expected number")


func test_pack_trait_bounds() -> void:
	var r := load_json_edit(E, func(d: Dictionary) -> void:
		d["enemies"]["deep_one"]["traits"]["pack"] = {"min": 5, "max": 4})
	assert_rejected(r, E, "enemies.deep_one.traits.pack.max", ">= min")
	var r2 := load_json_edit(E, func(d: Dictionary) -> void:
		d["enemies"]["deep_one"]["traits"]["pack"]["min"] = 0)
	assert_rejected(r2, E, "enemies.deep_one.traits.pack.min")
	var r3 := load_json_edit(E, func(d: Dictionary) -> void:
		d["enemies"]["deep_one"]["traits"]["pack"]["max"] = 5.5)
	assert_rejected(r3, E, "enemies.deep_one.traits.pack.max", "expected integer")


func test_unknown_effect_key() -> void:
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["rifleman"]["branches"]["a"]["effects"]["crit_chanse"] = 0.1)
	assert_rejected(r, T, "towers.rifleman.branches.a.effects.crit_chanse", "unknown field")


func test_effect_value_bounds() -> void:
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["elder_sign"]["levels"][0]["effects"]["slow"] = 1.5)
	assert_rejected(r, T, "towers.elder_sign.levels[0].effects.slow", "must be <= 1")
	var r2 := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["rifleman"]["branches"]["a"]["effects"]["crit_chance"] = 1.5)
	assert_rejected(r2, T, "towers.rifleman.branches.a.effects.crit_chance", "must be <= 1")
	var r3 := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["rifleman"]["branches"]["b"]["effects"]["shooters"] = -1)
	assert_rejected(r3, T, "towers.rifleman.branches.b.effects.shooters", ">= 0")


# --- sanity cross-field rules -----------------------------------------------

func test_threshold_mins_must_strictly_decrease() -> void:
	var r := load_json_edit(S, func(d: Dictionary) -> void: d["thresholds"]["whispers"]["min"] = 80)
	assert_rejected(r, S, "thresholds.whispers.min", "thresholds.lucid.min")
	var r2 := load_json_edit(S, func(d: Dictionary) -> void: d["thresholds"]["fraying"]["min"] = 40)
	assert_rejected(r2, S, "thresholds.fraying.min", "thresholds.whispers.min")


func test_madness_threshold_min_must_be_zero() -> void:
	var r := load_json_edit(S, func(d: Dictionary) -> void: d["thresholds"]["madness"]["min"] = 0.5)
	assert_rejected(r, S, "thresholds.madness.min", "must be 0")


func test_all_four_threshold_states_required() -> void:
	for state in ["lucid", "whispers", "fraying", "madness"]:
		var r := load_json_edit(S, func(d: Dictionary) -> void: d["thresholds"].erase(state))
		assert_rejected(r, S, "thresholds." + state, "missing required field")


func test_threshold_order_check_skips_mins_that_already_failed() -> void:
	# whispers.min is a string: one type error, no bogus ordering error derived from it
	var r := load_json_edit(S, func(d: Dictionary) -> void: d["thresholds"]["whispers"]["min"] = "x")
	assert_rejected(r, S, "thresholds.whispers.min", "expected number")
	assert_bool(has_error(r, S, "thresholds.whispers.min", "must be <")).is_false()
	assert_bool(has_error(r, S, "thresholds.fraying.min", "must be <")).is_false()


func test_shot_split_must_sum_to_one() -> void:
	var r := load_json_edit(S, func(d: Dictionary) -> void: d["madness"]["shot_split"]["empty"] = 0.05)
	assert_rejected(r, S, "madness.shot_split", "sum to 1")


func test_shot_split_missing_part_reports_only_the_missing_field() -> void:
	var r := load_json_edit(S, func(d: Dictionary) -> void: d["madness"]["shot_split"].erase("fake"))
	assert_rejected(r, S, "madness.shot_split.fake", "missing required field")
	assert_bool(has_error(r, S, "madness.shot_split", "sum to 1")).is_false()


# --- LT-13: restore_sanity 0 cannot exit madness ------------------------------------

func test_restore_sanity_zero_is_rejected_when_the_exit_rule_restores() -> void:
	for rule in ["buyout", "auto_restore"]:
		var r := load_json_edit(S, func(d: Dictionary) -> void:
			d["madness"]["exit_rule"] = rule
			d["madness"]["restore_sanity"] = 0)
		assert_rejected(r, S, "madness.restore_sanity", rule)
		assert_int(r.errors.size()).is_equal(1)


func test_restore_sanity_zero_is_accepted_for_the_permanent_rule() -> void:
	var r := load_json_edit(S, func(d: Dictionary) -> void:
		d["madness"]["exit_rule"] = "permanent"
		d["madness"]["restore_sanity"] = 0)
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()


func test_restore_sanity_above_zero_is_accepted_for_every_exit_rule() -> void:
	for rule in ["permanent", "buyout", "auto_restore"]:
		var r := load_json_edit(S, func(d: Dictionary) -> void:
			d["madness"]["exit_rule"] = rule
			d["madness"]["restore_sanity"] = 0.5)
		assert_bool(r.ok).override_failure_message("%s: %s" % [rule, "\n".join(r.errors)]) \
			.is_true()


func test_invalid_exit_rule_with_restore_zero_reports_only_the_exit_rule() -> void:
	var r := load_json_edit(S, func(d: Dictionary) -> void:
		d["madness"]["exit_rule"] = "magic"
		d["madness"]["restore_sanity"] = 0)
	assert_rejected(r, S, "madness.exit_rule", "magic")
	assert_int(r.errors.size()).is_equal(1)
	assert_bool(has_error(r, S, "madness.restore_sanity")).is_false()


func test_missing_exit_rule_with_restore_zero_reports_only_the_missing_field() -> void:
	var r := load_json_edit(S, func(d: Dictionary) -> void:
		d["madness"].erase("exit_rule")
		d["madness"]["restore_sanity"] = 0)
	assert_rejected(r, S, "madness.exit_rule", "missing required field")
	assert_int(r.errors.size()).is_equal(1)


# --- collecting ---------------------------------------------------------------

func test_errors_from_all_files_are_collected_in_file_order() -> void:
	var dir := make_dir()
	edit(dir, E, func(d: Dictionary) -> void: d["enemies"]["cultist"]["hp"] = 0)
	edit(dir, T, func(d: Dictionary) -> void: d["towers"]["rifleman"]["cost"] = -1)
	edit(dir, W, func(d: Dictionary) -> void: d["build_phase_seconds"] = 0)
	edit(dir, EC, func(d: Dictionary) -> void: d.erase("starting_gold"))
	edit(dir, S, func(d: Dictionary) -> void: d["max"] = 0)
	var r := GameConfig.load_from_dir(dir)
	assert_bool(r.ok).is_false()
	assert_object(r.config).is_null()
	assert_int(r.errors.size()).is_equal(5)
	var order: Array[String] = []
	for e in r.errors:
		order.append(e.get_slice(":", 0))
	assert_array(order).contains_exactly([E, T, W, EC, S])


func test_several_errors_in_one_file_are_all_reported() -> void:
	var r := load_json_edit(E, func(d: Dictionary) -> void:
		d["enemies"]["cultist"]["hp"] = 0
		d["enemies"]["hybrid"]["speed"] = -1
		d["enemies"]["deep_one"].erase("reward")
		d["enemies"]["shoggoth"]["bogus"] = 1)
	assert_rejected(r, E, "enemies.cultist.hp")
	assert_bool(has_error(r, E, "enemies.hybrid.speed")).is_true()
	assert_bool(has_error(r, E, "enemies.deep_one.reward")).is_true()
	assert_bool(has_error(r, E, "enemies.shoggoth.bogus")).is_true()
	assert_int(r.errors.size()).is_equal(4)


func test_bad_file_does_not_stop_other_files_being_checked() -> void:
	var dir := make_dir()
	write_file(dir, T, "not json")
	edit(dir, S, func(d: Dictionary) -> void: d["max"] = 0)
	var r := GameConfig.load_from_dir(dir)
	assert_bool(has_error(r, T, "", "invalid JSON")).is_true()
	assert_bool(has_error(r, S, "max")).is_true()


# --- F1: duplicate keys through the loader ----------------------------------

func test_duplicate_field_in_tower() -> void:
	var r := load_text_edit(T, "\"cost\": 50,", "\"cost\": 50, \"cost\": 60,")
	assert_rejected(r, T, "towers.rifleman.cost", "duplicate key")


func test_duplicate_enemy_id() -> void:
	var r := load_text_edit(E, "\"enemies\": {",
		"\"enemies\": { \"hybrid\": {\"name\": \"x\", \"hp\": 1, \"speed\": 1, \"armor\": 0, "
		+ "\"leak_damage\": 1, \"reward\": 1},")
	assert_rejected(r, E, "enemies.hybrid", "duplicate key")


func test_duplicate_tower_id() -> void:
	var r := load_text_edit(T, "\"towers\": {",
		"\"towers\": { \"harpooner\": {\"name\": \"x\"},")
	assert_rejected(r, T, "towers.harpooner", "duplicate key")


func test_duplicate_key_inside_array_element() -> void:
	var r := load_text_edit(W, "{ \"type\": \"hybrid\", \"count\": 6, \"interval\": 1.8 }",
		"{ \"type\": \"hybrid\", \"count\": 6, \"count\": 7, \"interval\": 1.8 }")
	assert_rejected(r, W, "waves[3].groups[0].count", "duplicate key")


func test_duplicate_key_in_flat_files() -> void:
	assert_rejected(load_text_edit(EC, "\"starting_gold\": 200,",
		"\"starting_gold\": 200, \"starting_gold\": 300,"), EC, "starting_gold", "duplicate key")
	assert_rejected(load_text_edit(S, "\"start\": 100,", "\"start\": 100, \"start\": 50,"),
		S, "start", "duplicate key")


func test_repeated_keys_in_different_objects_are_not_duplicates() -> void:
	# the real data repeats range/damage/upgrade_cost/name across levels, branches, towers
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).is_true()
	for e in r.errors:
		assert_bool(e.contains("duplicate")).is_false()
