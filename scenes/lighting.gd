class_name Lighting
extends Node2D
## LT-8 baseline lighting, drawn in board space (child of Board): a CanvasModulate
## darkens the world canvas (the UI CanvasLayer is not affected), a rotating lighthouse
## beam and glow, one small light per tower, and a sea fog shader over water cells.
## Visual only: reads `game.snapshot` (LT-85), never changes the sim. Nothing here depends on the
## enemy kind, so fake enemies (LT-12) render exactly like real ones.
## LT-27 §4 day/night: a render-only `night` factor (0 = day, 1 = night) eases toward 1 in
## a wave and 0 by day (BUILD, DONE); it blends the ambient from AMBIENT_DAY to
## AMBIENT_NIGHT, scales the beam, the lighthouse glow and the tower lights (the lamp is
## dark by day) and thins the fog by day. It reads `snapshot.phase` only and keeps easing
## while paused.

const FOG_SHADER := preload("res://shaders/sea_fog.gdshader")

## Ambient level outside lights at night. Not total darkness: enemies stay readable.
const AMBIENT_NIGHT := Color(0.30, 0.32, 0.42)
const AMBIENT_DAY := Color(0.80, 0.80, 0.76)  ## LT-27 §4: grey daylight
const NIGHT_EASE_SECONDS := 0.6  ## time constant of the day <-> night fade
const FOG_DAY_ALPHA := 0.45  ## fog opacity by day, relative to the night fog
const BEAM_COLOR := Color(1.0, 0.94, 0.72)
const BEAM_ENERGY := 2.6  ## LT-58: was 1.6 ("readable but weak", LT-54 playtest)
## LT-58 cone texture shape (fractions of the half angle / of the reach):
const BEAM_FILL_EDGE_START := 0.8  ## the fill stays solid up to here, then drops to 0 at 1.0 (was 0.55)
## The rim term lifts the 0.8..1.0 falloff back towards full (the fill is already 1 below 0.8,
## so the clamp hides it there): a wider solid cone with a sharper edge, not a brighter band.
const BEAM_RIM_START := 0.62
const BEAM_RIM_PEAK := 0.9
const BEAM_RIM_GAIN := 0.35  ## how far the falloff zone is lifted (0 = plain smoothstep edge)
const BEAM_FALLOFF_POWER := 0.5  ## brightness ~ (1 - d)^power along the length (was 0.8)
const LIGHTHOUSE_GLOW_CELLS := 3.0
const TOWER_LIGHT_COLOR := Color(1.0, 0.78, 0.48)
const TOWER_LIGHT_ENERGY := 0.9
const TOWER_LIGHT_CELLS := 2.2  ## radius
## Compatibility renderer: all lights hit the board's layer canvas items (LT-84; draw calls
## measured unchanged vs one item), so keep the count small. Towers past the cap stay unlit.
const MAX_TOWER_LIGHTS := 12
const BEAM_TEX_SIZE := 256
## LT-69: the flare light, a disc around the lighthouse whose bright core covers the board.
const FLARE_ENERGY := 1.3
const FLARE_EASE_IN := 0.15  ## seconds from the shot to full energy
const FLARE_EASE_OUT := 0.5  ## the last seconds of the flare fade to 0
const FLARE_TEX_SIZE := 256
## The flare texture's near-flat bright core ends at this fraction of its radius
## (_flare_texture); flare_cover_cells() puts every board corner inside it.
const FLARE_CORE := 0.7
## LT-92: a tiny light over FxLayer.WARMUP_RECT in the first WARM_FRAMES game frames (boot
## iterations 2-4: Main shows its Loading frame in iteration 1 and adds the Game in
## iteration 2). Every canvas item whose rect meets it, FxLayer with its warm-up among them,
## draws lit there while the first game frame is loading anyway. It compiles the lit
## shader variants that the first night otherwise compiled on the wave-call frame (frame B)
## and when the beam's rect first reached the warm-up corner (frame C). It must stay small:
## a board-covering one leaves the unlit variants to the first frame after it (iteration 5,
## a new stall); a small one leaves enough unlit items to compile them in frame A.
const WARM_FRAMES := 3
const WARM_ENERGY := 0.0  ## invisible; a light at 0 still selects the lit variants (LT-92 S6, 2/2 runs)
const WARM_COVER := 2.5  ## the light's texture spans this many times the rect's longer side

static var _beam_texs: Dictionary[int, ImageTexture] = {}  ## half angle (milli-rad) -> cone
static var _glow_tex: GradientTexture2D
static var _flare_tex: GradientTexture2D

var game: Game
var modulate_node: CanvasModulate
var beam: PointLight2D  ## the first beam (always present)
var beams: Array[PointLight2D] = []  ## LT-30: one per sim.beam_count(), beam is beams[0]
var glow: PointLight2D
var flare_light: PointLight2D  ## LT-69: the whole-board flare, visible only while one burns
var fog: Node2D
var _tower_lights: Dictionary[int, PointLight2D] = {}  ## tower id -> light
var night := 0.0  ## LT-27 §4: 0 = day, 1 = night; eases toward night_target()
var warm_light: PointLight2D  ## LT-92: null once WARM_FRAMES frames have drawn it
var _warm_left := WARM_FRAMES


## `world` is the node whose canvas gets darkened (the Game); the lights live here.
func setup(p_game: Game, world: Node) -> void:
	game = p_game
	modulate_node = CanvasModulate.new()
	modulate_node.name = "Darkness"
	night = night_target(game.snapshot.phase)
	modulate_node.color = ambient(night)
	world.add_child(modulate_node)


## LT-27 §4: 1 during a wave (night), 0 otherwise (day: BUILD, DONE, NONE).
static func night_target(phase: SimState.Phase) -> float:
	return 1.0 if phase == SimState.Phase.WAVE else 0.0


## The world ambient for a `night` factor: AMBIENT_DAY at 0, AMBIENT_NIGHT at 1.
static func ambient(p_night: float) -> Color:
	return AMBIENT_DAY.lerp(AMBIENT_NIGHT, clampf(p_night, 0.0, 1.0))


func _ready() -> void:
	var m := game.snapshot.map
	var view := game.board.view
	var lh_center := view.ground(m.grid.centre(m.lighthouse))

	fog = SeaFog.new()
	fog.name = "SeaFog"
	fog.map = m
	fog.view = view
	var mat := ShaderMaterial.new()
	mat.shader = FOG_SHADER
	fog.material = mat
	add_child(fog)

	glow = _light("LighthouseGlow", _glow_texture(), BEAM_COLOR, 1.0,
		view.cells_to_px(LIGHTHOUSE_GLOW_CELLS * 2.0) / 256.0)
	glow.position = lh_center
	flare_light = _light("FlareLight", _flare_texture(), BEAM_COLOR, 0.0, 1.0)
	flare_light.position = lh_center
	_sync_beams()
	beam = beams[0]
	_apply_night()
	_add_warm_light()


func _process(delta: float) -> void:
	_tick_warm_light()
	_sync_beams()
	_sync_tower_lights()
	ease_night(delta)
	_sync_flare()


## LT-92: the WarmLight over FxLayer.WARMUP_RECT (board-local; this node is the Board's child
## at its origin). Visible from the first frame and independent of `night`: _apply_night
## never touches it, so every day/night rule stays as it is.
func _add_warm_light() -> void:
	var r := FxLayer.WARMUP_RECT
	warm_light = _light("WarmLight", _glow_texture(), BEAM_COLOR, WARM_ENERGY,
		maxf(r.size.x, r.size.y) * WARM_COVER / _glow_texture().get_width())
	warm_light.position = r.get_center()
	_warm_left = WARM_FRAMES


## Frees the WarmLight in the first _process after WARM_FRAMES frames: it is drawn in the
## frames whose _process left it in place, WARM_FRAMES of them (boot: iterations 2-4, freed
## in iteration 5's _process, before that frame draws).
func _tick_warm_light() -> void:
	if warm_light == null:
		return
	if _warm_left > 0:
		_warm_left -= 1
		return
	remove_child(warm_light)
	warm_light.queue_free()
	warm_light = null


## Moves `night` toward the phase's target by 1 - exp(-delta / NIGHT_EASE_SECONDS) of the
## gap (real seconds, so it also runs while paused) and applies it.
func ease_night(delta: float) -> void:
	var target := night_target(game.snapshot.phase)
	night += (target - night) * (1.0 - exp(-maxf(delta, 0.0) / NIGHT_EASE_SECONDS))
	if absf(target - night) < 0.001:
		night = target
	_apply_night()


func _apply_night() -> void:
	modulate_node.color = ambient(night)
	for b: PointLight2D in beams:
		b.energy = BEAM_ENERGY * night
		b.visible = night > 0.0
	glow.energy = night
	glow.visible = night > 0.0
	for l: PointLight2D in _tower_lights.values():
		l.energy = TOWER_LIGHT_ENERGY * night
		l.visible = night > 0.0
	fog.modulate.a = lerpf(FOG_DAY_ALPHA, 1.0, night)


## LT-30 §3.2: the beams follow the sim. Count from beam_count() (a lighthouse upgrade adds
## beams), rotation from beam_directions(alpha) (tick + alpha, no timer of its own; empty by
## day, then the last rotation stays), cone width from the config (a flare no longer
## widens it: LT-69 lights the whole board instead, _sync_flare).
func _sync_beams() -> void:
	var sim := game.sim
	var view := game.board.view
	var lh_center := view.ground(game.snapshot.map.grid.centre(
		game.snapshot.map.lighthouse))
	var cfg := sim.config.economy
	var tex := _beam_texture(atan(cfg.beam.half_width_ratio))
	var tex_scale := view.cells_to_px(cfg.beam.reach_cells * 2.0) / BEAM_TEX_SIZE
	var want := sim.beam_count()
	while beams.size() < want:
		var b := _light("Beam%d" % beams.size(), tex, BEAM_COLOR, BEAM_ENERGY * night, tex_scale)
		b.position = lh_center
		b.rotation = PI  # starts pointing left (the sim's first direction)
		b.visible = night > 0.0
		beams.append(b)
	while beams.size() > want:
		beams.pop_back().queue_free()
	var dirs := sim.beam_directions(game.clock.alpha())
	for i in beams.size():
		beams[i].texture = tex
		beams[i].texture_scale = tex_scale
		if i < dirs.size():
			beams[i].rotation = dirs[i].angle()


## LT-69: the flare light's disc has a radius of flare_cover_cells() (the whole board inside
## its bright core) and burns while snapshot.flare_ticks_left > 0 (a read): energy eases in
## over FLARE_EASE_IN after the shot and out over the last FLARE_EASE_OUT seconds, x night.
func _sync_flare() -> void:
	var sim := game.sim
	flare_light.texture_scale = game.board.view.cells_to_px(
		flare_cover_cells(game.snapshot.map) * 2.0) / FLARE_TEX_SIZE
	flare_light.energy = FLARE_ENERGY * night * flare_strength(sim)
	flare_light.visible = flare_light.energy > 0.0


## LT-69: the flare disc's radius in cells: the farthest board corner from the lighthouse
## cell centre, divided by FLARE_CORE so the whole board lies in the bright core.
static func flare_cover_cells(m: MapDef) -> float:
	var c := m.grid.centre(m.lighthouse)
	var far := 0.0
	var b := m.grid.bounds()
	for corner: Vector2 in [b.position, Vector2(b.end.x, b.position.y),
			Vector2(b.position.x, b.end.y), b.end]:
		far = maxf(far, c.distance_to(corner))
	return far / FLARE_CORE


## 0..1 brightness of the flare now: 0 when none burns, ramps up over FLARE_EASE_IN seconds
## after the shot and down over the last FLARE_EASE_OUT seconds of flare_seconds() (the
## burn time at the current lighthouse level; an upgrade mid-burn can only happen by day,
## when no flare burns).
static func flare_strength(sim: Simulation) -> float:
	var burn := sim.flare_burn()  # LT-76: the sim's own burn length
	var left: int = burn["left_ticks"]
	if left <= 0:
		return 0.0
	var total: int = burn["total_ticks"]
	var since := float(total - left + 1) * SimTime.DT
	var until := float(left) * SimTime.DT
	return clampf(since / FLARE_EASE_IN, 0.0, 1.0) * clampf(until / FLARE_EASE_OUT, 0.0, 1.0)


func _sync_tower_lights() -> void:
	var seen: Dictionary[int, bool] = {}
	for t in game.snapshot.towers:
		if seen.size() >= MAX_TOWER_LIGHTS:
			break
		seen[t.id] = true
		if not _tower_lights.has(t.id):
			var l := _light("TowerLight%d" % t.id, _glow_texture(), TOWER_LIGHT_COLOR,
				TOWER_LIGHT_ENERGY * night,
				game.board.view.cells_to_px(TOWER_LIGHT_CELLS * 2.0) / 256.0)
			l.visible = night > 0.0
			_tower_lights[t.id] = l
		# LT-117: placed on every sync, so a lifted tower's light follows it.
		_tower_lights[t.id].position = \
			game.board.view.ground(game.snapshot.map.grid.centre(t.cell))
	for id in _tower_lights.keys():
		if not seen.has(id):
			_tower_lights[id].queue_free()
			_tower_lights.erase(id)


func _light(node_name: String, tex: Texture2D, color: Color, energy: float,
		tex_scale: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.name = node_name
	l.texture = tex
	l.color = color
	l.energy = energy
	l.texture_scale = tex_scale
	l.blend_mode = Light2D.BLEND_MODE_ADD
	add_child(l)
	return l


## Soft radial falloff, 256 px across.
static func _glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(0, 0, 0, 0))
		g.add_point(0.5, Color(0.45, 0.45, 0.45, 0.45))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(0.5, 0.0)
		_glow_tex.width = 256
		_glow_tex.height = 256
	return _glow_tex


## The flare disc, FLARE_TEX_SIZE across: near-flat bright core out to FLARE_CORE (LT-69:
## the whole board is lit in the sim, flare_cover_cells() keeps it inside) falling to 0 at the rim.
static func _flare_texture() -> GradientTexture2D:
	if _flare_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(0, 0, 0, 0))
		g.add_point(FLARE_CORE, Color(0.8, 0.8, 0.8, 0.8))
		g.add_point(0.94, Color(0.55, 0.55, 0.55, 0.55))
		_flare_tex = GradientTexture2D.new()
		_flare_tex.gradient = g
		_flare_tex.fill = GradientTexture2D.FILL_RADIAL
		_flare_tex.fill_from = Vector2(0.5, 0.5)
		_flare_tex.fill_to = Vector2(0.5, 0.0)
		_flare_tex.width = FLARE_TEX_SIZE
		_flare_tex.height = FLARE_TEX_SIZE
	return _flare_tex


## A cone of half angle `half_angle` (radians) pointing along +x from the texture centre
## (the light's position), cached per angle, with soft edges and a falloff along its length. Built once on the CPU: no shader needed.
static func _beam_texture(half_angle: float) -> ImageTexture:
	var key := roundi(half_angle * 1000.0)
	if not _beam_texs.has(key):
		var n := BEAM_TEX_SIZE
		var half := n * 0.5
		var img := Image.create(n, n, false, Image.FORMAT_LA8)
		for y in n:
			for x in n:
				var v := Vector2(x + 0.5 - half, y + 0.5 - half)
				var d := v.length() / half
				var a := 0.0
				if d < 1.0 and v.x > 0.0:
					var t := absf(v.angle()) / half_angle  # 0 on the axis, 1 at the edge
					var edge := 1.0 - smoothstep(BEAM_FILL_EDGE_START, 1.0, t)
					var rim := smoothstep(BEAM_RIM_START, BEAM_RIM_PEAK, t) * edge * BEAM_RIM_GAIN
					a = minf(edge + rim, 1.0) * pow(1.0 - d, BEAM_FALLOFF_POWER) \
						* smoothstep(0.0, 0.04, d)
				a = maxf(a, 0.0)
				img.set_pixel(x, y, Color(a, a, a, a))
		_beam_texs[key] = ImageTexture.create_from_image(img)
	return _beam_texs[key]


## Fog quads over every water cell; the shader does the noise.
class SeaFog extends Node2D:
	var map: MapDef
	var view: BoardView  ## the board's view (tiles from GridTopology.polygon)

	func _draw() -> void:
		for c in map.grid.cells():
			if map.kind_at(c) == MapDef.Kind.WATER:
				view.fill_cell(self, c, Color.WHITE)
