class_name TowerPicker
extends PanelContainer
## Build view for a buildable cell (LT-7; LT-43 §3, owner Q1 "Широкая поверх поля"): one
## table over the board, towers as columns (mundane left, occult right, by TowerDef.kind,
## data order inside each kind, a band and a divider between), the TowerInfo.ROWS as rows.
## It sits in the half of the board away from the clicked cell, so the cell and its range
## ring stay visible. Each column is one button (Q5: one click builds); hovering it frames
## it, shows its range on the cell and emits hovered_changed (the side panel's L1 card).
## A column is disabled whenever Simulation.can_build refuses it: unaffordable dims it and
## reddens the cost, any other refusal puts the reason in the cost cell; a reserve that
## would take the sanity cap to 0 (LT-23 Q3) marks the Reserve cell red with "!".
## Cancel, Esc, or a click elsewhere on the board closes it. `visible` is "the build view
## is shown".

signal hovered_changed(def_id: String)  ## "" when no column is hovered

## Kept for callers of the LT-7 name; the texts live in TowerInfo.REASONS.
const REASONS := TowerInfo.REASONS

const GROUP_TITLES := {"mundane": "MUNDANE", "occult": "OCCULT"}
const STATUS_COLOR := Color(0.95, 0.55, 0.45)  ## refusal reason, unaffordable cost, "!"
const DIM := Color(1, 1, 1, 0.5)  ## a refused column's cells (the cost cell excepted)
const MAD_MARK := "!"  ## after the Reserve value when building drives you mad
const FONT_SIZE := 12
const NAME_FONT_MAX := 13  ## LT-43 §3: the name shrinks to fit its longest word
const NAME_FONT_MIN := 10
const COL_W := 88  ## LT-43 §3: 10 columns x 88 + the label column = the board width
const COL_W_MIN := 76  ## past 10 towers columns shrink to this, then the table scrolls
const LABEL_W := 64
const DIVIDER_W := 6
const ROW_H := 17
const NAME_H := 32  ## two name lines (WRAP_SPACING tightens them)
const SPECIAL_H := 30  ## two Special lines
const WRAP_SPACING := -4  ## line_spacing of the two-line cells, so two lines fit their row
const BAND_H := 22
const PAD := 3  ## column content inset (inside the button frame)
const MARGIN := 4  ## between the table and the board edge
const COLOR_FRAME := Color(0.95, 0.75, 0.3)  ## gold frame of the hovered column

var game: Game
var cell := Vector2i(-1, -1)
var buttons: Dictionary[String, Button] = {}  ## tower def id -> its column button
var costs: Dictionary[String, Label] = {}  ## tower def id -> its cost cell
## Tower def id -> ROWS key -> its value cell (the base text is TowerInfo.row_values).
var cells: Dictionary[String, Dictionary] = {}
var names: Dictionary[String, Label] = {}  ## tower def id -> its name label
var hovered := ""  ## def id of the hovered column, "" for none
var cancel_button: Button  ## top-left of the table
var col_w := COL_W
var _values: Dictionary[String, Dictionary] = {}  ## def id -> row_values of its L1
var _scroll: ScrollContainer


func _ready() -> void:
	visible = false
	theme = UiStyle.theme(FONT_SIZE)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(UiStyle.COLOR_BG, 0.94)
	bg.border_color = UiStyle.COLOR_BORDER
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(3)
	bg.set_content_margin_all(PAD)
	add_theme_stylebox_override("panel", bg)
	var map := game.sim.state.map
	var board_w := map.width * Board.CELL
	var by_kind := {}
	for kind in TowerDef.KINDS:
		by_kind[kind] = game.sim.config.towers.keys().filter(
			func(id: String) -> bool: return game.sim.config.towers[id].kind == kind)
	var n := game.sim.config.towers.size()
	var inner_w := board_w - 2 * MARGIN - 2 * PAD - 2
	var avail := inner_w - LABEL_W - DIVIDER_W * (TowerDef.KINDS.size() - 1)
	col_w = clampi(floori(float(avail) / maxi(n, 1)), COL_W_MIN, COL_W)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size.x = inner_w
	root.add_child(_scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 0)
	_scroll.add_child(body)

	var band := HBoxContainer.new()
	band.name = "Band"
	band.add_theme_constant_override("separation", 0)
	band.custom_minimum_size.y = BAND_H
	body.add_child(band)
	var cancel := SidePanel.make_button("CancelButton", close, "Cancel")
	cancel.size_flags_horizontal = Control.SIZE_FILL
	cancel.custom_minimum_size = Vector2(LABEL_W - 2, BAND_H - 2)
	cancel.alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel.autowrap_mode = TextServer.AUTOWRAP_OFF
	band.add_child(cancel)
	cancel_button = cancel
	band.add_child(_spacer(2))

	var table := HBoxContainer.new()
	table.name = "Table"
	table.add_theme_constant_override("separation", 0)
	body.add_child(table)
	table.add_child(_label_column())
	var first := true
	for kind in TowerDef.KINDS:
		var ids: Array = by_kind[kind]
		if ids.is_empty():
			continue
		if not first:
			band.add_child(_spacer(DIVIDER_W))
			var div := VSeparator.new()
			div.name = "Divider_" + kind
			div.custom_minimum_size.x = DIVIDER_W
			table.add_child(div)
		first = false
		var header := _cell("Group_" + kind, GROUP_TITLES[kind], StatsTable.kind_color(kind))
		header.custom_minimum_size = Vector2(col_w * ids.size(), BAND_H)
		header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		band.add_child(header)
		for id: String in ids:
			table.add_child(_column(id, game.sim.config.towers[id]))
	_fit_names()
	reset_size()


## The row labels: "Tower", "Cost", then TowerInfo.ROWS.
func _label_column() -> VBoxContainer:
	var v := _vbox("Labels")
	v.custom_minimum_size.x = LABEL_W
	v.add_child(_spacer(0, PAD))
	v.add_child(_sized(_cell("Label_name", "Tower", StatsTable.COLOR_LABEL), NAME_H))
	v.add_child(_sized(_cell("Label_cost", "Cost", StatsTable.COLOR_LABEL), ROW_H))
	for row: Array in TowerInfo.ROWS:
		var h := SPECIAL_H if row[0] == "special" else ROW_H
		v.add_child(_sized(_cell("Label_" + row[0], row[1], StatsTable.COLOR_LABEL), h))
	return v


## One tower: a button holding its name, cost and ROWS cells (L1, picker DPS range).
func _column(id: String, def: TowerDef) -> Button:
	var b := Button.new()
	b.name = "Tower_" + id
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(col_w, PAD * 2 + NAME_H + ROW_H * (TowerInfo.ROWS.size())
		+ SPECIAL_H)
	b.pressed.connect(_on_tower_pressed.bind(id))
	b.mouse_entered.connect(_on_hover.bind(id, true))
	b.mouse_exited.connect(_on_hover.bind(id, false))
	buttons[id] = b
	var v := _vbox("Cells")
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = PAD
	v.offset_top = PAD
	v.offset_right = -PAD
	v.offset_bottom = -PAD
	b.add_child(v)
	var name_label := _cell("Name", def.name, StatsTable.kind_color(def.kind))
	_wrap(name_label)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	names[id] = name_label
	v.add_child(_sized(name_label, NAME_H))
	var cost := _cell("Cost", TowerInfo.cost_text(def.cost), StatsTable.COLOR_VALUE)
	costs[id] = cost
	v.add_child(_sized(cost, ROW_H))
	var values := TowerInfo.row_values(def, def.levels[0], game.sim.config)
	_values[id] = values
	var by_row := {}
	for row: Array in TowerInfo.ROWS:
		var key: String = row[0]
		var l := _cell("Row_" + key, values[key], StatsTable.color_for(key, values[key]))
		if key == "special":
			_wrap(l)
			l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			l.add_theme_font_size_override("font_size", FONT_SIZE - 1)
		v.add_child(_sized(l, SPECIAL_H if key == "special" else ROW_H))
		by_row[key] = l
	cells[id] = by_row
	return b


## LT-43 §3: each name at the largest size in NAME_FONT_MAX..NAME_FONT_MIN where its
## longest word fits the column.
func _fit_names() -> void:
	for id: String in names:
		var l := names[id]
		var font := l.get_theme_font("font")
		var longest := 0.0
		var fs := NAME_FONT_MAX
		while fs > NAME_FONT_MIN:
			longest = 0.0
			for word in l.text.split(" "):
				longest = maxf(longest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT,
					-1, fs).x)
			if longest <= col_w - 2 * PAD:
				break
			fs -= 1
		l.add_theme_font_size_override("font_size", fs)


func open_for(p_cell: Vector2i) -> void:
	cell = p_cell
	_anchor(p_cell)
	visible = true
	refresh()
	game.board.selected_cell = p_cell
	game.board.selected_range = 0.0
	game.board.queue_redraw()


## LT-43 §3: the overlay in the board half away from `p_cell` (cell in the upper half ->
## at the bottom), centred across the board, in base viewport units.
func _anchor(p_cell: Vector2i) -> void:
	var map := game.sim.state.map
	reset_size()
	var board := Rect2(Game.BOARD_ORIGIN, Vector2(map.width, map.height) * Board.CELL)
	var x := board.position.x + floorf((board.size.x - size.x) / 2.0)
	var upper := p_cell.y < map.height / 2.0
	var y := board.end.y - size.y - MARGIN if upper else board.position.y + MARGIN
	position = Vector2(x, y)


func close() -> void:
	if not visible:
		return
	visible = false
	_set_hovered("")
	game.board.selected_cell = Vector2i(-1, -1)
	game.board.selected_range = 0.0
	game.board.queue_redraw()


## Re-evaluates every column against the sim (money and the phase change while it is open).
func refresh() -> void:
	if not visible:
		return
	for id in buttons:
		var def: TowerDef = game.sim.config.towers[id]
		var r := game.sim.can_build(id, cell)
		var b := buttons[id]
		b.disabled = r != Simulation.CommandResult.OK
		var cost := costs[id]
		var status := ""
		cost.text = TowerInfo.cost_text(def.cost)
		if r == Simulation.CommandResult.NOT_ENOUGH_GOLD:
			status = TowerInfo.reason(r)
		elif b.disabled:
			status = TowerInfo.reason(r)
			cost.text += " · " + status
		cost.add_theme_color_override("font_color",
			StatsTable.COLOR_VALUE if status.is_empty() else STATUS_COLOR)
		var mad := not b.disabled and game.sim.would_drive_mad_build(id)
		var reserve: Label = cells[id]["reserve"]
		var base: String = _values[id]["reserve"]
		reserve.text = base + MAD_MARK if mad else base
		reserve.add_theme_color_override("font_color",
			STATUS_COLOR if mad else StatsTable.color_for("reserve", base))
		var modulate_cells := DIM if b.disabled else Color.WHITE
		for key: String in cells[id]:
			cells[id][key].modulate = modulate_cells
		names[id].modulate = modulate_cells
		var tip := def.name + TowerInfo.DASH + TowerInfo.cost_text(def.cost)
		if not status.is_empty():
			tip += " (%s)" % status
		elif mad:
			tip += TowerInfo.MADNESS_WARNING
		b.tooltip_text = tip


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_tower_pressed(def_id: String) -> void:
	if game.build(def_id, cell) == Simulation.CommandResult.OK:
		close()


func _on_hover(def_id: String, entered: bool) -> void:
	if entered:
		_set_hovered(def_id)
	elif hovered == def_id:
		_set_hovered("")


## Frames the hovered column gold, shows its L1 range on the cell, tells the side panel.
func _set_hovered(def_id: String) -> void:
	if def_id == hovered:
		return
	if buttons.has(hovered):
		_frame(buttons[hovered], false)
	hovered = def_id
	var r := 0.0
	if buttons.has(def_id):
		_frame(buttons[def_id], true)
		r = game.sim.config.towers[def_id].levels[0].range_cells
	if visible and game.board.selected_range != r:
		game.board.selected_range = r
		game.board.queue_redraw()
	hovered_changed.emit(def_id)


func _frame(b: Button, on: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		if on:
			var box := (b.get_theme_stylebox(state) as StyleBoxFlat).duplicate() as StyleBoxFlat
			box.border_color = COLOR_FRAME
			box.set_border_width_all(2)
			b.add_theme_stylebox_override(state, box)
		else:
			b.remove_theme_stylebox_override(state)


func _vbox(node_name: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = node_name
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	return v


func _cell(node_name: String, text: String, color: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	return l


## Up to two word-wrapped lines (a clipped label never wraps).
func _wrap(l: Label) -> void:
	l.clip_text = false
	l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = 2
	l.add_theme_constant_override("line_spacing", WRAP_SPACING)


func _sized(l: Label, h: int) -> Label:
	l.custom_minimum_size.y = h
	return l


func _spacer(w: int, h := 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
