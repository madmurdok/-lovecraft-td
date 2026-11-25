class_name LightingTest
extends GdUnitTestSuite
## LT-8: the lighting layer follows sim state (one light per tower, darkness under the
## Game, HUD outside it) and never changes the sim.

var _vp: SubViewport
var _game: Game
var _extra_vps: Array[SubViewport] = []  ## LT-92: viewports of games built inside a test


func before_test() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_vp = GameFixture.make_viewport(self)
	_game = GameFixture.make_game(_vp, r.config, 7)
	await get_tree().process_frame


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null
	for v in _extra_vps:
		if is_instance_valid(v):
			v.queue_free()
	_extra_vps.clear()


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
		assert_int(_game.commands.build("rifleman", c)).is_equal(SimCommand.CommandResult.OK)
	await get_tree().process_frame
	assert_int(_game.lighting._tower_lights.size()).is_equal(2)
	var t := _game.sim.tower_by_id(_game.sim.state.tower_at[cells[0]])
	var light := _game.lighting._tower_lights[t.id]
	assert_vector(light.position).is_equal(
		_game.board.view.cell_to_world(Vector2(cells[0]) + Vector2(0.5, 0.5)))
	_game.commands.sell(t.id)
	await get_tree().process_frame
	assert_int(_game.lighting._tower_lights.size()).is_equal(1)
	assert_bool(_game.lighting._tower_lights.has(t.id)).is_false()


func test_tower_lights_are_capped() -> void:
	_game.sim.state.gold = 1000000
	for c in _buildable_cells(Lighting.MAX_TOWER_LIGHTS + 3):
		_game.commands.build("rifleman", c)
	await get_tree().process_frame
	assert_int(_game.sim.state.towers.size()).is_greater(Lighting.MAX_TOWER_LIGHTS)
	assert_int(_game.lighting._tower_lights.size()).is_equal(Lighting.MAX_TOWER_LIGHTS)


## LT-30 §3.2 (LT-33 boundary rule): the beam turns with the sim's ticks at night, its
## rotation is the sim's direction at tick + alpha; frames without a tick do not turn it.
func test_beam_rotates_over_time() -> void:
	assert_int(_game.commands.call_wave()).is_equal(SimCommand.CommandResult.OK)
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
	assert_int(_game.commands.call_wave()).is_equal(SimCommand.CommandResult.OK)
	l.ease_night(0.1)
	assert_float(l.night).is_between(0.01, 0.99)  # fading, not a jump
	l.ease_night(10.0)
	assert_float(l.night).is_equal(1.0)
	assert_that(l.modulate_node.color).is_equal(Lighting.AMBIENT_NIGHT)
	assert_bool(l.beam.visible).is_true()
	_game.sim.state.phase = SimState.Phase.BUILD
	GameFixture.sync(_game)
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


## LT-58 (behaviour 2b): the rim lifts the falloff zone (t 0.8..1.0), so near the edge the
## texture is brighter than the plain smoothstep edge times the length falloff.
func test_beam_texture_rim_widens_the_solid_cone_near_the_edge() -> void:
	var ha := 0.5
	var tex := Lighting._beam_texture(ha)
	var p := _beam_px(tex, ha, 0.4, 0.9)
	var plain := (1.0 - smoothstep(Lighting.BEAM_FILL_EDGE_START, 1.0, p["t"])) \
		* pow(1.0 - p["d"], Lighting.BEAM_FALLOFF_POWER)
	assert_float(p["a"]).is_greater(plain + 0.02)


## LT-58 (behaviour 3): the far end (d = 0.8, on the axis) is brighter than the pre-LT-58
## length falloff gave.
func test_beam_texture_far_end_is_brighter_than_the_old_falloff() -> void:
	var ha := 0.5
	var tex := Lighting._beam_texture(ha)
	var old_falloff_power := 0.8  # pre-LT-58 shape: pow(1 - d, 0.8)
	var far := _beam_px(tex, ha, 0.8, 0.0)
	assert_float(far["a"]).is_greater(pow(1.0 - far["d"], old_falloff_power) + 0.02)


## LT-58 (behaviour 4): beam energy is BEAM_ENERGY * night (2.6 at full night).
func test_beam_energy_is_beam_energy_times_night() -> void:
	assert_float(Lighting.BEAM_ENERGY).is_equal(2.6)
	var l := _game.lighting
	assert_int(_game.commands.call_wave()).is_equal(SimCommand.CommandResult.OK)
	l.ease_night(10.0)
	assert_float(l.night).is_equal(1.0)
	for b: PointLight2D in l.beams:
		assert_float(b.energy).is_equal_approx(Lighting.BEAM_ENERGY, 1e-5)
	l.night = 0.5
	l._apply_night()
	for b: PointLight2D in l.beams:
		assert_float(b.energy).is_equal_approx(Lighting.BEAM_ENERGY * 0.5, 1e-5)


# ---- LT-92: the WarmLight (docs/design/LT-92-startup-frames.md, edit map 2 and 4) --------


## A game whose Lighting has not processed a frame yet (no await after it is added), so the
## warm-up frame count starts at zero. Driven by hand: Lighting._process(0.0) is one frame.
func _fresh_game() -> Game:
	var r := ConfigLoader.load_dir("res://data")
	var vp := GameFixture.make_viewport(self)
	_extra_vps.append(vp)
	return GameFixture.make_game(vp, r.config, 7)


## The light's rect in the Lighting's (board-local) space: texture size x scale, centred.
func _rect_of(l: PointLight2D) -> Rect2:
	var side := l.texture.get_width() * l.texture_scale
	return Rect2(l.position - Vector2(side, side) / 2.0, Vector2(side, side))


func test_warm_light_exists_on_the_first_frame_and_gives_no_light() -> void:
	var g := _fresh_game()
	var wl := g.lighting.warm_light
	assert_object(wl).is_not_null()
	assert_str(wl.name).is_equal("WarmLight")
	assert_object(wl.get_parent()).is_same(g.lighting)
	assert_bool(wl.visible).is_true()  # drawn from frame 1, whatever `night` is
	assert_float(wl.energy).is_equal(Lighting.WARM_ENERGY)
	assert_float(wl.energy).is_less_equal(0.01)  # never a visible light
	assert_float(g.lighting.night).is_equal(0.0)
	assert_bool(g.lighting.beam.visible).is_false()
	assert_bool(g.lighting.glow.visible).is_false()


func test_warm_light_rect_contains_the_warmup_rect() -> void:
	var g := _fresh_game()
	var rect := _rect_of(g.lighting.warm_light)
	assert_bool(rect.encloses(FxLayer.WARMUP_RECT)) \
		.override_failure_message("warm rect %s does not enclose %s" % [rect, FxLayer.WARMUP_RECT]) \
		.is_true()


func test_warm_light_rect_is_far_smaller_than_the_board() -> void:
	var g := _fresh_game()
	var rect := _rect_of(g.lighting.warm_light)
	var board := g.board.view.world_rect()
	assert_float(rect.get_area() * 16.0).is_less(board.get_area())


func test_warm_light_is_freed_after_exactly_warm_frames_frames() -> void:
	var g := _fresh_game()
	var l := g.lighting
	var wl := l.warm_light
	for i in Lighting.WARM_FRAMES:
		l._process(0.0)
		assert_object(l.warm_light).is_same(wl)  # still drawn in each of the warm frames
		assert_bool(wl.is_inside_tree()).is_true()
	l._process(0.0)
	assert_object(l.warm_light).is_null()
	assert_bool(is_instance_valid(wl) and wl.is_inside_tree()).is_false()
	assert_object(l.get_node_or_null("WarmLight")).is_null()
	assert_array(g.find_children("WarmLight", "", true, false)).is_empty()
	for i in 3:  # later frames leave nothing behind and do not fail
		l._process(0.0)
	assert_array(g.find_children("WarmLight", "", true, false)).is_empty()


func test_warm_light_is_freed_by_real_frames() -> void:
	var g := _fresh_game()
	var l := g.lighting
	assert_object(l.warm_light).is_not_null()
	for i in Lighting.WARM_FRAMES + 3:
		await get_tree().process_frame
	assert_object(l.warm_light).is_null()
	assert_array(g.find_children("WarmLight", "", true, false)).is_empty()


func test_warm_frames_leave_day_and_night_lighting_unchanged() -> void:
	var g := _fresh_game()
	var l := g.lighting
	for i in Lighting.WARM_FRAMES:
		assert_float(l.night).is_equal(0.0)
		assert_bool(l.beam.visible).is_false()
		assert_bool(l.glow.visible).is_false()
		for tl: PointLight2D in l._tower_lights.values():
			assert_bool(tl.visible).is_false()
		assert_object(l.modulate_node.color).is_equal(Lighting.ambient(0.0))
		l._process(0.0)
	assert_float(l.night).is_equal(0.0)
	assert_object(l.modulate_node.color).is_equal(Lighting.ambient(0.0))


func test_night_does_not_touch_the_warm_light() -> void:
	var g := _fresh_game()
	var l := g.lighting
	var wl := l.warm_light
	assert_int(g.commands.call_wave()).is_equal(SimCommand.CommandResult.OK)
	for i in 5:
		l.ease_night(10.0)
	assert_float(l.night).is_greater(0.9)
	assert_bool(l.beam.visible).is_true()
	assert_bool(wl.visible).is_true()
	assert_float(wl.energy).is_equal(Lighting.WARM_ENERGY)  # _apply_night leaves it alone


func test_a_wave_called_in_the_first_frames_still_frees_the_warm_light() -> void:
	var g := _fresh_game()
	var l := g.lighting
	var wl := l.warm_light
	l._process(0.0)
	assert_int(g.commands.call_wave()).is_equal(SimCommand.CommandResult.OK)
	for i in Lighting.WARM_FRAMES - 1:
		l._process(0.0)
		assert_object(l.warm_light).is_same(wl)
	l._process(0.0)
	assert_object(l.warm_light).is_null()
	assert_bool(is_instance_valid(wl) and wl.is_inside_tree()).is_false()
	assert_array(g.find_children("WarmLight", "", true, false)).is_empty()


func test_the_game_freed_in_the_first_frames_takes_the_warm_light_with_it() -> void:
	var g := _fresh_game()
	var vp: SubViewport = g.get_parent()
	var wl := g.lighting.warm_light
	g.lighting._process(0.0)
	g.free()
	assert_bool(is_instance_valid(wl)).is_false()
	for i in Lighting.WARM_FRAMES + 2:
		await get_tree().process_frame
	assert_array(vp.find_children("WarmLight", "", true, false)).is_empty()
	assert_int(vp.get_child_count()).is_equal(0)
