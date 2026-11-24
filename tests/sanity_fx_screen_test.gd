class_name SanityFxScreenTest
extends GdUnitTestSuite
## LT-62 P3: the SanityFx screen pass covers only the board. The BackBufferCopy rect is the
## board (+ COPY_MARGIN) in screen pixels (stretch scale only, clipped to the stretched
## viewport, recomputed on a resize), it is shown and hidden together with the pass, and the
## shader skips the madness grade (and the framebuffer read) when it can. The rect tests run
## in a stretched SubViewport (size_2d_override), because gl_compatibility reads the rect in
## render-target pixels and S8's unstretched look-check missed that.

const BASE := Vector2i(1200, 675)
const MARGIN := 32.0  ## SanityFx.COPY_MARGIN, spelled out so a change to it shows here

var _vp: SubViewport
var _game: Game
var _config: GameConfig


func before_test() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


## `size` is the render target; a non-zero `override` makes it stretch the BASE viewport.
func _start(size: Vector2i, override: Vector2i) -> void:
	_vp = GameFixture.make_viewport(self, size, override)
	_game = GameFixture.make_game(_vp, _config, 7)
	await get_tree().process_frame


## The board (0, 48, 960, 560 at the default map) plus margin, times the stretch `f`, clipped
## to the stretched viewport (BASE * f). Written from the numbers, not from SanityFx.
func _expected_rect(f: float) -> Rect2:
	var board := Rect2(0.0, 48.0, 960.0, 560.0)
	var raw := Rect2(board.position * f - Vector2(MARGIN, MARGIN) * f, (board.size + Vector2(2, 2) * MARGIN) * f)
	return raw.intersection(Rect2(Vector2.ZERO, Vector2(BASE) * f))


func _set_sanity(v: float) -> void:
	_game.sim._add_sanity(v - _game.sim.state.sanity, "test", 0)
	_game.advance(0.0)
	_game.sanity_fx._snap()


func test_the_screen_pass_rect_is_the_board_not_the_viewport() -> void:
	await _start(BASE, Vector2i.ZERO)
	var fx := _game.sanity_fx
	assert_vector(fx.screen_rect.position).is_equal(Vector2(0, 48))
	assert_vector(fx.screen_rect.size).is_equal(Vector2(960, 560))
	assert_vector(fx.screen_rect.position).is_equal(fx.board_rect().position)
	assert_vector(fx.screen_rect.size).is_equal(fx.board_rect().size)
	assert_int(fx.screen_rect.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_copy_rect_equals_the_board_plus_margin_at_the_base_size() -> void:
	await _start(BASE, Vector2i.ZERO)
	var copy := _game.sanity_fx.screen_copy
	assert_int(copy.copy_mode).is_equal(BackBufferCopy.COPY_MODE_RECT)
	var want := _expected_rect(1.0)  # (0, 16) .. (992, 640)
	assert_vector(copy.rect.position).is_equal(want.position)
	assert_vector(copy.rect.size).is_equal(want.size)
	assert_vector(copy.rect.position).is_equal(Vector2(0, 16))
	assert_vector(copy.rect.size).is_equal(Vector2(992, 624))


func test_copy_rect_scales_with_the_stretch() -> void:
	await _start(Vector2i(1600, 900), BASE)  # 4/3 stretch of the 1200x675 base
	var f := 1600.0 / 1200.0
	assert_float(_vp.get_final_transform().get_scale().x).is_equal_approx(f, 1e-4)
	var copy := _game.sanity_fx.screen_copy
	var want := _expected_rect(f)
	assert_vector(copy.rect.position).is_equal_approx(want.position, Vector2(1e-3, 1e-3))
	assert_vector(copy.rect.size).is_equal_approx(want.size, Vector2(1e-3, 1e-3))
	# not the base-unit rect, which is the unstretched-render bug
	assert_float(copy.rect.size.x).is_greater(992.0)


func test_copy_rect_is_clipped_to_the_stretched_viewport() -> void:
	await _start(Vector2i(2400, 1350), BASE)  # 2x
	var copy := _game.sanity_fx.screen_copy
	assert_float(copy.rect.position.x).is_equal(0.0)  # the margin left of x=0 is cut
	assert_float(copy.rect.end.x).is_less_equal(2400.0)
	assert_float(copy.rect.end.y).is_less_equal(1350.0)
	assert_vector(copy.rect.size).is_equal_approx(Vector2(992.0 * 2.0, 624.0 * 2.0), Vector2(1e-3, 1e-3))


func test_copy_rect_is_recomputed_after_a_size_change() -> void:
	await _start(BASE, BASE)  # stretch 1
	var copy := _game.sanity_fx.screen_copy
	assert_vector(copy.rect.size).is_equal(Vector2(992, 624))
	_vp.size = Vector2i(1600, 900)
	await get_tree().process_frame
	var want := _expected_rect(1600.0 / 1200.0)
	assert_vector(copy.rect.position).is_equal_approx(want.position, Vector2(1e-3, 1e-3))
	assert_vector(copy.rect.size).is_equal_approx(want.size, Vector2(1e-3, 1e-3))


func test_copy_is_a_sibling_drawn_before_the_screen_rect() -> void:
	await _start(BASE, Vector2i.ZERO)
	var fx := _game.sanity_fx
	assert_object(fx.screen_copy.get_parent()).is_same(fx.screen_layer)
	assert_object(fx.screen_rect.get_parent()).is_same(fx.screen_layer)
	assert_int(fx.screen_copy.get_index()).is_less(fx.screen_rect.get_index())


func test_copy_is_shown_and_hidden_with_the_pass() -> void:
	await _start(BASE, Vector2i.ZERO)
	var fx := _game.sanity_fx
	_set_sanity(100.0)
	assert_bool(fx.screen_rect.visible).is_false()
	assert_bool(fx.screen_copy.visible).is_false()
	for v in [55.0, 20.0, 0.0]:
		_set_sanity(v)
		assert_bool(fx.screen_rect.visible).is_true()
		assert_bool(fx.screen_copy.visible).is_true()
	_set_sanity(100.0)
	fx.pulse = 1.0  # a threshold jolt shows the pass even at level 0
	fx.tick(0.0)
	assert_bool(fx.screen_rect.visible).is_true()
	assert_bool(fx.screen_copy.visible).is_true()


func test_shader_does_not_blend_and_gates_the_madness_grade() -> void:
	await _start(BASE, Vector2i.ZERO)
	var code := _game.sanity_fx.screen_material.shader.code
	assert_str(code).contains("blend_disabled")
	assert_str(code).contains("if (madness > 0.0)")


func test_madness_uniform_is_zero_outside_madness_and_one_in_it() -> void:
	await _start(BASE, Vector2i.ZERO)
	var mat := _game.sanity_fx.screen_material
	assert_float(mat.get_shader_parameter("madness")).is_equal(0.0)  # Lucid at the start
	_set_sanity(20.0)  # Fraying
	assert_float(mat.get_shader_parameter("madness")).is_equal(0.0)
	_set_sanity(0.0)
	assert_float(mat.get_shader_parameter("madness")).is_equal(1.0)


# ---- LT-40: the wave keeps the board centre still, the HUD sway eases --------------------
# Shader code is not run headless. These pin the SOURCE: the wave amount is scaled by the
# edge mask and the mask is computed before it. They do not prove the look (the centre
# staying still on screen is the owner's eye check).


func test_screen_wave_is_scaled_by_the_edge_mask_computed_before_it() -> void:
	await _start(BASE, Vector2i.ZERO)
	var code := _game.sanity_fx.screen_material.shader.code
	var edge_at := code.find("float board_edge")
	var amount_at := code.find("float amount")
	var wave_at := code.find("uv += wave")
	assert_int(edge_at).is_greater(-1)
	assert_int(amount_at).is_greater(-1)
	assert_int(edge_at).is_less(amount_at)
	assert_int(amount_at).is_less(wave_at)
	var amount_line := code.substr(amount_at, code.find("\n", amount_at) - amount_at)
	assert_str(amount_line).contains("* smoothstep(0.25, 0.9, board_edge)")
	# LT-40/S9: the mask is centred on the board rect (its own UV), not the viewport.
	var edge_line := code.substr(edge_at, code.find("\n", edge_at) - edge_at)
	assert_str(edge_line).contains("(UV - vec2(0.5))")
	assert_str(amount_line).contains("distortion")


func test_hud_jitter_shader_eases_between_steps() -> void:
	await _start(BASE, Vector2i.ZERO)
	var code := _game.sanity_fx.ui_jitter_material.shader.code
	assert_str(code).contains("mix(step_offset(s), step_offset(s + 1.0), smoothstep(0.0, 1.0, fract(t)))")
	assert_str(code).contains("uniform float rate")


# ---- LT-40/S15: vignette, madness rim and aberration are centred on the board -----------
# Source-text pins (the shader is not run headless): each of the three reads `board_edge` /
# the rect's own UV, and no SCREEN_UV-based edge (`from_centre`, `float edge`) feeds them.
# They do not prove the look on screen.


func _line_with(code: String, needle: String) -> String:
	var at := code.find(needle)
	assert_int(at).override_failure_message("shader has no '%s'" % needle).is_greater(-1)
	return code.substr(at, code.find("\n", at) - at)


func test_vignette_uses_the_board_centred_edge() -> void:
	await _start(BASE, Vector2i.ZERO)
	var code := _game.sanity_fx.screen_material.shader.code
	var line := _line_with(code, "float vig =")
	assert_str(line).contains("smoothstep(0.35, 1.15, board_edge)")


func test_madness_rim_uses_the_board_centred_edge() -> void:
	await _start(BASE, Vector2i.ZERO)
	var code := _game.sanity_fx.screen_material.shader.code
	var line := _line_with(code, "col += vec3(0.30, 0.0, 0.03)")
	assert_str(line).contains("smoothstep(0.55, 1.2, board_edge)")


func test_aberration_direction_and_reach_are_centred_on_the_board_rect() -> void:
	await _start(BASE, Vector2i.ZERO)
	var code := _game.sanity_fx.screen_material.shader.code
	var line := _line_with(code, "vec2 split")
	assert_str(line).contains("normalize(UV - vec2(0.5)")
	assert_str(line).contains("(0.3 + board_edge)")


func test_no_screen_uv_based_edge_is_left_in_the_shader() -> void:
	await _start(BASE, Vector2i.ZERO)
	var code := _game.sanity_fx.screen_material.shader.code
	assert_int(code.find("from_centre")).is_equal(-1)
	assert_int(code.find("float edge")).is_equal(-1)
	# board_edge itself is the only edge measure and is built from UV, not SCREEN_UV
	assert_str(_line_with(code, "float board_edge")).contains("(UV - vec2(0.5))")
	assert_str(_line_with(code, "float board_edge")).not_contains("uv")
