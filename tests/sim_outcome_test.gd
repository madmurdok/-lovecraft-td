class_name SimOutcomeTest
extends SimTestBase
## LT-4 §5: leaks, lighthouse HP, win/lose, fakes, post-outcome freeze (behaviours 4-8, 19).

const SEED := 7


# --- leaks ------------------------------------------------------------------

func test_leak_removes_enemy_and_reports_damage_and_hp_after() -> void:
	var cfg := make_config(line_map(2), 20)
	var sim := Simulation.new(cfg, SEED)
	var id := sim.spawn_enemy("cultist")
	var events := run(sim, 60)
	var leaks := of_type(events, SimEvent.Type.LEAKED)
	assert_int(leaks.size()).is_equal(1)
	assert_int(leaks[0].id).is_equal(id)
	assert_int(leaks[0].tick).is_equal(60)
	assert_dict(leaks[0].data).is_equal({"damage": 1, "hp_after": 19})  # no "fake" key (LT-12)
	assert_int(sim.state.lighthouse_hp).is_equal(19)
	assert_object(sim.enemy_by_id(id)).is_null()
	assert_array(sim.state.enemies).is_empty()
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.NONE)


func test_leak_damage_comes_from_the_enemy_def() -> void:
	var cfg := make_config(line_map(2), 20, {"cultist": {"leak_damage": 3}})
	var sim := Simulation.new(cfg, SEED)
	sim.spawn_enemy("cultist")
	var leaks := of_type(run(sim, 60), SimEvent.Type.LEAKED)
	assert_int(leaks.size()).is_equal(1)
	assert_int(leaks[0].data["damage"]).is_equal(3)
	assert_int(leaks[0].data["hp_after"]).is_equal(17)
	assert_int(sim.state.lighthouse_hp).is_equal(17)


# --- lose -------------------------------------------------------------------

## Design note §5 example: HP 2, two cultists leak on the same tick.
func test_hp_zero_is_lost_with_one_outcome_and_tick_frozen() -> void:
	var cfg := make_config(line_map(3), 2)
	var sim := Simulation.new(cfg, SEED)
	sim.spawn_enemy("cultist")
	sim.spawn_enemy("cultist")
	var events := run_to(sim, 90)
	var leaks := of_type(events, SimEvent.Type.LEAKED)
	assert_int(leaks.size()).is_equal(2)
	assert_int(leaks[0].data["hp_after"]).is_equal(1)
	assert_int(leaks[1].data["hp_after"]).is_equal(0)
	var outcomes := of_type(events, SimEvent.Type.OUTCOME)
	assert_int(outcomes.size()).is_equal(1)
	assert_int(outcomes[0].tick).is_equal(90)
	assert_int(outcomes[0].id).is_equal(0)
	assert_dict(outcomes[0].data).is_equal({"result": "lost"})
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.LOST)

	var after := run(sim, 25)
	assert_int(sim.state.tick).is_equal(90)
	assert_array(after).is_empty()
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.LOST)


func test_hp_floors_at_zero_and_every_leak_of_the_tick_is_reported() -> void:
	var cfg := make_config(line_map(2), 2)
	var sim := Simulation.new(cfg, SEED)
	for i in 4:
		sim.spawn_enemy("cultist")
	var events := run_to(sim, 60)
	var leaks := of_type(events, SimEvent.Type.LEAKED)
	assert_int(leaks.size()).is_equal(4)
	var hp_after: Array = leaks.map(func(e: SimEvent) -> int: return e.data["hp_after"])
	assert_array(hp_after).is_equal([1, 0, 0, 0])
	assert_int(sim.state.lighthouse_hp).is_equal(0)
	assert_int(of_type(events, SimEvent.Type.OUTCOME).size()).is_equal(1)


func test_hp_floor_when_leak_damage_overshoots() -> void:
	var cfg := make_config(line_map(2), 3)
	var gaunt: EnemyDef = cfg.enemies["night_gaunt"]
	assert_int(gaunt.leak_damage).is_equal(2)
	var sim := Simulation.new(cfg, SEED)
	sim.spawn_enemy("night_gaunt")
	sim.spawn_enemy("night_gaunt")
	var leak := expected_leak_tick(0, ground_length(3), SimTime.units_per_tick(gaunt.speed))
	var leaks := of_type(run_to(sim, leak), SimEvent.Type.LEAKED)
	assert_int(leaks.size()).is_equal(2)
	assert_int(leaks[0].data["hp_after"]).is_equal(1)
	assert_int(leaks[1].data["hp_after"]).is_equal(0)
	assert_int(sim.state.lighthouse_hp).is_equal(0)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.LOST)


# --- win --------------------------------------------------------------------

func test_win_when_exhausted_and_last_real_enemy_killed() -> void:
	var cfg := make_config(line_map(5))
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(ScriptedSpawner.new([[1, "cultist"]]))
	run(sim, 3)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.NONE)
	sim.apply_damage(sim.state.enemies[0].id, 1000.0, "test")
	var events := run(sim, 1)
	var outcomes := of_type(events, SimEvent.Type.OUTCOME)
	assert_int(outcomes.size()).is_equal(1)
	assert_int(outcomes[0].tick).is_equal(4)
	assert_dict(outcomes[0].data).is_equal({"result": "won"})
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.WON)
	run(sim, 5)
	assert_int(sim.state.tick).is_equal(4)


func test_win_when_last_real_enemy_leaks_with_hp_left() -> void:
	var cfg := make_config(line_map(1), 2)
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(ScriptedSpawner.new([[1, "cultist"]]))
	var events := run(sim, 31)
	assert_int(of_type(events, SimEvent.Type.LEAKED).size()).is_equal(1)
	var outcomes := of_type(events, SimEvent.Type.OUTCOME)
	assert_int(outcomes.size()).is_equal(1)
	assert_int(outcomes[0].tick).is_equal(31)
	assert_dict(outcomes[0].data).is_equal({"result": "won"})


func test_no_win_while_spawner_has_pending_entries() -> void:
	var cfg := make_config(line_map(1))
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(ScriptedSpawner.new([[50, "cultist"]]))
	run(sim, 49)  # nothing alive yet, but more will spawn
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.NONE)


func test_no_win_while_a_real_enemy_is_alive() -> void:
	var cfg := make_config(line_map(5))
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(ScriptedSpawner.new([[1, "cultist"]]))
	var events := run(sim, 149)  # exhausted after tick 1; leaks on 151
	assert_array(of_type(events, SimEvent.Type.OUTCOME)).is_empty()
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.NONE)


## Deviation A: without a spawner nothing is ever "exhausted".
func test_without_spawner_the_run_never_wins() -> void:
	var cfg := make_config(line_map(1))
	var sim := Simulation.new(cfg, SEED)
	sim.spawn_enemy("cultist")
	run(sim, 100)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.NONE)
	assert_int(sim.state.tick).is_equal(100)


## §5 / §7 Q6: a last-enemy leak that empties HP is a loss, not a win.
func test_lose_takes_precedence_over_win_on_the_same_tick() -> void:
	var cfg := make_config(line_map(1), 1)
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(ScriptedSpawner.new([[1, "cultist"]]))
	var events := run(sim, 31)
	var outcomes := of_type(events, SimEvent.Type.OUTCOME)
	assert_int(outcomes.size()).is_equal(1)
	assert_dict(outcomes[0].data).is_equal({"result": "lost"})
	assert_int(outcomes[0].tick).is_equal(31)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.LOST)


# --- fakes ------------------------------------------------------------------

## LT-12 §3 (owner Q1): a fake reaching the lighthouse dissolves instead of leaking.
func test_fake_at_the_lighthouse_dissolves_without_leaking() -> void:
	var cfg := make_config(line_map(2), 1)
	var sim := Simulation.new(cfg, SEED)
	var id := sim.spawn_enemy("cultist", true)
	var events := run(sim, 60)
	assert_array(of_type(events, SimEvent.Type.LEAKED)).is_empty()
	var gone := of_type(events, SimEvent.Type.FAKE_DISSOLVED)
	assert_int(gone.size()).is_equal(1)
	assert_int(gone[0].id).is_equal(id)
	assert_int(gone[0].tick).is_equal(60)
	assert_dict(gone[0].data).is_equal({"reason": "lighthouse"})
	assert_int(sim.state.lighthouse_hp).is_equal(1)
	assert_object(sim.enemy_by_id(id)).is_null()
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.NONE)


func test_live_fake_does_not_block_the_win() -> void:
	var cfg := make_config(line_map(10))
	var sim := Simulation.new(cfg, SEED)
	var fake := sim.spawn_enemy("cultist", true)
	sim.set_spawner(ScriptedSpawner.new([[1, "cultist"]]))
	run(sim, 2)
	var real := sim.state.enemies[1]
	assert_bool(real.is_fake).is_false()
	sim.apply_damage(real.id, 1000.0, "test")
	var outcomes := of_type(run(sim, 1), SimEvent.Type.OUTCOME)
	assert_int(outcomes.size()).is_equal(1)
	assert_dict(outcomes[0].data).is_equal({"result": "won"})
	assert_object(sim.enemy_by_id(fake)).is_not_null()


# --- after the outcome (behaviour 19) ---------------------------------------

func test_after_lost_spawn_damage_and_step_change_nothing() -> void:
	var cfg := make_config(line_map(2), 1)
	var sim := Simulation.new(cfg, SEED)
	sim.spawn_enemy("cultist")
	run(sim, 30)
	var survivor := sim.spawn_enemy("cultist")
	run_to(sim, 60)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.LOST)
	var e := sim.enemy_by_id(survivor)
	assert_object(e).is_not_null()
	var next_id := sim.state.next_id
	var count := sim.state.enemies.size()
	var hp := e.hp
	var distance := e.distance

	assert_int(sim.spawn_enemy("cultist")).is_equal(0)
	assert_float(sim.apply_damage(survivor, 10.0, "test")).is_equal(0.0)
	run(sim, 5)
	assert_int(sim.state.next_id).is_equal(next_id)
	assert_int(sim.state.enemies.size()).is_equal(count)
	assert_float(e.hp).is_equal(hp)
	assert_bool(e.dead).is_false()
	assert_int(e.distance).is_equal(distance)
	assert_int(sim.state.tick).is_equal(60)
	assert_int(sim.state.lighthouse_hp).is_equal(0)
	assert_array(sim.drain_events()).is_empty()


func test_after_won_spawn_and_damage_change_nothing() -> void:
	var cfg := make_config(line_map(10))
	var sim := Simulation.new(cfg, SEED)
	var fake := sim.spawn_enemy("cultist", true)
	sim.set_spawner(ScriptedSpawner.new([]))
	run(sim, 1)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.WON)
	var next_id := sim.state.next_id
	var e := sim.enemy_by_id(fake)
	assert_int(sim.spawn_enemy("hybrid")).is_equal(0)
	assert_float(sim.apply_damage(fake, 1000.0, "test")).is_equal(0.0)
	assert_float(e.hp).is_equal(e.max_hp)
	assert_int(sim.state.next_id).is_equal(next_id)
	assert_array(sim.drain_events()).is_empty()
