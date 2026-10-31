class_name EndScreen
extends PanelContainer
## Win / lose screen with restart (LT-7). Shown on the sim's OUTCOME event. LT-27 §4: the
## relics left unsold and, when any, the star-stones found.

signal restart_pressed

var result_label: Label
var restart_button: Button


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	var list := VBoxContainer.new()
	list.name = "List"
	add_child(list)
	result_label = Label.new()
	result_label.name = "ResultLabel"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(result_label)
	restart_button = Button.new()
	restart_button.name = "RestartButton"
	restart_button.text = "Restart"
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.pressed.connect(func() -> void: restart_pressed.emit())
	list.add_child(restart_button)


func show_result(won: bool, s: SimState, star_stones := 0) -> void:
	var lines := PackedStringArray()
	if won:
		lines.append("The lighthouse stands.")
		lines.append("All %d nights survived." % s.waves_total)
	else:
		lines.append("The lighthouse has fallen.")
		lines.append("Night %d / %d." % [s.wave_index, s.waves_total])
	var unsold := 0
	for kind: String in s.relics:
		unsold += s.relics[kind]
	lines.append("Relics left unsold: %d" % unsold)
	if star_stones > 0:
		lines.append("Star-stones found: %d" % star_stones)
	result_label.text = "\n".join(lines)
	visible = true
	position = (get_viewport_rect().size - get_combined_minimum_size()) * 0.5
