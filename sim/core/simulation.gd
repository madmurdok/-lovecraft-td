class_name Simulation
extends RefCounted
## The plain-script game simulation (design note LT-4). Advanced one fixed tick at a
## time by step(); scenes read `state` directly and drain one-shot events.
## Same config + seed + command log -> same events and state (§4).

## Result of a player command (build/sell). OK = applied; anything else = rejected and
## nothing changed (no gold, no event, no command_log entry).
enum CommandResult {
	OK,
	OUTCOME_REACHED,  ## the run is over; every command is refused
	UNKNOWN_TOWER,  ## no such tower def
	NOT_AVAILABLE,  ## tower kind not playable yet (occult towers: LT-11)
	NOT_BUILDABLE,  ## path, water, the lighthouse or out of bounds
	OCCUPIED,  ## another tower stands on the cell
	NOT_ENOUGH_GOLD,
	NO_SUCH_TOWER,  ## sell: unknown or already sold tower id
}

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
	state.gold = config.economy.starting_gold
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
	# 5. Towers fire / damage: LT-6 (mundane); LT-11, LT-13 add theirs.
	_fire_towers()
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
## (a pack's ids are consecutive), or 0 if `def_id` is unknown or the outcome is set
## (then nothing changes and no event is emitted).
func spawn_enemy(def_id: String, is_fake := false) -> int:
	if state.outcome != SimState.Outcome.NONE:
		return 0
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


## The one armor rule for every damage source (§3.4). Returns the hp actually removed
## (capped at the remaining hp, so overkill is not counted); 0 for an unknown, dead or
## leaked enemy, or once the outcome is set (then nothing changes and no event is emitted).
## A killed enemy emits DIED and is removed at the end of the current/next tick.
func apply_damage(enemy_id: int, amount: float, source: String) -> float:
	if state.outcome != SimState.Outcome.NONE:
		return 0.0
	var e := enemy_by_id(enemy_id)
	if e == null or not e.is_live():
		return 0.0
	var armor := maxf(0.0, e.def.armor + e.armor_bonus)
	var taken := maxf(0.0, amount - armor) * e.damage_taken_mult
	var removed := minf(taken, e.hp)
	e.hp -= taken
	if e.hp <= 0.0:
		e.dead = true
		_emit(SimEvent.Type.DIED, e.id, {"source": source, "reward": e.def.reward})
		_on_enemy_killed(e, source)
	return removed


## Whether `def_id` may be built on `cell` now; OK or the first failing reason, checked in
## the order of CommandResult. Changes nothing.
func can_build(def_id: String, cell: Vector2i) -> CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return CommandResult.OUTCOME_REACHED
	if not config.towers.has(def_id):
		return CommandResult.UNKNOWN_TOWER
	var def: TowerDef = config.towers[def_id]
	if def.kind != "mundane":
		return CommandResult.NOT_AVAILABLE
	if not state.map.is_buildable(cell):
		return CommandResult.NOT_BUILDABLE
	if state.tower_at.has(cell):
		return CommandResult.OCCUPIED
	if state.gold < def.cost:
		return CommandResult.NOT_ENOUGH_GOLD
	return CommandResult.OK


## Player command (§1.3, applied at once between ticks): builds an L1 `def_id` on `cell`
## for its cost. On OK the tower gets the next entity id, is ready to fire on the next
## tick, and TOWER_BUILT + GOLD_CHANGED are emitted.
func build_tower(def_id: String, cell: Vector2i) -> CommandResult:
	var result := can_build(def_id, cell)
	if result != CommandResult.OK:
		return result
	var def: TowerDef = config.towers[def_id]
	var t := SimTower.new()
	t.id = state.next_id
	state.next_id += 1
	t.def = def
	t.cell = cell
	t.spent = def.cost
	t.build_tick = state.tick
	state.towers.append(t)
	state.tower_at[cell] = t.id
	state.command_log.append([state.tick, "build", def_id, cell])
	_emit(SimEvent.Type.TOWER_BUILT, t.id, {"def": def_id, "cell": cell, "cost": def.cost})
	_add_gold(-def.cost, "build", t.id)
	return CommandResult.OK


## Player command: sells tower `tower_id` for economy.sell_refund_ratio of everything spent
## on it (rounded to the nearest gold) and frees its cell. Emits TOWER_SOLD + GOLD_CHANGED.
func sell_tower(tower_id: int) -> CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return CommandResult.OUTCOME_REACHED
	var t := tower_by_id(tower_id)
	if t == null:
		return CommandResult.NO_SUCH_TOWER
	var refund := sell_refund(t)
	state.towers.erase(t)
	state.tower_at.erase(t.cell)
	state.command_log.append([state.tick, "sell", tower_id])
	_emit(SimEvent.Type.TOWER_SOLD, t.id, {"def": t.def.id, "cell": t.cell, "refund": refund})
	_add_gold(refund, "sell", t.id)
	return CommandResult.OK


## Gold a sell of `t` would return now.
func sell_refund(t: SimTower) -> int:
	return roundi(t.spent * config.economy.sell_refund_ratio)


## Wave completion bonus for 1-based `wave_number`: base + per_wave * wave_number
## (economy.json). Called by the wave system (LT-5); not a player command, so not logged.
## Returns the gold added; 0 (and nothing changes) once the outcome is set.
func award_wave_bonus(wave_number: int) -> int:
	if state.outcome != SimState.Outcome.NONE:
		return 0
	if wave_number < 1:
		push_error("Simulation.award_wave_bonus: wave_number %d < 1" % wave_number)
		return 0
	var econ := config.economy
	var bonus := econ.wave_bonus_base + econ.wave_bonus_per_wave * wave_number
	_add_gold(bonus, "wave_bonus", 0)
	return bonus


## The tower with this id, or null (also null once sold).
func tower_by_id(id: int) -> SimTower:
	for t in state.towers:
		if t.id == id:
			return t
	return null


## Live enemies (fakes included) whose position is within `range_cells` of the centre of
## `cell`, boundary included; id order (§6 target query).
func enemies_in_range(cell: Vector2i, range_cells: float) -> Array[SimEnemy]:
	var c := Vector2(cell.x + 0.5, cell.y + 0.5)
	var r2 := range_cells * range_cells
	var out: Array[SimEnemy] = []
	for e in state.enemies:
		if not e.is_live():
			continue
		var p := e.route.position_at(e.distance)
		var dx := float(p.x) - float(c.x)
		var dy := float(p.y) - float(c.y)
		if dx * dx + dy * dy <= r2:
			out.append(e)
	return out


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


## Every gold change goes through here: GOLD_CHANGED {delta, gold, reason}; `id` is the
## enemy (kill) or tower (build/sell) it is about, 0 for the wave bonus.
func _add_gold(delta: int, reason: String, id: int) -> void:
	if delta == 0:
		return
	state.gold += delta
	_emit(SimEvent.Type.GOLD_CHANGED, id, {"delta": delta, "gold": state.gold, "reason": reason})


## Kill hook, called once per enemy when apply_damage kills it. Real enemies pay their
## reward; fakes (LT-12) pay nothing. `source` is the damage source; for towers it is the
## tower def id. LT-10 adds the mundane-kill sanity regen here (source is a tower def of
## kind "mundane").
func _on_enemy_killed(e: SimEnemy, _source: String) -> void:
	if not e.is_fake:
		_add_gold(e.def.reward, "kill", e.id)


## Slot 5 (§3.3): every tower in id order counts down its cooldown and, when ready, fires
## at the live enemy in range nearest the end of its route (ties: lower id). Instant hit.
## A level with a `pierce` effect fires a line shot (_line_hits) instead of a single shot.
func _fire_towers() -> void:
	for t in state.towers:
		if t.cooldown_ticks > 0:
			t.cooldown_ticks -= 1
			if t.cooldown_ticks > 0:
				continue
		var s := t.stats()
		if s.damage <= 0.0:
			continue
		var target := _first_along_route(enemies_in_range(t.cell, s.range_cells))
		if target == null:
			continue
		var pierce: float = s.effects.get("pierce", 0.0)
		var hits: Array[SimEnemy] = [target]
		var to := target.route.position_at(target.distance)
		if pierce > 0.0:
			to = _line_end(t.centre(), to, s.range_cells)
			hits = _line_hits(t.centre(), to, pierce * 0.5, target)
		var ids: Array[int] = []
		for e in hits:
			ids.append(e.id)
		_emit(SimEvent.Type.SHOT, t.id,
			{"def": t.def.id, "target": target.id, "hits": ids, "to": to})
		for e in hits:
			apply_damage(e.id, s.damage, t.def.id)
		t.cooldown_ticks = maxi(1, SimTime.ticks(s.fire_interval))


## "First" = least route distance left to the lighthouse; ties by lower id. Null if empty.
func _first_along_route(candidates: Array[SimEnemy]) -> SimEnemy:
	var best: SimEnemy = null
	var best_left := 0
	for e in candidates:
		var left := e.route.length - e.distance
		if best == null or left < best_left:
			best = e
			best_left = left
	return best


## End of a line shot: from `origin` through `aim`, `length` cells long. If `aim` is
## `origin` (a flyer straight over the tower) the line degenerates to that point.
func _line_end(origin: Vector2, aim: Vector2, length: float) -> Vector2:
	var dx := float(aim.x) - float(origin.x)
	var dy := float(aim.y) - float(origin.y)
	var d := sqrt(dx * dx + dy * dy)
	if d == 0.0:
		return origin
	return Vector2(origin.x + dx / d * length, origin.y + dy / d * length)


## Live enemies (fakes included, id order) on the segment origin -> `end` widened by
## `half_width` cells on each side: projection onto the segment in [0, its length] and
## perpendicular distance <= half_width. `primary` is always hit.
func _line_hits(origin: Vector2, end: Vector2, half_width: float,
		primary: SimEnemy) -> Array[SimEnemy]:
	var ux := float(end.x) - float(origin.x)
	var uy := float(end.y) - float(origin.y)
	var length := sqrt(ux * ux + uy * uy)
	var out: Array[SimEnemy] = []
	for e in state.enemies:
		if not e.is_live():
			continue
		if e == primary:
			out.append(e)
			continue
		if length == 0.0:
			continue
		var p := e.route.position_at(e.distance)
		var px := float(p.x) - float(origin.x)
		var py := float(p.y) - float(origin.y)
		var along := (px * ux + py * uy) / length
		var across := absf(px * uy - py * ux) / length
		if along >= 0.0 and along <= length and across <= half_width:
			out.append(e)
	return out


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
