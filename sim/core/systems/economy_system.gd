class_name EconomySystem
extends RefCounted
## LT-81 (B6 of LT-65 §3.1 Economy): owns gold, the relic stash and the relic tokens
## (state.gold, relics, relic_tokens, next_token_id), the drop roll, the sell commands and
## the dawn wage. Built once by the sim facade, which orders the step slots and forwards the
## public names. Light and Sanity reach gold through add_gold; events, RNG and the command
## log go through SimContext.

var _ctx: SimContext
var _state: SimState
var _config: GameConfig
## LT-27 §1.3: token id -> true for tokens dropped by fakes. Sim-private: the render must
## never tell a ghost token from a real one before it vanishes. Only looked up and erased.
var _ghost_tokens: Dictionary[int, bool] = {}


func _init(ctx: SimContext) -> void:
	_ctx = ctx
	_state = ctx.state
	_config = ctx.config
	_state.gold = _config.economy.starting_gold
	for kind in _config.economy.relic_ids():
		_state.relics[kind] = 0


## Every money change ("gold" internally, LT-27 §2) goes through here: GOLD_CHANGED {delta,
## gold, reason}; `id` is the tower (build/sell/upgrade) it is about, 0 for the dawn wage
## ("wave_bonus"), a relic sale ("relic_sale") or the buyout. Kills pay no money since LT-27.
func add_gold(delta: int, reason: String, id: int) -> void:
	if delta == 0:
		return
	_state.gold += delta
	_ctx.emit(SimEvent.Type.GOLD_CHANGED, id, {"delta": delta, "gold": _state.gold, "reason": reason})




## LT-27 §1.4: the money one relic of `kind` sells for (economy.relics price); 0 for an
## unknown kind. The only place a relic price is read.
func relic_price(kind: String) -> int:
	var k := _config.economy.relic(kind)
	return 0 if k == null else k.price


## The stash at today's prices: sum of relic_price x count.
func relics_value() -> int:
	var total := 0
	for kind: String in _state.relics:
		total += relic_price(kind) * _state.relics[kind]
	return total


## Whether sell_relics(kind) would be applied now; OK or the first failing reason in this
## order: OUTCOME_REACHED, NOT_BUILD_PHASE (at night), NO_RELICS (unknown kind, or nothing
## of `kind` / nothing at all for "" in the stash). Changes nothing.
func can_sell_relics(kind := "") -> SimCommand.CommandResult:
	if _state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	var day := _ctx.day_only()
	if day != SimCommand.CommandResult.OK:
		return day
	if kind != "":
		return SimCommand.CommandResult.OK if _state.relics.get(kind, 0) > 0 else SimCommand.CommandResult.NO_RELICS
	for k: String in _state.relics:
		if _state.relics[k] > 0:
			return SimCommand.CommandResult.OK
	return SimCommand.CommandResult.NO_RELICS


## Player command (LT-27 §1.4, day only): sells the whole stack of `kind`, or of every kind
## for "", at the fixed relic_price. Logs [tick, "sell_relics", kind]; emits one
## RELICS_CHANGED {kind, delta: -n, count: 0, reason: "sell"} per non-empty kind in config
## order, then one GOLD_CHANGED {reason: "relic_sale"} for the sum (none when it is 0).
func sell_relics(kind := "") -> SimCommand.CommandResult:
	var result := can_sell_relics(kind)
	if result != SimCommand.CommandResult.OK:
		return result
	_ctx.log_command([_state.tick, "sell_relics", kind])
	var total := 0
	for k in _config.economy.relic_ids():
		if kind != "" and k != kind:
			continue
		var n: int = _state.relics[k]
		if n <= 0:
			continue
		total += relic_price(k) * n
		add_relics(k, -n, "sell", 0)
	add_gold(total, "relic_sale", 0)
	return SimCommand.CommandResult.OK


## The night luck call_wave() would set now (LT-27 §1.2): 1 +
## economy.early_night_luck_per_second x whole seconds left on the day timer (seconds
## rounded down from ticks); 1.0 when call_wave() would be refused. Changes nothing.
func early_night_luck(has_director: bool) -> float:
	if _state.outcome != SimState.Outcome.NONE or _state.phase != SimState.Phase.BUILD:
		return 1.0
	if not has_director:
		return 1.0
	var seconds_left := SimTime.whole_seconds(_state.build_ticks_left)
	return 1.0 + _config.economy.early_night_luck_per_second * seconds_left


## Gold a sell of `t` would return now: sell_refund_ratio x t.spent (build + upgrades),
## rounded once.
func sell_refund(t: SimTower) -> int:
	return roundi(t.spent * _config.economy.sell_refund_ratio)


## The dawn wage (LT-27 §2; the wave completion bonus) for 1-based `wave_number`: base +
## per_wave * wave_number money (economy.json wave_bonus). Called by the wave system (LT-5);
## not a player command, so not logged. Returns the money added; 0 (and nothing changes)
## once the outcome is set.
func award_wave_bonus(wave_number: int) -> int:
	if _state.outcome != SimState.Outcome.NONE:
		return 0
	if wave_number < 1:
		push_error("EconomySystem.award_wave_bonus: wave_number %d < 1" % wave_number)
		return 0
	var econ := _config.economy
	var bonus := econ.wave_bonus_base + econ.wave_bonus_per_wave * wave_number
	add_gold(bonus, "wave_bonus", 0)
	return bonus


## LT-27 §1.2: one draw on `stream` picks a relic kind from `def.drops` (config order).
## Every kind's weight is multiplied by state.night_luck except the table's cheapest kind
## (lowest price among the kinds with weight > 0; ties -> the first in config order).
func _roll_drop(def: EnemyDef, stream: SimRng.Stream) -> String:
	var cheapest := ""
	for kind: String in def.drops:
		if def.drops[kind] > 0 and (cheapest == "" or relic_price(kind) < relic_price(cheapest)):
			cheapest = kind
	var weights: Array[float] = []
	var total := 0.0
	for kind: String in def.drops:
		var w := float(def.drops[kind])
		if kind != cheapest:
			w *= _state.night_luck
		weights.append(w)
		total += w
	var r := _ctx.rng(stream).randf() * total
	var i := 0
	var last := cheapest
	for kind: String in def.drops:
		var w := weights[i]
		i += 1
		if w <= 0.0:
			continue
		last = kind
		if r < w:
			return kind
		r -= w
	return last  # float rounding at the very top of the range


## LT-27 §1.3: the kill of `e` drops one token, rolled on LOOT (real) or GHOST_LOOT (fake)
## with the same table and luck. Emits RELIC_DROPPED {token, kind, at, arrive_tick}, the
## same shape and timing for both; only _ghost_tokens remembers a ghost.
func drop_token(e: SimEnemy) -> void:
	var tok := RelicToken.new()
	tok.id = _state.next_token_id
	_state.next_token_id += 1
	tok.kind = _roll_drop(e.def, SimRng.Stream.GHOST_LOOT if e.is_fake else SimRng.Stream.LOOT)
	tok.at = e.route.position_at(e.distance)
	tok.drop_tick = _state.tick
	tok.arrive_tick = _state.tick + SimTime.ticks(_config.economy.token_fly_seconds)
	_state.relic_tokens.append(tok)
	if e.is_fake:
		_ghost_tokens[tok.id] = true
	_ctx.emit(SimEvent.Type.RELIC_DROPPED, tok.id, {"token": tok.id, "kind": tok.kind,
		"at": tok.at, "arrive_tick": tok.arrive_tick})


## Slot 6b (LT-27 §1.3), tokens in id order: a ghost vanishes at drop_tick +
## ticks(ghost_vanish_seconds) (RELIC_VANISHED, credits nothing); a real token is credited at
## its arrive_tick (RELICS_CHANGED {reason: "kill"}). Both leave state.relic_tokens.
func settle_tokens() -> void:
	if _state.relic_tokens.is_empty():
		return
	var vanish := SimTime.ticks(_config.economy.ghost_vanish_seconds)
	var kept: Array[RelicToken] = []
	for tok in _state.relic_tokens:
		if _ghost_tokens.has(tok.id):
			if _state.tick >= tok.drop_tick + vanish:
				_vanish_token(tok)
				continue
		elif _state.tick >= tok.arrive_tick:
			add_relics(tok.kind, 1, "kill", tok.id)
			continue
		kept.append(tok)
	_state.relic_tokens = kept


## Dawn (LT-27 §1.3, called by the wave director right after dissolve_fakes): every token in
## flight settles now, in id order: ghosts vanish, real tokens are credited. A day starts with
## no token in flight.
func settle_all_tokens() -> void:
	for tok in _state.relic_tokens:
		if _ghost_tokens.has(tok.id):
			_vanish_token(tok)
		else:
			add_relics(tok.kind, 1, "kill", tok.id)
	_state.relic_tokens = []


func _vanish_token(tok: RelicToken) -> void:
	_ghost_tokens.erase(tok.id)
	_ctx.emit(SimEvent.Type.RELIC_VANISHED, tok.id, {"token": tok.id})


## Every stash change goes through here: RELICS_CHANGED {kind, delta, count, reason} (+ token
## for a kill); id = the token (kill) or 0 (sell).
func add_relics(kind: String, delta: int, reason: String, token: int) -> void:
	if delta == 0:
		return
	_state.relics[kind] = _state.relics.get(kind, 0) + delta
	var data := {"kind": kind, "delta": delta, "count": _state.relics[kind], "reason": reason}
	if token > 0:
		data["token"] = token
	_ctx.emit(SimEvent.Type.RELICS_CHANGED, token, data)
