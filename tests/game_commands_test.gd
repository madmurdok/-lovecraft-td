class_name GameCommandsTest
extends WaveTestBase
## LT-107: GameCommands.issue runs a Simulation.COMMANDS entry and calls `after` once, OK or
## refused; the named forwarders are one-liners over it and match the direct sim call.
## A bare GameCommands over a sim (no Game, no nodes).

const RIFLE := "rifleman"


## [GameCommands, after-call counter] over `sim`.
func _commands(sim: Simulation) -> Array:
	var calls := {"n": 0}
	var gc := GameCommands.new(sim, null, func() -> void: calls["n"] += 1)
	return [gc, calls]


func _day_sim() -> Simulation:
	var sim := wsim([[group("deep_one", 1)]], 5)
	sim.state.gold = 100000
	sim.state.relics["star_stone"] = 2
	sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	return sim


func test_issue_returns_the_sim_result_and_calls_after_once_when_ok() -> void:
	var sim := _day_sim()
	var c := _commands(sim)
	assert_int(c[0].issue("call_wave", [])).is_equal(R.OK)
	assert_int(c[1]["n"]).is_equal(1)
	assert_str(sim.state.command_log.back()[1]).is_equal("call_wave")


func test_issue_returns_the_refusal_and_calls_after_once_when_refused() -> void:
	var sim := _day_sim()
	var want := sim.can_buy_sanity()  # not in MADNESS: refused
	assert_int(want).is_not_equal(R.OK)
	var c := _commands(sim)
	var n := sim.state.command_log.size()
	assert_int(c[0].issue("buy_sanity", [])).is_equal(want)
	assert_int(c[1]["n"]).is_equal(1)
	assert_int(sim.state.command_log.size()).is_equal(n)
	assert_int(c[0].issue("fire_flare", [])).is_equal(R.NOT_NIGHT)
	assert_int(c[1]["n"]).is_equal(2)


## Each named forwarder vs the sim method on a twin: same result, same log; after once each.
func test_named_forwarders_match_the_direct_sim_call() -> void:
	var a := _day_sim()
	var b := _day_sim()
	var c := _commands(a)
	var gc: GameCommands = c[0]
	var steps: Array = [
		[func() -> int: return gc.build(RIFLE, Vector2i(5, 1)),
			func() -> int: return b.build_tower(RIFLE, Vector2i(5, 1))],
		[func() -> int: return gc.set_target_priority(a.state.tower_at[Vector2i(5, 1)], "strongest"),
			func() -> int: return b.set_target_priority(b.state.tower_at[Vector2i(5, 1)], "strongest")],
		[func() -> int: return gc.upgrade(a.state.tower_at[Vector2i(5, 1)]),
			func() -> int: return b.upgrade_tower(b.state.tower_at[Vector2i(5, 1)])],
		[func() -> int: return gc.sell(a.state.tower_at[Vector2i(5, 1)]),
			func() -> int: return b.sell_tower(b.state.tower_at[Vector2i(5, 1)])],
		[func() -> int: return gc.sell_relics(), func() -> int: return b.sell_relics()],
		[func() -> int: return gc.buy_sanity(), func() -> int: return b.buy_sanity()],
		[func() -> int: return gc.upgrade_lighthouse(), func() -> int: return b.upgrade_lighthouse()],
		[func() -> int: return gc.buy_oil(), func() -> int: return b.buy_oil()],
		[func() -> int: return gc.fire_flare(), func() -> int: return b.fire_flare()],
		[func() -> int: return gc.call_wave(), func() -> int: return b.call_wave()],
	]
	for i in steps.size():
		var got: int = steps[i][0].call()
		var want: int = steps[i][1].call()
		assert_int(got).override_failure_message("step %d" % i).is_equal(want)
		assert_array(a.state.command_log).override_failure_message("step %d" % i) \
			.is_equal(b.state.command_log)
		assert_int(c[1]["n"]).is_equal(i + 1)
	assert_int(a.state.command_log.size()).is_greater(5)
