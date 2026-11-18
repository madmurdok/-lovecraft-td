class_name SquareGridTest
extends TowerTestBase
## LT-77 (docs/design/LT-77-grid-topology.md §1, §6 behaviours 1-7, 9, 10): SquareGrid on
## hand-checked cases, route numbers pinned from release-0.5.0, and the tower centre.

var _grid := SquareGrid.new(5, 4)


# --- 1: centre -------------------------------------------------------------------------

func test_centre_is_the_cell_plus_a_half() -> void:
	assert_object(_grid.centre(Vector2i(0, 0))).is_equal(Vector2(0.5, 0.5))
	assert_object(_grid.centre(Vector2i(3, 1))).is_equal(Vector2(3.5, 1.5))
	assert_object(_grid.centre(Vector2i(-1, 3))).is_equal(Vector2(-0.5, 3.5))
	assert_object(_grid.centre(Vector2i(-4, -2))).is_equal(Vector2(-3.5, -1.5))


# --- 2: neighbours ---------------------------------------------------------------------

func test_interior_neighbours_are_the_four_in_pinned_order() -> void:
	assert_array(_grid.neighbours(Vector2i(2, 2))).is_equal([
		Vector2i(3, 2), Vector2i(2, 3), Vector2i(1, 2), Vector2i(2, 1)])  # R, D, L, U


func test_corner_neighbours_are_two_and_in_bounds() -> void:
	assert_array(_grid.neighbours(Vector2i(0, 0))).is_equal([Vector2i(1, 0), Vector2i(0, 1)])
	assert_array(_grid.neighbours(Vector2i(4, 3))).is_equal([Vector2i(3, 3), Vector2i(4, 2)])
	assert_array(_grid.neighbours(Vector2i(4, 0))).is_equal([Vector2i(4, 1), Vector2i(3, 0)])


func test_neighbours_are_never_out_of_bounds() -> void:
	for c in _grid.cells():
		for n in _grid.neighbours(c):
			assert_bool(_grid.contains(n)).override_failure_message("%s -> %s" % [c, n]).is_true()
			assert_int(absi(n.x - c.x) + absi(n.y - c.y)).is_equal(1)


# --- 3 / 4: distance and steps ---------------------------------------------------------

func test_distance_is_euclid_between_centres() -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(3, 4)
	assert_float(_grid.distance(a, b)).is_equal(5.0)
	assert_float(_grid.distance(b, a)).is_equal(5.0)
	assert_float(_grid.distance(b, b)).is_equal(0.0)
	assert_float(_grid.distance(Vector2i(1, 1), Vector2i(2, 1))).is_equal(1.0)


func test_steps_are_graph_hops() -> void:
	assert_int(_grid.steps(Vector2i(0, 0), Vector2i(3, 4))).is_equal(7)
	assert_int(_grid.steps(Vector2i(3, 4), Vector2i(0, 0))).is_equal(7)
	assert_int(_grid.steps(Vector2i(2, 2), Vector2i(2, 2))).is_equal(0)


# --- 5: polygon and cell_at ------------------------------------------------------------

func test_polygon_has_four_corners_in_pinned_order() -> void:
	assert_array(_grid.polygon(Vector2i(2, 1))).is_equal([
		Vector2(2, 1), Vector2(3, 1), Vector2(3, 2), Vector2(2, 2)])


func test_cell_at_inverts_centre_and_corner_nudges() -> void:
	for c in _grid.cells():
		assert_object(_grid.cell_at(_grid.centre(c))).is_equal(c)
		var centre := _grid.centre(c)
		for corner in _grid.polygon(c):
			var inward: Vector2 = corner + (centre - corner) * 0.01
			assert_object(_grid.cell_at(inward)).override_failure_message(
				"cell %s corner %s" % [c, corner]).is_equal(c)


func test_cell_at_left_or_above_the_board_is_outside() -> void:
	for p in [Vector2(-0.01, 1.5), Vector2(1.5, -0.01), Vector2(-3.2, -0.5)]:
		assert_bool(_grid.contains(_grid.cell_at(p))).override_failure_message(
			"%s" % p).is_false()
	assert_object(_grid.cell_at(Vector2(-0.5, 0.5))).is_equal(Vector2i(-1, 0))


# --- 6: contains, cells, index ---------------------------------------------------------

func test_contains_matches_the_rectangle() -> void:
	for y in range(-2, 7):
		for x in range(-2, 8):
			var want := 0 <= x and x < 5 and 0 <= y and y < 4
			assert_bool(_grid.contains(Vector2i(x, y))).override_failure_message(
				"(%d, %d)" % [x, y]).is_equal(want)


func test_cells_are_row_major_and_index_inverts_them() -> void:
	var cells := _grid.cells()
	assert_int(cells.size()).is_equal(20)
	assert_int(_grid.cell_count()).is_equal(20)
	assert_object(cells[0]).is_equal(Vector2i(0, 0))
	assert_object(cells[1]).is_equal(Vector2i(1, 0))  # x runs first
	assert_object(cells[5]).is_equal(Vector2i(0, 1))
	assert_object(cells[19]).is_equal(Vector2i(4, 3))
	for i in cells.size():
		assert_int(_grid.index(cells[i])).is_equal(i)


# --- 7: bounds -------------------------------------------------------------------------

func test_bounds_is_the_world_rect_and_kind_is_square() -> void:
	assert_object(_grid.bounds()).is_equal(Rect2(0.0, 0.0, 5.0, 4.0))
	assert_str(_grid.kind()).is_equal("square")


# --- 9: route numbers, computed on release-0.5.0 before LT-77 ---------------------------

func test_ground_route_matches_the_release_0_5_0_numbers() -> void:
	var m := real_config().map
	var route := SimRoute.from_cells(m.grid, m.path)
	assert_int(route.length).is_equal(1200000)
	var pins := {
		0: Vector2(0.5, 1.5),
		1: Vector2(0.50003331899643, 1.5),
		250: Vector2(0.50833332538605, 1.5),
		1000: Vector2(0.53333336114883, 1.5),
		600000: Vector2(12.5, 9.5),
		1199999: Vector2(21.5, 10.4999666213989),
		1200000: Vector2(21.5, 10.5),
		1200100: Vector2(21.5, 10.5),  # clamped to the route
	}
	for d: int in pins:
		assert_object(route.position_at(d)).override_failure_message("distance %d" % d) \
			.is_equal(pins[d])


func test_flyer_route_matches_the_release_0_5_0_numbers() -> void:
	var m := real_config().map
	var route := SimRoute.straight(m.grid, m.spawn, m.lighthouse)  # diagonal S -> L
	assert_int(route.length).is_equal(685420)
	var pins := {
		0: Vector2(0.5, 1.5),
		1: Vector2(0.50003063678741, 1.50001311302185),
		777: Vector2(0.52380585670471, 1.5102025270462),
		342710: Vector2(11.0, 6.0),
		685419: Vector2(21.4999694824219, 10.4999866485596),
		685420: Vector2(21.5, 10.5),
	}
	for d: int in pins:
		assert_object(route.position_at(d)).override_failure_message("distance %d" % d) \
			.is_equal(pins[d])


# --- 10: tower centre ------------------------------------------------------------------

func test_built_tower_centre_is_the_grids_centre_of_its_cell() -> void:
	var sim := tsim()
	for cell: Vector2i in [TOWER, Vector2i(0, 1), Vector2i(14, 1), Vector2i(3, 1)]:
		var t := build(sim, "rifleman", cell)
		assert_object(t).is_not_null()
		assert_object(t.centre()).is_equal(sim.config.map.grid.centre(cell))


# --- LightRules.covers takes the grid (LT-77 §6 step 7) --------------------------------

func test_covers_measures_from_the_grids_centre_of_the_cell() -> void:
	var cell := Vector2i(3, 1)  # centre (3.5, 1.5)
	assert_bool(LightRules.covers(_grid, cell, 3.0, Vector2(6.5, 1.5))).is_true()
	assert_bool(LightRules.covers(_grid, cell, 3.0, Vector2(6.51, 1.5))).is_false()
