class_name SimDamageTest
extends SimTestBase
## LT-4 §3.4 armor/damage/DIED and entity ids (behaviours 10, 11, 20).

const SEED := 3


func _sim() -> Simulation:
	return Simulation.new(make_config(line_map(20)), SEED)


# --- armor ------------------------------------------------------------------

## Design note §3.4 example: Hybrid (armor 2) hit for 10 takes 8; hit for 1 takes 0.
func test_armor_is_subtracted_and_damage_floored_at_zero() -> void:
	var sim := _sim()
	var id := sim.spawn_enemy("hybrid")
	var e := sim.enemy_by_id(id)
	assert_float(e.def.armor).is_equal(2.0)
	assert_float(sim.apply_damage(id, 10.0, "test")).is_equal(8.0)
	assert_float(e.hp).is_equal(e.max_hp - 8.0)
	assert_float(sim.apply_damage(id, 1.0, "test")).is_equal(0.0)
	assert_float(e.hp).is_equal(e.max_hp - 8.0)  # no negative damage heals
	assert_array(of_type(sim.drain_events(), SimEvent.Type.DIED)).is_empty()


func test_negative_armor_bonus_floors_armor_at_zero() -> void:
	var sim := _sim()
	var id := sim.spawn_enemy("hybrid")
	var e := sim.enemy_by_id(id)
	e.armor_bonus = -5.0  # effective armor max(0, 2 - 5) = 0, not -3
	assert_float(sim.apply_damage(id, 10.0, "test")).is_equal(10.0)
	e.armor_bonus = -1.0  # effective armor 1
	assert_float(sim.apply_damage(id, 10.0, "test")).is_equal(9.0)
	assert_float(e.hp).is_equal(e.max_hp - 19.0)


func test_damage_taken_multiplier_applies_after_armor() -> void:
	var sim := _sim()
	var id := sim.spawn_enemy("hybrid")
	sim.enemy_by_id(id).damage_taken_mult = 1.5
	assert_float(sim.apply_damage(id, 10.0, "test")).is_equal(12.0)  # (10 - 2) * 1.5


# --- death ------------------------------------------------------------------

func test_kill_emits_died_with_source_and_removes_after_the_tick() -> void:
	var sim := _sim()
	var id := sim.spawn_enemy("cultist")
	run(sim, 5)
	var e := sim.enemy_by_id(id)
	var distance := e.distance
	sim.apply_damage(id, 1000.0, "harpoon")
	var died := of_type(sim.drain_events(), SimEvent.Type.DIED)
	assert_int(died.size()).is_equal(1)
	assert_int(died[0].id).is_equal(id)
	assert_int(died[0].tick).is_equal(5)
	assert_dict(died[0].data).is_equal({"source": "harpoon"})

	# A second hit on the dead enemy does nothing and emits nothing.
	assert_float(sim.apply_damage(id, 10.0, "harpoon")).is_equal(0.0)
	assert_array(sim.drain_events()).is_empty()

	var events := run(sim, 1)
	assert_object(sim.enemy_by_id(id)).is_null()
	assert_array(sim.state.enemies).is_empty()
	assert_int(e.distance).is_equal(distance)  # did not move after dying
	assert_array(events).is_empty()  # no LEAKED, no second DIED


func test_exact_lethal_damage_kills() -> void:
	var sim := _sim()
	var id := sim.spawn_enemy("cultist")
	assert_float(sim.apply_damage(id, 60.0, "test")).is_equal(60.0)
	assert_int(of_type(sim.drain_events(), SimEvent.Type.DIED).size()).is_equal(1)


# --- return value (behaviour 20) --------------------------------------------

func test_apply_damage_returns_hp_removed_capped_at_remaining_hp() -> void:
	var sim := _sim()
	var a := sim.spawn_enemy("cultist")
	assert_float(sim.apply_damage(a, 1000.0, "test")).is_equal(60.0)
	assert_float(sim.enemy_by_id(a).hp).is_equal(60.0 - 1000.0)
	var b := sim.spawn_enemy("cultist")
	assert_float(sim.apply_damage(b, 10.0, "test")).is_equal(10.0)
	assert_float(sim.apply_damage(b, 45.0, "test")).is_equal(45.0)
	assert_float(sim.apply_damage(b, 45.0, "test")).is_equal(5.0)


func test_apply_damage_to_unknown_id_returns_zero() -> void:
	var sim := _sim()
	sim.spawn_enemy("cultist")
	assert_float(sim.apply_damage(9999, 10.0, "test")).is_equal(0.0)
	assert_array(sim.drain_events().filter(func(e: SimEvent) -> bool:
		return e.type != SimEvent.Type.SPAWNED)).is_empty()


# --- ids --------------------------------------------------------------------

func test_ids_are_unique_increasing_and_never_reused() -> void:
	var sim := _sim()
	var first := sim.spawn_enemy("cultist")
	assert_int(first).is_greater(0)
	var pack_first := sim.spawn_enemy("deep_one")
	assert_int(pack_first).is_equal(first + 1)
	var after_pack := sim.spawn_enemy("hybrid")
	var spawned := of_type(sim.drain_events(), SimEvent.Type.SPAWNED)
	var pack_size := spawned.size() - 2
	assert_int(pack_size).is_between(4, 6)
	assert_int(after_pack).is_equal(pack_first + pack_size)
	# Pack ids are consecutive from the returned first id.
	for i in pack_size:
		assert_int(spawned[1 + i].id).is_equal(pack_first + i)
		assert_str(spawned[1 + i].data["def"]).is_equal("deep_one")

	# Kill and remove the newest one; its id must not come back.
	sim.apply_damage(after_pack, 1000.0, "test")
	run(sim, 1)
	assert_object(sim.enemy_by_id(after_pack)).is_null()
	var again := sim.spawn_enemy("cultist")
	assert_int(again).is_greater(after_pack)
	spawned.append_array(of_type(sim.drain_events(), SimEvent.Type.SPAWNED))

	var seen := {}
	var last := 0
	for ev in spawned:
		assert_bool(seen.has(ev.id)).override_failure_message("id %d reused" % ev.id).is_false()
		assert_int(ev.id).is_greater(last)
		seen[ev.id] = true
		last = ev.id
	assert_int(sim.state.next_id).is_equal(again + 1)
