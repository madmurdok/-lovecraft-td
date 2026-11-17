class_name LightShadowTest
extends TowerTestBase
## LT-70 (docs/design/LT-70-light-shadow.md §8): a Searchlight lights towers and enemies,
## an Elder Sign shadows towers, both at night only; light and shadow cancel. The default
## fixture (tsim, phase NONE) shines at night with a dark lighthouse beam, so only casters
## light or shadow a tower. Tower row y = 1: a tower at cell (x, 1) has its centre at
## (x + 0.5, 1.5), so two cells dx apart are dx cells apart. Searchlight L1 range 3, Elder
## Sign L1 range 2.5; a parked enemy at c cells sits at (c + 0.5, 0.5).

const T := SimEvent.Type
const P := SimState.Phase
const RIFLE := "rifleman"
const SL := "searchlight"
const SIGN := "elder_sign"
const NECRO := "necronomicon_reader"
const RS := "resonator"
const SK := "silver_key"
const SC := "summoning_circle"
const EPS := 1e-4


# --- helpers ---------------------------------------------------------------------------

func _sim() -> Simulation:
	var sim := tsim()
	sim.state.gold = 1000000
	return sim


## A still lighthouse beam that lights the default tower cell (phase NONE shines).
func _beam_sim() -> Simulation:
	lit_beam = true
	var sim := tsim()
	lit_beam = false
	sim.state.gold = 1000000
	sim.config.economy.beam.turn_t = 0.0
	return sim


func _day(sim: Simulation) -> void:
	sim.state.phase = P.BUILD


func _at(x: int) -> Vector2i:
	return Vector2i(x, 1)


func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	sim.drain_events()


func _mods(e: SimEnemy) -> Array:
	return [snappedf(e.speed_mult, 0.0001), snappedf(e.damage_taken_mult, 0.0001)]


func _want(speed: float, taken: float) -> Array:
	return [snappedf(speed, 0.0001), snappedf(taken, 0.0001)]


func _flags(t: SimTower) -> Array:
	return [t.lit, t.shadowed]


## Ticks between the first two SHOTs of a rifle at TOWER with a cultist parked at path 7.
func _rifle_gap(sim: Simulation) -> int:
	build(sim, RIFLE)
	put(sim, "cultist", 7.0)
	sim.drain_events()
	var ticks := shot_ticks(run(sim, 200))
	assert_int(ticks.size()).is_greater_equal(2)
	return ticks[1] - ticks[0]


## `n` SHOT events of a rifle at TOWER (sign at cell 9 when `shadowed`) at Lucid.
func _rifle_shots(sim: Simulation, shadowed: bool, ticks: int) -> Array[SimEvent]:
	var t := build(sim, RIFLE)
	if shadowed:
		build(sim, SIGN, _at(9))
	put(sim, "cultist", 7.0)
	sim.drain_events()
	assert_int(sim.state.sanity_state).is_equal(SimState.SanityState.LUCID)
	var shots := of_type(run(sim, ticks), T.SHOT)
	assert_bool(t.shadowed).is_equal(shadowed)
	return shots


# --- 1-3: where light and shadow reach --------------------------------------------------

func test_searchlight_lights_towers_in_range_inclusive_but_not_itself() -> void:
	var sim := _sim()
	var sl := build(sim, SL, _at(3))
	var edge := build(sim, RIFLE, _at(6))  # exactly range 3 from the Searchlight
	var out := build(sim, RIFLE, _at(7))  # range 4
	run(sim, 1)
	assert_array(_flags(edge)).is_equal([true, false])
	assert_array(_flags(out)).is_equal([false, false])
	assert_array(_flags(sl)).is_equal([false, false])
	# The boundary itself, centre to centre: inclusive, and not a hair beyond.
	var c := Vector2(3.5, 1.5)
	assert_bool(Simulation.in_cast_radius(c, 3.0, Vector2(6.5, 1.5))).is_true()
	assert_bool(Simulation.in_cast_radius(c, 3.0, Vector2(6.51, 1.5))).is_false()


func test_elder_sign_shadows_towers_in_range_and_other_signs_but_not_itself() -> void:
	var sim := _sim()
	var a := build(sim, SIGN, _at(7))
	var near := build(sim, RIFLE, _at(5))  # range 2
	var far := build(sim, RIFLE, _at(4))  # range 3 > 2.5
	run(sim, 1)
	assert_array(_flags(near)).is_equal([false, true])
	assert_array(_flags(far)).is_equal([false, false])
	assert_array(_flags(a)).is_equal([false, false])
	var b := build(sim, SIGN, _at(9))
	run(sim, 1)
	assert_array(_flags(a)).is_equal([false, true])
	assert_array(_flags(b)).is_equal([false, true])


func test_by_day_neither_light_nor_shadow_applies() -> void:
	var sim := _sim()
	build(sim, SL, _at(3))
	var lit := build(sim, RIFLE, _at(5))
	build(sim, SIGN, _at(9))
	var dark := build(sim, RIFLE, _at(7))
	run(sim, 1)
	assert_array(_flags(lit)).is_equal([true, false])  # night: the arms differ
	assert_array(_flags(dark)).is_equal([false, true])
	_day(sim)
	run(sim, 1)
	assert_array(_flags(lit)).is_equal([false, false])
	assert_array(_flags(dark)).is_equal([false, false])


# --- 4: cancel --------------------------------------------------------------------------

func test_light_and_shadow_cancel_for_a_searchlight_beam_and_flare() -> void:
	# Searchlight (range 2) and Elder Sign (range 2) both reach the rifle at cell 5.
	var sim := _sim()
	build(sim, SL, _at(3))
	var r := build(sim, RIFLE, _at(5))
	build(sim, SIGN, _at(7))
	run(sim, 1)
	assert_array(_flags(r)).is_equal([false, false])
	# Beam: lit alone, neither with a sign in range.
	var b := _beam_sim()
	var rb := build(b, RIFLE)
	run(b, 1)
	assert_array(_flags(rb)).is_equal([true, false])
	build(b, SIGN, _at(9))
	run(b, 1)
	assert_array(_flags(rb)).is_equal([false, false])
	# Flare: the whole map is lit while it burns; shadowed again once it is out.
	var f := _sim()
	var rf := build(f, RIFLE)
	build(f, SIGN, _at(9))
	run(f, 1)
	assert_array(_flags(rf)).is_equal([false, true])
	f.state.oil = 2 * f.config.economy.flare.cost_oil
	assert_int(f.fire_flare()).is_equal(Simulation.CommandResult.OK)
	run(f, 2)
	assert_array(_flags(rf)).is_equal([false, false])
	run(f, SimTime.ticks(f.flare_seconds()) + 2)
	assert_array(_flags(rf)).is_equal([false, true])


# --- 5: shadowed mundane ----------------------------------------------------------------

func test_a_shadowed_mundane_cooldown_is_the_interval_times_1_25() -> void:
	var fi: float = tconfig().towers[RIFLE].levels[0].fire_interval
	var plain := _rifle_gap(_sim())
	assert_int(plain).is_equal(maxi(1, SimTime.ticks(fi)))
	var sim := _sim()
	build(sim, SIGN, _at(9))
	var gap := _rifle_gap(sim)
	assert_float(sim.config.economy.shadow.mundane_fire_interval_mult).is_equal(1.25)
	assert_int(gap).is_equal(maxi(1, SimTime.ticks(fi * 1.25)))
	assert_int(gap).is_greater(plain)


func test_a_shadowed_mundane_misses_every_shot_when_the_add_is_1() -> void:
	var sim := _sim()
	sim.config.economy.shadow.mundane_miss_chance_add = 1.0
	var shots := _rifle_shots(sim, true, 150)
	assert_int(shots.size()).is_greater_equal(3)
	for s in shots:
		assert_bool(s.data["miss"]).is_true()
	# Control arm: the same rifle unshadowed never misses at Lucid.
	var plain := _rifle_shots(_sim(), false, 150)
	assert_int(plain.size()).is_greater_equal(3)
	for s in plain:
		assert_bool(s.data["miss"]).is_false()


func test_a_shadowed_shot_draws_combat_once_and_an_unshadowed_one_never_at_lucid() -> void:
	var shadowed := _sim()
	var before_s := shadowed.rng(SimRng.Stream.COMBAT).state
	var shots := _rifle_shots(shadowed, true, 150)
	assert_int(shots.size()).is_greater_equal(3)
	# The same stream, advanced by exactly one randf() per shot, lands on the same state.
	var ref := RandomNumberGenerator.new()
	ref.state = before_s
	for i in shots.size():
		ref.randf()
	assert_int(shadowed.rng(SimRng.Stream.COMBAT).state).is_equal(ref.state)
	var plain := _sim()
	var before_p := plain.rng(SimRng.Stream.COMBAT).state
	_rifle_shots(plain, false, 150)
	assert_int(plain.rng(SimRng.Stream.COMBAT).state).is_equal(before_p)


# --- 6: shadowed occult -----------------------------------------------------------------

func test_a_shadowed_necronomicon_deals_1_3_times_its_damage() -> void:
	for shadowed in [false, true]:
		var sim := _sim()
		build(sim, NECRO)
		if shadowed:
			build(sim, SIGN, _at(5))  # range 2; the cultist at 9 is out of its aura
		var dmg: float = sim.config.towers[NECRO].levels[0].damage
		var e := put(sim, "cultist", 9.0)
		sim.step()
		var pm := sim.config.economy.shadow.occult_power_mult if shadowed else 1.0
		assert_float(pm).is_equal(1.3 if shadowed else 1.0)
		assert_array(_mods(e)).is_equal([1.0, 1.0])
		assert_float(e.hp).override_failure_message("shadowed=%s" % shadowed) \
			.is_equal_approx(HUGE_HP - dmg * pm, 0.0001)


func test_a_shadowed_resonator_scales_its_sanity_scaled_damage_by_1_3() -> void:
	var out := []
	for shadowed in [false, true]:
		var sim := _sim()
		build(sim, RS)
		if shadowed:
			build(sim, SIGN, _at(9))  # range 2; the cultist at 6 is 3.2 away
		var e := put(sim, "cultist", 6.0)
		_set_sanity(sim, 40.0)
		var shots := of_type(run(sim, 1), T.SHOT)
		assert_int(shots.size()).is_equal(1)
		assert_array(_mods(e)).is_equal([1.0, 1.0])
		out.append(HUGE_HP - e.hp)
		if shadowed:
			var sf: float = shots[0].data["sanity_factor"]
			assert_float(HUGE_HP - e.hp).is_equal_approx(3.0 * sf * 1.3, 1e-6)
	assert_float(out[1]).is_equal_approx(out[0] * 1.3, 1e-6)


func test_a_shadowed_silver_key_banishes_1_3_times_the_cells() -> void:
	var moved := []
	for shadowed in [false, true]:
		var sim := _sim()
		build(sim, SK)
		if shadowed:
			build(sim, SIGN, _at(5))
		var e := put(sim, "cultist", 9.0, 400.0)
		var d0 := e.distance
		sim.step()
		moved.append(d0 - e.distance)
	var u := SimTime.UNITS_PER_CELL
	assert_int(moved[0]).is_equal(roundi(4.0 * u))
	assert_int(moved[1]).is_equal(roundi(4.0 * 1.3 * u))


func test_a_circle_unit_summoned_in_shadow_keeps_its_1_3_dps_after_the_sign_is_sold() -> void:
	var dps := []
	for shadowed in [false, true]:
		var sim := _sim()
		var circle := build(sim, SC)
		var es: SimTower = null
		if shadowed:
			es = build(sim, SIGN, _at(5))
		run(sim, 1)
		assert_bool(circle.shadowed).is_equal(shadowed)
		assert_int(sim.state.allies.size()).is_equal(1)
		var a: SimAlly = sim.state.allies[0]
		if shadowed:
			assert_int(sim.sell_tower(es.id)).is_equal(Simulation.CommandResult.OK)
		var e := put(sim, "cultist", 7.0)
		for i in 300:
			sim.step()
			if a.held_id >= 0:
				break
		assert_int(a.held_id).is_greater_equal(0)
		assert_bool(circle.shadowed).is_false()
		var hp := e.hp
		run(sim, 30)
		dps.append(hp - e.hp)
	assert_float(dps[0]).is_equal_approx(15.0, EPS)
	assert_float(dps[1]).is_equal_approx(15.0 * 1.3, EPS)


# --- 7-8: the sign's own aura, the Searchlight in shadow --------------------------------

func test_a_shadowed_elder_sign_aura_is_slow_0_26_and_taken_1_65() -> void:
	var sim := _sim()
	var a := build(sim, SIGN, _at(7))
	var b := build(sim, SIGN, _at(9))
	var e := put(sim, "cultist", 7.0)
	run(sim, 1)
	assert_array(_flags(a)).is_equal([false, true])
	assert_array(_flags(b)).is_equal([false, true])
	assert_array(_mods(e)).is_equal(_want(0.74, 1.65))  # the max of the two, not the sum
	# A lone sign is unshadowed: slow 0.2, taken 1.5 (the arms differ).
	var lone := _sim()
	build(lone, SIGN, _at(7))
	var e2 := put(lone, "cultist", 7.0)
	run(lone, 1)
	assert_array(_mods(e2)).is_equal(_want(0.8, 1.5))


func test_a_searchlight_in_shadow_keeps_its_slow_and_reveal() -> void:
	var sim := _sim()
	var sl := build(sim, SL, _at(3))
	build(sim, SIGN, _at(5))
	var e := put(sim, "cultist", 1.0)  # inside the Searchlight, 4.1 from the sign
	var fake := put(sim, "cultist", 1.0, HUGE_HP, true)
	run(sim, 1)
	assert_bool(sl.shadowed).is_true()
	assert_array(_mods(e)).is_equal(_want(0.7, 1.0))
	assert_bool(fake.revealed).is_true()


# --- 9: enemies lit by a Searchlight ----------------------------------------------------

func test_a_searchlight_lights_enemies_and_they_skip_the_madness_buff() -> void:
	var sim := _sim()
	build(sim, SL, _at(3))
	_set_sanity(sim, 0.0)
	assert_int(sim.state.sanity_state).is_equal(SimState.SanityState.MADNESS)
	var mad := sim.config.sanity.madness
	var real := put(sim, "cultist", 3.0)
	var fake := put(sim, "cultist", 3.0, HUGE_HP, true)
	var outside := put(sim, "cultist", 9.0)
	sim.step()
	for e: SimEnemy in [real, fake]:
		assert_bool(e.lit).is_true()
		# No madness buff and no flare x0.5: only the Searchlight's slow.
		assert_array(_mods(e)).is_equal(_want(0.7, 1.0))
	assert_bool(outside.lit).is_false()
	assert_array(_mods(outside)).is_equal([snappedf(mad.enemy_speed_multiplier, 0.0001),
		snappedf(mad.enemy_damage_taken_multiplier, 0.0001)])


func test_a_searchlight_does_not_light_enemies_by_day_and_a_sign_does_not_unlight_them() -> void:
	var sim := _sim()
	build(sim, SL, _at(3))
	var e := put(sim, "cultist", 3.0)
	run(sim, 1)
	assert_bool(e.lit).is_true()
	_day(sim)
	run(sim, 1)
	assert_bool(e.lit).is_false()
	var both := _sim()
	build(both, SL, _at(3))
	build(both, SIGN, _at(5))
	var e2 := put(both, "cultist", 3.0)  # in both radii
	run(both, 1)
	assert_bool(e2.lit).is_true()


# --- 10: events -------------------------------------------------------------------------

func test_tower_lit_fires_once_per_flip_of_either_flag_in_id_order() -> void:
	var sim := _sim()
	build(sim, SL, _at(3))
	var a := build(sim, RIFLE, _at(5))  # lit
	var s := build(sim, SIGN, _at(9))
	var b := build(sim, RIFLE, _at(7))  # shadowed
	sim.drain_events()
	var ev := of_type(run(sim, 1), T.TOWER_LIT)
	assert_array(ev.map(func(e: SimEvent) -> Array: return [e.id, e.data["lit"], e.data["shadowed"]])) \
		.is_equal([[a.id, true, false], [b.id, false, true]])
	assert_array(of_type(run(sim, 5), T.TOWER_LIT)).is_empty()
	assert_int(sim.sell_tower(s.id)).is_equal(Simulation.CommandResult.OK)
	sim.drain_events()
	var flip := of_type(run(sim, 1), T.TOWER_LIT)
	assert_array(flip.map(func(e: SimEvent) -> Array: return [e.id, e.data["lit"], e.data["shadowed"]])) \
		.is_equal([[b.id, false, false]])


# --- 11: no shadow block ----------------------------------------------------------------

func test_without_a_shadow_block_shadowed_towers_run_at_x1() -> void:
	var fi: float = tconfig().towers[RIFLE].levels[0].fire_interval
	var sim := _sim()
	sim.config.economy.shadow = null
	build(sim, SIGN, _at(9))
	var gap := _rifle_gap(sim)
	assert_int(gap).is_equal(maxi(1, SimTime.ticks(fi)))
	var t := sim.tower_by_id(sim.state.tower_at[TOWER])
	assert_bool(t.shadowed).is_true()  # the flag is still set; only the numbers are neutral
	var n := _sim()
	n.config.economy.shadow = null
	build(n, NECRO)
	build(n, SIGN, _at(5))
	var dmg: float = n.config.towers[NECRO].levels[0].damage
	var e := put(n, "cultist", 9.0)
	n.step()
	assert_float(e.hp).is_equal_approx(HUGE_HP - dmg, 0.0001)


# --- 15: determinism --------------------------------------------------------------------

func _log(seed_value: int) -> Array:
	var sim := Simulation.new(tconfig(), seed_value)
	sim.state.gold = 1000000
	build(sim, RIFLE)
	build(sim, SIGN, _at(9))
	put(sim, "cultist", 7.0)
	var out := []
	for e in run(sim, 200):
		out.append("%d %d %d %s" % [e.tick, e.type, e.id, str(e.data)])
	return out


func test_same_seed_elder_sign_over_a_rifle_gives_identical_event_logs() -> void:
	var a := _log(SEED)
	assert_int(a.size()).is_greater(5)
	assert_array(_log(SEED)).is_equal(a)
