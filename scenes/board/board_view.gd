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
## Tiles come from GridTopology.polygon (cell_polygon, LT-77 Q4); layers draw them through
## fill_cell / outline_cell and anchor text and marks to cell_centre (LT-108 F2, guard G15).

const CELL := 40.0  ## pixels per cell unit
const HUD_H := 48.0  ## the HUD bar's height on screen; LT-66: the side overlay starts below it
const ORIGIN := Vector2(0, HUD_H)  ## the board's top-left on screen: below the HUD bar
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


## LT-66 §4: a screen point -> cell units (the inverse of cell_to_screen for points).
func screen_to_cells(screen_pos: Vector2) -> Vector2:
	return (screen_pos - ORIGIN) / CELL


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


## The tile of `cell` in world coordinates, from GridTopology.polygon, shrunk by `inset_px`
## towards the centre (LT-108 F2): each corner moves by (a - inset) / a with a the apothem
## (half the neighbour spacing, the same on square and hex). Multiply first, divide second,
## so square is exactly the tile rect grown by -inset.
func cell_polygon(cell: Vector2i, inset_px := 0.0) -> PackedVector2Array:
	var poly := grid.polygon(cell)
	var c := cell_centre(cell)
	var a := cells_to_px(0.5)
	for i in poly.size():
		poly[i] = c + (cell_to_world(poly[i]) - c) * (a - inset_px) / a
	return poly


## The centre of `cell` in world coordinates: the anchor of text and marks on a tile.
func cell_centre(cell: Vector2i) -> Vector2:
	return cell_to_world(grid.centre(cell))


## A centred outline of width `width_px` along the tile inset by `inset_px`, as n
## non-overlapping quads [outer i, outer i+1, inner i+1, inner i] (mitred corners on any
## polygon): outer at inset - w/2, inner at inset + w/2.
func outline_quads(cell: Vector2i, width_px: float, inset_px := 0.0) -> Array[PackedVector2Array]:
	var outer := cell_polygon(cell, inset_px - width_px * 0.5)
	var inner := cell_polygon(cell, inset_px + width_px * 0.5)
	var out: Array[PackedVector2Array] = []
	var n := outer.size()
	for i in n:
		var j := (i + 1) % n
		out.append(PackedVector2Array([outer[i], outer[j], inner[j], inner[i]]))
	return out


## Fills the tile of `cell` (inset by `inset_px`) on `ci`. Takes a CanvasItem because
## MapLayer and SeaFog are plain Node2D, not BoardLayers.
func fill_cell(ci: CanvasItem, cell: Vector2i, color: Color, inset_px := 0.0) -> void:
	ci.draw_colored_polygon(cell_polygon(cell, inset_px), color)


## Outlines the tile of `cell` (inset by `inset_px`) on `ci`: a centred `width_px` line.
func outline_cell(ci: CanvasItem, cell: Vector2i, color: Color, width_px: float,
		inset_px := 0.0) -> void:
	for q in outline_quads(cell, width_px, inset_px):
		ci.draw_colored_polygon(q, color)
