class_name SanitySystem
extends RefCounted
## LT-80 (LT-65 §3.1, B5): sanity, the cap held by tower reserves, the threshold state and
## madness. Owns sanity, sanity_cap and sanity_state, and the buyout / debug / restore /
## regen paths whole. Built once by the sim facade, which orders the step slots and
## forwards the public names. Gold goes through EconomySystem; events and the command log
## through SimContext.

## Sanity change reasons that may move sanity while in MADNESS (LT-13): the exit rules.
const MADNESS_EXIT_REASONS: PackedStringArray = ["buyout", "auto_restore"]

var _ctx: SimContext
var _state: SimState
var _config: GameConfig
var _economy: EconomySystem


func _init(ctx: SimContext, economy: EconomySystem) -> void:
	_ctx = ctx
	_state = ctx.state
	_config = ctx.config
	_economy = economy
	_state.sanity_cap = _config.sanity.max_sanity
	_state.sanity = clampf(_config.sanity.start, 0.0, _state.sanity_cap)
	_state.sanity_state = sanity_state_for(_state.sanity)  # initial state: no event


## LT-23 Q3: reserving `delta` more cap would take it to 0 (and so start madness); a delta
## <= 0 never does, and nothing does while already in MADNESS.
func reserve_drives_mad(delta: float) -> bool:
	return delta > 0.0 and _state.sanity_cap - delta <= 0.0 \
		and _state.sanity_state != SimState.SanityState.MADNESS


## LT-36: whether the buyout can apply at all right now: exit rule "buyout" and the player
## in MADNESS (gold, cap room and outcome aside: can_buy_sanity says if it would be applied).
## The HUD shows the buyout button exactly while this is true. Changes nothing.
func buyout_applies() -> bool:
	return _config.sanity.madness.exit_rule == "buyout" \
		and _state.sanity_state == SimState.SanityState.MADNESS


## LT-121: whether the player is in MADNESS under exit_rule "recover", i.e. climbing back
## to exit_target(). The HUD shows the exit mark and the recover line exactly while this is
## true. Changes nothing.
func recover_applies() -> bool:
	return _config.sanity.madness.exit_rule == "recover" \
		and _state.sanity_state == SimState.SanityState.MADNESS


## Whether buy_sanity() would be applied now; OK or the first failing reason, in this
## order: OUTCOME_REACHED, NO_BUYOUT, NOT_IN_MADNESS, NO_SANITY_ROOM (the cap is 0, LT-23
## Q6), NOT_ENOUGH_GOLD. Changes nothing.
func can_buy_sanity() -> SimCommand.CommandResult:
	if _state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	var m := _config.sanity.madness
	if m.exit_rule != "buyout":
		return SimCommand.CommandResult.NO_BUYOUT
	if _state.sanity_state != SimState.SanityState.MADNESS:
		return SimCommand.CommandResult.NOT_IN_MADNESS
	if restore_target() <= 0.0:
		return SimCommand.CommandResult.NO_SANITY_ROOM
	if _state.gold < m.buyout_cost:
		return SimCommand.CommandResult.NOT_ENOUGH_GOLD
	return SimCommand.CommandResult.OK


## Player command (LT-13, exit rule "buyout"): pays madness.buyout_cost gold and sets sanity
## to restore_target() (min of madness.restore_sanity and the cap), in any phase (also at
## night, LT-27 §3). Emits GOLD_CHANGED {reason: "buyout"}, then
## SANITY_CHANGED {reason: "buyout"} and SANITY_STATE_CHANGED (MADNESS -> the new state).
func buy_sanity() -> SimCommand.CommandResult:
	var result := can_buy_sanity()
	if result != SimCommand.CommandResult.OK:
		return result
	var m := _config.sanity.madness
	_ctx.log_command([_state.tick, "buy_sanity"])
	_economy.add_gold(-m.buyout_cost, "buyout", 0)
	add(restore_target() - _state.sanity, "buyout", 0)
	return SimCommand.CommandResult.OK


## LT-107: debug_set_sanity's check, changes nothing: OUTCOME_REACHED once the run is
## over, else OK (any value is accepted).
func can_debug_set_sanity(_value: float) -> SimCommand.CommandResult:
	if _state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	return SimCommand.CommandResult.OK


## Debug command (LT-34, LT-33 finding 5; the `--sanity` flag of debug builds): sets
## sanity to `value` through add "debug" (clamped to [0, sanity_cap]; SANITY_CHANGED
## {reason: "debug"} and SANITY_STATE_CHANGED as usual; nothing applies while in MADNESS,
## "debug" is no exit reason). Logged as [tick, "debug_set_sanity", value] so a replay
## reproduces it. OUTCOME_REACHED once the run is over, else OK.
func debug_set_sanity(value: float) -> SimCommand.CommandResult:
	var result := can_debug_set_sanity(value)
	if result != SimCommand.CommandResult.OK:
		return result
	_ctx.log_command([_state.tick, "debug_set_sanity", value])
	add(value - _state.sanity, "debug", 0)
	return SimCommand.CommandResult.OK


## Exit rule "auto_restore" (LT-13): called by the wave system when a wave is cleared,
## after the bonus and between-waves regen, before WAVE_CLEARED. In MADNESS, sets sanity to
## restore_target() (SANITY_CHANGED {reason: "auto_restore"}; nothing at cap 0, LT-23 Q6);
## otherwise, under another exit rule or once the outcome is set, does nothing. Returns the
## applied delta.
func auto_restore_sanity() -> float:
	if _state.outcome != SimState.Outcome.NONE:
		return 0.0
	var m := _config.sanity.madness
	if m.exit_rule != "auto_restore" or _state.sanity_state != SimState.SanityState.MADNESS:
		return 0.0
	return add(restore_target() - _state.sanity, "auto_restore", 0)


## Sanity a buyout / auto restore sets (LT-23 Q6): min(madness.restore_sanity, sanity_cap).
func restore_target() -> float:
	return minf(_config.sanity.madness.restore_sanity, _state.sanity_cap)


## LT-121 §2: sanity at which MADNESS ends under exit_rule "recover":
## min(madness.exit_sanity, sanity_cap). At cap 0 there is no exit (0 is still MADNESS).
func exit_target() -> float:
	return minf(_config.sanity.madness.exit_sanity, _state.sanity_cap)


## The sanity cap `t` holds now: its current level's (or branch's) sanity_reserve.
func reserve_of(t: SimTower) -> float:
	return t.stats().sanity_reserve


## How much more cap tower `def_id` holds at `to` than at `from` (negative when it holds
## less); for previews and upgrade_tower. `def_id` names the tower for readers of a preview.
func reserve_delta(_def_id: String, from: TowerDef.Level, to: TowerDef.Level) -> float:
	return to.sanity_reserve - from.sanity_reserve


## LT-23 §1.2: tower `t` now holds `delta` more cap (negative: less). The cap is recomputed
## as sanity.max minus every standing tower's reserve, floored at 0, and SANITY_CAP_CHANGED
## {delta, cap, reason} (id = tower, delta = the change actually applied) is emitted when it
## moves; then sanity above the new cap drops to it (add "reserve", so a cap of 0
## starts MADNESS). Sanity below the cap never changes here (Q1, Q4). Called by build,
## upgrade and sell after their gold event; `t` is already removed on a sell.
func change_reserve(t: SimTower, delta: float, reason: String) -> void:
	if delta == 0.0:
		return
	var reserved := 0.0
	for tower in _state.towers:
		reserved += reserve_of(tower)
	var before := _state.sanity_cap
	_state.sanity_cap = maxf(0.0, _config.sanity.max_sanity - reserved)
	var applied := _state.sanity_cap - before
	if applied == 0.0:
		return
	_ctx.emit(SimEvent.Type.SANITY_CAP_CHANGED, t.id,
		{"delta": applied, "cap": _state.sanity_cap, "reason": reason})
	if _state.sanity > _state.sanity_cap:
		add(_state.sanity_cap - _state.sanity, "reserve", t.id)


## Between-waves sanity regen (sanity.json regen.between_waves), paid once per cleared wave
## by the wave system right after award_wave_bonus, so also for the last wave in the tick
## WON is set. Returns the sanity actually added (0 at the cap or once the outcome is set).
func award_wave_sanity() -> float:
	if _state.outcome != SimState.Outcome.NONE:
		return 0.0
	return add(_config.sanity.regen_between_waves, "between_waves", 0)


## Threshold state for a sanity value (GDD §5.3, §5.4): MADNESS iff s <= 0 ("triggered when
## sanity hits 0"); otherwise the highest state whose `min` <= s, with FRAYING covering
## everything in (0, whispers.min), so 0 < s < fraying.min is FRAYING, not MADNESS.
func sanity_state_for(s: float) -> SimState.SanityState:
	if s <= 0.0:
		return SimState.SanityState.MADNESS
	var th := _config.sanity.thresholds
	if s >= th["lucid"].min_sanity:
		return SimState.SanityState.LUCID
	if s >= th["whispers"].min_sanity:
		return SimState.SanityState.WHISPERS
	return SimState.SanityState.FRAYING


## LT-121 §2: the state after a sanity change from `old` to `s`. Under exit_rule "recover"
## MADNESS holds while s < exit_target() (hysteresis: entry at 0, exit at exit_sanity);
## otherwise, and under the other rules, sanity_state_for(s).
func _next_state(old: SimState.SanityState, s: float) -> SimState.SanityState:
	if old == SimState.SanityState.MADNESS and _config.sanity.madness.exit_rule == "recover" \
			and s < exit_target():
		return SimState.SanityState.MADNESS
	return sanity_state_for(s)


## Every sanity change goes through here: clamps to [0, sanity_cap], then emits SANITY_CHANGED
## {delta, sanity, reason} with the delta actually applied (nothing when it is 0, e.g. regen
## at the cap), and SANITY_STATE_CHANGED {old, new} (SimState.SanityState values) when the
## threshold state moves. `id` is the enemy (kill) or tower (build, cast) it is about,
## 0 otherwise ("reserve": the cap fell below sanity). MADNESS is latched (LT-13): while in it only MADNESS_EXIT_REASONS change
## sanity; regen and drain apply nothing and emit nothing. Under exit_rule "recover"
## (LT-121) every reason applies while mad, and the state leaves MADNESS only once sanity
## reaches exit_target() (see _next_state).
## Returns the applied delta.
func add(delta: float, reason: String, id: int) -> float:
	if _state.sanity_state == SimState.SanityState.MADNESS \
			and _config.sanity.madness.exit_rule != "recover" \
			and not MADNESS_EXIT_REASONS.has(reason):
		return 0.0
	var before := _state.sanity
	_state.sanity = clampf(before + delta, 0.0, _state.sanity_cap)
	var applied := _state.sanity - before
	if applied == 0.0:
		return 0.0
	_ctx.emit(SimEvent.Type.SANITY_CHANGED, id,
		{"delta": applied, "sanity": _state.sanity, "reason": reason})
	var old := _state.sanity_state
	_state.sanity_state = _next_state(old, _state.sanity)
	if _state.sanity_state != old:
		_ctx.emit(SimEvent.Type.SANITY_STATE_CHANGED, 0, {"old": old, "new": _state.sanity_state})
	return applied


## Slot 6: every live real enemy with horror_drain > 0 within sanity.horror_radius_cells of
## any tower (same metric as enemies_in_range: enemy position to tower cell centre, boundary
## included) drains horror_drain per second, i.e. horror_drain * DT per tick; counted once
## per enemy however many towers are near. Fakes never drain (illusions, LT-12); flyers do.
## One SANITY_CHANGED "horror" per tick with the summed delta.
func horror_drain() -> void:
	if _state.towers.is_empty():
		return
	var r := _config.sanity.horror_radius_cells
	var r2 := r * r
	var total := 0.0
	for e in _state.enemies:
		if not e.is_live() or e.is_fake or e.def.horror_drain <= 0.0:
			continue
		var p := e.route.position_at(e.distance)
		for t in _state.towers:
			var c := t.centre()
			var dx := float(p.x) - c.x
			var dy := float(p.y) - c.y
			if dx * dx + dy * dy <= r2:
				total += e.def.horror_drain * SimTime.DT
				break
	if total > 0.0:
		add(-total, "horror", 0)


## Slot 2, after _apply_auras (LT-23 §3): in MADNESS every live enemy, real and fake alike,
## gets speed_mult x madness.enemy_speed_multiplier and damage_taken_mult x
## madness.enemy_damage_taken_multiplier for this tick (on top of any aura), except those
## madness_buff_blocked holds back. Reset with the other modifiers in slot 1, so it ends
## the tick after MADNESS does.
func apply_madness_buff() -> void:
	if _state.sanity_state != SimState.SanityState.MADNESS:
		return
	var m := _config.sanity.madness
	if m.enemy_speed_multiplier == 1.0 and m.enemy_damage_taken_multiplier == 1.0:
		return
	for e in _state.enemies:
		if not e.is_live() or madness_buff_blocked(e):
			continue
		e.speed_mult *= m.enemy_speed_multiplier
		e.damage_taken_mult *= m.enemy_damage_taken_multiplier


## LT-30 (LT-26 D4): true when `e` must not get the madness buff: lit this tick (the
## lighthouse beam, the flare or, LT-70 Q1, a Searchlight's casts_light radius; real and
## fake alike) and beam.enemy.cancel_madness_buff is on.
func madness_buff_blocked(e: SimEnemy) -> bool:
	return _config.economy.beam.cancel_madness_buff and e.lit


## The sanity.json threshold of the current sanity state (SimState.SanityState and
## SanityConfig.STATES share their order: LUCID..MADNESS = "lucid".."madness").
func threshold() -> SanityConfig.Threshold:
	return _config.sanity.thresholds[SanityConfig.STATES[_state.sanity_state]]
