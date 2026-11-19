class_name Lt62FpsTest
extends GdUnitTestSuite
## LT-62 P1 + P2: the board's first-use warm-up draw (runs in the first WARMUP_SECONDS
## only) and the frame-spike log (FrameStats.is_spike / worst_ms / spike_line / text, and
## Game.advance printing one line per spike, only under --frame-stats).

## Collects what print() writes, to see whether Game.advance logged a spike line.
class LogSpy:
	extends Logger
	var lines: Array[String] = []

	func _log_message(message: String, error: bool) -> void:
		if not error:
			lines.append(message)

	func spikes() -> Array[String]:
		var out: Array[String] = []
		for l in lines:
			if l.contains("LT-62 spike"):
				out.append(l)
		return out


## Board that counts its warm-up draws and its _draw passes.
class SpyBoard:
	extends Board
	var warmups := 0
	var draws := 0

	func _draw() -> void:
		draws += 1
		super._draw()

	func _draw_warmup() -> void:
		warmups += 1
		super._draw_warmup()


var _vp: SubViewport
var _game: Game
var _config: GameConfig
var _spy: LogSpy


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = GameFixture.make_viewport(self)


func after_test() -> void:
	if _spy != null:
		OS.remove_logger(_spy)
		_spy = null
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _start_game(args: PackedStringArray = PackedStringArray()) -> void:
	_game = GameFixture.make_game(_vp, _config, 7, args)
	await get_tree().process_frame


func _watch_log() -> void:
	_spy = LogSpy.new()
	OS.add_logger(_spy)


func _stats(values: Array) -> FrameStats:
	var s := FrameStats.new()
	for v: float in values:
		s.push(v)
	return s


# ---- P1: warm-up draw -------------------------------------------------------------------


## A SpyBoard on the started game's sim, drawn once per frame awaited.
func _spy_board() -> SpyBoard:
	await _start_game()
	var b := SpyBoard.new()
	b.game = _game
	_vp.add_child(b)
	return b


func _draw_frames(b: SpyBoard, n: int) -> void:
	for i in n:
		b.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame


func test_warmup_draw_runs_in_the_first_half_second() -> void:
	var b := await _spy_board()
	await _draw_frames(b, 2)
	assert_int(b.draws).is_greater(0)
	assert_int(b.warmups).is_greater(0)
	assert_int(b.warmups).is_equal(b.draws)  # every draw while _time == 0 warms up


func test_warmup_draw_stops_after_half_second_of_effects_time() -> void:
	var b := await _spy_board()
	b.tick_effects(Board.WARMUP_SECONDS - 0.01)
	await _draw_frames(b, 1)
	var before := b.warmups
	assert_int(before).is_greater(0)  # still inside the window
	b.tick_effects(0.02)  # _time now past WARMUP_SECONDS
	await _draw_frames(b, 3)
	assert_int(b.warmups).is_equal(before)
	assert_int(b.draws).is_greater(before)  # the board did keep drawing


func test_board_without_a_game_draws_no_warmup() -> void:
	var b := SpyBoard.new()
	_vp.add_child(b)
	await _draw_frames(b, 2)
	assert_int(b.warmups).is_equal(0)


# ---- P2: FrameStats ---------------------------------------------------------------------


func test_is_spike_is_strictly_above_the_threshold() -> void:
	assert_bool(FrameStats.is_spike(100.0)).is_false()
	assert_bool(FrameStats.is_spike(100.01)).is_true()
	assert_bool(FrameStats.is_spike(16.7)).is_false()
	assert_bool(FrameStats.is_spike(412.3)).is_true()


func test_worst_ms_of_an_empty_buffer_is_zero() -> void:
	assert_float(FrameStats.new().worst_ms()).is_equal(0.0)


func test_worst_ms_ignores_samples_older_than_the_last_second() -> void:
	# newest first: 40 x 20 ms = 800 ms, then 15 (815), then an old 500 would reach 1315.
	var values: Array = [500.0, 15.0]
	for i in 40:
		values.append(20.0)
	assert_float(_stats(values).worst_ms()).is_equal(20.0)
	# the same big sample inside the window is the worst
	var inside: Array = [20.0, 20.0, 500.0, 20.0, 20.0]
	assert_float(_stats(inside).worst_ms()).is_equal(500.0)


func test_worst_ms_window_boundary_is_inclusive_of_exactly_one_second() -> void:
	# newest first: 4 x 250 = 1000 ms exactly counts; the 900 before it does not.
	var s := _stats([900.0, 250.0, 250.0, 250.0, 250.0])
	assert_float(s.worst_ms()).is_equal(250.0)


func test_worst_ms_counts_the_newest_sample_even_when_alone_over_a_second() -> void:
	assert_float(_stats([5.0, 1500.0]).worst_ms()).is_equal(1500.0)


func test_worst_ms_follows_the_ring_after_wrap_around() -> void:
	var s := FrameStats.new()
	s.push(900.0)  # evicted below
	for i in FrameStats.CAPACITY:
		s.push(10.0)
	s.push(80.0)  # newest, written over the oldest slot
	assert_int(s.count()).is_equal(FrameStats.CAPACITY)
	assert_float(s.worst_ms()).is_equal(80.0)
	s.push(10.0)
	# the 80 is still inside the last second (2 samples, 90 ms)
	assert_float(s.worst_ms()).is_equal(80.0)


func test_text_ends_with_the_worst_of_the_last_second() -> void:
	var s := _stats([10.0, 20.0, 350.0, 30.0])
	assert_str(s.text()).ends_with("/ worst 350.0")
	assert_str(s.text()).is_equal("frame 25.0 ms median / 350.0 p90 / worst 350.0")


func test_spike_line_has_ms_and_context_in_insertion_order() -> void:
	var ctx := {"t": "12.50s", "tick": 300, "sanity": "FRAYING", "focus": true}
	assert_str(FrameStats.spike_line(412.34, ctx)).is_equal(
		"LT-62 spike 412.3 ms | t=12.50s tick=300 sanity=FRAYING focus=true")
	var swapped := {"focus": false, "tick": 1}
	assert_str(FrameStats.spike_line(101.0, swapped)).is_equal(
		"LT-62 spike 101.0 ms | focus=false tick=1")


# ---- P2: Game wiring --------------------------------------------------------------------


func test_flag_creates_stats_in_a_debug_build_and_no_flag_does_not() -> void:
	await _start_game(PackedStringArray([DebugArgs.FRAME_STATS_ARG]))
	assert_bool(_game.frame_stats != null).is_equal(OS.is_debug_build())
	_game.queue_free()
	await _start_game(PackedStringArray())
	assert_object(_game.frame_stats).is_null()


func test_spike_interval_prints_one_line_under_the_flag() -> void:
	if not OS.is_debug_build():
		return
	await _start_game(PackedStringArray([DebugArgs.FRAME_STATS_ARG]))
	_game.advance(0.0)  # first frame only records the time
	_watch_log()
	OS.delay_msec(130)
	_game.advance(0.0)
	assert_int(_spy.spikes().size()).is_equal(1)
	assert_str(_spy.spikes()[0]).contains("LT-62 spike 1")  # 130+ ms
	assert_str(_spy.spikes()[0]).contains("tick=")


func test_fast_and_first_frames_print_no_spike_line() -> void:
	if not OS.is_debug_build():
		return
	await _start_game(PackedStringArray([DebugArgs.FRAME_STATS_ARG]))
	_watch_log()
	_game.advance(0.0)  # first frame: no interval to judge
	_game.advance(0.0)  # microseconds later
	assert_int(_spy.spikes().size()).is_equal(0)
	assert_int(_game.frame_stats.count()).is_equal(1)


func test_no_spike_line_without_the_flag() -> void:
	await _start_game(PackedStringArray())
	_game.advance(0.0)
	_watch_log()
	OS.delay_msec(130)
	_game.advance(0.0)
	assert_int(_spy.spikes().size()).is_equal(0)
	assert_object(_game.frame_stats).is_null()


func test_spike_context_reports_the_run_without_changing_it() -> void:
	await _start_game(PackedStringArray([DebugArgs.FRAME_STATS_ARG]))
	var before := [_game.sim.state.tick, _game.sim.state.sanity, _game.sim.state.enemies.size()]
	var ctx := _game.spike_context(2_500_000)
	assert_array(ctx.keys()).is_equal(
		["t", "tick", "sanity", "enemies", "towers", "effects", "focus", "events"])
	assert_str(ctx["t"]).is_equal("2.50s")
	assert_int(ctx["tick"]).is_equal(_game.sim.state.tick)
	assert_str(ctx["sanity"]).is_equal(
		SimState.SanityState.keys()[_game.sim.state.sanity_state])
	assert_int(ctx["enemies"]).is_equal(_game.sim.state.enemies.size())
	assert_int(ctx["towers"]).is_equal(_game.sim.state.towers.size())
	assert_int(ctx["effects"]).is_equal(_game.board.effects.size())
	assert_array([_game.sim.state.tick, _game.sim.state.sanity, _game.sim.state.enemies.size()]) \
		.is_equal(before)


func test_events_are_counted_by_type_only_under_the_flag_and_cleared_by_advance() -> void:
	await _start_game(PackedStringArray([DebugArgs.FRAME_STATS_ARG]))
	if _game.frame_stats == null:
		return  # release build: no stats
	_game.sim._add_sanity(-5.0, "test", 0)
	_game._consume_events()
	assert_bool(_game._frame_events.is_empty()).is_false()
	for k: String in _game._frame_events:
		assert_bool(SimEvent.Type.keys().has(k)).is_true()
	assert_dict(_game.spike_context(1)["events"]).is_equal(_game._frame_events)
	_game.advance(0.0)
	assert_bool(_game._frame_events.is_empty()).is_true()
	_game.queue_free()
	await _start_game(PackedStringArray())
	_game.sim._add_sanity(-5.0, "test", 0)
	_game._consume_events()
	assert_bool(_game._frame_events.is_empty()).is_true()
