class_name BuildPhaseTest
extends WaveTestBase
## LT-5 build phase: early call (GDD 5.1: bonus = rate x seconds left), refusals, command
## log + replay, speed x1/x2 and pause with building (GDD 8).


func _rate(sim: Simulation) -> float:
	return sim.config.economy.early_call_gold_per_second


# --- early call -----------------------------------------------------------------

func test_early_call_pays_rate_times_whole_seconds_left() -> void:
	var sim := wsim([[group("cultist", 1)]], 25)
	run(sim, 1)  # 749 ticks left = 24 whole seconds
	var gold := sim.state.gold
	sim.drain_events()
	assert_int(sim.call_wave()).is_equal(R.OK)
	var bonus := floori(_rate(sim) * 24)
	assert_int(sim.state.gold).is_equal(gold + bonus)
	var ev := sim.drain_events()
	assert_int(ev.size()).is_equal(2)
	assert_int(ev[0].type).is_equal(SimEvent.Type.WAVE_STARTED)
	assert_dict(ev[0].data).is_equal({"wave": 1, "early": true, "ticks_left": 749})
	assert_int(ev[1].type).is_equal(SimEvent.Type.GOLD_CHANGED)
	assert_int(ev[1].id).is_equal(0)
	assert_dict(ev[1].data).is_equal({"delta": bonus, "gold": gold + bonus,
		"reason": "early_call"})
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	assert_int(sim.state.wave_index).is_equal(1)
	assert_int(sim.state.build_ticks_left).is_equal(0)


func test_early_call_on_the_first_tick_pays_the_full_timer() -> void:
	var sim := wsim([[group("cultist", 1)]], 25)
	var gold := sim.state.gold
	assert_int(sim.call_wave()).is_equal(R.OK)
	assert_int(sim.state.gold).is_equal(gold + floori(_rate(sim) * 25))


func test_early_call_rounds_seconds_down() -> void:
	var sim := wsim([[group("cultist", 1)]], 2)
	run(sim, 60 - 59)  # 59 ticks left: 1 whole second
	var gold := sim.state.gold
	sim.call_wave()
	assert_int(sim.state.gold).is_equal(gold + floori(_rate(sim) * 1))
	# Under one second left: no bonus and no GOLD_CHANGED.
	var sim2 := wsim([[group("cultist", 1)]], 2)
	run(sim2, 60 - 29)
	assert_int(sim2.state.build_ticks_left).is_equal(29)
	var gold2 := sim2.state.gold
	sim2.drain_events()
	assert_int(sim2.call_wave()).is_equal(R.OK)
	assert_int(sim2.state.gold).is_equal(gold2)
	assert_array(of_type(sim2.drain_events(), SimEvent.Type.GOLD_CHANGED)).is_empty()


func test_first_spawn_after_an_early_call_is_on_the_next_tick() -> void:
	var sim := wsim([[group("cultist", 1)]], 25)
	run(sim, 10)
	sim.call_wave()
	sim.drain_events()
	var ev := run(sim, 3)
	assert_array(ticks_of(of_type(ev, SimEvent.Type.SPAWNED))).is_equal([11])


func test_early_call_is_logged_with_its_tick() -> void:
	var sim := wsim([[group("cultist", 1)]], 25)
	run(sim, 10)
	sim.call_wave()
	assert_array(sim.state.command_log).is_equal([[10, "call_wave"]])


func test_early_call_works_in_a_later_build_phase_too() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 3)
	run(sim, SimTime.ticks(3))
	kill_real(sim)
	run(sim, 1)
	run(sim, 31)  # part of the second build phase has run
	var left := sim.state.build_ticks_left
	var gold := sim.state.gold
	assert_int(sim.call_wave()).is_equal(R.OK)
	assert_int(sim.state.wave_index).is_equal(2)
	assert_int(sim.state.gold).is_equal(gold + floori(_rate(sim) * SimTime.whole_seconds(left)))


func test_call_wave_is_refused_outside_build_and_changes_nothing() -> void:
	var sim := wsim([[group("cultist", 1)]], 1)
	run(sim, SimTime.ticks(1))  # wave 1 running
	var gold := sim.state.gold
	sim.drain_events()
	assert_int(sim.call_wave()).is_equal(R.NOT_BUILD_PHASE)
	assert_int(sim.state.gold).is_equal(gold)
	assert_int(sim.state.wave_index).is_equal(1)
	assert_array(sim.state.command_log).is_empty()
	assert_array(sim.drain_events()).is_empty()


func test_second_call_in_a_row_is_refused() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 25)
	assert_int(sim.call_wave()).is_equal(R.OK)
	assert_int(sim.call_wave()).is_equal(R.NOT_BUILD_PHASE)
	assert_int(sim.state.wave_index).is_equal(1)
	assert_int(sim.state.command_log.size()).is_equal(1)


func test_call_wave_without_a_wave_director_is_refused() -> void:
	var sim := tsim()
	assert_int(sim.call_wave()).is_equal(R.NOT_BUILD_PHASE)
	sim.set_spawner(ScriptedSpawner.new())
	assert_int(sim.call_wave()).is_equal(R.NOT_BUILD_PHASE)
	assert_array(sim.state.command_log).is_empty()


func test_call_wave_after_a_loss_reports_outcome_reached() -> void:
	var sim := wsim([[group("cultist", 1)]], 1, 1)
	for i in 700:
		sim.step()
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.LOST)
	assert_int(sim.call_wave()).is_equal(R.OUTCOME_REACHED)


# --- replay -----------------------------------------------------------------------

## Plays `script` (tick -> command) on a fresh sim; returns [events, snapshot].
func _play(run_seed: int, commands: Array, ticks: int) -> Array:
	var sim := wsim([[group("deep_one", 2, 0.5), group("cultist", 2, 0.5, 0.3)],
		[group("deep_one", 1)]], 2, -1, run_seed)
	var out: Array[String] = []
	for t in ticks:
		for c: Array in commands:
			if int(c[0]) == sim.state.tick:
				_apply(sim, c)
		sim.step()
		out.append_array(strings_of(sim.drain_events()))
	out.append("tick=%d gold=%d hp=%d phase=%d wave=%d next_id=%d left=%d" % [
		sim.state.tick, sim.state.gold, sim.state.lighthouse_hp, sim.state.phase,
		sim.state.wave_index, sim.state.next_id, sim.state.build_ticks_left])
	return [out, sim.state.command_log]


func _apply(sim: Simulation, c: Array) -> void:
	match c[1]:
		"build": sim.build_tower(c[2], c[3])
		"sell": sim.sell_tower(c[2])
		"call_wave": sim.call_wave()


func test_replaying_the_command_log_with_the_same_seed_gives_the_same_run() -> void:
	var commands := [[5, "build", "rifleman", TOWER], [20, "call_wave"]]
	var first := _play(SEED, commands, 300)
	assert_array(first[1]).contains([[20, "call_wave"]])
	var replay := _play(SEED, first[1], 300)
	assert_array(replay[0]).is_equal(first[0])
	assert_array(replay[1]).is_equal(first[1])
	# Control: without the logged call the run differs.
	var without := _play(SEED, [[5, "build", "rifleman", TOWER]], 300)
	assert_bool(without[0] == first[0]).is_false()


# --- speed and pause ----------------------------------------------------------------

## Drives the sim like the game loop: frames of `delta` through the clock.
func _drive(sim: Simulation, clock: SimClock, frames: int, delta: float) -> int:
	var steps := 0
	for f in frames:
		var n := clock.advance(delta)
		for i in n:
			sim.step()
		steps += n
	return steps


func test_speed_two_runs_the_build_timer_twice_as_fast() -> void:
	var secs := 25
	var left := {}
	for speed: int in [1, 2]:
		var sim := wsim([[group("cultist", 1)]], secs)
		var clock := SimClock.new()
		clock.speed = speed
		var steps := _drive(sim, clock, 60, 1.0 / 60.0)  # one real second
		assert_int(steps).is_equal(SimTime.TICK_RATE * speed)
		left[speed] = sim.state.build_ticks_left
	assert_int(left[1]).is_equal(SimTime.ticks(secs) - SimTime.TICK_RATE)
	assert_int(left[2]).is_equal(SimTime.ticks(secs) - 2 * SimTime.TICK_RATE)


func test_clock_speed_is_clamped_and_steps_are_capped() -> void:
	var clock := SimClock.new()
	clock.speed = 5
	assert_int(clock.speed).is_equal(2)
	clock.speed = -3
	assert_int(clock.speed).is_equal(0)
	clock.speed = 2
	assert_int(clock.advance(10.0)).is_equal(SimClock.MAX_STEPS_PER_FRAME)


func test_pause_runs_zero_steps_and_freezes_the_timer() -> void:
	var sim := wsim([[group("cultist", 1)]], 25)
	var clock := SimClock.new()
	_drive(sim, clock, 30, 1.0 / 30.0)
	var left := sim.state.build_ticks_left
	var tick := sim.state.tick
	clock.speed = 0
	assert_int(_drive(sim, clock, 120, 1.0 / 60.0)).is_equal(0)
	assert_int(sim.state.build_ticks_left).is_equal(left)
	assert_int(sim.state.tick).is_equal(tick)
	clock.speed = 1
	assert_int(_drive(sim, clock, 30, 1.0 / 30.0)).is_equal(30)
	assert_int(sim.state.build_ticks_left).is_equal(left - 30)


func test_building_and_selling_still_apply_while_paused() -> void:
	var sim := wsim([[group("cultist", 1)]], 25)
	var clock := SimClock.new()
	clock.speed = 0
	_drive(sim, clock, 10, 1.0 / 30.0)
	var left := sim.state.build_ticks_left
	var gold := sim.state.gold
	assert_int(sim.build_tower("rifleman", TOWER)).is_equal(R.OK)
	assert_int(sim.state.gold).is_less(gold)
	assert_int(sim.state.tower_at[TOWER]).is_greater(0)
	assert_int(sim.sell_tower(sim.state.tower_at[TOWER])).is_equal(R.OK)
	assert_bool(sim.state.tower_at.has(TOWER)).is_false()
	assert_int(sim.state.build_ticks_left).is_equal(left)
	assert_int(sim.state.tick).is_equal(0)
	assert_int(sim.state.command_log.size()).is_equal(2)
