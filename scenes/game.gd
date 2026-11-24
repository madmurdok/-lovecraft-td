class_name Game
extends Node2D
## One run (LT-7): owns the Simulation, its WaveDirector and the SimClock, steps the sim
## from _process and hands the frame's events to the board and the HUD.
## Scenes only read `snapshot` (LT-85) and call sim commands; no game rules live here.

signal restart_requested
signal speed_changed  ## LT-78: chosen_speed or paused changed (the HUD's speed group)

const SKIP_KEY := KEY_N
const UI_LAYER := 2  ## above SanityFx.SCREEN_LAYER, so the HUD is never distorted

var sim: Simulation
## LT-85 §4: the one shared read-only copy of the sim that presentation reads, rebuilt on
## frames where the sim changed (a step or a command). Tests that poke the sim's state directly
## call refresh_snapshot() (GameFixture.sync) before reading presentation.
var snapshot: SimSnapshot
var clock := SimClock.new()
var chosen_speed := 1  ## x1 / x2; the clock runs at 0 while paused
var paused := false
var run_seed := 0
var frame_stats: FrameStats  ## LT-38 P1: null unless `--frame-stats` in a debug build
var _last_frame_usec := 0
## LT-62 P2: SimEvent type name -> count of the events consumed in the latest advance (only
## with frame_stats); a spike line reports the frame before it, whose draw took the time.
var _frame_events := {}
var debug := DebugArgs.new()  ## LT-78: the parsed launch args
var commands: GameCommands  ## LT-78: player commands (build, sell, ...), built in setup
## LT-67: `--sandbox` in a debug build (lives in `debug`; tests may set it after setup)
var sandbox: bool:
	get:
		return debug.sandbox
	set(v):
		debug.sandbox = v

var board: Board
## LT-84: the board overlay's selection; the panels write it, the board redraws on change.
var selection := SelectionModel.new()
var lighting: Lighting  ## LT-8: darkness, beam, tower lights, sea fog (visual only)
var sanity_fx: SanityFx  ## LT-14: screen distortion, UI jitter, whispers (visual only)
var hud: Hud
var relic_tokens: RelicTokens  ## LT-27 §4: tokens flying from kills to the HUD counter
var star_stones_found := 0  ## LT-27 §4: star-stones credited this run (end screen)
var side_panel: SidePanel  ## LT-24: fixed right panel holding the two views below
var picker: TowerPicker  ## LT-61: the build list at the top of side_panel, its card below
var tower_panel: TowerPanel  ## tower view of side_panel
var lighthouse_panel: LighthousePanel  ## LT-30: lighthouse view of side_panel
var crew_panel: CrewPanel  ## LT-32 §4: crew view of side_panel (opened from the HUD)
var end_screen: EndScreen


## `args` are the launch user args (after a bare `--`); tests pass their own.
func setup(
	config: GameConfig, p_seed: int, args: PackedStringArray = OS.get_cmdline_user_args()
) -> void:
	run_seed = p_seed
	debug = DebugArgs.parse(args)
	if debug.sandbox:
		config = config.sandboxed(DebugArgs.SANDBOX_GOLD)
	sim = Simulation.new(config, p_seed)
	sim.set_spawner(WaveDirector.new(config.waves))
	# LT-12 §1: debug builds only; the board then marks fakes via sim.debug_is_fake_id.
	sim.debug_reveal_fakes = OS.is_debug_build() and debug.reveal_fakes
	DebugArgs.apply_mute(args)
	if debug.sanity >= 0.0:
		sim.debug_set_sanity(debug.sanity)
	if debug.frame_stats:
		frame_stats = FrameStats.new()
	commands = GameCommands.new(sim, debug, _after_command)
	refresh_snapshot()  # LT-85 §4: built before any child's _ready reads it


## LT-85 §4: rebuilds `snapshot` from the sim. Game calls it after steps and commands;
## tests call it (GameFixture.sync) after poking sim state directly.
func refresh_snapshot() -> void:
	snapshot = sim.snapshot()


func _ready() -> void:
	board = Board.new()
	board.name = "Board"
	board.game = self
	board.selection = selection
	add_child(board)
	board.cell_clicked.connect(_on_cell_clicked)
	board.outside_clicked.connect(close_panels)
	lighting = Lighting.new()
	lighting.name = "Lighting"
	lighting.setup(self, self)
	board.add_child(lighting)
	sanity_fx = SanityFx.new()
	sanity_fx.name = "SanityFx"
	sanity_fx.game = self
	add_child(sanity_fx)

	var ui := CanvasLayer.new()
	ui.name = "UI"
	ui.layer = UI_LAYER
	add_child(ui)
	hud = Hud.new()
	hud.name = "Hud"
	hud.game = self
	ui.add_child(hud)
	relic_tokens = RelicTokens.new()
	relic_tokens.name = "RelicTokens"
	relic_tokens.game = self
	ui.add_child(relic_tokens)
	side_panel = SidePanel.new()
	side_panel.name = "SidePanel"
	side_panel.game = self
	ui.add_child(side_panel)
	picker = side_panel.picker  # LT-61 §1: the build list is in the side panel
	tower_panel = side_panel.tower_panel
	lighthouse_panel = side_panel.lighthouse_panel
	crew_panel = side_panel.crew_panel
	end_screen = EndScreen.new()
	end_screen.name = "EndScreen"
	ui.add_child(end_screen)
	end_screen.restart_pressed.connect(func() -> void: restart_requested.emit())
	_apply_speed()
	_consume_events()  # BUILD_STARTED from set_spawner
	hud.refresh()


func _process(delta: float) -> void:
	advance(delta)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if sandbox and k != null and k.pressed and not k.echo and k.keycode == SKIP_KEY:
		commands.skip_ahead()
		get_viewport().set_input_as_handled()


## LT-62 P2: the context of a spike line at wall clock `now_usec`: run time, sim tick, sanity
## state, live enemies, towers, board effects, window focus and the events consumed in the
## previous frame (the one whose process + draw the spike interval covers). Read-only.
func spike_context(now_usec: int) -> Dictionary:
	var st := snapshot
	var win: Window = get_window() if is_inside_tree() else null
	return {
		"t": "%.2fs" % (now_usec / 1000000.0),
		"tick": st.tick,
		"sanity": SimState.SanityState.keys()[st.sanity_state],
		"enemies": st.enemies.size(),
		"towers": st.towers.size(),
		"effects": board.fx_layer.effects.size() if board != null else 0,
		"focus": win.has_focus() if win != null else false,
		"events": _frame_events.duplicate(),
	}


## One frame: runs the steps SimClock grants, consumes the events, redraws.
func advance(delta: float) -> void:
	if frame_stats != null:
		var now := Time.get_ticks_usec()
		if _last_frame_usec > 0:
			var ms := (now - _last_frame_usec) / 1000.0
			frame_stats.push(ms)
			if FrameStats.is_spike(ms):
				print(FrameStats.spike_line(ms, spike_context(now)))
		_last_frame_usec = now
		_frame_events.clear()
	var steps := clock.advance(delta)
	for i in steps:
		sim.step()
	if steps > 0:
		refresh_snapshot()  # LT-85 §4: before the events reach their consumers
	# LT-78 §1: panels change only when events (or a running timer, on stepped frames) say so.
	if _consume_events() > 0 or steps > 0:
		_flush_ui()
	if steps > 0:
		hud.on_stepped()
	board.alpha = clock.alpha()
	board.tick_effects(delta)
	relic_tokens.tick(delta)
	board.queue_redraw()


func toggle_speed() -> void:
	chosen_speed = 2 if chosen_speed == 1 else 1
	_apply_speed()
	speed_changed.emit()


func toggle_pause() -> void:
	paused = not paused
	_apply_speed()
	speed_changed.emit()


func _apply_speed() -> void:
	clock.speed = 0 if paused else chosen_speed


## Commands apply between ticks; show their effect without waiting for the next frame.
func _after_command() -> void:
	refresh_snapshot()  # LT-85 §4: before the events and the panel flush read it
	_consume_events()
	board.queue_redraw()
	_flush_ui()


## Hands the drained events to their consumers (the panels only mark field groups; see
## _flush_ui). Returns how many events there were.
func _consume_events() -> int:
	var events := sim.drain_events()
	for ev in events:
		if frame_stats != null:
			var type_name: String = SimEvent.Type.keys()[ev.type]
			_frame_events[type_name] = _frame_events.get(type_name, 0) + 1
		board.on_event(ev)
		sanity_fx.on_event(ev)
		relic_tokens.on_event(ev)
		hud.on_event(ev)
		picker.on_event(ev)
		tower_panel.on_event(ev)
		lighthouse_panel.on_event(ev)
		crew_panel.on_event(ev)
		if ev.type == SimEvent.Type.RELICS_CHANGED and ev.data.get("reason", "") == "kill" \
				and ev.data.get("kind", "") == RelicTokens.STAR_STONE:
			star_stones_found += 1
		if ev.type == SimEvent.Type.OUTCOME:
			picker.close()
			tower_panel.close()
			lighthouse_panel.close()
			crew_panel.close()
			side_panel.visible = false
			end_screen.show_result(ev.data.get("result", "") == "won", snapshot,
				star_stones_found)
	return events.size()


## LT-78 §1: once per drain (never per event), each panel rebuilds the field groups the
## drained events marked, so a command that emits several events is read in its final state.
func _flush_ui() -> void:
	hud.flush()
	picker.flush()
	tower_panel.flush()
	lighthouse_panel.flush()
	crew_panel.flush()


## LT-28: closes the build and tower views (a click on a cell, or one off the grid).
func close_panels() -> void:
	picker.close()
	tower_panel.close()
	lighthouse_panel.close()
	crew_panel.close()


## LT-32 §4: the HUD's crew button: the crew view replaces whatever the side panel shows.
func open_crew_panel() -> void:
	close_panels()
	if snapshot.outcome == SimState.Outcome.NONE:
		crew_panel.open()


func _on_cell_clicked(cell: Vector2i) -> void:
	close_panels()
	if snapshot.outcome != SimState.Outcome.NONE:
		return
	if cell == snapshot.map.lighthouse:
		lighthouse_panel.open()
	elif snapshot.tower_at(cell) != null:
		tower_panel.open_for(snapshot.tower_at(cell).id)
	elif snapshot.map.is_buildable(cell):
		picker.open_for(cell)
