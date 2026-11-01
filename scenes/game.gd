class_name Game
extends Node2D
## One run (LT-7): owns the Simulation, its WaveDirector and the SimClock, steps the sim
## from _process and hands the frame's events to the board and the HUD.
## Scenes only read `sim.state` and call sim commands; no game rules live here.

signal restart_requested

const BOARD_ORIGIN := Vector2(0, 48)  ## below the HUD bar
const REVEAL_FAKES_ARG := "--reveal-fakes"  ## `-- --reveal-fakes` (debug builds only)
## `-- --sanity=<v>` or `-- --sanity <v>` (debug builds only, LT-14, LT-21): sets sanity at
## the start of the run through the sim's own sanity path, so SANITY_CHANGED /
## SANITY_STATE_CHANGED fire as usual. User args must follow a bare `--`.
const SANITY_ARG := "--sanity"
## `-- --frame-stats` (debug builds only, LT-38 P1): shows the wall-clock frame time
## (median / p90 over the last FrameStats.CAPACITY frames) in the HUD.
const FRAME_STATS_ARG := "--frame-stats"
const UI_LAYER := 2  ## above SanityFx.SCREEN_LAYER, so the HUD is never distorted

var sim: Simulation
var clock := SimClock.new()
var chosen_speed := 1  ## x1 / x2; the clock runs at 0 while paused
var paused := false
var run_seed := 0
var frame_stats: FrameStats  ## LT-38 P1: null unless `--frame-stats` in a debug build
var _last_frame_usec := 0

var board: Board
var lighting: Lighting  ## LT-8: darkness, beam, tower lights, sea fog (visual only)
var sanity_fx: SanityFx  ## LT-14: screen distortion, UI jitter, whispers (visual only)
var hud: Hud
var relic_tokens: RelicTokens  ## LT-27 §4: tokens flying from kills to the HUD counter
var star_stones_found := 0  ## LT-27 §4: star-stones credited this run (end screen)
var side_panel: SidePanel  ## LT-24: fixed right panel holding the two views below
var picker: TowerPicker  ## LT-61: the build list at the top of side_panel, its card below
var tower_panel: TowerPanel  ## tower view of side_panel
var lighthouse_panel: LighthousePanel  ## LT-30: lighthouse view of side_panel
var end_screen: EndScreen


func setup(config: GameConfig, p_seed: int) -> void:
	run_seed = p_seed
	sim = Simulation.new(config, p_seed)
	sim.set_spawner(WaveDirector.new(config.waves))
	# LT-12 §1: debug builds only; the board then marks fakes via sim.debug_is_fake.
	sim.debug_reveal_fakes = OS.is_debug_build() \
		and OS.get_cmdline_user_args().has(REVEAL_FAKES_ARG)
	if OS.is_debug_build():
		var forced := debug_sanity_arg(OS.get_cmdline_user_args())
		if forced >= 0.0:
			sim.debug_set_sanity(forced)
		if OS.get_cmdline_user_args().has(FRAME_STATS_ARG):
			frame_stats = FrameStats.new()


## The `--sanity=<v>` / `--sanity <v>` value clamped to >= 0, or -1 when absent or not a
## number.
static func debug_sanity_arg(args: PackedStringArray) -> float:
	for i in args.size():
		var v := ""
		if args[i].begins_with(SANITY_ARG + "="):
			v = args[i].trim_prefix(SANITY_ARG + "=")
		elif args[i] == SANITY_ARG and i + 1 < args.size():
			v = args[i + 1]
		else:
			continue
		return maxf(v.to_float(), 0.0) if v.is_valid_float() else -1.0
	return -1.0


func _ready() -> void:
	board = Board.new()
	board.name = "Board"
	board.position = BOARD_ORIGIN
	board.game = self
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
	end_screen = EndScreen.new()
	end_screen.name = "EndScreen"
	ui.add_child(end_screen)
	end_screen.restart_pressed.connect(func() -> void: restart_requested.emit())
	_apply_speed()
	_consume_events()  # BUILD_STARTED from set_spawner
	hud.refresh()


func _process(delta: float) -> void:
	advance(delta)


## One frame: runs the steps SimClock grants, consumes the events, redraws.
func advance(delta: float) -> void:
	if frame_stats != null:
		var now := Time.get_ticks_usec()
		if _last_frame_usec > 0:
			frame_stats.push((now - _last_frame_usec) / 1000.0)
		_last_frame_usec = now
	var steps := clock.advance(delta)
	for i in steps:
		sim.step()
	_consume_events()
	board.alpha = clock.alpha()
	board.tick_effects(delta)
	relic_tokens.tick(delta)
	board.queue_redraw()
	hud.refresh()
	picker.refresh()
	tower_panel.refresh()
	lighthouse_panel.refresh()


# --- Player commands (forwarded to the sim) -------------------------------------------

func build(def_id: String, cell: Vector2i) -> Simulation.CommandResult:
	var r := sim.build_tower(def_id, cell)
	_after_command()
	return r


func sell(tower_id: int) -> Simulation.CommandResult:
	var r := sim.sell_tower(tower_id)
	_after_command()
	return r


## LT-24: branch "" for L1 -> L2, "a"/"b" for L2 -> L3.
func upgrade(tower_id: int, branch := "") -> Simulation.CommandResult:
	var r := sim.upgrade_tower(tower_id, branch)
	_after_command()
	return r


## LT-31: mode is one of SimTower.TARGET_PRIORITIES; allowed in any phase.
func set_target_priority(tower_id: int, mode: String) -> Simulation.CommandResult:
	var r := sim.set_target_priority(tower_id, mode)
	_after_command()
	return r


func call_wave() -> Simulation.CommandResult:
	var r := sim.call_wave()
	_after_command()
	return r


## LT-27 §1.4: sells the whole stash (by day only).
func sell_relics() -> Simulation.CommandResult:
	var r := sim.sell_relics()
	_after_command()
	return r


func buy_sanity() -> Simulation.CommandResult:
	var r := sim.buy_sanity()
	_after_command()
	return r


## LT-30: lighthouse level, by day, paid in money.
func upgrade_lighthouse() -> Simulation.CommandResult:
	var r := sim.upgrade_lighthouse()
	_after_command()
	return r


## LT-30: one unit of lamp oil, by day.
func buy_oil() -> Simulation.CommandResult:
	var r := sim.buy_oil()
	_after_command()
	return r


## LT-57 §4: oil for one flare, by day: buys one unit at a time (each a logged sim
## buy_oil) up to flare_oil_to_buy() units, stopping at the first refusal. Returns OK when
## at least one unit was bought, else the refusal.
func buy_flare_oil() -> Simulation.CommandResult:
	var r := Simulation.CommandResult.OK
	var bought := 0
	for i in flare_oil_to_buy():
		r = sim.buy_oil()
		if r != Simulation.CommandResult.OK:
			break
		bought += 1
	if bought == 0 and r == Simulation.CommandResult.OK:
		r = sim.can_buy_oil()
	_after_command()
	return Simulation.CommandResult.OK if bought > 0 else r


## LT-57: units buy_flare_oil() tries: min(flare.cost_oil, cap - oil) (1 per click without
## a flare block); 0 without an oil block.
func flare_oil_to_buy() -> int:
	var eco := sim.config.economy
	if eco.oil == null:
		return 0
	var want := eco.flare.cost_oil if eco.flare != null else 1
	return clampi(eco.oil.cap - sim.state.oil, 0, want)


## LT-30: the night flare, paid with oil.
func fire_flare() -> Simulation.CommandResult:
	var r := sim.fire_flare()
	_after_command()
	return r


func toggle_speed() -> void:
	chosen_speed = 2 if chosen_speed == 1 else 1
	_apply_speed()


func toggle_pause() -> void:
	paused = not paused
	_apply_speed()


func _apply_speed() -> void:
	clock.speed = 0 if paused else chosen_speed


## Commands apply between ticks; show their effect without waiting for the next frame.
func _after_command() -> void:
	_consume_events()
	board.queue_redraw()
	hud.refresh()
	picker.refresh()
	tower_panel.refresh()
	lighthouse_panel.refresh()


func _consume_events() -> void:
	for ev in sim.drain_events():
		board.on_event(ev)
		sanity_fx.on_event(ev)
		relic_tokens.on_event(ev)
		if ev.type == SimEvent.Type.RELICS_CHANGED and ev.data.get("reason", "") == "kill" \
				and ev.data.get("kind", "") == RelicTokens.STAR_STONE:
			star_stones_found += 1
		if ev.type == SimEvent.Type.OUTCOME:
			picker.close()
			tower_panel.close()
			lighthouse_panel.close()
			side_panel.visible = false
			end_screen.show_result(ev.data.get("result", "") == "won", sim.state,
				star_stones_found)


## LT-28: closes the build and tower views (a click on a cell, or one off the grid).
func close_panels() -> void:
	picker.close()
	tower_panel.close()
	lighthouse_panel.close()


func _on_cell_clicked(cell: Vector2i) -> void:
	close_panels()
	if sim.state.outcome != SimState.Outcome.NONE:
		return
	if cell == sim.state.map.lighthouse:
		lighthouse_panel.open()
	elif sim.state.tower_at.has(cell):
		tower_panel.open_for(sim.state.tower_at[cell])
	elif sim.state.map.is_buildable(cell):
		picker.open_for(cell)
