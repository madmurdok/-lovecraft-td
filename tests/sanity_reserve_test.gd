class_name SanityReserveTest
extends WaveTestBase
## LT-23 §1 sanity reserve (design note §6, pins 4, 5, 7, 9, 17): regen stops at the cap,
## a sell raises only the cap (MADNESS too), reserves above sanity.max floor the cap at 0,
## buyout / auto restore to min(restore_sanity, cap) with NO_SANITY_ROOM at cap 0, and
## determinism of a build/upgrade/sell log. A test that wants a given cap edits a level's
## sanity_reserve on the loaded config and builds, never state.sanity_cap (S2 note).

const T := SimEvent.Type
const S := SimState.SanityState
const SIGN := "elder_sign"
const NECRO := "necronomicon_reader"
const RIFLE := "rifleman"


# --- helpers ---------------------------------------------------------------------------

func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	sim.drain_events()


func _l1(sim: Simulation, def_id: String) -> TowerDef.Level:
	return sim.config.towers[def_id].levels[0]


## The i-th cell of the buildable row (row 1 of ROWS).
func _cell(i: int) -> Vector2i:
	return Vector2i(i, 1)


## Builds a Necronomicon whose L1 reserve is `reserve` (edited on the loaded config).
func _reserve_tower(sim: Simulation, reserve: float, cell := TOWER) -> SimTower:
	_l1(sim, NECRO).sanity_reserve = reserve
	sim.state.gold = 100000
	return build(sim, NECRO, cell)


# --- 4: regen stops at the cap ---------------------------------------------------------

func test_mundane_kill_regen_stops_at_the_cap() -> void:
	var sim := tsim()
	build(sim, RIFLE, _cell(1))
	_reserve_tower(sim, 10.0)
	var cap := sim.state.sanity_cap
	assert_float(cap).is_equal_approx(sim.config.sanity.max_sanity - 10.0, 0.0001)
	var regen: float = sim.config.sanity.regen_mundane_kill
	assert_float(regen).is_greater(0.0)
	_set_sanity(sim, cap - regen / 2.0)
	var e := put(sim, "cultist", 3.0)
	sim.apply_damage(e.id, 1.0e9, RIFLE)
	assert_float(sim.state.sanity).is_equal_approx(cap, 0.0001)
	var ch := of_type(sim.drain_events(), T.SANITY_CHANGED)
	assert_int(ch.size()).is_equal(1)
	assert_float(ch[0].data["delta"]).is_equal_approx(regen / 2.0, 0.0001)
	# At the cap: nothing applied, nothing emitted.
	var e2 := put(sim, "cultist", 4.0)
	sim.apply_damage(e2.id, 1.0e9, RIFLE)
	assert_float(sim.state.sanity).is_equal_approx(cap, 0.0001)
	assert_array(of_type(sim.drain_events(), T.SANITY_CHANGED)).is_empty()


func test_between_waves_regen_stops_at_the_cap() -> void:
	var sim := tsim()
	_reserve_tower(sim, 25.0)
	var cap := sim.state.sanity_cap
	var regen: float = sim.config.sanity.regen_between_waves
	assert_float(regen).is_greater(5.0)
	_set_sanity(sim, cap - 5.0)
	assert_float(sim.award_wave_sanity()).is_equal_approx(5.0, 0.0001)
	assert_float(sim.state.sanity).is_equal_approx(cap, 0.0001)
	assert_float(sim.award_wave_sanity()).is_equal(0.0)
	assert_float(sim.state.sanity).is_equal_approx(cap, 0.0001)


# --- 5: sell raises the cap only -------------------------------------------------------

func test_sell_raises_the_cap_by_the_reserve_after_the_gold_and_keeps_sanity() -> void:
	var sim := tsim()
	var t := _reserve_tower(sim, 20.0)
	_set_sanity(sim, 50.0)
	var cap := sim.state.sanity_cap
	assert_int(sim.sell_tower(t.id)).is_equal(Simulation.CommandResult.OK)
	var ev := sim.drain_events()
	assert_array(ev.map(func(x: SimEvent) -> int: return x.type)).is_equal(
		[T.TOWER_SOLD, T.GOLD_CHANGED, T.SANITY_CAP_CHANGED])
	assert_int(ev[2].id).is_equal(t.id)
	assert_dict(ev[2].data).is_equal({"delta": 20.0, "cap": cap + 20.0, "reason": "sell"})
	assert_float(sim.state.sanity_cap).is_equal(sim.config.sanity.max_sanity)
	assert_float(sim.state.sanity).is_equal(50.0)
	# Regen refills up to the new, higher cap.
	_set_sanity(sim, cap)
	sim.award_wave_sanity()
	assert_float(sim.state.sanity).is_greater(cap)


func test_sell_in_madness_raises_the_cap_and_stays_mad() -> void:
	var sim := tsim()
	var t := _reserve_tower(sim, 20.0)
	_set_sanity(sim, 0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	assert_int(sim.sell_tower(t.id)).is_equal(Simulation.CommandResult.OK)
	assert_float(sim.state.sanity_cap).is_equal(sim.config.sanity.max_sanity)
	assert_float(sim.state.sanity).is_equal(0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	var ev := sim.drain_events()
	assert_int(of_type(ev, T.SANITY_CAP_CHANGED).size()).is_equal(1)
	assert_array(of_type(ev, T.SANITY_CHANGED)).is_empty()
	assert_array(of_type(ev, T.SANITY_STATE_CHANGED)).is_empty()


func test_selling_a_mundane_tower_moves_no_cap() -> void:
	var sim := tsim()
	sim.state.gold = 1000
	var t := build(sim, RIFLE)
	sim.drain_events()
	sim.sell_tower(t.id)
	assert_array(of_type(sim.drain_events(), T.SANITY_CAP_CHANGED)).is_empty()
	assert_float(sim.state.sanity_cap).is_equal(sim.config.sanity.max_sanity)


# --- 7: reserves above max floor the cap at 0 -------------------------------------------

func test_reserves_above_max_keep_the_cap_at_zero_until_the_sum_drops_below_max() -> void:
	var sim := tsim()
	var top := sim.config.sanity.max_sanity
	var r := top * 0.6
	var a := _reserve_tower(sim, r, _cell(1))
	var b := _reserve_tower(sim, r, _cell(3))
	assert_float(sim.state.sanity_cap).is_equal(0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	# The second build applied only what was left of the cap.
	var caps := of_type(sim.drain_events(), T.SANITY_CAP_CHANGED)
	assert_int(caps.size()).is_equal(2)
	assert_float(caps[1].data["delta"]).is_equal_approx(-(top - r), 0.0001)
	var c := _reserve_tower(sim, r, _cell(5))  # sum 1.8 x max: no cap move, no event
	assert_array(of_type(sim.drain_events(), T.SANITY_CAP_CHANGED)).is_empty()
	sim.sell_tower(a.id)  # sum 1.2 x max: still 0
	assert_float(sim.state.sanity_cap).is_equal(0.0)
	assert_array(of_type(sim.drain_events(), T.SANITY_CAP_CHANGED)).is_empty()
	sim.sell_tower(b.id)  # sum 0.6 x max: cap max - r
	assert_float(sim.state.sanity_cap).is_equal_approx(top - r, 0.0001)
	caps = of_type(sim.drain_events(), T.SANITY_CAP_CHANGED)
	assert_int(caps.size()).is_equal(1)
	assert_float(caps[0].data["delta"]).is_equal_approx(top - r, 0.0001)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)  # latched
	assert_float(sim.state.sanity).is_equal(0.0)
	assert_bool(c != null).is_true()


# --- 9: buyout / auto_restore under the cap ---------------------------------------------

func _rule_sim(rule: String, reserve: float) -> Simulation:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]])
	sim.config.sanity.madness.exit_rule = rule
	if reserve > 0.0:
		_reserve_tower(sim, reserve)
	sim.state.gold = 1000
	_set_sanity(sim, 0.0)
	return sim


func test_buyout_restores_restore_sanity_when_the_cap_allows_it() -> void:
	var sim := _rule_sim("buyout", 10.0)
	var m := sim.config.sanity.madness
	assert_float(m.restore_sanity).is_less(sim.state.sanity_cap)
	assert_int(sim.buy_sanity()).is_equal(Simulation.CommandResult.OK)
	assert_float(sim.state.sanity).is_equal(m.restore_sanity)


func test_buyout_restores_only_up_to_a_lower_cap() -> void:
	var sim := _rule_sim("buyout", 0.0)
	var m := sim.config.sanity.madness
	var top := sim.config.sanity.max_sanity
	_reserve_tower(sim, top - m.restore_sanity / 2.0)
	_set_sanity(sim, 0.0)
	var cap := sim.state.sanity_cap
	assert_float(cap).is_equal_approx(m.restore_sanity / 2.0, 0.0001)
	sim.state.gold = m.buyout_cost
	assert_float(sim.restore_target()).is_equal_approx(cap, 0.0001)
	assert_int(sim.buy_sanity()).is_equal(Simulation.CommandResult.OK)
	assert_float(sim.state.sanity).is_equal_approx(cap, 0.0001)
	assert_int(sim.state.gold).is_equal(0)
	var ch := of_type(sim.drain_events(), T.SANITY_CHANGED)
	assert_int(ch.size()).is_equal(1)
	assert_str(ch[0].data["reason"]).is_equal("buyout")
	assert_float(ch[0].data["delta"]).is_equal_approx(cap, 0.0001)


func test_buyout_at_cap_zero_is_no_sanity_room_and_pays_nothing() -> void:
	var sim := _rule_sim("buyout", 0.0)
	_reserve_tower(sim, sim.config.sanity.max_sanity)
	sim.state.gold = 1000
	sim.drain_events()
	var log_size := sim.state.command_log.size()
	assert_float(sim.state.sanity_cap).is_equal(0.0)
	assert_int(sim.can_buy_sanity()).is_equal(Simulation.CommandResult.NO_SANITY_ROOM)
	assert_int(sim.buy_sanity()).is_equal(Simulation.CommandResult.NO_SANITY_ROOM)
	assert_int(sim.state.gold).is_equal(1000)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	assert_int(sim.state.command_log.size()).is_equal(log_size)
	assert_array(sim.drain_events()).is_empty()
	# Before NOT_ENOUGH_GOLD: no gold either still reads NO_SANITY_ROOM.
	sim.state.gold = 0
	assert_int(sim.can_buy_sanity()).is_equal(Simulation.CommandResult.NO_SANITY_ROOM)
	# After NOT_IN_MADNESS (state forced: at cap 0 the sim itself is always mad).
	sim.state.sanity_state = S.FRAYING
	assert_int(sim.can_buy_sanity()).is_equal(Simulation.CommandResult.NOT_IN_MADNESS)
	# After NO_BUYOUT.
	sim.state.sanity_state = S.MADNESS
	sim.config.sanity.madness.exit_rule = "permanent"
	assert_int(sim.can_buy_sanity()).is_equal(Simulation.CommandResult.NO_BUYOUT)


func test_auto_restore_restores_only_up_to_a_lower_cap() -> void:
	var sim := _rule_sim("auto_restore", 0.0)
	var m := sim.config.sanity.madness
	_reserve_tower(sim, sim.config.sanity.max_sanity - m.restore_sanity / 2.0)
	_set_sanity(sim, 0.0)
	var cap := sim.state.sanity_cap
	assert_float(sim.auto_restore_sanity()).is_equal_approx(cap, 0.0001)
	assert_float(sim.state.sanity).is_equal_approx(cap, 0.0001)


func test_auto_restore_at_cap_zero_does_nothing() -> void:
	var sim := _rule_sim("auto_restore", 0.0)
	_reserve_tower(sim, sim.config.sanity.max_sanity)
	sim.drain_events()
	assert_float(sim.auto_restore_sanity()).is_equal(0.0)
	assert_float(sim.state.sanity).is_equal(0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	assert_array(sim.drain_events()).is_empty()


# --- 17: determinism ---------------------------------------------------------------------

## Plays `commands` ([tick, name, ...]) on a fresh wave sim; "upgrade_at"/"sell_at" resolve
## the tower on a cell. Returns [event strings + final state line, command_log].
func _play(commands: Array, ticks: int) -> Array:
	var sim := wsim([[group("deep_one", 2, 0.5), group("shoggoth", 1, 0.5, 0.3)],
		[group("deep_one", 1)]], 2)
	sim.state.gold = 10000
	var out: Array[String] = []
	for tk in ticks:
		for c: Array in commands:
			if int(c[0]) == sim.state.tick:
				match c[1]:
					"build": sim.build_tower(c[2], c[3])
					"sell": sim.sell_tower(c[2])
					"upgrade": sim.upgrade_tower(c[2], c[3])
					"call_wave": sim.call_wave()
					"upgrade_at": sim.upgrade_tower(sim.state.tower_at[c[2]], c[3])
					"sell_at": sim.sell_tower(sim.state.tower_at[c[2]])
		sim.step()
		out.append_array(strings_of(sim.drain_events()))
	out.append("tick=%d sanity=%s cap=%s state=%d" % [sim.state.tick, sim.state.sanity,
		sim.state.sanity_cap, sim.state.sanity_state])
	return [out, sim.state.command_log.duplicate(true)]


func test_same_seed_and_reserve_command_log_replay_identically() -> void:
	var cmds := [[1, "build", SIGN, _cell(6)], [2, "build", NECRO, _cell(8)],
		[3, "upgrade_at", _cell(6), ""], [20, "sell_at", _cell(8)],
		[40, "build", NECRO, _cell(10)], [50, "call_wave"]]  # LT-27: sell/build by day
	var first := _play(cmds, 300)
	var replay := _play(first[1], 300)
	assert_array(replay[0]).is_equal(first[0])
	assert_array(replay[1]).is_equal(first[1])
	# The log really moved the cap three ways (build, upgrade, sell).
	var log: Array = first[1]
	assert_array(log.map(func(c: Array) -> String: return c[1])).is_equal(
		["build", "build", "upgrade", "sell", "build", "call_wave"])
	var caps: Array = first[0].filter(func(x: String) -> bool:
		return x.begins_with("SANITY_CAP_CHANGED"))
	assert_int(caps.size()).is_equal(5)
	assert_bool(caps.any(func(x: String) -> bool: return x.contains("sell"))).is_true()
	# Control: without the sell the run differs.
	var without := _play(cmds.filter(func(c: Array) -> bool: return c[1] != "sell_at"), 300)
	assert_bool(without[0] == first[0]).is_false()
