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
## SimEnemy.status timers that only count down to 0 and go (LT-29 pull, LT-51 banish).
const IMMUNITY_KEYS: PackedStringArray = ["pull_immune_ticks", "banish_immune_ticks"]
## LT-52 (LT-46 §2.2): an allied unit within this many cells of an enemy it chases holds it.
const ALLY_CONTACT := 0.4

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
## LT-63: pack members not entered yet, queue order: [due_tick, EnemyDef, is_fake, pack_of].
## Sim only (fakes are queued too, LT-12 §1); slot 7 lets them in (_release_pack_members).
var _pack_queue: Array = []


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
	# then Elder Sign auras (LT-11; Corrupted Seal's armor strip, LT-29), the madness buff
	# (LT-23 §3) and the flare's slow; then enemy status timers (LT-29 P6: bleed pulses see
	# this tick's auras and buff; pull immunity counts down); later slows/stuns add theirs
	# here. The flare timers count down last.
	_update_beam()
	_apply_auras()
	_apply_madness_buff()
	_apply_flare_slow()
	_tick_statuses()
	# LT-52 (P10): allies past their lifetime are gone; the rest hold their enemy
	# (speed_mult 0, after every other speed modifier).
	_tick_allies()
	_count_down_flare()
	# 3. Movement: enemies, then allies chase them (LT-52; contact starts a hold).
	_move()
	_move_allies()
	# 4. Leaks.
	_leak()
	# 5. Towers fire / damage: single and line shots (LT-6), AoE casts (LT-11, no sanity
	# cost since LT-23); madness damage and astray shots (LT-13). Kills drop relic tokens
	# (LT-27 §1.3).
	_fire_towers()
	# LT-52 (P10): each holding ally and its enemy trade damage, in ally id order.
	_ally_combat()
	# 5b. Fused charges (LT-47 P2) whose fuse ran out explode, in throw order; a charge
	# thrown this tick waits at least one tick.
	_settle_blasts()
	# 6. Sanity (LT-10): horror drain. Kill regen is paid in slot 5 (_on_enemy_killed),
	# between-waves regen in slot 8 (wave system), each through _add_sanity.
	_horror_drain()
	# 6b. Relic tokens (LT-27 §1.3): ghosts vanish, real tokens are credited on arrival.
	_settle_tokens()
	# 7. Spawning: queued pack members due now (LT-63), then the spawner, then fakes (LT-12)
	# from the spawner's candidates.
	_release_pack_members()
	if _spawner != null:
		_spawner.tick(self)
		_hallucinations.tick(self, _spawner)
	# 8. Remove dead and leaked enemies and gone allies (LT-52); then the wave system settles
	# a cleared wave (its bonus is paid before the outcome check, so the last wave's bonus
	# lands too).
	_compact()
	if _spawner != null:
		_spawner.end_tick(self)
	# 9. Outcome.
	_check_outcome()


## Spawns `def_id` at the start of its route; a `pack` enemy spawns min..max of them
## (rolled on SPAWN, or on SANITY for a fake so hallucinations never change real pack
## sizes, LT-12 §2). LT-63: only the first member enters now; member k (1..count-1) is
## queued and enters at the start of the route in slot 7 of tick now + k x
## ticks(pack.spacing_s), before the spawner's spawns of that tick, so members never stack
## on one spot. Every member's pack_of is the first member's id. Returns the first new id,
## or 0 if `def_id` is unknown or the outcome is set (then nothing changes and no event is
## emitted).
func spawn_enemy(def_id: String, is_fake := false) -> int:
	if state.outcome != SimState.Outcome.NONE:
		return 0
	if not config.enemies.has(def_id):
		push_error("Simulation.spawn_enemy: unknown enemy \"%s\"" % def_id)
		return 0
	var def: EnemyDef = config.enemies[def_id]
	if not def.traits.has("pack"):
		return _enter(def, is_fake, 0)
	var pack: Dictionary = def.traits["pack"]
	var stream := SimRng.Stream.SANITY if is_fake else SimRng.Stream.SPAWN
	var count := rng(stream).randi_range(int(pack["min"]), int(pack["max"]))
	var spacing := SimTime.ticks(pack["spacing_s"])
	var first_id := _enter(def, is_fake, state.next_id)
	for k in range(1, count):
		_pack_queue.append([state.tick + k * spacing, def, is_fake, first_id])
	return first_id


## LT-63: true while a real pack member is queued and not entered yet (a wave is not
## cleared and the run is not won before it has entered).
func has_queued_real_members() -> bool:
	for q: Array in _pack_queue:
		if not q[2]:
			return true
	return false


## Slot 7 (LT-63): every queued pack member whose due tick has come enters, queue order.
func _release_pack_members() -> void:
	if _pack_queue.is_empty():
		return
	var left: Array = []
	for q: Array in _pack_queue:
		if int(q[0]) > state.tick:
			left.append(q)
		else:
			_enter(q[1], q[2], q[3])
	_pack_queue = left


## One enemy of `def` enters at the start of its route on this tick, with a new id and
## SPAWNED {def}; returns that id.
func _enter(def: EnemyDef, is_fake: bool, pack_of: int) -> int:
	var e := SimEnemy.new()
	e.id = state.next_id
	state.next_id += 1
	e.def = def
	e.hp = def.hp
	e.max_hp = def.hp
	e.is_fake = is_fake
	e.pack_of = pack_of
	e.spawn_tick = state.tick
	e.base_units_per_tick = SimTime.units_per_tick(def.speed)
	# Flyers start at S too (owner decision, §7 Q3) and fly straight to L.
	e.route = SimRoute.straight(state.map.spawn, state.map.lighthouse) if def.flying \
		else _ground_route
	state.enemies.append(e)
	_emit(SimEvent.Type.SPAWNED, e.id, {"def": def.id})
	return e.id


## The one armor rule for every damage source (§3.4). Returns the hp actually removed
## (capped at the remaining hp, so overkill is not counted); 0 for an unknown, dead or
## leaked enemy, or once the outcome is set (then nothing changes and no event is emitted).
## A killed enemy emits DIED and is removed at the end of the current/next tick.
## `ignore_armor` (LT-48 P7): the hit skips armor; damage_taken_mult still applies.
func apply_damage(enemy_id: int, amount: float, source: String, ignore_armor := false) -> float:
	if state.outcome != SimState.Outcome.NONE:
		return 0.0
	var e := enemy_by_id(enemy_id)
	if e == null or not e.is_live():
		return 0.0
	# LT-48 (P7): an ignore_armor hit skips the whole armor (base and bonus).
	var armor := 0.0 if ignore_armor else maxf(0.0, e.def.armor + e.armor_bonus)
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
	_dismiss_allies(t.id)
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


## Whether `t` picks a target when it fires (LT-31): its current level acts (deals damage
## or banishes, LT-51 P9). False for an aura tower (Elder Sign), which has no target
## priority to switch, and (LT-52) for a Summoning Circle: it acts, but its units pick the
## nearest enemy themselves, so a priority would change nothing.
func has_targeting(t: SimTower) -> bool:
	var s := t.stats()
	return s.acts() and not s.is_summon()


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
	t.locked_id = -1  # LT-50: a beam re-picks by the new mode at its next shot
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


## Player command (LT-30 §1.1, LT-57 radial): for flare.seconds everything within
## flare_radius() cells of the lighthouse is lit (beams keep turning and keep their width),
## and every lit enemy moves at x enemy_speed_mult; the cooldown runs from now. Emits FLARE_FIRED {ticks, cooldown}
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


## LT-52 (LT-46 P10): places an allied unit at `at` (cell units; also its leash centre) and
## emits ALLY_SUMMONED. `tower` is the summoning tower's id (0 = none), `source` the kill
## credit; `dps` is dealt to the held enemy (armor: Simulation._ally_combat), `speed` in
## cells/s, `flying` lets it engage flyers, `leash` (cells from `at`) bounds whom it
## engages; `lifetime_ticks` <= 0 = no lifetime. Returns the new id, or 0 if the outcome
## is set or `hp` <= 0 (then nothing changes and no event is emitted).
func spawn_ally(tower: int, source: String, at: Vector2, hp: float, dps: float, speed: float,
		flying: bool, lifetime_ticks: int, leash: float) -> int:
	if state.outcome != SimState.Outcome.NONE or hp <= 0.0:
		return 0
	var a := SimAlly.new()
	a.id = state.next_id
	state.next_id += 1
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
	a.summon_tick = state.tick
	a.expires_tick = state.tick + lifetime_ticks if lifetime_ticks > 0 else 0
	state.allies.append(a)
	_emit(SimEvent.Type.ALLY_SUMMONED, a.id, {"tower": tower, "source": source, "at": at,
		"hp": hp, "flying": flying, "expires_tick": a.expires_tick})
	return a.id


## The ally with this id, or null (also null once removed).
func ally_by_id(id: int) -> SimAlly:
	for a in state.allies:
		if a.id == id:
			return a
	return null


## Live allies of tower `tower_id`, id order (a summoner counts them against its maximum).
func allies_of(tower_id: int) -> Array[SimAlly]:
	var out: Array[SimAlly] = []
	for a in state.allies:
		if a.is_live() and a.tower == tower_id:
			out.append(a)
	return out


## Position in cell units, interpolated between the last two ticks by `alpha` (0..1).
func ally_position(a: SimAlly, alpha: float) -> Vector2:
	return a.prev_pos.lerp(a.pos, alpha)


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


## LT-57: the flare's lit radius in cells at the current lighthouse level
## (flare.radius_cells[lighthouse_level]); 0 without a flare block.
func flare_radius() -> float:
	var flare := config.economy.flare
	if flare == null or state.lighthouse_level >= flare.radius_cells.size():
		return 0.0
	return flare.radius_cells[state.lighthouse_level]


## LT-57: whether the point p (cell units, the frame of SimTower.centre) lies within
## flare_radius() of the lighthouse cell centre, boundary inclusive. Independent of whether
## a flare burns (the bot asks before firing).
func in_flare_radius(p: Vector2) -> bool:
	var lh := config.map.lighthouse
	var vx := p.x - (lh.x + 0.5)
	var vy := p.y - (lh.y + 0.5)
	var r := flare_radius()
	return vx * vx + vy * vy <= r * r


## Lit now by a beam (dirs, half-width k) or, while a flare burns, by its circle (LT-57).
func _lit_now(dirs: Array, k: float, px: float, py: float) -> bool:
	return _lit_by(dirs, k, px, py) or (_flaring() and in_flare_radius(Vector2(px, py)))


## Slot 2, first (LT-30 §3.1): saves prev_beam_*, turns the base direction (night only; a
## flare no longer holds it, LT-57), then sets `lit` (in a beam or the flare circle)
## of every tower (centre; TOWER_LIT {lit} on a flip, id order) and of every live enemy
## (route position at the start of the tick, as auras). By day every flag is false.
func _update_beam() -> void:
	state.prev_beam_dx = state.beam_dx
	state.prev_beam_dy = state.beam_dy
	var on := _beam_on()
	if on:
		_turn_beam()
	var dirs := _beam_dirs() if on else []
	var k := config.economy.beam.half_width_ratio
	for t in state.towers:
		var c := t.centre()
		var lit := on and _lit_now(dirs, k, c.x, c.y)
		if lit != t.lit:
			t.lit = lit
			_emit(SimEvent.Type.TOWER_LIT, t.id, {"lit": lit})
	if not on:
		return
	for e in state.enemies:
		if not e.is_live():
			continue
		var p := e.route.position_at(e.distance)
		e.lit = _lit_now(dirs, k, p.x, p.y)


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
## now (LT-26 §1.1) or within the flare circle while one burns (LT-57). False by day.
func _is_lit(px: float, py: float) -> bool:
	return _beam_on() and _lit_now(_beam_dirs(), config.economy.beam.half_width_ratio, px, py)


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
## (fakes alike; lit includes the flare circle, LT-57) gets speed_mult x
## flare.enemy_speed_mult this tick. The passive beam never
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
## support level (damage 0) with a `slow`, `damage_taken_multiplier` and/or `strip_armor`
## (LT-29 §1.5: armor_bonus -= strip, so apply_damage sees armor - strip) effect; its aura
## radius is the level's range, measured like enemies_in_range from the enemy's position at
## the start of the tick (before movement). Every live enemy inside (fakes too) gets
## speed_mult x (1 - slow) and damage_taken_mult x multiplier. Auras do not stack: inside
## several signs an enemy gets each modifier once, the strongest among the covering signs.
## The speed modifier scales this tick's movement (slot 3); the damage modifier applies to
## every hit this tick (slot 5), after armor (apply_damage).
## LT-49 (LT-46 P8): a `reveal_fakes` aura (Searchlight) also sets `revealed` on every live
## fake inside, for good; _candidates then drops it, so no tower targets it again. A lit
## mundane aura is unchanged (LT-30 modifiers apply to firing and to occult auras only).
func _apply_auras() -> void:
	var auras: Array[SimTower] = []
	for t in state.towers:
		var s := t.stats()
		if not s.acts() and (s.effects.has("slow") or s.effects.has("damage_taken_multiplier")
				or s.effects.has("strip_armor") or s.effects.get("reveal_fakes", 0.0) > 0.0):
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
		var strip := 0.0
		var reveal := false
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
			var t_strip: float = s.effects.get("strip_armor", 0.0)
			if t.lit and t.def.kind == "occult":
				# LT-30 §2: a lit occult aura works at beam.occult.power_mult strength
				# (LT-29 §2: the armor strip too).
				var pm := config.economy.beam.occult_power_mult
				t_slow *= pm
				t_mult = 1.0 + (t_mult - 1.0) * pm
				t_strip *= pm
			slow = maxf(slow, t_slow)
			mult = maxf(mult, t_mult)
			strip = maxf(strip, t_strip)
			reveal = reveal or s.effects.get("reveal_fakes", 0.0) > 0.0
		if inside:
			e.speed_mult *= 1.0 - slow
			e.damage_taken_mult *= mult
			e.armor_bonus -= strip
			if reveal and e.is_fake:
				e.revealed = true


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
## LT-29: a `burst_targets` level (Gangsters) fires each shot at the next of the top N
## ranked targets (round robin, SimTower.burst_index). A shot that hits and whose level has
## `crit_chance` rolls once on CRIT after the miss roll (lit towers skip the miss roll but
## still crit): damage x crit_multiplier on every hit, before armor; SHOT {crit: true}.
## After the damage, _on_hit_effects applies bleed, the on-hit fake reveal and the chain pull.
## LT-50: a `sanity_scaling` level (Resonator, TowerDef.Level.is_beam) keeps its target while
## it stays a candidate (_beam_target) and deals damage x sanity_factor (current sanity on
## the full bar, §7 Q2) before the lit and madness multipliers; SHOT {beam, sanity_factor}.
func _fire_towers() -> void:
	for t in state.towers:
		if t.cooldown_ticks > 0:
			t.cooldown_ticks -= 1
			if t.cooldown_ticks > 0:
				continue
		var s := t.stats()
		if not s.acts():
			continue
		if s.is_banish():
			_cast_banish(t, s)  # LT-51: its own cast; no miss, crit or shot shape
			continue
		if s.is_summon():
			_summon(t, s)  # LT-52: allied units do the damage (slot 5 _ally_combat)
			continue
		var in_range := _candidates(t, s)
		var target: SimEnemy = null
		var burst := int(s.effects.get("burst_targets", 0.0))
		if burst > 0:
			# LT-29 §1.2: round robin over the top `burst` by target_priority; a miss moves on
			# too. The ranked set may shrink between shots: nothing is locked.
			var ranked := _ranked_targets(t, in_range, burst)
			if not ranked.is_empty():
				var m := ranked.size()
				target = ranked[t.burst_index % m]
				t.burst_index = (t.burst_index % m + 1) % m
		elif s.is_beam():
			target = _beam_target(t, in_range)
		else:
			target = _pick_target(t, in_range)
		if target == null:
			continue
		# LT-13: a madness_affected tower in MADNESS deals x damage_multiplier and its shot
		# goes astray (shot_split on MADNESS): centred on a random real / fake in range, or
		# on nothing. An empty shot keeps the usual target as its aim point.
		# LT-50 (§7 Q2): a sanity_scaling level x 1 + k x (1 - sanity / max) on the full bar,
		# before the lit x0.7 and the madness x2.
		var factor := s.sanity_factor(state.sanity, config.sanity.max_sanity)
		var damage := s.damage * factor
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
				pool = _outside_dead_zone(t, s,
					_ground_filter(t, live_fakes_in_range(t.cell, s.range_cells)))
			if pool.is_empty():
				astray = "empty"
			else:
				target = pool[rng(SimRng.Stream.MADNESS).randi_range(0, pool.size() - 1)]
		var pierce: float = s.effects.get("pierce", 0.0)
		var aoe: float = s.effects.get("aoe_radius", 0.0)
		var fuse_ticks := 0
		if s.effects.get("fuse_seconds", 0.0) > 0.0:
			fuse_ticks = maxi(1, SimTime.ticks(float(s.effects["fuse_seconds"])))
		var hits: Array[SimEnemy] = [target]
		var to := target.route.position_at(target.distance)
		if fuse_ticks > 0:
			# LT-47 (Q5 "lead"): thrown where the target will be after the fuse at its speed
			# this tick; who is hit is decided when it explodes (_settle_blasts).
			to = _lead_point(target, fuse_ticks)
			hits = []
		elif pierce > 0.0:
			to = _line_end(t.centre(), to, s.range_cells)
			hits = _ground_filter(t, _line_hits(t.centre(), to, pierce * 0.5, target))
		elif aoe > 0.0:
			hits = _ground_filter(t, enemies_near(to, aoe))
		# LT-12 §4: a mundane shot may miss as a whole (Q3: occult towers never miss).
		# LT-30: a lit mundane tower with ignore_miss never misses (no COMBAT draw).
		var miss := t.def.kind == "mundane" and not (lit_mundane and beam.mundane_ignore_miss) \
			and _roll_miss()
		var dud := miss or astray == "empty"
		if dud:
			hits = []
		# LT-29 §1.1: one CRIT roll per shot that hits, after the miss roll; all before armor
		# (power_mult x madness x crit), so apply_damage subtracts armor from the crit. A
		# fused charge that is not a dud rolls at the throw.
		var lands := (not dud) if fuse_ticks > 0 else (not hits.is_empty())
		var crit := lands and _roll_crit(float(s.effects.get("crit_chance", 0.0)))
		if crit:
			damage *= float(s.effects.get("crit_multiplier", 1.0))
		var ids: Array[int] = []
		for e in hits:
			ids.append(e.id)
		var shot := {"def": t.def.id, "target": target.id, "hits": ids, "to": to, "miss": miss}
		if astray != "":
			# A bool, not the outcome: a shot centred on a fake must look like any other
			# (LT-12 §1). An empty one is told by its empty "hits".
			shot["astray"] = true
		if crit:
			shot["crit"] = true
		if s.is_beam():
			shot["beam"] = true  # LT-50: the board holds one beam per tower
			shot["sanity_factor"] = factor
		if fuse_ticks > 0:
			# LT-47: a dud (a Fraying miss) is thrown but never explodes; blast 0.
			shot["fuse"] = true
			shot["detonate_tick"] = state.tick + fuse_ticks
			shot["radius"] = aoe
			shot["blast"] = 0 if dud else _queue_blast(t, s, to, damage, fuse_ticks)
		_emit(SimEvent.Type.SHOT, t.id, shot)
		var no_armor: bool = s.effects.get("ignore_armor", 0.0) > 0.0
		for e in hits:
			apply_damage(e.id, damage, t.def.id, no_armor)
		if fuse_ticks == 0:
			_on_hit_effects(t, s, target, hits, shot)
		var interval := s.fire_interval
		if lit_mundane:
			interval *= beam.mundane_fire_interval_mult  # LT-30: decided at the shot
		t.cooldown_ticks = maxi(1, SimTime.ticks(interval))


## LT-51 (§2.2, Q4): a Silver Key cast. Picks (by target_priority) up to banish_targets of
## the tower's candidates that may be banished (_banishable), moves each back banish_cells
## along its own route (P5 _push_back, the Chain pull's rewind; x occult_power_mult when the
## tower is lit) and gives it banish_immune_seconds of banish immunity (its own status key:
## pull immunity does not block a banish, nor the reverse). A level with damage (Corrupted)
## then hits each one (armor applies; x occult_power_mult lit, x the madness multiplier).
## No candidate: no cast and no cooldown, the gate stays ready. In MADNESS a
## madness_affected gate goes astray (LT-13, one roll per cast): its picks are drawn at
## random from the banishable reals in range, or from the banishable fakes in range
## (revealed ones too), or the cast moves nothing ("empty") and still spends the cooldown.
## One SHOT per moved enemy {banish, target, hits [id], from, to: its position before and
## after}, before the damage (SHOT -> DIED).
func _cast_banish(t: SimTower, s: TowerDef.Level) -> void:
	var n := s.banish_targets()
	var picks := _ranked_targets(t, _banishable(s, _candidates(t, s)), n)
	if picks.is_empty():
		return
	var beam := config.economy.beam
	var power := beam.occult_power_mult if t.lit and t.def.kind == "occult" else 1.0
	var damage := s.damage * power
	var astray := ""
	if s.madness_affected and state.sanity_state == SimState.SanityState.MADNESS:
		damage *= config.sanity.madness.damage_multiplier
		astray = _roll_astray()
		var pool: Array[SimEnemy] = []
		if astray == "real":
			for e in _candidates(t, s):
				if not e.is_fake:
					pool.append(e)
		elif astray == "fake":
			pool = _ground_filter(t, live_fakes_in_range(t.cell, s.range_cells))
		pool = _banishable(s, pool)
		picks = []
		var stream := rng(SimRng.Stream.MADNESS)
		while picks.size() < n and not pool.is_empty():
			picks.append(pool.pop_at(stream.randi_range(0, pool.size() - 1)))
	var cells: float = s.effects.get("banish_cells", 0.0) * power
	var immune := SimTime.ticks(float(s.effects.get("banish_immune_seconds", 0.0)))
	for e in picks:
		var from := e.route.position_at(e.distance)
		_push_back(e, cells)
		if immune > 0:
			e.status["banish_immune_ticks"] = immune
		var shot := {"def": t.def.id, "target": e.id, "hits": [e.id], "banish": true,
			"from": from, "to": e.route.position_at(e.distance), "miss": false}
		if astray != "":
			shot["astray"] = true
		_emit(SimEvent.Type.SHOT, t.id, shot)
	if damage > 0.0:
		for e in picks:
			apply_damage(e.id, damage, t.def.id)
	t.cooldown_ticks = maxi(1, SimTime.ticks(s.fire_interval))


## LT-52 (§2.2): a Summoning Circle with fewer than summon_max live units summons one at
## its centre (spawn_ally: leash = range + 1, lifetime summon_lifetime) and spends the
## cooldown. At its maximum it does not summon and stays ready, so a unit gone frees a
## slot at once. A circle lit at summon time gives the unit summon_dps x occult_power_mult
## for its whole life (§3 "lit at summon time"); madness is applied live by _ally_combat.
## No miss, crit or astray (a unit bites what it holds).
func _summon(t: SimTower, s: TowerDef.Level) -> void:
	if allies_of(t.id).size() >= s.summon_max():
		return
	var dps: float = s.effects.get("summon_dps", 0.0)
	if t.lit and t.def.kind == "occult":
		dps *= config.economy.beam.occult_power_mult
	var id := spawn_ally(t.id, t.def.id, t.centre(), s.effects.get("summon_hp", 0.0), dps,
		s.effects.get("summon_speed", 0.0), s.summon_flying(),
		SimTime.ticks(float(s.effects.get("summon_lifetime", 0.0))), s.range_cells + 1.0)
	if id != 0:
		t.cooldown_ticks = maxi(1, SimTime.ticks(s.fire_interval))


## LT-51 (Q4 "HP cap per level"): those of `enemies` a gate with stats `s` may banish:
## max_hp <= banish_max_hp (Dagon's is above every cap) and no banish immunity.
func _banishable(s: TowerDef.Level, enemies: Array[SimEnemy]) -> Array[SimEnemy]:
	var cap: float = s.effects.get("banish_max_hp", 0.0)
	var out: Array[SimEnemy] = []
	for e in enemies:
		if e.max_hp <= cap and int(e.status.get("banish_immune_ticks", 0)) <= 0:
			out.append(e)
	return out


## LT-46 P1: the enemies `t` may fire at with stats `s`: live ones in range (fakes too,
## except revealed ones, LT-49 P8), without flyers for a ground tower (P3) and without those
## inside `min_range` (P4). Id order. A revealed fake is still hit by blasts, line shots and
## madness astray shots (those pick from live_fakes_in_range, LT-13): it is only never a
## chosen target.
func _candidates(t: SimTower, s: TowerDef.Level) -> Array[SimEnemy]:
	var out: Array[SimEnemy] = []
	for e in enemies_in_range(t.cell, s.range_cells):
		if not e.revealed:
			out.append(e)
	return _outside_dead_zone(t, s, _ground_filter(t, out))


## LT-50 (P14): a beam keeps `t.locked_id` while that enemy is still among `candidates`
## (live, in range, not a revealed fake); otherwise it locks on _pick_target's choice (or
## clears the lock when there is none).
func _beam_target(t: SimTower, candidates: Array[SimEnemy]) -> SimEnemy:
	if t.locked_id >= 0:
		for e in candidates:
			if e.id == t.locked_id:
				return e
	var target := _pick_target(t, candidates)
	t.locked_id = target.id if target != null else -1
	return target


## LT-48 (P4): `enemies` without those whose cell-centre distance from `t` is strictly less
## than `s.min_range`; `enemies` itself when the level has no dead zone.
func _outside_dead_zone(t: SimTower, s: TowerDef.Level,
		enemies: Array[SimEnemy]) -> Array[SimEnemy]:
	if s.min_range <= 0.0:
		return enemies
	var c := t.centre()
	var r2 := s.min_range * s.min_range
	var out: Array[SimEnemy] = []
	for e in enemies:
		var p := e.route.position_at(e.distance)
		var dx := float(p.x) - float(c.x)
		var dy := float(p.y) - float(c.y)
		if dx * dx + dy * dy >= r2:
			out.append(e)
	return out


## `enemies` without flyers if `t` is ground only (LT-47 P3), else `enemies` itself.
func _ground_filter(t: SimTower, enemies: Array[SimEnemy]) -> Array[SimEnemy]:
	return _ground_only(enemies) if t.def.ground_only() else enemies


static func _ground_only(enemies: Array[SimEnemy]) -> Array[SimEnemy]:
	var out: Array[SimEnemy] = []
	for e in enemies:
		if not e.def.flying:
			out.append(e)
	return out


## LT-47 (Q5): where `e` will be after `ticks` more moves at this tick's speed (as _move
## rounds it), clamped to its route.
func _lead_point(e: SimEnemy, ticks: int) -> Vector2:
	var step_units := roundi(e.base_units_per_tick * e.speed_mult)
	return e.route.position_at(clampi(e.distance + step_units * ticks, 0, e.route.length))


## LT-47 (P2): queues a charge from `t` at `at` exploding `fuse_ticks` from now; its id.
func _queue_blast(t: SimTower, s: TowerDef.Level, at: Vector2, damage: float,
		fuse_ticks: int) -> int:
	var b := SimBlast.new()
	b.id = state.next_blast_id
	state.next_blast_id += 1
	b.tower = t.id
	b.source = t.def.id
	b.at = at
	b.throw_tick = state.tick
	b.detonate_tick = state.tick + fuse_ticks
	b.damage = damage
	b.radius = float(s.effects.get("aoe_radius", 0.0))
	b.ground_only = t.def.ground_only()
	b.effects = s.effects
	state.blasts.append(b)
	return b.id


## Slot 5b (LT-47 P2): every charge whose detonate_tick has come explodes, in id order:
## BLAST {tower, def, at, radius, hits}, then its damage to each live enemy (fakes too;
## flyers only if not ground_only) within `radius` of `at` now, credited to its def id, then
## its on-hit bleed. Enemies slowed, sped up or pushed back since the throw may be outside.
func _settle_blasts() -> void:
	if state.blasts.is_empty():
		return
	var left: Array[SimBlast] = []
	for b in state.blasts:
		if b.detonate_tick > state.tick:
			left.append(b)
			continue
		var hits := enemies_near(b.at, b.radius)
		if b.ground_only:
			hits = _ground_only(hits)
		var ids: Array[int] = []
		for e in hits:
			ids.append(e.id)
		_emit(SimEvent.Type.BLAST, b.id, {"tower": b.tower, "def": b.source, "at": b.at,
			"radius": b.radius, "hits": ids})
		var no_armor: bool = b.effects.get("ignore_armor", 0.0) > 0.0
		for e in hits:
			apply_damage(e.id, b.damage, b.source, no_armor)
		_apply_bleed_hits(hits, b.effects, b.source)
	state.blasts = left


## The target `t` fires at among `candidates` by its target_priority: the top of
## _ranked_targets. Null if empty.
func _pick_target(t: SimTower, candidates: Array[SimEnemy]) -> SimEnemy:
	var ranked := _ranked_targets(t, candidates, 1)
	return null if ranked.is_empty() else ranked[0]


## Up to `n` of `candidates`, best first, by t.target_priority (LT-31): "first" = least
## route distance left to the lighthouse, "strongest" = highest current hp, "fastest" =
## highest units moved this tick (base_units_per_tick x speed_mult, as _move rounds it, so
## auras' slow counts). Every tie -> lower id. One ranking rule for single shots and
## bursts (LT-29 P12).
func _ranked_targets(t: SimTower, candidates: Array[SimEnemy], n: int) -> Array[SimEnemy]:
	var out: Array[SimEnemy] = []
	if n <= 0 or candidates.is_empty():
		return out
	var mode := t.target_priority
	if n == 1:
		# One pick: a linear scan, the same order as the sort below.
		var best: SimEnemy = null
		var best_key := 0.0
		for e in candidates:
			var k := _rank_key(mode, e)
			if best == null or k > best_key or (k == best_key and e.id < best.id):
				best = e
				best_key = k
		out.append(best)
		return out
	out = candidates.duplicate()
	out.sort_custom(func(a: SimEnemy, b: SimEnemy) -> bool:
		var ka := _rank_key(mode, a)
		var kb := _rank_key(mode, b)
		return ka > kb or (ka == kb and a.id < b.id))
	if out.size() > n:
		out.resize(n)
	return out


## Higher = ranked first under `mode` (see _ranked_targets).
func _rank_key(mode: String, e: SimEnemy) -> float:
	match mode:
		"strongest":
			return e.hp
		"fastest":
			return float(roundi(e.base_units_per_tick * e.speed_mult))
	return -float(e.route.length - e.distance)


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


## LT-29 P5: moves `e` `cells` back along its own route (path walkers along the path,
## flyers along their straight line), never before its start. prev_distance follows, so the
## render does not slide it backwards through the tick. Distance only decreases, so _leak
## and _check_outcome are unaffected.
func _push_back(e: SimEnemy, cells: float) -> void:
	e.distance = maxi(0, e.distance - roundi(cells * SimTime.UNITS_PER_CELL))
	e.prev_distance = e.distance


## Slot 5, after a shot's damage (LT-29 §1.3-1.4): bleed on every hit still live; the chain
## pull on the shot's primary target only (Q4), if it was hit, is still live, has max_hp <=
## pull_max_hp (0 = no cap) and no pull immunity. SHOT was emitted before the damage (the
## pinned SHOT -> DIED order), so `pulled` is written into the same `shot` Dictionary
## already passed to _emit: events are drained only after step(), and SimEvent keeps the
## Dictionary by reference.
func _on_hit_effects(t: SimTower, s: TowerDef.Level, target: SimEnemy, hits: Array[SimEnemy],
		shot: Dictionary) -> void:
	_apply_bleed_hits(hits, s.effects, t.def.id)
	if s.effects.get("reveal_fakes", 0.0) > 0.0:
		# LT-50 (P8, Resonator Pure): a fake the shot hit is revealed for good; _candidates
		# then drops it, so the beam lets go of it at its next shot.
		for e in hits:
			if e.is_fake:
				e.revealed = true
	var pull: float = s.effects.get("pull_cells", 0.0)
	if pull <= 0.0:
		return
	var pulled: Array[int] = []
	var cap: float = s.effects.get("pull_max_hp", 0.0)
	if hits.has(target) and target.is_live() and (cap <= 0.0 or target.max_hp <= cap) \
			and int(target.status.get("pull_immune_ticks", 0)) <= 0:
		_push_back(target, pull)
		var immune := SimTime.ticks(float(s.effects.get("pull_immune_seconds", 0.0)))
		if immune > 0:
			target.status["pull_immune_ticks"] = immune
		pulled.append(target.id)
	shot["pulled"] = pulled


## Bleed from `effects` (bleed_dps, bleed_seconds) on every hit still live, in hit order.
func _apply_bleed_hits(hits: Array[SimEnemy], effects: Dictionary, source: String) -> void:
	var bleed_dps: float = effects.get("bleed_dps", 0.0)
	var bleed_seconds: float = effects.get("bleed_seconds", 0.0)
	if bleed_dps > 0.0 and bleed_seconds > 0.0:
		for e in hits:
			if e.is_live():
				_apply_bleed(e, bleed_dps, bleed_seconds, source)


## LT-29 §1.3 (shared with later bleeders): refresh, never stack. The duration restarts
## (max of what is left and `seconds`), the higher dps wins (its source too; a tie -> the
## newest), and a new bleed's first pulse comes one second after the hit.
func _apply_bleed(e: SimEnemy, dps: float, seconds: float, source: String) -> void:
	var st := e.status
	var left := int(st.get("bleed_ticks", 0))
	st["bleed_ticks"] = maxi(left, SimTime.ticks(seconds))
	if left <= 0 or dps >= float(st.get("bleed_dps", 0.0)):
		st["bleed_dps"] = dps
		st["bleed_source"] = source
	if left <= 0:
		st["bleed_pulse"] = SimTime.TICK_RATE


## Slot 2 (LT-29 P6): every live enemy (fakes too) in id order counts its status timers down.
## Bleed: each second one pulse of bleed_dps through apply_damage (armor once per pulse,
## Q1; this tick's strip, vuln and madness buff apply), credited to bleed_source; the keys
## are erased when the duration ends. Pull and banish (LT-51) immunity: erased at 0.
func _tick_statuses() -> void:
	for e in state.enemies:
		if not e.is_live() or e.status.is_empty():
			continue
		var st := e.status
		for key: String in IMMUNITY_KEYS:
			if st.has(key):
				st[key] = int(st[key]) - 1
				if int(st[key]) <= 0:
					st.erase(key)
		if st.has("bleed_ticks"):
			st["bleed_ticks"] = int(st["bleed_ticks"]) - 1
			st["bleed_pulse"] = int(st["bleed_pulse"]) - 1
			if int(st["bleed_pulse"]) <= 0:
				st["bleed_pulse"] = SimTime.TICK_RATE
				apply_damage(e.id, float(st["bleed_dps"]), String(st["bleed_source"]))
			if int(st["bleed_ticks"]) <= 0:
				for key: String in ["bleed_ticks", "bleed_dps", "bleed_pulse", "bleed_source"]:
					st.erase(key)


## LT-52 slot 2: an ally whose lifetime ran out is gone ("expired"); a live ally's held
## enemy gets speed_mult 0. A hold that is no longer valid (_holds: the enemy died, was
## revealed as a fake, or was pushed out of contact by a pull / banish in the last slot 5)
## is dropped first, so that enemy is not frozen for another tick.
func _tick_allies() -> void:
	for a in state.allies:
		if not a.is_live():
			continue
		if a.expires_tick > 0 and state.tick >= a.expires_tick:
			_ally_gone(a, "expired")
			continue
		if a.held_id < 0:
			continue
		var e := enemy_by_id(a.held_id)
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
func _move_allies() -> void:
	if state.allies.is_empty():
		return
	var held: Dictionary[int, bool] = {}
	for a in state.allies:
		if a.is_live() and a.held_id >= 0:
			held[a.held_id] = true
	for a in state.allies:
		if not a.is_live():
			continue
		a.prev_pos = a.pos
		if a.held_id >= 0:
			if _holds(a, enemy_by_id(a.held_id)):
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


## The enemy `a` chases this tick (see _move_allies), or null.
func _ally_target(a: SimAlly, held: Dictionary[int, bool]) -> SimEnemy:
	var leash2 := a.leash * a.leash
	var best: SimEnemy = null
	var best_d2 := INF
	for e in state.enemies:
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
func _ally_combat() -> void:
	var madness := state.sanity_state == SimState.SanityState.MADNESS
	for a in state.allies:
		if not a.is_live() or a.held_id < 0:
			continue
		var e := enemy_by_id(a.held_id)
		if not _holds(a, e):
			a.held_id = -1
			continue
		var dps := a.dps
		if madness:
			var t := tower_by_id(a.tower)
			if t != null and t.stats().madness_affected:
				dps *= config.sanity.madness.damage_multiplier
		var armor := maxf(0.0, e.def.armor + e.armor_bonus)
		apply_damage(e.id, maxf(0.0, dps - armor) * SimTime.DT, a.source, true)
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
	_emit(SimEvent.Type.ALLY_GONE, a.id, data)


## A sold tower's live allies are gone ("dismissed"), in id order.
func _dismiss_allies(tower_id: int) -> void:
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
## compacted again, so the build phase starts with no enemy in `state`. Fake pack members
## still queued (LT-63) are dropped without an event: they never entered.
func dissolve_fakes(reason: String) -> void:
	_pack_queue = _pack_queue.filter(func(q: Array) -> bool: return not q[2])
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


## LT-29 §1.1 crit hook: one roll on CRIT against `chance`; no roll (no CRIT draw) at 0.
func _roll_crit(chance: float) -> bool:
	if chance <= 0.0:
		return false
	return rng(SimRng.Stream.CRIT).randf() < chance


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
	if state.allies.is_empty():
		return
	var kept: Array[SimAlly] = []
	for a in state.allies:
		if a.is_live():
			kept.append(a)
	state.allies = kept


## Lose first, so a leak that empties HP on the last enemy is a loss (§5).
func _check_outcome() -> void:
	if state.lighthouse_hp == 0:
		state.outcome = SimState.Outcome.LOST
		_emit(SimEvent.Type.OUTCOME, 0, {"result": "lost"})
		return
	if _spawner == null or not _spawner.is_exhausted() or has_queued_real_members():
		return
	for e in state.enemies:
		if not e.is_fake:
			return
	state.outcome = SimState.Outcome.WON
	_emit(SimEvent.Type.OUTCOME, 0, {"result": "won"})
