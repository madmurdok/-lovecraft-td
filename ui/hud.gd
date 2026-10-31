class_name Hud
extends Control
## Top HUD bar (LT-7, GDD §8-§9): gold, lighthouse HP, wave n / total, phase + build
## timer, call-wave button with the bonus it would pay, x1/x2 speed, pause, the sanity
## bar (LT-14) and, with madness exit_rule "buyout", the buyout button while in madness.
## LT-23 Q10: in madness a line under the sanity bar names the enemy buff (from config).
## Texts are rebuilt from sim state by refresh(); buttons call Game commands.

var game: Game

var gold_label: Label
var hp_label: Label
var wave_label: Label
var phase_label: Label
var call_wave_button: Button
var speed_button: Button
var pause_button: Button
var sanity_bar: SanityBar  ## LT-14: sanity with threshold marks
var buyout_button: Button  ## LT-13/14: madness buyout, only with exit_rule "buyout", in madness
var hostile_label: Label  ## LT-23 Q10: the madness enemy buff, only in madness


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.08, 0.08, 0.1)
	bg.custom_minimum_size = Vector2(0, Game.BOARD_ORIGIN.y)
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var bar := HBoxContainer.new()
	bar.name = "Bar"
	bar.position = Vector2(8, 8)
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	gold_label = _label(bar, "GoldLabel")
	hp_label = _label(bar, "HpLabel")
	wave_label = _label(bar, "WaveLabel")
	phase_label = _label(bar, "PhaseLabel")
	phase_label.custom_minimum_size = Vector2(190, 0)
	call_wave_button = _button(bar, "CallWaveButton", game.call_wave)
	speed_button = _button(bar, "SpeedButton", game.toggle_speed)
	pause_button = _button(bar, "PauseButton", game.toggle_pause)
	sanity_bar = SanityBar.new()
	sanity_bar.name = "SanityBar"
	sanity_bar.game = game
	sanity_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(sanity_bar)
	# LT-13 exit rule "buyout": shown by refresh() only in madness.
	buyout_button = _button(bar, "BuyoutButton", game.buy_sanity)
	buyout_button.visible = false
	# LT-23 Q10: just below the HUD strip, under the sanity bar (placed by refresh()).
	hostile_label = Label.new()
	hostile_label.name = "HostileLabel"
	hostile_label.visible = false
	hostile_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hostile_label.add_theme_font_size_override("font_size", 13)
	hostile_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.0, 0.02, 0.85)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 1
	box.content_margin_bottom = 2
	hostile_label.add_theme_stylebox_override("normal", box)
	add_child(hostile_label)
	# LT-14 Whispers jitter: the shader moves only the drawing, so click areas stay put.
	if game.sanity_fx != null:
		for c: CanvasItem in [gold_label, hp_label, wave_label, phase_label, call_wave_button,
				speed_button, pause_button, sanity_bar, buyout_button]:
			c.material = game.sanity_fx.ui_jitter_material


func refresh() -> void:
	var s := game.sim.state
	gold_label.text = "Gold: %d" % s.gold
	hp_label.text = "Lighthouse: %d / %d" % [s.lighthouse_hp, game.sim.config.economy.lighthouse_hp]
	wave_label.text = "Wave %d / %d" % [s.wave_index, s.waves_total]
	phase_label.text = phase_text(s)
	# LT-27/S5 stopgap: the early call sets the night luck now; S6 renames the button.
	call_wave_button.text = "Call wave (luck x%.2f)" % game.sim.early_night_luck()
	call_wave_button.disabled = (s.phase != SimState.Phase.BUILD
		or s.outcome != SimState.Outcome.NONE)
	speed_button.text = "x%d" % game.chosen_speed
	pause_button.text = "Resume" if game.paused else "Pause"
	# Visible only while it could ever apply: exit rule "buyout" and the player in madness.
	buyout_button.visible = (game.sim.config.sanity.madness.exit_rule == "buyout"
		and s.sanity_state == SimState.SanityState.MADNESS)
	buyout_button.text = "Restore (%dg)" % game.sim.config.sanity.madness.buyout_cost
	buyout_button.disabled = game.sim.can_buy_sanity() != Simulation.CommandResult.OK
	hostile_label.visible = s.sanity_state == SimState.SanityState.MADNESS
	if hostile_label.visible:
		hostile_label.text = hostile_text(game.sim.config.sanity.madness)
		# Starts under the sanity bar, shifted left so it ends before the side panel.
		var board_right := Game.BOARD_ORIGIN.x + s.map.width * Board.CELL
		var w := hostile_label.get_combined_minimum_size().x
		var x := minf(sanity_bar.get_global_rect().position.x - get_global_rect().position.x,
			board_right - w - 4.0)
		hostile_label.position = Vector2(x, Game.BOARD_ORIGIN.y + 2)
	sanity_bar.queue_redraw()


## LT-23 Q10: "The world turns hostile: enemies +20 % speed, −20 % damage taken" from the
## madness multipliers (a part is left out when its multiplier is 1).
static func hostile_text(m: SanityConfig.Madness) -> String:
	var parts := PackedStringArray()
	var speed := roundi((m.enemy_speed_multiplier - 1.0) * 100.0)
	if speed != 0:
		parts.append("%s%d %% speed" % ["+" if speed > 0 else TowerInfo.MINUS, absi(speed)])
	var taken := roundi((m.enemy_damage_taken_multiplier - 1.0) * 100.0)
	if taken != 0:
		parts.append("%s%d %% damage taken" % ["+" if taken > 0 else TowerInfo.MINUS, absi(taken)])
	if parts.is_empty():
		return "The world turns hostile"
	return "The world turns hostile: enemies " + ", ".join(parts)


## The build timer shows whole seconds rounded down, the same seconds the early-call
## night luck is set from (Simulation.early_night_luck).
static func phase_text(s: SimState) -> String:
	match s.phase:
		SimState.Phase.BUILD:
			return "Build: wave %d in %d s" % [s.wave_index + 1,
				SimTime.whole_seconds(s.build_ticks_left)]
		SimState.Phase.WAVE:
			return "Wave %d in progress" % s.wave_index
		SimState.Phase.DONE:
			return "All waves cleared"
	return ""


func _label(parent: Node, node_name: String) -> Label:
	var l := Label.new()
	l.name = node_name
	parent.add_child(l)
	return l


func _button(parent: Node, node_name: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: action.call())
	parent.add_child(b)
	return b
