class_name BoardView
extends RefCounted
## LT-35 (LT-65 §3.3, block B4): the coordinate layer between the sim's cell units and the
## screen. The only holder of the pixel scale (CELL) and the board origin (guard G2): game
## code and ui/ deal in cells and ask this view for pixels, rects and picking.
## Frames:
## - cell units: the sim's world frame (GridTopology.centre, SimRoute.position_at, ranges);
## - world: the board node's local canvas, where the board layers draw (cell_to_world);
## - screen: the Game's canvas in base viewport units (1200x675 before stretch), where the
##   UI lays out and input arrives (cell_at_screen, cell_to_screen, world_rect).
## The cell -> world map is linear (no offset), so it also scales offsets and directions.
## Tiles come from GridTopology.polygon (cell_polygon); cell_rect is its bounding box, which
## for the square grid is the tile itself (LT-77 Q4: tile drawing from polygon() in B4).

const CELL := 40.0  ## pixels per cell unit
const ORIGIN := Vector2(0, 48)  ## the board's top-left on screen: below the HUD bar
const OFF_BOARD := Vector2i(-1, -1)

var grid: GridTopology  ## the current map's topology; Board.sync_map keeps it current


## The board's rect on screen for `g` (static so layout helpers can ask without a board).
static func world_rect_for(g: GridTopology) -> Rect2:
	var b := g.bounds()
	return Rect2(ORIGIN + b.position * CELL, b.size * CELL)


## The board's rect on screen: HUD, side panel, sanity FX and relic tokens anchor to it.
func world_rect() -> Rect2:
	return world_rect_for(grid)


## The board node's position on screen.
func origin() -> Vector2:
	return ORIGIN


## The in-bounds cell under a screen point, or OFF_BOARD. The only input path to a cell.
func cell_at_screen(screen_pos: Vector2) -> Vector2i:
	if grid == null:
		return OFF_BOARD
	var c := grid.cell_at((screen_pos - ORIGIN) / CELL)
	return c if grid.contains(c) else OFF_BOARD


## Cell units (a point or an offset; the caller applies GridTopology.centre) -> world.
func cell_to_world(p_cells: Vector2) -> Vector2:
	return p_cells * CELL


## Cell units -> screen (for UI overlays that point at the board).
func cell_to_screen(p_cells: Vector2) -> Vector2:
	return ORIGIN + cell_to_world(p_cells)


## A length in cell units (radius, ring, mark size) -> pixels.
func cells_to_px(len_cells: float) -> float:
	return len_cells * CELL


## A length in pixels -> cell units.
func px_to_cells(len_px: float) -> float:
	return len_px / CELL


## The tile of `cell` in world coordinates, from GridTopology.polygon.
func cell_polygon(cell: Vector2i) -> PackedVector2Array:
	var poly := grid.polygon(cell)
	for i in poly.size():
		poly[i] = cell_to_world(poly[i])
	return poly


## The bounding box of cell_polygon (square grid: the tile itself).
func cell_rect(cell: Vector2i) -> Rect2:
	var poly := cell_polygon(cell)
	var r := Rect2(poly[0], Vector2.ZERO)
	for i in range(1, poly.size()):
		r = r.expand(poly[i])
	return r
