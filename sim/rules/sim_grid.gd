class_name SimGrid
extends RefCounted
## LT-76 (LT-65 §3.2, rule #11): the one cell-centre rule of the square grid, in cell units
## (the frame of SimRoute.position_at and SimTower.centre). A plain helper only: neighbours,
## distance and cell polygons belong to the later GridTopology block (LT-77).


## The centre of `cell`: (x + 0.5, y + 0.5).
static func centre(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5)
