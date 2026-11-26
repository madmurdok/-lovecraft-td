class_name GenMap
extends RefCounted
## LT-130: a generated (or fixture) map v2: a grid, one LT-18 §2 terrain kind per cell, the
## entries and L, plus generator-only extras for the viewer (pockets, loop links, skeleton).
## Not a MapDef: today's MapDef parses one non-forking path; LT-109's MapDef v2 reads
## to_map_dict() and the Terrain enum moves there. Per-cell data is indexed by grid.index.

## LT-18 §2 terrain kinds; LEGEND[kind] is the map text character.
enum Terrain {SEA, CHANNEL, ISLAND, ROCK, ENTRY, LIGHTHOUSE}

const LEGEND := "~#.^SL"
const NO_CELL := Vector2i(-1048576, -1048576)  ## "no cell": outside any board

var grid: GridTopology
var width := 0
var height := 0
var terrain := PackedByteArray()  ## Terrain per grid.index
var entries: Array[Vector2i] = []  ## ascending grid.index
var lighthouse := NO_CELL
## Generator extras (empty for fixtures): each pocket's carved cells, mouth side first (the
## corridor cell it opens from is not included); loop links as flat (from, to) pairs; the
## funnel node F and one waypoint per entry; how many entries were drawn (S2 check).
var pockets: Array = []  ## of Array[Vector2i]
var links: Array[Vector2i] = []
var funnel := NO_CELL
var waypoints: Array[Vector2i] = []
var entries_drawn := 0


## A `width` x `height` map of `kind`, all ISLAND; null for an unregistered kind.
static func blank(kind: String, w: int, h: int) -> GenMap:
	var g := GridFactory.make(kind, w, h)
	if g == null:
		return null
	var m := GenMap.new()
	m.grid = g
	m.width = w
	m.height = h
	m.terrain.resize(g.cell_count())
	m.terrain.fill(Terrain.ISLAND)
	return m


## A fixture from text rows in the §2 legend (`~ # . ^ S L`), read like map.json. Null when
## the kind is unknown, the rows are ragged or empty, a character is not in the legend, or
## there is not exactly one L. Entries are the S cells in ascending index.
static func from_rows(kind: String, rows: Array) -> GenMap:
	if rows.is_empty() or not (rows[0] is String) or str(rows[0]).is_empty():
		return null
	var w := str(rows[0]).length()
	for row: Variant in rows:
		if not (row is String) or str(row).length() != w:
			return null
	var m := blank(kind, w, rows.size())
	if m == null:
		return null
	var lights := 0
	for c in m.grid.cells():
		var t := m.grid.text_of(c)
		var k := LEGEND.find(str(rows[t.y])[t.x])
		if k < 0:
			return null
		m.terrain[m.grid.index(c)] = k
		if k == Terrain.ENTRY:
			m.entries.append(c)
		elif k == Terrain.LIGHTHOUSE:
			m.lighthouse = c
			lights += 1
	if lights != 1:
		return null
	m.entries_drawn = m.entries.size()
	return m


func kind_at(cell: Vector2i) -> int:
	return terrain[grid.index(cell)]


func set_kind(cell: Vector2i, k: int) -> void:
	terrain[grid.index(cell)] = k


## Ground units walk it: CHANNEL, ENTRY, LIGHTHOUSE (LT-18 §2).
func is_walkable(cell: Vector2i) -> bool:
	var k := kind_at(cell)
	return k == Terrain.CHANNEL or k == Terrain.ENTRY or k == Terrain.LIGHTHOUSE


## A tower may stand on it: ISLAND only.
func is_buildable(cell: Vector2i) -> bool:
	return kind_at(cell) == Terrain.ISLAND


## The map text, one string per text row (cells() is row-major in text order).
func rows() -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for c in grid.cells():
		line += LEGEND[terrain[grid.index(c)]]
		if grid.text_of(c).x == width - 1:
			out.append(line)
			line = ""
	return out


## The map.json shape (`width`, `height`, `grid`, `rows`) LT-109's MapDef v2 parses.
func to_map_dict() -> Dictionary:
	return {"width": width, "height": height, "grid": grid.kind(), "rows": Array(rows())}


## Every pocket cell, in ascending grid.index.
func pocket_cells() -> Array[Vector2i]:
	var idx := PackedInt64Array()
	for pocket: Array in pockets:
		for c: Vector2i in pocket:
			idx.append(grid.index(c))
	idx.sort()
	var out: Array[Vector2i] = []
	for i in idx:
		out.append(grid.cells()[i])
	return out


## The text the digest hashes: kind, size, rows, entries and pocket cells as text coords in
## ascending grid.index. The seed is not part of it (it names the map, not how it was found).
func canonical() -> String:
	return "mapv2|%s|%dx%d|%s|E:%s|P:%s" % [grid.kind(), width, height, "\n".join(rows()),
		_coords(entries), _coords(pocket_cells())]


## sha256 of canonical(), hex.
func digest() -> String:
	return canonical().sha256_text()


func _coords(cells: Array[Vector2i]) -> String:
	var parts := PackedStringArray()
	for c in cells:
		var t := grid.text_of(c)
		parts.append("%d,%d" % [t.x, t.y])
	return ";".join(parts)
