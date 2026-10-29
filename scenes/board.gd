class_name Board
extends Node2D
## Grey-box renderer of the sim (LT-7): grid, path, start, lighthouse, towers, enemies
## (interpolated by the clock alpha), shots and hit flashes. Reads sim state only; a left
## click on the grid emits `cell_clicked` and the Game decides what it means.

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
const COLOR_HP_BACK := Color(0.2, 0, 0)
const COLOR_HP := Color(0.9, 0.2, 0.2)
const COLOR_SHOT := Color(1, 1, 0.7)
const COLOR_DEATH := Color(1, 0.5, 0.2)
const COLOR_LEAK := Color(1, 0.1, 0.1)
const COLOR_SELECT := Color(1, 1, 1, 0.8)

var game: Game
var alpha := 0.0  ## render interpolation between the last two ticks
var selected_cell := Vector2i(-1, -1)  ## outlined while the picker or sell panel is open
var selected_range := 0.0  ## range ring (cells) for a selected tower; 0 = none
## Short-lived effects: {kind, from, to, ttl} in cell units.
var effects: Array[Dictionary] = []
var _last_pos: Dictionary[int, Vector2] = {}  ## enemy id -> last drawn position (cells)


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
				effects.append({"kind": "shot", "from": t.centre(), "to": ev.data["to"],
					"ttl": SHOT_SECONDS})
		SimEvent.Type.DIED:
			if _last_pos.has(ev.id):
				effects.append({"kind": "death", "from": _last_pos[ev.id], "ttl": FLASH_SECONDS})
		SimEvent.Type.LEAKED:
			var lh := game.sim.state.map.lighthouse
			effects.append({"kind": "leak", "from": Vector2(lh) + Vector2(0.5, 0.5),
				"ttl": FLASH_SECONDS})


func tick_effects(delta: float) -> void:
	for fx in effects:
		fx["ttl"] -= delta
	effects = effects.filter(func(fx: Dictionary) -> bool: return fx["ttl"] > 0.0)


func _draw() -> void:
	if game == null or game.sim == null:
		return
	var s := game.sim.state
	_draw_map(s.map)
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


func _draw_tower(t: SimTower) -> void:
	var r := Rect2(cell_origin(t.cell), Vector2(CELL, CELL)).grow(-6)
	draw_rect(r, COLOR_TOWER)
	draw_rect(r, Color.BLACK, false, 1.0)
	draw_string(ThemeDB.fallback_font, r.position + Vector2(8, 20), t.def.name.left(1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)


func _draw_enemies(s: SimState) -> void:
	_last_pos.clear()
	for e in s.enemies:
		if not e.is_live():
			continue
		var p := game.sim.enemy_position(e, alpha)
		_last_pos[e.id] = p
		var px := p * CELL
		var color := COLOR_ENEMY
		if e.revealed:
			color.a = 0.35
		draw_circle(px, CELL * 0.25, color)
		var w := CELL * 0.6
		var bar := Rect2(px + Vector2(-w * 0.5, -CELL * 0.4), Vector2(w, 4))
		draw_rect(bar, COLOR_HP_BACK)
		bar.size.x = w * clampf(e.hp / e.max_hp, 0.0, 1.0)
		draw_rect(bar, COLOR_HP)


func _draw_effects() -> void:
	for fx in effects:
		match fx["kind"]:
			"shot":
				draw_line(fx["from"] * CELL, fx["to"] * CELL, COLOR_SHOT, 2.0)
			"death":
				draw_circle(fx["from"] * CELL, CELL * 0.35, COLOR_DEATH)
			"leak":
				draw_rect(Rect2((fx["from"] - Vector2(0.5, 0.5)) * CELL, Vector2(CELL, CELL)),
					COLOR_LEAK, false, 4.0)
