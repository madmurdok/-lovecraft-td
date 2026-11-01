class_name MapLayerTest
extends GdUnitTestSuite
## LT-41: the static map is drawn by Board's child MapLayer only when the map changes.
## A redraw is observed through CanvasItem's `draw` signal, emitted once per _draw run;
## queue_redraw coalesces, so one or more requests within a frame give exactly one draw.

const RIFLE := "rifleman"
const FRAMES := 5

var _vp: SubViewport
var _game: Game
var _config: GameConfig


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = SubViewport.new()
	_vp.size = Vector2i(1152, 648)
	add_child(_vp)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


## A Game that only advances through advance(): its own _process is switched off.
func _start_game() -> void:
	_game = Game.new()
	_game.setup(_config, 7)
	_vp.add_child(_game)
	_game.set_process(false)
	await _frames(2)


## Waits long enough for a queued redraw (a deferred call) to have run.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Counts `draw` emissions of `item` into counter[0].
func _count_draws(item: CanvasItem) -> Array[int]:
	var counter: Array[int] = [0]
	item.draw.connect(func() -> void: counter[0] += 1)
	return counter


## A copy of `m` that is a different MapDef object with the same content.
func _copy_map(m: MapDef) -> MapDef:
	var c := MapDef.new()
	c.width = m.width
	c.height = m.height
	c.spawn = m.spawn
	c.lighthouse = m.lighthouse
	c.path = m.path.duplicate()
	c._kinds = m._kinds.duplicate()
	return c


func _buildable_cell() -> Vector2i:
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			if m.is_buildable(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# --- 1. MapLayer.set_map --------------------------------------------------------------

func test_set_map_redraws_for_a_new_map_and_not_for_the_same_map() -> void:
	var layer := Board.MapLayer.new()
	_vp.add_child(layer)
	await _frames(2)
	var draws := _count_draws(layer)
	var m1 := _copy_map(_config.map)
	layer.set_map(m1)
	await _frames(2)
	assert_int(draws[0]).override_failure_message("a new map must redraw once").is_equal(1)
	assert_object(layer.map).is_same(m1)

	layer.set_map(m1)
	await _frames(FRAMES)
	assert_int(draws[0]).override_failure_message("the same map must not redraw") \
		.is_equal(1)

	var m2 := _copy_map(_config.map)
	layer.set_map(m2)
	await _frames(2)
	assert_int(draws[0]).override_failure_message("another new map must redraw").is_equal(2)
	assert_object(layer.map).is_same(m2)


# --- 2. Board._draw on ordinary frames ------------------------------------------------

func test_ordinary_frames_redraw_the_board_but_not_the_map_layer() -> void:
	await _start_game()
	var layer := _game.board.map_layer
	assert_object(layer.map).is_same(_game.sim.state.map)
	var map_draws := _count_draws(layer)
	var board_draws := _count_draws(_game.board)
	for i in FRAMES:
		_game.advance(1.0 / 60.0)
		await _frames(2)
	# The observation can see a redraw: the board itself redrew on these frames.
	assert_int(board_draws[0]).is_greater_equal(FRAMES)
	assert_int(map_draws[0]).override_failure_message("map layer redrew on ordinary frames") \
		.is_equal(0)


func test_a_new_map_in_the_sim_redraws_the_layer_on_the_next_board_draw() -> void:
	await _start_game()
	var layer := _game.board.map_layer
	var map_draws := _count_draws(layer)
	var fresh := _copy_map(_game.sim.state.map)
	_game.sim.state.map = fresh
	_game.board.queue_redraw()
	await _frames(3)
	assert_object(layer.map).is_same(fresh)
	assert_int(map_draws[0]).is_equal(1)


# --- 3. Build / sell / upgrade --------------------------------------------------------

func test_build_upgrade_and_sell_do_not_redraw_the_map_layer() -> void:
	await _start_game()
	var map_draws := _count_draws(_game.board.map_layer)
	var board_draws := _count_draws(_game.board)
	_game.sim.state.gold = 1_000_000
	var cell := _buildable_cell()
	assert_int(_game.build(RIFLE, cell)).is_equal(Simulation.CommandResult.OK)
	await _frames(2)
	assert_int(_game.sim.state.towers.size()).is_equal(1)
	var id: int = _game.sim.state.towers[0].id
	assert_int(_game.upgrade(id)).is_equal(Simulation.CommandResult.OK)
	await _frames(2)
	assert_int(_game.sim.state.towers[0].level).is_equal(1)
	assert_int(_game.sell(id)).is_equal(Simulation.CommandResult.OK)
	await _frames(2)
	assert_int(_game.sim.state.towers.size()).is_equal(0)
	assert_int(board_draws[0]).is_greater_equal(3)
	assert_int(map_draws[0]).override_failure_message("a tower command redrew the map layer") \
		.is_equal(0)


# --- 4. Board._ready wiring -----------------------------------------------------------

func test_map_layer_is_the_boards_first_child_behind_it_with_the_same_light_mask() -> void:
	await _start_game()
	var board := _game.board
	var layer := board.map_layer
	assert_object(layer).is_not_null()
	assert_object(board.get_child(0)).is_same(layer)
	assert_bool(layer.show_behind_parent).is_true()
	assert_int(layer.light_mask).is_equal(1)
	assert_int(layer.light_mask).is_equal(board.light_mask)
	assert_object(layer.material).is_null()
	assert_bool(layer.use_parent_material).is_false()


func test_map_layer_is_first_even_when_the_board_already_has_children() -> void:
	var board: Board = Board.new()
	var other := Node2D.new()
	other.name = "Other"
	board.add_child(other)
	_vp.add_child(board)
	await _frames(1)
	assert_object(board.get_child(0)).is_same(board.map_layer)
	assert_object(board.get_child(1)).is_same(other)
