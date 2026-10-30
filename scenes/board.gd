class_name Board
extends Node2D
## Grey-box renderer of the sim (LT-7): grid, path, start, lighthouse, towers, enemies
## (interpolated by the clock alpha), shots and hit flashes. Reads sim state only; a left
## click on the grid emits `cell_clicked` and the Game decides what it means.
## LT-14 sanity feedback drawn here: flicker on every enemy while Fraying / in Madness
## (the same for real and fake ones), a flickering phantom path, and astray shots with no
## hits drawn off-target into an empty spot. Its randomness is presentation-only.
## LT-25: each attack kind has its own look, chosen from the tower's current stats
## (shot_kind): rifle tracer, piercing harpoon, Elder Sign ward aura, Necronomicon dark
## wave; slow and damage-taken markers on enemies (enemy_markers). Nothing here tells a
## fake from a real enemy: every look depends only on SHOT fields and aura state.

signal cell_clicked(cell: Vector2i)

const CELL := 40.0  ## pixels per cell
const FLASH_SECONDS := 0.25

const COLOR_BUILDABLE := Color(0.30, 0.36, 0.28)
const COLOR_PATH := Color(0.55, 0.48, 0.36)
const COLOR_WATER := Color(0.12, 0.20, 0.32)
const COLOR_GRID := Color(0, 0, 0, 0.25)
const COLOR_START := Color(0.45, 0.20, 0.20)
const COLOR_LIGHTHOUSE := Color(0.95, 0.90, 0.55)
const COLOR_TOWER := Color(0.75, 0.75, 0.80)
const COLOR_ENEMY := Color(0.55, 0.85, 0.55)
const COLOR_HP_BACK := Color(0.2, 0, 0)
const COLOR_HP := Color(0.9, 0.2, 0.2)
const COLOR_DEATH := Color(1, 0.5, 0.2)
const COLOR_LEAK := Color(1, 0.1, 0.1)
const COLOR_DISSOLVE := Color(0.6, 0.6, 0.75)
const COLOR_DEBUG_FAKE := Color(1, 0, 1)  ## debug outline (--reveal-fakes), LT-12 §1
const COLOR_SELECT := Color(1, 1, 1, 0.8)
const COLOR_ASTRAY := Color(2.0, 1.5, 2.6)  ## over 1: stays bright under the darkness
const ASTRAY_SECONDS := 0.3
const ASTRAY_MIN_CELLS := 0.7  ## how far off the aim point an empty astray shot lands
const ASTRAY_MAX_CELLS := 1.4

## LT-25 attack looks (spec docs/design/LT-25-tower-attack-visuals.md). Colours use
## channels over 1 to stay bright under the world's CanvasModulate darkness.
const MAX_FX_PER_TOWER := 2  ## live attack effects per tower; a third replaces the oldest
const TRACER_COLOR := Color(2.2, 2.0, 1.2)
const TRACER_TRAVEL := 0.08  ## seconds for the dash to reach its end
const TRACER_MUZZLE := 0.05
const TRACER_SECONDS := 0.18  ## travel + hit spark
const TRACER_DASH_CELLS := 0.35
const TRACER_MISS_SIDE_CELLS := 0.4  ## a miss ends this far to the side of the aim point
const TRACER_MISS_PAST_CELLS := 0.5  ## and this far past it
const HARPOON_COLOR := Color(1.3, 1.6, 1.9)
const HARPOON_TRAVEL := 0.22
const HARPOON_SECONDS := 0.32  ## travel + rope fade
const HARPOON_FADE := 0.1
const HARPOON_TICK_SECONDS := 0.3  ## a cross tick stays this long on each pierced enemy
const WARD_COLOR := Color(0.9, 2.0, 1.6)
const WARD_IDLE_ALPHA := 0.25
const WARD_PULSE_LOW := 0.45  ## active ring pulses between this and WARD_ACTIVE_ALPHA
const WARD_ACTIVE_ALPHA := 0.6
const WARD_PULSE_HZ := 1.5
const WARD_TURN_SECONDS := 12.0
const WAVE_FILL := Color(0.05, 0, 0.08, 0.55)
const WAVE_RIM := Color(1.8, 0.6, 2.4)
const WAVE_TENDRIL := 0.15
const WAVE_BLAST := 0.45
const WAVE_SECONDS := 0.6  ## tendril + blast
const WAVE_START_CELLS := 0.2  ## blast radius at its start
const WAVE_FLASH := 0.2
const WAVE_FIZZLE_CELLS := 0.5  ## max ring of an empty astray wave (not aoe_radius)
const MARK_SLOW_CELLS := 0.34
const MARK_VULN := Color(1.6, 0.7, 2.2)

## LT-14 visual tunables.
@export var flicker_rate := 13.0  ## flicker steps per second
@export var phantom_seconds := Vector2(0.9, 2.2)  ## lifetime range of one phantom path
@export var phantom_cells := Vector2i(4, 9)  ## length range of a phantom path
@export var phantom_alpha := 0.7

var game: Game
var alpha := 0.0  ## render interpolation between the last two ticks
var selected_cell := Vector2i(-1, -1)  ## outlined while the picker or sell panel is open
var selected_range := 0.0  ## range ring (cells) for a selected tower; 0 = none
## Short-lived effects: {kind, from, to, ttl, ...} in cell units. Attack effects (LT-25)
## also carry tower, end, hits, hit_pos, miss, astray, dur (initial ttl), seed.
var effects: Array[Dictionary] = []
var _last_pos: Dictionary[int, Vector2] = {}  ## enemy id -> last drawn position (cells)
var phantom: Array[Vector2i] = []  ## LT-14: cells of the current phantom path (none Lucid)
var _phantom_ttl := 0.0
var _time := 0.0  ## seconds of effects time, drives the flicker
var _fx_rng := RandomNumberGenerator.new()  ## presentation-only; never the sim's RNG


func _ready() -> void:
	_fx_rng.randomize()


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell := cell_at((make_input_local(mb) as InputEventMouseButton).position)
	if game.sim.state.map.in_bounds(cell):
		get_viewport().set_input_as_handled()
		cell_clicked.emit(cell)


## Local pixel position -> grid cell (may be out of bounds).
func cell_at(local: Vector2) -> Vector2i:
	return Vector2i(floori(local.x / CELL), floori(local.y / CELL))


## Grid cell -> top-left in this node's local pixels.
func cell_origin(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL


func on_event(ev: SimEvent) -> void:
	match ev.type:
		SimEvent.Type.SHOT:
			var t := game.sim.tower_by_id(ev.id)
			if t != null:
				_add_attack_fx(_shot_fx(t, ev.data))
		SimEvent.Type.DIED:
			if _last_pos.has(ev.id):
				effects.append({"kind": "death", "from": _last_pos[ev.id], "ttl": FLASH_SECONDS})
		SimEvent.Type.FAKE_DISSOLVED:
			if _last_pos.has(ev.id):
				effects.append({"kind": "dissolve", "from": _last_pos[ev.id],
					"ttl": FLASH_SECONDS})
		SimEvent.Type.LEAKED:
			var lh := game.sim.state.map.lighthouse
			effects.append({"kind": "leak", "from": Vector2(lh) + Vector2(0.5, 0.5),
				"ttl": FLASH_SECONDS})


## LT-25 §1: the attack look from the tower's current stats (so upgrades and branches
## change it): pierce -> "harpoon", aoe_radius -> "wave", support level -> "aura",
## otherwise "tracer".
static func shot_kind(t: SimTower) -> String:
	var s := t.stats()
	if s.damage <= 0.0:
		return "aura"
	if s.effects.get("pierce", 0.0) > 0.0:
		return "harpoon"
	if s.effects.get("aoe_radius", 0.0) > 0.0:
		return "wave"
	return "tracer"


## LT-25 §2: the markers an enemy shows, from its per-tick aura state only.
static func enemy_markers(e: SimEnemy) -> PackedStringArray:
	var out := PackedStringArray()
	if e.speed_mult < 0.999:
		out.append("slow")
	if e.damage_taken_mult > 1.001:
		out.append("vuln")
	return out


## LT-25 §1.3: the ward ring's alpha: idle while no drawn enemy (`_last_pos`, real or fake
## alike) is inside its radius, pulsing between WARD_PULSE_LOW and WARD_ACTIVE_ALPHA while
## one is.
func ward_alpha(t: SimTower) -> float:
	var c := t.centre()
	var r := t.stats().range_cells
	for p: Vector2 in _last_pos.values():
		if p.distance_to(c) <= r:
			var k := 0.5 + 0.5 * sin(_time * TAU * WARD_PULSE_HZ)
			return lerpf(WARD_PULSE_LOW, WARD_ACTIVE_ALPHA, k)
	return WARD_IDLE_ALPHA


## The effect for one SHOT, or {} for a tower that draws no shot. Uses only the SHOT
## fields (to, hits, miss, astray) and the tower's stats, never what was hit (LT-12 §1).
func _shot_fx(t: SimTower, data: Dictionary) -> Dictionary:
	var kind := shot_kind(t)
	if kind == "aura":
		return {}
	var hits: Array = data.get("hits", [])
	var to: Vector2 = data["to"]
	var fx := {"kind": kind, "tower": t.id, "from": t.centre(), "to": to, "end": to,
		"hits": hits.duplicate(), "hit_pos": _hit_positions(hits),
		"miss": data.get("miss", false), "astray": data.get("astray", false),
		"seed": _fx_rng.randi()}
	if fx["astray"] and hits.is_empty():
		# An empty astray shot lands off its aim point (LT-14); a wave tower fizzles there
		# with a small ring, not a full blast (LT-25 §3).
		fx["kind"] = "astray"
		fx["aim"] = to
		fx["to"] = astray_end(to)
		fx["end"] = fx["to"]
		fx["ttl"] = ASTRAY_SECONDS
		if kind == "wave":
			fx["radius"] = WAVE_FIZZLE_CELLS
	else:
		match kind:
			"tracer":
				fx["ttl"] = TRACER_SECONDS
				if fx["miss"]:
					fx["end"] = _miss_end(fx["from"], to)
			"harpoon":
				fx["pass_t"] = _pass_times(fx["from"], to, fx["hit_pos"])
				var last := 0.0
				for p: float in fx["pass_t"]:
					last = maxf(last, p)
				fx["ttl"] = maxf(HARPOON_SECONDS, last + HARPOON_TICK_SECONDS)
			"wave":
				fx["radius"] = t.stats().effects.get("aoe_radius", 0.0)
				fx["ttl"] = WAVE_SECONDS
	fx["dur"] = fx["ttl"]
	return fx


## Appends an attack effect, keeping at most MAX_FX_PER_TOWER live ones per tower.
func _add_attack_fx(fx: Dictionary) -> void:
	if fx.is_empty():
		return
	var mine: Array[int] = []
	for i in effects.size():
		if effects[i].get("tower", -1) == fx["tower"]:
			mine.append(i)
	var drop := mine.size() - (MAX_FX_PER_TOWER - 1)
	for k in range(drop - 1, -1, -1):
		effects.remove_at(mine[k])
	effects.append(fx)


## Positions (cells) of the hit enemies at the shot's tick; real and fake alike.
func _hit_positions(hits: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for id: int in hits:
		var e := game.sim.enemy_by_id(id)
		if e != null:
			out.append(game.sim.enemy_position(e, 1.0))
		elif _last_pos.has(id):
			out.append(_last_pos[id])
	return out


## A missed tracer ends beside its aim point and runs past it (LT-25 §3).
func _miss_end(from: Vector2, aim: Vector2) -> Vector2:
	var dir := (aim - from).normalized()
	var side := 1.0 if _fx_rng.randf() < 0.5 else -1.0
	return aim + dir.orthogonal() * side * TRACER_MISS_SIDE_CELLS + dir * TRACER_MISS_PAST_CELLS


## Seconds after the shot at which the harpoon head passes each hit position.
func _pass_times(from: Vector2, to: Vector2, pos: Array[Vector2]) -> Array[float]:
	var out: Array[float] = []
	var d := to - from
	var l2 := maxf(d.length_squared(), 0.0001)
	for p in pos:
		out.append(clampf((p - from).dot(d) / l2, 0.0, 1.0) * HARPOON_TRAVEL)
	return out


## An empty astray shot (LT-13 "hits an empty cell") lands next to its aim point, on a
## spot no drawn enemy covers, so it reads as "went astray". Presentation RNG only.
func astray_end(aim: Vector2) -> Vector2:
	var best := aim
	for attempt in 8:
		var p: Vector2 = aim + Vector2.from_angle(_fx_rng.randf() * TAU) \
			* _fx_rng.randf_range(ASTRAY_MIN_CELLS, ASTRAY_MAX_CELLS)
		best = p
		var clear := true
		for q: Vector2 in _last_pos.values():
			if q.distance_to(p) < 0.6:
				clear = false
				break
		if clear:
			break
	return best


func tick_effects(delta: float) -> void:
	_time += delta
	for fx in effects:
		fx["ttl"] -= delta
	effects = effects.filter(func(fx: Dictionary) -> bool: return fx["ttl"] > 0.0)
	_tick_phantom(delta)


func _flicker_strength() -> float:
	return game.sanity_fx.flicker if game != null and game.sanity_fx != null else 0.0


## While Fraying / in Madness a phantom stretch of path appears off the real one, flickers
## and moves elsewhere every second or two (GDD §5.3 "phantom path flickers on screen").
func _tick_phantom(delta: float) -> void:
	if _flicker_strength() <= 0.0:
		phantom.clear()
		return
	_phantom_ttl -= delta
	if _phantom_ttl <= 0.0 or phantom.is_empty():
		_phantom_ttl = _fx_rng.randf_range(phantom_seconds.x, phantom_seconds.y)
		phantom = _new_phantom()


## A random walk that leaves the real path sideways and wanders over non-path cells.
func _new_phantom() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s := game.sim.state
	var m := s.map
	var path_cells: Array[Vector2i] = []
	for y in m.height:
		for x in m.width:
			if m.kind_at(Vector2i(x, y)) == MapDef.Kind.PATH:
				path_cells.append(Vector2i(x, y))
	if path_cells.is_empty():
		return out
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var cur: Vector2i = path_cells[_fx_rng.randi_range(0, path_cells.size() - 1)]
	var dir: Vector2i = dirs[_fx_rng.randi_range(0, 3)]
	var length := _fx_rng.randi_range(phantom_cells.x, phantom_cells.y)
	for step in length * 3:
		if out.size() >= length:
			break
		if _fx_rng.randf() < 0.3:
			dir = dirs[_fx_rng.randi_range(0, 3)]
		var nxt := cur + dir
		if not m.in_bounds(nxt) or m.kind_at(nxt) == MapDef.Kind.PATH \
				or s.tower_at.has(nxt) or out.has(nxt):
			dir = dirs[_fx_rng.randi_range(0, 3)]
			continue
		out.append(nxt)
		cur = nxt
	return out


## 0..1 dip for one flicker step; seeded by step and `key`, so each enemy twitches on
## its own beat. Uses only the id and time: real and fake enemies flicker alike.
func _flicker_dip(key: int) -> float:
	var step := floori(_time * flicker_rate)
	var h := absf(sin(float(step) * 12.9898 + float(key) * 78.233) * 43758.5453)
	h -= floorf(h)
	return 1.0 if h > 0.72 else h * 0.35


func _draw() -> void:
	if game == null or game.sim == null:
		return
	var s := game.sim.state
	_draw_map(s.map)
	_draw_phantom()
	_draw_auras(s)
	for t in s.towers:
		_draw_tower(t)
	_draw_enemies(s)
	_draw_effects()
	if game.sim.state.map.in_bounds(selected_cell):
		draw_rect(Rect2(cell_origin(selected_cell), Vector2(CELL, CELL)), COLOR_SELECT, false, 2.0)
		if selected_range > 0.0:
			draw_arc((Vector2(selected_cell) + Vector2(0.5, 0.5)) * CELL, selected_range * CELL,
				0, TAU, 48, COLOR_SELECT, 1.0)


func _draw_map(m: MapDef) -> void:
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			var color := COLOR_WATER
			match m.kind_at(c):
				MapDef.Kind.BUILDABLE:
					color = COLOR_BUILDABLE
				MapDef.Kind.PATH:
					color = COLOR_PATH
			var r := Rect2(cell_origin(c), Vector2(CELL, CELL))
			draw_rect(r, color)
			draw_rect(r, COLOR_GRID, false, 1.0)
	draw_rect(Rect2(cell_origin(m.spawn), Vector2(CELL, CELL)).grow(-4), COLOR_START)
	var lh := Rect2(cell_origin(m.lighthouse), Vector2(CELL, CELL)).grow(-4)
	draw_rect(lh, COLOR_LIGHTHOUSE)
	draw_string(ThemeDB.fallback_font, lh.position + Vector2(9, 24), "L",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.BLACK)


func _draw_phantom() -> void:
	if phantom.is_empty():
		return
	var a := phantom_alpha * (1.0 - _flicker_dip(-1)) * clampf(_flicker_strength() / 0.6, 0.0, 1.0)
	if a <= 0.02:
		return
	var c := COLOR_PATH
	c.a = a
	for cell in phantom:
		draw_rect(Rect2(cell_origin(cell), Vector2(CELL, CELL)).grow(-2), c)


## The colour that links a tower to its attack look (LT-25 §1).
static func attack_color(kind: String) -> Color:
	match kind:
		"tracer":
			return TRACER_COLOR
		"harpoon":
			return HARPOON_COLOR
		"wave":
			return WAVE_RIM
		"aura":
			return WARD_COLOR
	return Color.BLACK


func _draw_tower(t: SimTower) -> void:
	var r := Rect2(cell_origin(t.cell), Vector2(CELL, CELL)).grow(-6)
	var c := attack_color(shot_kind(t))
	draw_rect(r, COLOR_TOWER)
	draw_rect(r, c, false, 2.0)
	draw_string(ThemeDB.fallback_font, r.position + Vector2(8, 20), t.def.name.left(1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c)


## Elder Sign wards (LT-25 §1.3): a faint ring at the aura radius with 5 slowly turning
## dashes; brighter and pulsing while a drawn enemy is inside.
func _draw_auras(s: SimState) -> void:
	for t in s.towers:
		if shot_kind(t) != "aura":
			continue
		var c := t.centre() * CELL
		var r := t.stats().range_cells * CELL
		var a := ward_alpha(t)
		draw_arc(c, r, 0, TAU, 64, Color(WARD_COLOR, a), 2.0)
		var rot := _time * TAU / WARD_TURN_SECONDS
		for i in 5:
			var st := rot + i * TAU / 5.0
			draw_arc(c, r, st, st + 0.22, 6, Color(WARD_COLOR, minf(1.0, a + 0.15)), 4.0)


func _draw_enemies(s: SimState) -> void:
	_last_pos.clear()
	var fl := _flicker_strength()
	for e in s.enemies:
		if not e.is_live():
			continue
		var p := game.sim.enemy_position(e, alpha)
		_last_pos[e.id] = p
		var px := p * CELL
		var color := COLOR_ENEMY
		if e.revealed:
			color.a = 0.35
		var dip := fl * _flicker_dip(e.id) if fl > 0.0 else 0.0
		color.a *= 1.0 - dip
		if dip > 0.5:  # a torn frame: a faint double a few pixels off
			var ghost := color
			ghost.a = 0.35
			draw_circle(px + Vector2(CELL * 0.15, 0), CELL * 0.25, ghost)
		var marks := enemy_markers(e)
		if marks.has("slow"):  # ground ring under the body
			var sc := Color(WARD_COLOR, color.a)
			for i in 6:
				var st := i * TAU / 6.0
				draw_arc(px, CELL * MARK_SLOW_CELLS, st, st + TAU / 12.0, 4, sc, 2.0)
		draw_circle(px, CELL * 0.25, color)
		if marks.has("vuln"):  # body outline
			draw_arc(px, CELL * 0.25, 0, TAU, 24, Color(MARK_VULN, color.a), 2.0)
		if game.sim.debug_is_fake(e):
			draw_arc(px, CELL * 0.3, 0, TAU, 24, COLOR_DEBUG_FAKE, 2.0)
		var w := CELL * 0.6
		var bar := Rect2(px + Vector2(-w * 0.5, -CELL * 0.4), Vector2(w, 4))
		draw_rect(bar, Color(COLOR_HP_BACK, 1.0 - dip))
		bar.size.x = w * clampf(e.hp / e.max_hp, 0.0, 1.0)
		draw_rect(bar, Color(COLOR_HP, 1.0 - dip))


func _draw_effects() -> void:
	for fx in effects:
		match fx["kind"]:
			"tracer":
				_draw_tracer(fx)
			"harpoon":
				_draw_harpoon(fx)
			"wave":
				_draw_wave(fx)
			"astray":
				_draw_astray(fx)
			"death":
				draw_circle(fx["from"] * CELL, CELL * 0.35, COLOR_DEATH)
			"dissolve":
				draw_arc(fx["from"] * CELL, CELL * 0.35, 0, TAU, 24, COLOR_DISSOLVE, 2.0)
			"leak":
				draw_rect(Rect2((fx["from"] - Vector2(0.5, 0.5)) * CELL, Vector2(CELL, CELL)),
					COLOR_LEAK, false, 4.0)


## A wavering bolt from the tower to an empty spot, ending in a small fading ring; from a
## wave tower the ring is a fizzle growing to `radius` (LT-25 §3).
func _draw_astray(fx: Dictionary) -> void:
	var b: Vector2 = fx["to"] * CELL
	var fade := clampf(fx["ttl"] / ASTRAY_SECONDS, 0.0, 1.0)
	var c := Color(COLOR_ASTRAY, fade)
	draw_polyline(_waver_points(fx["from"] * CELL, b, fx["seed"]), c, 3.0)
	if fx.has("radius"):
		draw_arc(b, CELL * fx["radius"] * (0.3 + 0.7 * (1.0 - fade)), 0, TAU, 20, c, 2.0)
	else:
		draw_arc(b, CELL * (0.4 - 0.2 * fade), 0, TAU, 20, c, 3.0)


## The LT-14 astray waver (5 px, 3 half-waves) from a to b (pixels), phase from `key`.
func _waver_points(a: Vector2, b: Vector2, key: int) -> PackedVector2Array:
	return _wave_points(a, b, float(key % 1000) * 0.01, 3.0, 5.0, 8)


## A polyline from a to b bent by `half_waves` half-sines of `amp` px, pinned at both ends.
func _wave_points(a: Vector2, b: Vector2, phase: float, half_waves: float, amp: float,
		segs: int) -> PackedVector2Array:
	var n := (b - a).orthogonal().normalized()
	var pts := PackedVector2Array()
	for i in segs + 1:
		var k := float(i) / segs
		var off := sin(k * PI * half_waves + phase) * amp * sin(k * PI)
		pts.append(a.lerp(b, k) + n * off)
	return pts


func _elapsed(fx: Dictionary) -> float:
	return fx["dur"] - fx["ttl"]


## Rifleman (LT-25 §1.1): muzzle dot, a short dash racing to `end`, then a spark of 4 rays
## on each hit enemy. A miss ends off target with no spark.
func _draw_tracer(fx: Dictionary) -> void:
	var el := _elapsed(fx)
	var a: Vector2 = fx["from"] * CELL
	var b: Vector2 = fx["end"] * CELL
	var dir := (b - a).normalized()
	if el < TRACER_MUZZLE:
		draw_circle(a, CELL * 0.12, TRACER_COLOR)
	if el < TRACER_TRAVEL:
		var head := a.lerp(b, clampf(el / TRACER_TRAVEL, 0.0, 1.0))
		var tail := head - dir * minf(CELL * TRACER_DASH_CELLS, head.distance_to(a))
		draw_line(tail, head, TRACER_COLOR, 2.0)
	elif not fx["miss"]:
		var fade := clampf(1.0 - (el - TRACER_TRAVEL) / (TRACER_SECONDS - TRACER_TRAVEL),
			0.0, 1.0)
		for p: Vector2 in fx["hit_pos"]:
			for i in 4:
				var v := Vector2.from_angle(PI * 0.25 + i * PI * 0.5)
				draw_line(p * CELL + v * CELL * 0.05, p * CELL + v * CELL * 0.2,
					Color(TRACER_COLOR, fade), 2.0)


## Harpooner (LT-25 §1.2): a head flying the whole line on a rope, a cross tick on each
## pierced enemy as it passes. A miss leaves no ticks and the head drops at the end.
func _draw_harpoon(fx: Dictionary) -> void:
	var el := _elapsed(fx)
	var a: Vector2 = fx["from"] * CELL
	var b: Vector2 = fx["to"] * CELL
	var dir := (b - a).normalized()
	var fade := clampf(1.0 - (el - (HARPOON_SECONDS - HARPOON_FADE)) / HARPOON_FADE, 0.0, 1.0)
	if fade > 0.0:
		var head := a.lerp(b, clampf(el / HARPOON_TRAVEL, 0.0, 1.0))
		if fx["miss"] and el > HARPOON_TRAVEL:
			head += Vector2(0, CELL * 0.3 * (1.0 - fade))
		var base := head - dir * CELL * 0.3
		draw_line(a, base, Color(HARPOON_COLOR, 0.6 * fade), 1.0)
		var w := dir.orthogonal() * CELL * 0.09
		draw_colored_polygon(PackedVector2Array([head, base + w, base - w]),
			Color(HARPOON_COLOR, fade))
	var pos: Array = fx["hit_pos"]
	var passes: Array = fx.get("pass_t", [])
	for i in mini(pos.size(), passes.size()):
		var since: float = el - passes[i]
		if since < 0.0 or since >= HARPOON_TICK_SECONDS:
			continue
		var p: Vector2 = pos[i] * CELL
		var c := Color(HARPOON_COLOR, 1.0 - since / HARPOON_TICK_SECONDS * 0.6)
		var h := CELL * 0.125
		draw_line(p + Vector2(-h, -h), p + Vector2(h, h), c, 3.0)
		draw_line(p + Vector2(-h, h), p + Vector2(h, -h), c, 3.0)


## Necronomicon (LT-25 §1.4): an S-bent tendril to `to`, then a dark disc with a bright rim
## growing to `radius` and a flash on each hit enemy. Astray: wavering tendril, astray rim.
func _draw_wave(fx: Dictionary) -> void:
	var el := _elapsed(fx)
	var a: Vector2 = fx["from"] * CELL
	var b: Vector2 = fx["to"] * CELL
	var rim := COLOR_ASTRAY if fx["astray"] else WAVE_RIM
	if el < WAVE_TENDRIL + 0.05:
		var pts := _waver_points(a, b, fx["seed"]) if fx["astray"] \
			else _wave_points(a, b, 0.0, 2.0, 6.0, 12)
		var ta := clampf(1.0 - (el - WAVE_TENDRIL) / 0.05, 0.0, 1.0)
		draw_polyline(pts, Color(rim, ta), 3.0)
	var be := el - WAVE_TENDRIL
	if be < 0.0:
		return
	var k := clampf(be / WAVE_BLAST, 0.0, 1.0)
	var r := lerpf(WAVE_START_CELLS, fx["radius"], k) * CELL
	draw_circle(b, r, Color(WAVE_FILL, WAVE_FILL.a * (1.0 - k)))
	draw_arc(b, r, 0, TAU, 48, Color(rim, 1.0 - k * k), 3.0)
	if be < WAVE_FLASH:
		for p: Vector2 in fx["hit_pos"]:
			draw_arc(p * CELL, CELL * 0.3, 0, TAU, 20, Color(rim, 1.0 - be / WAVE_FLASH), 2.0)
