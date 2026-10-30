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
	NOT_AVAILABLE,  ## reserved: no tower kind is refused since LT-11 (kept so values never shift)
	NOT_BUILDABLE,  ## path, water, the lighthouse or out of bounds
	OCCUPIED,  ## another tower stands on the cell
	NOT_ENOUGH_GOLD,
	NO_SUCH_TOWER,  ## sell: unknown or already sold tower id
	NOT_BUILD_PHASE,  ## call_wave: not in the build phase (or no WaveDirector)
}

var state: SimState
var config: GameConfig
var events: Array[SimEvent] = []
## Debug only (LT-12 §1): set by scenes/game.gd in debug builds with `--reveal-fakes`.
## The sim never reads it; only debug_is_fake does, so it cannot change an outcome.
var debug_reveal_fakes := false

var _spawner: SimSpawner
var _rng: SimRng
var _ground_route: SimRoute
var _hallucinations := HallucinationSystem.new()


func _init(p_config: GameConfig, run_seed: int) -> void:
	config = p_config
	_rng = SimRng.new(run_seed)
	state = SimState.new()
	state.map = config.map
	state.lighthouse_hp = config.economy.lighthouse_hp
	state.gold = config.economy.starting_gold
	state.sanity = clampf(config.sanity.start, 0.0, config.sanity.max_sanity)
	state.sanity_state = sanity_state_for(state.sanity)  # initial state: no event
	_ground_route = SimRoute.from_cells(config.map.path)


## Without a spawner the run never wins (nothing can be "exhausted"). A WaveDirector
## starts the build phase before wave 1 here (BUILD_STARTED on tick 0).
func set_spawner(s: SimSpawner) -> void:
	_spawner = s
	_spawner.attach(self)


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
	# 2. Effect systems: Elder Sign auras (LT-11); later slows/stuns add theirs here.
	_apply_auras()
	# 3. Movement.
	_move()
	# 4. Leaks.
	_leak()
	# 5. Towers fire / damage: single and line shots (LT-6), AoE casts and their sanity
	# cost (LT-11); LT-13 adds madness effects.
	_fire_towers()
	# 6. Sanity (LT-10): horror drain. Kill regen is paid in slot 5 (_on_enemy_killed),
	# between-waves regen in slot 8 (wave system), each through _add_sanity.
	_horror_drain()
	# 7. Spawning, then fakes (LT-12) from the spawner's candidates.
	if _spawner != null:
		_spawner.tick(self)
		_hallucinations.tick(self, _spawner)
	# 8. Remove dead and leaked enemies; then the wave system settles a cleared wave
	# (its bonus is paid before the outcome check, so the last wave's bonus lands too).
	_compact()
	if _spawner != null:
		_spawner.end_tick(self)
	# 9. Outcome.
	_check_outcome()


## Spawns `def_id` at the start of its route; a `pack` enemy spawns min..max of them
## (rolled on SPAWN, or on SANITY for a fake so hallucinations never change real pack
## sizes, LT-12 §2) on the same tick at the same spot. Returns the first new id
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
		var stream := SimRng.Stream.SANITY if is_fake else SimRng.Stream.SPAWN
		count = rng(stream).randi_range(int(pack["min"]), int(pack["max"]))
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
	if not state.map.is_buildable(cell):
		return CommandResult.NOT_BUILDABLE
	if state.tower_at.has(cell):
		return CommandResult.OCCUPIED
	if state.gold < def.cost:
		return CommandResult.NOT_ENOUGH_GOLD
	return CommandResult.OK


## Player command (§1.3, applied at once between ticks): builds an L1 `def_id` on `cell`
## for its cost. On OK the tower gets the next entity id, is ready to fire on the next
## tick, and TOWER_BUILT + GOLD_CHANGED are emitted. An occult tower's sanity_cost is then
## paid through _add_sanity (SANITY_CHANGED "build"): allowed at any sanity, clamped at 0,
## so building can push the player into MADNESS (GDD §11). Only gold is checked.
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
	if def.sanity_cost > 0.0:
		_add_sanity(-def.sanity_cost, "build", t.id)
	return CommandResult.OK


## Player command: sells tower `tower_id` for economy.sell_refund_ratio of everything spent
## on it (rounded to the nearest gold) and frees its cell. Emits TOWER_SOLD + GOLD_CHANGED.
## Sanity paid to build an occult tower is not refunded.
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


## Player command: ends the build phase now; the next wave spawns from the next tick on.
## Pays economy.early_call_gold_per_second x whole seconds left on the build timer
## (seconds rounded down from ticks, the product rounded down). Emits WAVE_STARTED
## {early: true} + GOLD_CHANGED {reason: "early_call"} (none when the bonus is 0).
func call_wave() -> CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return CommandResult.OUTCOME_REACHED
	var director := _spawner as WaveDirector
	if director == null or state.phase != SimState.Phase.BUILD:
		return CommandResult.NOT_BUILD_PHASE
	var bonus := early_call_bonus()
	state.command_log.append([state.tick, "call_wave"])
	director.start_wave(self, true)
	_add_gold(bonus, "early_call", 0)
	return CommandResult.OK


## Gold call_wave() would pay if called now: economy.early_call_gold_per_second x whole
## seconds left on the build timer (seconds rounded down from ticks, the product rounded
## down); 0 when call_wave() would be refused. Changes nothing.
func early_call_bonus() -> int:
	if state.outcome != SimState.Outcome.NONE or state.phase != SimState.Phase.BUILD:
		return 0
	if not (_spawner is WaveDirector):
		return 0
	var seconds_left := SimTime.whole_seconds(state.build_ticks_left)
	return floori(config.economy.early_call_gold_per_second * seconds_left)


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


## Between-waves sanity regen (sanity.json regen.between_waves), paid once per cleared wave
## by the wave system right after award_wave_bonus, so also for the last wave in the tick
## WON is set. Returns the sanity actually added (0 at the cap or once the outcome is set).
func award_wave_sanity() -> float:
	if state.outcome != SimState.Outcome.NONE:
		return 0.0
	return _add_sanity(config.sanity.regen_between_waves, "between_waves", 0)


## Threshold state for a sanity value (GDD §5.3, §5.4): MADNESS iff s <= 0 ("triggered when
## sanity hits 0"); otherwise the highest state whose `min` <= s, with FRAYING covering
## everything in (0, whispers.min), so 0 < s < fraying.min is FRAYING, not MADNESS.
func sanity_state_for(s: float) -> SimState.SanityState:
	if s <= 0.0:
		return SimState.SanityState.MADNESS
	var th := config.sanity.thresholds
	if s >= th["lucid"].min_sanity:
		return SimState.SanityState.LUCID
	if s >= th["whispers"].min_sanity:
		return SimState.SanityState.WHISPERS
	return SimState.SanityState.FRAYING


## The tower with this id, or null (also null once sold).
func tower_by_id(id: int) -> SimTower:
	for t in state.towers:
		if t.id == id:
			return t
	return null


## Live enemies (fakes included) whose position is within `range_cells` of the centre of
## `cell`, boundary included; id order (§6 target query).
func enemies_in_range(cell: Vector2i, range_cells: float) -> Array[SimEnemy]:
	return enemies_near(Vector2(cell.x + 0.5, cell.y + 0.5), range_cells)


## Live enemies (fakes included) whose position is within `radius` cells of `centre`
## (cell units), boundary included; id order.
func enemies_near(centre: Vector2, radius: float) -> Array[SimEnemy]:
	var r2 := radius * radius
	var out: Array[SimEnemy] = []
	for e in state.enemies:
		if not e.is_live():
			continue
		var p := e.route.position_at(e.distance)
		var dx := float(p.x) - float(centre.x)
		var dy := float(p.y) - float(centre.y)
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


## For sim systems outside this script (the wave director); scenes never call it.
func emit_event(type: SimEvent.Type, id: int, data: Dictionary) -> void:
	_emit(type, id, data)


func _emit(type: SimEvent.Type, id: int, data: Dictionary) -> void:
	events.append(SimEvent.new(type, state.tick, id, data))


## Every gold change goes through here: GOLD_CHANGED {delta, gold, reason}; `id` is the
## enemy (kill) or tower (build/sell) it is about, 0 for the wave bonus.
func _add_gold(delta: int, reason: String, id: int) -> void:
	if delta == 0:
		return
	state.gold += delta
	_emit(SimEvent.Type.GOLD_CHANGED, id, {"delta": delta, "gold": state.gold, "reason": reason})


## Every sanity change goes through here: clamps to [0, max], then emits SANITY_CHANGED
## {delta, sanity, reason} with the delta actually applied (nothing when it is 0, e.g. regen
## at the cap), and SANITY_STATE_CHANGED {old, new} (SimState.SanityState values) when the
## threshold state moves. `id` is the enemy (kill) or tower (build, cast) it is about,
## 0 otherwise.
## Returns the applied delta.
func _add_sanity(delta: float, reason: String, id: int) -> float:
	# LT-13 hook: with madness.exit_rule "permanent", MADNESS is latched and regen must not
	# lift sanity out of it; gate positive deltas here once the latch exists.
	var before := state.sanity
	state.sanity = clampf(before + delta, 0.0, config.sanity.max_sanity)
	var applied := state.sanity - before
	if applied == 0.0:
		return 0.0
	_emit(SimEvent.Type.SANITY_CHANGED, id,
		{"delta": applied, "sanity": state.sanity, "reason": reason})
	var old := state.sanity_state
	state.sanity_state = sanity_state_for(state.sanity)
	if state.sanity_state != old:
		_emit(SimEvent.Type.SANITY_STATE_CHANGED, 0, {"old": old, "new": state.sanity_state})
	return applied


## Slot 6: every live real enemy with horror_drain > 0 within sanity.horror_radius_cells of
## any tower (same metric as enemies_in_range: enemy position to tower cell centre, boundary
## included) drains horror_drain per second, i.e. horror_drain * DT per tick; counted once
## per enemy however many towers are near. Fakes never drain (illusions, LT-12); flyers do.
## One SANITY_CHANGED "horror" per tick with the summed delta.
func _horror_drain() -> void:
	if state.towers.is_empty():
		return
	var r := config.sanity.horror_radius_cells
	var r2 := r * r
	var total := 0.0
	for e in state.enemies:
		if not e.is_live() or e.is_fake or e.def.horror_drain <= 0.0:
			continue
		var p := e.route.position_at(e.distance)
		for t in state.towers:
			var c := t.centre()
			var dx := float(p.x) - c.x
			var dy := float(p.y) - c.y
			if dx * dx + dy * dy <= r2:
				total += e.def.horror_drain * SimTime.DT
				break
	if total > 0.0:
		_add_sanity(-total, "horror", 0)


## Kill hook, called once per enemy when apply_damage kills it. Real enemies pay their
## reward; fakes (LT-12) pay nothing. `source` is the damage source; for towers it is the
## tower def id. A real enemy killed by a mundane tower restores regen.mundane_kill sanity
## (only damage-dealing levels fire, so a tower kill is always by a damage level).
func _on_enemy_killed(e: SimEnemy, source: String) -> void:
	if e.is_fake:
		return
	_add_gold(e.def.reward, "kill", e.id)
	var tower_def: TowerDef = config.towers.get(source)
	if tower_def != null and tower_def.kind == "mundane":
		_add_sanity(config.sanity.regen_mundane_kill, "mundane_kill", e.id)


## Slot 2 (§3.3): aura towers (Elder Sign) set this tick's modifiers. An aura tower is a
## support level (damage 0) with a `slow` and/or `damage_taken_multiplier` effect; its aura
## radius is the level's range, measured like enemies_in_range from the enemy's position at
## the start of the tick (before movement). Every live enemy inside (fakes too) gets
## speed_mult x (1 - slow) and damage_taken_mult x multiplier. Auras do not stack: inside
## several signs an enemy gets each modifier once, the strongest among the covering signs.
## The speed modifier scales this tick's movement (slot 3); the damage modifier applies to
## every hit this tick (slot 5), after armor (apply_damage).
func _apply_auras() -> void:
	var auras: Array[SimTower] = []
	for t in state.towers:
		var s := t.stats()
		if s.damage <= 0.0 and (s.effects.has("slow") or s.effects.has("damage_taken_multiplier")):
			auras.append(t)
	if auras.is_empty():
		return
	for e in state.enemies:
		if not e.is_live():
			continue
		var p := e.route.position_at(e.distance)
		var inside := false
		var slow := 0.0
		var mult := 1.0
		for t in auras:
			var s := t.stats()
			var c := t.centre()
			var dx := float(p.x) - c.x
			var dy := float(p.y) - c.y
			if dx * dx + dy * dy > s.range_cells * s.range_cells:
				continue
			inside = true
			slow = maxf(slow, s.effects.get("slow", 0.0))
			mult = maxf(mult, s.effects.get("damage_taken_multiplier", 1.0))
			# Corrupted Seal's strip_armor (L3 branch) is not wired yet: L1 only in LT-11.
		if inside:
			e.speed_mult *= 1.0 - slow
			e.damage_taken_mult *= mult


## Slot 5 (§3.3): every tower in id order counts down its cooldown and, when ready, fires
## at the live enemy in range nearest the end of its route (ties: lower id). Instant hit.
## A level with a `pierce` effect fires a line shot (_line_hits) instead of a single shot;
## one with an `aoe_radius` effect casts a blast centred on that target, hitting every live
## enemy (fakes too) within aoe_radius of it (Necronomicon). No enemy in range: no shot, no
## cast and no sanity cost; the tower stays ready. A mundane shot may miss (LT-12 §4,
## _roll_miss): cooldown spent, no damage, SHOT {miss: true, hits: []}, `to` = aim point. A level's sanity_per_cast is paid through
## _add_sanity (SANITY_CHANGED "cast", id = tower) in the tick it fires, before its damage.
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
		# LT-13 hook: madness_affected levels (s.madness_affected) deal x2 and may shoot
		# astray while state.sanity_state == MADNESS; not implemented here.
		var pierce: float = s.effects.get("pierce", 0.0)
		var aoe: float = s.effects.get("aoe_radius", 0.0)
		var hits: Array[SimEnemy] = [target]
		var to := target.route.position_at(target.distance)
		if pierce > 0.0:
			to = _line_end(t.centre(), to, s.range_cells)
			hits = _line_hits(t.centre(), to, pierce * 0.5, target)
		elif aoe > 0.0:
			hits = enemies_near(to, aoe)
		# LT-12 §4: a mundane shot may miss as a whole (Q3: occult towers never miss).
		var miss := t.def.kind == "mundane" and _roll_miss()
		if miss:
			hits = []
		var ids: Array[int] = []
		for e in hits:
			ids.append(e.id)
		_emit(SimEvent.Type.SHOT, t.id,
			{"def": t.def.id, "target": target.id, "hits": ids, "to": to, "miss": miss})
		if s.sanity_per_cast > 0.0:
			_add_sanity(-s.sanity_per_cast, "cast", t.id)
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
## A fake never leaks: it dissolves there (LT-12 §3), no HP change and no LEAKED.
func _leak() -> void:
	for e in state.enemies:
		if not e.is_live() or e.distance != e.route.length:
			continue
		if e.is_fake:
			e.dissolved = true
			_emit(SimEvent.Type.FAKE_DISSOLVED, e.id, {"reason": "lighthouse"})
			continue
		e.leaked = true
		state.lighthouse_hp = maxi(0, state.lighthouse_hp - e.def.leak_damage)
		_emit(SimEvent.Type.LEAKED, e.id,
			{"damage": e.def.leak_damage, "hp_after": state.lighthouse_hp})


## LT-12 §5 (called by the wave director when a wave is cleared): every live fake, in id
## order, is marked dissolved with FAKE_DISSOLVED {reason}; then state.enemies is
## compacted again, so the build phase starts with no enemy in `state`.
func dissolve_fakes(reason: String) -> void:
	for e in state.enemies:
		if e.is_live() and e.is_fake:
			e.dissolved = true
			_emit(SimEvent.Type.FAKE_DISSOLVED, e.id, {"reason": reason})
	_compact()


## The only way a scene may tell a fake (LT-12 §1): false unless debug_reveal_fakes.
func debug_is_fake(e: SimEnemy) -> bool:
	return debug_reveal_fakes and e.is_fake


## Sim only (LT-13 madness "hit a fake" branch): live fakes in range, id order.
func live_fakes_in_range(cell: Vector2i, range_cells: float) -> Array[SimEnemy]:
	var out: Array[SimEnemy] = []
	for e in enemies_in_range(cell, range_cells):
		if e.is_fake:
			out.append(e)
	return out


## The sanity.json threshold of the current sanity state (SimState.SanityState and
## SanityConfig.STATES share their order: LUCID..MADNESS = "lucid".."madness").
func threshold() -> SanityConfig.Threshold:
	return config.sanity.thresholds[SanityConfig.STATES[state.sanity_state]]


## LT-12 §4 miss hook: one roll on COMBAT against the state's miss_chance; no roll (and no
## COMBAT draw) when the chance is 0, so Lucid/Whispers consume COMBAT as before.
func _roll_miss() -> bool:
	var chance := threshold().miss_chance
	if chance <= 0.0:
		return false
	return rng(SimRng.Stream.COMBAT).randf() < chance


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
