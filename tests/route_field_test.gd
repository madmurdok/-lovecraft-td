class_name RouteFieldTest
extends GdUnitTestSuite
## LT-130 §8 T3 (docs/design/LT-130-p1-generator.md §3, LT-18 §3): the route field is a reverse
## Dijkstra from L in sim units; a cell's next hop is its FIRST neighbour in neighbours() order
## one step closer to L. Fixtures are map text rows (GenMap.from_rows); cells are named by text
## coords. Expected hops are worked out from HexGrid's pinned neighbour order (E, NE, NW, W, SW,
## SE) and odd-r rows, not read from the field.
##
## Controls (code revert -> failing test), described for the verify slice:
##  T3: RouteField.next_hop takes the LAST equal-cost neighbour instead of the first
##      -> test_diamond_tie_takes_the_first_neighbour_in_order fails.

const U := SimTime.UNITS_PER_CELL


func _at(m: GenMap, x: int, y: int) -> Vector2i:
	return m.grid.cell_of_text(x, y)


## L at text (0,0) = axial (0,0), S at text (1,1) = axial (1,1): two steps apart, off a
## straight line, so two shortest paths: via axial (1,0) = text (1,0) and axial (0,1) =
## text (0,1). From S, neighbours() lists NW (1,0) before W (0,1).
func _diamond() -> GenMap:
	return GenMap.from_rows("hex", ["L#^", "#S^"])


func test_diamond_costs_are_whole_cells_in_sim_units() -> void:
	var m := _diamond()
	var f := RouteField.build(m)
	assert_int(f.cost_at(m.lighthouse)).is_equal(0)
	assert_int(f.cost_at(_at(m, 1, 0))).is_equal(U)
	assert_int(f.cost_at(_at(m, 0, 1))).is_equal(U)
	assert_int(f.cost_at(m.entries[0])).is_equal(2 * U)
	assert_int(f.cells_at(m.entries[0])).is_equal(2)
	assert_int(f.cost_at(_at(m, 2, 0))).is_equal(RouteField.UNREACHED)  # rock


func test_diamond_tie_takes_the_first_neighbour_in_order() -> void:
	var m := _diamond()
	var f := RouteField.build(m)
	var s := m.entries[0]
	var nw := _at(m, 1, 0)
	assert_bool(m.grid.neighbours(s).find(nw) < m.grid.neighbours(s).find(_at(m, 0, 1))).is_true()
	assert_that(f.next_hop(s)).is_equal(nw)
	assert_array(f.route(s)).is_equal([s, nw, m.lighthouse])


func test_blocking_the_first_choice_takes_the_other_side() -> void:
	var m := _diamond()
	var one: Array[Vector2i] = [_at(m, 1, 0)]
	var f := RouteField.build(m, one)
	assert_that(f.next_hop(m.entries[0])).is_equal(_at(m, 0, 1))
	assert_int(f.cells_at(m.entries[0])).is_equal(2)
	var both: Array[Vector2i] = [_at(m, 1, 0), _at(m, 0, 1)]
	var cut := RouteField.build(m, both)
	assert_bool(cut.reaches(m.entries[0])).is_false()
	assert_array(cut.route(m.entries[0])).is_empty()


func test_blocking_the_lighthouse_is_ignored() -> void:
	var m := _diamond()
	var wall: Array[Vector2i] = [m.lighthouse]
	assert_int(RouteField.build(m, wall).cells_at(m.entries[0])).is_equal(2)


## One winding corridor, no side cells: L (0,0) (1,0) (2,0) | (2,1) | (3,2) S (4,2) in text.
## (2,1) is axial (2,1); its SE neighbour axial (2,2) is text (3,2), and text (2,2) (axial
## (1,2), its SW) is rock, so the corridor has exactly one cell per step.
func test_one_corridor_route_is_exactly_its_cells() -> void:
	var m := GenMap.from_rows("hex", ["L##^^", "^^#^^", "^^^#S"])
	var f := RouteField.build(m)
	var want: Array[Vector2i] = [_at(m, 4, 2), _at(m, 3, 2), _at(m, 2, 1), _at(m, 2, 0),
		_at(m, 1, 0), _at(m, 0, 0)]
	assert_array(f.route(m.entries[0])).is_equal(want)
	for i in want.size():
		assert_int(f.cells_at(want[i])).is_equal(want.size() - 1 - i)
	assert_that(f.next_hop(m.lighthouse)).is_equal(m.lighthouse)


func test_unreached_entry_has_no_route() -> void:
	var m := GenMap.from_rows("hex", ["L#^#S"])
	var f := RouteField.build(m)
	assert_bool(f.reaches(m.entries[0])).is_false()
	assert_int(f.cells_at(m.entries[0])).is_equal(RouteField.UNREACHED)
	assert_array(f.route(m.entries[0])).is_empty()
	assert_that(f.next_hop(m.entries[0])).is_equal(m.entries[0])


## Square works through the same GridTopology calls: a straight row is its own route.
func test_square_corridor_route() -> void:
	var m := GenMap.from_rows("square", ["^^^^", "L##S", "^^^^"])
	var want: Array[Vector2i] = [Vector2i(3, 1), Vector2i(2, 1), Vector2i(1, 1), Vector2i(0, 1)]
	assert_array(RouteField.build(m).route(m.entries[0])).is_equal(want)
