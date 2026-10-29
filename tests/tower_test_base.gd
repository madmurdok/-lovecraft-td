class_name TowerTestBase
extends SimTestBase
## Shared fixtures for the LT-6 tower/gold suites: a 15x3 map with a straight path row
## (y = 0, x = 0..14, S at 0 and L at 14), a buildable row below it (y = 1) and water
## (y = 2). Enemies are parked with `put` (speed 0, huge HP) so geometry is exact.

const SEED := 11
const ROWS := [
	"S#############L",
	"...............",
	"~~~~~~~~~~~~~~~",
]
const TOWER := Vector2i(7, 1)  ## default tower cell; centre (7.5, 1.5)
const HUGE_HP := 100000.0


func tconfig(enemy_edits := {}, hp := -1) -> GameConfig:
	return make_config(ROWS, hp, enemy_edits)


func tsim(enemy_edits := {}, hp := -1) -> Simulation:
	return Simulation.new(tconfig(enemy_edits, hp), SEED)


## Spawns `def_id` parked `cells` cells along the route (cell centre of path cell
## `cells` when whole), speed 0, with `hp` hit points.
func put(sim: Simulation, def_id: String, cells: float, hp := HUGE_HP,
		fake := false) -> SimEnemy:
	var id := sim.spawn_enemy(def_id, fake)
	var e := sim.enemy_by_id(id)
	e.distance = roundi(cells * SimTime.UNITS_PER_CELL)
	e.prev_distance = e.distance
	e.base_units_per_tick = 0
	e.hp = hp
	e.max_hp = hp
	return e


func build(sim: Simulation, def_id: String, cell := TOWER) -> SimTower:
	var r := sim.build_tower(def_id, cell)
	assert_int(r).override_failure_message("build %s at %s -> %d" % [def_id, cell, r]) \
		.is_equal(Simulation.CommandResult.OK)
	return sim.tower_by_id(sim.state.tower_at[cell])


## Ticks (1-based) of the SHOT events in `events`.
func shot_ticks(events: Array[SimEvent]) -> Array[int]:
	var out: Array[int] = []
	for e in of_type(events, SimEvent.Type.SHOT):
		out.append(e.tick)
	return out


func fire_ticks(def_id: String) -> int:
	return SimTime.ticks(tconfig().towers[def_id].levels[0].fire_interval)
