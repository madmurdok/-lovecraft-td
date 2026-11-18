class_name LightShadowRenderTest
extends GdUnitTestSuite
## LT-70 §5, §8 item 12: the tower plate colour and border from the net lit / shadowed
## flags, the caster kind of a level, and the BUILD preview of a caster's radius.

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


func _start_game() -> void:
	_game = GameFixture.make_game(_vp, _config, 7)
	await get_tree().process_frame
	_game.sim.state.gold = 10000


func _tower(lit: bool, shadowed: bool) -> SimTower:
	var t := SimTower.new()
	t.pos = SquareGrid.new(1, 1).centre(t.cell)
	t.lit = lit
	t.shadowed = shadowed
	return t


## `n` buildable cells of the real map in row-major order.
func _cells(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			if m.is_buildable(Vector2i(x, y)) and out.size() < n:
				out.append(Vector2i(x, y))
	return out


func _place(def_id: String, cell: Vector2i) -> SimTower:
	assert_int(_game.build(def_id, cell) as int).is_equal(Simulation.CommandResult.OK)
	return _game.sim.tower_by_id(_game.sim.state.tower_at[cell])


func test_plate_color_is_warm_when_lit_violet_when_shadowed_plain_otherwise() -> void:
	assert_that(Board.plate_color(_tower(true, false))).is_equal(Board.LIT_TINT)
	assert_that(Board.plate_color(_tower(false, true))).is_equal(Board.SHADOW_TINT)
	assert_that(Board.plate_color(_tower(false, false))).is_equal(Board.COLOR_TOWER)
	# The tints are told apart: warm has more red than blue, violet the reverse.
	assert_bool(Board.LIT_TINT.r > Board.LIT_TINT.b).is_true()
	assert_bool(Board.SHADOW_TINT.b > Board.SHADOW_TINT.r).is_true()
	# A real flag wins over a preview.
	assert_that(Board.plate_color(_tower(true, false), "shadow")).is_equal(Board.LIT_TINT)
	assert_that(Board.plate_color(_tower(false, true), "light")).is_equal(Board.SHADOW_TINT)


func test_a_preview_tints_a_plain_tower_only_and_by_its_kind() -> void:
	var plain := _tower(false, false)
	assert_that(Board.plate_color(plain, "shadow")).is_equal(
		Board.COLOR_TOWER.lerp(Board.SHADOW_TINT, Board.PREVIEW_TINT_WEIGHT))
	assert_that(Board.plate_color(plain, "light")).is_equal(
		Board.COLOR_TOWER.lerp(Board.LIT_TINT, Board.PREVIEW_TINT_WEIGHT))
	assert_that(Board.plate_color(plain, "")).is_equal(Board.COLOR_TOWER)
	assert_that(Board.plate_color(plain, "shadow")).is_not_equal(Board.COLOR_TOWER)


func test_state_border_marks_lit_and_shadowed_and_nothing_else() -> void:
	assert_that(Board.state_border(_tower(true, false))).is_equal(Board.LIT_BORDER)
	assert_that(Board.state_border(_tower(false, true))).is_equal(Board.SHADOW_BORDER)
	assert_that(Board.state_border(_tower(false, false))).is_equal(Color.TRANSPARENT)
	assert_that(Board.state_border(_tower(false, false), "light")).is_equal(Board.LIT_TINT)
	assert_that(Board.state_border(_tower(false, false), "shadow")).is_equal(Board.SHADOW_TINT)
	assert_that(Board.state_border(_tower(true, false), "shadow")).is_equal(Board.LIT_BORDER)


func test_cast_of_names_the_level_flag() -> void:
	assert_str(Board.cast_of(_config.towers["searchlight"].levels[0])).is_equal("light")
	assert_str(Board.cast_of(_config.towers["elder_sign"].levels[0])).is_equal("shadow")
	assert_str(Board.cast_of(_config.towers["rifleman"].levels[0])).is_equal("")
	assert_str(Board.cast_of(null)).is_equal("")


func test_build_preview_tints_towers_inside_the_radius_inclusive_only() -> void:
	await _start_game()
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.BUILD)
	var cs := _cells(3)
	var centre_cell := cs[0]
	var near := _place("rifleman", cs[1])
	var far := _place("rifleman", cs[2])
	var b := _game.board
	b.selected_cell = centre_cell
	b.selected_cast = "shadow"
	var d_near := (Vector2(centre_cell) - Vector2(near.cell)).length()
	var d_far := (Vector2(centre_cell) - Vector2(far.cell)).length()
	assert_float(d_far).is_greater(d_near)
	b.selected_range = d_near  # exactly on the boundary: inclusive
	assert_str(b.preview_cast(near)).is_equal("shadow")
	assert_str(b.preview_cast(far)).is_equal("")
	b.selected_range = d_far
	assert_str(b.preview_cast(far)).is_equal("shadow")
	# A tower on the selected cell itself is never previewed.
	b.selected_cell = near.cell
	assert_str(b.preview_cast(near)).is_equal("")
	b.selected_cell = centre_cell
	# No preview without a cast kind or a range.
	b.selected_cast = ""
	assert_str(b.preview_cast(near)).is_equal("")
	b.selected_cast = "shadow"
	b.selected_range = 0.0
	assert_str(b.preview_cast(near)).is_equal("")


func test_no_preview_at_night() -> void:
	await _start_game()
	var cs := _cells(2)
	var t := _place("rifleman", cs[1])
	var b := _game.board
	b.selected_cell = cs[0]
	b.selected_cast = "light"
	b.selected_range = 50.0
	assert_str(b.preview_cast(t)).is_equal("light")  # BUILD: the arms differ
	_game.sim.state.phase = SimState.Phase.WAVE
	assert_str(b.preview_cast(t)).is_equal("")
	_game.sim.state.phase = SimState.Phase.NONE
	assert_str(b.preview_cast(t)).is_equal("")
