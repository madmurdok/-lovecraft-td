class_name Lighting
extends Node2D
## LT-8 baseline lighting, drawn in board space (child of Board): a CanvasModulate
## darkens the world canvas (the UI CanvasLayer is not affected), a rotating lighthouse
## beam and glow, one small light per tower, and a sea fog shader over water cells.
## Visual only: reads `game.sim.state`, never changes it. Nothing here depends on the
## enemy kind, so fake enemies (LT-12) render exactly like real ones.

const FOG_SHADER := preload("res://shaders/sea_fog.gdshader")

## Ambient level outside lights. Not total darkness: enemies stay readable at the edge.
const AMBIENT := Color(0.30, 0.32, 0.42)
const BEAM_COLOR := Color(1.0, 0.94, 0.72)
const BEAM_ENERGY := 1.6
const BEAM_SPEED := 0.45  ## radians per second (about one turn every 14 s)
const BEAM_REACH_CELLS := 16.0
const BEAM_HALF_ANGLE := 0.24  ## radians
const LIGHTHOUSE_GLOW_CELLS := 3.0
const TOWER_LIGHT_COLOR := Color(1.0, 0.78, 0.48)
const TOWER_LIGHT_ENERGY := 0.9
const TOWER_LIGHT_CELLS := 2.2  ## radius
## Compatibility renderer: all lights hit the one board canvas item, so keep the count
## small. Towers past the cap stay unlit (still visible under the ambient).
const MAX_TOWER_LIGHTS := 12
const BEAM_TEX_SIZE := 256

static var _beam_tex: ImageTexture
static var _glow_tex: GradientTexture2D

var game: Game
var modulate_node: CanvasModulate
var beam: PointLight2D
var glow: PointLight2D
var fog: Node2D
var _tower_lights: Dictionary[int, PointLight2D] = {}  ## tower id -> light


## `world` is the node whose canvas gets darkened (the Game); the lights live here.
func setup(p_game: Game, world: Node) -> void:
	game = p_game
	modulate_node = CanvasModulate.new()
	modulate_node.name = "Darkness"
	modulate_node.color = AMBIENT
	world.add_child(modulate_node)


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
	beam = _light("Beam", _beam_texture(), BEAM_COLOR, BEAM_ENERGY,
		BEAM_REACH_CELLS * 2.0 * Board.CELL / BEAM_TEX_SIZE)
	beam.position = lh_center
	beam.rotation = PI  # starts pointing left; sweeps up over the land first


func _process(delta: float) -> void:
	beam.rotation = wrapf(beam.rotation + BEAM_SPEED * delta, -PI, PI)
	_sync_tower_lights()


func _sync_tower_lights() -> void:
	var seen: Dictionary[int, bool] = {}
	for t in game.sim.state.towers:
		if seen.size() >= MAX_TOWER_LIGHTS:
			break
		seen[t.id] = true
		if not _tower_lights.has(t.id):
			var l := _light("TowerLight%d" % t.id, _glow_texture(), TOWER_LIGHT_COLOR,
				TOWER_LIGHT_ENERGY, TOWER_LIGHT_CELLS * 2.0 * Board.CELL / 256.0)
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


## A cone pointing along +x from the texture centre (the light's position), with soft
## edges and a falloff along its length. Built once on the CPU: no shader needed.
static func _beam_texture() -> ImageTexture:
	if _beam_tex == null:
		var n := BEAM_TEX_SIZE
		var half := n * 0.5
		var img := Image.create(n, n, false, Image.FORMAT_LA8)
		for y in n:
			for x in n:
				var v := Vector2(x + 0.5 - half, y + 0.5 - half)
				var d := v.length() / half
				var a := 0.0
				if d < 1.0 and v.x > 0.0:
					var edge := 1.0 - smoothstep(BEAM_HALF_ANGLE * 0.55, BEAM_HALF_ANGLE,
						absf(v.angle()))
					a = edge * pow(1.0 - d, 0.8) * smoothstep(0.0, 0.04, d)
				a = maxf(a, 0.0)
				img.set_pixel(x, y, Color(a, a, a, a))
		_beam_tex = ImageTexture.create_from_image(img)
	return _beam_tex


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
