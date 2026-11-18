class_name LightRules
extends RefCounted
## LT-76 (LT-65 §3.2): config-derived light geometry rules, pure static, shared by the sim,
## the UI and the bot. State-derived light queries (light_at) live on the Simulation facade.


## LT-70 §2.1: the aura / cast radius test, |p - c|² <= range² (boundary inclusive), in
## 64-bit scalars.
static func in_cast_radius(c: Vector2, range_cells: float, p: Vector2) -> bool:
	var dx := float(p.x) - c.x
	var dy := float(p.y) - c.y
	return dx * dx + dy * dy <= range_cells * range_cells


## Whether a caster (aura, light or shadow tower) standing on `cell` with radius
## `range_cells` covers the point p (cell units): in_cast_radius of the cell centre. Works
## for a tower not built yet (the board's BUILD preview, the bot's placement score).
static func covers(grid: GridTopology, cell: Vector2i, range_cells: float, p: Vector2) -> bool:
	return in_cast_radius(grid.centre(cell), range_cells, p)
