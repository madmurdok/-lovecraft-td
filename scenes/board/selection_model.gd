class_name SelectionModel
extends RefCounted
## LT-84 (LT-65 §3.4, guard G7): what the board's overlay shows for the open panel: the
## selected cell, its range ring (cells; 0 = none), the hovered build-list tower's ghost
## letter (LT-61 §7; "" = none) and what that tower casts over the ring (LT-70 §5: "light",
## "shadow" or ""; Board.cast_of). Owned by the Game; the panels (tower picker, tower panel,
## lighthouse panel) write it only through these methods, never the fields. Each method
## emits `changed` once when it changed a value, and the Board redraws on it.

signal changed

const NONE := Vector2i(-1, -1)

var cell := NONE
var range_cells := 0.0
var glyph := ""
var cast := ""


## A fresh selection of `p_cell`: no ring, no ghost letter, no cast (picker opened).
func show_cell(p_cell: Vector2i) -> void:
	_assign(p_cell, 0.0, "", "")


## Moves the selection to `p_cell` and keeps the ring, letter and cast.
func set_cell(p_cell: Vector2i) -> void:
	_assign(p_cell, range_cells, glyph, cast)


## The range ring and its cast; the cell and letter stay.
func set_ring(p_range: float, p_cast: String) -> void:
	_assign(cell, p_range, glyph, p_cast)


## The hovered build-list tower's preview: ring, ghost letter and cast; the cell stays.
func set_preview(p_range: float, p_glyph: String, p_cast: String) -> void:
	_assign(cell, p_range, p_glyph, p_cast)


## Nothing selected.
func clear() -> void:
	_assign(NONE, 0.0, "", "")


func _assign(p_cell: Vector2i, p_range: float, p_glyph: String, p_cast: String) -> void:
	if p_cell == cell and p_range == range_cells and p_glyph == glyph and p_cast == cast:
		return
	cell = p_cell
	range_cells = p_range
	glyph = p_glyph
	cast = p_cast
	changed.emit()
