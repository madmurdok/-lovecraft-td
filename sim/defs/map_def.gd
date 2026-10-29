class_name MapDef
extends RefCounted
## map.json: the grid and its single enemy path (design note LT-4 §3.1).
## Legend: "." buildable, "#" path, "~" water, "S" path start, "L" lighthouse (path end).
## The path is derived by walking from S through 4-neighbouring path cells to L.

enum Kind {BUILDABLE, PATH, WATER}

const FIELDS := ["width", "height", "rows"]
const KIND_OF := {".": Kind.BUILDABLE, "#": Kind.PATH, "~": Kind.WATER, "S": Kind.PATH,
	"L": Kind.PATH}
const NEIGHBOURS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

var width: int  ## >= 1
var height: int  ## >= 1
var spawn: Vector2i  ## the S cell (path start, docks)
var lighthouse: Vector2i  ## the L cell (path end)
var path: Array[Vector2i] = []  ## S ... L inclusive, in walking order
var _kinds: PackedByteArray = []  ## Kind per cell, row-major


static func parse(r: ConfigReader, root: Dictionary) -> MapDef:
	r.check_keys(root, FIELDS, "")
	var m := MapDef.new()
	var start_errors := r.errors.size()
	m.width = r.req_int(root, "width", "", 1)
	m.height = r.req_int(root, "height", "", 1)
	var rows: Variant = r.req_array(root, "rows", "")
	if rows == null or r.errors.size() > start_errors:
		return m
	if rows.size() != m.height:
		r.error("rows", "expected %d rows (height), got %d" % [m.height, rows.size()])
	m._kinds.resize(m.width * m.height)
	var starts: Array[Vector2i] = []
	var ends: Array[Vector2i] = []
	for y in rows.size():
		var rp := ConfigReader.index("rows", y)
		var n := r.errors.size()
		var row := r.as_string(rows[y], rp)
		if r.errors.size() > n:
			continue
		if row.length() != m.width:
			r.error(rp, "expected %d characters (width), got %d" % [m.width, row.length()])
			continue
		for x in row.length():
			var ch := row[x]
			if not KIND_OF.has(ch):
				r.error(rp, "unknown character \"%s\" at column %d" % [ch, x])
				continue
			if y < m.height:
				m._kinds[y * m.width + x] = KIND_OF[ch]
			if ch == "S":
				starts.append(Vector2i(x, y))
			elif ch == "L":
				ends.append(Vector2i(x, y))
	if r.errors.size() > start_errors:
		return m  # a skipped row may hold S or L; counting them now would mislead
	if starts.size() != 1:
		r.error("rows", "expected exactly one S (path start), got %d" % starts.size())
	if ends.size() != 1:
		r.error("rows", "expected exactly one L (lighthouse), got %d" % ends.size())
	if r.errors.size() > start_errors:
		return m
	m.spawn = starts[0]
	m.lighthouse = ends[0]
	m._derive_path(r)
	return m


## Walks S -> L and reports forks, dead ends and orphan path cells.
func _derive_path(r: ConfigReader) -> void:
	var n := r.errors.size()
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			if kind_at(cell) == Kind.PATH and _path_neighbours(cell).size() > 2:
				r.error(ConfigReader.index("rows", y), "path forks at column %d" % x)
	if r.errors.size() > n:
		return
	var visited := {spawn: true}
	var walk: Array[Vector2i] = [spawn]
	var cur := spawn
	while cur != lighthouse:
		var next: Array[Vector2i] = []
		for nb in _path_neighbours(cur):
			if not visited.has(nb):
				next.append(nb)
		if next.size() > 1:
			r.error(ConfigReader.index("rows", cur.y), "path forks at column %d" % cur.x)
			return
		if next.is_empty():
			r.error(ConfigReader.index("rows", cur.y),
				"path from S ends at column %d without reaching L" % cur.x)
			return
		cur = next[0]
		visited[cur] = true
		walk.append(cur)
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			if kind_at(cell) == Kind.PATH and not visited.has(cell):
				r.error(ConfigReader.index("rows", y),
					"path cell at column %d is not on the walk from S to L" % x)
	if r.errors.size() == n:
		path = walk


func _path_neighbours(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in NEIGHBOURS:
		if kind_at(cell + d) == Kind.PATH:
			out.append(cell + d)
	return out


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


## Out-of-bounds cells read as water.
func kind_at(cell: Vector2i) -> Kind:
	if not in_bounds(cell):
		return Kind.WATER
	return _kinds[cell.y * width + cell.x] as Kind


## The lighthouse cell is a path cell, so it is never buildable.
func is_buildable(cell: Vector2i) -> bool:
	return kind_at(cell) == Kind.BUILDABLE
