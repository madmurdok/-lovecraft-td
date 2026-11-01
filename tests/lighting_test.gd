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


## LT-30 §3.2 (LT-33 boundary rule): the beam turns with the sim's ticks at night, its
## rotation is the sim's direction at tick + alpha; frames without a tick do not turn it.
func test_beam_rotates_over_time() -> void:
	assert_int(_game.call_wave()).is_equal(Simulation.CommandResult.OK)
	await get_tree().process_frame
	var before := _game.lighting.beam.rotation
	for i in 3:
		await get_tree().process_frame
	assert_float(_game.lighting.beam.rotation).is_equal(before)  # no sim tick: no turn
	for i in 10:
		_game.sim.step()
	await get_tree().process_frame
	var want := _game.sim.beam_directions(_game.clock.alpha())[0].angle()
	assert_float(_game.lighting.beam.rotation).is_equal_approx(want, 1e-5)
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


## LT-58: one beam-texture pixel at radius frac d (0..1) and angle t * half_angle off the
## axis; returns the alpha with the pixel's own d and t (the shape is evaluated at pixel centres).
func _beam_px(tex: ImageTexture, half_angle: float, d_want: float, t_want: float) -> Dictionary:
	var img := tex.get_image()
	var half := Lighting.BEAM_TEX_SIZE * 0.5
	var ang := t_want * half_angle
	var px := Vector2i(int(half + cos(ang) * d_want * half), int(half + sin(ang) * d_want * half))
	var v := Vector2(px.x + 0.5 - half, px.y + 0.5 - half)
	return {"a": img.get_pixelv(px).a, "d": v.length() / half, "t": absf(v.angle()) / half_angle}


## LT-58 (behaviour 1): on the axis near the source the beam is at full brightness for its
## falloff, and nothing is lit outside the half-angle or behind the lighthouse.
func test_beam_texture_axis_is_bright_and_outside_the_cone_is_dark() -> void:
	var ha := 0.5
	var tex := Lighting._beam_texture(ha)
	var near := _beam_px(tex, ha, 0.1, 0.0)
	assert_float(near["a"]).is_equal_approx(pow(1.0 - near["d"], Lighting.BEAM_FALLOFF_POWER), 0.01)
	var out := _beam_px(tex, ha, 0.5, 1.3)
	assert_float(out["t"]).is_greater(1.0)
	assert_float(out["a"]).is_equal(0.0)
	var img := tex.get_image()
	assert_float(img.get_pixel(20, 128).a).is_equal(0.0)  # behind the source (x < centre)


## LT-58 (behaviour 2): the edge band is solid up to BEAM_FILL_EDGE_START plus the rim, so
## at t in 0.6..0.9 it is at least the fill ramp from the constant (and clearly above the
## pre-change soft ramp that started at 0.55 with no rim).
func test_beam_texture_edge_band_is_brighter_than_the_old_soft_ramp() -> void:
	var ha := 0.5
	var tex := Lighting._beam_texture(ha)
	var old_ramp_start := 0.55  # pre-LT-58 value of BEAM_FILL_EDGE_START, no rim
	for t_want in [0.65, 0.75, 0.85]:
		var p := _beam_px(tex, ha, 0.4, t_want)
		var radial := pow(1.0 - p["d"], Lighting.BEAM_FALLOFF_POWER)
		var profile: float = p["a"] / radial
		var fill := 1.0 - smoothstep(Lighting.BEAM_FILL_EDGE_START, 1.0, p["t"])
		var old := 1.0 - smoothstep(old_ramp_start, 1.0, p["t"])
		assert_float(profile).is_greater_equal(fill - 0.02)
		assert_float(profile).is_greater(old + 0.1)


## LT-58 (behaviour 2b): the rim makes the band brighter than the axis fill alone would be.
func test_beam_texture_rim_is_brighter_than_the_fill() -> void:
	var ha := 0.5
	var tex := Lighting._beam_texture(ha)
	var p := _beam_px(tex, ha, 0.4, 0.75)
	var radial := pow(1.0 - p["d"], Lighting.BEAM_FALLOFF_POWER)
	var axis := _beam_px(tex, ha, 0.4, 0.0)
	# axis has no rim (smoothstep = 0 at t = 0): value 1.0 * radial; rim band must exceed 1.0
	# where edge + rim > 1 is clamped, so assert it reaches the clamp (profile ~ 1) at the peak
	var peak := _beam_px(tex, ha, 0.4, Lighting.BEAM_RIM_PEAK - 0.02)
	var edge := 1.0 - smoothstep(Lighting.BEAM_FILL_EDGE_START, 1.0, peak["t"])
	var rim := smoothstep(Lighting.BEAM_RIM_START, Lighting.BEAM_RIM_PEAK, peak["t"]) * edge \
		* Lighting.BEAM_RIM_GAIN
	assert_float(rim).is_greater(0.0)
	assert_float(peak["a"] / pow(1.0 - peak["d"], Lighting.BEAM_FALLOFF_POWER)) \
		.is_greater_equal(minf(edge + rim, 1.0) - 0.02)
	assert_float(axis["a"] / pow(1.0 - axis["d"], Lighting.BEAM_FALLOFF_POWER)).is_greater(0.97)
	assert_float(p["a"] / radial).is_greater(0.0)


## LT-58 (behaviour 3): the far end (d = 0.8) keeps at least 0.2^BEAM_FALLOFF_POWER of the
## near brightness (near ~ 1 on the axis).
func test_beam_texture_far_end_keeps_its_brightness() -> void:
	var ha := 0.5
	var tex := Lighting._beam_texture(ha)
	var far := _beam_px(tex, ha, 0.8, 0.0)
	var near := _beam_px(tex, ha, 0.1, 0.0)
	var near_a: float = near["a"] / pow(1.0 - near["d"], Lighting.BEAM_FALLOFF_POWER)
	assert_float(far["a"]).is_greater_equal(near_a * pow(0.2, Lighting.BEAM_FALLOFF_POWER) - 0.01)


## LT-58 (behaviour 4): beam energy is BEAM_ENERGY * night (2.6 at full night).
func test_beam_energy_is_beam_energy_times_night() -> void:
	assert_float(Lighting.BEAM_ENERGY).is_equal(2.6)
	var l := _game.lighting
	assert_int(_game.call_wave()).is_equal(Simulation.CommandResult.OK)
	l.ease_night(10.0)
	assert_float(l.night).is_equal(1.0)
	for b: PointLight2D in l.beams:
		assert_float(b.energy).is_equal_approx(Lighting.BEAM_ENERGY, 1e-5)
	l.night = 0.5
	l._apply_night()
	for b: PointLight2D in l.beams:
		assert_float(b.energy).is_equal_approx(Lighting.BEAM_ENERGY * 0.5, 1e-5)
