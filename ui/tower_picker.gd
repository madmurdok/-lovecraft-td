class_name TowerPicker
extends VBoxContainer
## Build view of the side panel (LT-7, LT-24 §4) for a buildable cell: one button per tower
## in the config with its cost, and under it the tower's role and L1 info (TowerInfo). A
## button is disabled, with the reason, whenever Simulation.can_build refuses it, and warns
## "(drives you mad!)" when its reserve would take the sanity cap to 0 (LT-23 Q3).
## `visible` is "the build view is shown"; SidePanel shows its idle text otherwise.

## Kept for callers of the LT-7 name; the texts live in TowerInfo.REASONS.
const REASONS := TowerInfo.REASONS

## Group headers by TowerDef.kind ("role" is free text; kind is the mundane/occult split).
const GROUP_TITLES := {"mundane": "Mundane", "occult": "Occult"}
const ENTRY_FONT_SIZE := 11  ## smaller than the panel's 14 so 10 entries fit (LT-55)

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
	add_theme_constant_override("separation", 2)
	# LT-55 (LT-46 P15): two labelled groups, data order kept inside each, so 10 towers fit
	# the panel without scrolling.
	for kind in TowerDef.KINDS:
		var header := SidePanel.make_label("Group_" + kind, SidePanel.COLOR_ROLE)
		header.text = GROUP_TITLES[kind]
		header.add_theme_font_size_override("font_size", ENTRY_FONT_SIZE)
		add_child(header)
		for def_id in game.sim.config.towers:
			var def: TowerDef = game.sim.config.towers[def_id]
			if def.kind == kind:
				_add_entry(def_id, def)
	add_child(SidePanel.make_button("CancelButton", close, "Cancel"))


## One tower: its button, and under it the role line (full L1 info in the label's text and the
## button's tooltip; only the first line is drawn, to keep 10 entries inside the panel).
func _add_entry(def_id: String, def: TowerDef) -> void:
	var b := SidePanel.make_button("Tower_" + def_id, _on_tower_pressed.bind(def_id))
	b.add_theme_font_size_override("font_size", ENTRY_FONT_SIZE)
	add_child(b)
	buttons[def_id] = b
	var info := SidePanel.make_label("Info_" + def_id, SidePanel.COLOR_INFO)
	var text := PackedStringArray()
	if not def.role.is_empty():
		text.append(def.role)
	text.append_array(TowerInfo.lines(def, def.levels[0], game.sim.config.sanity))
	info.text = "\n".join(text)
	info.max_lines_visible = 1
	info.add_theme_font_size_override("font_size", ENTRY_FONT_SIZE)
	b.tooltip_text = info.text
	add_child(info)
	infos[def_id] = info


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


## Re-evaluates every button against the sim (money and the phase change while the view is open).
func refresh() -> void:
	if not visible:
		return
	for def_id in buttons:
		var def: TowerDef = game.sim.config.towers[def_id]
		var r := game.sim.can_build(def_id, cell)
		var b := buttons[def_id]
		b.disabled = r != Simulation.CommandResult.OK
		var text := def.name + TowerInfo.DASH + TowerInfo.cost_text(def.cost)
		if b.disabled:
			text += " (%s)" % TowerInfo.reason(r)
		elif game.sim.would_drive_mad_build(def_id):
			text += TowerInfo.MADNESS_WARNING
		b.text = text


func _on_tower_pressed(def_id: String) -> void:
	if game.build(def_id, cell) == Simulation.CommandResult.OK:
		close()
