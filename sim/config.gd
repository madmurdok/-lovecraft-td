class_name GameConfig
extends RefCounted
## All balance data (GDD §10), loaded from JSON files in one directory.
## Pure data: no scene or Node dependencies, so the sim and tests can use it headless.

const DEFAULT_DIR := "res://data"
const TOWERS_FILE := "towers.json"
const ENEMIES_FILE := "enemies.json"
const WAVES_FILE := "waves.json"
const ECONOMY_FILE := "economy.json"
const SANITY_FILE := "sanity.json"
const MAP_FILE := "map.json"

var towers: Dictionary[String, TowerDef] = {}
var enemies: Dictionary[String, EnemyDef] = {}
var waves: WavesConfig
var economy: EconomyConfig
var sanity: SanityConfig
var map: MapDef


## Loads and validates every config file in `dir`. Never returns a partial config:
## on any error `result.ok` is false, `result.config` is null and `result.errors`
## lists every problem found across all files.
static func load_from_dir(dir: String = DEFAULT_DIR) -> ConfigLoadResult:
	var result := ConfigLoadResult.new()
	var c := GameConfig.new()
	var r: ConfigReader

	r = ConfigReader.new(ENEMIES_FILE)
	var enemy_ids: Variant = null  # null = enemies.json unreadable; skip cross-references
	var enemies_root: Variant = _read_json(dir, r)
	if enemies_root != null:
		var map: Variant = _read_id_map(r, enemies_root, "enemies")
		if map != null:
			enemy_ids = map.keys()
			for id: String in map:
				var eo: Variant = r.as_object(map[id], ConfigReader.join("enemies", id))
				if eo != null:
					c.enemies[id] = EnemyDef.parse(r, id, eo, ConfigReader.join("enemies", id))
	result.errors.append_array(r.errors)

	r = ConfigReader.new(TOWERS_FILE)
	var towers_root: Variant = _read_json(dir, r)
	if towers_root != null:
		var map: Variant = _read_id_map(r, towers_root, "towers")
		if map != null:
			for id: String in map:
				var to: Variant = r.as_object(map[id], ConfigReader.join("towers", id))
				if to != null:
					c.towers[id] = TowerDef.parse(r, id, to, ConfigReader.join("towers", id))
			# LT-47 (P11): the board tells towers apart by their glyph.
			var glyph_of: Dictionary[String, String] = {}
			for id: String in c.towers:
				var g: String = c.towers[id].glyph
				if glyph_of.has(g):
					r.error(ConfigReader.join("towers", id),
						"glyph \"%s\" is already used by tower \"%s\"" % [g, glyph_of[g]])
				else:
					glyph_of[g] = id
	result.errors.append_array(r.errors)

	r = ConfigReader.new(WAVES_FILE)
	var waves_root: Variant = _read_json(dir, r)
	if waves_root != null:
		c.waves = WavesConfig.parse(r, waves_root, enemy_ids)
	result.errors.append_array(r.errors)

	r = ConfigReader.new(ECONOMY_FILE)
	var economy_root: Variant = _read_json(dir, r)
	if economy_root != null:
		c.economy = EconomyConfig.parse(r, economy_root)
	result.errors.append_array(r.errors)
	if c.economy != null and not c.economy.relics.is_empty():
		result.errors.append_array(_check_drops(c))

	r = ConfigReader.new(SANITY_FILE)
	var sanity_root: Variant = _read_json(dir, r)
	if sanity_root != null:
		c.sanity = SanityConfig.parse(r, sanity_root)
	result.errors.append_array(r.errors)

	r = ConfigReader.new(MAP_FILE)
	var map_root: Variant = _read_json(dir, r)
	if map_root != null:
		c.map = MapDef.parse(r, map_root)
	result.errors.append_array(r.errors)

	if result.ok:
		result.config = c
	return result


## LT-27 §1.1 cross-file check: every enemy's `drops` key is a relic kind of economy.json
## (reported in enemies.json). Also reorders each enemy's drops into economy.relics order
## (the roll walks that order). Returns the errors.
static func _check_drops(c: GameConfig) -> Array[String]:
	var r := ConfigReader.new(ENEMIES_FILE)
	var kinds := c.economy.relic_ids()
	for id: String in c.enemies:
		var def := c.enemies[id]
		var ordered: Dictionary[String, int] = {}
		for kind in kinds:
			if def.drops.has(kind):
				ordered[kind] = def.drops[kind]
		for kind: String in def.drops:
			if not kinds.has(kind):
				r.error(ConfigReader.join(ConfigReader.join(ConfigReader.join("enemies", id),
					"drops"), kind), "unknown relic kind \"%s\"" % kind)
		def.drops = ordered
	return r.errors


## Reads `<dir>/<r.file>` and returns its root object, or null after recording why not.
static func _read_json(dir: String, r: ConfigReader) -> Variant:
	var full := dir.path_join(r.file)
	if not FileAccess.file_exists(full):
		r.error("", "file not found (%s)" % full)
		return null
	var text := FileAccess.get_file_as_string(full)
	var open_error := FileAccess.get_open_error()
	if open_error != OK:
		r.error("", "cannot read (%s): %s" % [full, error_string(open_error)])
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		r.error("", "invalid JSON at line %d: %s" % [json.get_error_line() + 1,
			json.get_error_message()])
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		r.error("", "root must be an object, got %s" % ConfigReader.type_name(json.data))
		return null
	# JSON.parse keeps the last of duplicate keys, so a duplicate id or field
	# would silently win; find them in the text instead.
	for dup_path in find_duplicate_keys(text):
		r.error(dup_path, "duplicate key")
	return json.data


## Field paths (e.g. "towers.rifleman.cost") of keys that repeat inside one JSON
## object. Expects text that JSON.parse accepted. Keys are compared as written
## (escape sequences are not decoded).
static func find_duplicate_keys(text: String) -> Array[String]:
	var dups: Array[String] = []
	# One frame per open object/array: {"obj": bool, "keys": {}, "label": String}.
	var stack: Array[Dictionary] = []
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		if ch == "\"":
			var start := i + 1
			i += 1
			while i < n and text[i] != "\"":
				i += 2 if text[i] == "\\" else 1
			var s := text.substr(start, i - start)
			i += 1
			if not stack.is_empty() and stack[-1]["obj"]:
				var j := i
				while j < n and text[j] in " \t\r\n":
					j += 1
				if j < n and text[j] == ":":
					var frame: Dictionary = stack[-1]
					frame["label"] = s
					if frame["keys"].has(s):
						dups.append(_frame_path(stack))
					frame["keys"][s] = true
			continue
		match ch:
			"{":
				stack.append({"obj": true, "keys": {}, "label": ""})
			"[":
				stack.append({"obj": false, "keys": {}, "label": "0"})
			"}", "]":
				stack.pop_back()
			",":
				if not stack.is_empty() and not stack[-1]["obj"]:
					stack[-1]["label"] = str(int(stack[-1]["label"]) + 1)
		i += 1
	return dups


static func _frame_path(stack: Array[Dictionary]) -> String:
	var path := ""
	for frame in stack:
		if frame["obj"]:
			path = ConfigReader.join(path, frame["label"])
		else:
			path = ConfigReader.index(path, int(frame["label"]))
	return path


## Root of towers/enemies.json: {"<key>": {"<id>": {...}, ...}}. Returns the id map
## with invalid ids already reported (and dropped), or null.
static func _read_id_map(r: ConfigReader, root: Dictionary, key: String) -> Variant:
	r.check_keys(root, [key], "")
	var map: Variant = r.req_object(root, key, "")
	if map == null:
		return null
	if map.is_empty():
		r.error(key, "must not be empty")
	var out := {}
	for id: Variant in map:
		if r.check_id(str(id), ConfigReader.join(key, str(id))):
			out[id] = map[id]
	return out
