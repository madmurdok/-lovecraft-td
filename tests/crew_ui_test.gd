class_name CrewUiTest
extends GdUnitTestSuite
## LT-32 §4 (grey-box UI): the HUD crew button, the crew view (hire by day, counts), the
## picker's crewed price and its night post rows, deploying from a row, the post's hover card
## and its tower view (no upgrade, no sale, closes at dawn), the picker's refresh when a
## lifted tower lands on its cell (44e7b65), and nothing of it with crew off. res://data ships
## crew.json (crew on); the golden data has none (crew off).

const R := SimCommand.CommandResult
const RIFLE := "rifleman"
const HARP := "harpooner"

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


func _free_cells(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if m.is_buildable(c) and not _game.sim.state.tower_at.has(c) and out.size() < n:
				out.append(c)
	return out


func _hire(kind: String, n: int) -> void:
	_game.sim.state.gold = 100000
	for i in n:
		assert_int(_game.commands.hire(kind)).is_equal(R.OK)


func _night() -> void:
	assert_int(_game.commands.call_wave()).is_equal(R.OK)
	_game.advance(0.0)
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.WAVE)


func _post_crew() -> int:
	return _game.sim.config.crew.post.crew


# --- HUD crew button ------------------------------------------------------------------------------

## Crew on: "Crew: <reserve total>" with one tooltip line per kind, following hires.
func test_hud_crew_button_shows_the_reserve_total_and_per_kind_lines() -> void:
	await _start()
	var b := _game.hud.crew_button
	assert_object(b).is_not_null()
	assert_str(b.text).is_equal("Crew: 0")
	_hire(RIFLE, 2)
	_hire(HARP, 1)
	assert_str(b.text).is_equal("Crew: 3")
	var lines := b.tooltip_text.split("\n")
	assert_int(lines.size()).is_equal(_game.sim.config.crew.crews.size())
	assert_str(lines[0]).is_equal(CrewPanel.count_text(_game.sim, _game.snapshot, RIFLE))
	assert_str(lines[0]).contains("2 in reserve")
	assert_str(lines[1]).contains("1 in reserve")
	b.pressed.emit()
	assert_bool(_game.crew_panel.visible).is_true()


## Crew off (golden data, no crew.json): no crew button, no post section, no post note.
func test_crew_off_builds_no_crew_ui() -> void:
	await _start(GoldenRuns.golden_config())
	assert_bool(_game.sim.config.crew_on()).is_false()
	assert_object(_game.hud.crew_button).is_null()
	assert_object(_game.hud.find_child("CrewButton", true, false)).is_null()
	assert_object(_game.picker.post_box).is_null()
	assert_object(_game.tower_panel.post_label).is_null()


# --- crew view ------------------------------------------------------------------------------------

## By day a Hire button adds one man (counts and HUD follow); at night every Hire button is
## disabled with "hire by day". On duty counts a tower's crew and posts of the kind.
func test_crew_view_hires_by_day_only_and_counts_men_on_duty() -> void:
	await _start()
	_game.sim.state.gold = 100000
	_game.open_crew_panel()
	var p := _game.crew_panel
	assert_bool(p.visible).is_true()
	assert_bool(p.hire_buttons[RIFLE].disabled).is_false()
	p.hire_buttons[RIFLE].pressed.emit()
	assert_int(_game.sim.crew_reserve()[RIFLE]).is_equal(1)
	assert_str(p.counts[RIFLE].text).is_equal(CrewPanel.count_text(_game.sim, _game.snapshot, RIFLE))
	assert_str(p.counts[RIFLE].text).contains("1 in reserve, 0 on duty")
	var cells := _free_cells(2)
	assert_int(_game.commands.build(RIFLE, cells[0])).is_equal(R.OK)
	_hire(HARP, _post_crew())
	_night()
	_game.open_crew_panel()  # LT-66 §2: dusk closes every view
	for kind: String in p.hire_buttons:
		assert_bool(p.hire_buttons[kind].disabled).override_failure_message(kind).is_true()
		assert_str(p.hire_buttons[kind].text).contains("hire by day")
	assert_int(_game.commands.deploy(HARP, cells[1])).is_equal(R.OK)
	var need := _game.sim.crew_need(RIFLE)
	assert_int(CrewPanel.on_duty(_game.snapshot, RIFLE)).is_equal(need)
	assert_int(CrewPanel.on_duty(_game.snapshot, HARP)).is_equal(_post_crew())
	assert_str(p.counts[HARP].text).contains("0 in reserve, %d on duty" % _post_crew())


# --- picker ---------------------------------------------------------------------------------------

## By day the cost cell is build_price: def.cost with an empty reserve, the frame with a full
## one, and the tooltip names the men it takes; no post section by day.
func test_picker_cost_is_the_build_price_and_names_reserve_men() -> void:
	await _start()
	_game.sim.state.gold = 100000
	var cell := _free_cells(1)[0]
	_game._on_cell_clicked(cell)
	var pk := _game.picker
	var cost: int = _game.sim.config.towers[RIFLE].cost
	assert_str(pk.costs[RIFLE].text).is_equal(TowerText.cost_text(cost))
	assert_str(pk.buttons[RIFLE].tooltip_text).not_contains("from the reserve")
	assert_bool(pk.post_box.visible).is_false()
	var need := _game.sim.crew_need(RIFLE)
	_hire(RIFLE, need)
	var price := _game.sim.build_price(RIFLE)
	assert_int(price).is_less(cost)
	assert_str(pk.costs[RIFLE].text).is_equal(TowerText.cost_text(price))
	# LT-118: the tooltip's price split names the men the reserve gives.
	assert_str(pk.buttons[RIFLE].tooltip_text).contains("%s: %d from the reserve" % [
		_game.sim.config.crew.crews[RIFLE].name, need])


## At night the post rows show, one per crew kind, enabled when can_deploy accepts; the title
## invites a deploy while one is possible. A row click deploys on the picker's cell and closes
## the picker; hovering a row shows the post's card (no Upgrades head).
func test_night_picker_lists_post_rows_and_a_click_deploys() -> void:
	await _start()
	_hire(HARP, _post_crew())
	var cell := _free_cells(1)[0]
	_night()
	_game._on_cell_clicked(cell)
	var pk := _game.picker
	assert_bool(pk.visible).is_true()
	assert_bool(pk.post_box.visible).is_true()
	assert_array(pk.post_buttons.keys()).is_equal(_game.sim.config.crew.crews.keys())
	assert_bool(pk.post_buttons[HARP].disabled).is_false()
	assert_bool(pk.post_buttons[RIFLE].disabled).is_true()  # RESERVE_SHORT
	assert_str(pk.post_buttons[HARP].text).is_equal("Post: %d %s (%d in reserve)" % [
		_post_crew(), _game.sim.config.crew.crews[HARP].name, _post_crew()])
	assert_str(pk.title_label.text).is_equal(TowerPicker.POST_TITLE_TEXT)
	for id: String in pk.buttons:
		assert_bool(pk.buttons[id].disabled).is_true()
	# Hover card.
	pk._set_hovered(TowerPicker.POST_PREFIX + HARP)
	var sp := _game.side_panel
	assert_bool(sp.card.visible).is_true()
	assert_str(sp.card_role.text).is_equal(TowerPicker.post_crew_text(_game.sim, HARP))
	assert_bool(sp.card_upgrades.visible).is_false()
	assert_str(sp.card_path.text).contains("Not a tower")
	# Click.
	pk.post_buttons[HARP].pressed.emit()
	assert_bool(pk.visible).is_false()
	var t := _game.sim.tower_by_id(_game.sim.state.tower_at.get(cell, -1))
	assert_object(t).is_not_null()
	assert_bool(t.post).is_true()
	assert_str(t.crew_kind).is_equal(HARP)


## With an empty reserve at night every post row is disabled and the title keeps the towers'
## refusal (not the deploy invitation).
func test_night_picker_without_reserve_keeps_the_towers_refusal() -> void:
	await _start()
	_night()
	_game._on_cell_clicked(_free_cells(1)[0])
	var pk := _game.picker
	assert_bool(pk.post_box.visible).is_true()
	for kind: String in pk.post_buttons:
		assert_bool(pk.post_buttons[kind].disabled).is_true()
	assert_str(pk.title_label.text).is_not_equal(TowerPicker.POST_TITLE_TEXT)
	assert_str(pk.title_label.text).is_not_equal(TowerPicker.TITLE_TEXT)


## 44e7b65: a lifted tower dropped on the open picker's cell refreshes the post rows (the
## deploy would be OCCUPIED now).
func test_picker_post_rows_refresh_when_a_lifted_tower_lands_on_the_cell() -> void:
	await _start()
	var cells := _free_cells(2)
	_game.sim.state.gold = 100000
	assert_int(_game.commands.build(RIFLE, cells[0])).is_equal(R.OK)
	_hire(HARP, _post_crew())
	_night()
	_game._on_cell_clicked(cells[1])
	var pk := _game.picker
	assert_bool(pk.post_buttons[HARP].disabled).is_false()
	var t := _game.sim.tower_by_id(_game.sim.state.tower_at[cells[0]])
	_game.sim._lift_tower(t, cells[1], 90, 0)
	_game.advance(0.0)
	assert_int(_game.sim.can_deploy(HARP, cells[1])).is_equal(R.OCCUPIED)
	assert_bool(pk.post_buttons[HARP].disabled).is_true()


# --- post view ------------------------------------------------------------------------------------

## A post's view: its name and crew line, no upgrade rows, no "Max level", no Sell, the
## "Not a tower" note; it closes when the post leaves at dawn.
func test_post_view_has_no_upgrade_or_sell_and_closes_at_dawn() -> void:
	await _start()
	_hire(RIFLE, _post_crew())
	var cell := _free_cells(1)[0]
	_night()
	assert_int(_game.commands.deploy(RIFLE, cell)).is_equal(R.OK)
	_game._on_cell_clicked(cell)
	var tp := _game.tower_panel
	assert_bool(tp.visible).is_true()
	assert_str(tp.title_label.text).is_equal(_game.sim.config.crew.post.def.name)
	assert_str(tp.role_label.text).is_equal(TowerPicker.post_crew_text(_game.sim, RIFLE))
	assert_bool(tp.sell_button.visible).is_false()
	assert_bool(tp.max_label.visible).is_false()
	assert_bool(tp.upgrade_title.visible).is_false()
	for branch: String in tp.upgrade_buttons:
		assert_bool(tp.upgrade_buttons[branch].visible).override_failure_message(branch).is_false()
	assert_bool(tp.post_label.visible).is_true()
	assert_int(_game.sim.debug_end_night()).is_equal(R.OK)
	for i in 200:
		_game.advance(1.0 / 20.0)
		if _game.sim.state.phase != SimState.Phase.WAVE:
			break
	assert_int(_game.sim.state.phase).is_not_equal(SimState.Phase.WAVE)
	assert_bool(_game.sim.state.tower_at.has(cell)).is_false()
	assert_bool(tp.visible).is_false()
