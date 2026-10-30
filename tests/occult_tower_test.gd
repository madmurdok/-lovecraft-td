class_name OccultTowerTest
extends TowerTestBase
## LT-11 occult towers L1 (GDD §6 Elder Sign, Necronomicon Reader; §5.3 drains): build/sell
## rules with the sanity cost, the Elder Sign aura and the Necronomicon cast. Balance numbers
## are read from config, never hard-coded.

const R := Simulation.CommandResult
const T := SimEvent.Type
const S := SimState.SanityState
const SIGN := "elder_sign"
const NECRO := "necronomicon_reader"


func _l1(sim: Simulation, def_id: String) -> TowerDef.Level:
	return sim.config.towers[def_id].levels[0]


func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	sim.drain_events()


func _casts(events: Array[SimEvent]) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in of_type(events, T.SANITY_CHANGED):
		if e.data["reason"] == "cast":
			out.append(e)
	return out


## Sim with a sign at TOWER; enemy `put` at `cells` 
func _sign_sim() -> Simulation:
	var sim := tsim()
	sim.state.gold = 1000
	build(sim, SIGN)
	sim.drain_events()
	return sim


# --- building and selling ---------------------------------------------------------

func test_occult_towers_are_buildable_with_gold_and_sanity_costs_from_config() -> void:
	for def_id: String in [SIGN, NECRO]:
		var sim := tsim()
		var def: TowerDef = sim.config.towers[def_id]
		assert_str(def.kind).is_equal("occult")
		var gold := sim.state.gold
		var sanity := sim.state.sanity
		assert_int(sim.can_build(def_id, TOWER)).is_equal(R.OK)
		assert_int(sim.build_tower(def_id, TOWER)).is_equal(R.OK)
		assert_int(sim.state.gold).is_equal(gold - def.cost)
		assert_float(sim.state.sanity).is_equal_approx(sanity - def.sanity_cost, 0.0001)


func test_elder_sign_build_emits_gold_then_sanity_build_event() -> void:
	var sim := tsim()
	var cost := sim.config.towers[SIGN].sanity_cost
	assert_float(cost).is_greater(0.0)
	var before := sim.state.sanity
	var id := build(sim, SIGN).id
	var ev := sim.drain_events()
	var types: Array = []
	for e in ev:
		types.append(e.type)
	assert_array(types).is_equal([T.TOWER_BUILT, T.GOLD_CHANGED, T.SANITY_CHANGED])
	assert_int(ev[2].id).is_equal(id)
	assert_str(ev[2].data["reason"]).is_equal("build")
	assert_float(ev[2].data["delta"]).is_equal_approx(-cost, 0.0001)
	assert_float(ev[2].data["sanity"]).is_equal_approx(before - cost, 0.0001)


func test_necronomicon_build_costs_no_sanity() -> void:
	var sim := tsim()
	var before := sim.state.sanity
	build(sim, NECRO)
	assert_float(sim.state.sanity).is_equal(before)
	assert_array(of_type(sim.drain_events(), T.SANITY_CHANGED)).is_empty()


func test_build_below_the_sanity_cost_succeeds_clamps_at_zero_and_enters_madness() -> void:
	var sim := tsim()
	var cost := sim.config.towers[SIGN].sanity_cost
	_set_sanity(sim, cost - 3.0)
	build(sim, SIGN)
	assert_float(sim.state.sanity).is_equal(0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	var ev := sim.drain_events()
	var ch := of_type(ev, T.SANITY_CHANGED)
	assert_int(ch.size()).is_equal(1)
	assert_float(ch[0].data["delta"]).is_equal_approx(-(cost - 3.0), 0.0001)
	var st := of_type(ev, T.SANITY_STATE_CHANGED)
	assert_int(st.size()).is_equal(1)
	assert_int(st[0].data["new"]).is_equal(S.MADNESS)


func test_build_at_zero_sanity_is_allowed_and_emits_no_sanity_event() -> void:
	var sim := tsim()
	_set_sanity(sim, 0.0)
	var gold := sim.state.gold
	assert_int(sim.build_tower(SIGN, TOWER)).is_equal(R.OK)
	assert_int(sim.state.gold).is_equal(gold - sim.config.towers[SIGN].cost)
	assert_float(sim.state.sanity).is_equal(0.0)
	assert_array(of_type(sim.drain_events(), T.SANITY_CHANGED)).is_empty()


func test_refused_occult_builds_change_nothing_sanity_included() -> void:
	var sim := tsim()
	for def_id: String in [SIGN, NECRO]:
		var cost: int = sim.config.towers[def_id].cost
		sim.state.gold = cost - 1
		sim.drain_events()
		var sanity := sim.state.sanity
		var next_id := sim.state.next_id
		var log_size := sim.state.command_log.size()
		assert_int(sim.build_tower(def_id, TOWER)).is_equal(R.NOT_ENOUGH_GOLD)
		assert_int(sim.build_tower(def_id, Vector2i(3, 0))).is_equal(R.NOT_BUILDABLE)
		assert_int(sim.state.gold).is_equal(cost - 1)
		assert_float(sim.state.sanity).is_equal(sanity)
		assert_int(sim.state.next_id).is_equal(next_id)
		assert_int(sim.state.command_log.size()).is_equal(log_size)
		assert_array(sim.drain_events()).is_empty()


func test_selling_an_occult_tower_refunds_gold_only() -> void:
	for def_id: String in [SIGN, NECRO]:
		var sim := tsim()
		var t := build(sim, def_id)
		sim.drain_events()
		var gold := sim.state.gold
		var sanity := sim.state.sanity
		var refund := sim.sell_refund(t)
		assert_int(refund).is_greater(0)
		assert_int(sim.sell_tower(t.id)).is_equal(R.OK)
		assert_int(sim.state.gold).is_equal(gold + refund)
		assert_float(sim.state.sanity).is_equal(sanity)
		assert_array(of_type(sim.drain_events(), T.SANITY_CHANGED)).is_empty()


# --- Elder Sign aura ---------------------------------------------------------------

func test_enemy_inside_the_sign_moves_slower_outside_at_full_speed() -> void:
	var sim := _sign_sim()
	var slow: float = _l1(sim, SIGN).effects["slow"]
	var inside := put(sim, "cultist", 7.0)
	var outside := put(sim, "cultist", 0.0)
	for e in [inside, outside]:
		e.base_units_per_tick = 1000
	var in0 := inside.distance
	var out0 := outside.distance
	sim.step()
	assert_int(inside.distance - in0).is_equal(roundi(1000 * (1.0 - slow)))
	assert_int(outside.distance - out0).is_equal(1000)
	assert_float(inside.speed_mult).is_equal_approx(1.0 - slow, 0.0001)
	assert_float(outside.speed_mult).is_equal(1.0)


func test_enemy_inside_takes_damage_after_armor_times_multiplier() -> void:
	var sim := _sign_sim()
	var mult: float = _l1(sim, SIGN).effects["damage_taken_multiplier"]
	var armor: float = sim.config.enemies["hybrid"].armor
	assert_float(armor).is_greater(0.0)
	var inside := put(sim, "hybrid", 7.0)
	var outside := put(sim, "hybrid", 0.0)
	sim.step()
	var hit := armor + 8.0
	assert_float(sim.apply_damage(inside.id, hit, "test")).is_equal_approx(8.0 * mult, 0.0001)
	assert_float(sim.apply_damage(outside.id, hit, "test")).is_equal_approx(8.0, 0.0001)
	# Armor >= hit: floored at 0, the multiplier does not revive it.
	assert_float(sim.apply_damage(inside.id, armor - 0.5, "test")).is_equal(0.0)
	assert_float(sim.apply_damage(inside.id, armor, "test")).is_equal(0.0)


func test_aura_boundary_is_inclusive() -> void:
	var sim := tsim()
	sim.state.gold = 1000
	# Enemy at path cell 7 is exactly 1.0 from the tower centre (7.5, 1.5).
	_l1(sim, SIGN).range_cells = 1.0
	build(sim, SIGN)
	var on_edge := put(sim, "cultist", 7.0)
	sim.step()
	assert_float(on_edge.damage_taken_mult).is_greater(1.0)
	var sim2 := tsim()
	sim2.state.gold = 1000
	_l1(sim2, SIGN).range_cells = 0.99
	build(sim2, SIGN)
	var past := put(sim2, "cultist", 7.0)
	sim2.step()
	assert_float(past.damage_taken_mult).is_equal(1.0)
	assert_float(past.speed_mult).is_equal(1.0)


func test_overlapping_signs_do_not_stack() -> void:
	var sim := tsim()
	sim.state.gold = 1000
	build(sim, SIGN, Vector2i(6, 1))
	build(sim, SIGN, Vector2i(7, 1))
	build(sim, SIGN, Vector2i(8, 1))
	var e := put(sim, "cultist", 7.0)
	sim.step()
	var l := _l1(sim, SIGN)
	assert_float(e.speed_mult).is_equal_approx(1.0 - l.effects["slow"], 0.0001)
	assert_float(e.damage_taken_mult).is_equal_approx(l.effects["damage_taken_multiplier"], 0.0001)


func test_strongest_overlapping_sign_wins_per_modifier() -> void:
	var sim := tsim()
	sim.state.gold = 1000
	var weak := build(sim, SIGN, Vector2i(6, 1))
	var strong := build(sim, SIGN, Vector2i(8, 1))
	strong.level = 1
	var l2: TowerDef.Level = sim.config.towers[SIGN].levels[1]
	l2.effects = {"slow": 0.5, "damage_taken_multiplier": 1.6}
	var e := put(sim, "cultist", 7.0)
	assert_int(sim.enemies_in_range(weak.cell, _l1(sim, SIGN).range_cells).size()).is_equal(1)
	sim.step()
	assert_float(e.speed_mult).is_equal_approx(0.5, 0.0001)
	assert_float(e.damage_taken_mult).is_equal_approx(1.6, 0.0001)


func test_aura_affects_fakes() -> void:
	var sim := _sign_sim()
	var f := put(sim, "cultist", 7.0, HUGE_HP, true)
	sim.step()
	assert_float(f.speed_mult).is_equal_approx(1.0 - _l1(sim, SIGN).effects["slow"], 0.0001)
	assert_float(f.damage_taken_mult).is_greater(1.0)


func test_modifiers_follow_membership_at_the_start_of_each_tick() -> void:
	# Walk an enemy through the sign: after every step both modifiers are set exactly when the
	# enemy was inside at the START of that tick (pre-movement), so entering and leaving each
	# show a 1-tick lag against the post-move position.
	var sim := _sign_sim()
	var l := _l1(sim, SIGN)
	var e := put(sim, "cultist", 4.0)
	e.base_units_per_tick = SimTime.UNITS_PER_CELL / 10  # 0.1 cell per tick
	var seen_in := 0
	var seen_out := 0
	var lag_ticks := 0
	for i in 100:
		var was_inside := sim.enemies_in_range(TOWER, l.range_cells).has(e)
		sim.step()
		var now_inside := sim.enemies_in_range(TOWER, l.range_cells).has(e)
		if was_inside:
			seen_in += 1
			assert_float(e.speed_mult).is_equal_approx(1.0 - l.effects["slow"], 0.0001)
			assert_float(e.damage_taken_mult).is_equal_approx(
					l.effects["damage_taken_multiplier"], 0.0001)
		else:
			seen_out += 1
			assert_float(e.speed_mult).is_equal(1.0)
			assert_float(e.damage_taken_mult).is_equal(1.0)
		if was_inside != now_inside:
			lag_ticks += 1
	assert_int(seen_in).is_greater(2)
	assert_int(seen_out).is_greater(2)
	assert_int(lag_ticks).is_equal(2)  # one entering, one leaving


func test_modifiers_clear_the_tick_after_the_sign_is_sold() -> void:
	var sim := _sign_sim()
	var e := put(sim, "cultist", 7.0)
	sim.step()
	assert_float(e.speed_mult).is_less(1.0)
	sim.sell_tower(sim.state.towers[0].id)
	sim.step()
	assert_float(e.speed_mult).is_equal(1.0)
	assert_float(e.damage_taken_mult).is_equal(1.0)


func test_elder_sign_never_fires() -> void:
	var sim := _sign_sim()
	put(sim, "cultist", 7.0)
	var ev := run(sim, 200)
	assert_array(of_type(ev, T.SHOT)).is_empty()
	assert_array(of_type(ev, T.SANITY_CHANGED)).is_empty()


# --- Necronomicon Reader -----------------------------------------------------------

func test_no_enemy_in_range_means_no_cast_and_no_cost_then_casts_the_tick_one_arrives() -> void:
	var sim := tsim()
	sim.state.gold = 1000
	build(sim, NECRO)
	sim.drain_events()
	var sanity := sim.state.sanity
	# Far beyond several fire intervals: the tower stays ready.
	var idle := run(sim, SimTime.ticks(_l1(sim, NECRO).fire_interval) * 2 + 3)
	assert_array(of_type(idle, T.SHOT)).is_empty()
	assert_array(of_type(idle, T.SANITY_CHANGED)).is_empty()
	assert_float(sim.state.sanity).is_equal(sanity)
	put(sim, "cultist", 7.0)
	sim.step()
	var ev := sim.drain_events()
	assert_array(shot_ticks(ev)).is_equal([sim.state.tick])
	assert_int(_casts(ev).size()).is_equal(1)


func test_an_enemy_out_of_range_causes_no_cast() -> void:
	var sim := tsim()
	sim.state.gold = 1000
	build(sim, NECRO)
	put(sim, "cultist", 0.0)
	sim.drain_events()
	var ev := run(sim, 10)
	assert_array(of_type(ev, T.SHOT)).is_empty()
	assert_array(_casts(ev)).is_empty()


func test_casts_repeat_every_fire_interval_and_each_costs_sanity_per_cast_once() -> void:
	var sim := tsim()
	sim.state.gold = 1000
	build(sim, NECRO)
	put(sim, "cultist", 7.0)
	sim.drain_events()
	var l := _l1(sim, NECRO)
	var n := SimTime.ticks(l.fire_interval)
	var start := sim.state.sanity
	var ev := run(sim, n * 2 + 1)
	assert_array(shot_ticks(ev)).is_equal([1, 1 + n, 1 + 2 * n])
	var casts := _casts(ev)
	assert_int(casts.size()).is_equal(3)
	for i in 3:
		assert_int(casts[i].tick).is_equal(1 + i * n)
		assert_int(casts[i].id).is_equal(sim.state.towers[0].id)
		assert_float(casts[i].data["delta"]).is_equal_approx(-l.sanity_per_cast, 0.0001)
	assert_float(sim.state.sanity).is_equal_approx(start - 3.0 * l.sanity_per_cast, 0.0001)


func test_a_cast_hitting_several_enemies_costs_sanity_per_cast_exactly_once() -> void:
	var sim := tsim()
	sim.state.gold = 1000
	build(sim, NECRO)
	var l := _l1(sim, NECRO)
	var a := put(sim, "cultist", 8.0, HUGE_HP)
	var b := put(sim, "cultist", 8.0 - 0.3, HUGE_HP)
	var c := put(sim, "cultist", 8.0 - 0.6, HUGE_HP)
	sim.drain_events()
	var start := sim.state.sanity
	sim.step()
	var ev := sim.drain_events()
	var shots := of_type(ev, T.SHOT)
	assert_int(shots.size()).is_equal(1)
	assert_int(shots[0].data["hits"].size()).is_greater_equal(3)
	for e in [a, b, c]:
		assert_float(e.hp).is_equal_approx(HUGE_HP - l.damage, 0.0001)
	var casts := _casts(ev)
	assert_int(casts.size()).is_equal(1)
	assert_float(casts[0].data["delta"]).is_equal_approx(-l.sanity_per_cast, 0.0001)
	assert_float(sim.state.sanity - start).is_equal_approx(-l.sanity_per_cast, 0.0001)


func test_blast_hits_every_enemy_within_the_radius_of_the_target() -> void:
	var sim := tsim()
	sim.state.gold = 1000
	build(sim, NECRO)
	var l := _l1(sim, NECRO)
	var radius: float = l.effects["aoe_radius"]
	var real := put(sim, "cultist", 8.0)  # furthest along: the target
	var fake := put(sim, "cultist", 8.0 - radius, HUGE_HP, true)  # exactly on the boundary
	var flyer := put(sim, "night_gaunt", 8.0 - 0.5)
	var beyond := put(sim, "cultist", 8.0 - radius - 0.01)
	sim.drain_events()
	sim.step()
	var shots := of_type(sim.drain_events(), T.SHOT)
	assert_int(shots.size()).is_equal(1)
	assert_int(shots[0].data["target"]).is_equal(real.id)
	assert_array(shots[0].data["hits"]).is_equal([real.id, fake.id, flyer.id])
	for e in [real, fake, flyer]:
		assert_float(e.hp).is_equal_approx(HUGE_HP - l.damage, 0.0001)
	assert_float(beyond.hp).is_equal(HUGE_HP)


func test_cast_event_order_shot_then_sanity_then_deaths_and_kill_pays_gold_only() -> void:
	var sim := tsim()
	sim.state.gold = 1000
	build(sim, NECRO)
	var l := _l1(sim, NECRO)
	var e := put(sim, "cultist", 7.0, l.damage)
	var reward: int = sim.config.enemies["cultist"].reward
	var gold := sim.state.gold
	var sanity := sim.state.sanity
	sim.drain_events()
	sim.step()
	var ev := sim.drain_events()
	var order: Array = []
	for x in ev:
		order.append(x.type)
	assert_array(order).is_equal([T.SHOT, T.SANITY_CHANGED, T.DIED, T.GOLD_CHANGED])
	assert_str(ev[3].data["reason"]).is_equal("kill")
	assert_int(sim.state.gold).is_equal(gold + reward)
	assert_float(sim.state.sanity).is_equal_approx(sanity - l.sanity_per_cast, 0.0001)
	assert_str(ev[2].data["source"]).is_equal(NECRO)
	assert_int(ev[2].id).is_equal(e.id)


func test_killing_a_fake_by_blast_pays_nothing() -> void:
	var sim := tsim()
	sim.state.gold = 1000
	build(sim, NECRO)
	put(sim, "cultist", 7.0, _l1(sim, NECRO).damage, true)
	var gold := sim.state.gold
	sim.step()
	assert_int(sim.state.gold).is_equal(gold)


func test_cast_at_zero_sanity_still_fires_and_deals_damage() -> void:
	var sim := tsim()
	# LT-13: at 0 the cast is astray; pin the roll to "real" so the test never depends on the seed.
	var m := sim.config.sanity.madness
	m.shot_real = 1.0
	m.shot_fake = 0.0
	m.shot_empty = 0.0
	sim.state.gold = 1000
	build(sim, NECRO)
	var e := put(sim, "cultist", 7.0)
	_set_sanity(sim, 0.0)
	sim.step()
	var ev := sim.drain_events()
	assert_int(of_type(ev, T.SHOT).size()).is_equal(1)
	assert_array(of_type(ev, T.SANITY_CHANGED)).is_empty()
	assert_float(sim.state.sanity).is_equal(0.0)
	assert_float(e.hp).is_less(HUGE_HP)


func test_cast_drives_sanity_into_madness_and_reports_the_state_change() -> void:
	var sim := tsim()
	sim.state.gold = 1000
	build(sim, NECRO)
	put(sim, "cultist", 7.0)
	_set_sanity(sim, _l1(sim, NECRO).sanity_per_cast)
	sim.step()
	var ev := sim.drain_events()
	assert_float(sim.state.sanity).is_equal(0.0)
	var st := of_type(ev, T.SANITY_STATE_CHANGED)
	assert_int(st.size()).is_equal(1)
	assert_int(st[0].data["new"]).is_equal(S.MADNESS)


func test_sign_boosts_blast_damage_after_armor() -> void:
	var sim := tsim()
	sim.state.gold = 1000
	build(sim, SIGN, Vector2i(6, 1))
	build(sim, NECRO)
	var mult: float = _l1(sim, SIGN).effects["damage_taken_multiplier"]
	var dmg := _l1(sim, NECRO).damage
	var armor: float = sim.config.enemies["hybrid"].armor
	var e := put(sim, "hybrid", 7.0)
	sim.step()
	assert_float(e.hp).is_equal_approx(HUGE_HP - (dmg - armor) * mult, 0.0001)


# --- determinism -------------------------------------------------------------------

func _occult_run() -> Array[String]:
	var sim := tsim()
	sim.state.gold = 1000
	build(sim, SIGN, Vector2i(5, 1))
	build(sim, NECRO, Vector2i(9, 1))
	var out: Array[String] = []
	for i in 600:
		if i % 40 == 0:
			sim.spawn_enemy("cultist", i % 80 == 40)
		sim.step()
		out.append_array(strings_of(sim.drain_events()))
	return out


func test_same_seed_and_commands_give_identical_events() -> void:
	var a := _occult_run()
	var b := _occult_run()
	assert_array(a).is_equal(b)
	var shots := 0
	for s in a:
		if s.begins_with("SHOT"):
			shots += 1
	assert_int(shots).is_greater(0)
