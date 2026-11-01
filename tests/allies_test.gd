class_name AlliesTest
extends TowerTestBase
## LT-52 allied units in the sim (docs/design/LT-46-tower-roster.md §2.2 Summoning Circle,
## §4 P10, §7 Q3 "HP + contact damage"): a unit moves straight at `speed` toward the nearest
## enemy it may engage (live, not a revealed fake, ground only unless it flies, not held by
## another unit, within `leash` of its home), holds it on contact (<= 0.4 cells: the enemy
## does not move) and both trade damage: the unit deals max(0, dps - armor) per second, the
## enemy its contact_dps (default leak_damage x 10). The unit is gone at 0 HP or after its
## lifetime. Units are spawned here through the generic Simulation.spawn_ally (tower 0), so
## these tests do not depend on the circle's numbers; tests/summoning_circle_test.gd pins
## the tower. Map: TowerTestBase's 15x3 line; an enemy `put` at c cells is at (c + 0.5, 0.5),
## a unit's home is the default tower centre (7.5, 1.5).

const T := SimEvent.Type
const SRC := "summoning_circle"
const HOME := Vector2(7.5, 1.5)
const LEASH := 3.5  ## L1 circle: range 2.5 + 1
const CONTACT := 0.4
const WALK := 1000  ## units per tick = 1 cell/s
const EPS := 1e-6


# --- helpers ---------------------------------------------------------------------------

func _sim(enemy_edits := {}) -> Simulation:
	var sim := tsim(enemy_edits)
	sim.state.gold = 1000000
	return sim


## A ghoul-like unit (L1 numbers by default) with no tower; lifetime 0 = none.
func _ally(sim: Simulation, flying := false, lifetime := 0, at := HOME, hp := 120.0,
		dps := 15.0, speed := 1.5, leash := LEASH) -> SimAlly:
	var id := sim.spawn_ally(0, SRC, at, hp, dps, speed, flying, lifetime, leash)
	assert_int(id).is_greater(0)
	return sim.ally_by_id(id)


## `def_id` at `cells` walking toward the lighthouse at 1 cell/s.
func _walker(sim: Simulation, def_id: String, cells: float, hp := HUGE_HP,
		fake := false) -> SimEnemy:
	var e := put(sim, def_id, cells, hp, fake)
	e.base_units_per_tick = WALK
	return e


func _pos(e: SimEnemy) -> Vector2:
	return e.route.position_at(e.distance)


## Steps until `a` holds `e` (at most `cap` steps); returns that tick.
func _until_held(sim: Simulation, a: SimAlly, e: SimEnemy, cap := 300) -> int:
	for i in cap:
		sim.step()
		if a.held_id == e.id:
			return sim.state.tick
	fail("unit %d never held enemy %d within %d ticks" % [a.id, e.id, cap])
	return -1


## Steps until an event of `type` is emitted (at most `cap` steps); returns it (or null).
func _until_event(sim: Simulation, type: SimEvent.Type, cap := 600) -> SimEvent:
	for i in cap:
		sim.step()
		var ev := of_type(sim.drain_events(), type)
		if not ev.is_empty():
			return ev[0]
	fail("no %s within %d ticks" % [T.keys()[type], cap])
	return null


# --- spawn API --------------------------------------------------------------------------------

func test_spawn_ally_takes_the_next_entity_id_and_emits_ally_summoned() -> void:
	var sim := _sim()
	var before := sim.state.next_id
	var a := _ally(sim, false, 30)
	assert_int(a.id).is_equal(before)
	assert_int(sim.state.next_id).is_equal(before + 1)
	assert_int(sim.state.allies.size()).is_equal(1)
	var ev := of_type(sim.drain_events(), T.ALLY_SUMMONED)
	assert_int(ev.size()).is_equal(1)
	assert_int(ev[0].id).is_equal(a.id)
	assert_dict(ev[0].data).is_equal({"tower": 0, "source": SRC, "at": HOME, "hp": 120.0,
		"flying": false, "expires_tick": 30})
	assert_that(a.pos).is_equal(HOME)
	assert_float(a.hp).is_equal(120.0)


func test_spawn_ally_refuses_no_hp_and_a_finished_run() -> void:
	var sim := _sim()
	assert_int(sim.spawn_ally(0, SRC, HOME, 0.0, 15.0, 1.5, false, 0, LEASH)).is_equal(0)
	sim.state.outcome = SimState.Outcome.LOST
	assert_int(sim.spawn_ally(0, SRC, HOME, 120.0, 15.0, 1.5, false, 0, LEASH)).is_equal(0)
	assert_int(sim.state.allies.size()).is_equal(0)
	assert_int(of_type(sim.drain_events(), T.ALLY_SUMMONED).size()).is_equal(0)


func test_allies_of_lists_the_live_units_of_one_tower_in_id_order() -> void:
	var sim := _sim()
	var a := sim.spawn_ally(5, SRC, HOME, 10.0, 1.0, 1.0, false, 0, LEASH)
	sim.spawn_ally(6, SRC, HOME, 10.0, 1.0, 1.0, false, 0, LEASH)
	var c := sim.spawn_ally(5, SRC, HOME, 10.0, 1.0, 1.0, false, 0, LEASH)
	var mine := sim.allies_of(5)
	assert_array(mine.map(func(x: SimAlly) -> int: return x.id)).is_equal([a, c])
	assert_int(sim.allies_of(7).size()).is_equal(0)


# --- movement and contact ---------------------------------------------------------------------

func test_a_unit_moves_speed_per_tick_straight_toward_its_target() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var e := put(sim, "cultist", 5.0)
	sim.step()
	assert_that(a.prev_pos).is_equal(HOME)
	var want := HOME + (_pos(e) - HOME).normalized() * 1.5 / 30.0
	assert_float(a.pos.distance_to(want)).is_less(1e-4)
	assert_int(a.target_id).is_equal(e.id)
	assert_int(a.held_id).is_equal(-1)


func test_on_contact_the_unit_holds_its_enemy_and_the_enemy_stops() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var e := _walker(sim, "cultist", 2.0)
	var d_start := e.distance
	_until_held(sim, a, e)
	assert_int(e.distance).is_greater(d_start)
	assert_float(a.pos.distance_to(_pos(e))).is_less_equal(CONTACT + EPS)
	var d := e.distance
	run(sim, 30)
	assert_int(e.distance).override_failure_message("held enemy moved").is_equal(d)
	assert_int(a.held_id).is_equal(e.id)
	# Contact damage from the hold tick on: 31 ticks x cultist contact 10/s.
	assert_float(a.hp).is_equal_approx(120.0 - 31 * 10.0 / 30.0, 1e-4)


func test_a_ghoul_kills_a_cultist_in_four_seconds_and_survives() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var e := put(sim, "cultist", 7.0, 60.0)
	var n := _until_held(sim, a, e)
	# The trade starts on the contact tick.
	assert_float(e.hp).is_equal_approx(60.0 - 0.5, EPS)
	sim.drain_events()
	var died := _until_event(sim, T.DIED)
	assert_int(died.id).is_equal(e.id)
	assert_str(died.data["source"]).is_equal(SRC)
	assert_int(died.tick - n + 1).override_failure_message("hold ticks").is_equal(120)
	assert_bool(a.is_live()).is_true()
	# The unit strikes first each tick: the killing tick brings no contact damage.
	assert_float(a.hp).is_equal_approx(120.0 - 119 * 10.0 / 30.0, 1e-4)
	assert_int(a.held_id).is_equal(-1)


func test_armor_is_subtracted_once_per_second_not_per_tick() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var e := put(sim, "hybrid", 7.0)  # armor 2
	assert_float(e.def.armor).is_equal(2.0)
	_until_held(sim, a, e)
	var hp := e.hp
	run(sim, 30)
	assert_float(hp - e.hp).is_equal_approx(15.0 - 2.0, 1e-4)


func test_a_shoggoth_kills_the_unit_in_2_4_seconds_and_walks_on() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var e := _walker(sim, "shoggoth", 2.0)
	assert_float(e.def.contact_dps).is_equal(50.0)
	var n := _until_held(sim, a, e)
	var hp := e.hp
	sim.drain_events()
	var gone := _until_event(sim, T.ALLY_GONE)
	assert_int(gone.id).is_equal(a.id)
	assert_dict(gone.data).is_equal({"tower": 0, "reason": "killed", "by": e.id})
	# 120 HP / 50 per s = 2.4 s = 72 contact ticks (float rounding may need a 73rd).
	var ticks := gone.tick - n + 1
	assert_int(ticks).is_between(72, 73)
	assert_float(a.hp).is_equal(0.0)
	assert_bool(a.is_live()).is_false()
	# Meanwhile the shoggoth took (15 - armor 5) per second.
	assert_float(hp - e.hp).is_equal_approx(10.0 * (ticks - 1) / 30.0, 1e-3)
	var d := e.distance
	sim.step()
	assert_int(e.distance).override_failure_message("freed shoggoth moves").is_greater(d)
	assert_object(sim.ally_by_id(a.id)).is_null()


func test_contact_dps_on_the_enemy_overrides_the_default() -> void:
	for row: Array in [[60.0, 118.0], [0.0, 120.0]]:
		var sim := _sim({"cultist": {"contact_dps": row[0]}})
		var a := _ally(sim)
		var e := put(sim, "cultist", 7.0)
		_until_held(sim, a, e)
		assert_float(a.hp).override_failure_message("contact_dps %s" % row[0]) \
			.is_equal_approx(row[1], 1e-4)


# --- whom a unit engages ----------------------------------------------------------------------

func test_a_ground_unit_ignores_a_flyer_and_takes_a_farther_ground_enemy() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var gaunt := put(sim, "night_gaunt", 7.0)
	assert_bool(gaunt.def.flying).is_true()
	var c := put(sim, "cultist", 9.0)
	sim.step()
	assert_int(a.target_id).is_equal(c.id)
	run(sim, 90)
	assert_int(a.held_id).is_equal(c.id)
	assert_float(gaunt.hp).is_equal(HUGE_HP)


func test_a_ground_unit_never_engages_a_lone_flyer() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var gaunt := put(sim, "night_gaunt", 7.0)
	run(sim, 120)
	assert_int(a.held_id).is_equal(-1)
	assert_int(a.target_id).is_equal(-1)
	assert_that(a.pos).is_equal(HOME)
	assert_float(gaunt.hp).is_equal(HUGE_HP)


func test_a_flying_unit_holds_a_flyer() -> void:
	var sim := _sim()
	var a := _ally(sim, true)
	var gaunt := _walker(sim, "night_gaunt", 2.0)
	_until_held(sim, a, gaunt)
	var d := gaunt.distance
	var hp := gaunt.hp
	run(sim, 30)
	assert_int(gaunt.distance).is_equal(d)
	assert_float(hp - gaunt.hp).is_equal_approx(15.0, 1e-4)


func test_an_enemy_outside_the_leash_is_ignored() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var e := put(sim, "cultist", 3.0)  # (3.5, 0.5): 4.12 cells from home > 3.5
	run(sim, 60)
	assert_int(a.target_id).is_equal(-1)
	assert_that(a.pos).is_equal(HOME)
	assert_float(e.hp).is_equal(HUGE_HP)
	var f := put(sim, "cultist", 4.0)  # (4.5, 0.5): 3.16 cells, inside
	sim.step()
	assert_int(a.target_id).is_equal(f.id)


func test_with_no_target_left_the_unit_walks_back_home() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var e := put(sim, "cultist", 4.0, 60.0)
	_until_held(sim, a, e)
	assert_that(a.pos).is_not_equal(HOME)
	sim.apply_damage(e.id, 1000.0, "test")
	run(sim, 90)  # <= 3.2 cells back at 1.5 cells/s
	assert_int(a.target_id).is_equal(-1)
	assert_that(a.pos).is_equal(HOME)


func test_one_unit_holds_one_enemy_and_a_second_unit_does_not_share_it() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var b := _ally(sim)
	var e := put(sim, "cultist", 7.0)
	_until_held(sim, a, e)
	var hp := e.hp
	run(sim, 60)
	assert_int(a.held_id).is_equal(e.id)
	assert_int(b.held_id).is_equal(-1)
	assert_that(b.pos).is_equal(HOME)
	assert_float(hp - e.hp).override_failure_message("one unit's damage only") \
		.is_equal_approx(30.0, 1e-4)


func test_two_units_hold_two_enemies_one_each() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var b := _ally(sim)
	var e := put(sim, "cultist", 7.0)
	var f := put(sim, "cultist", 8.0)
	run(sim, 90)
	assert_array([a.held_id, b.held_id]).contains_exactly_in_any_order([e.id, f.id])


func test_a_revealed_fake_is_never_engaged() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var e := put(sim, "cultist", 7.0, HUGE_HP, true)
	e.revealed = true
	run(sim, 90)
	assert_int(a.target_id).is_equal(-1)
	assert_int(a.held_id).is_equal(-1)
	assert_that(a.pos).is_equal(HOME)
	assert_float(a.hp).is_equal(120.0)


func test_an_unrevealed_fake_is_engaged_and_hits_back() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var e := put(sim, "cultist", 7.0, HUGE_HP, true)
	_until_held(sim, a, e)
	run(sim, 29)
	assert_float(a.hp).is_equal_approx(110.0, 1e-4)
	assert_float(HUGE_HP - e.hp).is_equal_approx(15.0, 1e-4)


# --- what ends a hold -------------------------------------------------------------------------

## LT-52 review LOW-1: a held enemy pushed back in slot 5 of tick N gets no trade that tick
## and walks again on tick N+1 (the hold is dropped in slot 2, not one tick later).
func test_a_push_back_frees_the_held_enemy_at_once() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var e := _walker(sim, "cultist", 2.0, 400.0)
	_until_held(sim, a, e)
	var gate_cell := Vector2i(floori(_pos(e).x), 1)
	build(sim, "silver_key", gate_cell)
	var d := e.distance
	var hp := e.hp
	var ally_hp := a.hp
	var ev := run(sim, 1)  # tick N: the gate banishes it 4 cells back in slot 5
	assert_int(of_type(ev, T.SHOT).size()).is_equal(1)
	assert_int(e.distance).is_less(d)
	assert_float(e.hp).override_failure_message("no unit hit after the push").is_equal(hp)
	assert_float(a.hp).override_failure_message("no contact after the push").is_equal(ally_hp)
	var pushed := e.distance
	sim.step()  # tick N+1
	assert_int(e.distance).override_failure_message("still frozen on N+1").is_greater(pushed)
	assert_int(a.held_id).is_equal(-1)


## LT-52 review LOW-2: a held fake revealed by a Searchlight aura (slot 2) is let go that
## tick: it walks, no trade, and the unit never takes it again.
func test_a_held_fake_revealed_by_a_searchlight_is_released() -> void:
	var sim := _sim()
	var a := _ally(sim)
	var e := _walker(sim, "cultist", 2.0, HUGE_HP, true)
	_until_held(sim, a, e)
	build(sim, "searchlight", Vector2i(floori(_pos(e).x), 1))
	var d := e.distance
	var ally_hp := a.hp
	var hp := e.hp
	sim.step()
	assert_bool(e.revealed).is_true()
	assert_int(a.held_id).is_equal(-1)
	assert_int(e.distance).override_failure_message("revealed fake still held").is_greater(d)
	assert_float(a.hp).is_equal(ally_hp)
	assert_float(e.hp).is_equal(hp)
	for i in 60:
		sim.step()
		assert_int(a.held_id).is_equal(-1)
		assert_int(a.target_id).is_not_equal(e.id)


# --- lifetime ---------------------------------------------------------------------------------

func test_a_unit_expires_after_its_lifetime() -> void:
	var sim := _sim()
	var a := _ally(sim, false, 30)
	assert_int(of_type(run(sim, 29), T.ALLY_GONE).size()).is_equal(0)
	assert_bool(a.is_live()).is_true()
	var ev := of_type(run(sim, 1), T.ALLY_GONE)
	assert_int(ev.size()).is_equal(1)
	assert_int(ev[0].tick).is_equal(30)
	assert_int(ev[0].id).is_equal(a.id)
	assert_dict(ev[0].data).is_equal({"tower": 0, "reason": "expired"})
	assert_object(sim.ally_by_id(a.id)).is_null()


func test_an_expired_unit_lets_its_enemy_walk_on() -> void:
	var sim := _sim()
	var e := put(sim, "cultist", 7.0)
	var a := _ally(sim, false, 60)
	_until_held(sim, a, e)
	e.base_units_per_tick = WALK
	run_to(sim, 59)
	var d := e.distance
	run(sim, 1)
	assert_bool(a.is_live()).is_false()
	assert_int(e.distance).is_greater(d)


func test_a_unit_without_a_lifetime_never_expires() -> void:
	var sim := _sim()
	var a := _ally(sim, false, 0)
	assert_int(of_type(run(sim, 900), T.ALLY_GONE).size()).is_equal(0)
	assert_bool(a.is_live()).is_true()
