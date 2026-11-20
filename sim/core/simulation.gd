class_name Simulation
extends RefCounted
## The plain-script game simulation (design note LT-4). Advanced one fixed tick at a
## time by step(); scenes read `state` directly and drain one-shot events.
## Same config + seed + command log -> same events and state (§4).

## LT-82: the constants moved with their code; kept here for existing callers.
const IMMUNITY_KEYS: PackedStringArray = CombatSystem.IMMUNITY_KEYS
const ALLY_CONTACT := AllySystem.ALLY_CONTACT

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
var _combat: CombatSystem
var _ally: AllySystem
var _spawn: SpawnSystem
var _hallucinations := HallucinationSystem.new()


func _init(p_config: GameConfig, run_seed: int) -> void:
	_ctx = SimContext.new(p_config, run_seed)
	config = _ctx.config
	state = _ctx.state
	state.map = config.map
	state.lighthouse_hp = config.economy.lighthouse_hp
	# Construction writes start values (gold; sanity, cap, state; oil, beam) but emits and
	# draws nothing, so this order changes no output (LT-80 §3).
	_economy = EconomySystem.new(_ctx)
	_sanity = SanitySystem.new(_ctx, _economy)
	_light = LightSystem.new(_ctx, _economy)
	# LT-82: Ally holds Combat; Combat spawns through method Callables (object id, no ref).
	# LT-83: Combat holds Spawn (push_back); Spawn compacts allies through a method Callable.
	_spawn = SpawnSystem.new(_ctx)
	_combat = CombatSystem.new(_ctx, _light, _sanity, _economy, _spawn)
	_ally = AllySystem.new(_ctx, _combat)
	_combat.set_ally_hooks(_ally.spawn, _ally.allies_of)
	_spawn.set_ally_compact(_ally.compact)


## Without a spawner the run never wins (nothing can be "exhausted"). A WaveDirector
## starts the build phase before wave 1 here (BUILD_STARTED on tick 0).
func set_spawner(s: SimSpawner) -> void:
	_spawner = s
	_spawner.attach(self)


## Inspection only (seed, state); draws go through SimContext.randf / randi_range.
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
	_combat.apply_auras()
	_sanity.apply_madness_buff()
	_light.apply_flare_slow()
	_combat.tick_statuses()
	# LT-52 (P10): allies past their lifetime are gone; the rest hold their enemy
	# (speed_mult 0, after every other speed modifier).
	_ally.tick_allies()
	_light.count_down_flare()
	# 3. Movement: enemies, then allies chase them (LT-52; contact starts a hold).
	_spawn.move()
	_ally.move_allies()
	# 4. Leaks.
	_spawn.leak()
	# 5. Towers fire / damage: single and line shots (LT-6), AoE casts (LT-11, no sanity
	# cost since LT-23); madness damage and astray shots (LT-13). Kills drop relic tokens
	# (LT-27 §1.3).
	_combat.fire_towers()
	# LT-52 (P10): each holding ally and its enemy trade damage, in ally id order.
	_ally.ally_combat()
	# 5b. Fused charges (LT-47 P2) whose fuse ran out explode, in throw order; a charge
	# thrown this tick waits at least one tick.
	_combat.settle_blasts()
	# 6. Sanity (LT-10): horror drain. Kill regen is paid in slot 5 (CombatSystem._on_enemy_killed),
	# between-waves regen in slot 8 (wave system), each through _add_sanity.
	_sanity.horror_drain()
	# 6b. Relic tokens (LT-27 §1.3): ghosts vanish, real tokens are credited on arrival.
	_economy.settle_tokens()
	# 7. Spawning: queued real pack members due now (LT-63), then the spawner, then fakes
	# (LT-12) from the spawner's candidates.
	_spawn.release_pack_members(false)
	if _spawner != null:
		_spawner.tick(self)
		_hallucinations.tick(self, _spawner, _ctx.sim_rng())
	# 8. Remove dead and leaked enemies and gone allies (LT-52); then the wave system settles
	# a cleared wave (its bonus is paid before the outcome check, so the last wave's bonus
	# lands too).
	_spawn.compact()
	if _spawner != null:
		_spawner.end_tick(self)
	# 8b. Queued fake pack members due now enter after the dawn check (LT-63), so one due on
	# the dawn tick is dropped with the rest instead of entering and dissolving at once.
	_spawn.release_pack_members(true)
	# 9. Outcome.
	_check_outcome()


## LT-83: SpawnSystem.spawn_enemy (pack rolls, queue, ids).
func spawn_enemy(def_id: String, is_fake := false) -> int:
	return _spawn.spawn_enemy(def_id, is_fake)


## LT-63: true while a real pack member is queued and not entered yet.
func has_queued_real_members() -> bool:
	return _spawn.has_queued_real_members()


func apply_damage(enemy_id: int, amount: float, source: String, ignore_armor := false) -> float:
	return _combat.apply_damage(enemy_id, amount, source, ignore_armor)


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
	t.id = _ctx.next_id()
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
	_ally.dismiss_allies(t.id)
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
	_spawn.clear_pack_queue()
	for e in state.enemies:
		if e.is_live() and not e.is_fake:
			e.dead = true
			_emit(SimEvent.Type.DIED, e.id, {"source": "debug"})
	_spawn.compact()
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
## LT-81 forwarders: the relic / economy names now live in EconomySystem.
func relic_price(kind: String) -> int:
	return _economy.relic_price(kind)


func relics_value() -> int:
	return _economy.relics_value()


func can_sell_relics(kind := "") -> SimCommand.CommandResult:
	return _economy.can_sell_relics(kind)


func sell_relics(kind := "") -> SimCommand.CommandResult:
	return _economy.sell_relics(kind)


## LT-99 dawn phase hook: the wave director calls it when wave `n` is cleared, before it emits
## WAVE_CLEARED and resets night_luck. The actions run in this order (golden replay pins it);
## a new dawn action is one line here, no director edit. Returns the wave bonus paid.
func on_dawn(n: int) -> int:
	dissolve_fakes("wave_end")  # LT-12 §5: before the bonus, so BUILD starts with none
	settle_all_tokens()  # LT-27 §1.3: dawn credits real tokens, ghosts vanish
	var bonus := award_wave_bonus(n)
	award_wave_sanity()  # LT-10: regen.between_waves, also for the last wave
	auto_restore_sanity()  # LT-13: exit rule auto_restore; regen above is 0 in madness
	return bonus


## 1.0 without a WaveDirector (the director is the facade's, so it is passed in).
func early_night_luck() -> float:
	return _economy.early_night_luck(_spawner is WaveDirector)


func sell_refund(t: SimTower) -> int:
	return _economy.sell_refund(t)


func award_wave_bonus(wave_number: int) -> int:
	return _economy.award_wave_bonus(wave_number)


func settle_all_tokens() -> void:
	_economy.settle_all_tokens()


## Test-only forwarder (LT-81, like LT-80 Q1: relic_ui / ui_event_refresh tests stock relics).
func _add_relics(kind: String, delta: int, reason: String, token: int) -> void:
	_economy.add_relics(kind, delta, reason, token)


func auto_restore_sanity() -> float:
	return _sanity.auto_restore_sanity()


func restore_target() -> float:
	return _sanity.restore_target()


func reserve_of(t: SimTower) -> float:
	return _sanity.reserve_of(t)


func reserve_delta(def_id: String, from: TowerDef.Level, to: TowerDef.Level) -> float:
	return _sanity.reserve_delta(def_id, from, to)


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


func tower_by_id(id: int) -> SimTower:
	return _combat.tower_by_id(id)


func enemies_in_range(cell: Vector2i, range_cells: float) -> Array[SimEnemy]:
	return _combat.enemies_in_range(cell, range_cells)


func enemies_near(centre: Vector2, radius: float) -> Array[SimEnemy]:
	return _combat.enemies_near(centre, radius)


func enemy_by_id(id: int) -> SimEnemy:
	return _combat.enemy_by_id(id)


## Position in cell units, interpolated between the last two ticks by `alpha` (0..1).
func enemy_position(e: SimEnemy, alpha: float) -> Vector2:
	var d := roundi(lerpf(float(e.prev_distance), float(e.distance), alpha))
	return e.route.position_at(d)


func spawn_ally(tower: int, source: String, at: Vector2, hp: float, dps: float, speed: float,
		flying: bool, lifetime_ticks: int, leash: float) -> int:
	return _ally.spawn(tower, source, at, hp, dps, speed, flying, lifetime_ticks, leash)


func ally_by_id(id: int) -> SimAlly:
	return _ally.ally_by_id(id)


func allies_of(tower_id: int) -> Array[SimAlly]:
	return _ally.allies_of(tower_id)


func ally_position(a: SimAlly, alpha: float) -> Vector2:
	return _ally.ally_position(a, alpha)


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


## Test-only forwarder (LT-80, like Q1: madness_buff_test reads it; B8 revisits it).
func _madness_buff_blocked(e: SimEnemy) -> bool:
	return _sanity.madness_buff_blocked(e)


## Test-only forwarders (LT-82, like LT-80 Q1: dynamite / branch_effects tests).
func _push_back(e: SimEnemy, cells: float) -> void:
	_spawn.push_back(e, cells)


func _apply_bleed(e: SimEnemy, dps: float, seconds: float, source: String) -> void:
	_combat.apply_bleed(e, dps, seconds, source)


## LT-12 §5 (called by the wave director when a wave is cleared): SpawnSystem.dissolve_fakes.
func dissolve_fakes(reason: String) -> void:
	_spawn.dissolve_fakes(reason)


## The only way a scene may tell a fake (LT-12 §1): false unless debug_reveal_fakes.
func debug_is_fake(e: SimEnemy) -> bool:
	return debug_reveal_fakes and e.is_fake


func live_fakes_in_range(cell: Vector2i, range_cells: float) -> Array[SimEnemy]:
	return _combat.live_fakes_in_range(cell, range_cells)


func threshold() -> SanityConfig.Threshold:
	return _sanity.threshold()


## Lose first, so a leak that empties HP on the last enemy is a loss (§5).
func _check_outcome() -> void:
	if state.lighthouse_hp == 0:
		state.outcome = SimState.Outcome.LOST
		_emit(SimEvent.Type.OUTCOME, 0, {"result": "lost"})
		return
	if _spawner == null or not _spawner.is_exhausted() or _spawn.has_queued_real_members():
		return
	for e in state.enemies:
		if not e.is_fake:
			return
	state.outcome = SimState.Outcome.WON
	_emit(SimEvent.Type.OUTCOME, 0, {"result": "won"})
