class_name RouteSourceTest
extends TowerTestBase
## LT-109 (docs/design/LT-109-route-source.md section 4.3, owner decisions section 6): the route
## source (MapDef routes / RouteProvider), the optional waves.json group "route", the per-wave
## RoutePlan (RouteSystem), spawns on a route, the ROUTE RNG stream and the golden dumper rule.
## Written from the note, not from the code. Fixture: the TowerTestBase map (15x3, route "main"
## = row y = 0) plus a hand-made second route "alt" (row y = 1, then up to L), set on the config's
## MapDef (v1 parsing yields one route only) and on wave 1 group 0 of the loaded waves.
##
## Behaviour -> tests (section 4.3 numbers):
##   1  golden replay / trace unchanged: golden_replay_test, golden_trace_test (run, not edited).
##   2  test_v1_map_has_the_one_main_route, test_fixed_provider_*
##   3  test_waves_route_*
##   4  test_group_alt_walks_alt, test_enemies_of_one_route_share_one_sim_route,
##      test_flyer_flies_straight_from_its_route_start_to_the_lighthouse
##   5  test_pack_member_walks_its_leaders_route
##   6  test_wave_1_plan_exists_at_tick_0, test_plan_made_by_day_reaches_spawns_only_after_wave_started,
##      test_next_plan_follows_a_cleared_wave
##   7  test_rng_stream_enum_and_seeds, test_fixed_map_run_leaves_route_undrawn
##   8  test_dumper_*  (review F2: tested through state_text / trace_final output, not through
##      GoldenRuns.dumped_streams)
##   9  test_g4b_route_plans_have_one_writer (the guard scan itself: architecture_guard_test)
##   10 test_spawn_system_without_the_facade_reads_the_map_routes
##   11 test_planned_route_cells_*
##   F1 test_unknown_route_id_falls_back_to_the_default_route (the push_error is pinned with
##      assert_error().is_push_error, the way sim_spawn_test pins "unknown enemy")
##
## Controls (each: revert the production code, the named test must fail; verify builds them):
##   C1  SpawnSystem._enter: `e.route_id = _resolve_route_id(route_id)` ignores its argument
##       (always the default route)               -> test_group_alt_walks_alt
##   C2  SpawnSystem._route_for: build a new SimRoute per call (skip the cache hit)
##                                                -> test_enemies_of_one_route_share_one_sim_route
##   C3  WaveDirector.start_wave: drop `sim.on_wave_start()`
##                                                -> test_plan_made_by_day_reaches_spawns_only_after_wave_started
##   C4  WaveDirector._begin_build: drop `sim.on_build_start(...)` and plan in Simulation.on_dawn
##       instead                                  -> test_wave_1_plan_exists_at_tick_0
##   C5  SimRng.Stream: insert ROUTE before LIFT  -> test_rng_stream_enum_and_seeds (and golden)
##   C6  GoldenRuns.state_text dumps every stream unconditionally (and trace_final alike)
##                                                -> golden_replay_test (digest differs) and
##                                                   test_dumper_undrawn_route_adds_no_entry
##   C7  GameConfig._cross_checks: drop _check_routes
##                                                -> test_waves_route_unknown_id_is_a_config_error
##   C8  (F1) SpawnSystem._resolve_route_id: return `route_id` unchecked (no fallback)
##                                                -> test_unknown_route_id_falls_back_to_the_default_route
##   C9  (F2) GoldenRuns.dumped_streams never adds a drawn later stream (only 0 .. PINNED - 1)
##                                                -> test_dumper_drawn_route_adds_one_entry
##                                                   (golden stays green: no run draws ROUTE)

const T := SimEvent.Type
const W := "waves.json"
const MAIN := "main"
const ALT := "alt"
const SLOW := {"cultist": {"speed": 0.05}, "deep_one": {"speed": 0.05}}
const LH_HP := 100000


## The second route: row y = 1 (x = 0..14), then up into L (14, 0). Longer than main (14 cells).
func _alt_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in 15:
		out.append(Vector2i(x, 1))
	out.append(Vector2i(14, 0))
	return out


## Two-route config: map routes {main, alt}; wave 1 group 0 walks "alt", group 1 has no route.
func _cfg2() -> GameConfig:
	var cfg := make_config(ROWS, LH_HP, SLOW)
	cfg.map.routes[ALT] = _alt_cells()
	cfg.map.route_ids.append(ALT)
	cfg.waves.waves[0].groups[0].route = ALT
	return cfg


## A sim with the real wave director on `cfg`.
func _sim_with_waves(cfg: GameConfig) -> Simulation:
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(WaveDirector.new(cfg.waves))
	return sim


func _route_len(cfg: GameConfig, cells: Array[Vector2i]) -> int:
	return SimRoute.from_cells(cfg.map.grid, cells).length


func _with_route(group_route: Variant) -> ConfigLoadResult:
	return load_json_edit(W, func(d: Dictionary) -> void:
		d["waves"][0]["groups"][0]["route"] = group_route)


func _of_route(sim: Simulation, id: String) -> Array[SimEnemy]:
	var out: Array[SimEnemy] = []
	for e in sim.state.enemies:
		if e.route_id == id:
			out.append(e)
	return out


# --- 2: MapDef routes, the provider ----------------------------------------------------------

func test_v1_map_has_the_one_main_route() -> void:
	var m := real_config().map
	assert_array(Array(m.route_ids)).is_equal([MAIN])
	assert_array(m.routes.keys()).is_equal([MAIN])
	assert_array(m.routes[MAIN]).is_equal(m.path)


func test_fixed_provider_returns_the_path_for_any_extra_cost_and_nothing_for_unknown_ids() -> void:
	var m := real_config().map
	var p := m.route_provider()
	assert_array(Array(p.ids())).is_equal([MAIN])
	var costs: Array[PackedInt64Array] = [PackedInt64Array(),
		PackedInt64Array([1, 2, 3]), PackedInt64Array([999999, 0, 5, 7, 11])]
	for cost in costs:
		assert_array(p.cells(MAIN, cost)).is_equal(m.path)
	assert_array(p.cells("nope", PackedInt64Array())).is_empty()
	assert_array(p.cells("", PackedInt64Array())).is_empty()


func test_fixed_provider_serves_every_authored_route() -> void:
	var cfg := _cfg2()
	var p := cfg.map.route_provider()
	assert_array(Array(p.ids())).is_equal([MAIN, ALT])
	assert_array(p.cells(ALT, PackedInt64Array())).is_equal(_alt_cells())
	assert_array(p.cells(MAIN, PackedInt64Array())).is_equal(cfg.map.path)


# --- 3: waves.json "route" -------------------------------------------------------------------

func test_waves_route_absent_is_the_empty_string() -> void:
	for w in real_config().waves.waves:
		for g in w.groups:
			assert_str(g.route).is_empty()


func test_waves_route_known_id_loads() -> void:
	var r := _with_route(MAIN)
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_str(r.config.waves.waves[0].groups[0].route).is_equal(MAIN)


func test_waves_route_unknown_id_is_a_config_error() -> void:
	assert_rejected(_with_route("nope"), W, "waves[0].groups[0].route", "nope")


func test_waves_route_any_is_a_config_error() -> void:
	assert_rejected(_with_route("any"), W, "waves[0].groups[0].route", "any")


func test_waves_route_error_names_the_wave_and_group() -> void:
	var r := load_json_edit(W, func(d: Dictionary) -> void:
		d["waves"][2]["groups"][1]["route"] = "nope")
	assert_rejected(r, W, "waves[2].groups[1].route", "nope")


# --- 4: spawn on a route ---------------------------------------------------------------------

func test_group_alt_walks_alt() -> void:
	var cfg := _cfg2()
	var sim := _sim_with_waves(cfg)
	assert_int(sim.call_wave()).is_equal(SimCommand.CommandResult.OK)
	run(sim, 3 * SimTime.TICK_RATE)  # group 0 (alt) fires from the next tick; group 1 only at 12 s
	var alts := _of_route(sim, ALT)
	assert_int(alts.size()).is_greater(0)
	assert_int(_of_route(sim, MAIN).size()).is_equal(0)
	assert_int(alts[0].route.length).is_equal(_route_len(cfg, _alt_cells()))
	assert_int(alts[0].route.length).is_not_equal(_route_len(cfg, cfg.map.path))
	# the group without a route walks the default route
	run(sim, 10 * SimTime.TICK_RATE)
	var mains := _of_route(sim, MAIN)
	assert_int(mains.size()).is_greater(0)
	assert_int(mains[0].route.length).is_equal(_route_len(cfg, cfg.map.path))


func test_enemies_of_one_route_share_one_sim_route() -> void:
	var sim := _sim_with_waves(_cfg2())
	sim.call_wave()
	run(sim, 4 * SimTime.TICK_RATE)  # interval 1.2 s: several alt walkers
	var alts := _of_route(sim, ALT)
	assert_int(alts.size()).is_greater_equal(3)
	for e in alts:
		assert_bool(is_instance_valid(e.route) and e.route == alts[0].route).is_true()
	var other := sim.enemy_by_id(sim.spawn_enemy("cultist", false, MAIN))
	assert_bool(other.route != alts[0].route).is_true()


func test_flyer_flies_straight_from_its_route_start_to_the_lighthouse() -> void:
	var cfg := _cfg2()
	var sim := Simulation.new(cfg, SEED)
	var fly_alt := sim.enemy_by_id(sim.spawn_enemy("night_gaunt", false, ALT))
	var fly_main := sim.enemy_by_id(sim.spawn_enemy("night_gaunt"))
	var g := cfg.map.grid
	var alt := _alt_cells()
	assert_int(fly_alt.route.length).is_equal(SimRoute.straight(g, alt[0], alt[-1]).length)
	assert_int(fly_main.route.length).is_equal(
		SimRoute.straight(g, cfg.map.path[0], cfg.map.path[-1]).length)
	assert_object(fly_alt.route.position_at(0)).is_equal(g.centre(alt[0]))
	assert_object(fly_alt.route.position_at(fly_alt.route.length)).is_equal(g.centre(alt[-1]))
	assert_object(fly_main.route.position_at(0)).is_equal(g.centre(cfg.map.path[0]))
	assert_int(fly_alt.route.length).is_not_equal(fly_main.route.length)


# --- 5: pack ---------------------------------------------------------------------------------

func test_pack_member_walks_its_leaders_route() -> void:
	var sim := Simulation.new(_cfg2(), SEED)
	var lead := sim.enemy_by_id(sim.spawn_enemy("deep_one", false, ALT))
	run(sim, 10 * SimTime.TICK_RATE)  # members enter 0.5 s apart
	assert_int(sim.state.enemies.size()).is_greater_equal(4)  # pack min 4
	for e in sim.state.enemies:
		assert_str(e.route_id).is_equal(ALT)
		assert_bool(e.route == lead.route).is_true()


# --- 6: plan timing --------------------------------------------------------------------------

func test_wave_1_plan_exists_at_tick_0() -> void:
	var sim := _sim_with_waves(_cfg2())
	assert_int(sim.state.tick).is_equal(0)
	assert_int(sim.state.route_next.wave).is_equal(1)
	assert_array(Array(sim.state.route_next.group_routes).slice(0, 2)).is_equal([ALT, MAIN])
	assert_int(sim.state.route_now.wave).is_equal(0)  # nothing started yet: the default plan


func test_plan_made_by_day_reaches_spawns_only_after_wave_started() -> void:
	var cfg := _cfg2()
	var sim := _sim_with_waves(cfg)
	var main_len := _route_len(cfg, cfg.map.path)
	var changed := _alt_cells()
	# a stub provider whose cells change per call: the map's "main" is re-authored by day
	cfg.map.routes[MAIN] = changed
	var changed_len := _route_len(cfg, changed)
	assert_int(changed_len).is_not_equal(main_len)
	sim.on_build_start(1)
	assert_array(sim.state.route_next.cells[MAIN]).is_equal(changed)  # planned...
	var before := sim.enemy_by_id(sim.spawn_enemy("cultist", false, MAIN))
	assert_int(before.route.length).is_equal(main_len)  # ...but not read by spawns yet
	assert_int(sim.call_wave()).is_equal(SimCommand.CommandResult.OK)  # WAVE_STARTED
	assert_bool(sim.state.route_now == sim.state.route_next).is_true()
	assert_int(sim.state.route_now.wave).is_equal(1)
	var after := sim.enemy_by_id(sim.spawn_enemy("cultist", false, MAIN))
	assert_int(after.route.length).is_equal(changed_len)
	# an enemy already walking keeps its route
	assert_int(before.route.length).is_equal(main_len)
	assert_bool(before.route != after.route).is_true()


## §2.3: the cache holds while the cells are equal, so a new wave's plan with the same cells
## reuses the SimRoute (LT-109/S9 G1). Control: compare cells by identity (`is_same(built[id],
## cells)`) in SpawnSystem._route_for -> this test fails, the within-wave share test passes.
func test_unchanged_route_is_reused_across_waves() -> void:
	var sim := _sim_with_waves(_cfg2())
	sim.call_wave()
	var first := sim.enemy_by_id(sim.spawn_enemy("cultist", false, ALT))
	var r1 := first.route
	assert_int(sim.debug_end_night()).is_equal(SimCommand.CommandResult.OK)
	run(sim, 3)
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	sim.call_wave()
	assert_int(sim.state.route_now.wave).is_equal(2)
	var second := sim.enemy_by_id(sim.spawn_enemy("cultist", false, ALT))
	assert_bool(second.route == r1).is_true()


func test_next_plan_follows_a_cleared_wave() -> void:
	var sim := _sim_with_waves(_cfg2())
	sim.call_wave()
	assert_int(sim.state.route_now.wave).is_equal(1)
	assert_int(sim.debug_end_night()).is_equal(SimCommand.CommandResult.OK)
	run(sim, 3)
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	assert_int(sim.state.route_next.wave).is_equal(2)
	assert_int(sim.state.route_now.wave).is_equal(1)  # the cleared wave's plan stays until wave 2 starts


# --- 7: RNG ----------------------------------------------------------------------------------

func test_rng_stream_enum_and_seeds() -> void:
	assert_int(SimRng.Stream.LIFT).is_equal(7)
	assert_int(SimRng.Stream.ROUTE).is_equal(8)
	assert_int(SimRng.Stream.size()).is_equal(9)
	var sim := Simulation.new(tconfig(), SEED)
	for i in 9:
		var fresh := RandomNumberGenerator.new()
		fresh.seed = SEED * 16 + i
		var g := sim.rng(i as SimRng.Stream)
		assert_int(g.seed).override_failure_message("stream %d seed" % i).is_equal(SEED * 16 + i)
		assert_int(g.state).override_failure_message("stream %d state" % i).is_equal(fresh.state)


func test_fixed_map_run_leaves_route_undrawn() -> void:
	var sim := _sim_with_waves(_cfg2())
	sim.call_wave()
	run(sim, 15 * SimTime.TICK_RATE)
	sim.debug_end_night()
	run(sim, 3)
	sim.call_wave()
	run(sim, 5 * SimTime.TICK_RATE)
	assert_int(sim.state.wave_index).is_equal(2)
	var fresh := RandomNumberGenerator.new()
	fresh.seed = SEED * 16 + SimRng.Stream.ROUTE
	assert_int(sim.rng(SimRng.Stream.ROUTE).state).is_equal(fresh.state)


# --- 8: the golden dumper rule (F2: through the dump text, not dumped_streams) ----------------

func _rng_lines(text: String) -> Array[String]:
	var out: Array[String] = []
	for m in RegEx.create_from_string("rng(\\d+)=").search_all(text):
		out.append(m.get_string(1))
	return out


func _trace_rng(sim: Simulation) -> Array:
	var errors: Array[String] = []
	var d: Dictionary = JSON.parse_string(GoldenRuns.trace_final(sim, errors))
	assert_array(errors).is_empty()
	return d["final"]["rng"]


func test_dumper_undrawn_route_adds_no_entry() -> void:
	var sim := Simulation.new(tconfig(), SEED)
	var lines := _rng_lines(GoldenRuns.state_text(sim))
	assert_array(lines).is_equal(["0", "1", "2", "3", "4", "5", "6", "7"])
	assert_int(_trace_rng(sim).size()).is_equal(8)


func test_dumper_drawn_route_adds_one_entry() -> void:
	var sim := Simulation.new(tconfig(), SEED)
	sim.rng(SimRng.Stream.ROUTE).randf()
	var text := GoldenRuns.state_text(sim)
	assert_array(_rng_lines(text)).is_equal(["0", "1", "2", "3", "4", "5", "6", "7", "8"])
	assert_str(text).contains("rng8=%d" % sim.rng(SimRng.Stream.ROUTE).state)
	var trace := _trace_rng(sim)
	assert_int(trace.size()).is_equal(9)
	assert_str(trace[8]).is_equal(str(sim.rng(SimRng.Stream.ROUTE).state))


# --- 9: G4b ----------------------------------------------------------------------------------

func test_g4b_route_plans_have_one_writer() -> void:
	var owners := ["core/systems/route_system.gd"]
	assert_array(ArchitectureGuardTest.G4B_OWNERS["route_now"]).is_equal(owners)
	assert_array(ArchitectureGuardTest.G4B_OWNERS["route_next"]).is_equal(owners)


# --- 10: SpawnSystem without the facade ------------------------------------------------------

func test_spawn_system_without_the_facade_reads_the_map_routes() -> void:
	var cfg := _cfg2()
	var ctx := SimContext.new(cfg, SEED)
	ctx.state.map = cfg.map
	ctx.state.lighthouse_hp = cfg.economy.lighthouse_hp
	var spawn := SpawnSystem.new(ctx)
	spawn.set_trait_host(TraitHost.new(ctx, spawn.queue_pack_member))
	assert_object(ctx.state.route_now).is_null()
	var on_alt: SimEnemy = null
	var on_main: SimEnemy = null
	var alt_id := spawn.spawn_enemy("cultist", false, ALT)
	var main_id := spawn.spawn_enemy("cultist")
	for e in ctx.state.enemies:
		if e.id == alt_id:
			on_alt = e
		elif e.id == main_id:
			on_main = e
	assert_str(on_alt.route_id).is_equal(ALT)
	assert_int(on_alt.route.length).is_equal(_route_len(cfg, _alt_cells()))
	assert_str(on_main.route_id).is_equal(MAIN)
	assert_int(on_main.route.length).is_equal(_route_len(cfg, cfg.map.path))


# --- 11: bot ---------------------------------------------------------------------------------

func test_planned_route_cells_equal_the_path_on_the_fixed_map() -> void:
	var sim := tsim()
	assert_array(sim.planned_route_cells()).is_equal(sim.config.map.path)
	var cfg := make_config(ROWS, LH_HP)
	var with_waves := _sim_with_waves(cfg)
	assert_array(with_waves.planned_route_cells()).is_equal(cfg.map.path)


func test_planned_route_cells_cover_every_route_the_next_wave_uses_once() -> void:
	var cfg := _cfg2()  # wave 1: group 0 alt, group 1 default
	var sim := _sim_with_waves(cfg)
	var got := sim.planned_route_cells()
	var want := {}
	for c in cfg.map.path:
		want[c] = true
	for c in _alt_cells():
		want[c] = true
	assert_int(got.size()).is_equal(want.size())  # each cell once
	for c in got:
		assert_bool(want.has(c)).is_true()


# --- F1: an unknown route id passed in code --------------------------------------------------

func test_unknown_route_id_falls_back_to_the_default_route() -> void:
	var cfg := _cfg2()
	var sim := Simulation.new(cfg, SEED)
	var r := {"id": 0}
	await assert_error(func() -> void: r["id"] = sim.spawn_enemy("cultist", false, "nope")) \
		.is_push_error("SpawnSystem: unknown route \"nope\", using \"main\"")
	var e := sim.enemy_by_id(r["id"])
	assert_int(e.id).is_greater(0)
	assert_str(e.route_id).is_equal(MAIN)
	assert_int(e.route.length).is_equal(_route_len(cfg, cfg.map.path))
	assert_bool(e.route == sim.enemy_by_id(sim.spawn_enemy("cultist")).route).is_true()
