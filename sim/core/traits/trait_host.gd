class_name TraitHost
extends RefCounted
## LT-106 T5: the only API an enemy trait sees. Built once by the sim facade after the
## systems; holds the shared context and method Callables (object id, no RefCounted cycle).
## A later trait adds the one method it needs here.
## LT-105 G12: modify_tower is the traits' one write into the tower modifier channel.

var _ctx: SimContext
var _queue_pack_member: Callable
var _lift_tower: Callable


## `lift_tower` may be left out by a test that wires systems by hand without a facade.
func _init(ctx: SimContext, queue_pack_member: Callable, lift_tower := Callable()) -> void:
	_ctx = ctx
	_queue_pack_member = queue_pack_member
	_lift_tower = lift_tower


func tick() -> int:
	return _ctx.state.tick


## LT-117: the 1-based number of the current or last started wave (state.wave_index).
func wave() -> int:
	return _ctx.state.wave_index


## LT-117: the tower on the cell under `e`'s current position (grid.cell_at), or null.
func tower_under(e: SimEnemy) -> SimTower:
	var cell := _ctx.state.map.grid.cell_at(e.route.position_at(e.distance))
	var id: int = _ctx.state.tower_at.get(cell, -1)
	if id < 0:
		return null
	for t in _ctx.state.towers:
		if t.id == id:
			return t
	return null


## LT-117 Q2: the free buildable cells exactly `steps` topology steps from `t`'s cell, in
## grid.cells() order: on the board, buildable (never path, lighthouse or water), no tower.
func drop_candidates(t: SimTower, steps: int) -> Array[Vector2i]:
	var grid := _ctx.state.map.grid
	var out: Array[Vector2i] = []
	for c in grid.cells():
		if c != t.cell and grid.steps(t.cell, c) == steps and _ctx.state.map.is_buildable(c) \
				and not _ctx.state.tower_at.has(c):
			out.append(c)
	return out


## A draw on `real_stream` for a real enemy, on SANITY for a fake (LT-12 §2): hallucinations
## never move a real stream.
func randi_range(e: SimEnemy, real_stream: SimRng.Stream, from: int, to: int) -> int:
	return _ctx.randi_range(SimRng.Stream.SANITY if e.is_fake else real_stream, from, to)


func randf(e: SimEnemy, real_stream: SimRng.Stream) -> float:
	return _ctx.randf(SimRng.Stream.SANITY if e.is_fake else real_stream)


## LT-63: one pack member enters at `due_tick` (SpawnSystem.queue_pack_member).
func queue_pack_member(due_tick: int, def: EnemyDef, is_fake: bool, pack_of: int) -> void:
	_queue_pack_member.call(due_tick, def, is_fake, pack_of)


## LT-105: composes into `t`'s modifier channel this tick (slot 2, near_tower only).
func modify_tower(t: SimTower, power: float, interval: float, miss: float, no_miss := false,
		off := false) -> void:
	t.add_modifiers(power, interval, miss, no_miss, off)


## LT-117: moves `t` to `to` (or leaves it when to == t.cell), disables it for `ticks` and
## emits TOWER_LIFTED (through the sim facade, the one tower_at writer).
func lift_tower(t: SimTower, to: Vector2i, ticks: int, by: int) -> void:
	_lift_tower.call(t, to, ticks, by)
