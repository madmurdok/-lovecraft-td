class_name SummoningCircleTest
extends TowerTestBase
## LT-52 Summoning Circle in the sim (docs/design/LT-46-tower-roster.md §2.2, §3 madness/lit
## row, §4 P10; owner Q3 "HP + contact damage"): every fire_interval, with fewer than
## summon_max of its units live, the circle summons one at its centre (leash range + 1,
## summon_hp / summon_dps / summon_speed, gone after summon_lifetime); the Byakhee branch's
## unit flies and holds flyers. At its maximum it stays ready (accepted choice D1), so a unit
## gone is replaced without waiting. Units deal summon_dps x madness.damage_multiplier while
## in MADNESS (read live) and summon_dps x occult_power_mult when the circle was lit at
## summon time. Kills credit "summoning_circle" (occult: no sanity regen). Selling the
## circle dismisses its units. The circle has no targeting. allies_test.gd pins the units.
## Circle at the default tower cell (7, 1), centre (7.5, 1.5).

const T := SimEvent.Type
const SC := "summoning_circle"
const CENTRE := Vector2(7.5, 1.5)
const EPS := 1e-4


# --- helpers ---------------------------------------------------------------------------

func _sim(enemy_edits := {}) -> Simulation:
	var sim := tsim(enemy_edits)
	sim.state.gold = 1000000
	return sim


## A sim whose beam lights the default tower cell (turn_t 0 holds the beam still).
func _lit_sim() -> Simulation:
	lit_beam = true
	var sim := tsim()
	lit_beam = false
	sim.state.gold = 1000000
	sim.config.economy.beam.turn_t = 0.0
	return sim


## The circle at TOWER set to `level` (0 = L1, 1 = L2, 2 = L3 `branch`).
func _circle(sim: Simulation, level := 0, branch := "") -> SimTower:
	var t := build(sim, SC)
	t.level = level
	t.branch = branch
	sim.drain_events()
	return t


func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	sim.drain_events()


func _ticks(ev: Array[SimEvent]) -> Array:
	return ev.map(func(e: SimEvent) -> int: return e.tick)


## Steps until `a` holds an enemy (at most `cap` steps); returns that tick.
func _until_holding(sim: Simulation, a: SimAlly, cap := 300) -> int:
	for i in cap:
		sim.step()
		if a.held_id >= 0:
			return sim.state.tick
	fail("unit %d held nothing within %d ticks" % [a.id, cap])
	return -1


## HP the enemy held by `a` loses over the next 30 ticks (one second).
func _damage_per_second(sim: Simulation, e: SimEnemy) -> float:
	var hp := e.hp
	run(sim, 30)
	return hp - e.hp


# --- summoning --------------------------------------------------------------------------------

func test_l1_summons_one_ghoul_at_its_centre_on_its_first_step() -> void:
	var sim := _sim()
	var t := _circle(sim)
	var ev := of_type(run(sim, 1), T.ALLY_SUMMONED)
	assert_int(ev.size()).is_equal(1)
	var a := sim.ally_by_id(ev[0].id)
	assert_object(a).is_not_null()
	assert_dict(ev[0].data).is_equal({"tower": t.id, "source": SC, "at": CENTRE, "hp": 120.0,
		"flying": false, "expires_tick": 1 + 600})
	assert_float(a.dps).is_equal(15.0)
	assert_float(a.speed).is_equal(1.5)
	assert_float(a.leash).is_equal(3.5)
	assert_that(a.home).is_equal(CENTRE)
	assert_int(t.cooldown_ticks).is_equal(SimTime.ticks(10.0))


## [level, branch, summon_max, interval ticks, hp, dps, speed, flying, leash] per §2.2.
const LEVELS := [
	[0, "", 1, 300, 120.0, 15.0, 1.5, false, 3.5],
	[1, "", 2, 270, 150.0, 18.0, 1.5, false, 4.0],
	[2, "a", 3, 240, 200.0, 20.0, 1.5, false, 4.0],
	[2, "b", 1, 300, 150.0, 45.0, 3.0, true, 5.0],
]


func test_each_level_keeps_up_to_summon_max_units_one_per_fire_interval() -> void:
	for row: Array in LEVELS:
		var sim := _sim()
		var t := _circle(sim, row[0], row[1])
		var label := "level %s%s" % [row[0], row[1]]
		var want: Array = []
		for k in int(row[2]):
			want.append(1 + k * int(row[3]))
		# Before the first unit expires (tick 601), with nothing to fight.
		var ev := of_type(run(sim, 600), T.ALLY_SUMMONED)
		assert_array(_ticks(ev)).override_failure_message(label).is_equal(want)
		var live := sim.allies_of(t.id)
		assert_int(live.size()).override_failure_message(label).is_equal(row[2])
		for a in live:
			assert_array([a.max_hp, a.dps, a.speed, a.flying, a.leash]) \
				.override_failure_message(label).is_equal(row.slice(4))


func test_at_its_maximum_the_circle_stays_ready_and_replaces_an_expired_unit_at_once() -> void:
	var sim := _sim()
	var t := _circle(sim)
	run(sim, 600)
	assert_int(t.cooldown_ticks).is_equal(0)
	var ev := run(sim, 1)  # tick 601: the first ghoul expires in slot 2
	var gone := of_type(ev, T.ALLY_GONE)
	assert_int(gone.size()).is_equal(1)
	assert_str(gone[0].data["reason"]).is_equal("expired")
	assert_array(_ticks(of_type(ev, T.ALLY_SUMMONED))).is_equal([601])


func test_a_killed_unit_is_replaced_on_the_next_tick_not_a_fire_interval_later() -> void:
	var sim := _sim()
	var t := _circle(sim)
	run(sim, 400)  # cooldown ran out at tick 301 with the ghoul still live
	assert_int(t.cooldown_ticks).is_equal(0)
	var first := sim.allies_of(t.id)[0]
	put(sim, "shoggoth", 7.0)  # contact 50/s: kills the ghoul in 2.4 s
	var killed := -1
	var summoned: Array = []
	for i in 120:
		var ev := run(sim, 1)
		for g in of_type(ev, T.ALLY_GONE):
			if g.id == first.id:
				assert_str(g.data["reason"]).is_equal("killed")
				killed = g.tick
		summoned.append_array(_ticks(of_type(ev, T.ALLY_SUMMONED)))
	assert_int(killed).override_failure_message("ghoul never killed").is_greater(400)
	assert_array(summoned).is_equal([killed + 1])


func test_byakhee_holds_a_flyer_and_an_l1_ghoul_never_does() -> void:
	var sim := _sim()
	_circle(sim, 2, "b")
	var gaunt := put(sim, "night_gaunt", 7.0)
	run(sim, 60)
	var a := sim.state.allies[0]
	assert_bool(a.flying).is_true()
	assert_int(a.held_id).is_equal(gaunt.id)
	assert_float(gaunt.hp).is_less(HUGE_HP)
	var sim1 := _sim()
	_circle(sim1)
	var gaunt1 := put(sim1, "night_gaunt", 7.0)
	run(sim1, 300)
	assert_int(sim1.state.allies[0].held_id).is_equal(-1)
	assert_float(gaunt1.hp).is_equal(HUGE_HP)


func test_selling_the_circle_dismisses_its_units() -> void:
	var sim := _sim()
	var t := _circle(sim, 1)
	run(sim, 271)
	var ids := sim.allies_of(t.id).map(func(a: SimAlly) -> int: return a.id)
	assert_int(ids.size()).is_equal(2)
	assert_int(sim.sell_tower(t.id)).is_equal(Simulation.CommandResult.OK)
	var gone := of_type(sim.drain_events(), T.ALLY_GONE)
	assert_array(gone.map(func(e: SimEvent) -> int: return e.id)).is_equal(ids)
	for g in gone:
		assert_dict(g.data).is_equal({"tower": t.id, "reason": "dismissed"})
	run(sim, 1)
	assert_int(sim.state.allies.size()).is_equal(0)


func test_the_circle_has_no_targeting_at_any_level() -> void:
	for row: Array in LEVELS:
		var sim := _sim()
		var t := _circle(sim, row[0], row[1])
		assert_bool(sim.has_targeting(t)).is_false()
		assert_int(sim.can_set_target_priority(t.id, "strongest")) \
			.is_equal(Simulation.CommandResult.NO_TARGETING)


# --- damage multipliers ------------------------------------------------------------------------

func test_a_circle_lit_at_summon_time_gives_its_unit_x0_7_for_life() -> void:
	var sim := _lit_sim()
	var reach := sim.config.economy.beam.reach_cells
	var pm := sim.config.economy.beam.occult_power_mult
	assert_float(pm).is_equal(0.7)
	var t := _circle(sim)
	run(sim, 1)
	assert_bool(t.lit).is_true()
	var a := sim.state.allies[0]
	# The beam leaves before the unit fights: it keeps the lit damage.
	sim.config.economy.beam.reach_cells = 0.0001
	var e := put(sim, "cultist", 7.0)
	_until_holding(sim, a)
	assert_bool(t.lit).is_false()
	assert_float(_damage_per_second(sim, e)).is_equal_approx(15.0 * pm, EPS)
	assert_float(reach).is_greater(1.0)


func test_a_circle_dark_at_summon_time_gives_full_damage_even_lit_later() -> void:
	var sim := _lit_sim()
	var reach := sim.config.economy.beam.reach_cells
	sim.config.economy.beam.reach_cells = 0.0001
	var t := _circle(sim)
	run(sim, 1)
	assert_bool(t.lit).is_false()
	var a := sim.state.allies[0]
	sim.config.economy.beam.reach_cells = reach
	var e := put(sim, "cultist", 7.0)
	_until_holding(sim, a)
	assert_bool(t.lit).is_true()
	assert_float(_damage_per_second(sim, e)).is_equal_approx(15.0, EPS)


func test_in_madness_units_deal_double_damage_read_live() -> void:
	var sim := _sim()
	var m := sim.config.sanity.madness
	assert_float(m.damage_multiplier).is_equal(2.0)
	# Isolate the unit's multiplier from the enemy buff (madness_buff_test pins that).
	m.enemy_damage_taken_multiplier = 1.0
	m.enemy_speed_multiplier = 1.0
	_circle(sim)
	run(sim, 1)  # the ghoul is summoned before madness
	var a := sim.state.allies[0]
	var e := put(sim, "hybrid", 7.0)  # armor 2
	_until_holding(sim, a)
	assert_float(_damage_per_second(sim, e)).is_equal_approx(15.0 - 2.0, EPS)
	_set_sanity(sim, 0.0)
	assert_int(sim.state.sanity_state).is_equal(SimState.SanityState.MADNESS)
	assert_float(_damage_per_second(sim, e)).is_equal_approx(15.0 * 2.0 - 2.0, EPS)
	_set_sanity(sim, 80.0)
	assert_float(_damage_per_second(sim, e)).is_equal_approx(15.0 - 2.0, EPS)


# --- kill credit -------------------------------------------------------------------------------

func test_kills_credit_summoning_circle_and_restore_no_sanity() -> void:
	var sim := _sim()
	_circle(sim)
	_set_sanity(sim, 50.0)
	var sanity := sim.state.sanity
	var e := put(sim, "cultist", 7.0, 60.0)
	var died := of_type(run(sim, 200), T.DIED)
	assert_int(died.size()).is_equal(1)
	assert_int(died[0].id).is_equal(e.id)
	assert_str(died[0].data["source"]).is_equal(SC)
	assert_float(sim.state.sanity).is_equal(sanity)
