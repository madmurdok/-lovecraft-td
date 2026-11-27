class_name RouteField
extends RefCounted
## LT-18 §3 route field: one reverse Dijkstra from L over the walkable cells (CHANNEL, ENTRY,
## LIGHTHOUSE), integer costs in sim units (SimTime.UNITS_PER_CELL per step). The heap orders
## by (cost, grid.index); a cell's next hop is its first neighbour in neighbours() order whose
## cost is its own minus the step. No floats, no RNG. LT-109 adds the barricade breach weight
## in _enter_cost; P1 only blocks cells outright (the C5 detour test).

const UNREACHED := -1

var grid: GridTopology
var goal: Vector2i
var cost := PackedInt64Array()  ## per grid.index; UNREACHED when no walk reaches L
var _walk := PackedByteArray()  ## 1 = walkable and not blocked
var _heap := PackedInt64Array()  ## build only: keys cost * cell_count + index


## The field of `m` toward its lighthouse, with `blocked` cells treated as walls.
@warning_ignore("integer_division")
static func build(m: GenMap, blocked: Array[Vector2i] = []) -> RouteField:
	var f := RouteField.new()
	f.grid = m.grid
	f.goal = m.lighthouse
	var n := m.grid.cell_count()
	f.cost.resize(n)
	f.cost.fill(UNREACHED)
	f._walk.resize(n)
	var cells := m.grid.cells()
	for i in n:
		f._walk[i] = 1 if m.is_walkable(cells[i]) else 0
	for b in blocked:
		if m.grid.contains(b) and b != m.lighthouse:
			f._walk[m.grid.index(b)] = 0
	if not m.grid.contains(m.lighthouse):
		return f
	var gi := m.grid.index(m.lighthouse)
	f.cost[gi] = 0
	f._push(gi)
	while not f._heap.is_empty():
		var key := f._pop()
		var i := key % n
		var c := key / n
		if c != f.cost[i]:
			continue  # stale entry
		for nb in m.grid.neighbours(cells[i]):
			var j := m.grid.index(nb)
			if f._walk[j] == 0:
				continue
			# reverse search: walking nb -> cells[i] enters cells[i]
			var nc := c + f._enter_cost(i)
			if f.cost[j] == UNREACHED or nc < f.cost[j]:
				f.cost[j] = nc
				f._push(nc * n + j)
	return f


## The cost from `cell` to L in sim units, UNREACHED when it has none.
func cost_at(cell: Vector2i) -> int:
	if not grid.contains(cell):
		return UNREACHED
	return cost[grid.index(cell)]


## The cost in whole cells (steps), UNREACHED when it has none.
@warning_ignore("integer_division")
func cells_at(cell: Vector2i) -> int:
	var c := cost_at(cell)
	return UNREACHED if c == UNREACHED else c / SimTime.UNITS_PER_CELL


func reaches(cell: Vector2i) -> bool:
	return cost_at(cell) != UNREACHED


## The first neighbour of `cell` (neighbours() order) one step closer to L; `cell` itself for
## L or an unreached cell.
func next_hop(cell: Vector2i) -> Vector2i:
	var c := cost_at(cell)
	if c <= 0:
		return cell
	for nb in grid.neighbours(cell):
		var j := grid.index(nb)
		if _walk[j] == 1 and cost[j] != UNREACHED and cost[j] + _enter_cost(j) == c:
			return nb
	return cell


## `from` ... L along the next hops (SimRoute.from_cells input); empty when unreached.
func route(from: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not reaches(from):
		return out
	var cur := from
	out.append(cur)
	while cur != goal:
		var nxt := next_hop(cur)
		if nxt == cur:
			out.clear()
			return out
		cur = nxt
		out.append(cur)
	return out


## The cost of stepping into cell index `i`; LT-109 adds breach_cost here.
func _enter_cost(_i: int) -> int:
	return SimTime.UNITS_PER_CELL


# --- binary min-heap of int keys -------------------------------------------------------------

func _push(key: int) -> void:
	_heap.append(key)
	var i := _heap.size() - 1
	while i > 0:
		@warning_ignore("integer_division")
		var parent := (i - 1) / 2
		if _heap[parent] <= _heap[i]:
			break
		var t := _heap[parent]
		_heap[parent] = _heap[i]
		_heap[i] = t
		i = parent


func _pop() -> int:
	var top := _heap[0]
	var last := _heap[_heap.size() - 1]
	_heap.resize(_heap.size() - 1)
	if _heap.is_empty():
		return top
	_heap[0] = last
	var i := 0
	var n := _heap.size()
	while true:
		var l := 2 * i + 1
		if l >= n:
			break
		var s := l
		if l + 1 < n and _heap[l + 1] < _heap[l]:
			s = l + 1
		if _heap[i] <= _heap[s]:
			break
		var t := _heap[s]
		_heap[s] = _heap[i]
		_heap[i] = t
		i = s
	return top
