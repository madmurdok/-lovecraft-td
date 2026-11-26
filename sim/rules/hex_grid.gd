class_name HexGrid
extends GridTopology
## LT-108 F5: the pointy-top hex grid, w x h text cells, axial id (q, r) (LT-77 §3).
## The map text's rows are odd-r offset rows: text (x, y) <-> axial (x - (y - (y & 1)) / 2, y).
## Neighbour centres are 1 apart (flat-to-flat width 1, apothem 0.5), so range, speed and
## reach keep their LT-77 meaning. Pure and immutable; no trig: sqrt(3) is computed once.
## Registered in GridFactory.MAKERS as "hex" (LT-129).

## E, NE, NW, W, SW, SE: screen counter-clockwise from east.
const NEIGHBOUR_OFFSETS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]

var _w: int
var _h: int
var _r: float  ## circumradius 1 / sqrt(3)
var _pitch: float  ## row pitch sqrt(3) / 2
var _cells: Array[Vector2i] = []


func _init(w: int, h: int) -> void:
	_w = w
	_h = h
	var s3 := sqrt(3.0)
	_r = 1.0 / s3
	_pitch = s3 / 2.0
	for y in h:
		for x in w:
			_cells.append(cell_of_text(x, y))


func kind() -> String:
	return "hex"


## The one home of the hex cell-centre rule (LT-76 G3).
func centre(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5 * cell.y + 0.5, _r + cell.y * _pitch)


func neighbours(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in NEIGHBOUR_OFFSETS:
		if contains(cell + d):
			out.append(cell + d)
	return out


func distance(a: Vector2i, b: Vector2i) -> float:
	var dr := float(b.y) - a.y
	var dx := (float(b.x) - a.x) + 0.5 * dr
	var dy := dr * _pitch
	return sqrt(dx * dx + dy * dy)


@warning_ignore("integer_division")
func steps(a: Vector2i, b: Vector2i) -> int:
	var dq := b.x - a.x
	var dr := b.y - a.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


## Six corners, screen-clockwise from the top.
func polygon(cell: Vector2i) -> PackedVector2Array:
	var c := centre(cell)
	var half := _r * 0.5
	return PackedVector2Array([c + Vector2(0.0, -_r), c + Vector2(0.5, -half),
		c + Vector2(0.5, half), c + Vector2(0.0, _r), c + Vector2(-0.5, half),
		c + Vector2(-0.5, -half)])


## Fractional axial from the point, then cube rounding: the component with the largest
## rounding error is re-derived from the other two.
func cell_at(p: Vector2) -> Vector2i:
	var x := float(p.x) - 0.5
	var y := float(p.y) - _r
	var fq := x - y * _r
	var fr := y * 2.0 * _r
	var fs := -fq - fr
	var q := roundf(fq)
	var r := roundf(fr)
	var s := roundf(fs)
	var dq := absf(q - fq)
	var dr := absf(r - fr)
	var ds := absf(s - fs)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))


func contains(cell: Vector2i) -> bool:
	var t := text_of(cell)
	return t.x >= 0 and t.y >= 0 and t.x < _w and t.y < _h


func cells() -> Array[Vector2i]:
	return _cells


func index(cell: Vector2i) -> int:
	var t := text_of(cell)
	return t.y * _w + t.x


func cell_count() -> int:
	return _w * _h


func bounds() -> Rect2:
	return Rect2(0.0, 0.0, _w + (0.5 if _h > 1 else 0.0), (_h - 1) * _pitch + 2.0 * _r)


## Odd-r text (x, y) -> axial. `y - (y & 1)` is even, so the division is exact.
@warning_ignore("integer_division")
func cell_of_text(x: int, y: int) -> Vector2i:
	return Vector2i(x - (y - (y & 1)) / 2, y)


@warning_ignore("integer_division")
func text_of(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x + (cell.y - (cell.y & 1)) / 2, cell.y)
