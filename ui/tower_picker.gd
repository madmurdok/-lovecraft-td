class_name TowerPicker
extends PanelContainer
## Tower picker for a buildable cell (LT-7, GDD §9): one button per tower in the config
## with its cost; a button is disabled, with the reason, whenever Simulation.can_build
## refuses it (not enough gold, occult towers NOT_AVAILABLE until LT-11, ...).

## Player-facing text for a refused build (presentation only).
const REASONS := {
	Simulation.CommandResult.OUTCOME_REACHED: "run over",
	Simulation.CommandResult.UNKNOWN_TOWER: "unknown tower",
	Simulation.CommandResult.NOT_AVAILABLE: "not available yet",
	Simulation.CommandResult.NOT_BUILDABLE: "cannot build here",
	Simulation.CommandResult.OCCUPIED: "cell occupied",
	Simulation.CommandResult.NOT_ENOUGH_GOLD: "not enough gold",
}

var game: Game
var cell := Vector2i(-1, -1)
var buttons: Dictionary[String, Button] = {}  ## tower def id -> its button
var _list: VBoxContainer


func _ready() -> void:
	visible = false
	_list = VBoxContainer.new()
	_list.name = "List"
	add_child(_list)
	var title := Label.new()
	title.name = "Title"
	title.text = "Build"
	_list.add_child(title)
	for def_id in game.sim.config.towers:
		var b := Button.new()
		b.name = "Tower_" + def_id
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_tower_pressed.bind(def_id))
		_list.add_child(b)
		buttons[def_id] = b
	var cancel := Button.new()
	cancel.name = "CancelButton"
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(close)
	_list.add_child(cancel)


func open_for(p_cell: Vector2i) -> void:
	cell = p_cell
	visible = true
	refresh()
	position = _panel_position(p_cell)
	game.board.selected_cell = p_cell
	game.board.selected_range = 0.0
	game.board.queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	game.board.selected_cell = Vector2i(-1, -1)
	game.board.queue_redraw()


## Re-evaluates every button against the sim (gold changes while the panel is open).
func refresh() -> void:
	if not visible:
		return
	for def_id in buttons:
		var def: TowerDef = game.sim.config.towers[def_id]
		var r := game.sim.can_build(def_id, cell)
		var b := buttons[def_id]
		b.disabled = r != Simulation.CommandResult.OK
		b.text = "%s - %d gold" % [def.name, def.cost]
		if b.disabled:
			b.text += " (%s)" % REASONS.get(r, "unavailable")


func _on_tower_pressed(def_id: String) -> void:
	if game.build(def_id, cell) == Simulation.CommandResult.OK:
		close()


func _panel_position(p_cell: Vector2i) -> Vector2:
	var p := game.board.position + game.board.cell_origin(p_cell) + Vector2(Board.CELL + 4, 0)
	var view := get_viewport_rect().size
	var sz := get_combined_minimum_size()
	return Vector2(minf(p.x, view.x - sz.x), minf(p.y, view.y - sz.y))
