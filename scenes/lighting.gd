class_name Lighting
extends Node2D
## LT-8 baseline lighting, drawn in board space (child of Board): a CanvasModulate
## darkens the world canvas (the UI CanvasLayer is not affected), a rotating lighthouse
## beam and glow, one small light per tower, and a sea fog shader over water cells.
## Visual only: reads `game.sim.state`, never changes it. Nothing here depends on the
## enemy kind, so fake enemies (LT-12) render exactly like real ones.
## LT-27 §4 day/night: a render-only `night` factor (0 = day, 1 = night) eases toward 1 in
## a wave and 0 by day (BUILD, DONE); it blends the ambient from AMBIENT_DAY to
## AMBIENT_NIGHT, scales the beam, the lighthouse glow and the tower lights (the lamp is
## dark by day) and thins the fog by day. It reads `state.phase` only and keeps easing
## while paused.

const FOG_SHADER := preload("res://shaders/sea_fog.gdshader")

## Ambient level outside lights at night. Not total darkness: enemies stay readable.
const AMBIENT_NIGHT := Color(0.30, 0.32, 0.42)
const AMBIENT_DAY := Color(0.80, 0.80, 0.76)  ## LT-27 §4: grey daylight
const NIGHT_EASE_SECONDS := 0.6  ## time constant of the day <-> night fade
const FOG_DAY_ALPHA := 0.45  ## fog opacity by day, relative to the night fog
const BEAM_COLOR := Color(1.0, 0.94, 0.72)
const BEAM_ENERGY := 1.6
const LIGHTHOUSE_GLOW_CELLS := 3.0
const TOWER_LIGHT_COLOR := Color(1.0, 0.78, 0.48)
const TOWER_LIGHT_ENERGY := 0.9
const TOWER_LIGHT_CELLS := 2.2  ## radius
## Compatibility renderer: all lights hit the one board canvas item, so keep the count
## small. Towers past the cap stay unlit (still visible under the ambient).
const MAX_TOWER_LIGHTS := 12
const BEAM_TEX_SIZE := 256

static var _beam_texs: Dictionary[int, ImageTexture] = {}  ## half angle (milli-rad) -> cone
static var _glow_tex: GradientTexture2D

var game: Game
var modulate_node: CanvasModulate
var beam: PointLight2D  ## the first beam (always present)
var beams: Array[PointLight2D] = []  ## LT-30: one per sim.beam_count(), beam is beams[0]
var glow: PointLight2D
var fog: Node2D
var _tower_lights: Dictionary[int, PointLight2D] = {}  ## tower id -> light
var night := 0.0  ## LT-27 §4: 0 = day, 1 = night; eases toward night_target()


## `world` is the node whose canvas gets darkened (the Game); the lights live here.
func setup(p_game: Game, world: Node) -> void:
	game = p_game
	modulate_node = CanvasModulate.new()
	modulate_node.name = "Darkness"
	night = night_target(game.sim.state.phase)
	modulate_node.color = ambient(night)
	world.add_child(modulate_node)


## LT-27 §4: 1 during a wave (night), 0 otherwise (day: BUILD, DONE, NONE).
static func night_target(phase: SimState.Phase) -> float:
	return 1.0 if phase == SimState.Phase.WAVE else 0.0


## The world ambient for a `night` factor: AMBIENT_DAY at 0, AMBIENT_NIGHT at 1.
static func ambient(p_night: float) -> Color:
	return AMBIENT_DAY.lerp(AMBIENT_NIGHT, clampf(p_night, 0.0, 1.0))


func _ready() -> void:
	var m := game.sim.state.map
	var lh_center := (Vector2(m.lighthouse) + Vector2(0.5, 0.5)) * Board.CELL

	fog = SeaFog.new()
	fog.name = "SeaFog"
	fog.map = m
	var mat := ShaderMaterial.new()
	mat.shader = FOG_SHADER
	fog.material = mat
	add_child(fog)

	glow = _light("LighthouseGlow", _glow_texture(), BEAM_COLOR, 1.0,
		LIGHTHOUSE_GLOW_CELLS * 2.0 * Board.CELL / 256.0)
	glow.position = lh_center
	_sync_beams()
	beam = beams[0]
	_apply_night()


func _process(delta: float) -> void:
	_sync_beams()
	_sync_tower_lights()
	ease_night(delta)


## Moves `night` toward the phase's target by 1 - exp(-delta / NIGHT_EASE_SECONDS) of the
## gap (real seconds, so it also runs while paused) and applies it.
func ease_night(delta: float) -> void:
	var target := night_target(game.sim.state.phase)
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
## day, then the last rotation stays), cone width from the config, widened while a flare
## burns (state.flare_ticks_left, a read).
func _sync_beams() -> void:
	var sim := game.sim
	var lh_center := (Vector2(sim.state.map.lighthouse) + Vector2(0.5, 0.5)) * Board.CELL
	var cfg := sim.config.economy
	var k := cfg.beam.half_width_ratio
	if cfg.flare != null and sim.state.flare_ticks_left > 0:
		k *= cfg.flare.width_mult
	var tex := _beam_texture(atan(k))
	var tex_scale := cfg.beam.reach_cells * 2.0 * Board.CELL / BEAM_TEX_SIZE
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


func _sync_tower_lights() -> void:
	var seen: Dictionary[int, bool] = {}
	for t in game.sim.state.towers:
		if seen.size() >= MAX_TOWER_LIGHTS:
			break
		seen[t.id] = true
		if not _tower_lights.has(t.id):
			var l := _light("TowerLight%d" % t.id, _glow_texture(), TOWER_LIGHT_COLOR,
				TOWER_LIGHT_ENERGY * night, TOWER_LIGHT_CELLS * 2.0 * Board.CELL / 256.0)
			l.visible = night > 0.0
			l.position = (Vector2(t.cell) + Vector2(0.5, 0.5)) * Board.CELL
			_tower_lights[t.id] = l
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
					var edge := 1.0 - smoothstep(half_angle * 0.55, half_angle,
						absf(v.angle()))
					a = edge * pow(1.0 - d, 0.8) * smoothstep(0.0, 0.04, d)
				a = maxf(a, 0.0)
				img.set_pixel(x, y, Color(a, a, a, a))
		_beam_texs[key] = ImageTexture.create_from_image(img)
	return _beam_texs[key]


## Fog quads over every water cell; the shader does the noise.
class SeaFog extends Node2D:
	var map: MapDef

	func _draw() -> void:
		for y in map.height:
			for x in map.width:
				var c := Vector2i(x, y)
				if map.kind_at(c) == MapDef.Kind.WATER:
					draw_rect(Rect2(Vector2(c) * Board.CELL, Vector2(Board.CELL, Board.CELL)),
						Color.WHITE)
