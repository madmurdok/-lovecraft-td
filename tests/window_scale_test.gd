class_name WindowScaleTest
extends GdUnitTestSuite
## LT-22: the game scales with the window. Pins the stretch settings, the boot window
## fit (aspect kept, 85% of the usable screen), the screen shader's pixel tunables
## following the stretch, and board clicks under a 2x stretched viewport. The scaled
## viewport is a 2304x1296 SubViewport stretching a 1200x675 base (size_2d_override),
## the same final transform the window stretch gives the root viewport.

const MAIN := preload("res://scenes/main.gd")
const RIFLE := "rifleman"
const BASE := Vector2i(1200, 675)
const SCALE := 2.0

var _vp: SubViewport
var _game: Game
var _config: GameConfig


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = SubViewport.new()
	_vp.size = Vector2i(Vector2(BASE) * SCALE)
	_vp.size_2d_override = BASE
	_vp.size_2d_override_stretch = true
	add_child(_vp)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _start_game() -> void:
	_game = Game.new()
	_game.setup(_config, 7)
	_vp.add_child(_game)
	_game.set_process(false)
	await get_tree().process_frame


## A click at a base-viewport position, delivered in screen pixels (scaled).
func _click(base_pos: Vector2) -> void:
	var screen_pos := base_pos * SCALE
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = screen_pos
		ev.global_position = screen_pos
		_vp.push_input(ev)
	await get_tree().process_frame


## The buildable cell farthest from the board origin, so a scale error cannot land on it.
func _far_buildable_cell() -> Vector2i:
	var m := _game.sim.state.map
	var best := Vector2i(-1, -1)
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if m.is_buildable(c) and (best.x < 0 or c.x + c.y > best.x + best.y):
				best = c
	return best


func test_project_stretches_canvas_items_and_keeps_aspect_over_a_1200x675_base() -> void:
	assert_str(ProjectSettings.get_setting("display/window/stretch/mode")).is_equal("canvas_items")
	assert_str(ProjectSettings.get_setting("display/window/stretch/aspect")).is_equal("keep")
	assert_int(ProjectSettings.get_setting("display/window/size/viewport_width")).is_equal(1200)
	assert_int(ProjectSettings.get_setting("display/window/size/viewport_height")).is_equal(675)
	assert_int(ProjectSettings.get_setting("display/window/size/window_width_override")) \
		.is_equal(1600)
	assert_int(ProjectSettings.get_setting("display/window/size/window_height_override")) \
		.is_equal(900)


func test_fit_window_size_fills_the_height_of_a_wide_screen() -> void:
	# room 2924x1224: the height limits, 1224 / 675 = 1.813...
	assert_vector(MAIN.fit_window_size(Vector2i(3440, 1440), BASE, 0.85)) \
		.is_equal(Vector2i(2176, 1224))


func test_fit_window_size_fills_the_width_of_a_tall_screen() -> void:
	# room 1020x1632: the width limits, 675 * 1020 / 1200 = 573.75
	assert_vector(MAIN.fit_window_size(Vector2i(1200, 1920), BASE, 0.85)) \
		.is_equal(Vector2i(1020, 574))


func test_boot_window_takes_85_percent_of_the_usable_screen() -> void:
	assert_float(MAIN.WINDOW_FILL).is_equal(0.85)
	# 16:9 usable area: both sides are exactly 85%.
	assert_vector(MAIN.fit_window_size(Vector2i(2560, 1440), BASE, MAIN.WINDOW_FILL)) \
		.is_equal(Vector2i(2176, 1224))



## LT-28: an explicit window size or position turns the boot fit off. Pinned on the static
## check over argument arrays (the headless run returns before it reads launch_args()).
func test_window_flags_turn_the_boot_fit_off_in_both_forms() -> void:
	assert_array(Array(MAIN.WINDOW_FLAGS)).is_equal(["--resolution", "--position"])
	for args: PackedStringArray in [
			PackedStringArray(["--resolution", "1600x900"]),
			PackedStringArray(["--position", "10,10"]),
			PackedStringArray(["--resolution=1600x900"]),
			PackedStringArray(["--position=0,0"]),
			PackedStringArray(["godot", "--path", ".", "--position", "5,5", "--", "--seed=1"])]:
		assert_bool(MAIN.has_window_flag(args)).override_failure_message(str(args)).is_true()


func test_other_flags_and_user_args_after_a_bare_dashdash_do_not_count() -> void:
	for args: PackedStringArray in [
			PackedStringArray([]),
			PackedStringArray(["--path", "."]),
			PackedStringArray(["--resolutions", "--positionx=1", "-resolution", "resolution"]),
			PackedStringArray(["--", "--resolution", "1600x900"]),
			PackedStringArray(["--path", ".", "--", "--position=10,10"])]:
		assert_bool(MAIN.has_window_flag(args)).override_failure_message(str(args)).is_false()

func test_distortion_and_aberration_scale_with_the_stretch() -> void:
	await _start_game()
	var fx := _game.sanity_fx
	_game.sim._add_sanity(-_game.sim.state.sanity, "test", 0)  # madness: level 1
	_game.advance(0.0)
	fx._snap()
	assert_float(fx.screen_scale()).is_equal_approx(SCALE, 0.0001)
	assert_float(fx.level).is_greater(0.0)
	assert_float(fx.screen_material.get_shader_parameter("distortion")) \
		.is_equal_approx(fx.max_distortion_px * fx.level * SCALE, 0.0001)
	assert_float(fx.screen_material.get_shader_parameter("aberration")) \
		.is_equal_approx(fx.max_aberration_px * fx.level * SCALE, 0.0001)


func test_click_under_a_scaled_viewport_picks_the_cell_and_builds() -> void:
	await _start_game()
	var cell := _far_buildable_cell()
	var gold := _game.sim.state.gold
	await _click(_game.board.position + (Vector2(cell) + Vector2(0.5, 0.5)) * Board.CELL)
	assert_bool(_game.picker.visible).is_true()
	assert_vector(_game.picker.cell).is_equal(cell)
	await _click(_game.picker.buttons[RIFLE].get_global_rect().get_center())
	assert_bool(_game.sim.state.tower_at.has(cell)).is_true()
	assert_int(_game.sim.state.gold).is_equal(gold - _config.towers[RIFLE].cost)
