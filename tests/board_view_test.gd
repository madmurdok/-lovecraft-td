class_name BoardViewTest
extends GdUnitTestSuite
## LT-35 (LT-65 §3.3, G2): BoardView, the screen <-> cell layer. Pinned from the spec with
## hand-computed numbers on a 7x5 grid (not square, so an x/y swap shows): picking at the
## board's edges, the HUD strip, the cell <-> screen inverse, world_rect, cell_rect, linearity,
## the board origin, light and relic-token positions, a standalone MapLayer, and picking
## through the running Game. The pixel numbers below (40 per cell, origin (0, 48)) are the
## spec's, written out on purpose: the view's own constants are not used to compute them.

const W := 7
const H := 5
const TILE := 40.0
const TOP := 48.0
const RIFLE := "rifleman"

var _vp: SubViewport
var _game: Game
var _config: GameConfig
var _view: BoardView


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_view = BoardView.new()
	_view.grid = SquareGrid.new(W, H)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _start_game(size := Vector2i(1200, 675)) -> void:
	_vp = GameFixture.make_viewport(self, size)
	_game = GameFixture.make_game(_vp, _config, 7)
	await get_tree().process_frame


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		_vp.push_input(ev)
	await get_tree().process_frame


func _buildable_cell() -> Vector2i:
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			if m.is_buildable(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _screen_of(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, TOP + cell.y * TILE + TILE / 2.0)


# --- 1. picking: edges, HUD strip, off board ----------------------------------------------

func test_the_four_corner_cells_are_picked_at_their_centres() -> void:
	assert_vector(_view.cell_at_screen(Vector2(20, TOP + 20))).is_equal(Vector2i(0, 0))
	assert_vector(_view.cell_at_screen(Vector2(W * TILE - 20, TOP + 20))).is_equal(Vector2i(W - 1, 0))
	assert_vector(_view.cell_at_screen(Vector2(20, TOP + H * TILE - 20))).is_equal(Vector2i(0, H - 1))
	assert_vector(_view.cell_at_screen(Vector2(W * TILE - 20, TOP + H * TILE - 20))) \
		.is_equal(Vector2i(W - 1, H - 1))


func test_a_point_just_inside_each_outer_edge_is_on_the_board() -> void:
	assert_vector(_view.cell_at_screen(Vector2(0.0, TOP))).is_equal(Vector2i(0, 0))
	assert_vector(_view.cell_at_screen(Vector2(W * TILE - 0.01, TOP + 100))).is_equal(Vector2i(W - 1, 2))
	assert_vector(_view.cell_at_screen(Vector2(100, TOP + H * TILE - 0.01))).is_equal(Vector2i(2, H - 1))
	assert_vector(_view.cell_at_screen(Vector2(0.0, TOP + 100))).is_equal(Vector2i(0, 2))


func test_a_point_just_outside_each_outer_edge_is_off_board() -> void:
	var off := BoardView.OFF_BOARD
	assert_vector(_view.cell_at_screen(Vector2(-0.01, TOP + 100))).is_equal(off)  # left
	assert_vector(_view.cell_at_screen(Vector2(W * TILE, TOP + 100))).is_equal(off)  # right
	assert_vector(_view.cell_at_screen(Vector2(100, TOP - 0.01))).is_equal(off)  # top
	assert_vector(_view.cell_at_screen(Vector2(100, TOP + H * TILE))).is_equal(off)  # bottom
	assert_vector(_view.cell_at_screen(Vector2(-1, TOP - 1))).is_equal(off)  # corner
	assert_vector(_view.cell_at_screen(Vector2(5000, 5000))).is_equal(off)


func test_the_hud_strip_is_off_board_across_its_whole_height_and_width() -> void:
	for y in [0.0, 1.0, 24.0, TOP - 0.5]:
		for x in [0.0, 100.0, 279.0, 600.0]:
			assert_vector(_view.cell_at_screen(Vector2(x, y))).override_failure_message(
				"(%s, %s)" % [x, y]).is_equal(BoardView.OFF_BOARD)


func test_a_tile_edge_belongs_to_the_next_cell() -> void:
	# floor, not round: x = 40k is cell k; 40k - 0.01 is cell k-1; the same on y.
	for k in range(1, W):
		assert_int(_view.cell_at_screen(Vector2(k * TILE, TOP + 10)).x).is_equal(k)
		assert_int(_view.cell_at_screen(Vector2(k * TILE - 0.01, TOP + 10)).x).is_equal(k - 1)
		assert_int(_view.cell_at_screen(Vector2(k * TILE + 19.99, TOP + 10)).x).is_equal(k)
		assert_int(_view.cell_at_screen(Vector2(k * TILE - 19.99, TOP + 10)).x).is_equal(k - 1)
	for k in range(1, H):
		assert_int(_view.cell_at_screen(Vector2(10, TOP + k * TILE)).y).is_equal(k)
		assert_int(_view.cell_at_screen(Vector2(10, TOP + k * TILE - 0.01)).y).is_equal(k - 1)


func test_without_a_grid_every_point_is_off_board() -> void:
	var v := BoardView.new()
	assert_vector(v.cell_at_screen(Vector2(100, 100))).is_equal(BoardView.OFF_BOARD)


# --- 2. the cell <-> screen inverse -----------------------------------------------------------

func test_cell_at_screen_inverts_cell_to_screen_over_every_cell() -> void:
	assert_int(_view.grid.cells().size()).is_equal(W * H)
	for c in _view.grid.cells():
		var p := _view.cell_to_screen(_view.grid.centre(c))
		assert_vector(p).is_equal(_screen_of(c))
		assert_vector(_view.cell_at_screen(p)).override_failure_message(str(c)).is_equal(c)


func test_the_inverse_holds_over_the_configured_map_and_all_four_tile_corners() -> void:
	var m := _config.map
	var v := BoardView.new()
	v.grid = m.grid
	for c in m.grid.cells():
		assert_vector(v.cell_at_screen(v.cell_to_screen(m.grid.centre(c)))).is_equal(c)
		var tl := Vector2(c.x * TILE, TOP + c.y * TILE)
		assert_vector(v.cell_at_screen(tl)).override_failure_message("tl %s" % c).is_equal(c)
		assert_vector(v.cell_at_screen(tl + Vector2(39.99, 39.99))) \
			.override_failure_message("br %s" % c).is_equal(c)


# --- 3. world_rect --------------------------------------------------------------------------------

func test_world_rect_is_the_grid_size_in_pixels_anchored_at_the_origin() -> void:
	assert_object(_view.world_rect()).is_equal(Rect2(0, TOP, W * TILE, H * TILE))
	assert_object(BoardView.world_rect_for(_view.grid)).is_equal(_view.world_rect())
	assert_vector(_view.origin()).is_equal(Vector2(0, TOP))


func test_world_rect_of_the_configured_map_and_its_layout_anchors() -> void:
	var m := _config.map
	var want := Rect2(0, TOP, m.width * TILE, m.height * TILE)
	assert_object(BoardView.world_rect_for(m.grid)).is_equal(want)
	assert_float(SidePanel.panel_rect(m).position.x).is_equal(want.end.x)
	assert_float(SidePanel.panel_rect(m).position.y).is_equal(TOP)


func test_world_rect_is_the_same_in_a_1200x675_and_a_1920x1080_viewport() -> void:
	var m := _config.map
	var want := Rect2(0, TOP, m.width * TILE, m.height * TILE)
	for size: Vector2i in [Vector2i(1200, 675), Vector2i(1920, 1080)]:
		await _start_game(size)
		assert_object(_game.board.view.world_rect()).override_failure_message(str(size)) \
			.is_equal(want)
		assert_object(_game.hud.board_rect()).is_equal(want)
		var bg: Control = _game.hud.get_node("Background")
		assert_float(bg.size.y).is_equal(TOP)  # the HUD bar is the strip above the board
		assert_float(_game.side_panel.position.x).is_equal(want.end.x)
		_vp.queue_free()
		_vp = null
		await get_tree().process_frame


# --- 4. cell_rect = the polygon's bounding box ----------------------------------------------

func test_cell_rect_is_the_tile_and_equals_the_polygon_bbox() -> void:
	for c in _view.grid.cells():
		var poly := _view.cell_polygon(c)
		assert_int(poly.size()).is_equal(4)
		var lo := poly[0]
		var hi := poly[0]
		for p in poly:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		var r := _view.cell_rect(c)
		assert_object(r).override_failure_message(str(c)).is_equal(Rect2(lo, hi - lo))
		assert_object(r).override_failure_message(str(c)).is_equal(
			Rect2(c.x * TILE, c.y * TILE, TILE, TILE))  # board-local: no origin


func test_cell_rect_tiles_tile_without_gaps_or_overlap() -> void:
	var area := 0.0
	for c in _view.grid.cells():
		area += _view.cell_rect(c).get_area()
		var right := Vector2i(c.x + 1, c.y)
		if _view.grid.contains(right):
			assert_float(_view.cell_rect(c).end.x).is_equal(_view.cell_rect(right).position.x)
	assert_float(area).is_equal(W * H * TILE * TILE)


# --- 5. linearity -------------------------------------------------------------------------------

func test_cell_to_world_is_linear_so_offsets_and_directions_scale() -> void:
	var a := Vector2(1.25, -3.5)
	var b := Vector2(0.5, 2.0)
	assert_vector(_view.cell_to_world(Vector2.ZERO)).is_equal(Vector2.ZERO)
	assert_vector(_view.cell_to_world(a + b)).is_equal_approx(
		_view.cell_to_world(a) + _view.cell_to_world(b), Vector2(1e-4, 1e-4))
	assert_vector(_view.cell_to_world(a * 3.0)).is_equal_approx(
		_view.cell_to_world(a) * 3.0, Vector2(1e-4, 1e-4))
	assert_vector(_view.cell_to_world(Vector2(1, 0))).is_equal(Vector2(TILE, 0))
	assert_vector(_view.cell_to_world(Vector2(0, 1))).is_equal(Vector2(0, TILE))


func test_screen_is_world_plus_the_origin_and_lengths_round_trip() -> void:
	var p := Vector2(2.5, 1.5)
	assert_vector(_view.cell_to_screen(p)).is_equal(Vector2(100, TOP + 60))
	assert_vector(_view.cell_to_screen(p)).is_equal(_view.origin() + _view.cell_to_world(p))
	assert_float(_view.cells_to_px(1.0)).is_equal(TILE)
	assert_float(_view.cells_to_px(2.5)).is_equal(100.0)
	assert_float(_view.px_to_cells(100.0)).is_equal(2.5)
	for len in [0.0, 0.3, 1.0, 7.75]:
		assert_float(_view.px_to_cells(_view.cells_to_px(len))).is_equal_approx(len, 1e-5)


# --- 6. board origin, light and relic positions, standalone MapLayer ------------------------

func test_board_sits_at_the_view_origin_and_shares_one_grid_with_its_layer() -> void:
	await _start_game()
	assert_vector(_game.board.position).is_equal(Vector2(0, TOP))
	assert_vector(_game.board.position).is_equal(_game.board.view.origin())
	assert_object(_game.board.view.grid).is_same(_game.sim.state.map.grid)
	assert_object(_game.board.map_layer.view).is_same(_game.board.view)


func test_tower_lights_and_the_lighthouse_glow_sit_at_cell_centres_in_world() -> void:
	await _start_game()
	_game.sim.state.gold = 100000
	var c := _buildable_cell()
	assert_int(_game.commands.build(RIFLE, c)).is_equal(Simulation.CommandResult.OK)
	await get_tree().process_frame
	var t := _game.sim.tower_by_id(_game.sim.state.tower_at[c])
	assert_vector(_game.lighting._tower_lights[t.id].position).is_equal(
		Vector2(c.x * TILE + 20.0, c.y * TILE + 20.0))  # world: no origin
	var lh := _game.sim.state.map.lighthouse
	assert_vector(_game.lighting.glow.position).is_equal(
		Vector2(lh.x * TILE + 20.0, lh.y * TILE + 20.0))


func test_relic_tokens_start_on_screen_coordinates() -> void:
	await _start_game()
	assert_vector(_game.relic_tokens.board_to_layer(Vector2(3.5, 2.5))) \
		.is_equal(Vector2(140, TOP + 100))
	assert_vector(_game.relic_tokens.board_to_layer(Vector2.ZERO)).is_equal(Vector2(0, TOP))


func test_a_standalone_map_layer_draws_with_its_own_view() -> void:
	_vp = GameFixture.make_viewport(self)
	var layer := Board.MapLayer.new()
	_vp.add_child(layer)
	await get_tree().process_frame
	var draws: Array[int] = [0]
	layer.draw.connect(func() -> void: draws[0] += 1)
	layer.set_map(_config.map)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(draws[0]).is_equal(1)
	assert_object(layer.view.grid).is_same(_config.map.grid)
	var m := _config.map
	assert_object(layer.view.cell_rect(m.lighthouse)).is_equal(
		Rect2(m.lighthouse.x * TILE, m.lighthouse.y * TILE, TILE, TILE))


# --- 7. picking through the view in the game ----------------------------------------------------

func test_a_click_at_a_buildable_cells_screen_centre_opens_the_picker_and_builds_there() -> void:
	await _start_game()
	var c := _buildable_cell()
	var gold := _game.sim.state.gold
	await _click(_screen_of(c))
	assert_bool(_game.picker.visible).is_true()
	assert_vector(_game.picker.cell).is_equal(c)
	await _click(_game.picker.buttons[RIFLE].get_global_rect().get_center())
	assert_bool(_game.sim.state.tower_at.has(c)).is_true()
	assert_int(_game.sim.state.gold).is_equal(gold - _config.towers[RIFLE].cost)


func test_clicks_on_a_tower_and_on_the_lighthouse_open_their_panels() -> void:
	await _start_game()
	_game.sim.state.gold = 100000
	var c := _buildable_cell()
	assert_int(_game.commands.build(RIFLE, c)).is_equal(Simulation.CommandResult.OK)
	await get_tree().process_frame
	await _click(_screen_of(c))
	assert_bool(_game.tower_panel.visible).is_true()
	assert_bool(_game.picker.visible).is_false()
	await _click(_screen_of(_game.sim.state.map.lighthouse))
	assert_bool(_game.lighthouse_panel.visible).is_true()
	assert_bool(_game.tower_panel.visible).is_false()


func test_board_signals_follow_the_view_cell_and_off_board() -> void:
	await _start_game()
	var cells: Array[Vector2i] = []
	var outside: Array[int] = [0]
	_game.board.cell_clicked.connect(func(c: Vector2i) -> void: cells.append(c))
	_game.board.outside_clicked.connect(func() -> void: outside[0] += 1)
	var m := _game.sim.state.map
	var last := Vector2i(m.width - 1, m.height - 1)
	await _click(_screen_of(Vector2i(0, 0)))
	await _click(_screen_of(last))
	assert_array(cells).is_equal([Vector2i(0, 0), last])
	assert_int(outside[0]).is_equal(0)
	# One pixel below the board's bottom edge, off the right edge: off board.
	await _click(Vector2(100, TOP + m.height * TILE + 1.0))
	assert_int(outside[0]).is_equal(1)
	assert_array(cells).has_size(2)
	# The first pixel row of the board, and the last one above it (HUD strip side panel free).
	await _click(Vector2(100, TOP + 0.5))
	assert_array(cells).has_size(3)
	assert_vector(cells[2]).is_equal(Vector2i(2, 0))
