class_name GridFactoryTest
extends GdUnitTestSuite
## LT-108 §6 item 1 and owner Q1/Q6 (docs/design/LT-108-grid-factory.md): GridFactory builds a
## registered topology by kind, an unknown kind is null. LT-129: hex is registered (one MAKERS
## line), so a "grid": "hex" map parses through MapDef with axial ids.

var _saved: Dictionary


func before_test() -> void:
	_saved = GridFactory.MAKERS.duplicate()


func after_test() -> void:
	GridFactory.MAKERS = _saved  # never leak a test registration into other suites


func test_square_is_a_square_grid_like_a_hand_built_one() -> void:
	var g := GridFactory.make("square", 5, 4)
	var want := SquareGrid.new(5, 4)
	assert_bool(g is SquareGrid).override_failure_message(str(g)).is_true()
	assert_str(g.kind()).is_equal(want.kind())
	assert_array(g.cells()).is_equal(want.cells())
	assert_object(g.bounds()).is_equal(want.bounds())
	assert_int(g.cell_count()).is_equal(20)


func test_each_call_builds_a_fresh_grid_of_its_size() -> void:
	var a := GridFactory.make("square", 3, 2)
	var b := GridFactory.make("square", 7, 5)
	assert_object(a).is_not_same(b)
	assert_object(a.bounds()).is_equal(Rect2(0, 0, 3, 2))
	assert_object(b.bounds()).is_equal(Rect2(0, 0, 7, 5))


func test_unknown_kinds_are_null() -> void:
	assert_object(GridFactory.make("squre", 5, 4)).is_null()
	assert_object(GridFactory.make("tri", 5, 4)).is_null()
	assert_object(GridFactory.make("", 5, 4)).is_null()


func test_hex_is_registered_and_kinds_are_sorted() -> void:
	assert_array(Array(GridFactory.kinds())).is_equal(["hex", "square"])
	var g := GridFactory.make("hex", 4, 3)
	assert_bool(g is HexGrid).override_failure_message(str(g)).is_true()
	assert_int(g.cell_count()).is_equal(12)
	# an interior cell has 6 neighbours
	var interior := Vector2i(1, 1)
	assert_bool(g.cells().has(interior)).is_true()
	assert_int(g.neighbours(interior).size()).is_equal(6)


func test_a_hex_map_parses_through_the_factory_into_axial_ids() -> void:
	var r := ConfigReader.new("map.json")
	var m := MapDef.parse(r, {"width": 4, "height": 3, "grid": "hex",
		"rows": [".S..", "#...", "L..."]})
	assert_array(r.errors).is_empty()
	assert_bool(m.grid is HexGrid).is_true()
	assert_array(m.path).is_equal([Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 2)])


func test_maps_without_grid_or_with_square_build_a_square_grid() -> void:
	for extra in [{}, {"grid": "square"}]:
		var d := {"width": 3, "height": 1, "rows": ["S#L"]}
		d.merge(extra)
		var r := ConfigReader.new("map.json")
		var m := MapDef.parse(r, d)
		assert_array(r.errors).is_empty()
		assert_bool(m.grid is SquareGrid).is_true()


func test_the_unknown_grid_error_lists_the_registered_kinds() -> void:
	var r := ConfigReader.new("map.json")
	MapDef.parse(r, {"width": 3, "height": 1, "grid": "tri", "rows": ["S#L"]})
	assert_array(r.errors).is_equal(
		["map.json: grid: unknown grid \"tri\" (expected \"hex\", \"square\")"])
