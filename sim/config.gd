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

var towers: Dictionary[String, TowerDef] = {}
var enemies: Dictionary[String, EnemyDef] = {}
var waves: WavesConfig
var economy: EconomyConfig
var sanity: SanityConfig


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

	r = ConfigReader.new(SANITY_FILE)
	var sanity_root: Variant = _read_json(dir, r)
	if sanity_root != null:
		c.sanity = SanityConfig.parse(r, sanity_root)
	result.errors.append_array(r.errors)

	if result.ok:
		result.config = c
	return result


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
	return json.data


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
