class_name FigureOrderTest
extends GdUnitTestSuite
## LT-126 (LT-64 §1.3): EntityLayer draws towers, enemies, summon leash rings and allies in
## ONE list sorted by [BoardView.depth, kind TOWER < ENEMY < LEASH < ALLY, snapshot index].
## At identity depth is 0 everywhere, so the kind and the snapshot order alone give today's
## top-down order; with a depth that varies, a nearer figure is drawn after a farther one
## whatever its kind. The figure order is pinned on figure_before (pure) and on
## _draw_figures through a running Game with a spy layer that logs instead of drawing.

const RIFLE := "rifleman"
const CIRCLE := "summoning_circle"
const ALLY_AT := Vector2(0.1, 0.5)  ## left of every tower centre and the enemy spawn


## Logs each figure it is asked to draw ("T<id>", "E<id>", "L<id>", "A<id>"), draws nothing.
class SpyFigures:
	extends EntityLayer
	var order: Array[String] = []

	func _draw_tower(t: TowerRecord) -> void:
		order.append("T%d" % t.id)

	func _draw_enemy(e: EnemyRecord, _p: Vector2) -> void:
		order.append("E%d" % e.id)

	func _draw_leash(t: TowerRecord) -> void:
		order.append("L%d" % t.id)

	func _draw_ally(a: AllyRecord, _p: Vector2) -> void:
		order.append("A%d" % a.id)


## A view whose depth is the ground x (a stand-in for an angled camera).
class DepthByX:
	extends BoardView

	func depth(p_cells: Vector2) -> float:
		return p_cells.x


## A Board drawing through `v` with the spy figure layer.
class FigureBoard:
	extends Board
	var spy := SpyFigures.new()

	func _init(v: BoardView) -> void:
		view = v
		camera = BoardCamera.new(view)
		entity_layer = spy


var _vp: SubViewport
var _game: Game
var _config: GameConfig


func before_test() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = GameFixture.make_viewport(self)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _key(depth: float, kind: EntityLayer.Fig, index: int) -> Array:
	return [depth, kind, index]


## figure_before as a sort: the keys of `shuffled` in the order it puts them.
func _sorted(shuffled: Array) -> Array:
	var a := shuffled.duplicate()
	a.sort_custom(EntityLayer.figure_before)
	return a


# --- 1. figure_before -------------------------------------------------------------------------

func test_at_equal_depth_towers_then_enemies_then_leashes_then_allies_by_index() -> void:
	var expected := [
		_key(0.0, EntityLayer.Fig.TOWER, 0), _key(0.0, EntityLayer.Fig.TOWER, 1),
		_key(0.0, EntityLayer.Fig.ENEMY, 0), _key(0.0, EntityLayer.Fig.ENEMY, 1),
		_key(0.0, EntityLayer.Fig.ENEMY, 2), _key(0.0, EntityLayer.Fig.LEASH, 1),
		_key(0.0, EntityLayer.Fig.ALLY, 0), _key(0.0, EntityLayer.Fig.ALLY, 3)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 126
	for round in 20:
		var shuffled := expected.duplicate()
		for i in range(shuffled.size() - 1, 0, -1):  # Fisher-Yates, seeded
			var j := rng.randi_range(0, i)
			var tmp: Array = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = tmp
		assert_array(_sorted(shuffled)).override_failure_message(str(shuffled)).is_equal(expected)


func test_a_larger_depth_is_drawn_later_whatever_the_kind() -> void:
	var near_tower := _key(2.0, EntityLayer.Fig.TOWER, 0)
	var far_ally := _key(-1.0, EntityLayer.Fig.ALLY, 5)
	var mid_enemy := _key(0.5, EntityLayer.Fig.ENEMY, 2)
	var mid_leash := _key(0.5, EntityLayer.Fig.LEASH, 0)
	assert_array(_sorted([near_tower, mid_leash, far_ally, mid_enemy])) \
		.is_equal([far_ally, mid_enemy, mid_leash, near_tower])


func test_figure_before_is_a_strict_order() -> void:
	var a := _key(0.0, EntityLayer.Fig.ENEMY, 1)
	var b := _key(0.0, EntityLayer.Fig.ENEMY, 2)
	assert_bool(EntityLayer.figure_before(a, b)).is_true()
	assert_bool(EntityLayer.figure_before(b, a)).is_false()
	assert_bool(EntityLayer.figure_before(a, a)).is_false()  # irreflexive: no equal keys move


func test_the_kind_tie_order_is_tower_enemy_leash_ally() -> void:
	assert_bool(EntityLayer.Fig.TOWER < EntityLayer.Fig.ENEMY).is_true()
	assert_bool(EntityLayer.Fig.ENEMY < EntityLayer.Fig.LEASH).is_true()
	assert_bool(EntityLayer.Fig.LEASH < EntityLayer.Fig.ALLY).is_true()


# --- 2. _draw_figures through a running Game ---------------------------------------------------

## The started game with two riflemen and a circle built, night called, two enemies and one
## still ally at ALLY_AT; a FigureBoard drawing through `v` on it, its log cleared.
func _figure_board(v: BoardView) -> FigureBoard:
	_game = GameFixture.make_game(_vp, _config, 7)
	await get_tree().process_frame
	_game.sim.state.gold = 100000
	var m := _game.sim.state.map
	var built := 0
	var kinds := [RIFLE, CIRCLE, RIFLE]
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if built < kinds.size() and x > 0 and m.is_buildable(c) \
					and not _game.sim.state.tower_at.has(c):
				if _game.commands.build(kinds[built], c) == SimCommand.CommandResult.OK:
					built += 1
	assert_int(built).is_equal(kinds.size())
	assert_int(_game.commands.call_wave()).is_equal(SimCommand.CommandResult.OK)
	_game.sim.step()
	_game.sim.spawn_enemy("cultist")
	_game.sim.spawn_enemy("cultist")
	assert_int(_game.sim.spawn_ally(0, CIRCLE, ALLY_AT, 100.0, 1.0, 0.0, false, 0, 3.0)) \
		.is_greater(0)
	GameFixture.sync(_game)
	var b := FigureBoard.new(v)
	b.game = _game
	_vp.add_child(b)
	await get_tree().process_frame
	b.spy.order.clear()
	return b


func test_at_identity_the_figures_are_drawn_by_kind_then_snapshot_order() -> void:
	var b := await _figure_board(BoardView.new())
	var s := _game.snapshot
	assert_int(s.enemies.size()).is_greater_equal(2)
	assert_int(s.allies.size()).is_greater_equal(1)
	var expected: Array[String] = []
	var leashes: Array[String] = []
	for t in s.towers:
		expected.append("T%d" % t.id)
		if t.def.id == CIRCLE:
			leashes.append("L%d" % t.id)
	assert_array(leashes).has_size(1)
	for e in s.enemies:
		expected.append("E%d" % e.id)
	expected.append_array(leashes)
	for a in s.allies:
		expected.append("A%d" % a.id)
	b.spy._draw_figures(s)
	assert_array(b.spy.order).is_equal(expected)
	for e in s.enemies:  # last_pos is refilled for every enemy drawn
		assert_bool(b.last_pos.has(e.id)).is_true()


func test_with_a_varying_depth_a_nearer_figure_is_drawn_later_whatever_its_kind() -> void:
	var b := await _figure_board(DepthByX.new())
	var s := _game.snapshot
	var depth_of := {}  # logged name -> its ground x
	for t in s.towers:
		depth_of["T%d" % t.id] = t.centre.x
		depth_of["L%d" % t.id] = t.centre.x
	for e in s.enemies:
		depth_of["E%d" % e.id] = e.position(b.alpha).x
	var mine := ""
	for a in s.allies:
		depth_of["A%d" % a.id] = a.position(b.alpha).x
		if a.position(b.alpha) == ALLY_AT:
			mine = "A%d" % a.id
	assert_str(mine).is_not_empty()
	b.spy._draw_figures(s)
	var order := b.spy.order
	assert_int(order.size()).is_greater(4)
	assert_str(order[0]).is_equal(mine)  # the farthest figure first, though an ally
	for i in range(1, order.size()):
		assert_float(depth_of[order[i]]).override_failure_message(str(order)) \
			.is_greater_equal(depth_of[order[i - 1]])
	for t in s.towers:  # same depth: the tower before its own leash ring
		if t.def.id == CIRCLE:
			assert_int(order.find("T%d" % t.id)).is_less(order.find("L%d" % t.id))
