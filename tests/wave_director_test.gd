class_name WaveDirectorTest
extends WaveTestBase
## LT-5 wave director: build timer, spawn schedule, wave end, bonus order, outcome.
## Spec: GDD 5.1 (wave bonus), 8 (build phase). Numbers come from the config.


# --- build phase before wave 1 ------------------------------------------------

func test_run_starts_in_build_with_the_config_timer() -> void:
	for secs: int in [7, 25]:
		var sim := wsim([[group("cultist", 1)]], secs)
		var ticks := SimTime.ticks(secs)
		assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
		assert_int(sim.state.wave_index).is_equal(0)
		assert_int(sim.state.waves_total).is_equal(1)
		assert_int(sim.state.build_ticks_left).is_equal(ticks)
		var ev := of_type(sim.drain_events(), SimEvent.Type.BUILD_STARTED)
		assert_int(ev.size()).is_equal(1)
		assert_int(ev[0].tick).is_equal(0)
		assert_dict(ev[0].data).is_equal({"next_wave": 1, "ticks": ticks})


func test_real_config_first_build_phase_is_its_build_seconds() -> void:
	var cfg := real_config()
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(WaveDirector.new(cfg.waves))
	assert_int(sim.state.build_ticks_left).is_equal(SimTime.ticks(cfg.waves.build_phase_seconds))
	assert_int(sim.state.waves_total).is_equal(cfg.waves.waves.size())


func test_timer_counts_down_one_per_step_and_expiry_starts_wave_one() -> void:
	var sim := wsim([[group("cultist", 1)]], 2)
	var n := SimTime.ticks(2)
	sim.drain_events()
	run(sim, 1)
	assert_int(sim.state.build_ticks_left).is_equal(n - 1)
	var early := run(sim, n - 2)
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	assert_int(sim.state.build_ticks_left).is_equal(1)
	assert_array(of_type(early, SimEvent.Type.WAVE_STARTED)).is_empty()
	var ev := run(sim, 1)
	assert_int(sim.state.tick).is_equal(n)
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	assert_int(sim.state.wave_index).is_equal(1)
	assert_int(sim.state.build_ticks_left).is_equal(0)
	var started := of_type(ev, SimEvent.Type.WAVE_STARTED)
	assert_int(started.size()).is_equal(1)
	assert_int(started[0].tick).is_equal(n)
	assert_dict(started[0].data).is_equal({"wave": 1, "early": false, "ticks_left": 0})
	# Wave tick 0 is the expiry tick: an offset-0 group spawns right then.
	assert_array(ticks_of(of_type(ev, SimEvent.Type.SPAWNED))).is_equal([n])


# --- spawn schedule -------------------------------------------------------------

func test_group_spawns_at_delay_plus_k_times_interval() -> void:
	var sim := wsim([[group("cultist", 3, 1.2, 0.5)]], 2)
	var start := SimTime.ticks(2)
	var d := SimTime.ticks(0.5)
	var i := SimTime.ticks(1.2)
	sim.drain_events()
	var ev := run(sim, start + d + 2 * i + 5)
	assert_array(ticks_of(of_type(ev, SimEvent.Type.SPAWNED))).is_equal(
		[start + d, start + d + i, start + d + 2 * i])


func test_interval_zero_spawns_the_whole_group_in_one_tick() -> void:
	var sim := wsim([[group("cultist", 4, 0.0, 1.0)]], 1)
	var at := SimTime.ticks(1) + SimTime.ticks(1.0)
	sim.drain_events()
	var ev := run(sim, at + 3)
	assert_array(ticks_of(of_type(ev, SimEvent.Type.SPAWNED))).is_equal([at, at, at, at])


func test_total_spawned_equals_group_counts() -> void:
	var sim := wsim([[group("cultist", 3, 0.2), group("hybrid", 2, 0.2, 0.1)]], 1)
	sim.drain_events()
	var ev := run(sim, SimTime.ticks(1) + 60)
	var defs: Array = of_type(ev, SimEvent.Type.SPAWNED).map(func(e: SimEvent) -> String:
		return e.data["def"])
	assert_int(defs.count("cultist")).is_equal(3)
	assert_int(defs.count("hybrid")).is_equal(2)


func test_same_tick_events_fire_in_group_order() -> void:
	var sim := wsim([[group("hybrid", 2), group("cultist", 2)]], 1)
	sim.drain_events()
	var ev := run(sim, SimTime.ticks(1))
	var defs: Array = of_type(ev, SimEvent.Type.SPAWNED).map(func(e: SimEvent) -> String:
		return e.data["def"])
	assert_array(defs).is_equal(["hybrid", "hybrid", "cultist", "cultist"])


func test_pack_group_rolls_sizes_on_the_spawn_stream() -> void:
	var waves := [[group("deep_one", 4)]]
	var sim := wsim(waves, 1)
	var pack: Dictionary = sim.config.enemies["deep_one"].traits["pack"]
	sim.drain_events()
	var span := pack_span_ticks(sim.config, "deep_one")  # LT-63: members enter one by one
	var ev := run(sim, SimTime.ticks(1) + span)
	var n := of_type(ev, SimEvent.Type.SPAWNED).size()
	assert_int(n).is_between(4 * int(pack["min"]), 4 * int(pack["max"]))
	# Same total as four direct spawns on a fresh sim with the same seed (SPAWN stream).
	var ref := Simulation.new(sim.config, SEED)
	for k in 4:
		ref.spawn_enemy("deep_one")
	run(ref, span)
	assert_int(n).is_equal(ref.state.next_id - 1)
	# Rolls on other streams do not change the wave's pack sizes.
	var other := wsim(waves, 1)
	for k in 30:
		other.rng(SimRng.Stream.COMBAT).randi()
	other.drain_events()
	assert_int(of_type(run(other, SimTime.ticks(1) + span), SimEvent.Type.SPAWNED).size()) \
		.is_equal(n)


func test_same_seed_same_events_different_seed_can_differ() -> void:
	var waves := [[group("deep_one", 3, 0.5), group("cultist", 3, 0.5, 0.2)]]
	var sizes := {}
	for s: int in [1, 2, 3, 4, 5, 6, 7, 8]:
		var a := run(wsim(waves, 1, -1, s), 200)
		var b := run(wsim(waves, 1, -1, s), 200)
		assert_array(strings_of(a)).is_equal(strings_of(b))
		sizes[of_type(a, SimEvent.Type.SPAWNED).size()] = true
	assert_int(sizes.size()).is_greater(1)


# --- wave end ----------------------------------------------------------------------

func test_wave_stays_open_while_a_real_enemy_lives_then_clears() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 1)
	run(sim, SimTime.ticks(1))
	var open := run(sim, 20)
	assert_array(of_type(open, SimEvent.Type.WAVE_CLEARED)).is_empty()
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	kill_real(sim)
	sim.drain_events()
	var ev := run(sim, 1)
	assert_int(of_type(ev, SimEvent.Type.WAVE_CLEARED).size()).is_equal(1)
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)


func test_unspawned_delayed_group_holds_the_wave_open() -> void:
	var sim := wsim([[group("cultist", 1), group("hybrid", 1, 0.0, 3.0)], [group("cultist", 1)]], 1)
	var start := SimTime.ticks(1)
	run(sim, start)
	kill_real(sim)
	var ev := run(sim, SimTime.ticks(3.0) - 2)  # everything spawned so far is dead
	assert_array(of_type(ev, SimEvent.Type.WAVE_CLEARED)).is_empty()
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	run(sim, 2)
	assert_int(sim.state.enemies.size()).is_equal(1)  # the hybrid is out now
	kill_real(sim)
	ev = run(sim, 1)
	assert_int(of_type(ev, SimEvent.Type.WAVE_CLEARED).size()).is_equal(1)


func test_fakes_do_not_hold_the_wave_open() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 1)
	run(sim, SimTime.ticks(1))
	sim.spawn_enemy("hybrid", true)
	kill_real(sim)
	sim.drain_events()
	var ev := run(sim, 1)
	assert_int(of_type(ev, SimEvent.Type.WAVE_CLEARED).size()).is_equal(1)


func test_clear_emits_bonus_then_cleared_then_next_build() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 1)
	run(sim, SimTime.ticks(1))
	kill_real(sim)
	var gold := sim.state.gold
	sim.drain_events()
	var ev := run(sim, 1)
	var bonus := bonus_for(sim, 1)
	var kinds: Array[SimEvent] = []
	for e in ev:
		if e.type in [SimEvent.Type.GOLD_CHANGED, SimEvent.Type.WAVE_CLEARED,
				SimEvent.Type.BUILD_STARTED, SimEvent.Type.OUTCOME]:
			kinds.append(e)
	assert_int(kinds.size()).is_equal(3)
	assert_int(kinds[0].type).is_equal(SimEvent.Type.GOLD_CHANGED)
	assert_dict(kinds[0].data).is_equal({"delta": bonus, "gold": gold + bonus,
		"reason": "wave_bonus"})
	assert_int(kinds[1].type).is_equal(SimEvent.Type.WAVE_CLEARED)
	assert_dict(kinds[1].data).is_equal({"wave": 1, "bonus": bonus})
	assert_int(kinds[2].type).is_equal(SimEvent.Type.BUILD_STARTED)
	assert_dict(kinds[2].data).is_equal({"next_wave": 2, "ticks": SimTime.ticks(1)})
	assert_int(sim.state.gold).is_equal(gold + bonus)
	assert_int(sim.state.build_ticks_left).is_equal(SimTime.ticks(1))
	assert_int(sim.state.wave_index).is_equal(1)


func test_second_wave_starts_after_a_full_build_and_pays_its_own_bonus() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 1)
	run(sim, SimTime.ticks(1))
	kill_real(sim)
	run(sim, 1)
	var cleared_at := sim.state.tick
	var ev := run(sim, SimTime.ticks(1))
	var started := of_type(ev, SimEvent.Type.WAVE_STARTED)
	assert_int(started.size()).is_equal(1)
	assert_int(started[0].tick).is_equal(cleared_at + SimTime.ticks(1))
	assert_dict(started[0].data).is_equal({"wave": 2, "early": false, "ticks_left": 0})
	kill_real(sim)
	sim.drain_events()
	var paid := of_type(run(sim, 1), SimEvent.Type.WAVE_CLEARED)
	assert_dict(paid[0].data).is_equal({"wave": 2, "bonus": bonus_for(sim, 2)})


func test_last_wave_pays_bonus_clears_and_wins_in_the_same_tick() -> void:
	var sim := wsim([[group("cultist", 1)]], 1)
	run(sim, SimTime.ticks(1))
	kill_real(sim)
	var gold := sim.state.gold
	sim.drain_events()
	var ev := run(sim, 1)
	var order: Array[int] = []
	for e in ev:
		if e.type in [SimEvent.Type.GOLD_CHANGED, SimEvent.Type.WAVE_CLEARED,
				SimEvent.Type.OUTCOME, SimEvent.Type.BUILD_STARTED]:
			order.append(e.type)
	assert_array(order).is_equal([SimEvent.Type.GOLD_CHANGED, SimEvent.Type.WAVE_CLEARED,
		SimEvent.Type.OUTCOME])
	assert_int(ev.back().tick).is_equal(sim.state.tick)
	assert_dict(of_type(ev, SimEvent.Type.OUTCOME)[0].data).is_equal({"result": "won"})
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.WON)
	assert_int(sim.state.phase).is_equal(SimState.Phase.DONE)
	assert_int(sim.state.gold).is_equal(gold + bonus_for(sim, 1))


func test_lighthouse_falling_on_the_clearing_tick_loses_without_bonus() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 1, 1)
	var gold := sim.state.gold
	var all: Array[SimEvent] = []
	all.append_array(run(sim, SimTime.ticks(1)))
	for i in 600:
		all.append_array(run(sim, 1))
		if sim.state.outcome != SimState.Outcome.NONE:
			break
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.LOST)
	assert_int(sim.state.lighthouse_hp).is_equal(0)
	assert_array(of_type(all, SimEvent.Type.WAVE_CLEARED)).is_empty()
	for e in of_type(all, SimEvent.Type.GOLD_CHANGED):
		assert_str(e.data["reason"]).is_not_equal("wave_bonus")
	assert_int(sim.state.gold).is_equal(gold)
	assert_int(sim.state.phase).is_not_equal(SimState.Phase.DONE)


func test_leaks_still_pay_the_full_wave_bonus() -> void:
	var sim := wsim([[group("cultist", 2, 0.5)], [group("cultist", 1)]], 1)
	var hp := sim.state.lighthouse_hp
	var gold := sim.state.gold
	var ev: Array[SimEvent] = []
	for i in 900:
		ev.append_array(run(sim, 1))
		if not of_type(ev, SimEvent.Type.WAVE_CLEARED).is_empty():
			break
	assert_int(of_type(ev, SimEvent.Type.LEAKED).size()).is_equal(2)
	assert_int(sim.state.lighthouse_hp).is_less(hp)
	var cleared := of_type(ev, SimEvent.Type.WAVE_CLEARED)
	assert_dict(cleared[0].data).is_equal({"wave": 1, "bonus": bonus_for(sim, 1)})
	assert_int(sim.state.gold).is_equal(gold + bonus_for(sim, 1))


func test_everything_is_frozen_after_the_outcome() -> void:
	var sim := wsim([[group("cultist", 1)]], 1)
	run(sim, SimTime.ticks(1))
	kill_real(sim)
	run(sim, 1)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.WON)
	var tick := sim.state.tick
	var gold := sim.state.gold
	assert_array(run(sim, 50)).is_empty()
	assert_int(sim.state.tick).is_equal(tick)
	assert_int(sim.state.gold).is_equal(gold)
	assert_int(sim.call_wave()).is_equal(R.OUTCOME_REACHED)
	assert_int(sim.award_wave_bonus(1)).is_equal(0)
	assert_int(sim.state.gold).is_equal(gold)


# --- start_wave guard, no director -------------------------------------------------

func test_start_wave_outside_build_is_a_no_op() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 1)
	run(sim, SimTime.ticks(1))
	sim.drain_events()
	director.start_wave(sim, false)
	director.start_wave(sim, true)
	assert_int(sim.state.wave_index).is_equal(1)
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	assert_array(sim.drain_events()).is_empty()


func test_scripted_spawner_sims_keep_phase_none() -> void:
	var sim := tsim()
	sim.set_spawner(ScriptedSpawner.new([[3, "cultist"]]))
	run(sim, 10)
	assert_int(sim.state.phase).is_equal(SimState.Phase.NONE)
	assert_int(sim.state.wave_index).is_equal(0)
	assert_int(sim.state.build_ticks_left).is_equal(0)
