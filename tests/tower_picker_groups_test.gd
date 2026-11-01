class_name TowerPickerGroupsTest
extends ConfigTestBase
## LT-55 (LT-46 P15): the build picker shows two labelled groups, "Mundane" then "Occult", by
## TowerDef.kind, data order inside each; with 10 towers every entry fits the side panel at
## 1152x648 without scrolling. Owner decision "Роль + подсказка": under each button only the
## role line is drawn, the full L1 info is the button's tooltip. The 10-tower config is built
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


## The picker's children by name, in order.
func _child_names() -> Array:
	var out := []
	for c in _game.picker.get_children():
		out.append(String(c.name))
	return out


func _expected_children(mundane: Array, occult: Array) -> Array:
	var out := ["Title", "Group_mundane"]
	for id: String in mundane:
		out.append_array(["Tower_" + id, "Info_" + id])
	out.append("Group_occult")
	for id: String in occult:
		out.append_array(["Tower_" + id, "Info_" + id])
	out.append("CancelButton")
	return out


## Role line (when set) + the L1 info lines, as before LT-55.
func _full_info(id: String) -> String:
	var def: TowerDef = _config.towers[id]
	var text := PackedStringArray()
	if not def.role.is_empty():
		text.append(def.role)
	text.append_array(TowerInfo.lines(def, def.levels[0], _config.sanity))
	return "\n".join(text)


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
	assert_int(_game.picker.infos.size()).is_equal(10)
	for id: String in _config.towers:
		assert_str(String(_game.picker.buttons[id].name)).is_equal("Tower_" + id)
		assert_str(String(_game.picker.infos[id].name)).is_equal("Info_" + id)


func test_group_headers_read_mundane_and_occult() -> void:
	await _start_game(_ten_config())
	await _open_picker()
	for pair: Array in [["Group_mundane", "Mundane"], ["Group_occult", "Occult"]]:
		var h := _game.picker.get_node(pair[0]) as Label
		assert_object(h).is_not_null()
		assert_str(h.text).is_equal(pair[1])
		assert_bool(h.is_visible_in_tree()).is_true()


# --- tooltip and the single role line -------------------------------------------------------

func test_tooltip_carries_the_full_l1_info_and_the_label_keeps_it() -> void:
	await _start_game(_ten_config())
	for id: String in _config.towers:
		var full := _full_info(id)
		assert_str(_game.picker.buttons[id].tooltip_text).is_equal(full)
		assert_str(_game.picker.infos[id].text).is_equal(full)
		assert_str(full.split("\n")[0]).is_equal(_config.towers[id].role)
	# Damage and range for a shooter, the reserve for an occult tower.
	var rifle := _game.picker.buttons[RIFLE].tooltip_text
	assert_str(rifle).contains("Range %s cells" % TowerInfo.num(_config.towers[RIFLE].levels[0].range_cells))
	assert_int(rifle.split("\n").size()).is_greater(2)
	var sign: TowerDef = _config.towers[SIGN]
	assert_str(_game.picker.buttons[SIGN].tooltip_text).contains(
		"Reserves %s sanity" % TowerInfo.num(sign.levels[0].sanity_reserve))


func test_only_the_role_line_is_drawn_under_each_button() -> void:
	await _start_game(_ten_config())
	await _open_picker()
	await get_tree().process_frame
	for id: String in _config.towers:
		var info: Label = _game.picker.infos[id]
		assert_int(info.text.split("\n").size()).is_greater(1)
		assert_int(info.get_visible_line_count()) \
			.override_failure_message("%s draws %d lines" % [id, info.get_visible_line_count()]) \
			.is_equal(1)
		# Its box is one line tall: shorter than two lines of its font.
		assert_float(info.size.y).is_less(2.0 * info.get_line_height())


# --- fit: 10 towers, 1152x648, no scrolling -------------------------------------------------

func _assert_fits(state: String) -> void:
	var scroll := _game.side_panel.scroll
	var views := scroll.get_child(0) as Control
	var r := SidePanel.panel_rect(_game.sim.state.map)
	assert_int(scroll.scroll_vertical).is_equal(0)
	assert_float(views.get_combined_minimum_size().y).override_failure_message(
		"%s: content %.1f px > scroll %.1f px" % [state, views.get_combined_minimum_size().y,
			scroll.size.y]).is_less_equal(scroll.size.y)
	assert_bool(scroll.get_v_scroll_bar().visible) \
		.override_failure_message("%s: vertical scroll bar shown" % state).is_false()
	assert_that(_game.side_panel.get_global_rect()).is_equal(r)
	var shown: Array[Control] = [_game.picker.get_node("CancelButton") as Control]
	for id: String in _config.towers:
		shown.append_array([_game.picker.buttons[id], _game.picker.infos[id]])
	for c: Control in shown:
		assert_bool(scroll.get_global_rect().encloses(c.get_global_rect())).override_failure_message(
			"%s: %s at %s outside %s" % [state, c.name, c.get_global_rect(), scroll.get_global_rect()]) \
			.is_true()


func test_ten_affordable_towers_fit_the_panel_without_scrolling_at_1152x648() -> void:
	await _start_game(_ten_config())
	assert_that(_vp.size).is_equal(Vector2i(1152, 648))
	_game.sim.state.gold = 10000
	await _open_picker()
	await get_tree().process_frame
	for id: String in _config.towers:
		assert_bool(_game.picker.buttons[id].disabled).is_false()
	_assert_fits("affordable")


## Disabled buttons carry a reason, the longest text a button gets (and the usual state early
## in a run, when most towers are unaffordable).
func test_ten_unaffordable_towers_fit_the_panel_without_scrolling_at_1152x648() -> void:
	await _start_game(_ten_config())
	_game.sim.state.gold = 0
	await _open_picker()
	await get_tree().process_frame
	for id: String in _config.towers:
		assert_bool(_game.picker.buttons[id].disabled).is_true()
	_assert_fits("not enough money")


# --- states and pressing, both groups -------------------------------------------------------

func _button_text(id: String) -> String:
	var def: TowerDef = _config.towers[id]
	return "%s — %s" % [def.name, TowerInfo.cost_text(def.cost)]


func test_refresh_states_hold_for_all_ten_buttons() -> void:
	await _start_game(_ten_config())
	_game.sim.state.gold = 10000
	await _open_picker()
	for id: String in _config.towers:
		var b: Button = _game.picker.buttons[id]
		assert_bool(b.disabled).is_false()
		assert_str(b.text).is_equal(_button_text(id))
		assert_str(_game.picker.infos[id].text).is_equal(_full_info(id))
		assert_that(_game.picker.infos[id].get_theme_color("font_color")).is_equal(SidePanel.COLOR_INFO)
	_game.sim.state.gold = 0
	_game.picker.refresh()
	for id: String in _config.towers:
		var b: Button = _game.picker.buttons[id]
		var info: Label = _game.picker.infos[id]
		assert_bool(b.disabled).is_true()
		assert_str(b.text).is_equal(_button_text(id))
		assert_str(info.text).is_equal("(not enough money)\n" + _full_info(id))
		assert_that(info.get_theme_color("font_color")).is_equal(TowerPicker.STATUS_COLOR)
	# Affordable again: the status line goes away and the role line is back.
	_game.sim.state.gold = 10000
	_game.picker.refresh()
	for id: String in _config.towers:
		assert_str(_game.picker.infos[id].text).is_equal(_full_info(id))
		assert_that(_game.picker.infos[id].get_theme_color("font_color")).is_equal(SidePanel.COLOR_INFO)


## F1: the tooltip the player sees is the one refresh() sets: button text, the status line
## (when any), then the full role + L1 info.
func test_tooltip_after_refresh_carries_the_status_line_and_the_full_info() -> void:
	await _start_game(_ten_config())
	_game.sim.state.gold = 10000
	await _open_picker()
	for id: String in _config.towers:
		assert_str(_game.picker.buttons[id].tooltip_text) \
			.is_equal(_button_text(id) + "\n" + _full_info(id))
	_game.sim.state.gold = 0
	_game.picker.refresh()
	for id: String in _config.towers:
		var tip: String = _game.picker.buttons[id].tooltip_text
		assert_str(tip).is_equal(_button_text(id) + "\n(not enough money)\n" + _full_info(id))
		assert_int(tip.split("\n").size()).is_greater(3)


## The button text is only "Name — $cost" in every state: the reason never enters it.
func test_button_text_never_contains_the_reason() -> void:
	await _start_game(_ten_config())
	await _open_picker()
	for gold in [0, 10000]:
		_game.sim.state.gold = gold
		_game.picker.refresh()
		for id: String in _config.towers:
			var t: String = _game.picker.buttons[id].text
			assert_str(t).is_equal(_button_text(id))
			assert_str(t).not_contains("(")
			for r: String in TowerInfo.REASONS.values():
				assert_str(t).not_contains(r)


## Verify of LT-55: "Necronomicon Reader — $15…" for $150. Every shipped tower's button text
## fits its button's content width at ENTRY_FONT_SIZE, so no ellipsis cuts the price.
func test_every_shipped_towers_price_is_visible_in_full() -> void:
	await _start_game(_data_config())
	_game.sim.state.gold = 0
	await _open_picker()
	await get_tree().process_frame
	for id: String in _config.towers:
		var b: Button = _game.picker.buttons[id]
		assert_bool(b.disabled).is_true()
		var font := b.get_theme_font("font")
		var text_w := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			TowerPicker.ENTRY_FONT_SIZE).x
		var content_w := b.size.x - b.get_theme_stylebox("disabled").get_minimum_size().x
		assert_float(text_w).override_failure_message("%s: \"%s\" is %.1f px, button content %.1f px"
			% [id, b.text, text_w, content_w]).is_less_equal(content_w)
		assert_str(b.text).ends_with(TowerInfo.cost_text(_config.towers[id].cost))


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
