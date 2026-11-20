class_name LookCatalog
extends RefCounted
## LT-104 §2: the look catalog. A tower look is a row {color, fx, area, modes, cap, marker}:
## `fx` names a builder + renderer pair in FxLayer ("" = no SHOT effect), `area` an
## entity-layer area renderer ("" = none), `modes` the EffectCatalog.Modes they can draw,
## `cap` the live attack effects per tower. An enemy look is {color, radius (cells), ring}.
## The built-in rows live here (they name draw code); a look is derived from the attack
## mode by default (derived_tower_look, the LT-25/LT-103 ladder). The optional,
## presentation-only data/looks.json adds variants of built-in rows and assigns looks to
## tower and enemy def ids:
##   looks    {id: {base: <built-in id>, color?: [r,g,b(,a)] 0..4, cap?: 1..8 (tower looks),
##            radius?: 0.15..0.5, ring?: bool (enemy looks)}}; an id never shadows a built-in
##   towers   {tower def id: tower look id}, used on the levels whose mode the look draws
##   enemies  {enemy def id: enemy look id}
## Keyed by def id only: a fake and a real of one def look alike (render isolation). The
## sim never loads it (not in ConfigLoader / GameConfig). A missing file is an empty table;
## an invalid one push_errors each problem, is used as {} and Main refuses to start (Q1).
## LookCatalog.use(table) injects a table (tests).

const PATH := "res://data/looks.json"
const ROOT_FIELDS := ["looks", "towers", "enemies"]
const TOWER_FIELDS := ["base", "color", "cap"]
const ENEMY_FIELDS := ["base", "color", "radius", "ring"]
const COLOR_MAX := 4.0
const CAP_MIN := 1
const CAP_MAX := 8
const RADIUS_MIN := 0.15
const RADIUS_MAX := 0.5
const ENEMY_RADIUS := 0.25  ## the built-in enemy body, cells (marker geometry is relative to it)

static var _table := {}
static var _loaded := false
static var _errors: Array[String] = []
static var _builtin_rows := {}  ## built once (a const could not name Board's colours)
static var _none_row := {}  ## row() of an unknown id: no fx, no area, BLACK
static var _rows := {}  ## look id -> row: the built-ins plus the table's variants
static var _tower_over := {}  ## tower def id -> look id (the table's `towers`)
static var _enemy_over := {}  ## enemy def id -> look id (the table's `enemies`)


## Replaces the table (tests): returns validate(table). An invalid table is used as {}
## (every look derived). `table` null: the next use loads PATH again.
static func use(table: Variant) -> Array[String]:
	if table == null:
		_table = {}
		_loaded = false
		_errors = []
		_rebuild()
		return _errors
	_errors = validate(table)
	_table = table if _errors.is_empty() else {}
	_loaded = true
	_rebuild()
	return _errors


## The table in use, loaded from PATH on first use; a missing file is {} with no error.
static func table() -> Dictionary:
	if not _loaded:
		_loaded = true
		var errs: Array[String] = []
		var data: Variant = {}
		if FileAccess.file_exists(PATH):
			var r := TextLoader.read_json(PATH)
			errs = r["errors"]
			data = r["data"]
			if data != null:
				errs.append_array(validate(data))
		_errors = errs
		_table = data if errs.is_empty() else {}
		for e in errs:
			push_error("LookCatalog: " + e)
		_rebuild()
	return _table


## The problems found when the table was loaded or injected (empty: it is valid).
static func errors() -> Array[String]:
	table()
	return _errors


## The built-in rows: 10 tower looks (today's ids and colours) and the `enemy` look.
static func builtin() -> Dictionary:
	if _builtin_rows.is_empty():
		var m := EffectCatalog.Mode
		var cap := FxLayer.MAX_FX_PER_TOWER
		_builtin_rows = {
			"tracer": _tower_row(Board.TRACER_COLOR, "tracer", "", [m.SINGLE, m.BURST], cap),
			"harpoon": _tower_row(Board.HARPOON_COLOR, "harpoon", "", [m.LINE], cap),
			"wave": _tower_row(Board.WAVE_RIM, "wave", "", [m.BLAST], cap),
			"shell": _tower_row(Board.SHELL_COLOR, "shell", "", [m.SINGLE, m.BURST, m.BLAST], cap),
			"beam": _tower_row(Board.BEAM_COLOR, "beam", "", [m.BEAM], cap),
			"dynamite": _tower_row(Board.DYNAMITE_COLOR, "dynamite", "", [m.FUSE], cap),
			"banish": _tower_row(Board.BANISH_COLOR, "banish", "", [m.BANISH], cap),
			"aura": _tower_row(EntityLayer.WARD_COLOR, "", "ward", [m.AURA], cap),
			"searchlight": _tower_row(EntityLayer.SEARCHLIGHT_COLOR, "", "searchlight", [m.AURA],
				cap),
			"summon": _tower_row(EntityLayer.SUMMON_COLOR, "", "summon_ring", [m.SUMMON], cap),
			"enemy": {"kind": "enemy", "color": EntityLayer.COLOR_ENEMY, "radius": ENEMY_RADIUS,
				"ring": false},
		}
		_none_row = _tower_row(Color.BLACK, "", "", [], cap)
	return _builtin_rows


static func _tower_row(color: Color, fx: String, area: String, modes: Array, cap: int) -> Dictionary:
	return {"kind": "tower", "color": color, "fx": fx, "area": area, "modes": modes, "cap": cap,
		"marker": "frame"}


## LT-104 §2.2: the look derived from a level's attack mode (LT-25 §1, LT-103 §2.2): one
## `match` on Level.mode plus its two modifiers (reveal_fakes, min_range). sanity_scaling
## -> "beam", pierce -> "harpoon", fuse_seconds -> "dynamite", min_range -> "shell",
## aoe_radius -> "wave", support -> "aura" ("searchlight" with reveal_fakes), banish_cells
## -> "banish", summon_max -> "summon", otherwise "tracer".
static func derived_tower_look(s: TowerDef.Level) -> String:
	match s.mode():
		EffectCatalog.Mode.AURA:
			return "searchlight" if s.effects.get("reveal_fakes", 0.0) > 0.0 else "aura"
		EffectCatalog.Mode.BANISH:
			return "banish"
		EffectCatalog.Mode.SUMMON:
			return "summon"
		EffectCatalog.Mode.BEAM:
			return "beam"
		EffectCatalog.Mode.LINE:
			return "harpoon"
		EffectCatalog.Mode.FUSE:
			return "dynamite"
		EffectCatalog.Mode.BLAST:
			return "shell" if s.min_range > 0.0 else "wave"
	return "shell" if s.min_range > 0.0 else "tracer"  # BURST, SINGLE


## LT-104 Q2: no built-in boss look; every enemy derives `enemy` until looks.json names one.
static func derived_enemy_look(_def: EnemyDef) -> String:
	return "enemy"


## The tower's look: its looks.json override when the override draws the current level's
## mode (an upgrade that changes mode falls back there), else the derived look. Not cached:
## level and branch change on upgrade.
static func tower_look(t: SimTower) -> String:
	if not _loaded:
		table()
	var s := t.stats()
	var o: String = _tower_over.get(t.def.id, "")
	if not o.is_empty() and s.mode() in _rows[o]["modes"]:
		return o
	return derived_tower_look(s)


## The enemy's look: its looks.json override, else the derived one.
static func enemy_look(e: SimEnemy) -> String:
	if not _loaded:
		table()
	var o: String = _enemy_over.get(e.def.id, "")
	return o if not o.is_empty() else derived_enemy_look(e.def)


## The row of look `id` (built-in or variant); an unknown id has no fx, no area, BLACK.
static func row(id: String) -> Dictionary:
	if not _loaded:
		table()
	return _rows.get(id, _none_row)


## The enemy row of look `id`; an unknown id is the built-in `enemy`.
static func enemy_row(id: String) -> Dictionary:
	if not _loaded:
		table()
	var r: Dictionary = _rows.get(id, _none_row)
	return r if r["kind"] == "enemy" else _rows["enemy"]


## The colour of look `id` (Color.BLACK for an unknown id, as attack_color always did).
static func color(id: String) -> Color:
	return row(id)["color"]


## The colour of tower def `def_id`'s look for `mode`, from the def id alone (a sold tower
## still has one): its override when the override draws `mode`, else `fallback`'s colour.
static func def_color(def_id: String, mode: int, fallback: String) -> Color:
	if not _loaded:
		table()
	var o: String = _tower_over.get(def_id, "")
	if not o.is_empty():
		var r: Dictionary = _rows[o]
		if mode in r["modes"]:
			return r["color"]
	return _rows[fallback]["color"]


## A summoned unit's colour (leash ring, claw, wings, rim): its tower def's SUMMON look.
static func ally_color(def_id: String) -> Color:
	return def_color(def_id, EffectCatalog.Mode.SUMMON, "summon")


## A BLAST's colour: the throwing tower def's FUSE look.
static func blast_color(def_id: String) -> Color:
	return def_color(def_id, EffectCatalog.Mode.FUSE, "dynamite")


## The problems of the table in use against `config` (empty: none): a `towers` / `enemies`
## id that is not in the config, and a tower override whose look draws none of that
## tower's levels' and branches' modes (a dead override).
static func check_config(config: GameConfig) -> Array[String]:
	table()
	var errs: Array[String] = []
	for id: String in _tower_over:
		if not config.towers.has(id):
			errs.append("towers.%s: no such tower" % id)
			continue
		var look: String = _tower_over[id]
		var modes: Array = _rows[look]["modes"]
		var def: TowerDef = config.towers[id]
		var levels: Array = []
		levels.append_array(def.levels)
		levels.append_array(def.branches.values())
		var drawn := false
		for l: TowerDef.Level in levels:
			if l.mode() in modes:
				drawn = true
				break
		if not drawn:
			errs.append("towers.%s: look \"%s\" draws none of this tower's modes" % [id, look])
	for id: String in _enemy_over:
		if not config.enemies.has(id):
			errs.append("enemies.%s: no such enemy" % id)
	return errs


## Every problem with `t` as a looks table (empty: valid): the shape in the header; a
## variant's base is a built-in id, its id is not; its fields fit the base's kind; every
## assignment names a look of the right kind.
static func validate(t: Variant) -> Array[String]:
	var errs: Array[String] = []
	if not t is Dictionary:
		errs.append("root must be an object")
		return errs
	var rows := builtin()
	for k: Variant in t:
		if k not in ROOT_FIELDS:
			errs.append("%s: unknown section" % k)
	var kinds := {}  ## look id -> "tower" / "enemy", built-ins and variants with a valid base
	for id: String in rows:
		kinds[id] = rows[id]["kind"]
	var looks: Variant = t.get("looks", {})
	if not looks is Dictionary:
		errs.append("looks: must be an object")
	else:
		for id: String in looks:
			var at := "looks." + id
			if rows.has(id):
				errs.append(at + ": shadows a built-in look")
				continue
			var v: Variant = looks[id]
			if not v is Dictionary:
				errs.append(at + ": must be an object")
				continue
			var base: Variant = v.get("base")
			if not base is String or not rows.has(base):
				errs.append("%s.base: must be a built-in look id (got %s)" % [at, base])
				continue
			var kind: String = rows[base]["kind"]
			kinds[id] = kind
			var fields := TOWER_FIELDS if kind == "tower" else ENEMY_FIELDS
			for f: Variant in v:
				if f not in fields:
					errs.append("%s.%s: unknown field for %s look" % [at, f, _a(kind)])
			if v.has("color"):
				_check_color(v["color"], at + ".color", errs)
			if v.has("cap") and "cap" in fields:
				var c: Variant = v["cap"]
				if not (c is int or c is float) or float(c) != floorf(float(c)) \
						or c < CAP_MIN or c > CAP_MAX:
					errs.append("%s.cap: must be a whole number %d..%d" % [at, CAP_MIN, CAP_MAX])
			if v.has("radius") and "radius" in fields:
				var r: Variant = v["radius"]
				if not (r is int or r is float) or r < RADIUS_MIN or r > RADIUS_MAX:
					errs.append("%s.radius: must be a number %s..%s" % [at, RADIUS_MIN, RADIUS_MAX])
			if v.has("ring") and "ring" in fields and not v["ring"] is bool:
				errs.append(at + ".ring: must be true or false")
	for section: String in ["towers", "enemies"]:
		var want := "tower" if section == "towers" else "enemy"
		var m: Variant = t.get(section, {})
		if not m is Dictionary:
			errs.append(section + ": must be an object")
			continue
		for id: String in m:
			var look: Variant = m[id]
			if not look is String or not kinds.has(look):
				errs.append("%s.%s: \"%s\" is not a look" % [section, id, look])
			elif kinds[look] != want:
				errs.append("%s.%s: \"%s\" is not %s look" % [section, id, look, _a(want)])
	return errs


## "a tower" / "an enemy".
static func _a(kind: String) -> String:
	return ("an " if kind == "enemy" else "a ") + kind


static func _check_color(c: Variant, at: String, errs: Array[String]) -> void:
	if not c is Array or (c.size() != 3 and c.size() != 4):
		errs.append(at + ": must be [r, g, b] or [r, g, b, a]")
		return
	for x: Variant in c:
		if not (x is int or x is float) or x < 0.0 or x > COLOR_MAX:
			errs.append("%s: each channel must be a number 0..%s" % [at, COLOR_MAX])
			return


static func _to_color(c: Array) -> Color:
	return Color(c[0], c[1], c[2], c[3] if c.size() == 4 else 1.0)


## Rebuilds the resolved rows and assignments from the (valid or {}) table in use.
static func _rebuild() -> void:
	_rows = builtin().duplicate()
	var looks: Dictionary = _table.get("looks", {})
	for id: String in looks:
		var v: Dictionary = looks[id]
		var r: Dictionary = (_rows[v["base"]] as Dictionary).duplicate()
		if v.has("color"):
			r["color"] = _to_color(v["color"])
		if v.has("cap"):
			r["cap"] = int(v["cap"])
		if v.has("radius"):
			r["radius"] = float(v["radius"])
		if v.has("ring"):
			r["ring"] = v["ring"]
		_rows[id] = r
	_tower_over = _table.get("towers", {})
	_enemy_over = _table.get("enemies", {})
