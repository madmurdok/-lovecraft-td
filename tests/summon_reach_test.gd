class_name SummonReachTest
extends TowerTestBase
## LT-103 owner Q2: the optional effect keys summon_contact (how close a unit holds an enemy)
## and summon_leash (whom it engages, cells from its summon spot). Absent, they are today's
## constants: AllySystem.ALLY_CONTACT (0.4) and range + 1; set, the circle's units use them
## (Level.summon_contact/summon_leash -> spawn_ally -> AllySystem._holds, move_allies).
## Map: TowerTestBase's 15x3 line; tower and unit home at (7.5, 1.5).

const SC := "summoning_circle"
const HOME := Vector2(7.5, 1.5)


func _sim() -> Simulation:
	var sim := tsim()
	sim.state.gold = 1000000
	return sim


## A unit at HOME with `contact` (cells), speed 1.5 cells/s, leash 5.
func _ally(sim: Simulation, contact: float) -> SimAlly:
	var id := sim.spawn_ally(0, SC, HOME, 120.0, 15.0, 1.5, false, 0, 5.0, contact)
	assert_int(id).is_greater(0)
	return sim.ally_by_id(id)


# --- Level -------------------------------------------------------------------------------

func test_absent_keys_are_todays_constants() -> void:
	var l := TowerDef.Level.new()
	l.range_cells = 2.5
	l.effects = {"summon_max": 1.0}
	assert_float(AllySystem.ALLY_CONTACT).is_equal(0.4)
	assert_float(l.summon_contact()).is_equal(0.4)
	assert_float(l.summon_leash()).is_equal(3.5)


func test_set_keys_are_used() -> void:
	var l := TowerDef.Level.new()
	l.range_cells = 2.5
	l.effects = {"summon_max": 1.0, "summon_contact": 1.2, "summon_leash": 6.0}
	assert_float(l.summon_contact()).is_equal(1.2)
	assert_float(l.summon_leash()).is_equal(6.0)


# --- circle -> unit ------------------------------------------------------------------------

func test_a_circle_gives_its_unit_the_level_contact_and_leash() -> void:
	var sim := _sim()
	var t := build(sim, SC)
	t.stats().effects["summon_contact"] = 1.2
	t.stats().effects["summon_leash"] = 6.0
	sim.drain_events()
	var ev := of_type(run(sim, 1), SimEvent.Type.ALLY_SUMMONED)
	assert_int(ev.size()).is_equal(1)
	var a := sim.ally_by_id(ev[0].id)
	assert_float(a.contact).is_equal(1.2)
	assert_float(a.leash).is_equal(6.0)


func test_a_circle_without_the_keys_gives_todays_contact_and_leash() -> void:
	var sim := _sim()
	var t := build(sim, SC)
	sim.drain_events()
	var ev := of_type(run(sim, 1), SimEvent.Type.ALLY_SUMMONED)
	assert_int(ev.size()).is_equal(1)
	var a := sim.ally_by_id(ev[0].id)
	assert_float(a.contact).is_equal(AllySystem.ALLY_CONTACT)
	assert_float(a.leash).is_equal(t.stats().range_cells + 1.0)


# --- AllySystem ------------------------------------------------------------------------------

## move_allies: a unit with contact 1.5 holds an enemy 1 cell away on its first move; one
## with the default 0.4 has to walk most of the way first.
func test_move_allies_holds_within_the_units_contact() -> void:
	var sim := _sim()
	var wide := _ally(sim, 1.5)
	var e := put(sim, "cultist", 7.0)  # (7.5, 0.5): 1 cell from HOME
	sim.step()
	assert_int(wide.held_id).is_equal(e.id)
	var sim2 := _sim()
	var narrow := _ally(sim2, AllySystem.ALLY_CONTACT)
	put(sim2, "cultist", 7.0)
	sim2.step()
	assert_int(narrow.held_id).is_equal(-1)


## _holds: a holding unit stays where it took the hold while its enemy is within its
## contact; with the 0.4 check it would let go each tick and step toward the enemy.
func test_a_holding_unit_keeps_its_hold_within_its_contact_and_does_not_move() -> void:
	var sim := _sim()
	var a := _ally(sim, 1.5)
	var e := put(sim, "cultist", 7.0)
	sim.step()
	assert_int(a.held_id).is_equal(e.id)
	var held_at := a.pos
	assert_float(held_at.distance_to(e.route.position_at(e.distance))).is_greater(0.4)
	for i in 10:
		sim.step()
		assert_int(a.held_id).is_equal(e.id)
		assert_that(a.pos).override_failure_message("tick %d: unit moved" % sim.state.tick) \
			.is_equal(held_at)
