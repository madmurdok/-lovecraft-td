class_name TowerPicker
extends VBoxContainer
## Build view for a buildable cell (LT-7; LT-61, owner "Список + карточка"): a list at the
## top of the side panel (SidePanel creates it above its Scroll), never over the board.
## A title line ("Build here" + Cancel), then the towers grouped by TowerDef.kind (mundane,
## then occult, data order inside each kind), one row each: short name, $, DPS and the
## TowerInfo.trait_text tag. Each row is one button (one click builds); hovering it frames
## it, shows its range ring and board letter (a ghost) on the cell and emits
## hovered_changed (the side panel's L1 card below the list). Leaving the row hides them.
## A row is disabled whenever Simulation.can_build refuses it: unaffordable dims it and
## reddens the cost; any other refusal (the same for every row) replaces the title with
## the reason and dims the rows; a reserve that would take the sanity cap to 0 (LT-23 Q3)
## marks the Trait cell red with "!". Past LIST_MAX_ROWS rows the rows scroll under the
## pinned first group line. Cancel, Esc, or a click elsewhere on the board closes it.
## `visible` is "the build view is shown".

signal hovered_changed(def_id: String)  ## "" when no row is hovered

## Kept for callers of the LT-7 name; the texts live in TowerInfo.REASONS.
const REASONS := TowerInfo.REASONS
const GROUP_TITLES := {"mundane": "MUNDANE", "occult": "OCCULT"}
const STATUS_COLOR := Color(0.95, 0.55, 0.45)  ## refusal reason, unaffordable cost, "!"
const DIM := Color(1, 1, 1, 0.5)  ## a refused row's cells (an unaffordable cost excepted)
const MAD_MARK := "!"  ## after the Trait's reserve when building drives you mad
const TITLE_TEXT := "Build here"
const FONT_SIZE := 12
const HEAD_FONT_SIZE := 11  ## group titles and column heads
const NAME_FONT_MIN := 10  ## past LIST_MAX_ROWS the names shrink to this, then ellipsis
## LT-61 §2: column widths at FONT_SIZE; their sum (176) is the panel's inner width.
const NAME_W := 62
const COST_W := 30
const COST_GAP := 4  ## between $ and DPS, so "$130" and "15–45" never read as one number
const DPS_W := 34
const TRAIT_W := 46
const TITLE_H := 22
const GROUP_H := 16
const ROW_H := 18
const SEPARATOR_H := 9
const LIST_MAX_ROWS := 14  ## LT-61 §5: more rows scroll inside the list
## LT-61 §3: column heads on the first group line: [text, tooltip, width].
const HEADS := [
	["$", "Cost", COST_W + COST_GAP],
	["DPS", "Damage per second", DPS_W],
	["Trait", "What sets it apart: Ground = never hits flyers, Blind N = can't fire within N"
		+ " cells, Line = pierces, Reveal = shows fakes, Res N = sanity reserve, ! = building"
		+ " it drives you mad", TRAIT_W],
]
## LT-61 §3: a row tooltip's full trait line, by the tag's first word ("%s" = its number).
const TRAIT_TIPS := {
	"Res": "Sanity reserve %s",
	"Ground": "Ground: never hits flyers",
	"Blind": "Blind %s: can't fire within %s",
	"Line": "Line: pierces",
	"Reveal": "Reveal: shows fakes",
	"Blast": "Blast: area damage",
}
const COLOR_FRAME := Color(0.95, 0.75, 0.3)  ## gold frame of the hovered row
const FRAME_FILL := Color(0.95, 0.75, 0.3, 0.12)  ## its faint fill

var game: Game
var cell := Vector2i(-1, -1)
var buttons: Dictionary[String, Button] = {}  ## tower def id -> its row button
var costs: Dictionary[String, Label] = {}  ## tower def id -> its cost cell
var cells: Dictionary[String, Dictionary] = {}  ## tower def id -> "dps"/"trait" -> its cell
var names: Dictionary[String, Label] = {}  ## tower def id -> its name label
var hovered := ""  ## def id of the hovered row, "" for none
var title_label: Label  ## "Build here", or the refusal every row shares
var cancel_button: Button  ## right of the title
var rows_scroll: ScrollContainer  ## the rows (and later group lines) below the pinned line
var _traits: Dictionary[String, String] = {}  ## def id -> trait_text of its L1


func _ready() -> void:
	visible = false
	theme = UiStyle.theme(FONT_SIZE)
	add_theme_constant_override("separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title_line := HBoxContainer.new()
	title_line.name = "TitleLine"
	title_line.custom_minimum_size.y = TITLE_H
	add_child(title_line)
	title_label = _cell("Title", TITLE_TEXT, Color.WHITE)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_line.add_child(title_label)
	cancel_button = SidePanel.make_button("CancelButton", close, "Cancel")
	cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	cancel_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel_button.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_line.add_child(cancel_button)

	var towers := game.sim.config.towers
	var groups: Array[Array] = []  ## [kind, ids]
	for kind in TowerDef.KINDS:
		var ids: Array = towers.keys().filter(
			func(id: String) -> bool: return towers[id].kind == kind)
		if not ids.is_empty():
			groups.append([kind, ids])
	rows_scroll = ScrollContainer.new()
	rows_scroll.name = "Rows"
	rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body := _vbox("Body")
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_scroll.add_child(body)
	var n_rows := towers.size()
	var inner_groups := 0
	for i in groups.size():
		var kind: String = groups[i][0]
		if i == 0:
			add_child(_head_line(kind, true))  # pinned above the scrolling rows
		else:
			body.add_child(_head_line(kind, false))
			inner_groups += 1
		for id: String in groups[i][1]:
			body.add_child(_row(id, towers[id]))
	add_child(rows_scroll)
	var scrolling := n_rows > LIST_MAX_ROWS
	# Past LIST_MAX_ROWS the rows lose the scrollbar's width; the pinned heads do too.
	var bar_w := scrollbar_w() if scrolling else 0
	if bar_w > 0:
		var pinned: HBoxContainer = get_node("Group_" + String(groups[0][0]))
		pinned.add_child(_spacer(bar_w))
		# The title loses that width too: one size down keeps "MUNDANE" whole.
		var title: Label = pinned.get_node("Title")
		title.add_theme_font_size_override("font_size", HEAD_FONT_SIZE - 1)
	rows_scroll.custom_minimum_size.y = mini(n_rows, LIST_MAX_ROWS) * ROW_H \
		+ inner_groups * GROUP_H
	var sep := HSeparator.new()
	sep.name = "Separator"
	sep.custom_minimum_size.y = SEPARATOR_H
	add_child(sep)
	_fit_names(bar_w)


## A group line: the kind's title, and (`with_heads`) the column heads with tooltips.
func _head_line(kind: String, with_heads: bool) -> HBoxContainer:
	var line := _hbox("Group_" + kind)
	line.custom_minimum_size.y = GROUP_H
	var title := _cell("Title", GROUP_TITLES[kind], StatsTable.kind_color(kind))
	title.add_theme_font_size_override("font_size", HEAD_FONT_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(title)
	if with_heads:
		for head: Array in HEADS:
			var h := _cell("Head_" + head[0], head[0], StatsTable.COLOR_LABEL)
			h.add_theme_font_size_override("font_size", HEAD_FONT_SIZE)
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.custom_minimum_size.x = head[2]
			h.tooltip_text = head[1]
			h.mouse_filter = Control.MOUSE_FILTER_STOP
			line.add_child(h)
	return line


## One tower: a flat button holding its short name, cost, L1 DPS and trait.
func _row(id: String, def: TowerDef) -> Button:
	var b := Button.new()
	b.name = "Tower_" + id
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = ROW_H
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_on_tower_pressed.bind(id))
	b.mouse_entered.connect(_on_hover.bind(id, true))
	b.mouse_exited.connect(_on_hover.bind(id, false))
	_frame(b, false)
	buttons[id] = b
	var h := _hbox("Cells")
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(h)
	var s: TowerDef.Level = def.levels[0]
	var name_label := _cell("Name", def.short_name, StatsTable.kind_color(def.kind))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names[id] = name_label
	h.add_child(name_label)
	var cost := _value("Cost", TowerInfo.cost_text(def.cost), StatsTable.COLOR_VALUE, COST_W)
	costs[id] = cost
	h.add_child(cost)
	var gap := _spacer(COST_GAP)
	gap.name = "Gap"
	h.add_child(gap)
	var dps_text := TowerInfo.dps_text(s, game.sim.config)
	var dps := _value("Dps", dps_text, StatsTable.color_for("dps", dps_text), DPS_W)
	h.add_child(dps)
	_traits[id] = TowerInfo.trait_text(def, s)
	var trait_cell := _value("Trait", _traits[id], _trait_color(_traits[id]), TRAIT_W)
	h.add_child(trait_cell)
	cells[id] = {"dps": dps, "trait": trait_cell}
	return b


## LT-61 §5: each name at FONT_SIZE, shrunk towards NAME_FONT_MIN while it is wider than
## NAME_W less `bar_w` (the scrollbar while the rows scroll); still too wide, it ends in an
## ellipsis.
func _fit_names(bar_w: int) -> void:
	var avail := NAME_W - bar_w
	for id: String in names:
		var l := names[id]
		var font := l.get_theme_font("font")
		var fs := FONT_SIZE
		while fs > NAME_FONT_MIN and font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				fs).x > avail:
			fs -= 1
		l.add_theme_font_size_override("font_size", fs)


func open_for(p_cell: Vector2i) -> void:
	cell = p_cell
	visible = true
	refresh()
	game.board.selected_cell = p_cell
	game.board.selected_range = 0.0
	game.board.selected_glyph = ""
	game.board.queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	_set_hovered("")
	game.board.selected_cell = Vector2i(-1, -1)
	game.board.selected_range = 0.0
	game.board.selected_glyph = ""
	game.board.queue_redraw()


## Re-evaluates every row against the sim (money and the phase change while it is open).
func refresh() -> void:
	if not visible:
		return
	var shared := Simulation.CommandResult.OK  ## LT-61 §6: the first refusal not about gold
	var any_ok := false
	for id in buttons:
		var def: TowerDef = game.sim.config.towers[id]
		var r := game.sim.can_build(id, cell)
		var b := buttons[id]
		b.disabled = r != Simulation.CommandResult.OK
		var poor := r == Simulation.CommandResult.NOT_ENOUGH_GOLD
		if b.disabled and not poor and shared == Simulation.CommandResult.OK:
			shared = r
		any_ok = any_ok or not b.disabled
		var cost := costs[id]
		cost.add_theme_color_override("font_color",
			STATUS_COLOR if poor else StatsTable.COLOR_VALUE)
		var mad := not b.disabled and game.sim.would_drive_mad_build(id)
		var trait_cell: Label = cells[id]["trait"]
		var base := _traits[id]
		trait_cell.text = base + MAD_MARK if mad else base
		trait_cell.add_theme_color_override("font_color",
			STATUS_COLOR if mad else _trait_color(base))
		var dim := DIM if b.disabled else Color.WHITE
		for key: String in cells[id]:
			cells[id][key].modulate = dim
		names[id].modulate = dim
		cost.modulate = Color.WHITE if poor else dim
		var tip := def.name + TowerInfo.DASH + TowerInfo.cost_text(def.cost)
		if b.disabled:
			tip += " (%s)" % TowerInfo.reason(r)
		elif mad:
			tip += TowerInfo.MADNESS_WARNING
		var trait_tip := _trait_tip(base)
		if not trait_tip.is_empty():
			tip += "\n" + trait_tip
		b.tooltip_text = tip
	# Every row poor: can_build reports gold before the phase, so the title says the night
	# itself, or by day that nothing is affordable.
	if shared == Simulation.CommandResult.OK and not any_ok and not buttons.is_empty():
		shared = Simulation.CommandResult.NOT_BUILD_PHASE \
			if game.sim.state.phase == SimState.Phase.WAVE \
			else Simulation.CommandResult.NOT_ENOUGH_GOLD
	var refused := shared != Simulation.CommandResult.OK
	var why := TowerInfo.reason(shared)
	title_label.text = why.left(1).to_upper() + why.substr(1) if refused else TITLE_TEXT
	title_label.add_theme_color_override("font_color", STATUS_COLOR if refused else Color.WHITE)


## The full words of a trait tag ("Blind 2" -> "Blind 2: can't fire within 2 cells").
static func _trait_tip(tag: String) -> String:
	var words := tag.split(" ")
	var tip: String = TRAIT_TIPS.get(words[0], "")
	if tip.is_empty() or words.size() < 2:
		return tip
	if words[0] == "Blind":  # the number twice: "Blind 1: can't fire within 1 cell"
		return tip % [words[1], TowerInfo.cells_text(words[1])]
	return tip.replace("%s", words[1])


## Reserve violet for an occult "Res N", the dash dim, any other tag plain.
static func _trait_color(tag: String) -> Color:
	return StatsTable.color_for("reserve" if tag.begins_with("Res ") else "trait", tag)


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


## Frames the hovered row gold, shows its L1 range ring and its letter (a ghost) on the
## cell, tells the side panel.
func _set_hovered(def_id: String) -> void:
	if def_id == hovered:
		return
	if buttons.has(hovered):
		_frame(buttons[hovered], false)
	hovered = def_id
	var r := 0.0
	var glyph := ""
	if buttons.has(def_id):
		_frame(buttons[def_id], true)
		var def: TowerDef = game.sim.config.towers[def_id]
		r = def.levels[0].range_cells
		glyph = def.glyph
	if visible and (game.board.selected_range != r or game.board.selected_glyph != glyph):
		game.board.selected_range = r
		game.board.selected_glyph = glyph
		game.board.queue_redraw()
	hovered_changed.emit(def_id)


## LT-61 §7: a hovered row is a 1 px gold frame over a faint gold fill; any other row has
## no box at all (the cells carry its state).
func _frame(b: Button, on: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = FRAME_FILL if on else Color.TRANSPARENT
	box.border_color = COLOR_FRAME if on else Color.TRANSPARENT
	box.set_border_width_all(1 if on else 0)
	box.set_content_margin_all(0)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(state, box)


func _vbox(node_name: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = node_name
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	return v


func _hbox(node_name: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = node_name
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 0)
	return h


func _cell(node_name: String, text: String, color: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	return l


## The rows' vertical scrollbar width in px (its theme minimum).
func scrollbar_w() -> int:
	return ceili(rows_scroll.get_v_scroll_bar().get_combined_minimum_size().x)


func _spacer(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = w
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A right-aligned value cell `w` px wide.
func _value(node_name: String, text: String, color: Color, w: int) -> Label:
	var l := _cell(node_name, text, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size.x = w
	return l
