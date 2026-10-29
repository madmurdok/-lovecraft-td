class_name Simulation
extends RefCounted
## The plain-script game simulation (design note LT-4). Advanced one fixed tick at a
## time by step(); scenes read `state` directly and drain one-shot events.
## Same config + seed + command log -> same events and state (§4).

var state: SimState
var config: GameConfig
var events: Array[SimEvent] = []

var _spawner: SimSpawner
var _rng: SimRng
var _ground_route: SimRoute


func _init(p_config: GameConfig, run_seed: int) -> void:
	config = p_config
	_rng = SimRng.new(run_seed)
	state = SimState.new()
	state.map = config.map
	state.lighthouse_hp = config.economy.lighthouse_hp
	_ground_route = SimRoute.from_cells(config.map.path)


## Without a spawner the run never wins (nothing can be "exhausted").
func set_spawner(s: SimSpawner) -> void:
	_spawner = s


func rng(stream: SimRng.Stream) -> RandomNumberGenerator:
	return _rng.stream(stream)


## Advances exactly one tick in the fixed order of §3.3. No-op once the outcome is set.
func step() -> void:
	if state.outcome != SimState.Outcome.NONE:
		return
	# 1. Tick and per-tick modifiers.
	state.tick += 1
	for e in state.enemies:
		e.reset_modifiers()
	# 2. Effect systems (auras, slows, stuns): LT-6/LT-11.
	# 3. Movement.
	_move()
	# 4. Leaks.
	_leak()
	# 5. Towers fire / damage: LT-6, LT-11, LT-13.
	# 6. Sanity: LT-10.
	# 7. Spawning.
	if _spawner != null:
		_spawner.tick(self)
	# 8. Remove dead and leaked enemies.
	_compact()
	# 9. Outcome.
	_check_outcome()


## Spawns `def_id` at the start of its route; a `pack` enemy spawns min..max of them
## (rolled on SPAWN) on the same tick at the same spot. Returns the first new id
## (a pack's ids are consecutive), or 0 if `def_id` is unknown.
func spawn_enemy(def_id: String, is_fake := false) -> int:
	if not config.enemies.has(def_id):
		push_error("Simulation.spawn_enemy: unknown enemy \"%s\"" % def_id)
		return 0
	var def: EnemyDef = config.enemies[def_id]
	var count := 1
	if def.traits.has("pack"):
		var pack: Dictionary = def.traits["pack"]
		count = rng(SimRng.Stream.SPAWN).randi_range(int(pack["min"]), int(pack["max"]))
	var first_id := state.next_id
	for i in count:
		var e := SimEnemy.new()
		e.id = state.next_id
		state.next_id += 1
		e.def = def
		e.hp = def.hp
		e.max_hp = def.hp
		e.is_fake = is_fake
		e.spawn_tick = state.tick
		e.base_units_per_tick = SimTime.units_per_tick(def.speed)
		# Flyers start at S too (owner decision, §7 Q3) and fly straight to L.
		e.route = SimRoute.straight(state.map.spawn, state.map.lighthouse) if def.flying \
			else _ground_route
		state.enemies.append(e)
		_emit(SimEvent.Type.SPAWNED, e.id, {"def": def_id})
	return first_id


## The one armor rule for every damage source (§3.4). Returns the damage taken.
## A killed enemy emits DIED and is removed at the end of the current/next tick.
func apply_damage(enemy_id: int, amount: float, source: String) -> float:
	var e := enemy_by_id(enemy_id)
	if e == null or not e.is_live():
		return 0.0
	var armor := maxf(0.0, e.def.armor + e.armor_bonus)
	var taken := maxf(0.0, amount - armor) * e.damage_taken_mult
	e.hp -= taken
	if e.hp <= 0.0:
		e.dead = true
		_emit(SimEvent.Type.DIED, e.id, {"source": source, "reward": e.def.reward})
	return taken


## The enemy with this id, or null (also null once removed).
func enemy_by_id(id: int) -> SimEnemy:
	for e in state.enemies:
		if e.id == id:
			return e
	return null


## Position in cell units, interpolated between the last two ticks by `alpha` (0..1).
func enemy_position(e: SimEnemy, alpha: float) -> Vector2:
	var d := roundi(lerpf(float(e.prev_distance), float(e.distance), alpha))
	return e.route.position_at(d)


## Every event since the last drain, oldest first; clears the buffer.
func drain_events() -> Array[SimEvent]:
	var out := events
	events = []
	return out


func _emit(type: SimEvent.Type, id: int, data: Dictionary) -> void:
	events.append(SimEvent.new(type, state.tick, id, data))


func _move() -> void:
	for e in state.enemies:
		if not e.is_live():
			continue
		e.prev_distance = e.distance
		var step_units := roundi(e.base_units_per_tick * e.speed_mult)
		e.distance = clampi(e.distance + step_units, 0, e.route.length)


## Every enemy at the end of its route leaks; all leaks of the tick are processed (§5).
func _leak() -> void:
	for e in state.enemies:
		if not e.is_live() or e.distance != e.route.length:
			continue
		e.leaked = true
		var damage := 0 if e.is_fake else e.def.leak_damage
		state.lighthouse_hp = maxi(0, state.lighthouse_hp - damage)
		_emit(SimEvent.Type.LEAKED, e.id,
			{"damage": damage, "hp_after": state.lighthouse_hp, "fake": e.is_fake})


func _compact() -> void:
	var live: Array[SimEnemy] = []
	for e in state.enemies:
		if e.is_live():
			live.append(e)
	state.enemies = live


## Lose first, so a leak that empties HP on the last enemy is a loss (§5).
func _check_outcome() -> void:
	if state.lighthouse_hp == 0:
		state.outcome = SimState.Outcome.LOST
		_emit(SimEvent.Type.OUTCOME, 0, {"result": "lost"})
		return
	if _spawner == null or not _spawner.is_exhausted():
		return
	for e in state.enemies:
		if not e.is_fake:
			return
	state.outcome = SimState.Outcome.WON
	_emit(SimEvent.Type.OUTCOME, 0, {"result": "won"})
