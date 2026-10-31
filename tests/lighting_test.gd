class_name LightingTest
extends GdUnitTestSuite
## LT-8: the lighting layer follows sim state (one light per tower, darkness under the
## Game, HUD outside it) and never changes the sim.

var _vp: SubViewport
var _game: Game


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_vp = SubViewport.new()
	_vp.size = Vector2i(1152, 648)
	add_child(_vp)
	_game = Game.new()
	_game.setup(r.config, 7)
	_vp.add_child(_game)
	_game.set_process(false)
	await get_tree().process_frame


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _buildable_cells(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			if out.size() < n and m.is_buildable(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


func test_darkness_dims_world_canvas_but_not_the_ui_layer() -> void:
	var dark := _game.lighting.modulate_node
	assert_object(dark.get_parent()).is_same(_game)
	assert_float(dark.color.v).is_less(1.0)
	assert_float(dark.color.v).is_greater(0.0)  # never total darkness
	assert_bool(_game.hud.get_parent() is CanvasLayer).is_true()


func test_one_light_per_tower_added_and_removed_with_it() -> void:
	_game.sim.state.gold = 100000
	var cells := _buildable_cells(2)
	for c in cells:
		assert_int(_game.build("rifleman", c)).is_equal(Simulation.CommandResult.OK)
	await get_tree().process_frame
	assert_int(_game.lighting._tower_lights.size()).is_equal(2)
	var t := _game.sim.tower_by_id(_game.sim.state.tower_at[cells[0]])
	var light := _game.lighting._tower_lights[t.id]
	assert_vector(light.position).is_equal((Vector2(cells[0]) + Vector2(0.5, 0.5)) * Board.CELL)
	_game.sell(t.id)
	await get_tree().process_frame
	assert_int(_game.lighting._tower_lights.size()).is_equal(1)
	assert_bool(_game.lighting._tower_lights.has(t.id)).is_false()


func test_tower_lights_are_capped() -> void:
	_game.sim.state.gold = 1000000
	for c in _buildable_cells(Lighting.MAX_TOWER_LIGHTS + 3):
		_game.build("rifleman", c)
	await get_tree().process_frame
	assert_int(_game.sim.state.towers.size()).is_greater(Lighting.MAX_TOWER_LIGHTS)
	assert_int(_game.lighting._tower_lights.size()).is_equal(Lighting.MAX_TOWER_LIGHTS)


func test_beam_rotates_over_time() -> void:
	var before := _game.lighting.beam.rotation
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(_game.lighting.beam.rotation).is_not_equal(before)


## LT-27 §4 (behaviour 15): day colour in BUILD, the night colour once the fade has run in a
## wave, and back to day at dawn; the lamp is dark by day.
func test_ambient_is_day_by_day_and_night_after_the_fade_at_night() -> void:
	var l := _game.lighting
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.BUILD)
	assert_float(l.night).is_equal(0.0)
	assert_that(l.modulate_node.color).is_equal(Lighting.AMBIENT_DAY)
	assert_bool(l.beam.visible).is_false()
	assert_int(_game.call_wave()).is_equal(Simulation.CommandResult.OK)
	l.ease_night(0.1)
	assert_float(l.night).is_between(0.01, 0.99)  # fading, not a jump
	l.ease_night(10.0)
	assert_float(l.night).is_equal(1.0)
	assert_that(l.modulate_node.color).is_equal(Lighting.AMBIENT_NIGHT)
	assert_bool(l.beam.visible).is_true()
	_game.sim.state.phase = SimState.Phase.BUILD
	l.ease_night(10.0)
	assert_that(l.modulate_node.color).is_equal(Lighting.AMBIENT_DAY)
