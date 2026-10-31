class_name HarpoonTest
extends TowerTestBase
## LT-6 harpooner line shot (behaviours 20-23). Tower at (7,1), range 4, width 1 cell.
## Primary target parked at route cell 10 (dx = 3, dy = -1): the line runs from
## (7.5,1.5) through (10.5,0.5), 4 cells long, half-width 0.5. Cell 9 is 0.32 cells off
## that line (hit), cell 8 is 0.63 off (miss).


func _fire(sim: Simulation) -> SimEvent:
	var shots := of_type(run(sim, 1), SimEvent.Type.SHOT)
	assert_int(shots.size()).is_equal(1)
	return shots[0]


func test_harpoon_pierces_two_enemies_on_its_line_and_misses_one_off_it() -> void:
	var sim := tsim()
	var t := build(sim, "harpooner")
	var dmg: float = sim.config.towers["harpooner"].levels[0].damage
	var off := put(sim, "cultist", 8.0)  # in range but off the line
	var on := put(sim, "cultist", 9.0)
	var primary := put(sim, "cultist", 10.0)
	sim.drain_events()
	var shot := _fire(sim)
	assert_int(shot.id).is_equal(t.id)
	assert_int(shot.data["target"]).is_equal(primary.id)
	assert_array(shot.data["hits"]).contains_exactly_in_any_order([on.id, primary.id])
	assert_float(primary.hp).is_equal(HUGE_HP - dmg)
	assert_float(on.hp).is_equal(HUGE_HP - dmg)  # full damage, not reduced
	assert_float(off.hp).is_equal(HUGE_HP)


func test_harpoon_does_not_hit_enemies_behind_the_tower() -> void:
	var sim := tsim()
	build(sim, "harpooner")
	var behind := put(sim, "cultist", 4.0)  # dx = -3: inside the range circle
	var primary := put(sim, "cultist", 10.0)
	var shot := _fire(sim)
	assert_array(shot.data["hits"]).is_equal([primary.id])
	assert_float(behind.hp).is_equal(HUGE_HP)


func test_harpoon_does_not_hit_beyond_its_length_even_within_the_width() -> void:
	var sim := tsim()
	build(sim, "harpooner")
	var primary := put(sim, "cultist", 10.0)
	# Cell 11: 0.32 off the line but 4.11 cells along it (line length = range = 4).
	var beyond := put(sim, "cultist", 11.0)
	var shot := _fire(sim)
	assert_int(shot.data["target"]).is_equal(primary.id)
	assert_array(shot.data["hits"]).is_equal([primary.id])
	assert_float(beyond.hp).is_equal(HUGE_HP)


func test_each_enemy_is_hit_at_most_once_per_shot() -> void:
	var sim := tsim()
	build(sim, "harpooner")
	var dmg: float = sim.config.towers["harpooner"].levels[0].damage
	var a := put(sim, "cultist", 9.0)
	var b := put(sim, "cultist", 10.0)
	var shot := _fire(sim)
	var hits: Array = shot.data["hits"]
	assert_int(hits.size()).is_equal(2)
	assert_int(hits.count(a.id)).is_equal(1)
	assert_float(a.hp).is_equal(HUGE_HP - dmg)
	assert_float(b.hp).is_equal(HUGE_HP - dmg)


func test_harpoon_hits_fakes_on_the_line_too() -> void:
	var sim := tsim()
	build(sim, "harpooner")
	var fake := put(sim, "cultist", 9.0, HUGE_HP, true)
	var primary := put(sim, "cultist", 10.0)
	var shot := _fire(sim)
	assert_array(shot.data["hits"]).contains_exactly_in_any_order([fake.id, primary.id])


func test_harpoon_line_to_point_is_the_range_long_endpoint() -> void:
	var sim := tsim()
	build(sim, "harpooner")
	var rng: float = sim.config.towers["harpooner"].levels[0].range_cells
	put(sim, "cultist", 10.0)
	var shot := _fire(sim)
	var origin := Vector2(7.5, 1.5)
	var to: Vector2 = shot.data["to"]
	assert_float(origin.distance_to(to)).is_equal_approx(rng, 0.001)
	# Direction is towards the primary target at (10.5, 0.5).
	assert_float((to - origin).normalized().distance_to(
		(Vector2(10.5, 0.5) - origin).normalized())).is_less(0.001)


func test_harpoon_kills_drop_one_token_each_on_a_multi_kill() -> void:
	var sim := tsim()
	build(sim, "harpooner")
	put(sim, "cultist", 9.0, 1.0)
	put(sim, "cultist", 10.0, 1.0)
	sim.drain_events()
	var events := run(sim, 1)
	assert_array(of_type(events, SimEvent.Type.DIED)).has_size(2)
	assert_array(of_type(events, SimEvent.Type.RELIC_DROPPED)).has_size(2)


func test_rifleman_hits_only_its_target_while_the_harpoon_pierces() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var a := put(sim, "cultist", 8.0)
	var b := put(sim, "cultist", 9.0)  # same geometry as a harpoon line
	var shot := _fire(sim)
	assert_array(shot.data["hits"]).is_equal([b.id])
	assert_float(a.hp).is_equal(HUGE_HP)
