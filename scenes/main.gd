extends Node2D
## Boot: loads every balance config before anything else starts.
## A bad config refuses to start: each error goes to push_error, the screen
## lists them, and a headless run exits with code 1.
## Override the config directory with `-- --config-dir=<path>` (dev/CI) and the run seed
## with `-- --seed=<int>` (random otherwise). A loaded config starts a Game (LT-7);
## its restart button replaces it with a fresh run.

const CONFIG_DIR_ARG := "--config-dir="
const SEED_ARG := "--seed="

var config: GameConfig
var game: Game


func _ready() -> void:
	var dir := _config_dir()
	var result := GameConfig.load_from_dir(dir)
	if not result.ok:
		_refuse_to_start(dir, result.errors)
		return
	config = result.config
	print("Config loaded from %s: %d towers, %d enemies, %d waves"
		% [dir, config.towers.size(), config.enemies.size(), config.waves.waves.size()])
	start_game()


## Replaces the current run (if any) with a new one on the same config.
func start_game() -> void:
	if game != null:
		remove_child(game)
		game.queue_free()
	var run_seed := _seed()
	game = Game.new()
	game.name = "Game"
	game.setup(config, run_seed)
	game.restart_requested.connect(start_game, CONNECT_DEFERRED)
	add_child(game)
	print("Run started, seed %d" % run_seed)


func _seed() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(SEED_ARG):
			return arg.trim_prefix(SEED_ARG).to_int()
	return randi()


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
