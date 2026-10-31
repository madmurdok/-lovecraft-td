class_name RelicTokens
extends Node2D
## LT-27 §4: relic tokens on the UI layer (above the darkness, so they read at night). On
## RELIC_DROPPED a kind-coloured token pops at the kill, hangs HANG_SECONDS, then flies to
## the HUD relic counter so that it lands at the event's arrive_tick: its progress comes
## from `state.tick` and the clock's alpha, so x2 speed and pause stay in sync with the sim.
## RELICS_CHANGED for that token (it was credited) removes it; RELIC_VANISHED fades and
## shrinks it where it is. A star-stone drop gets a larger glint and a brief chime. Every
## token is drawn the same way until its own events arrive: visual only, reads sim state
## and events, never changes them.

const STAR_STONE := "star_stone"  ## the rare kind: larger glint, chime, end-screen count
const KIND_COLORS := {
	"bone": Color(0.95, 0.93, 0.86),
	"amber": Color(1.0, 0.62, 0.18),
	"idol": Color(0.38, 0.85, 0.45),
	STAR_STONE: Color(0.72, 0.86, 1.0),
}
const COLOR_DEFAULT := Color(0.9, 0.9, 0.9)  ## a kind without a colour here
const COLOR_OUTLINE := Color(0.05, 0.04, 0.03, 0.9)
const HANG_SECONDS := 0.3  ## the pop at the kill before the flight
const RADIUS := 6.0  ## px
const STAR_RADIUS := 9.0
const POP_SCALE := 0.5  ## extra size at the top of the pop
const ARC_PX := 40.0  ## how far the flight bows upward at its middle
const DISSOLVE_SECONDS := 0.25  ## same length as the board's FAKE_DISSOLVED ring
const LATE_TICKS := 30  ## a token still flying this long after arrive_tick is dropped
const MIX_RATE := 22050
const CHIME_SECONDS := 0.7

static var _chime: AudioStreamWAV

var game: Game
## token id -> {kind, from (px, this layer), drop_tick, arrive_tick, fade (-1 = flying,
## else seconds left of the dissolve), at (px, frozen when the dissolve starts)}
var tokens: Dictionary[int, Dictionary] = {}
var _time := 0.0  ## presentation seconds, drives the glint
var _player: AudioStreamPlayer


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		_player = AudioStreamPlayer.new()
		_player.name = "Chime"
		_player.stream = chime_stream()
		_player.volume_db = -8.0
		add_child(_player)


func on_event(ev: SimEvent) -> void:
	match ev.type:
		SimEvent.Type.RELIC_DROPPED:
			var kind: String = ev.data.get("kind", "")
			tokens[ev.id] = {"kind": kind, "from": board_to_layer(ev.data.get("at", Vector2.ZERO)),
				"drop_tick": ev.tick, "arrive_tick": int(ev.data.get("arrive_tick", ev.tick)),
				"fade": -1.0, "at": Vector2.ZERO}
			if kind == STAR_STONE and _player != null:
				_player.play()
		SimEvent.Type.RELIC_VANISHED:
			_dissolve(ev.id)
		SimEvent.Type.RELICS_CHANGED:
			if ev.data.has("token"):
				tokens.erase(int(ev.data["token"]))  # landed on the counter
		SimEvent.Type.OUTCOME:
			for id: int in tokens.keys():
				_dissolve(id)


## Per frame: advances dissolves and redraws (flight positions come from the sim clock).
func tick(delta: float) -> void:
	_time += delta
	for id: int in tokens.keys():
		var tok := tokens[id]
		if tok["fade"] >= 0.0:
			tok["fade"] -= delta
			if tok["fade"] <= 0.0:
				tokens.erase(id)
		elif game.sim.state.tick > tok["arrive_tick"] + LATE_TICKS:
			tokens.erase(id)  # its credit event never came (not in normal play)
	queue_redraw()


## A sim position in cells -> this layer's pixels (the board's top-left plus cells).
func board_to_layer(cells: Vector2) -> Vector2:
	return game.board.global_position + cells * Board.CELL


## Where tokens land: beside the HUD relic counter (LT-28: its centre hid the digits).
func target() -> Vector2:
	return game.hud.relic_landing()


## 0 at the drop, 1 at arrive_tick, from the sim tick plus the clock's alpha.
func progress(tok: Dictionary) -> float:
	var span: int = tok["arrive_tick"] - tok["drop_tick"]
	if span <= 0:
		return 1.0
	var now := float(game.sim.state.tick) + game.clock.alpha()
	return clampf((now - tok["drop_tick"]) / span, 0.0, 1.0)


## Position and size factor of a flying token: a pop at the kill for HANG_SECONDS, then an
## eased, slightly arched flight to target().
func pose(tok: Dictionary) -> Array:
	var p := progress(tok)
	var span_s := float(tok["arrive_tick"] - tok["drop_tick"]) / SimTime.TICK_RATE
	var hang := clampf(HANG_SECONDS / span_s, 0.0, 0.9) if span_s > 0.0 else 0.0
	var from: Vector2 = tok["from"]
	if p < hang:
		var k := p / hang
		return [from + Vector2(0, -6.0 * sin(k * PI)), 1.0 + POP_SCALE * sin(k * PI)]
	var f := smoothstep(0.0, 1.0, (p - hang) / (1.0 - hang))
	var pos := from.lerp(target(), f) + Vector2(0, -ARC_PX * sin(f * PI))
	return [pos, 1.0 - 0.3 * f]


func _dissolve(id: int) -> void:
	if not tokens.has(id) or tokens[id]["fade"] >= 0.0:
		return
	tokens[id]["at"] = pose(tokens[id])[0]
	tokens[id]["fade"] = DISSOLVE_SECONDS


func _draw() -> void:
	for id: int in tokens:
		var tok := tokens[id]
		var kind: String = tok["kind"]
		var color: Color = KIND_COLORS.get(kind, COLOR_DEFAULT)
		var r := STAR_RADIUS if kind == STAR_STONE else RADIUS
		var pos: Vector2
		var sz := 1.0
		var a := 1.0
		if tok["fade"] >= 0.0:
			var k: float = clampf(tok["fade"] / DISSOLVE_SECONDS, 0.0, 1.0)
			pos = tok["at"]
			sz = k
			a = k
			draw_arc(pos, r * (2.2 - k), 0, TAU, 20, Color(Board.COLOR_DISSOLVE, k), 2.0)
		else:
			var pz := pose(tok)
			pos = pz[0]
			sz = pz[1]
		_draw_token(pos, r * sz, Color(color, a), kind == STAR_STONE)


func _draw_token(pos: Vector2, r: float, color: Color, star: bool) -> void:
	if r <= 0.2:
		return
	draw_circle(pos, r + 1.5, Color(COLOR_OUTLINE, COLOR_OUTLINE.a * color.a))
	draw_circle(pos, r, color)
	draw_circle(pos + Vector2(-r, -r) * 0.3, r * 0.35, Color(1, 1, 1, 0.55 * color.a))
	if star:
		# Four-pointed glint, slowly turning and pulsing.
		var ray := r * (2.2 + 0.4 * sin(_time * 6.0))
		for i in 4:
			var d := Vector2.from_angle(_time * 0.8 + i * PI * 0.5)
			draw_line(pos - d * ray * 0.25, pos + d * ray, Color(1, 1, 1, 0.85 * color.a), 2.0)


## A short two-note bell, generated once (no asset file).
static func chime_stream() -> AudioStreamWAV:
	if _chime == null:
		var n := int(MIX_RATE * CHIME_SECONDS)
		var data := PackedByteArray()
		data.resize(n * 2)
		for i in n:
			var t := float(i) / MIX_RATE
			var second := 1.0 if t > 0.12 else 0.0
			var v := sin(TAU * 1318.5 * t) * exp(-t * 6.0) * 0.5 \
				+ sin(TAU * 1975.5 * t) * exp(-(t - 0.12) * 5.0) * 0.4 * second
			data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
		_chime = AudioStreamWAV.new()
		_chime.format = AudioStreamWAV.FORMAT_16_BITS
		_chime.mix_rate = MIX_RATE
		_chime.stereo = false
		_chime.data = data
	return _chime
