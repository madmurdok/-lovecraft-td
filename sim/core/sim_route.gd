class_name SimRoute
extends RefCounted
## A polyline of cell centres with integer cumulative lengths (design note LT-4 §3.2).
## An enemy's position along it is one integer distance in SimTime.UNITS_PER_CELL units.

var length: int = 0  ## total length in units
var _cells: Array[Vector2i] = []
var _cumulative: PackedInt64Array = []  ## distance of each point from the start, in units


## Route through `cells` in order; each step's length is its euclidean length, rounded.
static func from_cells(cells: Array[Vector2i]) -> SimRoute:
	var route := SimRoute.new()
	route._cells = cells.duplicate()
	route._cumulative.resize(cells.size())
	var total := 0
	for i in cells.size():
		if i > 0:
			var d := cells[i] - cells[i - 1]
			total += roundi(sqrt(float(d.x * d.x + d.y * d.y)) * SimTime.UNITS_PER_CELL)
		route._cumulative[i] = total
	route.length = total
	return route


## Straight two-point route (flyers): length is the rounded euclidean distance.
static func straight(a: Vector2i, b: Vector2i) -> SimRoute:
	var cells: Array[Vector2i] = [a, b]
	return from_cells(cells)


## Position in cell units (cell centre = x + 0.5, y + 0.5); distance is clamped to the route.
func position_at(distance: int) -> Vector2:
	if _cells.is_empty():
		return Vector2.ZERO
	var d := clampi(distance, 0, length)
	var i := 0
	while i < _cells.size() - 2 and _cumulative[i + 1] <= d:
		i += 1
	var a := _centre(_cells[i])
	if _cells.size() == 1:
		return a
	var seg := _cumulative[i + 1] - _cumulative[i]
	if seg == 0:
		return a
	return a.lerp(_centre(_cells[i + 1]), float(d - _cumulative[i]) / float(seg))


static func _centre(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5)
