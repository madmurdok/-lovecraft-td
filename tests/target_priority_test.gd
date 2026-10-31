class_name TargetPriorityTest
extends WaveTestBase
## LT-31 tower target priority (docs/design/LT-31-target-priority.md): the modes "first" /
## "strongest" / "fastest" and their lower-id tie, the Elder Sign slow counted by "fastest",
## fakes as targets, the harpoon line and the Reader blast around the picked target, and
## the set_target_priority command (refusal order, nothing changed on refusal, any phase,
## log + event, upgrade keeps the mode, a sold id is gone). Madness astray and the replay
## are pinned in madness_test / upgrade_test, the panel in side_panel_test.
## Geometry: TOWER (7, 1) has its centre at (7.5, 1.5); a parked enemy `cells` along the
## route stands at (cells + 0.5, 0.5), so a range-3 tower reaches cells 4.17..9.83.

const T := SimEvent.Type
const RIFLE := "rifleman"
const HARP := "harpooner"
const SIGN := "elder_sign"
const NECRO := "necronomicon_reader"
const SIGN_CELL := Vector2i(3, 1)  ## aura radius 2 around (3.5, 1.5) covers cells 1.27..4.73


# --- helpers ---------------------------------------------------------------------------

func _rich(sim: Simulation) -> Simulation:
	sim.state.gold = 100000
	return sim


## Clears `t`'s cooldown, steps once and returns the target id of `t`'s SHOT (-1 if none).
func _shot_target(sim: Simulation, t: SimTower) -> int:
	var s := _shot(sim, t)
	return -1 if s == null else int(s.data["target"])


func _shot(sim: Simulation, t: SimTower) -> SimEvent:
	t.cooldown_ticks = 0
	sim.drain_events()
	sim.step()
	for e in of_type(sim.drain_events(), T.SHOT):
		if e.id == t.id:
			return e
	return null


func _mode(sim: Simulation, t: SimTower, mode: String) -> void:
	assert_int(sim.set_target_priority(t.id, mode)).is_equal(R.OK)
	sim.drain_events()


func _modes(sim: Simulation) -> Array:
	var out := []
	for t in sim.state.towers:
		out.append(t.target_priority)
	return out


## Asserts can_/set_target_priority both give `want` and that the refusal changed nothing:
## no command_log entry, no event, gold/sanity and every tower's mode unchanged.
func _assert_refused(sim: Simulation, id: int, mode: String, want: R) -> void:
	sim.drain_events()
	var log_size := sim.state.command_log.size()
	var modes := _modes(sim)
	var gold := sim.state.gold
	var sanity := sim.state.sanity
	assert_int(sim.can_set_target_priority(id, mode)) \
		.override_failure_message("can(%d, '%s')" % [id, mode]).is_equal(want)
	assert_int(sim.set_target_priority(id, mode)) \
		.override_failure_message("set(%d, '%s')" % [id, mode]).is_equal(want)
	assert_int(sim.state.command_log.size()).is_equal(log_size)
	assert_array(sim.drain_events()).is_empty()
	assert_array(_modes(sim)).is_equal(modes)
	assert_int(sim.state.gold).is_equal(gold)
	assert_float(sim.state.sanity).is_equal(sanity)


## Asserts an OK set_target_priority: the mode is set, the log gets
## [tick, "set_target_priority", id, mode], exactly one TARGET_PRIORITY_SET event (no gold
## or sanity event), gold, sanity and the cooldown unchanged.
func _assert_applied(sim: Simulation, t: SimTower, mode: String) -> void:
	sim.drain_events()
	var log_size := sim.state.command_log.size()
	var gold := sim.state.gold
	var sanity := sim.state.sanity
	var cd := t.cooldown_ticks
	assert_int(sim.can_set_target_priority(t.id, mode)).is_equal(R.OK)
	assert_int(sim.set_target_priority(t.id, mode)).is_equal(R.OK)
	assert_str(t.target_priority).is_equal(mode)
	assert_int(sim.state.command_log.size()).is_equal(log_size + 1)
	assert_array(sim.state.command_log[log_size]) \
		.is_equal([sim.state.tick, "set_target_priority", t.id, mode])
	var ev := sim.drain_events()
	assert_int(ev.size()).is_equal(1)
	assert_int(ev[0].type).is_equal(T.TARGET_PRIORITY_SET)
	assert_int(ev[0].id).is_equal(t.id)
	assert_dict(ev[0].data).is_equal({"def": t.def.id, "cell": t.cell, "mode": mode})
	assert_int(sim.state.gold).is_equal(gold)
	assert_float(sim.state.sanity).is_equal(sanity)
	assert_int(t.cooldown_ticks).is_equal(cd)


# --- 1: default "first" ----------------------------------------------------------------

func test_modes_in_panel_order_and_a_new_tower_starts_on_first() -> void:
	assert_array(Array(SimTower.TARGET_PRIORITIES)).is_equal(["first", "strongest", "fastest"])
	var sim := tsim()
	var t := build(sim, RIFLE)
	assert_str(t.target_priority).is_equal("first")


func test_first_shoots_the_enemy_nearest_the_lighthouse_and_switching_back_restores_it() -> void:
	var sim := tsim()
	var t := build(sim, RIFLE)
	var strong := put(sim, "cultist", 6.0, 5000.0)
	var front := put(sim, "cultist", 8.0, 50.0)
	assert_int(_shot_target(sim, t)).is_equal(front.id)
	_mode(sim, t, "strongest")
	assert_int(_shot_target(sim, t)).is_equal(strong.id)
	_mode(sim, t, "first")
	assert_int(_shot_target(sim, t)).is_equal(front.id)


# --- 2: strongest = current hp ---------------------------------------------------------

func test_strongest_shoots_the_highest_current_hp_also_behind_another() -> void:
	var sim := tsim()
	var t := build(sim, RIFLE)
	var front := put(sim, "cultist", 8.0, 100.0)
	var behind := put(sim, "cultist", 5.0, 900.0)
	put(sim, "cultist", 12.0, HUGE_HP)  # out of range: never a candidate
	_mode(sim, t, "strongest")
	assert_int(_shot_target(sim, t)).is_equal(behind.id)
	assert_float(behind.hp).is_less(900.0)
	assert_float(front.hp).is_equal(100.0)


func test_strongest_uses_current_hp_so_a_damaged_front_enemy_loses_to_a_full_one() -> void:
	var sim := tsim()
	var t := build(sim, RIFLE)
	var front := put(sim, "cultist", 8.0, 100.0)
	front.hp = 50.0  # max_hp 100 > behind's 60, current hp 50 < 60
	var behind := put(sim, "cultist", 6.0, 60.0)
	_mode(sim, t, "strongest")
	assert_int(_shot_target(sim, t)).is_equal(behind.id)


# --- 3: fastest = units this tick, Elder Sign slow counted -----------------------------

func test_fastest_shoots_the_highest_speed_also_behind_another() -> void:
	var sim := tsim()
	var t := build(sim, RIFLE)
	var front := put(sim, "cultist", 8.0)
	front.base_units_per_tick = 3
	var behind := put(sim, "cultist", 5.0)
	behind.base_units_per_tick = 9
	_mode(sim, t, "fastest")
	assert_int(_shot_target(sim, t)).is_equal(behind.id)


## a: 10 units/tick inside the Sign's aura (slow 0.3 -> roundi(7.0) = 7); b: 8, outside it.
func _fastest_with_sign(with_sign: bool) -> Array:
	var sim := _rich(tsim())
	if with_sign:
		build(sim, SIGN, SIGN_CELL)
	var t := build(sim, RIFLE)
	var a := put(sim, "cultist", 4.4)
	a.base_units_per_tick = 10
	var b := put(sim, "cultist", 8.0)
	b.base_units_per_tick = 8
	_mode(sim, t, "fastest")
	return [_shot_target(sim, t), a, b]


func test_fastest_counts_the_elder_sign_slow_of_this_tick() -> void:
	var slowed := _fastest_with_sign(true)
	var a: SimEnemy = slowed[1]
	assert_float(a.speed_mult).is_equal_approx(1.0 - 0.3, 1e-6)
	assert_int(slowed[0]).is_equal((slowed[2] as SimEnemy).id)
	# Without the Sign the faster-def enemy a wins: the slow is what flipped the pick.
	var plain := _fastest_with_sign(false)
	assert_int(plain[0]).is_equal((plain[1] as SimEnemy).id)


# --- 4: ties -> lower id ---------------------------------------------------------------

func test_a_strongest_tie_goes_to_the_lower_id_not_the_one_further_along() -> void:
	var sim := tsim()
	var t := build(sim, RIFLE)
	var low := put(sim, "cultist", 5.0, 300.0)
	put(sim, "cultist", 9.0, 300.0)
	_mode(sim, t, "strongest")
	assert_int(_shot_target(sim, t)).is_equal(low.id)


func test_a_fastest_tie_goes_to_the_lower_id_not_the_one_further_along() -> void:
	var sim := tsim()
	var t := build(sim, RIFLE)
	var low := put(sim, "cultist", 5.0)
	low.base_units_per_tick = 4
	var high := put(sim, "cultist", 9.0)
	high.base_units_per_tick = 4
	_mode(sim, t, "fastest")
	assert_int(_shot_target(sim, t)).is_equal(low.id)


# --- 5: fakes are targets --------------------------------------------------------------

func test_every_mode_picks_a_fake_like_a_real_enemy() -> void:
	var sim := tsim()
	var t := build(sim, RIFLE)
	var real := put(sim, "cultist", 5.0, 100.0)
	real.base_units_per_tick = 2
	var fake := put(sim, "cultist", 8.0, 500.0, true)
	fake.base_units_per_tick = 6
	assert_bool(fake.is_fake).is_true()
	for mode: String in ["first", "strongest", "fastest"]:
		_mode(sim, t, mode)
		assert_int(_shot_target(sim, t)).override_failure_message(mode).is_equal(fake.id)
	# And the real one when it leads that mode's key.
	real.hp = 5000.0
	_mode(sim, t, "strongest")
	assert_int(_shot_target(sim, t)).is_equal(real.id)


# --- 6, 7: harpoon line and Reader blast ------------------------------------------------

func test_harpoon_line_goes_through_the_strongest_enemy() -> void:
	var sim := _rich(tsim())
	var t := build(sim, HARP)
	var weak_front := put(sim, "cultist", 9.0, 100.0)
	var strong := put(sim, "cultist", 5.0, 5000.0)
	var pierced := put(sim, "cultist", 4.5, 100.0)  # 0.22 off the line, past `strong`
	_mode(sim, t, "strongest")
	var s := _shot(sim, t)
	assert_int(s.data["target"]).is_equal(strong.id)
	assert_bool(s.data["miss"]).is_false()
	assert_array(s.data["hits"]).contains_exactly_in_any_order([strong.id, pierced.id])
	assert_array(s.data["hits"]).not_contains([weak_front.id])
	# The line runs from the tower through the target, on to the tower's range.
	var origin := t.centre()
	var aim := strong.route.position_at(strong.distance)
	var to: Vector2 = s.data["to"]
	assert_float((to - origin).normalized().dot((aim - origin).normalized())) \
		.is_equal_approx(1.0, 1e-4)
	assert_float(origin.distance_to(to)).is_greater_equal(origin.distance_to(aim))


func _necro_blast(mode: String) -> void:
	var sim := _rich(tsim())
	var t := build(sim, NECRO)
	var first := put(sim, "cultist", 9.5, 100.0)
	first.base_units_per_tick = 1
	var picked := put(sim, "cultist", 5.0, 5000.0)
	picked.base_units_per_tick = 5
	var near := put(sim, "cultist", 6.0, 100.0)  # 1 cell from `picked`, 3.5 from `first`
	_mode(sim, t, mode)
	var s := _shot(sim, t)
	assert_int(s.data["target"]).override_failure_message(mode).is_equal(picked.id)
	assert_vector(s.data["to"]).is_equal(picked.route.position_at(picked.distance))
	assert_array(s.data["hits"]).contains_exactly_in_any_order([picked.id, near.id])


func test_reader_blast_centres_on_the_strongest_target() -> void:
	_necro_blast("strongest")


func test_reader_blast_centres_on_the_fastest_target() -> void:
	_necro_blast("fastest")


# --- 9: refusals, their order, nothing changed -----------------------------------------

func test_outcome_reached_comes_first_even_for_an_unknown_tower() -> void:
	var sim := _rich(tsim())
	var t := build(sim, RIFLE)
	var sign := build(sim, SIGN, SIGN_CELL)
	sim.state.outcome = SimState.Outcome.LOST
	_assert_refused(sim, t.id, "strongest", R.OUTCOME_REACHED)
	_assert_refused(sim, 9999, "strongest", R.OUTCOME_REACHED)
	_assert_refused(sim, sign.id, "weakest", R.OUTCOME_REACHED)


func test_unknown_or_sold_tower_is_no_such_tower_and_a_new_tower_starts_on_first() -> void:
	var sim := _rich(tsim())
	var t := build(sim, RIFLE)
	_assert_refused(sim, 9999, "strongest", R.NO_SUCH_TOWER)
	_assert_refused(sim, 9999, "weakest", R.NO_SUCH_TOWER)
	_mode(sim, t, "fastest")
	var id := t.id
	assert_int(sim.sell_tower(id)).is_equal(R.OK)
	_assert_refused(sim, id, "strongest", R.NO_SUCH_TOWER)
	var again := build(sim, RIFLE)
	assert_int(again.id).is_not_equal(id)
	assert_str(again.target_priority).is_equal("first")


func test_elder_sign_is_no_targeting_at_every_level_and_beats_bad_priority() -> void:
	for path: Array in [[], [""], ["", "a"], ["", "b"]]:
		var sim := _rich(tsim())
		var sign := build(sim, SIGN, SIGN_CELL)
		for b: String in path:
			assert_int(sim.upgrade_tower(sign.id, b)).is_equal(R.OK)
		assert_bool(sim.has_targeting(sign)).override_failure_message(str(path)).is_false()
		for mode: String in ["first", "strongest", "fastest", "weakest"]:
			_assert_refused(sim, sign.id, mode, R.NO_TARGETING)
		assert_str(sign.target_priority).is_equal("first")


func test_an_unknown_mode_is_bad_priority() -> void:
	var sim := tsim()
	var t := build(sim, RIFLE)
	assert_bool(sim.has_targeting(t)).is_true()
	for mode: String in ["weakest", "", "First", "strongest "]:
		_assert_refused(sim, t.id, mode, R.BAD_PRIORITY)
	assert_str(t.target_priority).is_equal("first")


# --- 10, 11: applied in every phase, logged, one event, cooldown kept ------------------

func test_applied_in_phase_none_build_wave_and_madness() -> void:
	var none := tsim()
	assert_int(none.state.phase).is_equal(SimState.Phase.NONE)
	_assert_applied(none, build(none, RIFLE), "strongest")
	var sim := wsim([[group("cultist", 3, 1.0)]], 2)
	sim.state.gold = 10000
	sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	var t := build(sim, RIFLE)
	_assert_applied(sim, t, "fastest")
	assert_int(sim.call_wave()).is_equal(R.OK)
	sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	_assert_applied(sim, t, "strongest")
	sim.state.sanity = 0.0
	sim.state.sanity_state = sim.sanity_state_for(0.0)
	assert_int(sim.state.sanity_state).is_equal(SimState.SanityState.MADNESS)
	_assert_applied(sim, t, "first")


func test_the_running_cooldown_is_kept_and_the_next_shot_uses_the_new_mode() -> void:
	var sim := tsim()
	var t := build(sim, RIFLE)
	var strong := put(sim, "cultist", 6.0, 5000.0)
	put(sim, "cultist", 8.0, 50.0)
	t.cooldown_ticks = 3
	_assert_applied(sim, t, "strongest")
	var ev := run(sim, 2)
	assert_array(of_type(ev, T.SHOT)).is_empty()
	ev = run(sim, 1)
	var shots := of_type(ev, T.SHOT)
	assert_int(shots.size()).is_equal(1)
	assert_int(shots[0].data["target"]).is_equal(strong.id)


func test_resetting_the_current_mode_is_applied_and_logged_again() -> void:
	var sim := tsim()
	var t := build(sim, RIFLE)
	_assert_applied(sim, t, "first")
	_assert_applied(sim, t, "fastest")
	sim.step()
	_assert_applied(sim, t, "fastest")
	var stp := sim.state.command_log.filter(
		func(c: Array) -> bool: return c[1] == "set_target_priority")
	assert_array(stp).is_equal([[0, "set_target_priority", t.id, "first"],
		[0, "set_target_priority", t.id, "fastest"], [1, "set_target_priority", t.id, "fastest"]])


func test_modes_are_per_tower() -> void:
	var sim := _rich(tsim())
	var a := build(sim, RIFLE)
	var b := build(sim, RIFLE, Vector2i(8, 1))
	_mode(sim, b, "strongest")
	assert_array(_modes(sim)).is_equal(["first", "strongest"])
	assert_str(a.target_priority).is_equal("first")


# --- 13: upgrades keep the mode ---------------------------------------------------------

func test_an_upgrade_keeps_the_chosen_mode_through_l2_and_l3() -> void:
	for spec: Array in [[RIFLE, "a", "fastest"], [HARP, "b", "strongest"],
			[NECRO, "a", "fastest"]]:
		var sim := _rich(tsim())
		var t := build(sim, spec[0])
		_mode(sim, t, spec[2])
		assert_int(sim.upgrade_tower(t.id)).is_equal(R.OK)
		assert_str(sim.tower_by_id(t.id).target_priority).override_failure_message(str(spec)) \
			.is_equal(spec[2])
		assert_int(sim.upgrade_tower(t.id, spec[1])).is_equal(R.OK)
		assert_str(sim.tower_by_id(t.id).target_priority).override_failure_message(str(spec)) \
			.is_equal(spec[2])
