class_name SidePanel
extends PanelContainer
## Info panel at the right edge of the window (LT-24 §4, Decision 2). LT-66: an overlay over
## the board, PANEL_W wide from below the HUD bar to the bottom, laid out in base viewport
## units (canvas_items stretch scales it with the window); a click on it never reaches the
## board. One view at a time inside a vertical scroll: idle text, the tower view
## (TowerPanel), the lighthouse view, the crew view (LT-32), the monster card (LT-66 §5), or
## (LT-61 §1) while the build list (TowerPicker, above the scroll) is open the hovered
## tower's L1 card (LT-32: or the hovered reserve post's card), or "Pick a tower to build"
## with no hover. LT-66 §2 (sync_visible): by day it always shows (idle text when no view is
## open); by night exactly while a view is open; never after the outcome. Esc closes the
## open view (_input).

const FONT_SIZE := 14  ## panel text (tunable; LT-28 owns the polish)
const MARGIN := 8
const PANEL_W := 304  ## LT-66 §1 (owner Q1): the overlay's width; inner PANEL_W - 2 * MARGIN
const COLOR_BG := UiStyle.COLOR_BG  ## opaque, same as the HUD bar
const COLOR_ROLE := Color(0.85, 0.8, 0.6)
const COLOR_INFO := Color(0.75, 0.75, 0.78)
const IDLE_TEXT := "Click a cell to build, a tower to upgrade."
const PICK_TEXT := "Pick a tower to build"  ## LT-43 §3: the picker is open, nothing hovered

var game: Game
var scroll: ScrollContainer
var idle_label: Label
var picker: TowerPicker  ## LT-61 §1: the build list, above `scroll` while open
var tower_panel: TowerPanel
## LT-43 §3: the hovered picker column's L1 card (title, role, table, special, kind, path).
var card: VBoxContainer
var card_title: Label
var card_role: Label
var card_table: StatsTable
var card_special: Label
var card_kind: Label
var card_path: Label
var card_id := ""  ## def id the card shows, "" while hidden
var lighthouse_panel: LighthousePanel  ## LT-30
var crew_panel: CrewPanel  ## LT-32 §4
var monster_card: MonsterCard  ## LT-66 §5
var card_upgrades: Label  ## the card's "Upgrades" head (hidden for a reserve post)


## A word-wrapping label at the panel width.
static func make_label(node_name: String, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.name = node_name
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if color != Color.WHITE:
		l.add_theme_color_override("font_color", color)
	return l


## A left-aligned, word-wrapping button that never takes keyboard focus.
static func make_button(node_name: String, on_pressed: Callable, text := "") -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_pressed)
	return b


## LT-66 §1: the overlay rect in base viewport units: PANEL_W at the right edge, below
## the HUD bar to the bottom; it does not depend on the map.
static func panel_rect() -> Rect2:
	var base := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	var top := BoardView.HUD_H
	return Rect2(base.x - PANEL_W, top, PANEL_W, base.y - top)


func _ready() -> void:
	var r := panel_rect()
	mouse_filter = Control.MOUSE_FILTER_STOP  # LT-66 §2: a click on the overlay stays here
	position = r.position
	size = r.size
	custom_minimum_size = r.size
	clip_contents = true
	var bg := StyleBoxFlat.new()
	bg.bg_color = COLOR_BG
	bg.set_content_margin_all(MARGIN)
	add_theme_stylebox_override("panel", bg)
	theme = UiStyle.theme(FONT_SIZE)  # LT-28: opaque framed buttons, legible when disabled

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	picker = TowerPicker.new()
	picker.name = "TowerPicker"
	picker.game = game
	layout.add_child(picker)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var views := VBoxContainer.new()
	views.name = "Views"
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(views)
	idle_label = make_label("IdleLabel")
	idle_label.text = IDLE_TEXT
	views.add_child(idle_label)
	_make_card(views)
	tower_panel = TowerPanel.new()
	tower_panel.name = "TowerPanel"
	tower_panel.game = game
	views.add_child(tower_panel)
	lighthouse_panel = LighthousePanel.new()
	lighthouse_panel.name = "LighthousePanel"
	lighthouse_panel.game = game
	views.add_child(lighthouse_panel)
	crew_panel = CrewPanel.new()
	crew_panel.name = "CrewPanel"
	crew_panel.game = game
	views.add_child(crew_panel)
	monster_card = MonsterCard.new()
	monster_card.name = "MonsterCard"
	monster_card.game = game
	views.add_child(monster_card)
	lighthouse_panel.visibility_changed.connect(_update_idle)
	crew_panel.visibility_changed.connect(_update_idle)
	tower_panel.visibility_changed.connect(_update_idle)
	monster_card.visibility_changed.connect(_update_idle)
	picker.visibility_changed.connect(_update_idle)
	picker.hovered_changed.connect(show_card)
	_update_idle()


## LT-43 §3: shows the L1 card of tower `def_id` ("" hides it). LT-32: an id
## TowerPicker.POST_PREFIX + crew kind shows that kind's reserve post instead.
func show_card(def_id: String) -> void:
	var post_kind := def_id.trim_prefix(TowerPicker.POST_PREFIX) \
		if def_id.begins_with(TowerPicker.POST_PREFIX) else ""
	var def: TowerDef = game.sim.post_def(post_kind) if not post_kind.is_empty() \
		else game.sim.config.towers.get(def_id)
	card_id = def_id if def != null else ""
	if def != null:
		var s: TowerDef.Level = def.levels[0]
		card_title.text = def.name  # LT-61 §1: the row shows the cost
		card_title.add_theme_color_override("font_color", StatsTable.kind_color(def.kind))
		card_role.text = def.role
		card_role.visible = not def.role.is_empty()
		var cols: Array[Dictionary] = [TowerText.row_values(def, s, game.sim.config)]
		card_table.set_columns(PackedStringArray([""]), cols, {},  # no head row (LT-61 §1)
			StatsTable.kind_color(def.kind))
		card_special.text = "\n".join(TowerText.special_lines(s))
		card_special.visible = not card_special.text.is_empty()
		card_special.tooltip_text = TowerText.special_tip(s.effects, game.sim.config)  # LT-122
		card_kind.text = "\n".join(TowerText.kind_lines(def, s, game.sim.config.sanity))
		card_kind.visible = not card_kind.text.is_empty()
		card_path.text = TowerText.upgrade_path_text(def)
		card_upgrades.visible = post_kind.is_empty()
		if not post_kind.is_empty():
			card_role.text = TowerPicker.post_crew_text(game.sim, post_kind)
			card_role.visible = true
			card_path.text = "Not a tower: no upgrades, no sale. Returns to the reserve at dawn."
	_update_idle()


func _make_card(views: VBoxContainer) -> void:
	card = VBoxContainer.new()
	card.name = "PickerCard"
	card.visible = false
	card.add_theme_constant_override("separation", 2)
	views.add_child(card)
	card_title = make_label("CardTitle")
	card.add_child(card_title)
	card_role = make_label("CardRole", COLOR_ROLE)
	card.add_child(card_role)
	card_table = StatsTable.new()
	card_table.name = "CardTable"
	card.add_child(card_table)
	card_special = make_label("CardSpecial", COLOR_INFO)
	card_special.add_theme_font_size_override("font_size", StatsTable.FONT_SIZE)
	card_special.mouse_filter = Control.MOUSE_FILTER_PASS  # LT-122: Labels ignore the mouse by default; PASS shows the tooltip
	card.add_child(card_special)
	card_kind = make_label("CardKind", StatsTable.COLOR_LABEL)
	card_kind.add_theme_font_size_override("font_size", StatsTable.FONT_SIZE)
	card.add_child(card_kind)
	card_upgrades = make_label("CardUpgradesTitle")
	card_upgrades.text = "Upgrades"
	card.add_child(card_upgrades)
	card_path = make_label("CardPath", COLOR_INFO)
	card_path.add_theme_font_size_override("font_size", StatsTable.FONT_SIZE)
	card.add_child(card_path)


## Idle text while no view is shown ("Pick a tower to build" while the picker is open with
## no hover); a newly shown view starts scrolled to the top.
func _update_idle() -> void:
	var picking := picker != null and picker.visible
	card.visible = picking and not card_id.is_empty()
	idle_label.text = PICK_TEXT if picking else IDLE_TEXT
	idle_label.visible = not card.visible and not tower_panel.visible \
		and not lighthouse_panel.visible and not crew_panel.visible and not monster_card.visible
	scroll.scroll_vertical = 0
	sync_visible()


## True while a view is open: the build list, tower, lighthouse, crew or monster view.
func any_view_open() -> bool:
	return picker.visible or tower_panel.visible or lighthouse_panel.visible \
		or crew_panel.visible or monster_card.visible


## LT-66 §2: the one place the overlay's visibility is decided: shown by day, by night only
## while a view is open, never after the outcome. Phase and outcome from game.snapshot.
## Night is `phase == WAVE` (spec §2 table; the same predicate as Game._on_cell_clicked and
## the picker), so NONE and DONE count as day.
func sync_visible() -> void:
	var s := game.snapshot
	visible = s != null and s.outcome == SimState.Outcome.NONE \
		and (s.phase != SimState.Phase.WAVE or any_view_open())  # night = WAVE, as game.gd
	if game.board != null:  # LT-66 §6.3: a changed visible rect eases the pan to its clamp
		game.board.camera.set_visible_rect(board_visible_rect())


## LT-66 §6.1: where the map is seen: BoardView.play_rect, minus the overlay while it shows.
func board_visible_rect() -> Rect2:
	var play := BoardView.play_rect()
	if visible:
		play.end.x = minf(play.end.x, panel_rect().position.x)
	return play


## LT-66 §2 (owner Q3): Esc closes the open view (by day the idle text shows, by night the
## overlay hides).
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and any_view_open():
		get_viewport().set_input_as_handled()
		game.close_panels()
