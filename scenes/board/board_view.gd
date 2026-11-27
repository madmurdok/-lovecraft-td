class_name BoardView
extends RefCounted
## LT-35 (LT-65 §3.3, block B4): the coordinate layer between the sim's cell units and the
## screen. The only holder of the pixel scale (CELL) and the board origin (guard G2): game
## code and ui/ deal in cells and ask this view for pixels, rects and picking.
## Frames:
## - cell units: the sim's world frame (GridTopology.centre, SimRoute.position_at, ranges);
## - world: the board node's local canvas, where the board layers draw (cell_to_world);
## - screen: the Game's canvas in base viewport units (1200x675 before stretch), where the
##   UI lays out and input arrives (cell_at_screen, unproject, cell_to_screen, world_rect).
## The cell -> world map is linear (no offset), so it also scales offsets and directions.
## Tiles come from GridTopology.polygon (cell_polygon, LT-77 Q4); layers draw them through
## fill_cell / outline_cell and anchor text and marks to cell_centre (LT-108 F2, guard G15).
## LT-66 §6.1: the map scrolls by `pan` (a screen offset): origin() = ORIGIN + pan, and every
## screen conversion (picking and drawing) goes through origin(), so they cannot disagree.
## LT-126 (LT-64 §1.3): the board-plane roles have names, all at identity today. Two forward
## maps for points, kept apart because b2 changes one and not the other:
## - ground (G): a point ON the board plane -> board-plane px. Tiles (cell_polygon, fill_cell,
##   outline_cell), rings (ring), the sea rect (ground_rect), lights, auras, ground discs and
##   ground fx (wave, beam, banish, blast, impacts, death mark) draw through it. Under b2 these
##   draw flat in the board SubViewport and the 3D plane foreshortens them, so ground STAYS
##   p * CELL (only the (a) fallback would make it the oblique map);
## - project (U/H): a point a figure, label or height stands on -> the upright layer's canvas
##   px (screen minus origin()). Enemy/ally bodies, tower glyph/pips/marks (cell_centre), the
##   HP bar and smoke lifts (project(p, h)), shot lines between figures, cell_to_screen
##   (picking, reveal, relic tokens) and the pan bounds (project_rect) go through it. Under b2
##   it CHANGES: camera.unproject_position of the lifted ground point, minus origin().
## Plus unproject (screen -> cells on the ground plane; b2: the ray-plane hit), depth (the
## draw-order key; b2: minus the camera distance) and ring (a ground ring through ground).
## Never call project at a G site: under b2 it would project a ground draw twice (once by
## the camera here, once by the plane the SubViewport is drawn on).

signal panned  ## the pan changed; Board moves its node to origin()

const CELL := 40.0  ## pixels per cell unit
const HUD_H := 48.0  ## the HUD bar's height on screen; LT-66: the side overlay starts below it
const ORIGIN := Vector2(0, HUD_H)  ## the board's top-left on screen: below the HUD bar
const OFF_BOARD := Vector2i(-1, -1)
const FOOTER_H := 67.0  ## the footer strip's height at the bottom of the base viewport
const PAN_MARGIN := 20.0  ## LT-66 §6.1: how far past the map's edge (px) a pan may show sea

var grid: GridTopology  ## the current map's topology; Board.sync_map keeps it current
var pan := Vector2.ZERO  ## LT-66 §6.1: screen offset of the map (base units); set_pan only


## LT-66 §6.1: the fixed screen frame the board may occupy (between the HUD bar and the
## footer, the full base width). It does not move with the pan.
static func play_rect() -> Rect2:
	var w := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	return Rect2(0, HUD_H, w, h - HUD_H - FOOTER_H)


## The board's rect on screen for `g` (static so layout helpers can ask without a board).
static func world_rect_for(g: GridTopology) -> Rect2:
	var b := g.bounds()
	return Rect2(ORIGIN + b.position * CELL, b.size * CELL)


## The map's rect on screen at the current pan: the bbox of the projected map (LT-126),
## equal to world_rect_for at pan 0 under today's identity projection.
func world_rect() -> Rect2:
	var r := project_rect(grid.bounds())
	r.position = ORIGIN + r.position
	r.position += pan
	return r


## The board node's position on screen: the origin moved by the pan.
func origin() -> Vector2:
	return ORIGIN + pan


## LT-66 §6.1: `p` clamped for the visible rect `visible` (pure). Per axis: when the map
## fits in `visible` the pan is 0 there; otherwise the map grown by PAN_MARGIN keeps covering
## `visible`.
func clamp_pan(p: Vector2, visible: Rect2) -> Vector2:
	if grid == null:
		return Vector2.ZERO
	var b := project_rect(grid.bounds())
	b.position += ORIGIN
	var m := b.grow(PAN_MARGIN)
	var out := Vector2.ZERO
	for axis in 2:
		if b.size[axis] <= visible.size[axis]:
			continue
		var lo := visible.end[axis] - m.end[axis]  # M.end + pan >= V.end
		var hi := visible.position[axis] - m.position[axis]  # M.pos + pan <= V.pos
		out[axis] = clampf(p[axis], lo, hi)
	return out


## LT-66 §6.1: stores the pan (callers clamp first) and emits `panned` when it changed.
func set_pan(p: Vector2) -> void:
	if p == pan:
		return
	pan = p
	panned.emit()


## The in-bounds cell under a screen point, or OFF_BOARD. The only input path to a cell.
func cell_at_screen(screen_pos: Vector2) -> Vector2i:
	if grid == null:
		return OFF_BOARD
	var c := grid.cell_at(unproject(screen_pos))
	return c if grid.contains(c) else OFF_BOARD


## LT-126 (LT-64 §1.3, role U/H): the ground point `p_cells`, lifted `h_cells` screen-up, as
## seen by the viewer -> the upright layer's canvas px. Upright sites (a figure or label
## anchored at p) call it with h 0, height sites with h. Its frame is screen minus origin():
## cell_to_screen adds origin() once and unproject removes it once, so a camera-based body
## (b2: camera.unproject_position returns screen px with the pan already in it) must
## subtract origin() here, or the pan is added twice. At identity it equals ground(p) and
## the lift is a pure screen-up offset. Not for G sites: use ground.
func project(p_cells: Vector2, h_cells := 0.0) -> Vector2:
	if h_cells == 0.0:
		return p_cells * CELL
	return p_cells * CELL + Vector2(0, -h_cells * CELL)


## LT-126 (LT-64 §1.3, role G): a point on the board plane (cell units) -> board-plane px,
## where every ground draw lands (see the header). Never lifted: heights are project(p, h).
## Unchanged under b2 (the ground draws flat in the SubViewport); at identity == project(p).
func ground(p_cells: Vector2) -> Vector2:
	return p_cells * CELL


## LT-126 (LT-64 §1.3, LT-66 §4): a screen point -> cell units on the ground plane, the one
## inverse of project (+ origin) for points. Picking: cell_at_screen = grid.cell_at(this).
func unproject(screen_pos: Vector2) -> Vector2:
	return (screen_pos - origin()) / CELL


## LT-126 (LT-64 §1.3): the draw-order key of a ground point: its nearness to the viewer
## along the view axis, larger is nearer and drawn later (EntityLayer.figure_before breaks
## ties by figure kind, then snapshot order). Visual only. The identity view looks straight
## down (orthographic), so every ground point is equally near: 0, and the tie order alone
## keeps today's draw order. Under b2 (§8.1) it is minus the camera distance.
func depth(_p_cells: Vector2) -> float:
	return 0.0


## LT-126 (LT-64 §1.3, role S over U): the bbox of a ground rect (cell units) as the viewer
## sees it, in project's frame: the min/max of its four projected corners (a quad under an
## angled view). The pan bounds (world_rect, clamp_pan) use it. A draw on the board plane
## takes ground_rect instead.
func project_rect(r_cells: Rect2) -> Rect2:
	var lo := project(r_cells.position)
	var hi := lo
	for q: Vector2 in [Vector2(r_cells.end.x, r_cells.position.y), r_cells.end,
			Vector2(r_cells.position.x, r_cells.end.y)]:
		var w := project(q)
		lo = lo.min(w)
		hi = hi.max(w)
	return Rect2(lo, hi - lo)


## LT-126 (LT-64 §1.3, role G): a ground rect (cell units) in board-plane px (the MapLayer sea
## backdrop). A plain scale today and under b2; the bbox of ground's corners otherwise.
func ground_rect(r_cells: Rect2) -> Rect2:
	var lo := ground(r_cells.position)
	var hi := lo
	for q: Vector2 in [Vector2(r_cells.end.x, r_cells.position.y), r_cells.end,
			Vector2(r_cells.position.x, r_cells.end.y)]:
		var w := ground(q)
		lo = lo.min(w)
		hi = hi.max(w)
	return Rect2(lo, hi - lo)


## LT-126 (LT-64 §1.3, role G): a ring on the ground (a range, aura or blast rim) of
## radius `r_cells` around `centre_cells`, a `width` px line of `points` segments on `ci`;
## `start`/`end` (radians) draw an arc of it. Through ground: a circle on the board plane,
## which b2's plane foreshortens to an ellipse; only the (a) fallback would draw a polygon
## through ground.
func ring(ci: CanvasItem, centre_cells: Vector2, r_cells: float, color: Color, width: float,
		points := 48, start := 0.0, end := TAU) -> void:
	ci.draw_arc(ground(centre_cells), cells_to_px(r_cells), start, end, points, color, width)


## Cell units (a point or an offset; the caller applies GridTopology.centre) -> world.
func cell_to_world(p_cells: Vector2) -> Vector2:
	return p_cells * CELL


## A ground point in cell units -> screen, where the viewer sees it (role P/S over U: picking,
## reveal, relic tokens). origin() is added here once; project's frame excludes it.
func cell_to_screen(p_cells: Vector2) -> Vector2:
	return origin() + project(p_cells)


## A length in cell units (radius, ring, mark size) -> pixels.
func cells_to_px(len_cells: float) -> float:
	return len_cells * CELL


## A length in pixels -> cell units.
func px_to_cells(len_px: float) -> float:
	return len_px / CELL


## The tile of `cell` in board-plane px (role G, through ground), from GridTopology.polygon,
## shrunk by `inset_px` towards the centre (LT-108 F2): each corner moves by (a - inset) / a
## with a the apothem (half the neighbour spacing, the same on square and hex). Multiply
## first, divide second, so square is exactly the tile rect grown by -inset.
func cell_polygon(cell: Vector2i, inset_px := 0.0) -> PackedVector2Array:
	var poly := grid.polygon(cell)
	var c := ground(grid.centre(cell))
	var a := cells_to_px(0.5)
	for i in poly.size():
		poly[i] = c + (ground(poly[i]) - c) * (a - inset_px) / a
	return poly


## The centre of `cell` as the viewer sees it (role U, through project): the anchor of text
## and marks on a tile (glyph, pips, corner marks, "L"). The tile itself is G (cell_polygon).
func cell_centre(cell: Vector2i) -> Vector2:
	return project(grid.centre(cell))


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
