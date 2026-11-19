class_name SpawnSystem
extends RefCounted
## LT-83 (B8 of LT-65 §3.1 Spawn): where enemies enter, march, leak and leave. Owns
## state.enemies (append in _enter, compaction), state.lighthouse_hp (leaks), e.distance /
## e.prev_distance (move, push_back), the LT-63 pack queue and the fakes' dissolve. Built once
## by the sim facade, which orders the step slots and forwards the public names. Combat holds
## this system (push_back). Spawn needs no system of its own except the allied units' slot-8
## compaction, which the facade wires through a method Callable (set_ally_compact; it keeps
## the object id, not a reference, so there is no RefCounted cycle).

var _ctx: SimContext
var _state: SimState
var _config: GameConfig
var _ground_route: SimRoute
## AllySystem.compact, set by the facade after both systems exist.
var _compact_allies: Callable
## LT-63: pack members not entered yet, queue order: [due_tick, EnemyDef, is_fake, pack_of].
## Sim only (fakes are queued too, LT-12 §1); real members enter in slot 7, fake ones in
## slot 8 after the dawn check (release_pack_members).
var _pack_queue: Array = []


func _init(ctx: SimContext) -> void:
	_ctx = ctx
	_state = ctx.state
	_config = ctx.config
	_ground_route = SimRoute.from_cells(_config.map.grid, _config.map.path)


## The facade wires the allied units' compaction once (AllySystem.compact).
func set_ally_compact(compact_allies: Callable) -> void:
	_compact_allies = compact_allies


## Spawns `def_id` at the start of its route; a `pack` enemy spawns min..max of them
## (rolled on SPAWN, or on SANITY for a fake so hallucinations never change real pack
## sizes, LT-12 §2). LT-63: only the first member enters now; member k (1..count-1) is
## queued and enters at the start of the route on tick now + k x ticks(pack.spacing_s), so
## members never stack on one spot: a real one in slot 7 before the spawner's spawns, a
## fake one in slot 8 after the wave system's dawn check. Every member's pack_of is the first member's id. Returns the first new id,
## or 0 if `def_id` is unknown or the outcome is set (then nothing changes and no event is
## emitted).
func spawn_enemy(def_id: String, is_fake := false) -> int:
	if _state.outcome != SimState.Outcome.NONE:
		return 0
	if not _config.enemies.has(def_id):
		push_error("Simulation.spawn_enemy: unknown enemy \"%s\"" % def_id)
		return 0
	var def: EnemyDef = _config.enemies[def_id]
	if not def.traits.has("pack"):
		return _enter(def, is_fake, 0)
	var pack: Dictionary = def.traits["pack"]
	var stream := SimRng.Stream.SANITY if is_fake else SimRng.Stream.SPAWN
	var count := _ctx.rng(stream).randi_range(int(pack["min"]), int(pack["max"]))
	var spacing := SimTime.ticks(pack["spacing_s"])
	var first_id := _enter(def, is_fake, _state.next_id)
	for k in range(1, count):
		_pack_queue.append([_state.tick + k * spacing, def, is_fake, first_id])
	return first_id


## LT-63: true while a real pack member is queued and not entered yet (a wave is not
## cleared and the run is not won before it has entered).
func has_queued_real_members() -> bool:
	for q: Array in _pack_queue:
		if not q[2]:
			return true
	return false


## LT-63: every queued pack member with is_fake == `fakes` whose due tick has come enters,
## queue order (slot 7 for real members, slot 8 for fake ones). Draws no RNG.
func release_pack_members(fakes: bool) -> void:
	if _pack_queue.is_empty():
		return
	var left: Array = []
	for q: Array in _pack_queue:
		if bool(q[2]) != fakes or int(q[0]) > _state.tick:
			left.append(q)
		else:
			_enter(q[1], q[2], q[3])
	_pack_queue = left


## LT-67 (debug_end_night): the pack queue is emptied.
func clear_pack_queue() -> void:
	_pack_queue.clear()


## One enemy of `def` enters at the start of its route on this tick, with a new id and
## SPAWNED {def}; returns that id.
func _enter(def: EnemyDef, is_fake: bool, pack_of: int) -> int:
	var e := SimEnemy.new()
	e.id = _ctx.next_id()
	e.def = def
	e.hp = def.hp
	e.max_hp = def.hp
	e.is_fake = is_fake
	e.pack_of = pack_of
	e.spawn_tick = _state.tick
	e.base_units_per_tick = SimTime.units_per_tick(def.speed)
	# Flyers start at S too (owner decision, §7 Q3) and fly straight to L.
	e.route = _ground_route
	if def.flying:
		e.route = SimRoute.straight(_state.map.grid, _state.map.spawn, _state.map.lighthouse)
	_state.enemies.append(e)
	_ctx.emit(SimEvent.Type.SPAWNED, e.id, {"def": def.id})
	return e.id


## Slot 3: every live enemy walks one tick along its route.
func move() -> void:
	for e in _state.enemies:
		if not e.is_live():
			continue
		e.prev_distance = e.distance
		var step_units := roundi(e.base_units_per_tick * e.speed_mult)
		e.distance = clampi(e.distance + step_units, 0, e.route.length)


## LT-29 P5: moves `e` `cells` back along its own route (path walkers along the path,
## flyers along their straight line), never before its start. prev_distance follows, so the
## render does not slide it backwards through the tick. Distance only decreases, so leak
## and the outcome check are unaffected.
func push_back(e: SimEnemy, cells: float) -> void:
	e.distance = maxi(0, e.distance - roundi(cells * SimTime.UNITS_PER_CELL))
	e.prev_distance = e.distance


## Every enemy at the end of its route leaks; all leaks of the tick are processed (§5).
## A fake never leaks: it dissolves there (LT-12 §3), no HP change and no LEAKED.
func leak() -> void:
	for e in _state.enemies:
		if not e.is_live() or e.distance != e.route.length:
			continue
		if e.is_fake:
			e.dissolved = true
			_ctx.emit(SimEvent.Type.FAKE_DISSOLVED, e.id, {"reason": "lighthouse"})
			continue
		e.leaked = true
		_state.lighthouse_hp = maxi(0, _state.lighthouse_hp - e.def.leak_damage)
		_ctx.emit(SimEvent.Type.LEAKED, e.id,
			{"damage": e.def.leak_damage, "hp_after": _state.lighthouse_hp})


## LT-12 §5 (called by the wave director when a wave is cleared): every live fake, in id
## order, is marked dissolved with FAKE_DISSOLVED {reason}; then state.enemies is
## compacted again, so the build phase starts with no enemy in `state`. Fake pack members
## still queued (LT-63), due on this tick or later, are dropped without an event: they
## never entered.
func dissolve_fakes(reason: String) -> void:
	_pack_queue = _pack_queue.filter(func(q: Array) -> bool: return not q[2])
	for e in _state.enemies:
		if e.is_live() and e.is_fake:
			e.dissolved = true
			_ctx.emit(SimEvent.Type.FAKE_DISSOLVED, e.id, {"reason": reason})
	compact()


## Slot 8: dead and leaked enemies leave state.enemies, then the gone allies leave
## state.allies (the same order as before LT-83).
func compact() -> void:
	var live: Array[SimEnemy] = []
	for e in _state.enemies:
		if e.is_live():
			live.append(e)
	_state.enemies = live
	_compact_allies.call()
