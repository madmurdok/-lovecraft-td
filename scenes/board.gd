class_name Board
extends Node2D
## Grey-box renderer of the sim (LT-7): grid, path, start, lighthouse, towers, enemies
## (interpolated by the clock alpha), shots and hit flashes. Reads sim state only; a left
## click on the grid emits `cell_clicked` and the Game decides what it means.
## LT-14 sanity feedback drawn here: flicker on every enemy while Fraying / in Madness
## (the same for real and fake ones), a flickering phantom path, and astray shots with no
## hits drawn off-target into an empty spot. Its randomness is presentation-only.

signal cell_clicked(cell: Vector2i)

const CELL := 40.0  ## pixels per cell
const SHOT_SECONDS := 0.12
const FLASH_SECONDS := 0.25

const COLOR_BUILDABLE := Color(0.30, 0.36, 0.28)
const COLOR_PATH := Color(0.55, 0.48, 0.36)
const COLOR_WATER := Color(0.12, 0.20, 0.32)
const COLOR_GRID := Color(0, 0, 0, 0.25)
const COLOR_START := Color(0.45, 0.20, 0.20)
const COLOR_LIGHTHOUSE := Color(0.95, 0.90, 0.55)
const COLOR_TOWER := Color(0.75, 0.75, 0.80)
const COLOR_ENEMY := Color(0.55, 0.85, 0.55)
const COLOR_ENEMY_MAD := Color(1.0, 0.25, 0.15)  ## LT-23 Q10: hostile tint in madness
const COLOR_ENEMY_OUTLINE := Color(0.03, 0.0, 0.02)  ## LT-23 Q10: dark outline in madness
const COLOR_HP_BACK := Color(0.2, 0, 0)
const COLOR_HP := Color(0.9, 0.2, 0.2)
const COLOR_SHOT := Color(1, 1, 0.7)
const COLOR_DEATH := Color(1, 0.5, 0.2)
const COLOR_LEAK := Color(1, 0.1, 0.1)
const COLOR_DISSOLVE := Color(0.6, 0.6, 0.75)
const COLOR_DEBUG_FAKE := Color(1, 0, 1)  ## debug outline (--reveal-fakes), LT-12 §1
const COLOR_SELECT := Color(1, 1, 1, 0.8)
const COLOR_ASTRAY := Color(2.0, 1.5, 2.6)  ## over 1: stays bright under the darkness
const ASTRAY_SECONDS := 0.3
const ASTRAY_MIN_CELLS := 0.7  ## how far off the aim point an empty astray shot lands
const ASTRAY_MAX_CELLS := 1.4

## LT-14 visual tunables.
@export var flicker_rate := 13.0  ## flicker steps per second
@export var phantom_seconds := Vector2(0.9, 2.2)  ## lifetime range of one phantom path
@export var phantom_cells := Vector2i(4, 9)  ## length range of a phantom path
@export var phantom_alpha := 0.7

var game: Game
var alpha := 0.0  ## render interpolation between the last two ticks
var selected_cell := Vector2i(-1, -1)  ## outlined while the build or tower view is open
var selected_range := 0.0  ## range ring (cells) for a selected tower; 0 = none
## Short-lived effects: {kind, from, to, ttl} in cell units.
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
			if t == null:
				return
			var hits: Array = ev.data.get("hits", [])
			if ev.data.get("astray", false) and hits.is_empty():
				effects.append({"kind": "astray", "from": t.centre(),
					"to": astray_end(ev.data["to"]), "ttl": ASTRAY_SECONDS,
					"seed": _fx_rng.randi()})
			else:
				effects.append({"kind": "shot", "from": t.centre(), "to": ev.data["to"],
					"ttl": SHOT_SECONDS})
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


func _draw_tower(t: SimTower) -> void:
	var r := Rect2(cell_origin(t.cell), Vector2(CELL, CELL)).grow(-6)
	draw_rect(r, COLOR_TOWER)
	draw_rect(r, Color.BLACK, false, 1.0)
	draw_string(ThemeDB.fallback_font, r.position + Vector2(8, 20), t.def.name.left(1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
	# LT-24 level mark: one pip per level along the bottom, the branch letter at L3.
	for i in t.level + 1:
		draw_rect(Rect2(r.position + Vector2(3 + i * 6, r.size.y - 6), Vector2(4, 4)), Color.BLACK)
	if not t.branch.is_empty():
		draw_string(ThemeDB.fallback_font, r.position + Vector2(r.size.x - 9, 11), t.branch,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)


func _draw_enemies(s: SimState) -> void:
	_last_pos.clear()
	var fl := _flicker_strength()
	# LT-23 Q10: the smoothed madness grade tints and outlines every enemy alike.
	var mad := game.sanity_fx.madness if game.sanity_fx != null else 0.0
	for e in s.enemies:
		if not e.is_live():
			continue
		var p := game.sim.enemy_position(e, alpha)
		_last_pos[e.id] = p
		var px := p * CELL
		var color := COLOR_ENEMY.lerp(COLOR_ENEMY_MAD, mad)
		if e.revealed:
			color.a = 0.35
		var dip := fl * _flicker_dip(e.id) if fl > 0.0 else 0.0
		color.a *= 1.0 - dip
		if dip > 0.5:  # a torn frame: a faint double a few pixels off
			var ghost := color
			ghost.a = 0.35
			draw_circle(px + Vector2(CELL * 0.15, 0), CELL * 0.25, ghost)
		draw_circle(px, CELL * 0.25, color)
		if mad > 0.0:
			draw_arc(px, CELL * 0.25, 0, TAU, 24, Color(COLOR_ENEMY_OUTLINE, color.a * mad), 3.0)
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
			"shot":
				draw_line(fx["from"] * CELL, fx["to"] * CELL, COLOR_SHOT, 2.0)
			"astray":
				_draw_astray(fx)
			"death":
				draw_circle(fx["from"] * CELL, CELL * 0.35, COLOR_DEATH)
			"dissolve":
				draw_arc(fx["from"] * CELL, CELL * 0.35, 0, TAU, 24, COLOR_DISSOLVE, 2.0)
			"leak":
				draw_rect(Rect2((fx["from"] - Vector2(0.5, 0.5)) * CELL, Vector2(CELL, CELL)),
					COLOR_LEAK, false, 4.0)


## A wavering bolt from the tower to an empty spot, ending in a small fading ring.
func _draw_astray(fx: Dictionary) -> void:
	var a: Vector2 = fx["from"] * CELL
	var b: Vector2 = fx["to"] * CELL
	var n := (b - a).orthogonal().normalized()
	var pts := PackedVector2Array()
	var segs := 8
	var phase := float(fx["seed"] % 1000) * 0.01
	for i in segs + 1:
		var k := float(i) / segs
		var off := sin(k * PI * 3.0 + phase) * 5.0 * sin(k * PI)
		pts.append(a.lerp(b, k) + n * off)
	var fade := clampf(fx["ttl"] / ASTRAY_SECONDS, 0.0, 1.0)
	draw_polyline(pts, Color(COLOR_ASTRAY, fade), 3.0)
	draw_arc(b, CELL * (0.4 - 0.2 * fade), 0, TAU, 20, Color(COLOR_ASTRAY, fade), 3.0)
