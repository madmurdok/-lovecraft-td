class_name SanityBar
extends Control
## LT-14 HUD sanity bar (GDD §9): fill = sanity / max, a mark at each threshold boundary
## from sanity.json, the value and state name on top. While Fraying (and in Madness) the
## bar is drawn distorted: torn slices, a wobbling fill edge and glitch stripes. Only the
## drawing moves; the control's rect never does. Reads sim state, never changes it.

const SIZE := Vector2(190, 26)
const STATE_NAMES: PackedStringArray = ["Lucid", "Whispers", "Fraying", "Madness"]
const COLOR_BACK := Color(0.05, 0.05, 0.07)
const COLOR_FRAME := Color(0.55, 0.55, 0.6)
const COLOR_MARK := Color(0.9, 0.9, 0.95, 0.85)
const STATE_COLORS: Array[Color] = [
	Color(0.55, 0.75, 0.95),  # Lucid
	Color(0.80, 0.78, 0.45),  # Whispers
	Color(0.85, 0.45, 0.20),  # Fraying
	Color(0.65, 0.05, 0.10),  # Madness
]
const SLICES := 12
## Visual tunables for the Fraying look.
@export var tear_px := 3.0  ## vertical slice offset
@export var edge_wobble_px := 9.0  ## fill edge wobble
@export var glitch_rate := 9.0  ## new glitch pattern per second

var game: Game
var _time := 0.0
var _rng := RandomNumberGenerator.new()  ## presentation-only


func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Sanity as a 0..1 fill.
func fill_ratio() -> float:
	var s := game.sim.state
	return clampf(s.sanity / game.sim.config.sanity.max_sanity, 0.0, 1.0)


## Threshold boundaries to mark, as 0..1 positions (each state's `min`, except 0).
func mark_ratios() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var cfg := game.sim.config.sanity
	for st in SanityConfig.STATES:
		var m := cfg.thresholds[st].min_sanity / cfg.max_sanity
		if m > 0.02:
			out.append(m)
	return out


func _draw() -> void:
	if game == null or game.sim == null:
		return
	var s := game.sim.state
	var st := int(s.sanity_state)
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, COLOR_BACK)
	var fill := r.size.x * fill_ratio()
	var color := STATE_COLORS[st]
	var torn := st >= SimState.SanityState.FRAYING
	if torn:
		_draw_torn_fill(r, fill, color, st == SimState.SanityState.MADNESS)
	else:
		draw_rect(Rect2(r.position, Vector2(fill, r.size.y)), color)
	for m in mark_ratios():
		var x := r.size.x * m
		draw_line(Vector2(x, -3), Vector2(x, r.size.y + 3), COLOR_MARK, 2.0)
	draw_rect(r, COLOR_FRAME, false, 1.0)
	var text := "Sanity %d  %s" % [roundi(s.sanity), STATE_NAMES[st]]
	var font := ThemeDB.fallback_font
	var pos := Vector2(6, r.size.y * 0.5 + 5)
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


## Fraying / Madness: the fill is drawn as vertical slices that tear up and down, its end
## wobbles, and a few glitch stripes cross it. Seeded per glitch step: steady for ~0.1 s.
func _draw_torn_fill(r: Rect2, fill: float, color: Color, mad: bool) -> void:
	_rng.seed = int(floor(_time * glitch_rate)) + 7919
	var strength := 1.6 if mad else 1.0
	var edge := clampf(fill + _rng.randf_range(-1.0, 1.0) * edge_wobble_px * strength,
		0.0, r.size.x)
	var w := r.size.x / SLICES
	for i in SLICES:
		var x0 := i * w
		if x0 >= edge:
			break
		var dy := _rng.randf_range(-1.0, 1.0) * tear_px * strength
		var c := color
		if _rng.randf() < 0.18:
			c = c.lightened(0.35)
		draw_rect(Rect2(Vector2(x0, dy), Vector2(minf(w, edge - x0), r.size.y)), c)
	var stripes := 4 if mad else 2
	for i in stripes:
		var y := _rng.randf_range(0.0, r.size.y)
		var gx := _rng.randf_range(0.0, r.size.x * 0.8)
		draw_rect(Rect2(Vector2(gx, y), Vector2(_rng.randf_range(10, 50), 2)),
			Color(0.9, 0.1, 0.3, 0.7) if mad else Color(0.3, 0.9, 0.8, 0.6))
