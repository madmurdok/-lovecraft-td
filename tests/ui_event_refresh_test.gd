class_name UiEventRefreshTest
extends GdUnitTestSuite
## LT-78 (docs/design/LT-78-event-driven-ui.md §8): the panels change only when a sim event,
## a running timer on a stepped frame, or a UI signal says so. B1 idle frames do no panel
## work; B2 a scripted whole game on golden data never shows a stale field; B3 countdowns
## tick without sim events and rewrite at most once per whole second; B4 a panel reopened
## mid-game is current; B5 selling a tower closes its panel; B6 the sanity bar animates only
## while distorted; B7 DebugArgs.parse. (B8 is G6 in architecture_guard_test.)

const RIFLE := "rifleman"
const HARPOON := "harpooner"
const ELDER := "elder_sign"
const WHOLE_SECOND_FRAMES := 60

## B2: node paths that never change through flush/on_stepped, with the reason. A path of a
## snapshotted panel that changes at least once in the scripted game is "covered"; every
## other path must match one of these (a new field nobody exercised fails the test until it
## is covered or listed). Entries are "<panel>:<regex over the path>"; the list is exact (the
## stats-table value cells are named one by one).
const STATIC_OK: PackedStringArray = [
	# Layout containers and gaps: no text, no state (LT-78 §3 rows 15, 27). The sanity bar is
	# drawn, not a field: its redraws are pinned by B1, B6 and the within-state redraw test.
	"hud:^\\.$",
	"hud:^Bar(/(GapLeft|GapRight|Purse|SanityBar|Status))?$",
	"hud:^(Background|Footer)$",
	"lighthouse:^(\\.|CancelButton)$",
	"picker:^(\\.|Rows|Rows/Body|Separator)$",
	"picker:^Rows/Body/Tower_\\w+/Cells(/Gap)?$",
	# Group titles, column heads and the cancel button: fixed text per view (§3 rows 29, 54).
	"picker:^(Rows/Body/)?Group_\\w+(/(Head_.*|Title))?$",
	"picker:^TitleLine(/CancelButton)?$",
	"tower:^(\\.|CancelButton|PriorityTitle)$",
	# The golden data gives no first upgrade (L1 -> L2) a role line, so this label is never
	# shown (§3 row 36).
	"tower:^UpgradeInfo_L2$",
	# The stats table: its container, rows and row names are per def; of the value cells only
	# the upgrade-preview columns this game never changed while their row was on screen.
	# LT-89: beam/shadow Label#3 too. The percents come from whole cooldown ticks, so a
	# row splits into columns only when a level's ticks round differently; of the towers this
	# game builds only the Rifleman does, and its L2 card always previews L3b (0.2 s: lit
	# 5 ticks +20%, shadowed 8 ticks -25%), so the cell exists but never changes. The
	# percent per level is pinned by stats_rows_test.
	"tower:^Stats(/Head(/Label#\\d)?)?$",
	"tower:^Stats/Row_\\w+(/Label#0)?$",
	"tower:^Stats/Row_(attack/Label#[23]|beam/Label#[13]|damage/Label#3|dps/Label#3"
		+ "|every/Label#3|hits/Label#1|kill/Label#1|range/Label#3|reserve/Label#3"
		+ "|shadow/Label#[13])$",
]

var _vp: SubViewport
var _game: Game
var _config: GameConfig

# B2 bookkeeping
var _prev := {}  ## panel key -> the snapshot after the previous check
var _seen := {}  ## "panel:path" -> true, every snapshotted path
var _changed := {}  ## "panel:path" -> true, changed between two checks without refresh()
var _stale: Array[String] = []
var _checks := 0
var _facts := {}
var _results: Array[String] = []


func before_test() -> void:
	_config = GoldenRuns.golden_config()
	_vp = GameFixture.make_viewport(self)
	_prev = {}
	_seen = {}
	_changed = {}
	_stale = []
	_checks = 0
	_facts = {}
	_results = []


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


## A Game driven only through advance(); its own _process is off (GameFixture).
func _start(config: GameConfig = _config, args := PackedStringArray()) -> void:
	_game = GameFixture.make_game(_vp, config, 7, args)
	await get_tree().process_frame
	_game.advance(0.0)


func _buildable_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			if m.is_buildable(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


func _counters() -> Array:
	return [_game.hud.refresh_count, _game.picker.refresh_count,
		_game.tower_panel.refresh_count, _game.lighthouse_panel.refresh_count,
		_game.hud.sanity_bar.redraw_count, _game.crew_panel.refresh_count]


## LT-32: the golden config with the shipped data/crew.json (crew on), parsed into it.
func _crew_config() -> GameConfig:
	var cfg := GoldenRuns.golden_config()
	var root: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/crew.json"))
	var r := ConfigReader.new("crew.json")
	cfg.crew = CrewConfig.parse(r, root)
	assert_array(r.errors).is_empty()
	assert_bool(cfg.crew_on()).is_true()
	return cfg


## Opens `view` ("picker", "tower", "lighthouse") the way a click on its cell does; builds
## a tower first for "tower". "crew" (LT-32) is the HUD crew button's view.
func _open(view: String) -> void:
	var cells := _buildable_cells()
	match view:
		"picker":
			_game._on_cell_clicked(cells[0])
		"tower":
			assert_int(_game.commands.build(RIFLE, cells[1])).is_equal(SimCommand.CommandResult.OK)
			_game._on_cell_clicked(cells[1])
		"lighthouse":
			_game._on_cell_clicked(_game.sim.state.map.lighthouse)
		"crew":
			_game.open_crew_panel()
	_game.advance(0.0)


func _view_node(view: String) -> Control:
	match view:
		"picker":
			return _game.picker
		"tower":
			return _game.tower_panel
		"crew":
			return _game.crew_panel
	return _game.lighthouse_panel


# ---- B1 ------------------------------------------------------------------------------

## B1: with the picker, the tower panel, the lighthouse panel or (LT-32, crew on) the crew
## panel open, idle frames (paused, and unpaused with a zero delta) rebuild no group and
## redraw nothing.
func test_b1_idle_frames_do_no_panel_work() -> void:
	for view in ["picker", "tower", "lighthouse", "crew"]:
		await _start(_crew_config() if view == "crew" else _config)
		_open(view)
		assert_bool(_view_node(view).visible).override_failure_message(view).is_true()
		assert_int(_game.sim.state.sanity_state).is_equal(SimState.SanityState.LUCID)
		var before := _counters()
		_game.toggle_pause()  # a UI signal: it rewrites the speed group once, not per frame
		var after_toggle := _counters()
		for i in 120:
			_game.advance(1.0 / 60.0)
		for i in 3:
			await get_tree().process_frame  # engine frames: the bar's _process, if it ran
		assert_array(_counters()).override_failure_message(
			"%s, paused: %s -> %s" % [view, after_toggle, _counters()]).is_equal(after_toggle)
		_game.toggle_pause()
		var unpaused := _counters()
		var tick := _game.sim.state.tick
		for i in 120:
			_game.advance(0.0)
		for i in 3:
			await get_tree().process_frame
		assert_int(_game.sim.state.tick).is_equal(tick)  # a zero delta steps nothing
		assert_array(_counters()).override_failure_message(
			"%s, advance(0.0): %s -> %s" % [view, unpaused, _counters()]).is_equal(unpaused)
		assert_bool(_game.hud.sanity_bar.is_processing()).is_false()
		assert_int(before.size()).is_equal(6)
		_game.queue_free()
		await get_tree().process_frame


# ---- B3 ------------------------------------------------------------------------------

## B3: with no command and no event, the day label follows build_ticks_left on stepped
## frames and is rewritten at most once per whole second (at both speeds).
func test_b3_day_countdown_rewrites_once_per_whole_second() -> void:
	for speed in [1, 2]:
		await _start()
		if speed == 2:
			_game.toggle_speed()
		var hud := _game.hud
		var s := _game.sim.state
		var frames := 5 * WHOLE_SECOND_FRAMES
		var text_changes := 0
		var rewrites_before := hud.refresh_count
		var last := hud.phase_label.text
		var secs_start := SimTime.whole_seconds(s.build_ticks_left)
		for i in frames:
			_game.advance(1.0 / 60.0)
			var want := "Day 1 — night falls in %d s" % SimTime.whole_seconds(s.build_ticks_left)
			assert_str(hud.phase_label.text).override_failure_message(
				"x%d frame %d" % [speed, i]).is_equal(want)
			if hud.phase_label.text != last:
				text_changes += 1
				last = hud.phase_label.text
		var elapsed := secs_start - SimTime.whole_seconds(s.build_ticks_left)
		assert_int(elapsed).is_greater_equal(4 * speed)
		# One rewrite per whole second shown, never one per frame.
		assert_int(text_changes).is_equal(elapsed)
		assert_int(hud.refresh_count - rewrites_before).is_less_equal(elapsed)
		_game.queue_free()
		await get_tree().process_frame


# ---- B4 ------------------------------------------------------------------------------

## B4: a hidden lighthouse panel is not kept current; reopened mid-game it shows the truth.
func test_b4_hidden_panel_reopened_mid_game_is_current() -> void:
	await _start()
	var sim := _game.sim
	_game._on_cell_clicked(sim.state.map.lighthouse)
	var panel := _game.lighthouse_panel
	assert_bool(panel.visible).is_true()
	var old_oil := panel.oil_label.text
	var old_title := panel.title_label.text
	assert_str(old_title).is_equal("Lighthouse  L1")
	_game.close_panels()
	assert_bool(panel.visible).is_false()
	assert_int(_game.commands.upgrade_lighthouse()).is_equal(SimCommand.CommandResult.OK)
	assert_int(_game.commands.buy_oil()).is_equal(SimCommand.CommandResult.OK)
	assert_int(_game.commands.buy_oil()).is_equal(SimCommand.CommandResult.OK)
	_game.advance(0.0)
	_game._on_cell_clicked(sim.state.map.lighthouse)
	assert_bool(panel.visible).is_true()
	assert_str(panel.title_label.text).is_equal("Lighthouse  L2")
	assert_str(panel.oil_label.text).starts_with("Lamp oil: 2 / %d" % sim.oil_cap())
	assert_str(panel.oil_label.text).is_not_equal(old_oil)
	assert_str(panel.stats_label.text).starts_with("Beams: %d" % sim.beam_count())
	# Same for the tower panel and the picker: opened after changes, equal to a fresh sync.
	for view in ["tower", "picker"]:
		_game.close_panels()
		_open(view)
		var a := UiSnapshot.take(_view_node(view))
		_view_node(view).refresh()
		assert_array(UiSnapshot.diff(a, UiSnapshot.take(_view_node(view)))).is_empty()


# ---- B5 ------------------------------------------------------------------------------

## B5: selling a tower closes its open panel in the same drain, and the board selection.
func test_b5_selling_a_tower_closes_its_panel() -> void:
	await _start()
	var cells := _buildable_cells()
	assert_int(_game.commands.build(RIFLE, cells[1])).is_equal(SimCommand.CommandResult.OK)
	assert_int(_game.commands.build(RIFLE, cells[2])).is_equal(SimCommand.CommandResult.OK)
	var other := _game.sim.state.tower_at[cells[2]]
	var id: int = _game.sim.state.tower_at[cells[1]]
	_game._on_cell_clicked(cells[1])
	assert_bool(_game.tower_panel.visible).is_true()
	assert_int(_game.tower_panel.tower_id).is_equal(id)
	# Selling another tower leaves this panel open (and current).
	assert_int(_game.commands.sell(other)).is_equal(SimCommand.CommandResult.OK)
	assert_bool(_game.tower_panel.visible).is_true()
	assert_int(_game.commands.sell(id)).is_equal(SimCommand.CommandResult.OK)
	assert_bool(_game.tower_panel.visible).is_false()
	assert_vector(_game.selection.cell).is_equal(Vector2i(-1, -1))


# ---- B6 ------------------------------------------------------------------------------

## B6: the sanity bar processes only while FRAYING or MADNESS, switched by the HUD from the
## sanity-state event.
func test_b6_sanity_bar_animates_only_while_distorted() -> void:
	await _start()
	var bar := _game.hud.sanity_bar
	assert_bool(bar.is_processing()).override_failure_message("LUCID at start").is_false()
	# [sanity, expected state, expected processing]
	var steps := [
		[100.0, SimState.SanityState.LUCID, false],
		[55.0, SimState.SanityState.WHISPERS, false],
		[20.0, SimState.SanityState.FRAYING, true],
		[100.0, SimState.SanityState.LUCID, false],
		[30.0, SimState.SanityState.FRAYING, true],
		[0.0, SimState.SanityState.MADNESS, true],
	]
	for st: Array in steps:
		_game.sim.debug_set_sanity(st[0])
		GameFixture.sync(_game)  # LT-85: poked on the sim directly
		_game.advance(0.0)
		assert_int(_game.sim.state.sanity_state).is_equal(st[1])
		assert_bool(bar.is_processing()).override_failure_message(
			"sanity %s (state %d)" % [st[0], st[1]]).is_equal(st[2])


## §3 row 23: a sanity change inside one state (no SANITY_STATE_CHANGED, no cap change) still
## redraws the bar, so its fill does not go stale while LUCID drains (LT-78/S10 finding 1).
func test_b6_sanity_change_within_a_state_redraws_the_bar() -> void:
	await _start()
	var bar := _game.hud.sanity_bar
	for value: float in [95.0, 85.0]:
		var before_state := _game.sim.state.sanity_state
		var before := bar.redraw_count
		_game.sim.debug_set_sanity(value)
		GameFixture.sync(_game)
		_game.advance(0.0)
		assert_int(_game.sim.state.sanity_state).override_failure_message(
			"sanity %s must stay in one state" % value).is_equal(before_state)
		assert_int(bar.redraw_count).override_failure_message(
			"sanity %s: the bar was not redrawn" % value).is_greater(before)


# ---- B7 ------------------------------------------------------------------------------

## B7: DebugArgs.parse. Rows: [args, debug_build, sandbox, reveal_fakes, frame_stats, mute,
## sanity].
func test_b7_debug_args_parse_table() -> void:
	var all := PackedStringArray(["--sandbox", "--reveal-fakes", "--frame-stats", "--mute",
		"--sanity=30"])
	var rows := [
		[PackedStringArray(), true, false, false, false, false, -1.0],
		[PackedStringArray(), false, false, false, false, false, -1.0],
		[all, true, true, true, true, true, 30.0],
		# Release build: every debug flag is dropped, --mute stays (any build).
		[all, false, false, false, false, true, -1.0],
		[PackedStringArray(["--sandbox"]), true, true, false, false, false, -1.0],
		[PackedStringArray(["--sandbox"]), false, false, false, false, false, -1.0],
		[PackedStringArray(["--reveal-fakes"]), true, false, true, false, false, -1.0],
		[PackedStringArray(["--reveal-fakes"]), false, false, false, false, false, -1.0],
		[PackedStringArray(["--frame-stats"]), true, false, false, true, false, -1.0],
		[PackedStringArray(["--frame-stats"]), false, false, false, false, false, -1.0],
		[PackedStringArray(["--mute"]), true, false, false, false, true, -1.0],
		[PackedStringArray(["--mute"]), false, false, false, false, true, -1.0],
		[PackedStringArray(["--sanity", "25"]), true, false, false, false, false, 25.0],
		[PackedStringArray(["--sanity", "25"]), false, false, false, false, false, -1.0],
		[PackedStringArray(["--sanity=-5"]), true, false, false, false, false, 0.0],
		[PackedStringArray(["--sanity=abc"]), true, false, false, false, false, -1.0],
		[PackedStringArray(["--sanity"]), true, false, false, false, false, -1.0],
		[PackedStringArray(["--unknown", "--sanity=12", "x"]), true, false, false, false,
			false, 12.0],
		[PackedStringArray(["--sandbox=1", "--mute=1"]), true, false, false, false, false,
			-1.0],
	]
	for row: Array in rows:
		var d := DebugArgs.parse(row[0], row[1])
		var label := "%s debug_build=%s" % [row[0], row[1]]
		assert_bool(d.sandbox).override_failure_message(label + " sandbox").is_equal(row[2])
		assert_bool(d.reveal_fakes).override_failure_message(label + " reveal_fakes").is_equal(row[3])
		assert_bool(d.frame_stats).override_failure_message(label + " frame_stats").is_equal(row[4])
		assert_bool(d.mute).override_failure_message(label + " mute").is_equal(row[5])
		assert_float(d.sanity).override_failure_message(label + " sanity").is_equal(row[6])


## B7: the setup seam. Game.setup parses the launch args it is given into game.debug and
## builds its commands from them (a sandboxed purse); without flags nothing is set.
func test_b7_setup_reads_its_args_through_debug_args() -> void:
	await _start(_config, PackedStringArray(["--sandbox"]))
	assert_bool(_game.debug.sandbox).is_true()
	assert_bool(_game.sandbox).is_true()
	assert_int(_game.sim.state.gold).is_equal(DebugArgs.SANDBOX_GOLD)
	_game.queue_free()
	await get_tree().process_frame
	await _start(_config, PackedStringArray())
	assert_bool(_game.debug.sandbox).is_false()
	assert_int(_game.sim.state.gold).is_equal(_config.economy.starting_gold)
	assert_float(_game.debug.sanity).is_equal(-1.0)


# ---- B2 / B3: the whole-game coverage test --------------------------------------------

## B2 (+ B3 per frame): a scripted whole game on golden data. After every frame and every
## command, each visible panel is snapshotted, refresh()ed and snapshotted again; the two
## must be equal (a field that is stale names its panel, node path, frame and the field).
## Then every snapshotted node path must have changed at least once on its own (through
## flush or on_stepped), or be in STATIC_OK.
func test_b2_every_field_follows_its_events() -> void:
	await _start()
	await _script_whole_game()
	_game.queue_free()
	await get_tree().process_frame
	# The buyout variant: the madness exit through the HUD's button.
	var cfg := GoldenRuns.golden_config()
	cfg.sanity.madness.exit_rule = "buyout"
	await _start(cfg)
	await _script_buyout()
	_report_coverage()


func _panels() -> Dictionary:
	return {"hud": _game.hud, "picker": _game.picker, "tower": _game.tower_panel,
		"lighthouse": _game.lighthouse_panel, "crew": _game.crew_panel}


## One snapshot-refresh-snapshot check of every visible panel.
func _check(label: String) -> void:
	_checks += 1
	var panels := _panels()
	for key: String in panels:
		var p: Control = panels[key]
		if not p.visible:
			_prev.erase(key)
			continue
		var a := UiSnapshot.take(p)
		for path in a:
			_seen["%s:%s" % [key, path]] = true
		if _prev.has(key):
			for path in UiSnapshot.changed_paths(_prev[key], a):
				_changed["%s:%s" % [key, path]] = true
		# refresh() re-arms the HUD's timers and the bar; keep what the frame left so a
		# missed on_stepped / set_distorted stays visible on the next frame too.
		var hud := _game.hud
		var bar_on := hud.sanity_bar.is_processing()
		var saved := [hud._day_active, hud._day_secs, hud._flare_active, hud._flare_shown.duplicate()]
		p.refresh()
		var b := UiSnapshot.take(p)
		for line in UiSnapshot.diff(a, b):
			_stale.append("[%s] frame %d tick %d %s: %s" % [label, _checks,
				_game.sim.state.tick, key, line])
		if key == "hud":
			if bar_on != hud.sanity_bar.is_processing():
				_stale.append("[%s] frame %d hud: SanityBar.is_processing %s -> %s" % [
					label, _checks, bar_on, hud.sanity_bar.is_processing()])
			hud.sanity_bar.set_process(bar_on)
			hud._day_active = saved[0]
			hud._day_secs = saved[1]
			hud._flare_active = saved[2]
			hud._flare_shown = saved[3]
		_prev[key] = b
	_note_facts()


func _note_facts() -> void:
	var s := _game.sim.state
	_facts["leaked"] = _facts.get("leaked", false) or s.lighthouse_hp < _config.economy.lighthouse_hp
	_facts["flare_burn"] = _facts.get("flare_burn", false) or s.flare_ticks_left > 0
	_facts["flare_cooldown"] = _facts.get("flare_cooldown", false) or s.flare_cooldown_ticks > 0
	_facts["madness"] = _facts.get("madness", false) \
		or s.sanity_state == SimState.SanityState.MADNESS
	_facts["fraying"] = _facts.get("fraying", false) \
		or s.sanity_state == SimState.SanityState.FRAYING
	_facts["night"] = _facts.get("night", false) or s.phase == SimState.Phase.WAVE
	_facts["second_day"] = _facts.get("second_day", false) \
		or (s.phase == SimState.Phase.BUILD and s.wave_index >= 1)
	_facts["hostile"] = _facts.get("hostile", false) or _game.hud.hostile_label.visible
	_facts["buyout"] = _facts.get("buyout", false) or _game.hud.buyout_button.visible
	_facts["lit"] = _facts.get("lit", false) or _game.tower_panel.lit_label.visible


## Advances `n` frames of `delta`, checking after each.
func _frames(n: int, delta := 1.0 / 60.0, label := "frame") -> void:
	for i in n:
		_game.advance(delta)
		_check(label)


## Runs `command` (it drains and flushes itself), then checks.
func _cmd(label: String, command: Callable) -> void:
	var r: Variant = command.call()
	_results.append("%s=%s" % [label, SimCommand.CommandResult.keys()[r] if r is int else "-"])
	_check(label)


func _click(cell: Vector2i, label: String) -> void:
	_game._on_cell_clicked(cell)
	_prev.clear()  # opening syncs from the truth; only what changes afterwards counts
	_check("open " + label)


## Frames until `done` or `max_frames`.
func _until(done: Callable, max_frames: int, delta: float, label: String) -> void:
	var i := 0
	while i < max_frames and not done.call() \
			and _game.sim.state.outcome == SimState.Outcome.NONE:
		_game.advance(delta)
		_check(label)
		i += 1


## A command or a direct sim write (a test hook, e.g. _add_gold) followed by a drain, then
## a check. Hooks bypass Game's commands, so the drain is the next frame's job.
func _hook(label: String, write: Callable) -> void:
	write.call()
	GameFixture.sync(_game)  # LT-85: a direct sim write, as a command rebuilds the snapshot
	_game.advance(0.0)
	_check(label)


## Builds through the command, asserts it was applied, returns the tower id.
func _build(def_id: String, cell: Vector2i) -> int:
	var r: int = _game.commands.build(def_id, cell)
	assert_int(r).override_failure_message("build %s at %s: %s (phase %d wave %d tick %d outcome %d)\n%s" % [
		def_id, cell, SimCommand.CommandResult.keys()[r], _game.sim.state.phase,
		_game.sim.state.wave_index, _game.sim.state.tick, _game.sim.state.outcome,
		", ".join(_results)]).is_equal(SimCommand.CommandResult.OK)
	_check("build " + def_id)
	return _game.sim.state.tower_at.get(cell, -1)


func _script_whole_game() -> void:
	var sim := _game.sim
	var s := sim.state
	var c := _game.commands
	var cells := _buildable_cells()
	_check("start")
	_frames(30, 1.0 / 60.0, "day")
	# Day 1: build with the picker open, upgrade both branches, priorities, sell.
	_click(cells[0], "picker")
	_frames(5, 1.0 / 60.0, "picker idle")
	var t1 := _build(RIFLE, cells[1])
	var t2 := _build(RIFLE, cells[2])
	var th := _build(HARPOON, cells[3])
	var te := _build(ELDER, cells[4])
	# Poor, picker open: a top-up makes the dear rows affordable (GOLD_CHANGED -> rows).
	_frames(3, 1.0 / 60.0, "poor")
	_hook("top-up", func() -> void: sim._add_gold(600, "test", 0))
	_frames(3, 1.0 / 60.0, "rich")
	var t3 := _build(RIFLE, cells[5])
	_click(cells[1], "tower")
	_frames(3, 1.0 / 60.0, "tower idle")
	_cmd("upgrade L2", func() -> int: return c.upgrade(t1, ""))
	_cmd("upgrade a", func() -> int: return c.upgrade(t1, "a"))
	_cmd("priority strongest", func() -> int: return c.set_target_priority(t1, "strongest"))
	_cmd("priority fastest", func() -> int: return c.set_target_priority(t1, "fastest"))
	_cmd("priority first", func() -> int: return c.set_target_priority(t1, "first"))
	_click(cells[2], "tower 2")
	_cmd("upgrade 2 L2", func() -> int: return c.upgrade(t2, ""))
	_cmd("upgrade 2 b", func() -> int: return c.upgrade(t2, "b"))
	_click(cells[3], "harpooner")
	_cmd("upgrade harpooner", func() -> int: return c.upgrade(th, ""))
	_click(cells[4], "elder sign")
	_cmd("upgrade elder", func() -> int: return c.upgrade(te, ""))
	# The panel's own tower is sold while it is open (B5 on the whole-game path).
	_click(cells[5], "tower 3")
	_cmd("sell open tower", func() -> int: return c.sell(t3))
	# Relics and the lighthouse, by day.
	_hook("relics found", func() -> void:
		sim._add_relics("bone", 3, "test", 0)
		sim._add_relics("amber", 2, "test", 0))
	_cmd("sell relics", func() -> int: return c.sell_relics())
	_click(s.map.lighthouse, "lighthouse")
	_frames(3, 1.0 / 60.0, "lighthouse idle")
	_cmd("buy oil", func() -> int: return c.buy_oil())
	_cmd("buy flare oil", func() -> int: return c.buy_flare_oil())
	_cmd("upgrade lighthouse", func() -> int: return c.upgrade_lighthouse())
	_cmd("buy flare oil 2", func() -> int: return c.buy_flare_oil())
	_frames(3, 1.0 / 60.0, "lighthouse day")
	# Speed and pause (UI signals, not sim events).
	_cmd("speed x2", func() -> void: _game.toggle_speed())
	_frames(20, 1.0 / 60.0, "x2")
	_cmd("pause", func() -> void: _game.toggle_pause())
	_frames(10, 1.0 / 60.0, "paused")
	_cmd("unpause", func() -> void: _game.toggle_pause())
	_cmd("speed x1", func() -> void: _game.toggle_speed())
	_frames(40, 0.0, "zero delta")
	# Sell every tower before night 1, so enemies leak.
	_click(cells[0], "picker again")
	_cmd("sell 2", func() -> int: return c.sell(t2))
	_cmd("sell harpooner", func() -> int: return c.sell(th))
	_cmd("sell elder", func() -> int: return c.sell(te))
	_cmd("sell 1", func() -> int: return c.sell(t1))
	_click(s.map.lighthouse, "lighthouse")
	# Night 1: the lamp, a flare, leaks.
	_cmd("call wave", func() -> int: return c.call_wave())
	_frames(20, 1.0 / 20.0, "night 1")
	_cmd("fire flare", func() -> int: return c.fire_flare())
	_until(func() -> bool: return s.flare_ticks_left == 0, 600, 1.0 / 20.0, "flare burn")
	_frames(30, 1.0 / 20.0, "flare cooldown")
	_until(func() -> bool: return s.phase != SimState.Phase.WAVE, 4000, 1.0 / 20.0, "night 1")
	# Day 2: the day timer from the start, purchases, then a night with towers.
	_click(cells[6], "picker day 2")
	_hook("top-up 2", func() -> void: sim._add_gold(900, "test", 0))
	t1 = _build(RIFLE, cells[1])
	t2 = _build(RIFLE, cells[2])
	_build(HARPOON, cells[3])
	_build(ELDER, cells[4])
	# The tower nearest the lighthouse is lit by the beam as it sweeps by (TOWER_LIT).
	var near := cells[0]
	for cell in cells:
		if (cell - s.map.lighthouse).length_squared() < (near - s.map.lighthouse).length_squared() \
				and not s.tower_at.has(cell):
			near = cell
	_build(RIFLE, near)
	_click(cells[1], "tower d2")
	_frames(100, 1.0 / 20.0, "day 2")
	_cmd("call wave 2", func() -> int: return c.call_wave())
	_click(cells[1], "tower night 2")
	_frames(80, 1.0 / 20.0, "night 2 early")
	_click(near, "tower near the lighthouse")
	_frames(400, 1.0 / 20.0, "beam sweep")
	# Sanity through every tier at night (the bar, the madness line, tower warnings), with the
	# sanity-scaled elder sign open.
	_click(cells[4], "elder sign night 2")
	for v in [55.0, 25.0, 100.0, 30.0, 0.0]:
		_hook("sanity %s" % v, func() -> void: sim.debug_set_sanity(v))
		_frames(10, 1.0 / 20.0, "sanity %s" % v)
	_click(cells[2], "tower night 2b")
	_frames(100, 1.0 / 20.0, "tower night 2b")
	_until(func() -> bool: return s.phase != SimState.Phase.WAVE, 3000, 1.0 / 20.0, "night 2")


# ---- B2, LT-32 crew ------------------------------------------------------------------

## LT-32 crew fields that never change through flush while their view stays open, with the
## reason (same form as STATIC_OK): the crew view's title, note and cancel button are fixed
## text; a post's "Not a tower" note is fixed per opened tower, and a post's view is only
## reached by a click (which resyncs), so it is pinned by crew_ui_test instead.
const CREW_STATIC_OK: PackedStringArray = [
	"crew:^(\\.|Title|Note|CancelButton)$",
	"tower:^PostNote$",
]
## Paths the crew B2 run must cover: the crew view, the HUD crew button, the picker's post
## section and the post note.
const CREW_PATHS := "^(crew:|hud:Footer/CrewButton$|picker:Posts|tower:PostNote$)"


## B2 with crew on (golden data + the shipped crew.json): hires with the crew view open,
## a crewed build and sale (on duty), the picker's price following the reserve, the night
## post rows as posts are deployed (one from the picker row), the crew view at night, a
## post's view, dawn, and a hire on the next day: no stale field anywhere, and every crew
## field changes through flush at least once.
func test_b2_crew_fields_follow_their_events() -> void:
	await _start(_crew_config())
	await _script_crew()
	assert_array(_stale).override_failure_message(
		"stale fields (first 12 of %d):\n%s" % [_stale.size(), "\n".join(_stale.slice(0, 12))]
	).is_empty()
	var re := RegEx.create_from_string(CREW_PATHS)
	var covered := 0
	var unexercised: Array[String] = []
	for key: String in _seen:
		if re.search(key) == null:
			continue
		covered += 1
		var ok := _changed.has(key)
		for entry in CREW_STATIC_OK:
			var panel := entry.get_slice(":", 0)
			var pre := RegEx.create_from_string(entry.substr(panel.length() + 1))
			if key.begins_with(panel + ":") and pre.search(key.substr(panel.length() + 1)) != null:
				ok = true
		if not ok:
			unexercised.append(key)
	unexercised.sort()
	assert_int(covered).override_failure_message("crew paths seen: %d" % covered).is_greater(10)
	assert_array(unexercised).override_failure_message(
		"crew node paths never changed through flush and not in CREW_STATIC_OK:\n"
		+ "\n".join(unexercised) + "\nresults: " + ", ".join(_results)).is_empty()


func _open_crew(label: String) -> void:
	_game.open_crew_panel()
	_prev.clear()  # opening syncs from the truth; only what changes afterwards counts
	_check("open " + label)


func _script_crew() -> void:
	var sim := _game.sim
	var s := sim.state
	var c := _game.commands
	var cells := _buildable_cells()
	var kinds: Array = sim.config.crew.crews.keys()
	var men: int = sim.config.crew.post.crew
	_check("start")
	_hook("rich", func() -> void: sim._add_gold(3000, "test", 0))
	# Day 1, crew view open: hire a post's worth of every kind (two for riflemen), then a
	# crewed build takes its men (on duty) and its sale returns them.
	_open_crew("crew")
	_frames(3, 1.0 / 60.0, "crew idle")
	for kind: String in kinds:
		for i in men * (2 if kind == RIFLE else 1):
			_cmd("hire " + kind, func() -> int: return c.hire(kind))
	var t := _build(RIFLE, cells[1])
	_cmd("sell crewed", func() -> int: return c.sell(t))
	# Picker open: the rifleman's price follows the reserve.
	_click(cells[0], "picker")
	_build(RIFLE, cells[1])
	_build(RIFLE, cells[2])
	for k in men * 2:  # one post from the commands, one from the picker row
		_cmd("hire rifleman %d" % k, func() -> int: return c.hire(RIFLE))
	# Night 1 with the picker open: post rows follow each deploy, then one from the row.
	_cmd("call wave", func() -> int: return c.call_wave())
	_frames(5, 1.0 / 20.0, "night picker")
	var i := 3
	for kind: String in kinds:
		var cell := cells[i]
		_cmd("deploy " + kind, func() -> int: return c.deploy(kind, cell))
		i += 1
	assert_bool(_game.picker.post_buttons[RIFLE].disabled).is_false()
	_cmd("post row", func() -> int:
		_game.picker.post_buttons[RIFLE].pressed.emit()
		return SimCommand.CommandResult.OK)
	assert_bool(s.tower_at.has(cells[0])).override_failure_message("no post from the row").is_true()
	# The crew view at night (hire refused), then a post's view until dawn removes it.
	_open_crew("crew night")
	_frames(5, 1.0 / 20.0, "crew night")
	_click(cells[3], "post view")
	_frames(5, 1.0 / 20.0, "post view")
	_open_crew("crew to dawn")
	_hook("end night", func() -> void: sim.debug_end_night())
	_until(func() -> bool: return s.phase != SimState.Phase.WAVE, 400, 1.0 / 20.0, "to dawn")
	assert_int(s.phase).is_not_equal(SimState.Phase.WAVE)
	_frames(5, 1.0 / 20.0, "day 2")
	_cmd("hire day 2", func() -> int: return c.hire(HARPOON))


func _script_buyout() -> void:
	var sim := _game.sim
	var c := _game.commands
	_check("start")
	_hook("rich", func() -> void: sim._add_gold(500, "test", 0))
	_frames(5, 1.0 / 20.0, "day")
	_hook("madness", func() -> void: sim.debug_set_sanity(0.0))
	_frames(10, 1.0 / 20.0, "madness")
	_hook("broke", func() -> void: sim._add_gold(-sim.state.gold, "test", 0))
	_hook("rich again", func() -> void: sim._add_gold(500, "test", 0))
	_cmd("buyout", func() -> int: return c.buy_sanity())
	_frames(10, 1.0 / 20.0, "after buyout")


func _static_ok(key: String) -> bool:
	for entry in STATIC_OK:
		var panel := entry.get_slice(":", 0)
		var re := RegEx.create_from_string(entry.substr(panel.length() + 1))
		if key.begins_with(panel + ":") and re.search(key.substr(panel.length() + 1)) != null:
			return true
	return false


func _report_coverage() -> void:
	assert_int(_checks).is_greater(1000)
	for fact: String in ["leaked", "flare_burn", "flare_cooldown", "madness", "fraying", "night",
			"second_day", "hostile", "buyout", "lit"]:
		assert_bool(_facts.get(fact, false)).override_failure_message(
			"the scripted game never reached: " + fact).is_true()
	assert_array(_stale).override_failure_message(
		"stale fields (first 12 of %d):\n%s" % [_stale.size(), "\n".join(_stale.slice(0, 12))]
	).is_empty()
	var unexercised: Array[String] = []
	for key: String in _seen:
		if not _changed.has(key) and not _static_ok(key):
			unexercised.append(key)
	unexercised.sort()
	assert_array(unexercised).override_failure_message(
		"node paths never changed through flush/on_stepped and not in STATIC_OK:\n"
		+ "\n".join(unexercised) + "\nresults: " + ", ".join(_results)).is_empty()
