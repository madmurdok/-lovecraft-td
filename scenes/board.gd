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
## LT-70 §5: a lit tower's plate is tinted warm, a shadowed one cold violet (plate_color),
## each with its corner dot; by day (BUILD) the selected caster previews its radius with a
## faint tint on the towers it would light or shadow (preview_cast).
## LT-41 (LT-38 P2): the static map (cells, grid, start, lighthouse) lives in a child
## MapLayer drawn behind the board's own draw and redrawn only when the map changes, not
## every frame. Same parent, so the same CanvasModulate and light mask apply to it.
## LT-35: every pixel comes from `view` (BoardView): picking, positions, lengths and tiles.
## LT-84 (LT-65 §3.4): the drawing is split into child layers, each a BoardLayer with its
## own _draw, in draw order above the MapLayer: PhantomLayer (phantom path), EntityLayer
## (auras, towers, enemies, allies), FxLayer (effects, and the LT-62/LT-90 warm-up on the
## same canvas item), OverlayLayer (selection, range and dead-zone rings). The Board keeps
## input, the signals, event forwarding, the shared render state (alpha, time, last_pos,
## flicker) and the palette both entities and effects use; a board redraw queues every
## layer. The selection the overlay draws is a SelectionModel owned by the Game.

signal cell_clicked(cell: Vector2i)
signal outside_clicked  ## LT-28: a left click no control took that misses the grid

## LT-84: the palette shared by several layers: the map colours (MapLayer), the leak red
## (FxLayer's flash, OverlayLayer's dead zone) and each attack look's colour (EntityLayer's
## tower letter, FxLayer's effect). Constants used by one layer live in that layer.
const COLOR_BUILDABLE := Color(0.30, 0.36, 0.28)
const COLOR_PATH := Color(0.55, 0.48, 0.36)
const COLOR_WATER := Color(0.12, 0.20, 0.32)
const COLOR_GRID := Color(0, 0, 0, 0.25)
const COLOR_START := Color(0.45, 0.20, 0.20)
const COLOR_LIGHTHOUSE := Color(0.95, 0.90, 0.55)
const COLOR_LEAK := Color(1, 0.1, 0.1)
const TRACER_COLOR := Color(2.2, 2.0, 1.2)
const HARPOON_COLOR := Color(0.4, 1.3, 2.6)
const WAVE_RIM := Color(1.8, 0.6, 2.4)
## LT-47 Dynamite crew: the charge flies DYN_FLIGHT_TICKS (or the whole fuse if shorter) on
## an arc DYN_ARC_BASE + DYN_ARC_PER_CELL x distance cells high, then lies with a burning
## fuse until its detonate_tick; a dud fizzles out in grey smoke for DYN_DUD_TICKS more.
const DYNAMITE_COLOR := Color(2.6, 1.4, 0.45)
## LT-48 Coast battery: a muzzle flash and smoke puff at the gun, a heavy shell racing to
## `to` in SHELL_TRAVEL with a smoke trail, then an impact: a dust burst (AP) or a ring out
## to aoe_radius (HE). A miss lands off target and only throws up dust.
const SHELL_COLOR := Color(2.5, 0.8, 0.55)
## LT-50 Tillinghast Resonator (LT-46 P14): one held beam per tower, a violet glow with a
## bright quivering core from the tower to its (moving) target, a pulsing node at the tower
## and a crackling ring on the target. SHOT every 6 ticks refreshes it instead of adding a
## new effect; it fades BEAM_FADE seconds after the last SHOT's interval ran out. Thicker and
## brighter as sanity falls (the SHOT's sanity_factor).
const BEAM_COLOR := Color(1.5, 0.55, 2.7)
## LT-51 Silver Key Gate: per banished enemy, a silver thread from the gate to the enemy's
## old spot, a keyhole there while the enemy "folds" (arcs collapsing on a fading ghost),
## a dotted trail back to where it reappears and a ring opening around it there. Banish
## immunity shows as a silver lid arc over the body.
const BANISH_COLOR := Color(2.0, 2.1, 2.6)

## LT-14 visual tunables.
@export var flicker_rate := 13.0  ## flicker steps per second

var game: Game
var alpha := 0.0  ## render interpolation between the last two ticks
var time := 0.0  ## seconds of effects time, drives the flicker, pulses and sweeps
var last_pos: Dictionary[int, Vector2] = {}  ## enemy id -> last drawn position (cells)
## LT-84: what the overlay outlines; the Game hands its own model in before adding the board.
var selection := SelectionModel.new()
var map_layer: MapLayer  ## LT-41: the cached static map, drawn below everything else here
## LT-84: the drawing layers, in draw order. One set before _ready is kept (a test seam).
var phantom_layer: PhantomLayer
var entity_layer: EntityLayer
var fx_layer: FxLayer
var overlay_layer: OverlayLayer
var view := BoardView.new()  ## LT-35: cells <-> pixels; the only holder of the pixel scale


func _ready() -> void:
	position = view.origin()
	map_layer = MapLayer.new()
	map_layer.view = view
	map_layer.name = "MapLayer"
	map_layer.show_behind_parent = true  # below the phantom, towers, enemies and effects
	add_child(map_layer)
	move_child(map_layer, 0)
	sync_map()
	phantom_layer = _add_layer(phantom_layer if phantom_layer != null else PhantomLayer.new(),
		"PhantomLayer")
	entity_layer = _add_layer(entity_layer if entity_layer != null else EntityLayer.new(),
		"EntityLayer")
	fx_layer = _add_layer(fx_layer if fx_layer != null else FxLayer.new(), "FxLayer")
	overlay_layer = _add_layer(overlay_layer if overlay_layer != null else OverlayLayer.new(),
		"OverlayLayer")
	selection.changed.connect(queue_redraw)


func _add_layer(layer: BoardLayer, layer_name: String) -> BoardLayer:
	layer.board = self
	layer.view = view
	layer.name = layer_name
	add_child(layer)
	return layer


## Hands the sim's current map to the map layer; it redraws only if the map changed.
func sync_map() -> void:
	if game != null and game.sim != null and map_layer != null:
		view.grid = game.sim.state.map.grid
		map_layer.set_map(game.sim.state.map)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	sync_map()
	var cell := view.cell_at_screen((game.make_input_local(mb) as InputEventMouseButton).position)
	if cell != BoardView.OFF_BOARD:
		get_viewport().set_input_as_handled()
		cell_clicked.emit(cell)
	else:
		outside_clicked.emit()


## Sim events for the effects (SHOT, BLAST, DIED, FAKE_DISSOLVED, LEAKED): FxLayer.
func on_event(ev: SimEvent) -> void:
	fx_layer.on_event(ev)


## LT-25 §1: the attack look from the tower's current stats (so upgrades and branches
## change it): sanity_scaling -> "beam" (LT-50), pierce -> "harpoon", fuse_seconds ->
## "dynamite" (LT-47), min_range -> "shell" (LT-48), aoe_radius -> "wave", support level ->
## "aura" ("searchlight" with reveal_fakes, LT-49), banish_cells -> "banish" (LT-51),
## summon_max -> "summon" (LT-52: no SHOT, its units are drawn by _draw_allies),
## otherwise "tracer".
## LT-103 §2.2: one `match` on Level.mode plus its two modifiers (reveal_fakes, min_range).
static func shot_kind(t: SimTower) -> String:
	var s := t.stats()
	match s.mode():
		EffectCatalog.Mode.AURA:
			return "searchlight" if s.effects.get("reveal_fakes", 0.0) > 0.0 else "aura"
		EffectCatalog.Mode.BANISH:
			return "banish"
		EffectCatalog.Mode.SUMMON:
			return "summon"
		EffectCatalog.Mode.BEAM:
			return "beam"
		EffectCatalog.Mode.LINE:
			return "harpoon"
		EffectCatalog.Mode.FUSE:
			return "dynamite"
		EffectCatalog.Mode.BLAST:
			return "shell" if s.min_range > 0.0 else "wave"
	return "shell" if s.min_range > 0.0 else "tracer"  # BURST, SINGLE


## LT-70 §5: what a level casts at night: "light", "shadow" or "" (SelectionModel.cast).
static func cast_of(s: TowerDef.Level) -> String:
	if s == null:
		return ""
	if s.casts_light():
		return "light"
	if s.casts_shadow():
		return "shadow"
	return ""


## Advances effects time by `delta` seconds: the effects' ttl (FxLayer) and the phantom
## path (PhantomLayer). The Game calls it once per frame.
func tick_effects(delta: float) -> void:
	time += delta
	fx_layer.tick(delta)
	phantom_layer.tick(delta)


func flicker_strength() -> float:
	return game.sanity_fx.flicker if game != null and game.sanity_fx != null else 0.0


## 0..1 dip for one flicker step; seeded by step and `key`, so each enemy twitches on
## its own beat. Uses only the id and time: real and fake enemies flicker alike.
func flicker_dip(key: int) -> float:
	var step := floori(time * flicker_rate)
	var h := absf(sin(float(step) * 12.9898 + float(key) * 78.233) * 43758.5453)
	h -= floorf(h)
	return 1.0 if h > 0.72 else h * 0.35


## Syncs the map, then redraws every layer (a board redraw is a whole-board redraw).
func _draw() -> void:
	if game == null or game.sim == null:
		return
	sync_map()  # O(1) unless the map changed; the map itself is drawn by map_layer
	phantom_layer.queue_redraw()
	entity_layer.queue_redraw()
	fx_layer.queue_redraw()
	overlay_layer.queue_redraw()


## LT-41: the static map layer (water, buildable and path cells, grid, start, lighthouse).
## Its draw commands are cached by the engine and re-issued only on set_map with a new map.
## Nothing here depends on towers, enemies, sanity or day/night (lighting is the canvas's).
class MapLayer extends Node2D:
	var map: MapDef
	var view := BoardView.new()  ## the board's view once added (tiles from GridTopology.polygon)

	## Redraws only when `m` is a different map from the one drawn.
	func set_map(m: MapDef) -> void:
		if m == map:
			return
		map = m
		view.grid = m.grid
		queue_redraw()

	func _draw() -> void:
		if map == null:
			return
		var m := map
		for c in m.grid.cells():
			var color := Board.COLOR_WATER
			match m.kind_at(c):
				MapDef.Kind.BUILDABLE:
					color = Board.COLOR_BUILDABLE
				MapDef.Kind.PATH:
					color = Board.COLOR_PATH
			var r := view.cell_rect(c)
			draw_rect(r, color)
			draw_rect(r, Board.COLOR_GRID, false, 1.0)
		draw_rect(view.cell_rect(m.spawn).grow(-4),
			Board.COLOR_START)
		var lh := view.cell_rect(m.lighthouse).grow(-4)
		draw_rect(lh, Board.COLOR_LIGHTHOUSE)
		draw_string(ThemeDB.fallback_font, lh.position + Vector2(9, 24), "L",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.BLACK)
