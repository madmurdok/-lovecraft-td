class_name EnemyTraitsTest
extends ConfigTestBase
## LT-97 (LT-96 D2): every enemy trait in the data does something or is flagged pending.
## "Read by the sim" is a trait with a hook (LT-106: the sim calls hooks at fixed points), or
## a scan of sim/ code outside sim/defs/ and sim/core/traits/ (the schema, parsers and trait
## files) for the trait id as a string literal or its class name, comments stripped
## (SimBoundaryTest._code_lines). A scan, not a maintained list: a trait added to data and
## TraitCatalog without a reader fails here unless it is pending(), and a list could be
## edited to pass without wiring anything.
## LT-98: no roster pins here; every test iterates the live data or edits a copy of it.

const E := "enemies.json"
const SIM_DIR := "res://sim"
const DEFS_DIR := "res://sim/defs/"
const TRAITS_DIR := "res://sim/core/traits/"


## Trait ids that have a hook, or that some sim/ file outside sim/defs/ and sim/core/traits/
## names in code as a string literal or by the trait's class name.
func _sim_read_traits(ids: Array) -> Dictionary:
	var scan := SimBoundaryTest.new()
	var read := {}
	var names := {}
	for id: String in ids:
		var tr := TraitCatalog.get_trait(id)
		if tr != null and tr.hooks() != 0:
			read[id] = true
		if tr != null:
			names[id] = (tr.get_script() as Script).get_global_name()
	var scanned := 0
	for f in scan._gd_files(SIM_DIR):
		if f.begins_with(DEFS_DIR) or f.begins_with(TRAITS_DIR):
			continue
		scanned += 1
		for entry: Array in scan._code_lines(FileAccess.get_file_as_string(f), true):
			for id: String in ids:
				var line := entry[1] as String
				if line.contains("\"%s\"" % id) or (names.has(id)
						and RegEx.create_from_string("\\b%s\\b" % names[id]).search(line) != null):
					read[id] = true
	scan.free()
	assert_int(scanned).override_failure_message("the scan walked sim/").is_greater(10)
	return read


## Trait ids used by enemies in the shipped data/enemies.json (raw JSON, so an id the schema
## does not know shows up here too).
func _data_trait_ids() -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + E))
	assert_bool(data is Dictionary).is_true()
	var ids := {}
	for enemy_id: String in data["enemies"]:
		var traits: Variant = data["enemies"][enemy_id].get("traits", {})
		for t: String in traits:
			ids[t] = true
	return ids.keys()


func _first_enemy_id(d: Dictionary) -> String:
	return d["enemies"].keys()[0]


func test_every_data_trait_is_read_by_the_sim_or_pending() -> void:
	var ids := _data_trait_ids()
	assert_array(ids).is_not_empty()
	var read := _sim_read_traits(ids)
	for t: String in ids:
		assert_bool(read.has(t) or TraitCatalog.pending_ids().has(t)).override_failure_message(
			"enemies.json trait '%s' is neither read in sim/ (outside sim/defs/) nor in "
			% t + "TraitCatalog.pending_ids()").is_true()


func test_every_schema_trait_is_read_by_the_sim_or_pending() -> void:
	var ids := TraitCatalog.ids()
	var read := _sim_read_traits(ids)
	for t: String in ids:
		assert_bool(read.has(t) or TraitCatalog.pending_ids().has(t)).override_failure_message(
			"TraitCatalog '%s' is neither read in sim/ (outside sim/defs/) nor pending" % t
		).is_true()


## The other direction: a pending trait has no reader yet, and the task that wires one
## makes it non-pending (its trait file's pending()).
func test_pending_traits_are_known_and_have_no_sim_reader() -> void:
	assert_array(Array(TraitCatalog.pending_ids())).is_not_empty()
	var read := _sim_read_traits(Array(TraitCatalog.pending_ids()))
	for t: String in TraitCatalog.pending_ids():
		assert_bool(TraitCatalog.has(t)).override_failure_message(
			"pending trait '%s' is not in TraitCatalog" % t).is_true()
		assert_bool(read.has(t)).override_failure_message(
			"pending trait '%s' is read in sim/: make it non-pending" % t).is_false()


func test_boss_is_accepted_as_a_flag_trait() -> void:
	var picked := [""]
	var r := load_json_edit(E, func(d: Dictionary) -> void:
		picked[0] = _first_enemy_id(d)
		d["enemies"][picked[0]]["traits"] = {"boss": {}})
	assert_array(r.errors).is_empty()
	assert_bool(r.ok).is_true()
	var e: EnemyDef = r.config.enemies[picked[0]]
	assert_array(e.traits.keys()).contains_exactly(["boss"])
	assert_dict(e.traits["boss"]).is_empty()
	assert_bool(e.has_pending_traits()).is_false()


func test_boss_takes_no_parameters() -> void:
	var picked := [""]
	var r := load_json_edit(E, func(d: Dictionary) -> void:
		picked[0] = _first_enemy_id(d)
		d["enemies"][picked[0]]["traits"] = {"boss": {"hp": 1}})
	assert_rejected(r, E, "enemies.%s.traits.boss.hp" % picked[0], "unknown field")


## Each pending trait still parses with its schema params, is kept in `traits` and flags the
## enemy; the same enemy without it is not flagged.
func test_pending_traits_load_and_are_flagged() -> void:
	for t: String in TraitCatalog.pending_ids():
		var params := {}
		for key: String in TraitCatalog.get_trait(t).params():
			params[key] = 1
		var picked := [""]
		var r := load_json_edit(E, func(d: Dictionary) -> void:
			picked[0] = _first_enemy_id(d)
			d["enemies"][picked[0]]["traits"] = {t: params})
		assert_array(r.errors).override_failure_message(t).is_empty()
		var e: EnemyDef = r.config.enemies[picked[0]]
		assert_array(e.traits.keys()).override_failure_message(t).contains_exactly([t])
		for key: String in params:
			assert_float(e.traits[t][key]).override_failure_message(t + "." + key).is_equal(1.0)
		assert_bool(e.has_pending_traits()).override_failure_message(t).is_true()
	var r0 := load_json_edit(E, func(d: Dictionary) -> void:
		d["enemies"][_first_enemy_id(d)]["traits"] = {})
	assert_array(r0.errors).is_empty()
	for id: String in r0.config.enemies:
		var e0: EnemyDef = r0.config.enemies[id]
		if e0.traits.is_empty():
			assert_bool(e0.has_pending_traits()).override_failure_message(id).is_false()


## Over the live roster: an enemy is flagged exactly when it carries a pending trait.
func test_has_pending_traits_matches_the_pending_list_for_every_enemy() -> void:
	var result := ConfigLoader.load_dir("res://data")
	assert_bool(result.ok).is_true()
	for id: String in result.config.enemies:
		var e: EnemyDef = result.config.enemies[id]
		var expected := false
		for t: String in e.traits:
			if TraitCatalog.pending_ids().has(t):
				expected = true
		assert_bool(e.has_pending_traits()).override_failure_message(id).is_equal(expected)
