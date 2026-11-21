class_name HexGridTest
extends GdUnitTestSuite
## LT-108 §6 item 5 (docs/design/LT-108-grid-factory.md, owner Q7): HexGrid, pointy-top, axial
## id (q, r), map text in odd-r rows. Mirrors square_grid_test.gd on hand-checked cases. The
## numbers are written from the spec (neighbour centres 1 apart, circumradius 1 / sqrt(3),
## row pitch sqrt(3) / 2), not read from the grid's own fields.

const W := 5
const H := 4
const EPS := 1e-9

var _grid := HexGrid.new(W, H)
var _rad := 1.0 / sqrt(3.0)  ## circumradius
var _pitch := sqrt(3.0) / 2.0  ## row pitch


func _near(a: Vector2, b: Vector2, eps := EPS) -> bool:
	return absf(a.x - b.x) <= eps and absf(a.y - b.y) <= eps


# --- centre -------------------------------------------------------------------------------

func test_centre_shifts_half_a_cell_per_axial_row() -> void:
	var pins := {
		Vector2i(0, 0): Vector2(0.5, _rad),
		Vector2i(1, 0): Vector2(1.5, _rad),
		Vector2i(0, 1): Vector2(1.0, _rad + _pitch),  # text (0, 1): odd row, half a cell right
		Vector2i(-1, 2): Vector2(0.5, _rad + 2.0 * _pitch),  # text (0, 2)
		Vector2i(3, 3): Vector2(5.0, _rad + 3.0 * _pitch),  # text (4, 3), the last cell
	}
	for c: Vector2i in pins:
		assert_bool(_near(_grid.centre(c), pins[c])).override_failure_message(
			"%s: %s, want %s" % [c, _grid.centre(c), pins[c]]).is_true()


# --- neighbours ---------------------------------------------------------------------------

func test_interior_neighbours_are_the_six_axial_offsets_in_pinned_order() -> void:
	# E, NE, NW, W, SW, SE
	assert_array(_grid.neighbours(Vector2i(2, 1))).is_equal([Vector2i(3, 1), Vector2i(3, 0),
		Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)])


func test_corner_neighbours_stay_in_bounds() -> void:
	# text (0, 0): even row, so its lower-left is off the board
	assert_array(_grid.neighbours(Vector2i(0, 0))).is_equal([Vector2i(1, 0), Vector2i(0, 1)])
	# text (4, 3), axial (3, 3): the last cell
	assert_array(_grid.neighbours(Vector2i(3, 3))).is_equal([Vector2i(3, 2), Vector2i(2, 3)])
	# text (4, 1), axial (4, 1): odd row's right end has 3 neighbours
	assert_array(_grid.neighbours(Vector2i(4, 1))).is_equal([Vector2i(4, 0), Vector2i(3, 1),
		Vector2i(3, 2)])


func test_neighbourhood_is_symmetric_and_in_bounds() -> void:
	for c in _grid.cells():
		var ns := _grid.neighbours(c)
		assert_int(ns.size()).override_failure_message(str(c)).is_between(2, 6)
		for n in ns:
			assert_bool(_grid.contains(n)).override_failure_message("%s -> %s" % [c, n]).is_true()
			assert_bool(_grid.neighbours(n).has(c)).override_failure_message(
				"%s -> %s, not back" % [c, n]).is_true()


# --- distance and steps -------------------------------------------------------------------

func test_distance_to_every_neighbour_is_one() -> void:
	for c in _grid.cells():
		for n in _grid.neighbours(c):
			assert_float(_grid.distance(c, n)).override_failure_message("%s -> %s" % [c, n]) \
				.is_equal_approx(1.0, EPS)
			assert_float(_grid.centre(c).distance_to(_grid.centre(n))) \
				.override_failure_message("centres %s -> %s" % [c, n]).is_equal_approx(1.0, 1e-6)


func test_distance_is_euclid_between_centres() -> void:
	var a := Vector2i(0, 0)
	assert_float(_grid.distance(a, a)).is_equal(0.0)
	assert_float(_grid.distance(a, Vector2i(3, 0))).is_equal_approx(3.0, EPS)
	# two rows down, same text column: straight down 2 pitches
	assert_float(_grid.distance(a, Vector2i(-1, 2))).is_equal_approx(sqrt(3.0), EPS)
	assert_float(_grid.distance(Vector2i(-1, 2), a)).is_equal_approx(sqrt(3.0), EPS)


func test_steps_are_hex_hops() -> void:
	var pins := [
		[Vector2i(0, 0), Vector2i(3, 0), 3],
		[Vector2i(0, 0), Vector2i(0, 3), 3],
		[Vector2i(0, 0), Vector2i(-1, 3), 3],
		[Vector2i(0, 0), Vector2i(1, 1), 2],
		[Vector2i(0, 0), Vector2i(3, -3), 3],
		[Vector2i(2, 1), Vector2i(1, 2), 1],
		[Vector2i(2, 1), Vector2i(2, 1), 0],
		[Vector2i(0, 0), Vector2i(3, 3), 6],
	]
	for p: Array in pins:
		assert_int(_grid.steps(p[0], p[1])).override_failure_message("%s" % [p]).is_equal(p[2])
		assert_int(_grid.steps(p[1], p[0])).override_failure_message("back %s" % [p]) \
			.is_equal(p[2])
	for c in _grid.cells():
		for n in _grid.neighbours(c):
			assert_int(_grid.steps(c, n)).is_equal(1)


# --- polygon and cell_at ------------------------------------------------------------------

func test_polygon_has_six_corners_in_pinned_order() -> void:
	var poly := _grid.polygon(Vector2i(0, 0))  # centre (0.5, rad)
	var want := [Vector2(0.5, 0.0), Vector2(1.0, 0.5 * _rad), Vector2(1.0, 1.5 * _rad),
		Vector2(0.5, 2.0 * _rad), Vector2(0.0, 1.5 * _rad), Vector2(0.0, 0.5 * _rad)]
	assert_int(poly.size()).is_equal(6)
	for i in 6:
		assert_bool(_near(poly[i], want[i])).override_failure_message(
			"corner %d: %s, want %s" % [i, poly[i], want[i]]).is_true()


func test_cell_at_inverts_centre_and_corner_nudges() -> void:
	for c in _grid.cells():
		var centre := _grid.centre(c)
		assert_object(_grid.cell_at(centre)).override_failure_message(str(c)).is_equal(c)
		for corner in _grid.polygon(c):
			var inward: Vector2 = corner + (centre - corner) * 0.01
			assert_object(_grid.cell_at(inward)).override_failure_message(
				"cell %s corner %s" % [c, corner]).is_equal(c)


func test_points_nudged_toward_a_neighbour_land_by_the_shared_edge() -> void:
	for c in _grid.cells():
		var centre := _grid.centre(c)
		for d in HexGrid.NEIGHBOUR_OFFSETS:  # off-board neighbours too: cell_at may leave
			var other := _grid.centre(c + d)
			assert_object(_grid.cell_at(centre + (other - centre) * 0.4)) \
				.override_failure_message("%s toward %s, 0.4" % [c, c + d]).is_equal(c)
			assert_object(_grid.cell_at(other + (centre - other) * 0.4)) \
				.override_failure_message("%s toward %s, 0.6" % [c, c + d]).is_equal(c + d)


func test_cell_at_left_or_above_the_board_is_outside() -> void:
	for p in [Vector2(-0.01, _rad), Vector2(0.5, -0.01), Vector2(-3.2, -0.5)]:
		assert_bool(_grid.contains(_grid.cell_at(p))).override_failure_message(
			"%s" % p).is_false()


# --- text <-> axial -----------------------------------------------------------------------

func test_text_and_axial_hand_checked_pairs() -> void:
	var pins := {  # text -> axial
		Vector2i(0, 0): Vector2i(0, 0), Vector2i(3, 0): Vector2i(3, 0),
		Vector2i(0, 1): Vector2i(0, 1), Vector2i(2, 1): Vector2i(2, 1),
		Vector2i(0, 2): Vector2i(-1, 2), Vector2i(3, 2): Vector2i(2, 2),
		Vector2i(0, 3): Vector2i(-1, 3), Vector2i(4, 3): Vector2i(3, 3),
		Vector2i(0, -1): Vector2i(1, -1), Vector2i(0, -2): Vector2i(1, -2),
		Vector2i(2, -3): Vector2i(4, -3),
	}
	for t: Vector2i in pins:
		assert_object(_grid.cell_of_text(t.x, t.y)).override_failure_message(str(t)) \
			.is_equal(pins[t])
		assert_object(_grid.text_of(pins[t])).override_failure_message(str(t)).is_equal(t)


func test_text_round_trip_including_negative_rows() -> void:
	for y in range(-5, 8):
		for x in range(-3, 8):
			var cell := _grid.cell_of_text(x, y)
			assert_object(_grid.text_of(cell)).override_failure_message(
				"text (%d, %d) -> %s" % [x, y, cell]).is_equal(Vector2i(x, y))
			# axial -> text -> axial, too
			var a := Vector2i(x, y)
			var t := _grid.text_of(a)
			assert_object(_grid.cell_of_text(t.x, t.y)).override_failure_message(
				"axial %s -> %s" % [a, t]).is_equal(a)


# --- contains, cells, index, bounds ------------------------------------------------------

func test_contains_matches_the_text_rectangle() -> void:
	for y in range(-2, H + 3):
		for x in range(-2, W + 3):
			var want := 0 <= x and x < W and 0 <= y and y < H
			assert_bool(_grid.contains(_grid.cell_of_text(x, y))).override_failure_message(
				"text (%d, %d)" % [x, y]).is_equal(want)


func test_cells_are_text_row_major_and_index_inverts_them() -> void:
	var cells := _grid.cells()
	assert_int(cells.size()).is_equal(W * H)
	assert_int(_grid.cell_count()).is_equal(W * H)
	assert_object(cells[0]).is_equal(Vector2i(0, 0))
	assert_object(cells[1]).is_equal(Vector2i(1, 0))  # text x runs first
	assert_object(cells[5]).is_equal(Vector2i(0, 1))  # text (0, 1)
	assert_object(cells[10]).is_equal(Vector2i(-1, 2))  # text (0, 2)
	assert_object(cells[19]).is_equal(Vector2i(3, 3))  # text (4, 3)
	for i in cells.size():
		assert_int(_grid.index(cells[i])).is_equal(i)


func test_bounds_enclose_every_tile_tightly_and_kind_is_hex() -> void:
	var b := _grid.bounds()
	assert_bool(_near(b.position, Vector2.ZERO)).is_true()
	assert_bool(_near(b.size, Vector2(W + 0.5, (H - 1) * _pitch + 2.0 * _rad))) \
		.override_failure_message(str(b)).is_true()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in _grid.cells():
		for p in _grid.polygon(c):
			lo = lo.min(p)
			hi = hi.max(p)
	assert_bool(_near(lo, b.position, 1e-6)).override_failure_message(str(lo)).is_true()
	assert_bool(_near(hi, b.end, 1e-6)).override_failure_message(str(hi)).is_true()
	# one row: no odd row sticks out
	assert_bool(_near(HexGrid.new(3, 1).bounds().size, Vector2(3.0, 2.0 * _rad))).is_true()
	assert_str(_grid.kind()).is_equal("hex")
