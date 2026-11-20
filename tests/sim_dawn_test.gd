class_name SimDawnTest
extends WaveTestBase
## LT-99 dawn phase hook (LT-96 §4 S3, owner D10): Simulation.on_dawn(n) runs the dawn actions
## in one fixed order (fakes dissolve, tokens settle, wage, between-waves sanity, auto restore)
## and returns the wage; the wave director calls it once per cleared wave, then emits
## WAVE_CLEARED with that wage and resets the night luck.

const T := SimEvent.Type


## Records every on_dawn call (its wave number, the night luck it saw, what it returned).
class SpySim:
	extends Simulation

	var dawns: Array[int] = []
	var luck_seen: Array[float] = []
	var returned: Array[int] = []

	func _init(p_config: GameConfig, run_seed: int) -> void:
		super(p_config, run_seed)

	func on_dawn(n: int) -> int:
		dawns.append(n)
		luck_seen.append(state.night_luck)
		var bonus := super.on_dawn(n)
		returned.append(bonus)
		return bonus


func _spy(waves: Array) -> SpySim:
	var sim := SpySim.new(wconfig(waves), SEED)
	director = WaveDirector.new(sim.config.waves)
	sim.set_spawner(director)
	return sim


func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)


## The dawn-relevant events of `events`, as "TYPE:reason" strings in emit order.
func _dawn_trace(events: Array[SimEvent]) -> Array[String]:
	var out: Array[String] = []
	for e in events:
		match e.type:
			T.FAKE_DISSOLVED:
				out.append("fake_dissolved:%s" % e.data["reason"])
			T.RELICS_CHANGED, T.RELIC_VANISHED:
				out.append("%s:%s" % [T.keys()[e.type], e.data.get("reason", "")])
			T.GOLD_CHANGED, T.SANITY_CHANGED:
				out.append("%s:%s" % [T.keys()[e.type], e.data["reason"]])
			T.WAVE_CLEARED, T.BUILD_STARTED, T.OUTCOME:
				out.append(T.keys()[e.type])
	return out


# --- Simulation.on_dawn ----------------------------------------------------------------

## A fake alive, a real token in flight and sanity below the cap: the clearing tick shows the
## five actions in on_dawn order, then WAVE_CLEARED, then the next build.
func test_dawn_actions_run_in_order_before_wave_cleared() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]])
	run(sim, SimTime.ticks(1))
	sim.spawn_enemy("hybrid", true)
	kill_real(sim)  # drops a real token, in flight for token_fly_seconds
	assert_int(sim.state.relic_tokens.size()).is_equal(1)
	_set_sanity(sim, 50.0)
	assert_float(sim.config.sanity.regen_between_waves).is_greater(0.0)
	sim.drain_events()
	var trace := _dawn_trace(run(sim, 1))
	assert_array(trace).is_equal([
		"fake_dissolved:wave_end",
		"RELICS_CHANGED:kill",
		"GOLD_CHANGED:wave_bonus",
		"SANITY_CHANGED:between_waves",
		"WAVE_CLEARED",
		"BUILD_STARTED",
	])
	assert_array(sim.state.relic_tokens).is_empty()
	assert_int(sim.state.enemies.size()).is_equal(0)


## In madness under auto_restore the between-waves regen applies nothing and the restore
## comes last, so sanity is exactly the restore target (a regen after it would add on top).
func test_on_dawn_restores_last_so_no_regen_lands_on_top() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]])
	sim.config.sanity.madness.exit_rule = "auto_restore"
	_set_sanity(sim, 0.0)
	sim.drain_events()
	var bonus := sim.on_dawn(1)
	var trace := _dawn_trace(sim.drain_events())
	assert_array(trace).is_equal(["GOLD_CHANGED:wave_bonus", "SANITY_CHANGED:auto_restore"])
	assert_int(bonus).is_equal(bonus_for(sim, 1))
	assert_float(sim.state.sanity).is_equal(sim.restore_target())


func test_on_dawn_returns_the_wage_and_zero_after_the_outcome() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]])
	var gold := sim.state.gold
	assert_int(sim.on_dawn(2)).is_equal(bonus_for(sim, 2))
	assert_int(sim.state.gold).is_equal(gold + bonus_for(sim, 2))
	sim.state.outcome = SimState.Outcome.LOST
	assert_int(sim.on_dawn(1)).is_equal(0)
	assert_int(sim.state.gold).is_equal(gold + bonus_for(sim, 2))


# --- WaveDirector delegation -----------------------------------------------------------

## Two waves played out: on_dawn runs once per cleared wave with its 1-based number, and each
## WAVE_CLEARED carries what on_dawn returned.
func test_director_calls_on_dawn_once_per_cleared_wave() -> void:
	var sim := _spy([[group("cultist", 1)], [group("cultist", 1)]])
	var cleared: Array[SimEvent] = []
	for i in 4000:
		sim.step()
		cleared.append_array(of_type(sim.drain_events(), T.WAVE_CLEARED))
		if sim.state.outcome != SimState.Outcome.NONE:
			break
		kill_real(sim)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.WON)
	assert_array(sim.dawns).is_equal([1, 2])
	assert_int(cleared.size()).is_equal(2)
	for k in 2:
		assert_dict(cleared[k].data).is_equal({"wave": k + 1, "bonus": sim.returned[k]})
	assert_array(sim.returned).is_equal([bonus_for(sim, 1), bonus_for(sim, 2)])


## A tick where the wave is not cleared yet never calls on_dawn.
func test_director_does_not_call_on_dawn_while_the_wave_is_open() -> void:
	var sim := _spy([[group("cultist", 1)], [group("cultist", 1)]])
	run(sim, SimTime.ticks(1) + 20)
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	assert_array(sim.dawns).is_empty()


## on_dawn still sees the early night's luck; the director resets it to 1.0 afterwards.
func test_night_luck_is_reset_after_on_dawn() -> void:
	var sim := _spy([[group("cultist", 1)], [group("cultist", 1)]])
	run(sim, SimTime.ticks(1))
	kill_real(sim)
	sim.state.night_luck = 1.5
	sim.drain_events()
	run(sim, 1)
	assert_array(sim.dawns).is_equal([1])
	assert_array(sim.luck_seen).is_equal([1.5])
	assert_float(sim.state.night_luck).is_equal(1.0)
