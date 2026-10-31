class_name Hud
extends Control
## Top HUD bar (LT-7, GDD §8-§9): money, the relic stash and its value (LT-27), lighthouse
## HP, the day/night phase with its number (+ day timer; it replaced the wave counter), "Light the lamp" with the luck it would
## set, "Sell relics" (by day), the night's luck, x1/x2 speed, pause, the sanity bar (LT-14)
## and, with madness exit_rule "buyout", the buyout button while in madness.
## LT-23 Q10: in madness a line under the sanity bar names the enemy buff (from config).
## Texts are rebuilt from sim state by refresh(); buttons call Game commands.

var game: Game

var gold_label: Label  ## "Money: $240" (LT-27 §2: money is "gold" internally)
var relics_label: Label  ## LT-27 §4: "Relics: 12 (≈ $96)", per-kind tooltip; tokens land here
var hp_label: Label
var phase_label: Label
var call_wave_button: Button  ## "Light the lamp (luck ×1.62)": ends the day early
var sell_relics_button: Button  ## LT-27 §1.4: sells the whole stash, by day only
var luck_label: Label  ## LT-27 §1.2: "Luck ×1.62" at night while the night's luck > 1
var speed_button: Button
var pause_button: Button
var sanity_bar: SanityBar  ## LT-14: sanity with threshold marks
var buyout_button: Button  ## LT-13/14: madness buyout, only with exit_rule "buyout", in madness
var hostile_label: Label  ## LT-23 Q10: the madness enemy buff, only in madness
var footer: ColorRect  ## LT-28: covers the strip below the board (range rings end there)

const COLOR_LUCK := Color(0.75, 0.9, 1.0)
const FONT_SIZE := 14  ## LT-27: the bar fits the 1152 px base width, buyout included
const SEPARATION := 10
const MARGIN := 8  ## bar inset from the right edge
const RELIC_SLOT := 22.0  ## LT-28: left inset; relic tokens land in it, beside the counter


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	theme = UiStyle.theme(FONT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base_w := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = UiStyle.COLOR_BG
	bg.custom_minimum_size = Vector2(0, Game.BOARD_ORIGIN.y)
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	footer = ColorRect.new()
	footer.name = "Footer"
	footer.color = UiStyle.COLOR_BG
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a click there reaches the board
	footer.position = Vector2(0, board_rect().end.y)
	footer.size = Vector2(base_w,
		float(ProjectSettings.get_setting("display/window/size/viewport_height")) - footer.position.y)
	add_child(footer)
	var bar := HBoxContainer.new()
	bar.name = "Bar"
	# LT-27: two-line columns (money over relics, phase over lighthouse HP) keep the bar
	# inside the 1152 px base width with every button shown; children centre vertically.
	# LT-28: the bar spans the width in three groups (purse | day and night | speed, pause
	# and sanity) split by expanding gaps, so spare width goes between groups.
	bar.position = Vector2(RELIC_SLOT, 2)
	bar.custom_minimum_size = Vector2(base_w - RELIC_SLOT - MARGIN, Game.BOARD_ORIGIN.y - 4)
	bar.add_theme_constant_override("separation", SEPARATION)
	add_child(bar)
	var purse := _column(bar, "Purse")
	gold_label = _label(purse, "GoldLabel")
	relics_label = _label(purse, "RelicsLabel")
	relics_label.mouse_filter = Control.MOUSE_FILTER_PASS  # for the per-kind tooltip
	sell_relics_button = _button(bar, "SellRelicsButton", game.sell_relics)
	_gap(bar, "GapLeft")
	var status := _column(bar, "Status")
	phase_label = _label(status, "PhaseLabel")
	phase_label.custom_minimum_size = Vector2(176, 0)  # day text; no jump at dusk
	hp_label = _label(status, "HpLabel")
	luck_label = _label(bar, "LuckLabel")
	luck_label.add_theme_color_override("font_color", COLOR_LUCK)
	luck_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	luck_label.visible = false
	call_wave_button = _button(bar, "CallWaveButton", game.call_wave)
	_gap(bar, "GapRight")
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
		for c: CanvasItem in [gold_label, relics_label, hp_label, phase_label,
				luck_label, call_wave_button, sell_relics_button, speed_button, pause_button,
				sanity_bar, buyout_button]:
			c.material = game.sanity_fx.ui_jitter_material


func refresh() -> void:
	var s := game.sim.state
	gold_label.text = "Money: " + TowerInfo.money(s.gold)
	relics_label.text = relics_text(game.sim)
	relics_label.tooltip_text = relics_tooltip(game.sim)
	hp_label.text = "Lighthouse %d/%d" % [s.lighthouse_hp, game.sim.config.economy.lighthouse_hp]
	phase_label.text = phase_text(s)
	call_wave_button.disabled = game.sim.can_call_wave() != Simulation.CommandResult.OK
	call_wave_button.text = "Light the lamp" if call_wave_button.disabled \
		else "Light the lamp (luck %s)" % luck_text(game.sim.early_night_luck())
	sell_relics_button.text = "Sell relics (+%s)" % TowerInfo.money(game.sim.relics_value())
	sell_relics_button.disabled = game.sim.can_sell_relics() != Simulation.CommandResult.OK
	luck_label.visible = s.phase == SimState.Phase.WAVE and s.night_luck > 1.0
	luck_label.text = "Luck " + luck_text(s.night_luck)
	speed_button.text = "x%d" % game.chosen_speed
	pause_button.text = "Resume" if game.paused else "Pause"
	# Visible only while it could ever apply: exit rule "buyout" and the player in madness.
	buyout_button.visible = (game.sim.config.sanity.madness.exit_rule == "buyout"
		and s.sanity_state == SimState.SanityState.MADNESS)
	buyout_button.text = "Restore (%s)" % TowerInfo.money(game.sim.config.sanity.madness.buyout_cost)
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


## LT-27 §4: "Day 3 — night falls in 31 s" (day n comes before night n), "Night 3 of 5",
## "Dawn. All nights survived". The day timer shows whole seconds rounded down, the same
## seconds the early-night luck is set from (Simulation.early_night_luck).
static func phase_text(s: SimState) -> String:
	match s.phase:
		SimState.Phase.BUILD:
			return "Day %d — night falls in %d s" % [s.wave_index + 1,
				SimTime.whole_seconds(s.build_ticks_left)]
		SimState.Phase.WAVE:
			return "Night %d of %d" % [s.wave_index, s.waves_total]
		SimState.Phase.DONE:
			return "Dawn. All nights survived"
	return ""


## "×1.62": a luck multiplier, up to 2 decimals.
static func luck_text(luck: float) -> String:
	return "×" + TowerInfo.num(luck)


## LT-27 §4: "Relics: 12 (≈ $96)", the stash count and its value at today's prices.
static func relics_text(sim: Simulation) -> String:
	var n := 0
	for kind: String in sim.state.relics:
		n += sim.state.relics[kind]
	return "Relics: %d (≈ %s)" % [n, TowerInfo.money(sim.relics_value())]


## One line per relic kind in config order: "Amber: 3 × $15".
static func relics_tooltip(sim: Simulation) -> String:
	var lines := PackedStringArray()
	for k in sim.config.economy.relics:
		lines.append("%s: %d × %s" % [k.name, sim.state.relics.get(k.id, 0),
			TowerInfo.money(sim.relic_price(k.id))])
	return "\n".join(lines)


## The board in this layer's base pixels.
func board_rect() -> Rect2:
	var m := game.sim.state.map
	return Rect2(Game.BOARD_ORIGIN, Vector2(m.width, m.height) * Board.CELL)


## LT-28: where relic tokens land, in the slot left of the relic counter, so a landing
## token never covers its digits.
func relic_landing() -> Vector2:
	var r := relics_label.get_global_rect()
	return Vector2(r.position.x - RELIC_SLOT * 0.5, r.get_center().y)


## An expanding empty gap between bar groups.
func _gap(parent: Node, node_name: String) -> void:
	var c := Control.new()
	c.name = node_name
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)


func _label(parent: Node, node_name: String) -> Label:
	var l := Label.new()
	l.name = node_name
	parent.add_child(l)
	return l


## A tight two-line column in the bar, centred vertically.
func _column(parent: Node, node_name: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = node_name
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", -3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(v)
	return v


func _button(parent: Node, node_name: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: action.call())
	parent.add_child(b)
	return b
