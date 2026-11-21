class_name PhantomLayer
extends BoardLayer
## LT-84 (LT-65 §3.4): the LT-14 phantom path, drawn first of the board layers (right above
## the map): while Fraying / in Madness (SanityFx.flicker > 0) a flickering stretch of path
## off the real one. Owns its state and its own presentation RNG (never the sim's).

## LT-14 visual tunables.
@export var phantom_seconds := Vector2(0.9, 2.2)  ## lifetime range of one phantom path
@export var phantom_cells := Vector2i(4, 9)  ## length range of a phantom path
@export var phantom_alpha := 0.7

var phantom: Array[Vector2i] = []  ## LT-14: cells of the current phantom path (none Lucid)
var _phantom_ttl := 0.0
var _rng := RandomNumberGenerator.new()  ## presentation-only; never the sim's RNG


func _ready() -> void:
	_rng.randomize()


func _draw() -> void:
	if not has_sim() or phantom.is_empty():
		return
	var a := phantom_alpha * (1.0 - board.flicker_dip(-1)) \
		* clampf(board.flicker_strength() / 0.6, 0.0, 1.0)
	if a <= 0.02:
		return
	var c := Board.COLOR_PATH
	c.a = a
	for cell in phantom:
		view.fill_cell(self, cell, c, 2.0)


## While Fraying / in Madness a phantom stretch of path appears off the real one, flickers
## and moves elsewhere every second or two (GDD §5.3 "phantom path flickers on screen").
func tick(delta: float) -> void:
	if board.flicker_strength() <= 0.0:
		phantom.clear()
		return
	_phantom_ttl -= delta
	if _phantom_ttl <= 0.0 or phantom.is_empty():
		_phantom_ttl = _rng.randf_range(phantom_seconds.x, phantom_seconds.y)
		phantom = _new_phantom()


## A random walk that leaves the real path sideways and wanders over non-path cells.
func _new_phantom() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s := game.sim.state
	var m := s.map
	var path_cells: Array[Vector2i] = []
	for c in m.grid.cells():
		if m.kind_at(c) == MapDef.Kind.PATH:
			path_cells.append(c)
	if path_cells.is_empty():
		return out
	var cur: Vector2i = path_cells[_rng.randi_range(0, path_cells.size() - 1)]
	var dir := _random_step(m.grid, cur)
	var length := _rng.randi_range(phantom_cells.x, phantom_cells.y)
	for step in length * 3:
		if out.size() >= length:
			break
		if _rng.randf() < 0.3:
			dir = _random_step(m.grid, cur)
		var nxt := cur + dir
		if not m.grid.contains(nxt) or m.kind_at(nxt) == MapDef.Kind.PATH \
				or s.tower_at.has(nxt) or out.has(nxt):
			dir = _random_step(m.grid, cur)
			continue
		out.append(nxt)
		cur = nxt
	return out


## A random neighbour offset of `cell` (this layer's RNG only).
func _random_step(grid: GridTopology, cell: Vector2i) -> Vector2i:
	var nbs := grid.neighbours(cell)
	return nbs[_rng.randi_range(0, nbs.size() - 1)] - cell
