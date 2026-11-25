class_name TowerPicker
extends VBoxContainer
## Build view for a buildable cell (LT-7; LT-61, owner "Список + карточка"): a list at the
## top of the side panel (SidePanel creates it above its Scroll), never over the board.
## A title line ("Build here" + Cancel), then the towers grouped by TowerDef.kind (mundane,
## then occult, data order inside each kind), one row each: short name, $, DPS and the
## TowerText.trait_text tag. Each row is one button (one click builds); hovering it frames
## it, shows its range ring and board letter (a ghost) on the cell and emits
## hovered_changed (the side panel's L1 card below the list). Leaving the row hides them.
## A row is disabled whenever Simulation.can_build refuses it: unaffordable dims it and
## reddens the cost; any other refusal (the same for every row) replaces the title with
## the reason and dims the rows; a reserve that would take the sanity cap to 0 (LT-23 Q3)
## marks the Trait cell red with "!". Past LIST_MAX_ROWS rows (fewer by night, LT-113: the
## post rows take their slots) the rows scroll under the pinned first group line. Cancel, Esc, or a click elsewhere on the board closes it.
## LT-32 §4 (crew on): by day a row's cost is Simulation.build_price (the reserve covers
## crew). LT-118: a crewed row also shows a small crew mark at the right of its name cell
## (by day): "res 2" (the reserve covers the crew), "hire 2" (hired at build) or
## "res 1·hire 1", and its tooltip's last line splits the price into the frame and the
## crew (crew_price_text). At night a post
## section above the rows lists one "Post: 2 Harpooners (4 in reserve)" row per crew kind,
## enabled when Simulation.can_deploy accepts it; a click deploys that reserve post (not a
## tower: no glyph ghost, its hover card is the post's). The title then reads "Deploy a
## reserve post" while some post can be deployed; otherwise it keeps the towers' refusal.
## `visible` is "the build view is shown".

signal hovered_changed(def_id: String)  ## "" when no row is hovered

const GROUP_TITLES := {"mundane": "MUNDANE", "occult": "OCCULT"}
const STATUS_COLOR := Color(0.95, 0.55, 0.45)  ## refusal reason, unaffordable cost, "!"
const DIM := Color(1, 1, 1, 0.5)  ## a refused row's cells (an unaffordable cost excepted)
const MAD_MARK := "!"  ## after the Trait's reserve when building drives you mad
const TITLE_TEXT := "Build here"
const POST_TITLE_TEXT := "Deploy a reserve post"  ## LT-32 §4: the title at night, crew on
const POST_PREFIX := "post:"  ## LT-32: hover id of a post row (+ crew kind), see show_card
const G_ROWS := 1  ## LT-78: the one field group (rows 28-33 of the design note's §3)
## LT-78 §3: sim events that may change can_build or would_drive_mad_build for some row.
const REFRESH_ON: Dictionary[SimEvent.Type, int] = {
	SimEvent.Type.GOLD_CHANGED: G_ROWS,
	SimEvent.Type.BUILD_STARTED: G_ROWS,
	SimEvent.Type.WAVE_STARTED: G_ROWS,
	SimEvent.Type.WAVE_CLEARED: G_ROWS,
	SimEvent.Type.OUTCOME: G_ROWS,
	SimEvent.Type.TOWER_BUILT: G_ROWS,
	SimEvent.Type.TOWER_SOLD: G_ROWS,
	SimEvent.Type.SANITY_CAP_CHANGED: G_ROWS,
	SimEvent.Type.SANITY_STATE_CHANGED: G_ROWS,
	SimEvent.Type.CREW_CHANGED: G_ROWS,  # LT-32: build_price and the post rows
	SimEvent.Type.POST_DEPLOYED: G_ROWS,
	SimEvent.Type.POST_REMOVED: G_ROWS,
	SimEvent.Type.TOWER_LIFTED: G_ROWS,  # LT-117: a dropped tower may occupy the open cell
}
const FONT_SIZE := 12
const HEAD_FONT_SIZE := 11  ## group titles and column heads
const NAME_FONT_MIN := 10  ## past LIST_MAX_ROWS the names shrink to this, then ellipsis
## LT-61 §2: column widths at FONT_SIZE; their sum (224) is the panel's inner width.
const NAME_W := 110  ## 62 at the 192 px panel; LT-59 gives the name the extra 48 px of the 240 px panel
const COST_W := 30
const COST_GAP := 4  ## between $ and DPS, so "$130" and "15–45" never read as one number
const DPS_W := 34
const TRAIT_W := 46
const TITLE_H := 22
const GROUP_H := 16
const ROW_H := 18
const SEPARATOR_H := 9
## LT-61 §5: more rows scroll inside the list. LT-113: 10, not 14: the list stays at the
## shipped roster's height, so the tallest L1 card below it fits the panel unscrolled.
## LT-113 (owner): night post rows take list slots (posts + list rows <= LIST_MAX_ROWS),
## so the card fits by night too; the list keeps at least LIST_MIN_ROWS rows.
const LIST_MAX_ROWS := 10
const LIST_MIN_ROWS := 4
## LT-118: the crew mark at the right of a crewed row's name; at 9 px the widest mark
## ("res 1·hire 1") leaves the short names their full FONT_SIZE.
const CREW_FONT_SIZE := 9
const CREW_GAP := 3  ## LT-118: between a name and its crew mark
const CREW_MARK_COLOR := Color(0.6, 0.8, 0.95)  ## LT-118: muted blue, apart from $ and names
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
## LT-118: crewed tower def id -> its crew mark (a child of the name label, right-aligned);
## crew on only.
var crew_marks: Dictionary[String, Label] = {}
var hovered := ""  ## def id of the hovered row, "" for none
var title_label: Label  ## "Build here", or the refusal every row shares
var cancel_button: Button  ## right of the title
var rows_scroll: ScrollContainer  ## the rows (and later group lines) below the pinned line
var post_box: VBoxContainer  ## LT-32: the night post section (crew on only), above the rows
var post_buttons: Dictionary[String, Button] = {}  ## LT-32: crew kind -> its post row
var _traits: Dictionary[String, String] = {}  ## def id -> trait_text of its L1
var refresh_count := 0  ## LT-78 §8 B1: row rebuilds so far (refresh and flush)
var _dirty := 0  ## LT-78: G_ROWS when an event marked the rows since the last flush
var list_rows := 0  ## LT-113: rows the list shows unscrolled now (LIST_MAX_ROWS less posts)
var _marks_shown := true  ## LT-113: crew marks show (by day); names reserve their room only then
var _n_rows := 0  ## tower rows in the list
var _inner_groups := 0  ## group lines inside the scrolled body
var _pinned: HBoxContainer  ## the first group line, pinned above the rows
var _bar_spacer: Control  ## in _pinned while the list scrolls (the scrollbar's width)


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
	if game.sim.config.crew_on():
		_make_posts()

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
	_n_rows = n_rows
	_inner_groups = inner_groups
	_pinned = get_node("Group_" + String(groups[0][0]))
	var sep := HSeparator.new()
	sep.name = "Separator"
	sep.custom_minimum_size.y = SEPARATOR_H
	add_child(sep)
	_layout_rows()


## LT-113: sizes the list to LIST_MAX_ROWS rows less the shown post rows (at least
## LIST_MIN_ROWS), so the picker keeps one height by day and by night; past that the rows
## scroll inside the list. Re-run when the post section shows or hides.
func _layout_rows() -> void:
	var posts := post_box.get_child_count() if post_box != null and post_box.visible else 0
	var cap := maxi(LIST_MAX_ROWS - posts, LIST_MIN_ROWS)
	var marks := game.snapshot.phase != SimState.Phase.WAVE  # as refresh() shows them
	if cap == list_rows and marks == _marks_shown:
		return
	list_rows = cap
	_marks_shown = marks
	rows_scroll.custom_minimum_size.y = mini(_n_rows, cap) * ROW_H + _inner_groups * GROUP_H
	# Past `cap` the rows lose the scrollbar's width; the pinned heads do too.
	var bar_w := scrollbar_w() if _n_rows > cap else 0
	var title: Label = _pinned.get_node("Title")
	if bar_w > 0 and _bar_spacer == null:
		_bar_spacer = _spacer(bar_w)
		_pinned.add_child(_bar_spacer)
		# The title loses that width too: one size down keeps "MUNDANE" whole.
		title.add_theme_font_size_override("font_size", HEAD_FONT_SIZE - 1)
	elif bar_w == 0 and _bar_spacer != null:
		_pinned.remove_child(_bar_spacer)
		_bar_spacer.free()
		_bar_spacer = null
		title.add_theme_font_size_override("font_size", HEAD_FONT_SIZE)
	_fit_names(bar_w)


## LT-32 §4: the post section, one row per crew kind (crew.json order), hidden by day.
func _make_posts() -> void:
	post_box = _vbox("Posts")
	post_box.visible = false
	add_child(post_box)
	for kind: String in game.sim.config.crew.crews:
		var b := Button.new()
		b.name = "Post_" + kind
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = ROW_H
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.add_theme_color_override("font_color", StatsTable.kind_color("mundane"))
		b.pressed.connect(_on_post_pressed.bind(kind))
		var id := POST_PREFIX + kind
		b.mouse_entered.connect(_on_hover.bind(id, true))
		b.mouse_exited.connect(_on_hover.bind(id, false))
		_frame(b, false)
		post_buttons[kind] = b
		post_box.add_child(b)


## LT-32 §4: "2 Harpooners, fighting as riflemen" (the post card's role line).
static func post_crew_text(sim: Simulation, kind: String) -> String:
	return "%d %s, fighting as riflemen" % [sim.config.crew.post_of(kind).crew,
		sim.config.crew.crews[kind].name]


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
	if game.sim.crew_need(id) > 0:
		var mark := _cell("CrewMark", "", CREW_MARK_COLOR)
		mark.add_theme_font_size_override("font_size", CREW_FONT_SIZE)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		mark.clip_text = false
		mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		name_label.add_child(mark)
		crew_marks[id] = mark
	var cost := _value("Cost", TowerText.cost_text(def.cost), StatsTable.COLOR_VALUE, COST_W)
	costs[id] = cost
	h.add_child(cost)
	var gap := _spacer(COST_GAP)
	gap.name = "Gap"
	h.add_child(gap)
	var dps_text := TowerText.dps_text(s, game.sim.config)
	var dps := _value("Dps", dps_text, StatsTable.color_for("dps", dps_text), DPS_W)
	h.add_child(dps)
	_traits[id] = TowerText.trait_text(def, s)
	var trait_cell := _value("Trait", _traits[id], _trait_color(_traits[id]), TRAIT_W)
	h.add_child(trait_cell)
	cells[id] = {"dps": dps, "trait": trait_cell}
	return b


## LT-61 §5: each name at FONT_SIZE, shrunk towards NAME_FONT_MIN while it is wider than
## NAME_W less `bar_w` (the scrollbar while the rows scroll); still too wide, it ends in an
## ellipsis. LT-118: a crewed row's name also leaves room for its widest crew mark (the
## mixed one), so the mark never covers the name whatever the reserve holds.
func _fit_names(bar_w: int) -> void:
	for id: String in names:
		var l := names[id]
		var avail := NAME_W - bar_w
		if crew_marks.has(id) and not _marks_shown:  # LT-113: by night the name takes it all
			l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		elif crew_marks.has(id):
			var m := crew_marks[id]
			var need := game.sim.crew_need(id)
			var widest := crew_mark_text(maxi(need - 1, 0), mini(need, 1))
			var room := ceili(m.get_theme_font("font").get_string_size(widest,
				HORIZONTAL_ALIGNMENT_LEFT, -1, CREW_FONT_SIZE).x) + CREW_GAP
			avail -= room
			# The name's text (and its ellipsis) ends left of the mark.
			var box := StyleBoxEmpty.new()
			box.content_margin_right = room
			l.add_theme_stylebox_override("normal", box)
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
	game.selection.show_cell(p_cell)


func close() -> void:
	if not visible:
		return
	visible = false
	_set_hovered("")
	game.selection.clear()


## LT-78 §1: marks the rows when `ev` may change them; flush() rebuilds them once per drain.
func on_event(ev: SimEvent) -> void:
	_dirty |= REFRESH_ON.get(ev.type, 0)


## LT-78 §1: rebuilds the rows if an event marked them; a hidden picker drops the mark
## (open_for syncs it).
func flush() -> void:
	if _dirty == 0:
		return
	_dirty = 0
	refresh()


## Re-evaluates every row against the sim (money and the phase change while it is open).
func refresh() -> void:
	_dirty = 0
	if not visible:
		return
	refresh_count += 1
	var shared := SimCommand.CommandResult.OK  ## LT-61 §6: the first refusal not about gold
	var any_ok := false
	for id in buttons:
		var def: TowerDef = game.sim.config.towers[id]
		var r := game.sim.can_build(id, cell)
		var b := buttons[id]
		b.disabled = r != SimCommand.CommandResult.OK
		var poor := r == SimCommand.CommandResult.NOT_ENOUGH_GOLD
		if b.disabled and not poor and shared == SimCommand.CommandResult.OK:
			shared = r
		any_ok = any_ok or not b.disabled
		var cost := costs[id]
		var price := game.sim.build_price(id)  # LT-32: def.cost unless the reserve has crew
		cost.text = TowerText.cost_text(price)
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
		var tip := def.name + TowerText.DASH + TowerText.cost_text(price)
		if b.disabled:
			tip += " (%s)" % CommandText.reason(r)
		elif mad:
			tip += TowerText.MADNESS_WARNING
		if crew_marks.has(id):  # LT-118: where the crew comes from
			var from_reserve := _from_reserve(id)
			var hired := game.sim.crew_need(id) - from_reserve
			crew_marks[id].text = crew_mark_text(from_reserve, hired)
			crew_marks[id].visible = game.snapshot.phase != SimState.Phase.WAVE
		var trait_tip := _trait_tip(base)
		if not trait_tip.is_empty():
			tip += "\n" + trait_tip
		if crew_marks.has(id):  # LT-118: the price split, after the trait line (LT-61 §3)
			tip += "\n" + crew_price_text(game.sim, id)
		b.tooltip_text = tip
	# Every row poor: can_build reports gold before the phase, so the title says the night
	# itself, or by day that nothing is affordable.
	if shared == SimCommand.CommandResult.OK and not any_ok and not buttons.is_empty():
		shared = SimCommand.CommandResult.NOT_BUILD_PHASE \
			if game.snapshot.phase == SimState.Phase.WAVE \
			else SimCommand.CommandResult.NOT_ENOUGH_GOLD
	# LT-32: once some post can be deployed the title invites it; otherwise it keeps the
	# towers' refusal ("Only by day") and each dimmed post row says its own in the tooltip.
	var title := TITLE_TEXT
	if _refresh_posts() == SimCommand.CommandResult.OK:
		shared = SimCommand.CommandResult.OK
		title = POST_TITLE_TEXT
	_layout_rows()
	var refused := shared != SimCommand.CommandResult.OK
	var why := CommandText.reason(shared)
	title_label.text = why.left(1).to_upper() + why.substr(1) if refused else title
	title_label.add_theme_color_override("font_color", STATUS_COLOR if refused else Color.WHITE)


## LT-118: the row's crew mark for a build taking `from_reserve` men from the reserve and
## hiring `hired`: "res 2", "hire 2" or "res 1·hire 1"; "" when both are 0.
static func crew_mark_text(from_reserve: int, hired: int) -> String:
	var parts: PackedStringArray = []
	if from_reserve > 0:
		parts.append("res %d" % from_reserve)
	if hired > 0:
		parts.append("hire %d" % hired)
	return "·".join(parts)


## LT-118: the price split of crewed tower `def_id` now (the tooltip's last line), e.g. "Frame $20 +
## Harpooners: 2 from the reserve" / "Frame $20 + Harpooners: hire 2 × $25" / "Frame $20 +
## Harpooners: 1 from the reserve, hire 1 × $25"; "" when the def needs no crew (or crew is
## off).
static func crew_price_text(sim: Simulation, def_id: String) -> String:
	var need := sim.crew_need(def_id)
	if need == 0:
		return ""
	var crew: CrewConfig.CrewKind = sim.config.crew.crews[def_id]
	var from_reserve := mini(need, sim.crew_reserve().get(def_id, 0))
	var hired := need - from_reserve
	var parts: PackedStringArray = []
	if from_reserve > 0:
		parts.append("%d from the reserve" % from_reserve)
	if hired > 0:
		parts.append("hire %d × %s" % [hired, TowerText.money(crew.hire)])
	return "Frame %s + %s: %s" % [TowerText.money(sim.frame_price(def_id)), crew.name,
		", ".join(parts)]


## LT-32 §4: men of crewed tower `def_id` a build would take from the reserve now (0 when
## crew is off or the def needs none).
func _from_reserve(def_id: String) -> int:
	var need := game.sim.crew_need(def_id)
	if need == 0:
		return 0
	return mini(need, game.sim.crew_reserve().get(def_id, 0))


## LT-32 §4: shows the post rows at night (crew on) and re-evaluates them against
## Simulation.can_deploy; returns OK when some post can be deployed, else the first row's
## refusal, or -1 when the section is hidden (by day, crew off).
func _refresh_posts() -> int:
	var night := post_box != null and game.snapshot.phase == SimState.Phase.WAVE
	if post_box != null:
		post_box.visible = night
	if not night:
		return -1
	var first := -1
	var reserve := game.sim.crew_reserve()
	for kind: String in post_buttons:
		var b := post_buttons[kind]
		var r := game.sim.can_deploy(kind, cell)
		var crew: CrewConfig.CrewKind = game.sim.config.crew.crews[kind]
		b.text = "Post: %d %s (%d in reserve)" % [game.sim.config.crew.post_of(kind).crew,
			crew.name, reserve.get(kind, 0)]
		b.disabled = r != SimCommand.CommandResult.OK
		b.modulate = DIM if b.disabled else Color.WHITE
		b.tooltip_text = post_crew_text(game.sim, kind) + ", until dawn"
		if b.disabled:
			b.tooltip_text += " (%s)" % CommandText.reason(r, "deploy")
		if r == SimCommand.CommandResult.OK:
			first = SimCommand.CommandResult.OK
		elif first == -1:
			first = r
	return first


## The full words of a trait tag ("Blind 2" -> "Blind 2: can't fire within 2 cells").
static func _trait_tip(tag: String) -> String:
	var words := tag.split(" ")
	var tip: String = TRAIT_TIPS.get(words[0], "")
	if tip.is_empty() or words.size() < 2:
		return tip
	if words[0] == "Blind":  # the number twice: "Blind 1: can't fire within 1 cell"
		return tip % [words[1], TowerText.cells_text(words[1])]
	return tip.replace("%s", words[1])


## Reserve violet for an occult "Res N", the dash dim, any other tag plain.
static func _trait_color(tag: String) -> Color:
	return StatsTable.color_for("reserve" if tag.begins_with("Res ") else "trait", tag)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_tower_pressed(def_id: String) -> void:
	if game.commands.build(def_id, cell) == SimCommand.CommandResult.OK:
		close()


## LT-32 §4: deploys a reserve post of crew `kind` on the picker's cell.
func _on_post_pressed(kind: String) -> void:
	if game.commands.deploy(kind, cell) == SimCommand.CommandResult.OK:
		close()


func _on_hover(def_id: String, entered: bool) -> void:
	if entered:
		_set_hovered(def_id)
	elif hovered == def_id:
		_set_hovered("")


## Frames the hovered row gold, shows its L1 range ring and its letter (a ghost) on the
## cell (LT-70 §5: and, for a caster, its L1 light/shadow preview), tells the side panel.
func _set_hovered(def_id: String) -> void:
	if def_id == hovered:
		return
	if _row_button(hovered) != null:
		_frame(_row_button(hovered), false)
	hovered = def_id
	var r := 0.0
	var glyph := ""
	var cast := ""
	var post_kind := def_id.trim_prefix(POST_PREFIX) if def_id.begins_with(POST_PREFIX) else ""
	if post_buttons.has(post_kind):  # LT-32: a post shows its range, no tower glyph ghost
		_frame(post_buttons[post_kind], true)
		r = game.sim.post_def(post_kind).levels[0].range_cells
	elif buttons.has(def_id):
		_frame(buttons[def_id], true)
		var def: TowerDef = game.sim.config.towers[def_id]
		r = def.levels[0].range_cells
		glyph = def.glyph
		cast = Board.cast_of(def.levels[0])
	if visible:
		game.selection.set_preview(r, glyph, cast)  # redraws only when it changed
	hovered_changed.emit(def_id)


## The row button of hover id `id` (a tower def id or POST_PREFIX + crew kind), or null.
func _row_button(id: String) -> Button:
	if id.begins_with(POST_PREFIX):
		return post_buttons.get(id.trim_prefix(POST_PREFIX))
	return buttons.get(id)


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
