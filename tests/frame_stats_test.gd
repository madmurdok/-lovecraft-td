class_name FrameStatsTest
extends GdUnitTestSuite
## LT-38 P1: FrameStats median/p90 math, and the debug-only `--frame-stats` wiring in Game and Hud.

var _vp: SubViewport
var _game: Game
var _config: GameConfig


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = SubViewport.new()
	_vp.size = Vector2i(1152, 648)
	add_child(_vp)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _stats(values: Array) -> FrameStats:
	var s := FrameStats.new()
	for v: float in values:
		s.push(v)
	return s


## `with_stats` seeds the stats the way setup does under the flag (the gate itself reads
## OS.is_debug_build() and the process command line inline, so it cannot be driven here).
func _start_game(with_stats: bool) -> void:
	_game = Game.new()
	_game.setup(_config, 7)
	if with_stats:
		_game.frame_stats = FrameStats.new()
	_vp.add_child(_game)
	_game.set_process(false)
	await get_tree().process_frame


func test_empty_buffer_reports_zero_and_no_samples_text() -> void:
	var s := FrameStats.new()
	assert_int(s.count()).is_equal(0)
	assert_float(s.median_ms()).is_equal(0.0)
	assert_float(s.p90_ms()).is_equal(0.0)
	assert_str(s.text()).is_equal("frame - (no samples)")


func test_odd_count_median_is_the_middle_value_regardless_of_order() -> void:
	var s := _stats([5.0, 1.0, 3.0, 2.0, 4.0])
	assert_float(s.median_ms()).is_equal(3.0)
	assert_float(s.p90_ms()).is_equal(5.0)


func test_even_count_median_is_the_mean_of_the_two_middle_values() -> void:
	var s := _stats([4.0, 1.0, 3.0, 2.0])
	assert_float(s.median_ms()).is_equal(2.5)
	assert_float(s.p90_ms()).is_equal(4.0)


func test_partly_filled_buffer_uses_only_the_pushed_samples() -> void:
	var s := _stats([10.0, 20.0, 60.0])
	assert_int(s.count()).is_equal(3)
	assert_float(s.median_ms()).is_equal(20.0)
	assert_float(s.p90_ms()).is_equal(60.0)


func test_p90_is_nearest_rank() -> void:
	var values: Array = []
	for i in range(1, 16):
		values.append(float(i))
	assert_float(_stats(values).p90_ms()).is_equal(14.0)


func test_p90_where_nine_tenths_of_the_count_is_whole() -> void:
	var values: Array = []
	for i in range(1, 11):
		values.append(float(i))
	assert_float(_stats(values).p90_ms()).is_equal(9.0)


func test_p90_of_a_full_buffer_is_the_nearest_rank_value() -> void:
	var values: Array = []
	for i in range(1, FrameStats.CAPACITY + 1):
		values.append(float(i))
	var s := _stats(values)
	assert_int(s.count()).is_equal(FrameStats.CAPACITY)
	assert_float(s.p90_ms()).is_equal(108.0)  # sorted[107] of 1..120


func test_text_format() -> void:
	assert_str(_stats([10.0, 20.0, 30.0]).text()).is_equal("frame 20.0 ms median / 30.0 p90")


func test_wrap_around_evicts_the_oldest_samples() -> void:
	var s := FrameStats.new()
	for i in range(1, 131):
		s.push(float(i))
	assert_int(s.count()).is_equal(FrameStats.CAPACITY)
	# window is 11..130: mean of the 60th and 61st values (70, 71)
	assert_float(s.median_ms()).is_equal(70.5)
	# fully replacing the window leaves no trace of the old, large samples
	var t := FrameStats.new()
	for i in FrameStats.CAPACITY:
		t.push(1000.0)
	for i in FrameStats.CAPACITY:
		t.push(1.0)
	assert_int(t.count()).is_equal(FrameStats.CAPACITY)
	assert_float(t.median_ms()).is_equal(1.0)
	assert_float(t.p90_ms()).is_equal(1.0)


func test_percentile_does_not_mutate_its_input() -> void:
	var v := PackedFloat64Array([3.0, 1.0, 2.0])
	FrameStats.percentile(v, 0.5)
	assert_float(v[0]).is_equal(3.0)
	assert_float(v[1]).is_equal(1.0)


func test_setup_creates_stats_only_with_the_flag_in_a_debug_build() -> void:
	var g := Game.new()
	g.setup(_config, 7)
	var expected := OS.is_debug_build() and OS.get_cmdline_user_args().has(Game.FRAME_STATS_ARG)
	assert_bool(g.frame_stats != null).is_equal(expected)
	g.free()


func test_without_stats_there_is_no_label_and_advance_does_no_buffer_work() -> void:
	await _start_game(false)
	assert_object(_game.frame_stats).is_null()
	assert_object(_game.hud.frame_label).is_null()
	assert_object(_game.hud.find_child("FrameLabel", true, false)).is_null()
	_game.advance(0.0)
	_game.advance(0.0)
	assert_object(_game.frame_stats).is_null()


func test_with_stats_the_hud_gets_a_frame_label() -> void:
	await _start_game(true)
	assert_object(_game.hud.frame_label).is_not_null()
	assert_object(_game.hud.find_child("FrameLabel", true, false)).is_same(_game.hud.frame_label)


func test_advance_feeds_the_wall_clock_interval_not_the_delta() -> void:
	await _start_game(true)
	_game.advance(0.0)  # first call only records the timestamp
	assert_int(_game.frame_stats.count()).is_equal(0)
	OS.delay_msec(30)
	_game.advance(0.0)  # delta 0: a sample can only come from Time
	assert_int(_game.frame_stats.count()).is_equal(1)
	assert_float(_game.frame_stats.median_ms()).is_greater_equal(30.0)


func test_hud_label_shows_the_stats_text() -> void:
	await _start_game(true)
	OS.delay_msec(260)  # past the label's 250 ms refresh throttle
	for ms in [10.0, 20.0, 30.0]:
		_game.frame_stats.push(ms)
	_game.hud.refresh()
	assert_str(_game.hud.frame_label.text).is_equal(_game.frame_stats.text())
