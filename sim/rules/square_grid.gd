class_name SquareGrid
extends GridTopology
## LT-77: the square grid, w x h cells, id (x, y), 4-neighbours. The one home of the square
## cell-centre rule (LT-76 G3): (x + 0.5, y + 0.5).

const NEIGHBOUR_OFFSETS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT,
	Vector2i.UP]

var _w: int
var _h: int
var _cells: Array[Vector2i] = []


func _init(w: int, h: int) -> void:
	_w = w
	_h = h
	for y in h:
		for x in w:
			_cells.append(Vector2i(x, y))


func kind() -> String:
	return "square"


func centre(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5)


func neighbours(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in NEIGHBOUR_OFFSETS:
		if contains(cell + d):
			out.append(cell + d)
	return out


func distance(a: Vector2i, b: Vector2i) -> float:
	var dx := float(b.x) - a.x
	var dy := float(b.y) - a.y
	return sqrt(dx * dx + dy * dy)


func steps(a: Vector2i, b: Vector2i) -> int:
	return absi(b.x - a.x) + absi(b.y - a.y)


func polygon(cell: Vector2i) -> PackedVector2Array:
	var x := float(cell.x)
	var y := float(cell.y)
	return PackedVector2Array([Vector2(x, y), Vector2(x + 1.0, y), Vector2(x + 1.0, y + 1.0),
		Vector2(x, y + 1.0)])


func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _w and cell.y < _h


func cells() -> Array[Vector2i]:
	return _cells


func index(cell: Vector2i) -> int:
	return cell.y * _w + cell.x


func cell_count() -> int:
	return _w * _h


func bounds() -> Rect2:
	return Rect2(0.0, 0.0, _w, _h)
