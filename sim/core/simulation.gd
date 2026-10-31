class_name Simulation
extends RefCounted
## The plain-script game simulation (design note LT-4). Advanced one fixed tick at a
## time by step(); scenes read `state` directly and drain one-shot events.
## Same config + seed + command log -> same events and state (§4).

## Result of a player command (build/sell/upgrade/set_target_priority). OK = applied; anything else = rejected
## and nothing changed (no gold, no event, no command_log entry).
enum CommandResult {
	OK,
	OUTCOME_REACHED,  ## the run is over; every command is refused
	UNKNOWN_TOWER,  ## no such tower def
	NOT_AVAILABLE,  ## reserved: no tower kind is refused since LT-11 (kept so values never shift)
	NOT_BUILDABLE,  ## path, water, the lighthouse or out of bounds
	OCCUPIED,  ## another tower stands on the cell
	NOT_ENOUGH_GOLD,
	NO_SUCH_TOWER,  ## sell/upgrade/set_target_priority: unknown or already sold tower id
	## call_wave: not in the build phase (or no WaveDirector); build, sell, upgrade,
	## sell_relics: at night (during a wave, _day_only)
	NOT_BUILD_PHASE,
	NO_BUYOUT,  ## buy_sanity: madness.exit_rule is not "buyout"
	NOT_IN_MADNESS,  ## buy_sanity: sanity state is not MADNESS
	MAX_LEVEL,  ## upgrade: the tower is at L3
	NEED_BRANCH,  ## upgrade: L2 -> L3 needs branch "a" or "b"
	BAD_BRANCH,  ## upgrade: branch is not ""/"a"/"b", or non-empty for L1 -> L2
	NO_TARGETING,  ## set_target_priority: the tower picks no target (aura, Elder Sign)
	BAD_PRIORITY,  ## set_target_priority: mode is not one of SimTower.TARGET_PRIORITIES
	NO_SANITY_ROOM,  ## buy_sanity: the sanity cap is 0, a buyout would restore nothing (LT-23)
	NO_RELICS,  ## sell_relics: unknown kind or nothing of it in the stash (LT-27)
	UNKNOWN_COMMAND,  ## replay_command: the entry names no command (LT-34)
	BAD_ARGS,  ## replay_command: a known command with missing, extra or wrong-typed args (LT-36)
	NOT_NIGHT,  ## fire_flare: by day (phase BUILD) or after the last wave (DONE) (LT-30)
	ON_COOLDOWN,  ## fire_flare: the previous flare's cooldown is still running (LT-30)
	NO_FLARE,  ## fire_flare / buy_oil: no lighthouse.flare / lighthouse.oil block (LT-30)
	NO_OIL,  ## fire_flare: less oil in stock than flare.cost_oil (LT-30)
	OIL_FULL,  ## buy_oil: the stock is at oil.cap (LT-30)
}

## Sanity change reasons that may move sanity while in MADNESS (LT-13): the exit rules.
const MADNESS_EXIT_REASONS: PackedStringArray = ["buyout", "auto_restore"]

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
## LT-27 §1.3: token id -> true for tokens dropped by fakes. Sim-private: the render must
## never tell a ghost token from a real one before it vanishes.
var _ghost_tokens: Dictionary[int, bool] = {}


func _init(p_config: GameConfig, run_seed: int) -> void:
	config = p_config
	_rng = SimRng.new(run_seed)
	state = SimState.new()
	state.map = config.map
	state.lighthouse_hp = config.economy.lighthouse_hp
	state.gold = config.economy.starting_gold
	for kind in config.economy.relic_ids():
		state.relics[kind] = 0
	state.sanity_cap = config.sanity.max_sanity
	state.sanity = clampf(config.sanity.start, 0.0, state.sanity_cap)
	state.sanity_state = sanity_state_for(state.sanity)  # initial state: no event
	if config.economy.oil != null:
		state.oil = config.economy.oil.start
	_start_beam()
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
	# 2. Effect systems: the lighthouse beam first (LT-30: turn, `lit` of towers and enemies),
	# then Elder Sign auras (LT-11), the madness buff (LT-23 §3) and the flare's slow;
	# later slows/stuns add theirs here. The flare timers count down last.
	_update_beam()
	_apply_auras()
	_apply_madness_buff()
	_apply_flare_slow()
	_count_down_flare()
	# 3. Movement.
	_move()
	# 4. Leaks.
	_leak()
	# 5. Towers fire / damage: single and line shots (LT-6), AoE casts (LT-11, no sanity
	# cost since LT-23); madness damage and astray shots (LT-13). Kills drop relic tokens
	# (LT-27 §1.3).
	_fire_towers()
	# 6. Sanity (LT-10): horror drain. Kill regen is paid in slot 5 (_on_enemy_killed),
	# between-waves regen in slot 8 (wave system), each through _add_sanity.
	_horror_drain()
	# 6b. Relic tokens (LT-27 §1.3): ghosts vanish, real tokens are credited on arrival.
	_settle_tokens()
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
		_emit(SimEvent.Type.DIED, e.id, {"source": source})
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
	return _day_only()  # last: keeps "first failing reason in CommandResult order" (LT-27 §3)


## Player command (§1.3, applied at once between ticks): builds an L1 `def_id` on `cell`
## for its cost. On OK the tower gets the next entity id, is ready to fire on the next
## tick, and TOWER_BUILT + GOLD_CHANGED are emitted. Its L1 sanity_reserve then lowers the
## cap (_change_reserve "build", LT-23 §1.2); a cap taken to 0 empties sanity and so starts
## MADNESS. Only gold is checked. Day only (LT-27 §3): refused at night with NOT_BUILD_PHASE.
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
	_change_reserve(t, reserve_of(t), "build")
	return CommandResult.OK


## Whether sell_tower(tower_id) would be applied now; OK or the first failing reason in this
## order: OUTCOME_REACHED, NO_SUCH_TOWER, NOT_BUILD_PHASE (at night, LT-27 §3). Changes
## nothing.
func can_sell_tower(tower_id: int) -> CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return CommandResult.OUTCOME_REACHED
	if tower_by_id(tower_id) == null:
		return CommandResult.NO_SUCH_TOWER
	return _day_only()


## Player command: sells tower `tower_id` for economy.sell_refund_ratio of everything spent
## on it, build and upgrades (rounded once, on the total) and frees its cell. Emits
## TOWER_SOLD + GOLD_CHANGED, then the cap rises by the tower's reserve (_change_reserve
## "sell", LT-23 Q4); current sanity does not change, in MADNESS too. Day only (LT-27 §3):
## OUTCOME_REACHED, NO_SUCH_TOWER, then NOT_BUILD_PHASE at night.
func sell_tower(tower_id: int) -> CommandResult:
	var result := can_sell_tower(tower_id)
	if result != CommandResult.OK:
		return result
	var t := tower_by_id(tower_id)
	var refund := sell_refund(t)
	var reserve := reserve_of(t)
	state.towers.erase(t)
	state.tower_at.erase(t.cell)
	state.command_log.append([state.tick, "sell", tower_id])
	_emit(SimEvent.Type.TOWER_SOLD, t.id, {"def": t.def.id, "cell": t.cell, "refund": refund})
	_add_gold(refund, "sell", t.id)
	_change_reserve(t, -reserve, "sell")
	return CommandResult.OK


## Branches upgrade_tower accepts for `t` now (LT-24 §2): [""] at L1, ["a", "b"] at L2,
## [] at L3.
func upgrade_branches(t: SimTower) -> PackedStringArray:
	if t.level >= TowerDef.LEVEL_COUNT:
		return PackedStringArray()
	if t.level == TowerDef.LEVEL_COUNT - 1:
		return TowerDef.BRANCH_IDS
	return PackedStringArray([""])


## The level `t` would become with `branch`: def.levels[level + 1] below L2, the branch
## at L2; null at L3 or when `branch` is not one upgrade_branches(t) accepts.
func upgrade_target(t: SimTower, branch := "") -> TowerDef.Level:
	if not upgrade_branches(t).has(branch):
		return null
	if t.level == TowerDef.LEVEL_COUNT - 1:
		return t.def.branches[branch]
	return t.def.levels[t.level + 1]


## Whether upgrade_tower(tower_id, branch) would be applied now; OK or the first failing
## reason in this order: OUTCOME_REACHED, NO_SUCH_TOWER, MAX_LEVEL, NEED_BRANCH,
## BAD_BRANCH, NOT_BUILD_PHASE (at night, _day_only), NOT_ENOUGH_GOLD. Only gold is checked,
## not the sanity cap. Changes nothing.
func can_upgrade(tower_id: int, branch := "") -> CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return CommandResult.OUTCOME_REACHED
	var t := tower_by_id(tower_id)
	if t == null:
		return CommandResult.NO_SUCH_TOWER
	if t.level >= TowerDef.LEVEL_COUNT:
		return CommandResult.MAX_LEVEL
	if t.level == TowerDef.LEVEL_COUNT - 1 and branch.is_empty():
		return CommandResult.NEED_BRANCH
	var target := upgrade_target(t, branch)
	if target == null:
		return CommandResult.BAD_BRANCH
	var day := _day_only()
	if day != CommandResult.OK:
		return day
	if state.gold < target.upgrade_cost:
		return CommandResult.NOT_ENOUGH_GOLD
	return CommandResult.OK


## Player command (LT-24): raises tower `tower_id` one level (L1 -> L2 with branch "", L2 ->
## L3 with "a"/"b") for the target's upgrade_cost, by day only. The tower keeps its
## id, cell, build_tick, status and running cooldown; the new stats apply from its next
## shot. Emits TOWER_UPGRADED {def, cell, level, branch, cost} + GOLD_CHANGED "upgrade";
## the cap then moves by target reserve - current reserve (_change_reserve "upgrade",
## LT-23 §1.2), like a build: a cap taken to 0 starts MADNESS; a lower reserve raises it.
func upgrade_tower(tower_id: int, branch := "") -> CommandResult:
	var result := can_upgrade(tower_id, branch)
	if result != CommandResult.OK:
		return result
	var t := tower_by_id(tower_id)
	var target := upgrade_target(t, branch)
	var delta := reserve_delta(t.def.id, t.stats(), target)
	t.level += 1
	t.branch = branch
	t.spent += target.upgrade_cost
	state.command_log.append([state.tick, "upgrade", tower_id, branch])
	_emit(SimEvent.Type.TOWER_UPGRADED, t.id, {"def": t.def.id, "cell": t.cell,
		"level": t.level, "branch": branch, "cost": target.upgrade_cost})
	_add_gold(-target.upgrade_cost, "upgrade", t.id)
	_change_reserve(t, delta, "upgrade")
	return CommandResult.OK


## LT-34 (LT-33 finding 4): whether build_tower(def_id, ...) would start MADNESS: its L1
## sanity_reserve takes the cap to 0 or below (LT-23 Q3); never while already in MADNESS.
## False for an unknown def_id. Checks no gold, cell, phase or outcome: the UI warns only on
## a button can_build allows. Changes nothing.
func would_drive_mad_build(def_id: String) -> bool:
	if not config.towers.has(def_id):
		return false
	var def: TowerDef = config.towers[def_id]
	return _reserve_drives_mad(def.levels[0].sanity_reserve)


## LT-34: whether upgrade_tower(tower_id, branch) would start MADNESS: its reserve delta
## (reserve_delta, the upgrade's own) takes the cap to 0 or below; never in MADNESS. False
## for an unknown tower or no upgrade_target (L3, a bad branch). Checks no gold, phase or
## outcome. Changes nothing.
func would_drive_mad_upgrade(tower_id: int, branch := "") -> bool:
	var t := tower_by_id(tower_id)
	if t == null:
		return false
	var target := upgrade_target(t, branch)
	if target == null:
		return false
	return _reserve_drives_mad(reserve_delta(t.def.id, t.stats(), target))


## LT-23 Q3: reserving `delta` more cap would take it to 0 (and so start madness); a delta
## <= 0 never does, and nothing does while already in MADNESS.
func _reserve_drives_mad(delta: float) -> bool:
	return delta > 0.0 and state.sanity_cap - delta <= 0.0 \
		and state.sanity_state != SimState.SanityState.MADNESS


## Whether `t` picks a target when it fires (LT-31): its current level deals damage.
## False for an aura tower (Elder Sign), which has no target priority to switch.
func has_targeting(t: SimTower) -> bool:
	return t.stats().damage > 0.0


## Whether set_target_priority(tower_id, mode) would be applied now; OK or the first
## failing reason in this order: OUTCOME_REACHED, NO_SUCH_TOWER, NO_TARGETING,
## BAD_PRIORITY. Any phase (it costs nothing). Changes nothing.
func can_set_target_priority(tower_id: int, mode: String) -> CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return CommandResult.OUTCOME_REACHED
	var t := tower_by_id(tower_id)
	if t == null:
		return CommandResult.NO_SUCH_TOWER
	if not has_targeting(t):
		return CommandResult.NO_TARGETING
	if not SimTower.TARGET_PRIORITIES.has(mode):
		return CommandResult.BAD_PRIORITY
	return CommandResult.OK


## Player command (LT-31): sets whom tower `tower_id` shoots from its next shot on, in
## any phase, for free. Re-setting the current mode is applied too (logged, event).
## Emits TARGET_PRIORITY_SET {def, cell, mode}; logs [tick, "set_target_priority", id,
## mode]. The tower's cooldown is not touched.
func set_target_priority(tower_id: int, mode: String) -> CommandResult:
	var result := can_set_target_priority(tower_id, mode)
	if result != CommandResult.OK:
		return result
	var t := tower_by_id(tower_id)
	t.target_priority = mode
	state.command_log.append([state.tick, "set_target_priority", tower_id, mode])
	_emit(SimEvent.Type.TARGET_PRIORITY_SET, t.id, {"def": t.def.id, "cell": t.cell,
		"mode": mode})
	return CommandResult.OK


## Whether call_wave() would be applied now; OK, OUTCOME_REACHED, or NOT_BUILD_PHASE (no
## WaveDirector, or not by day). Changes nothing.
func can_call_wave() -> CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return CommandResult.OUTCOME_REACHED
	if not (_spawner is WaveDirector) or state.phase != SimState.Phase.BUILD:
		return CommandResult.NOT_BUILD_PHASE
	return CommandResult.OK


## Player command ("Light the lamp", LT-27 §1.2): ends the day now; the next wave spawns
## from the next tick on. Sets state.night_luck to early_night_luck() (1 +
## economy.early_night_luck_per_second x whole seconds left on the day timer) for this
## night; pays no money. Emits WAVE_STARTED {early: true}.
func call_wave() -> CommandResult:
	var result := can_call_wave()
	if result != CommandResult.OK:
		return result
	var director := _spawner as WaveDirector
	var luck := early_night_luck()
	state.command_log.append([state.tick, "call_wave"])
	director.start_wave(self, true)
	state.night_luck = luck
	return CommandResult.OK


## LT-36: whether the buyout can apply at all right now: exit rule "buyout" and the player
## in MADNESS (gold, cap room and outcome aside: can_buy_sanity says if it would be applied).
## The HUD shows the buyout button exactly while this is true. Changes nothing.
func buyout_applies() -> bool:
	return config.sanity.madness.exit_rule == "buyout" \
		and state.sanity_state == SimState.SanityState.MADNESS


## Whether buy_sanity() would be applied now; OK or the first failing reason, in this
## order: OUTCOME_REACHED, NO_BUYOUT, NOT_IN_MADNESS, NO_SANITY_ROOM (the cap is 0, LT-23
## Q6), NOT_ENOUGH_GOLD. Changes nothing.
func can_buy_sanity() -> CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return CommandResult.OUTCOME_REACHED
	var m := config.sanity.madness
	if m.exit_rule != "buyout":
		return CommandResult.NO_BUYOUT
	if state.sanity_state != SimState.SanityState.MADNESS:
		return CommandResult.NOT_IN_MADNESS
	if restore_target() <= 0.0:
		return CommandResult.NO_SANITY_ROOM
	if state.gold < m.buyout_cost:
		return CommandResult.NOT_ENOUGH_GOLD
	return CommandResult.OK


## Player command (LT-13, exit rule "buyout"): pays madness.buyout_cost gold and sets sanity
## to restore_target() (min of madness.restore_sanity and the cap), in any phase (also at
## night, LT-27 §3). Emits GOLD_CHANGED {reason: "buyout"}, then
## SANITY_CHANGED {reason: "buyout"} and SANITY_STATE_CHANGED (MADNESS -> the new state).
func buy_sanity() -> CommandResult:
	var result := can_buy_sanity()
	if result != CommandResult.OK:
		return result
	var m := config.sanity.madness
	state.command_log.append([state.tick, "buy_sanity"])
	_add_gold(-m.buyout_cost, "buyout", 0)
	_add_sanity(restore_target() - state.sanity, "buyout", 0)
	return CommandResult.OK


## Debug command (LT-34, LT-33 finding 5; the `--sanity` flag of debug builds): sets
## sanity to `value` through _add_sanity "debug" (clamped to [0, sanity_cap]; SANITY_CHANGED
## {reason: "debug"} and SANITY_STATE_CHANGED as usual; nothing applies while in MADNESS,
## "debug" is no exit reason). Logged as [tick, "debug_set_sanity", value] so a replay
## reproduces it. OUTCOME_REACHED once the run is over, else OK.
func debug_set_sanity(value: float) -> CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return CommandResult.OUTCOME_REACHED
	state.command_log.append([state.tick, "debug_set_sanity", value])
	_add_sanity(value - state.sanity, "debug", 0)
	return CommandResult.OK


# --- LT-30: lighthouse levels, lamp oil and the flare (player commands) -----------------

## LT-30 (LT-26 §1.2): beams of the current lighthouse level (1, 2, 4 or 8).
func beam_count() -> int:
	return config.economy.beam.levels[state.lighthouse_level].beams


## Money for the next lighthouse level; 0 at the top level.
func lighthouse_upgrade_cost() -> int:
	var levels := config.economy.beam.levels
	if state.lighthouse_level + 1 >= levels.size():
		return 0
	return levels[state.lighthouse_level + 1].upgrade_cost


## Whether upgrade_lighthouse() would be applied now; OK or the first failing reason, in
## this order: OUTCOME_REACHED, MAX_LEVEL, NOT_BUILD_PHASE (at night, _day_only),
## NOT_ENOUGH_GOLD. Changes nothing.
func can_upgrade_lighthouse() -> CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return CommandResult.OUTCOME_REACHED
	if state.lighthouse_level + 1 >= config.economy.beam.levels.size():
		return CommandResult.MAX_LEVEL
	var day := _day_only()
	if day != CommandResult.OK:
		return day
	if state.gold < lighthouse_upgrade_cost():
		return CommandResult.NOT_ENOUGH_GOLD
	return CommandResult.OK


## Player command (LT-30 §0, LT-27 D7): raises the lighthouse one level for money, by day
## only. The new beams light from the next night tick on, evenly spaced from the current
## base direction. Emits LIGHTHOUSE_UPGRADED {level, beams, cost} (id 0), then GOLD_CHANGED
## {reason: "lighthouse"}. No refund: the lighthouse is never sold.
func upgrade_lighthouse() -> CommandResult:
	var result := can_upgrade_lighthouse()
	if result != CommandResult.OK:
		return result
	var cost := lighthouse_upgrade_cost()
	state.lighthouse_level += 1
	state.command_log.append([state.tick, "upgrade_lighthouse"])
	_emit(SimEvent.Type.LIGHTHOUSE_UPGRADED, 0, {"level": state.lighthouse_level,
		"beams": beam_count(), "cost": cost})
	_add_gold(-cost, "lighthouse", 0)
	return CommandResult.OK


## Whether buy_oil() would be applied now; OK or the first failing reason, in this order
## (LT-30 §1.2): OUTCOME_REACHED, NO_FLARE (no lighthouse.oil block), NOT_BUILD_PHASE (at
## night, _day_only), OIL_FULL, NOT_ENOUGH_GOLD. Changes nothing.
func can_buy_oil() -> CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return CommandResult.OUTCOME_REACHED
	var oil := config.economy.oil
	if oil == null:
		return CommandResult.NO_FLARE
	var day := _day_only()
	if day != CommandResult.OK:
		return day
	if state.oil >= oil.cap:
		return CommandResult.OIL_FULL
	if state.gold < oil.price:
		return CommandResult.NOT_ENOUGH_GOLD
	return CommandResult.OK


## Player command (LT-30 §1.2): buys one unit of lamp oil for oil.price money, by day only.
## Emits OIL_CHANGED {delta: 1, oil, reason: "buy"}, then GOLD_CHANGED {reason: "oil"}.
## Oil stays across nights and is never sold back.
func buy_oil() -> CommandResult:
	var result := can_buy_oil()
	if result != CommandResult.OK:
		return result
	state.command_log.append([state.tick, "buy_oil"])
	_add_oil(1, "buy")
	_add_gold(-config.economy.oil.price, "oil", 0)
	return CommandResult.OK


## Whether fire_flare() would be applied now; OK or the first failing reason, in this order
## (LT-30 §1.1): OUTCOME_REACHED, NO_FLARE (no lighthouse.flare block), NOT_NIGHT (phase
## BUILD or DONE; NONE allowed, like _day_only), ON_COOLDOWN, NO_OIL. Changes nothing.
func can_fire_flare() -> CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return CommandResult.OUTCOME_REACHED
	var flare := config.economy.flare
	if flare == null:
		return CommandResult.NO_FLARE
	if not _beam_on():
		return CommandResult.NOT_NIGHT
	if state.flare_cooldown_ticks > 0:
		return CommandResult.ON_COOLDOWN
	if state.oil < flare.cost_oil:
		return CommandResult.NO_OIL
	return CommandResult.OK


## Player command (LT-30 §1.1): for flare.seconds the beams widen (half_width_ratio x
## width_mult), stop turning when hold_beams, and every lit enemy moves at
## x enemy_speed_mult; the cooldown runs from now. Emits FLARE_FIRED {ticks, cooldown}
## (id 0), then OIL_CHANGED {delta: -cost_oil, oil, reason: "flare"}.
func fire_flare() -> CommandResult:
	var result := can_fire_flare()
	if result != CommandResult.OK:
		return result
	var flare := config.economy.flare
	state.flare_ticks_left = maxi(1, SimTime.ticks(flare.seconds))
	state.flare_cooldown_ticks = maxi(1, SimTime.ticks(flare.cooldown_seconds))
	state.command_log.append([state.tick, "fire_flare"])
	_emit(SimEvent.Type.FLARE_FIRED, 0, {"ticks": state.flare_ticks_left,
		"cooldown": state.flare_cooldown_ticks})
	_add_oil(-flare.cost_oil, "flare")
	return CommandResult.OK


## Render only (LT-30 §3.2): the direction of every beam, interpolated between the previous
## and the current tick's base direction by `alpha` (0..1) and normalised; empty by day.
## Trig is fine in the render; the sim never reads this.
func beam_directions(alpha: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not _beam_on():
		return out
	var x := lerpf(state.prev_beam_dx, state.beam_dx, alpha)
	var y := lerpf(state.prev_beam_dy, state.beam_dy, alpha)
	var n := sqrt(x * x + y * y)
	if n <= 0.0:
		x = state.beam_dx
		y = state.beam_dy
		n = 1.0
	for d: Array in _dirs_of(x / n, y / n, beam_count()):
		out.append(Vector2(d[0], d[1]))
	return out


## LT-36: the argument types of each command_log entry name, after [tick, name]; the order
## of the public command's parameters. TYPE_STRING also takes a StringName, TYPE_FLOAT an int.
const REPLAY_ARGS: Dictionary[String, Array] = {
	"build": [TYPE_STRING, TYPE_VECTOR2I],
	"sell": [TYPE_INT],
	"upgrade": [TYPE_INT, TYPE_STRING],
	"set_target_priority": [TYPE_INT, TYPE_STRING],
	"call_wave": [],
	"buy_sanity": [],
	"sell_relics": [TYPE_STRING],
	"debug_set_sanity": [TYPE_FLOAT],
	"upgrade_lighthouse": [],
	"buy_oil": [],
	"fire_flare": [],
}


## LT-34: re-applies one command_log entry [tick, name, args...] now (the caller steps the
## sim to entry[0] first) through the same public command, so it is logged again.
## UNKNOWN_COMMAND (and an error) for an entry naming no command; BAD_ARGS (and an error)
## for a known name whose args do not match REPLAY_ARGS in count and type (LT-36). Never
## raises a script error, and a refused entry changes nothing.
func replay_command(entry: Array) -> CommandResult:
	var cmd: Variant = entry[1] if entry.size() > 1 else ""
	if typeof(cmd) not in [TYPE_STRING, TYPE_STRING_NAME] or not REPLAY_ARGS.has(String(cmd)):
		push_error("Simulation.replay_command: unknown entry %s" % [entry])
		return CommandResult.UNKNOWN_COMMAND
	if not _replay_args_ok(entry, REPLAY_ARGS[String(cmd)]):
		push_error("Simulation.replay_command: bad args %s" % [entry])
		return CommandResult.BAD_ARGS
	match String(cmd):
		"build": return build_tower(entry[2], entry[3])
		"sell": return sell_tower(entry[2])
		"upgrade": return upgrade_tower(entry[2], entry[3])
		"set_target_priority": return set_target_priority(entry[2], entry[3])
		"call_wave": return call_wave()
		"buy_sanity": return buy_sanity()
		"sell_relics": return sell_relics(entry[2])
		"debug_set_sanity": return debug_set_sanity(entry[2])
		"upgrade_lighthouse": return upgrade_lighthouse()
		"buy_oil": return buy_oil()
		"fire_flare": return fire_flare()
	return CommandResult.UNKNOWN_COMMAND  # unreachable: every REPLAY_ARGS key has an arm


## Whether entry[2..] has exactly types.size() values, each of the matching type.
func _replay_args_ok(entry: Array, types: Array) -> bool:
	if entry.size() != 2 + types.size():
		return false
	for i in types.size():
		var t := typeof(entry[2 + i])
		var want: int = types[i]
		if t == want or (want == TYPE_STRING and t == TYPE_STRING_NAME) \
				or (want == TYPE_FLOAT and t == TYPE_INT):
			continue
		return false
	return true


## LT-27 §1.4: the money one relic of `kind` sells for (economy.relics price); 0 for an
## unknown kind. The only place a relic price is read.
func relic_price(kind: String) -> int:
	var k := config.economy.relic(kind)
	return 0 if k == null else k.price


## The stash at today's prices: sum of relic_price x count.
func relics_value() -> int:
	var total := 0
	for kind: String in state.relics:
		total += relic_price(kind) * state.relics[kind]
	return total


## Whether sell_relics(kind) would be applied now; OK or the first failing reason in this
## order: OUTCOME_REACHED, NOT_BUILD_PHASE (at night), NO_RELICS (unknown kind, or nothing
## of `kind` / nothing at all for "" in the stash). Changes nothing.
func can_sell_relics(kind := "") -> CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return CommandResult.OUTCOME_REACHED
	var day := _day_only()
	if day != CommandResult.OK:
		return day
	if kind != "":
		return CommandResult.OK if state.relics.get(kind, 0) > 0 else CommandResult.NO_RELICS
	for k: String in state.relics:
		if state.relics[k] > 0:
			return CommandResult.OK
	return CommandResult.NO_RELICS


## Player command (LT-27 §1.4, day only): sells the whole stack of `kind`, or of every kind
## for "", at the fixed relic_price. Logs [tick, "sell_relics", kind]; emits one
## RELICS_CHANGED {kind, delta: -n, count: 0, reason: "sell"} per non-empty kind in config
## order, then one GOLD_CHANGED {reason: "relic_sale"} for the sum (none when it is 0).
func sell_relics(kind := "") -> CommandResult:
	var result := can_sell_relics(kind)
	if result != CommandResult.OK:
		return result
	state.command_log.append([state.tick, "sell_relics", kind])
	var total := 0
	for k in config.economy.relic_ids():
		if kind != "" and k != kind:
			continue
		var n: int = state.relics[k]
		if n <= 0:
			continue
		total += relic_price(k) * n
		_add_relics(k, -n, "sell", 0)
	_add_gold(total, "relic_sale", 0)
	return CommandResult.OK


## Exit rule "auto_restore" (LT-13): called by the wave system when a wave is cleared,
## after the bonus and between-waves regen, before WAVE_CLEARED. In MADNESS, sets sanity to
## restore_target() (SANITY_CHANGED {reason: "auto_restore"}; nothing at cap 0, LT-23 Q6);
## otherwise, under another exit rule or once the outcome is set, does nothing. Returns the
## applied delta.
func auto_restore_sanity() -> float:
	if state.outcome != SimState.Outcome.NONE:
		return 0.0
	var m := config.sanity.madness
	if m.exit_rule != "auto_restore" or state.sanity_state != SimState.SanityState.MADNESS:
		return 0.0
	return _add_sanity(restore_target() - state.sanity, "auto_restore", 0)


## Sanity a buyout / auto restore sets (LT-23 Q6): min(madness.restore_sanity, sanity_cap).
func restore_target() -> float:
	return minf(config.sanity.madness.restore_sanity, state.sanity_cap)


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
## moves; then sanity above the new cap drops to it (_add_sanity "reserve", so a cap of 0
## starts MADNESS). Sanity below the cap never changes here (Q1, Q4). Called by build,
## upgrade and sell after their gold event; `t` is already removed on a sell.
func _change_reserve(t: SimTower, delta: float, reason: String) -> void:
	if delta == 0.0:
		return
	var reserved := 0.0
	for tower in state.towers:
		reserved += reserve_of(tower)
	var before := state.sanity_cap
	state.sanity_cap = maxf(0.0, config.sanity.max_sanity - reserved)
	var applied := state.sanity_cap - before
	if applied == 0.0:
		return
	_emit(SimEvent.Type.SANITY_CAP_CHANGED, t.id,
		{"delta": applied, "cap": state.sanity_cap, "reason": reason})
	if state.sanity > state.sanity_cap:
		_add_sanity(state.sanity_cap - state.sanity, "reserve", t.id)


## The night luck call_wave() would set now (LT-27 §1.2): 1 +
## economy.early_night_luck_per_second x whole seconds left on the day timer (seconds
## rounded down from ticks); 1.0 when call_wave() would be refused. Changes nothing.
func early_night_luck() -> float:
	if state.outcome != SimState.Outcome.NONE or state.phase != SimState.Phase.BUILD:
		return 1.0
	if not (_spawner is WaveDirector):
		return 1.0
	var seconds_left := SimTime.whole_seconds(state.build_ticks_left)
	return 1.0 + config.economy.early_night_luck_per_second * seconds_left


## Gold a sell of `t` would return now: sell_refund_ratio x t.spent (build + upgrades),
## rounded once.
func sell_refund(t: SimTower) -> int:
	return roundi(t.spent * config.economy.sell_refund_ratio)


## The dawn wage (LT-27 §2; the wave completion bonus) for 1-based `wave_number`: base +
## per_wave * wave_number money (economy.json wave_bonus). Called by the wave system (LT-5);
## not a player command, so not logged. Returns the money added; 0 (and nothing changes)
## once the outcome is set.
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


## Every money change ("gold" internally, LT-27 §2) goes through here: GOLD_CHANGED {delta,
## gold, reason}; `id` is the tower (build/sell/upgrade) it is about, 0 for the dawn wage
## ("wave_bonus"), a relic sale ("relic_sale") or the buyout. Kills pay no money since LT-27.
func _add_gold(delta: int, reason: String, id: int) -> void:
	if delta == 0:
		return
	state.gold += delta
	_emit(SimEvent.Type.GOLD_CHANGED, id, {"delta": delta, "gold": state.gold, "reason": reason})


## LT-30 §1.2: the one writer of state.oil (buy_oil +1, fire_flare -cost_oil); emits
## OIL_CHANGED {delta, oil, reason} (id 0). Callers keep it within 0..oil.cap.
func _add_oil(delta: int, reason: String) -> void:
	if delta == 0:
		return
	state.oil += delta
	_emit(SimEvent.Type.OIL_CHANGED, 0, {"delta": delta, "oil": state.oil, "reason": reason})


## Every sanity change goes through here: clamps to [0, sanity_cap], then emits SANITY_CHANGED
## {delta, sanity, reason} with the delta actually applied (nothing when it is 0, e.g. regen
## at the cap), and SANITY_STATE_CHANGED {old, new} (SimState.SanityState values) when the
## threshold state moves. `id` is the enemy (kill) or tower (build, cast) it is about,
## 0 otherwise ("reserve": the cap fell below sanity). MADNESS is latched (LT-13): while in it only MADNESS_EXIT_REASONS change
## sanity; regen and drain apply nothing and emit nothing.
## Returns the applied delta.
func _add_sanity(delta: float, reason: String, id: int) -> float:
	if state.sanity_state == SimState.SanityState.MADNESS \
			and not MADNESS_EXIT_REASONS.has(reason):
		return 0.0
	var before := state.sanity
	state.sanity = clampf(before + delta, 0.0, state.sanity_cap)
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


## Kill hook, called once per enemy when apply_damage kills it. Every kill, real or fake,
## drops one relic token (LT-27 §1.3); only a real one is ever credited. `source` is the
## damage source; for towers it is the tower def id. A real enemy killed by a mundane tower
## restores regen.mundane_kill sanity (only damage-dealing levels fire, so a tower kill is
## always by a damage level).
func _on_enemy_killed(e: SimEnemy, source: String) -> void:
	_drop_token(e)
	if e.is_fake:
		return
	var tower_def: TowerDef = config.towers.get(source)
	if tower_def != null and tower_def.kind == "mundane":
		_add_sanity(config.sanity.regen_mundane_kill, "mundane_kill", e.id)


## LT-27 §3: NOT_BUILD_PHASE at night (phase WAVE), else OK. Not `!= BUILD`, so a sim
## without a WaveDirector (phase NONE) allows everything. The one seam for day-only rules
## (build, sell tower, upgrade, sell relics; later the crew layer, §7).
func _day_only() -> CommandResult:
	if state.phase == SimState.Phase.WAVE:
		return CommandResult.NOT_BUILD_PHASE
	return CommandResult.OK


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
			w *= state.night_luck
		weights.append(w)
		total += w
	var r := rng(stream).randf() * total
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
func _drop_token(e: SimEnemy) -> void:
	var tok := RelicToken.new()
	tok.id = state.next_token_id
	state.next_token_id += 1
	tok.kind = _roll_drop(e.def, SimRng.Stream.GHOST_LOOT if e.is_fake else SimRng.Stream.LOOT)
	tok.at = e.route.position_at(e.distance)
	tok.drop_tick = state.tick
	tok.arrive_tick = state.tick + SimTime.ticks(config.economy.token_fly_seconds)
	state.relic_tokens.append(tok)
	if e.is_fake:
		_ghost_tokens[tok.id] = true
	_emit(SimEvent.Type.RELIC_DROPPED, tok.id, {"token": tok.id, "kind": tok.kind,
		"at": tok.at, "arrive_tick": tok.arrive_tick})


## Slot 6b (LT-27 §1.3), tokens in id order: a ghost vanishes at drop_tick +
## ticks(ghost_vanish_seconds) (RELIC_VANISHED, credits nothing); a real token is credited at
## its arrive_tick (RELICS_CHANGED {reason: "kill"}). Both leave state.relic_tokens.
func _settle_tokens() -> void:
	if state.relic_tokens.is_empty():
		return
	var vanish := SimTime.ticks(config.economy.ghost_vanish_seconds)
	var kept: Array[RelicToken] = []
	for tok in state.relic_tokens:
		if _ghost_tokens.has(tok.id):
			if state.tick >= tok.drop_tick + vanish:
				_vanish_token(tok)
				continue
		elif state.tick >= tok.arrive_tick:
			_add_relics(tok.kind, 1, "kill", tok.id)
			continue
		kept.append(tok)
	state.relic_tokens = kept


## Dawn (LT-27 §1.3, called by the wave director right after dissolve_fakes): every token in
## flight settles now, in id order: ghosts vanish, real tokens are credited. A day starts with
## no token in flight.
func settle_all_tokens() -> void:
	for tok in state.relic_tokens:
		if _ghost_tokens.has(tok.id):
			_vanish_token(tok)
		else:
			_add_relics(tok.kind, 1, "kill", tok.id)
	state.relic_tokens = []


func _vanish_token(tok: RelicToken) -> void:
	_ghost_tokens.erase(tok.id)
	_emit(SimEvent.Type.RELIC_VANISHED, tok.id, {"token": tok.id})


## Every stash change goes through here: RELICS_CHANGED {kind, delta, count, reason} (+ token
## for a kill); id = the token (kill) or 0 (sell).
func _add_relics(kind: String, delta: int, reason: String, token: int) -> void:
	if delta == 0:
		return
	state.relics[kind] = state.relics.get(kind, 0) + delta
	var data := {"kind": kind, "delta": delta, "count": state.relics[kind], "reason": reason}
	if token > 0:
		data["token"] = token
	_emit(SimEvent.Type.RELICS_CHANGED, token, data)


# --- LT-30: the lighthouse beam in the sim (LT-26 §1.1; trig-free: + - * / sqrt only) ----

## LT-30 Q3 "Только ночью": the beam turns and lights only at night (phase WAVE) or without
## a WaveDirector (phase NONE, unit tests). By day (BUILD) and after the last wave (DONE)
## it is dark: nothing lit, direction held.
func _beam_on() -> bool:
	return state.phase != SimState.Phase.BUILD and state.phase != SimState.Phase.DONE


## A flare burns this tick (LT-30 §1.1).
func _flaring() -> bool:
	return state.flare_ticks_left > 0 and config.economy.flare != null


## tan of the beams' half angle this tick: half_width_ratio, x flare.width_mult while a
## flare burns.
func _beam_half_width() -> float:
	var k := config.economy.beam.half_width_ratio
	if _flaring():
		k *= config.economy.flare.width_mult
	return k


## Slot 2, first (LT-30 §3.1): saves prev_beam_* (also when held, so the render does not
## jump), turns the base direction (night only, not while a flare holds it), then sets `lit`
## of every tower (centre; TOWER_LIT {lit} on a flip, id order) and of every live enemy
## (route position at the start of the tick, as auras). By day every flag is false.
func _update_beam() -> void:
	state.prev_beam_dx = state.beam_dx
	state.prev_beam_dy = state.beam_dy
	var on := _beam_on()
	if on and not (_flaring() and config.economy.flare.hold_beams):
		_turn_beam()
	var dirs := _beam_dirs() if on else []
	var k := _beam_half_width()
	for t in state.towers:
		var c := t.centre()
		var lit := on and _lit_by(dirs, k, c.x, c.y)
		if lit != t.lit:
			t.lit = lit
			_emit(SimEvent.Type.TOWER_LIT, t.id, {"lit": lit})
	if not on:
		return
	for e in state.enemies:
		if not e.is_live():
			continue
		var p := e.route.position_at(e.distance)
		e.lit = _lit_by(dirs, k, p.x, p.y)


## Run start: "rotate" points the base direction left (SimState default); "sweep" starts at
## sweep_edges[0] (normalised), so the beam begins inside its arc and _turn_beam's edge
## checks reverse it once per edge (LT-30 review F1).
func _start_beam() -> void:
	var b := config.economy.beam
	if b.pattern != "sweep" or b.sweep_edges.size() != 2:
		return
	var x: float = b.sweep_edges[0][0]
	var y: float = b.sweep_edges[0][1]
	var n := sqrt(x * x + y * y)
	state.beam_dx = x / n
	state.beam_dy = y / n
	state.prev_beam_dx = state.beam_dx
	state.prev_beam_dy = state.beam_dy


## Rotates the base direction by the exact rational rotation of beam.turn_t (x beam_sign):
## c = (1 - t²)/(1 + t²), s = 2t/(1 + t²), then renormalises. "sweep" reverses beam_sign once
## the direction passes the arc edge it is heading for.
func _turn_beam() -> void:
	var b := config.economy.beam
	var t := b.turn_t * state.beam_sign
	if t == 0.0:
		return
	var q := 1.0 + t * t
	var c := (1.0 - t * t) / q
	var s := 2.0 * t / q
	var x := state.beam_dx * c - state.beam_dy * s
	var y := state.beam_dx * s + state.beam_dy * c
	var n := sqrt(x * x + y * y)
	state.beam_dx = x / n
	state.beam_dy = y / n
	if b.pattern == "sweep" and b.sweep_edges.size() == 2:
		var edge: Array = b.sweep_edges[1] if t > 0.0 else b.sweep_edges[0]
		var cross: float = edge[0] * state.beam_dy - edge[1] * state.beam_dx
		if (t > 0.0 and cross > 0.0) or (t < 0.0 and cross < 0.0):
			state.beam_sign = -state.beam_sign


## Every beam's direction as [x, y] pairs: the base direction rotated by i x 360° / count.
func _beam_dirs() -> Array:
	return _dirs_of(state.beam_dx, state.beam_dy, beam_count())


## Directions of `count` (1, 2, 4 or 8) evenly spaced beams from (x, y), counter-clockwise,
## without trig: negation, the perpendiculars (-y, x) / (y, -x) and the 45° rotation with
## c = s = sqrt(0.5).
static func _dirs_of(x: float, y: float, count: int) -> Array:
	if count == 1:
		return [[x, y]]
	if count == 2:
		return [[x, y], [-x, -y]]
	if count == 4:
		return [[x, y], [-y, x], [-x, -y], [y, -x]]
	var r := sqrt(0.5)
	var hx := (x - y) * r
	var hy := (x + y) * r
	return [[x, y], [hx, hy], [-y, x], [-hy, hx], [-x, -y], [-hx, -hy], [y, -x], [hy, -hx]]


## Whether the point (px, py) (cell units, the frame of SimTower.centre) is inside any beam
## now (LT-26 §1.1), with the flare's width when one burns. False by day.
func _is_lit(px: float, py: float) -> bool:
	return _beam_on() and _lit_by(_beam_dirs(), _beam_half_width(), px, py)


## LT-26 §1.1 lit test against the lighthouse cell centre L, v = p - L: |v|² <= reach²,
## v·d > 0 and cross(v, d)² <= k² (v·d)² for some beam d. Overlaps do not stack.
func _lit_by(dirs: Array, k: float, px: float, py: float) -> bool:
	var lh := config.map.lighthouse
	var vx := px - (lh.x + 0.5)
	var vy := py - (lh.y + 0.5)
	var reach := config.economy.beam.reach_cells
	if vx * vx + vy * vy > reach * reach:
		return false
	for d: Array in dirs:
		var dot: float = vx * d[0] + vy * d[1]
		if dot <= 0.0:
			continue
		var cross: float = vx * d[1] - vy * d[0]
		if cross * cross <= k * k * dot * dot:
			return true
	return false


## Slot 2, after the madness buff (LT-30 §1.1): while a flare burns, every lit live enemy
## (fakes alike) gets speed_mult x flare.enemy_speed_mult this tick. The passive beam never
## slows.
func _apply_flare_slow() -> void:
	if not _flaring():
		return
	var m := config.economy.flare.enemy_speed_mult
	for e in state.enemies:
		if e.is_live() and e.lit:
			e.speed_mult *= m


## Slot 2, last: the flare burns one tick less; the cooldown runs by day too.
func _count_down_flare() -> void:
	if state.flare_ticks_left > 0:
		state.flare_ticks_left -= 1
	if state.flare_cooldown_ticks > 0:
		state.flare_cooldown_ticks -= 1


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
			var t_slow: float = s.effects.get("slow", 0.0)
			var t_mult: float = s.effects.get("damage_taken_multiplier", 1.0)
			if t.lit and t.def.kind == "occult":
				# LT-30 §2: a lit occult aura works at beam.occult.power_mult strength.
				var pm := config.economy.beam.occult_power_mult
				t_slow *= pm
				t_mult = 1.0 + (t_mult - 1.0) * pm
			slow = maxf(slow, t_slow)
			mult = maxf(mult, t_mult)
			# Corrupted Seal's strip_armor is not wired yet: it is in TowerDef.Level.PENDING.
		if inside:
			e.speed_mult *= 1.0 - slow
			e.damage_taken_mult *= mult


## Slot 2, after _apply_auras (LT-23 §3): in MADNESS every live enemy, real and fake alike,
## gets speed_mult x madness.enemy_speed_multiplier and damage_taken_mult x
## madness.enemy_damage_taken_multiplier for this tick (on top of any aura), except those
## _madness_buff_blocked holds back. Reset with the other modifiers in slot 1, so it ends
## the tick after MADNESS does.
func _apply_madness_buff() -> void:
	if state.sanity_state != SimState.SanityState.MADNESS:
		return
	var m := config.sanity.madness
	if m.enemy_speed_multiplier == 1.0 and m.enemy_damage_taken_multiplier == 1.0:
		return
	for e in state.enemies:
		if not e.is_live() or _madness_buff_blocked(e):
			continue
		e.speed_mult *= m.enemy_speed_multiplier
		e.damage_taken_mult *= m.enemy_damage_taken_multiplier


## LT-30 (LT-26 D4): true when `e` must not get the madness buff: lit by the lighthouse beam
## this tick (real and fake alike) and beam.enemy.cancel_madness_buff is on.
func _madness_buff_blocked(e: SimEnemy) -> bool:
	return config.economy.beam.cancel_madness_buff and e.lit


## Slot 5 (§3.3): every tower in id order counts down its cooldown and, when ready, fires
## at the live enemy (fakes too) in range its target_priority picks (_pick_target; default
## nearest the end of its route; ties: lower id). Instant hit.
## A level with a `pierce` effect fires a line shot (_line_hits) instead of a single shot;
## one with an `aoe_radius` effect casts a blast centred on that target, hitting every live
## enemy (fakes too) within aoe_radius of it (Necronomicon). No enemy in range: no shot, no
## cast; the tower stays ready. A mundane shot may miss (LT-12 §4, _roll_miss): cooldown
## spent, no damage, SHOT {miss: true, hits: []}, `to` = aim point. Casts cost no sanity
## (LT-23: occult towers reserve the cap instead).
## In MADNESS a madness_affected level shoots astray (LT-13): SHOT {astray: true}, centre
## rolled by shot_split on MADNESS, damage x madness.damage_multiplier.
func _fire_towers() -> void:
	for t in state.towers:
		if t.cooldown_ticks > 0:
			t.cooldown_ticks -= 1
			if t.cooldown_ticks > 0:
				continue
		var s := t.stats()
		if s.damage <= 0.0:
			continue
		var in_range := enemies_in_range(t.cell, s.range_cells)
		var target := _pick_target(t, in_range)
		if target == null:
			continue
		# LT-13: a madness_affected tower in MADNESS deals x damage_multiplier and its shot
		# goes astray (shot_split on MADNESS): centred on a random real / fake in range, or
		# on nothing. An empty shot keeps the usual target as its aim point.
		var damage := s.damage
		var beam := config.economy.beam
		var lit_mundane := t.lit and t.def.kind == "mundane"
		if t.lit and t.def.kind == "occult":
			damage *= beam.occult_power_mult  # LT-30 §2, before the madness x2
		var astray := ""
		if s.madness_affected and state.sanity_state == SimState.SanityState.MADNESS:
			damage *= config.sanity.madness.damage_multiplier
			astray = _roll_astray()
			var pool: Array[SimEnemy] = []
			if astray == "real":
				for e in in_range:
					if not e.is_fake:
						pool.append(e)
			elif astray == "fake":
				pool = live_fakes_in_range(t.cell, s.range_cells)
			if pool.is_empty():
				astray = "empty"
			else:
				target = pool[rng(SimRng.Stream.MADNESS).randi_range(0, pool.size() - 1)]
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
		# LT-30: a lit mundane tower with ignore_miss never misses (no COMBAT draw).
		var miss := t.def.kind == "mundane" and not (lit_mundane and beam.mundane_ignore_miss) \
			and _roll_miss()
		if miss or astray == "empty":
			hits = []
		var ids: Array[int] = []
		for e in hits:
			ids.append(e.id)
		var shot := {"def": t.def.id, "target": target.id, "hits": ids, "to": to, "miss": miss}
		if astray != "":
			# A bool, not the outcome: a shot centred on a fake must look like any other
			# (LT-12 §1). An empty one is told by its empty "hits".
			shot["astray"] = true
		_emit(SimEvent.Type.SHOT, t.id, shot)
		for e in hits:
			apply_damage(e.id, damage, t.def.id)
		var interval := s.fire_interval
		if lit_mundane:
			interval *= beam.mundane_fire_interval_mult  # LT-30: decided at the shot
		t.cooldown_ticks = maxi(1, SimTime.ticks(interval))


## The target `t` fires at among `candidates` (id order) by its target_priority (LT-31):
## "first" -> _first_along_route, "strongest" -> highest current hp, "fastest" -> highest
## units moved this tick (base_units_per_tick x speed_mult, as _move rounds it, so auras'
## slow counts). Every tie -> lower id. Null if empty.
func _pick_target(t: SimTower, candidates: Array[SimEnemy]) -> SimEnemy:
	match t.target_priority:
		"strongest":
			return _best_by(candidates, func(e: SimEnemy) -> float: return e.hp)
		"fastest":
			return _best_by(candidates, func(e: SimEnemy) -> float:
				return float(roundi(e.base_units_per_tick * e.speed_mult)))
	return _first_along_route(candidates)


## The candidate with the highest `key`; the first (lower id) on a tie. Null if empty.
func _best_by(candidates: Array[SimEnemy], key: Callable) -> SimEnemy:
	var best: SimEnemy = null
	var best_key := 0.0
	for e in candidates:
		var k: float = key.call(e)
		if best == null or k > best_key:
			best = e
			best_key = k
	return best


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


## LT-13 shot_split: one MADNESS roll per astray shot -> "real" | "fake" | "empty".
func _roll_astray() -> String:
	var m := config.sanity.madness
	var r := rng(SimRng.Stream.MADNESS).randf()
	if r < m.shot_real:
		return "real"
	if r < m.shot_real + m.shot_fake:
		return "fake"
	return "empty"


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
