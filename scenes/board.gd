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
## wave; slow, damage-taken and (LT-29) bleed markers on enemies (enemy_markers), a longer
## hit spark on a crit and a dashed chain for a pull. LT-47: the Dynamite crew's lobbed
## charge (an arc, then a sputtering fuse on the ground until the BLAST event, sim time) and
## its blast ring. Nothing here tells a fake from a real enemy: every look depends only on
## SHOT / BLAST fields and aura state. LT-49: the Searchlight's aura is a lit disc with a
## sweeping beam; a fake its aura revealed (`SimEnemy.revealed`, sim state)
## is drawn as a ghost-grey body with an amber ring and slash.
## LT-41 (LT-38 P2): the static map (cells, grid, start, lighthouse) lives in a child
## MapLayer drawn behind the board's own draw and redrawn only when the map changes, not
## every frame. Same parent, so the same CanvasModulate and light mask apply to it.

signal cell_clicked(cell: Vector2i)
signal outside_clicked  ## LT-28: a left click no control took that misses the grid

const LIT_MARK_COLOR := Color(1.0, 0.95, 0.6)  ## LT-30: tower inside a beam
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
const COLOR_ENEMY_MAD := Color(1.0, 0.25, 0.15)  ## LT-23 Q10: hostile tint in madness
const COLOR_ENEMY_OUTLINE := Color(0.03, 0.0, 0.02)  ## LT-23 Q10: dark outline in madness
const COLOR_HP_BACK := Color(0.2, 0, 0)
const COLOR_HP := Color(0.9, 0.2, 0.2)
const COLOR_DEATH := Color(1, 0.5, 0.2)
const COLOR_LEAK := Color(1, 0.1, 0.1)
const COLOR_DISSOLVE := Color(0.6, 0.6, 0.75)
const COLOR_DEBUG_FAKE := Color(1, 0, 1)  ## debug outline (--reveal-fakes), LT-12 §1
const COLOR_SELECT := Color(1, 1, 1, 0.8)
const COLOR_LETTER_PLATE := Color(0.06, 0.05, 0.08)  ## LT-28: contrast plate under the letter
const LETTER_PLATE := Rect2(4, 4, 15, 19)  ## in the tower tile, under the 16 px letter
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
const HARPOON_COLOR := Color(0.4, 1.3, 2.6)
const HARPOON_TRAVEL := 0.22
const HARPOON_SECONDS := 0.32  ## travel + rope fade
const HARPOON_FADE := 0.1
const HARPOON_TICK_SECONDS := 0.3  ## a cross tick stays this long on each pierced enemy
const WARD_COLOR := Color(0.9, 2.0, 1.6)
const WARD_IDLE_ALPHA := 0.25
const WARD_PULSE_LOW := 0.75  ## active ring pulses between this and WARD_ACTIVE_ALPHA
const WARD_ACTIVE_ALPHA := 1.0
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
const MARK_BLEED := Color(1.7, 0.2, 0.15)  ## LT-29: bleed drops below the body
const BLEED_DROP_SECONDS := 0.5  ## one drip loop (decoration, real time)
const CHAIN_SECONDS := 0.3  ## LT-29: the pull chain, one shot
const CHAIN_DASH := 6.0  ## px per dash and per gap
const CRIT_SPARK_SCALE := 2.0  ## a crit's hit spark rays are this much longer
## LT-47 Dynamite crew: the charge flies DYN_FLIGHT_TICKS (or the whole fuse if shorter) on
## an arc DYN_ARC_BASE + DYN_ARC_PER_CELL x distance cells high, then lies with a burning
## fuse until its detonate_tick; a dud fizzles out in grey smoke for DYN_DUD_TICKS more.
const DYNAMITE_COLOR := Color(2.6, 1.4, 0.45)
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
## LT-48 Coast battery: a muzzle flash and smoke puff at the gun, a heavy shell racing to
## `to` in SHELL_TRAVEL with a smoke trail, then an impact: a dust burst (AP) or a ring out
## to aoe_radius (HE). A miss lands off target and only throws up dust.
const SHELL_COLOR := Color(2.5, 0.8, 0.55)
const SHELL_SMOKE := Color(0.7, 0.68, 0.65)
const SHELL_TRAVEL := 0.14
const SHELL_SECONDS := 0.55  ## travel + impact
const SHELL_MUZZLE := 0.09
const SHELL_IMPACT_CELLS := 0.45  ## burst radius of a shell without aoe_radius
const DEAD_ZONE_DASH := 5.0  ## px per dash of the selected tower's dead-zone ring
## LT-49 Searchlight: a faint lit disc at the aura radius with a beam wedge sweeping round
## once per SEARCH_SWEEP_SECONDS; brighter while a drawn enemy is inside (ward_alpha).
const SEARCHLIGHT_COLOR := Color(2.4, 2.2, 1.5)
const SEARCH_SWEEP_SECONDS := 5.0
const SEARCH_CONE := 0.45  ## half angle of the sweeping wedge, radians
const SEARCH_DISC_ALPHA := 0.07
const REVEALED_ALPHA := 0.45  ## body alpha of a revealed fake
## A revealed fake: a ghost-grey body, a bold amber ring outside the dashed slow mark and
## an amber slash across the body ("exposed, ignore"), unlike any other enemy marker.
const REVEALED_BODY := Color(0.62, 0.62, 0.72)
const REVEALED_MARK := Color(2.6, 1.3, 0.3)
const REVEALED_RING_CELLS := 0.44
const REVEALED_SLASH_CELLS := 0.3  ## half length of the slash
## LT-50 Tillinghast Resonator (LT-46 P14): one held beam per tower, a violet glow with a
## bright quivering core from the tower to its (moving) target, a pulsing node at the tower
## and a crackling ring on the target. SHOT every 6 ticks refreshes it instead of adding a
## new effect; it fades BEAM_FADE seconds after the last SHOT's interval ran out. Thicker and
## brighter as sanity falls (the SHOT's sanity_factor).
const BEAM_COLOR := Color(1.5, 0.55, 2.7)
const BEAM_CORE := Color(2.6, 2.0, 2.9)
const BEAM_GRACE_TICKS := 4  ## held this long past the next SHOT's due tick (3 dimmed it at 5 Hz)
const BEAM_FADE := 0.12
const BEAM_WIDTH := 2.0  ## core px at factor 1; + BEAM_WIDTH_PER_FACTOR per factor above 1
const BEAM_WIDTH_PER_FACTOR := 1.2
const BEAM_QUIVER_HZ := 9.0
const BEAM_RIM_CELLS := 0.42  ## the beam leaves the tower tile this far from its centre
## LT-51 Silver Key Gate: per banished enemy, a silver thread from the gate to the enemy's
## old spot, a keyhole there while the enemy "folds" (arcs collapsing on a fading ghost),
## a dotted trail back to where it reappears and a ring opening around it there. Banish
## immunity shows as a silver lid arc over the body.
const BANISH_COLOR := Color(2.0, 2.1, 2.6)
const BANISH_GHOST := Color(0.75, 0.8, 1.0)
const BANISH_SECONDS := 0.9
const BANISH_REACH := 0.3  ## the thread from the gate fades out over this long
const BANISH_FOLD := 0.45  ## the old spot collapses in this long; the new ring opens after
const BANISH_LID_CELLS := 0.33

## LT-14 visual tunables.
@export var flicker_rate := 13.0  ## flicker steps per second
@export var phantom_seconds := Vector2(0.9, 2.2)  ## lifetime range of one phantom path
@export var phantom_cells := Vector2i(4, 9)  ## length range of a phantom path
@export var phantom_alpha := 0.7

var game: Game
var alpha := 0.0  ## render interpolation between the last two ticks
var selected_cell := Vector2i(-1, -1)  ## outlined while the build or tower view is open
var selected_range := 0.0  ## range ring (cells) for a selected tower; 0 = none
## Short-lived effects: {kind, from, to, ttl, ...} in cell units. Attack effects (LT-25)
## also carry tower, end, hits, hit_pos, miss, astray, dur (initial ttl), seed.
var effects: Array[Dictionary] = []
var _last_pos: Dictionary[int, Vector2] = {}  ## enemy id -> last drawn position (cells)
var phantom: Array[Vector2i] = []  ## LT-14: cells of the current phantom path (none Lucid)
var _phantom_ttl := 0.0
var _time := 0.0  ## seconds of effects time, drives the flicker
var _fx_rng := RandomNumberGenerator.new()  ## presentation-only; never the sim's RNG
var map_layer: MapLayer  ## LT-41: the cached static map, drawn below everything else here


func _ready() -> void:
	_fx_rng.randomize()
	map_layer = MapLayer.new()
	map_layer.name = "MapLayer"
	map_layer.show_behind_parent = true  # below the phantom, towers, enemies and effects
	add_child(map_layer)
	move_child(map_layer, 0)
	sync_map()


## Hands the sim's current map to the map layer; it redraws only if the map changed.
func sync_map() -> void:
	if game != null and game.sim != null and map_layer != null:
		map_layer.set_map(game.sim.state.map)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell := cell_at((make_input_local(mb) as InputEventMouseButton).position)
	if game.sim.state.map.in_bounds(cell):
		get_viewport().set_input_as_handled()
		cell_clicked.emit(cell)
	else:
		outside_clicked.emit()


## Local pixel position -> grid cell (may be out of bounds).
func cell_at(local: Vector2) -> Vector2i:
	return Vector2i(floori(local.x / CELL), floori(local.y / CELL))


## Grid cell -> top-left in this node's local pixels.
func cell_origin(cell: Vector2i) -> Vector2:
	return origin_of(cell)


static func origin_of(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL


func on_event(ev: SimEvent) -> void:
	match ev.type:
		SimEvent.Type.SHOT:
			var t := game.sim.tower_by_id(ev.id)
			if t != null:
				var fx := _shot_fx(t, ev.data)
				if fx.get("kind", "") == "banish":
					# LT-51: one SHOT per banished enemy; a Pure cast moves 3 at once.
					_add_attack_fx(fx, maxi(MAX_FX_PER_TOWER, t.stats().banish_targets()))
					return
				if fx.get("kind", "") == "dynamite":
					fx["throw_tick"] = ev.tick
				if fx.get("kind", "") == "beam":
					# LT-50: held in sim time until the next SHOT is due (+ grace), so pause
					# and x2 follow the clock; one beam per tower, the new one replaces it.
					fx["end_tick"] = ev.tick + SimTime.ticks(t.stats().fire_interval) \
						+ BEAM_GRACE_TICKS
					_drop_beam(t.id)
				_add_attack_fx(fx)
		SimEvent.Type.BLAST:  # LT-47: the charge explodes (hits real and fake alike)
			var hits: Array = ev.data.get("hits", [])
			effects.append({"kind": "blast", "from": ev.data["at"],
				"radius": ev.data.get("radius", 0.0), "hit_pos": _hit_positions(hits),
				"seed": _fx_rng.randi(), "ttl": BLAST_SECONDS, "dur": BLAST_SECONDS})
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
## change it): sanity_scaling -> "beam" (LT-50), pierce -> "harpoon", fuse_seconds ->
## "dynamite" (LT-47), min_range -> "shell" (LT-48), aoe_radius -> "wave", support level ->
## "aura" ("searchlight" with reveal_fakes, LT-49), banish_cells -> "banish" (LT-51),
## otherwise "tracer".
static func shot_kind(t: SimTower) -> String:
	var s := t.stats()
	if not s.acts():
		return "searchlight" if s.effects.get("reveal_fakes", 0.0) > 0.0 else "aura"
	if s.is_banish():
		return "banish"
	if s.is_beam():
		return "beam"
	if s.effects.get("pierce", 0.0) > 0.0:
		return "harpoon"
	if s.effects.get("fuse_seconds", 0.0) > 0.0:
		return "dynamite"
	if s.min_range > 0.0:
		return "shell"
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
	if e.status.get("bleed_ticks", 0) > 0:  # LT-29: state, per tick
		out.append("bleed")
	if e.status.get("banish_immune_ticks", 0) > 0:  # LT-51: a gate cannot banish it now
		out.append("sealed")
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
	if kind == "aura" or kind == "searchlight":
		return {}
	if kind == "banish":
		# LT-51: `from` / `to` are the banished enemy's spots before and after the move.
		return {"kind": "banish", "tower": t.id, "origin": t.centre(), "from": data["from"],
			"to": data["to"], "hits": data.get("hits", []).duplicate(),
			"astray": data.get("astray", false), "seed": _fx_rng.randi(),
			"ttl": BANISH_SECONDS, "dur": BANISH_SECONDS}
	var hits: Array = data.get("hits", [])
	var to: Vector2 = data["to"]
	var fx := {"kind": kind, "tower": t.id, "from": t.centre(), "to": to, "end": to,
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


## Appends an attack effect, keeping at most `cap` (MAX_FX_PER_TOWER) live ones per tower.
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
		if fx.has("end_tick") and game != null and game.sim != null:
			# LT-47: a lobbed charge lives in sim time (pause and x2 follow the clock).
			fx["ttl"] = delta + (float(fx["end_tick"] - game.sim.state.tick) - alpha) \
				/ SimTime.TICK_RATE
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
	sync_map()  # O(1) unless the map changed; the map itself is drawn by map_layer
	_draw_phantom()
	_draw_auras(s)
	for t in s.towers:
		_draw_tower(t)
	_draw_enemies(s)
	_draw_effects()
	if game.sim.state.map.in_bounds(selected_cell):
		draw_rect(Rect2(cell_origin(selected_cell), Vector2(CELL, CELL)), COLOR_SELECT, false, 2.0)
		if selected_range > 0.0:
			var sc := (Vector2(selected_cell) + Vector2(0.5, 0.5)) * CELL
			draw_arc(sc, selected_range * CELL, 0, TAU, 48, COLOR_SELECT, 1.0)
			var dz := selected_dead_zone()
			if dz > 0.0:  # LT-48: the dead zone, a dashed ring over a faint fill
				draw_circle(sc, dz * CELL, Color(COLOR_LEAK, 0.08))
				_draw_dashed_circle(sc, dz * CELL, Color(COLOR_LEAK, 0.7))


## LT-48: the min_range (cells) of the tower on selected_cell while its range ring shows;
## 0 when none.
func selected_dead_zone() -> float:
	if selected_range <= 0.0 or game == null or game.sim == null:
		return 0.0
	for t in game.sim.state.towers:
		if t.cell == selected_cell:
			return t.stats().min_range
	return 0.0


func _draw_dashed_circle(c: Vector2, r: float, color: Color) -> void:
	var n := maxi(8, int(TAU * r / (DEAD_ZONE_DASH * 2.0)))
	for i in n:
		var a0 := TAU * float(i) / n
		draw_arc(c, r, a0, a0 + TAU / n * 0.5, 3, color, 1.5)


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
		"searchlight":
			return SEARCHLIGHT_COLOR
		"dynamite":
			return DYNAMITE_COLOR
		"shell":
			return SHELL_COLOR
		"beam":
			return BEAM_COLOR
		"banish":
			return BANISH_COLOR
	return Color.BLACK


func _draw_tower(t: SimTower) -> void:
	var r := Rect2(cell_origin(t.cell), Vector2(CELL, CELL)).grow(-6)
	var c := attack_color(shot_kind(t))
	draw_rect(r, COLOR_TOWER)
	draw_rect(r, c, false, 2.0)
	# LT-28: a dark plate under the letter keeps it readable where the beam washes the
	# light tile out (the plate stays dark under the light; the letter's colour is over 1).
	draw_rect(Rect2(r.position + LETTER_PLATE.position, LETTER_PLATE.size), COLOR_LETTER_PLATE)
	draw_string(ThemeDB.fallback_font, r.position + Vector2(8, 20), t.def.glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c)
	# LT-30: a lit tower (a beam sweeps its centre) gets a small bright corner mark.
	if t.lit:
		draw_circle(r.position + Vector2(r.size.x - 6, 6), 3.5, LIT_MARK_COLOR)
	# LT-24 level mark: one pip per level along the bottom, the branch letter at L3.
	for i in t.level + 1:
		draw_rect(Rect2(r.position + Vector2(3 + i * 6, r.size.y - 6), Vector2(4, 4)), Color.BLACK)
	if not t.branch.is_empty():
		draw_string(ThemeDB.fallback_font, r.position + Vector2(r.size.x - 9, 11), t.branch,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)


## Elder Sign wards (LT-25 §1.3): a faint ring at the aura radius with 5 slowly turning
## dashes; brighter and pulsing while a drawn enemy is inside.
func _draw_auras(s: SimState) -> void:
	for t in s.towers:
		var kind := shot_kind(t)
		if kind == "searchlight":
			_draw_searchlight(t)
			continue
		if kind != "aura":
			continue
		var c := t.centre() * CELL
		var r := t.stats().range_cells * CELL
		var a := ward_alpha(t)
		var bright := a > WARD_IDLE_ALPHA
		draw_arc(c, r, 0, TAU, 64, Color(WARD_COLOR, a), 4.0 if bright else 2.0)
		var rot := _time * TAU / WARD_TURN_SECONDS
		for i in 5:
			var st := rot + i * TAU / 5.0
			draw_arc(c, r, st, st + 0.22, 6, Color(WARD_COLOR, minf(1.0, a + 0.15)), 4.0)


## LT-49: the Searchlight's aura: a faint disc and rim at the radius, and a beam wedge
## from the tower to the rim turning once per SEARCH_SWEEP_SECONDS (decoration: what is
## revealed is the whole disc, sim state).
func _draw_searchlight(t: SimTower) -> void:
	var c := t.centre() * CELL
	var r := t.stats().range_cells * CELL
	var a := ward_alpha(t)
	draw_circle(c, r, Color(SEARCHLIGHT_COLOR, SEARCH_DISC_ALPHA * (1.0 + a)))
	draw_arc(c, r, 0, TAU, 64, Color(SEARCHLIGHT_COLOR, a * 0.8), 2.0)
	var dir := _time * TAU / SEARCH_SWEEP_SECONDS
	var pts := PackedVector2Array([c])
	var cols := PackedColorArray([Color(SEARCHLIGHT_COLOR, 0.35 + 0.25 * a)])
	var steps := 8
	for i in steps + 1:
		var ang := dir - SEARCH_CONE + 2.0 * SEARCH_CONE * i / steps
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
		cols.append(Color(SEARCHLIGHT_COLOR, 0.04))
	draw_polygon(pts, cols)


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
			color = Color(REVEALED_BODY, REVEALED_ALPHA)
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
		if marks.has("bleed"):  # two red drops dripping below the body
			for i in 2:
				var ph := fposmod(_time / BLEED_DROP_SECONDS + i * 0.5, 1.0)
				var dc := Color(MARK_BLEED, color.a * (1.0 - ph * 0.7))
				draw_circle(px + Vector2((i - 0.5) * CELL * 0.22, CELL * (0.3 + 0.2 * ph)),
					CELL * 0.09, dc)
		if mad > 0.0:
			draw_arc(px, CELL * 0.25, 0, TAU, 24, Color(COLOR_ENEMY_OUTLINE, color.a * mad), 3.0)
		if marks.has("sealed"):  # LT-51: a silver lid over the body while banish-immune
			draw_arc(px, CELL * BANISH_LID_CELLS, PI * 1.15, PI * 1.85, 10,
				Color(BANISH_COLOR, 0.85 * color.a), 2.0)
		if marks.has("vuln"):  # body outline
			draw_arc(px, CELL * 0.25, 0, TAU, 24, Color(MARK_VULN, color.a), 2.0)
		if e.revealed:  # LT-49: amber ring outside the dashed slow mark, slash across the body
			var mc := Color(REVEALED_MARK, 1.0 - dip)
			draw_arc(px, CELL * REVEALED_RING_CELLS, 0, TAU, 24, mc, 3.0)
			var d := Vector2(1, -1).normalized() * CELL * REVEALED_SLASH_CELLS
			draw_line(px - d, px + d, mc, 3.0)
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
		var ray := CRIT_SPARK_SCALE if fx.get("crit", false) else 1.0  # LT-29
		for p: Vector2 in fx["hit_pos"]:
			for i in 4:
				var v := Vector2.from_angle(PI * 0.25 + i * PI * 0.5)
				draw_line(p * CELL + v * CELL * 0.05, p * CELL + v * CELL * 0.2 * ray,
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
	if el < CHAIN_SECONDS:  # LT-29: dashed steel chain from each pulled enemy to the tower
		var cc := Color(HARPOON_COLOR, 1.0 - el / CHAIN_SECONDS * 0.7)
		var chain: Dictionary = fx.get("chain", {})
		for id: int in chain:
			var p: Vector2 = _last_pos.get(id, chain[id])
			draw_dashed_line(p * CELL, a, cc, 2.0, CHAIN_DASH)
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


## LT-50 Resonator: the held beam. Its end follows the target's drawn position while that
## enemy is live (else the shot's `to`); width and glow grow with `factor` (sanity_factor).
func _draw_beam(fx: Dictionary) -> void:
	var a: Vector2 = fx["from"] * CELL
	var end: Vector2 = fx["to"]
	var e := game.sim.enemy_by_id(fx["target"]) if game != null and game.sim != null else null
	if e != null and e.is_live():
		end = game.sim.enemy_position(e, alpha)
	var b := end * CELL
	# From the tile's rim, not its centre, so the glyph stays readable under the beam.
	a += (b - a).normalized() * minf(CELL * BEAM_RIM_CELLS, a.distance_to(b))
	var fade := clampf(fx["ttl"] / BEAM_FADE, 0.0, 1.0)
	var f: float = fx.get("factor", 1.0)
	var w := BEAM_WIDTH + BEAM_WIDTH_PER_FACTOR * maxf(0.0, f - 1.0)
	var ph := _time * TAU * BEAM_QUIVER_HZ + float(fx["seed"] % 1000) * 0.01
	var glow := Color(BEAM_COLOR, 0.35 * fade)
	draw_line(a, b, glow, w * 3.5)
	draw_polyline(_wave_points(a, b, ph, 5.0, 1.5 + 0.5 * f, 16), Color(BEAM_COLOR, fade), w)
	draw_line(a, b, Color(BEAM_CORE, fade), maxf(1.0, w * 0.4))
	var pulse := 0.5 + 0.5 * sin(ph * 0.5)
	draw_circle(a, CELL * (0.06 + 0.03 * pulse), Color(BEAM_CORE, fade))
	draw_arc(b, CELL * (0.18 + 0.08 * pulse), 0, TAU, 16, Color(BEAM_COLOR, fade), 2.0)
	for i in 3:
		var v := Vector2.from_angle(ph * 0.3 + i * TAU / 3.0)
		draw_line(b + v * CELL * 0.1, b + v * CELL * (0.22 + 0.06 * pulse),
			Color(BEAM_CORE, fade), 1.5)


## LT-51 Silver Key Gate, one banished enemy: a silver thread from the gate to its old
## spot; there a keyhole and four arcs collapsing on a fading ghost body (the fold); a
## dotted trail to the new spot, where a ring opens around the enemy (it is already drawn
## there: the sim moved it without a slide).
func _draw_banish(fx: Dictionary) -> void:
	var el := _elapsed(fx)
	var dur: float = fx["dur"]
	var k := clampf(el / dur, 0.0, 1.0)
	var o: Vector2 = fx["origin"] * CELL
	var a: Vector2 = fx["from"] * CELL
	var b: Vector2 = fx["to"] * CELL
	if el < BANISH_REACH:
		var rf := 1.0 - el / BANISH_REACH
		o += (a - o).normalized() * minf(CELL * BEAM_RIM_CELLS, o.distance_to(a))
		draw_line(o, a, Color(BANISH_COLOR, 0.9 * rf), 2.0)
	if a.distance_to(b) > 1.0:
		draw_dashed_line(a, b, Color(BANISH_COLOR, 0.7 * (1.0 - k)), 2.5, 6.0)
	var fold := clampf(el / BANISH_FOLD, 0.0, 1.0)
	if fold < 1.0:
		var left := 1.0 - fold
		draw_circle(a, CELL * 0.3 * left, Color(BANISH_GHOST, 0.6 * left))
		var r := CELL * (0.22 + 0.4 * left)
		for i in 4:
			var st := i * TAU / 4.0 + fold * PI
			draw_arc(a, r, st, st + TAU / 7.0, 6, Color(BANISH_COLOR, 0.4 + 0.6 * left), 3.0)
	# The keyhole outlasts the fold: the gate's mark on the old spot.
	var kc := Color(BANISH_COLOR, 1.0 - k)
	var hole := CELL * 0.14
	draw_circle(a + Vector2(0, -hole * 0.6), hole, kc)
	draw_colored_polygon(PackedVector2Array([a + Vector2(-hole * 0.45, 0),
		a + Vector2(hole * 0.45, 0), a + Vector2(hole * 0.8, hole * 1.9),
		a + Vector2(-hole * 0.8, hole * 1.9)]), kc)
	if el >= BANISH_FOLD * 0.5:
		var open := clampf((el - BANISH_FOLD * 0.5) / (dur - BANISH_FOLD * 0.5), 0.0, 1.0)
		draw_arc(b, CELL * (0.25 + 0.35 * open), 0, TAU, 24, Color(BANISH_COLOR, 1.0 - open), 3.0)


## LT-48 Coast battery: a muzzle flash and a smoke puff drifting off the gun, the shell (a
## bright slug with a smoke trail) racing to `end`, then the impact: a ring to the HE
## `radius` (or a small burst) with debris and a flash on each hit enemy. A miss lands
## beside the aim point and throws up only grey dust.
func _draw_shell(fx: Dictionary) -> void:
	var el := _elapsed(fx)
	var a: Vector2 = fx["from"] * CELL
	var b: Vector2 = fx["end"] * CELL
	var dir := (b - a).normalized()
	var k_all := clampf(el / SHELL_SECONDS, 0.0, 1.0)
	# Smoke puff at the gun, rising and fading over the whole effect.
	draw_circle(a + dir * CELL * 0.35 + Vector2(0, -CELL * 0.25 * k_all),
		CELL * (0.18 + 0.22 * k_all), Color(SHELL_SMOKE, 0.5 * (1.0 - k_all)))
	if el < SHELL_MUZZLE:
		var mk := 1.0 - el / SHELL_MUZZLE
		draw_circle(a + dir * CELL * 0.3, CELL * 0.2 * (0.6 + 0.4 * mk), Color(3.0, 2.4, 1.4, mk))
	if el < SHELL_TRAVEL:
		var kk := clampf(el / SHELL_TRAVEL, 0.0, 1.0)
		var head := a.lerp(b, kk)
		var tail := head - dir * minf(CELL * 1.2, head.distance_to(a))
		draw_line(tail, head, Color(SHELL_SMOKE, 0.45), 4.0)
		draw_line(head - dir * CELL * 0.3, head, SHELL_COLOR, 4.0)
		draw_circle(head, 3.5, Color(3.0, 2.6, 2.0))
		return
	var ie := el - SHELL_TRAVEL
	var k := clampf(ie / (SHELL_SECONDS - SHELL_TRAVEL), 0.0, 1.0)
	var grow := 1.0 - (1.0 - k) * (1.0 - k)
	if fx["miss"]:
		draw_circle(b + Vector2(0, -CELL * 0.2 * k), CELL * (0.15 + 0.25 * grow),
			Color(SHELL_SMOKE, 0.6 * (1.0 - k)))
		return
	var radius: float = fx.get("radius", 0.0)
	var r := CELL * (radius if radius > 0.0 else SHELL_IMPACT_CELLS)
	draw_circle(b, r * (0.5 + 0.5 * grow), Color(SHELL_SMOKE, 0.4 * (1.0 - k)))
	if ie < BLAST_FLASH:
		draw_circle(b, r * 0.5, Color(3.0, 2.6, 1.6, 1.0 - ie / BLAST_FLASH))
	draw_arc(b, r * (0.3 + 0.7 * grow), 0, TAU, 40, Color(SHELL_COLOR, 1.0 - k * k), 3.0)
	var sd: int = fx["seed"]
	for i in 6:
		var ang := float((sd >> i) % 628) * 0.01 + i * TAU / 6.0
		draw_circle(b + Vector2.from_angle(ang) * r * (0.3 + 0.8 * grow), 2.0,
			Color(SHELL_COLOR, 1.0 - k))
	if ie < WAVE_FLASH:
		var ray := CRIT_SPARK_SCALE if fx.get("crit", false) else 1.0
		for p: Vector2 in fx["hit_pos"]:
			draw_arc(p * CELL, CELL * 0.3 * ray, 0, TAU, 20,
				Color(SHELL_COLOR, 1.0 - ie / WAVE_FLASH), 2.0)


## LT-47 Dynamite crew: the stick flies on an arc to `to` (a dotted trail behind it, its
## fuse spitting sparks), then lies there under a pulsing ring of the blast radius until
## detonate_tick; the BLAST event takes over. A dud's fuse dies and it smokes instead.
func _draw_charge(fx: Dictionary) -> void:
	var el := float(game.sim.state.tick - int(fx["throw_tick"])) + alpha  # ticks
	var fuse := maxf(1.0, float(int(fx["detonate_tick"]) - int(fx["throw_tick"])))
	var flight := minf(float(DYN_FLIGHT_TICKS), fuse)
	var a: Vector2 = fx["from"] * CELL
	var b: Vector2 = fx["to"] * CELL
	var h := _arc_lift(a, b) * CELL * (DYN_ARC_BASE + DYN_ARC_PER_CELL * a.distance_to(b) / CELL)
	var k := clampf(el / flight, 0.0, 1.0)
	var pos := _arc_point(a, b, h, k)
	if k < 1.0:
		draw_circle(a.lerp(b, k), 3.0, Color(0, 0, 0, 0.35))  # its shadow on the ground
		var n := 10
		for i in n:
			var kk := k * float(i) / n
			draw_circle(_arc_point(a, b, h, kk), 1.5,
				Color(DYNAMITE_COLOR, 0.15 + 0.5 * float(i) / n))
		var dir := (_arc_point(a, b, h, minf(1.0, k + 0.05)) - pos).normalized()
		var spin := dir.rotated(el * 0.6)
		_draw_stick(pos, spin, true, el)
		return
	var lying := el - flight
	var left := fuse - el  # ticks to detonation
	if left > 0.0:
		var urgency := 1.0 - clampf(left / maxf(1.0, fuse - flight), 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(_time * TAU * (2.0 + 6.0 * urgency))
		var r := CELL * float(fx["radius"])
		draw_circle(b, r, Color(DYNAMITE_COLOR, 0.04 + 0.06 * urgency))
		draw_arc(b, r, 0, TAU, 40, Color(DYNAMITE_COLOR, 0.25 + 0.35 * pulse * urgency + 0.1), 1.5)
		_draw_stick(b, Vector2.RIGHT.rotated(0.35), not fx["miss"] or left > fuse * 0.3, lying)
	else:
		# A dud: the stick lies dead and a grey puff rises.
		var dk := clampf(-left / DYN_DUD_TICKS, 0.0, 1.0)
		_draw_stick(b, Vector2.RIGHT.rotated(0.35), false, lying)
		draw_circle(b + Vector2(0, -CELL * 0.3 * dk), CELL * (0.15 + 0.2 * dk),
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
func _draw_stick(p: Vector2, dir: Vector2, burning: bool, el: float) -> void:
	var half := dir * DYN_STICK_PX
	draw_line(p - half, p + half, Color(0.05, 0.02, 0.02), 7.0)
	draw_line(p - half * 0.9, p + half * 0.9, DYN_STICK_COLOR, 5.0)
	var tip := p + half + dir * 3.0
	draw_line(p + half, tip, Color(0.9, 0.85, 0.7), 1.5)
	if not burning:
		return
	var flick := 0.6 + 0.4 * absf(sin(el * 2.3 + _time * 31.0))
	draw_circle(tip, 2.0 + 2.0 * flick, Color(DYNAMITE_COLOR, flick))
	for i in 3:
		var v := Vector2.from_angle(_time * 17.0 + i * TAU / 3.0)
		draw_line(tip + v * 2.0, tip + v * (4.0 + 4.0 * flick), Color(2.4, 2.2, 1.2, flick), 1.0)


## LT-47: a white flash, an orange ring racing out to the blast radius over a fading smoke
## disc, flying debris, and a flash ring on each hit enemy.
func _draw_blast(fx: Dictionary) -> void:
	var el := _elapsed(fx)
	var c: Vector2 = fx["from"] * CELL
	var r := CELL * float(fx["radius"])
	var k := clampf(el / BLAST_SECONDS, 0.0, 1.0)
	var grow := 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)  # fast out, slow end
	draw_circle(c, r * (0.6 + 0.4 * grow), Color(DYN_SMOKE, 0.45 * (1.0 - k)))
	if el < BLAST_FLASH:
		draw_circle(c, r * 0.7, Color(3.0, 2.6, 1.6, 1.0 - el / BLAST_FLASH))
	draw_arc(c, r * (0.2 + 0.8 * grow), 0, TAU, 48, Color(DYNAMITE_COLOR, 1.0 - k * k), 4.0)
	var sd: int = fx["seed"]
	for i in BLAST_DEBRIS:
		var ang := float((sd >> i) % 628) * 0.01 + i * TAU / BLAST_DEBRIS
		var d := r * (0.3 + 0.9 * grow)
		draw_circle(c + Vector2.from_angle(ang) * d, 2.0, Color(DYNAMITE_COLOR, 1.0 - k))
	if el < WAVE_FLASH:
		for p: Vector2 in fx["hit_pos"]:
			draw_arc(p * CELL, CELL * 0.3, 0, TAU, 20,
				Color(DYNAMITE_COLOR, 1.0 - el / WAVE_FLASH), 2.0)


## LT-41: the static map layer (water, buildable and path cells, grid, start, lighthouse).
## Its draw commands are cached by the engine and re-issued only on set_map with a new map.
## Nothing here depends on towers, enemies, sanity or day/night (lighting is the canvas's).
class MapLayer extends Node2D:
	var map: MapDef

	## Redraws only when `m` is a different map from the one drawn.
	func set_map(m: MapDef) -> void:
		if m == map:
			return
		map = m
		queue_redraw()

	func _draw() -> void:
		if map == null:
			return
		var m := map
		for y in m.height:
			for x in m.width:
				var c := Vector2i(x, y)
				var color := Board.COLOR_WATER
				match m.kind_at(c):
					MapDef.Kind.BUILDABLE:
						color = Board.COLOR_BUILDABLE
					MapDef.Kind.PATH:
						color = Board.COLOR_PATH
				var r := Rect2(Board.origin_of(c), Vector2(CELL, CELL))
				draw_rect(r, color)
				draw_rect(r, Board.COLOR_GRID, false, 1.0)
		draw_rect(Rect2(Board.origin_of(m.spawn), Vector2(CELL, CELL)).grow(-4),
			Board.COLOR_START)
		var lh := Rect2(Board.origin_of(m.lighthouse), Vector2(CELL, CELL)).grow(-4)
		draw_rect(lh, Board.COLOR_LIGHTHOUSE)
		draw_string(ThemeDB.fallback_font, lh.position + Vector2(9, 24), "L",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.BLACK)
