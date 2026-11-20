class_name ConfigIdCheckTest
extends GdUnitTestSuite
## LT-102 B8 (docs/design/LT-102-portability-core.md §1 D-3): ConfigReader.is_valid_id, the
## character loop that replaced RegEx("^[a-z][a-z0-9_]*$"). Non-empty, first char a-z, the
## rest a-z, 0-9 or "_". Deliberately stricter than PCRE on one point: "abc\n" is rejected
## (PCRE's "$" matched before a final newline).


func test_ids_matching_the_pattern_are_accepted() -> void:
	for id: String in ["a", "z", "a_1", "abc", "tower_9", "a__", "z09_", "a0123456789"]:
		assert_bool(ConfigReader.is_valid_id(id)).override_failure_message(
			"rejected valid id %s" % id.c_escape()).is_true()


func test_ids_outside_the_pattern_are_rejected() -> void:
	for id: String in ["", "Bad-Id", "1tower", "_a", "é", "aé", "A", "aB", "a-b", "a b", "a.b",
			"0", "9a",
			# the code points next to each range: / : ` { @ [ ^
			"a/", "a:", "`a", "{a", "a`", "a{", "@a", "[a", "a^", "a@", "a[",
			# look-alikes: fullwidth a, Kelvin sign (folds to k), Arabic-Indic zero
			"ａ", "aK", "a٠"]:
		assert_bool(ConfigReader.is_valid_id(id)).override_failure_message(
			"accepted invalid id %s" % id.c_escape()).is_false()


func test_whitespace_and_a_trailing_newline_are_rejected() -> void:
	# "abc\n" is the deliberate change from the PCRE pattern (D-3).
	for id: String in ["abc\n", "a\n", "abc\n\n", "\nabc", "ab\ncd", "a\r", "a\r\n", "a\t",
			" a", "a ", "a "]:
		assert_bool(ConfigReader.is_valid_id(id)).override_failure_message(
			"accepted invalid id %s" % id.c_escape()).is_false()


func test_check_id_reports_the_pattern_text_and_returns_false() -> void:
	var r := ConfigReader.new("towers.json")
	assert_bool(r.check_id("tower_1", "towers.tower_1")).is_true()
	assert_array(r.errors).is_empty()
	assert_bool(r.check_id("abc\n", "towers.abc")).is_false()
	assert_bool(r.check_id("Bad-Id", "towers.Bad-Id")).is_false()
	assert_array(r.errors).contains_exactly([
		"towers.json: towers.abc: invalid id \"abc\n\" (expected ^[a-z][a-z0-9_]*$)",
		"towers.json: towers.Bad-Id: invalid id \"Bad-Id\" (expected ^[a-z][a-z0-9_]*$)",
	])
	assert_str(ConfigReader.ID_PATTERN).is_equal("^[a-z][a-z0-9_]*$")
