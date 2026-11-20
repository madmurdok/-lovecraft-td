extends RefCounted
## LT-101: the bot's strategies as data. Loads and validates tools/bot/strategies.json: the
## shared tunables (`build_first`, `flare_min_live`) and one row per strategy (build order as
## `prefix` + `cycle`, L3 `branches`, cap guard `cap_floor` with its `on_blocked` policy,
## `buy_sanity`). Read by tools/bot/bot_strategies.gd (the interpreter), tools/bot_runs.gd
## (the strategy list), tests/golden_runs.gd and tools/balance/balance.py (by json.load).
## Rows are normalized (every key present) and read-only. See
## docs/design/LT-101-bot-strategies-data.md §3.

const Self := preload("res://tools/bot/strategy_table.gd")
const DEFAULT_PATH := "res://tools/bot/strategies.json"
const ROW_KEYS := ["name", "about", "prefix", "cycle", "branches", "cap_floor", "on_blocked",
	"fallback", "fallback_max", "buy_sanity"]
const TUNABLE_KEYS := ["build_first", "flare_min_live"]
const ON_BLOCKED := ["skip", "fallback"]
## A strategy name: lower-case letters, digits and "_", starting with a letter (it is a
## --strategies= item, a balance.py log file name part and the golden key bot/<name>/<seed>).
const NAME_PATTERN := "^[a-z][a-z0-9_]*$"

static var _default: Self = null  ## default() cache

var names: Array[String] = []  ## play order; read-only once parsed
var rows := {}  ## name -> normalized read-only row
var errors: Array[String] = []
## Towers on the board before the bot starts upgrading (and topping the oil up).
var build_first := 0
## Live enemies (reals and fakes) on the map that make the bot fire the flare (LT-57, LT-69).
var flare_min_live := 0


## Parses and validates `text` (validation 1-5 of the design); `errors` lists every problem.
## `names` is read-only afterwards (the shared default() table hands it out).
static func parse_text(text: String) -> Self:
	var t := Self.new()
	t._parse(text)
	t.names.make_read_only()
	return t


## Reads and parses `path`; a missing or unreadable file is an error, not a crash.
static func load_file(path := DEFAULT_PATH) -> Self:
	if not FileAccess.file_exists(path):
		var t := Self.new()
		t.errors.append("file not found (%s)" % path)
		t.names.make_read_only()
		return t
	return parse_text(FileAccess.get_file_as_string(path))


## The shipped table, loaded once per process. Never asserts: a bad file gives a table with
## `errors` set (its valid rows kept), which tools/bot_runs.gd prints before quitting 1.
static func default() -> Self:
	if _default == null:
		_default = load_file()
	return _default


## Validation 6: tower ids against a loaded config. Empty when every id resolves.
func check_towers(cfg: GameConfig) -> Array[String]:
	var errs: Array[String] = []
	for n in names:
		var r: Dictionary = rows[n]
		var ids: Array = r.prefix + r.cycle + r.branches.keys()
		if r.fallback != "":
			ids.append(r.fallback)
		for id in ids:
			if not cfg.towers.has(id):
				errs.append("strategy %s: unknown tower \"%s\"" % [n, id])
		if r.fallback != "" and cfg.towers.has(r.fallback) \
				and cfg.towers[r.fallback].kind == "occult":
			errs.append("strategy %s: fallback \"%s\" is occult" % [n, r.fallback])
		if r.on_blocked == "skip":
			var mundane := false
			for id in r.cycle:
				if cfg.towers.has(id) and cfg.towers[id].kind != "occult":
					mundane = true
			if not mundane:
				errs.append("strategy %s: a \"skip\" cycle needs a non-occult tower" % n)
	return errs


## The normalized row of `name`, or {} for an unknown name.
func row(name: String) -> Dictionary:
	return rows.get(name, {})


func _parse(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("invalid JSON at line %d: %s" % [json.get_error_line() + 1,
			json.get_error_message()])
		return
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append("root must be an object")
		return
	for dup_path in GameConfig.find_duplicate_keys(text):
		errors.append("%s: duplicate key" % dup_path)
	var root: Dictionary = json.data
	for k in root:
		if k not in ["strategies", "tunables"]:
			errors.append("unknown key \"%s\"" % k)
	_read_tunables(root.get("tunables"))
	var list: Variant = root.get("strategies")
	if typeof(list) != TYPE_ARRAY:
		errors.append("strategies: must be an array")
		return
	if list.is_empty():
		errors.append("strategies: must name at least one strategy")
	for i in list.size():
		_read_row(i, list[i])


func _read_tunables(v: Variant) -> void:
	if typeof(v) != TYPE_DICTIONARY:
		errors.append("tunables: must be an object")
		return
	for k in v:
		if k not in TUNABLE_KEYS:
			errors.append("tunables: unknown key \"%s\"" % k)
	for k in TUNABLE_KEYS:
		if not v.has(k):
			errors.append("tunables.%s: missing" % k)
		elif not _is_count(v[k]):
			errors.append("tunables.%s: must be an integer >= 0" % k)
		else:
			set(k, int(v[k]))


func _read_row(i: int, v: Variant) -> void:
	var at := "strategies[%d]" % i
	if typeof(v) != TYPE_DICTIONARY:
		errors.append("%s: must be an object" % at)
		return
	var src: Dictionary = v
	var ok := true
	for k in src:
		if k not in ROW_KEYS:
			errors.append("%s: unknown key \"%s\"" % [at, k])
			ok = false
	var name: Variant = src.get("name")
	if typeof(name) != TYPE_STRING or not _name_ok(name):
		errors.append("%s.name: must match %s (lower-case letters, digits, _)" % [at, NAME_PATTERN])
		ok = false
	elif rows.has(name):
		errors.append("%s.name: duplicate name \"%s\"" % [at, name])
		ok = false
	if src.has("about") and typeof(src.about) != TYPE_STRING:
		errors.append("%s.about: must be a string" % at)
		ok = false
	if src.has("prefix") and not _is_id_list(src.prefix):
		errors.append("%s.prefix: must be an array of tower ids" % at)
		ok = false
	if not src.has("cycle") or not _is_id_list(src.cycle) or src.cycle.is_empty():
		errors.append("%s.cycle: must be a non-empty array of tower ids" % at)
		ok = false
	if src.has("branches"):
		if typeof(src.branches) != TYPE_DICTIONARY:
			errors.append("%s.branches: must be an object" % at)
			ok = false
		else:
			for tower in src.branches:
				if src.branches[tower] not in ["a", "b"]:
					errors.append("%s.branches.%s: must be \"a\" or \"b\"" % [at, tower])
					ok = false
	if src.has("cap_floor") and typeof(src.cap_floor) not in [TYPE_FLOAT, TYPE_INT]:
		errors.append("%s.cap_floor: must be a number" % at)
		ok = false
	if src.has("cap_floor") != src.has("on_blocked"):
		errors.append("%s: cap_floor and on_blocked go together" % at)
		ok = false
	var policy: Variant = src.get("on_blocked", "")
	if src.has("on_blocked") and policy not in ON_BLOCKED:
		errors.append("%s.on_blocked: must be one of %s" % [at, ON_BLOCKED])
		ok = false
	var is_fallback: bool = typeof(policy) == TYPE_STRING and policy == "fallback"
	for k in ["fallback", "fallback_max"]:
		if src.has(k) != is_fallback:
			errors.append("%s.%s: %s" % [at, k, "required by on_blocked \"fallback\"" \
				if is_fallback else "only with on_blocked \"fallback\""])
			ok = false
	if src.has("fallback") and (typeof(src.fallback) != TYPE_STRING or src.fallback == ""):
		errors.append("%s.fallback: must be a tower id" % at)
		ok = false
	if src.has("fallback_max") and not _is_count(src.fallback_max):
		errors.append("%s.fallback_max: must be an integer >= 0" % at)
		ok = false
	if src.has("buy_sanity") and typeof(src.buy_sanity) != TYPE_BOOL:
		errors.append("%s.buy_sanity: must be a bool" % at)
		ok = false
	if not ok:
		return
	var prefix: Array = src.get("prefix", []).duplicate()
	var cycle: Array = src.cycle.duplicate()
	var branches: Dictionary = src.get("branches", {}).duplicate()
	prefix.make_read_only()
	cycle.make_read_only()
	branches.make_read_only()
	var r := {
		"name": name,
		"about": src.get("about", ""),
		"prefix": prefix,
		"cycle": cycle,
		"branches": branches,
		"cap_floor": float(src.cap_floor) if src.has("cap_floor") else null,
		"on_blocked": src.get("on_blocked", ""),
		"fallback": src.get("fallback", ""),
		"fallback_max": int(src.get("fallback_max", 0)),
		"buy_sanity": src.get("buy_sanity", false),
	}
	r.make_read_only()
	rows[name] = r
	names.append(name)


static func _name_ok(name: String) -> bool:
	var m := RegEx.create_from_string(NAME_PATTERN).search(name)
	return m != null and m.get_string() == name  # "$" also matches before a final "\n"


static func _is_id_list(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY:
		return false
	for x in v:
		if typeof(x) != TYPE_STRING or x == "":
			return false
	return true


## An integral number >= 0 (JSON numbers parse as float).
static func _is_count(v: Variant) -> bool:
	if typeof(v) not in [TYPE_FLOAT, TYPE_INT]:
		return false
	return v >= 0 and float(v) == floor(float(v))
