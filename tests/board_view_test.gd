class_name BoardViewTest
extends GdUnitTestSuite
## LT-35 (LT-65 §3.3, G2): BoardView, the screen <-> cell layer. Pinned from the spec with
## hand-computed numbers on a 7x5 grid (not square, so an x/y swap shows): picking at the
## board's edges, the HUD strip, the cell <-> screen inverse, world_rect, cell_polygon, linearity,
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
	var r := ConfigLoader.load_dir("res://data")
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
	assert_float(SidePanel.panel_rect().position.y).is_equal(TOP)  # LT-66: below the HUD bar


func test_world_rect_is_the_same_in_a_1200x675_and_a_1920x1080_viewport() -> void:
	var m := _config.map
	var want := Rect2(0, TOP, m.width * TILE, m.height * TILE)
	for size: Vector2i in [Vector2i(1200, 675), Vector2i(1920, 1080)]:
		await _start_game(size)
		assert_object(_game.board.view.world_rect()).override_failure_message(str(size)) \
			.is_equal(want)
		# LT-66 §6.1: the HUD lays out on the fixed play frame, not on the (pannable) map
		assert_object(_game.hud.board_rect()).is_equal(Rect2(0, TOP, 1200, want.size.y))
		assert_object(_game.hud.board_rect()).is_equal(BoardView.play_rect())
		var bg: Control = _game.hud.get_node("Background")
		assert_float(bg.size.y).is_equal(TOP)  # the HUD bar is the strip above the board
		assert_float(_game.side_panel.position.x).is_equal(SidePanel.panel_rect().position.x)
		_vp.queue_free()
		_vp = null
		await get_tree().process_frame


# --- 4. cell_polygon = the square tile (LT-108: cell_rect deleted) ---------------------------

## The corners of the square tile rect `r`, screen-clockwise from the top-left.
func _corners(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y)])


## The area of a simple polygon (shoelace).
func _area(poly: PackedVector2Array) -> float:
	var twice := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		twice += p.x * q.y - q.x * p.y
	return absf(twice) * 0.5


func test_cell_polygon_is_the_square_tile() -> void:
	for c in _view.grid.cells():
		assert_object(_view.cell_polygon(c)).override_failure_message(str(c)).is_equal(
			_corners(Rect2(c.x * TILE, c.y * TILE, TILE, TILE)))  # board-local: no origin


func test_cell_polygons_tile_without_gaps_or_overlap() -> void:
	var area := 0.0
	for c in _view.grid.cells():
		var poly := _view.cell_polygon(c)
		area += _area(poly)
		var right := Vector2i(c.x + 1, c.y)
		if _view.grid.contains(right):  # the shared edge: this tile's right, its left
			var rp := _view.cell_polygon(right)
			assert_object(poly[1]).override_failure_message(str(c)).is_equal(rp[0])
			assert_object(poly[2]).override_failure_message(str(c)).is_equal(rp[3])
	assert_float(area).is_equal(W * H * TILE * TILE)


# --- 4b. inset tiles and outline quads (LT-108 §6 items 3, 4, 6) --------------------------------

const INSETS: Array[float] = [0.0, 2.0, 4.0, 6.0]


## The summed area of Geometry2D's intersection of two polygons (0 when they only touch).
func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var sum := 0.0
	for p in Geometry2D.intersect_polygons(a, b):
		sum += _area(p)
	return sum


func _hex_view() -> BoardView:
	var v := BoardView.new()
	v.grid = HexGrid.new(5, 4)
	return v


func test_an_inset_square_tile_is_the_tile_rect_grown_by_minus_the_inset() -> void:
	for d in INSETS:
		for c in _view.grid.cells():
			assert_object(_view.cell_polygon(c, d)).override_failure_message("%s inset %s" % [c, d]) \
				.is_equal(_corners(Rect2(c.x * TILE, c.y * TILE, TILE, TILE).grow(-d)))


func test_square_outline_quads_are_the_ring_between_the_two_insets() -> void:
	var c := Vector2i(1, 1)  # the tile (40, 40)..(80, 80)
	var quads := _view.outline_quads(c, 2.0, 0.0)
	var outer := _corners(Rect2(39, 39, 42, 42))  # inset - w/2
	var inner := _corners(Rect2(41, 41, 38, 38))  # inset + w/2
	assert_int(quads.size()).is_equal(4)
	for i in 4:
		var j := (i + 1) % 4
		assert_object(quads[i]).override_failure_message("quad %d" % i).is_equal(
			PackedVector2Array([outer[i], outer[j], inner[j], inner[i]]))


func _assert_outline_ring(view: BoardView, sides: int) -> void:
	for c in view.grid.cells():
		for w: float in [1.0, 2.0, 4.0]:
			for d in INSETS:
				var quads := view.outline_quads(c, w, d)
				var outer := view.cell_polygon(c, d - w * 0.5)
				var inner := view.cell_polygon(c, d + w * 0.5)
				var tag := "%s w %s inset %s" % [c, w, d]
				assert_int(quads.size()).override_failure_message(tag).is_equal(sides)
				var area := 0.0
				for i in quads.size():
					area += _area(quads[i])
					# outer corners first, inner last (a swap draws the same band inside out)
					assert_object(quads[i][0]).override_failure_message(tag).is_equal(outer[i])
					assert_object(quads[i][3]).override_failure_message(tag).is_equal(inner[i])
					for k in range(i + 1, quads.size()):
						assert_float(_overlap(quads[i], quads[k])) \
							.override_failure_message("%s quads %d, %d" % [tag, i, k]) \
							.is_less(1e-3)
				assert_float(area).override_failure_message(tag) \
					.is_equal_approx(_area(outer) - _area(inner), 1e-3)


func test_outline_quads_cover_the_ring_without_overlap_on_square() -> void:
	_assert_outline_ring(_view, 4)


func test_outline_quads_cover_the_ring_without_overlap_on_hex() -> void:
	_assert_outline_ring(_hex_view(), 6)


func test_hex_tiles_are_hexagons_that_tile_without_overlap() -> void:
	var hex := _hex_view()
	var area := 0.0
	for c in hex.grid.cells():
		var poly := hex.cell_polygon(c)
		assert_int(poly.size()).override_failure_message(str(c)).is_equal(6)
		area += _area(poly)
		for n in hex.grid.neighbours(c):
			assert_float(_overlap(poly, hex.cell_polygon(n))) \
				.override_failure_message("%s / %s" % [c, n]).is_less(1e-3)
	# each hex is sqrt(3) / 2 cell units^2 (flat-to-flat width 1)
	assert_float(area).is_equal_approx(20 * sqrt(3.0) / 2.0 * TILE * TILE, 1e-2)


func test_an_inset_hex_tile_keeps_its_apothem_minus_the_inset() -> void:
	var hex := _hex_view()
	for c in hex.grid.cells():
		var centre := hex.cell_centre(c)
		for d in INSETS:
			var poly := hex.cell_polygon(c, d)
			for i in poly.size():
				var mid := (poly[i] + poly[(i + 1) % poly.size()]) * 0.5
				assert_float(mid.distance_to(centre)) \
					.override_failure_message("%s inset %s edge %d" % [c, d, i]) \
					.is_equal_approx(TILE * 0.5 - d, 1e-3)


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
	assert_int(_game.commands.build(RIFLE, c)).is_equal(SimCommand.CommandResult.OK)
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
	assert_object(layer.view.cell_polygon(m.lighthouse)).is_equal(
		_corners(Rect2(m.lighthouse.x * TILE, m.lighthouse.y * TILE, TILE, TILE)))


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
	assert_int(_game.commands.build(RIFLE, c)).is_equal(SimCommand.CommandResult.OK)
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
	# LT-66 §1: the day overlay lies over the right columns; the last cell left of it.
	var last := Vector2i(mini(m.width, int(SidePanel.panel_rect().position.x / TILE)) - 1,
		m.height - 1)
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


# --- 7. LT-126 (LT-64 §1.3): the named roles at identity -----------------------------------------
# Spy views subclass BoardView: GDScript dispatches the view's own calls (ring -> ground,
# cell_to_screen -> project) to the override, so a spy shows which role a function goes
# through. Numbers are written out from the spec (40 px per cell, origin (0, 48)).

const SHIFT := Vector2(1000, -300)  ## a non-identity project: the upright frame moved
const PAN := Vector2(30, 10)


## project moved by SHIFT (a camera body under b2 would change it; ground must not follow).
class ShiftedView:
	extends BoardView

	func project(p_cells: Vector2, h_cells := 0.0) -> Vector2:
		return super.project(p_cells, h_cells) + SHIFT


## Records every ground / project / cells_to_px argument it is asked for.
class RecordingView:
	extends BoardView
	var grounds: Array[Vector2] = []
	var projects: Array[Vector2] = []
	var lengths: Array[float] = []

	func ground(p_cells: Vector2) -> Vector2:
		grounds.append(p_cells)
		return super.ground(p_cells)

	func project(p_cells: Vector2, h_cells := 0.0) -> Vector2:
		projects.append(p_cells)
		return super.project(p_cells, h_cells)

	func cells_to_px(len_cells: float) -> float:
		lengths.append(len_cells)
		return super.cells_to_px(len_cells)


## Calls view.ring once inside its own _draw (drawing is only allowed there).
class RingHost:
	extends Node2D
	var view: BoardView
	var draws := 0

	func _draw() -> void:
		draws += 1
		view.ring(self, Vector2(2.5, 1.5), 1.75, Color.RED, 2.0, 16, 0.25, 1.5)


func _pan_screen(p_cells: Vector2, pan: Vector2) -> Vector2:
	return Vector2(0, TOP) + pan + p_cells * TILE


# 7.1 project / unproject / cell_to_screen: the pan is added once and removed once.

func test_project_and_ground_are_the_cell_scale_at_identity_and_the_lift_is_screen_up() -> void:
	for p: Vector2 in [Vector2.ZERO, Vector2(2.5, 1.5), Vector2(-1.25, 3.75), Vector2(6.9, -0.1)]:
		assert_vector(_view.ground(p)).is_equal(p * TILE)
		assert_vector(_view.project(p)).is_equal(p * TILE)
		assert_vector(_view.project(p, 0.4)).is_equal_approx(
			p * TILE + Vector2(0, -0.4 * TILE), Vector2(1e-4, 1e-4))
		assert_vector(_view.project(p, -0.3)).is_equal_approx(
			p * TILE + Vector2(0, 0.3 * TILE), Vector2(1e-4, 1e-4))
		assert_float(_view.depth(p)).is_equal(0.0)


func test_unproject_inverts_cell_to_screen_with_the_pan_added_once() -> void:
	_view.set_pan(PAN)
	for p: Vector2 in [Vector2(0.5, 0.5), Vector2(2.5, 1.5), Vector2(6.25, 4.75), Vector2(-1, 7)]:
		var s := _view.cell_to_screen(p)
		assert_vector(s).override_failure_message(str(p)).is_equal(_pan_screen(p, PAN))
		assert_vector(_view.unproject(s)).is_equal_approx(p, Vector2(1e-5, 1e-5))
		assert_vector(_view.unproject(_pan_screen(p, PAN))).is_equal_approx(p, Vector2(1e-5, 1e-5))


func test_cell_picking_under_a_pan_follows_the_moved_board() -> void:
	_view.set_pan(PAN)
	for c in _view.grid.cells():
		var s := _pan_screen(_view.grid.centre(c), PAN)
		assert_vector(_view.cell_at_screen(s)).override_failure_message(str(c)).is_equal(c)
	# The unpanned centre of (0, 0) now lies left of / above the moved board: off it.
	assert_vector(_view.cell_at_screen(Vector2(20, TOP + 5))).is_equal(BoardView.OFF_BOARD)
	assert_vector(_view.cell_at_screen(_pan_screen(Vector2(-0.01, 2.5), PAN))) \
		.is_equal(BoardView.OFF_BOARD)
	assert_vector(_view.cell_at_screen(_pan_screen(Vector2(W + 0.01, 2.5), PAN))) \
		.is_equal(BoardView.OFF_BOARD)


func test_a_non_identity_project_reaches_the_screen_through_one_origin_and_one_pan() -> void:
	var v := ShiftedView.new()
	v.grid = SquareGrid.new(W, H)
	v.set_pan(PAN)
	var p := Vector2(2.5, 1.5)
	assert_vector(v.cell_to_screen(p)).is_equal(_pan_screen(p, PAN) + SHIFT)
	assert_vector(v.cell_centre(Vector2i(2, 1))).is_equal(p * TILE + SHIFT)
	# The pan bounds are the projected map's bbox, moved by the origin and the pan once.
	assert_that(v.world_rect()).is_equal(Rect2(Vector2(0, TOP) + PAN + SHIFT, Vector2(W, H) * TILE))
	assert_that(v.project_rect(Rect2(1, 2, 3, 4))).is_equal(
		Rect2(Vector2(40, 80) + SHIFT, Vector2(120, 160)))


# 7.2 ring: at identity the draw_arc of today (centre via ground, radius in px).

func test_ring_at_identity_centres_on_ground_and_scales_the_radius_by_the_cell() -> void:
	var v := RecordingView.new()
	v.grid = SquareGrid.new(W, H)
	var host := RingHost.new()
	host.view = v
	_vp = GameFixture.make_viewport(self)
	_vp.add_child(host)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(host.draws).is_greater(0)
	var grounds := v.grounds.duplicate()
	var lengths := v.lengths.duplicate()
	assert_int(grounds.size()).is_equal(host.draws)  # one ground call per ring
	assert_array(grounds.filter(func(g: Vector2) -> bool: return g != Vector2(2.5, 1.5))).is_empty()
	assert_array(v.projects).is_empty()  # a ring is G: never through project
	assert_int(lengths.size()).is_equal(host.draws)
	assert_array(lengths.filter(func(r: float) -> bool: return r != 1.75)).is_empty()
	assert_vector(v.ground(Vector2(2.5, 1.5))).is_equal(Vector2(100, 60))
	assert_float(v.cells_to_px(1.75)).is_equal(70.0)


## draw_arc's arguments cannot be read back headless (no renderer, and a script override of
## the native draw_arc is not reached through a CanvasItem parameter), so the pass-through of
## points / start / end / colour / width to the old draw_arc order is pinned on the source.
func test_ring_passes_points_start_end_colour_and_width_through_to_draw_arc() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/board/board_view.gd")
	var at := src.find("\nfunc ring(")
	assert_int(at).is_greater_equal(0)
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_str(body).contains("points := 48, start := 0.0, end := TAU)")
	assert_str(body).contains(
		"ci.draw_arc(ground(centre_cells), cells_to_px(r_cells), start, end, points, color, width)")


# 7.3 ground: p * cell, never the pan, never project.

func test_ground_and_ground_rect_are_the_plain_cell_scale_whatever_the_pan() -> void:
	_view.set_pan(PAN)
	for p: Vector2 in [Vector2(2.5, 1.5), Vector2(-1.25, 3.75), Vector2(0.1, -7.5)]:
		assert_vector(_view.ground(p)).is_equal(p * _view.cells_to_px(1.0))
		assert_vector(_view.ground(p)).is_equal(p * TILE)
	assert_that(_view.ground_rect(Rect2(-2, -1, 9, 7))).is_equal(Rect2(-80, -40, 360, 280))
	assert_that(_view.ground_rect(Rect2(0, 0, W, H))).is_equal(Rect2(0, 0, W * TILE, H * TILE))


func test_ground_sites_do_not_follow_a_non_identity_project() -> void:
	var v := ShiftedView.new()
	v.grid = SquareGrid.new(W, H)
	var c := Vector2i(3, 2)
	assert_vector(v.ground(Vector2(3.5, 2.5))).is_equal(Vector2(140, 100))
	assert_that(v.ground_rect(Rect2(0, 0, W, H))).is_equal(Rect2(0, 0, W * TILE, H * TILE))
	assert_array(Array(v.cell_polygon(c))).is_equal(Array(_view.cell_polygon(c)))
	assert_array(Array(v.cell_polygon(c, 4.0))).is_equal(Array(_view.cell_polygon(c, 4.0)))
	assert_array(Array(_view.cell_polygon(c))).contains_exactly_in_any_order(
		[Vector2(120, 80), Vector2(160, 80), Vector2(160, 120), Vector2(120, 120)])


# 7.4 upright-first picking through the running Game, under a pan.

func _night() -> void:
	assert_int(_game.commands.call_wave()).is_equal(SimCommand.CommandResult.OK)
	_game.sim.step()
	_game.advance(0.0)


func test_a_click_on_an_enemy_body_over_the_next_cell_picks_the_enemy_else_the_ground_cell() \
		-> void:
	await _start_game()
	_night()
	var board := _game.board
	board.view.set_pan(PAN)
	var picks: Array = []
	board.enemy_clicked.connect(func(id: int) -> void: picks.append(["enemy", id]))
	board.cell_clicked.connect(func(c: Vector2i) -> void: picks.append(["cell", c]))
	board.outside_clicked.connect(func() -> void: picks.append(["outside"]))
	var id := _game.sim.spawn_enemy("cultist")
	GameFixture.sync(_game)
	board.last_pos.clear()
	var at := Vector2(4.9, 3.5)  # in cell (4, 3), its body reaches over into (5, 3)
	board.last_pos[id] = at
	var on_body := at + Vector2(0.35, 0)  # in (5, 3), 0.35 cells from the body's centre
	assert_vector(board.view.cell_at_screen(_pan_screen(on_body, PAN))).is_equal(Vector2i(5, 3))
	await _click(_pan_screen(on_body, PAN))
	assert_vector(board.view.pan).is_equal(PAN)
	board.last_pos.clear()  # the frame after the click redrew last_pos from the sim
	board.last_pos[id] = at
	var off_body := at + Vector2(0.7, 0)  # same cell (5, 3), outside every body
	await _click(_pan_screen(off_body, PAN))
	assert_vector(board.view.pan).is_equal(PAN)
	board.last_pos.clear()
	board.last_pos[id] = at
	var outside := Vector2(-0.5, 3.5)  # left of the panned board's edge, on screen
	assert_float(_pan_screen(outside, PAN).x).is_greater(0.0)
	await _click(_pan_screen(outside, PAN))
	assert_array(picks).is_equal([["enemy", id], ["cell", Vector2i(5, 3)], ["outside"]])
