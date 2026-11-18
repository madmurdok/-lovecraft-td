class_name SimRoute
extends RefCounted
## A polyline of cell centres with integer cumulative lengths (design note LT-4 §3.2).
## An enemy's position along it is one integer distance in SimTime.UNITS_PER_CELL units.

var length: int = 0  ## total length in units
var _points: PackedVector2Array = []  ## cell centres in cell units
var _cumulative: PackedInt64Array = []  ## distance of each point from the start, in units


## Route through `cells` in order; each step's length is the grid distance between the
## centres, rounded.
static func from_cells(grid: GridTopology, cells: Array[Vector2i]) -> SimRoute:
	var route := SimRoute.new()
	route._points.resize(cells.size())
	for i in cells.size():
		route._points[i] = grid.centre(cells[i])
	route._cumulative.resize(cells.size())
	var total := 0
	for i in cells.size():
		if i > 0:
			total += roundi(grid.distance(cells[i - 1], cells[i]) * SimTime.UNITS_PER_CELL)
		route._cumulative[i] = total
	route.length = total
	return route


## Straight two-point route (flyers): length is the rounded euclidean distance.
static func straight(grid: GridTopology, a: Vector2i, b: Vector2i) -> SimRoute:
	var cells: Array[Vector2i] = [a, b]
	return from_cells(grid, cells)


## Position in cell units (the grid's cell centres); distance is clamped to the route.
func position_at(distance: int) -> Vector2:
	if _points.is_empty():
		return Vector2.ZERO
	var d := clampi(distance, 0, length)
	var i := 0
	while i < _points.size() - 2 and _cumulative[i + 1] <= d:
		i += 1
	var a := _points[i]
	if _points.size() == 1:
		return a
	var seg := _cumulative[i + 1] - _cumulative[i]
	if seg == 0:
		return a
	return a.lerp(_points[i + 1], float(d - _cumulative[i]) / float(seg))
