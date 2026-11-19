class_name SimSystemsTest
extends TowerTestBase
## LT-80 (B5, docs/design/LT-80-sim-split.md section 6): the split of Simulation into SimContext
## and the Economy seed, Light and Sanity systems keeps behaviour. Pins: no RefCounted cycle
## (a dropped sim frees its context and systems), one event buffer drained once in emit order,
## the day-only refusals, each moved command's result / event order / command_log entry / replay,
## and the sanity arithmetic. Map: TowerTestBase ROWS, phase NONE (a sim without a WaveDirector).

const T := SimEvent.Type
const R := SimCommand.CommandResult
const P := SimState.Phase
const S := SimState.SanityState


# --- B4: no RefCounted cycles --------------------------------------------------------------

## Weak refs to the sim, its context and each system; the sim itself dies on return. LT-82:
## a Summoning Circle summons first, so the hook Callables between Combat and Ally were called.
func _weak_refs_of_a_dropped_sim() -> Array[WeakRef]:
	var sim := tsim()
	sim.state.gold = 100000
	sim.step()
	sim.upgrade_lighthouse()  # touch every system so none is only lazily referenced
	sim.buy_oil()
	build(sim, "summoning_circle")
	sim.step()
	assert_int(sim.state.allies.size()).override_failure_message("no unit was summoned").is_greater(0)
	var refs: Array[WeakRef] = [weakref(sim)]
	for system: Variant in [sim._ctx, sim._economy, sim._sanity, sim._light, sim._combat, sim._ally]:
		refs.append(weakref(system))
	return refs


func test_a_dropped_sim_frees_its_context_and_systems() -> void:
	var refs := _weak_refs_of_a_dropped_sim()
	assert_int(refs.size()).is_equal(7)
	var live: Array[int] = []
	for i in refs.size():
		if refs[i].get_ref() != null:
			live.append(i)
	assert_array(live).override_failure_message(
		"still alive after the last Simulation reference was dropped (0 sim, 1 ctx, 2 economy, "
		+ "3 sanity, 4 light, 5 combat, 6 ally): %s" % [live]).is_empty()


## Weak refs to Combat and Ally of a dropped sim whose spawn hook captures the ally. The hook
## lambdas die with this frame's stack, so only the cycle can keep the systems alive.
func _weak_refs_with_a_capturing_hook() -> Array[WeakRef]:
	var sim := tsim()
	var combat: CombatSystem = sim._combat
	var ally: AllySystem = sim._ally
	combat.set_ally_hooks(
		func(...args: Array) -> Variant: return ally.callv("spawn", args),
		func(id: int) -> Array[SimAlly]: return ally.allies_of(id))
	return [weakref(combat), weakref(ally)]


## The check above can fail: a hook that captures the ally keeps Combat and Ally alive in a
## cycle (Combat -> lambda -> Ally -> Combat) once the sim is gone.
func test_a_hook_capturing_the_ally_is_seen_as_a_cycle() -> void:
	var refs := _weak_refs_with_a_capturing_hook()
	var combat_alive: bool = refs[0].get_ref() != null
	var ally_alive: bool = refs[1].get_ref() != null
	if combat_alive:  # break the cycle so the test leaves nothing behind
		refs[0].get_ref().set_ally_hooks(Callable(), Callable())
	assert_bool(combat_alive).override_failure_message("a capturing hook did not keep Combat").is_true()
	assert_bool(ally_alive).override_failure_message("a capturing hook did not keep Ally").is_true()
	assert_object(refs[0].get_ref()).is_null()
	assert_object(refs[1].get_ref()).is_null()


# --- B5: one event buffer, one drain -------------------------------------------------------

func test_system_and_facade_events_come_out_of_one_drain_in_emit_order() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	sim.drain_events()
	assert_int(sim.buy_oil()).is_equal(R.OK)  # a system emits OIL_CHANGED, GOLD_CHANGED
	build(sim, "rifleman")  # the facade emits TOWER_BUILT ...
	assert_int(sim.upgrade_lighthouse()).is_equal(R.OK)  # ... then a system again
	var ev := sim.drain_events()
	var types := ev.map(func(e: SimEvent) -> int: return e.type)
	var oil_at := types.find(T.OIL_CHANGED)
	var built_at := types.find(T.TOWER_BUILT)
	var up_at := types.find(T.LIGHTHOUSE_UPGRADED)
	assert_int(oil_at).is_equal(0)
	assert_int(types[1]).is_equal(T.GOLD_CHANGED)
	assert_int(built_at).is_greater(1)
	assert_int(up_at).is_greater(built_at)
	assert_int(types.rfind(T.GOLD_CHANGED)).is_equal(types.size() - 1)  # the upgrade's payment
	assert_int(types.count(T.LIGHTHOUSE_UPGRADED)).is_equal(1)
	assert_array(sim.drain_events()).is_empty()  # the second drain is empty


func test_a_drained_batch_is_not_changed_by_later_emits() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	sim.drain_events()
	sim.buy_oil()
	var first := sim.drain_events()
	var size := first.size()
	assert_int(size).is_greater(0)
	sim.buy_oil()
	assert_int(first.size()).is_equal(size)  # the drain handed the buffer over, it did not copy a view
	var second := sim.drain_events()
	assert_int(second.size()).is_equal(size)
	assert_array(sim.drain_events()).is_empty()


func test_the_events_view_reads_the_one_buffer() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	sim.drain_events()
	sim.buy_oil()
	assert_int(sim.events.size()).is_equal(2)
	assert_array(sim.drain_events()).has_size(2)
	assert_array(sim.events).is_empty()


func test_the_context_stamps_emitted_events_with_the_current_tick() -> void:
	var ctx := SimContext.new(tconfig(), SEED)
	ctx.state.tick = 7
	ctx.emit(T.GOLD_CHANGED, 3, {"k": 1})
	assert_array(ctx.events).has_size(1)
	assert_int(ctx.events[0].tick).is_equal(7)
	assert_int(ctx.events[0].id).is_equal(3)
	assert_dict(ctx.events[0].data).is_equal({"k": 1})


# --- B6: day_only ---------------------------------------------------------------------------

func test_day_only_refuses_at_night_only() -> void:
	var ctx := SimContext.new(tconfig(), SEED)
	var by_phase := {}
	for p: P in [P.NONE, P.BUILD, P.WAVE, P.DONE]:
		ctx.state.phase = p
		by_phase[p] = ctx.day_only()
	assert_int(by_phase[P.WAVE]).is_equal(R.NOT_BUILD_PHASE)
	# not `!= BUILD`: no WaveDirector (NONE) and the end screen (DONE) allow it
	for p: P in [P.NONE, P.BUILD, P.DONE]:
		assert_int(by_phase[p]).override_failure_message("phase %d" % p).is_equal(R.OK)


func _night_sim() -> Simulation:
	var sim := tsim()
	sim.state.gold = 100000
	sim.state.oil = 3
	sim.state.phase = P.WAVE
	sim.drain_events()
	return sim


## `cmd` is refused with `want` and changes nothing (gold, oil, level, log, events).
func _refuses(sim: Simulation, cmd: Callable, want: int) -> void:
	var s := sim.state
	var before := [s.gold, s.oil, s.lighthouse_level, s.command_log.size()]
	assert_int(cmd.call()).is_equal(want)
	assert_array([s.gold, s.oil, s.lighthouse_level, s.command_log.size()]).is_equal(before)
	assert_array(sim.drain_events()).is_empty()


func test_lighthouse_and_oil_are_refused_at_night() -> void:
	var sim := _night_sim()
	assert_int(sim.can_upgrade_lighthouse()).is_equal(R.NOT_BUILD_PHASE)
	assert_int(sim.can_buy_oil()).is_equal(R.NOT_BUILD_PHASE)
	_refuses(sim, sim.upgrade_lighthouse, R.NOT_BUILD_PHASE)
	_refuses(sim, sim.buy_oil, R.NOT_BUILD_PHASE)
	sim.state.phase = P.BUILD  # by day the same sim accepts both
	assert_int(sim.buy_oil()).is_equal(R.OK)
	assert_int(sim.upgrade_lighthouse()).is_equal(R.OK)


func test_the_night_refusal_comes_before_the_money_and_after_the_outcome() -> void:
	var sim := _night_sim()
	sim.state.gold = 0  # also too poor: the night reason is the first failing one
	_refuses(sim, sim.upgrade_lighthouse, R.NOT_BUILD_PHASE)
	_refuses(sim, sim.buy_oil, R.NOT_BUILD_PHASE)
	sim.state.oil = sim.config.economy.oil.cap  # and oil full
	_refuses(sim, sim.buy_oil, R.NOT_BUILD_PHASE)
	sim.state.outcome = SimState.Outcome.LOST
	_refuses(sim, sim.upgrade_lighthouse, R.OUTCOME_REACHED)
	_refuses(sim, sim.buy_oil, R.OUTCOME_REACHED)


# --- B6: each moved command: events, log entry, replay --------------------------------------

## A sim with gold, in phase NONE (flare allowed), madness-by-buyout set up for buy_sanity.
func _prepared(in_madness := true) -> Simulation:
	var sim := tsim()
	sim.state.gold = 1000
	sim.state.oil = sim.config.economy.flare.cost_oil + 3
	sim.config.sanity.madness.exit_rule = "buyout"
	sim.state.sanity = 0.0 if in_madness else sim.state.sanity_cap
	sim.state.sanity_state = sim.sanity_state_for(sim.state.sanity)
	sim.drain_events()
	return sim


## [type, id, data] of events, comparable across two sims.
func _flat(events: Array[SimEvent]) -> Array:
	return events.map(func(e: SimEvent) -> Array: return [e.type, e.tick, e.id, e.data])


func _digest(sim: Simulation) -> Array:
	var s := sim.state
	return [s.tick, s.gold, s.oil, s.lighthouse_level, s.flare_ticks_left,
		s.flare_cooldown_ticks, s.sanity, s.sanity_state, s.sanity_cap, s.command_log]


## Runs `cmd` on a prepared sim, then replays the logged entry on a second prepared sim:
## same result, same events in the same order, same state.
func _replays_identically(name: String, cmd: Callable, expect_event_types: Array,
		in_madness := true) -> void:
	var a := _prepared(in_madness)
	var result: int = cmd.call(a)
	assert_int(result).override_failure_message(name + " result").is_equal(R.OK)
	var ev_a := a.drain_events()
	assert_array(ev_a.map(func(e: SimEvent) -> int: return e.type)) \
		.override_failure_message(name + " event order").is_equal(expect_event_types)
	assert_array(a.state.command_log).override_failure_message(name + " log size").has_size(1)
	var entry: Array = a.state.command_log[0]
	assert_str(entry[1]).is_equal(name)
	assert_int(entry[0]).is_equal(a.state.tick)
	var b := _prepared(in_madness)
	assert_int(b.replay_command(entry)).override_failure_message(name + " replay result") \
		.is_equal(result)
	assert_array(_flat(b.drain_events())).override_failure_message(name + " replay events") \
		.is_equal(_flat(ev_a))
	assert_array(_digest(b)).override_failure_message(name + " replay state") \
		.is_equal(_digest(a))


func test_upgrade_lighthouse_replays_identically() -> void:
	_replays_identically("upgrade_lighthouse",
		func(sim: Simulation) -> int: return sim.upgrade_lighthouse(),
		[T.LIGHTHOUSE_UPGRADED, T.GOLD_CHANGED])


func test_buy_oil_replays_identically() -> void:
	_replays_identically("buy_oil", func(sim: Simulation) -> int: return sim.buy_oil(),
		[T.OIL_CHANGED, T.GOLD_CHANGED])


func test_fire_flare_replays_identically() -> void:
	_replays_identically("fire_flare", func(sim: Simulation) -> int: return sim.fire_flare(),
		[T.FLARE_FIRED, T.OIL_CHANGED])


func test_buy_sanity_replays_identically() -> void:
	_replays_identically("buy_sanity", func(sim: Simulation) -> int: return sim.buy_sanity(),
		[T.GOLD_CHANGED, T.SANITY_CHANGED, T.SANITY_STATE_CHANGED])


func test_debug_set_sanity_replays_identically() -> void:
	_replays_identically("debug_set_sanity",
		func(sim: Simulation) -> int: return sim.debug_set_sanity(0.0),
		[T.SANITY_CHANGED, T.SANITY_STATE_CHANGED], false)


func test_a_mixed_command_log_replays_to_the_same_events_and_state() -> void:
	var a := _prepared(false)
	a.state.gold = 100000
	var cmds := [
		func() -> int: return a.buy_oil(),
		func() -> int: return a.upgrade_lighthouse(),
		func() -> int: return a.debug_set_sanity(5.0),
		func() -> int: return a.fire_flare(),
		func() -> int: return a.debug_set_sanity(0.0),
		func() -> int: return a.buy_sanity(),
		func() -> int: return a.buy_oil(),
	]
	var all_a: Array = []
	for c: Callable in cmds:
		a.step()
		c.call()
		all_a.append_array(_flat(a.drain_events()))
	var b := _prepared(false)
	b.state.gold = 100000
	var all_b: Array = []
	for entry: Array in a.state.command_log:
		while b.state.tick < entry[0]:
			b.step()
			all_b.append_array(_flat(b.drain_events()))
		assert_int(b.replay_command(entry)).is_equal(R.OK)
		all_b.append_array(_flat(b.drain_events()))
	assert_int(a.state.command_log.size()).is_equal(7)
	assert_array(all_b).is_equal(all_a)
	assert_array(_digest(b)).is_equal(_digest(a))


func test_refused_moved_commands_log_nothing() -> void:
	var sim := _prepared()
	sim.state.gold = 0
	sim.state.oil = 0
	assert_int(sim.upgrade_lighthouse()).is_equal(R.NOT_ENOUGH_GOLD)
	assert_int(sim.buy_oil()).is_equal(R.NOT_ENOUGH_GOLD)
	assert_int(sim.fire_flare()).is_equal(R.NO_OIL)
	assert_int(sim.buy_sanity()).is_equal(R.NOT_ENOUGH_GOLD)
	sim.state.outcome = SimState.Outcome.LOST
	assert_int(sim.debug_set_sanity(3.0)).is_equal(R.OUTCOME_REACHED)
	assert_array(sim.state.command_log).is_empty()
	assert_array(sim.drain_events()).is_empty()


# --- C1: SanitySystem.add arithmetic --------------------------------------------------------

func _sane_sim() -> Simulation:
	var sim := tsim()
	sim.state.sanity = sim.state.sanity_cap
	sim.state.sanity_state = sim.sanity_state_for(sim.state.sanity)
	sim.drain_events()
	return sim


func test_sanity_change_is_clamped_to_zero_and_the_cap_and_reports_the_applied_delta() -> void:
	var sim := _sane_sim()
	var cap := sim.state.sanity_cap
	assert_int(sim.debug_set_sanity(cap + 500.0)).is_equal(R.OK)  # already at the cap
	assert_float(sim.state.sanity).is_equal(cap)
	assert_array(sim.drain_events()).is_empty()  # delta 0 applied: nothing emitted
	var low := cap * 0.5
	sim.debug_set_sanity(low)
	assert_float(sim.state.sanity).is_equal_approx(low, 1e-6)
	var ev := sim.drain_events()
	assert_int(ev[0].type).is_equal(T.SANITY_CHANGED)
	assert_float(ev[0].data["delta"]).is_equal_approx(low - cap, 1e-6)  # the delta applied
	assert_float(ev[0].data["sanity"]).is_equal_approx(low, 1e-6)
	assert_str(ev[0].data["reason"]).is_equal("debug")
	sim.debug_set_sanity(cap + 500.0)  # clamped up: the applied delta is cap - low
	ev = sim.drain_events()
	assert_float(sim.state.sanity).is_equal(cap)
	assert_float(ev[0].data["delta"]).is_equal_approx(cap - low, 1e-6)
	sim.debug_set_sanity(-50.0)  # clamped down to 0
	assert_float(sim.state.sanity).is_equal(0.0)


func test_a_threshold_move_emits_the_state_change_after_the_amount_change() -> void:
	var sim := _sane_sim()
	var before := sim.state.sanity_state
	sim.debug_set_sanity(0.0)
	var after := sim.sanity_state_for(0.0)
	assert_int(sim.state.sanity_state).is_equal(after)
	var ev := sim.drain_events()
	assert_array(ev.map(func(e: SimEvent) -> int: return e.type)).is_equal(
		[T.SANITY_CHANGED, T.SANITY_STATE_CHANGED])
	assert_dict(ev[1].data).is_equal({"old": before, "new": after})
	assert_int(after).is_not_equal(before)


func test_madness_is_latched_against_a_debug_change() -> void:
	var sim := _sane_sim()
	sim.debug_set_sanity(0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	sim.drain_events()
	assert_int(sim.debug_set_sanity(sim.state.sanity_cap)).is_equal(R.OK)  # "debug" is no exit reason
	assert_float(sim.state.sanity).is_equal(0.0)
	assert_array(sim.drain_events()).is_empty()
	assert_array(sim.state.command_log.back()).is_equal([0, "debug_set_sanity", sim.state.sanity_cap])
