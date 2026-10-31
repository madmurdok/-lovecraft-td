class_name SidePanel
extends PanelContainer
## Fixed info panel on the right of the board (LT-24 §4, Decision 2): the free strip from
## the board's right edge to the base viewport's right edge, from below the HUD bar to the
## bottom. Laid out in base viewport units, so canvas_items stretch scales it with the
## window and it never covers the board. One view at a time inside a vertical scroll:
## idle text, the build view (TowerPicker) or the tower view (TowerPanel).

const FONT_SIZE := 14  ## panel text (tunable; LT-28 owns the polish)
const MARGIN := 8
const COLOR_BG := UiStyle.COLOR_BG  ## opaque, same as the HUD bar
const COLOR_ROLE := Color(0.85, 0.8, 0.6)
const COLOR_INFO := Color(0.75, 0.75, 0.78)
const IDLE_TEXT := "Click a cell to build, a tower to upgrade."

var game: Game
var scroll: ScrollContainer
var idle_label: Label
var picker: TowerPicker
var tower_panel: TowerPanel


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

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var views := VBoxContainer.new()
	views.name = "Views"
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(views)
	idle_label = make_label("IdleLabel")
	idle_label.text = IDLE_TEXT
	views.add_child(idle_label)
	picker = TowerPicker.new()
	picker.name = "TowerPicker"
	picker.game = game
	views.add_child(picker)
	tower_panel = TowerPanel.new()
	tower_panel.name = "TowerPanel"
	tower_panel.game = game
	views.add_child(tower_panel)
	picker.visibility_changed.connect(_update_idle)
	tower_panel.visibility_changed.connect(_update_idle)
	_update_idle()


## Idle text while neither view is shown; a newly shown view starts scrolled to the top.
func _update_idle() -> void:
	idle_label.visible = not picker.visible and not tower_panel.visible
	scroll.scroll_vertical = 0
