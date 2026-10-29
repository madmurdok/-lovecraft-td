class_name MapDefTest
extends SimTestBase
## LT-4 §3.1: map.json loads and derives the path; malformed maps are rejected with
## LT-3-style error paths (behaviours 14, 17).


func _load_map(rows: Array, width := -1, height := -1) -> ConfigLoadResult:
	return load_json_edit(MAP, func(root: Dictionary) -> void:
		root["width"] = width if width >= 0 else String(rows[0]).length()
		root["height"] = height if height >= 0 else rows.size()
		root["rows"] = rows)


func _assert_map_rejected(rows: Array, path: String, fragment: String) -> void:
	assert_rejected(_load_map(rows), MAP, path, fragment)


# --- the real map -----------------------------------------------------------

func test_real_map_loads() -> void:
	var m := real_config().map
	assert_int(m.width).is_equal(24)
	assert_int(m.height).is_equal(14)
	assert_int(m.path.size()).is_equal(41)
	assert_that(m.path[0]).is_equal(m.spawn)
	assert_that(m.path[-1]).is_equal(m.lighthouse)
	assert_that(m.spawn).is_equal(Vector2i(0, 1))
	assert_that(m.lighthouse).is_equal(Vector2i(21, 10))


func test_real_map_path_is_a_simple_4_connected_walk() -> void:
	var m := real_config().map
	var seen := {}
	for i in m.path.size():
		var c: Vector2i = m.path[i]
		assert_bool(seen.has(c)).is_false()
		seen[c] = true
		assert_int(m.kind_at(c)).is_equal(MapDef.Kind.PATH)
		if i > 0:
			var d: Vector2i = c - m.path[i - 1]
			assert_int(absi(d.x) + absi(d.y)).is_equal(1)
	# Every path cell of the grid is on the walk (no orphans).
	var path_cells := 0
	for y in m.height:
		for x in m.width:
			if m.kind_at(Vector2i(x, y)) == MapDef.Kind.PATH:
				path_cells += 1
	assert_int(path_cells).is_equal(m.path.size())


func test_real_map_buildable_cells() -> void:
	var m := real_config().map
	assert_bool(m.is_buildable(m.lighthouse)).is_false()
	assert_bool(m.is_buildable(m.spawn)).is_false()
	for c in m.path:
		assert_bool(m.is_buildable(c)).is_false()
	assert_bool(m.is_buildable(Vector2i(0, 2))).is_true()  # "." row 2
	assert_bool(m.is_buildable(Vector2i(0, 0))).is_false()  # "~"
	assert_bool(m.is_buildable(Vector2i(-1, 2))).is_false()  # out of bounds
	assert_int(m.kind_at(Vector2i(24, 0))).is_equal(MapDef.Kind.WATER)
	var buildable := 0
	for y in m.height:
		for x in m.width:
			if m.is_buildable(Vector2i(x, y)):
				buildable += 1
	assert_int(buildable).is_between(100, 140)  # GDD target ~120


func test_custom_map_derives_path_in_walking_order() -> void:
	var r := _load_map([
		"S#..",
		".#..",
		".##L",
	])
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	var path: Array = r.config.map.path
	assert_array(path).is_equal([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)])


# --- rejections -------------------------------------------------------------

func test_rejects_wrong_row_count() -> void:
	assert_rejected(_load_map(["S##L", "...."], 4, 3), MAP, "rows", "expected 3 rows")


func test_rejects_wrong_row_width() -> void:
	assert_rejected(_load_map(["S##L", "..."], 4, 2), MAP, "rows[1]",
		"expected 4 characters")


func test_rejects_unknown_character() -> void:
	_assert_map_rejected(["S#xL"], "rows[0]", "unknown character \"x\" at column 2")


func test_rejects_bad_width_and_height() -> void:
	assert_rejected(_load_map(["S##L"], 0, 1), MAP, "width")
	assert_rejected(_load_map(["S##L"], 4, 0), MAP, "height")


func test_rejects_missing_or_duplicate_s() -> void:
	_assert_map_rejected([".##L"], "rows", "exactly one S")
	_assert_map_rejected(["S##L", "S..."], "rows", "exactly one S")


func test_rejects_missing_or_duplicate_l() -> void:
	_assert_map_rejected(["S##."], "rows", "exactly one L")
	_assert_map_rejected(["S##L", "...L"], "rows", "exactly one L")


func test_rejects_fork() -> void:
	_assert_map_rejected(["S###L", "..#.."], "rows[0]", "path forks at column 2")


func test_rejects_orphan_path_cell() -> void:
	_assert_map_rejected(["S###L", ".....", "..#.."], "rows[2]",
		"path cell at column 2 is not on the walk from S to L")


func test_rejects_disconnected_path() -> void:
	_assert_map_rejected(["S#.#L"], "rows[0]", "path from S ends at column 1 without reaching L")


func test_rejects_s_in_the_middle_of_the_path() -> void:
	_assert_map_rejected(["#S##L"], "rows[0]", "S must be a path end")


func test_rejects_l_in_the_middle_of_the_path() -> void:
	_assert_map_rejected(["S##L#"], "rows[0]", "L must be a path end")


func test_rejects_isolated_s() -> void:
	_assert_map_rejected(["S.#L"], "rows[0]", "S must be a path end")
