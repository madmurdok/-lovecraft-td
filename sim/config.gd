class_name GameConfig
extends RefCounted
## All balance data (GDD §10), built from parsed JSON roots (one per config file;
## ConfigLoader reads them from a directory).
## Pure data: no scene or Node dependencies, so the sim and tests can use it headless.
##
## Sections (LT-100): every config file is one row of `_sections()`; checks that span
## files are in `_cross_checks()` and run after all sections.
## Rule: a new mechanic's config is an OPTIONAL block (an optional key inside an existing
## file, as economy.json lighthouse.oil / lighthouse.flare; or a new file in a
## `required = false` row), and an absent block means the mechanic is OFF. Existing
## configs and fixtures then load unchanged, so suites that do not use the mechanic stay
## green. Adding a new optional file takes exactly one registry row (plus its field and
## parser).

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


## Builds and validates a config from already-parsed file roots (LT-102: the file IO is
## ConfigLoader's, outside sim/). Never returns a partial config: on any error `result.ok`
## is false, `result.config` is null and `result.errors` lists every problem found across
## all files. `roots`: file name ("towers.json") -> parsed root, any Variant (a Dictionary
## to be valid); a file absent from `roots` was not read. `read_errors`: file name -> Array
## of [path, message] recorded while reading that file (not found, unreadable, bad JSON,
## duplicate keys); they lead that file's errors, so the per-file error order is the one a
## read-then-parse load produces. A required section with no root and no read error gets
## "<file>: missing"; an optional one is off, no error. The config may keep references to
## sub-dictionaries of `roots` (e.g. pack traits): the caller hands them over. `sections`
## replaces the registry (tests only: they inject an optional row no shipped file uses);
## empty means `_sections()`.
static func from_dicts(roots: Dictionary, read_errors: Dictionary = {},
		sections: Array[Array] = []) -> ConfigLoadResult:
	var result := ConfigLoadResult.new()
	var c := GameConfig.new()
	var ctx := {}  # values a later section's parser reads from an earlier one (enemy_ids)
	for row: Array in (sections if not sections.is_empty() else _sections()):
		var file: String = row[0]
		var parse: Callable = row[1]
		var required: bool = row[2]
		var r := ConfigReader.new(file)
		var read: Array = read_errors.get(file, [])
		for e: Array in read:
			r.error(e[0], e[1])
		if roots.has(file):
			var root: Variant = roots[file]
			if typeof(root) != TYPE_DICTIONARY:
				r.error("", "root must be an object, got %s" % ConfigReader.type_name(root))
			else:
				# Parse step: pure, from the parsed root only.
				parse.call(r, root, c, ctx)
		elif required and read.is_empty():
			r.error("", "missing")
		result.errors.append_array(r.errors)
	for check: Callable in _cross_checks():
		result.errors.append_array(check.call(c))
	if result.ok:
		result.config = c
	return result


## The files a loader reads, as [file, required] pairs in registry order: from `sections`
## (the same test seam as from_dicts) or, when empty, `_sections()`. One table: a loader
## never keeps its own file list.
static func section_files(sections: Array[Array] = []) -> Array[Array]:
	var files: Array[Array] = []
	for row: Array in (sections if not sections.is_empty() else _sections()):
		files.append([row[0], row[2]])
	return files


## The section registry: one [file, parser, required] row per config file, loaded in this
## order (which is also the order of their errors). A parser is
## `func(r: ConfigReader, root: Dictionary, c: GameConfig, ctx: Dictionary) -> void`: it
## reports into `r` and fills its part of `c`; it may read what an earlier row put in `ctx`.
## A required row whose file is missing is an error ("file not found"); an optional row
## (required = false) whose file is missing leaves its part of `c` at the default (off).
static func _sections() -> Array[Array]:
	return [
		[ENEMIES_FILE, _parse_enemies, true],
		[TOWERS_FILE, _parse_towers, true],
		[WAVES_FILE, _parse_waves, true],
		[ECONOMY_FILE, _parse_economy, true],
		[SANITY_FILE, _parse_sanity, true],
		[MAP_FILE, _parse_map, true],
	]


## Checks that span sections, run after every section is loaded, in this order. Each is
## `func(c: GameConfig) -> Array[String]` (formatted errors) and must cope with a section
## that is null (missing or broken).
static func _cross_checks() -> Array[Callable]:
	return [_check_drops]


static func _parse_enemies(r: ConfigReader, root: Dictionary, c: GameConfig,
		ctx: Dictionary) -> void:
	var map: Variant = _read_id_map(r, root, "enemies")
	if map == null:
		return
	# Waves resolve enemy references against every listed id, valid or not; absent
	# (enemies.json unreadable) means waves skip the cross-references.
	ctx["enemy_ids"] = map.keys()
	for id: String in map:
		var eo: Variant = r.as_object(map[id], ConfigReader.join("enemies", id))
		if eo != null:
			c.enemies[id] = EnemyDef.parse(r, id, eo, ConfigReader.join("enemies", id))


static func _parse_towers(r: ConfigReader, root: Dictionary, c: GameConfig,
		_ctx: Dictionary) -> void:
	var map: Variant = _read_id_map(r, root, "towers")
	if map == null:
		return
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


static func _parse_waves(r: ConfigReader, root: Dictionary, c: GameConfig,
		ctx: Dictionary) -> void:
	c.waves = WavesConfig.parse(r, root, ctx.get("enemy_ids"))


static func _parse_economy(r: ConfigReader, root: Dictionary, c: GameConfig,
		_ctx: Dictionary) -> void:
	c.economy = EconomyConfig.parse(r, root)


static func _parse_sanity(r: ConfigReader, root: Dictionary, c: GameConfig,
		_ctx: Dictionary) -> void:
	c.sanity = SanityConfig.parse(r, root)


static func _parse_map(r: ConfigReader, root: Dictionary, c: GameConfig,
		_ctx: Dictionary) -> void:
	c.map = MapDef.parse(r, root)


## LT-67 (debug `--sandbox`, set by scenes/game.gd): a copy of this config whose
## economy.starting_gold is `gold` and, with an oil block, oil.start = oil.cap (the cap
## stays). Everything else is shared with this config, which is left unchanged.
func sandboxed(gold: int) -> GameConfig:
	var c: GameConfig = _shallow_copy(self, GameConfig.new())
	c.economy = _shallow_copy(economy, EconomyConfig.new())
	c.economy.starting_gold = gold
	if economy.oil != null:
		c.economy.oil = _shallow_copy(economy.oil, EconomyConfig.OilConfig.new())
		c.economy.oil.start = c.economy.oil.cap
	return c


## Copies every script variable of `from` into `to` (by reference) and returns `to`.
static func _shallow_copy(from: RefCounted, to: RefCounted) -> RefCounted:
	for p in from.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			to.set(p["name"], from.get(p["name"]))
	return to


## LT-27 §1.1 cross-file check: every enemy's `drops` key is a relic kind of economy.json
## (reported in enemies.json). Also reorders each enemy's drops into economy.relics order
## (the roll walks that order). Skipped when economy.json failed or lists no relics.
## Returns the errors.
static func _check_drops(c: GameConfig) -> Array[String]:
	var r := ConfigReader.new(ENEMIES_FILE)
	if c.economy == null or c.economy.relics.is_empty():
		return r.errors
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
