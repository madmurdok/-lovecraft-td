class_name ChokepointMetric
extends RefCounted
## LT-18 §8 chokepoint metric (LT-130 §4), pure static. Inputs: a GenMap, its route field
## with no barricades, MapGenParams thresholds. `routes` = one Array[Vector2i] per entry
## (entry ... L, from RouteField.route); "buildable" = ISLAND. Route positions are indexes
## into a route; lengths are in steps (route cells - 1). The only float is R in the range
## test within(): centre distance <= R, computed from integer cell deltas.

## detour_deltas value of a chokepoint whose barricade leaves no way around (a cut cell).
const CUT := -1
## detour_deltas value of a chokepoint C5 did not measure (it stopped at a qualifying one).
const SKIPPED := -2


## Per map: what the report tool prints (LT-18 §8 "report per map"). Per-route arrays are in
## entry order (GenMap.entries).
class MetricReport extends RefCounted:
	var passed := false
	var reasons := PackedStringArray()  ## failed rule codes, "C1" .. "C7" (S1/S2 from the generator)
	var details := PackedStringArray()  ## one "<code>: ..." line per finding
	var routes: Array = []  ## Array[Vector2i] per entry
	var lengths: Array[int] = []  ## steps per route
	var chokepoints: Array = []  ## Array[Vector2i] per route, in route order
	var spaced: Array[int] = []  ## C1: chokepoints spaced >= S apart, greedy from the entry
	var max_blind: Array[int] = []  ## C2
	var detour_deltas: Array = []  ## C5: Array[int] per route, aligned with chokepoints; CUT, SKIPPED
	var shared_share_pct := -1  ## C3: -1 = n/a (one entry)
	var last_shared := GenMap.NO_CELL  ## C3: the common last chokepoint before the floor

	func fail(code: String, detail: String) -> void:
		if not reasons.has(code):
			reasons.append(code)
		details.append("%s: %s" % [code, detail])


## The whole §8 check of `m`. `field` is the barricade-free route field (built when null).
## An entry the field does not reach is reported "S1" and the rules are skipped.
static func evaluate(m: GenMap, p: MapGenParams, field: RouteField = null) -> MetricReport:
	var rep := MetricReport.new()
	if field == null:
		field = RouteField.build(m)
	for e in m.entries:
		var r := field.route(e)
		if r.is_empty():
			rep.fail("S1", "entry %s does not reach L" % _txt(m, e))
		rep.routes.append(r)
	if not rep.reasons.is_empty() or m.entries.is_empty():
		if m.entries.is_empty():
			rep.fail("S2", "no entry")
		return rep
	var discs := disc_table(m, rep.routes, p.tower_range)
	var chokes_pos: Array = []
	var c5_cache := {}
	for ri in rep.routes.size():
		var r: Array[Vector2i] = rep.routes[ri]
		rep.lengths.append(r.size() - 1)
		var pos := chokepoints(m, r, discs, exposures(m, r, discs), p)
		chokes_pos.append(pos)
		var cells: Array[Vector2i] = []
		for i in pos:
			cells.append(r[i])
		rep.chokepoints.append(cells)
		rep.spaced.append(c1_spaced(pos, p.c1_s))
		rep.max_blind.append(c2_max_blind(m, r, discs))
		rep.detour_deltas.append(c5_detours(m, field, r, pos, c5_cache, p.c5_d))
	# C1 .. C7 in code order, so reasons come out sorted
	for ri in rep.routes.size():
		if rep.spaced[ri] < p.c1_m:
			rep.fail("C1", "route %d has %d chokepoints spaced >= %d (need %d)"
				% [ri, rep.spaced[ri], p.c1_s, p.c1_m])
	for ri in rep.routes.size():
		if rep.max_blind[ri] > p.c2_g:
			rep.fail("C2", "route %d blind for %d cells (max %d)" % [ri, rep.max_blind[ri], p.c2_g])
	var c3 := c3_convergence(m, rep.routes, chokes_pos, field, p)
	rep.shared_share_pct = c3["share_pct"]
	rep.last_shared = c3["last_shared"]
	if not c3["ok"]:
		rep.fail("C3", c3["detail"])
	if not c4_lengths(rep.lengths, p):
		rep.fail("C4", "lengths %s outside [%d, %d] or ratio over %d %%"
			% [rep.lengths, p.c4_lmin, p.c4_lmax, p.c4_ratio_pct])
	for ri in rep.routes.size():
		if not c5_passes(rep.detour_deltas[ri], p.c5_d):
			rep.fail("C5", "route %d detours %s (need one cut or >= %d)"
				% [ri, rep.detour_deltas[ri], p.c5_d])
	for ri in rep.routes.size():
		if not c6_floor_room(rep.routes[ri], field, p):
			rep.fail("C6", "route %d has no cell at cost >= %d cells"
				% [ri, p.floor_cells + p.c6_extra])
	var hidden := c7_clickable(m, p)
	if not hidden.is_empty():
		rep.fail("C7", "%d buildable cells under the HUD or L, first %s"
			% [hidden.size(), _txt(m, hidden[0])])
	rep.passed = rep.reasons.is_empty()
	return rep


## exposure(b, r): route cells of `route` whose centre lies within `r` of b's centre.
static func exposure(grid: GridTopology, b: Vector2i, route: Array[Vector2i], r: float) -> int:
	var n := 0
	var hex := grid.kind() == "hex"
	for c in route:
		if _within(hex, c - b, r):
			n += 1
	return n


## The buildable cells within `r` of `cell`, as grid indexes ascending.
static func disc(m: GenMap, cell: Vector2i, r: float) -> PackedInt64Array:
	var out := PackedInt64Array()
	var hex := m.grid.kind() == "hex"
	for b in m.grid.cells():
		if m.is_buildable(b) and _within(hex, cell - b, r):
			out.append(m.grid.index(b))
	return out


## Whether b's centre lies within `r` of a's centre, from integer cell deltas (LT-130/S20):
## absolute float32 centres rounded differently per row and dropped ring-3 hex corners on some
## rows. Hex centres are (q + r/2, r * sqrt(3)/2) with neighbours 1 apart, so
## 4 * d^2 = (2 dq + dr)^2 + 3 dr^2, an exact integer; square centres are (x, y), d^2 = dx^2 + dy^2.
static func within(grid: GridTopology, a: Vector2i, b: Vector2i, r: float) -> bool:
	return _within(grid.kind() == "hex", b - a, r)


static func _within(hex: bool, d: Vector2i, r: float) -> bool:
	if hex:
		var u := 2 * d.x + d.y
		return u * u + 3 * d.y * d.y <= 4.0 * r * r
	return d.x * d.x + d.y * d.y <= r * r


## disc() of every route cell, by grid index (null for cells on no route); once per map.
static func disc_table(m: GenMap, routes: Array, r: float) -> Array:
	var table := []
	table.resize(m.grid.cell_count())
	for route: Array[Vector2i] in routes:
		for c in route:
			var i := m.grid.index(c)
			if table[i] == null:
				table[i] = disc(m, c, r)
	return table


## exposure(b, route) for every buildable b, by grid index (0 elsewhere), from the discs:
## the range test is symmetric, so b sees route cell c iff b is in disc(c).
static func exposures(m: GenMap, route: Array[Vector2i], discs: Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	out.resize(m.grid.cell_count())
	for c in route:
		for b: int in discs[m.grid.index(c)]:
			out[b] += 1
	return out


## Route positions that are chokepoints: a CHANNEL cell (a barricade may stand there; ENTRY
## and L are not candidates) with at least K buildable cells in its disc whose exposure to
## this route is >= E.
static func chokepoints(m: GenMap, route: Array[Vector2i], discs: Array,
		expo: PackedInt64Array, p: MapGenParams) -> PackedInt64Array:
	var out := PackedInt64Array()
	for i in route.size():
		var c := route[i]
		if m.kind_at(c) != GenMap.Terrain.CHANNEL:
			continue
		var k := 0
		for b: int in discs[m.grid.index(c)]:
			if expo[b] >= p.choke_e:
				k += 1
		if k >= p.choke_k:
			out.append(i)
	return out


## C1: how many chokepoints are spaced >= `s` route cells apart, taken greedily from the
## entry end (positions ascending). Passes when >= M.
static func c1_spaced(positions: PackedInt64Array, s: int) -> int:
	var n := 0
	var last := -1
	for i in positions:
		if n == 0 or i - last >= s:
			n += 1
			last = i
	return n


## C2: the longest run of consecutive route cells with no buildable cell within R.
static func c2_max_blind(m: GenMap, route: Array[Vector2i], discs: Array) -> int:
	var best := 0
	var run := 0
	for c in route:
		var d: PackedInt64Array = discs[m.grid.index(c)]
		if d.is_empty():
			run += 1
			best = maxi(best, run)
		else:
			run = 0
	return best


## C3: every route's last chokepoint before the floor (the one with the smallest field cost
## >= floor_cells) must be the same cell, and the cells common to every route must be at most
## c3_share_pct of the shortest route's cells. One route: n/a, passes, share_pct -1.
## Returns {ok: bool, last_shared: Vector2i, share_pct: int, detail: String}.
@warning_ignore("integer_division")
static func c3_convergence(m: GenMap, routes: Array, chokes: Array, field: RouteField,
		p: MapGenParams) -> Dictionary:
	var out := {"ok": true, "last_shared": GenMap.NO_CELL, "share_pct": -1, "detail": "n/a"}
	if routes.size() < 2:
		return out
	var floor_cost := p.floor_cells * SimTime.UNITS_PER_CELL
	var lasts: Array[Vector2i] = []
	for ri in routes.size():
		var r: Array[Vector2i] = routes[ri]
		var best := GenMap.NO_CELL
		var best_cost := -1
		for i: int in chokes[ri]:
			var c := field.cost_at(r[i])
			if c >= floor_cost and (best_cost < 0 or c < best_cost):
				best = r[i]
				best_cost = c
		lasts.append(best)
	var count := PackedInt64Array()
	count.resize(m.grid.cell_count())
	var shortest := -1
	for r: Array[Vector2i] in routes:
		for c in r:
			count[m.grid.index(c)] += 1
		if shortest < 0 or r.size() < shortest:
			shortest = r.size()
	var common := 0
	for v in count:
		if v == routes.size():
			common += 1
	out["share_pct"] = common * 100 / shortest
	var same := lasts[0] != GenMap.NO_CELL
	for c in lasts:
		same = same and c == lasts[0]
	if same:
		out["last_shared"] = lasts[0]
	var share_ok := common * 100 <= shortest * p.c3_share_pct
	out["ok"] = same and share_ok
	var names := PackedStringArray()
	for c in lasts:
		names.append("none" if c == GenMap.NO_CELL else _txt(m, c))
	out["detail"] = "last chokepoints before the floor [%s], shared %d of %d cells" \
		% [", ".join(names), common, shortest]
	return out


## C4: every length in [Lmin, Lmax], and longest * 100 <= shortest * c4_ratio_pct.
static func c4_lengths(lengths: Array[int], p: MapGenParams) -> bool:
	if lengths.is_empty():
		return false
	var lo: int = lengths.min()
	var hi: int = lengths.max()
	return lo >= p.c4_lmin and hi <= p.c4_lmax and hi * 100 <= lo * p.c4_ratio_pct


## C5: per chokepoint of `route`, the extra cells the route's entry walks when a barricade
## (a wall in P1) stands there: (cost with it blocked - cost) in cells, CUT when the entry no
## longer reaches L. Aligned with `positions`. With `stop_at_d` >= 0 it stops at the first
## qualifying chokepoint (CUT or >= stop_at_d), walking from the L end (cuts sit on the shared
## trunk), and leaves the others SKIPPED; with -1 it measures all. `cache` maps a blocked grid
## index to its field (lookup only), shared by the routes of one map.
@warning_ignore("integer_division")
static func c5_detours(m: GenMap, field: RouteField, route: Array[Vector2i],
		positions: PackedInt64Array, cache: Dictionary, stop_at_d := -1) -> Array[int]:
	var out: Array[int] = []
	out.resize(positions.size())
	out.fill(SKIPPED)
	var entry := route[0]
	var base := field.cost_at(entry)
	for k in range(positions.size() - 1, -1, -1):
		var cell := route[positions[k]]
		var key := m.grid.index(cell)
		if not cache.has(key):
			var wall: Array[Vector2i] = [cell]
			cache[key] = RouteField.build(m, wall)
		var blocked: RouteField = cache[key]
		var c := blocked.cost_at(entry)
		out[k] = CUT if c == RouteField.UNREACHED else (c - base) / SimTime.UNITS_PER_CELL
		if stop_at_d >= 0 and (out[k] == CUT or out[k] >= stop_at_d):
			break
	return out


## C5, owner decision on LT-130 Q2 ("Хотя бы одно узкое место на маршрут"): the route has at
## least one chokepoint where a one-cell barricade cuts it or forces a detour >= D. The other
## chokepoints are unconstrained.
static func c5_passes(deltas: Array[int], d: int) -> bool:
	for v in deltas:
		if v == CUT or v >= d:
			return true
	return false


## C6: some cell of `route` is at field cost >= floor_cells + c6_extra cells.
static func c6_floor_room(route: Array[Vector2i], field: RouteField, p: MapGenParams) -> bool:
	var need := (p.floor_cells + p.c6_extra) * SimTime.UNITS_PER_CELL
	for c in route:
		if field.cost_at(c) >= need:
			return true
	return false


## C7 (P1 proxy until LT-64): the ISLAND cells hidden from a click, those in the top
## c7_hud_rows text rows or within c7_l_cover steps of L, ascending index. Empty passes.
static func c7_clickable(m: GenMap, p: MapGenParams) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in m.grid.cells():
		if not m.is_buildable(c):
			continue
		if m.grid.text_of(c).y < p.c7_hud_rows or m.grid.steps(c, m.lighthouse) <= p.c7_l_cover:
			out.append(c)
	return out


static func _txt(m: GenMap, c: Vector2i) -> String:
	var t := m.grid.text_of(c)
	return "(%d,%d)" % [t.x, t.y]
