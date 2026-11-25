extends Node2D
## Boot: loads every balance config before anything else starts.
## A bad config (or data/effect_text.json, LT-103, or data/looks.json, LT-104) refuses to
## start: each error goes to push_error, the screen lists them, and a headless run exits
## with code 1.
## Override the config directory with `-- --config-dir=<path>` (dev/CI) and the run seed
## with `-- --seed=<int>` (random otherwise). A loaded config starts a Game (LT-7);
## its restart button replaces it with a fresh run.
## LT-22: the game scales with the window (stretch mode canvas_items, aspect keep, base
## 1200x675 in project.godot). At boot a desktop window is sized to fill WINDOW_FILL of
## the screen's usable area: window sizes are in physical pixels, so a fixed size is
## half as large on a 2x (Retina) screen.
## LT-92: the first run starts one frame after a plain "Loading..." frame is presented, so the
## heavy first game frame (GL shader compiles, 0.3-1 s) reads as loading. A refusal never
## shows it, and a restart (start_game) skips it: the shaders are compiled by then.

const CONFIG_DIR_ARG := "--config-dir="
const SEED_ARG := "--seed="
const WINDOW_FILL := 0.85  ## share of the usable screen area the boot window may take
## LT-28: engine flags that place or size the window; either one turns the boot fit off.
const WINDOW_FLAGS: PackedStringArray = ["--resolution", "--position"]

const LOADING_TEXT := "Loading..."

var config: GameConfig
var game: Game
var loading: CanvasLayer  ## LT-92: the boot "Loading..." layer, null once the game started


func _ready() -> void:
	_fit_window()
	var dir := _config_dir()
	var result := ConfigLoader.load_dir(dir)
	if not result.ok:
		_refuse_to_start(dir, result.errors)
		return
	# LT-103 §2.4: the effect text file (presentation, not GameConfig) is checked here too,
	# so a missing or broken entry refuses to start instead of showing `key: value` lines.
	var text_errors := EffectText.errors()
	if not text_errors.is_empty():
		_refuse_to_start(EffectText.PATH, text_errors)
		return
	# LT-104 Q1: so does data/looks.json (optional; a missing file is no error): an invalid
	# table, an id not in the config or an override that draws none of its tower's modes.
	var look_errors: Array[String] = []
	look_errors.append_array(LookCatalog.errors())
	look_errors.append_array(LookCatalog.check_config(result.config))
	if not look_errors.is_empty():
		_refuse_to_start(LookCatalog.PATH, look_errors)
		return
	config = result.config
	print("Config loaded from %s: %d towers, %d enemies, %d waves"
		% [dir, config.towers.size(), config.enemies.size(), config.waves.waves.size()])
	_show_loading()
	# The first process_frame fires before frame 1 draws, the second after it: the label is
	# drawn and presented once. Not frame_post_draw: headless runs must not wait on a draw.
	var tree := get_tree()
	await tree.process_frame
	await tree.process_frame
	if not is_inside_tree():
		return
	start_game()
	_hide_loading()


## LT-92: a CanvasLayer above the game's UI with a centred plain Label (theme font, no
## material), so its own first frame costs only tens of ms.
func _show_loading() -> void:
	loading = CanvasLayer.new()
	loading.name = "Loading"
	loading.layer = Game.UI_LAYER + 1
	var label := Label.new()
	label.text = LOADING_TEXT
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.add_child(label)
	add_child(loading)


## Removes the loading layer at once (the frame after it draws the game in its place).
func _hide_loading() -> void:
	if loading == null:
		return
	remove_child(loading)
	loading.queue_free()
	loading = null


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


## The largest window with the base viewport's aspect that fits `fill` of `usable`.
static func fit_window_size(usable: Vector2i, base: Vector2i, fill: float) -> Vector2i:
	var room := Vector2(usable) * fill
	var s := minf(room.x / base.x, room.y / base.y)
	return Vector2i((Vector2(base) * s).round())


## True when `args` (the engine's own, before a bare `--`) hold a WINDOW_FLAGS flag.
static func has_window_flag(args: PackedStringArray) -> bool:
	for a in args:
		if a == "--":
			return false
		for f in WINDOW_FLAGS:
			if a == f or a.begins_with(f + "="):
				return true
	return false


## The process's launch arguments. The engine consumes `--resolution` and `--position`
## before OS.get_cmdline_args(), so they are read back from `ps` where it exists (macOS,
## Linux); elsewhere this is OS.get_cmdline_args() and those flags go unseen.
static func launch_args() -> PackedStringArray:
	if OS.get_name() in ["macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
		var out := []
		if OS.execute("ps", ["-o", "args=", "-p", str(OS.get_process_id())], out) == 0 \
				and not out.is_empty():
			return (out[0] as String).strip_edges().split(" ", false)
	return OS.get_cmdline_args()


## Desktop only: no headless run, no web page (the canvas follows the page), no window
## embedded in the editor, and only a window still at the project's size (an explicit
## `--resolution` or `--position`, or fullscreen, wins: LT-28).
func _fit_window() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web") \
			or Engine.is_embedded_in_editor():
		return
	if has_window_flag(launch_args()):
		return
	var w := get_window()
	var project_size := Vector2i(
		ProjectSettings.get_setting("display/window/size/window_width_override"),
		ProjectSettings.get_setting("display/window/size/window_height_override"))
	if w.mode != Window.MODE_WINDOWED or w.size != project_size:
		return
	var usable := DisplayServer.screen_get_usable_rect(w.current_screen)
	var base := Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	w.size = fit_window_size(usable.size, base, WINDOW_FILL)
	w.position = usable.position + (usable.size - w.size) / 2


func _seed() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(SEED_ARG):
			return arg.trim_prefix(SEED_ARG).to_int()
	return randi()


func _config_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(CONFIG_DIR_ARG):
			return arg.trim_prefix(CONFIG_DIR_ARG)
	return ConfigLoader.DEFAULT_DIR


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
