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
## LT-106: the trait API, set by the facade once (set_trait_host).
var _host: TraitHost


func _init(ctx: SimContext) -> void:
	_ctx = ctx
	_state = ctx.state
	_config = ctx.config
	_ground_route = SimRoute.from_cells(_config.map.grid, _config.map.path)


## The facade wires the allied units' compaction once (AllySystem.compact).
func set_ally_compact(compact_allies: Callable) -> void:
	_compact_allies = compact_allies


## The facade wires the trait API once (LT-106), before the first spawn.
func set_trait_host(host: TraitHost) -> void:
	_host = host


## Spawns `def_id` at the start of its route (one spawn event). LT-106: a `pack` enemy's
## PackTrait.on_spawn then rolls min..max members (on SPAWN, or SANITY for a fake, LT-12 §2)
## and queues members 1..count-1 (queue_pack_member; LT-63: a real one enters in slot 7
## before the spawner's spawns, a fake one in slot 8 after the dawn check). Returns the
## first new id, or 0 if `def_id` is unknown or the outcome is set (then nothing changes and
## no event is emitted).
func spawn_enemy(def_id: String, is_fake := false) -> int:
	if _state.outcome != SimState.Outcome.NONE:
		return 0
	if not _config.enemies.has(def_id):
		push_error("Simulation.spawn_enemy: unknown enemy \"%s\"" % def_id)
		return 0
	return _enter(_config.enemies[def_id], is_fake, 0, true)


## LT-63 / LT-106 (TraitHost.queue_pack_member): one pack member enters at `due_tick` with
## pack_of `pack_of`, queue order (release_pack_members).
func queue_pack_member(due_tick: int, def: EnemyDef, is_fake: bool, pack_of: int) -> void:
	_pack_queue.append([due_tick, def, is_fake, pack_of])


## LT-63: true while a real pack member is queued and not entered yet (a wave is not
## cleared and the run is not won before it has entered).
func has_queued_real_members() -> bool:
	for q: Array in _pack_queue:
		if not q[2]:
			return true
	return false


## LT-63: every queued pack member with is_fake == `fakes` whose due tick has come enters,
## queue order (slot 7 for real members, slot 8 for fake ones). Draws no RNG itself (a
## member's on_spawn hooks run with from_event false; pack does not roll again). Anything a
## hook queues meanwhile goes after the members still waiting.
func release_pack_members(fakes: bool) -> void:
	if _pack_queue.is_empty():
		return
	var queued := _pack_queue
	_pack_queue = []
	var left: Array = []
	for q: Array in queued:
		if bool(q[2]) != fakes or int(q[0]) > _state.tick:
			left.append(q)
		else:
			_enter(q[1], q[2], q[3], false)
	left.append_array(_pack_queue)
	_pack_queue = left


## LT-67 (debug_end_night): the pack queue is emptied.
func clear_pack_queue() -> void:
	_pack_queue.clear()


## One enemy of `def` enters at the start of its route on this tick, with a new id and
## SPAWNED {def}, then its on_spawn trait hooks (LT-106; `from_event` false for a queued pack
## member); returns that id. LT-111: HP and base speed are scaled by the current
## wave's hp_mult / speed_mult (fakes and queued pack members alike); base_max_hp keeps
## def.hp for the HP caps. Unconditional multiply: x 1.0 is exact, so absent fields
## change nothing.
func _enter(def: EnemyDef, is_fake: bool, pack_of: int, from_event: bool) -> int:
	var m := _wave_mults()
	var e := SimEnemy.new()
	e.id = _ctx.next_id()
	e.def = def
	e.hp = def.hp * m[0]
	e.max_hp = e.hp
	e.base_max_hp = def.hp
	e.is_fake = is_fake
	e.pack_of = pack_of
	e.spawn_tick = _state.tick
	# One rounding: units_per_tick of the scaled speed (LT-111 §3). A tiny speed_mult must
	# not round a moving enemy down to 0 (it would never arrive and the wave never clear):
	# floor at 1 unit/tick when the unscaled speed moves. At x1.0 scaled == unscaled, so
	# the floor changes nothing there.
	var units := SimTime.units_per_tick(def.speed * m[1])
	e.base_units_per_tick = maxi(units, mini(SimTime.units_per_tick(def.speed), 1))
	# Flyers start at S too (owner decision, §7 Q3) and fly straight to L.
	e.route = _ground_route
	if def.flying:
		e.route = SimRoute.straight(_state.map.grid, _state.map.spawn, _state.map.lighthouse)
	_state.enemies.append(e)
	_ctx.emit(SimEvent.Type.SPAWNED, e.id, {"def": def.id})
	if def.hooks & EnemyTrait.ON_SPAWN:
		for i in def.hook_traits.size():
			var tr := def.hook_traits[i]
			if tr.hooks() & EnemyTrait.ON_SPAWN:
				tr.on_spawn(_host, e, def.hook_params[i], from_event)
	return e.id


## LT-111: [hp_mult, speed_mult] of the current (or last started) wave; [1.0, 1.0] before
## wave 1, past the last wave, or with no waves config (ScriptedSpawner, test spawns).
func _wave_mults() -> Array[float]:
	var waves := _config.waves
	var i := _state.wave_index
	if waves == null or i < 1 or i > waves.waves.size():
		return [1.0, 1.0]
	var w: WavesConfig.Wave = waves.waves[i - 1]
	return [w.hp_mult, w.speed_mult]


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
## A fake never leaks: it dissolves there (LT-12 §3), no HP change, no LEAKED and no
## on_leak trait hook (LT-106; a real leak runs them after LEAKED).
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
		var d := e.def
		if d.hooks & EnemyTrait.ON_LEAK:
			for i in d.hook_traits.size():
				var tr := d.hook_traits[i]
				if tr.hooks() & EnemyTrait.ON_LEAK:
					tr.on_leak(_host, e, d.hook_params[i])


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
