class_name SimMovementTest
extends SimTestBase
## LT-4 §3.2/§3.3: integer movement along routes; exact leak ticks (behaviours 1-3).

const SEED := 42


# --- acceptance: the real map -----------------------------------------------

func test_cultist_on_real_map_leaks_on_tick_1210_not_earlier() -> void:
	var cfg := real_config()
	assert_int(cfg.map.path.size()).is_equal(41)  # route of 40 cells
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(ScriptedSpawner.new([[10, "cultist"]]))
	var before := run_to(sim, 1209)
	assert_array(of_type(before, SimEvent.Type.LEAKED)).is_empty()
	assert_int(sim.state.enemies.size()).is_equal(1)
	var e: SimEnemy = sim.state.enemies[0]
	assert_int(e.spawn_tick).is_equal(10)
	assert_int(e.distance).is_equal(e.route.length - 1000)
	var hp := cfg.economy.lighthouse_hp
	assert_int(sim.state.lighthouse_hp).is_equal(hp)

	var at := run(sim, 1)
	var leaks := of_type(at, SimEvent.Type.LEAKED)
	assert_int(leaks.size()).is_equal(1)
	assert_int(leaks[0].tick).is_equal(1210)
	assert_int(leaks[0].id).is_equal(e.id)
	assert_int(sim.state.lighthouse_hp).is_equal(hp - cfg.enemies["cultist"].leak_damage)


## LT-63: members enter one by one, so each leaks 750 ticks after its own spawn tick.
func test_deep_one_pack_on_real_map_leaks_member_by_member() -> void:
	var cfg := real_config()
	var def: EnemyDef = cfg.enemies["deep_one"]
	var upt := SimTime.units_per_tick(def.speed)
	var length := ground_length(cfg.map.path.size())
	var leak := expected_leak_tick(10, length, upt)
	assert_int(leak).is_equal(10 + 750)
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(ScriptedSpawner.new([[10, "deep_one"]]))
	var before := run_to(sim, leak - 1)
	assert_array(of_type(before, SimEvent.Type.LEAKED)).is_empty()
	var spawned := of_type(before, SimEvent.Type.SPAWNED)
	var leaks := of_type(run(sim, pack_span_ticks(cfg, "deep_one") + 1), SimEvent.Type.LEAKED)
	assert_int(leaks.size()).is_equal(spawned.size())
	assert_array(ids_of(leaks)).is_equal(ids_of(spawned))
	for i in leaks.size():
		assert_int(leaks[i].tick).is_equal(expected_leak_tick(spawned[i].tick, length, upt))


# --- formula over lengths and spawn ticks -----------------------------------

func test_cultist_leaks_on_spawn_plus_30_per_cell() -> void:
	for cells: int in [1, 3, 7, 12]:
		var cfg := make_config(line_map(cells))
		var upt := SimTime.units_per_tick(cfg.enemies["cultist"].speed)
		assert_int(upt).is_equal(1000)
		for s: int in [1, 5]:
			var expected := expected_leak_tick(s, ground_length(cells + 1), upt)
			assert_int(expected).is_equal(s + 30 * cells)
			_assert_leaks_exactly_on(cfg, "cultist", s, expected)


func test_enemy_spawned_directly_on_tick_0_leaks_on_30_per_cell() -> void:
	var cfg := make_config(line_map(2))
	var sim := Simulation.new(cfg, SEED)
	var id := sim.spawn_enemy("cultist")
	var before := run_to(sim, 59)
	assert_array(of_type(before, SimEvent.Type.LEAKED)).is_empty()
	var leaks := of_type(run(sim, 1), SimEvent.Type.LEAKED)
	assert_int(leaks.size()).is_equal(1)
	assert_int(leaks[0].id).is_equal(id)
	assert_int(leaks[0].tick).is_equal(60)


## 7 cells = 210 000 units at 1600 units/tick = 131.25 ticks -> arrives on the 132nd.
func test_deep_one_leak_tick_rounds_up() -> void:
	var cfg := make_config(line_map(7))
	var upt := SimTime.units_per_tick(cfg.enemies["deep_one"].speed)
	assert_int(upt).is_equal(1600)
	var expected := expected_leak_tick(3, ground_length(8), upt)
	assert_int(expected).is_equal(3 + 132)
	_assert_leaks_exactly_on(cfg, "deep_one", 3, expected)


func test_enemy_does_not_move_on_its_spawn_tick() -> void:
	var cfg := make_config(line_map(5))
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(ScriptedSpawner.new([[4, "cultist"]]))
	run_to(sim, 4)
	var e: SimEnemy = sim.state.enemies[0]
	assert_int(e.distance).is_equal(0)
	run(sim, 1)
	assert_int(e.prev_distance).is_equal(0)
	assert_int(e.distance).is_equal(e.base_units_per_tick)


# --- flyers -----------------------------------------------------------------

func test_flyer_takes_straight_route_from_s_to_l() -> void:
	var cfg := real_config()
	var m := cfg.map
	var d := m.lighthouse - m.spawn
	var length := roundi(sqrt(float(d.x * d.x + d.y * d.y)) * SimTime.UNITS_PER_CELL)
	var def: EnemyDef = cfg.enemies["night_gaunt"]
	assert_bool(def.flying).is_true()
	var upt := SimTime.units_per_tick(def.speed)
	var leak := expected_leak_tick(10, length, upt)
	# Shorter than walking the 40-cell path.
	assert_int(leak).is_less(expected_leak_tick(10, ground_length(m.path.size()), upt))

	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(ScriptedSpawner.new([[10, "night_gaunt"]]))
	run_to(sim, 10)
	var e: SimEnemy = sim.state.enemies[0]
	assert_int(e.route.length).is_equal(length)
	var a := Vector2(m.spawn) + Vector2(0.5, 0.5)
	var b := Vector2(m.lighthouse) + Vector2(0.5, 0.5)
	var before := run_to(sim, (10 + leak) / 2)
	assert_array(of_type(before, SimEvent.Type.LEAKED)).is_empty()
	var p := sim.enemy_position(e, 1.0)
	# On the S-L segment: zero distance to the line, strictly between its ends.
	var dir := (b - a).normalized()
	assert_float(absf(dir.cross(p - a))).is_less(0.001)
	assert_float(dir.dot(p - a)).is_between(0.1, (b - a).length() - 0.1)

	before = run_to(sim, leak - 1)
	assert_array(of_type(before, SimEvent.Type.LEAKED)).is_empty()
	var leaks := of_type(run(sim, 1), SimEvent.Type.LEAKED)
	assert_int(leaks.size()).is_equal(1)
	assert_int(leaks[0].tick).is_equal(leak)
	assert_int(leaks[0].data["damage"]).is_equal(def.leak_damage)


# --- render position --------------------------------------------------------

func test_enemy_position_interpolates_between_ticks() -> void:
	var cfg := make_config(line_map(4))
	var sim := Simulation.new(cfg, SEED)
	sim.spawn_enemy("cultist")
	run(sim, 15)  # 15 000 units = half a cell
	var e: SimEnemy = sim.state.enemies[0]
	assert_vector(sim.enemy_position(e, 1.0)).is_equal_approx(Vector2(1.0, 0.5),
		Vector2(1e-4, 1e-4))
	assert_vector(sim.enemy_position(e, 0.0)).is_equal_approx(
		Vector2(0.5 + 14.0 / 30.0, 0.5), Vector2(1e-4, 1e-4))
	run(sim, 15)  # exactly on the centre of path[1]
	assert_vector(sim.enemy_position(e, 1.0)).is_equal_approx(Vector2(1.5, 0.5),
		Vector2(1e-4, 1e-4))


func _assert_leaks_exactly_on(cfg: GameConfig, def_id: String, s: int, expected: int) -> void:
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(ScriptedSpawner.new([[s, def_id]]))
	var before := run_to(sim, expected - 1)
	assert_array(of_type(before, SimEvent.Type.LEAKED)).override_failure_message(
		"%s spawned on %d leaked before tick %d: %s" % [def_id, s, expected, before]).is_empty()
	var leaks := of_type(run(sim, 1), SimEvent.Type.LEAKED)
	assert_bool(leaks.is_empty()).override_failure_message(
		"%s spawned on %d did not leak on tick %d" % [def_id, s, expected]).is_false()
	for l in leaks:
		assert_int(l.tick).is_equal(expected)
