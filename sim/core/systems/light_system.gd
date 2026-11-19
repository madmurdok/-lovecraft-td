class_name LightSystem
extends RefCounted
## LT-80 (LT-65 §3.1, B5): the lighthouse beam, the flare and lamp oil. Owns
## lighthouse_level, beam_*, prev_beam_*, flare_*, oil and the light flags of towers
## (lit, shadowed) and enemies (lit), and the lighthouse / oil / flare commands whole.
## Built once by the sim facade, which orders the step slots and forwards the public names.
## Gold goes through EconomySystem; events and the command log through SimContext.

## _light_flags bits (LT-76): the net lit / shadowed state of a point.
const LIT_FLAG := 1
const SHADOWED_FLAG := 2

var _ctx: SimContext
var _state: SimState
var _config: GameConfig
var _economy: EconomySystem


func _init(ctx: SimContext, economy: EconomySystem) -> void:
	_ctx = ctx
	_state = ctx.state
	_config = ctx.config
	_economy = economy
	if _config.economy.oil != null:
		_state.oil = _config.economy.oil.start
	_start_beam()


## LT-30 (LT-26 §1.2): beams of the current lighthouse level (1, 2, 4 or 8).
func beam_count() -> int:
	return _config.economy.beam.levels[_state.lighthouse_level].beams


## Money for the next lighthouse level; 0 at the top level.
func lighthouse_upgrade_cost() -> int:
	var levels := _config.economy.beam.levels
	if _state.lighthouse_level + 1 >= levels.size():
		return 0
	return levels[_state.lighthouse_level + 1].upgrade_cost


## Whether upgrade_lighthouse() would be applied now; OK or the first failing reason, in
## this order: OUTCOME_REACHED, MAX_LEVEL, NOT_BUILD_PHASE (at night, _day_only),
## NOT_ENOUGH_GOLD. Changes nothing.
func can_upgrade_lighthouse() -> SimCommand.CommandResult:
	if _state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	if _state.lighthouse_level + 1 >= _config.economy.beam.levels.size():
		return SimCommand.CommandResult.MAX_LEVEL
	var day := _ctx.day_only()
	if day != SimCommand.CommandResult.OK:
		return day
	if _state.gold < lighthouse_upgrade_cost():
		return SimCommand.CommandResult.NOT_ENOUGH_GOLD
	return SimCommand.CommandResult.OK


## Player command (LT-30 §0, LT-27 D7): raises the lighthouse one level for money, by day
## only. The new beams light from the next night tick on, evenly spaced from the current
## base direction. Emits LIGHTHOUSE_UPGRADED {level, beams, cost} (id 0), then GOLD_CHANGED
## {reason: "lighthouse"}. No refund: the lighthouse is never sold.
func upgrade_lighthouse() -> SimCommand.CommandResult:
	var result := can_upgrade_lighthouse()
	if result != SimCommand.CommandResult.OK:
		return result
	var cost := lighthouse_upgrade_cost()
	_state.lighthouse_level += 1
	_ctx.log_command([_state.tick, "upgrade_lighthouse"])
	_ctx.emit(SimEvent.Type.LIGHTHOUSE_UPGRADED, 0, {"level": _state.lighthouse_level,
		"beams": beam_count(), "cost": cost})
	_economy.add_gold(-cost, "lighthouse", 0)
	return SimCommand.CommandResult.OK


## Whether buy_oil() would be applied now; OK or the first failing reason, in this order
## (LT-30 §1.2): OUTCOME_REACHED, NO_FLARE (no lighthouse.oil block), NOT_BUILD_PHASE (at
## night, _day_only), OIL_FULL, NOT_ENOUGH_GOLD. Changes nothing.
func can_buy_oil() -> SimCommand.CommandResult:
	if _state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	var oil := _config.economy.oil
	if oil == null:
		return SimCommand.CommandResult.NO_FLARE
	var day := _ctx.day_only()
	if day != SimCommand.CommandResult.OK:
		return day
	if _state.oil >= oil.cap:
		return SimCommand.CommandResult.OIL_FULL
	if _state.gold < oil.price:
		return SimCommand.CommandResult.NOT_ENOUGH_GOLD
	return SimCommand.CommandResult.OK


## Player command (LT-30 §1.2): buys one unit of lamp oil for oil.price money, by day only.
## Emits OIL_CHANGED {delta: 1, oil, reason: "buy"}, then GOLD_CHANGED {reason: "oil"}.
## Oil stays across nights and is never sold back.
func buy_oil() -> SimCommand.CommandResult:
	var result := can_buy_oil()
	if result != SimCommand.CommandResult.OK:
		return result
	_ctx.log_command([_state.tick, "buy_oil"])
	_add_oil(1, "buy")
	_economy.add_gold(-_config.economy.oil.price, "oil", 0)
	return SimCommand.CommandResult.OK


## Whether fire_flare() would be applied now; OK or the first failing reason, in this order
## (LT-30 §1.1): OUTCOME_REACHED, NO_FLARE (no lighthouse.flare block), NOT_NIGHT (phase
## BUILD or DONE; NONE allowed, like _day_only), ON_COOLDOWN, NO_OIL. Changes nothing.
func can_fire_flare() -> SimCommand.CommandResult:
	if _state.outcome != SimState.Outcome.NONE:
		return SimCommand.CommandResult.OUTCOME_REACHED
	var flare := _config.economy.flare
	if flare == null:
		return SimCommand.CommandResult.NO_FLARE
	if not beam_on():
		return SimCommand.CommandResult.NOT_NIGHT
	if _state.flare_cooldown_ticks > 0:
		return SimCommand.CommandResult.ON_COOLDOWN
	if _state.oil < flare.cost_oil:
		return SimCommand.CommandResult.NO_OIL
	return SimCommand.CommandResult.OK


## Player command (LT-30 §1.1, LT-69 whole map): for flare_seconds() every tower and enemy
## on the map is lit (beams keep turning and keep their width),
## and every lit enemy moves at x enemy_speed_mult; the cooldown runs from now. Emits FLARE_FIRED {ticks, cooldown}
## (id 0), then OIL_CHANGED {delta: -cost_oil, oil, reason: "flare"}.
func fire_flare() -> SimCommand.CommandResult:
	var result := can_fire_flare()
	if result != SimCommand.CommandResult.OK:
		return result
	var flare := _config.economy.flare
	_state.flare_ticks_left = _flare_ticks()
	_state.flare_cooldown_ticks = maxi(1, SimTime.ticks(flare.cooldown_seconds))
	_ctx.log_command([_state.tick, "fire_flare"])
	_ctx.emit(SimEvent.Type.FLARE_FIRED, 0, {"ticks": _state.flare_ticks_left,
		"cooldown": _state.flare_cooldown_ticks})
	_add_oil(-flare.cost_oil, "flare")
	return SimCommand.CommandResult.OK


## Render only (LT-30 §3.2): the direction of every beam, interpolated between the previous
## and the current tick's base direction by `alpha` (0..1) and normalised; empty by day.
## Trig is fine in the render; the sim never reads this.
func beam_directions(alpha: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not beam_on():
		return out
	var x := lerpf(_state.prev_beam_dx, _state.beam_dx, alpha)
	var y := lerpf(_state.prev_beam_dy, _state.beam_dy, alpha)
	var n := sqrt(x * x + y * y)
	if n <= 0.0:
		x = _state.beam_dx
		y = _state.beam_dy
		n = 1.0
	for d: Array in _dirs_of(x / n, y / n, beam_count()):
		out.append(Vector2(d[0], d[1]))
	return out


## LT-30 §1.2: the one writer of _state.oil (buy_oil +1, fire_flare -cost_oil); emits
## OIL_CHANGED {delta, oil, reason} (id 0). Callers keep it within 0..oil.cap.
func _add_oil(delta: int, reason: String) -> void:
	if delta == 0:
		return
	_state.oil += delta
	_ctx.emit(SimEvent.Type.OIL_CHANGED, 0, {"delta": delta, "oil": _state.oil, "reason": reason})


## LT-30 Q3 "Только ночью": the beam turns and lights only at night (phase WAVE) or without
## a WaveDirector (phase NONE, unit tests). By day (BUILD) and after the last wave (DONE)
## it is dark: nothing lit, direction held.
func beam_on() -> bool:
	return _state.phase != SimState.Phase.BUILD and _state.phase != SimState.Phase.DONE


## A flare burns this tick (LT-30 §1.1).
func flaring() -> bool:
	return _state.flare_ticks_left > 0 and _config.economy.flare != null


## LT-69: how long a flare fired now burns, in seconds: flare.seconds[lighthouse_level];
## 0 without a flare block.
func flare_seconds() -> float:
	var flare := _config.economy.flare
	if flare == null or flare.seconds.is_empty():
		return 0.0
	return flare.seconds[mini(_state.lighthouse_level, flare.seconds.size() - 1)]


## LT-76: how many ticks a flare fired now burns: flare_seconds() in whole ticks, at least 1.
func _flare_ticks() -> int:
	return maxi(1, SimTime.ticks(flare_seconds()))


## LT-76 (LT-65 §3.2) read-only: the flare burning now as {left_ticks, total_ticks}
## (total: the burn of a flare fired at the current level, never below left); {0, 0} when
## none burns.
func flare_burn() -> Dictionary:
	if not flaring():
		return {"left_ticks": 0, "total_ticks": 0}
	var left := _state.flare_ticks_left
	return {"left_ticks": left, "total_ticks": maxi(left, _flare_ticks())}


## LT-30 §1.2: the lamp oil cap (oil.cap); 0 without an oil block.
func oil_cap() -> int:
	var oil := _config.economy.oil
	return oil.cap if oil != null else 0


## LT-30 §1.1: the oil one flare burns (flare.cost_oil); 0 without a flare block.
func flare_cost_oil() -> int:
	var flare := _config.economy.flare
	return flare.cost_oil if flare != null else 0


## LT-57 (LT-76: moved from Game.flare_oil_to_buy): the oil units one "buy oil for a flare"
## click tries, by day: min(flare.cost_oil, cap - oil), 1 per click without a flare block;
## 0 without an oil block or with a full tank.
func oil_for_flare() -> int:
	var eco := _config.economy
	if eco.oil == null:
		return 0
	var want := eco.flare.cost_oil if eco.flare != null else 1
	return clampi(eco.oil.cap - _state.oil, 0, want)


## Lit now by a beam (dirs, half-width k) or, while a flare burns, anywhere (LT-69).
func _lit_now(dirs: Array, k: float, px: float, py: float) -> bool:
	return flaring() or _lit_by(dirs, k, px, py)


## Slot 2, first (LT-30 §3.1): saves prev_beam_*, turns the base direction (night only; a
## flare no longer holds it, LT-57), then sets the net `lit` / `shadowed` of every tower
## (centre; TOWER_LIT {lit, shadowed} when either flips, id order) and `lit` of every live
## enemy (route position at the start of the tick, as auras). LT-70 §2.1: a tower is lit
## by a beam, the flare (LT-69) or another casts_light tower's radius, shadowed by another
## casts_shadow tower's radius; both at once cancel to neither. An enemy is lit by a beam,
## the flare or a casts_light radius; enemies have no shadow. By day every flag is false.
func update_beam() -> void:
	_state.prev_beam_dx = _state.beam_dx
	_state.prev_beam_dy = _state.beam_dy
	var on := beam_on()
	if on:
		_turn_beam()
	var dirs := _beam_dirs() if on else []
	var k := _config.economy.beam.half_width_ratio
	var casters: Array[SimTower] = []
	if on:
		casters = _casters()
	for t in _state.towers:
		var flags := _light_flags(t.centre(), t.id, on, dirs, k, casters)
		var lit := (flags & LIT_FLAG) != 0
		var shadowed := (flags & SHADOWED_FLAG) != 0
		if lit != t.lit or shadowed != t.shadowed:
			t.lit = lit
			t.shadowed = shadowed
			_ctx.emit(SimEvent.Type.TOWER_LIT, t.id, {"lit": lit, "shadowed": shadowed})
	if not on:
		return
	for e in _state.enemies:
		if not e.is_live():
			continue
		var p := e.route.position_at(e.distance)
		e.lit = _lit_now(dirs, k, p.x, p.y) or _in_cast(p, "casts_light", -1, casters)


## LT-70 §2.1: the net light of the point p (a tower centre; `skip_id` is that tower,
## -1 for none) as LIT_FLAG / SHADOWED_FLAG bits: lit by a beam, the flare or another
## casts_light radius, shadowed by another casts_shadow radius; both at once cancel to
## neither; 0 when `on` is false (day). `dirs`, `k` and `casters` as update_beam reads them.
func _light_flags(p: Vector2, skip_id: int, on: bool, dirs: Array, k: float,
		casters: Array[SimTower]) -> int:
	var light_any := on and (_lit_now(dirs, k, p.x, p.y)
		or _in_cast(p, "casts_light", skip_id, casters))
	var shadow_any := on and _in_cast(p, "casts_shadow", skip_id, casters)
	var flags := 0
	if light_any and not shadow_any:
		flags |= LIT_FLAG
	if shadow_any and not light_any:
		flags |= SHADOWED_FLAG
	return flags


## LT-76 (LT-65 §3.2) read-only query, changes nothing: the light at the point p (cell units)
## now, for a tower centre (`skip_id` its id: a caster does not light or shadow itself) or
## any point (-1): {beam (bool: a beam or the flare covers it, night only), light_casters /
## shadow_casters (int: casts_light / casts_shadow towers other than skip_id whose radius
## covers it, by day too), lit, shadowed (bool: the net state update_beam would give a
## tower there with the beam where it is now)}.
func light_at(p: Vector2, skip_id := -1) -> Dictionary:
	var on := beam_on()
	var dirs := _beam_dirs() if on else []
	var k := _config.economy.beam.half_width_ratio
	var casters := _casters()
	var flags := _light_flags(p, skip_id, on, dirs, k, casters)
	return {
		"beam": on and _lit_now(dirs, k, p.x, p.y),
		"light_casters": _cast_count(p, "casts_light", skip_id, casters),
		"shadow_casters": _cast_count(p, "casts_shadow", skip_id, casters),
		"lit": (flags & LIT_FLAG) != 0,
		"shadowed": (flags & SHADOWED_FLAG) != 0,
	}


## LT-70 §2.2: the towers whose current level casts light or shadow, in id order.
func _casters() -> Array[SimTower]:
	var out: Array[SimTower] = []
	for t in _state.towers:
		var s := t.stats()
		if s.casts_light() or s.casts_shadow():
			out.append(t)
	return out


## LT-70 §2.1: true when some caster other than `skip_id` whose current level has
## effects[key] > 0 covers the point p (in_cast_radius of its centre and range).
func _in_cast(p: Vector2, key: String, skip_id: int, casters: Array[SimTower]) -> bool:
	for o in casters:
		if o.id == skip_id:
			continue
		var s := o.stats()
		if s.effects.get(key, 0.0) > 0.0 \
				and LightRules.covers(_config.map.grid, o.cell, s.range_cells, p):
			return true
	return false


## How many casters other than `skip_id` with effects[key] > 0 cover the point p (_in_cast
## counted).
func _cast_count(p: Vector2, key: String, skip_id: int, casters: Array[SimTower]) -> int:
	var n := 0
	for o in casters:
		if o.id == skip_id:
			continue
		var s := o.stats()
		if s.effects.get(key, 0.0) > 0.0 \
				and LightRules.covers(_config.map.grid, o.cell, s.range_cells, p):
			n += 1
	return n


## LT-30 §2, LT-70 §2.3: an occult tower's damage / aura / banish / summon multiplier from
## its net state: beam.occult_power_mult lit, shadow.occult_power_mult shadowed (1.0 without
## a shadow block), else 1.0. Mundane towers: 1.0.
func power_mult(t: SimTower) -> float:
	return TowerRules.power_mult(t.def.kind, _config, t.lit, t.shadowed)


## LT-30 §2, LT-70 §2.3: a mundane tower's fire interval multiplier from its net state:
## beam.mundane_fire_interval_mult lit, shadow.mundane_fire_interval_mult shadowed (1.0
## without a shadow block), else 1.0. Occult towers: 1.0.
func interval_mult(t: SimTower) -> float:
	return TowerRules.interval_mult(t.def.kind, _config, t.lit, t.shadowed)


## Run start: "rotate" points the base direction left (SimState default); "sweep" starts at
## sweep_edges[0] (normalised), so the beam begins inside its arc and _turn_beam's edge
## checks reverse it once per edge (LT-30 review F1).
func _start_beam() -> void:
	var b := _config.economy.beam
	if b.pattern != "sweep" or b.sweep_edges.size() != 2:
		return
	var x: float = b.sweep_edges[0][0]
	var y: float = b.sweep_edges[0][1]
	var n := sqrt(x * x + y * y)
	_state.beam_dx = x / n
	_state.beam_dy = y / n
	_state.prev_beam_dx = _state.beam_dx
	_state.prev_beam_dy = _state.beam_dy


## Rotates the base direction by the exact rational rotation of beam.turn_t (x beam_sign):
## c = (1 - t²)/(1 + t²), s = 2t/(1 + t²), then renormalises. "sweep" reverses beam_sign once
## the direction passes the arc edge it is heading for.
func _turn_beam() -> void:
	var b := _config.economy.beam
	var t := b.turn_t * _state.beam_sign
	if t == 0.0:
		return
	var q := 1.0 + t * t
	var c := (1.0 - t * t) / q
	var s := 2.0 * t / q
	var x := _state.beam_dx * c - _state.beam_dy * s
	var y := _state.beam_dx * s + _state.beam_dy * c
	var n := sqrt(x * x + y * y)
	_state.beam_dx = x / n
	_state.beam_dy = y / n
	if b.pattern == "sweep" and b.sweep_edges.size() == 2:
		var edge: Array = b.sweep_edges[1] if t > 0.0 else b.sweep_edges[0]
		var cross: float = edge[0] * _state.beam_dy - edge[1] * _state.beam_dx
		if (t > 0.0 and cross > 0.0) or (t < 0.0 and cross < 0.0):
			_state.beam_sign = -_state.beam_sign


## Every beam's direction as [x, y] pairs: the base direction rotated by i x 360° / count.
func _beam_dirs() -> Array:
	return _dirs_of(_state.beam_dx, _state.beam_dy, beam_count())


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
## now (LT-26 §1.1) or anywhere while a flare burns (LT-69). False by day.
func is_lit(px: float, py: float) -> bool:
	return beam_on() and _lit_now(_beam_dirs(), _config.economy.beam.half_width_ratio, px, py)


## LT-26 §1.1 lit test against the lighthouse cell centre L, v = p - L: |v|² <= reach²,
## v·d > 0 and cross(v, d)² <= k² (v·d)² for some beam d. Overlaps do not stack.
func _lit_by(dirs: Array, k: float, px: float, py: float) -> bool:
	var lh := _config.map.grid.centre(_config.map.lighthouse)
	var vx := px - lh.x
	var vy := py - lh.y
	var reach := _config.economy.beam.reach_cells
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
## (fakes alike; while it burns every live enemy is lit, LT-69) gets speed_mult x
## flare.enemy_speed_mult this tick. The passive beam never
## slows.
func apply_flare_slow() -> void:
	if not flaring():
		return
	var m := _config.economy.flare.enemy_speed_mult
	for e in _state.enemies:
		if e.is_live() and e.lit:
			e.speed_mult *= m


## Slot 2, last: the flare burns one tick less; the cooldown runs by day too.
func count_down_flare() -> void:
	if _state.flare_ticks_left > 0:
		_state.flare_ticks_left -= 1
	if _state.flare_cooldown_ticks > 0:
		_state.flare_cooldown_ticks -= 1
