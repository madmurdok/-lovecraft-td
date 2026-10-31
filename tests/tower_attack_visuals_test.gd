class_name TowerAttackVisualsTest
extends GdUnitTestSuite
## LT-25: each tower's SHOT becomes its own attack look (tracer / harpoon / wave, aura for
## the Elder Sign), astray and missed shots get their own variants, live attack effects are
## capped per tower, the ward aura brightens with an enemy inside, and enemy markers follow
## the per-tick aura state. Pinned through the pure mapping (shot_kind, enemy_markers,
## ward_alpha) and the effect dicts on_event appends; the look itself is checked by render.

var _vp: SubViewport
var _game: Game
var _config: GameConfig
var _next_cell := 0


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_next_cell = 0
	_vp = SubViewport.new()
	_vp.size = Vector2i(1152, 648)
	add_child(_vp)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _start_game() -> void:
	_game = Game.new()
	_game.setup(_config, 7)
	_vp.add_child(_game)
	_game.set_process(false)
	await get_tree().process_frame
	_game.sim.state.gold = 10000


func _buildable(n: int) -> Vector2i:
	var m := _game.sim.state.map
	var seen := 0
	for y in m.height:
		for x in m.width:
			if m.is_buildable(Vector2i(x, y)):
				if seen == n:
					return Vector2i(x, y)
				seen += 1
	return Vector2i(-1, -1)


func _tower(def_id: String) -> SimTower:
	var cell := _buildable(_next_cell)
	_next_cell += 1
	var r := _game.build(def_id, cell)
	assert_int(r as int).override_failure_message("build %s at %s -> %d" % [def_id, cell, r]) \
		.is_equal(Simulation.CommandResult.OK)
	return _game.sim.tower_by_id(_game.sim.state.tower_at[cell])


func _enemy(fake := false, cells := 2.0) -> SimEnemy:
	var id := _game.sim.spawn_enemy("cultist", fake)
	var e := _game.sim.enemy_by_id(id)
	e.distance = roundi(cells * SimTime.UNITS_PER_CELL)
	e.prev_distance = e.distance
	return e


func _shoot(t: SimTower, to: Vector2, hits: Array, miss := false, astray := false) -> void:
	var ev := SimEvent.new(SimEvent.Type.SHOT, 0, t.id, {"def": t.def.id,
		"target": hits[0] if not hits.is_empty() else 0, "hits": hits, "to": to,
		"miss": miss, "astray": astray})
	_game.board.on_event(ev)


func _last_fx() -> Dictionary:
	return _game.board.effects.back()


# --- 1-4: event -> attack kind per tower ---------------------------------------------

func test_a_rifleman_hit_is_a_tracer_ending_at_the_target() -> void:
	await _start_game()
	var t := _tower("rifleman")
	var e := _enemy()
	var to := Vector2(4.5, 2.5)
	_shoot(t, to, [e.id])
	var fx := _last_fx()
	assert_str(fx["kind"]).is_equal("tracer")
	assert_int(fx["tower"]).is_equal(t.id)
	assert_vector(fx["to"]).is_equal(to)
	assert_vector(fx["end"]).is_equal(to)
	assert_bool(fx["miss"]).is_false()


func test_a_harpoon_flies_to_the_line_end_and_marks_each_pierced_enemy() -> void:
	await _start_game()
	var t := _tower("harpooner")
	var a := _enemy(false, 2.0)
	var b := _enemy(false, 3.0)
	var to := Vector2(7.5, 1.5)
	_shoot(t, to, [a.id, b.id])
	var fx := _last_fx()
	assert_str(fx["kind"]).is_equal("harpoon")
	assert_vector(fx["to"]).is_equal(to)
	assert_array(fx["hits"]).contains_exactly([a.id, b.id])
	assert_int((fx["hit_pos"] as Array).size()).is_equal(2)
	assert_bool(fx.has("pass_t")).is_true()
	assert_int((fx.get("pass_t", []) as Array).size()).is_equal(2)


func test_a_necronomicon_shot_is_a_wave_of_its_aoe_radius() -> void:
	await _start_game()
	var t := _tower("necronomicon_reader")
	var e := _enemy()
	_shoot(t, Vector2(3.5, 2.5), [e.id])
	var fx := _last_fx()
	assert_str(fx["kind"]).is_equal("wave")
	assert_float(fx["radius"]).is_equal(float(t.stats().effects["aoe_radius"]))
	assert_float(fx["radius"]).is_equal(1.5)
	assert_bool(fx["astray"]).is_false()


func test_the_elder_sign_is_an_aura_and_draws_no_shot() -> void:
	await _start_game()
	var t := _tower("elder_sign")
	assert_str(Board.shot_kind(t)).is_equal("aura")
	var before := _game.board.effects.size()
	_shoot(t, t.centre() + Vector2(1, 0), [])
	assert_int(_game.board.effects.size()).is_equal(before)


func test_shot_kind_follows_the_stats_of_each_tower() -> void:
	await _start_game()
	assert_str(Board.shot_kind(_tower("rifleman"))).is_equal("tracer")
	assert_str(Board.shot_kind(_tower("harpooner"))).is_equal("harpoon")
	assert_str(Board.shot_kind(_tower("necronomicon_reader"))).is_equal("wave")
	assert_str(Board.shot_kind(_tower("elder_sign"))).is_equal("aura")


# --- 5: markers from enemy state ------------------------------------------------------

func _marked(speed: float, taken: float) -> PackedStringArray:
	var e := SimEnemy.new()
	e.speed_mult = speed
	e.damage_taken_mult = taken
	return Board.enemy_markers(e)


func test_enemy_markers_follow_slow_and_damage_taken() -> void:
	assert_array(Array(_marked(0.7, 1.0))).contains_exactly(["slow"])
	assert_array(Array(_marked(1.0, 1.25))).contains_exactly(["vuln"])
	assert_array(Array(_marked(0.7, 1.25))).contains_exactly(["slow", "vuln"])
	assert_array(Array(_marked(1.0, 1.0))).is_empty()


# --- 6: ward aura alpha ---------------------------------------------------------------

func test_the_ward_is_faint_when_empty_and_bright_with_an_enemy_inside() -> void:
	await _start_game()
	var t := _tower("elder_sign")
	var r := t.stats().range_cells
	var board := _game.board
	board._last_pos.clear()
	assert_float(board.ward_alpha(t)).is_equal(Board.WARD_IDLE_ALPHA)
	board._last_pos[9001] = t.centre() + Vector2(r + 0.5, 0)
	assert_float(board.ward_alpha(t)).is_equal(Board.WARD_IDLE_ALPHA)
	board._last_pos[9002] = t.centre() + Vector2(r * 0.5, 0)
	var a := board.ward_alpha(t)
	assert_float(a).is_between(Board.WARD_PULSE_LOW, Board.WARD_ACTIVE_ALPHA)
	assert_float(a).is_greater(Board.WARD_IDLE_ALPHA)


# --- 7: astray variants ---------------------------------------------------------------

func test_an_astray_wave_with_hits_stays_a_wave_flagged_astray() -> void:
	await _start_game()
	var t := _tower("necronomicon_reader")
	var e := _enemy()
	var to := Vector2(3.5, 2.5)
	_shoot(t, to, [e.id], false, true)
	var fx := _last_fx()
	assert_str(fx["kind"]).is_equal("wave")
	assert_bool(fx["astray"]).is_true()
	assert_float(fx["radius"]).is_equal(1.5)


func test_an_empty_astray_wave_fizzles_small_off_its_aim() -> void:
	await _start_game()
	var t := _tower("necronomicon_reader")
	var aim := Vector2(3.5, 2.5)
	_shoot(t, aim, [], false, true)
	var fx := _last_fx()
	assert_str(fx["kind"]).is_equal("astray")
	assert_float(fx["radius"]).is_equal(Board.WAVE_FIZZLE_CELLS)
	assert_float(fx["radius"]).is_less_equal(0.5)
	assert_vector(fx["aim"]).is_equal(aim)
	assert_bool((fx["to"] as Vector2).is_equal_approx(aim)).is_false()


func test_an_empty_astray_rifle_shot_is_the_generic_bolt_without_a_ring() -> void:
	await _start_game()
	var t := _tower("rifleman")
	_shoot(t, Vector2(3.5, 1.5), [], false, true)
	var fx := _last_fx()
	assert_str(fx["kind"]).is_equal("astray")
	assert_bool(fx.has("radius")).is_false()


# --- 8: fake parity -------------------------------------------------------------------

func _fx_without_ids(fx: Dictionary) -> Dictionary:
	var out := fx.duplicate(true)
	out.erase("seed")
	out.erase("hits")
	return out


func test_a_shot_at_a_fake_draws_like_the_same_shot_at_a_real_enemy() -> void:
	await _start_game()
	var real := _enemy(false, 2.0)
	var fake := _enemy(true, 2.0)
	fake.route = real.route
	assert_vector(_game.sim.enemy_position(fake, 1.0)) \
		.is_equal(_game.sim.enemy_position(real, 1.0))
	for def_id in ["rifleman", "harpooner", "necronomicon_reader"]:
		var t := _tower(def_id)
		for astray in [false, true]:
			var to := Vector2(3.5, 2.5)
			_shoot(t, to, [real.id], false, astray)
			var at_real := _last_fx()
			_shoot(t, to, [fake.id], false, astray)
			var at_fake := _last_fx()
			assert_dict(_fx_without_ids(at_fake)).override_failure_message(
				"%s astray=%s: %s vs %s" % [def_id, astray, at_fake, at_real]) \
				.is_equal(_fx_without_ids(at_real))
			assert_array(at_fake["hits"]).contains_exactly([fake.id])


# --- 9: mundane misses ----------------------------------------------------------------

func test_a_missed_rifle_shot_ends_beside_and_past_its_aim() -> void:
	await _start_game()
	var t := _tower("rifleman")
	var to := Vector2(4.5, 2.5)
	_shoot(t, to, [], true)
	var fx := _last_fx()
	assert_str(fx["kind"]).is_equal("tracer")
	assert_bool(fx["miss"]).is_true()
	var end: Vector2 = fx["end"]
	assert_bool(end.is_equal_approx(to)).is_false()
	var dir := (to - t.centre()).normalized()
	var off := end - to
	assert_float(off.dot(dir)).is_equal_approx(Board.TRACER_MISS_PAST_CELLS, 0.001)
	assert_float(absf(off.dot(dir.orthogonal()))) \
		.is_equal_approx(Board.TRACER_MISS_SIDE_CELLS, 0.001)


func test_a_missed_harpoon_flies_its_line_with_no_hit_ticks() -> void:
	await _start_game()
	var t := _tower("harpooner")
	var to := Vector2(7.5, 1.5)
	_shoot(t, to, [], true)
	var fx := _last_fx()
	assert_str(fx["kind"]).is_equal("harpoon")
	assert_bool(fx["miss"]).is_true()
	assert_vector(fx["to"]).is_equal(to)
	assert_array(fx["hit_pos"]).is_empty()
	assert_bool(fx.has("pass_t")).is_true()
	assert_array(fx.get("pass_t", [])).is_empty()


# --- 10: per-tower cap ----------------------------------------------------------------

func _fx_of(tower_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for fx in _game.board.effects:
		if fx.get("tower", -1) == tower_id:
			out.append(fx)
	return out


func test_one_tower_keeps_at_most_two_attack_effects_the_newest() -> void:
	await _start_game()
	var other := _tower("harpooner")
	var t := _tower("rifleman")
	_shoot(other, Vector2(7.5, 1.5), [])
	for i in 10:
		_shoot(t, Vector2(1.5 + i, 2.5), [])
	var mine := _fx_of(t.id)
	assert_int(mine.size()).is_equal(Board.MAX_FX_PER_TOWER)
	assert_int(Board.MAX_FX_PER_TOWER).is_equal(2)
	assert_vector(mine[0]["to"]).is_equal(Vector2(9.5, 2.5))
	assert_vector(mine[1]["to"]).is_equal(Vector2(10.5, 2.5))
	assert_int(_fx_of(other.id).size()).is_equal(1)
