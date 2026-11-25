class_name CrewSourceUiTest
extends GdUnitTestSuite
## LT-118: where a crewed tower's men come from, in the UI. By day a crewed picker row marks
## its crew source ("res N" / "hire N" / "res A·hire B") and follows the reserve; no mark at
## night, for uncrewed towers or with crew off. The row tooltip's last line splits the price
## into the frame and the crew (also with an empty reserve). The crew panel states the
## reserve-first rule. res://data ships crew.json (crew on); the golden data has none.

const R := SimCommand.CommandResult
const HARP := "harpooner"
const RIFLE := "rifleman"
const UNCREWED := ["searchlight", "elder_sign"]
const RULE := "A crewed tower takes men from the reserve first; any it lacks are hired at build."

var _vp: SubViewport
var _game: Game


func before_test() -> void:
	_vp = GameFixture.make_viewport(self)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _start(cfg: GameConfig = null) -> void:
	if cfg == null:
		var r := ConfigLoader.load_dir("res://data")
		assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
		cfg = r.config
	_game = GameFixture.make_game(_vp, cfg, 7, PackedStringArray())
	await get_tree().process_frame
	_game.advance(0.0)


func _free_cell() -> Vector2i:
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if m.is_buildable(c) and not _game.sim.state.tower_at.has(c):
				return c
	return Vector2i(-1, -1)


func _open_picker() -> TowerPicker:
	_game.sim.state.gold = 100000
	_game._on_cell_clicked(_free_cell())
	var pk := _game.picker
	assert_bool(pk.visible).is_true()
	return pk


func _hire(kind: String, n: int) -> void:
	_game.sim.state.gold = 100000
	for i in n:
		assert_int(_game.commands.hire(kind)).is_equal(R.OK)


func _last_line(s: String) -> String:
	var lines := s.split("\n")
	return lines[lines.size() - 1]


func _crew(id: String) -> CrewConfig.CrewKind:
	return _game.sim.config.crew.crews[id]


# --- pure text ------------------------------------------------------------------------------------

func test_crew_mark_text_names_reserve_and_hired_men() -> void:
	assert_str(TowerPicker.crew_mark_text(2, 0)).is_equal("res 2")
	assert_str(TowerPicker.crew_mark_text(0, 2)).is_equal("hire 2")
	assert_str(TowerPicker.crew_mark_text(1, 1)).is_equal("res 1·hire 1")
	assert_str(TowerPicker.crew_mark_text(0, 0)).is_equal("")


## frame_price = def.cost less the crew's hire (per_tower × hire); def.cost when uncrewed.
## Harpooner on res://data: 70 - 2 × 25 = 20 (the spec's "Frame $20").
func test_frame_price_is_cost_less_the_crew_or_cost_when_uncrewed() -> void:
	await _start()
	var sim := _game.sim
	for id: String in sim.config.crew.crews:
		var k := _crew(id)
		assert_int(sim.frame_price(id)).override_failure_message(id).is_equal(
			sim.config.towers[id].cost - k.per_tower * k.hire)
	assert_int(sim.frame_price(HARP)).is_equal(20)
	for id: String in UNCREWED:
		assert_int(sim.frame_price(id)).override_failure_message(id).is_equal(
			sim.config.towers[id].cost)


func test_frame_price_is_cost_with_crew_off() -> void:
	await _start(GoldenRuns.golden_config())
	assert_bool(_game.sim.config.crew_on()).is_false()
	assert_int(_game.sim.frame_price(HARP)).is_equal(_game.sim.config.towers[HARP].cost)


# --- picker marks ---------------------------------------------------------------------------------

## Only crewed defs get a mark, a child of their name label; uncrewed rows have none.
func test_only_crewed_rows_have_a_mark() -> void:
	await _start()
	var pk := _open_picker()
	var crewed: Array = []
	for id: String in pk.buttons:
		if _game.sim.crew_need(id) > 0:
			crewed.append(id)
	assert_array(crewed).is_not_empty()
	assert_array(pk.crew_marks.keys()).contains_exactly_in_any_order(crewed)
	for id: String in crewed:
		assert_object(pk.crew_marks[id].get_parent()).override_failure_message(id) \
			.is_same(pk.names[id])
	for id: String in UNCREWED:
		assert_bool(pk.crew_marks.has(id)).override_failure_message(id).is_false()
		assert_object(pk.names[id].find_child("CrewMark", true, false)) \
			.override_failure_message(id).is_null()


## Empty reserve -> "hire N"; one hired -> mixed; full -> "res N"; each step follows the
## CREW_CHANGED of a hire while the picker stays open; visible by day.
func test_mark_follows_the_reserve() -> void:
	await _start()
	var pk := _open_picker()
	var need := _game.sim.crew_need(HARP)
	assert_int(need).is_equal(2)
	var mark := pk.crew_marks[HARP]
	assert_bool(mark.visible).is_true()
	assert_str(mark.text).is_equal("hire 2")
	_hire(HARP, 1)
	assert_str(mark.text).is_equal("res 1·hire 1")
	_hire(HARP, 1)
	assert_str(mark.text).is_equal("res 2")
	# Another kind's reserve leaves this row alone; its own row follows.
	assert_str(pk.crew_marks[RIFLE].text).is_equal("hire %d" % _game.sim.crew_need(RIFLE))
	_hire(RIFLE, _game.sim.crew_need(RIFLE))
	assert_str(pk.crew_marks[RIFLE].text).is_equal("res %d" % _game.sim.crew_need(RIFLE))
	assert_str(mark.text).is_equal("res 2")


func test_no_mark_at_night() -> void:
	await _start()
	_hire(HARP, 1)
	assert_int(_game.commands.call_wave()).is_equal(R.OK)
	_game.advance(0.0)
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.WAVE)
	var pk := _open_picker()
	for id: String in pk.crew_marks:
		assert_bool(pk.crew_marks[id].visible).override_failure_message(id).is_false()


func test_crew_off_has_no_marks_and_no_price_split() -> void:
	await _start(GoldenRuns.golden_config())
	var pk := _open_picker()
	assert_bool(pk.crew_marks.is_empty()).is_true()
	for id: String in pk.names:
		assert_object(pk.names[id].find_child("CrewMark", true, false)) \
			.override_failure_message(id).is_null()
		assert_str(TowerPicker.crew_price_text(_game.sim, id)).override_failure_message(id) \
			.is_equal("")
		assert_str(pk.buttons[id].tooltip_text).override_failure_message(id) \
			.not_contains("Frame ")


## A crewed name leaves room on its right for the widest (mixed) mark at CREW_FONT_SIZE plus
## CREW_GAP, so the mark never covers it; uncrewed names get no such margin.
func test_crewed_names_leave_room_for_the_widest_mark() -> void:
	await _start()
	var pk := _open_picker()
	for id: String in pk.crew_marks:
		var need := _game.sim.crew_need(id)
		var widest := TowerPicker.crew_mark_text(need - 1, 1)
		var w := pk.crew_marks[id].get_theme_font("font").get_string_size(widest,
			HORIZONTAL_ALIGNMENT_LEFT, -1, TowerPicker.CREW_FONT_SIZE).x
		var l := pk.names[id]
		assert_bool(l.has_theme_stylebox_override("normal")).override_failure_message(id) \
			.is_true()
		assert_float(l.get_theme_stylebox("normal").content_margin_right) \
			.override_failure_message(id).is_greater_equal(w + TowerPicker.CREW_GAP)
	for id: String in UNCREWED:
		assert_bool(pk.names[id].has_theme_stylebox_override("normal")) \
			.override_failure_message(id).is_false()


## LT-124: a crew mark's right edge sits CREW_END_GAP (5 px) left of its name label's right
## edge, which is the $ cell's left edge, so "hire 3" never touches "$120".
func test_the_crew_mark_ends_5_px_left_of_the_name_and_cost_edge() -> void:
	await _start()
	var pk := _open_picker()
	await get_tree().process_frame
	assert_int(pk.crew_marks.size()).is_greater(0)
	for id: String in pk.crew_marks:
		var m := pk.crew_marks[id].get_global_rect()
		var n := pk.names[id].get_global_rect()
		assert_float(n.end.x - m.end.x).override_failure_message(id).is_equal_approx(5.0, 0.01)
		assert_float(n.end.x - m.end.x).override_failure_message(id) \
			.is_equal_approx(float(TowerPicker.CREW_END_GAP), 0.01)
		assert_float(pk.costs[id].get_global_rect().position.x - m.end.x) \
			.override_failure_message(id).is_equal_approx(5.0, 0.51)


## LT-124: _fit_names reserves the widest mark's width (whole px) + CREW_GAP + CREW_END_GAP on a
## crewed name's right, so the name's text box ends CREW_GAP left of where the widest mark's
## text starts (the mark is right-aligned in its box, which ends CREW_END_GAP short).
func test_crewed_names_reserve_the_widest_mark_plus_both_gaps() -> void:
	await _start()
	var pk := _open_picker()
	await get_tree().process_frame
	assert_int(pk.crew_marks.size()).is_greater(0)
	for id: String in pk.crew_marks:
		var need := _game.sim.crew_need(id)
		var widest := TowerPicker.crew_mark_text(maxi(need - 1, 0), mini(need, 1))
		var w := ceili(pk.crew_marks[id].get_theme_font("font").get_string_size(widest,
			HORIZONTAL_ALIGNMENT_LEFT, -1, TowerPicker.CREW_FONT_SIZE).x)
		var l := pk.names[id]
		var margin := l.get_theme_stylebox("normal").content_margin_right
		assert_float(margin).override_failure_message(id).is_equal(
			float(w + TowerPicker.CREW_GAP + TowerPicker.CREW_END_GAP))
		var text_end := l.get_global_rect().end.x - margin
		var mark_start := pk.crew_marks[id].get_global_rect().end.x - w
		assert_float(mark_start - text_end).override_failure_message(id) \
			.is_equal_approx(float(TowerPicker.CREW_GAP), 0.01)


# --- tooltip --------------------------------------------------------------------------------------

## The price split is the tooltip's last line with an empty, a partial and a full reserve.
func test_tooltip_last_line_splits_the_price() -> void:
	await _start()
	var pk := _open_picker()
	var k := _crew(HARP)
	var frame := TowerText.money(_game.sim.frame_price(HARP))
	var hire := TowerText.money(k.hire)
	var b := pk.buttons[HARP]
	assert_str(_last_line(b.tooltip_text)).is_equal("Frame %s + %s: hire 2 × %s" % [
		frame, k.name, hire])
	assert_str(_last_line(b.tooltip_text)).is_equal("Frame $20 + Harpooners: hire 2 × $25")
	_hire(HARP, 1)
	assert_str(_last_line(b.tooltip_text)).is_equal(
		"Frame %s + %s: 1 from the reserve, hire 1 × %s" % [frame, k.name, hire])
	_hire(HARP, 1)
	assert_str(_last_line(b.tooltip_text)).is_equal(
		"Frame %s + %s: 2 from the reserve" % [frame, k.name])
	assert_str(_last_line(b.tooltip_text)).is_equal(TowerPicker.crew_price_text(_game.sim, HARP))
	# Line 1 still names the tower and its build price.
	assert_str(b.tooltip_text.split("\n")[0]).starts_with(_game.sim.config.towers[HARP].name)


func test_uncrewed_tooltip_has_no_price_split() -> void:
	await _start()
	var pk := _open_picker()
	for id: String in UNCREWED:
		assert_str(TowerPicker.crew_price_text(_game.sim, id)).override_failure_message(id) \
			.is_equal("")
		assert_str(pk.buttons[id].tooltip_text).override_failure_message(id) \
			.not_contains("Frame ")
		assert_str(pk.buttons[id].tooltip_text).override_failure_message(id) \
			.not_contains("from the reserve")


# --- crew panel -----------------------------------------------------------------------------------

func test_crew_panel_states_the_reserve_first_rule() -> void:
	await _start()
	_game.open_crew_panel()
	var p := _game.crew_panel
	assert_bool(p.visible).is_true()
	assert_str(p.note_label.text.split("\n")[0]).is_equal(RULE)
