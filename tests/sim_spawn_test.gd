class_name SimSpawnTest
extends TowerTestBase
## LT-83 (B8 of LT-80, docs/design/LT-80-sim-split.md section 7): SpawnSystem owns the enemies
## (enter, march, leak, compact), the pack queue and the fakes' dissolve; SimContext.next_id()
## is the one allocator of entity ids. Pins them standalone (a SimContext, no Simulation), the
## shared id sequence, the facade forwarders and the compact hook. The overall check stays the
## golden digest. Map: TowerTestBase ROWS (route length 14 cells, enemies enter at distance 0).

const T := SimEvent.Type
const SC := "summoning_circle"

var _ctx: SimContext
var _spawn: SpawnSystem
## What the compact hook saw: state.enemies.size() at each call.
var _compact_calls: Array = []


## Records the calls the facade would forward to it.
class SpySpawn:
	extends SpawnSystem
	var calls: Array = []

	func spawn_enemy(def_id: String, is_fake := false, _route_id := "") -> int:
		calls.append(["spawn_enemy", def_id, is_fake])
		return 4242

	func has_queued_real_members() -> bool:
		calls.append(["has_queued_real_members"])
		return true

	func dissolve_fakes(reason: String) -> void:
		calls.append(["dissolve_fakes", reason])

	func push_back(e: SimEnemy, cells: float) -> void:
		calls.append(["push_back", e, cells])


func before_test() -> void:
	_ctx = SimContext.new(tconfig(), SEED)
	_ctx.state.map = _ctx.config.map
	_ctx.state.lighthouse_hp = _ctx.config.economy.lighthouse_hp
	_spawn = SpawnSystem.new(_ctx)
	_spawn.set_trait_host(TraitHost.new(_ctx, _spawn.queue_pack_member))  # LT-106, like the facade
	_compact_calls = []
	_spawn.set_ally_compact(func() -> void: _compact_calls.append(_ctx.state.enemies.size()))


func _types(events: Array[SimEvent]) -> Array:
	return events.map(func(e: SimEvent) -> int: return e.type)


func _drain() -> Array[SimEvent]:
	var out := _ctx.events.duplicate()
	_ctx.events.clear()
	return out


## The stream's draw sequence a fresh run with SEED would see (same seeding as SimRng).
func _fresh(stream: SimRng.Stream) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = SEED * SimRng.STREAM_SEED_STRIDE + int(stream)
	return g


func _enemy(id: int) -> SimEnemy:
	for e in _ctx.state.enemies:
		if e.id == id:
			return e
	return null


## The ticks a deep_one pack member k waits after the first one.
func _spacing() -> int:
	return SimTime.ticks(float(_ctx.config.enemies["deep_one"].traits["pack"]["spacing_s"]))


func _pack_count(stream: SimRng.Stream) -> int:
	var p: Dictionary = _ctx.config.enemies["deep_one"].traits["pack"]
	return _fresh(stream).randi_range(int(p["min"]), int(p["max"]))


# --- ctx.next_id(): the one allocator --------------------------------------------------------

func test_next_id_returns_the_current_counter_and_then_advances_it() -> void:
	assert_int(_ctx.state.next_id).is_equal(1)
	assert_int(_ctx.next_id()).is_equal(1)
	assert_int(_ctx.state.next_id).is_equal(2)
	_ctx.state.next_id = 40
	assert_int(_ctx.next_id()).is_equal(40)
	assert_int(_ctx.next_id()).is_equal(41)
	assert_int(_ctx.state.next_id).is_equal(42)


## One fixed scenario through the facade, in the order the facade calls the allocator: a
## tower, an enemy, an ally, a pack whose later members enter between an ally summon and
## another tower. The [event type, id] pairs are in emit order; the list was printed by
## running the scenario on commit ad594fd (no hand-written ids).
func _scenario_ids() -> Array:
	var sim := tsim()
	sim.state.gold = 100000
	build(sim, "rifleman", Vector2i(2, 1))
	sim.spawn_enemy("hybrid")
	sim.spawn_ally(0, SC, Vector2(5.5, 1.5), 50.0, 5.0, 1.0, false, 0, 2.0)
	sim.spawn_enemy("deep_one")
	for i in _spacing():
		sim.step()
	sim.spawn_ally(0, SC, Vector2(6.5, 1.5), 50.0, 5.0, 1.0, false, 0, 2.0)
	for i in _spacing():
		sim.step()
	build(sim, "rifleman", Vector2i(4, 1))
	for i in 4 * _spacing():
		sim.step()
	var ids: Array = []
	for ev in sim.drain_events():
		if ev.type in [T.TOWER_BUILT, T.SPAWNED, T.ALLY_SUMMONED]:
			ids.append([ev.type, ev.id])
	return ids


const SCENARIO_IDS := [
	[T.TOWER_BUILT, 1], [T.SPAWNED, 2], [T.ALLY_SUMMONED, 3], [T.SPAWNED, 4], [T.SPAWNED, 5],
	[T.ALLY_SUMMONED, 6], [T.SPAWNED, 7], [T.TOWER_BUILT, 8], [T.SPAWNED, 9], [T.SPAWNED, 10],
	[T.SPAWNED, 11]]


func test_towers_allies_and_enemies_draw_ids_from_one_shared_sequence() -> void:
	var ids := _scenario_ids()
	assert_array(ids).is_equal(SCENARIO_IDS)
	# one sequence: the ids are exactly 1..n in emit order, no gap and no repeat
	assert_array(ids.map(func(p: Array) -> int: return p[1])).is_equal(range(1, ids.size() + 1))


func test_a_summoning_circle_ally_and_the_enemies_share_the_counter_through_the_facade() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	var t := build(sim, SC)
	assert_int(t.id).is_equal(1)
	var e := put(sim, "hybrid", 3.0)
	assert_int(e.id).is_equal(2)
	var a := sim.ally_by_id(sim.spawn_ally(t.id, SC, t.centre(), 50.0, 5.0, 1.0, false, 0, 2.0))
	assert_int(a.id).is_equal(3)
	assert_int(sim.state.next_id).is_equal(4)


# --- SpawnSystem standalone: spawn_enemy ---------------------------------------------------------

func test_spawn_enemy_enters_one_enemy_at_the_route_start_with_a_spawned_event() -> void:
	var id := _spawn.spawn_enemy("hybrid")
	assert_int(id).is_equal(1)
	var e := _enemy(id)
	var def: EnemyDef = _ctx.config.enemies["hybrid"]
	assert_object(e).is_not_null()
	assert_int(e.distance).is_equal(0)
	assert_float(e.hp).is_equal(float(def.hp))
	assert_float(e.max_hp).is_equal(float(def.hp))
	assert_bool(e.is_fake).is_false()
	assert_int(e.pack_of).is_equal(0)
	assert_int(e.spawn_tick).is_equal(_ctx.state.tick)
	assert_int(e.base_units_per_tick).is_equal(SimTime.units_per_tick(def.speed))
	var ev := _drain()
	assert_array(_types(ev)).is_equal([T.SPAWNED])
	assert_int(ev[0].id).is_equal(id)
	assert_dict(ev[0].data).is_equal({"def": "hybrid"})
	assert_bool(_spawn.has_queued_real_members()).is_false()


func test_a_flyer_takes_the_straight_route_and_a_walker_the_path() -> void:
	var walker := _enemy(_spawn.spawn_enemy("hybrid"))
	var flyer := _enemy(_spawn.spawn_enemy("night_gaunt"))
	assert_bool(flyer.def.flying).is_true()
	assert_bool(flyer.route != walker.route).is_true()
	assert_int(flyer.route.length).is_greater(0)


func test_spawn_enemy_returns_zero_and_changes_nothing_for_an_unknown_def_or_a_set_outcome() -> void:
	var r := {"v": -1}
	await assert_error(func() -> void: r["v"] = _spawn.spawn_enemy("no_such_enemy")) \
		.is_push_error("Simulation.spawn_enemy: unknown enemy \"no_such_enemy\"")
	assert_int(r["v"]).is_equal(0)
	assert_int(_ctx.state.next_id).is_equal(1)
	_ctx.state.outcome = SimState.Outcome.LOST
	assert_int(_spawn.spawn_enemy("hybrid")).is_equal(0)
	assert_array(_ctx.state.enemies).is_empty()
	assert_int(_ctx.state.next_id).is_equal(1)
	assert_array(_drain()).is_empty()


func test_a_pack_enters_its_first_member_now_and_queues_the_rest_on_the_spawn_stream() -> void:
	var count := _pack_count(SimRng.Stream.SPAWN)
	assert_int(count).is_greater(1)
	_ctx.state.tick = 10
	var first := _spawn.spawn_enemy("deep_one")
	assert_int(_ctx.state.enemies.size()).is_equal(1)
	assert_int(_enemy(first).pack_of).is_equal(first)
	assert_int(_spawn._pack_queue.size()).is_equal(count - 1)
	for k in range(1, count):
		var q: Array = _spawn._pack_queue[k - 1]
		assert_int(q[0]).is_equal(10 + k * _spacing())
		assert_bool(q[2]).is_false()
		assert_int(q[3]).is_equal(first)
	assert_bool(_spawn.has_queued_real_members()).is_true()
	# the roll came from the SPAWN stream: the next SPAWN draw continues where this one stopped
	var g := _fresh(SimRng.Stream.SPAWN)
	g.randi_range(4, 6)
	assert_float(_ctx.rng(SimRng.Stream.SPAWN).randf()).is_equal(g.randf())


func test_a_fake_pack_rolls_on_the_sanity_stream_and_leaves_the_spawn_stream_alone() -> void:
	var count := _pack_count(SimRng.Stream.SANITY)
	_spawn.spawn_enemy("deep_one", true)
	assert_int(_spawn._pack_queue.size()).is_equal(count - 1)
	for q: Array in _spawn._pack_queue:
		assert_bool(q[2]).is_true()
	assert_bool(_spawn.has_queued_real_members()).is_false()  # queued fakes are not real members
	assert_float(_ctx.rng(SimRng.Stream.SPAWN).randf()).is_equal(_fresh(SimRng.Stream.SPAWN).randf())


# --- release_pack_members, clear_pack_queue --------------------------------------------------------

func test_release_pack_members_enters_the_due_members_of_one_kind_in_queue_order() -> void:
	var first := _spawn.spawn_enemy("deep_one")
	var fake_first := _spawn.spawn_enemy("deep_one", true)
	var real_left := _spawn._pack_queue.filter(func(q: Array) -> bool: return not q[2]).size()
	var fake_left := _spawn._pack_queue.size() - real_left
	_drain()
	var spawn_state := _ctx.rng(SimRng.Stream.SPAWN).state
	var sanity_state := _ctx.rng(SimRng.Stream.SANITY).state
	_ctx.state.tick = _spacing()  # exactly member 1 of each pack is due
	_spawn.release_pack_members(false)
	assert_int(_spawn._pack_queue.size()).is_equal(real_left + fake_left - 1)
	var ev := _drain()
	assert_array(_types(ev)).is_equal([T.SPAWNED])
	var entered := _enemy(ev[0].id)
	assert_bool(entered.is_fake).is_false()
	assert_int(entered.pack_of).is_equal(first)
	assert_int(entered.spawn_tick).is_equal(_spacing())
	_spawn.release_pack_members(true)
	ev = _drain()
	assert_array(_types(ev)).is_equal([T.SPAWNED])
	assert_bool(_enemy(ev[0].id).is_fake).is_true()
	assert_int(_enemy(ev[0].id).pack_of).is_equal(fake_first)
	assert_int(_spawn._pack_queue.size()).is_equal(real_left + fake_left - 2)
	# a later tick releases every remaining real member, in queue order, drawing no RNG
	_ctx.state.tick = 100 * _spacing()
	_spawn.release_pack_members(false)
	ev = _drain()
	assert_int(ev.size()).is_equal(real_left - 1)
	var ids := ev.map(func(x: SimEvent) -> int: return x.id)
	var sorted := ids.duplicate()
	sorted.sort()
	assert_array(ids).is_equal(sorted)
	assert_bool(_spawn.has_queued_real_members()).is_false()
	assert_int(_spawn._pack_queue.size()).is_equal(fake_left - 1)
	assert_int(_ctx.rng(SimRng.Stream.SPAWN).state).is_equal(spawn_state)  # releasing draws no RNG
	assert_int(_ctx.rng(SimRng.Stream.SANITY).state).is_equal(sanity_state)


func test_release_pack_members_enters_two_packs_in_the_order_they_were_queued() -> void:
	var pack_a := _spawn.spawn_enemy("deep_one")
	_ctx.state.tick = 1
	var pack_b := _spawn.spawn_enemy("deep_one")
	assert_int(pack_b).is_greater(pack_a)
	_drain()
	_ctx.state.tick = 100 * _spacing()  # every queued member of both packs is due on this tick
	_spawn.release_pack_members(false)
	var ev := _drain()
	var packs := ev.map(func(x: SimEvent) -> int: return _enemy(x.id).pack_of)
	assert_int(packs.size()).is_greater(2)
	assert_int(packs.front()).is_equal(pack_a)
	assert_int(packs.back()).is_equal(pack_b)
	var expected := packs.duplicate()
	expected.sort()
	assert_array(packs).is_equal(expected)  # all of pack A (queued first), then all of pack B


func test_release_pack_members_with_an_empty_queue_does_nothing() -> void:
	_spawn.release_pack_members(false)
	_spawn.release_pack_members(true)
	assert_array(_ctx.state.enemies).is_empty()
	assert_array(_drain()).is_empty()


func test_clear_pack_queue_empties_it() -> void:
	_spawn.spawn_enemy("deep_one")
	_spawn.spawn_enemy("deep_one", true)
	assert_bool(_spawn._pack_queue.is_empty()).is_false()
	_spawn.clear_pack_queue()
	assert_bool(_spawn._pack_queue.is_empty()).is_true()
	assert_bool(_spawn.has_queued_real_members()).is_false()


# --- move, push_back -------------------------------------------------------------------------------

func test_move_advances_live_enemies_by_their_step_and_remembers_the_previous_distance() -> void:
	var e := _enemy(_spawn.spawn_enemy("hybrid"))
	e.speed_mult = 0.5
	var step := roundi(e.base_units_per_tick * 0.5)
	assert_int(step).is_greater(0)
	_spawn.move()
	assert_int(e.distance).is_equal(step)
	assert_int(e.prev_distance).is_equal(0)
	_spawn.move()
	assert_int(e.distance).is_equal(2 * step)
	assert_int(e.prev_distance).is_equal(step)


func test_move_skips_dead_enemies_and_clamps_at_the_route_end() -> void:
	var dead := _enemy(_spawn.spawn_enemy("hybrid"))
	dead.dead = true
	var near := _enemy(_spawn.spawn_enemy("hybrid"))
	near.distance = near.route.length - 1
	_spawn.move()
	assert_int(dead.distance).is_equal(0)
	assert_int(dead.prev_distance).is_equal(0)
	assert_int(near.distance).is_equal(near.route.length)
	assert_int(near.prev_distance).is_equal(near.route.length - 1)


func test_push_back_moves_an_enemy_back_by_cells_never_before_the_start() -> void:
	var e := _enemy(_spawn.spawn_enemy("hybrid"))
	e.distance = 5 * SimTime.UNITS_PER_CELL
	e.prev_distance = e.distance - 7
	_spawn.push_back(e, 2.0)
	assert_int(e.distance).is_equal(3 * SimTime.UNITS_PER_CELL)
	assert_int(e.prev_distance).is_equal(e.distance)  # the render does not slide it back
	_spawn.push_back(e, 50.0)
	assert_int(e.distance).is_equal(0)
	assert_int(e.prev_distance).is_equal(0)


# --- leak ---------------------------------------------------------------------------------------------

func test_leak_takes_the_leak_damage_off_the_lighthouse_floors_at_zero_and_emits_leaked() -> void:
	_ctx.state.lighthouse_hp = 3
	var e := _enemy(_spawn.spawn_enemy("shoggoth"))  # leak_damage 5 > 3 hp
	assert_int(e.def.leak_damage).is_equal(5)
	e.distance = e.route.length
	_drain()
	_spawn.leak()
	assert_bool(e.leaked).is_true()
	assert_int(_ctx.state.lighthouse_hp).is_equal(0)
	var ev := _drain()
	assert_array(_types(ev)).is_equal([T.LEAKED])
	assert_int(ev[0].id).is_equal(e.id)
	assert_dict(ev[0].data).is_equal({"damage": 5, "hp_after": 0})


func test_leak_only_touches_live_enemies_at_the_route_end_and_a_fake_dissolves_without_damage() -> void:
	var start_hp := _ctx.state.lighthouse_hp
	var walking := _enemy(_spawn.spawn_enemy("hybrid"))
	var gone := _enemy(_spawn.spawn_enemy("hybrid"))
	gone.dead = true
	gone.distance = gone.route.length
	var fake := _enemy(_spawn.spawn_enemy("hybrid", true))
	fake.distance = fake.route.length
	var real := _enemy(_spawn.spawn_enemy("hybrid"))
	real.distance = real.route.length
	_drain()
	_spawn.leak()
	assert_bool(walking.leaked or walking.dissolved).is_false()
	assert_bool(gone.leaked).is_false()
	assert_bool(fake.dissolved).is_true()
	assert_bool(fake.leaked).is_false()
	assert_bool(real.leaked).is_true()
	assert_int(_ctx.state.lighthouse_hp).is_equal(start_hp - real.def.leak_damage)  # the fake cost nothing
	var ev := _drain()
	assert_array(_types(ev)).is_equal([T.FAKE_DISSOLVED, T.LEAKED])
	assert_dict(ev[0].data).is_equal({"reason": "lighthouse"})
	assert_int(ev[0].id).is_equal(fake.id)


# --- dissolve_fakes, compact -----------------------------------------------------------------------------

func test_dissolve_fakes_drops_queued_fakes_dissolves_live_ones_in_id_order_then_compacts() -> void:
	var real := _enemy(_spawn.spawn_enemy("hybrid"))
	var f1 := _enemy(_spawn.spawn_enemy("hybrid", true))
	var pack_real := _spawn.spawn_enemy("deep_one")
	_spawn.spawn_enemy("deep_one", true)
	var f2 := _enemy(_ctx.state.enemies.back().id)
	var real_queued := _spawn._pack_queue.filter(func(q: Array) -> bool: return not q[2]).size()
	assert_int(_spawn._pack_queue.size()).is_greater(real_queued)
	_drain()
	_spawn.dissolve_fakes("dawn")
	assert_int(_spawn._pack_queue.size()).is_equal(real_queued)  # fakes dropped, reals stay
	for q: Array in _spawn._pack_queue:
		assert_int(q[3]).is_equal(pack_real)
	var ev := _drain()
	assert_array(_types(ev)).is_equal([T.FAKE_DISSOLVED, T.FAKE_DISSOLVED])  # queued ones: no event
	assert_array(ev.map(func(x: SimEvent) -> int: return x.id)).is_equal([f1.id, f2.id])
	assert_dict(ev[0].data).is_equal({"reason": "dawn"})
	assert_bool(real.dissolved).is_false()
	assert_array(_ctx.state.enemies.filter(func(e: SimEnemy) -> bool: return e.is_fake)).is_empty()
	assert_bool(real in _ctx.state.enemies).is_true()
	assert_int(_compact_calls.size()).is_equal(1)  # compact ran (and its ally hook)


func test_compact_drops_dead_and_leaked_enemies_and_then_calls_the_ally_hook() -> void:
	var keep := _enemy(_spawn.spawn_enemy("hybrid"))
	var dead := _enemy(_spawn.spawn_enemy("hybrid"))
	dead.dead = true
	var leaked := _enemy(_spawn.spawn_enemy("hybrid"))
	leaked.leaked = true
	var dissolved := _enemy(_spawn.spawn_enemy("hybrid", true))
	dissolved.dissolved = true
	_spawn.compact()
	assert_array(_ctx.state.enemies).is_equal([keep])
	assert_array(_compact_calls).is_equal([1])  # the hook saw the already compacted enemies, once


# --- facade forwarders and the hook target --------------------------------------------------------------

func test_the_facade_forwards_spawn_enemy_queue_query_dissolve_and_push_back_to_the_spawn_system() -> void:
	var sim := tsim()
	var spy := SpySpawn.new(sim._ctx)
	sim._spawn = spy
	assert_int(sim.spawn_enemy("hybrid", true)).is_equal(4242)
	assert_bool(sim.has_queued_real_members()).is_true()
	sim.dissolve_fakes("dawn")
	var e := SimEnemy.new()
	sim._push_back(e, 1.5)
	assert_array(spy.calls).is_equal([
		["spawn_enemy", "hybrid", true], ["has_queued_real_members"], ["dissolve_fakes", "dawn"],
		["push_back", e, 1.5]])


## G4a cannot see a Callable (it is opaque), so the wiring is pinned here, as LT-82 pinned the
## Combat hooks: the compact hook points at AllySystem.compact of the facade's own ally system
## (a lambda or a facade method would show another object or method), and Combat holds the
## facade's SpawnSystem.
func test_the_facade_wires_the_compact_hook_to_the_ally_system_and_combat_to_its_spawn_system() -> void:
	var sim := tsim()
	var hook: Callable = sim._spawn._compact_allies
	assert_bool(hook.is_valid()).is_true()
	assert_bool(hook.get_object() is AllySystem).is_true()
	assert_object(hook.get_object()).is_same(sim._ally)
	assert_str(String(hook.get_method())).is_equal("compact")
	assert_object(sim._combat._spawn).is_same(sim._spawn)
	assert_bool(sim._spawn is SpawnSystem).is_true()
