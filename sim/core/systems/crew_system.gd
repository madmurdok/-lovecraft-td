class_name CrewSystem
extends RefCounted
## LT-32 §2.3 (LT-80 system pattern): the crew reserve (state.crew), hiring by day, the
## crew a crewed tower takes when built, reserve posts deployed at night and their removal
## at dawn. Built once by the sim facade after Economy; the facade forwards the public
## names. Every method is a no-op (or answers "no crew") when crew is off
## (GameConfig.crew_on()), so a config without crew.json behaves byte-identically. Draws no
## RNG (Q5 a).

var _ctx: SimContext
var _state: SimState
var _config: GameConfig
var _economy: EconomySystem


func _init(ctx: SimContext, economy: EconomySystem) -> void:
	_ctx = ctx
	_state = ctx.state
	_config = ctx.config
	_economy = economy
	if _config.crew_on():
		for kind: String in _config.crew.crews:
			_state.crew[kind] = 0


## Men a tower of `def_id` needs: the kind's per_tower when crewed, else 0 (also when off).
func crew_need(def_id: String) -> int:
	var k := _kind(def_id)
	return 0 if k == null else k.per_tower


## The frame price of `def_id` (Q2 a): cost - per_tower x hire for a crewed def, else cost.
## The refund base (SimTower.spent) of a fresh tower. 0 for an unknown def.
func frame_price(def_id: String) -> int:
	var def: TowerDef = _config.towers.get(def_id)
	if def == null:
		return 0
	var k := _kind(def_id)
	return def.cost if k == null else def.cost - k.per_tower * k.hire


## Money a build of `def_id` costs now: the frame plus the crew the reserve does not cover,
## hired on the spot; def.cost when the def needs no crew (or crew is off). With an empty
## reserve this is def.cost exactly. 0 for an unknown def.
func build_price(def_id: String) -> int:
	var def: TowerDef = _config.towers.get(def_id)
	if def == null:
		return 0
	var k := _kind(def_id)
	if k == null:
		return def.cost
	var missing := maxi(0, k.per_tower - _state.crew.get(def_id, 0))
	return frame_price(def_id) + missing * k.hire


## Build hook (after the tower is placed and paid): the reserve of its kind gives what it
## has, up to the need (the rest was hired inside build_price); `t.crew` = the need. Emits
## CREW_CHANGED "build" only when the reserve changed.
func take_for_build(t: SimTower) -> void:
	var need := crew_need(t.def.id)
	if need == 0:
		return
	var kind := t.def.id
	var take := mini(_state.crew.get(kind, 0), need)
	t.crew = need
	if take > 0:
		_change(kind, -take, "build")


## Whether hire(kind) would be applied now; OK or the first failing reason in this order:
## OUTCOME_REACHED, NO_CREW (crew off or `kind` is no crew kind), NOT_ENOUGH_GOLD,
## NOT_BUILD_PHASE (at night, SimContext.day_only, last). Changes nothing.
func can_hire(kind: String) -> SimCommand.CommandResult:
	if _state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	var k := _kind(kind)
	if k == null:
		return SimCommand.CommandResult.NO_CREW
	if _state.gold < k.hire:
		return SimCommand.CommandResult.NOT_ENOUGH_GOLD
	return _ctx.day_only()


## Player command (day only): one man of `kind` joins the reserve for its `hire` money.
## Logs [tick, "hire", kind]; emits CREW_CHANGED {delta 1, reason "hire"} then GOLD_CHANGED
## "hire" (id 0).
func hire(kind: String) -> SimCommand.CommandResult:
	var result := can_hire(kind)
	if result != SimCommand.CommandResult.OK:
		return result
	_ctx.log_command([_state.tick, "hire", kind])
	_change(kind, 1, "hire")
	_economy.add_gold(-_kind(kind).hire, "hire", 0)
	return SimCommand.CommandResult.OK


## Whether deploy(kind, cell) would be applied now; OK or the first failing reason in this
## order: OUTCOME_REACHED, NO_CREW, NOT_BUILDABLE, OCCUPIED, RESERVE_SHORT (the kind's
## reserve is below the post's crew), NOT_NIGHT (phase is not WAVE, last). Changes nothing.
func can_deploy(kind: String, cell: Vector2i) -> SimCommand.CommandResult:
	if _state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	if _kind(kind) == null:
		return SimCommand.CommandResult.NO_CREW
	if not _state.map.is_buildable(cell):
		return SimCommand.CommandResult.NOT_BUILDABLE
	if _state.tower_at.has(cell):
		return SimCommand.CommandResult.OCCUPIED
	if _state.crew.get(kind, 0) < _config.crew.post_of(kind).crew:
		return SimCommand.CommandResult.RESERVE_SHORT
	if _state.phase != SimState.Phase.WAVE:
		return SimCommand.CommandResult.NOT_NIGHT
	return SimCommand.CommandResult.OK


## Player command (night only, free): `post.crew` reserve men of `kind` stand on `cell` as a
## reserve post (Q3 a): a SimTower record with the next entity id, the post def at L1,
## post = true, crew_kind = kind, spent 0, ready to fire on the next tick. Logs
## [tick, "deploy", kind, cell]; emits POST_DEPLOYED {kind, cell, crew} then CREW_CHANGED
## "deploy". No TOWER_BUILT, no money, no sanity reserve.
func deploy(kind: String, cell: Vector2i) -> SimCommand.CommandResult:
	var result := can_deploy(kind, cell)
	if result != SimCommand.CommandResult.OK:
		return result
	var p := _config.crew.post_of(kind)
	var t := SimTower.new()
	t.id = _ctx.next_id()
	t.def = p.def
	t.cell = cell
	t.pos = _state.map.grid.centre(cell)
	t.build_tick = _state.tick
	t.post = true
	t.crew_kind = kind
	t.crew = p.crew
	_state.towers.append(t)
	_state.tower_at[cell] = t.id
	_ctx.log_command([_state.tick, "deploy", kind, cell])
	_ctx.emit(SimEvent.Type.POST_DEPLOYED, t.id, {"kind": kind, "cell": cell, "crew": p.crew})
	_change(kind, -p.crew, "deploy")
	return SimCommand.CommandResult.OK


## The men on `t` go back to the reserve: a post's crew_kind, a tower's def id. Used by
## sell ("sell") and dawn ("dawn"); `t` is already off the board. No-op for t.crew 0.
func release(t: SimTower, reason: String) -> void:
	if t.crew <= 0:
		return
	_change(t.crew_kind if t.post else t.def.id, t.crew, reason)


## LT-32 Q4, the last dawn action: every post (id order) leaves the board, emits
## POST_REMOVED {kind, cell, reason "dawn"} and returns its men (CREW_CHANGED "dawn").
func on_dawn() -> void:
	if not _config.crew_on():
		return
	var posts: Array[SimTower] = []
	for t in _state.towers:
		if t.post:
			posts.append(t)
	for t in posts:
		_state.towers.erase(t)
		_state.tower_at.erase(t.cell)
		_ctx.emit(SimEvent.Type.POST_REMOVED, t.id, {"kind": t.crew_kind, "cell": t.cell,
			"reason": "dawn"})
		release(t, "dawn")


## The reserve, crew kind -> men (a copy; empty when crew is off).
func reserve() -> Dictionary:
	return _state.crew.duplicate()


## The post def a deploy of `kind` would field; null when crew is off or `kind` has no crew.
func post_def(kind: String) -> TowerDef:
	if _kind(kind) == null:
		return null
	return _config.crew.post_of(kind).def


## The crew row of `kind` when crew is on, else null.
func _kind(kind: String) -> CrewConfig.CrewKind:
	if not _config.crew_on():
		return null
	return _config.crew.crews.get(kind)


func _change(kind: String, delta: int, reason: String) -> void:
	_state.crew[kind] = _state.crew.get(kind, 0) + delta
	_ctx.emit(SimEvent.Type.CREW_CHANGED, 0, {"kind": kind, "reserve": _state.crew[kind],
		"delta": delta, "reason": reason})
