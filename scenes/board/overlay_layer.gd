class_name OverlayLayer
extends BoardLayer
## LT-84 (LT-65 §3.4): the selection overlay, drawn last of the board layers: the selected
## cell's outline, the hovered build-list tower's ghost letter (LT-61 §7), the range ring
## and the dead-zone ring (LT-48); LT-66 §4: a ring round the monster card's enemy.
## Reads `board.selection` (SelectionModel, owned by the
## Game; the panels write it) and the sim; writes nothing.

const COLOR_SELECT := Color(1, 1, 1, 0.8)
const GHOST_GLYPH_ALPHA := 0.55  ## LT-61 §7: the selection's ghost letter
const DEAD_ZONE_DASH := 5.0  ## px per dash of the selected tower's dead-zone ring


func _draw() -> void:
	if not has_sim():
		return
	var sel := board.selection
	if sel.enemy_id != 0 and board.last_pos.has(sel.enemy_id):  # LT-66 §4: the shown monster
		draw_arc(view.cell_to_world(board.last_pos[sel.enemy_id]),
			view.cells_to_px(Board.PICK_RADIUS), 0, TAU, 32, COLOR_SELECT, 2.0)
	if game.snapshot.map.grid.contains(sel.cell):
		view.outline_cell(self, sel.cell, COLOR_SELECT, 2.0)
		if not sel.glyph.is_empty():  # LT-61 §7: placed like EntityLayer._draw_tower's letter
			draw_string(ThemeDB.fallback_font,
				view.cell_centre(sel.cell) + EntityLayer.GLYPH_OFFSET, sel.glyph,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(COLOR_SELECT, GHOST_GLYPH_ALPHA))
		if sel.range_cells > 0.0:
			var sc := view.cell_to_world(game.snapshot.map.grid.centre(sel.cell))
			draw_arc(sc, view.cells_to_px(sel.range_cells), 0, TAU, 48, COLOR_SELECT, 1.0)
			var dz := selected_dead_zone()
			if dz > 0.0:  # LT-48: the dead zone, a dashed ring over a faint fill
				draw_circle(sc, view.cells_to_px(dz), Color(Board.COLOR_LEAK, 0.08))
				_draw_dashed_circle(sc, view.cells_to_px(dz), Color(Board.COLOR_LEAK, 0.7))


## LT-48: the min_range (cells) of the tower on the selected cell while its range ring
## shows; 0 when none.
func selected_dead_zone() -> float:
	var sel := board.selection
	if sel.range_cells <= 0.0 or not has_sim():
		return 0.0
	var t := game.snapshot.tower_at(sel.cell)  # LT-76, LT-85
	return TowerRules.dead_zone(t.stats) if t != null else 0.0


func _draw_dashed_circle(c: Vector2, r: float, color: Color) -> void:
	var n := maxi(8, int(TAU * r / (DEAD_ZONE_DASH * 2.0)))
	for i in n:
		var a0 := TAU * float(i) / n
		draw_arc(c, r, a0, a0 + TAU / n * 0.5, 3, color, 1.5)


## LT-70 §5: the BUILD preview for tower `t`: the selection's cast when it is day (BUILD), a
## caster is selected (cast, range_cells) and `t` is another tower whose centre is in that
## radius (LightRules.covers, the sim's own test); "" otherwise, and always at night, where
## the real tint shows. EntityLayer tints the tower plate with it.
func preview_cast(t: TowerRecord) -> String:
	var sel := board.selection
	if sel.cast.is_empty() or sel.range_cells <= 0.0 or not has_sim():
		return ""
	var s := game.snapshot
	if s.phase != SimState.Phase.BUILD or not s.map.grid.contains(sel.cell) \
			or t.cell == sel.cell:
		return ""
	var covered := LightRules.covers(s.map.grid, sel.cell, sel.range_cells, t.centre)
	return sel.cast if covered else ""
