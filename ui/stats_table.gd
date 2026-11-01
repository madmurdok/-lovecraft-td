class_name StatsTable
extends VBoxContainer
## LT-43 §1-§2, §4: the unified stats table of the side panel (a placed tower and the
## picker's hover card): a header row, then one row per TowerInfo.ROWS key (Special
## excluded: its lines go under the table), one value column per state ("Now | L2",
## "Now | A | B", "L1"). A row equal in every column is one cell across all columns; an
## upgrade cell that differs from Now is gold; lit Now cells (LT-43 §5) show their value
## with TowerInfo.LIT_MARK. Presentation only: the values come from TowerInfo.row_values.

const FONT_SIZE := 12
const FONT_SIZE_NARROW := 11  ## values at 3 columns, so "Single" / "Summon" keep a gap
const LABEL_W := 62  ## the row-label column (LT-43 §4)
const SEPARATION := 2
const COLOR_LABEL := Color(0.6, 0.6, 0.64)
const COLOR_DASH := Color(0.45, 0.45, 0.5)
const COLOR_VALUE := Color(0.93, 0.93, 0.95)
const COLOR_GAIN := Color(0.5, 0.85, 0.5)
const COLOR_LOSS := Color(0.95, 0.45, 0.4)
const COLOR_RESERVE := Color(0.72, 0.6, 0.95)  ## the occult violet
const COLOR_CHANGED := Color(0.95, 0.75, 0.3)  ## gold: an upgrade changes this cell
const COLOR_LIT := Color(1.0, 0.95, 0.6)  ## pale yellow: the beam changes this cell now
const COLOR_MUNDANE := Color(0.85, 0.8, 0.6)  ## = SidePanel.COLOR_ROLE
const COLOR_OCCULT := COLOR_RESERVE

## The rows the table shows (TowerInfo.ROWS without "special").
var row_keys: PackedStringArray = []
## Row key -> its value labels, left to right (one label when the row spans every column).
var cells: Dictionary[String, Array] = {}
var heads: Array[Label] = []
var _value_font := FONT_SIZE
var _shown := []  ## the last set_columns arguments: refresh() calls it every frame


func _init() -> void:
	add_theme_constant_override("separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row: Array in TowerInfo.ROWS:
		if row[0] != "special":
			row_keys.append(row[0])


## The semantic colour of `value` in row `key` (LT-43 §1 colours): dash dim, kill regen
## green, reserve violet, beam gain green / loss red, everything else plain.
static func color_for(key: String, value: String) -> Color:
	if value == TowerInfo.CELL_DASH:
		return COLOR_DASH
	match key:
		"kill":
			return COLOR_GAIN
		"reserve":
			return COLOR_RESERVE
		"beam":
			return COLOR_GAIN if value.begins_with("+") else COLOR_LOSS
	return COLOR_VALUE


## The colour of a tower kind's names and headers (mundane warm, occult violet).
static func kind_color(kind: String) -> Color:
	return COLOR_OCCULT if kind == "occult" else COLOR_MUNDANE


## Rebuilds the table: `heads[i]` over `cols[i]` (TowerInfo.row_values dictionaries);
## `lit` (row key -> text with LIT_MARK) overrides column 0. `head_color` colours the heads.
func set_columns(p_heads: PackedStringArray, cols: Array[Dictionary], lit: Dictionary = {},
		head_color := COLOR_MUNDANE) -> void:
	var args := [p_heads, cols, lit, head_color]
	if args == _shown:
		return
	_shown = args.duplicate(true)
	for c in get_children():
		remove_child(c)
		c.queue_free()
	cells.clear()
	heads.clear()
	var n := cols.size()
	_value_font = FONT_SIZE_NARROW if n >= 3 else FONT_SIZE
	var head_row := _row("Head")
	head_row.add_child(_label("", COLOR_LABEL, LABEL_W))
	for i in n:
		var h := _label(p_heads[i] if i < p_heads.size() else "", head_color)
		heads.append(h)
		head_row.add_child(h)
	for key: String in row_keys:
		var row := _row("Row_" + key)
		row.add_child(_label(_row_label(key), COLOR_LABEL, LABEL_W))
		var shown: Array[String] = []
		for i in n:
			shown.append(String(lit.get(key, cols[i][key])) if i == 0 else String(cols[i][key]))
		var labels: Array = []
		if n > 1 and shown.all(func(v: String) -> bool: return v == shown[0]):
			var span := _label(shown[0], color_for(key, shown[0]))
			span.size_flags_stretch_ratio = n
			labels.append(span)
			row.add_child(span)
		else:
			for i in n:
				var color := color_for(key, shown[i])
				if i == 0 and lit.has(key):
					color = COLOR_LIT
				elif i > 0 and shown[i] != String(cols[0][key]):
					color = COLOR_CHANGED
				var l := _label(shown[i], color)
				labels.append(l)
				row.add_child(l)
		cells[key] = labels


## The text a reader sees in row `key`, column `col` (a spanning cell answers every column).
func text_at(key: String, col: int) -> String:
	var labels: Array = cells.get(key, [])
	if labels.is_empty():
		return ""
	return (labels[0] if labels.size() == 1 else labels[col]).text


## Whether row `key` is one cell across every column.
func is_spanned(key: String) -> bool:
	return cells.get(key, []).size() == 1 and heads.size() > 1


static func _row_label(key: String) -> String:
	for row: Array in TowerInfo.ROWS:
		if row[0] == key:
			return row[1]
	return key


func _row(node_name: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.name = node_name
	r.add_theme_constant_override("separation", SEPARATION)
	add_child(r)
	return r


func _label(text: String, color: Color, width := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.clip_text = true
	l.add_theme_font_size_override("font_size", FONT_SIZE if width > 0 else _value_font)
	l.add_theme_color_override("font_color", color)
	if width > 0:
		l.custom_minimum_size.x = width
	else:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
