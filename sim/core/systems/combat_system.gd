class_name CombatSystem
extends RefCounted
## LT-82 (B7 of LT-65 §3.1 Combat): tower fire, casts, summons, fused charges, auras, enemy
## status timers and the one armor rule (apply_damage) with its kill path. Owns e.hp,
## e.status, e.dead, t.cooldown_ticks, t.burst_index, t.locked_id, state.blasts and
## state.next_blast_id. Built once by the sim facade, which orders the step slots and
## forwards the public names. Peers by constructor: Light (power / interval mult), Sanity
## (threshold, kill regen), Economy (drop on kill), Spawn (push_back). AllySystem holds this system; summons
## reach it back only through Callables the facade sets (set_ally_hooks): a method Callable
## keeps the object id, not a reference, so there is no RefCounted cycle.


## SimEnemy.status timers that only count down to 0 and go (LT-29 pull, LT-51 banish);
## LT-106: the StatusRules table owns them.
const IMMUNITY_KEYS: PackedStringArray = StatusRules.COUNTDOWN_KEYS

var _ctx: SimContext
var _state: SimState
var _config: GameConfig
var _light: LightSystem
var _sanity: SanitySystem
var _economy: EconomySystem
var _spawn: SpawnSystem
## AllySystem.spawn / AllySystem.allies_of, set by the facade after both systems exist.
var _spawn_ally: Callable
var _allies_of: Callable
## LT-106: the trait API (on_damaged, on_death), set by the facade once (set_trait_host).
var _host: TraitHost


func _init(ctx: SimContext, light: LightSystem, sanity: SanitySystem,
		economy: EconomySystem, spawn: SpawnSystem) -> void:
	_ctx = ctx
	_state = ctx.state
	_config = ctx.config
	_light = light
	_sanity = sanity
	_economy = economy
	_spawn = spawn


## The facade wires the summon path once: `spawn` places a unit (AllySystem.spawn), `allies_of`
## lists a tower's live units (AllySystem.allies_of).
func set_ally_hooks(spawn: Callable, allies_of: Callable) -> void:
	_spawn_ally = spawn
	_allies_of = allies_of


## The facade wires the trait API once (LT-106).
func set_trait_host(host: TraitHost) -> void:
	_host = host


## The tower with this id, or null (also null once sold).
func tower_by_id(id: int) -> SimTower:
	for t in _state.towers:
		if t.id == id:
			return t
	return null


## Live enemies (fakes included) whose position is within `range_cells` of the centre of
## `cell`, boundary included; id order (§6 target query).
func enemies_in_range(cell: Vector2i, range_cells: float) -> Array[SimEnemy]:
	return enemies_near(_state.map.grid.centre(cell), range_cells)


## Live enemies (fakes included) whose position is within `radius` cells of `centre`
## (cell units), boundary included; id order.
func enemies_near(centre: Vector2, radius: float) -> Array[SimEnemy]:
	var r2 := radius * radius
	var out: Array[SimEnemy] = []
	for e in _state.enemies:
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
	for e in _state.enemies:
		if e.id == id:
			return e
	return null


## Sim only (LT-13 madness "hit a fake" branch): live fakes in range, id order.
func live_fakes_in_range(cell: Vector2i, range_cells: float) -> Array[SimEnemy]:
	var out: Array[SimEnemy] = []
	for e in enemies_in_range(cell, range_cells):
		if e.is_fake:
			out.append(e)
	return out


## The one armor rule for every damage source (§3.4). Returns the hp actually removed
## (capped at the remaining hp, so overkill is not counted); 0 for an unknown, dead or
## leaked enemy, or once the outcome is set (then nothing changes and no event is emitted).
## A killed enemy emits DIED and is removed at the end of the current/next tick.
## `ignore_armor` (LT-48 P7): the hit skips armor; damage_taken_mult still applies.
## LT-106 T4: a survivor runs its on_damaged trait hooks, a killed enemy its on_death hooks
## after the kill hook (token drop first); one int test per hit when it has none. A hook
## must not damage its own enemy (no re-entry).
func apply_damage(enemy_id: int, amount: float, source: String, ignore_armor := false) -> float:
	if _state.outcome != SimState.Outcome.NONE:
		return 0.0
	var e := enemy_by_id(enemy_id)
	if e == null or not e.is_live():
		return 0.0
	# LT-48 (P7): an ignore_armor hit skips the whole armor (base and bonus).
	var armor := 0.0 if ignore_armor else maxf(0.0, e.def.armor + e.armor_bonus)
	var taken := maxf(0.0, amount - armor) * e.damage_taken_mult
	var removed := minf(taken, e.hp)
	e.hp -= taken
	var d := e.def
	if e.hp <= 0.0:
		e.dead = true
		_ctx.emit(SimEvent.Type.DIED, e.id, {"source": source})
		_on_enemy_killed(e, source)
		if d.hooks & EnemyTrait.ON_DEATH:
			for i in d.hook_traits.size():
				var tr := d.hook_traits[i]
				if tr.hooks() & EnemyTrait.ON_DEATH:
					tr.on_death(_host, e, d.hook_params[i], source)
	elif d.hooks & EnemyTrait.ON_DAMAGED:
		for i in d.hook_traits.size():
			var tr := d.hook_traits[i]
			if tr.hooks() & EnemyTrait.ON_DAMAGED:
				tr.on_damaged(_host, e, d.hook_params[i], taken, source)
	return removed


## Kill hook, called once per enemy when apply_damage kills it. Every kill, real or fake,
## drops one relic token (LT-27 §1.3); only a real one is ever credited. `source` is the
## damage source; for towers it is the tower def id. A real enemy killed by a mundane tower
## restores regen.mundane_kill sanity (only damage-dealing levels fire, so a tower kill is
## always by a damage level).
func _on_enemy_killed(e: SimEnemy, source: String) -> void:
	_economy.drop_token(e)
	if e.is_fake:
		return
	var tower_def: TowerDef = _config.towers.get(source)
	if tower_def != null and tower_def.kind == "mundane":
		_sanity.add(_config.sanity.regen_mundane_kill, "mundane_kill", e.id)


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
## occult auras only); a lit or shadowed occult aura works at t.power_mult strength (the
## LT-105 channel). LT-105 D6: a disabled aura applies nothing.
func apply_auras() -> void:
	var auras: Array[SimTower] = []
	for t in _state.towers:
		var s := t.stats()
		if t.disabled:
			continue  # LT-105 D6: a disabled aura applies nothing
		if not s.acts() and (s.effects.has("slow") or s.effects.has("damage_taken_multiplier")
				or s.effects.has("strip_armor") or s.effects.get("reveal_fakes", 0.0) > 0.0):
			auras.append(t)
	if auras.is_empty():
		return
	for e in _state.enemies:
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
			if not LightRules.covers(_config.map.grid, t.cell, s.range_cells, p):
				continue
			inside = true
			var t_slow: float = s.effects.get("slow", 0.0)
			var t_mult: float = s.effects.get("damage_taken_multiplier", 1.0)
			var t_strip: float = s.effects.get("strip_armor", 0.0)
			var pm := t.power_mult  # LT-105: the modifier channel (light wrote it in slot 2)
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
func fire_towers() -> void:
	for t in _state.towers:
		if t.cooldown_ticks > 0:
			t.cooldown_ticks -= 1
			if t.cooldown_ticks > 0:
				continue
		# LT-105 D6 (Q2): a disabled tower keeps counting its cooldown but does nothing else
		# (no target, no RNG draw, no burst / beam lock change).
		if t.disabled:
			continue
		var s := t.stats()
		var mode := s.mode()  # LT-103 §2.2: one precedence (EffectCatalog.Mode)
		if mode == EffectCatalog.Mode.AURA:
			continue
		if mode == EffectCatalog.Mode.BANISH:
			_cast_banish(t, s)  # LT-51: its own cast; no miss, crit or shot shape
			continue
		if mode == EffectCatalog.Mode.SUMMON:
			_summon(t, s)  # LT-52: allied units do the damage (slot 5 _ally_combat)
			continue
		var in_range := _candidates(t, s)
		var target: SimEnemy = null
		# A burst below 1 target (0 < n < 1) aims like a single shot.
		var burst := int(s.effects.get("burst_targets", 0.0)) if mode == EffectCatalog.Mode.BURST \
			else 0
		if burst > 0:
			# LT-29 §1.2: round robin over the top `burst` by target_priority; a miss moves on
			# too. The ranked set may shrink between shots: nothing is locked.
			var ranked := _ranked_targets(t, in_range, burst)
			if not ranked.is_empty():
				var m := ranked.size()
				target = ranked[t.burst_index % m]
				t.burst_index = (t.burst_index % m + 1) % m
		elif mode == EffectCatalog.Mode.BEAM:
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
		var factor := TowerRules.shot_factor(s, _config, _state.sanity)
		# LT-30 §2 / LT-70 §2.3: lit x0.7 / shadowed x1.15 (occult), before the madness x2.
		var damage := TowerRules.shot_damage(s, factor, t.power_mult)
		var astray := ""
		if s.madness_affected and _state.sanity_state == SimState.SanityState.MADNESS:
			damage *= _config.sanity.madness.damage_multiplier
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
				target = pool[_ctx.randi_range(SimRng.Stream.MADNESS, 0, pool.size() - 1)]
		var pierce: float = s.effects.get("pierce", 0.0)
		var aoe: float = s.effects.get("aoe_radius", 0.0)
		var fuse_ticks := 0
		if mode == EffectCatalog.Mode.FUSE:
			fuse_ticks = maxi(1, SimTime.ticks(float(s.effects["fuse_seconds"])))
		var hits: Array[SimEnemy] = [target]
		var to := target.route.position_at(target.distance)
		if fuse_ticks > 0:
			# LT-47 (Q5 "lead"): thrown where the target will be after the fuse at its speed
			# this tick; who is hit is decided when it explodes (settle_blasts).
			to = _lead_point(target, fuse_ticks)
			hits = []
		elif mode == EffectCatalog.Mode.LINE:
			to = _line_end(t.centre(), to, s.range_cells)
			hits = _ground_filter(t, _line_hits(t.centre(), to, pierce * 0.5, target))
		elif mode == EffectCatalog.Mode.BLAST:
			hits = _ground_filter(t, enemies_near(to, aoe))
		# LT-12 §4: a mundane shot may miss as a whole (Q3: occult towers never miss).
		# LT-30: a lit mundane tower with ignore_miss never misses (no COMBAT draw).
		# LT-70 §2.3: a shadowed one adds shadow.mundane.miss_chance_add to the chance.
		# LT-105: both from the modifier channel (ignore_miss wins: no COMBAT draw).
		var miss := t.def.kind == "mundane" and not t.ignore_miss and _roll_miss(t.miss_add)
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
		if mode == EffectCatalog.Mode.BEAM:
			shot["beam"] = true  # LT-50: the board holds one beam per tower
			shot["sanity_factor"] = factor
		if fuse_ticks > 0:
			# LT-47: a dud (a Fraying miss) is thrown but never explodes; blast 0.
			shot["fuse"] = true
			shot["detonate_tick"] = _state.tick + fuse_ticks
			shot["radius"] = aoe
			shot["blast"] = 0 if dud else _queue_blast(t, s, to, damage, fuse_ticks)
		_ctx.emit(SimEvent.Type.SHOT, t.id, shot)
		var no_armor: bool = s.effects.get("ignore_armor", 0.0) > 0.0
		for e in hits:
			apply_damage(e.id, damage, t.def.id, no_armor)
		if fuse_ticks == 0:
			_on_hit_effects(t, s, target, hits, shot)
		# LT-30 / LT-70 §2.3: lit x0.8 / shadowed x1.25 (mundane), decided at the shot.
		var interval := TowerRules.fire_interval(s, t.interval_mult)
		t.cooldown_ticks = TowerRules.cooldown_ticks(interval)


## LT-51 (§2.2, Q4): a Silver Key cast. Picks (by target_priority) up to banish_targets of
## the tower's candidates that may be banished (_banishable), moves each back banish_cells
## along its own route (P5 push_back, the Chain pull's rewind; x t.power_mult: lit x0.7,
## LT-70 shadowed x1.15) and gives it banish_immune_seconds of banish immunity (its own status key:
## pull immunity does not block a banish, nor the reverse). A level with damage (Corrupted)
## then hits each one (armor applies; x t.power_mult, x the madness multiplier).
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
	var power := t.power_mult  # LT-105: the modifier channel
	var damage := TowerRules.shot_damage(s, 1.0, power)
	var astray := ""
	if s.madness_affected and _state.sanity_state == SimState.SanityState.MADNESS:
		damage *= _config.sanity.madness.damage_multiplier
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
		while picks.size() < n and not pool.is_empty():
			picks.append(pool.pop_at(_ctx.randi_range(SimRng.Stream.MADNESS, 0, pool.size() - 1)))
	var cells: float = s.effects.get("banish_cells", 0.0) * power
	var immune := SimTime.ticks(float(s.effects.get("banish_immune_seconds", 0.0)))
	for e in picks:
		var from := e.route.position_at(e.distance)
		_spawn.push_back(e, cells)
		if immune > 0:
			e.status["banish_immune_ticks"] = immune
		var shot := {"def": t.def.id, "target": e.id, "hits": [e.id], "banish": true,
			"from": from, "to": e.route.position_at(e.distance), "miss": false}
		if astray != "":
			shot["astray"] = true
		_ctx.emit(SimEvent.Type.SHOT, t.id, shot)
	if damage > 0.0:
		for e in picks:
			apply_damage(e.id, damage, t.def.id)
	t.cooldown_ticks = TowerRules.cooldown_ticks(s.fire_interval)


## LT-52 (§2.2): a Summoning Circle with fewer than summon_max live units summons one at
## its centre (spawn_ally: leash Level.summon_leash, default range + 1; hold distance
## Level.summon_contact, LT-103 Q2; lifetime summon_lifetime) and spends the
## cooldown. At its maximum it does not summon and stays ready, so a unit gone frees a
## slot at once. A circle lit (or, LT-70, shadowed) at summon time gives the unit
## summon_dps x t.power_mult for its whole life (§3 "lit at summon time"); madness is
## applied live by _ally_combat.
## No miss, crit or astray (a unit bites what it holds).
func _summon(t: SimTower, s: TowerDef.Level) -> void:
	if _allies_of.call(t.id).size() >= s.summon_max():
		return
	var dps := TowerRules.unit_dps(s, t.power_mult)  # LT-105: the modifier channel
	var id: int = _spawn_ally.call(t.id, t.def.id, t.centre(),
		s.effects.get("summon_hp", 0.0), dps, s.effects.get("summon_speed", 0.0), s.summon_flying(),
		SimTime.ticks(float(s.effects.get("summon_lifetime", 0.0))), s.summon_leash(),
		s.summon_contact())
	if id != 0:
		t.cooldown_ticks = TowerRules.cooldown_ticks(s.fire_interval)


## LT-51 (Q4 "HP cap per level"): those of `enemies` a gate with stats `s` may banish:
## base_max_hp <= banish_max_hp (Dagon's is above every cap; LT-111: base HP, before the
## wave's hp_mult) and no banish immunity.
func _banishable(s: TowerDef.Level, enemies: Array[SimEnemy]) -> Array[SimEnemy]:
	var cap: float = s.effects.get("banish_max_hp", 0.0)
	var out: Array[SimEnemy] = []
	for e in enemies:
		if e.base_max_hp <= cap and int(e.status.get("banish_immune_ticks", 0)) <= 0:
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
	b.id = _state.next_blast_id
	_state.next_blast_id += 1
	b.tower = t.id
	b.source = t.def.id
	b.at = at
	b.throw_tick = _state.tick
	b.detonate_tick = _state.tick + fuse_ticks
	b.damage = damage
	b.radius = float(s.effects.get("aoe_radius", 0.0))
	b.ground_only = t.def.ground_only()
	b.effects = s.effects
	_state.blasts.append(b)
	return b.id


## Slot 5b (LT-47 P2): every charge whose detonate_tick has come explodes, in id order:
## BLAST {tower, def, at, radius, hits}, then its damage to each live enemy (fakes too;
## flyers only if not ground_only) within `radius` of `at` now, credited to its def id, then
## its on-hit bleed. Enemies slowed, sped up or pushed back since the throw may be outside.
func settle_blasts() -> void:
	if _state.blasts.is_empty():
		return
	var left: Array[SimBlast] = []
	for b in _state.blasts:
		if b.detonate_tick > _state.tick:
			left.append(b)
			continue
		var hits := enemies_near(b.at, b.radius)
		if b.ground_only:
			hits = _ground_only(hits)
		var ids: Array[int] = []
		for e in hits:
			ids.append(e.id)
		_ctx.emit(SimEvent.Type.BLAST, b.id, {"tower": b.tower, "def": b.source, "at": b.at,
			"radius": b.radius, "hits": ids})
		var no_armor: bool = b.effects.get("ignore_armor", 0.0) > 0.0
		for e in hits:
			apply_damage(e.id, b.damage, b.source, no_armor)
		_apply_bleed_hits(hits, b.effects, b.source)
	_state.blasts = left


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
	for e in _state.enemies:
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


## Slot 5, after a shot's damage (LT-29 §1.3-1.4): bleed on every hit still live; the chain
## pull on the shot's primary target only (Q4), if it was hit, is still live, has base_max_hp
## <= pull_max_hp (0 = no cap; LT-111: base HP, before the wave's hp_mult) and no pull immunity. SHOT was emitted before the damage (the
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
	if hits.has(target) and target.is_live() and (cap <= 0.0 or target.base_max_hp <= cap) \
			and int(target.status.get("pull_immune_ticks", 0)) <= 0:
		_spawn.push_back(target, pull)
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
				apply_bleed(e, bleed_dps, bleed_seconds, source)


## LT-29 §1.3 (shared with later bleeders): refresh, never stack. The duration restarts
## (max of what is left and `seconds`), the higher dps wins (its source too; a tie -> the
## newest), and a new bleed's first pulse comes one second after the hit.
func apply_bleed(e: SimEnemy, dps: float, seconds: float, source: String) -> void:
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
func tick_statuses() -> void:
	for e in _state.enemies:
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


## LT-12 §4 miss hook: one roll on COMBAT against the state's miss_chance plus `extra`
## (LT-70: a shadowed mundane shot), capped at 1; no roll (and no COMBAT draw) when the
## chance is 0, so Lucid/Whispers consume COMBAT as before for unshadowed shots.
func _roll_miss(extra := 0.0) -> bool:
	var chance := minf(1.0, _sanity.threshold().miss_chance + extra)
	if chance <= 0.0:
		return false
	return _ctx.randf(SimRng.Stream.COMBAT) < chance


## LT-29 §1.1 crit hook: one roll on CRIT against `chance`; no roll (no CRIT draw) at 0.
func _roll_crit(chance: float) -> bool:
	if chance <= 0.0:
		return false
	return _ctx.randf(SimRng.Stream.CRIT) < chance


## LT-13 shot_split: one MADNESS roll per astray shot -> "real" | "fake" | "empty".
func _roll_astray() -> String:
	var m := _config.sanity.madness
	var r := _ctx.randf(SimRng.Stream.MADNESS)
	if r < m.shot_real:
		return "real"
	if r < m.shot_real + m.shot_fake:
		return "fake"
	return "empty"
