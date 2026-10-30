class_name Game
extends Node2D
## One run (LT-7): owns the Simulation, its WaveDirector and the SimClock, steps the sim
## from _process and hands the frame's events to the board and the HUD.
## Scenes only read `sim.state` and call sim commands; no game rules live here.

signal restart_requested

const BOARD_ORIGIN := Vector2(0, 48)  ## below the HUD bar
const REVEAL_FAKES_ARG := "--reveal-fakes"  ## `-- --reveal-fakes` (debug builds only)
## `-- --sanity=<v>` (debug builds only, LT-14): sets sanity at the start of the run through
## the sim's own sanity path, so SANITY_CHANGED / SANITY_STATE_CHANGED fire as usual.
const SANITY_ARG := "--sanity="
const UI_LAYER := 2  ## above SanityFx.SCREEN_LAYER, so the HUD is never distorted

var sim: Simulation
var clock := SimClock.new()
var chosen_speed := 1  ## x1 / x2; the clock runs at 0 while paused
var paused := false
var run_seed := 0

var board: Board
var lighting: Lighting  ## LT-8: darkness, beam, tower lights, sea fog (visual only)
var sanity_fx: SanityFx  ## LT-14: screen distortion, UI jitter, whispers (visual only)
var hud: Hud
var picker: TowerPicker
var sell_panel: SellPanel
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
			sim._add_sanity(forced - sim.state.sanity, "debug", 0)


## The `--sanity=<v>` value, or -1 when absent.
static func debug_sanity_arg(args: PackedStringArray) -> float:
	for arg in args:
		if arg.begins_with(SANITY_ARG):
			return maxf(arg.trim_prefix(SANITY_ARG).to_float(), 0.0)
	return -1.0


func _ready() -> void:
	board = Board.new()
	board.name = "Board"
	board.position = BOARD_ORIGIN
	board.game = self
	add_child(board)
	board.cell_clicked.connect(_on_cell_clicked)
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
	picker = TowerPicker.new()
	picker.name = "TowerPicker"
	picker.game = self
	ui.add_child(picker)
	sell_panel = SellPanel.new()
	sell_panel.name = "SellPanel"
	sell_panel.game = self
	ui.add_child(sell_panel)
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
	var steps := clock.advance(delta)
	for i in steps:
		sim.step()
	_consume_events()
	board.alpha = clock.alpha()
	board.tick_effects(delta)
	board.queue_redraw()
	hud.refresh()
	picker.refresh()
	sell_panel.refresh()


# --- Player commands (forwarded to the sim) -------------------------------------------

func build(def_id: String, cell: Vector2i) -> Simulation.CommandResult:
	var r := sim.build_tower(def_id, cell)
	_after_command()
	return r


func sell(tower_id: int) -> Simulation.CommandResult:
	var r := sim.sell_tower(tower_id)
	_after_command()
	return r


func call_wave() -> Simulation.CommandResult:
	var r := sim.call_wave()
	_after_command()
	return r


func buy_sanity() -> Simulation.CommandResult:
	var r := sim.buy_sanity()
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
	sell_panel.refresh()


func _consume_events() -> void:
	for ev in sim.drain_events():
		board.on_event(ev)
		sanity_fx.on_event(ev)
		if ev.type == SimEvent.Type.OUTCOME:
			picker.close()
			sell_panel.close()
			end_screen.show_result(ev.data.get("result", "") == "won", sim.state)


func _on_cell_clicked(cell: Vector2i) -> void:
	picker.close()
	sell_panel.close()
	if sim.state.outcome != SimState.Outcome.NONE:
		return
	if sim.state.tower_at.has(cell):
		sell_panel.open_for(sim.state.tower_at[cell])
	elif sim.state.map.is_buildable(cell):
		picker.open_for(cell)
