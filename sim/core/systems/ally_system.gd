class_name AllySystem
extends RefCounted
## LT-82 (B7 of LT-65 §3.1 Ally): the allied units of LT-52 (Summoning Circle). Owns
## state.allies (spawn, hold, chase, trade damage, gone, compaction). Built once by the sim
## facade, which orders the step slots and forwards the public names. Its one peer is
## CombatSystem (enemy / tower lookup and apply_damage), injected through the constructor;
## Combat never holds this system (it spawns through a facade-set Callable).


## LT-52 (LT-46 §2.2): an allied unit within this many cells of an enemy it chases holds it.
const ALLY_CONTACT := 0.4

var _ctx: SimContext
var _state: SimState
var _config: GameConfig
var _combat: CombatSystem


func _init(ctx: SimContext, combat: CombatSystem) -> void:
	_ctx = ctx
	_state = ctx.state
	_config = ctx.config
	_combat = combat


## LT-52 (LT-46 P10): places an allied unit at `at` (cell units; also its leash centre) and
## emits ALLY_SUMMONED. `tower` is the summoning tower's id (0 = none), `source` the kill
## credit; `dps` is dealt to the held enemy (armor: ally_combat), `speed` in
## cells/s, `flying` lets it engage flyers, `leash` (cells from `at`) bounds whom it
## engages; `lifetime_ticks` <= 0 = no lifetime. Returns the new id, or 0 if the outcome
## is set or `hp` <= 0 (then nothing changes and no event is emitted).
func spawn(tower: int, source: String, at: Vector2, hp: float, dps: float, speed: float,
		flying: bool, lifetime_ticks: int, leash: float) -> int:
	if _state.outcome != SimState.Outcome.NONE or hp <= 0.0:
		return 0
	var a := SimAlly.new()
	a.id = _state.next_id
	_state.next_id += 1
	a.tower = tower
	a.source = source
	a.home = at
	a.leash = maxf(0.0, leash)
	a.pos = at
	a.prev_pos = at
	a.hp = hp
	a.max_hp = hp
	a.dps = maxf(0.0, dps)
	a.speed = maxf(0.0, speed)
	a.flying = flying
	a.summon_tick = _state.tick
	a.expires_tick = _state.tick + lifetime_ticks if lifetime_ticks > 0 else 0
	_state.allies.append(a)
	_ctx.emit(SimEvent.Type.ALLY_SUMMONED, a.id, {"tower": tower, "source": source, "at": at,
		"hp": hp, "flying": flying, "expires_tick": a.expires_tick})
	return a.id


## The ally with this id, or null (also null once removed).
func ally_by_id(id: int) -> SimAlly:
	for a in _state.allies:
		if a.id == id:
			return a
	return null


## Live allies of tower `tower_id`, id order (a summoner counts them against its maximum).
func allies_of(tower_id: int) -> Array[SimAlly]:
	var out: Array[SimAlly] = []
	for a in _state.allies:
		if a.is_live() and a.tower == tower_id:
			out.append(a)
	return out


## Position in cell units, interpolated between the last two ticks by `alpha` (0..1).
func ally_position(a: SimAlly, alpha: float) -> Vector2:
	return a.prev_pos.lerp(a.pos, alpha)


## LT-52 slot 2: an ally whose lifetime ran out is gone ("expired"); a live ally's held
## enemy gets speed_mult 0. A hold that is no longer valid (_holds: the enemy died, was
## revealed as a fake, or was pushed out of contact by a pull / banish in the last slot 5)
## is dropped first, so that enemy is not frozen for another tick.
func tick_allies() -> void:
	for a in _state.allies:
		if not a.is_live():
			continue
		if a.expires_tick > 0 and _state.tick >= a.expires_tick:
			_ally_gone(a, "expired")
			continue
		if a.held_id < 0:
			continue
		var e := _combat.enemy_by_id(a.held_id)
		if not _holds(a, e):
			a.held_id = -1
			continue
		e.speed_mult = 0.0


## LT-52: true while `a` may keep holding `e`: live, not a revealed fake (units never
## engage one) and within ALLY_CONTACT of `a` (a push back breaks the hold).
func _holds(a: SimAlly, e: SimEnemy) -> bool:
	return e != null and e.is_live() and not e.revealed \
		and _dist2(a.pos, e.route.position_at(e.distance)) <= ALLY_CONTACT * ALLY_CONTACT


## LT-52 slot 3, after enemies move; allies in id order. A holding ally stays while its enemy
## is live and within ALLY_CONTACT (a push back breaks the hold). Otherwise it picks the
## nearest enemy (to itself; ties by id) it may engage: live, not a revealed fake, ground
## only unless it flies, not held by another ally, position within `leash` of `home`; it
## moves `speed x DT` straight toward that enemy and holds it once within ALLY_CONTACT. With
## no such enemy it walks back toward `home`.
func move_allies() -> void:
	if _state.allies.is_empty():
		return
	var held: Dictionary[int, bool] = {}
	for a in _state.allies:
		if a.is_live() and a.held_id >= 0:
			held[a.held_id] = true
	for a in _state.allies:
		if not a.is_live():
			continue
		a.prev_pos = a.pos
		if a.held_id >= 0:
			if _holds(a, _combat.enemy_by_id(a.held_id)):
				a.target_id = a.held_id
				continue
			held.erase(a.held_id)
			a.held_id = -1
		var target := _ally_target(a, held)
		var step_cells := a.speed * SimTime.DT
		if target == null:
			a.target_id = -1
			a.pos = _step_toward(a.pos, a.home, step_cells)
			continue
		a.target_id = target.id
		var p := target.route.position_at(target.distance)
		a.pos = _step_toward(a.pos, p, step_cells)
		if _dist2(a.pos, p) <= ALLY_CONTACT * ALLY_CONTACT:
			a.held_id = target.id
			held[target.id] = true


## The enemy `a` chases this tick (see move_allies), or null.
func _ally_target(a: SimAlly, held: Dictionary[int, bool]) -> SimEnemy:
	var leash2 := a.leash * a.leash
	var best: SimEnemy = null
	var best_d2 := INF
	for e in _state.enemies:
		if not e.is_live() or e.revealed or held.has(e.id):
			continue
		if e.def.flying and not a.flying:
			continue
		var p := e.route.position_at(e.distance)
		if _dist2(p, a.home) > leash2:
			continue
		var d2 := _dist2(p, a.pos)
		if d2 < best_d2:
			best = e
			best_d2 = d2
	return best


## LT-52 slot 5 (after the towers fire), allies in id order: a holding ally deals
## `max(0, dps - armor) x DT` to its enemy (armor once per second, not per tick, LT-46 P10;
## the hit skips armor, damage_taken_mult applies; kill credit `source`); an enemy still
## live then deals `contact_dps x DT` to the ally, which is gone ("killed") at 0 HP.
## Unrevealed fakes are engaged and hit back like real enemies (the unit cannot tell); a
## hold this slot's shots broke (_holds: pushed out of contact, fake revealed) is dropped
## with no damage either way. The unit's dps is x madness.damage_multiplier while sanity is
## in MADNESS and its circle is madness_affected, read every tick (§3 "units deal").
func ally_combat() -> void:
	var madness := _state.sanity_state == SimState.SanityState.MADNESS
	for a in _state.allies:
		if not a.is_live() or a.held_id < 0:
			continue
		var e := _combat.enemy_by_id(a.held_id)
		if not _holds(a, e):
			a.held_id = -1
			continue
		var dps := a.dps
		if madness:
			var t := _combat.tower_by_id(a.tower)
			if t != null and t.stats().madness_affected:
				dps *= _config.sanity.madness.damage_multiplier
		var armor := maxf(0.0, e.def.armor + e.armor_bonus)
		_combat.apply_damage(e.id, maxf(0.0, dps - armor) * SimTime.DT, a.source, true)
		if not e.is_live():
			a.held_id = -1
			continue
		a.hp -= e.def.contact_dps * SimTime.DT
		if a.hp <= 0.0:
			a.hp = 0.0
			_ally_gone(a, "killed", e.id)


## Marks `a` gone (removed in slot 8), dropping its hold, and emits ALLY_GONE.
func _ally_gone(a: SimAlly, reason: String, by := 0) -> void:
	a.gone = true
	a.held_id = -1
	a.target_id = -1
	var data := {"tower": a.tower, "reason": reason}
	if reason == "killed":
		data["by"] = by
	_ctx.emit(SimEvent.Type.ALLY_GONE, a.id, data)


## A sold tower's live allies are gone ("dismissed"), in id order.
func dismiss_allies(tower_id: int) -> void:
	for a in allies_of(tower_id):
		_ally_gone(a, "dismissed")


## `from` moved up to `max_step` cells straight toward `to`; `to` itself when within reach.
static func _step_toward(from: Vector2, to: Vector2, max_step: float) -> Vector2:
	var dx := float(to.x) - float(from.x)
	var dy := float(to.y) - float(from.y)
	var d := sqrt(dx * dx + dy * dy)
	if d <= max_step:
		return to
	var k := max_step / d
	return Vector2(float(from.x) + dx * k, float(from.y) + dy * k)


static func _dist2(p: Vector2, q: Vector2) -> float:
	var dx := float(p.x) - float(q.x)
	var dy := float(p.y) - float(q.y)
	return dx * dx + dy * dy


## Slot 8 (from the facade's _compact, after the enemies): gone allies leave state.allies.
func compact() -> void:
	if _state.allies.is_empty():
		return
	var kept: Array[SimAlly] = []
	for a in _state.allies:
		if a.is_live():
			kept.append(a)
	_state.allies = kept
