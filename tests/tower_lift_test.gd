class_name TowerLiftTest
extends TowerTestBase
## LT-117 (docs/design/LT-117-tower-lift.md §1, §3, §7): the night-gaunt's tower_lift trait.
## Gaunts are parked on their straight flight line (`put`, speed 0); the wave gate reads
## state.wave_index, set by hand. Data: from_wave 6, drop_cells 2, disable_seconds 3.
##
## Two boards, both with the flight line on row 0 (S (0,0) -> L (8,0)) and the ground path
## around them through row 2:
## - OPEN: row 1 buildable, so the ring 2 around (3,0) has four free cells (a real draw).
## - NARROW: row 1 water, so every ring cell is on row 0: around (6,0) the ring 2 holds the
##   lighthouse (8,0), water (5,1) (7,1), path (6,2), off-board cells and one free cell (4,0).

const GAUNT := "night_gaunt"
const TOWER_DEF := "searchlight"  ## no shot: no COMBAT draw, no target noise
const SHOOTER := "rifleman"  ## hits flyers, range 3
const OPEN := [
	"S.......L",
	"#.......#",
	"#########",
]
const NARROW := [
	"S.......L",
	"#~~~~~~~#",
	"#########",
]
const OPEN_AT := Vector2i(3, 0)
const OPEN_RING2: Array[Vector2i] = [Vector2i(1, 0), Vector2i(5, 0), Vector2i(2, 1), Vector2i(4, 1)]
const NARROW_AT := Vector2i(6, 0)
const NARROW_DROP := Vector2i(4, 0)  ## the one free buildable cell 2 steps from (6,0)
const DISABLE_TICKS := 90  ## SimTime.ticks(3)

var _open_cfg: GameConfig
var _narrow_cfg: GameConfig


func _cfg(rows: Array) -> GameConfig:
	if rows == OPEN:
		if _open_cfg == null:
			_open_cfg = make_config(rows)
		return _open_cfg
	if _narrow_cfg == null:
		_narrow_cfg = make_config(rows)
	return _narrow_cfg


func _sim(rows: Array, wave := 6, run_seed := SEED) -> Simulation:
	var sim := Simulation.new(_cfg(rows), run_seed)
	sim.state.gold = 1000000
	sim.state.wave_index = wave
	return sim


func _gaunt(sim: Simulation, cell_x: int, fake := false) -> SimEnemy:
	return put(sim, GAUNT, float(cell_x), HUGE_HP, fake)


func _park(e: SimEnemy, cell_x: int) -> void:
	e.distance = cell_x * SimTime.UNITS_PER_CELL
	e.prev_distance = e.distance


func _lifts(events: Array[SimEvent]) -> Array[SimEvent]:
	return of_type(events, SimEvent.Type.TOWER_LIFTED)


func _lift_state(sim: Simulation) -> int:
	return sim.rng(SimRng.Stream.LIFT).state


func _states(sim: Simulation) -> Array[int]:
	var out: Array[int] = []
	for s: int in SimRng.Stream.values():
		out.append(sim.rng(s).state)
	return out


## The LIFT state after one randi_range(0, n - 1) from `sim`'s current LIFT state.
func _after_draw(sim: Simulation, n: int) -> int:
	var src := sim.rng(SimRng.Stream.LIFT)
	var ref := RandomNumberGenerator.new()
	ref.seed = src.seed
	ref.state = src.state
	ref.randi_range(0, n - 1)
	return ref.state


func _steps(sim: Simulation, a: Vector2i, b: Vector2i) -> int:
	return sim.state.map.grid.steps(a, b)


# --- §7.1, 11, 14: the lift itself -------------------------------------------------------------

## A real gaunt over a tower from from_wave on moves it to a free buildable cell exactly
## drop_cells steps away (one draw on LIFT, no other stream moves); tower_at and pos follow
## the cell; TOWER_LIFTED carries {from, to, by, ticks}.
func test_lift_moves_the_tower_to_a_free_cell_drop_cells_away() -> void:
	var seen := {}
	for s in range(1, 13):
		var sim := _sim(OPEN, 6, s)
		var t := build(sim, TOWER_DEF, OPEN_AT)
		sim.drain_events()
		var e := _gaunt(sim, OPEN_AT.x)
		var states := _states(sim)
		var want_lift := _after_draw(sim, OPEN_RING2.size())
		var lifts := _lifts(run(sim, 1))
		var msg := "seed %d" % s
		assert_int(lifts.size()).override_failure_message(msg).is_equal(1)
		var ev := lifts[0]
		assert_int(ev.id).is_equal(t.id)
		assert_int(ev.tick).is_equal(sim.state.tick)
		assert_array(OPEN_RING2).override_failure_message("%s: %s" % [msg, t.cell]).contains([t.cell])
		assert_int(_steps(sim, OPEN_AT, t.cell)).is_equal(2)
		assert_dict(ev.data).is_equal({"from": OPEN_AT, "to": t.cell, "by": e.id,
			"ticks": DISABLE_TICKS})
		assert_object(t.pos).is_equal(sim.state.map.grid.centre(t.cell))
		assert_object(t.centre()).is_equal(sim.state.map.grid.centre(t.cell))
		assert_int(sim.state.tower_at.get(t.cell, -1)).is_equal(t.id)
		assert_bool(sim.state.tower_at.has(OPEN_AT)).override_failure_message(msg).is_false()
		assert_object(sim.tower_by_id(t.id)).is_same(t)
		assert_int(_lift_state(sim)).override_failure_message(msg).is_equal(want_lift)
		var after := _states(sim)
		after[SimRng.Stream.LIFT] = states[SimRng.Stream.LIFT]
		assert_array(after).override_failure_message("%s: a stream other than LIFT moved" % msg) \
			.is_equal(states)
		seen[t.cell] = true
	assert_int(seen.size()).override_failure_message("drop cells over 12 seeds: %s" % [seen.keys()]) \
		.is_greater(1)


## §7.13 / §3: same seed and the same setup give byte-identical lifts.
func test_same_seed_same_lifts() -> void:
	var runs: Array = []
	for i in 2:
		var sim := _sim(OPEN, 6, 77)
		var a := build(sim, TOWER_DEF, OPEN_AT)
		var b := build(sim, TOWER_DEF, Vector2i(7, 0))
		_gaunt(sim, OPEN_AT.x)
		_gaunt(sim, 7)
		var ev := run(sim, 3)
		runs.append([strings_of(_lifts(ev)), a.cell, b.cell, _states(sim)])
	assert_int((runs[0][0] as Array).size()).is_equal(2)
	assert_array(runs[1]).is_equal(runs[0])


# --- §7.2: the wave gate -----------------------------------------------------------------------

## Below from_wave nothing moves, nothing is emitted, LIFT is not drawn and the gaunt keeps
## its lift for the gate wave.
func test_no_lift_before_from_wave() -> void:
	var sim := _sim(OPEN, 5)
	var t := build(sim, TOWER_DEF, OPEN_AT)
	var e := _gaunt(sim, OPEN_AT.x)
	var lift := _lift_state(sim)
	assert_array(_lifts(run(sim, 5))).is_empty()
	assert_object(t.cell).is_equal(OPEN_AT)
	assert_int(t.lift_ticks_left).is_equal(0)
	assert_bool(t.disabled).is_false()
	assert_int(_lift_state(sim)).is_equal(lift)
	sim.state.wave_index = 6
	var lifts := _lifts(run(sim, 1))
	assert_int(lifts.size()).is_equal(1)
	assert_int(lifts[0].data["by"]).is_equal(e.id)


# --- §7.3: fakes ------------------------------------------------------------------------------

## A fake gaunt never lifts and draws nothing (no stream moves, SANITY included); a real one
## over the same tower does.
func test_fake_gaunt_never_lifts() -> void:
	var sim := _sim(OPEN)
	var t := build(sim, TOWER_DEF, OPEN_AT)
	_gaunt(sim, OPEN_AT.x, true)
	var states := _states(sim)
	assert_array(_lifts(run(sim, 3))).is_empty()
	assert_object(t.cell).is_equal(OPEN_AT)
	assert_array(_states(sim)).is_equal(states)
	var real := _gaunt(sim, OPEN_AT.x)
	var lifts := _lifts(run(sim, 1))
	assert_int(lifts.size()).is_equal(1)
	assert_int(lifts[0].data["by"]).is_equal(real.id)


# --- §7.4, 5: once per gaunt, no juggling -------------------------------------------------------

## A gaunt that lifted passes over a second tower without lifting it; a fresh gaunt there does.
func test_one_lift_per_gaunt() -> void:
	var sim := _sim(NARROW)
	var a := build(sim, TOWER_DEF, NARROW_AT)
	var b := build(sim, TOWER_DEF, Vector2i(2, 0))
	var g1 := _gaunt(sim, NARROW_AT.x)
	assert_int(_lifts(run(sim, 1)).size()).is_equal(1)
	assert_object(a.cell).is_equal(NARROW_DROP)
	_park(g1, 2)
	assert_array(_lifts(run(sim, 3))).override_failure_message("lifted twice").is_empty()
	assert_object(b.cell).is_equal(Vector2i(2, 0))
	var g2 := _gaunt(sim, 2)
	var lifts := _lifts(run(sim, 1))
	assert_int(lifts.size()).is_equal(1)
	assert_int(lifts[0].id).is_equal(b.id)
	assert_int(lifts[0].data["by"]).is_equal(g2.id)


## A tower whose lift timer runs is not lifted again; the gaunt keeps its lift and takes the
## next tower on its line.
func test_a_tower_with_a_running_lift_timer_is_not_lifted_again() -> void:
	var sim := _sim(NARROW)
	var a := build(sim, TOWER_DEF, NARROW_AT)
	var b := build(sim, TOWER_DEF, Vector2i(2, 0))
	_gaunt(sim, NARROW_AT.x)
	assert_int(_lifts(run(sim, 1)).size()).is_equal(1)
	assert_object(a.cell).is_equal(NARROW_DROP)
	var g2 := _gaunt(sim, NARROW_DROP.x)  # over the lifted tower, its timer running
	assert_array(_lifts(run(sim, 2))).override_failure_message("juggled").is_empty()
	assert_object(a.cell).is_equal(NARROW_DROP)
	_park(g2, 2)
	var lifts := _lifts(run(sim, 1))
	assert_int(lifts.size()).is_equal(1)
	assert_int(lifts[0].id).is_equal(b.id)
	assert_int(lifts[0].data["by"]).is_equal(g2.id)


# --- §7.6, 7: the drop cell, ring fallback, the LIFT draw ---------------------------------------

## Around (6,0) the ring 2 has the lighthouse, water, path and off-board cells and one free
## buildable cell: every seed lands there. A one-cell ring leaves LIFT unchanged
## (randi_range(0, 0) draws nothing).
func test_the_drop_cell_is_free_and_buildable_and_a_one_cell_ring_draws_nothing() -> void:
	for s in range(1, 9):
		var sim := _sim(NARROW, 6, s)
		var t := build(sim, TOWER_DEF, NARROW_AT)
		_gaunt(sim, NARROW_AT.x)
		var states := _states(sim)
		var lifts := _lifts(run(sim, 1))
		assert_int(lifts.size()).is_equal(1)
		assert_object(t.cell).override_failure_message("seed %d" % s).is_equal(NARROW_DROP)
		assert_array(_states(sim)).override_failure_message("seed %d: a stream moved" % s) \
			.is_equal(states)


## No free cell at drop_cells: the next smaller ring (two cells here, so LIFT advances by one
## draw); the occupied ring-2 cell is never taken.
func test_a_full_ring_falls_back_to_the_next_smaller_ring() -> void:
	var seen := {}
	for s in range(1, 9):
		var sim := _sim(NARROW, 6, s)
		var t := build(sim, TOWER_DEF, NARROW_AT)
		var blocker := build(sim, TOWER_DEF, NARROW_DROP)
		_gaunt(sim, NARROW_AT.x)
		var want := _after_draw(sim, 2)
		var lifts := _lifts(run(sim, 1))
		assert_int(lifts.size()).is_equal(1)
		assert_array([Vector2i(5, 0), Vector2i(7, 0)]).override_failure_message(
			"seed %d: %s" % [s, t.cell]).contains([t.cell])
		assert_int(_steps(sim, NARROW_AT, t.cell)).is_equal(1)
		assert_object(blocker.cell).is_equal(NARROW_DROP)
		assert_int(sim.state.tower_at[NARROW_DROP]).is_equal(blocker.id)
		assert_int(_lift_state(sim)).override_failure_message("seed %d" % s).is_equal(want)
		seen[t.cell] = true
	assert_int(seen.size()).is_equal(2)


## No free cell on any ring: the tower stays, TOWER_LIFTED has to == from, still disabled.
func test_a_boxed_in_tower_stays_and_is_still_disabled() -> void:
	var sim := _sim(NARROW)
	var t := build(sim, TOWER_DEF, NARROW_AT)
	for c: Vector2i in [NARROW_DROP, Vector2i(5, 0), Vector2i(7, 0)]:
		build(sim, TOWER_DEF, c)
	var e := _gaunt(sim, NARROW_AT.x)
	var lifts := _lifts(run(sim, 1))
	assert_int(lifts.size()).is_equal(1)
	assert_dict(lifts[0].data).is_equal({"from": NARROW_AT, "to": NARROW_AT, "by": e.id,
		"ticks": DISABLE_TICKS})
	assert_object(t.cell).is_equal(NARROW_AT)
	assert_int(sim.state.tower_at[NARROW_AT]).is_equal(t.id)
	assert_bool(t.disabled).is_true()


# --- §7.8, 9, 10: the disable --------------------------------------------------------------

## Ticks (after each step) on which `t` is disabled, over `n` steps.
func _disabled_ticks(sim: Simulation, t: SimTower, n: int, on_step := Callable()) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		sim.step()
		if t.disabled:
			out.append(sim.state.tick)
		if on_step.is_valid():
			on_step.call()
	return out


## Off for exactly ticks(disable_seconds) from the lift tick: no shot in that window; the
## cooldown kept counting, so the first shot is the first enabled tick even when the lift
## came right after a shot.
func test_disabled_for_exactly_disable_seconds_and_the_cooldown_keeps_counting() -> void:
	var sim := _sim(NARROW, 5)
	var t := build(sim, SHOOTER, NARROW_AT)
	_gaunt(sim, NARROW_AT.x)
	var shot_at := -1
	for i in 200:
		var ev := run(sim, 1)
		if not of_type(ev, SimEvent.Type.SHOT).is_empty():
			shot_at = sim.state.tick
			break
	assert_int(shot_at).override_failure_message("the rifleman never shot").is_greater(0)
	assert_int(fire_ticks(SHOOTER)).is_less(DISABLE_TICKS)
	sim.state.wave_index = 6
	var lift_tick := sim.state.tick + 1
	var off: Array[int] = []
	var shots: Array[int] = []
	for i in DISABLE_TICKS + 5:
		var ev := run(sim, 1)
		if t.disabled:
			off.append(sim.state.tick)
		for s in of_type(ev, SimEvent.Type.SHOT):
			if s.id == t.id:
				shots.append(s.tick)
		if i == 0:
			assert_int(_lifts(ev).size()).is_equal(1)
	assert_object(t.cell).is_equal(NARROW_DROP)
	var want: Array[int] = []
	for k in DISABLE_TICKS:
		want.append(lift_tick + k)
	assert_array(off).is_equal(want)
	assert_array(shots).is_not_empty()
	assert_int(shots[0]).override_failure_message("shots %s" % [shots]) \
		.is_equal(lift_tick + DISABLE_TICKS)


## The gaunt's death does not end the disable.
func test_the_gaunts_death_does_not_end_the_disable() -> void:
	var sim := _sim(NARROW)
	var t := build(sim, TOWER_DEF, NARROW_AT)
	var e := _gaunt(sim, NARROW_AT.x)
	var lift_tick := sim.state.tick + 1
	var killed := [false]
	var off := _disabled_ticks(sim, t, DISABLE_TICKS + 5, func() -> void:
		if not killed[0]:
			sim.apply_damage(e.id, HUGE_HP * 10.0, "hit")
			killed[0] = true)
	assert_object(sim.enemy_by_id(e.id)).is_null()
	assert_int(off.size()).is_equal(DISABLE_TICKS)
	assert_int(off[0]).is_equal(lift_tick)
	assert_int(off[-1]).is_equal(lift_tick + DISABLE_TICKS - 1)


## Level, branch, spent, target priority, the sanity cap and the sell refund are unchanged.
func test_a_lift_keeps_the_towers_progress_and_refund() -> void:
	var sim := _sim(NARROW)
	var t := build(sim, SHOOTER, NARROW_AT)
	t.target_priority = "strong"
	var before := [t.id, t.level, t.branch, t.spent, t.target_priority, t.build_tick,
		sim.state.sanity_cap, sim.sell_refund(t)]
	sim.drain_events()
	_gaunt(sim, NARROW_AT.x)
	var ev := run(sim, 1)
	assert_int(_lifts(ev).size()).is_equal(1)
	assert_array(of_type(ev, SimEvent.Type.SANITY_CAP_CHANGED)).is_empty()
	assert_array([t.id, t.level, t.branch, t.spent, t.target_priority, t.build_tick,
		sim.state.sanity_cap, sim.sell_refund(t)]).is_equal(before)


# --- §7.12: two lifts in one tick ----------------------------------------------------------

## Lower gaunt id first, against the board it left: A takes (4,0), so B's ring 2 is full and
## B falls back to ring 1. (B first would take (4,0) and push A to ring 1.)
func test_two_lifts_in_one_tick_resolve_in_gaunt_id_order() -> void:
	for s in range(1, 5):
		var sim := _sim(NARROW, 6, s)
		var a := build(sim, TOWER_DEF, NARROW_AT)
		var b := build(sim, TOWER_DEF, Vector2i(2, 0))
		var g1 := _gaunt(sim, NARROW_AT.x)
		var g2 := _gaunt(sim, 2)
		assert_int(g2.id).is_greater(g1.id)
		var lifts := _lifts(run(sim, 1))
		assert_array(ids_of(lifts)).is_equal([a.id, b.id])
		assert_object(a.cell).is_equal(NARROW_DROP)
		assert_array([Vector2i(1, 0), Vector2i(3, 0)]).override_failure_message(
			"seed %d: %s" % [s, b.cell]).contains([b.cell])


# --- §7.16: hex topology ---------------------------------------------------------------------

## drop_candidates counts topology steps: on a HexGrid board the ring is the hex ring (axial
## distance), in grid.cells() order, not the square (Manhattan) one.
func test_hex_ring_uses_hex_steps() -> void:
	var r := ConfigReader.new("map.json")
	var m := MapDef.new()
	m.width = 7
	m.height = 5
	m.grid = HexGrid.new(7, 5)
	m._read_rows(r, ["S#####L", ".......", ".......", ".......", "......."])
	assert_array(r.errors).is_empty()
	var ctx := SimContext.new(real_config(), SEED)
	ctx.state.map = m
	var host := TraitHost.new(ctx, Callable())
	var t := SimTower.new()
	t.id = 99
	t.cell = m.grid.cell_of_text(3, 2)
	ctx.state.tower_at[t.cell] = t.id
	var occupied := m.grid.cell_of_text(3, 4)
	ctx.state.tower_at[occupied] = 98
	var want: Array[Vector2i] = []
	var manhattan: Array[Vector2i] = []
	for c in m.grid.cells():
		if not m.is_buildable(c) or ctx.state.tower_at.has(c):
			continue
		var dq := c.x - t.cell.x
		var dr := c.y - t.cell.y
		if absi(dq) + absi(dr) + absi(dq + dr) == 4:  # axial distance 2
			want.append(c)
		if absi(dq) + absi(dr) == 2:
			manhattan.append(c)
	assert_array(want).is_not_empty()
	assert_array(want).is_not_equal(manhattan)
	assert_array(host.drop_candidates(t, 2)).is_equal(want)


# --- §7.17: params -------------------------------------------------------------------------

func test_params_must_be_whole_and_at_least_one() -> void:
	var base := "enemies.night_gaunt.traits.tower_lift."
	for key: String in ["from_wave", "drop_cells"]:
		for bad: Variant in [0, 1.5, "2"]:
			var res := load_json_edit(ENEMIES, func(d: Dictionary) -> void:
				d["enemies"][GAUNT]["traits"]["tower_lift"][key] = bad)
			assert_rejected(res, ENEMIES, base + key)
	var sub := load_json_edit(ENEMIES, func(d: Dictionary) -> void:
		d["enemies"][GAUNT]["traits"]["tower_lift"]["disable_seconds"] = SimTime.DT * 0.5)
	assert_rejected(sub, ENEMIES, base + "disable_seconds", "at least one tick")
