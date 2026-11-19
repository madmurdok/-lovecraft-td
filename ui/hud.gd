class_name Hud
extends Control
## Top HUD bar (LT-7, GDD §8-§9): money, the relic stash and its value (LT-27), lighthouse
## HP, the day/night phase with its number (+ day timer; it replaced the wave counter), "Light the lamp" with the luck it would
## set, "Sell relics" (by day), the night's luck, x1/x2 speed, pause, the sanity bar (LT-14)
## and, with madness exit_rule "buyout", the buyout button while in madness.
## LT-23 Q10: in madness a line under the sanity bar names the enemy buff (from config).
## LT-78: texts are rebuilt per field group from the rule queries, only when a sim event
## marks the group (REFRESH_ON, flush), a timer shown in it ticks (on_stepped) or the speed
## changes; refresh() syncs every group. Buttons call Game commands.

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
var flare_button: Button  ## LT-30: the night flare, in the footer strip at the board's right end
var oil_label: Label  ## LT-30: "Oil 4 / 6", beside the flare button
var frame_label: Label  ## LT-38 P1: only with `--frame-stats` (debug builds)
var sandbox_label: Label  ## LT-67: "SANDBOX", only in a `--sandbox` run, top-right of the board
var fps_label: Label  ## LT-44: always-visible FPS readout, bottom-left in the footer strip
var _fps_shown := -1
var readout_timer: Timer  ## LT-78 Q3: refreshes the FPS and frame-stats labels
var footer: ColorRect  ## LT-28: covers the strip below the board (range rings end there)
## LT-78 §8 B1: field groups rebuilt so far (flush, on_stepped, refresh, speed_changed).
var refresh_count := 0
var _dirty := 0  ## groups marked by on_event since the last flush
var _day_active := false  ## the day timer runs (BUILD, no outcome): on_stepped watches it
var _day_secs := -1  ## whole seconds of the day timer the phase group last showed
var _flare_active := false  ## a flare burns or cools down: on_stepped watches it
var _flare_shown: Array = []  ## _flare_key() the flare group last showed

const COLOR_LUCK := Color(0.75, 0.9, 1.0)
const FONT_SIZE := 14  ## LT-27: the bar fits the 1200 px base width, buyout included
const SEPARATION := 10
const MARGIN := 8  ## bar inset from the right edge
const FPS_INTERVAL_MSEC := 250  ## LT-44: the readout Timer's period (FPS, frame stats)
const RELIC_SLOT := 22.0  ## LT-28: left inset; relic tokens land in it, beside the counter
## LT-78 §1: field groups (bits of _dirty).
const G_PURSE := 1  ## gold
const G_RELICS := 2  ## relic count, value and tooltip; "Sell relics"
const G_HP := 4  ## lighthouse HP
const G_PHASE := 8  ## phase line, "Light the lamp", night luck (+ the day timer)
const G_SPEED := 16  ## x1/x2 and pause (Game.speed_changed, not a sim event)
const G_SANITY := 32  ## sanity bar redraw and distortion, the madness line
const G_BUYOUT := 64  ## madness buyout button
const G_FLARE := 128  ## flare button and oil stock (+ the flare burn and cooldown timers)
const G_ALL := 255
const _PH := G_PHASE | G_RELICS | G_FLARE  ## phase events: day-only / night-only fields
## LT-78 §3 (rows 1-24): sim event -> the groups it may change. A group's values come from
## the rule queries at flush, never from the payload.
const REFRESH_ON: Dictionary[SimEvent.Type, int] = {
	SimEvent.Type.GOLD_CHANGED: G_PURSE | G_BUYOUT,
	SimEvent.Type.RELICS_CHANGED: G_RELICS,
	SimEvent.Type.LEAKED: G_HP,
	SimEvent.Type.BUILD_STARTED: _PH,
	SimEvent.Type.WAVE_STARTED: _PH,
	SimEvent.Type.WAVE_CLEARED: _PH,
	SimEvent.Type.OUTCOME: _PH | G_BUYOUT,
	SimEvent.Type.SANITY_CHANGED: G_SANITY,
	SimEvent.Type.SANITY_CAP_CHANGED: G_SANITY | G_BUYOUT,
	SimEvent.Type.SANITY_STATE_CHANGED: G_SANITY | G_BUYOUT,
	SimEvent.Type.OIL_CHANGED: G_FLARE,
	SimEvent.Type.FLARE_FIRED: G_FLARE,
	SimEvent.Type.LIGHTHOUSE_UPGRADED: G_FLARE,
}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	theme = UiStyle.theme(FONT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base_w := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var bar_h := board_rect().position.y  # the HUD bar is the strip above the board
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = UiStyle.COLOR_BG
	bg.custom_minimum_size = Vector2(0, bar_h)
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
	# LT-44: bottom-left of the footer strip (LT-30 oil + flare sit at its right end); not in the jitter list below.
	fps_label = Label.new()
	fps_label.name = "FpsLabel"
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.add_theme_font_size_override("font_size", 13)
	fps_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	fps_label.position = Vector2(6, footer.position.y + 4)
	add_child(fps_label)
	var bar := HBoxContainer.new()
	bar.name = "Bar"
	# LT-27: two-line columns (money over relics, phase over lighthouse HP) keep the bar
	# inside the 1200 px base width with every button shown; children centre vertically.
	# LT-28: the bar spans the width in three groups (purse | day and night | speed, pause
	# and sanity) split by expanding gaps, so spare width goes between groups.
	bar.position = Vector2(RELIC_SLOT, 2)
	bar.custom_minimum_size = Vector2(base_w - RELIC_SLOT - MARGIN, bar_h - 4)
	bar.add_theme_constant_override("separation", SEPARATION)
	add_child(bar)
	var purse := _column(bar, "Purse")
	gold_label = _label(purse, "GoldLabel")
	relics_label = _label(purse, "RelicsLabel")
	relics_label.mouse_filter = Control.MOUSE_FILTER_PASS  # for the per-kind tooltip
	sell_relics_button = _button(bar, "SellRelicsButton", game.commands.sell_relics)
	_gap(bar, "GapLeft")
	var status := _column(bar, "Status")
	phase_label = _label(status, "PhaseLabel")
	phase_label.custom_minimum_size = Vector2(176, 0)  # day text; no jump at dusk
	hp_label = _label(status, "HpLabel")
	luck_label = _label(bar, "LuckLabel")
	luck_label.add_theme_color_override("font_color", COLOR_LUCK)
	luck_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	luck_label.visible = false
	call_wave_button = _button(bar, "CallWaveButton", game.commands.call_wave)
	_gap(bar, "GapRight")
	speed_button = _button(bar, "SpeedButton", game.toggle_speed)
	pause_button = _button(bar, "PauseButton", game.toggle_pause)
	sanity_bar = SanityBar.new()
	sanity_bar.name = "SanityBar"
	sanity_bar.game = game
	sanity_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(sanity_bar)
	sanity_bar.item_rect_changed.connect(_place_hostile)
	# LT-13 exit rule "buyout": shown by refresh() only in madness.
	buyout_button = _button(bar, "BuyoutButton", game.commands.buy_sanity)
	buyout_button.visible = false
	# LT-30: the flare and the oil stock in the footer strip, right-aligned to the board's
	# edge; the FPS readout owns the left end of that strip.
	if game.sim.config.economy.flare != null:
		flare_button = _button(footer, "FlareButton", game.commands.fire_flare)
		oil_label = _label(footer, "OilLabel")
		oil_label.add_theme_color_override("font_color", COLOR_LUCK)
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
	if game.frame_stats != null:
		frame_label = Label.new()
		frame_label.name = "FrameLabel"
		frame_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame_label.add_theme_font_size_override("font_size", 13)
		frame_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		frame_label.position = Vector2(RELIC_SLOT, board_rect().position.y + 2)
		add_child(frame_label)
	if game.sandbox:
		sandbox_label = Label.new()
		sandbox_label.name = "SandboxLabel"
		sandbox_label.text = "SANDBOX"
		sandbox_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sandbox_label.add_theme_font_size_override("font_size", 16)
		sandbox_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
		add_child(sandbox_label)  # first, so the minimum size sees the HUD theme
		sandbox_label.size = sandbox_label.get_minimum_size()
		sandbox_label.position = Vector2(board_rect().end.x - sandbox_label.size.x - 6,
			board_rect().position.y + 2)
	# LT-78 Q3: the wall-clock readouts on a Timer instead of every frame.
	readout_timer = Timer.new()
	readout_timer.name = "ReadoutTimer"
	readout_timer.wait_time = FPS_INTERVAL_MSEC / 1000.0
	readout_timer.autostart = true
	readout_timer.timeout.connect(refresh_readouts)
	add_child(readout_timer)
	game.speed_changed.connect(_on_speed_changed)
	# LT-14 Whispers jitter: the shader moves only the drawing, so click areas stay put.
	if game.sanity_fx != null:
		for c: CanvasItem in [gold_label, relics_label, hp_label, phase_label,
				luck_label, call_wave_button, sell_relics_button, speed_button, pause_button,
				sanity_bar, buyout_button]:
			c.material = game.sanity_fx.ui_jitter_material


## LT-78 §1: full sync of every group from the sim (the HUD's initial sync in Game._ready;
## tests may call it). Between syncs a group changes only through flush() (its REFRESH_ON
## events), on_stepped() (the day and flare timers) or speed_changed.
func refresh() -> void:
	_dirty = 0
	_rebuild(G_ALL)


## LT-78 §1: marks the groups `ev` may change; flush() rebuilds them once per drain.
func on_event(ev: SimEvent) -> void:
	_dirty |= REFRESH_ON.get(ev.type, 0)


## LT-78 §1: rebuilds the groups marked since the last flush, from the rule queries.
func flush() -> void:
	if _dirty == 0:
		return
	var mask := _dirty
	_dirty = 0
	if not visible:
		return
	_rebuild(mask)


## LT-78 §1.1 (owner Q1, option C): called on frames that ran sim steps. While the day timer
## or a flare burn/cooldown runs, re-reads it and rewrites its group only when the shown
## whole seconds (or the flare's burning/cooldown/ready state) changed.
func on_stepped() -> void:
	if _day_active and SimTime.whole_seconds(game.sim.state.build_ticks_left) != _day_secs:
		_rebuild(G_PHASE)
	if _flare_active and _flare_key() != _flare_shown:
		_rebuild(G_FLARE)


func _rebuild(mask: int) -> void:
	if mask & G_PURSE:
		_refresh_purse()
	if mask & G_RELICS:
		_refresh_relics()
	if mask & G_HP:
		_refresh_hp()
	if mask & G_PHASE:
		_refresh_phase()
	if mask & G_SPEED:
		_refresh_speed()
	if mask & G_SANITY:
		_refresh_sanity()
	if mask & G_BUYOUT:
		_refresh_buyout()
	if mask & G_FLARE and flare_button != null:
		_refresh_flare()


func _refresh_purse() -> void:
	refresh_count += 1
	gold_label.text = "Money: " + TowerInfo.money(game.sim.state.gold)


func _refresh_relics() -> void:
	refresh_count += 1
	relics_label.text = relics_text(game.sim)
	relics_label.tooltip_text = relics_tooltip(game.sim)
	sell_relics_button.text = "Sell relics (+%s)" % TowerInfo.money(game.sim.relics_value())
	sell_relics_button.disabled = game.sim.can_sell_relics() != Simulation.CommandResult.OK


func _refresh_hp() -> void:
	refresh_count += 1
	hp_label.text = "Lighthouse %d/%d" % [game.sim.state.lighthouse_hp,
		game.sim.config.economy.lighthouse_hp]


## The phase line, "Light the lamp" (its luck comes from the same whole seconds as the day
## timer) and the night's luck. Arms the day timer for on_stepped while it is day.
func _refresh_phase() -> void:
	refresh_count += 1
	var s := game.sim.state
	phase_label.text = phase_text(s)
	call_wave_button.disabled = game.sim.can_call_wave() != Simulation.CommandResult.OK
	call_wave_button.text = "Light the lamp" if call_wave_button.disabled \
		else "Light the lamp (luck %s)" % luck_text(game.sim.early_night_luck())
	luck_label.visible = s.phase == SimState.Phase.WAVE and s.night_luck > 1.0
	luck_label.text = "Luck " + luck_text(s.night_luck)
	_day_secs = SimTime.whole_seconds(s.build_ticks_left)
	_day_active = s.phase == SimState.Phase.BUILD and s.outcome == SimState.Outcome.NONE


func _refresh_speed() -> void:
	refresh_count += 1
	speed_button.text = "x%d" % game.chosen_speed
	pause_button.text = "Resume" if game.paused else "Pause"


## The sanity bar (redraw; the torn animation runs only while Fraying or mad, owner Q3) and
## the madness line under it.
func _refresh_sanity() -> void:
	refresh_count += 1
	var s := game.sim.state
	sanity_bar.set_distorted(s.sanity_state >= SimState.SanityState.FRAYING)
	sanity_bar.redraw()
	hostile_label.visible = s.sanity_state == SimState.SanityState.MADNESS
	if hostile_label.visible:
		hostile_label.text = hostile_text(game.sim.config.sanity.madness)
		_place_hostile()


## Starts under the sanity bar, shifted left so it ends before the side panel. Also run
## when the sanity bar moves (the buyout button showing or hiding shifts the bar).
func _place_hostile() -> void:
	if hostile_label == null or not hostile_label.visible:
		return
	var board_right := board_rect().end.x
	var w := hostile_label.get_combined_minimum_size().x
	var x := minf(sanity_bar.get_global_rect().position.x - get_global_rect().position.x,
		board_right - w - 4.0)
	hostile_label.position = Vector2(x, board_rect().position.y + 2)


func _refresh_buyout() -> void:
	refresh_count += 1
	# Visible only while it could ever apply (sim query, LT-36): exit rule "buyout", in madness.
	buyout_button.visible = game.sim.buyout_applies()
	buyout_button.text = "Restore (%s)" % TowerInfo.money(game.sim.config.sanity.madness.buyout_cost)
	buyout_button.disabled = game.sim.can_buy_sanity() != Simulation.CommandResult.OK


func _on_speed_changed() -> void:
	_dirty |= G_SPEED
	flush()


## LT-30 §3.2: "Flare (2 oil)" while it can be fired, "Flare 12 s" during the cooldown,
## "Flare burning" while it burns; the oil stock beside it. The button shows at night only
## (a night command); the stock shows all the time. Arms the flare timer for on_stepped
## while a flare burns or cools down.
func _refresh_flare() -> void:
	refresh_count += 1
	var sim := game.sim
	var s := sim.state
	var night := s.phase == SimState.Phase.WAVE
	flare_button.visible = night
	oil_label.text = "Oil %d / %d" % [s.oil, sim.oil_cap()]
	var can := sim.can_fire_flare()
	flare_button.disabled = can != Simulation.CommandResult.OK
	# LT-69: the flare lights the whole map, for the current level's seconds.
	flare_button.tooltip_text = "Lights the whole map for %s s" % ConfigReader.fmt(
		sim.flare_seconds())
	if s.flare_ticks_left > 0:
		flare_button.text = "Flare burning"
	elif s.flare_cooldown_ticks > 0:
		flare_button.text = "Flare %d s" % _cooldown_secs(s)
	else:
		flare_button.text = "Flare (%d oil)" % sim.flare_cost_oil()
	_flare_shown = _flare_key()
	_flare_active = s.flare_ticks_left > 0 or s.flare_cooldown_ticks > 0
	var right := board_rect().end.x - MARGIN
	var y := board_rect().end.y + 4.0
	var w := flare_button.get_combined_minimum_size().x
	var lw := oil_label.get_combined_minimum_size().x
	flare_button.position = Vector2(right - w, y - footer.position.y)
	var label_right := right - w - 8.0 if night else right
	oil_label.position = Vector2(label_right - lw, y - footer.position.y + 4.0)


static func _cooldown_secs(s: SimState) -> int:
	return ceili(float(s.flare_cooldown_ticks) / SimTime.TICK_RATE)


## What the flare button shows from its timers: burning, cooldown seconds, fireable.
func _flare_key() -> Array:
	var s := game.sim.state
	return [s.flare_ticks_left > 0, _cooldown_secs(s), game.sim.can_fire_flare()]


## LT-44 / LT-38 P1 (LT-78 owner Q3): the wall-clock readouts, on the 0.25 s readout Timer,
## not every frame. The FPS string is rebuilt only when the integer changed.
func refresh_readouts() -> void:
	var fps := int(Engine.get_frames_per_second())
	if fps != _fps_shown:
		_fps_shown = fps
		fps_label.text = "FPS %d" % fps
	if frame_label != null:
		frame_label.text = game.frame_stats.text()


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


## The board in this layer's base pixels (BoardView.world_rect).
func board_rect() -> Rect2:
	return game.board.view.world_rect()


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
