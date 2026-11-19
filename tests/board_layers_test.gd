class_name BoardLayersTest
extends GdUnitTestSuite
## LT-84 (LT-65 §3.4, B9): the board's drawing layers and the SelectionModel.
## Layers: Board adds Phantom, Entity, Fx and Overlay layers (in that draw order) above the
## MapLayer; each draws its own part; a board redraw queues them entity-before-fx (EntityLayer
## writes `board.last_pos`, which FxLayer reads in the same frame, F5). SelectionModel: every
## setter sets its fields and emits `changed` once, none when nothing changed; the board
## redraws on `changed` (F3). The warm-up's same-frame stamp check lives in lt62_fps_test.

const C1 := Vector2i(2, 3)
const C2 := Vector2i(4, 1)

## Spies log into the board's shared `log` (draw order across layers).


class SpyPhantom:
	extends PhantomLayer
	var log: Array[String]

	func _draw() -> void:
		log.append("phantom")
		super._draw()


class SpyEntity:
	extends EntityLayer
	var log: Array[String]

	func _draw() -> void:
		log.append("entity")
		super._draw()

	func _draw_auras(s: SimState) -> void:
		log.append("auras")
		super._draw_auras(s)

	func _draw_tower(t: SimTower) -> void:
		log.append("tower")
		super._draw_tower(t)

	func _draw_enemies(s: SimState) -> void:
		log.append("enemies")
		super._draw_enemies(s)

	func _draw_allies(s: SimState) -> void:
		log.append("allies")
		super._draw_allies(s)


class SpyFx:
	extends FxLayer
	var log: Array[String]
	var last_pos_seen: Array[Dictionary] = []  ## board.last_pos as FxLayer saw it, per draw

	func _draw() -> void:
		log.append("fx")
		last_pos_seen.append(board.last_pos.duplicate())
		super._draw()

	func _draw_warmup() -> void:
		log.append("warmup")
		super._draw_warmup()

	func _draw_effects() -> void:
		log.append("effects")
		super._draw_effects()


class SpyOverlay:
	extends OverlayLayer
	var log: Array[String]

	func _draw() -> void:
		log.append("overlay")
		super._draw()


## A Board whose four layers are spies sharing one log.
class SpyBoard:
	extends Board
	var log: Array[String] = []
	var board_draws := 0
	var spy_phantom := SpyPhantom.new()
	var spy_entity := SpyEntity.new()
	var spy_fx := SpyFx.new()
	var spy_overlay := SpyOverlay.new()

	func _init() -> void:
		for l in [spy_phantom, spy_entity, spy_fx, spy_overlay]:
			l.log = log
		phantom_layer = spy_phantom
		entity_layer = spy_entity
		fx_layer = spy_fx
		overlay_layer = spy_overlay

	func _draw() -> void:
		board_draws += 1
		log.append("board")
		super._draw()


var _vp: SubViewport
var _game: Game
var _config: GameConfig


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = GameFixture.make_viewport(self)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _start_game() -> void:
	_game = GameFixture.make_game(_vp, _config, 7)
	await _frames(3)


## A SpyBoard on the started game's sim, settled, with an empty log.
func _spy_board() -> SpyBoard:
	await _start_game()
	var b := SpyBoard.new()
	b.game = _game
	_vp.add_child(b)
	await _frames(3)
	b.log.clear()
	b.spy_fx.last_pos_seen.clear()
	return b


## Counts `draw` emissions of `item` into counter[0].
func _count_draws(item: CanvasItem) -> Array[int]:
	var counter: Array[int] = [0]
	item.draw.connect(func() -> void: counter[0] += 1)
	return counter


## Counts `changed` emissions of `m` into counter[0].
func _count_changed(m: SelectionModel) -> Array[int]:
	var counter: Array[int] = [0]
	m.changed.connect(func() -> void: counter[0] += 1)
	return counter


# ---- SelectionModel ----------------------------------------------------------------------


func _assert_state(m: SelectionModel, c: Vector2i, r: float, g: String, k: String) -> void:
	assert_object(m.cell).is_equal(c)
	assert_float(m.range_cells).is_equal(r)
	assert_str(m.glyph).is_equal(g)
	assert_str(m.cast).is_equal(k)


func test_selection_starts_empty() -> void:
	var m := SelectionModel.new()
	_assert_state(m, SelectionModel.NONE, 0.0, "", "")
	assert_object(SelectionModel.NONE).is_equal(Vector2i(-1, -1))


func test_show_cell_sets_the_cell_and_resets_ring_glyph_and_cast() -> void:
	var m := SelectionModel.new()
	m.set_preview(3.5, "R", "light")
	var n := _count_changed(m)
	m.show_cell(C1)
	_assert_state(m, C1, 0.0, "", "")
	assert_int(n[0]).is_equal(1)


func test_set_cell_moves_the_cell_and_keeps_ring_glyph_and_cast() -> void:
	var m := SelectionModel.new()
	m.set_preview(3.5, "R", "shadow")
	var n := _count_changed(m)
	m.set_cell(C2)
	_assert_state(m, C2, 3.5, "R", "shadow")
	assert_int(n[0]).is_equal(1)


func test_set_ring_sets_range_and_cast_and_keeps_cell_and_glyph() -> void:
	var m := SelectionModel.new()
	m.show_cell(C1)
	m.set_preview(1.0, "G", "light")
	var n := _count_changed(m)
	m.set_ring(4.0, "shadow")
	_assert_state(m, C1, 4.0, "G", "shadow")
	assert_int(n[0]).is_equal(1)


func test_set_preview_sets_ring_glyph_and_cast_and_keeps_the_cell() -> void:
	var m := SelectionModel.new()
	m.show_cell(C2)
	var n := _count_changed(m)
	m.set_preview(2.5, "S", "light")
	_assert_state(m, C2, 2.5, "S", "light")
	assert_int(n[0]).is_equal(1)


func test_clear_resets_everything() -> void:
	var m := SelectionModel.new()
	m.show_cell(C1)
	m.set_preview(2.5, "S", "light")
	var n := _count_changed(m)
	m.clear()
	_assert_state(m, SelectionModel.NONE, 0.0, "", "")
	assert_int(n[0]).is_equal(1)


func test_each_setter_emits_nothing_when_nothing_changes() -> void:
	var m := SelectionModel.new()
	m.show_cell(C1)
	m.set_preview(2.5, "S", "light")
	var n := _count_changed(m)
	m.set_cell(C1)
	m.set_ring(2.5, "light")
	m.set_preview(2.5, "S", "light")
	assert_int(n[0]).is_equal(0)
	m.clear()
	assert_int(n[0]).is_equal(1)
	m.clear()  # already empty
	assert_int(n[0]).is_equal(1)
	m.show_cell(C1)
	m.show_cell(C1)  # same cell, ring already 0
	assert_int(n[0]).is_equal(2)


func test_each_changed_field_alone_emits() -> void:
	var m := SelectionModel.new()
	m.show_cell(C1)
	var n := _count_changed(m)
	m.set_ring(1.0, "")
	assert_int(n[0]).is_equal(1)
	m.set_ring(1.0, "light")  # only the cast
	assert_int(n[0]).is_equal(2)
	m.set_preview(1.0, "R", "light")  # only the glyph
	assert_int(n[0]).is_equal(3)
	m.set_cell(C2)  # only the cell
	assert_int(n[0]).is_equal(4)


# ---- F3: the board redraws on selection.changed ------------------------------------------


func test_game_hands_its_selection_to_the_board() -> void:
	await _start_game()
	assert_object(_game.board.selection).is_same(_game.selection)
	assert_object(_game.board.overlay_layer.board.selection).is_same(_game.selection)


func test_selection_change_redraws_the_overlay_and_entity_layers() -> void:
	await _start_game()  # Game.advance is not running: only `changed` can queue a redraw
	var overlay := _count_draws(_game.board.overlay_layer)
	var entity := _count_draws(_game.board.entity_layer)
	var fx := _count_draws(_game.board.fx_layer)
	var phantom := _count_draws(_game.board.phantom_layer)
	await _frames(2)
	assert_int(overlay[0]).is_equal(0)  # idle: nothing redraws by itself
	_game.selection.set_cell(C1)
	await _frames(2)
	assert_int(overlay[0]).is_equal(1)  # the selection outline
	assert_int(entity[0]).is_equal(1)  # the BUILD preview tint depends on it (LT-70 §5)
	assert_int(fx[0]).is_equal(1)  # a board redraw is a whole-board redraw
	assert_int(phantom[0]).is_equal(1)


func test_selection_change_through_each_setter_redraws_the_overlay() -> void:
	await _start_game()
	var overlay := _count_draws(_game.board.overlay_layer)
	await _frames(2)
	var sel := _game.selection
	var before := 0
	for step: Callable in [
		func() -> void: sel.show_cell(C1),
		func() -> void: sel.set_ring(2.0, "light"),
		func() -> void: sel.set_preview(3.0, "R", "shadow"),
		func() -> void: sel.set_cell(C2),
		func() -> void: sel.clear(),
	]:
		step.call()
		await _frames(2)
		assert_int(overlay[0]).is_equal(before + 1)
		before = overlay[0]


func test_unchanged_selection_does_not_redraw_the_board() -> void:
	await _start_game()
	_game.selection.show_cell(C1)
	await _frames(3)
	var overlay := _count_draws(_game.board.overlay_layer)
	_game.selection.set_cell(C1)
	_game.selection.show_cell(C1)
	await _frames(2)
	assert_int(overlay[0]).is_equal(0)


func test_a_bare_board_has_its_own_selection_and_redraws_on_it() -> void:
	await _start_game()
	var b := Board.new()
	b.game = _game
	_vp.add_child(b)
	await _frames(3)
	assert_object(b.selection).is_not_null()
	var overlay := _count_draws(b.overlay_layer)
	b.selection.show_cell(C2)
	await _frames(2)
	assert_int(overlay[0]).is_equal(1)


# ---- Layer creation and order ------------------------------------------------------------


func test_board_creates_the_five_layers_in_draw_order() -> void:
	await _start_game()
	var b := _game.board
	var names: Array[String] = []
	for c in b.get_children():
		if c is CanvasItem:
			names.append(String(c.name))
	# (the Game adds its Lighting after them, on top)
	assert_array(names.slice(0, 5)).is_equal(
		["MapLayer", "PhantomLayer", "EntityLayer", "FxLayer", "OverlayLayer"])
	assert_bool(b.map_layer.get_index() < b.phantom_layer.get_index()).is_true()
	assert_bool(b.phantom_layer is PhantomLayer and b.entity_layer is EntityLayer).is_true()
	assert_bool(b.fx_layer is FxLayer and b.overlay_layer is OverlayLayer).is_true()
	assert_int(b.phantom_layer.get_index()).is_equal(1)
	assert_int(b.entity_layer.get_index()).is_equal(2)
	assert_int(b.fx_layer.get_index()).is_equal(3)
	assert_int(b.overlay_layer.get_index()).is_equal(4)


func test_every_layer_knows_its_board_and_view() -> void:
	await _start_game()
	var b := _game.board
	for l: BoardLayer in [b.phantom_layer, b.entity_layer, b.fx_layer, b.overlay_layer]:
		assert_object(l.board).is_same(b)
		assert_object(l.view).is_same(b.view)
		assert_object(l.game).is_same(_game)
		assert_int(l.light_mask).is_equal(b.light_mask)
		assert_object(l.material).is_null()


func test_a_layer_set_before_ready_is_kept() -> void:
	var b := await _spy_board()
	assert_object(b.fx_layer).is_same(b.spy_fx)
	assert_object(b.entity_layer).is_same(b.spy_entity)
	assert_object(b.spy_fx.get_parent()).is_same(b)


# ---- What each layer draws, and in which order -------------------------------------------


func test_a_board_redraw_draws_the_layers_in_spec_order() -> void:
	var b := await _spy_board()
	b.queue_redraw()
	await _frames(2)
	assert_int(b.board_draws).is_greater(0)
	# board (draws nothing itself) -> phantom -> entity parts -> fx (warm-up, then effects)
	# -> overlay
	assert_array(b.log).is_equal(["board", "phantom", "entity", "auras", "enemies", "allies",
		"fx", "warmup", "effects", "overlay"])


func test_entity_layer_is_drawn_before_fx_and_fx_sees_this_frames_last_pos() -> void:
	# F5: EntityLayer._draw_enemies rewrites board.last_pos; FxLayer reads it in the same
	# frame, so the entity layer must be queued (and drawn) first.
	var b := await _spy_board()
	b.last_pos[999] = Vector2(1, 1)  # a stale entry from "last frame"
	b.queue_redraw()
	await _frames(2)
	assert_bool(b.log.find("entity") < b.log.find("fx")).is_true()
	assert_int(b.spy_fx.last_pos_seen.size()).is_equal(1)
	assert_bool(b.spy_fx.last_pos_seen[0].has(999)).override_failure_message(
		"FxLayer saw last frame's last_pos: the entity layer was not drawn first").is_false()


func test_each_layer_draws_once_per_board_redraw() -> void:
	var b := await _spy_board()
	b.queue_redraw()
	await _frames(2)
	for key in ["board", "phantom", "entity", "fx", "overlay", "auras", "enemies", "allies"]:
		assert_int(b.log.count(key)).override_failure_message(key).is_equal(1)


func test_entity_layer_draws_towers_and_not_effects() -> void:
	var b := await _spy_board()
	var tower_id := _build_a_tower()
	assert_int(tower_id).is_greater_equal(0)
	b.log.clear()
	b.queue_redraw()
	await _frames(2)
	assert_int(b.log.count("tower")).is_equal(_game.sim.state.towers.size())
	assert_int(b.log.count("tower")).is_greater(0)
	# the effects belong to the fx layer only
	assert_bool(b.spy_entity.has_method("_draw_effects")).is_false()
	assert_bool(b.spy_entity.has_method("_draw_warmup")).is_false()
	assert_bool(b.spy_fx.has_method("_draw_tower")).is_false()
	assert_bool(b.spy_overlay.has_method("_draw_effects")).is_false()


func test_fx_layer_draws_the_effects_list() -> void:
	var b := await _spy_board()
	b.fx_layer.effects.append({"kind": "leak", "from": Vector2(1, 1), "ttl": 1.0})
	b.queue_redraw()
	await _frames(2)
	assert_int(b.log.count("effects")).is_equal(1)
	assert_bool(b.log.find("warmup") < b.log.find("effects")).is_true()


func test_layers_draw_nothing_without_a_game() -> void:
	var b := SpyBoard.new()
	_vp.add_child(b)
	await _frames(2)
	b.log.clear()
	b.queue_redraw()
	await _frames(2)
	assert_array(b.log).is_equal(["board"])  # the board does not queue the layers
	b.spy_overlay.queue_redraw()
	b.spy_entity.queue_redraw()
	b.spy_fx.queue_redraw()
	await _frames(2)
	assert_int(b.log.count("auras")).is_equal(0)  # each layer's own guard: no sim, no draw
	assert_int(b.log.count("effects")).is_equal(0)
	assert_int(b.log.count("warmup")).is_equal(0)


func test_overlay_reads_the_selection_and_paints_no_cast_on_an_empty_one() -> void:
	await _start_game()
	var o := _game.board.overlay_layer
	assert_float(o.selected_dead_zone()).is_equal(0.0)
	_build_a_tower()
	var t := _game.sim.state.towers[0]
	assert_str(o.preview_cast(t)).is_equal("")  # no cast selected
	_game.selection.show_cell(C2)
	_game.selection.set_ring(50.0, "light")  # a caster on C2 whose ring covers every tower
	assert_str(o.preview_cast(t)).is_equal(
		"light" if _game.sim.state.phase == SimState.Phase.BUILD else "")
	_game.selection.show_cell(t.cell)  # the tower's own cell is never tinted
	_game.selection.set_ring(50.0, "light")
	assert_str(o.preview_cast(t)).is_equal("")


func test_phantom_layer_holds_no_path_while_lucid() -> void:
	var b := await _spy_board()
	b.tick_effects(5.0)
	assert_array(b.spy_phantom.phantom).is_empty()  # flicker 0 at full sanity


## Builds a rifleman on the first free buildable cell; returns its id or -1.
func _build_a_tower() -> int:
	var sim := _game.sim
	sim.state.gold = 100000
	for c in sim.state.map.grid.cells():
		if sim.state.map.kind_at(c) != MapDef.Kind.BUILDABLE or c == C2:
			continue
		if sim.build_tower("rifleman", c) == Simulation.CommandResult.OK:
			return sim.state.towers.back().id
	return -1
