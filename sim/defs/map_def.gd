class_name MapDef
extends RefCounted
## map.json: the grid and its single enemy path (design note LT-4 §3.1).
## Legend: "." buildable, "#" path, "~" water, "S" path start, "L" lighthouse (path end).
## The path is derived by walking from S through neighbouring path cells to L (the grid's
## neighbours: 4 on square). The topology comes from GridFactory (LT-108).

enum Kind {BUILDABLE, PATH, WATER}

const FIELDS := ["width", "height", "rows", "grid"]
const KIND_OF := {".": Kind.BUILDABLE, "#": Kind.PATH, "~": Kind.WATER, "S": Kind.PATH,
	"L": Kind.PATH}

var width: int  ## >= 1
var height: int  ## >= 1
var spawn: Vector2i  ## the S cell (path start, docks)
var lighthouse: Vector2i  ## the L cell (path end)
var path: Array[Vector2i] = []  ## S ... L inclusive, in walking order
var grid: GridTopology  ## cell geometry (LT-77); built by GridFactory; "square" today
var _kinds: PackedByteArray = []  ## Kind per cell, indexed by grid.index


static func parse(r: ConfigReader, root: Dictionary) -> MapDef:
	r.check_keys(root, FIELDS, "")
	var m := MapDef.new()
	var start_errors := r.errors.size()
	m.width = r.req_int(root, "width", "", 1)
	m.height = r.req_int(root, "height", "", 1)
	var grid_kind := r.opt_string(root, "grid", "", "square")
	m.grid = GridFactory.make(grid_kind, m.width, m.height)
	if m.grid == null:  # LT-108 F1: report, then go on as square so later checks still run
		var quoted := PackedStringArray()
		for k in GridFactory.kinds():
			quoted.append("\"%s\"" % k)
		r.error("grid", "unknown grid \"%s\" (expected %s)" % [grid_kind, ", ".join(quoted)])
		m.grid = GridFactory.make("square", m.width, m.height)
	var rows: Variant = r.req_array(root, "rows", "")
	if rows == null or r.errors.size() > start_errors:
		return m
	m._read_rows(r, rows)
	return m


## Reads the `rows` text into `_kinds`, spawn and lighthouse and derives the path. Text
## cells map to ids through grid.cell_of_text (LT-108 F6), so a hand-set topology works too.
func _read_rows(r: ConfigReader, rows: Array) -> void:
	var start_errors := r.errors.size()
	if rows.size() != height:
		r.error("rows", "expected %d rows (height), got %d" % [height, rows.size()])
	_kinds.resize(grid.cell_count())
	var starts: Array[Vector2i] = []
	var ends: Array[Vector2i] = []
	for y in rows.size():
		var rp := ConfigReader.index("rows", y)
		var n := r.errors.size()
		var row := r.as_string(rows[y], rp)
		if r.errors.size() > n:
			continue
		if row.length() != width:
			r.error(rp, "expected %d characters (width), got %d" % [width, row.length()])
			continue
		for x in row.length():
			var ch := row[x]
			if not KIND_OF.has(ch):
				r.error(rp, "unknown character \"%s\" at column %d" % [ch, x])
				continue
			var cell := grid.cell_of_text(x, y)
			if y < height:
				_kinds[grid.index(cell)] = KIND_OF[ch]
			if ch == "S":
				starts.append(cell)
			elif ch == "L":
				ends.append(cell)
	if r.errors.size() > start_errors:
		return  # a skipped row may hold S or L; counting them now would mislead
	if starts.size() != 1:
		r.error("rows", "expected exactly one S (path start), got %d" % starts.size())
	if ends.size() != 1:
		r.error("rows", "expected exactly one L (lighthouse), got %d" % ends.size())
	if r.errors.size() > start_errors:
		return
	spawn = starts[0]
	lighthouse = ends[0]
	_derive_path(r)


## Walks S -> L and reports forks, dead ends and orphan path cells.
func _derive_path(r: ConfigReader) -> void:
	var n := r.errors.size()
	for end: Array in [["S", spawn], ["L", lighthouse]]:
		var cell: Vector2i = end[1]
		var count := _path_neighbours(cell).size()
		if count != 1:
			var t := grid.text_of(cell)
			r.error(ConfigReader.index("rows", t.y),
				"%s must be a path end (column %d has %d path neighbours, needs 1)"
				% [end[0], t.x, count])
	if r.errors.size() > n:
		return
	for cell in grid.cells():
		if kind_at(cell) == Kind.PATH and _path_neighbours(cell).size() > 2:
			var t := grid.text_of(cell)
			r.error(ConfigReader.index("rows", t.y), "path forks at column %d" % t.x)
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
		var t := grid.text_of(cur)
		if next.size() > 1:
			r.error(ConfigReader.index("rows", t.y), "path forks at column %d" % t.x)
			return
		if next.is_empty():
			r.error(ConfigReader.index("rows", t.y),
				"path from S ends at column %d without reaching L" % t.x)
			return
		cur = next[0]
		visited[cur] = true
		walk.append(cur)
	for cell in grid.cells():
		if kind_at(cell) == Kind.PATH and not visited.has(cell):
			var t := grid.text_of(cell)
			r.error(ConfigReader.index("rows", t.y),
				"path cell at column %d is not on the walk from S to L" % t.x)
	if r.errors.size() == n:
		path = walk


func _path_neighbours(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for nb in grid.neighbours(cell):
		if kind_at(nb) == Kind.PATH:
			out.append(nb)
	return out


## Out-of-bounds cells read as water.
func kind_at(cell: Vector2i) -> Kind:
	if not grid.contains(cell):
		return Kind.WATER
	return _kinds[grid.index(cell)] as Kind


## The lighthouse cell is a path cell, so it is never buildable.
func is_buildable(cell: Vector2i) -> bool:
	return kind_at(cell) == Kind.BUILDABLE
