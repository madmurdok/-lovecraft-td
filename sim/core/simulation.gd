class_name Simulation
extends RefCounted
## The plain-script game simulation (design note LT-4). Advanced one fixed tick at a
## time by step(); scenes read `state` directly and drain one-shot events.
## Same config + seed + command log -> same events and state (§4).

## SimEnemy.status timers that only count down to 0 and go (LT-29 pull, LT-51 banish).
const IMMUNITY_KEYS: PackedStringArray = ["pull_immune_ticks", "banish_immune_ticks"]
## LT-52 (LT-46 §2.2): an allied unit within this many cells of an enemy it chases holds it.
const ALLY_CONTACT := 0.4

var state: SimState
var config: GameConfig
## Read-only view of the one event buffer (LT-80: it lives in SimContext).
var events: Array[SimEvent]:
	get:
		return _ctx.events
## Debug only (LT-12 §1): set by scenes/game.gd in debug builds with `--reveal-fakes`.
## The sim never reads it; only debug_is_fake does, so it cannot change an outcome.
var debug_reveal_fakes := false

var _spawner: SimSpawner
## LT-80 (B5): shared plumbing and the systems split out of this facade; built in _init.
var _ctx: SimContext
var _economy: EconomySystem
var _sanity: SanitySystem
var _light: LightSystem
var _ground_route: SimRoute
var _hallucinations := HallucinationSystem.new()
## LT-27 §1.3: token id -> true for tokens dropped by fakes. Sim-private: the render must
## never tell a ghost token from a real one before it vanishes.
var _ghost_tokens: Dictionary[int, bool] = {}
## LT-63: pack members not entered yet, queue order: [due_tick, EnemyDef, is_fake, pack_of].
## Sim only (fakes are queued too, LT-12 §1); real members enter in slot 7, fake ones in
## slot 8 after the dawn check (_release_pack_members).
var _pack_queue: Array = []


func _init(p_config: GameConfig, run_seed: int) -> void:
	_ctx = SimContext.new(p_config, run_seed)
	config = _ctx.config
	state = _ctx.state
	state.map = config.map
	state.lighthouse_hp = config.economy.lighthouse_hp
	for kind in config.economy.relic_ids():
		state.relics[kind] = 0
	# Construction writes start values (gold; sanity, cap, state; oil, beam) but emits and
	# draws nothing, so this order changes no output (LT-80 §3).
	_economy = EconomySystem.new(_ctx)
	_sanity = SanitySystem.new(_ctx, _economy)
	_light = LightSystem.new(_ctx, _economy)
	_ground_route = SimRoute.from_cells(config.map.grid, config.map.path)


## Without a spawner the run never wins (nothing can be "exhausted"). A WaveDirector
## starts the build phase before wave 1 here (BUILD_STARTED on tick 0).
func set_spawner(s: SimSpawner) -> void:
	_spawner = s
	_spawner.attach(self)


func rng(stream: SimRng.Stream) -> RandomNumberGenerator:
	return _ctx.rng(stream)


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
	_light.update_beam()
	_apply_auras()
	_sanity.apply_madness_buff()
	_light.apply_flare_slow()
	_tick_statuses()
	# LT-52 (P10): allies past their lifetime are gone; the rest hold their enemy
	# (speed_mult 0, after every other speed modifier).
	_tick_allies()
	_light.count_down_flare()
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
	_sanity.horror_drain()
	# 6b. Relic tokens (LT-27 §1.3): ghosts vanish, real tokens are credited on arrival.
	_settle_tokens()
	# 7. Spawning: queued real pack members due now (LT-63), then the spawner, then fakes
	# (LT-12) from the spawner's candidates.
	_release_pack_members(false)
	if _spawner != null:
		_spawner.tick(self)
		_hallucinations.tick(self, _spawner)
	# 8. Remove dead and leaked enemies and gone allies (LT-52); then the wave system settles
	# a cleared wave (its bonus is paid before the outcome check, so the last wave's bonus
	# lands too).
	_compact()
	if _spawner != null:
		_spawner.end_tick(self)
	# 8b. Queued fake pack members due now enter after the dawn check (LT-63), so one due on
	# the dawn tick is dropped with the rest instead of entering and dissolving at once.
	_release_pack_members(true)
	# 9. Outcome.
	_check_outcome()


## Spawns `def_id` at the start of its route; a `pack` enemy spawns min..max of them
## (rolled on SPAWN, or on SANITY for a fake so hallucinations never change real pack
## sizes, LT-12 §2). LT-63: only the first member enters now; member k (1..count-1) is
## queued and enters at the start of the route on tick now + k x ticks(pack.spacing_s), so
## members never stack on one spot: a real one in slot 7 before the spawner's spawns, a
## fake one in slot 8 after the wave system's dawn check. Every member's pack_of is the first member's id. Returns the first new id,
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


## LT-63: every queued pack member with is_fake == `fakes` whose due tick has come enters,
## queue order (slot 7 for real members, slot 8 for fake ones). Draws no RNG.
func _release_pack_members(fakes: bool) -> void:
	if _pack_queue.is_empty():
		return
	var left: Array = []
	for q: Array in _pack_queue:
		if bool(q[2]) != fakes or int(q[0]) > state.tick:
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
	e.route = _ground_route
	if def.flying:
		e.route = SimRoute.straight(state.map.grid, state.map.spawn, state.map.lighthouse)
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
## the order of SimCommand.CommandResult. Changes nothing.
func can_build(def_id: String, cell: Vector2i) -> SimCommand.CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	if not config.towers.has(def_id):
		return SimCommand.CommandResult.UNKNOWN_TOWER
	var def: TowerDef = config.towers[def_id]
	if not state.map.is_buildable(cell):
		return SimCommand.CommandResult.NOT_BUILDABLE
	if state.tower_at.has(cell):
		return SimCommand.CommandResult.OCCUPIED
	if state.gold < def.cost:
		return SimCommand.CommandResult.NOT_ENOUGH_GOLD
	return _ctx.day_only()  # last: keeps "first failing reason in SimCommand.CommandResult order" (LT-27 §3)


## Player command (§1.3, applied at once between ticks): builds an L1 `def_id` on `cell`
## for its cost. On OK the tower gets the next entity id, is ready to fire on the next
## tick, and TOWER_BUILT + GOLD_CHANGED are emitted. Its L1 sanity_reserve then lowers the
## cap (_change_reserve "build", LT-23 §1.2); a cap taken to 0 empties sanity and so starts
## MADNESS. Only gold is checked. Day only (LT-27 §3): refused at night with NOT_BUILD_PHASE.
func build_tower(def_id: String, cell: Vector2i) -> SimCommand.CommandResult:
	var result := can_build(def_id, cell)
	if result != SimCommand.CommandResult.OK:
		return result
	var def: TowerDef = config.towers[def_id]
	var t := SimTower.new()
	t.id = state.next_id
	state.next_id += 1
	t.def = def
	t.cell = cell
	t.pos = state.map.grid.centre(cell)
	t.spent = def.cost
	t.build_tick = state.tick
	state.towers.append(t)
	state.tower_at[cell] = t.id
	_ctx.log_command([state.tick, "build", def_id, cell])
	_emit(SimEvent.Type.TOWER_BUILT, t.id, {"def": def_id, "cell": cell, "cost": def.cost})
	_economy.add_gold(-def.cost, "build", t.id)
	_sanity.change_reserve(t, _sanity.reserve_of(t), "build")
	return SimCommand.CommandResult.OK


## Whether sell_tower(tower_id) would be applied now; OK or the first failing reason in this
## order: OUTCOME_REACHED, NO_SUCH_TOWER, NOT_BUILD_PHASE (at night, LT-27 §3). Changes
## nothing.
func can_sell_tower(tower_id: int) -> SimCommand.CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	if tower_by_id(tower_id) == null:
		return SimCommand.CommandResult.NO_SUCH_TOWER
	return _ctx.day_only()


## Player command: sells tower `tower_id` for economy.sell_refund_ratio of everything spent
## on it, build and upgrades (rounded once, on the total) and frees its cell. Emits
## TOWER_SOLD + GOLD_CHANGED, then the cap rises by the tower's reserve (_change_reserve
## "sell", LT-23 Q4); current sanity does not change, in MADNESS too. Day only (LT-27 §3):
## OUTCOME_REACHED, NO_SUCH_TOWER, then NOT_BUILD_PHASE at night.
func sell_tower(tower_id: int) -> SimCommand.CommandResult:
	var result := can_sell_tower(tower_id)
	if result != SimCommand.CommandResult.OK:
		return result
	var t := tower_by_id(tower_id)
	var refund := sell_refund(t)
	var reserve := _sanity.reserve_of(t)
	state.towers.erase(t)
	state.tower_at.erase(t.cell)
	_dismiss_allies(t.id)
	_ctx.log_command([state.tick, "sell", tower_id])
	_emit(SimEvent.Type.TOWER_SOLD, t.id, {"def": t.def.id, "cell": t.cell, "refund": refund})
	_economy.add_gold(refund, "sell", t.id)
	_sanity.change_reserve(t, -reserve, "sell")
	return SimCommand.CommandResult.OK


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
func can_upgrade(tower_id: int, branch := "") -> SimCommand.CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	var t := tower_by_id(tower_id)
	if t == null:
		return SimCommand.CommandResult.NO_SUCH_TOWER
	if t.level >= TowerDef.LEVEL_COUNT:
		return SimCommand.CommandResult.MAX_LEVEL
	if t.level == TowerDef.LEVEL_COUNT - 1 and branch.is_empty():
		return SimCommand.CommandResult.NEED_BRANCH
	var target := upgrade_target(t, branch)
	if target == null:
		return SimCommand.CommandResult.BAD_BRANCH
	var day := _ctx.day_only()
	if day != SimCommand.CommandResult.OK:
		return day
	if state.gold < target.upgrade_cost:
		return SimCommand.CommandResult.NOT_ENOUGH_GOLD
	return SimCommand.CommandResult.OK


## Player command (LT-24): raises tower `tower_id` one level (L1 -> L2 with branch "", L2 ->
## L3 with "a"/"b") for the target's upgrade_cost, by day only. The tower keeps its
## id, cell, build_tick, status and running cooldown; the new stats apply from its next
## shot. Emits TOWER_UPGRADED {def, cell, level, branch, cost} + GOLD_CHANGED "upgrade";
## the cap then moves by target reserve - current reserve (_change_reserve "upgrade",
## LT-23 §1.2), like a build: a cap taken to 0 starts MADNESS; a lower reserve raises it.
func upgrade_tower(tower_id: int, branch := "") -> SimCommand.CommandResult:
	var result := can_upgrade(tower_id, branch)
	if result != SimCommand.CommandResult.OK:
		return result
	var t := tower_by_id(tower_id)
	var target := upgrade_target(t, branch)
	var delta := _sanity.reserve_delta(t.def.id, t.stats(), target)
	t.level += 1
	t.branch = branch
	t.spent += target.upgrade_cost
	_ctx.log_command([state.tick, "upgrade", tower_id, branch])
	_emit(SimEvent.Type.TOWER_UPGRADED, t.id, {"def": t.def.id, "cell": t.cell,
		"level": t.level, "branch": branch, "cost": target.upgrade_cost})
	_economy.add_gold(-target.upgrade_cost, "upgrade", t.id)
	_sanity.change_reserve(t, delta, "upgrade")
	return SimCommand.CommandResult.OK


## LT-34 (LT-33 finding 4): whether build_tower(def_id, ...) would start MADNESS: its L1
## sanity_reserve takes the cap to 0 or below (LT-23 Q3); never while already in MADNESS.
## False for an unknown def_id. Checks no gold, cell, phase or outcome: the UI warns only on
## a button can_build allows. Changes nothing.
func would_drive_mad_build(def_id: String) -> bool:
	if not config.towers.has(def_id):
		return false
	var def: TowerDef = config.towers[def_id]
	return _sanity.reserve_drives_mad(def.levels[0].sanity_reserve)


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
	return _sanity.reserve_drives_mad(_sanity.reserve_delta(t.def.id, t.stats(), target))


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
func can_set_target_priority(tower_id: int, mode: String) -> SimCommand.CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	var t := tower_by_id(tower_id)
	if t == null:
		return SimCommand.CommandResult.NO_SUCH_TOWER
	if not has_targeting(t):
		return SimCommand.CommandResult.NO_TARGETING
	if not SimTower.TARGET_PRIORITIES.has(mode):
		return SimCommand.CommandResult.BAD_PRIORITY
	return SimCommand.CommandResult.OK


## Player command (LT-31): sets whom tower `tower_id` shoots from its next shot on, in
## any phase, for free. Re-setting the current mode is applied too (logged, event).
## Emits TARGET_PRIORITY_SET {def, cell, mode}; logs [tick, "set_target_priority", id,
## mode]. The tower's cooldown is not touched.
func set_target_priority(tower_id: int, mode: String) -> SimCommand.CommandResult:
	var result := can_set_target_priority(tower_id, mode)
	if result != SimCommand.CommandResult.OK:
		return result
	var t := tower_by_id(tower_id)
	t.target_priority = mode
	t.locked_id = -1  # LT-50: a beam re-picks by the new mode at its next shot
	_ctx.log_command([state.tick, "set_target_priority", tower_id, mode])
	_emit(SimEvent.Type.TARGET_PRIORITY_SET, t.id, {"def": t.def.id, "cell": t.cell,
		"mode": mode})
	return SimCommand.CommandResult.OK


## Whether call_wave() would be applied now; OK, OUTCOME_REACHED, or NOT_BUILD_PHASE (no
## WaveDirector, or not by day). Changes nothing.
func can_call_wave() -> SimCommand.CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	if not (_spawner is WaveDirector) or state.phase != SimState.Phase.BUILD:
		return SimCommand.CommandResult.NOT_BUILD_PHASE
	return SimCommand.CommandResult.OK


## Player command ("Light the lamp", LT-27 §1.2): ends the day now; the next wave spawns
## from the next tick on. Sets state.night_luck to early_night_luck() (1 +
## economy.early_night_luck_per_second x whole seconds left on the day timer) for this
## night; pays no money. Emits WAVE_STARTED {early: true}.
func call_wave() -> SimCommand.CommandResult:
	var result := can_call_wave()
	if result != SimCommand.CommandResult.OK:
		return result
	var director := _spawner as WaveDirector
	var luck := early_night_luck()
	_ctx.log_command([state.tick, "call_wave"])
	director.start_wave(self, true)
	state.night_luck = luck
	return SimCommand.CommandResult.OK


func buyout_applies() -> bool:
	return _sanity.buyout_applies()


func can_buy_sanity() -> SimCommand.CommandResult:
	return _sanity.can_buy_sanity()


func buy_sanity() -> SimCommand.CommandResult:
	return _sanity.buy_sanity()


func debug_set_sanity(value: float) -> SimCommand.CommandResult:
	return _sanity.debug_set_sanity(value)


## LT-67 (debug, `--sandbox`): ends the current night now. The WaveDirector marks every
## spawn event of the wave fired (debug_fire_all), the pack queue is emptied, and every live
## real enemy dies with DIED {source: "debug"} (no drop, no sanity regen, no kill reward);
## fakes are left to the dawn. The wave is then cleared by the usual dawn check in slot 8
## of the next tick (wage, sanity regen, BUILD_STARTED or DONE). Logged as
## [tick, "debug_end_night"] so a replay reproduces it. OUTCOME_REACHED once the run is
## over; NOT_NIGHT without a WaveDirector or outside a wave (phase BUILD / DONE); else OK.
func debug_end_night() -> SimCommand.CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	if not (_spawner is WaveDirector) or state.phase != SimState.Phase.WAVE:
		return SimCommand.CommandResult.NOT_NIGHT
	_ctx.log_command([state.tick, "debug_end_night"])
	(_spawner as WaveDirector).debug_fire_all(self)
	_pack_queue.clear()
	for e in state.enemies:
		if e.is_live() and not e.is_fake:
			e.dead = true
			_emit(SimEvent.Type.DIED, e.id, {"source": "debug"})
	_compact()
	return SimCommand.CommandResult.OK


# --- LT-30: lighthouse levels, lamp oil and the flare (player commands) -----------------

func beam_count() -> int:
	return _light.beam_count()


func lighthouse_upgrade_cost() -> int:
	return _light.lighthouse_upgrade_cost()


func can_upgrade_lighthouse() -> SimCommand.CommandResult:
	return _light.can_upgrade_lighthouse()


func upgrade_lighthouse() -> SimCommand.CommandResult:
	return _light.upgrade_lighthouse()


func can_buy_oil() -> SimCommand.CommandResult:
	return _light.can_buy_oil()


func buy_oil() -> SimCommand.CommandResult:
	return _light.buy_oil()


func can_fire_flare() -> SimCommand.CommandResult:
	return _light.can_fire_flare()


func fire_flare() -> SimCommand.CommandResult:
	return _light.fire_flare()


func beam_directions(alpha: float) -> Array[Vector2]:
	return _light.beam_directions(alpha)


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
	"debug_end_night": [],
}


## LT-34: re-applies one command_log entry [tick, name, args...] now (the caller steps the
## sim to entry[0] first) through the same public command, so it is logged again.
## UNKNOWN_COMMAND (and an error) for an entry naming no command; BAD_ARGS (and an error)
## for a known name whose args do not match REPLAY_ARGS in count and type (LT-36). Never
## raises a script error, and a refused entry changes nothing.
func replay_command(entry: Array) -> SimCommand.CommandResult:
	var cmd: Variant = entry[1] if entry.size() > 1 else ""
	if typeof(cmd) not in [TYPE_STRING, TYPE_STRING_NAME] or not REPLAY_ARGS.has(String(cmd)):
		push_error("Simulation.replay_command: unknown entry %s" % [entry])
		return SimCommand.CommandResult.UNKNOWN_COMMAND
	if not _replay_args_ok(entry, REPLAY_ARGS[String(cmd)]):
		push_error("Simulation.replay_command: bad args %s" % [entry])
		return SimCommand.CommandResult.BAD_ARGS
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
		"debug_end_night": return debug_end_night()
	return SimCommand.CommandResult.UNKNOWN_COMMAND  # unreachable: every REPLAY_ARGS key has an arm


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
func can_sell_relics(kind := "") -> SimCommand.CommandResult:
	if state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	var day := _ctx.day_only()
	if day != SimCommand.CommandResult.OK:
		return day
	if kind != "":
		return SimCommand.CommandResult.OK if state.relics.get(kind, 0) > 0 else SimCommand.CommandResult.NO_RELICS
	for k: String in state.relics:
		if state.relics[k] > 0:
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
	_ctx.log_command([state.tick, "sell_relics", kind])
	var total := 0
	for k in config.economy.relic_ids():
		if kind != "" and k != kind:
			continue
		var n: int = state.relics[k]
		if n <= 0:
			continue
		total += relic_price(k) * n
		_add_relics(k, -n, "sell", 0)
	_economy.add_gold(total, "relic_sale", 0)
	return SimCommand.CommandResult.OK


func auto_restore_sanity() -> float:
	return _sanity.auto_restore_sanity()


func restore_target() -> float:
	return _sanity.restore_target()


func reserve_of(t: SimTower) -> float:
	return _sanity.reserve_of(t)


func reserve_delta(def_id: String, from: TowerDef.Level, to: TowerDef.Level) -> float:
	return _sanity.reserve_delta(def_id, from, to)


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
	_economy.add_gold(bonus, "wave_bonus", 0)
	return bonus


func award_wave_sanity() -> float:
	return _sanity.award_wave_sanity()


func sanity_state_for(s: float) -> SimState.SanityState:
	return _sanity.sanity_state_for(s)


## LT-76 (LT-65 §3.2) read-only: TowerRules.light_effect of tower `tower_id` in its net light
## state now ({power_mult, interval_mult, ignore_miss, miss_add}); {} for no such tower.
func tower_mults(tower_id: int) -> Dictionary:
	var t := tower_by_id(tower_id)
	if t == null:
		return {}
	return TowerRules.light_effect(t.def, config, t.lit, t.shadowed)


## LT-76 (LT-65 §3.2): the tower standing on `cell` (built or building), or null.
func tower_at_cell(cell: Vector2i) -> SimTower:
	if not state.tower_at.has(cell):
		return null
	return tower_by_id(state.tower_at[cell])


## The tower with this id, or null (also null once sold).
func tower_by_id(id: int) -> SimTower:
	for t in state.towers:
		if t.id == id:
			return t
	return null


## Live enemies (fakes included) whose position is within `range_cells` of the centre of
## `cell`, boundary included; id order (§6 target query).
func enemies_in_range(cell: Vector2i, range_cells: float) -> Array[SimEnemy]:
	return enemies_near(state.map.grid.centre(cell), range_cells)


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
	var out := _ctx.events
	_ctx.events = []
	return out


## For sim systems outside this script (the wave director); scenes never call it.
func emit_event(type: SimEvent.Type, id: int, data: Dictionary) -> void:
	_emit(type, id, data)


func _emit(type: SimEvent.Type, id: int, data: Dictionary) -> void:
	# Inlined rather than _ctx.emit: the hottest call in the sim (LT-80 §2).
	_ctx.events.append(SimEvent.new(type, state.tick, id, data))


## Test-only forwarder (LT-80, like Q1: ui_event_refresh / scene_game tests top up gold).
func _add_gold(delta: int, reason: String, id: int) -> void:
	_economy.add_gold(delta, reason, id)


## Test-only forwarder (LT-80 Q1; B8 revisits it).
func _add_sanity(delta: float, reason: String, id: int) -> float:
	return _sanity.add(delta, reason, id)


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
		_sanity.add(config.sanity.regen_mundane_kill, "mundane_kill", e.id)


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

func flare_seconds() -> float:
	return _light.flare_seconds()


func flare_burn() -> Dictionary:
	return _light.flare_burn()


func oil_cap() -> int:
	return _light.oil_cap()


func flare_cost_oil() -> int:
	return _light.flare_cost_oil()


func oil_for_flare() -> int:
	return _light.oil_for_flare()


func light_at(p: Vector2, skip_id := -1) -> Dictionary:
	return _light.light_at(p, skip_id)


## LT-70 §2.1: the aura / cast radius test; the rule is LightRules.in_cast_radius (kept here
## for existing callers).
static func in_cast_radius(c: Vector2, range_cells: float, p: Vector2) -> bool:
	return LightRules.in_cast_radius(c, range_cells, p)


## Test-only forwarder (LT-80 Q1; B8 revisits it).
func _is_lit(px: float, py: float) -> bool:
	return _light.is_lit(px, py)


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
## fake inside, for good; _candidates then drops it, so no tower targets it again. A lit or
## shadowed mundane aura is unchanged (LT-30 / LT-70 modifiers apply to firing and to
## occult auras only); a lit or shadowed occult aura works at _power_mult strength.
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
			if not LightRules.covers(config.map.grid, t.cell, s.range_cells, p):
				continue
			inside = true
			var t_slow: float = s.effects.get("slow", 0.0)
			var t_mult: float = s.effects.get("damage_taken_multiplier", 1.0)
			var t_strip: float = s.effects.get("strip_armor", 0.0)
			var pm := _light.power_mult(t)
			if pm != 1.0:
				# LT-30 §2 / LT-70 §2.3: a lit (x0.7) or shadowed (x1.15) occult aura works at
				# that strength (LT-29 §2: the armor strip too).
				t_slow *= pm
				t_mult = TowerRules.powered_taken_mult(t_mult, pm)
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


## Test-only forwarder (LT-80, like Q1: madness_buff_test reads it; B8 revisits it).
func _madness_buff_blocked(e: SimEnemy) -> bool:
	return _sanity.madness_buff_blocked(e)


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
		var factor := TowerRules.shot_factor(s, config, state.sanity)
		# LT-30 §2 / LT-70 §2.3: lit x0.7 / shadowed x1.15 (occult), before the madness x2.
		var damage := TowerRules.shot_damage(s, factor, _light.power_mult(t))
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
		# LT-70 §2.3: a shadowed one adds shadow.mundane.miss_chance_add to the chance.
		var miss_add := TowerRules.miss_add(t.def.kind, config, t.shadowed)
		var miss := t.def.kind == "mundane" \
			and not TowerRules.ignore_miss(t.def.kind, config, t.lit) and _roll_miss(miss_add)
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
		# LT-30 / LT-70 §2.3: lit x0.8 / shadowed x1.25 (mundane), decided at the shot.
		var interval := TowerRules.fire_interval(s, _light.interval_mult(t))
		t.cooldown_ticks = TowerRules.cooldown_ticks(interval)


## LT-51 (§2.2, Q4): a Silver Key cast. Picks (by target_priority) up to banish_targets of
## the tower's candidates that may be banished (_banishable), moves each back banish_cells
## along its own route (P5 _push_back, the Chain pull's rewind; x _power_mult: lit x0.7,
## LT-70 shadowed x1.15) and gives it banish_immune_seconds of banish immunity (its own status key:
## pull immunity does not block a banish, nor the reverse). A level with damage (Corrupted)
## then hits each one (armor applies; x _power_mult, x the madness multiplier).
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
	var power := _light.power_mult(t)
	var damage := TowerRules.shot_damage(s, 1.0, power)
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
	t.cooldown_ticks = TowerRules.cooldown_ticks(s.fire_interval)


## LT-52 (§2.2): a Summoning Circle with fewer than summon_max live units summons one at
## its centre (spawn_ally: leash = range + 1, lifetime summon_lifetime) and spends the
## cooldown. At its maximum it does not summon and stays ready, so a unit gone frees a
## slot at once. A circle lit (or, LT-70, shadowed) at summon time gives the unit
## summon_dps x _power_mult for its whole life (§3 "lit at summon time"); madness is
## applied live by _ally_combat.
## No miss, crit or astray (a unit bites what it holds).
func _summon(t: SimTower, s: TowerDef.Level) -> void:
	if allies_of(t.id).size() >= s.summon_max():
		return
	var dps := TowerRules.unit_dps(s, _light.power_mult(t))
	var id := spawn_ally(t.id, t.def.id, t.centre(), s.effects.get("summon_hp", 0.0), dps,
		s.effects.get("summon_speed", 0.0), s.summon_flying(),
		SimTime.ticks(float(s.effects.get("summon_lifetime", 0.0))), s.range_cells + 1.0)
	if id != 0:
		t.cooldown_ticks = TowerRules.cooldown_ticks(s.fire_interval)


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
	var out: Array[SimEnemy] = []
	for e in enemies:
		if not TowerRules.in_dead_zone(c, s.min_range, e.route.position_at(e.distance)):
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
## still queued (LT-63), due on this tick or later, are dropped without an event: they
## never entered.
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


func threshold() -> SanityConfig.Threshold:
	return _sanity.threshold()


## LT-12 §4 miss hook: one roll on COMBAT against the state's miss_chance plus `extra`
## (LT-70: a shadowed mundane shot), capped at 1; no roll (and no COMBAT draw) when the
## chance is 0, so Lucid/Whispers consume COMBAT as before for unshadowed shots.
func _roll_miss(extra := 0.0) -> bool:
	var chance := minf(1.0, _sanity.threshold().miss_chance + extra)
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
