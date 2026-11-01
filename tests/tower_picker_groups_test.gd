class_name TowerPickerGroupsTest
extends ConfigTestBase
## LT-55 (LT-46 P15), LT-61: the build list shows two labelled groups, "MUNDANE" then
## "OCCULT", by TowerDef.kind, data order inside each; with 10 towers the list fits the side
## panel's 176 px at 1152x648. Each row shows its short name, cost, L1 DPS and trait. The 10-tower config is built
## here (res://data plus five towers appended in mixed kind order), never in data/. Real mouse
## events go into a 1152x648 SubViewport like side_panel_test.

const RIFLE := "rifleman"
const SIGN := "elder_sign"

const PER_KIND := 5
## Padding per kind, used in this order until the kind has PER_KIND towers. Names near the
## longest real one, roles at the 24-char limit: the worst case for the fit. The glyph
## column is unused: _ten_config picks glyphs no shipped tower has.
const DUMMIES := {
	"mundane": [
		["lamplighter", "Lamplighter", "Lamps reveal the unseen!", "L"],
		["harbour_watchman", "Harbour Watchman", "Warns of foes far ahead.", "W"],
		["dock_sniper", "Innsmouth Dock Sniper", "Picks off the far stragg", "D"],
		["net_thrower", "Fishing Net Thrower", "Nets slow a whole column", "N"],
		["flare_gunner", "Lighthouse Flare Gun", "Flares light the shallow", "F"],
	],
	"occult": [
		["shoggoth_binder", "Shoggoth Binder", "Binds foes, then crushes", "S"],
		["yithian_lens", "Yithian Scrying Lens", "Scrying lens marks prey.", "Y"],
		["mi_go_cylinder", "Mi-Go Brain Cylinder", "Burns wide cones of foes", "M"],
		["dagon_idol", "Idol of Father Dagon", "Calls the deep to drown", "I"],
		["silver_key", "The Silver Key Gate", "Opens a gate under foes", "K"],
	],
}

var _vp: SubViewport
var _game: Game
var _config: GameConfig
var _ten_mundane: Array = []  ## the 10-tower fixture's mundane ids, config order
var _ten_occult: Array = []


func before_test() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1152, 648)
	add_child(_vp)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _data_config() -> GameConfig:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	return r.config


## Exactly PER_KIND mundane + PER_KIND occult towers, whatever res://data ships: the real
## towers of each kind in data order (any past PER_KIND dropped), then DUMMIES padding with
## kinds alternating, so config order != group order. Each dummy copies the first real tower
## of its kind. Loaded through the real towers.json parser, written with sort_keys off:
## ConfigTestBase.edit's JSON.stringify sorts keys and would lose data order.
func _ten_config() -> GameConfig:
	var dir := make_dir()
	var d: Dictionary = JSON.parse_string(read_file(dir, "towers.json"))
	var real: Dictionary = d["towers"]
	var out := {}
	var ids := {"mundane": [], "occult": []}
	for id: String in real:
		var kind: String = real[id]["kind"]
		if ids[kind].size() < PER_KIND:
			out[id] = real[id]
			ids[kind].append(id)
	var templates := {"mundane": ids["mundane"][0], "occult": ids["occult"][0]}
	# Glyphs are unique per config: dummies take letters no shipped tower uses (its glyph, or
	# the first letter of its name when it has none, as TowerDef.parse does).
	var used := {}
	for id: String in real:
		used[String(real[id].get("glyph", String(real[id]["name"]).left(1)))] = true
	var free := []
	for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
		if not used.has(c):
			free.append(c)
	var next := {"mundane": 0, "occult": 0}
	while ids["mundane"].size() < PER_KIND or ids["occult"].size() < PER_KIND:
		for kind: String in ["occult", "mundane"]:
			if ids[kind].size() >= PER_KIND:
				continue
			var e: Array = DUMMIES[kind][next[kind]]
			next[kind] += 1
			var t: Dictionary = real[templates[kind]].duplicate(true)
			t["name"] = e[1]
			t["role"] = e[2]
			t["glyph"] = free.pop_front()
			out[e[0]] = t
			ids[kind].append(e[0])
	d["towers"] = out
	write_file(dir, "towers.json", JSON.stringify(d, "  ", false))
	var r := GameConfig.load_from_dir(dir)
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_int(r.config.towers.size()).is_equal(2 * PER_KIND)
	_ten_mundane = ids["mundane"]
	_ten_occult = ids["occult"]
	return r.config


func _start_game(config: GameConfig) -> void:
	_config = config
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
	await _click(c.get_global_rect().get_center())


func _buildable_cell() -> Vector2i:
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			if m.is_buildable(Vector2i(x, y)) and not _game.sim.state.tower_at.has(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _open_picker() -> void:
	var cell := _buildable_cell()
	await _click(_game.board.position + (Vector2(cell) + Vector2(0.5, 0.5)) * Board.CELL)
	assert_bool(_game.picker.visible).is_true()
	await get_tree().process_frame


## Ids of `kind` in config order.
func _ids_of(kind: String) -> Array:
	var out := []
	for id: String in _config.towers:
		if _config.towers[id].kind == kind:
			out.append(id)
	return out


## The picker list's scrolling children by name, in order (LT-61: the mundane rows under
## the pinned MUNDANE line, then the OCCULT line and the occult rows).
func _child_names() -> Array:
	var out := []
	for c in _game.picker.find_child("Body", true, false).get_children():
		out.append(String(c.name))
	return out


func _expected_children(mundane: Array, occult: Array) -> Array:
	var out := []
	for id: String in mundane:
		out.append("Tower_" + id)
	out.append("Group_occult")
	for id: String in occult:
		out.append("Tower_" + id)
	return out


## The first tooltip line (LT-61 §3: a second line names the trait).
func _tip_line(id: String) -> String:
	return _game.picker.buttons[id].tooltip_text.get_slice("\n", 0)


func _tip(id: String) -> String:
	var def: TowerDef = _config.towers[id]
	return "%s — %s" % [def.name, TowerInfo.cost_text(def.cost)]


# --- grouping, order, headers ---------------------------------------------------------------

func test_data_towers_are_grouped_mundane_then_occult_in_data_order() -> void:
	await _start_game(_data_config())
	assert_array(_ids_of("mundane")).is_not_empty()
	assert_array(_ids_of("occult")).is_not_empty()
	assert_array(_child_names()).is_equal(_expected_children(_ids_of("mundane"), _ids_of("occult")))


func test_ten_towers_group_by_kind_and_keep_data_order_inside_each_group() -> void:
	await _start_game(_ten_config())
	assert_array(_ten_mundane).has_size(PER_KIND)
	assert_array(_ten_occult).has_size(PER_KIND)
	assert_array(_ids_of("mundane")).is_equal(_ten_mundane)
	assert_array(_ids_of("occult")).is_equal(_ten_occult)
	# The fixture interleaves kinds, so a data-order list would not match.
	assert_array(_config.towers.keys()).is_not_equal(_ten_mundane + _ten_occult)
	assert_array(_child_names()).is_equal(_expected_children(_ten_mundane, _ten_occult))
	assert_int(_game.picker.buttons.size()).is_equal(10)
	assert_int(_game.picker.costs.size()).is_equal(10)
	for id: String in _config.towers:
		assert_str(String(_game.picker.buttons[id].name)).is_equal("Tower_" + id)


func test_group_headers_read_mundane_and_occult() -> void:
	await _start_game(_ten_config())
	await _open_picker()
	for pair: Array in [["Group_mundane", "MUNDANE"], ["Group_occult", "OCCULT"]]:
		var line := _game.picker.find_child(pair[0], true, false)
		assert_object(line).is_not_null()
		var h := line.get_node("Title") as Label
		assert_object(h).is_not_null()
		assert_str(h.text).is_equal(pair[1])
		assert_bool(h.is_visible_in_tree()).is_true()


# --- LT-61 §2: the row cells ---------------------------------------------------------------

func test_every_row_shows_its_short_name_cost_dps_and_trait() -> void:
	await _start_game(_ten_config())
	_game.sim.state.gold = 10000
	await _open_picker()
	for id: String in _config.towers:
		var def: TowerDef = _config.towers[id]
		assert_str(_game.picker.names[id].text).is_equal(def.short_name)
		assert_str(_game.picker.costs[id].text).is_equal(TowerInfo.cost_text(def.cost))
		assert_str(_game.picker.cells[id]["dps"].text).override_failure_message(id) \
			.is_equal(TowerInfo.dps_text(def.levels[0], _config))
		assert_str(_game.picker.cells[id]["trait"].text).override_failure_message(id) \
			.is_equal(TowerInfo.trait_text(def, def.levels[0]))


# --- fit: 10 towers, 1152x648, the side panel's 176 px --------------------------------------

func _assert_fits(state: String) -> void:
	var map := _game.sim.state.map
	var panel := SidePanel.panel_rect(map)
	var r := _game.picker.get_global_rect()
	assert_bool(panel.encloses(r)).override_failure_message(
		"%s: picker %s outside the panel %s" % [state, r, panel]).is_true()
	assert_float(r.size.x).override_failure_message("%s: picker %s wider than 176 px"
		% [state, r]).is_less_equal(176.0)
	for id: String in _config.towers:
		var c: Control = _game.picker.buttons[id]
		assert_bool(r.encloses(c.get_global_rect())).override_failure_message(
			"%s: %s at %s outside %s" % [state, c.name, c.get_global_rect(), r]).is_true()


func test_ten_affordable_towers_fit_176_px_at_1152x648() -> void:
	await _start_game(_ten_config())
	assert_that(_vp.size).is_equal(Vector2i(1152, 648))
	_game.sim.state.gold = 10000
	await _open_picker()
	await get_tree().process_frame
	for id: String in _config.towers:
		assert_bool(_game.picker.buttons[id].disabled).is_false()
	_assert_fits("affordable")


func test_ten_unaffordable_towers_fit_176_px_at_1152x648() -> void:
	await _start_game(_ten_config())
	_game.sim.state.gold = 0
	await _open_picker()
	await get_tree().process_frame
	for id: String in _config.towers:
		assert_bool(_game.picker.buttons[id].disabled).is_true()
	_assert_fits("not enough money")


# --- states and pressing, both groups -------------------------------------------------------

func test_refresh_states_hold_for_all_ten_columns() -> void:
	await _start_game(_ten_config())
	_game.sim.state.gold = 10000
	await _open_picker()
	for id: String in _config.towers:
		assert_bool(_game.picker.buttons[id].disabled).is_false()
		assert_str(_tip_line(id)).is_equal(_tip(id))
		assert_that(_game.picker.costs[id].get_theme_color("font_color")) \
			.is_equal(StatsTable.COLOR_VALUE)
	_game.sim.state.gold = 0
	_game.picker.refresh()
	for id: String in _config.towers:
		assert_bool(_game.picker.buttons[id].disabled).is_true()
		assert_str(_tip_line(id)).is_equal(_tip(id) + " (not enough money)")
		assert_that(_game.picker.costs[id].get_theme_color("font_color")) \
			.is_equal(TowerPicker.STATUS_COLOR)
	# Affordable again: the cost is back to its plain colour.
	_game.sim.state.gold = 10000
	_game.picker.refresh()
	for id: String in _config.towers:
		assert_str(_tip_line(id)).is_equal(_tip(id))
		assert_that(_game.picker.costs[id].get_theme_color("font_color")) \
			.is_equal(StatsTable.COLOR_VALUE)


## LT-43 §3: unaffordable only reddens the cost; the cost cell never carries that reason.
func test_cost_cell_never_contains_the_money_reason() -> void:
	await _start_game(_ten_config())
	await _open_picker()
	for gold in [0, 10000]:
		_game.sim.state.gold = gold
		_game.picker.refresh()
		for id: String in _config.towers:
			var t: String = _game.picker.costs[id].text
			assert_str(t).is_equal(TowerInfo.cost_text(_config.towers[id].cost))
			assert_str(t).not_contains("(")


## Verify of LT-55, carried to LT-43: every shipped tower's cost cell fits its column, so no
## ellipsis cuts the price.
func test_every_shipped_towers_price_is_visible_in_full() -> void:
	await _start_game(_data_config())
	_game.sim.state.gold = 0
	await _open_picker()
	await get_tree().process_frame
	for id: String in _config.towers:
		var l: Label = _game.picker.costs[id]
		var font := l.get_theme_font("font")
		var text_w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			l.get_theme_font_size("font_size")).x
		assert_float(text_w).override_failure_message("%s: \"%s\" is %.1f px, cell %.1f px"
			% [id, l.text, text_w, l.size.x]).is_less_equal(l.size.x)
		assert_str(l.text).is_equal(TowerInfo.cost_text(_config.towers[id].cost))


func test_pressing_a_button_in_either_group_builds_it_and_closes_the_picker() -> void:
	await _start_game(_ten_config())
	for id: String in [_ten_mundane[-1], _ten_occult[-1]]:
		_game.sim.state.gold = 10000
		var cell := _buildable_cell()
		await _open_picker()
		await _click_control(_game.picker.buttons[id])
		assert_bool(_game.sim.state.tower_at.has(cell)) \
			.override_failure_message("%s not built" % id).is_true()
		assert_str(_game.sim.tower_by_id(_game.sim.state.tower_at[cell]).def.id).is_equal(id)
		assert_bool(_game.picker.visible).is_false()


# --- LT-61 §2, §5: columns, names, scrolling -----------------------------------------------

## res://data towers plus clones of the first mundane one (own id, long name, free glyph)
## until the list has `total` towers.
func _total_config(total: int) -> GameConfig:
	var dir := make_dir()
	var d: Dictionary = JSON.parse_string(read_file(dir, "towers.json"))
	var towers: Dictionary = d["towers"]
	var template: Dictionary = {}
	var used := {}
	for id: String in towers:
		used[String(towers[id].get("glyph", String(towers[id]["name"]).left(1)))] = true
		if template.is_empty() and towers[id]["kind"] == "mundane":
			template = towers[id]
	var free := []
	for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
		if not used.has(c):
			free.append(c)
	var n := 0
	while towers.size() < total:
		n += 1
		var t: Dictionary = template.duplicate(true)
		t["name"] = "Extra Harbour Gunner %d" % n
		t.erase("short")
		t["glyph"] = free.pop_front()
		towers["extra_gunner_%d" % n] = t
	d["towers"] = towers
	write_file(dir, "towers.json", JSON.stringify(d, "  ", false))
	var r := GameConfig.load_from_dir(dir)
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_int(r.config.towers.size()).is_equal(total)
	return r.config


func _name_w(l: Label, fs: int) -> float:
	return l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _font_of(l: Label) -> int:
	return l.get_theme_font_size("font_size")


## The widths of the four cells add up to the panel's 176 px, and each cell has its width.
func test_row_cells_have_their_column_widths_summing_to_176() -> void:
	await _start_game(_data_config())
	_game.sim.state.gold = 10000
	await _open_picker()
	await get_tree().process_frame
	var sum := TowerPicker.NAME_W + TowerPicker.COST_W + TowerPicker.COST_GAP \
		+ TowerPicker.DPS_W + TowerPicker.TRAIT_W
	assert_int(sum).is_equal(176)
	assert_float(_game.picker.size.x).is_equal(176.0)
	for id: String in _config.towers:
		assert_float(_game.picker.names[id].size.x).override_failure_message(id) \
			.is_equal(float(TowerPicker.NAME_W))
		assert_float(_game.picker.costs[id].size.x).is_equal(float(TowerPicker.COST_W))
		assert_float(_game.picker.cells[id]["dps"].size.x).is_equal(float(TowerPicker.DPS_W))
		assert_float(_game.picker.cells[id]["trait"].size.x).is_equal(float(TowerPicker.TRAIT_W))
		var row: Control = _game.picker.buttons[id].find_child("Gap", true, false)
		assert_float(row.size.x).is_equal(float(TowerPicker.COST_GAP))


## Every shipped name fits NAME_W whole, with no ellipsis: the owner's short names at the
## full 12 px, the unchanged names (a few px wider) shrunk by at most to the 10 px floor.
func test_shipped_names_fit_the_name_column_whole() -> void:
	await _start_game(_data_config())
	await _open_picker()
	await get_tree().process_frame
	var shortened := 0
	for id: String in _config.towers:
		var def: TowerDef = _config.towers[id]
		var l: Label = _game.picker.names[id]
		var fs := _font_of(l)
		assert_str(l.text).is_equal(def.short_name)
		assert_int(fs).is_between(TowerPicker.NAME_FONT_MIN, TowerPicker.FONT_SIZE)
		assert_float(_name_w(l, fs)).override_failure_message(
			"%s '%s' %.1f px at %d > %d" % [id, l.text, _name_w(l, fs), fs, TowerPicker.NAME_W]) \
			.is_less_equal(float(TowerPicker.NAME_W))
		if def.short_name != def.name:
			shortened += 1
			assert_int(fs).override_failure_message("%s '%s'" % [id, l.text]) \
				.is_equal(TowerPicker.FONT_SIZE)
	assert_int(shortened).is_greater(0)


## A name wider than NAME_W shrinks 12 -> 10 until it fits, at 10 it ends in an ellipsis.
## The expectation is recomputed here from the font, not read from the picker.
func test_a_long_name_shrinks_to_10_px_then_ends_in_an_ellipsis() -> void:
	await _start_game(_total_config(11))
	await _open_picker()
	var shrunk := 0
	var ellipsis := 0
	for id: String in _config.towers:
		var l: Label = _game.picker.names[id]
		var want := TowerPicker.FONT_SIZE
		while want > TowerPicker.NAME_FONT_MIN and _name_w(l, want) > TowerPicker.NAME_W:
			want -= 1
		assert_int(_font_of(l)).override_failure_message("%s '%s'" % [id, l.text]).is_equal(want)
		shrunk += 1 if want < TowerPicker.FONT_SIZE else 0
		if _name_w(l, want) > TowerPicker.NAME_W:
			ellipsis += 1
			assert_int(want).is_equal(TowerPicker.NAME_FONT_MIN)
			assert_int(l.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_int(shrunk).override_failure_message("fixture has no long name").is_greater(0)
	assert_int(ellipsis).override_failure_message("fixture has no over-long name").is_greater(0)


## 10 shipped towers: no scrolling in the list (neither way), the whole list inside 176 px.
func test_ten_towers_need_no_scrolling_in_the_list() -> void:
	await _start_game(_data_config())
	_game.sim.state.gold = 10000
	await _open_picker()
	await get_tree().process_frame
	await get_tree().process_frame
	var rows := _game.picker.rows_scroll
	assert_int(rows.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	assert_bool(rows.get_h_scroll_bar().visible).is_false()
	assert_bool(rows.get_v_scroll_bar().visible).is_false()
	var body: Control = rows.get_child(0)
	assert_float(body.get_combined_minimum_size().y).is_less_equal(rows.size.y)
	assert_float(body.get_combined_minimum_size().x).is_less_equal(rows.size.x)
	assert_float(rows.custom_minimum_size.y).is_equal(float(
		_config.towers.size() * TowerPicker.ROW_H + TowerPicker.GROUP_H))
	assert_float(rows.size.y).is_equal(rows.custom_minimum_size.y)


## Each shipped tower's card, shown below the list, fits the side panel without scrolling.
func test_every_card_fits_below_the_list_without_scrolling() -> void:
	await _start_game(_data_config())
	_game.sim.state.gold = 10000
	await _open_picker()
	var sp := _game.side_panel
	for id: String in _config.towers:
		sp.show_card(id)
		await get_tree().process_frame
		await get_tree().process_frame
		var bar := sp.scroll.get_v_scroll_bar()
		assert_bool(bar.visible).override_failure_message("%s card scrolls" % id).is_false()
		assert_float(sp.card.get_global_rect().position.y).is_greater_equal(
			_game.picker.get_global_rect().end.y)
		assert_bool(SidePanel.panel_rect(_game.sim.state.map).encloses(sp.card.get_global_rect())) \
			.override_failure_message("%s card %s" % [id, sp.card.get_global_rect()]).is_true()


## Exactly LIST_MAX_ROWS rows do not scroll: no scrollbar, no spacer in the pinned heads.
func test_fourteen_towers_still_fit_without_a_scrollbar() -> void:
	await _start_game(_total_config(TowerPicker.LIST_MAX_ROWS))
	await _open_picker()
	await get_tree().process_frame
	await get_tree().process_frame
	var rows := _game.picker.rows_scroll
	assert_float(rows.custom_minimum_size.y).is_equal(float(
		TowerPicker.LIST_MAX_ROWS * TowerPicker.ROW_H + TowerPicker.GROUP_H))
	assert_bool(rows.get_v_scroll_bar().visible).is_false()
	var pinned := _game.picker.get_node("Group_mundane")
	assert_int(pinned.get_child_count()).is_equal(1 + TowerPicker.HEADS.size())


## LT-61 §5: the 15th row scrolls the list at LIST_MAX_ROWS rows; the first group line with
## its heads stays pinned and the heads are narrowed by the real scrollbar's width, so each
## head still sits over its column; the names narrow by it too.
func test_fifteen_towers_scroll_the_list_and_pin_heads_aligned_to_the_scrollbar() -> void:
	await _start_game(_total_config(TowerPicker.LIST_MAX_ROWS + 1))
	_game.sim.state.gold = 10000
	await _open_picker()
	await get_tree().process_frame
	await get_tree().process_frame
	var picker := _game.picker
	var rows := picker.rows_scroll
	assert_float(rows.custom_minimum_size.y).is_equal(float(
		TowerPicker.LIST_MAX_ROWS * TowerPicker.ROW_H + TowerPicker.GROUP_H))
	var bar := rows.get_v_scroll_bar()
	assert_bool(bar.visible).is_true()
	assert_float(bar.max_value).is_greater(bar.page)
	assert_bool(rows.get_h_scroll_bar().visible).is_false()
	assert_int(picker.scrollbar_w()).is_greater(0)
	assert_float(bar.size.x).override_failure_message("scrollbar %s" % bar.size) \
		.is_equal(float(picker.scrollbar_w()))
	# The first group line is pinned (outside the scrolled Body), the second scrolls with it.
	var pinned: Control = picker.get_node("Group_mundane")
	assert_object(pinned.get_parent()).is_same(picker)
	assert_object(picker.find_child("Group_occult", true, false).get_parent()) \
		.is_same(rows.get_child(0))
	rows.scroll_vertical = int(bar.max_value)
	await get_tree().process_frame
	assert_bool(pinned.is_visible_in_tree()).is_true()
	assert_float(pinned.get_global_rect().position.y).is_less(rows.get_global_rect().position.y)
	rows.scroll_vertical = 0
	await get_tree().process_frame
	# Alignment: each head's right edge is its column's right edge in a row.
	var id: String = picker.buttons.keys()[0]
	var tol := 0.51
	var heads: Dictionary = {}
	for h: Label in pinned.get_children().filter(func(c: Node) -> bool: return c is Label):
		heads[h.name] = h
	assert_float(heads["Head_DPS"].get_global_rect().end.x).is_equal_approx(
		picker.cells[id]["dps"].get_global_rect().end.x, tol)
	assert_float(heads["Head_Trait"].get_global_rect().end.x).is_equal_approx(
		picker.cells[id]["trait"].get_global_rect().end.x, tol)
	assert_float(heads["Head_$"].get_global_rect().end.x).is_equal_approx(
		picker.costs[id].get_global_rect().end.x + TowerPicker.COST_GAP, tol)
	# The scrollbar takes the right edge: rows end where the bar starts.
	assert_float(picker.cells[id]["trait"].get_global_rect().end.x).is_equal_approx(
		bar.get_global_rect().position.x, tol)
	# Names fit what is left of NAME_W, or sit at the minimum font (ellipsis).
	var avail := TowerPicker.NAME_W - picker.scrollbar_w()
	var narrowed := 0
	for tid: String in picker.names:
		var l: Label = picker.names[tid]
		var fs := _font_of(l)
		if fs > TowerPicker.NAME_FONT_MIN:
			assert_float(_name_w(l, fs)).override_failure_message("%s '%s' %d px" % [tid, l.text, fs]) \
				.is_less_equal(float(avail))
		if _name_w(l, TowerPicker.FONT_SIZE) > avail and _name_w(l, TowerPicker.FONT_SIZE) <= TowerPicker.NAME_W:
			narrowed += 1
			assert_int(fs).is_less(TowerPicker.FONT_SIZE)
	assert_int(narrowed).override_failure_message("no name between %d and %d px" % [avail,
		TowerPicker.NAME_W]).is_greater(0)


## The column heads (LT-61 §3) sit on the first group line only, each with its tooltip.
func test_heads_are_on_the_first_group_line_only_with_tooltips() -> void:
	await _start_game(_data_config())
	await _open_picker()
	var pinned: Control = _game.picker.get_node("Group_mundane")
	for head: Array in TowerPicker.HEADS:
		var h := pinned.get_node("Head_" + head[0]) as Label
		assert_str(h.text).is_equal(head[0])
		assert_str(h.tooltip_text).is_equal(head[1])
		assert_str(h.tooltip_text).is_not_empty()
	var occult := _game.picker.find_child("Group_occult", true, false)
	assert_int(occult.get_child_count()).is_equal(1)
