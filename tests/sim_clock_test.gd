class_name SimClockTest
extends GdUnitTestSuite
## LT-4 §1.1/§1.2: SimTime conversions and SimClock frame -> steps (behaviours 12, 13, 18).
## Feeds synthetic deltas only; nothing depends on real time.


func _total(clock: SimClock, frames: int, delta: float) -> int:
	var total := 0
	for i in frames:
		total += clock.advance(delta)
	return total


# --- SimTime ----------------------------------------------------------------

func test_ticks_rounds_seconds_to_whole_ticks() -> void:
	assert_int(SimTime.TICK_RATE).is_equal(30)
	assert_int(SimTime.ticks(1.2)).is_equal(36)
	assert_int(SimTime.ticks(25.0)).is_equal(750)
	assert_int(SimTime.ticks(0.0)).is_equal(0)
	assert_int(SimTime.ticks(1.0 / 30.0)).is_equal(1)


func test_units_per_tick_from_cells_per_second() -> void:
	assert_int(SimTime.UNITS_PER_CELL).is_equal(30000)
	assert_int(SimTime.units_per_tick(1.0)).is_equal(1000)
	assert_int(SimTime.units_per_tick(1.6)).is_equal(1600)
	assert_int(SimTime.units_per_tick(0.9)).is_equal(900)
	assert_int(SimTime.units_per_tick(1.3)).is_equal(1300)
	assert_int(SimTime.units_per_tick(0.4)).is_equal(400)


# --- frame-rate independence ------------------------------------------------

func test_one_second_is_30_steps_at_any_frame_rate() -> void:
	for fps: int in [30, 60, 144, 50, 240]:
		var clock := SimClock.new()
		assert_int(_total(clock, fps, 1.0 / fps)).override_failure_message(
			"%d fps" % fps).is_equal(30)


func test_60_fps_alternates_0_and_1() -> void:
	var clock := SimClock.new()
	var steps: Array[int] = []
	for i in 6:
		steps.append(clock.advance(1.0 / 60.0))
	assert_array(steps).is_equal([0, 1, 0, 1, 0, 1])


func test_speed_2_doubles_steps() -> void:
	var clock := SimClock.new()
	clock.speed = 2
	assert_int(_total(clock, 60, 1.0 / 60.0)).is_equal(60)


func test_pause_yields_zero_and_freezes_the_accumulator() -> void:
	var clock := SimClock.new()
	clock.advance(1.0 / 60.0)  # half a tick pending
	var alpha := clock.alpha()
	clock.speed = 0
	assert_int(_total(clock, 100, 1.0 / 60.0)).is_equal(0)
	assert_float(clock.alpha()).is_equal(alpha)
	clock.speed = 1
	assert_int(clock.advance(1.0 / 60.0)).is_equal(1)  # the pending half completes


# --- catch-up cap -----------------------------------------------------------

func test_long_hitch_is_capped_at_8_and_excess_dropped() -> void:
	var clock := SimClock.new()
	assert_int(SimClock.MAX_STEPS_PER_FRAME).is_equal(8)
	assert_int(clock.advance(1.0)).is_equal(8)
	# The other 22 ticks are gone: the next normal frame is a normal frame.
	assert_int(clock.advance(1.0 / 30.0)).is_equal(1)
	assert_int(clock.advance(0.0)).is_equal(0)


func test_advance_always_in_0_to_8() -> void:
	var clock := SimClock.new()
	for spd: int in [0, 1, 2]:
		clock.speed = spd
		for d: float in [0.0, 0.001, 1.0 / 144.0, 1.0 / 60.0, 0.1, 0.27, 0.5, 3.0, 100.0, -0.5]:
			assert_int(clock.advance(d)).is_between(0, 8)


# --- clamps (behaviour 18) --------------------------------------------------

func test_speed_is_clamped_into_0_to_2() -> void:
	var clock := SimClock.new()
	assert_int(clock.speed).is_equal(1)
	clock.speed = -1
	assert_int(clock.speed).is_equal(0)
	clock.speed = 5
	assert_int(clock.speed).is_equal(2)
	assert_int(_total(clock, 30, 1.0 / 30.0)).is_equal(60)  # behaves as x2, not x5


func test_non_positive_delta_yields_zero_steps() -> void:
	var clock := SimClock.new()
	clock.advance(1.0 / 60.0)
	var alpha := clock.alpha()
	assert_int(clock.advance(0.0)).is_equal(0)
	assert_int(clock.advance(-1.0)).is_equal(0)
	assert_float(clock.alpha()).is_equal(alpha)  # a negative delta does not rewind
	assert_int(clock.advance(1.0 / 60.0)).is_equal(1)


# --- alpha ------------------------------------------------------------------

func test_alpha_is_the_elapsed_fraction_of_the_next_tick() -> void:
	var clock := SimClock.new()
	assert_float(clock.alpha()).is_equal(0.0)
	clock.advance(1.0 / 60.0)
	assert_float(clock.alpha()).is_equal_approx(0.5, 1e-6)
	clock.advance(1.0 / 60.0)
	assert_float(clock.alpha()).is_equal_approx(0.0, 1e-5)


func test_alpha_stays_in_0_1() -> void:
	var clock := SimClock.new()
	for i in 500:
		clock.advance(0.0071 * (1 + i % 13))
		var a := clock.alpha()
		assert_float(a).is_greater_equal(0.0)
		assert_float(a).is_less(1.0)
