class_name OverlayPanelTest
extends GdUnitTestSuite
## LT-66 §2, §4, §9 (1-5, 8, 15, 16) and review fix R3: the side panel as an overlay. By day
## it shows (idle text when no view is open), at dusk every view closes and it hides, by night
## it shows only while a view is open; a night click within Board.PICK_RADIUS of a drawn enemy
## opens its monster card (nearest wins, ties to the lower id) and a click farther away opens
## the tower or cell under it; the card and the overlay close with the enemy; opening a view
## under the overlay pans it into sight; the build list has the Rng column; the HUD's
## right-anchored labels end left of the overlay; relic tokens follow the pan; the card closes
## on a leak and a dissolve too; a click on the overlay over a buildable cell never reaches the
## board (LT-124, §9.5, §9.9). Already pinned elsewhere: the rect (side_panel_test, §9.9),
## SanityFx's rect at a pan (sanity_fx_screen_test, §9.16), G6c/G7 (architecture_guard_test).
## Clicks are real mouse events in a 1200x675 SubViewport.

const RIFLE := "rifleman"

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


func _start() -> void:
	_game = GameFixture.make_game(_vp, _config, 7)
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


func _escape() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = pressed
		_vp.push_input(ev)
	await get_tree().process_frame


func _screen(cells: Vector2) -> Vector2:
	return _game.board.view.cell_to_screen(cells)


## A buildable cell left of the overlay that no tower stands on, row `y`, from the right.
func _free_cell(y := 3) -> Vector2i:
	var m := _game.sim.state.map
	for x in range(m.width - 1, -1, -1):
		var c := Vector2i(x, y)
		if m.is_buildable(c) and not _game.sim.state.tower_at.has(c) \
				and _game.board.view.cells_to_px(x + 1.0) < SidePanel.panel_rect().position.x:
			return c
	return Vector2i(-1, -1)


func _build_tower(y := 3) -> SimTower:
	_game.sim.state.gold = 10000
	var cell := _free_cell(y)
	assert_int(_game.commands.build(RIFLE, cell)).is_equal(SimCommand.CommandResult.OK)
	return _game.sim.tower_by_id(_game.sim.state.tower_at[cell])


func _night() -> void:
	assert_int(_game.commands.call_wave()).is_equal(SimCommand.CommandResult.OK)
	_game.sim.step()
	_game.advance(0.0)
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.WAVE)


func _enemy(at: Vector2, fake := false) -> int:
	var id := _game.sim.spawn_enemy("cultist", fake)
	GameFixture.sync(_game)
	_game.board.last_pos[id] = at
	return id


func _no_view() -> bool:
	return not _game.side_panel.any_view_open()


# --- 1, 2, 3: when the overlay shows -----------------------------------------------------------

func test_dawn_shows_the_overlay_with_the_idle_text_and_dusk_closes_every_view_and_hides_it() -> void:
	await _start()
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.BUILD)
	assert_bool(_game.side_panel.visible).is_true()
	assert_bool(_game.side_panel.idle_label.visible).is_true()
	assert_str(_game.side_panel.idle_label.text).is_equal(SidePanel.IDLE_TEXT)
	var t := _build_tower()
	_game.tower_panel.open_for(t.id)
	assert_bool(_game.tower_panel.visible).is_true()
	_night()
	assert_bool(_game.tower_panel.visible).is_false()
	assert_bool(_no_view()).is_true()
	assert_bool(_game.side_panel.visible).is_false()


func test_night_a_click_on_a_tower_opens_the_overlay_esc_hides_it_and_water_hides_it() -> void:
	await _start()
	var t := _build_tower()
	_night()
	assert_bool(_game.side_panel.visible).is_false()
	_game.board.last_pos.clear()
	await _click(_screen(_game.sim.state.map.grid.centre(t.cell)))
	assert_bool(_game.tower_panel.visible).is_true()
	assert_bool(_game.side_panel.visible).is_true()
	await _escape()
	assert_bool(_game.tower_panel.visible).is_false()
	assert_bool(_game.side_panel.visible).is_false()
	await _click(_screen(_game.sim.state.map.grid.centre(t.cell)))
	assert_bool(_game.side_panel.visible).is_true()
	var water := Vector2i(0, 0)
	assert_bool(_game.sim.state.map.is_buildable(water)).is_false()
	await _click(_screen(_game.sim.state.map.grid.centre(water)))
	assert_bool(_no_view()).is_true()
	assert_bool(_game.side_panel.visible).is_false()


func test_day_esc_and_a_water_click_close_the_view_and_the_overlay_stays_with_the_idle_text() -> void:
	await _start()
	var t := _build_tower()
	for how: String in ["esc", "water"]:
		_game.tower_panel.open_for(t.id)
		assert_bool(_game.tower_panel.visible).is_true()
		if how == "esc":
			await _escape()
		else:
			await _click(_screen(_game.sim.state.map.grid.centre(Vector2i(0, 0))))
		assert_bool(_game.tower_panel.visible).override_failure_message(how).is_false()
		assert_bool(_game.side_panel.visible).override_failure_message(how).is_true()
		assert_bool(_game.side_panel.idle_label.visible).override_failure_message(how).is_true()
		assert_str(_game.side_panel.idle_label.text).is_equal(SidePanel.IDLE_TEXT)


## R3: night is `phase == WAVE` everywhere; the idle phases (NONE, DONE) count as day.
func test_the_overlay_shows_in_every_phase_but_the_wave_and_never_after_the_outcome() -> void:
	await _start()
	var s := _game.snapshot
	for phase: SimState.Phase in [SimState.Phase.NONE, SimState.Phase.BUILD,
			SimState.Phase.DONE]:
		s.phase = phase
		_game.side_panel.sync_visible()
		assert_bool(_game.side_panel.visible).override_failure_message("phase %d" % phase) \
			.is_true()
	s.phase = SimState.Phase.WAVE
	_game.side_panel.sync_visible()
	assert_bool(_game.side_panel.visible).is_false()
	s.phase = SimState.Phase.NONE
	s.outcome = SimState.Outcome.LOST
	_game.side_panel.sync_visible()
	assert_bool(_game.side_panel.visible).is_false()


func test_night_a_click_on_a_buildable_cell_with_the_crew_off_acts_as_an_empty_click() -> void:
	_config.crew.enabled = false
	await _start()
	assert_bool(_game.sim.config.crew_on()).is_false()
	var cell := _free_cell()
	_night()
	_game.board.last_pos.clear()
	await _click(_screen(_game.sim.state.map.grid.centre(cell)))
	assert_bool(_game.picker.visible).is_false()
	assert_bool(_no_view()).is_true()
	assert_bool(_game.side_panel.visible).is_false()


func test_night_a_click_on_a_buildable_cell_with_the_crew_on_still_opens_the_post_list() -> void:
	await _start()
	assert_bool(_game.sim.config.crew_on()).is_true()
	var cell := _free_cell()
	_night()
	_game.board.last_pos.clear()
	await _click(_screen(_game.sim.state.map.grid.centre(cell)))
	assert_bool(_game.picker.visible).is_true()
	assert_bool(_game.side_panel.visible).is_true()


# --- 4: night click, monster or tower ---------------------------------------------------------

func test_a_click_within_the_pick_radius_opens_the_monster_card_beating_the_tower_under_it() -> void:
	await _start()
	var t := _build_tower()
	_night()
	var centre := _game.sim.state.map.grid.centre(t.cell)
	var at := centre + Vector2(0, -0.4)
	var id := _enemy(at)
	var near := at + Vector2(0, Board.PICK_RADIUS * 0.6)  # same tile as the tower
	assert_vector(Vector2(_game.board.view.cell_at_screen(_screen(near)))).is_equal(Vector2(t.cell))
	await _click(_screen(near))
	assert_bool(_game.monster_card.visible).is_true()
	assert_int(_game.monster_card.enemy_id).is_equal(id)
	assert_bool(_game.tower_panel.visible).is_false()
	assert_bool(_game.side_panel.visible).is_true()
	assert_int(_game.selection.enemy_id).is_equal(id)


func test_a_click_just_outside_the_pick_radius_on_the_same_tile_opens_the_tower_instead() -> void:
	await _start()
	var t := _build_tower()
	_night()
	var at := _game.sim.state.map.grid.centre(t.cell) + Vector2(0, -0.4)
	var id := _enemy(at)
	var far := at + Vector2(0, Board.PICK_RADIUS + 0.1)  # 0.6 cells: still on the tile
	assert_vector(Vector2(_game.board.view.cell_at_screen(_screen(far)))).is_equal(Vector2(t.cell))
	await _click(_screen(far))
	assert_bool(_game.tower_panel.visible).is_true()
	assert_bool(_game.monster_card.visible).is_false()
	assert_int(_game.monster_card.enemy_id).is_equal(0)
	assert_bool(_game.snapshot.enemy(id) != null).is_true()


func test_the_nearest_of_two_enemies_wins_and_a_tie_goes_to_the_lower_id() -> void:
	await _start()
	_night()
	var at := Vector2(10.5, 3.5)
	var first := _enemy(at)
	var second := _enemy(at + Vector2(0.4, 0))
	assert_int(second).is_greater(first)
	var click := at + Vector2(0.3, 0)  # 0.3 from the first, 0.1 from the second
	assert_int(_game.board.enemy_at_screen(_screen(click))).is_equal(second)
	assert_int(_game.board.enemy_at_screen(_screen(at - Vector2(0.3, 0)))).is_equal(first)
	_game.board.last_pos[second] = at  # same place: equal distance
	assert_int(_game.board.enemy_at_screen(_screen(at + Vector2(0.2, 0)))).is_equal(first)
	await _click(_screen(click + Vector2(-0.3, 0.0)))
	assert_int(_game.monster_card.enemy_id).is_equal(first)
	# a drawn id that left the snapshot is skipped (a frame since the click redrew last_pos)
	_game.board.last_pos[first] = at
	_game.board.last_pos[second] = at
	_game.board.last_pos[999999] = at
	assert_int(_game.board.enemy_at_screen(_screen(at))).is_equal(first)


# --- 5: the card closes with its enemy -------------------------------------------------------

func test_a_kill_closes_the_card_and_hides_the_night_overlay() -> void:
	await _start()
	_night()
	var id := _enemy(Vector2(10.5, 3.5))
	await _click(_screen(Vector2(10.5, 3.5)))
	assert_int(_game.monster_card.enemy_id).is_equal(id)
	assert_bool(_game.side_panel.visible).is_true()
	_game.sim.apply_damage(id, 1.0e9, "test", true)
	_game.advance(0.0)  # consumes the DIED event
	assert_bool(_game.monster_card.visible).is_false()
	assert_bool(_game.side_panel.visible).is_false()
	assert_int(_game.selection.enemy_id).is_equal(0)


## Puts enemy `id` at the end of its route and runs one sim tick, so it leaks (a real one) or
## dissolves at the lighthouse (a fake, SpawnSystem.leak). The frame then consumes the events
## without a step, so only the event closes the card: on_stepped (which also closes it once the
## enemy leaves the snapshot) does not run. Returns the enemy.
func _to_the_lighthouse(id: int) -> SimEnemy:
	_game.sim.state.lighthouse_hp = 1000  # one leak never ends the run
	var e := _game.sim.enemy_by_id(id)
	e.distance = e.route.length
	_game.sim.step()
	_game.advance(0.0)  # consumes the LEAKED / FAKE_DISSOLVED event
	assert_int(_game.sim.state.outcome).is_equal(SimState.Outcome.NONE)
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.WAVE)
	return e


func test_a_leak_closes_the_card_and_hides_the_night_overlay() -> void:
	await _start()
	_night()
	var id := _enemy(Vector2(10.5, 3.5))
	await _click(_screen(Vector2(10.5, 3.5)))
	assert_int(_game.monster_card.enemy_id).is_equal(id)
	assert_bool(_game.side_panel.visible).is_true()
	var e := _to_the_lighthouse(id)
	assert_bool(e.leaked).is_true()
	assert_bool(_game.monster_card.visible).is_false()
	assert_bool(_game.side_panel.visible).is_false()
	assert_int(_game.selection.enemy_id).is_equal(0)


func test_a_hallucination_dissolving_closes_the_card_and_hides_the_night_overlay() -> void:
	await _start()
	_night()
	var id := _enemy(Vector2(10.5, 3.5), true)
	await _click(_screen(Vector2(10.5, 3.5)))
	assert_int(_game.monster_card.enemy_id).is_equal(id)
	assert_bool(_game.side_panel.visible).is_true()
	var e := _to_the_lighthouse(id)
	assert_bool(e.dissolved).is_true()
	assert_bool(e.leaked).is_false()
	assert_bool(_game.monster_card.visible).is_false()
	assert_bool(_game.side_panel.visible).is_false()
	assert_int(_game.selection.enemy_id).is_equal(0)


# --- 9: a click on the overlay never reaches the board ----------------------------------------

## [cell, point]: a screen point inside the overlay's left margin strip (x in [left edge,
## left edge + MARGIN), where only the SidePanel itself is, no child) and clear of its top and
## bottom margins, over a buildable cell no tower stands on; [OFF_BOARD, -] when none.
func _cell_under_overlay() -> Array:
	var r := SidePanel.panel_rect()
	var m := _game.sim.state.map
	var v := _game.board.view
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if not m.is_buildable(c) or _game.sim.state.tower_at.has(c):
				continue
			var lo := maxf(v.cell_to_screen(Vector2(x, y)).x, r.position.x)
			var hi := minf(v.cell_to_screen(Vector2(x + 1, y)).x, r.position.x + SidePanel.MARGIN)
			var p := Vector2((lo + hi) / 2.0, _screen(m.grid.centre(c)).y)
			if hi - lo >= 2.0 and p.y > r.position.y + SidePanel.MARGIN \
					and p.y < r.end.y - SidePanel.MARGIN and v.cell_at_screen(p) == c:
				return [c, p]
	return [BoardView.OFF_BOARD, Vector2.ZERO]


## §9.9: a real left click inside the overlay over a buildable cell stays on the overlay: no
## build list, no selection, no tower. The map is panned to its far end first: at pan 0 no
## buildable cell lies under the overlay, at the far end one reaches ~4 px into its margin
## strip (the map ends left of mid-panel at every pan). Then the same point with the overlay
## hidden opens that cell's build list, so the point does reach the board without it.
func test_a_click_on_the_overlay_over_a_buildable_cell_never_reaches_the_board() -> void:
	await _start()
	assert_bool(_game.side_panel.visible).is_true()
	var cam := _game.board.camera
	cam.set_visible_rect(_game.side_panel.board_visible_rect())
	cam.pan_by(Vector2(1.0e6, 0))  # the far end: the map shifted right, under the overlay
	var towers := _game.sim.state.towers.size()
	var gold := _game.sim.state.gold
	var hit := _cell_under_overlay()
	assert_int((hit[0] as Vector2i).x).override_failure_message(
		"no buildable cell under the overlay's margin strip").is_greater(-1)
	assert_bool(SidePanel.panel_rect().has_point(hit[1])).is_true()
	await _click(hit[1])
	assert_bool(_game.picker.visible).is_false()
	assert_bool(_no_view()).is_true()
	assert_vector(Vector2(_game.selection.cell)).is_equal(Vector2(SelectionModel.NONE))
	assert_int(_game.selection.enemy_id).is_equal(0)
	assert_bool(_game.side_panel.idle_label.visible).is_true()
	assert_str(_game.side_panel.idle_label.text).is_equal(SidePanel.IDLE_TEXT)
	assert_int(_game.sim.state.towers.size()).is_equal(towers)
	assert_int(_game.sim.state.gold).is_equal(gold)
	_game.side_panel.visible = false
	await _click(hit[1])
	assert_bool(_game.picker.visible).is_true()
	assert_vector(Vector2(_game.picker.cell)).is_equal(Vector2(hit[0]))


# --- 15: auto-reveal ---------------------------------------------------------------------------

func test_a_monster_under_the_overlay_pans_into_sight_when_its_card_opens() -> void:
	await _start()
	_night()
	var v := BoardView.play_rect()
	v.end.x = SidePanel.panel_rect().position.x
	var at := Vector2(_game.board.view.px_to_cells(v.end.x) + 1.0, 3.5)  # a cell beyond the overlay's edge
	var id := _enemy(at)
	assert_float(_screen(at).x).is_greater(v.end.x)
	assert_bool(_game.side_panel.visible).is_false()  # night: the click reaches the board
	await _click(_screen(at))
	assert_int(_game.monster_card.enemy_id).is_equal(id)
	var r := _game.board.view.cells_to_px(BoardCamera.REVEAL_CELLS)
	assert_float(_game.board.view.pan.x).is_less(0.0)
	assert_float(_screen(at).x + r).is_equal_approx(v.end.x, 1e-3)
	assert_bool(_game.board.camera.easing()).is_false()


func test_a_cell_panned_under_the_overlay_pans_into_sight_when_clicked() -> void:
	await _start()
	var cam := _game.board.camera
	cam.set_visible_rect(_game.side_panel.board_visible_rect())
	cam.pan_by(Vector2(1.0e6, 0))  # the far end: the map shifted right
	var m := _game.sim.state.map
	var shifted := Vector2i(-1, -1)
	for x in range(m.width - 1, -1, -1):  # a buildable cell whose box crosses the overlay edge
		var c := Vector2i(x, 3)
		var hi := _game.board.view.cell_to_screen(m.grid.centre(c)).x \
			+ _game.board.view.cells_to_px(BoardCamera.REVEAL_CELLS)
		if m.is_buildable(c) and hi > cam.visible_rect.end.x and hi - 40.0 < cam.visible_rect.end.x:
			shifted = c
			break
	assert_int(shifted.x).is_greater(-1)
	var before := _game.board.view.pan.x
	await _click(_screen(m.grid.centre(shifted)))
	assert_vector(Vector2(_game.picker.cell)).is_equal(Vector2(shifted))
	assert_float(_game.board.view.pan.x).is_less(before)
	var hi_after := _game.board.view.cell_to_screen(m.grid.centre(shifted)).x \
		+ _game.board.view.cells_to_px(BoardCamera.REVEAL_CELLS)
	assert_float(hi_after).is_equal_approx(cam.visible_rect.end.x, 1e-3)


# --- 14 (wiring): the overlay's visibility drives the camera's rect -------------------------

func test_dusk_hides_the_overlay_and_starts_the_ease_that_a_tick_finishes() -> void:
	await _start()
	var t := _build_tower()
	var cam := _game.board.camera
	_game.side_panel.sync_visible()
	assert_that(cam.visible_rect).is_equal(_game.side_panel.board_visible_rect())
	assert_float(cam.visible_rect.end.x).is_equal(SidePanel.panel_rect().position.x)
	cam.pan_by(Vector2(-1.0e6, 0))
	assert_float(_game.board.view.pan.x).is_less(0.0)
	_night()
	assert_that(cam.visible_rect).is_equal(BoardView.play_rect())
	assert_bool(cam.easing()).is_true()
	cam.tick(BoardCamera.EASE_SECONDS, cam.visible_rect.get_center(), false)
	assert_float(_game.board.view.pan.x).is_equal(0.0)
	assert_bool(cam.easing()).is_false()
	assert_vector(_game.board.position).is_equal(_game.board.view.origin())
	# a view opening at night shows the overlay and narrows V again
	_game.tower_panel.open_for(t.id)
	assert_bool(_game.side_panel.visible).is_true()
	assert_float(cam.visible_rect.end.x).is_equal(SidePanel.panel_rect().position.x)


# --- 8: the build list's Rng column -------------------------------------------------------------

func test_the_build_list_heads_are_cost_dps_rng_trait_and_each_row_shows_its_l1_range() -> void:
	await _start()
	_game.picker.open_for(_free_cell())
	var heads := []
	for h: Node in _game.picker.find_children("Head_*", "Label", true, false):
		heads.append((h as Label).text)
	assert_array(heads.slice(0, 4)).is_equal(["$", "DPS", "Rng", "Trait"])
	for id: String in _config.towers:
		var rng := _game.picker.buttons[id].find_child("Rng", true, false) as Label
		assert_object(rng).override_failure_message(id).is_not_null()
		assert_str(rng.text).override_failure_message(id).is_equal(
			TowerText.range_text(_config.towers[id].levels[0]))
	assert_int(TowerPicker.NAME_W).is_equal(142)
	for sc: Node in _game.picker.find_children("*", "ScrollContainer", true, false):
		var s := sc as ScrollContainer
		assert_int(s.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
		assert_bool(s.get_h_scroll_bar().visible).is_false()


# --- 16: HUD labels end left of the overlay -------------------------------------------------

func test_the_flare_oil_and_hostile_labels_end_left_of_the_overlay() -> void:
	await _start()
	var left := SidePanel.panel_rect().position.x
	assert_float(Hud.overlay_left()).is_equal(left)
	await get_tree().process_frame
	var hud := _game.hud
	assert_bool(hud.oil_label.get_global_rect().end.x <= left).is_true()
	if hud.buy_oil_button != null:
		assert_bool(hud.buy_oil_button.get_global_rect().end.x <= left).is_true()
	_night()
	await get_tree().process_frame
	assert_bool(hud.flare_button.visible).is_true()
	assert_bool(hud.flare_button.get_global_rect().end.x <= left).is_true()
	assert_bool(hud.oil_label.get_global_rect().end.x <= left).is_true()
	hud.hostile_label.text = "Hostile: a long line that has to be pushed left of the overlay"
	hud.hostile_label.visible = true
	hud._place_hostile()
	var w := hud.hostile_label.get_combined_minimum_size().x
	assert_bool(hud.hostile_label.position.x + w <= left).is_true()


func test_the_sandbox_label_ends_left_of_the_overlay() -> void:
	_game = GameFixture.make_game(null, _config, 7)
	_game.sandbox = true
	_vp.add_child(_game)
	_game.set_process(false)
	await get_tree().process_frame
	var l := _game.hud.sandbox_label
	assert_object(l).is_not_null()
	assert_bool(l.position.x + l.size.x <= SidePanel.panel_rect().position.x).is_true()


# --- R2: a relic token follows the pan --------------------------------------------------------

func test_a_relic_token_follows_the_pan_during_its_hang() -> void:
	await _start()
	var tokens := _game.relic_tokens
	var at := Vector2(6.5, 3.5)
	var tick := _game.snapshot.tick
	tokens.on_event(SimEvent.new(SimEvent.Type.RELIC_DROPPED, tick, 77,
		{"kind": RelicTokens.STAR_STONE, "at": at, "arrive_tick": tick + 3 * SimTime.TICK_RATE}))
	var tok := tokens.tokens[77]
	var cam := _game.board.camera
	cam.set_visible_rect(_game.side_panel.board_visible_rect())
	assert_float(tokens.progress(tok)).is_less(0.05)  # inside the hang
	var p0: Vector2 = tokens.pose(tok)[0]
	assert_vector(p0).is_equal_approx(_screen(at), Vector2(7.0, 7.0))  # the pop lifts it < 6 px
	cam.pan_by(Vector2(-40, 0))
	var p1: Vector2 = tokens.pose(tok)[0]
	assert_float(p1.x - p0.x).is_equal_approx(_game.board.view.pan.x, 1e-3)
	assert_vector(p1).is_equal_approx(_screen(at), Vector2(7.0, 7.0))
