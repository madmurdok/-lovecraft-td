class_name EndScreen
extends PanelContainer
## Win / lose screen with restart (LT-7). Shown on the sim's OUTCOME event.

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


func show_result(won: bool, s: SimState) -> void:
	if won:
		result_label.text = "The lighthouse stands.\nAll %d waves repelled." % s.waves_total
	else:
		result_label.text = "The lighthouse has fallen.\nWave %d / %d." % [s.wave_index, s.waves_total]
	visible = true
	position = (get_viewport_rect().size - get_combined_minimum_size()) * 0.5
