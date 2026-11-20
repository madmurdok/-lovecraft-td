extends ConfigTestBase
## LT-100: the config section registry (GameConfig._sections) and the cross-file checks
## that run after it. Pins the load = error order, the drops check running after every
## section, the required-file rule and the enemies -> waves dependency.
##
## Optional rows (required = false): no shipped row is optional, so those tests inject one
## through ConfigLoader.load_dir's `sections` argument (passed on to GameConfig.from_dicts).

const E := "enemies.json"
const T := "towers.json"
const W := "waves.json"
const EC := "economy.json"
const S := "sanity.json"
const M := "map.json"


func _registry_files() -> Array[String]:
	var files: Array[String] = []
	for row: Array in GameConfig._sections():
		files.append(row[0])
	return files


func _file_order(r: ConfigLoadResult) -> Array[String]:
	var order: Array[String] = []
	for e in r.errors:
		order.append(e.get_slice(":", 0))
	return order


func test_registry_lists_every_config_file_once_in_load_order() -> void:
	assert_array(_registry_files()).contains_exactly([E, T, W, EC, S, M])


func test_errors_follow_registry_order_across_all_six_files() -> void:
	# Each file broken at its root: exactly one error per file, so the order of the
	# errors is the order the registry loads the files in.
	var dir := make_dir()
	for f: String in FILES:
		write_file(dir, f, "[1]")
	var r := ConfigLoader.load_dir(dir)
	assert_bool(r.ok).is_false()
	assert_object(r.config).is_null()
	assert_array(_file_order(r)).contains_exactly(_registry_files())
	for e in r.errors:
		assert_bool(e.contains("root must be an object")).override_failure_message(
			"unexpected error: %s" % e).is_true()


func test_drops_cross_check_runs_after_every_section() -> void:
	# The unknown-relic error is reported in enemies.json but comes from the cross-file
	# check, which runs after sanity.json and map.json are loaded.
	var dir := make_dir()
	edit(dir, E, func(d: Dictionary) -> void: d["enemies"]["cultist"]["drops"]["gem"] = 1)
	edit(dir, T, func(d: Dictionary) -> void: d["towers"]["rifleman"]["cost"] = -1)
	edit(dir, S, func(d: Dictionary) -> void: d["max"] = 0)
	write_file(dir, M, "[1]")
	var r := ConfigLoader.load_dir(dir)
	assert_bool(r.ok).is_false()
	assert_array(_file_order(r)).contains_exactly([T, S, M, E])
	assert_bool(r.errors[r.errors.size() - 1].begins_with(
		"enemies.json: enemies.cultist.drops.gem: unknown relic kind")).override_failure_message(
		"last error is not the drops check:\n%s" % "\n".join(r.errors)).is_true()


func test_drops_cross_check_skipped_when_economy_is_broken() -> void:
	var dir := make_dir()
	edit(dir, E, func(d: Dictionary) -> void: d["enemies"]["cultist"]["drops"]["gem"] = 1)
	write_file(dir, EC, "[1]")
	var r := ConfigLoader.load_dir(dir)
	assert_array(r.errors).contains_exactly(
		["economy.json: root must be an object, got array"])


func test_missing_required_file_keeps_old_error_text() -> void:
	for f: String in _registry_files():
		var dir := make_dir()
		DirAccess.remove_absolute(dir.path_join(f))
		var r := ConfigLoader.load_dir(dir)
		assert_bool(r.ok).is_false()
		assert_object(r.config).is_null()
		assert_array(r.errors).contains_exactly(
			["%s: file not found (%s)" % [f, dir.path_join(f)]])


func test_enemies_without_id_map_adds_no_waves_errors() -> void:
	# enemies.json readable but its "enemies" block is not an object: the waves parser
	# gets no enemy ids and skips its cross-references instead of failing on them.
	var r := load_json_edit(E, func(d: Dictionary) -> void: d["enemies"] = [1])
	assert_bool(r.ok).is_false()
	assert_array(r.errors).is_not_empty()
	for e in r.errors:
		assert_bool(e.begins_with(E + ": ")).override_failure_message(
			"error outside enemies.json: %s" % e).is_true()


func test_missing_enemies_adds_no_waves_errors() -> void:
	var r := load_edited(func(dir: String) -> void: DirAccess.remove_absolute(dir.path_join(E)))
	assert_int(r.errors.size()).is_equal(1)
	assert_bool(has_error(r, E, "", "not found")).is_true()


func test_invalid_enemy_entry_still_resolves_for_waves() -> void:
	# Waves resolve enemy references against every listed id, valid or not: a broken
	# cultist is reported once, in enemies.json, not again as an unknown enemy in waves.
	var r := load_json_edit(E, func(d: Dictionary) -> void: d["enemies"]["cultist"]["hp"] = 0)
	assert_array(r.errors).has_size(1)
	assert_bool(has_error(r, E, "enemies.cultist.hp")).is_true()


func test_non_object_enemy_entry_still_resolves_for_waves() -> void:
	# Same rule when the entry is not even an object (it never becomes an EnemyDef).
	var r := load_json_edit(E, func(d: Dictionary) -> void: d["enemies"]["cultist"] = 1)
	assert_array(r.errors).has_size(1)
	assert_bool(has_error(r, E, "enemies.cultist")).is_true()


# --- LT-102 F3: a roots / read_errors key with no registry row ---------------------------

func test_a_key_naming_no_registry_file_is_an_error_after_the_section_errors() -> void:
	var roots := parsed_roots()
	roots[T]["towers"]["rifleman"]["cost"] = -1
	roots[E]["enemies"]["cultist"]["drops"]["gem"] = 1  # a cross-check error
	roots["unknown.json"] = {}
	var r := GameConfig.from_dicts(roots, {"bogus.json": [["", "file not found (x)"]]})
	assert_bool(r.ok).is_false()
	assert_object(r.config).is_null()
	assert_array(_file_order(r)).override_failure_message("\n".join(r.errors)) \
		.contains_exactly([T, "unknown.json", "bogus.json", E])
	assert_str(r.errors[1]).is_equal("unknown.json: not a config file (no registry row)")
	assert_str(r.errors[2]).is_equal("bogus.json: not a config file (no registry row)")
	assert_bool(r.errors[3].contains("unknown relic kind")).is_true()


func test_a_stray_key_is_reported_once_and_alone_on_valid_data() -> void:
	var roots := parsed_roots()
	roots["Towers.json"] = {}
	var r := GameConfig.from_dicts(roots, {"Towers.json": [["", "x"]]})
	assert_bool(r.ok).is_false()
	assert_array(r.errors).contains_exactly(
		["Towers.json: not a config file (no registry row)"])
	var r2 := GameConfig.from_dicts(parsed_roots().merged({7: {}}))
	assert_array(r2.errors).contains_exactly(["7: not a config file (no registry row)"])


# --- optional rows (injected through load_dir's `sections`) -------------------------

const CREW := "crew.json"


## The shipped rows plus one optional crew.json row whose parser records each call in
## `calls` and requires a "size" field.
func _rows_with_crew(calls: Dictionary) -> Array[Array]:
	var rows := GameConfig._sections()
	var parse := func(r: ConfigReader, root: Dictionary, _c: GameConfig,
			_ctx: Dictionary) -> void:
		calls["n"] = int(calls.get("n", 0)) + 1
		calls["root"] = root
		if not root.has("size"):
			r.error("size", "missing required field")
	rows.append([CREW, parse, false])
	return rows


func test_optional_row_absent_is_off_without_error() -> void:
	var calls := {}
	var r := ConfigLoader.load_dir(make_dir(), _rows_with_crew(calls))
	assert_array(r.errors).is_empty()
	assert_bool(r.ok).is_true()
	assert_object(r.config).is_not_null()
	assert_bool(calls.has("n")).override_failure_message(
		"optional parser was called with its file absent").is_false()


func test_optional_row_present_is_parsed_with_no_other_change() -> void:
	var calls := {}
	var dir := make_dir()
	write_file(dir, CREW, "{\"size\": 3}")
	var r := ConfigLoader.load_dir(dir, _rows_with_crew(calls))
	assert_array(r.errors).is_empty()
	assert_bool(r.ok).is_true()
	assert_int(calls.get("n", 0)).is_equal(1)
	assert_int(int(calls["root"]["size"])).is_equal(3)


func test_optional_row_present_but_invalid_json_reports_its_error() -> void:
	var calls := {}
	var dir := make_dir()
	write_file(dir, CREW, "nope")
	var r := ConfigLoader.load_dir(dir, _rows_with_crew(calls))
	assert_bool(r.ok).is_false()
	assert_object(r.config).is_null()
	assert_int(r.errors.size()).is_equal(1)
	assert_bool(has_error(r, CREW, "", "invalid JSON")).is_true()
	assert_bool(calls.has("n")).is_false()


func test_optional_row_present_but_bad_field_reports_its_error() -> void:
	var calls := {}
	var dir := make_dir()
	write_file(dir, CREW, "{\"crew\": 1}")
	var r := ConfigLoader.load_dir(dir, _rows_with_crew(calls))
	assert_bool(r.ok).is_false()
	assert_array(r.errors).contains_exactly(["crew.json: size: missing required field"])
	assert_int(calls.get("n", 0)).is_equal(1)
