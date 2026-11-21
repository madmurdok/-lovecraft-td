@abstract
class_name GridTopology
extends RefCounted
## LT-77: cell geometry behind one interface. Pure, immutable after construction, no RNG.
## Frame: "cell units", the world frame of the sim (SimRoute.position_at, SimTower.centre,
## every range_cells). The unit is the distance between the centres of two neighbouring cells.
## Cell id is a Vector2i for every topology (square: (x, y)).
## Range tests between continuous points are NOT topology methods; they take centre() points.
## Order contracts: cells() and neighbours() orders are fixed (golden replay and the bot
## tie-break depend on them). No trig: use constants (sqrt computed once in the constructor).


## "square" etc., for the config check and error text.
@abstract func kind() -> String


## The centre of `cell` in cell units.
@abstract func centre(cell: Vector2i) -> Vector2


## In-bounds neighbours of `cell` in a fixed order.
@abstract func neighbours(cell: Vector2i) -> Array[Vector2i]


## Euclidean distance between the centres of two cells, computed in 64-bit scalars.
@abstract func distance(a: Vector2i, b: Vector2i) -> float


## Graph hops between two cells on an empty board.
@abstract func steps(a: Vector2i, b: Vector2i) -> int


## Corners of the cell in cell units, screen-clockwise.
@abstract func polygon(cell: Vector2i) -> PackedVector2Array


## The cell under a world point (cell units); may be out of bounds.
@abstract func cell_at(p: Vector2) -> Vector2i


@abstract func contains(cell: Vector2i) -> bool


## Every cell in a fixed (row-major) order; cached.
@abstract func cells() -> Array[Vector2i]


## Storage slot of `cell` for per-cell arrays, in 0 .. cell_count() - 1.
@abstract func index(cell: Vector2i) -> int


@abstract func cell_count() -> int


## World rect in cell units.
@abstract func bounds() -> Rect2


## LT-108 F6: the cell id of the map text's (column x, row y). Identity unless a topology's
## ids differ from the text layout (HexGrid: axial from odd-r rows).
func cell_of_text(x: int, y: int) -> Vector2i:
	return Vector2i(x, y)


## LT-108 F6: the map text's (column, row) of `cell`; the inverse of cell_of_text.
func text_of(cell: Vector2i) -> Vector2i:
	return cell
