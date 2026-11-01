class_name FpsReadoutTest
extends GdUnitTestSuite
## LT-44: always-visible FPS label in the Hud (presentation only). The throttle is driven
## through Hud's own timestamp/shown fields, so no test depends on the real frame rate.

var _vp: SubViewport
var _game: Game
var _config: GameConfig


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = SubViewport.new()
	_vp.size = Vector2i(1200, 675)
	add_child(_vp)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _start_game(with_stats: bool) -> void:
	_game = Game.new()
	_game.setup(_config, 7)
	_game.frame_stats = FrameStats.new() if with_stats else null
	_vp.add_child(_game)
	_game.set_process(false)
	await get_tree().process_frame


func _assert_fps_label_in_footer() -> void:
	var hud: Hud = _game.hud
	assert_object(hud.fps_label).is_not_null()
	assert_object(hud.fps_label.get_parent()).is_same(hud)
	assert_str(String(hud.fps_label.name)).is_equal("FpsLabel")
	assert_float(hud.fps_label.position.y).is_greater_equal(hud.footer.position.y)
	assert_int(hud.fps_label.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_fps_label_exists_without_frame_stats() -> void:
	await _start_game(false)
	assert_object(_game.frame_stats).is_null()
	_assert_fps_label_in_footer()


func test_fps_label_exists_with_frame_stats() -> void:
	await _start_game(true)
	_assert_fps_label_in_footer()
	assert_object(_game.hud.frame_label).is_not_null()


func test_fps_refresh_is_throttled_and_formats_the_integer() -> void:
	await _start_game(false)
	var hud: Hud = _game.hud
	assert_int(Hud.FPS_INTERVAL_MSEC).is_equal(250)
	# Inside the interval: refresh leaves the text alone.
	# _fps_shown = -1 so the change guard cannot hide a missing throttle.
	hud.fps_label.text = "sentinel"
	hud._fps_shown = -1
	hud._fps_label_msec = Time.get_ticks_msec()
	hud.refresh()
	assert_str(hud.fps_label.text).is_equal("sentinel")
	# Interval elapsed and nothing shown yet: text becomes "FPS <int>".
	hud._fps_label_msec = Time.get_ticks_msec() - Hud.FPS_INTERVAL_MSEC
	hud._fps_shown = -1
	hud.refresh()
	assert_str(hud.fps_label.text).is_equal("FPS %d" % hud._fps_shown)
	assert_int(hud._fps_shown).is_greater_equal(0)
	# The timestamp was reset, so an immediate second refresh does nothing.
	hud.fps_label.text = "sentinel"
	hud._fps_shown = -1
	hud.refresh()
	assert_str(hud.fps_label.text).is_equal("sentinel")


func test_fps_string_is_rebuilt_only_when_the_integer_changes() -> void:
	await _start_game(false)
	var hud: Hud = _game.hud
	var before := int(Engine.get_frames_per_second())
	hud.fps_label.text = "sentinel"
	hud._fps_shown = before
	hud._fps_label_msec = Time.get_ticks_msec() - Hud.FPS_INTERVAL_MSEC
	hud.refresh()
	if int(Engine.get_frames_per_second()) == before:  # Engine updates the value ~1/s
		assert_str(hud.fps_label.text).is_equal("sentinel")
	# A different shown value forces the rebuild.
	hud._fps_shown = -2
	hud._fps_label_msec = Time.get_ticks_msec() - Hud.FPS_INTERVAL_MSEC
	hud.refresh()
	assert_str(hud.fps_label.text).starts_with("FPS ")


func test_fps_label_is_not_in_the_jitter_material_list() -> void:
	await _start_game(false)
	var hud: Hud = _game.hud
	assert_object(_game.sanity_fx).is_not_null()
	# Control for the precondition: the jitter list really was applied to the HUD.
	assert_object(hud.gold_label.material).is_not_null()
	assert_object(hud.fps_label.material).is_null()


func test_frame_label_only_with_frame_stats() -> void:
	await _start_game(false)
	assert_object(_game.hud.frame_label).is_null()
	assert_object(_game.hud.find_child("FrameLabel", true, false)).is_null()
	_vp.remove_child(_game)
	_game.free()
	await _start_game(true)
	assert_object(_game.hud.frame_label).is_not_null()
