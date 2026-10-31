class_name TowerPicker
extends VBoxContainer
## Build view of the side panel (LT-7, LT-24 §4) for a buildable cell: one button per tower
## in the config with its cost, and under it the tower's role and L1 info (TowerInfo). A
## button is disabled, with the reason, whenever Simulation.can_build refuses it.
## `visible` is "the build view is shown"; SidePanel shows its idle text otherwise.

## Kept for callers of the LT-7 name; the texts live in TowerInfo.REASONS.
const REASONS := TowerInfo.REASONS

var game: Game
var cell := Vector2i(-1, -1)
var buttons: Dictionary[String, Button] = {}  ## tower def id -> its button
var infos: Dictionary[String, Label] = {}  ## tower def id -> role + L1 info under its button


func _ready() -> void:
	visible = false
	var title := Label.new()
	title.name = "Title"
	title.text = "Build"
	add_child(title)
	for def_id in game.sim.config.towers:
		var def: TowerDef = game.sim.config.towers[def_id]
		var b := SidePanel.make_button("Tower_" + def_id, _on_tower_pressed.bind(def_id))
		add_child(b)
		buttons[def_id] = b
		var info := SidePanel.make_label("Info_" + def_id, SidePanel.COLOR_INFO)
		var text := PackedStringArray()
		if not def.role.is_empty():
			text.append(def.role)
		text.append_array(TowerInfo.lines(def, def.levels[0], game.sim.config.sanity))
		info.text = "\n".join(text)
		add_child(info)
		infos[def_id] = info
	add_child(SidePanel.make_button("CancelButton", close, "Cancel"))


func open_for(p_cell: Vector2i) -> void:
	cell = p_cell
	visible = true
	refresh()
	game.board.selected_cell = p_cell
	game.board.selected_range = 0.0
	game.board.queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	game.board.selected_cell = Vector2i(-1, -1)
	game.board.queue_redraw()


## Re-evaluates every button against the sim (gold changes while the view is open).
func refresh() -> void:
	if not visible:
		return
	for def_id in buttons:
		var def: TowerDef = game.sim.config.towers[def_id]
		var r := game.sim.can_build(def_id, cell)
		var b := buttons[def_id]
		b.disabled = r != Simulation.CommandResult.OK
		var text := "%s - %s" % [def.name, TowerInfo.cost_text(def.cost)]
		if b.disabled:
			text += " (%s)" % TowerInfo.reason(r)
		b.text = text


func _on_tower_pressed(def_id: String) -> void:
	if game.build(def_id, cell) == Simulation.CommandResult.OK:
		close()
