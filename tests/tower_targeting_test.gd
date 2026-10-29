class_name TowerTargetingTest
extends TowerTestBase
## LT-6 targeting, fire cadence and shot resolution of the rifleman (behaviours 12, 16-20,
## 23-26). Tower at (7,1); an enemy parked `c` cells along the route is dx = c - 7 cells
## from it horizontally and 1 cell vertically.


# --- cadence -----------------------------------------------------------------

func test_new_tower_fires_on_the_first_step_then_every_fire_interval() -> void:
	for def_id: String in ["rifleman", "harpooner"]:
		var sim := tsim()
		build(sim, def_id)
		put(sim, "cultist", 8.0)
		var n := fire_ticks(def_id)
		assert_int(n).is_greater(1)
		var ticks := shot_ticks(run(sim, 3 * n + 2))
		assert_array(ticks).is_equal([1, 1 + n, 1 + 2 * n, 1 + 3 * n])


func test_fire_interval_comes_from_config_in_ticks() -> void:
	var cfg := tconfig()
	assert_int(fire_ticks("rifleman")).is_equal(SimTime.ticks(cfg.towers["rifleman"].levels[0].fire_interval))
	assert_int(fire_ticks("harpooner")).is_greater(fire_ticks("rifleman"))


func test_tower_stays_ready_while_nothing_is_in_range() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var far := put(sim, "cultist", 0.0)  # dx = -7: out of range
	var events := run(sim, 100)
	assert_array(of_type(events, SimEvent.Type.SHOT)).is_empty()
	far.distance = 8 * SimTime.UNITS_PER_CELL  # now in range
	assert_array(shot_ticks(run(sim, 1))).is_equal([101])


func test_cooldown_starts_after_the_shot_not_after_the_target_appears() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var e := put(sim, "cultist", 8.0)
	var n := fire_ticks("rifleman")
	run(sim, 1)  # shot on tick 1
	e.distance = 0  # leaves range for the whole cooldown and beyond
	run(sim, 2 * n)
	e.distance = 8 * SimTime.UNITS_PER_CELL
	assert_array(shot_ticks(run(sim, 1))).is_equal([2 + 2 * n])


# --- target choice -----------------------------------------------------------

func test_target_is_the_enemy_closest_to_the_lighthouse_not_the_lowest_id() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var behind := put(sim, "cultist", 6.0)  # lower id, further from L
	var ahead := put(sim, "cultist", 8.0)
	var shots := of_type(run(sim, 1), SimEvent.Type.SHOT)
	assert_int(shots.size()).is_equal(1)
	assert_int(shots[0].data["target"]).is_equal(ahead.id)
	assert_float(ahead.hp).is_less(HUGE_HP)
	assert_float(behind.hp).is_equal(HUGE_HP)


func test_target_is_still_the_front_enemy_when_the_higher_id_is_behind() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var ahead := put(sim, "cultist", 8.0)  # lower id and in front
	put(sim, "cultist", 6.0)
	var shots := of_type(run(sim, 1), SimEvent.Type.SHOT)
	assert_int(shots[0].data["target"]).is_equal(ahead.id)


func test_equal_route_distance_tie_goes_to_the_lower_id() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var first := put(sim, "cultist", 8.0)
	var second := put(sim, "cultist", 8.0)
	assert_int(first.id).is_less(second.id)
	var shots := of_type(run(sim, 1), SimEvent.Type.SHOT)
	assert_int(shots[0].data["target"]).is_equal(first.id)
	assert_float(second.hp).is_equal(HUGE_HP)


func test_enemies_out_of_range_are_ignored_even_if_closer_to_the_lighthouse() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var in_range := put(sim, "cultist", 8.0)
	put(sim, "cultist", 12.0)  # dx = 5: out of range 3
	var shots := of_type(run(sim, 1), SimEvent.Type.SHOT)
	assert_int(shots[0].data["target"]).is_equal(in_range.id)


func test_enemy_just_inside_range_is_hit_and_just_outside_is_not() -> void:
	var sim := tsim()
	var rng: float = sim.config.towers["rifleman"].levels[0].range_cells
	var tower := build(sim, "rifleman")
	# Horizontal offset at which the (dx, 1) distance equals the range exactly.
	var dx := sqrt(rng * rng - 1.0)
	var e := put(sim, "cultist", 7.0 + dx - 0.05)
	assert_array(shot_ticks(run(sim, 1))).is_equal([1])
	e.distance = roundi((7.0 + dx + 0.05) * SimTime.UNITS_PER_CELL)
	tower.cooldown_ticks = 0
	assert_array(shot_ticks(run(sim, 1))).is_empty()


func test_fakes_are_targeted_like_real_enemies() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var real := put(sim, "cultist", 8.0)
	var fake := put(sim, "cultist", 9.0, HUGE_HP, true)
	var shots := of_type(run(sim, 1), SimEvent.Type.SHOT)
	assert_int(shots[0].data["target"]).is_equal(fake.id)
	assert_float(fake.hp).is_less(HUGE_HP)
	assert_float(real.hp).is_equal(HUGE_HP)


func test_dead_enemy_is_not_targeted_by_a_later_tower_in_the_same_tick() -> void:
	var sim := tsim()
	var t1 := build(sim, "rifleman", TOWER)
	var t2 := build(sim, "rifleman", TOWER + Vector2i.RIGHT)
	assert_int(t1.id).is_less(t2.id)
	var victim := put(sim, "cultist", 8.0, 1.0)
	var spare := put(sim, "cultist", 7.0)
	var shots := of_type(run(sim, 1), SimEvent.Type.SHOT)
	assert_int(shots.size()).is_equal(2)
	assert_int(shots[0].id).is_equal(t1.id)  # towers fire in id order
	assert_int(shots[0].data["target"]).is_equal(victim.id)
	assert_int(shots[1].id).is_equal(t2.id)
	assert_int(shots[1].data["target"]).is_equal(spare.id)  # the corpse is skipped


# --- shot resolution ---------------------------------------------------------

func test_rifleman_damage_and_shot_event_contents() -> void:
	var sim := tsim()
	var t := build(sim, "rifleman")
	var dmg: float = sim.config.towers["rifleman"].levels[0].damage
	var e := put(sim, "cultist", 8.0)
	sim.drain_events()
	var events := run(sim, 1)
	assert_float(e.hp).is_equal(HUGE_HP - dmg)
	var shots := of_type(events, SimEvent.Type.SHOT)
	assert_int(shots.size()).is_equal(1)
	assert_int(shots[0].id).is_equal(t.id)
	assert_int(shots[0].tick).is_equal(1)
	assert_str(shots[0].data["def"]).is_equal("rifleman")
	assert_int(shots[0].data["target"]).is_equal(e.id)
	assert_array(shots[0].data["hits"]).is_equal([e.id])
	assert_vector(shots[0].data["to"]).is_equal(Vector2(8.5, 0.5))


func test_armor_reduces_tower_damage_and_is_floored_at_zero() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var dmg: float = sim.config.towers["rifleman"].levels[0].damage
	var armor: float = sim.config.enemies["hybrid"].armor
	assert_float(armor).is_greater(0.0)
	var h := put(sim, "hybrid", 8.0)
	run(sim, 1)
	assert_float(h.hp).is_equal(HUGE_HP - (dmg - armor))
	# Armor above the damage: nothing taken, no death, shot still happens.
	var sim2 := tsim({"cultist": {"armor": 1000}})
	build(sim2, "rifleman")
	var c := put(sim2, "cultist", 8.0, 5.0)
	var events := run(sim2, 1)
	assert_array(of_type(events, SimEvent.Type.SHOT)).has_size(1)
	assert_float(c.hp).is_equal(5.0)
	assert_array(of_type(events, SimEvent.Type.DIED)).is_empty()


func test_shot_event_precedes_the_died_and_gold_events_it_causes() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var e := put(sim, "cultist", 8.0, 1.0)
	sim.drain_events()
	var events := run(sim, 1)
	var types: Array[int] = []
	for ev in events:
		types.append(ev.type)
	assert_array(types).is_equal([SimEvent.Type.SHOT, SimEvent.Type.DIED,
		SimEvent.Type.GOLD_CHANGED])
	assert_str(of_type(events, SimEvent.Type.DIED)[0].data["source"]).is_equal("rifleman")
	assert_int(events[1].id).is_equal(e.id)


func test_died_source_of_a_harpoon_kill_is_harpooner() -> void:
	var sim := tsim()
	build(sim, "harpooner")
	put(sim, "cultist", 8.0, 1.0)
	sim.drain_events()
	var died := of_type(run(sim, 1), SimEvent.Type.DIED)
	assert_str(died[0].data["source"]).is_equal("harpooner")


# --- slot order and outcome --------------------------------------------------

func test_enemy_spawned_this_tick_is_not_shot_until_the_next_tick() -> void:
	# Tower next to S: a fresh spawn at distance 0 is in range at once.
	var sim := Simulation.new(tconfig(), SEED)
	sim.set_spawner(ScriptedSpawner.new([[1, "cultist"]]))
	build(sim, "rifleman", Vector2i(1, 1))
	var events := run(sim, 1)
	assert_array(of_type(events, SimEvent.Type.SPAWNED)).has_size(1)
	assert_array(of_type(events, SimEvent.Type.SHOT)).is_empty()
	assert_array(shot_ticks(run(sim, 1))).is_equal([2])


func test_enemy_that_leaked_this_tick_is_not_shot() -> void:
	var sim := tsim()
	build(sim, "rifleman", Vector2i(13, 1))
	var e := put(sim, "cultist", 13.5)
	e.base_units_per_tick = SimTime.UNITS_PER_CELL  # reaches L this tick
	var events := run(sim, 1)
	assert_array(of_type(events, SimEvent.Type.LEAKED)).has_size(1)
	assert_array(of_type(events, SimEvent.Type.SHOT)).is_empty()
	assert_float(e.hp).is_equal(HUGE_HP)


func test_towers_do_not_fire_after_the_outcome() -> void:
	var sim := tsim({}, 1)
	build(sim, "rifleman")
	var target := put(sim, "cultist", 8.0)
	var leaker := put(sim, "cultist", 14.0)
	leaker.distance = leaker.route.length
	run(sim, 1)  # leak -> LOST (towers fire in this tick: accepted)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.LOST)
	var hp := target.hp
	var tick := sim.state.tick
	var events := run(sim, 3 * fire_ticks("rifleman"))
	assert_array(events).is_empty()
	assert_float(target.hp).is_equal(hp)
	assert_int(sim.state.tick).is_equal(tick)


# --- determinism -------------------------------------------------------------

func _scenario(run_seed: int) -> Array[String]:
	var sim := Simulation.new(real_config(), run_seed)
	sim.set_spawner(ScriptedSpawner.new([[1, "cultist"], [20, "deep_one"], [45, "hybrid"],
		[80, "cultist"], [120, "deep_one"]]))
	sim.build_tower("rifleman", Vector2i(11, 6))
	sim.build_tower("harpooner", Vector2i(12, 4))
	var out: Array[String] = []
	for t in 900:
		sim.step()
		out.append_array(strings_of(sim.drain_events()))
	out.append("gold=%d tick=%d hp=%d outcome=%d" % [sim.state.gold, sim.state.tick,
		sim.state.lighthouse_hp, sim.state.outcome])
	return out


func test_same_seed_and_commands_give_identical_event_logs_with_towers() -> void:
	var a := _scenario(5)
	var b := _scenario(5)
	assert_array(a).is_equal(b)
	var shots := a.filter(func(s: String) -> bool: return s.begins_with("SHOT"))
	assert_array(shots).is_not_empty()
