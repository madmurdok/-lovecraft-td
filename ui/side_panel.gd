class_name SidePanel
extends PanelContainer
## Fixed info panel on the right of the board (LT-24 §4, Decision 2): the free strip from
## the board's right edge to the base viewport's right edge, from below the HUD bar to the
## bottom. Laid out in base viewport units, so canvas_items stretch scales it with the
## window and it never covers the board. One view at a time inside a vertical scroll:
## idle text, the tower view (TowerPanel), the lighthouse view, or (LT-61 §1) while the
## build list (TowerPicker, above the scroll) is open the hovered tower's L1 card, or
## "Pick a tower to build" with no hover.

const FONT_SIZE := 14  ## panel text (tunable; LT-28 owns the polish)
const MARGIN := 8
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


## The panel rect in base viewport units: right of the board, below the HUD bar.
static func panel_rect(map: MapDef) -> Rect2:
	var base := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	var left := Game.BOARD_ORIGIN.x + map.width * Board.CELL
	return Rect2(left, Game.BOARD_ORIGIN.y, base.x - left, base.y - Game.BOARD_ORIGIN.y)


func _ready() -> void:
	var r := panel_rect(game.sim.state.map)
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
	lighthouse_panel.visibility_changed.connect(_update_idle)
	tower_panel.visibility_changed.connect(_update_idle)
	picker.visibility_changed.connect(_update_idle)
	picker.hovered_changed.connect(show_card)
	_update_idle()


## LT-43 §3: shows the L1 card of tower `def_id` ("" hides it).
func show_card(def_id: String) -> void:
	var def: TowerDef = game.sim.config.towers.get(def_id)
	card_id = def_id if def != null else ""
	if def != null:
		var s: TowerDef.Level = def.levels[0]
		card_title.text = def.name  # LT-61 §1: the row shows the cost
		card_title.add_theme_color_override("font_color", StatsTable.kind_color(def.kind))
		card_role.text = def.role
		card_role.visible = not def.role.is_empty()
		var cols: Array[Dictionary] = [TowerInfo.row_values(def, s, game.sim.config)]
		card_table.set_columns(PackedStringArray([""]), cols, {},  # no head row (LT-61 §1)
			StatsTable.kind_color(def.kind))
		card_special.text = "\n".join(TowerInfo.special_lines(s))
		card_special.visible = not card_special.text.is_empty()
		card_kind.text = "\n".join(TowerInfo.kind_lines(def, s, game.sim.config.sanity))
		card_kind.visible = not card_kind.text.is_empty()
		card_path.text = TowerInfo.upgrade_path_text(def)
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
	card.add_child(card_special)
	card_kind = make_label("CardKind", StatsTable.COLOR_LABEL)
	card_kind.add_theme_font_size_override("font_size", StatsTable.FONT_SIZE)
	card.add_child(card_kind)
	var up := make_label("CardUpgradesTitle")
	up.text = "Upgrades"
	card.add_child(up)
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
		and not lighthouse_panel.visible
	scroll.scroll_vertical = 0
