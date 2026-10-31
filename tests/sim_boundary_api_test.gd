class_name SimBoundaryApiTest
extends WaveTestBase
## LT-34/S2 pins for the sim API the UI used to re-derive (LT-33 findings 3-6):
## would_drive_mad_build / would_drive_mad_upgrade (the cap-to-zero rule, ported from the
## removed TowerInfo.drives_mad test), debug_set_sanity and replay_command.

const T := SimEvent.Type
const S := SimState.SanityState
const R2 := Simulation.CommandResult
const SIGN := "elder_sign"
const NECRO := "necronomicon_reader"
const RIFLE := "rifleman"


# --- helpers ---------------------------------------------------------------------------

## A comparable snapshot of everything a query must not touch.
func _digest(sim: Simulation) -> String:
	var s := sim.state
	var ev: Array[String] = []
	for e in sim.events:
		ev.append(str(e))
	return "tick=%d gold=%d sanity=%s cap=%s st=%d out=%d next=%d towers=%d log=%s ev=%s" % [
		s.tick, s.gold, s.sanity, s.sanity_cap, s.sanity_state, s.outcome, s.next_id,
		s.towers.size(), str(s.command_log), "|".join(ev)]


func _l1(sim: Simulation, def_id: String) -> TowerDef.Level:
	return sim.config.towers[def_id].levels[0]


## Puts the sim in the given sanity condition without any command (the cap rule reads state).
func _at(sim: Simulation, cap: float, state: S = S.FRAYING) -> void:
	sim.state.sanity_cap = cap
	sim.state.sanity = minf(sim.state.sanity, cap)
	sim.state.sanity_state = state


func _build_sign(sim: Simulation) -> SimTower:
	sim.state.gold = 100000
	return build(sim, SIGN, Vector2i(3, 1))


## A sim with an Elder Sign at L2 (reserve 8); branch reserves a=2, b=15 edited on the config.
func _sign_at_l2(a_reserve := 10.0, b_reserve := 15.0) -> Array:
	var sim := tsim()
	var def: TowerDef = sim.config.towers[SIGN]
	def.branches["a"].sanity_reserve = a_reserve
	def.branches["b"].sanity_reserve = b_reserve
	var t := _build_sign(sim)
	assert_int(sim.upgrade_tower(t.id)).is_equal(R2.OK)
	sim.drain_events()
	return [sim, t]


# --- would_drive_mad_build -------------------------------------------------------------

func test_would_drive_mad_build_cap_taken_to_zero_outside_madness_only() -> void:
	var sim := tsim()
	for row: Array in [[10.0, 10.0, true], [10.0, 12.0, true], [10.0, 9.5, false],
			[10.0, 0.0, false], [0.0, 0.0, false], [10.0, -5.0, false]]:
		_l1(sim, NECRO).sanity_reserve = row[1]
		_at(sim, row[0])
		assert_bool(sim.would_drive_mad_build(NECRO)).override_failure_message(
			"cap %s reserve %s" % [row[0], row[1]]).is_equal(row[2])
	_l1(sim, NECRO).sanity_reserve = 12.0
	_at(sim, 10.0, S.MADNESS)
	assert_bool(sim.would_drive_mad_build(NECRO)).is_false()


func test_would_drive_mad_build_unknown_tower_and_ignores_gold() -> void:
	var sim := tsim()
	_l1(sim, NECRO).sanity_reserve = 10.0
	_at(sim, 10.0)
	sim.state.gold = 0
	assert_bool(sim.would_drive_mad_build("no_such_tower")).is_false()
	assert_bool(sim.would_drive_mad_build("")).is_false()
	assert_bool(sim.would_drive_mad_build(NECRO)).is_true()
	assert_int(sim.can_build(NECRO, Vector2i(3, 1))).is_equal(R2.NOT_ENOUGH_GOLD)


func test_would_drive_mad_build_changes_nothing() -> void:
	var sim := tsim()
	_l1(sim, NECRO).sanity_reserve = 10.0
	_at(sim, 10.0)
	sim.state.gold = 1000
	var before := _digest(sim)
	for i in 3:
		sim.would_drive_mad_build(NECRO)
		sim.would_drive_mad_build("no_such_tower")
	assert_str(_digest(sim)).is_equal(before)
	assert_array(sim.state.towers).is_empty()


func test_would_drive_mad_build_agrees_with_build_tower() -> void:
	for offset in [0.0, 1.0, -1.0]:  # reserve = max, max + 1 (floors the cap), max - 1
		var sim := tsim()
		_l1(sim, NECRO).sanity_reserve = sim.config.sanity.max_sanity + offset
		sim.state.gold = 1000
		var predicted := sim.would_drive_mad_build(NECRO)
		assert_int(sim.build_tower(NECRO, Vector2i(3, 1))).is_equal(R2.OK)
		assert_bool(sim.state.sanity_state == S.MADNESS).override_failure_message(
			"offset %s" % offset).is_equal(predicted)
		assert_bool(predicted).is_equal(offset >= 0.0)


# --- would_drive_mad_upgrade -----------------------------------------------------------

func test_would_drive_mad_upgrade_uses_the_delta_not_the_absolute_reserve() -> void:
	var sim := tsim()
	var t := _build_sign(sim)  # L1 reserve 5 -> L2 reserve 8: delta 3
	for row: Array in [[3.0, true], [2.0, true], [3.5, false], [5.0, false], [8.0, false]]:
		_at(sim, row[0])
		assert_bool(sim.would_drive_mad_upgrade(t.id)).override_failure_message(
			"cap %s" % row[0]).is_equal(row[1])
	_at(sim, 3.0, S.MADNESS)
	assert_bool(sim.would_drive_mad_upgrade(t.id)).is_false()


func test_would_drive_mad_upgrade_branches_use_their_own_delta() -> void:
	var made := _sign_at_l2(10.0, 15.0)  # from L2 reserve 8: a = +2, b = +7
	var sim: Simulation = made[0]
	var t: SimTower = made[1]
	_at(sim, 5.0)
	assert_bool(sim.would_drive_mad_upgrade(t.id, "a")).is_false()
	assert_bool(sim.would_drive_mad_upgrade(t.id, "b")).is_true()
	_at(sim, 2.0)
	assert_bool(sim.would_drive_mad_upgrade(t.id, "a")).is_true()


func test_would_drive_mad_upgrade_false_without_a_target_or_a_positive_delta() -> void:
	var made := _sign_at_l2(2.0, 15.0)  # branch a frees cap: 2 - 8 = -6
	var sim: Simulation = made[0]
	var t: SimTower = made[1]
	_at(sim, 1.0)
	assert_bool(sim.would_drive_mad_upgrade(t.id, "a")).is_false()
	assert_bool(sim.would_drive_mad_upgrade(t.id, "b")).is_true()
	assert_bool(sim.would_drive_mad_upgrade(t.id)).is_false()  # L2 needs a branch
	assert_bool(sim.would_drive_mad_upgrade(t.id, "x")).is_false()
	assert_bool(sim.would_drive_mad_upgrade(9999, "b")).is_false()
	sim.state.gold = 100000
	assert_int(sim.upgrade_tower(t.id, "b")).is_equal(R2.OK)  # now L3
	_at(sim, 0.5)
	assert_bool(sim.would_drive_mad_upgrade(t.id, "a")).is_false()
	assert_bool(sim.would_drive_mad_upgrade(t.id, "b")).is_false()
	assert_bool(sim.would_drive_mad_upgrade(t.id)).is_false()
	# A fresh L1 tower refuses a branch.
	var sim2 := tsim()
	var t2 := _build_sign(sim2)
	_at(sim2, 0.5)
	assert_bool(sim2.would_drive_mad_upgrade(t2.id, "a")).is_false()
	assert_bool(sim2.would_drive_mad_upgrade(t2.id)).is_true()


func test_would_drive_mad_upgrade_changes_nothing_and_ignores_gold() -> void:
	var sim := tsim()
	var t := _build_sign(sim)
	_at(sim, 3.0)
	sim.state.gold = 0
	var before := _digest(sim)
	assert_bool(sim.would_drive_mad_upgrade(t.id)).is_true()
	sim.would_drive_mad_upgrade(t.id, "a")
	sim.would_drive_mad_upgrade(9999)
	assert_str(_digest(sim)).is_equal(before)
	assert_int(t.level).is_equal(0)


func test_would_drive_mad_upgrade_agrees_with_upgrade_tower() -> void:
	for l2: float in [100.0, 99.0]:  # L1 reserve 5 leaves cap 95; the delta takes it to 0 / 4
		var sim := tsim()
		sim.config.towers[SIGN].levels[1].sanity_reserve = l2
		var t := _build_sign(sim)
		var predicted := sim.would_drive_mad_upgrade(t.id)
		assert_int(sim.upgrade_tower(t.id)).is_equal(R2.OK)
		assert_bool(sim.state.sanity_state == S.MADNESS).override_failure_message(
			"L2 reserve %s" % l2).is_equal(predicted)
		assert_bool(predicted).is_equal(l2 >= 100.0)


# --- debug_set_sanity ------------------------------------------------------------------

func test_debug_set_sanity_sets_logs_and_emits_debug_reason() -> void:
	var sim := tsim()
	sim.drain_events()
	assert_int(sim.debug_set_sanity(40.0)).is_equal(R2.OK)
	assert_float(sim.state.sanity).is_equal(40.0)
	assert_array(sim.state.command_log).is_equal([[0, "debug_set_sanity", 40.0]])
	var ch := of_type(sim.drain_events(), T.SANITY_CHANGED)
	assert_int(ch.size()).is_equal(1)
	assert_str(ch[0].data["reason"]).is_equal("debug")
	assert_float(ch[0].data["delta"]).is_equal_approx(-60.0, 0.0001)
	assert_float(ch[0].data["sanity"]).is_equal(40.0)
	assert_int(ch[0].id).is_equal(0)


func test_debug_set_sanity_clamps_to_zero_and_to_the_cap() -> void:
	var sim := tsim()
	sim.config.towers[NECRO].levels[0].sanity_reserve = 30.0
	sim.state.gold = 1000
	build(sim, NECRO)
	assert_float(sim.state.sanity_cap).is_equal_approx(70.0, 0.0001)
	assert_int(sim.debug_set_sanity(10.0)).is_equal(R2.OK)
	assert_int(sim.debug_set_sanity(1000.0)).is_equal(R2.OK)
	assert_float(sim.state.sanity).is_equal_approx(70.0, 0.0001)
	assert_int(sim.debug_set_sanity(-5.0)).is_equal(R2.OK)
	assert_float(sim.state.sanity).is_equal(0.0)


func test_debug_set_sanity_to_zero_starts_madness() -> void:
	var sim := tsim()
	sim.drain_events()
	sim.debug_set_sanity(0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	var evs := sim.drain_events()
	assert_int(of_type(evs, T.SANITY_STATE_CHANGED).size()).is_equal(1)
	assert_str(of_type(evs, T.SANITY_CHANGED)[0].data["reason"]).is_equal("debug")


func test_debug_set_sanity_in_madness_applies_nothing_but_is_ok_and_logged() -> void:
	var sim := tsim()
	sim.debug_set_sanity(0.0)
	sim.drain_events()
	assert_int(sim.debug_set_sanity(50.0)).is_equal(R2.OK)
	assert_float(sim.state.sanity).is_equal(0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	assert_array(sim.drain_events()).is_empty()
	assert_int(sim.state.command_log.size()).is_equal(2)


func test_debug_set_sanity_to_the_current_value_is_logged_without_an_event() -> void:
	var sim := tsim()
	sim.drain_events()
	assert_int(sim.debug_set_sanity(sim.state.sanity)).is_equal(R2.OK)
	assert_array(sim.drain_events()).is_empty()
	assert_int(sim.state.command_log.size()).is_equal(1)


func test_debug_set_sanity_is_refused_once_the_run_is_over() -> void:
	for outcome in [SimState.Outcome.WON, SimState.Outcome.LOST]:
		var sim := tsim()
		sim.drain_events()
		sim.state.outcome = outcome
		var before := _digest(sim)
		assert_int(sim.debug_set_sanity(10.0)).is_equal(R2.OUTCOME_REACHED)
		assert_str(_digest(sim)).is_equal(before)
		assert_array(sim.state.command_log).is_empty()
		assert_float(sim.state.sanity).is_equal(100.0)
	# A real outcome too: a lighthouse of 1 HP is overrun.
	var lost := tsim({}, 1)
	put(lost, "cultist", 13.0).base_units_per_tick = 100000
	for i in 200:
		lost.step()
	assert_int(lost.state.outcome).is_equal(SimState.Outcome.LOST)
	assert_int(lost.debug_set_sanity(1.0)).is_equal(R2.OUTCOME_REACHED)


func test_a_debug_run_replays_through_replay_command() -> void:
	var a := _debug_run()
	var b := wsim([[group("deep_one", 2, 0.5)]], 2)
	b.state.gold = 10000
	_replay(b, a.state.command_log, a.state.tick)
	assert_str(_digest_all(b)).is_equal(_digest_all(a))
	assert_array(b.state.command_log).is_equal(a.state.command_log)
	var names: Array = a.state.command_log.map(func(c: Array) -> String: return c[1])
	assert_array(names).contains(["debug_set_sanity", "build", "upgrade", "call_wave"])
	# Control: without the debug entry the sanity differs.
	var c := wsim([[group("deep_one", 2, 0.5)]], 2)
	c.state.gold = 10000
	_replay(c, a.state.command_log.filter(func(e: Array) -> bool: return e[1] != "debug_set_sanity"),
		a.state.tick)
	assert_bool(_digest_all(c) == _digest_all(a)).is_false()


# --- replay_command --------------------------------------------------------------------

func _debug_run() -> Simulation:
	var sim := wsim([[group("deep_one", 2, 0.5)]], 2)
	sim.state.gold = 10000
	sim.debug_set_sanity(35.0)
	for i in 5:
		sim.step()
	var t := build(sim, SIGN, Vector2i(3, 1))
	build(sim, RIFLE, Vector2i(6, 1))
	sim.step()
	assert_int(sim.upgrade_tower(t.id)).is_equal(R2.OK)
	assert_int(sim.call_wave()).is_equal(R2.OK)
	for i in 400:
		sim.step()
	return sim


## State digest including every event emitted so far (events are not drained).
func _digest_all(sim: Simulation) -> String:
	return _digest(sim) + " enemies=" + str(sim.state.enemies.map(
		func(e: SimEnemy) -> String: return "%d:%s:%d" % [e.id, e.hp, e.distance]))


## Re-applies `log` on a fresh sim: steps to each entry's tick, then replay_command.
func _replay(sim: Simulation, log: Array, end_tick: int) -> void:
	for entry: Array in log:
		while sim.state.tick < int(entry[0]):
			sim.step()
		sim.replay_command(entry)
	while sim.state.tick < end_tick:
		sim.step()


func _twin() -> Array:
	var pair: Array = []
	for i in 2:
		var sim := wsim([[group("deep_one", 1)]], 5)
		sim.state.gold = 100000
		sim.state.relics["star_stone"] = 2
		sim.config.sanity.madness.exit_rule = "buyout"
		pair.append(sim)
	return pair


## `entry` through replay_command on one twin and `direct` on the other: same result, same
## state, and the replayed command is logged (when it succeeded) exactly like the original.
func _same_as_direct(pair: Array, entry: Array, direct: Callable) -> void:
	var viaReplay: int = pair[0].replay_command(entry)
	var viaDirect: int = direct.call(pair[1])
	assert_int(viaReplay).override_failure_message("%s" % [entry]).is_equal(viaDirect)
	assert_str(_digest(pair[0])).override_failure_message("%s" % [entry]).is_equal(
		_digest(pair[1]))
	if viaReplay == R2.OK:
		assert_array(pair[0].state.command_log.back()).is_equal(entry)


func test_replay_command_build_sell_upgrade_priority() -> void:
	var p := _twin()
	var c := Vector2i(3, 1)
	_same_as_direct(p, [0, "build", SIGN, c], func(s: Simulation) -> int:
		return s.build_tower(SIGN, c))
	_same_as_direct(p, [0, "build", SIGN, c], func(s: Simulation) -> int:
		return s.build_tower(SIGN, c))  # occupied on both
	_same_as_direct(p, [0, "build", RIFLE, Vector2i(5, 1)], func(s: Simulation) -> int:
		return s.build_tower(RIFLE, Vector2i(5, 1)))
	var rid: int = p[0].state.tower_at[Vector2i(5, 1)]
	_same_as_direct(p, [0, "set_target_priority", rid, "strongest"], func(s: Simulation) -> int:
		return s.set_target_priority(rid, "strongest"))
	_same_as_direct(p, [0, "upgrade", rid, ""], func(s: Simulation) -> int:
		return s.upgrade_tower(rid, ""))
	_same_as_direct(p, [0, "upgrade", rid, "b"], func(s: Simulation) -> int:
		return s.upgrade_tower(rid, "b"))  # L2 -> L3 branch b
	var sid: int = p[0].state.tower_at[c]
	_same_as_direct(p, [0, "sell", sid], func(s: Simulation) -> int:
		return s.sell_tower(sid))
	assert_int(p[0].state.towers.size()).is_equal(1)
	assert_int(p[0].state.tower_at.size()).is_equal(1)
	var rt: SimTower = p[0].tower_by_id(rid)
	assert_int(rt.level).is_equal(2)
	assert_str(rt.target_priority).is_equal("strongest")


func test_replay_command_call_wave_sell_relics_buy_sanity_debug() -> void:
	var p := _twin()
	_same_as_direct(p, [0, "sell_relics", "star_stone"], func(s: Simulation) -> int:
		return s.sell_relics("star_stone"))
	assert_int(p[0].state.relics["star_stone"]).is_equal(0)
	_same_as_direct(p, [0, "sell_relics", "star_stone"], func(s: Simulation) -> int:
		return s.sell_relics("star_stone"))  # NO_RELICS on both
	_same_as_direct(p, [0, "buy_sanity"], func(s: Simulation) -> int: return s.buy_sanity())
	_same_as_direct(p, [0, "debug_set_sanity", 0.0], func(s: Simulation) -> int:
		return s.debug_set_sanity(0.0))
	assert_int(p[0].state.sanity_state).is_equal(S.MADNESS)
	_same_as_direct(p, [0, "buy_sanity"], func(s: Simulation) -> int: return s.buy_sanity())
	assert_float(p[0].state.sanity).is_greater(0.0)
	_same_as_direct(p, [0, "debug_set_sanity", 12.5], func(s: Simulation) -> int:
		return s.debug_set_sanity(12.5))
	_same_as_direct(p, [0, "call_wave"], func(s: Simulation) -> int: return s.call_wave())
	assert_int(p[0].state.phase).is_equal(SimState.Phase.WAVE)
	var names: Array = p[0].state.command_log.map(func(e: Array) -> String: return e[1])
	assert_array(names).is_equal(["sell_relics", "debug_set_sanity", "buy_sanity",
		"debug_set_sanity", "call_wave"])


func test_replay_command_unknown_or_short_entries_change_nothing() -> void:
	var sim := tsim()
	sim.drain_events()
	var before := _digest(sim)
	for entry: Array in [[0, "no_such_command"], [0, "no_such_command", 1, 2], [0], [], [0, ""]]:
		var r := {"v": -1}
		await assert_error(func() -> void: r["v"] = sim.replay_command(entry)) \
			.is_push_error("Simulation.replay_command: unknown entry %s" % [entry])
		assert_int(r["v"]).override_failure_message("%s" % [entry]).is_equal(
			R2.UNKNOWN_COMMAND)
	assert_str(_digest(sim)).is_equal(before)


func test_unknown_command_is_a_distinct_result() -> void:
	var seen := {}
	for k: String in R2:
		assert_bool(seen.has(R2[k])).is_false()
		seen[R2[k]] = true
	assert_int(R2.UNKNOWN_COMMAND).is_equal(R2.size() - 2)
	assert_int(R2.BAD_ARGS).is_equal(R2.size() - 1)  # LT-36: appended, values never shift
	assert_int(R2.OK).is_equal(0)


# --- LT-36: replay_command refuses malformed entries; buyout_applies ----------------------

## Malformed entries per known command: missing, extra and wrong-typed args.
const BAD_ENTRIES := {
	"build": [[0, "build"], [0, "build", SIGN], [0, "build", SIGN, Vector2i(3, 1), 1],
		[0, "build", 5, Vector2i(3, 1)], [0, "build", SIGN, Vector2(3, 1)], [0, "build", SIGN, "3,1"]],
	"sell": [[0, "sell"], [0, "sell", 1, 2], [0, "sell", "1"], [0, "sell", 1.0], [0, "sell", null]],
	"upgrade": [[0, "upgrade"], [0, "upgrade", 1], [0, "upgrade", 1, "", 3],
		[0, "upgrade", "1", ""], [0, "upgrade", 1, null], [0, "upgrade", 1, 2]],
	"set_target_priority": [[0, "set_target_priority", 1], [0, "set_target_priority", 1, 7],
		[0, "set_target_priority", "strongest", 1]],
	"call_wave": [[0, "call_wave", 1], [0, "call_wave", null]],
	"buy_sanity": [[0, "buy_sanity", ""]],
	"sell_relics": [[0, "sell_relics"], [0, "sell_relics", 3], [0, "sell_relics", "star_stone", 1]],
	"debug_set_sanity": [[0, "debug_set_sanity"], [0, "debug_set_sanity", "40"],
		[0, "debug_set_sanity", true], [0, "debug_set_sanity", 1.0, 2.0]],
}


## A sim where every well-formed command could apply: gold, relics, a tower (id known),
## exit rule "buyout" and the player in MADNESS.
func _ready_sim() -> Array:
	var sim := wsim([[group("deep_one", 1)]], 5)
	sim.state.gold = 100000
	sim.state.relics["star_stone"] = 2
	sim.config.sanity.madness.exit_rule = "buyout"
	var t := build(sim, RIFLE, Vector2i(5, 1))
	sim.drain_events()
	return [sim, t.id]


func test_bad_entries_cover_every_replayable_command() -> void:
	var keys: Array = BAD_ENTRIES.keys()
	keys.sort()
	var want: Array = Simulation.REPLAY_ARGS.keys()
	want.sort()
	assert_array(keys).is_equal(want)


func test_replay_command_known_name_with_bad_args_is_bad_args_and_changes_nothing() -> void:
	var p := _ready_sim()
	var sim: Simulation = p[0]
	var before := _digest_all(sim)
	for cmd: String in BAD_ENTRIES:
		for entry: Array in BAD_ENTRIES[cmd]:
			var r := {"v": -1}
			await assert_error(func() -> void: r["v"] = sim.replay_command(entry)) \
				.is_push_error("Simulation.replay_command: bad args %s" % [entry])
			assert_int(r["v"]).override_failure_message("%s" % [entry]).is_equal(R2.BAD_ARGS)
	assert_str(_digest_all(sim)).is_equal(before)
	assert_array(sim.drain_events()).is_empty()


func test_replay_command_non_string_or_unknown_name_stays_unknown_command() -> void:
	var sim: Simulation = _ready_sim()[0]
	var before := _digest_all(sim)
	for entry: Array in [[0, 5], [0, null], [0, ["build"]], [0, &"no_such_command"],
			[0, "Build", RIFLE, Vector2i(6, 1)], [0, "build_tower", RIFLE, Vector2i(6, 1)]]:
		var r := {"v": -1}
		await assert_error(func() -> void: r["v"] = sim.replay_command(entry)) \
			.is_push_error("Simulation.replay_command: unknown entry %s" % [entry])
		assert_int(r["v"]).override_failure_message("%s" % [entry]).is_equal(
			R2.UNKNOWN_COMMAND)
	assert_str(_digest_all(sim)).is_equal(before)


func test_replay_command_accepts_string_name_for_string_and_int_for_float() -> void:
	var a: Array = _ready_sim()
	var b: Array = _ready_sim()
	assert_int(a[0].replay_command([0, &"sell_relics", &"star_stone"])).is_equal(R2.OK)
	assert_int(b[0].sell_relics("star_stone")).is_equal(R2.OK)
	assert_int(a[0].replay_command([0, "upgrade", a[1], &"b"])).is_equal(
		b[0].upgrade_tower(b[1], "b"))
	assert_int(a[0].replay_command([0, "debug_set_sanity", 12])).is_equal(R2.OK)
	assert_int(b[0].debug_set_sanity(12.0)).is_equal(R2.OK)
	assert_str(_digest_all(a[0])).is_equal(_digest_all(b[0]))
	assert_float(a[0].state.sanity).is_equal(minf(12.0, a[0].state.sanity_cap))


func test_buyout_applies_only_with_the_buyout_rule_in_madness() -> void:
	for rule: String in ["permanent", "buyout", "auto_restore"]:
		for st: S in [S.LUCID, S.WHISPERS, S.FRAYING, S.MADNESS]:
			var sim := tsim()
			sim.config.sanity.madness.exit_rule = rule
			sim.state.sanity_state = st
			var before := _digest_all(sim)
			assert_bool(sim.buyout_applies()).override_failure_message("%s %d" % [rule, st]) \
				.is_equal(rule == "buyout" and st == S.MADNESS)
			assert_str(_digest_all(sim)).is_equal(before)


func test_buyout_applies_ignores_gold_cap_and_outcome() -> void:
	# It says whether the button exists; can_buy_sanity says whether pressing it works.
	var sim := tsim()
	sim.config.sanity.madness.exit_rule = "buyout"
	_at(sim, 0.0, S.MADNESS)
	sim.state.gold = 0
	assert_int(sim.can_buy_sanity()).is_not_equal(R2.OK)
	assert_bool(sim.buyout_applies()).is_true()
	sim.state.outcome = SimState.Outcome.LOST
	assert_int(sim.can_buy_sanity()).is_equal(R2.OUTCOME_REACHED)
	assert_bool(sim.buyout_applies()).is_true()
