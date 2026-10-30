class_name SellPanel
extends PanelContainer
## Panel for a clicked tower (LT-7, GDD §9): sell for the refund Simulation.sell_refund
## reports now. Upgrades / branches come with their own task.

var game: Game
var tower_id := 0
var title_label: Label
var sell_button: Button


func _ready() -> void:
	visible = false
	var list := VBoxContainer.new()
	list.name = "List"
	add_child(list)
	title_label = Label.new()
	title_label.name = "Title"
	list.add_child(title_label)
	sell_button = Button.new()
	sell_button.name = "SellButton"
	sell_button.focus_mode = Control.FOCUS_NONE
	sell_button.pressed.connect(_on_sell_pressed)
	list.add_child(sell_button)
	var cancel := Button.new()
	cancel.name = "CancelButton"
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(close)
	list.add_child(cancel)


func open_for(p_tower_id: int) -> void:
	var t := game.sim.tower_by_id(p_tower_id)
	if t == null:
		return
	tower_id = p_tower_id
	visible = true
	refresh()
	position = game.board.position + game.board.cell_origin(t.cell) + Vector2(Board.CELL + 4, 0)
	var view := get_viewport_rect().size
	var sz := get_combined_minimum_size()
	position = Vector2(minf(position.x, view.x - sz.x), minf(position.y, view.y - sz.y))
	game.board.selected_cell = t.cell
	game.board.selected_range = t.stats().range_cells
	game.board.queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	game.board.selected_cell = Vector2i(-1, -1)
	game.board.selected_range = 0.0
	game.board.queue_redraw()


## Closes itself once the tower is gone; otherwise re-reads the refund.
func refresh() -> void:
	if not visible:
		return
	var t := game.sim.tower_by_id(tower_id)
	if t == null:
		close()
		return
	title_label.text = t.def.name
	sell_button.text = "Sell (+%d gold)" % game.sim.sell_refund(t)


func _on_sell_pressed() -> void:
	game.sell(tower_id)
	close()
