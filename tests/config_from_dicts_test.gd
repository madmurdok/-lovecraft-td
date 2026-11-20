class_name ConfigFromDictsTest
extends ConfigTestBase
## LT-102 (docs/design/LT-102-portability-core.md §1 D-2, §7 B2-B4): GameConfig.from_dicts,
## the validation half of a config load, fed roots parsed in memory (no ConfigLoader, as a
## port would feed it). The file IO half is ConfigLoader's (config_reject / config_registry).

const E := "enemies.json"
const T := "towers.json"
const EC := "economy.json"
const S := "sanity.json"


func _file_order(r: ConfigLoadResult) -> Array[String]:
	var order: Array[String] = []
	for e in r.errors:
		order.append(e.get_slice(":", 0))
	return order


# --- B2: same config as the loader --------------------------------------------------------

func test_from_dicts_on_roots_parsed_in_memory_plays_like_load_dir() -> void:
	var loaded := ConfigLoader.load_dir("res://data")
	var built := GameConfig.from_dicts(parsed_roots("res://data"))
	assert_array(loaded.errors).is_empty()
	assert_array(built.errors).is_empty()
	assert_bool(built.ok).is_true()
	assert_object(built.config).is_not_null()
	var want := SimNoTreeLoop.digest(SimNoTreeLoop.play(loaded.config, 5))
	var got := SimNoTreeLoop.digest(SimNoTreeLoop.play(built.config, 5))
	assert_str(got).is_equal(want)


# --- B3: read errors lead their file's errors, files in registry order --------------------

func test_read_errors_lead_the_parse_errors_of_their_file() -> void:
	var roots := parsed_roots()
	roots[T]["towers"]["rifleman"]["cost"] = -1
	var r := GameConfig.from_dicts(roots,
		{T: [["towers.rifleman.cost", "duplicate key"]]})
	assert_bool(r.ok).is_false()
	assert_object(r.config).is_null()
	assert_int(r.errors.size()).override_failure_message("\n".join(r.errors)).is_equal(2)
	assert_str(r.errors[0]).is_equal("towers.json: towers.rifleman.cost: duplicate key")
	assert_bool(r.errors[1].begins_with("towers.json: towers.rifleman.cost: ")).is_true()
	assert_bool(r.errors[1].contains("duplicate key")).is_false()


func test_read_errors_keep_registry_file_order() -> void:
	# A read error of a later file (economy) comes after a parse error of an earlier one
	# (enemies), and a read error with no root replaces "missing".
	var roots := parsed_roots()
	roots[E]["enemies"]["cultist"]["hp"] = 0
	roots.erase(S)
	var r := GameConfig.from_dicts(roots, {
		S: [["", "invalid JSON at line 1: x"]],
		EC: [["starting_gold", "duplicate key"]],
	})
	assert_array(_file_order(r)).contains_exactly([E, EC, S])
	assert_str(r.errors[1]).is_equal("economy.json: starting_gold: duplicate key")
	assert_str(r.errors[2]).is_equal("sanity.json: invalid JSON at line 1: x")


# --- B4: root type, missing, optional -----------------------------------------------------

func test_a_root_that_is_not_an_object_is_rejected() -> void:
	for root: Variant in [[1], null, "x", 3.0]:
		var roots := parsed_roots()
		roots[T] = root
		var r := GameConfig.from_dicts(roots)
		assert_rejected(r, T, "", "root must be an object, got %s" % ConfigReader.type_name(root))
		assert_int(r.errors.size()).override_failure_message("\n".join(r.errors)).is_equal(1)


func test_a_required_file_absent_without_read_error_is_missing() -> void:
	var roots := parsed_roots()
	roots.erase(T)
	var r := GameConfig.from_dicts(roots)
	assert_bool(r.ok).is_false()
	assert_object(r.config).is_null()
	assert_array(r.errors).contains_exactly(["towers.json: missing"])


func test_a_required_file_absent_with_a_read_error_is_not_also_missing() -> void:
	var roots := parsed_roots()
	roots.erase(T)
	var r := GameConfig.from_dicts(roots, {T: [["", "file not found (x/towers.json)"]]})
	assert_array(r.errors).contains_exactly(["towers.json: file not found (x/towers.json)"])


func test_no_roots_at_all_is_missing_for_every_required_file() -> void:
	var r := GameConfig.from_dicts({})
	assert_bool(r.ok).is_false()
	var want: Array[String] = []
	for entry: Array in GameConfig.section_files():
		if entry[1]:
			want.append("%s: missing" % entry[0])
	assert_array(r.errors).contains_exactly(want)


func test_an_optional_file_absent_is_off_without_error() -> void:
	var calls := {}
	var rows := GameConfig._sections()
	var parse := func(_r: ConfigReader, _root: Dictionary, _c: GameConfig,
			_ctx: Dictionary) -> void:
		calls["n"] = 1
	rows.append(["crew.json", parse, false])
	var r := GameConfig.from_dicts(parsed_roots(), {}, rows)
	assert_array(r.errors).is_empty()
	assert_bool(r.ok).is_true()
	assert_object(r.config).is_not_null()
	assert_bool(calls.has("n")).override_failure_message(
		"optional parser ran with no root").is_false()
	# The same row with a root is parsed: the test above is not vacuous.
	var roots := parsed_roots()
	roots["crew.json"] = {}
	assert_bool(GameConfig.from_dicts(roots, {}, rows).ok).is_true()
	assert_bool(calls.has("n")).is_true()
