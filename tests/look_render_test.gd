class_name LookRenderTest
extends GdUnitTestSuite
## LT-104 §2.4, §2.5, §4 pins 2, 4, 5, 7, 8: the look catalog on a running board. A variant
## that reuses a built-in look through looks.json (tests/fixtures/looks/variant_looks.json,
## no code) reaches the SHOT effect (builder, look id, colour), the per-tower cap, the BLAST
## colour and the enemy body; the shipped file leaves every effect as it was. Headless
## drawing renders nothing, so the enemy marker geometry is pinned on the draw code and a
## frame with a larger body is drawn for errors only.

const FIXTURE := "res://tests/fixtures/looks/variant_looks.json"

var _vp: SubViewport
var _game: Game
var _config: GameConfig
var _next_cell := 0


func before_test() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_next_cell = 0
	_vp = GameFixture.make_viewport(self)


func after_test() -> void:
	LookCatalog.use(null)
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _use_fixture() -> void:
	var r := TextLoader.read_json(FIXTURE)
	assert_array(r["errors"]).is_empty()
	assert_array(LookCatalog.use(r["data"])).is_empty()
	assert_array(LookCatalog.check_config(_config)).is_empty()


func _start_game() -> void:
	_game = GameFixture.make_game(_vp, _config, 7)
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
	var r := _game.commands.build(def_id, cell)
	assert_int(r as int).override_failure_message("build %s at %s -> %d" % [def_id, cell, r]) \
		.is_equal(SimCommand.CommandResult.OK)
	return _game.sim.tower_by_id(_game.sim.state.tower_at[cell])


func _enemy(def_id := "cultist", fake := false, cells := 2.0) -> SimEnemy:
	var id := _game.sim.spawn_enemy(def_id, fake)
	var e := _game.sim.enemy_by_id(id)
	e.distance = roundi(cells * SimTime.UNITS_PER_CELL)
	e.prev_distance = e.distance
	return e


func _shoot(t: SimTower, to: Vector2) -> void:
	_game.board.on_event(SimEvent.new(SimEvent.Type.SHOT, 0, t.id, {"def": t.def.id,
		"target": 0, "hits": [], "to": to, "miss": false, "astray": false}))


func _banish(t: SimTower, i: int) -> void:
	_game.board.on_event(SimEvent.new(SimEvent.Type.SHOT, 0, t.id, {"def": t.def.id,
		"target": 0, "hits": [], "from": Vector2(1.5 + i, 2.5), "to": Vector2(0.5 + i, 2.5)}))


func _blast(def_id: String) -> Dictionary:
	_game.board.on_event(SimEvent.new(SimEvent.Type.BLAST, 5, 999, {"tower": 999,
		"def": def_id, "at": Vector2(3.5, 2.5), "radius": 1.3, "hits": []}))
	return _game.board.fx_layer.effects.back()


func _fx_of(tower_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for fx in _game.board.fx_layer.effects:
		if fx.get("tower", -1) == tower_id:
			out.append(fx)
	return out


func _frame() -> void:
	_game.board.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame


# --- 7, 11: the shipped file changes nothing -------------------------------------------------

func test_with_the_shipped_file_a_shot_keeps_its_built_in_look_colour_and_cap() -> void:
	LookCatalog.use(null)
	assert_array(LookCatalog.errors()).is_empty()
	await _start_game()
	var t := _tower("rifleman")
	for i in 4:
		_shoot(t, Vector2(1.5 + i, 2.5))
	var mine := _fx_of(t.id)
	assert_int(mine.size()).is_equal(FxLayer.MAX_FX_PER_TOWER)
	assert_str(mine[0]["kind"]).is_equal("tracer")
	assert_str(mine[0]["look"]).is_equal("tracer")
	assert_bool(mine[0]["color"] == Board.TRACER_COLOR).is_true()
	assert_bool(_blast("dynamite_crew")["color"] == Board.DYNAMITE_COLOR).is_true()


# --- 2, 10: a variant reused through looks.json, end to end ---------------------------------

func test_a_variant_from_looks_json_reaches_the_shot_effect_and_tower_colour() -> void:
	_use_fixture()
	await _start_game()
	var t := _tower("rifleman")
	_shoot(t, Vector2(4.5, 2.5))
	var fx: Dictionary = _game.board.fx_layer.effects.back()
	assert_str(Board.shot_kind(t)).is_equal("pale_tracer")
	assert_str(fx["kind"]).is_equal("tracer")  # the built-in builder and renderer
	assert_str(fx["look"]).is_equal("pale_tracer")
	assert_bool(fx["color"] == Color(1.2, 2.0, 2.4)).is_true()
	assert_bool(EntityLayer.attack_color(Board.shot_kind(t)) == Color(1.2, 2.0, 2.4)).is_true()
	# A built-in look assigned to another tower: the coast battery fires tracers.
	var c := _tower("coast_battery")
	_shoot(c, Vector2(5.5, 2.5))
	fx = _game.board.fx_layer.effects.back()
	assert_str(fx["kind"]).is_equal("tracer")
	assert_str(fx["look"]).is_equal("tracer")
	assert_bool(fx["color"] == Board.TRACER_COLOR).is_true()
	await _frame()


# --- 4: the cap comes from the look row; banish keeps max(cap, targets) ----------------------

func test_a_variant_cap_keeps_that_many_live_effects_and_built_ins_keep_two() -> void:
	_use_fixture()
	await _start_game()
	var t := _tower("rifleman")
	var h := _tower("harpooner")
	for i in 4:
		_shoot(t, Vector2(1.5 + i, 2.5))
		_shoot(h, Vector2(1.5 + i, 3.5))
	var mine := _fx_of(t.id)
	assert_int(mine.size()).is_equal(3)
	assert_vector(mine[0]["to"]).is_equal(Vector2(2.5, 2.5))  # the oldest one dropped
	assert_int(_fx_of(h.id).size()).is_equal(FxLayer.MAX_FX_PER_TOWER)


func test_a_banish_look_cap_above_its_targets_keeps_cap_effects() -> void:
	_use_fixture()
	await _start_game()
	var t := _tower("silver_key")
	assert_int(t.stats().banish_targets()).is_equal(1)
	for i in 6:
		_banish(t, i)
	assert_int(_fx_of(t.id).size()).is_equal(5)


func test_a_built_in_banish_keeps_its_targets_when_they_exceed_the_cap() -> void:
	LookCatalog.use({})
	await _start_game()
	var t := _tower("silver_key")
	for i in 4:
		_banish(t, i)
	assert_int(_fx_of(t.id).size()).is_equal(FxLayer.MAX_FX_PER_TOWER)
	t.level = TowerDef.LEVEL_COUNT
	t.branch = "a"
	assert_int(t.stats().banish_targets()).is_equal(3)
	for i in 4:
		_banish(t, i)
	assert_int(_fx_of(t.id).size()).is_equal(3)


# --- 5: the BLAST colour from the throwing tower's def (a sold tower's too) ------------------

func test_a_blast_takes_the_colour_of_its_tower_defs_fuse_look() -> void:
	_use_fixture()
	await _start_game()
	# Tower 999 does not exist (sold): the colour comes from the def id alone.
	assert_bool(_blast("dynamite_crew")["color"] == Color(0.5, 2.0, 0.5)).is_true()
	assert_bool(_blast("rifleman")["color"] == Board.DYNAMITE_COLOR).is_true()
	await _frame()


# --- 3, 9: the enemy body from its look, markers offset by the radius ------------------------

## The body of `func name(` in `src` up to the next top-level func.
func _func_body(src: String, name: String) -> String:
	var start := src.find("\nfunc %s(" % name)
	assert_int(start).override_failure_message(name).is_greater_equal(0)
	var end := src.find("\nfunc ", start + 1)
	return src.substr(start, end - start if end >= 0 else -1)


func test_enemy_markers_and_hp_bar_move_out_by_the_body_radius_above_a_quarter_cell() -> void:
	var body := _func_body(FileAccess.get_file_as_string("res://scenes/board/entity_layer.gd"),
		"_draw_enemies")
	assert_str(body).contains("LookCatalog.enemy_row(LookCatalog.enemy_look(e))")
	assert_str(body).contains("var body: float = look[\"radius\"]")
	assert_str(body).contains("var dr := body - LookCatalog.ENEMY_RADIUS")
	for part: String in ["cells_to_px(MARK_SLOW_CELLS + dr)", "cells_to_px(0.3 + dr + 0.2 * ph)",
			"cells_to_px(BANISH_LID_CELLS + dr)", "cells_to_px(REVEALED_RING_CELLS + dr)",
			"cells_to_px(0.3 + dr)", "cells_to_px(0.4 + dr)"]:
		assert_str(body).override_failure_message(part).contains(part)
	# No marker or body is drawn at the built-in radius any more.
	assert_str(body).not_contains("cells_to_px(0.25)")
	assert_str(body).not_contains("COLOR_ENEMY.lerp")


func test_a_real_and_a_fake_of_one_def_get_its_override_and_draw_with_every_marker() -> void:
	_use_fixture()
	await _start_game()
	var real := _enemy("shoggoth", false, 2.0)
	var fake := _enemy("shoggoth", true, 3.0)
	var plain := _enemy("cultist", false, 4.0)
	assert_str(LookCatalog.enemy_look(real)).is_equal("big_body")
	assert_str(LookCatalog.enemy_look(fake)).is_equal("big_body")
	assert_str(LookCatalog.enemy_look(plain)).is_equal("enemy")
	for e: SimEnemy in [real, fake, plain]:
		e.status["bleed_ticks"] = 100
		e.status["banish_immune_ticks"] = 100
	fake.revealed = true
	await _frame()
