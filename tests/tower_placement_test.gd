class_name TowerPlacementTest
extends TowerTestBase
## LT-6 placement rules and build command (handover behaviours 1-9, 12).

const R := Simulation.CommandResult
const DEFS := ["rifleman", "harpooner"]


func _assert_rejected(sim: Simulation, def_id: String, cell: Vector2i, want: int) -> void:
	sim.drain_events()
	var gold := sim.state.gold
	var next_id := sim.state.next_id
	var towers := sim.state.towers.size()
	var log_size := sim.state.command_log.size()
	assert_int(sim.can_build(def_id, cell)).is_equal(want)
	assert_int(sim.build_tower(def_id, cell)).is_equal(want)
	assert_int(sim.state.gold).is_equal(gold)
	assert_int(sim.state.next_id).is_equal(next_id)
	assert_int(sim.state.towers.size()).is_equal(towers)
	assert_int(sim.state.command_log.size()).is_equal(log_size)
	assert_array(sim.drain_events()).is_empty()


func test_starting_gold_is_the_gdd_value_and_comes_from_config() -> void:
	var sim := tsim()
	assert_int(sim.config.economy.starting_gold).is_equal(300)  # GDD §6
	assert_int(sim.state.gold).is_equal(sim.config.economy.starting_gold)


func test_build_deducts_cost_registers_tower_and_emits_events_in_order() -> void:
	for def_id: String in DEFS:
		var sim := tsim()
		var cost: int = sim.config.towers[def_id].cost
		var before := sim.state.gold
		var next_id := sim.state.next_id
		assert_int(sim.build_tower(def_id, TOWER)).is_equal(R.OK)
		assert_int(sim.state.gold).is_equal(before - cost)
		assert_int(sim.state.tower_at[TOWER]).is_equal(next_id)
		assert_int(sim.state.next_id).is_equal(next_id + 1)
		assert_int(sim.state.towers.size()).is_equal(1)
		var t := sim.state.towers[0]
		assert_int(t.id).is_equal(next_id)
		assert_str(t.def.id).is_equal(def_id)
		assert_object(sim.tower_by_id(next_id)).is_same(t)
		assert_array(sim.state.command_log).is_equal([[0, "build", def_id, TOWER]])
		var ev := sim.drain_events()
		assert_int(ev.size()).is_equal(2)
		assert_int(ev[0].type).is_equal(SimEvent.Type.TOWER_BUILT)
		assert_int(ev[0].id).is_equal(next_id)
		assert_dict(ev[0].data).is_equal({"def": def_id, "cell": TOWER, "cost": cost})
		assert_int(ev[1].type).is_equal(SimEvent.Type.GOLD_CHANGED)
		assert_dict(ev[1].data).is_equal({"delta": -cost, "gold": before - cost,
			"reason": "build"})


func test_build_works_between_ticks_without_stepping() -> void:
	var sim := tsim()
	assert_int(sim.state.tick).is_equal(0)
	assert_int(sim.build_tower("rifleman", TOWER)).is_equal(R.OK)
	assert_int(sim.state.tick).is_equal(0)
	run(sim, 7)
	assert_int(sim.build_tower("harpooner", TOWER + Vector2i.RIGHT)).is_equal(R.OK)
	assert_int(sim.state.tick).is_equal(7)
	assert_array(sim.state.command_log[1]).is_equal([7, "build", "harpooner",
		TOWER + Vector2i.RIGHT])


func test_tower_ids_share_the_entity_counter_with_enemies() -> void:
	var sim := tsim()
	var e := put(sim, "cultist", 2.0)
	var t := build(sim, "rifleman")
	assert_int(t.id).is_equal(e.id + 1)
	var e2 := put(sim, "cultist", 3.0)
	assert_int(e2.id).is_equal(t.id + 1)


# --- rejections --------------------------------------------------------------

func test_cannot_build_on_path_start_or_lighthouse_cells() -> void:
	var sim := tsim()
	for def_id: String in DEFS:
		for cell in [Vector2i(3, 0), Vector2i(0, 0), Vector2i(14, 0)]:
			_assert_rejected(sim, def_id, cell, R.NOT_BUILDABLE)


func test_cannot_build_on_water() -> void:
	var sim := tsim()
	for def_id: String in DEFS:
		_assert_rejected(sim, def_id, Vector2i(3, 2), R.NOT_BUILDABLE)


func test_cannot_build_out_of_bounds() -> void:
	var sim := tsim()
	for cell in [Vector2i(-1, 1), Vector2i(0, -1), Vector2i(15, 1), Vector2i(3, 3)]:
		_assert_rejected(sim, "rifleman", cell, R.NOT_BUILDABLE)


func test_cannot_build_on_occupied_cell_and_gold_is_unchanged() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	_assert_rejected(sim, "rifleman", TOWER, R.OCCUPIED)
	_assert_rejected(sim, "harpooner", TOWER, R.OCCUPIED)


func test_cannot_build_without_enough_gold() -> void:
	for def_id: String in DEFS:
		var sim := tsim()
		var cost: int = sim.config.towers[def_id].cost
		sim.state.gold = cost - 1
		_assert_rejected(sim, def_id, TOWER, R.NOT_ENOUGH_GOLD)
		assert_int(sim.state.gold).is_equal(cost - 1)


func test_build_with_exactly_the_cost_is_allowed_and_leaves_zero_gold() -> void:
	for def_id: String in DEFS:
		var sim := tsim()
		sim.state.gold = sim.config.towers[def_id].cost
		assert_int(sim.build_tower(def_id, TOWER)).is_equal(R.OK)
		assert_int(sim.state.gold).is_equal(0)


func test_unknown_tower_is_rejected() -> void:
	var sim := tsim()
	_assert_rejected(sim, "no_such_tower", TOWER, R.UNKNOWN_TOWER)


func test_occult_towers_are_buildable_at_any_sanity() -> void:
	for def_id: String in ["elder_sign", "necronomicon_reader"]:
		var sim := tsim()
		var def: TowerDef = sim.config.towers[def_id]
		assert_str(def.kind).is_equal("occult")
		sim.state.sanity = 0.0
		assert_int(sim.can_build(def_id, TOWER)).is_equal(R.OK)
		assert_int(sim.build_tower(def_id, TOWER)).is_equal(R.OK)
		assert_int(sim.state.gold).is_equal(sim.config.economy.starting_gold - def.cost)
		assert_int(sim.state.tower_at.size()).is_equal(1)


func test_rejection_reasons_are_checked_in_the_documented_order() -> void:
	var sim := tsim()
	var path_cell := Vector2i(3, 0)
	sim.state.gold = 0
	# UNKNOWN before NOT_BUILDABLE before OCCUPIED before GOLD.
	assert_int(sim.can_build("nope", path_cell)).is_equal(R.UNKNOWN_TOWER)
	assert_int(sim.can_build("elder_sign", path_cell)).is_equal(R.NOT_BUILDABLE)
	assert_int(sim.can_build("elder_sign", TOWER)).is_equal(R.NOT_ENOUGH_GOLD)
	assert_int(sim.can_build("rifleman", path_cell)).is_equal(R.NOT_BUILDABLE)
	assert_int(sim.can_build("rifleman", TOWER)).is_equal(R.NOT_ENOUGH_GOLD)
	sim.state.gold = 200
	build(sim, "rifleman")
	sim.state.gold = 0
	assert_int(sim.can_build("rifleman", TOWER)).is_equal(R.OCCUPIED)


func test_can_build_changes_nothing() -> void:
	var sim := tsim()
	assert_int(sim.can_build("rifleman", TOWER)).is_equal(R.OK)
	assert_int(sim.state.gold).is_equal(sim.config.economy.starting_gold)
	assert_array(sim.state.towers).is_empty()
	assert_array(sim.drain_events()).is_empty()


func test_build_after_outcome_is_refused_before_any_other_check() -> void:
	var sim := tsim({}, 1)
	var leaker := put(sim, "cultist", 14.0)
	leaker.distance = leaker.route.length
	run(sim, 1)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.LOST)
	_assert_rejected(sim, "rifleman", TOWER, R.OUTCOME_REACHED)
	_assert_rejected(sim, "nope", Vector2i(3, 0), R.OUTCOME_REACHED)
