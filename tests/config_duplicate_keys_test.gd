class_name ConfigDuplicateKeysTest
extends GdUnitTestSuite
## LT-3/F1: GameConfig.find_duplicate_keys, a text scan (JSON.parse keeps the last duplicate).


func _dups(text: String) -> Array[String]:
	return GameConfig.find_duplicate_keys(text)


# --- true positives ---------------------------------------------------------

func test_top_level_duplicate() -> void:
	assert_array(_dups('{"a": 1, "a": 2}')).contains_exactly(["a"])


func test_nested_duplicate_has_full_path() -> void:
	assert_array(_dups('{"x": {"y": {"k": 1, "k": 2}}}')).contains_exactly(["x.y.k"])


func test_duplicate_inside_array_element_has_index_path() -> void:
	assert_array(_dups('{"arr": [{"k": 1}, {"k": 1, "k": 2}]}')).contains_exactly(["arr[1].k"])


func test_duplicate_object_id_reports_the_object_path() -> void:
	assert_array(_dups('{"enemies": {"hybrid": {"hp": 1}, "hybrid": {"hp": 2}}}')) \
		.contains_exactly(["enemies.hybrid"])


func test_key_and_colon_separated_by_whitespace_and_newlines() -> void:
	assert_array(_dups('{"a"\n  :1,\n"a"\t: 2}')).contains_exactly(["a"])


func test_every_duplicate_is_reported() -> void:
	assert_array(_dups('{"a": 1, "a": 2, "b": {"c": 1, "c": 2}}')) \
		.contains_exactly_in_any_order(["a", "b.c"])


func test_escaped_backslash_before_closing_quote_does_not_hide_a_duplicate() -> void:
	# value is the one-character string \ ; the quote after it closes the string
	assert_array(_dups('{"a": "\\\\", "a": 1}')).contains_exactly(["a"])


# --- false positives that must NOT be flagged -------------------------------

func test_same_key_in_array_elements_is_not_a_duplicate() -> void:
	assert_array(_dups('{"levels": [{"cost": 1}, {"cost": 2}, {"cost": 3}]}')).is_empty()


func test_same_key_in_sibling_objects_is_not_a_duplicate() -> void:
	assert_array(_dups('{"a": {"cost": 1}, "b": {"cost": 2}}')).is_empty()


func test_same_key_in_parent_and_child_is_not_a_duplicate() -> void:
	assert_array(_dups('{"cost": 1, "x": {"cost": 2, "y": {"cost": 3}}}')).is_empty()


func test_key_reappearing_after_nested_object_closes_is_only_flagged_if_same_level() -> void:
	assert_array(_dups('{"a": {"x": 1}, "x": 2}')).is_empty()
	assert_array(_dups('{"x": {"x": 1}}')).is_empty()


func test_same_key_in_sibling_nested_arrays_of_objects() -> void:
	assert_array(_dups('{"a": [[{"k": 1}], [{"k": 2}]], "b": [{"k": 3}]}')).is_empty()


func test_string_values_equal_to_a_key_are_not_keys() -> void:
	assert_array(_dups('{"a": "b", "b": "a", "list": ["a", "a", "b"]}')).is_empty()


func test_key_like_text_inside_string_value_is_ignored() -> void:
	assert_array(_dups('{"a": "x \\"k\\": 1, \\"k\\": 2"}')).is_empty()


func test_braces_and_brackets_inside_string_values_do_not_change_nesting() -> void:
	assert_array(_dups('{"a": "{ \\"k\\": 1 , \\"k\\": 2 }", "b": "]]}}", "c": 1}')).is_empty()
	# and a real duplicate after such a string is still found at the right level
	assert_array(_dups('{"a": "}}", "c": 1, "c": 2}')).contains_exactly(["c"])


func test_escaped_quote_inside_key_does_not_end_the_key() -> void:
	assert_array(_dups('{"a\\"b": 1, "a": 2}')).is_empty()


func test_commas_inside_strings_do_not_advance_array_index() -> void:
	# the duplicate is in element 1; commas in the string in element 0 must not shift the index
	assert_array(_dups('{"arr": ["a, b, c", {"k": 1, "k": 2}]}')).contains_exactly(["arr[1].k"])


func test_valid_documents_have_no_duplicates() -> void:
	assert_array(_dups("{}")).is_empty()
	assert_array(_dups('{"a": []}')).is_empty()
	assert_array(_dups('{"a": [1, 2, 3], "b": null, "c": true, "d": 1.5e3}')).is_empty()


func test_real_data_files_have_no_duplicates() -> void:
	for f in ["towers.json", "enemies.json", "waves.json", "economy.json", "sanity.json"]:
		assert_array(_dups(FileAccess.get_file_as_string("res://data/" + f))).is_empty()
