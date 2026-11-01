class_name StatsPanelTest
extends GdUnitTestSuite
## LT-53 (LT-43 §1, §2, §4, §5, Q3, Q4): the StatsTable and the side panel of a placed tower.
## The table itself (equal rows span every column, an upgrade cell that differs from Now is
## gold, lit Now cells pale yellow with "*", upgrade columns compared against the unlit Now);
## the panel's heads per level (Now | L2, Now | A | B, Now), the same §1 rows in the same
## order as the picker for every tower and branch, the lit status line and kind line, "*"
## only on the special lines the beam changes, the flare circle lighting a tower like the
## beam, and no value cut at 1280x720. Values are computed from game.sim.config.

const STAR := "*"
const RIFLE := "rifleman"

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


func _buildable_cell() -> Vector2i:
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			if m.is_buildable(Vector2i(x, y)) and not _game.sim.state.tower_at.has(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Builds `def_id` (gold enough), raises it through `path`, opens its panel. By day.
func _tower(def_id: String, path: Array = [], cell := Vector2i(-1, -1)) -> SimTower:
	_game.sim.state.gold = 100000
	if cell == Vector2i(-1, -1):
		cell = _buildable_cell()
	assert_int(_game.build(def_id, cell)).is_equal(Simulation.CommandResult.OK)
	var t := _game.sim.tower_by_id(_game.sim.state.tower_at[cell])
	for b: String in path:
		assert_int(_game.upgrade(t.id, b)).is_equal(Simulation.CommandResult.OK)
	_game.tower_panel.open_for(t.id)
	return t


func _table() -> StatsTable:
	return _game.tower_panel.stats_table


func _special_lines() -> PackedStringArray:
	return _game.tower_panel.special_label.text.split("\n")


func _rows(with_special := true) -> Array:
	var out := []
	for row: Array in TowerInfo.ROWS:
		if with_special or row[0] != "special":
			out.append(row[0])
	return out


func _color(l: Label) -> Color:
	return l.get_theme_color("font_color")


func _values(t: SimTower, s: TowerDef.Level) -> Dictionary:
	return TowerInfo.row_values(t.def, s, _config, _game.sim.state.sanity)


## LT-43 §2 for the table on screen: heads, every cell's text, one spanning cell for a row
## equal in every column, gold for an upgrade cell that differs from (unlit) Now.
func _assert_compare(tag: String, heads: Array, cols: Array, lit := {}) -> void:
	var st := _table()
	var got_heads := []
	for h: Label in st.heads:
		got_heads.append(h.text)
	assert_array(got_heads).override_failure_message(tag).is_equal(heads)
	for key: String in _rows(false):
		var shown := []
		for i in cols.size():
			shown.append(lit.get(key, cols[0][key]) if i == 0 else cols[i][key])
		var equal := shown.all(func(v: String) -> bool: return v == shown[0])
		var labels: Array = st.cells[key]
		var m := "%s %s %s" % [tag, key, shown]
		if cols.size() > 1 and equal:
			assert_bool(st.is_spanned(key)).override_failure_message(m + " not spanned").is_true()
			assert_int(labels.size()).override_failure_message(m).is_equal(1)
			assert_str(labels[0].text).override_failure_message(m).is_equal(shown[0])
			assert_that(_color(labels[0])).override_failure_message(m + " spanned gold") \
				.is_not_equal(StatsTable.COLOR_CHANGED)
			continue
		assert_bool(st.is_spanned(key)).override_failure_message(m + " spanned").is_false()
		assert_int(labels.size()).override_failure_message(m).is_equal(cols.size())
		for i in cols.size():
			assert_str(labels[i].text).override_failure_message("%s col %d" % [m, i]) \
				.is_equal(shown[i])
			if i == 0:
				var want := StatsTable.COLOR_LIT if lit.has(key) \
					else StatsTable.color_for(key, shown[0])
				assert_that(_color(labels[0])).override_failure_message(m + " Now colour") \
					.is_equal(want)
			elif shown[i] != cols[0][key]:
				assert_that(_color(labels[i])).override_failure_message("%s col %d not gold"
					% [m, i]).is_equal(StatsTable.COLOR_CHANGED)
			else:
				assert_that(_color(labels[i])).override_failure_message("%s col %d gold"
					% [m, i]).is_equal(StatsTable.color_for(key, shown[i]))


# --- StatsTable on its own ------------------------------------------------------------------

func _dict(base: Dictionary) -> Dictionary:
	var d := {}
	for key: String in _rows():
		d[key] = base.get(key, "x")
	return d


func test_table_spans_equal_rows_golds_changed_cells_and_marks_lit_now() -> void:
	var st := StatsTable.new()
	_vp.add_child(st)
	var now := _dict({"damage": "10", "every": "0.7", "hits": "All", "reserve": "—"})
	var a := _dict({"damage": "14", "every": "0.7", "hits": "All", "reserve": "—"})
	var b := _dict({"damage": "10", "every": "0.5", "hits": "All", "reserve": "—"})
	var cols: Array[Dictionary] = [now, a, b]
	st.set_columns(PackedStringArray(["Now", "A", "B"]), cols)
	assert_bool(st.is_spanned("hits")).is_true()
	assert_bool(st.is_spanned("reserve")).is_true()
	assert_that(_color(st.cells["reserve"][0])).is_equal(StatsTable.COLOR_DASH)
	assert_bool(st.is_spanned("damage")).is_false()
	assert_that(_color(st.cells["damage"][1])).is_equal(StatsTable.COLOR_CHANGED)
	assert_that(_color(st.cells["damage"][2])).is_equal(StatsTable.COLOR_VALUE)
	assert_that(_color(st.cells["every"][1])).is_equal(StatsTable.COLOR_VALUE)
	assert_that(_color(st.cells["every"][2])).is_equal(StatsTable.COLOR_CHANGED)
	# Lit Now: pale yellow with its mark; an upgrade column still compares with the base Now
	# (A's 0.7 equals it: not gold), and a row lit only in Now no longer spans.
	st.set_columns(PackedStringArray(["Now", "A", "B"]), cols,
		{"every": "0.56*", "hits": "All*"})
	assert_str(st.text_at("every", 0)).is_equal("0.56*")
	assert_that(_color(st.cells["every"][0])).is_equal(StatsTable.COLOR_LIT)
	assert_that(_color(st.cells["every"][1])).is_equal(StatsTable.COLOR_VALUE)
	assert_that(_color(st.cells["every"][2])).is_equal(StatsTable.COLOR_CHANGED)
	assert_bool(st.is_spanned("hits")).is_false()
	assert_that(_color(st.cells["hits"][1])).is_equal(StatsTable.COLOR_VALUE)
	# One column: nothing spans and nothing is gold.
	var one: Array[Dictionary] = [now]
	st.set_columns(PackedStringArray(["L1"]), one)
	for key: String in _rows(false):
		assert_bool(st.is_spanned(key)).is_false()
		assert_that(_color(st.cells[key][0])).is_not_equal(StatsTable.COLOR_CHANGED)
	st.queue_free()


## LT-61 §1: the build card is one column with no head; the table drops its head row only
## when every head is "" (a tower's panel keeps it), and the rows stay.
func test_head_row_is_hidden_only_when_every_head_is_empty() -> void:
	var st := StatsTable.new()
	_vp.add_child(st)
	var one: Array[Dictionary] = [_dict({})]
	st.set_columns(PackedStringArray([""]), one)
	var head_row: Control = st.get_node("Head")
	assert_bool(head_row.visible).is_false()
	assert_bool(st.get_node("Row_" + st.row_keys[0]).visible).is_true()
	st.set_columns(PackedStringArray(["L1"]), one)
	assert_bool(st.get_node("Head").visible).is_true()
	st.set_columns(PackedStringArray([""]), one)
	assert_bool(st.get_node("Head").visible).is_false()
	var two: Array[Dictionary] = [_dict({}), _dict({})]
	st.set_columns(PackedStringArray(["", "B"]), two)
	assert_bool(st.get_node("Head").visible).is_true()
	st.queue_free()


# --- the panel: same rows as the picker, heads per level ------------------------------------

## §1 "every tower shows the same 10 rows": the panel table (Special under it as lines)
## lists the ROWS in order, for every tower at L1, L2 and each branch. LT-61 §2: a build
## list row is Name, Cost, DPS and Trait for every tower.
func test_picker_and_panel_show_the_same_rows_in_the_same_order() -> void:
	await _start_game()
	var labels := []
	for row: Array in TowerInfo.ROWS:
		labels.append(row[1])
	_game.picker.open_for(_buildable_cell())
	for id: String in _config.towers:
		var names := []
		for c in _game.picker.buttons[id].find_child("Cells", true, false).get_children():
			names.append(String(c.name))
		assert_array(names).override_failure_message(id).is_equal(["Name", "Cost", "Gap", "Dps", "Trait"])
	_game.picker.close()
	# Panel: every tower, L1, L2 and both branches.
	var panel_names := ["Head"]
	for k: String in _rows(false):
		panel_names.append("Row_" + k)
	for id: String in _config.towers:
		for path: Array in [[], [""], ["", "a"], ["", "b"]]:
			var t := await _tower(id, path)
			var tag := "%s %s" % [id, path]
			var names := []
			var row_labels := []
			for row in _table().get_children():
				names.append(String(row.name))
				row_labels.append(row.get_child(0).text)
			assert_array(names).override_failure_message(tag).is_equal(panel_names)
			assert_array(row_labels).override_failure_message(tag).is_equal([""]
				+ labels.slice(0, labels.size() - 1))
			_game.close_panels()
			assert_int(_game.sell(t.id)).is_equal(Simulation.CommandResult.OK)


## §2: Now | L2 at L1, Now | A | B at L2, Now at L3, for every tower: each cell is its level's
## row_values (the live sanity), equal rows span, changed upgrade cells are gold.
func test_every_tower_compares_now_with_its_upgrades() -> void:
	await _start_game()
	for id: String in _config.towers:
		var def: TowerDef = _config.towers[id]
		var t := await _tower(id)
		_assert_compare(id + " L1", ["Now", "L2"],
			[_values(t, def.levels[0]), _values(t, def.levels[1])])
		assert_int(_game.upgrade(t.id, "")).is_equal(Simulation.CommandResult.OK)
		_game.tower_panel.refresh()
		_assert_compare(id + " L2", ["Now", "A", "B"], [_values(t, def.levels[1]),
			_values(t, def.branches["a"]), _values(t, def.branches["b"])])
		assert_int(_game.upgrade(t.id, "b")).is_equal(Simulation.CommandResult.OK)
		_game.tower_panel.refresh()
		_assert_compare(id + " B", ["Now"], [_values(t, def.branches["b"])])
		_game.close_panels()
		assert_int(_game.sell(t.id)).is_equal(Simulation.CommandResult.OK)


## Review finding 4: the reserve, dead-zone range and Resonator deltas the old delta lines
## said are now gold cells of the upgrade column.
func test_reserve_dead_zone_and_resonator_deltas_are_gold_cells() -> void:
	await _start_game()
	var sign: TowerDef = _config.towers["elder_sign"]
	assert_float(sign.levels[1].sanity_reserve).is_not_equal(sign.levels[0].sanity_reserve)
	await _tower("elder_sign")
	assert_str(_table().text_at("reserve", 0)).is_equal(TowerInfo.num(sign.levels[0].sanity_reserve))
	assert_str(_table().text_at("reserve", 1)).is_equal(TowerInfo.num(sign.levels[1].sanity_reserve))
	assert_that(_color(_table().cells["reserve"][1])).is_equal(StatsTable.COLOR_CHANGED)
	assert_that(_color(_table().cells["reserve"][0])).is_equal(StatsTable.COLOR_RESERVE)
	_game.close_panels()

	var coast: TowerDef = _config.towers["coast_battery"]
	var c1 := coast.levels[0]
	var c2 := coast.levels[1]
	await _tower("coast_battery")
	assert_str(_table().text_at("range", 0)).is_equal("%s–%s" % [TowerInfo.num(c1.min_range),
		TowerInfo.num(c1.range_cells)])
	assert_str(_table().text_at("range", 1)).is_equal("%s–%s" % [TowerInfo.num(c2.min_range),
		TowerInfo.num(c2.range_cells)])
	assert_that(_color(_table().cells["range"][1])).is_equal(StatsTable.COLOR_CHANGED)
	_game.close_panels()

	var res: TowerDef = _config.towers["resonator"]
	var r1 := res.levels[0]
	var r2 := res.levels[1]
	assert_float(r2.damage).is_not_equal(r1.damage)
	assert_int(_game.sim.debug_set_sanity(37.0)).is_equal(Simulation.CommandResult.OK)
	var sanity := _game.sim.state.sanity
	var top := _config.sanity.max_sanity
	await _tower("resonator")
	for pair: Array in [[0, r1], [1, r2]]:
		var s: TowerDef.Level = pair[1]
		var dps := s.damage / s.fire_interval * (1.0 + float(s.effects["sanity_scaling"])
			* (1.0 - sanity / top))
		assert_str(_table().text_at("dps", pair[0])).is_equal(TowerInfo.num(roundf(dps * 10.0)
			/ 10.0))
		assert_str(_table().text_at("damage", pair[0])).is_equal(TowerInfo.num(s.damage))
	assert_that(_color(_table().cells["damage"][1])).is_equal(StatsTable.COLOR_CHANGED)
	assert_that(_color(_table().cells["dps"][1])).is_equal(StatsTable.COLOR_CHANGED)
	# Q3: the panel says the DPS is live, first under the table.
	assert_str(_special_lines()[0]).is_equal("DPS at sanity %s; grows as it falls"
		% TowerInfo.num(floorf(sanity)))


## §2: special lines "Now: …" then "L2: …"/"A: …"/"B: …" (special_delta_lines); no prefix at L3.
func test_special_lines_are_prefixed_by_column_only_with_upgrade_columns() -> void:
	await _start_game()
	var dyn: TowerDef = _config.towers["dynamite_crew"]
	var t := await _tower("dynamite_crew", [""])
	var want := []
	for line in TowerInfo.special_lines(dyn.levels[1]):
		want.append("Now: " + line)
	for b: String in ["a", "b"]:
		for line in TowerInfo.special_delta_lines(dyn.levels[1], dyn.branches[b]):
			want.append("%s: %s" % [b.to_upper(), line])
	assert_array(Array(_special_lines())).is_equal(want)
	assert_int(_game.upgrade(t.id, "a")).is_equal(Simulation.CommandResult.OK)
	_game.tower_panel.refresh()
	assert_array(Array(_special_lines())).is_equal(Array(TowerInfo.special_lines(dyn.branches["a"])))


# --- §5 lit ----------------------------------------------------------------------------------

## Q4: a lit Rifleman L2: Every x fire_interval_mult and DPS / it with "*" in Now, the A/B
## columns unlit and compared with the base Now, the status line and "No misses while lit".
func test_lit_mundane_tower_shows_live_values_the_line_and_no_misses() -> void:
	await _start_game()
	var def: TowerDef = _config.towers[RIFLE]
	var s := def.levels[1]
	var m := _config.economy.beam.mundane_fire_interval_mult
	var t := await _tower(RIFLE, [""])
	assert_bool(_game.tower_panel.lit_label.visible).is_false()
	assert_str(_game.tower_panel.kind_label.text).not_contains(TowerInfo.NO_MISSES_LIT)
	for key: String in _rows(false):
		for l: Label in _table().cells[key]:
			assert_str(l.text).override_failure_message(key).not_contains(STAR)
	t.lit = true
	_game.tower_panel.refresh()
	var lit := {"every": TowerInfo.num(s.fire_interval * m) + STAR,
		"dps": TowerInfo.num(roundf(s.damage / s.fire_interval / m * 10.0) / 10.0) + STAR}
	_assert_compare("lit rifleman L2", ["Now", "A", "B"], [_values(t, s),
		_values(t, def.branches["a"]), _values(t, def.branches["b"])], lit)
	assert_bool(_game.tower_panel.lit_label.visible).is_true()
	assert_str(_game.tower_panel.lit_label.text).is_equal("* In the beam now: fire +%s%%, no misses"
		% TowerInfo.num(roundf((1.0 / m - 1.0) * 100.0)))
	assert_str(_game.tower_panel.kind_label.text).is_equal(TowerInfo.NO_MISSES_LIT)
	t.lit = false
	_game.tower_panel.refresh()
	assert_bool(_game.tower_panel.lit_label.visible).is_false()
	assert_str(_table().text_at("every", 0)).is_equal(TowerInfo.num(s.fire_interval))


## Q4: occult Damage / DPS x power_mult, the circle's unit DPS and DPS too (LT-53/S8); the
## status line "−30% power".
func test_lit_occult_shooter_and_circle_show_power_mult_values() -> void:
	await _start_game()
	var pm := _config.economy.beam.occult_power_mult
	var power := "* In the beam now: −%s%% power" % TowerInfo.num(roundf((1.0 - pm) * 100.0))
	var necro: TowerDef = _config.towers["necronomicon_reader"]
	var n1 := necro.levels[0]
	var t := await _tower("necronomicon_reader")
	t.lit = true
	_game.tower_panel.refresh()
	_assert_compare("lit necro", ["Now", "L2"], [_values(t, n1), _values(t, necro.levels[1])],
		{"damage": TowerInfo.num(n1.damage * pm) + STAR,
		"dps": TowerInfo.num(roundf(n1.damage / n1.fire_interval * pm * 10.0) / 10.0) + STAR})
	assert_str(_game.tower_panel.lit_label.text).is_equal(power)
	_game.close_panels()

	var circle: TowerDef = _config.towers["summoning_circle"]
	var c2 := circle.levels[1]
	var unit: float = c2.effects["summon_dps"] * pm
	var c := await _tower("summoning_circle", [""])
	c.lit = true
	_game.tower_panel.refresh()
	_assert_compare("lit circle L2", ["Now", "A", "B"], [_values(c, c2),
		_values(c, circle.branches["a"]), _values(c, circle.branches["b"])],
		{"damage": TowerInfo.num(roundf(unit * 10.0) / 10.0) + STAR,
		"dps": TowerInfo.num(roundf(unit * c2.summon_max() * 10.0) / 10.0) + STAR})
	assert_str(_game.tower_panel.lit_label.text).is_equal(power)


## LT-53/S8: on a lit occult aura / gate / circle "*" marks only the special lines the beam
## changes; the upgrade lines ("A: …") never.
func test_lit_mark_only_on_the_special_lines_the_beam_changes() -> void:
	await _start_game()
	var pm := _config.economy.beam.occult_power_mult
	var key: TowerDef = _config.towers["silver_key"]
	var k1 := key.levels[0]
	var t := await _tower("silver_key")
	t.lit = true
	_game.tower_panel.refresh()
	var lines := Array(_special_lines())
	assert_array(lines).contains(["Now: Banish %s cells back*"
		% TowerInfo.num(float(k1.effects["banish_cells"]) * pm)])
	assert_array(lines).contains(["Now: Max %s HP; immune %s s" % [
		TowerInfo.num(k1.effects["banish_max_hp"]), TowerInfo.num(k1.effects["banish_immune_seconds"])]])
	_assert_marks_only_changed(lines)
	_game.close_panels()

	var sign: TowerDef = _config.towers["elder_sign"]
	var s1 := sign.levels[0]
	var e := await _tower("elder_sign")
	e.lit = true
	_game.tower_panel.refresh()
	lines = Array(_special_lines())
	assert_array(lines).contains([
		"Now: Slows enemies %s%%*" % TowerInfo.num(float(s1.effects["slow"]) * pm * 100.0),
		"Now: Foes take +%s%% damage*" % TowerInfo.num((float(s1.effects["damage_taken_multiplier"])
			- 1.0) * pm * 100.0)])
	_assert_marks_only_changed(lines)
	_game.close_panels()

	var circle: TowerDef = _config.towers["summoning_circle"]
	var c2 := circle.levels[1]
	var c := await _tower("summoning_circle", [""])
	c.lit = true
	_game.tower_panel.refresh()
	lines = Array(_special_lines())
	var starred := lines.filter(func(l: String) -> bool: return l.ends_with(STAR))
	assert_array(starred).is_equal(["Now: Unit %s HP, %s DPS*" % [TowerInfo.num(c2.effects["summon_hp"]),
		TowerInfo.num(float(c2.effects["summon_dps"]) * pm)]])
	_assert_marks_only_changed(lines)


## Every "Now:" line with "*" differs from the unlit lines; none without differs; no upgrade
## line is marked.
func _assert_marks_only_changed(lines: Array) -> void:
	var t := _game.sim.tower_by_id(_game.tower_panel.tower_id)
	var base := Array(TowerInfo.special_lines(t.stats()))
	var marked := 0
	for l: String in lines:
		if not l.begins_with("Now: "):
			assert_str(l).override_failure_message(l).not_contains(STAR)
			continue
		var body := l.trim_prefix("Now: ")
		if body.ends_with(STAR):
			marked += 1
			assert_bool(base.has(body.trim_suffix(STAR))).override_failure_message(l).is_false()
		else:
			assert_bool(base.has(body)).override_failure_message(l).is_true()
	assert_int(marked).is_greater(0)


## LT-57: the flare circle lights a tower like the beam (SimTower.lit), so the panel shows
## the lit values; without the flare it does not.
func test_the_flare_circle_lights_a_tower_and_the_panel_marks_it() -> void:
	_config.economy.beam.reach_cells = 0.0001  # the beam lights nothing; only the flare can
	await _start_game()
	var lh := _config.map.lighthouse
	var cell := Vector2i(-1, -1)
	var r: float = _config.economy.flare.radius_cells[0]
	for y in _game.sim.state.map.height:
		for x in _game.sim.state.map.width:
			var c := Vector2i(x, y)
			var d := Vector2(c) + Vector2(0.5, 0.5) - (Vector2(lh) + Vector2(0.5, 0.5))
			if cell.x < 0 and _game.sim.state.map.is_buildable(c) and d.length() < r - 1.0:
				cell = c
	assert_int(cell.x).is_greater_equal(0)
	var t := await _tower(RIFLE, [], cell)
	assert_int(_game.call_wave()).is_equal(Simulation.CommandResult.OK)
	_game.sim.step()
	assert_bool(t.lit).is_false()
	_game.tower_panel.refresh()
	assert_str(_table().text_at("every", 0)).not_contains(STAR)
	_game.sim.state.flare_cooldown_ticks = 0
	_game.sim.state.oil = _config.economy.flare.cost_oil
	assert_int(_game.sim.fire_flare()).is_equal(Simulation.CommandResult.OK)
	_game.sim.step()
	assert_bool(t.lit).is_true()
	_game.tower_panel.refresh()
	var s := t.stats()
	assert_str(_table().text_at("every", 0)).is_equal(TowerInfo.num(s.fire_interval
		* _config.economy.beam.mundane_fire_interval_mult) + STAR)
	assert_bool(_game.tower_panel.lit_label.visible).is_true()


# --- §4: nothing cut at 1280x720 ------------------------------------------------------------

## LT-53/S8 probe as a test: at 1280x720 (base 1152x648 stretched, as canvas_items does) no
## label of the panel table is narrower than its text, and the table stays inside the side
## panel, for every tower at L1, L2 and branch B, lit and unlit (the Resonator also at low
## sanity, where its DPS is widest).
func test_no_table_value_is_cut_at_1280x720() -> void:
	_vp.size = Vector2i(1280, 720)
	_vp.size_2d_override = Vector2i(1152, 648)
	_vp.size_2d_override_stretch = true
	await _start_game()
	var cuts := []
	for id: String in _config.towers:
		for path: Array in [[], [""], ["", "b"]]:
			for lit: bool in [false, true]:
				for sanity: float in ([80.0, 5.0] if id == "resonator" else [80.0]):
					_game.sim.debug_set_sanity(sanity)
					var t := await _tower(id, path)
					t.lit = lit
					_game.tower_panel.refresh()
					await get_tree().process_frame
					await get_tree().process_frame
					var tag := "%s %s lit=%s s=%d" % [id, path, lit, sanity]
					for row in _table().get_children():
						for l: Label in row.get_children():
							var f := l.get_theme_font("font")
							var w := f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
								l.get_theme_font_size("font_size")).x
							if w > l.size.x + 0.01:
								cuts.append("%s '%s' %.1f > %.1f" % [tag, l.text, w, l.size.x])
					var right := _table().get_global_rect().end.x
					if right > _game.side_panel.get_global_rect().end.x + 0.5:
						cuts.append("%s table right %.1f" % [tag, right])
					_game.close_panels()
					assert_int(_game.sell(t.id)).is_equal(Simulation.CommandResult.OK)
	assert_array(cuts).is_empty()
