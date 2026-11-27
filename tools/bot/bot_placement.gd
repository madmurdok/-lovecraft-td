extends RefCounted
## Placement scoring of the bot (LT-15, LT-70 §6; split out of tools/bot_runs.gd by LT-86):
## which free buildable cell a build of tower `id` goes to. Stateless: the config, the sim
## and the score cache (def id -> Array of [score, cell], best first) come from the caller.

## LT-70 §6: path cells one lit/shadowed tower is worth in `best_cell` (tunable).
const CAST_WEIGHT := 3
## LT-109: the score cache entry holding the route cells its scores were made for; a new
## route plan with other cells empties the cache (def ids are never this key).
const ROUTE_CELLS_KEY := "@route_cells"


## The free buildable cell with the most path cells within the tower's L1 range (and not
## inside its L1 min_range, LT-48), plus CAST_WEIGHT * cast_term; ties go to the lowest
## row-major cell. (-1, -1) when none is free. LT-109: the path cells are the next wave's
## planned routes (Simulation.planned_route_cells; map.path on a v1 map).
static func best_cell(cfg: GameConfig, sim: Simulation, id: String, score_cache: Dictionary) \
		-> Vector2i:
	var route_cells := sim.planned_route_cells()
	if not score_cache.has(ROUTE_CELLS_KEY) or score_cache[ROUTE_CELLS_KEY] != route_cells:
		score_cache.clear()
		score_cache[ROUTE_CELLS_KEY] = route_cells
	if not score_cache.has(id):
		var rng_cells: float = cfg.towers[id].levels[0].range_cells
		var min_cells: float = cfg.towers[id].levels[0].min_range
		var m := cfg.map
		var list: Array = []
		for c in m.grid.cells():
			if not m.is_buildable(c):
				continue
			var score := 0
			for p in route_cells:
				var d := m.grid.distance(c, p)
				if d <= rng_cells and d >= min_cells:
					score += 1
			if score > 0:
				list.append([score, c])
		list.sort_custom(func(a, b): return a[0] > b[0])  # stable enough: row-major kept
		score_cache[id] = list
	var best := Vector2i(-1, -1)
	var best_score := -1000000
	for e in score_cache[id]:
		if sim.state.tower_at.has(e[1]):
			continue
		var sc: int = e[0] + CAST_WEIGHT * cast_term(cfg, sim, id, e[1])
		if sc > best_score:  # strict: ties keep the cached order (path score, row-major)
			best_score = sc
			best = e[1]
	return best


## LT-70 §6: how many towers on the board a build of `id` at `cell` would put on the right
## side of the light/shadow. A caster (level 0 flags): +1 per firing tower in its radius that
## it helps (light: mundane, shadow: occult), -1 per one it hurts. A firing tower: +1 per
## caster in range that helps it, -1 per one that hurts it. Read from the config flags, so a
## variant without casts_* gives 0 and today's placement.
static func cast_term(cfg: GameConfig, sim: Simulation, id: String, cell: Vector2i) -> int:
	var def: TowerDef = cfg.towers[id]
	var s: TowerDef.Level = def.levels[0]
	var term := 0
	if s.casts_light() or s.casts_shadow():
		for o in sim.state.towers:
			var o_mundane: bool = o.def.kind == "mundane"
			if o.stats().acts() \
					and LightRules.covers(sim.config.map.grid, cell, s.range_cells, o.centre()):
				if s.casts_light():
					term += 1 if o_mundane else -1
				if s.casts_shadow():
					term += -1 if o_mundane else 1
	if s.acts():
		# Casters on the board covering the cell (LT-76: Simulation.light_at counts them).
		var light := sim.light_at(sim.config.map.grid.centre(cell))
		var sign_ := 1 if def.kind == "mundane" else -1
		term += sign_ * int(light["light_casters"])
		term -= sign_ * int(light["shadow_casters"])
	return term


## LT-70: true when a shadow caster on the board covers the centre of `cell`.
static func in_shadow_radius(sim: Simulation, cell: Vector2i) -> bool:
	return int(sim.light_at(sim.config.map.grid.centre(cell))["shadow_casters"]) > 0
