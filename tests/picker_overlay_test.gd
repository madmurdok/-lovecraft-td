class_name PickerOverlayTest
extends GdUnitTestSuite
## LT-53 (LT-43 §3, Q3, Q5 "one click builds, card on hover"), moved by LT-61 into the side
## panel: the build list sits inside SidePanel.panel_rect and never covers the board;
## hovering a row frames it, puts that tower's L1 range on the cell and shows its L1 card in
## the side panel; Esc, Cancel and a click elsewhere on the board close it and the side panel
## goes back to idle; one click builds; refusals (money, night "Only by day" in the title,
## any reason never in a cost cell) and the madness "!"; the Resonator's DPS is a range in
## the picker; nothing cut at 1280x720. Real mouse and key events go into a SubViewport;
## numbers come from config.

const RIFLE := "rifleman"
const SIGN := "elder_sign"
const R := Simulation.CommandResult

var _vp: SubViewport
var _game: Game
var _config: GameConfig


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = SubViewport.new()
	_vp.size = Vector2i(1200, 675)
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


func _move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	_vp.push_input(ev)
	await get_tree().process_frame


func _escape() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = pressed
		_vp.push_input(ev)
	await get_tree().process_frame


func _cell_centre(cell: Vector2i) -> Vector2:
	return _game.board.position + (Vector2(cell) + Vector2(0.5, 0.5)) * Board.CELL


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_game.board.position + Vector2(cell) * Board.CELL, Vector2.ONE * Board.CELL)


func _board() -> Rect2:
	var map := _game.sim.state.map
	return Rect2(Game.BOARD_ORIGIN, Vector2(map.width, map.height) * Board.CELL)


## The first free buildable cell of row `y` (or of the whole map for y < 0).
func _buildable(y := -1) -> Vector2i:
	var m := _game.sim.state.map
	for yy in m.height:
		if y >= 0 and yy != y:
			continue
		for x in m.width:
			var c := Vector2i(x, yy)
			if m.is_buildable(c) and not _game.sim.state.tower_at.has(c):
				return c
	return Vector2i(-1, -1)


func _open(cell: Vector2i) -> void:
	await _click(_cell_centre(cell))
	assert_bool(_game.picker.visible).override_failure_message("picker at %s" % cell).is_true()
	await get_tree().process_frame


func _text_w(l: Label, text := "") -> float:
	return l.get_theme_font("font").get_string_size(l.text if text.is_empty() else text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x


# --- placement (LT-61 §1) ---------------------------------------------------------------------

## Every row with a buildable cell: the list is inside the side panel and never over the board.
func test_picker_sits_in_the_side_panel_and_never_covers_the_board() -> void:
	await _start_game()
	var map := _game.sim.state.map
	var panel := SidePanel.panel_rect(map)
	for y in map.height:
		var cell := _buildable(y)
		if cell.x < 0:
			continue
		await _open(cell)
		var r := _game.picker.get_global_rect()
		var tag := "cell %s picker %s panel %s board %s" % [cell, r, panel, _board()]
		assert_bool(panel.encloses(r)).override_failure_message(tag).is_true()
		assert_bool(r.intersects(_board())).override_failure_message(tag + " covers the board") \
			.is_false()
		_game.picker.close()


# --- hover: frame, ring, card (§3, Q5) -----------------------------------------------------

func test_hover_frames_the_column_rings_its_range_and_shows_the_l1_card() -> void:
	await _start_game()
	_game.sim.state.gold = 10000
	var cell := _buildable(_game.sim.state.map.height - 1 - 4)  # lower half: overlay on top
	if cell.x < 0:
		cell = _buildable()
	await _open(cell)
	assert_bool(_game.side_panel.idle_label.visible).is_true()
	assert_str(_game.side_panel.idle_label.text).is_equal(SidePanel.PICK_TEXT)
	assert_float(_game.board.selected_range).is_equal(0.0)
	assert_that(_game.board.selected_cell).is_equal(cell)
	for id: String in ["dynamite_crew", "resonator"]:
		var def: TowerDef = _config.towers[id]
		var b: Button = _game.picker.buttons[id]
		await _move(b.get_global_rect().get_center())
		assert_str(_game.picker.hovered).is_equal(id)
		var frame := b.get_theme_stylebox("normal") as StyleBoxFlat
		assert_that(frame.border_color).is_equal(TowerPicker.COLOR_FRAME)
		assert_float(_game.board.selected_range).is_equal(def.levels[0].range_cells)
		assert_str(_game.board.selected_glyph).is_equal(def.glyph)
		assert_that(_game.board.selected_cell).is_equal(cell)
		var sp := _game.side_panel
		assert_bool(sp.card.is_visible_in_tree()).is_true()
		assert_bool(sp.idle_label.visible).is_false()
		assert_str(sp.card_title.text).is_equal(def.name)
		assert_str(sp.card_role.text).is_equal(def.role)
		var values := TowerInfo.row_values(def, def.levels[0], _config)
		assert_str(sp.card_table.heads[0].text).is_equal("")
		assert_bool(sp.card_table.get_node("Head").visible).is_false()
		for key: String in sp.card_table.row_keys:
			assert_str(sp.card_table.text_at(key, 0)).override_failure_message(key) \
				.is_equal(values[key])
		assert_str(sp.card_special.text).is_equal("\n".join(TowerInfo.special_lines(def.levels[0])))
		assert_str(sp.card_kind.text).is_equal("\n".join(TowerInfo.kind_lines(def, def.levels[0],
			_config.sanity)))
		assert_str(sp.card_path.text).is_equal("L2 $%d · then A %s or B %s" % [
			def.levels[1].upgrade_cost, def.branches["a"].name, def.branches["b"].name])
	# The previous column lost its frame.
	var dyn: Button = _game.picker.buttons["dynamite_crew"]
	assert_that((dyn.get_theme_stylebox("normal") as StyleBoxFlat).border_color) \
		.is_not_equal(TowerPicker.COLOR_FRAME)
	# Off the table: no hover, no ring, "Pick a tower to build".
	await _move(_cell_centre(cell))
	assert_str(_game.picker.hovered).is_equal("")
	assert_float(_game.board.selected_range).is_equal(0.0)
	assert_str(_game.board.selected_glyph).is_equal("")
	assert_bool(_game.side_panel.card.visible).is_false()
	assert_bool(_game.side_panel.idle_label.visible).is_true()
	assert_str(_game.side_panel.idle_label.text).is_equal(SidePanel.PICK_TEXT)
	assert_bool(_game.picker.visible).is_true()


# --- closing (§3): Esc, Cancel, a click elsewhere on the board ------------------------------

func _assert_closed(how: String, cell: Vector2i) -> void:
	assert_bool(_game.picker.visible).override_failure_message(how).is_false()
	assert_str(_game.picker.hovered).override_failure_message(how).is_equal("")
	assert_float(_game.board.selected_range).override_failure_message(how).is_equal(0.0)
	assert_str(_game.board.selected_glyph).override_failure_message(how).is_equal("")
	assert_that(_game.board.selected_cell).override_failure_message(how).is_equal(Vector2i(-1, -1))
	assert_bool(_game.side_panel.card.visible).override_failure_message(how).is_false()
	assert_bool(_game.side_panel.idle_label.visible).override_failure_message(how).is_true()
	assert_str(_game.side_panel.idle_label.text).override_failure_message(how) \
		.is_equal(SidePanel.IDLE_TEXT)
	assert_bool(_game.sim.state.tower_at.has(cell)).override_failure_message(how).is_false()


func _open_and_hover(cell: Vector2i) -> void:
	await _open(cell)
	await _move(_game.picker.buttons[RIFLE].get_global_rect().get_center())
	assert_str(_game.picker.hovered).is_equal(RIFLE)
	assert_str(_game.board.selected_glyph).is_equal(_config.towers[RIFLE].glyph)
	assert_bool(_game.side_panel.card.visible).is_true()


func test_esc_cancel_and_a_board_click_close_and_the_side_panel_goes_idle() -> void:
	await _start_game()
	_game.sim.state.gold = 10000
	var cell := _buildable(3)
	assert_int(cell.x).is_greater_equal(0)
	await _open_and_hover(cell)
	await _escape()
	_assert_closed("Esc", cell)
	await _open_and_hover(cell)
	await _click(_game.picker.cancel_button.get_global_rect().get_center())
	_assert_closed("Cancel", cell)
	# A click on a board cell the overlay does not cover (water or path: nothing opens).
	await _open_and_hover(cell)
	var r := _game.picker.get_global_rect()
	var other := Vector2i(-1, -1)
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if other.x < 0 and not m.is_buildable(c) and c != m.lighthouse \
					and not r.intersects(_cell_rect(c)):
				other = c
	assert_int(other.x).is_greater_equal(0)
	await _click(_cell_centre(other))
	_assert_closed("board click at %s" % other, cell)


# --- one click builds (Q5) -------------------------------------------------------------------

func test_one_click_on_a_hovered_column_builds_it_once_and_closes() -> void:
	await _start_game()
	_game.sim.state.gold = 10000
	var cell := _buildable(3)
	await _open_and_hover(cell)
	var cost: int = _config.towers[RIFLE].cost
	await _click(_game.picker.buttons[RIFLE].get_global_rect().get_center())
	assert_bool(_game.sim.state.tower_at.has(cell)).is_true()
	assert_str(_game.sim.tower_by_id(_game.sim.state.tower_at[cell]).def.id).is_equal(RIFLE)
	assert_int(_game.sim.state.gold).is_equal(10000 - cost)
	assert_int(_game.sim.state.towers.size()).is_equal(1)
	assert_bool(_game.picker.visible).is_false()


# --- refusals and the madness mark (§3) ------------------------------------------------------

## The first tooltip line (LT-61 §3: a second line names the trait).
func _tip_line(b: Button) -> String:
	return b.tooltip_text.get_slice("\n", 0)


func _tip(id: String) -> String:
	var def: TowerDef = _config.towers[id]
	return "%s — %s" % [def.name, TowerInfo.cost_text(def.cost)]


## LT-61 §6: at night every row is refused "only by day"; the title says it once ("Only by
## day"), the cost cell keeps the price alone; the tooltip keeps the full reason. Without the
## money the price turns red: money wins over night.
func test_night_puts_only_by_day_in_the_title() -> void:
	await _start_game()
	_game.sim.state.gold = 10000
	var cell := _buildable(3)
	assert_int(_game.call_wave()).is_equal(R.OK)
	_game.sim.step()
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.WAVE)
	await _open(cell)
	assert_str(_game.picker.title_label.text).is_equal("Only by day")
	for id: String in _config.towers:
		var def: TowerDef = _config.towers[id]
		var b: Button = _game.picker.buttons[id]
		var l: Label = _game.picker.costs[id]
		assert_int(_game.sim.can_build(id, cell)).is_equal(R.NOT_BUILD_PHASE)
		assert_bool(b.disabled).is_true()
		assert_str(l.text).is_equal(TowerInfo.cost_text(def.cost))
		assert_float(_text_w(l)).override_failure_message("%s '%s' %.1f > %.1f"
			% [id, l.text, _text_w(l), l.size.x]).is_less_equal(l.size.x)
		assert_str(_tip_line(b)).is_equal(_tip(id) + " (%s)" % TowerInfo.reason(R.NOT_BUILD_PHASE))
		assert_that(_game.picker.cells[id]["dps"].modulate).is_equal(TowerPicker.DIM)
	_game.sim.state.gold = 0
	_game.picker.refresh()
	for id: String in _config.towers:
		var l: Label = _game.picker.costs[id]
		assert_str(l.text).is_equal(TowerInfo.cost_text(_config.towers[id].cost))
		assert_that(l.get_theme_color("font_color")).is_equal(TowerPicker.STATUS_COLOR)
		assert_str(_tip_line(_game.picker.buttons[id])).is_equal(_tip(id) + " (not enough money)")


## Behaviour 27 (LT-61 §6): a refusal not about money (an occupied cell) never goes in a
## cost cell: the price stands alone, the title has the reason, the tooltip has it all.
func test_a_long_refusal_reason_never_cuts_the_cost_cell() -> void:
	await _start_game()
	_game.sim.state.gold = 10000
	var cell := _buildable(3)
	await _open(cell)
	_game.sim.state.gold = 10000
	assert_int(_game.sim.build_tower(RIFLE, cell)).is_equal(R.OK)
	_game.picker.refresh()
	await get_tree().process_frame
	var reason := TowerInfo.reason(R.OCCUPIED)
	for id: String in _config.towers:
		var price := TowerInfo.cost_text(_config.towers[id].cost)
		var l: Label = _game.picker.costs[id]
		assert_bool(_game.picker.buttons[id].disabled).is_true()
		assert_str(l.text).override_failure_message("%s '%s'" % [id, l.text]).is_equal(price)
		assert_float(_text_w(l)).override_failure_message("%s '%s'" % [id, l.text]) \
			.is_less_equal(l.size.x)
		assert_str(_tip_line(_game.picker.buttons[id])).is_equal(_tip(id) + " (%s)" % reason)
	assert_str(_game.picker.title_label.text.to_lower()).is_equal(reason)


## LT-23 Q3 in the picker: a reserve that takes the cap to 0 marks the Trait cell "Res N!" in
## red, the row stays enabled and its tooltip's first line ends with MADNESS_WARNING.
func test_a_build_that_drives_mad_marks_the_trait_cell() -> void:
	var l1: TowerDef.Level = _config.towers[SIGN].levels[0]
	l1.sanity_reserve = _config.sanity.max_sanity
	await _start_game()
	_game.sim.state.gold = 10000
	await _open(_buildable(3))
	var cell: Label = _game.picker.cells[SIGN]["trait"]
	assert_bool(_game.picker.buttons[SIGN].disabled).is_false()
	assert_str(cell.text).is_equal("Res " + TowerInfo.num(l1.sanity_reserve) + "!")
	assert_that(cell.get_theme_color("font_color")).is_equal(TowerPicker.STATUS_COLOR)
	assert_str(_tip_line(_game.picker.buttons[SIGN])).is_equal(_tip(SIGN) + TowerInfo.MADNESS_WARNING)
	var rifle: Label = _game.picker.cells[RIFLE]["trait"]
	assert_str(rifle.text).is_equal(TowerInfo.CELL_DASH)


# --- ghost glyph (LT-61 §7) ------------------------------------------------------------------

## Hovering a row puts that tower's board letter in selected_glyph, moving to another row
## swaps it, leaving the list clears it; opening starts without one; building clears it.
func test_ghost_glyph_follows_the_hovered_row_and_clears_on_leave_and_build() -> void:
	await _start_game()
	_game.sim.state.gold = 10000
	var cell := _buildable(3)
	await _open(cell)
	assert_str(_game.board.selected_glyph).is_equal("")
	var glyphs := {}
	for id: String in ["dynamite_crew", "resonator", RIFLE]:
		await _move(_game.picker.buttons[id].get_global_rect().get_center())
		glyphs[id] = _config.towers[id].glyph
		assert_str(_game.board.selected_glyph).override_failure_message(id) \
			.is_equal(_config.towers[id].glyph)
	var letters := {}
	for g: String in glyphs.values():
		assert_str(g).is_not_empty()
		letters[g] = true
	assert_int(letters.size()).is_equal(3)  # three different letters, read from config
	await _move(_cell_centre(cell))
	assert_str(_game.board.selected_glyph).is_equal("")
	await _move(_game.picker.buttons[RIFLE].get_global_rect().get_center())
	assert_str(_game.board.selected_glyph).is_equal(_config.towers[RIFLE].glyph)
	await _click(_game.picker.buttons[RIFLE].get_global_rect().get_center())
	assert_bool(_game.sim.state.tower_at.has(cell)).is_true()
	assert_bool(_game.picker.visible).is_false()
	assert_str(_game.board.selected_glyph).is_equal("")
	# Reopening starts clean.
	await _open(_buildable(5))
	assert_str(_game.board.selected_glyph).is_equal("")
	assert_str(_game.picker.hovered).is_equal("")


## close() on its own (the code path every exit shares) drops the glyph even when no mouse
## event left the row first.
func test_close_clears_the_glyph_of_a_still_hovered_row() -> void:
	await _start_game()
	_game.sim.state.gold = 10000
	await _open(_buildable(3))
	await _move(_game.picker.buttons[RIFLE].get_global_rect().get_center())
	assert_str(_game.board.selected_glyph).is_not_empty()
	_game.picker.close()
	assert_str(_game.board.selected_glyph).is_equal("")
	assert_str(_game.picker.hovered).is_equal("")


# --- the title line and the cost, by state (LT-61 §6) ----------------------------------------

func _cheapest() -> int:
	var low := 1 << 30
	for id: String in _config.towers:
		low = mini(low, _config.towers[id].cost)
	return low


## By day: enough money for some rows keeps "Build here" (white) and reddens only the costs
## it cannot pay; money for none says "Not enough money" in red; night says "Only by day"
## whatever the money; money back clears the title.
func test_title_says_the_refusal_once_and_costs_redden_alone() -> void:
	await _start_game()
	var cell := _buildable(3)
	_game.sim.state.gold = _cheapest()
	await _open(cell)
	var t := _game.picker.title_label
	assert_str(t.text).is_equal(TowerPicker.TITLE_TEXT)
	assert_that(t.get_theme_color("font_color")).is_equal(Color.WHITE)
	var poor := 0
	for id: String in _config.towers:
		var can := _game.sim.can_build(id, cell) == R.OK
		var col := _game.picker.costs[id].get_theme_color("font_color")
		assert_that(col).override_failure_message(id).is_equal(
			StatsTable.COLOR_VALUE if can else TowerPicker.STATUS_COLOR)
		poor += 0 if can else 1
	assert_int(poor).is_greater(0)
	_game.sim.state.gold = _cheapest() - 1
	_game.picker.refresh()
	assert_str(t.text).is_equal("Not enough money")
	assert_that(t.get_theme_color("font_color")).is_equal(TowerPicker.STATUS_COLOR)
	_game.sim.state.gold = 10000
	_game.picker.refresh()
	assert_str(t.text).is_equal(TowerPicker.TITLE_TEXT)
	assert_that(t.get_theme_color("font_color")).is_equal(Color.WHITE)
	assert_int(_game.call_wave()).is_equal(R.OK)
	_game.sim.step()
	_game.sim.state.gold = 0
	_game.picker.refresh()
	assert_str(t.text).is_equal("Only by day")
	assert_that(t.get_theme_color("font_color")).is_equal(TowerPicker.STATUS_COLOR)
	_game.sim.state.gold = 10000
	_game.picker.refresh()
	assert_str(t.text).is_equal("Only by day")


# --- the tooltip's second line (LT-61 §3) ----------------------------------------------------

## Line 1 is the name, cost and any refusal / madness warning; line 2 spells out the trait
## tag (none for the dash); the "!" does not change line 2.
func test_tooltip_second_line_spells_out_the_trait() -> void:
	await _start_game()
	_game.sim.state.gold = 10000
	await _open(_buildable(3))
	var res: float = _config.towers[SIGN].levels[0].sanity_reserve
	var blind: float = _config.towers["coast_battery"].levels[0].min_range
	var want := {
		RIFLE: "",
		"harpooner": "Line: pierces",
		SIGN: "Sanity reserve " + TowerInfo.num(res),
		"dynamite_crew": "Ground: never hits flyers",
		"coast_battery": "Blind %s: can't fire within %s cells" % [TowerInfo.num(blind), TowerInfo.num(blind)],
		"searchlight": "Reveal: shows fakes",
	}
	for id: String in want:
		var lines := _game.picker.buttons[id].tooltip_text.split("\n")
		assert_str(lines[0]).override_failure_message(id).is_equal(_tip(id))
		if want[id].is_empty():
			assert_int(lines.size()).override_failure_message(id).is_equal(1)
		else:
			assert_int(lines.size()).override_failure_message(id).is_equal(2)
			assert_str(lines[1]).override_failure_message(id).is_equal(want[id])
	# Refused: line 1 carries the reason, line 2 stays.
	_game.sim.state.gold = 0
	_game.picker.refresh()
	var b := _game.picker.buttons["harpooner"]
	assert_str(b.tooltip_text.get_slice("\n", 0)).is_equal(_tip("harpooner") + " (not enough money)")
	assert_str(b.tooltip_text.get_slice("\n", 1)).is_equal("Line: pierces")


# --- the list above the card (LT-61 §1) ------------------------------------------------------

func test_list_sits_above_the_card_and_both_inside_the_panel() -> void:
	await _start_game()
	_game.sim.state.gold = 10000
	await _open(_buildable(3))
	var sp := _game.side_panel
	await _move(_game.picker.buttons[RIFLE].get_global_rect().get_center())
	var pr := _game.picker.get_global_rect()
	var cr := sp.card.get_global_rect()
	var panel := SidePanel.panel_rect(_game.sim.state.map)
	assert_bool(sp.card.is_visible_in_tree()).is_true()
	assert_float(cr.position.y).is_greater_equal(pr.end.y)
	assert_bool(panel.encloses(cr)).override_failure_message("card %s panel %s" % [cr, panel]).is_true()
	assert_float(sp.scroll.get_global_rect().position.y).is_greater_equal(pr.end.y)


# --- Q3: the Resonator's DPS, range in the picker, live in the panel -------------------------

func test_resonator_dps_is_a_range_in_the_picker_and_live_in_the_panel() -> void:
	await _start_game()
	assert_int(_game.sim.debug_set_sanity(37.0)).is_equal(R.OK)
	var s: TowerDef.Level = _config.towers["resonator"].levels[0]
	var base := s.damage / s.fire_interval
	var k: float = s.effects["sanity_scaling"]
	var top := _config.sanity.max_sanity
	var cell := _buildable(3)
	_game.sim.state.gold = 10000
	await _open(cell)
	assert_str(_game.picker.cells["resonator"]["dps"].text).is_equal("%s–%s" % [
		TowerInfo.num(roundf(base * 10.0) / 10.0), TowerInfo.num(roundf(base * (1.0 + k) * 10.0) / 10.0)])
	await _click(_game.picker.buttons["resonator"].get_global_rect().get_center())
	assert_bool(_game.sim.state.tower_at.has(cell)).is_true()
	await _click(_cell_centre(cell))
	assert_bool(_game.tower_panel.visible).is_true()
	var live := base * (1.0 + k * (1.0 - _game.sim.state.sanity / top))
	assert_str(_game.tower_panel.stats_table.text_at("dps", 0)).is_equal(
		TowerInfo.num(roundf(live * 10.0) / 10.0))


# --- nothing cut at 1280x720 -----------------------------------------------------------------

## At 1280x720 (base 1152x648 stretched) by day and at night: every cell of the 10 shipped
## rows is at least as wide as its text, and the list is inside the side panel.
func test_no_picker_text_is_cut_at_1280x720() -> void:
	_vp.size = Vector2i(1280, 720)
	_vp.size_2d_override = Vector2i(1200, 675)
	_vp.size_2d_override_stretch = true
	await _start_game()
	assert_int(_config.towers.size()).is_equal(10)
	var cuts := []
	for night: bool in [false, true]:
		_game.sim.state.gold = 10000
		if night:
			assert_int(_game.call_wave()).is_equal(R.OK)
			_game.sim.step()
		_game.picker.open_for(_buildable(3))
		await get_tree().process_frame
		await get_tree().process_frame
		if not SidePanel.panel_rect(_game.sim.state.map).encloses(_game.picker.get_global_rect()):
			cuts.append("night=%s picker %s" % [night, _game.picker.get_global_rect()])
		for id: String in _config.towers:
			var labels: Array = [_game.picker.names[id], _game.picker.costs[id]]
			labels.append_array(_game.picker.cells[id].values())
			for l: Label in labels:
				var tag := "night=%s %s %s '%s'" % [night, id, l.name, l.text]
				if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
					if _text_w(l) > l.size.x + 0.01:
						cuts.append("%s %.1f > %.1f" % [tag, _text_w(l), l.size.x])
					continue
				if l.get_line_count() > 2:
					cuts.append("%s %d lines" % [tag, l.get_line_count()])
				for word in l.text.split(" "):
					if _text_w(l, word) > l.size.x + 0.01:
						cuts.append("%s word '%s'" % [tag, word])
		_game.picker.close()
	assert_array(cuts).is_empty()
