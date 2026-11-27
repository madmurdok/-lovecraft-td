class_name MapGenerator
extends RefCounted
## LT-130 (LT-18 §9 option a): skeleton graph -> rasterize -> islands -> metric -> retry.
## Pure: one MapRng per attempt, seeded map_seed * 1000 + attempt; draws in the pinned order of
## LT-130 §3; candidates come from grid.neighbours() order or ascending grid.index; no
## Dictionary is iterated. Everything goes through GridTopology (G10), grids via GridFactory.

const T := GenMap.Terrain
## Reject codes in report order: structural, then the §8 rules.
const REASON_ORDER: PackedStringArray = ["S1", "S2", "C1", "C2", "C3", "C4", "C5", "C6", "C7"]


## What generate() hands back. Never a failing map: `map` is null when the cap was hit.
class GenResult extends RefCounted:
	var map: GenMap  ## the accepted map, or null at the attempt cap
	var report: ChokepointMetric.MetricReport  ## of the accepted map (of the last attempt on failure)
	var attempts := 0  ## 1 + rejected attempts (attempt_cap on failure)
	var rejects: Array[PackedStringArray] = []  ## reason codes per rejected attempt, in order
	var error := ""  ## "" or "attempt cap 50 reached (seed 17): C1 x41, C5 x9"


## Attempts 0, 1, ... of `map_seed` until one passes the metric or attempt_cap ran. Params
## failing MapGenParams.check() give map null, attempts 0 and error "params: ...".
static func generate(map_seed: int, p: MapGenParams) -> GenResult:
	var res := GenResult.new()
	var bad := p.check()
	if not bad.is_empty():
		res.error = "params: " + "; ".join(bad)
		return res
	for a in p.attempt_cap:
		var m := attempt(MapRng.attempt_seed(map_seed, a), p)
		var rep := check(m, p)
		res.attempts = a + 1
		res.report = rep
		if rep.passed:
			res.map = m
			return res
		res.rejects.append(rep.reasons)
	var hist := PackedStringArray()
	for code in REASON_ORDER:
		var n := 0
		for r in res.rejects:
			if r.has(code):
				n += 1
		if n > 0:
			hist.append("%s x%d" % [code, n])
	res.error = "attempt cap %d reached (seed %d): %s" % [p.attempt_cap, map_seed, ", ".join(hist)]
	return res


## The structural checks (S2: fewer entries placed than drawn; S1: an entry does not reach L),
## then the §8 metric. S2 skips the metric.
static func check(m: GenMap, p: MapGenParams) -> ChokepointMetric.MetricReport:
	if m.entries.is_empty() or m.entries.size() < m.entries_drawn:
		var rep := ChokepointMetric.MetricReport.new()
		rep.fail("S2", "%d of %d entries placed" % [m.entries.size(), m.entries_drawn])
		return rep
	return ChokepointMetric.evaluate(m, p, RouteField.build(m))


## One attempt, no metric (LT-130 §3 steps 1-9).
@warning_ignore("integer_division")
static func attempt(attempt_seed_value: int, p: MapGenParams) -> GenMap:
	var rng := MapRng.new(attempt_seed_value)
	var m := GenMap.blank(p.grid_kind, p.width, p.height)  # 1. all ISLAND
	var g := m.grid
	var w := p.width
	var h := p.height
	# 2. sea band: per text row (cells() is row-major), depth cells from the east edge
	var depth := PackedInt64Array()
	depth.resize(h)
	for c in g.cells():
		var t := g.text_of(c)
		if t.x == 0:
			depth[t.y] = rng.randi_range(p.sea_min, p.sea_max)
		if t.x >= w - depth[t.y]:
			m.set_kind(c, T.SEA)
	# 3. L: text x in [1, 2], y in the middle half
	var lx := rng.randi_range(1, 2)
	var ly := rng.randi_range(h / 4, h - 1 - h / 4)
	m.lighthouse = g.cell_of_text(lx, ly)
	m.set_kind(m.lighthouse, T.LIGHTHOUSE)
	# 4. entries: k row bands, one row drawn per band, the last land cell west of the sea
	var k := rng.randi_range(p.entries_min, p.entries_max)
	m.entries_drawn = k
	for i in k:
		var y := rng.randi_range(i * h / k, (i + 1) * h / k - 1)
		var e := g.cell_of_text(w - 1 - depth[y], y)
		var free := m.kind_at(e) == T.ISLAND
		for n in g.neighbours(e):
			free = free and m.kind_at(n) != T.ENTRY
		if free:
			m.set_kind(e, T.ENTRY)
			m.entries.append(e)
	if m.entries.is_empty():
		return m  # S2
	# 5. funnel F: funnel_steps from L toward the entries' mean row; the trunk F .. L is shared
	var sum_y := 0
	for e in m.entries:
		sum_y += g.text_of(e).y
	var mean_y := sum_y / m.entries.size()
	var target := g.cell_of_text(mini(lx + p.funnel_steps, w - 3 - p.sea_max), mean_y)
	var trunk: Array[Vector2i] = [m.lighthouse]
	_walk(m, rng, p, m.lighthouse, target, trunk, p.funnel_steps)
	m.funnel = trunk.back()
	var tf := g.text_of(m.funnel)
	for e in m.entries:
		var te := g.text_of(e)
		var wy := clampi((te.y + tf.y) / 2 + rng.randi_range(-p.waypoint_jitter, p.waypoint_jitter),
			0, h - 1)
		var wx := clampi((te.x + tf.x) / 2, 1, w - 2 - depth[wy])
		m.waypoints.append(g.cell_of_text(wx, wy))
	# 6. corridors entry -> waypoint -> F
	var corridors: Array = []
	for i in m.entries.size():
		var path: Array[Vector2i] = [m.entries[i]]
		if _walk(m, rng, p, m.entries[i], m.waypoints[i], path):
			_walk(m, rng, p, m.waypoints[i], m.funnel, path)
		corridors.append(path)
	# 7. loops: corridor i <-> i + 1 (middle thirds); one entry: a second waypoint -> F bypass
	var loops := rng.randi_range(p.loops_min, p.loops_max)
	for j in loops:
		var a := _middle_third(rng, corridors[0] if m.entries.size() < 2
			else corridors[j % (m.entries.size() - 1)])
		var path: Array[Vector2i] = [a]
		if m.entries.size() >= 2:
			var b := _middle_third(rng, corridors[j % (m.entries.size() - 1) + 1])
			_walk(m, rng, p, a, b, path)
			m.links.append_array([a, b])
		else:
			var ta := g.text_of(a)
			var wy := clampi((ta.y + tf.y) / 2
				+ rng.randi_range(-p.waypoint_jitter, p.waypoint_jitter), 0, h - 1)
			var wp := g.cell_of_text(clampi((ta.x + tf.x) / 2, 1, w - 2 - depth[wy]), wy)
			if _walk(m, rng, p, a, wp, path):
				_walk(m, rng, p, wp, m.funnel, path)
			m.links.append_array([a, wp])
	# 8. pockets
	_pockets(m, rng, p)
	# 9. islands, then the C7 zone (P1 proxy) becomes ROCK, then small leftovers
	_split_islands(m, rng, p)
	for c in g.cells():
		if m.kind_at(c) == T.ISLAND and (g.text_of(c).y < p.c7_hud_rows
				or g.steps(c, m.lighthouse) <= p.c7_l_cover):
			m.set_kind(c, T.ROCK)
	for comp in _land_components(m):
		if comp.size() < p.island_min:
			for i in comp:
				m.set_kind(g.cells()[i], T.ROCK)
	return m


## Greedy carve from `from` toward `to`: each step goes to a neighbour one step closer (not
## SEA), one draw among the candidates, then one wide_pct draw: when wide, the first ISLAND or
## ROCK cell next to both the old and the new cell is carved too. Appends the walked cells to
## `path`; stops after `max_steps` steps when >= 0. False when no candidate was left.
static func _walk(m: GenMap, rng: MapRng, p: MapGenParams, from: Vector2i, to: Vector2i,
		path: Array[Vector2i], max_steps := -1) -> bool:
	var g := m.grid
	var cur := from
	var done := 0
	while cur != to and (max_steps < 0 or done < max_steps):
		var d := g.steps(cur, to)
		var cands: Array[Vector2i] = []
		for n in g.neighbours(cur):
			if g.steps(n, to) == d - 1 and m.kind_at(n) != T.SEA:
				cands.append(n)
		if cands.is_empty():
			return false
		var nxt := cands[rng.pick(cands.size())]
		var wide := rng.randi_range(1, 100) <= p.wide_pct
		_carve(m, nxt)
		if wide:
			for n in g.neighbours(nxt):
				if g.steps(n, cur) == 1 and _carve(m, n):
					break
		path.append(nxt)
		cur = nxt
		done += 1
	return true


## ISLAND / ROCK -> CHANNEL; SEA, ENTRY, L and channels stay. True when it changed the cell.
static func _carve(m: GenMap, c: Vector2i) -> bool:
	var k := m.kind_at(c)
	if k == T.ISLAND or k == T.ROCK:
		m.set_kind(c, T.CHANNEL)
		return true
	return false


## A cell of the middle third of `path`, drawn.
@warning_ignore("integer_division")
static func _middle_third(rng: MapRng, path: Array) -> Vector2i:
	var n := path.size()
	var lo := n / 3
	var hi := maxi(lo, 2 * n / 3 - 1)
	return path[rng.randi_range(lo, hi)]


## Step 8: pockets_min..pockets_max dead-end spurs of pocket_len_min..max cells. Per pocket,
## draws in order: length, mouth (among CHANNEL cells within pocket_sea_steps of the sea,
## pockets excluded, ascending index), one direction 0..5 per cell. A spur that would touch
## another channel (or itself) is dropped after its draws. The cell past the tip becomes ROCK.
static func _pockets(m: GenMap, rng: MapRng, p: MapGenParams) -> void:
	var g := m.grid
	var sea := _sea_distance(m)
	var used := PackedByteArray()  # 1 = a pocket cell
	used.resize(g.cell_count())
	var count := rng.randi_range(p.pockets_min, p.pockets_max)
	for q in count:
		var mouths: Array[Vector2i] = []
		for c in g.cells():
			var i := g.index(c)
			if m.kind_at(c) == T.CHANNEL and used[i] == 0 and sea[i] >= 0 \
					and sea[i] <= p.pocket_sea_steps:
				mouths.append(c)
		var length := rng.randi_range(p.pocket_len_min, p.pocket_len_max)
		var mouth_i := rng.pick(mouths.size())
		var dirs := PackedInt64Array()
		for s in length:
			dirs.append(rng.randi_range(0, 5))
		if mouths.is_empty():
			continue
		var start := mouths[mouth_i]
		var spur: Array[Vector2i] = []
		var in_spur := {}  # lookup only
		var cur := start
		for s in length:
			var options: Array[Vector2i] = []
			for n in g.neighbours(cur):
				if m.kind_at(n) == T.ISLAND and not in_spur.has(n) \
						and _spur_cell_ok(m, n, cur, start, s == 0, in_spur):
					options.append(n)
			if options.is_empty():
				spur.clear()
				break
			cur = options[dirs[s] % options.size()]
			spur.append(cur)
			in_spur[cur] = true
		if spur.is_empty():
			continue
		for c in spur:
			m.set_kind(c, T.CHANNEL)
			used[g.index(c)] = 1
		var tip := spur.back() as Vector2i
		var cap := GenMap.NO_CELL
		for n in g.neighbours(tip):
			if m.kind_at(n) == T.ISLAND and (cap == GenMap.NO_CELL
					or g.steps(n, start) > g.steps(cap, start)):
				cap = n
		if cap != GenMap.NO_CELL:
			m.set_kind(cap, T.ROCK)
		m.pockets.append(spur)


## A spur may grow into `n` from `cur` when no walkable or spur cell touches `n` except `cur`
## (the first cell may also touch one of the mouth's own neighbours: it opens from a corridor).
## The first cell touching two of them would join two network cells that are not adjacent
## (the cells flanking an edge are 2 apart): a through cell and a barricade bypass (S20).
static func _spur_cell_ok(m: GenMap, n: Vector2i, cur: Vector2i, start: Vector2i, first: bool,
		in_spur: Dictionary) -> bool:
	var g := m.grid
	var flanks := 0
	for nn in g.neighbours(n):
		if nn == cur or not (m.is_walkable(nn) or in_spur.has(nn)):
			continue
		if first and g.steps(nn, start) == 1:
			flanks += 1
			if flanks == 1:
				continue
		return false
	return true


## Steps from every cell to the nearest SEA cell (BFS over all cells, sources in ascending
## index); -1 when the map has no sea.
static func _sea_distance(m: GenMap) -> PackedInt64Array:
	var g := m.grid
	var cells := g.cells()
	var dist := PackedInt64Array()
	dist.resize(g.cell_count())
	dist.fill(-1)
	var queue := PackedInt64Array()
	for i in cells.size():
		if m.kind_at(cells[i]) == T.SEA:
			dist[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		for n in g.neighbours(cells[i]):
			var j := g.index(n)
			if dist[j] < 0:
				dist[j] = dist[i] + 1
				queue.append(j)
	return dist


## ISLAND components (BFS over neighbours), each a PackedInt64Array of grid indexes in BFS
## order; components in ascending index of their first cell.
static func _land_components(m: GenMap) -> Array[PackedInt64Array]:
	var g := m.grid
	var cells := g.cells()
	var seen := PackedByteArray()
	seen.resize(cells.size())
	var out: Array[PackedInt64Array] = []
	for i in cells.size():
		if seen[i] == 1 or m.kind_at(cells[i]) != T.ISLAND:
			continue
		var comp := PackedInt64Array([i])
		seen[i] = 1
		var head := 0
		while head < comp.size():
			var cur := comp[head]
			head += 1
			for n in g.neighbours(cells[cur]):
				var j := g.index(n)
				if seen[j] == 0 and m.kind_at(n) == T.ISLAND:
					seen[j] = 1
					comp.append(j)
		out.append(comp)
	return out


## Step 9: while some land component is larger than island_max, split it: ceil(size /
## island_seed_div) (at least 2) seed cells drawn from its cells in ascending index, regions
## by multi-source BFS in draw order, and every cell next to a lower-numbered region becomes
## ROCK. Each split rocks at least one cell, so the loop ends.
@warning_ignore("integer_division")
static func _split_islands(m: GenMap, rng: MapRng, p: MapGenParams) -> void:
	var g := m.grid
	var cells := g.cells()
	var again := true
	while again:
		again = false
		for comp in _land_components(m):
			if comp.size() <= p.island_max:
				continue
			again = true
			var pool := comp.duplicate()
			pool.sort()
			var n_seeds := maxi(2, (comp.size() + p.island_seed_div - 1) / p.island_seed_div)
			var region := PackedInt64Array()
			region.resize(cells.size())
			region.fill(-1)
			var queue := PackedInt64Array()
			for r in n_seeds:
				var at := rng.pick(pool.size())
				region[pool[at]] = r
				queue.append(pool[at])
				pool.remove_at(at)
			var head := 0
			while head < queue.size():
				var cur := queue[head]
				head += 1
				for nb in g.neighbours(cells[cur]):
					var j := g.index(nb)
					if region[j] < 0 and m.kind_at(nb) == T.ISLAND:
						region[j] = region[cur]
						queue.append(j)
			var sorted := comp.duplicate()
			sorted.sort()
			for i in sorted:
				for nb in g.neighbours(cells[i]):
					var j := g.index(nb)
					if region[j] >= 0 and region[j] < region[i]:
						m.set_kind(cells[i], T.ROCK)
						break
