extends Node2D
## LT-130 §6: throwaway grey viewer for the P1 map generator, not part of the game (deleted when
## the generator enters it; excluded from exports). 20 seeds side by side (5 x 4) for one preset.
## Launch: godot --path . res://tools/proto/map_viewer.tscn -- --mute [--preset small|large]
##   [--from 1] [--params f.json] [--screenshot out.png]
## Keys: H plain / jittered hexes, N / P next / previous 20 seeds.
## Marks: routes = polylines (one colour per entry), chokepoints = rings, pockets = hatched,
## loop links = dashed, F = diamond, L = white dot.

const COLS := 5
const ROWS := 4
const PER_PAGE := COLS * ROWS
const TILE := Vector2(380.0, 255.0)
const LABEL_H := 22.0
const JITTER := 0.14  ## in cell units
const SCREEN := Vector2i(COLS * 380, ROWS * 255 + 30)
const KIND_COLOUR := {
	GenMap.Terrain.SEA: Color(0.13, 0.20, 0.30),
	GenMap.Terrain.CHANNEL: Color(0.34, 0.42, 0.52),
	GenMap.Terrain.ISLAND: Color(0.50, 0.50, 0.46),
	GenMap.Terrain.ROCK: Color(0.26, 0.26, 0.26),
	GenMap.Terrain.ENTRY: Color(0.62, 0.52, 0.30),
	GenMap.Terrain.LIGHTHOUSE: Color(0.85, 0.85, 0.60),
}
const ROUTE_COLOURS: Array[Color] = [Color.ORANGE_RED, Color.LIME_GREEN, Color.DODGER_BLUE,
	Color.MAGENTA]
const CHOKE_COLOUR := Color(1.0, 1.0, 0.3)
const POCKET_COLOUR := Color(0.18, 0.18, 0.16)

var _params: MapGenParams
var _preset := "large"
var _first := 1
var _jitter := true
var _results: Array[MapGenerator.GenResult] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	DebugArgs.apply_mute(args)
	_preset = _opt(args, "--preset", "large")
	_params = MapGenParams.p1_large() if _preset == "large" else MapGenParams.p1_small()
	var pf := _opt(args, "--params", "")
	if pf != "":
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(pf))
		var r := MapGenParams.from_dict(d if d is Dictionary else {}, _params)
		if r["params"] == null:
			printerr("--params errors: ", "; ".join(r["errors"]))
			get_tree().quit(2)
			return
		_params = r["params"]
	_first = int(_opt(args, "--from", "1"))
	var w := get_window()
	w.content_scale_size = SCREEN  # the whole 5 x 4 sheet fits whatever the window size
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	w.size = Vector2i(1500, 900)
	get_window().title = "LT-130 map viewer (%s)" % _preset
	_load_page()
	var shot := _opt(args, "--screenshot", "")
	if shot != "":
		_screenshot_and_quit(shot)


func _screenshot_and_quit(path: String) -> void:
	for i in 20:
		await get_tree().process_frame
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err != OK:
		printerr("cannot save screenshot ", path, ": ", err)
	get_tree().quit(0 if err == OK else 1)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_H:
			_jitter = not _jitter
		KEY_N:
			_first += PER_PAGE
			_load_page()
		KEY_P:
			_first = maxi(1, _first - PER_PAGE)
			_load_page()
	queue_redraw()


func _load_page() -> void:
	_results.clear()
	for i in PER_PAGE:
		_results.append(MapGenerator.generate(_first + i, _params))
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, Vector2(SCREEN)), Color(0.08, 0.08, 0.09))
	for i in _results.size():
		var origin := Vector2(i % COLS, i / COLS) * TILE
		_draw_tile(origin, _first + i, _results[i], font)
	draw_string(font, Vector2(6.0, SCREEN.y - 8.0),
		"%s %dx%d | H: %s hexes | N/P: seeds %d-%d | rings = chokepoints, hatched = pockets, dashed = loops" % [
			_preset, _params.width, _params.height, "jittered" if _jitter else "plain",
			_first, _first + PER_PAGE - 1], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13)


func _draw_tile(origin: Vector2, s: int, res: MapGenerator.GenResult, font: Font) -> void:
	var ok := res.map != null
	draw_string(font, origin + Vector2(8.0, 15.0), "seed %d  %s  attempts %d%s" % [
		s, "PASS" if ok else "FAIL", res.attempts,
		"" if ok else "  " + res.error.substr(0, 60)], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13,
		Color(0.6, 1.0, 0.6) if ok else Color(1.0, 0.45, 0.45))
	if not ok:
		return
	var m := res.map
	var rep := res.report
	var b := m.grid.bounds()
	var room := TILE - Vector2(8.0, LABEL_H + 6.0)
	var sc := minf(room.x / b.size.x, room.y / b.size.y)
	var off := origin + Vector2(4.0, LABEL_H) - b.position * sc
	var pocket_set := {}
	for c in m.pocket_cells():
		pocket_set[c] = true
	for c in m.grid.cells():
		var poly := _tile(m.grid, c, sc, off)
		var col: Color = POCKET_COLOUR if pocket_set.has(c) else KIND_COLOUR[m.kind_at(c)]
		draw_colored_polygon(poly, col)
		if pocket_set.has(c):
			var mid := m.grid.centre(c) * sc + off
			draw_line(mid - Vector2(sc * 0.3, sc * 0.3), mid + Vector2(sc * 0.3, sc * 0.3),
				Color(0.8, 0.5, 0.2), 1.0)
			draw_line(mid - Vector2(sc * 0.3, -sc * 0.3), mid + Vector2(sc * 0.3, -sc * 0.3),
				Color(0.8, 0.5, 0.2), 1.0)
		var loop := poly.duplicate()
		loop.append(poly[0])
		draw_polyline(loop, Color(0.0, 0.0, 0.0, 0.35), 1.0)
	for ri in rep.routes.size():
		var pts := PackedVector2Array()
		for c: Vector2i in rep.routes[ri]:
			pts.append(m.grid.centre(c) * sc + off)
		draw_polyline(pts, ROUTE_COLOURS[ri % ROUTE_COLOURS.size()], 2.0)
		for c: Vector2i in rep.chokepoints[ri]:
			draw_arc(m.grid.centre(c) * sc + off, sc * 0.26, 0.0, TAU, 10, CHOKE_COLOUR, 1.0)
	for li in range(0, m.links.size() - 1, 2):
		draw_dashed_line(m.grid.centre(m.links[li]) * sc + off,
			m.grid.centre(m.links[li + 1]) * sc + off, Color.WHITE, 1.5, 4.0)
	if m.funnel != GenMap.NO_CELL:
		var f := m.grid.centre(m.funnel) * sc + off
		var d := sc * 0.4
		draw_colored_polygon(PackedVector2Array([f + Vector2(0.0, -d), f + Vector2(d, 0.0),
			f + Vector2(0.0, d), f + Vector2(-d, 0.0)]), Color(0.9, 0.3, 0.9))
	draw_circle(m.grid.centre(m.lighthouse) * sc + off, sc * 0.35, Color.WHITE)


## The cell polygon scaled and placed; jittered when on: every vertex moves by an offset hashed
## from its rounded position (no RNG), so the neighbours that share a vertex still meet.
func _tile(grid: GridTopology, c: Vector2i, sc: float, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in grid.polygon(c):
		out.append((v + (_jitter_offset(v) if _jitter else Vector2.ZERO)) * sc + off)
	return out


static func _jitter_offset(v: Vector2) -> Vector2:
	var h := hash(Vector2i((v * 64.0).round()))
	return Vector2(float(h & 0xFFFF) / 65535.0 - 0.5,
		float((h >> 16) & 0xFFFF) / 65535.0 - 0.5) * 2.0 * JITTER


static func _opt(args: PackedStringArray, key: String, fallback: String) -> String:
	var i := args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return fallback
