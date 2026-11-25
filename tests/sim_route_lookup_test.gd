class_name SimRouteLookupTest
extends GdUnitTestSuite
## LT-85/S15 (control: LT-85-controls.md, S18): SimRoute.position_at (bisect on the cumulative
## lengths) equals a reference linear walk written here, at every unit distance on a square
## and a hex route, with zero-length segments, 0-1 point routes and out-of-range distances.

const MARGIN := 5  ## units checked past each end
const EPS := 1.0e-4  ## cell units; a segment boundary may differ by an ulp between walks


func _cells(list: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in list:
		out.append(c)
	return out


## The reference: cumulative lengths as from_cells defines them, then the last point at or
## before the clamped distance (at most n - 2), walked from the start.
func _reference(grid: GridTopology, cells: Array[Vector2i], distance: int) -> Vector2:
	var n := cells.size()
	if n == 0:
		return Vector2.ZERO
	if n == 1:
		return grid.centre(cells[0])
	var cum: Array[int] = [0]
	for i in range(1, n):
		cum.append(cum[i - 1] + roundi(grid.distance(cells[i - 1], cells[i]) * SimTime.UNITS_PER_CELL))
	var d := clampi(distance, 0, cum[n - 1])
	var i := 0
	while i < n - 2 and cum[i + 1] <= d:
		i += 1
	var seg := cum[i + 1] - cum[i]
	if seg == 0:
		return grid.centre(cells[i])
	return grid.centre(cells[i]).lerp(grid.centre(cells[i + 1]), float(d - cum[i]) / float(seg))


func _check(grid: GridTopology, cells: Array[Vector2i], label: String) -> void:
	var route := SimRoute.from_cells(grid, cells)
	var bad := 0
	var first := ""
	for d in range(-MARGIN, route.length + MARGIN + 1):
		var got := route.position_at(d)
		var want := _reference(grid, cells, d)
		if not got.is_equal_approx(want) and got.distance_to(want) > EPS:
			bad += 1
			if first == "":
				first = "d=%d got %s want %s" % [d, got, want]
	assert_int(bad).override_failure_message("%s: %d mismatches, first %s" % [label, bad, first]) \
		.is_equal(0)


func test_square_route_with_a_turn_and_zero_length_segments_equals_the_linear_walk() -> void:
	var g := SquareGrid.new(8, 8)
	_check(g, _cells([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(1, 1), Vector2i(1, 1), Vector2i(2, 1)]), "square zero-length")
	_check(g, _cells([Vector2i(0, 0), Vector2i(3, 0), Vector2i(3, 2)]), "square long")
	_check(g, _cells([Vector2i(2, 2), Vector2i(2, 2), Vector2i(2, 2)]), "square all zero")


func test_hex_route_with_a_turn_and_zero_length_segments_equals_the_linear_walk() -> void:
	var g := HexGrid.new(8, 8)
	_check(g, _cells([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 1),
		Vector2i(2, 1), Vector2i(2, 2)]), "hex zero-length")
	_check(g, _cells([Vector2i(0, 0), Vector2i(0, 0), Vector2i(3, 2)]), "hex leading zero")


func test_short_routes_and_two_points_equal_the_reference() -> void:
	for g: GridTopology in [SquareGrid.new(6, 6), HexGrid.new(6, 6)]:
		_check(g, _cells([]), "empty")
		_check(g, _cells([Vector2i(2, 3)]), "one point")
		_check(g, _cells([Vector2i(0, 0), Vector2i(2, 0)]), "two points")
		_check(g, _cells([Vector2i(1, 1), Vector2i(1, 1)]), "two equal points")
		_check(g, SimRoute.new() if false else _cells([Vector2i(5, 5), Vector2i(0, 0)]), "reversed")


func test_distance_is_clamped_to_the_route_ends() -> void:
	var g := SquareGrid.new(8, 8)
	var cells := _cells([Vector2i(0, 0), Vector2i(2, 0), Vector2i(2, 2)])
	var route := SimRoute.from_cells(g, cells)
	assert_vector(route.position_at(-1000000)).is_equal(g.centre(cells[0]))
	assert_vector(route.position_at(route.length + 1000000)).is_equal(g.centre(cells[2]))
	assert_vector(route.position_at(route.length)).is_equal(g.centre(cells[2]))
	assert_int(route.length).is_equal(4 * SimTime.UNITS_PER_CELL)
