class_name SidePanelTest
extends GdUnitTestSuite
## LT-24 §4 fixed side panel (Decision 2): its rect, the idle / build / tower views, role
## lines, button texts and disabled reasons, the madness warning, upgrading from the panel,
## and closing. Also the HUD bar fix (22a9d9c): the bar spans the full width above the
## board, so a range ring near the top edge is drawn under it. Real mouse events go into a
## 1152x648 SubViewport like scene_game_test; text formats come from the design note,
## numbers from config.

const RIFLE := "rifleman"
const SIGN := "elder_sign"

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


func _start_game() -> void:
	_game = Game.new()
	_game.setup(_config, 7)
	_vp.add_child(_game)
	_game.set_process(false)
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


func _click_control(c: Control) -> void:
	assert_bool(c.is_visible_in_tree()).override_failure_message("%s hidden" % c.name).is_true()
	if _game != null and _game.side_panel.is_ancestor_of(c):
		# Long views scroll: bring the control into the panel before clicking it.
		_game.side_panel.scroll.ensure_control_visible(c)
		await get_tree().process_frame
		assert_bool(SidePanel.panel_rect(_game.sim.state.map).encloses(c.get_global_rect())) \
			.override_failure_message("%s outside the panel" % c.name).is_true()
	await _click(c.get_global_rect().get_center())


func _click_cell(cell: Vector2i) -> void:
	await _click(_game.board.position + (Vector2(cell) + Vector2(0.5, 0.5)) * Board.CELL)


func _buildable_cell() -> Vector2i:
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			if m.is_buildable(Vector2i(x, y)) and not _game.sim.state.tower_at.has(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Builds `def_id` with plenty of gold, raises it through `path` (branches per upgrade),
## then clicks it open. Returns the tower.
func _open_tower(def_id: String, path: Array = []) -> SimTower:
	_game.sim.state.gold = 10000
	var cell := _buildable_cell()
	assert_int(_game.build(def_id, cell)).is_equal(Simulation.CommandResult.OK)
	var t := _game.sim.tower_by_id(_game.sim.state.tower_at[cell])
	for b: String in path:
		assert_int(_game.upgrade(t.id, b)).is_equal(Simulation.CommandResult.OK)
	await _click_cell(cell)
	assert_bool(_game.tower_panel.visible).is_true()
	return t


func _ups() -> Dictionary:
	return _game.tower_panel.upgrade_buttons


func _visible_ups() -> Array:
	var out := []
	for k: String in _ups():
		if _ups()[k].visible:
			out.append(k)
	return out


func _first_line(l: Label) -> String:
	return l.text.split("\n")[0]


func _run_into_wave() -> void:
	assert_int(_game.call_wave()).is_equal(Simulation.CommandResult.OK)
	_game.sim.step()
	_game.advance(0.0)
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.WAVE)


# --- 21: rect and scrolling ------------------------------------------------------------------

func test_panel_rect_is_right_of_the_board_below_the_hud() -> void:
	await _start_game()
	var map := _game.sim.state.map
	var r := SidePanel.panel_rect(map)
	var board := Rect2(Game.BOARD_ORIGIN, Vector2(map.width, map.height) * Board.CELL)
	assert_float(r.position.x).is_equal(Game.BOARD_ORIGIN.x + map.width * Board.CELL)
	assert_float(r.position.y).is_equal(Game.BOARD_ORIGIN.y)
	assert_float(r.end.x).is_equal(1152.0)
	assert_float(r.end.y).is_equal(648.0)
	assert_bool(r.intersects(board)).is_false()
	if map.width * Board.CELL == 960:
		assert_that(r).is_equal(Rect2(960, 48, 192, 600))
	assert_that(_game.side_panel.get_global_rect()).is_equal(r)


func test_long_content_scrolls_vertically_and_never_grows_the_panel() -> void:
	await _start_game()
	var r := SidePanel.panel_rect(_game.sim.state.map)
	var scroll := _game.side_panel.scroll
	assert_int(scroll.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	await _click_cell(_buildable_cell())
	assert_bool(_game.picker.visible).is_true()
	await get_tree().process_frame
	assert_that(_game.side_panel.get_global_rect()).is_equal(r)
	assert_bool(r.encloses(scroll.get_global_rect())).is_true()
	_game.picker.close()
	await _open_tower(RIFLE, [""])  # L2: two branch buttons with their deltas
	await get_tree().process_frame
	assert_that(_game.side_panel.get_global_rect()).is_equal(r)
	assert_bool(r.encloses(scroll.get_global_rect())).is_true()
	assert_float(_game.tower_panel.size.y).is_greater(scroll.size.y)  # it scrolls


# --- 22, 28: exactly one view; closing ---------------------------------------------------------

func _assert_view(idle: bool, picker: bool, tower: bool) -> void:
	assert_array([_game.side_panel.idle_label.visible, _game.picker.visible,
		_game.tower_panel.visible]).is_equal([idle, picker, tower])


func test_idle_text_shows_iff_no_view_is_open() -> void:
	await _start_game()
	assert_str(_game.side_panel.idle_label.text).is_equal("Click a cell to build, a tower to upgrade.")
	_assert_view(true, false, false)
	await _click_cell(_buildable_cell())
	_assert_view(false, true, false)
	await _click_control(_game.picker.get_node("CancelButton"))
	_assert_view(true, false, false)
	await _open_tower(RIFLE)
	_assert_view(false, false, true)


func test_cancel_water_sell_and_a_vanished_tower_return_to_idle() -> void:
	await _start_game()
	var t := await _open_tower(RIFLE)
	await _click_control(_game.tower_panel.get_node("CancelButton"))
	_assert_view(true, false, false)
	await _click_cell(t.cell)
	_assert_view(false, false, true)
	var water := Vector2i(0, 0)
	assert_bool(_game.sim.state.map.is_buildable(water)).is_false()
	await _click_cell(water)
	_assert_view(true, false, false)
	await _click_cell(t.cell)
	await _click_control(_game.tower_panel.sell_button)
	_assert_view(true, false, false)
	var t2 := await _open_tower(RIFLE)
	assert_int(_game.sim.sell_tower(t2.id)).is_equal(Simulation.CommandResult.OK)
	_game.advance(0.0)
	_game.tower_panel.refresh()
	_assert_view(true, false, false)


func test_a_click_on_empty_panel_space_does_not_reach_the_board() -> void:
	await _start_game()
	await _open_tower(RIFLE, ["", "a"])  # short L3 view
	var r := SidePanel.panel_rect(_game.sim.state.map)
	await _click(r.end - Vector2(12, 12))
	_assert_view(false, false, true)


func test_outcome_hides_the_whole_panel() -> void:
	await _start_game()
	await _open_tower(RIFLE)
	_game.sim.state.lighthouse_hp = 0
	_game.sim.step()
	_game.advance(0.0)
	assert_bool(_game.side_panel.visible).is_false()
	assert_bool(_game.tower_panel.visible).is_false()


# --- 20, 23: build view ----------------------------------------------------------------------

func test_build_buttons_show_name_cost_and_role_first() -> void:
	await _start_game()
	await _click_cell(_buildable_cell())
	for id: String in _config.towers:
		var def: TowerDef = _config.towers[id]
		var b: Button = _game.picker.buttons[id]
		if not b.disabled:
			assert_str(b.text).is_equal("%s — %s" % [def.name, TowerInfo.cost_text(def.cost)])
		assert_str(_first_line(_game.picker.infos[id])).is_equal(def.role)
	# LT-23 Q5: an occult build costs gold only; its info names the reserve instead.
	var sign: TowerDef = _config.towers[SIGN]
	assert_float(sign.levels[0].sanity_reserve).is_greater(0.0)
	assert_str(_game.picker.buttons[SIGN].text).not_contains("sanity")
	assert_str(_game.picker.infos[SIGN].text).contains(
		"Reserves %s sanity" % TowerInfo.num(sign.levels[0].sanity_reserve))


func test_build_buttons_are_disabled_with_the_reason() -> void:
	await _start_game()
	await _click_cell(_buildable_cell())
	_game.sim.state.gold = 0
	_game.picker.refresh()
	for id: String in _config.towers:
		var b: Button = _game.picker.buttons[id]
		assert_bool(b.disabled).is_true()
		assert_str(b.text).ends_with(" (not enough money)")
	_game.sim.state.gold = 10000
	_game.picker.refresh()
	assert_bool(_game.picker.buttons[RIFLE].disabled).is_false()
	assert_str(_game.picker.buttons[RIFLE].text).not_contains("(")


func test_no_role_line_when_the_role_is_empty() -> void:
	var def: TowerDef = _config.towers[RIFLE]
	def.role = ""
	await _start_game()
	var lines := TowerInfo.lines(def, def.levels[0], _config.sanity)
	assert_str(_first_line(_game.picker.infos[RIFLE])).is_equal(lines[0])
	await _open_tower(RIFLE)
	assert_bool(_game.tower_panel.role_label.visible).is_false()


# --- 20, 24: tower view per level -------------------------------------------------------------

func test_l1_view_shows_only_the_l2_upgrade() -> void:
	await _start_game()
	var def: TowerDef = _config.towers[RIFLE]
	await _open_tower(RIFLE)
	var p := _game.tower_panel
	assert_str(p.title_label.text).is_equal("%s  L1" % def.name)
	assert_bool(p.role_label.visible).is_true()
	assert_str(p.role_label.text).is_equal(def.role)
	assert_array(_visible_ups()).is_equal([""])
	assert_str(_ups()[""].text).is_equal("Upgrade to L2 — %s" % TowerInfo.cost_text(
		def.levels[1].upgrade_cost))
	assert_bool(p.max_label.visible).is_false()


func test_l2_view_shows_the_two_named_branches_with_role_first() -> void:
	await _start_game()
	var def: TowerDef = _config.towers[RIFLE]
	await _open_tower(RIFLE, [""])
	var p := _game.tower_panel
	assert_str(p.title_label.text).is_equal("%s  L2" % def.name)
	assert_str(p.role_label.text).is_equal(def.role)
	assert_array(_visible_ups()).is_equal(["a", "b"])
	for b: String in ["a", "b"]:
		var br := def.branches[b]
		assert_str(_ups()[b].text).is_equal("%s — %s" % [br.name,
			TowerInfo.cost_text(br.upgrade_cost)])
		assert_str(_first_line(p.upgrade_infos[b])).is_equal(br.role)
	assert_bool(p.max_label.visible).is_false()


func test_l3_view_shows_max_level_branch_title_and_branch_role() -> void:
	await _start_game()
	var def: TowerDef = _config.towers[RIFLE]
	await _open_tower(RIFLE, ["", "b"])
	var p := _game.tower_panel
	assert_str(p.title_label.text).is_equal("%s  L3 · %s" % [def.name, def.branches["b"].name])
	assert_str(p.role_label.text).is_equal(def.branches["b"].role)
	assert_array(_visible_ups()).is_empty()
	assert_bool(p.max_label.visible).is_true()
	assert_str(p.max_label.text).is_equal("Max level")


# --- 25, 26: disabled reasons and the madness warning ----------------------------------------

func test_upgrade_is_disabled_mid_wave_and_enabled_again_after_it() -> void:
	await _start_game()
	await _open_tower(RIFLE)
	_run_into_wave()
	_game.tower_panel.refresh()
	assert_bool(_ups()[""].disabled).is_true()
	assert_str(_ups()[""].text).ends_with(" (only by day)")
	for i in 20000:
		if _game.sim.state.phase == SimState.Phase.BUILD:
			break
		for e in _game.sim.state.enemies:
			if not e.is_fake:
				_game.sim.apply_damage(e.id, 1.0e9, "test")
		_game.sim.step()
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.BUILD)
	_game.sim.state.gold = 10000
	_game.advance(0.0)
	_game.tower_panel.refresh()
	assert_bool(_ups()[""].disabled).is_false()
	assert_str(_ups()[""].text).not_contains("(")


func test_upgrade_is_disabled_without_gold_and_enabled_when_gold_rises() -> void:
	await _start_game()
	var def: TowerDef = _config.towers[RIFLE]
	await _open_tower(RIFLE, [""])
	_game.sim.state.gold = def.branches["a"].upgrade_cost - 1
	_game.tower_panel.refresh()
	for b: String in ["a", "b"]:
		assert_bool(_ups()[b].disabled).is_true()
		assert_str(_ups()[b].text).ends_with(" (not enough money)")
	_game.sim.state.gold = def.branches["a"].upgrade_cost
	_game.tower_panel.refresh()
	assert_bool(_ups()["a"].disabled).is_false()


func test_upgrade_is_disabled_once_the_run_is_over() -> void:
	await _start_game()
	await _open_tower(RIFLE)
	_game.sim.state.outcome = SimState.Outcome.LOST
	_game.tower_panel.refresh()
	assert_bool(_ups()[""].disabled).is_true()
	assert_str(_ups()[""].text).ends_with(" (run over)")


func _sign_sanity(v: float) -> void:
	_game.sim.state.sanity = v
	_game.sim.state.sanity_state = _game.sim.sanity_state_for(v)
	_game.tower_panel.refresh()


## LT-23 Q3: the warning follows the cap: an upgrade whose reserve delta takes the cap to 0
## warns but stays enabled; one that leaves it above 0 does not; none in MADNESS.
func test_an_upgrade_that_takes_the_cap_to_zero_warns_but_stays_enabled() -> void:
	await _start_game()
	await _open_tower(SIGN)
	var l2 := _config.towers[SIGN].levels[1]
	var top := _config.sanity.max_sanity
	l2.sanity_reserve = top  # cap after the upgrade: exactly 0
	_game.tower_panel.refresh()
	assert_bool(_ups()[""].disabled).is_false()
	assert_str(_ups()[""].text).ends_with(TowerInfo.MADNESS_WARNING)
	l2.sanity_reserve = top - 1.0  # cap after: 1
	_game.tower_panel.refresh()
	assert_str(_ups()[""].text).not_contains("drives you mad")
	# Current sanity does not matter (Q1): low sanity with room in the cap never warns.
	_sign_sanity(0.5)
	assert_str(_ups()[""].text).not_contains("drives you mad")
	l2.sanity_reserve = top
	_sign_sanity(0.0)  # already mad: nothing more to lose
	assert_int(_game.sim.state.sanity_state).is_equal(SimState.SanityState.MADNESS)
	assert_bool(_ups()[""].disabled).is_false()
	assert_str(_ups()[""].text).not_contains("drives you mad")


func test_a_tower_without_a_reserve_never_warns() -> void:
	_config.towers[SIGN].levels[0].sanity_reserve = _config.sanity.max_sanity - 0.5
	await _start_game()
	_game.sim.state.gold = 10000
	assert_int(_game.build(SIGN, _buildable_cell())).is_equal(Simulation.CommandResult.OK)
	assert_float(_game.sim.state.sanity_cap).is_equal_approx(0.5, 0.0001)
	await _open_tower(RIFLE)
	assert_float(_game.sim.reserve_delta(RIFLE, _config.towers[RIFLE].levels[0],
		_config.towers[RIFLE].levels[1])).is_equal(0.0)
	assert_str(_ups()[""].text).not_contains("drives you mad")


## LT-23 pin 25: an enabled build button warns when the L1 reserve would take the cap to 0;
## never for a reserve of 0, in MADNESS, or on a disabled button.
func test_build_button_warns_when_its_reserve_takes_the_cap_to_zero() -> void:
	var l1 := _config.towers[SIGN].levels[0]
	l1.sanity_reserve = _config.sanity.max_sanity
	await _start_game()
	_game.sim.state.gold = 10000
	await _click_cell(_buildable_cell())
	_game.picker.refresh()
	assert_bool(_game.picker.buttons[SIGN].disabled).is_false()
	assert_str(_game.picker.buttons[SIGN].text).ends_with(TowerInfo.MADNESS_WARNING)
	assert_str(_game.picker.buttons[RIFLE].text).not_contains("drives you mad")
	l1.sanity_reserve = _config.sanity.max_sanity - 1.0
	_game.picker.refresh()
	assert_str(_game.picker.buttons[SIGN].text).not_contains("drives you mad")
	l1.sanity_reserve = _config.sanity.max_sanity
	_game.sim.state.gold = 0
	_game.picker.refresh()
	assert_str(_game.picker.buttons[SIGN].text).ends_with(" (not enough money)")
	assert_str(_game.picker.buttons[SIGN].text).not_contains("drives you mad")
	_game.sim.state.gold = 10000
	_game.sim.state.sanity = 0.0
	_game.sim.state.sanity_state = SimState.SanityState.MADNESS
	_game.picker.refresh()
	assert_str(_game.picker.buttons[SIGN].text).not_contains("drives you mad")


# --- 27: upgrading from the panel -------------------------------------------------------------

func test_clicking_upgrade_and_branch_keeps_the_view_and_updates_ring_and_refund() -> void:
	await _start_game()
	var t := await _open_tower(RIFLE)
	var id := t.id
	await _click_control(_ups()[""])
	assert_int(t.level).is_equal(1)
	assert_bool(_game.tower_panel.visible).is_true()
	assert_int(_game.tower_panel.tower_id).is_equal(id)
	assert_float(_game.board.selected_range).is_equal(t.stats().range_cells)
	await _click_control(_ups()["a"])
	assert_int(t.level).is_equal(2)
	assert_str(t.branch).is_equal("a")
	assert_bool(_game.tower_panel.visible).is_true()
	assert_float(_game.board.selected_range).is_equal(t.stats().range_cells)
	var refund := _game.sim.sell_refund(t)
	assert_str(_game.tower_panel.sell_button.text).is_equal("Sell (+$%d)" % refund)
	if is_equal_approx(_config.economy.sell_refund_ratio, 0.7):
		assert_int(refund).is_equal(119)  # LT-24 §2: Rifleman L3 at today's config


# --- LT-31: target priority switch -------------------------------------------------------------

const PRIORITY_TEXTS := {"first": "Closest to the lighthouse", "strongest": "Strongest",
	"fastest": "Fastest"}


func _prio(mode: String) -> Button:
	return _game.tower_panel.get_node("Priority_" + mode) as Button


func _prio_title() -> Label:
	return _game.tower_panel.get_node("PriorityTitle") as Label


## The switch is shown with `current` marked "▸ ", disabled and in the role colour; the
## other modes read their plain name and are enabled.
func _assert_switch(current: String) -> void:
	assert_bool(_prio_title().visible).is_true()
	assert_str(_prio_title().text).is_equal("── Target ──")
	for mode: String in PRIORITY_TEXTS:
		var b := _prio(mode)
		assert_bool(b.visible).override_failure_message(mode).is_true()
		if mode == current:
			assert_str(b.text).is_equal("▸ " + PRIORITY_TEXTS[mode])
			assert_bool(b.disabled).override_failure_message(mode).is_true()
			assert_that(b.get_theme_color("font_disabled_color")).is_equal(SidePanel.COLOR_ROLE)
		else:
			assert_str(b.text).is_equal(PRIORITY_TEXTS[mode])
			assert_bool(b.disabled).override_failure_message(mode).is_false()
			assert_bool(b.has_theme_color_override("font_disabled_color")).is_false()


func test_targeting_towers_show_the_switch_between_stats_and_upgrade_first_marked() -> void:
	await _start_game()
	for def_id: String in [RIFLE, "harpooner", "necronomicon_reader"]:
		await _open_tower(def_id)
		_assert_switch("first")
	var p := _game.tower_panel
	var order := ["Stats", "PriorityTitle", "Priority_first", "Priority_strongest",
		"Priority_fastest", "UpgradeTitle"]
	var idx := order.map(func(n: String) -> int: return p.get_node(n).get_index())
	var sorted := idx.duplicate()
	sorted.sort()
	assert_array(idx).is_equal(sorted)


func test_elder_sign_hides_the_switch_at_every_level() -> void:
	await _start_game()
	for path: Array in [[], [""], ["", "a"]]:
		await _open_tower(SIGN, path)
		assert_bool(_prio_title().visible).override_failure_message(str(path)).is_false()
		for mode: String in PRIORITY_TEXTS:
			assert_bool(_prio(mode).visible).override_failure_message(mode).is_false()
	# Opening a targeting tower afterwards shows it again.
	await _open_tower(RIFLE)
	_assert_switch("first")


func test_clicking_a_mode_sets_it_marks_it_and_keeps_the_view() -> void:
	await _start_game()
	var t := await _open_tower(RIFLE)
	var log_size := _game.sim.state.command_log.size()
	await _click_control(_prio("fastest"))
	assert_str(t.target_priority).is_equal("fastest")
	assert_array(_game.sim.state.command_log.slice(log_size)) \
		.is_equal([[_game.sim.state.tick, "set_target_priority", t.id, "fastest"]])
	assert_bool(_game.tower_panel.visible).is_true()
	assert_int(_game.tower_panel.tower_id).is_equal(t.id)
	_assert_switch("fastest")
	await _click_control(_prio("first"))
	assert_str(t.target_priority).is_equal("first")
	_assert_switch("first")


func test_the_switch_stays_enabled_mid_wave() -> void:
	await _start_game()
	await _open_tower(RIFLE)
	_run_into_wave()
	_game.tower_panel.refresh()
	_assert_switch("first")


func test_after_the_outcome_the_other_modes_read_run_over() -> void:
	await _start_game()
	var t := await _open_tower(RIFLE)
	assert_int(_game.set_target_priority(t.id, "strongest")).is_equal(Simulation.CommandResult.OK)
	_game.sim.state.outcome = SimState.Outcome.LOST
	_game.tower_panel.refresh()
	assert_str(_prio("strongest").text).is_equal("▸ Strongest")
	assert_bool(_prio("strongest").disabled).is_true()
	for mode: String in ["first", "fastest"]:
		assert_bool(_prio(mode).disabled).override_failure_message(mode).is_true()
		assert_str(_prio(mode).text).is_equal(PRIORITY_TEXTS[mode] + " (run over)")


# --- HUD fix 22a9d9c ---------------------------------------------------------------------------

func test_hud_bar_spans_the_full_width_above_the_board() -> void:
	await _start_game()
	var hud := _game.hud
	assert_float(hud.get_global_rect().size.x).is_equal(1152.0)
	var bg: Control = hud.get_node("Background")
	assert_that(bg.get_global_rect()).is_equal(Rect2(0, 0, 1152, Game.BOARD_ORIGIN.y))


func test_a_range_ring_crossing_the_top_edge_is_drawn_under_the_hud() -> void:
	await _start_game()
	var hud := _game.hud
	# The HUD lives on a canvas layer above the board's canvas.
	var layer := hud.get_parent() as CanvasLayer
	assert_object(layer).is_not_null()
	assert_int(layer.layer).is_greater(0)
	assert_object(_game.board.get_canvas_layer_node()).is_null()
	# A ring around a top-row tower reaches above the board: that strip is HUD background.
	var t := await _open_tower(RIFLE)
	var ring_top := _game.board.position.y + (t.cell.y + 0.5 - _game.board.selected_range) * Board.CELL
	var cx := _game.board.position.x + (t.cell.x + 0.5) * Board.CELL
	var bg: Control = hud.get_node("Background")
	if ring_top < Game.BOARD_ORIGIN.y:
		assert_bool(bg.get_global_rect().has_point(Vector2(cx, maxf(ring_top, 0.0) + 1.0))).is_true()
	assert_bool(bg.get_global_rect().has_point(Vector2(cx, Game.BOARD_ORIGIN.y - 1.0))).is_true()


# --- LT-28: opaque buttons, the footer strip -------------------------------------------------

const BUTTON_BOXES := ["normal", "hover", "pressed", "hover_pressed", "disabled"]


## Every state box of `b` is an opaque flat box and its disabled text is opaque (the default
## theme draws both see-through).
func _assert_opaque_button(b: Button) -> void:
	for state: String in BUTTON_BOXES:
		var box := b.get_theme_stylebox(state) as StyleBoxFlat
		assert_object(box).override_failure_message("%s %s not flat" % [b.name, state]) \
			.is_not_null()
		if box != null:
			assert_float(box.bg_color.a).override_failure_message("%s %s" % [b.name, state]) \
				.is_equal(1.0)
	assert_float(b.get_theme_color("font_disabled_color").a).is_equal(1.0)
	assert_that(b.get_theme_color("font_disabled_color")).is_equal(UiStyle.COLOR_TEXT_DISABLED)


func test_picker_and_hud_buttons_are_opaque_and_a_disabled_one_stays_legible() -> void:
	await _start_game()
	await _click_cell(_buildable_cell())
	_game.sim.state.gold = 0
	_game.picker.refresh()
	var b: Button = _game.picker.buttons[RIFLE]
	assert_bool(b.disabled).is_true()
	_assert_opaque_button(b)
	_assert_opaque_button(_game.hud.call_wave_button)
	_assert_opaque_button(_game.hud.pause_button)


## The strip below the board is HUD background on the HUD layer, so a range ring crossing
## the bottom edge is drawn under it; it never takes a click.
func test_the_footer_covers_the_strip_below_the_board() -> void:
	await _start_game()
	var hud := _game.hud
	var footer := hud.get_node_or_null("Footer") as ColorRect
	assert_object(footer).is_not_null()
	if footer == null or not footer.is_inside_tree():
		return
	var m := _game.sim.state.map
	var bottom := Game.BOARD_ORIGIN.y + m.height * Board.CELL
	assert_float(bottom).is_less(648.0)
	assert_that(footer.get_global_rect()).is_equal(Rect2(0, bottom, 1152, 648 - bottom))
	assert_that(footer.color).is_equal(UiStyle.COLOR_BG)
	assert_float(footer.color.a).is_equal(1.0)
	assert_int(footer.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(footer.is_visible_in_tree()).is_true()
	# A ring around a tower on the lowest buildable row reaches below the board, into the footer.
	_game.sim.state.gold = 10000
	var cell := Vector2i(-1, -1)
	for y in range(m.height - 1, -1, -1):
		for x in m.width:
			if cell.x < 0 and m.is_buildable(Vector2i(x, y)):
				cell = Vector2i(x, y)
		if cell.x >= 0:
			break
	# The widest ring config has: an L3 branch (rifleman "a" today, 5 cells).
	var best_def := ""
	var best_branch := ""
	for id: String in _config.towers:
		var def: TowerDef = _config.towers[id]
		for b: String in def.branches:
			if best_def == "" or def.branches[b].range_cells \
					> _config.towers[best_def].branches[best_branch].range_cells:
				best_def = id
				best_branch = b
	assert_int(_game.build(best_def, cell)).is_equal(Simulation.CommandResult.OK)
	var t := _game.sim.tower_by_id(_game.sim.state.tower_at[cell])
	assert_int(_game.upgrade(t.id, "")).is_equal(Simulation.CommandResult.OK)
	assert_int(_game.upgrade(t.id, best_branch)).is_equal(Simulation.CommandResult.OK)
	await _click_cell(cell)
	assert_bool(_game.tower_panel.visible).is_true()
	var ring_bottom := _game.board.position.y + (cell.y + 0.5 + _game.board.selected_range) * Board.CELL
	var cx := _game.board.position.x + (cell.x + 0.5) * Board.CELL
	assert_float(ring_bottom).is_greater(bottom)
	assert_bool(footer.get_global_rect().has_point(Vector2(cx, minf(ring_bottom, 647.0)))).is_true()
