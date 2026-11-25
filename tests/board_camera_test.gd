class_name BoardCameraTest
extends GdUnitTestSuite
## LT-66 §6 / §9 (10-15) and review fixes R4, R5: the scrollable map. BoardView.clamp_pan and
## play_rect, the camera's keys, drag, wheel, gesture, edge pan, ease and auto-reveal, picking
## under a pan, and the Board's input filter. Time is driven by explicit `tick(delta, mouse)`
## calls, never a timer. Pixel numbers come from BoardView / BoardCamera constants and the
## spec's formulas (the map plus PAN_MARGIN covers the visible rect), not from typed values.

const DELTA := 0.05

var _view: BoardView
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


func _start_game() -> void:
	_vp = GameFixture.make_viewport(self)
	_game = GameFixture.make_game(_vp, _config, 7)
	await get_tree().process_frame


## V by day: the play rect without the overlay.
static func _day_v() -> Rect2:
	var v := BoardView.play_rect()
	v.end.x = SidePanel.panel_rect().position.x
	return v


## A camera over a `cols` x `rows` map, looking at the day rect, pan 0.
func _cam(cols := 24, rows := 12, v := Rect2()) -> BoardCamera:
	_view = BoardView.new()
	_view.grid = SquareGrid.new(cols, rows)
	var cam := BoardCamera.new(_view)
	cam.set_visible_rect(v if v.size != Vector2.ZERO else _day_v())
	return cam


func _park() -> Vector2:  ## a cursor in no edge strip
	return _day_v().get_center()


func _key(code: Key, pressed := true, ctrl := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = pressed
	k.ctrl_pressed = ctrl
	return k


func _wheel(button: MouseButton, shift := false, pressed := true) -> InputEventMouseButton:
	var w := InputEventMouseButton.new()
	w.button_index = button
	w.pressed = pressed
	w.shift_pressed = shift
	return w


func _motion(rel: Vector2, mask: int) -> InputEventMouseMotion:
	var m := InputEventMouseMotion.new()
	m.relative = rel
	m.button_mask = mask
	return m


## The pan range of `cam`'s visible rect on both axes.
func _range(cam: BoardCamera) -> Array[Vector2]:
	return [_view.clamp_pan(Vector2(-1.0e6, -1.0e6), cam.visible_rect),
		_view.clamp_pan(Vector2(1.0e6, 1.0e6), cam.visible_rect)]


# --- 11: clamp ---------------------------------------------------------------------------------

func test_play_rect_is_the_screen_between_the_hud_and_the_footer() -> void:
	var w := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	assert_that(BoardView.play_rect()).is_equal(
		Rect2(0, BoardView.HUD_H, w, h - BoardView.HUD_H - BoardView.FOOTER_H))


func test_the_map_plus_margin_covers_the_visible_rect_at_both_ends_of_the_range() -> void:
	var cam := _cam()
	var b := BoardView.world_rect_for(_view.grid)
	var v := cam.visible_rect
	var lo := _range(cam)[0]
	var hi := _range(cam)[1]
	assert_float(b.end.x + BoardView.PAN_MARGIN + lo.x).is_equal(v.end.x)
	assert_float(b.position.x - BoardView.PAN_MARGIN + hi.x).is_equal(v.position.x)
	assert_float(lo.x).is_less(0.0)
	assert_float(hi.x).is_greater(0.0)
	# inside the range a pan is untouched
	assert_vector(_view.clamp_pan(Vector2(lo.x * 0.5, 0), v)).is_equal(Vector2(lo.x * 0.5, 0))


func test_an_axis_where_the_map_fits_has_no_pan() -> void:
	var cam := _cam()  # 24 x 12 cells: the height fits the 560 px rect by day and by night
	assert_float(_range(cam)[0].y).is_equal(0.0)
	assert_float(_range(cam)[1].y).is_equal(0.0)
	# at night V is the whole play rect: the 24-column map fits it, so there is no pan at all
	var night := _cam(24, 12, BoardView.play_rect())
	assert_vector(_range(night)[0]).is_equal(Vector2.ZERO)
	assert_vector(_range(night)[1]).is_equal(Vector2.ZERO)


func test_a_taller_map_pans_vertically_and_covers_the_rect() -> void:
	var cam := _cam(24, 20)
	var b := BoardView.world_rect_for(_view.grid)
	var v := cam.visible_rect
	assert_float(b.end.y + BoardView.PAN_MARGIN + _range(cam)[0].y).is_equal(v.end.y)
	assert_float(b.position.y - BoardView.PAN_MARGIN + _range(cam)[1].y).is_equal(v.position.y)


# --- 10: picking under a pan -----------------------------------------------------------------

func test_every_cell_is_picked_at_its_screen_centre_across_the_pan_range() -> void:
	var cam := _cam()
	var lo := _range(cam)[0]
	var hi := _range(cam)[1]
	for pan: Vector2 in [lo, lo * 0.5, Vector2.ZERO, hi * 0.5, hi]:
		_view.set_pan(pan)
		for y in 12:
			for x in 24:
				var c := Vector2i(x, y)
				var at := _view.cell_to_screen(_view.grid.centre(c))
				assert_vector(Vector2(_view.cell_at_screen(at))) \
					.override_failure_message("pan %s cell %s" % [pan, c]).is_equal(Vector2(c))
		var p := Vector2(3.25, 4.75)
		assert_vector(_view.screen_to_cells(_view.cell_to_screen(p))).is_equal_approx(p,
			Vector2(1e-4, 1e-4))


func test_the_board_node_follows_the_pan_and_a_click_at_a_cell_centre_opens_that_cell() -> void:
	await _start_game()
	var cam := _game.board.camera
	cam.set_visible_rect(_day_v())
	var lo := _view_range(_game.board.view, cam)[0]
	var cell := Vector2i(-1, -1)
	var m := _game.sim.state.map
	for x in range(m.width - 1, -1, -1):  # a buildable cell left of the overlay at any pan
		if m.is_buildable(Vector2i(x, 3)) and _game.board.view.cells_to_px(x + 1.0) < _day_v().end.x:
			cell = Vector2i(x, 3)
			break
	assert_int(cell.x).is_greater(-1)
	for pan: Vector2 in [lo * 0.5, Vector2.ZERO]:
		_game.board.view.set_pan(pan)
		assert_vector(_game.board.position).is_equal(_game.board.view.origin())
		var at := _game.board.view.cell_to_screen(m.grid.centre(cell))
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.position = at
			ev.global_position = at
			_vp.push_input(ev)
		await get_tree().process_frame
		assert_bool(_game.picker.visible).override_failure_message("pan %s" % pan).is_true()
		assert_vector(Vector2(_game.picker.cell)).is_equal(Vector2(cell))
		_game.close_panels()


func _view_range(view: BoardView, cam: BoardCamera) -> Array[Vector2]:
	return [view.clamp_pan(Vector2(-1.0e6, -1.0e6), cam.visible_rect),
		view.clamp_pan(Vector2(1.0e6, 1.0e6), cam.visible_rect)]


# --- 12: keys, drag, wheel, gesture ------------------------------------------------------------

func test_a_held_key_pans_at_the_key_speed_the_other_way_and_release_stops_it() -> void:
	var cam := _cam(24, 20)
	_view.set_pan(Vector2(-40, -100))
	var step := BoardCamera.KEY_SPEED * DELTA
	assert_bool(cam.key_input(_key(KEY_D))).is_true()
	cam.tick(DELTA, _park(), false)
	assert_vector(_view.pan).is_equal_approx(Vector2(-40 - step, -100), Vector2(1e-3, 1e-3))
	assert_bool(cam.key_input(_key(KEY_D, false))).is_true()
	cam.tick(DELTA, _park(), false)
	assert_vector(_view.pan).is_equal_approx(Vector2(-40 - step, -100), Vector2(1e-3, 1e-3))
	var cases := {KEY_A: Vector2(step, 0), KEY_LEFT: Vector2(step, 0),
		KEY_RIGHT: Vector2(-step, 0), KEY_W: Vector2(0, step), KEY_UP: Vector2(0, step),
		KEY_S: Vector2(0, -step), KEY_DOWN: Vector2(0, -step)}
	for code: Key in cases:
		_view.set_pan(Vector2(-40, -100))
		cam.key_input(_key(code))
		cam.tick(DELTA, _park(), false)
		cam.key_input(_key(code, false))
		assert_vector(_view.pan - Vector2(-40, -100)).override_failure_message("key %d" % code) \
			.is_equal_approx(cases[code], Vector2(1e-3, 1e-3))


func test_right_and_middle_drag_pan_one_to_one_and_other_motion_does_not() -> void:
	var cam := _cam()
	_view.set_pan(Vector2(-40, 0))
	assert_bool(cam.input(_motion(Vector2(-10, 0), MOUSE_BUTTON_MASK_RIGHT))).is_true()
	assert_vector(_view.pan).is_equal(Vector2(-50, 0))
	assert_bool(cam.input(_motion(Vector2(15, 0), MOUSE_BUTTON_MASK_MIDDLE))).is_true()
	assert_vector(_view.pan).is_equal(Vector2(-35, 0))
	assert_bool(cam.input(_motion(Vector2(15, 0), MOUSE_BUTTON_MASK_LEFT))).is_false()
	assert_bool(cam.input(_motion(Vector2(15, 0), 0))).is_false()
	assert_vector(_view.pan).is_equal(Vector2(-35, 0))


func test_the_wheel_pans_a_cell_per_notch_and_shift_turns_it_horizontal() -> void:
	var step := _view_cell() * BoardCamera.WHEEL_CELLS
	var cam := _cam(24, 20)
	_view.set_pan(Vector2(-40, -100))
	cam.input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	assert_vector(_view.pan).is_equal(Vector2(-40, -100 + step))
	cam.input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	cam.input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	assert_vector(_view.pan).is_equal(Vector2(-40, -100 - step))
	_view.set_pan(Vector2(-40, -100))
	cam.input(_wheel(MOUSE_BUTTON_WHEEL_UP, true))
	assert_vector(_view.pan).is_equal(Vector2(-40 + step, -100))
	cam.input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, true))
	cam.input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, true))
	assert_vector(_view.pan).is_equal(Vector2(-40 - step, -100))
	_view.set_pan(Vector2(-40, -100))
	cam.input(_wheel(MOUSE_BUTTON_WHEEL_LEFT))
	assert_vector(_view.pan).is_equal(Vector2(-40 + step, -100))
	cam.input(_wheel(MOUSE_BUTTON_WHEEL_RIGHT))
	cam.input(_wheel(MOUSE_BUTTON_WHEEL_RIGHT))
	assert_vector(_view.pan).is_equal(Vector2(-40 - step, -100))
	# a release is not a notch
	_view.set_pan(Vector2(-40, -100))
	cam.input(_wheel(MOUSE_BUTTON_WHEEL_UP, false, false))
	assert_vector(_view.pan).is_equal(Vector2(-40, -100))


func _view_cell() -> float:
	return _view.cells_to_px(1.0)


func test_a_pan_gesture_moves_the_pan_by_a_cell_per_unit_and_a_left_click_never_pans() -> void:
	var cam := _cam(24, 20)
	_view.set_pan(Vector2(-40, -100))
	var g := InputEventPanGesture.new()
	g.delta = Vector2(1, 0)
	assert_bool(cam.input(g)).is_true()
	assert_vector(_view.pan).is_equal(Vector2(-40 - _view.cells_to_px(1.0), -100))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_bool(cam.input(click)).is_false()
	assert_vector(_view.pan).is_equal(Vector2(-40 - _view.cells_to_px(1.0), -100))


func test_every_pan_is_clamped() -> void:
	var cam := _cam()
	var lo := _range(cam)[0]
	var hi := _range(cam)[1]
	_view.set_pan(lo)
	cam.input(_motion(Vector2(-500, 0), MOUSE_BUTTON_MASK_RIGHT))
	assert_vector(_view.pan).is_equal(lo)
	cam.input(_motion(Vector2(5000, 0), MOUSE_BUTTON_MASK_RIGHT))
	assert_vector(_view.pan).is_equal(hi)
	cam.input(_wheel(MOUSE_BUTTON_WHEEL_UP))  # no vertical travel today
	assert_float(_view.pan.y).is_equal(0.0)


# --- R5: a shortcut is not a pan ----------------------------------------------------------------

func test_a_pan_key_with_a_modifier_is_not_taken_and_a_release_still_clears_the_hold() -> void:
	var cam := _cam()
	_view.set_pan(Vector2(-40, 0))
	assert_bool(cam.key_input(_key(KEY_D, true, true))).is_false()  # Ctrl+D
	cam.tick(DELTA, _park(), false)
	assert_vector(_view.pan).is_equal(Vector2(-40, 0))
	var meta := _key(KEY_A)
	meta.meta_pressed = true
	assert_bool(cam.key_input(meta)).is_false()
	var alt := _key(KEY_A)
	alt.alt_pressed = true
	assert_bool(cam.key_input(alt)).is_false()
	cam.tick(DELTA, _park(), false)
	assert_vector(_view.pan).is_equal(Vector2(-40, 0))
	# held plain, then released with a modifier down: the key must not stick
	assert_bool(cam.key_input(_key(KEY_D))).is_true()
	assert_bool(cam.key_input(_key(KEY_D, false, true))).is_true()
	cam.tick(DELTA, _park(), false)
	assert_vector(_view.pan).is_equal(Vector2(-40, 0))


# --- 13: edge pan ------------------------------------------------------------------------------

func test_edge_pan_starts_after_the_dwell_and_not_before() -> void:
	var cam := _cam()
	var v := cam.visible_rect
	var strip := Vector2(v.end.x - BoardCamera.EDGE_PX * 0.5, v.get_center().y)
	assert_bool(v.has_point(strip)).is_true()
	assert_vector(cam.edge_look(strip)).is_equal(Vector2.RIGHT)
	cam.tick(0.2, strip)
	assert_vector(_view.pan).is_equal(Vector2.ZERO)
	cam.tick(0.2, strip)  # 0.1 s past the dwell
	assert_vector(_view.pan).is_equal_approx(
		Vector2(-BoardCamera.EDGE_SPEED * (0.4 - BoardCamera.EDGE_DWELL), 0), Vector2(1e-3, 1e-3))
	# exactly the dwell moves nothing
	var cam2 := _cam()
	cam2.tick(BoardCamera.EDGE_DWELL, strip)
	assert_vector(_view.pan).is_equal(Vector2.ZERO)


func test_the_left_strip_pans_the_other_way() -> void:
	var cam := _cam()
	var lo := _range(cam)[0]
	_view.set_pan(lo)
	var v := cam.visible_rect
	var strip := Vector2(v.position.x + BoardCamera.EDGE_PX * 0.5, v.get_center().y)
	cam.tick(0.2, strip)
	cam.tick(0.2, strip)
	assert_float(_view.pan.x).is_equal_approx(
		lo.x + BoardCamera.EDGE_SPEED * (0.4 - BoardCamera.EDGE_DWELL), 1e-3)


func test_the_overlay_the_hud_and_the_footer_never_edge_pan() -> void:
	var cam := _cam()
	var v := cam.visible_rect
	var play := BoardView.play_rect()
	var spots := {
		"overlay": Vector2(SidePanel.panel_rect().position.x + 4.0, v.get_center().y),
		"overlay far edge": Vector2(play.end.x - 2.0, v.get_center().y),
		"hud": Vector2(v.get_center().x, play.position.y - 4.0),
		"footer": Vector2(v.get_center().x, play.end.y + 4.0),
		"footer corner": Vector2(v.end.x - 2.0, play.end.y + 4.0),
	}
	for label: String in spots:
		_view.set_pan(Vector2(-10, 0))
		cam.release_all()
		cam.tick(0.4, spots[label])
		cam.tick(0.4, spots[label])
		assert_vector(_view.pan).override_failure_message(label).is_equal(Vector2(-10, 0))


func test_leaving_the_strip_resets_the_dwell_and_no_edge_ok_means_no_pan() -> void:
	var cam := _cam()
	var v := cam.visible_rect
	var strip := Vector2(v.end.x - 2.0, v.get_center().y)
	cam.tick(0.2, strip)
	cam.tick(DELTA, _park())
	cam.tick(0.2, strip)  # 0.2 s again, not 0.4
	assert_vector(_view.pan).is_equal(Vector2.ZERO)
	var cam2 := _cam()
	cam2.tick(0.4, strip, false)
	cam2.tick(0.4, strip, false)  # Control hovered, unfocused, button held ...
	assert_vector(_view.pan).is_equal(Vector2.ZERO)


func test_no_edge_pan_along_an_axis_without_travel_and_none_at_night() -> void:
	var cam := _cam()  # the map fits the height: the top and bottom strips do nothing
	var v := cam.visible_rect
	cam.tick(0.4, Vector2(v.get_center().x, v.position.y + 2.0))
	cam.tick(0.4, Vector2(v.get_center().x, v.end.y - 2.0))
	assert_vector(_view.pan).is_equal(Vector2.ZERO)
	var night := _cam(24, 12, BoardView.play_rect())
	var p := BoardView.play_rect()
	night.tick(0.4, Vector2(p.end.x - 2.0, p.get_center().y))
	night.tick(0.4, Vector2(p.end.x - 2.0, p.get_center().y))
	night.tick(0.4, Vector2(p.position.x + 2.0, p.get_center().y))
	night.tick(0.4, Vector2(p.position.x + 2.0, p.get_center().y))
	assert_vector(_view.pan).is_equal(Vector2.ZERO)


# --- 14: ease --------------------------------------------------------------------------------

func _eased_cam() -> BoardCamera:
	var cam := _cam()
	cam.pan_by(Vector2(-1.0e6, 0))  # the far end of the day range
	assert_float(_view.pan.x).is_less(0.0)
	cam.set_visible_rect(BoardView.play_rect())  # the overlay hides
	return cam


func test_hiding_the_overlay_eases_the_pan_to_zero_through_the_smoothstep_midpoint() -> void:
	var cam := _eased_cam()
	var from := _view.pan
	assert_bool(cam.easing()).is_true()
	cam.tick(BoardCamera.EASE_SECONDS / 2.0, _park(), false)
	assert_float(_view.pan.x).is_equal_approx(from.x * 0.5, 1e-3)  # smoothstep(0.5) = 0.5
	assert_bool(cam.easing()).is_true()
	cam.tick(BoardCamera.EASE_SECONDS / 2.0, _park(), false)
	assert_float(_view.pan.x).is_equal(0.0)
	assert_bool(cam.easing()).is_false()


func test_user_input_during_the_ease_cancels_it_and_clamps_at_once() -> void:
	for how: String in ["pan_by", "held key", "wheel"]:
		var cam := _eased_cam()
		cam.tick(0.05, _park(), false)
		assert_bool(cam.easing()).is_true()
		match how:
			"pan_by":
				cam.pan_by(Vector2(-1, 0))
			"held key":
				cam.key_input(_key(KEY_D))
				cam.tick(DELTA, _park(), false)
			"wheel":
				cam.input(_wheel(MOUSE_BUTTON_WHEEL_RIGHT))
		assert_bool(cam.easing()).override_failure_message(how).is_false()
		assert_float(_view.pan.x).override_failure_message(how).is_equal(0.0)  # the night clamp


func test_showing_the_overlay_with_the_pan_already_inside_does_not_ease() -> void:
	var cam := _cam(24, 12, BoardView.play_rect())
	cam.set_visible_rect(_day_v())
	assert_bool(cam.easing()).is_false()


# --- 15: auto-reveal ---------------------------------------------------------------------------

func test_reveal_pans_by_the_least_amount_that_brings_the_point_inside_at_once() -> void:
	var cam := _cam()
	var v := cam.visible_rect
	var r := _view.cells_to_px(BoardCamera.REVEAL_CELLS)
	# a point under the overlay (at pan 0 its right box edge is past V.end)
	var p := Vector2(_view.px_to_cells(v.end.x) + 1.0, 3.5)
	var hi := _view.cell_to_screen(p).x + r
	assert_float(hi).is_greater(v.end.x)
	cam.reveal(p)
	assert_float(_view.pan.x).is_equal_approx(v.end.x - hi, 1e-3)
	assert_float(_view.cell_to_screen(p).x + r).is_equal_approx(v.end.x, 1e-3)
	assert_bool(cam.easing()).is_false()
	# a point already inside moves nothing
	var before := _view.pan
	cam.reveal(Vector2(3.5, 3.5))
	assert_vector(_view.pan).is_equal(before)
	# a point past the left edge comes back from the other side
	cam.pan_by(Vector2(-1.0e6, 0))
	var left := _view.cell_to_screen(Vector2(0.5, 3.5)).x - r
	assert_float(left).is_less(v.position.x)
	cam.reveal(Vector2(0.5, 3.5))
	assert_float(_view.cell_to_screen(Vector2(0.5, 3.5)).x - r).is_equal_approx(v.position.x, 1e-3)


# --- R4: the Board's input filter ----------------------------------------------------------------

class SpyCamera:
	extends BoardCamera
	var inputs := 0

	func input(event: InputEvent) -> bool:
		inputs += 1
		return super.input(event)


func test_the_board_hands_the_camera_only_drag_wheel_and_gesture_events() -> void:
	await _start_game()
	var board := _game.board
	var spy := SpyCamera.new(board.view)
	board.camera = spy
	board._unhandled_input(_motion(Vector2(3, 0), 0))  # a plain mouse move
	board._unhandled_input(_motion(Vector2(3, 0), MOUSE_BUTTON_MASK_LEFT))
	board._unhandled_input(_key(KEY_D))
	board._unhandled_input(_key(KEY_A, false))
	assert_int(spy.inputs).is_equal(0)
	board._unhandled_input(_motion(Vector2(3, 0), MOUSE_BUTTON_MASK_RIGHT))
	board._unhandled_input(_motion(Vector2(3, 0), MOUSE_BUTTON_MASK_MIDDLE))
	board._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	var g := InputEventPanGesture.new()
	board._unhandled_input(g)
	assert_int(spy.inputs).is_equal(4)
