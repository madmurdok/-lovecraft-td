class_name SandboxSimTest
extends WaveTestBase
## LT-67 sim side of `--sandbox`: GameConfig.sandboxed and Simulation.debug_end_night (ends the
## night now; logged, replayable, no rewards).

const T := SimEvent.Type
const GOLD := 100000


## One night in progress: wave 1 = 3 cultists 1 s apart (+ an optional last-wave flag), the
## night called at once and `ticks` stepped (the first cultist is in after one tick).
func _night(waves := 2, ticks := 2) -> Simulation:
	var spec: Array = []
	for i in waves:
		spec.append([group("cultist", 3, 1.0)])
	var sim := wsim(spec, 10)  # a long day after the cleared night: no next wave in a test's span
	assert_int(sim.call_wave()).is_equal(R.OK)
	run(sim, ticks)
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	return sim


# --- behaviour 2: sandbox start money and oil; the base config is left alone ------------

func test_sandboxed_config_starts_with_the_gold_and_a_full_tank() -> void:
	var cfg := real_config()
	var sb := cfg.sandboxed(GOLD)
	assert_int(sb.economy.starting_gold).is_equal(GOLD)
	assert_int(sb.economy.oil.start).is_equal(cfg.economy.oil.cap)
	assert_int(sb.economy.oil.cap).is_equal(cfg.economy.oil.cap)
	var sim := Simulation.new(sb, 7)
	assert_int(sim.state.gold).is_equal(GOLD)
	assert_int(sim.state.oil).is_equal(cfg.economy.oil.cap)
	assert_int(sim.state.oil).is_greater(0)


func test_sandboxed_leaves_the_base_config_unchanged() -> void:
	var cfg := real_config()
	var gold := cfg.economy.starting_gold
	var oil_start := cfg.economy.oil.start
	var oil_cap := cfg.economy.oil.cap
	var economy := cfg.economy
	var oil := cfg.economy.oil
	var sb := cfg.sandboxed(GOLD)
	assert_int(cfg.economy.starting_gold).is_equal(gold)
	assert_int(cfg.economy.oil.start).is_equal(oil_start)
	assert_int(cfg.economy.oil.cap).is_equal(oil_cap)
	assert_bool(cfg.economy == economy).is_true()
	assert_bool(cfg.economy.oil == oil).is_true()
	assert_bool(sb.economy != economy).is_true()
	assert_bool(sb.economy.oil != oil).is_true()
	assert_int(gold).is_not_equal(GOLD)
	assert_int(oil_start).is_not_equal(oil_cap)  # else the oil check above proves nothing
	# Everything else is the same data.
	assert_bool(sb.towers == cfg.towers).is_true()
	assert_bool(sb.waves == cfg.waves).is_true()
	assert_bool(sb.enemies == cfg.enemies).is_true()


func test_sandboxed_without_an_oil_block_only_sets_the_gold() -> void:
	var base := real_config().sandboxed(1)  # a private copy, safe to edit
	base.economy.oil = null
	var sb := base.sandboxed(GOLD)
	assert_int(sb.economy.starting_gold).is_equal(GOLD)
	assert_object(sb.economy.oil).is_null()
	assert_int(base.economy.starting_gold).is_equal(1)
	assert_int(Simulation.new(sb, 7).state.oil).is_equal(0)


# --- behaviour 1: without the flag the sim is unchanged ---------------------------------

func _script_run(cfg: GameConfig, run_seed: int) -> Array:
	var sim := Simulation.new(cfg, run_seed)
	var director := WaveDirector.new(cfg.waves)
	sim.set_spawner(director)
	var out: Array[String] = []
	for t in 400:
		if t == 5:
			sim.call_wave()
		sim.step()
		out.append_array(strings_of(sim.drain_events()))
	out.append("gold=%d oil=%d hp=%d phase=%d wave=%d next_id=%d log=%s" % [
		sim.state.gold, sim.state.oil, sim.state.lighthouse_hp, sim.state.phase,
		sim.state.wave_index, sim.state.next_id, sim.state.command_log])
	return out


func test_building_a_sandbox_copy_does_not_change_a_run_on_the_base_config() -> void:
	var cfg := real_config()
	for run_seed: int in [3, 42]:
		var before := _script_run(cfg, run_seed)
		cfg.sandboxed(GOLD)
		var after := _script_run(cfg, run_seed)
		assert_array(after).is_equal(before)
		assert_int(before.size()).is_greater(10)
		assert_str(before.back()).contains("gold=%d" % cfg.economy.starting_gold) \
			.override_failure_message("sanity: the run must not have touched the start gold")


func test_a_run_that_never_ends_a_night_logs_no_debug_command() -> void:
	var sim := _night()
	run(sim, 100)
	assert_bool(sim.state.command_log.any(
		func(c: Array) -> bool: return c[1] == "debug_end_night")).is_false()


# --- behaviour 3/4: ending the night ----------------------------------------------------

func test_end_night_is_logged_and_kills_real_enemies_with_the_debug_source() -> void:
	var sim := _night()
	var live: Array[int] = []
	for e in sim.state.enemies:
		live.append(e.id)
	assert_array(live).is_not_empty()
	sim.drain_events()
	var tick := sim.state.tick
	assert_int(sim.debug_end_night()).is_equal(R.OK)
	assert_array(sim.state.command_log.back()).is_equal([tick, "debug_end_night"])
	var ev := sim.drain_events()
	var died := of_type(ev, T.DIED)
	assert_array(ids_of(died)).is_equal(live)
	for d in died:
		assert_str(d.data["source"]).is_equal("debug")
	assert_int(sim.state.enemies.size()).is_equal(0)


func test_end_night_by_night_clears_the_wave_on_the_next_tick_and_pays_the_wage() -> void:
	var sim := _night(2)
	var gold := sim.state.gold
	assert_int(sim.debug_end_night()).is_equal(R.OK)
	assert_int(sim.state.gold).is_equal(gold)  # the kills pay nothing
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)  # cleared by the tick, not here
	sim.drain_events()
	var ev := run(sim, 1)
	var cleared := of_type(ev, T.WAVE_CLEARED)
	assert_int(cleared.size()).is_equal(1)
	assert_int(cleared[0].data["wave"]).is_equal(1)
	assert_int(sim.state.gold).is_equal(gold + bonus_for(sim, 1))
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	assert_array(of_type(ev, T.SPAWNED)).is_empty()


func test_end_night_on_the_last_wave_finishes_the_run() -> void:
	var sim := _night(1)
	assert_int(sim.debug_end_night()).is_equal(R.OK)
	var ev := run(sim, 1)
	assert_int(of_type(ev, T.WAVE_CLEARED).size()).is_equal(1)
	assert_int(sim.state.phase).is_equal(SimState.Phase.DONE)
	assert_int(sim.state.lighthouse_hp).is_greater(0)


func test_end_night_before_the_wave_spawned_anything_cancels_its_whole_schedule() -> void:
	var sim := wsim([[group("cultist", 3, 1.0, 2.0)], [group("cultist", 1)]], 10)
	sim.call_wave()
	assert_int(sim.debug_end_night()).is_equal(R.OK)
	sim.drain_events()
	var ev := run(sim, SimTime.ticks(6))
	assert_array(of_type(ev, T.SPAWNED)).is_empty()
	assert_int(of_type(ev, T.WAVE_CLEARED).size()).is_equal(1)
	assert_int(sim.state.next_id).is_equal(1)


func test_killed_enemies_drop_no_relics_and_leave_the_stash_alone() -> void:
	var sim := _night(2, 4)
	var stash := sim.state.relics.duplicate()
	assert_int(sim.state.enemies.size()).is_greater(0)
	sim.debug_end_night()
	assert_array(sim.state.relic_tokens).is_empty()
	run(sim, 3)
	assert_array(sim.state.relic_tokens).is_empty()
	assert_dict(sim.state.relics).is_equal(stash)


func test_end_night_drops_queued_pack_members_real_and_fake() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 10)
	sim.call_wave()
	run(sim, 1)
	var real_first := sim.spawn_enemy("deep_one")
	var fake_first := sim.spawn_enemy("deep_one", true)
	sim.drain_events()
	assert_bool(sim.has_queued_real_members()).is_true()
	var next_before := sim.state.next_id
	assert_int(sim.debug_end_night()).is_equal(R.OK)
	assert_bool(sim.has_queued_real_members()).is_false()
	var ev := run(sim, 1)
	assert_int(of_type(ev, T.WAVE_CLEARED).size()).is_equal(1)  # a queued real member would hold it
	var after := run(sim, pack_span_ticks(sim.config, "deep_one") + 3)
	assert_array(of_type(after, T.SPAWNED)).is_empty()
	assert_int(sim.state.enemies.size()).is_equal(0)
	assert_int(sim.state.next_id).is_equal(next_before)
	assert_bool(real_first < fake_first).is_true()


# --- behaviour 5: refusals --------------------------------------------------------------

func test_end_night_by_day_is_refused_not_night_and_logs_nothing() -> void:
	var sim := wsim([[group("cultist", 1)]], 5)
	run(sim, 3)
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	var snap := [sim.state.tick, sim.state.phase, sim.state.build_ticks_left, sim.state.gold]
	assert_int(sim.debug_end_night()).is_equal(R.NOT_NIGHT)
	assert_array(sim.state.command_log).is_empty()
	assert_array([sim.state.tick, sim.state.phase, sim.state.build_ticks_left,
		sim.state.gold]).is_equal(snap)


func test_end_night_without_a_wave_director_is_refused_not_night() -> void:
	var sim := Simulation.new(real_config(), 1)
	assert_int(sim.debug_end_night()).is_equal(R.NOT_NIGHT)
	assert_array(sim.state.command_log).is_empty()


## The win lands in the same tick as DONE, so the outcome check comes first: OUTCOME_REACHED.
func test_end_night_in_done_is_refused_outcome_reached() -> void:
	var sim := _night(1)
	sim.debug_end_night()
	run(sim, 1)
	assert_int(sim.state.phase).is_equal(SimState.Phase.DONE)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.WON)
	var n := sim.state.command_log.size()
	assert_int(sim.debug_end_night()).is_equal(R.OUTCOME_REACHED)
	assert_int(sim.state.command_log.size()).is_equal(n)


func test_end_night_after_the_outcome_is_refused_outcome_reached() -> void:
	var sim := _night(2)
	sim.state.outcome = SimState.Outcome.LOST
	var n := sim.state.command_log.size()
	assert_int(sim.debug_end_night()).is_equal(R.OUTCOME_REACHED)
	assert_int(sim.state.command_log.size()).is_equal(n)
	assert_int(sim.state.enemies.size()).is_greater(0)  # nothing was killed


# --- behaviour 6: log and replay --------------------------------------------------------

func _play(commands: Array, ticks: int) -> Array:
	var sim := wsim([[group("deep_one", 2, 0.5), group("cultist", 2, 0.5, 0.3)],
		[group("deep_one", 1)]], 2, -1, SEED)
	var out: Array[String] = []
	for t in ticks:
		for c: Array in commands:
			if int(c[0]) == sim.state.tick:
				sim.replay_command(c)
		sim.step()
		out.append_array(strings_of(sim.drain_events()))
	out.append("tick=%d gold=%d hp=%d phase=%d wave=%d next_id=%d left=%d enemies=%d" % [
		sim.state.tick, sim.state.gold, sim.state.lighthouse_hp, sim.state.phase,
		sim.state.wave_index, sim.state.next_id, sim.state.build_ticks_left,
		sim.state.enemies.size()])
	return [out, sim.state.command_log]


func test_replaying_the_log_reproduces_a_run_that_ended_a_night() -> void:
	var first := _play([[5, "call_wave"], [40, "debug_end_night"]], 400)
	assert_array(first[1]).is_equal([[5, "call_wave"], [40, "debug_end_night"]])
	var replay := _play(first[1], 400)
	assert_array(replay[0]).is_equal(first[0])
	assert_array(replay[1]).is_equal(first[1])
	# The end-night had an effect: the run differs from one that only called the wave.
	var without := _play([[5, "call_wave"]], 400)
	assert_bool(without[0] == first[0]).is_false()
	assert_str(" ".join(first[0])).contains("debug")
