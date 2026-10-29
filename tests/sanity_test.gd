class_name SanityTest
extends WaveTestBase
## LT-10 sanity pool (GDD §5.3, §5.4): horror drain, mundane-kill and between-waves regen,
## clamping, threshold states and their events. Sanity values are compared approximately.

const T := SimEvent.Type
const S := SimState.SanityState
const FAR_CELLS := 0.0  ## path cell 0: 7+ cells from the default tower, outside any radius


func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	sim.drain_events()


func _tick_drain(sim: Simulation, id: String) -> float:
	return sim.config.enemies[id].horror_drain * SimTime.DT


func _changes(events: Array[SimEvent]) -> Array[SimEvent]:
	return of_type(events, T.SANITY_CHANGED)


func _state_changes(events: Array[SimEvent]) -> Array[SimEvent]:
	return of_type(events, T.SANITY_STATE_CHANGED)


func _radius_sim(radius: float, enemy_edits := {}) -> Simulation:
	var r := load_edited(func(dir: String) -> void:
		edit(dir, MAP, func(root: Dictionary) -> void:
			root["width"] = ROWS[0].length()
			root["height"] = ROWS.size()
			root["rows"] = ROWS)
		edit(dir, "sanity.json", func(root: Dictionary) -> void:
			root["horror_radius_cells"] = radius)
		for id: String in enemy_edits:
			var fields: Dictionary = enemy_edits[id]
			edit(dir, ENEMIES, func(root: Dictionary) -> void:
				for k: String in fields:
					root["enemies"][id][k] = fields[k]))
	assert_bool(r.ok).override_failure_message("config rejected:\n%s" % "\n".join(r.errors)) \
		.is_true()
	return Simulation.new(r.config, SEED)


# --- initial state -----------------------------------------------------------

func test_initial_sanity_is_the_configured_start_with_derived_state_and_no_event() -> void:
	var sim := tsim()
	var c := sim.config.sanity
	assert_float(sim.state.sanity).is_equal(minf(c.start, c.max_sanity))
	assert_int(sim.state.sanity_state).is_equal(sim.sanity_state_for(sim.state.sanity))
	assert_int(sim.state.sanity_state).is_equal(S.LUCID)
	assert_array(sim.drain_events()).is_empty()


# --- horror drain ------------------------------------------------------------

func test_shoggoth_in_radius_drains_horror_drain_per_second() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0)
	var h: float = sim.config.enemies["shoggoth"].horror_drain
	var start := sim.state.sanity
	sim.drain_events()
	run(sim, SimTime.TICK_RATE)
	assert_bool(is_equal_approx(sim.state.sanity, start - h)) \
		.override_failure_message("sanity %f, expected %f" % [sim.state.sanity, start - h]).is_true()


func test_horror_is_one_event_per_tick_with_reason_horror() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0)
	sim.drain_events()
	var events := run(sim, 3)
	var ev := _changes(events)
	assert_int(ev.size()).is_equal(3)
	for e in ev:
		assert_str(e.data["reason"]).is_equal("horror")
		assert_bool(is_equal_approx(e.data["delta"], -_tick_drain(sim, "shoggoth"))).is_true()
	assert_bool(is_equal_approx(ev[2].data["sanity"], sim.state.sanity)).is_true()


func test_enemy_exactly_at_the_radius_drains() -> void:
	# Tower centre (7.5, 1.5), path cell 7 centre (7.5, 0.5): distance exactly 1.
	var sim := _radius_sim(1.0)
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0)
	sim.drain_events()
	run(sim, 1)
	assert_float(sim.state.sanity).is_less(sim.config.sanity.start)


func test_enemy_just_outside_the_radius_does_not_drain() -> void:
	var sim := _radius_sim(1.0)
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.5)  # distance sqrt(1.25) > 1
	sim.drain_events()
	var events := run(sim, 5)
	assert_float(sim.state.sanity).is_equal(sim.config.sanity.start)
	assert_array(_changes(events)).is_empty()


func test_shoggoth_far_from_every_tower_does_not_drain() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "shoggoth", FAR_CELLS)
	sim.drain_events()
	var events := run(sim, 5)
	assert_float(sim.state.sanity).is_equal(sim.config.sanity.start)
	assert_array(_changes(events)).is_empty()


func test_no_tower_means_no_drain() -> void:
	var sim := tsim()
	put(sim, "shoggoth", 7.0)
	sim.drain_events()
	var events := run(sim, 5)
	assert_float(sim.state.sanity).is_equal(sim.config.sanity.start)
	assert_array(_changes(events)).is_empty()


func test_enemy_without_horror_drain_does_not_drain() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	assert_float(sim.config.enemies["cultist"].horror_drain).is_equal(0.0)
	put(sim, "cultist", 7.0)
	sim.drain_events()
	var events := run(sim, 5)
	assert_float(sim.state.sanity).is_equal(sim.config.sanity.start)
	assert_array(_changes(events)).is_empty()


func test_fake_shoggoth_does_not_drain() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0, HUGE_HP, true)
	sim.drain_events()
	var events := run(sim, 5)
	assert_float(sim.state.sanity).is_equal(sim.config.sanity.start)
	assert_array(_changes(events)).is_empty()


func test_flying_horror_enemy_drains() -> void:
	var sim := tsim({"shoggoth": {"flying": true}})
	assert_bool(sim.config.enemies["shoggoth"].flying).is_true()
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0)
	sim.drain_events()
	run(sim, 1)
	var h := _tick_drain(sim, "shoggoth")
	assert_bool(is_equal_approx(sim.state.sanity, sim.config.sanity.start - h)).is_true()


func test_one_shoggoth_near_several_towers_drains_once() -> void:
	var sim := tsim()
	build(sim, "rifleman", TOWER)
	build(sim, "harpooner", TOWER + Vector2i.RIGHT)
	build(sim, "rifleman", TOWER + Vector2i.RIGHT * 2)
	put(sim, "shoggoth", 7.0)
	sim.drain_events()
	var events := run(sim, 1)
	var ev := _changes(events)
	assert_int(ev.size()).is_equal(1)
	assert_bool(is_equal_approx(ev[0].data["delta"], -_tick_drain(sim, "shoggoth"))).is_true()


func test_two_shoggoths_sum_into_one_event_per_tick() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0)
	put(sim, "shoggoth", 8.0)
	sim.drain_events()
	var events := run(sim, 2)
	var ev := _changes(events)
	assert_int(ev.size()).is_equal(2)
	for e in ev:
		assert_bool(is_equal_approx(e.data["delta"], -2.0 * _tick_drain(sim, "shoggoth"))) \
			.is_true()


func test_only_the_shoggoth_in_radius_counts_when_another_is_far() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0)
	put(sim, "shoggoth", FAR_CELLS)
	sim.drain_events()
	var ev := _changes(run(sim, 1))
	assert_int(ev.size()).is_equal(1)
	assert_bool(is_equal_approx(ev[0].data["delta"], -_tick_drain(sim, "shoggoth"))).is_true()


# --- floor and cap -----------------------------------------------------------

func test_drain_clamps_at_zero_and_reports_the_applied_delta() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0)
	var tiny := _tick_drain(sim, "shoggoth") / 4.0
	_set_sanity(sim, tiny)
	var events := run(sim, 1)
	assert_float(sim.state.sanity).is_equal(0.0)
	var ev := _changes(events)
	assert_int(ev.size()).is_equal(1)
	assert_bool(is_equal_approx(ev[0].data["delta"], -tiny)).is_true()
	assert_float(ev[0].data["sanity"]).is_equal(0.0)


func test_no_event_and_sanity_stays_zero_when_draining_at_zero() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0)
	_set_sanity(sim, 0.0)
	var events := run(sim, 5)
	assert_float(sim.state.sanity).is_equal(0.0)
	assert_array(_changes(events)).is_empty()
	assert_array(_state_changes(events)).is_empty()


func test_regen_at_the_cap_changes_nothing_and_emits_nothing() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var e := put(sim, "cultist", 8.0)
	var max_s: float = sim.config.sanity.max_sanity
	_set_sanity(sim, max_s)
	sim.apply_damage(e.id, 1.0e9, "rifleman")
	var events := sim.drain_events()
	assert_float(sim.state.sanity).is_equal(max_s)
	assert_array(_changes(events)).is_empty()
	assert_array(_state_changes(events)).is_empty()


func test_partial_regen_is_clamped_at_max_and_reports_the_clamped_delta() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var e := put(sim, "cultist", 8.0)
	var max_s: float = sim.config.sanity.max_sanity
	var regen: float = sim.config.sanity.regen_mundane_kill
	_set_sanity(sim, max_s - regen / 4.0)
	sim.apply_damage(e.id, 1.0e9, "rifleman")
	var ev := _changes(sim.drain_events())
	assert_int(ev.size()).is_equal(1)
	assert_float(sim.state.sanity).is_equal(max_s)
	assert_bool(is_equal_approx(ev[0].data["delta"], regen / 4.0)).is_true()


# --- mundane-kill regen ------------------------------------------------------

func test_mundane_tower_kill_restores_regen_with_enemy_id_and_reason() -> void:
	for tower_id: String in ["rifleman", "harpooner"]:
		var sim := tsim()
		build(sim, tower_id)
		var e := put(sim, "cultist", 8.0)
		_set_sanity(sim, 50.0)
		sim.apply_damage(e.id, 1.0e9, tower_id)
		var ev := _changes(sim.drain_events())
		var regen: float = sim.config.sanity.regen_mundane_kill
		assert_int(ev.size()).is_equal(1)
		assert_int(ev[0].id).is_equal(e.id)
		assert_str(ev[0].data["reason"]).is_equal("mundane_kill")
		assert_bool(is_equal_approx(ev[0].data["delta"], regen)).is_true()
		assert_bool(is_equal_approx(sim.state.sanity, 50.0 + regen)).is_true()


func test_a_real_tower_shot_kill_restores_sanity() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "cultist", 8.0, 1.0)
	_set_sanity(sim, 50.0)
	var events := run(sim, 1)
	assert_array(of_type(events, T.DIED)).has_size(1)
	var ev := _changes(events)
	assert_int(ev.size()).is_equal(1)
	assert_str(ev[0].data["reason"]).is_equal("mundane_kill")
	assert_bool(is_equal_approx(sim.state.sanity, 50.0 + sim.config.sanity.regen_mundane_kill)) \
		.is_true()


func test_two_kills_in_one_tick_give_two_events() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var a := put(sim, "cultist", 8.0)
	var b := put(sim, "cultist", 9.0)
	_set_sanity(sim, 50.0)
	sim.apply_damage(a.id, 1.0e9, "rifleman")
	sim.apply_damage(b.id, 1.0e9, "harpooner")
	var ev := _changes(sim.drain_events())
	assert_int(ev.size()).is_equal(2)
	assert_bool(is_equal_approx(sim.state.sanity, 50.0 + 2.0 * sim.config.sanity.regen_mundane_kill)) \
		.is_true()


func test_a_killed_enemy_pays_regen_only_once() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var e := put(sim, "cultist", 8.0)
	_set_sanity(sim, 50.0)
	sim.apply_damage(e.id, 1.0e9, "rifleman")
	sim.apply_damage(e.id, 1.0e9, "harpooner")
	assert_array(_changes(sim.drain_events())).has_size(1)


func test_occult_tower_kill_gives_no_regen() -> void:
	var sim := tsim()
	var e := put(sim, "cultist", 8.0)
	_set_sanity(sim, 50.0)
	for occult: String in ["elder_sign", "necronomicon_reader"]:
		assert_str(sim.config.towers[occult].kind).is_equal("occult")
	sim.apply_damage(e.id, 1.0e9, "elder_sign")
	assert_array(_changes(sim.drain_events())).is_empty()
	assert_float(sim.state.sanity).is_equal(50.0)


func test_kill_without_a_tower_source_gives_no_regen() -> void:
	var sim := tsim()
	var e := put(sim, "cultist", 8.0)
	_set_sanity(sim, 50.0)
	sim.apply_damage(e.id, 1.0e9, "test")
	assert_array(_changes(sim.drain_events())).is_empty()
	assert_float(sim.state.sanity).is_equal(50.0)


func test_fake_kill_by_a_mundane_tower_gives_no_regen() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var e := put(sim, "cultist", 8.0, HUGE_HP, true)
	_set_sanity(sim, 50.0)
	sim.apply_damage(e.id, 1.0e9, "rifleman")
	assert_array(_changes(sim.drain_events())).is_empty()
	assert_float(sim.state.sanity).is_equal(50.0)


# --- thresholds --------------------------------------------------------------

func test_state_for_exact_boundaries() -> void:
	var sim := tsim()
	var th := sim.config.sanity.thresholds
	var lucid: float = th["lucid"].min_sanity
	var whispers: float = th["whispers"].min_sanity
	var max_s: float = sim.config.sanity.max_sanity
	assert_int(sim.sanity_state_for(max_s)).is_equal(S.LUCID)
	assert_int(sim.sanity_state_for(lucid)).is_equal(S.LUCID)
	assert_int(sim.sanity_state_for(lucid - 0.001)).is_equal(S.WHISPERS)
	assert_int(sim.sanity_state_for(whispers)).is_equal(S.WHISPERS)
	assert_int(sim.sanity_state_for(whispers - 0.001)).is_equal(S.FRAYING)
	assert_int(sim.sanity_state_for(1.0)).is_equal(S.FRAYING)
	assert_int(sim.sanity_state_for(0.5)).is_equal(S.FRAYING)
	assert_int(sim.sanity_state_for(0.0001)).is_equal(S.FRAYING)
	assert_int(sim.sanity_state_for(0.0)).is_equal(S.MADNESS)


func test_lucid_to_whispers_at_just_below_70_emits_state_change() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0)
	var lucid: float = sim.config.sanity.thresholds["lucid"].min_sanity
	_set_sanity(sim, lucid)
	assert_int(sim.state.sanity_state).is_equal(S.LUCID)
	var events := run(sim, 1)
	assert_int(sim.state.sanity_state).is_equal(S.WHISPERS)
	var sc := _state_changes(events)
	assert_int(sc.size()).is_equal(1)
	assert_dict(sc[0].data).is_equal({"old": S.LUCID, "new": S.WHISPERS})
	# the state event follows the sanity event of the same change
	assert_int(events.find(sc[0])).is_equal(events.find(_changes(events)[0]) + 1)


func test_whispers_to_fraying_just_below_40() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0)
	_set_sanity(sim, sim.config.sanity.thresholds["whispers"].min_sanity)
	assert_int(sim.state.sanity_state).is_equal(S.WHISPERS)
	var sc := _state_changes(run(sim, 1))
	assert_int(sim.state.sanity_state).is_equal(S.FRAYING)
	assert_int(sc.size()).is_equal(1)
	assert_dict(sc[0].data).is_equal({"old": S.WHISPERS, "new": S.FRAYING})


func test_fraying_to_madness_only_when_sanity_reaches_zero() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0)
	var h := _tick_drain(sim, "shoggoth")
	_set_sanity(sim, h * 3.5)
	var seen_madness_early := false
	var sc: Array[SimEvent] = []
	for i in 10:
		var events := run(sim, 1)
		sc.append_array(_state_changes(events))
		if sim.state.sanity > 0.0 and sim.state.sanity_state == S.MADNESS:
			seen_madness_early = true
	assert_bool(seen_madness_early).is_false()
	assert_float(sim.state.sanity).is_equal(0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	assert_int(sc.size()).is_equal(1)
	assert_dict(sc[0].data).is_equal({"old": S.FRAYING, "new": S.MADNESS})


func test_half_a_point_of_sanity_is_fraying_not_madness() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var e := put(sim, "cultist", 8.0)
	_set_sanity(sim, 0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	sim.apply_damage(e.id, 1.0e9, "rifleman")
	var regen: float = sim.config.sanity.regen_mundane_kill
	assert_bool(is_equal_approx(sim.state.sanity, regen)).is_true()
	assert_int(sim.state.sanity_state).is_equal(sim.sanity_state_for(regen))
	assert_int(sim.state.sanity_state).is_equal(S.FRAYING)


func test_regen_out_of_madness_emits_the_reverse_transition() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var e := put(sim, "cultist", 8.0)
	_set_sanity(sim, 0.0)
	sim.apply_damage(e.id, 1.0e9, "rifleman")
	var sc := _state_changes(sim.drain_events())
	assert_int(sc.size()).is_equal(1)
	assert_dict(sc[0].data).is_equal({"old": S.MADNESS, "new": S.FRAYING})


func test_regen_upward_across_70_and_40_emits_transitions() -> void:
	var th := tsim().config.sanity.thresholds
	var regen: float = tsim().config.sanity.regen_mundane_kill
	var cases := [
		[th["lucid"].min_sanity, S.WHISPERS, S.LUCID],
		[th["whispers"].min_sanity, S.FRAYING, S.WHISPERS],
	]
	for c: Array in cases:
		var sim := tsim()
		build(sim, "rifleman")
		var e := put(sim, "cultist", 8.0)
		_set_sanity(sim, c[0] - regen)  # lands exactly on the boundary
		assert_int(sim.state.sanity_state).is_equal(c[1])
		sim.apply_damage(e.id, 1.0e9, "rifleman")
		var sc := _state_changes(sim.drain_events())
		assert_int(sim.state.sanity_state).is_equal(c[2])
		assert_int(sc.size()).is_equal(1)
		assert_dict(sc[0].data).is_equal({"old": c[1], "new": c[2]})


func test_no_state_event_when_the_change_stays_within_a_state() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0)
	var events := run(sim, 10)
	assert_array(_changes(events)).is_not_empty()
	assert_array(_state_changes(events)).is_empty()
	assert_int(sim.state.sanity_state).is_equal(S.LUCID)


# --- between-waves regen -----------------------------------------------------

## Steps (killing the real enemies between steps) until `n` WAVE_CLEARED events were seen;
## returns every event, with the last cleared tick's events being the tail.
func _until_cleared(sim: Simulation, n: int) -> Array[SimEvent]:
	var all: Array[SimEvent] = []
	var seen := 0
	for i in 2000:
		sim.step()
		var ev := sim.drain_events()
		all.append_array(ev)
		seen += of_type(ev, T.WAVE_CLEARED).size()
		if seen >= n or sim.state.outcome != SimState.Outcome.NONE:
			break
		kill_real(sim)
	return all


func test_clearing_a_wave_restores_between_waves_sanity_after_the_gold_bonus() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]])
	_set_sanity(sim, 50.0)
	var regen: float = sim.config.sanity.regen_between_waves
	var events := _until_cleared(sim, 1)
	var ev := _changes(events)
	assert_int(ev.size()).is_equal(1)
	assert_str(ev[0].data["reason"]).is_equal("between_waves")
	assert_bool(is_equal_approx(ev[0].data["delta"], regen)).is_true()
	assert_bool(is_equal_approx(sim.state.sanity, 50.0 + regen)).is_true()
	var bonus_i := -1
	for i in events.size():
		if events[i].type == T.GOLD_CHANGED and events[i].data["reason"] != "kill":
			bonus_i = i
	assert_int(bonus_i).is_greater_equal(0)
	assert_int(events.find(ev[0])).is_equal(bonus_i + 1)
	assert_int(events.find(of_type(events, T.WAVE_CLEARED)[0])).is_equal(bonus_i + 2)


func test_every_cleared_wave_pays_once() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)], [group("cultist", 1)]])
	_set_sanity(sim, 10.0)
	var regen: float = sim.config.sanity.regen_between_waves
	_until_cleared(sim, 2)
	assert_bool(is_equal_approx(sim.state.sanity, 10.0 + 2.0 * regen)).is_true()


func test_the_last_wave_also_pays_in_the_tick_the_game_is_won() -> void:
	var sim := wsim([[group("cultist", 1)]])
	_set_sanity(sim, 50.0)
	var regen: float = sim.config.sanity.regen_between_waves
	var events := _until_cleared(sim, 1)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.WON)
	var ev := _changes(events)
	assert_int(ev.size()).is_equal(1)
	assert_str(ev[0].data["reason"]).is_equal("between_waves")
	assert_int(ev[0].tick).is_equal(of_type(events, T.OUTCOME)[0].tick)
	assert_bool(is_equal_approx(sim.state.sanity, 50.0 + regen)).is_true()


func test_between_waves_regen_is_clamped_at_max() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]])
	var max_s: float = sim.config.sanity.max_sanity
	var regen: float = sim.config.sanity.regen_between_waves
	_set_sanity(sim, max_s - regen / 3.0)
	var ev := _changes(_until_cleared(sim, 1))
	assert_float(sim.state.sanity).is_equal(max_s)
	assert_int(ev.size()).is_equal(1)
	assert_bool(is_equal_approx(ev[0].data["delta"], regen / 3.0)).is_true()


func test_between_waves_regen_at_max_emits_nothing() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]])
	var max_s: float = sim.config.sanity.max_sanity
	_set_sanity(sim, max_s)
	assert_array(_changes(_until_cleared(sim, 1))).is_empty()
	assert_float(sim.state.sanity).is_equal(max_s)


func test_between_waves_regen_can_lift_out_of_a_state() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]])
	var lucid: float = sim.config.sanity.thresholds["lucid"].min_sanity
	_set_sanity(sim, lucid - 1.0)
	assert_int(sim.state.sanity_state).is_equal(S.WHISPERS)
	var sc := _state_changes(_until_cleared(sim, 1))
	assert_int(sc.size()).is_equal(1)
	assert_dict(sc[0].data).is_equal({"old": S.WHISPERS, "new": S.LUCID})


# --- frozen after the outcome ------------------------------------------------

func test_award_wave_sanity_pays_nothing_after_the_outcome() -> void:
	for outcome: SimState.Outcome in [SimState.Outcome.WON, SimState.Outcome.LOST]:
		var sim := tsim()
		_set_sanity(sim, 50.0)
		sim.state.outcome = outcome
		assert_float(sim.award_wave_sanity()).is_equal(0.0)
		assert_float(sim.state.sanity).is_equal(50.0)
		assert_array(sim.drain_events()).is_empty()


func test_sanity_does_not_move_after_the_outcome() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "shoggoth", 7.0)
	_set_sanity(sim, 50.0)
	sim.state.outcome = SimState.Outcome.LOST
	var events := run(sim, 10)
	assert_float(sim.state.sanity).is_equal(50.0)
	assert_array(events).is_empty()


func test_a_wave_won_freezes_sanity_afterwards() -> void:
	var sim := wsim([[group("cultist", 1)]])
	_until_cleared(sim, 1)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.WON)
	var s := sim.state.sanity
	run(sim, 30)
	assert_float(sim.state.sanity).is_equal(s)
	assert_float(sim.award_wave_sanity()).is_equal(0.0)
	assert_float(sim.state.sanity).is_equal(s)
