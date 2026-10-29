extends Node2D
## Boot: loads every balance config before anything else starts.
## A bad config refuses to start: each error goes to push_error, the screen
## lists them, and a headless run exits with code 1.
## Override the config directory with `-- --config-dir=<path>` (dev/CI).

const CONFIG_DIR_ARG := "--config-dir="

var config: GameConfig


func _ready() -> void:
	var dir := _config_dir()
	var result := GameConfig.load_from_dir(dir)
	if not result.ok:
		_refuse_to_start(dir, result.errors)
		return
	config = result.config
	print("Config loaded from %s: %d towers, %d enemies, %d waves"
		% [dir, config.towers.size(), config.enemies.size(), config.waves.waves.size()])


func _config_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(CONFIG_DIR_ARG):
			return arg.trim_prefix(CONFIG_DIR_ARG)
	return GameConfig.DEFAULT_DIR


func _refuse_to_start(dir: String, errors: Array[String]) -> void:
	var header := "Config error (%s): %d problem(s); game not started" % [dir, errors.size()]
	push_error(header)
	for e in errors:
		push_error(e)
	var label := Label.new()
	label.text = header + "\n" + "\n".join(errors)
	label.add_theme_color_override("font_color", Color.RED)
	label.position = Vector2(16, 16)
	add_child(label)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
