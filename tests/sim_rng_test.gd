class_name SimRngTest
extends GdUnitTestSuite
## LT-102 B7 (docs/design/LT-102-portability-core.md §1 D-1, §7): SimRng.randf / randi_range
## and the SimContext forwarders are the plain RandomNumberGenerator calls on the stream's
## generator (seed run_seed * 16 + stream), and randi_range(s, a, a) draws nothing.

const RUN_SEED := 7


## A fresh generator seeded as SimRng seeds stream `s`.
func _reference(s: SimRng.Stream) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = RUN_SEED * SimRng.STREAM_SEED_STRIDE + s
	return g


func test_the_stream_seed_is_run_seed_times_16_plus_stream() -> void:
	assert_int(SimRng.STREAM_SEED_STRIDE).is_equal(16)
	var rng := SimRng.new(RUN_SEED)
	for s: SimRng.Stream in SimRng.Stream.values():
		assert_int(rng.stream(s).seed).is_equal(RUN_SEED * 16 + s)


func test_draws_equal_a_fresh_generator_with_the_same_seed() -> void:
	var rng := SimRng.new(RUN_SEED)
	for s: SimRng.Stream in SimRng.Stream.values():
		var ref := _reference(s)
		for i in 200:
			if i % 3 == 0:
				assert_float(rng.randf(s)).is_equal(ref.randf())
			else:
				assert_int(rng.randi_range(s, 0, i)).is_equal(ref.randi_range(0, i))
		assert_int(rng.stream(s).state).is_equal(ref.state)


func test_a_draw_on_one_stream_leaves_the_others_untouched() -> void:
	var rng := SimRng.new(RUN_SEED)
	var before := {}
	for s: SimRng.Stream in SimRng.Stream.values():
		before[s] = rng.stream(s).state
	rng.randf(SimRng.Stream.COMBAT)
	rng.randi_range(SimRng.Stream.COMBAT, 0, 9)
	for s: SimRng.Stream in SimRng.Stream.values():
		if s == SimRng.Stream.COMBAT:
			assert_int(rng.stream(s).state).is_not_equal(before[s])
		else:
			assert_int(rng.stream(s).state).is_equal(before[s])


func test_randi_range_of_one_value_returns_it_and_draws_nothing() -> void:
	var rng := SimRng.new(RUN_SEED)
	for s: SimRng.Stream in SimRng.Stream.values():
		for v: int in [3, 0, -5]:
			var state := rng.stream(s).state
			assert_int(rng.randi_range(s, v, v)).is_equal(v)
			assert_int(rng.stream(s).state).override_failure_message(
				"randi_range(%d, %d, %d) drew on the stream" % [s, v, v]).is_equal(state)
		# The next real draw is the generator's first.
		assert_float(rng.randf(s)).is_equal(_reference(s).randf())


func test_the_sim_context_forwards_to_the_same_streams() -> void:
	var ctx := SimContext.new(null, RUN_SEED)
	assert_object(ctx.sim_rng()).is_not_null()
	for s: SimRng.Stream in SimRng.Stream.values():
		var ref := _reference(s)
		for i in 30:
			assert_float(ctx.randf(s)).is_equal(ref.randf())
			assert_int(ctx.randi_range(s, -4, 4)).is_equal(ref.randi_range(-4, 4))
		var state := ctx.rng(s).state
		assert_int(ctx.randi_range(s, 2, 2)).is_equal(2)
		assert_int(ctx.rng(s).state).is_equal(state)
		assert_int(ctx.sim_rng().stream(s).state).is_equal(ref.state)
