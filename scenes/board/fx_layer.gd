class_name FxLayer
extends BoardLayer
## LT-84 (LT-65 §3.4): short-lived effects, drawn each board redraw above the entities and
## below the selection overlay. Fed by sim events only (Board.on_event forwards them here):
## the 12 attack looks (LT-25 and later), death / dissolve / leak flashes. Owns the effect
## list and its own presentation RNG (never the sim's).
## LT-62 P1 / LT-90 F1: the first-use warm-up draw lives here, on this same canvas item, as
## the effect draws whose first-use stall it pays; the effect draws set _line_drawn,
## _polyline_drawn and _polygon_drawn.

const FLASH_SECONDS := 0.25
const COLOR_DEATH := Color(1, 0.5, 0.2)
const COLOR_DISSOLVE := Color(0.6, 0.6, 0.75)
const COLOR_ASTRAY := Color(2.0, 1.5, 2.6)  ## over 1: stays bright under the darkness
const ASTRAY_SECONDS := 0.3
const ASTRAY_MIN_CELLS := 0.7  ## how far off the aim point an empty astray shot lands
const ASTRAY_MAX_CELLS := 1.4
## LT-25 attack looks (spec docs/design/LT-25-tower-attack-visuals.md). Colours use
## channels over 1 to stay bright under the world's CanvasModulate darkness.
const MAX_FX_PER_TOWER := 2  ## live attack effects per tower; a third replaces the oldest
const TRACER_TRAVEL := 0.08  ## seconds for the dash to reach its end
const TRACER_MUZZLE := 0.05
const TRACER_SECONDS := 0.18  ## travel + hit spark
const WARMUP_ALPHA := 0.01  ## invisible over the board, but still a real draw
const TRACER_DASH_CELLS := 0.35
const TRACER_MISS_SIDE_CELLS := 0.4  ## a miss ends this far to the side of the aim point
const TRACER_MISS_PAST_CELLS := 0.5  ## and this far past it
const HARPOON_TRAVEL := 0.22
const HARPOON_SECONDS := 0.32  ## travel + rope fade
const HARPOON_FADE := 0.1
const HARPOON_TICK_SECONDS := 0.3  ## a cross tick stays this long on each pierced enemy
const WAVE_FILL := Color(0.05, 0, 0.08, 0.55)
const WAVE_TENDRIL := 0.15
const WAVE_BLAST := 0.45
const WAVE_SECONDS := 0.6  ## tendril + blast
const WAVE_START_CELLS := 0.2  ## blast radius at its start
const WAVE_FLASH := 0.2
const WAVE_FIZZLE_CELLS := 0.5  ## max ring of an empty astray wave (not aoe_radius)
const CHAIN_SECONDS := 0.3  ## LT-29: the pull chain, one shot
const CHAIN_DASH := 6.0  ## px per dash and per gap
const CRIT_SPARK_SCALE := 2.0  ## a crit's hit spark rays are this much longer
const DYN_STICK_COLOR := Color(0.85, 0.12, 0.08)
const DYN_SMOKE := Color(0.55, 0.52, 0.5)
const DYN_FLIGHT_TICKS := 12
const DYN_ARC_BASE := 0.5
const DYN_ARC_PER_CELL := 0.3
const DYN_DUD_TICKS := 12
const DYN_STICK_PX := 7.0  ## half length of the stick
const BLAST_SECONDS := 0.5
const BLAST_FLASH := 0.08
const BLAST_DEBRIS := 8
const SHELL_SMOKE := Color(0.7, 0.68, 0.65)
const SHELL_TRAVEL := 0.14
const SHELL_SECONDS := 0.55  ## travel + impact
const SHELL_MUZZLE := 0.09
const SHELL_IMPACT_CELLS := 0.45  ## burst radius of a shell without aoe_radius
const BEAM_CORE := Color(2.6, 2.0, 2.9)
const BEAM_GRACE_TICKS := 4  ## held this long past the next SHOT's due tick (3 dimmed it at 5 Hz)
const BEAM_FADE := 0.12
const BEAM_WIDTH := 2.0  ## core px at factor 1; + BEAM_WIDTH_PER_FACTOR per factor above 1
const BEAM_WIDTH_PER_FACTOR := 1.2
const BEAM_QUIVER_HZ := 9.0
const BEAM_RIM_CELLS := 0.42  ## the beam leaves the tower tile this far from its centre
const BANISH_GHOST := Color(0.75, 0.8, 1.0)
const BANISH_SECONDS := 0.9
const BANISH_REACH := 0.3  ## the thread from the gate fades out over this long
const BANISH_FOLD := 0.45  ## the old spot collapses in this long; the new ring opens after

## Short-lived effects: {kind, from, to, ttl, ...} in cell units. Attack effects (LT-25)
## also carry tower, end, hits, hit_pos, miss, astray, dur (initial ttl), seed.
var effects: Array[Dictionary] = []
## LT-90 F1: per primitive kind _draw_warmup warms, true once an effect drew it for real.
## Only effect draws (shots) set them: those come after the window is up, while board draws
## in the startup frames would set them before the first-use cost could be paid.
var _line_drawn := false  ## draw_line with a width
var _polyline_drawn := false  ## draw_polyline with a width
var _polygon_drawn := false  ## draw_colored_polygon
var _fx_rng := RandomNumberGenerator.new()  ## presentation-only; never the sim's RNG


func _ready() -> void:
	_fx_rng.randomize()


func _draw() -> void:
	if not has_sim():
		return
	if not (_line_drawn and _polyline_drawn and _polygon_drawn):
		_draw_warmup()
	_draw_effects()


func on_event(ev: SimEvent) -> void:
	match ev.type:
		SimEvent.Type.SHOT:
			var t := game.sim.tower_by_id(ev.id)
			if t != null:
				var fx := _shot_fx(t, ev.data)
				if fx.is_empty():
					return
				var cap: int = LookCatalog.row(fx["look"])["cap"]  # LT-104 §2.4
				if fx["kind"] == "banish":
					# LT-51: one SHOT per banished enemy; a Pure cast moves 3 at once.
					_add_attack_fx(fx, maxi(cap, t.stats().banish_targets()))
					return
				if fx.get("kind", "") == "dynamite":
					fx["throw_tick"] = ev.tick
				if fx.get("kind", "") == "beam":
					# LT-50: held in sim time until the next SHOT is due (+ grace), so pause
					# and x2 follow the clock; one beam per tower, the new one replaces it.
					fx["end_tick"] = ev.tick + SimTime.ticks(t.stats().fire_interval) \
						+ BEAM_GRACE_TICKS
					_drop_beam(t.id)
				_add_attack_fx(fx, cap)
		SimEvent.Type.BLAST:  # LT-47: the charge explodes (hits real and fake alike)
			var hits: Array = ev.data.get("hits", [])
			# LT-104 §2.5: in the throwing tower def's FUSE look (a sold tower's too).
			effects.append({"kind": "blast", "from": ev.data["at"],
				"color": LookCatalog.blast_color(ev.data.get("def", "")),
				"radius": ev.data.get("radius", 0.0), "hit_pos": _hit_positions(hits),
				"seed": _fx_rng.randi(), "ttl": BLAST_SECONDS, "dur": BLAST_SECONDS})
		SimEvent.Type.DIED:
			if board.last_pos.has(ev.id):
				effects.append({"kind": "death", "from": board.last_pos[ev.id], "ttl": FLASH_SECONDS})
		SimEvent.Type.FAKE_DISSOLVED:
			if board.last_pos.has(ev.id):
				effects.append({"kind": "dissolve", "from": board.last_pos[ev.id],
					"ttl": FLASH_SECONDS})
		SimEvent.Type.LEAKED:
			var lh := game.sim.state.map.lighthouse
			effects.append({"kind": "leak", "from": game.sim.state.map.grid.centre(lh),
				"ttl": FLASH_SECONDS})




## Ages the effects by `delta` seconds (a lobbed charge and a held beam follow sim time)
## and drops the expired ones. Board.tick_effects calls it once per frame.
func tick(delta: float) -> void:
	for fx in effects:
		if fx.has("end_tick") and game != null and game.sim != null:
			# LT-47: a lobbed charge lives in sim time (pause and x2 follow the clock).
			fx["ttl"] = delta + (float(fx["end_tick"] - game.sim.state.tick) - alpha) \
				/ SimTime.TICK_RATE
		fx["ttl"] -= delta
	effects = effects.filter(func(fx: Dictionary) -> bool: return fx["ttl"] > 0.0)


## The effect for one SHOT, or {} for a tower that draws no shot. Uses only the SHOT
## fields (to, hits, miss, astray) and the tower's stats, never what was hit (LT-12 §1).
## LT-104 §2.5: `kind` is the look row's `fx` (the builder and renderer pair, "" = none),
## `look` the look id (its cap), `color` the row's colour (the renderers read it).
func _shot_fx(t: SimTower, data: Dictionary) -> Dictionary:
	var look := Board.shot_kind(t)
	var row := LookCatalog.row(look)
	var kind: String = row["fx"]
	if kind.is_empty():
		return {}
	if kind == "banish":
		# LT-51: `from` / `to` are the banished enemy's spots before and after the move.
		return {"kind": "banish", "look": look, "color": row["color"], "tower": t.id,
			"origin": t.centre(), "from": data["from"],
			"to": data["to"], "hits": data.get("hits", []).duplicate(),
			"astray": data.get("astray", false), "seed": _fx_rng.randi(),
			"ttl": BANISH_SECONDS, "dur": BANISH_SECONDS}
	var hits: Array = data.get("hits", [])
	var to: Vector2 = data["to"]
	var fx := {"kind": kind, "look": look, "color": row["color"], "tower": t.id,
		"from": t.centre(), "to": to, "end": to,
		"hits": hits.duplicate(), "hit_pos": _hit_positions(hits),
		"miss": data.get("miss", false), "astray": data.get("astray", false),
		"seed": _fx_rng.randi(), "crit": data.get("crit", false)}
	var pulled: Array = data.get("pulled", [])
	if not pulled.is_empty():  # LT-29: chain from each pulled enemy back to the tower
		var chain := {}
		for id: int in pulled:
			var e := game.sim.enemy_by_id(id)
			if e != null:
				chain[id] = game.sim.enemy_position(e, 1.0)
		fx["chain"] = chain
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
			"shell":
				fx["radius"] = t.stats().effects.get("aoe_radius", 0.0)
				fx["ttl"] = SHELL_SECONDS
				if fx["miss"]:
					fx["end"] = _miss_end(fx["from"], to)
			"beam":
				# Sim time: on_event sets end_tick; tick_effects keeps ttl to it.
				fx["factor"] = data.get("sanity_factor", 1.0)
				fx["target"] = data.get("target", -1)
				fx["ttl"] = BEAM_FADE
			"dynamite":
				# Sim time: tick_effects keeps ttl at what is left until detonate_tick
				# (+ DYN_DUD_TICKS for a dud); the BLAST event draws the explosion.
				fx["radius"] = data.get("radius", 0.0)
				fx["detonate_tick"] = data.get("detonate_tick", 0)
				fx["end_tick"] = fx["detonate_tick"] + (DYN_DUD_TICKS if fx["miss"] else 0)
				fx["ttl"] = BLAST_SECONDS
	fx["dur"] = fx["ttl"]
	return fx


## LT-50: removes tower `tower_id`'s held beam, if any (a new SHOT replaces it).
func _drop_beam(tower_id: int) -> void:
	effects = effects.filter(func(fx: Dictionary) -> bool:
		return not (fx["kind"] == "beam" and fx.get("tower", -1) == tower_id))


## Appends an attack effect, keeping at most `cap` (MAX_FX_PER_TOWER by default; LT-104: the
## look row's cap) live ones per tower.
func _add_attack_fx(fx: Dictionary, cap := MAX_FX_PER_TOWER) -> void:
	if fx.is_empty():
		return
	var mine: Array[int] = []
	for i in effects.size():
		if effects[i].get("tower", -1) == fx["tower"]:
			mine.append(i)
	var drop := mine.size() - (cap - 1)
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
		elif board.last_pos.has(id):
			out.append(board.last_pos[id])
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
		for q: Vector2 in board.last_pos.values():
			if q.distance_to(p) < 0.6:
				clear = false
				break
		if clear:
			break
	return best


## LT-62 P1 / LT-90 F1: invisible (alpha WARMUP_ALPHA) draws in the board corner of each
## primitive the effects use with a width or as a polygon, so the renderer's first-use cost
## (a 350-1000 ms stall at the first tower shot) is paid before a shot needs it. _draw calls
## this on every frame until an effect has drawn each of these primitive kinds for real
## (_line_drawn, _polyline_drawn, _polygon_drawn), and it draws only the kinds still cold.
## Not timed: the startup frames, before the window is up, do not pay the cost (LT-90), so
## the warm-up must still be running once the window is presented. Presentation only.
func _draw_warmup() -> void:
	var c := Color(Board.TRACER_COLOR, WARMUP_ALPHA)
	if not _line_drawn:
		draw_line(Vector2(2, 2), Vector2(6, 2), c, 2.0)
	if not _polyline_drawn:
		draw_polyline(PackedVector2Array([Vector2(2, 4), Vector2(4, 5), Vector2(6, 4)]), c, 3.0)
	if not _polygon_drawn:
		draw_colored_polygon(PackedVector2Array([Vector2(2, 6), Vector2(6, 6), Vector2(4, 8)]), c)


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
			"dynamite":
				_draw_charge(fx)
			"shell":
				_draw_shell(fx)
			"beam":
				_draw_beam(fx)
			"banish":
				_draw_banish(fx)
			"blast":
				_draw_blast(fx)
			"death":
				draw_circle(view.cell_to_world(fx["from"]), view.cells_to_px(0.35), COLOR_DEATH)
			"dissolve":
				draw_arc(view.cell_to_world(fx["from"]), view.cells_to_px(0.35), 0, TAU, 24,
					COLOR_DISSOLVE, 2.0)
			"leak":
				draw_rect(Rect2(view.cell_to_world(fx["from"] - Vector2(0.5, 0.5)),
					Vector2.ONE * view.cells_to_px(1.0)),
					Board.COLOR_LEAK, false, 4.0)


## A wavering bolt from the tower to an empty spot, ending in a small fading ring; from a
## wave tower the ring is a fizzle growing to `radius` (LT-25 §3).
func _draw_astray(fx: Dictionary) -> void:
	var b: Vector2 = view.cell_to_world(fx["to"])
	var fade := clampf(fx["ttl"] / ASTRAY_SECONDS, 0.0, 1.0)
	var c := Color(COLOR_ASTRAY, fade)
	draw_polyline(_waver_points(view.cell_to_world(fx["from"]), b, fx["seed"]), c, 3.0)
	_polyline_drawn = true
	if fx.has("radius"):
		draw_arc(b, view.cells_to_px(fx["radius"]) * (0.3 + 0.7 * (1.0 - fade)), 0, TAU, 20, c, 2.0)
	else:
		draw_arc(b, view.cells_to_px(0.4 - 0.2 * fade), 0, TAU, 20, c, 3.0)


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
	var col: Color = fx.get("color", Board.TRACER_COLOR)
	var el := _elapsed(fx)
	var a: Vector2 = view.cell_to_world(fx["from"])
	var b: Vector2 = view.cell_to_world(fx["end"])
	var dir := (b - a).normalized()
	if el < TRACER_MUZZLE:
		draw_circle(a, view.cells_to_px(0.12), col)
	if el < TRACER_TRAVEL:
		var head := a.lerp(b, clampf(el / TRACER_TRAVEL, 0.0, 1.0))
		var tail := head - dir * minf(view.cells_to_px(TRACER_DASH_CELLS), head.distance_to(a))
		draw_line(tail, head, col, 2.0)
		_line_drawn = true
	elif not fx["miss"]:
		var fade := clampf(1.0 - (el - TRACER_TRAVEL) / (TRACER_SECONDS - TRACER_TRAVEL),
			0.0, 1.0)
		var ray := CRIT_SPARK_SCALE if fx.get("crit", false) else 1.0  # LT-29
		for p: Vector2 in fx["hit_pos"]:
			for i in 4:
				var v := Vector2.from_angle(PI * 0.25 + i * PI * 0.5)
				draw_line(view.cell_to_world(p) + view.cell_to_world(v) * 0.05,
					view.cell_to_world(p) + view.cell_to_world(v) * 0.2 * ray,
					Color(col, fade), 2.0)


## Harpooner (LT-25 §1.2): a head flying the whole line on a rope, a cross tick on each
## pierced enemy as it passes. A miss leaves no ticks and the head drops at the end.
func _draw_harpoon(fx: Dictionary) -> void:
	var col: Color = fx.get("color", Board.HARPOON_COLOR)
	var el := _elapsed(fx)
	var a: Vector2 = view.cell_to_world(fx["from"])
	var b: Vector2 = view.cell_to_world(fx["to"])
	var dir := (b - a).normalized()
	var fade := clampf(1.0 - (el - (HARPOON_SECONDS - HARPOON_FADE)) / HARPOON_FADE, 0.0, 1.0)
	if fade > 0.0:
		var head := a.lerp(b, clampf(el / HARPOON_TRAVEL, 0.0, 1.0))
		if fx["miss"] and el > HARPOON_TRAVEL:
			head += Vector2(0, view.cells_to_px(0.3) * (1.0 - fade))
		var base := head - view.cell_to_world(dir) * 0.3
		draw_line(a, base, Color(col, 0.6 * fade), 1.0)
		var w := view.cell_to_world(dir.orthogonal()) * 0.09
		draw_colored_polygon(PackedVector2Array([head, base + w, base - w]),
			Color(col, fade))
		_polygon_drawn = true
	if el < CHAIN_SECONDS:  # LT-29: dashed steel chain from each pulled enemy to the tower
		var cc := Color(col, 1.0 - el / CHAIN_SECONDS * 0.7)
		var chain: Dictionary = fx.get("chain", {})
		for id: int in chain:
			var p: Vector2 = board.last_pos.get(id, chain[id])
			draw_dashed_line(view.cell_to_world(p), a, cc, 2.0, CHAIN_DASH)
	var pos: Array = fx["hit_pos"]
	var passes: Array = fx.get("pass_t", [])
	for i in mini(pos.size(), passes.size()):
		var since: float = el - passes[i]
		if since < 0.0 or since >= HARPOON_TICK_SECONDS:
			continue
		var p: Vector2 = view.cell_to_world(pos[i])
		var c := Color(col, 1.0 - since / HARPOON_TICK_SECONDS * 0.6)
		var h := view.cells_to_px(0.125)
		draw_line(p + Vector2(-h, -h), p + Vector2(h, h), c, 3.0)
		draw_line(p + Vector2(-h, h), p + Vector2(h, -h), c, 3.0)
		_line_drawn = true


## Necronomicon (LT-25 §1.4): an S-bent tendril to `to`, then a dark disc with a bright rim
## growing to `radius` and a flash on each hit enemy. Astray: wavering tendril, astray rim.
func _draw_wave(fx: Dictionary) -> void:
	var col: Color = fx.get("color", Board.WAVE_RIM)
	var el := _elapsed(fx)
	var a: Vector2 = view.cell_to_world(fx["from"])
	var b: Vector2 = view.cell_to_world(fx["to"])
	var rim := COLOR_ASTRAY if fx["astray"] else col
	if el < WAVE_TENDRIL + 0.05:
		var pts := _waver_points(a, b, fx["seed"]) if fx["astray"] \
			else _wave_points(a, b, 0.0, 2.0, 6.0, 12)
		var ta := clampf(1.0 - (el - WAVE_TENDRIL) / 0.05, 0.0, 1.0)
		draw_polyline(pts, Color(rim, ta), 3.0)
		_polyline_drawn = true
	var be := el - WAVE_TENDRIL
	if be < 0.0:
		return
	var k := clampf(be / WAVE_BLAST, 0.0, 1.0)
	var r := view.cells_to_px(lerpf(WAVE_START_CELLS, fx["radius"], k))
	draw_circle(b, r, Color(WAVE_FILL, WAVE_FILL.a * (1.0 - k)))
	draw_arc(b, r, 0, TAU, 48, Color(rim, 1.0 - k * k), 3.0)
	if be < WAVE_FLASH:
		for p: Vector2 in fx["hit_pos"]:
			draw_arc(view.cell_to_world(p), view.cells_to_px(0.3), 0, TAU, 20,
				Color(rim, 1.0 - be / WAVE_FLASH), 2.0)


## LT-50 Resonator: the held beam. Its end follows the target's drawn position while that
## enemy is live (else the shot's `to`); width and glow grow with `factor` (sanity_factor).
func _draw_beam(fx: Dictionary) -> void:
	var col: Color = fx.get("color", Board.BEAM_COLOR)
	var a: Vector2 = view.cell_to_world(fx["from"])
	var end: Vector2 = fx["to"]
	var e := game.sim.enemy_by_id(fx["target"]) if game != null and game.sim != null else null
	if e != null and e.is_live():
		end = game.sim.enemy_position(e, alpha)
	var b := view.cell_to_world(end)
	# From the tile's rim, not its centre, so the glyph stays readable under the beam.
	a += (b - a).normalized() * minf(view.cells_to_px(BEAM_RIM_CELLS), a.distance_to(b))
	var fade := clampf(fx["ttl"] / BEAM_FADE, 0.0, 1.0)
	var f: float = fx.get("factor", 1.0)
	var w := BEAM_WIDTH + BEAM_WIDTH_PER_FACTOR * maxf(0.0, f - 1.0)
	var ph := board.time * TAU * BEAM_QUIVER_HZ + float(fx["seed"] % 1000) * 0.01
	var glow := Color(col, 0.35 * fade)
	draw_line(a, b, glow, w * 3.5)
	draw_polyline(_wave_points(a, b, ph, 5.0, 1.5 + 0.5 * f, 16), Color(col, fade), w)
	draw_line(a, b, Color(BEAM_CORE, fade), maxf(1.0, w * 0.4))
	_line_drawn = true
	_polyline_drawn = true
	var pulse := 0.5 + 0.5 * sin(ph * 0.5)
	draw_circle(a, view.cells_to_px(0.06 + 0.03 * pulse), Color(BEAM_CORE, fade))
	draw_arc(b, view.cells_to_px(0.18 + 0.08 * pulse), 0, TAU, 16, Color(col, fade), 2.0)
	for i in 3:
		var v := Vector2.from_angle(ph * 0.3 + i * TAU / 3.0)
		draw_line(b + view.cell_to_world(v) * 0.1, b + view.cell_to_world(v) * (0.22 + 0.06 * pulse),
			Color(BEAM_CORE, fade), 1.5)


## LT-51 Silver Key Gate, one banished enemy: a silver thread from the gate to its old
## spot; there a keyhole and four arcs collapsing on a fading ghost body (the fold); a
## dotted trail to the new spot, where a ring opens around the enemy (it is already drawn
## there: the sim moved it without a slide).
func _draw_banish(fx: Dictionary) -> void:
	var col: Color = fx.get("color", Board.BANISH_COLOR)
	var el := _elapsed(fx)
	var dur: float = fx["dur"]
	var k := clampf(el / dur, 0.0, 1.0)
	var o: Vector2 = view.cell_to_world(fx["origin"])
	var a: Vector2 = view.cell_to_world(fx["from"])
	var b: Vector2 = view.cell_to_world(fx["to"])
	if el < BANISH_REACH:
		var rf := 1.0 - el / BANISH_REACH
		o += (a - o).normalized() * minf(view.cells_to_px(BEAM_RIM_CELLS), o.distance_to(a))
		draw_line(o, a, Color(col, 0.9 * rf), 2.0)
		_line_drawn = true
	if a.distance_to(b) > 1.0:
		draw_dashed_line(a, b, Color(col, 0.7 * (1.0 - k)), 2.5, 6.0)
	var fold := clampf(el / BANISH_FOLD, 0.0, 1.0)
	if fold < 1.0:
		var left := 1.0 - fold
		draw_circle(a, view.cells_to_px(0.3) * left, Color(BANISH_GHOST, 0.6 * left))
		var r := view.cells_to_px(0.22 + 0.4 * left)
		for i in 4:
			var st := i * TAU / 4.0 + fold * PI
			draw_arc(a, r, st, st + TAU / 7.0, 6, Color(col, 0.4 + 0.6 * left), 3.0)
	# The keyhole outlasts the fold: the gate's mark on the old spot.
	var kc := Color(col, 1.0 - k)
	var hole := view.cells_to_px(0.14)
	draw_circle(a + Vector2(0, -hole * 0.6), hole, kc)
	draw_colored_polygon(PackedVector2Array([a + Vector2(-hole * 0.45, 0),
		a + Vector2(hole * 0.45, 0), a + Vector2(hole * 0.8, hole * 1.9),
		a + Vector2(-hole * 0.8, hole * 1.9)]), kc)
	_polygon_drawn = true
	if el >= BANISH_FOLD * 0.5:
		var open := clampf((el - BANISH_FOLD * 0.5) / (dur - BANISH_FOLD * 0.5), 0.0, 1.0)
		draw_arc(b, view.cells_to_px(0.25 + 0.35 * open), 0, TAU, 24,
			Color(col, 1.0 - open), 3.0)


## LT-48 Coast battery: a muzzle flash and a smoke puff drifting off the gun, the shell (a
## bright slug with a smoke trail) racing to `end`, then the impact: a ring to the HE
## `radius` (or a small burst) with debris and a flash on each hit enemy. A miss lands
## beside the aim point and throws up only grey dust.
func _draw_shell(fx: Dictionary) -> void:
	var col: Color = fx.get("color", Board.SHELL_COLOR)
	var el := _elapsed(fx)
	var a: Vector2 = view.cell_to_world(fx["from"])
	var b: Vector2 = view.cell_to_world(fx["end"])
	var dir := (b - a).normalized()
	var k_all := clampf(el / SHELL_SECONDS, 0.0, 1.0)
	# Smoke puff at the gun, rising and fading over the whole effect.
	draw_circle(a + view.cell_to_world(dir) * 0.35 + Vector2(0, -view.cells_to_px(0.25) * k_all),
		view.cells_to_px(0.18 + 0.22 * k_all), Color(SHELL_SMOKE, 0.5 * (1.0 - k_all)))
	if el < SHELL_MUZZLE:
		var mk := 1.0 - el / SHELL_MUZZLE
		draw_circle(a + view.cell_to_world(dir) * 0.3, view.cells_to_px(0.2) * (0.6 + 0.4 * mk),
			Color(3.0, 2.4, 1.4, mk))
	if el < SHELL_TRAVEL:
		var kk := clampf(el / SHELL_TRAVEL, 0.0, 1.0)
		var head := a.lerp(b, kk)
		var tail := head - dir * minf(view.cells_to_px(1.2), head.distance_to(a))
		draw_line(tail, head, Color(SHELL_SMOKE, 0.45), 4.0)
		draw_line(head - view.cell_to_world(dir) * 0.3, head, col, 4.0)
		_line_drawn = true
		draw_circle(head, 3.5, Color(3.0, 2.6, 2.0))
		return
	var ie := el - SHELL_TRAVEL
	var k := clampf(ie / (SHELL_SECONDS - SHELL_TRAVEL), 0.0, 1.0)
	var grow := 1.0 - (1.0 - k) * (1.0 - k)
	if fx["miss"]:
		draw_circle(b + Vector2(0, -view.cells_to_px(0.2) * k), view.cells_to_px(0.15 + 0.25 * grow),
			Color(SHELL_SMOKE, 0.6 * (1.0 - k)))
		return
	var radius: float = fx.get("radius", 0.0)
	var r := view.cells_to_px(radius if radius > 0.0 else SHELL_IMPACT_CELLS)
	draw_circle(b, r * (0.5 + 0.5 * grow), Color(SHELL_SMOKE, 0.4 * (1.0 - k)))
	if ie < BLAST_FLASH:
		draw_circle(b, r * 0.5, Color(3.0, 2.6, 1.6, 1.0 - ie / BLAST_FLASH))
	draw_arc(b, r * (0.3 + 0.7 * grow), 0, TAU, 40, Color(col, 1.0 - k * k), 3.0)
	var sd: int = fx["seed"]
	for i in 6:
		var ang := float((sd >> i) % 628) * 0.01 + i * TAU / 6.0
		draw_circle(b + Vector2.from_angle(ang) * r * (0.3 + 0.8 * grow), 2.0,
			Color(col, 1.0 - k))
	if ie < WAVE_FLASH:
		var ray := CRIT_SPARK_SCALE if fx.get("crit", false) else 1.0
		for p: Vector2 in fx["hit_pos"]:
			draw_arc(view.cell_to_world(p), view.cells_to_px(0.3) * ray, 0, TAU, 20,
				Color(col, 1.0 - ie / WAVE_FLASH), 2.0)


## LT-47 Dynamite crew: the stick flies on an arc to `to` (a dotted trail behind it, its
## fuse spitting sparks), then lies there under a pulsing ring of the blast radius until
## detonate_tick; the BLAST event takes over. A dud's fuse dies and it smokes instead.
func _draw_charge(fx: Dictionary) -> void:
	var col: Color = fx.get("color", Board.DYNAMITE_COLOR)
	var el := float(game.sim.state.tick - int(fx["throw_tick"])) + alpha  # ticks
	var fuse := maxf(1.0, float(int(fx["detonate_tick"]) - int(fx["throw_tick"])))
	var flight := minf(float(DYN_FLIGHT_TICKS), fuse)
	var a: Vector2 = view.cell_to_world(fx["from"])
	var b: Vector2 = view.cell_to_world(fx["to"])
	var h := view.cell_to_world(_arc_lift(a, b)) \
		* (DYN_ARC_BASE + view.px_to_cells(DYN_ARC_PER_CELL * a.distance_to(b)))
	var k := clampf(el / flight, 0.0, 1.0)
	var pos := _arc_point(a, b, h, k)
	if k < 1.0:
		draw_circle(a.lerp(b, k), 3.0, Color(0, 0, 0, 0.35))  # its shadow on the ground
		var n := 10
		for i in n:
			var kk := k * float(i) / n
			draw_circle(_arc_point(a, b, h, kk), 1.5,
				Color(col, 0.15 + 0.5 * float(i) / n))
		var dir := (_arc_point(a, b, h, minf(1.0, k + 0.05)) - pos).normalized()
		var spin := dir.rotated(el * 0.6)
		_draw_stick(pos, spin, true, el, col)
		return
	var lying := el - flight
	var left := fuse - el  # ticks to detonation
	if left > 0.0:
		var urgency := 1.0 - clampf(left / maxf(1.0, fuse - flight), 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(board.time * TAU * (2.0 + 6.0 * urgency))
		var r := view.cells_to_px(float(fx["radius"]))
		draw_circle(b, r, Color(col, 0.04 + 0.06 * urgency))
		draw_arc(b, r, 0, TAU, 40, Color(col, 0.25 + 0.35 * pulse * urgency + 0.1), 1.5)
		_draw_stick(b, Vector2.RIGHT.rotated(0.35), not fx["miss"] or left > fuse * 0.3, lying, col)
	else:
		# A dud: the stick lies dead and a grey puff rises.
		var dk := clampf(-left / DYN_DUD_TICKS, 0.0, 1.0)
		_draw_stick(b, Vector2.RIGHT.rotated(0.35), false, lying, col)
		draw_circle(b + Vector2(0, -view.cells_to_px(0.3) * dk), view.cells_to_px(0.15 + 0.2 * dk),
			Color(DYN_SMOKE, 0.6 * (1.0 - dk)))


## A point of the throw arc at k in [0, 1]: the chord a -> b lifted by a parabola whose
## top is the offset `h` (pixels, a vector).
func _arc_point(a: Vector2, b: Vector2, h: Vector2, k: float) -> Vector2:
	return a.lerp(b, k) + h * (4.0 * k * (1.0 - k))


## The unit direction the arc bulges: the chord's normal on the screen-up side, so a throw
## straight up or down the screen still reads as a curve (it bends to the left).
static func _arc_lift(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	if d.length_squared() < 0.0001:
		return Vector2.UP
	var n := d.orthogonal().normalized()
	if n.y > 0.0 or (absf(n.y) < 0.001 and n.x > 0.0):
		n = -n
	return (n + Vector2.UP).normalized() if absf(n.y) > 0.3 else n


## One stick of dynamite at `p` along `dir`, its fuse end spitting a flickering spark.
func _draw_stick(p: Vector2, dir: Vector2, burning: bool, el: float, col: Color) -> void:
	var half := dir * DYN_STICK_PX
	draw_line(p - half, p + half, Color(0.05, 0.02, 0.02), 7.0)
	draw_line(p - half * 0.9, p + half * 0.9, DYN_STICK_COLOR, 5.0)
	var tip := p + half + dir * 3.0
	draw_line(p + half, tip, Color(0.9, 0.85, 0.7), 1.5)
	if not burning:
		return
	var flick := 0.6 + 0.4 * absf(sin(el * 2.3 + board.time * 31.0))
	draw_circle(tip, 2.0 + 2.0 * flick, Color(col, flick))
	for i in 3:
		var v := Vector2.from_angle(board.time * 17.0 + i * TAU / 3.0)
		draw_line(tip + v * 2.0, tip + v * (4.0 + 4.0 * flick), Color(2.4, 2.2, 1.2, flick), 1.0)


## LT-47: a white flash, an orange ring racing out to the blast radius over a fading smoke
## disc, flying debris, and a flash ring on each hit enemy.
func _draw_blast(fx: Dictionary) -> void:
	var col: Color = fx.get("color", Board.DYNAMITE_COLOR)
	var el := _elapsed(fx)
	var c: Vector2 = view.cell_to_world(fx["from"])
	var r := view.cells_to_px(float(fx["radius"]))
	var k := clampf(el / BLAST_SECONDS, 0.0, 1.0)
	var grow := 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)  # fast out, slow end
	draw_circle(c, r * (0.6 + 0.4 * grow), Color(DYN_SMOKE, 0.45 * (1.0 - k)))
	if el < BLAST_FLASH:
		draw_circle(c, r * 0.7, Color(3.0, 2.6, 1.6, 1.0 - el / BLAST_FLASH))
	draw_arc(c, r * (0.2 + 0.8 * grow), 0, TAU, 48, Color(col, 1.0 - k * k), 4.0)
	var sd: int = fx["seed"]
	for i in BLAST_DEBRIS:
		var ang := float((sd >> i) % 628) * 0.01 + i * TAU / BLAST_DEBRIS
		var d := r * (0.3 + 0.9 * grow)
		draw_circle(c + Vector2.from_angle(ang) * d, 2.0, Color(col, 1.0 - k))
	if el < WAVE_FLASH:
		for p: Vector2 in fx["hit_pos"]:
			draw_arc(view.cell_to_world(p), view.cells_to_px(0.3), 0, TAU, 20,
				Color(col, 1.0 - el / WAVE_FLASH), 2.0)
