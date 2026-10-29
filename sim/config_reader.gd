class_name ConfigReader
extends RefCounted
## Typed field access over parsed JSON for one config file.
## Records every problem as "<file>: <field path>: <message>" and keeps going,
## so one load reports all errors at once. Getters return a fallback value on
## error; callers must check `errors` before trusting the result.

const ID_PATTERN := "^[a-z][a-z0-9_]*$"
## Largest integer a JSON number (a double) holds exactly; also keeps int() from overflowing.
const MAX_SAFE_INT := 9007199254740992.0

var file: String
var errors: Array[String] = []
var _id_regex := RegEx.create_from_string(ID_PATTERN)


func _init(p_file: String) -> void:
	file = p_file


static func join(path: String, key: String) -> String:
	return key if path.is_empty() else "%s.%s" % [path, key]


static func index(path: String, i: int) -> String:
	return "%s[%d]" % [path, i]


static func type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "boolean"
		TYPE_INT, TYPE_FLOAT:
			return "number"
		TYPE_STRING, TYPE_STRING_NAME:
			return "string"
		TYPE_ARRAY:
			return "array"
		TYPE_DICTIONARY:
			return "object"
	return type_string(typeof(value))


## Formats a number for messages: whole numbers without ".0".
static func fmt(v: float) -> String:
	return str(int(v)) if is_finite(v) and v == floorf(v) and absf(v) <= MAX_SAFE_INT else str(v)


func error(path: String, message: String) -> void:
	if path.is_empty():
		errors.append("%s: %s" % [file, message])
	else:
		errors.append("%s: %s: %s" % [file, path, message])


## Reports every key of `obj` not listed in `allowed` (catches typos).
func check_keys(obj: Dictionary, allowed: Array, path: String) -> void:
	for key: Variant in obj:
		if not allowed.has(key):
			error(join(path, str(key)), "unknown field")


## Validates a map key used as an id (tower/enemy ids). Returns false on error.
func check_id(id: String, path: String) -> bool:
	if _id_regex.search(id) == null:
		error(path, "invalid id \"%s\" (expected %s)" % [id, ID_PATTERN])
		return false
	return true


# --- Value checks (for array elements and map values) ---

## Returns the value as a Dictionary, or null after recording a type error.
func as_object(value: Variant, path: String) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		error(path, "expected object, got %s" % type_name(value))
		return null
	return value


## Returns the value as an Array, or null after recording a type error.
func as_array(value: Variant, path: String) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		error(path, "expected array, got %s" % type_name(value))
		return null
	return value


## Checks type and range; returns `fallback` on error.
func as_number(value: Variant, path: String, min_value := -INF, max_value := INF,
		min_exclusive := false, fallback := 0.0) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		error(path, "expected number, got %s" % type_name(value))
		return fallback
	var v := float(value)
	if min_exclusive and v <= min_value:
		error(path, "must be > %s, got %s" % [fmt(min_value), fmt(v)])
		return fallback
	if v < min_value:
		error(path, "must be >= %s, got %s" % [fmt(min_value), fmt(v)])
		return fallback
	if v > max_value:
		error(path, "must be <= %s, got %s" % [fmt(max_value), fmt(v)])
		return fallback
	return v


## Like as_number, plus the value must be a whole number.
func as_int(value: Variant, path: String, min_value := -INF, max_value := INF,
		fallback := 0) -> int:
	if (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) \
			and float(value) != floorf(float(value)):
		error(path, "expected integer, got %s" % str(value))
		return fallback
	var n := errors.size()
	var v := as_number(value, path, maxf(min_value, -MAX_SAFE_INT),
		minf(max_value, MAX_SAFE_INT), false, float(fallback))
	return fallback if errors.size() > n else int(v)


func as_string(value: Variant, path: String, allowed: PackedStringArray = []) -> String:
	if typeof(value) != TYPE_STRING:
		error(path, "expected string, got %s" % type_name(value))
		return ""
	var s: String = value
	if s.is_empty():
		error(path, "must not be empty")
		return ""
	if not allowed.is_empty() and not allowed.has(s):
		error(path, "must be one of [%s], got \"%s\"" % [", ".join(allowed), s])
		return ""
	return s


func as_bool(value: Variant, path: String, fallback := false) -> bool:
	if typeof(value) != TYPE_BOOL:
		error(path, "expected boolean, got %s" % type_name(value))
		return fallback
	return value


# --- Field getters on an object ---

func _require(obj: Dictionary, key: String, path: String) -> bool:
	if obj.has(key):
		return true
	error(join(path, key), "missing required field")
	return false


func req_object(obj: Dictionary, key: String, path: String) -> Variant:
	return as_object(obj[key], join(path, key)) if _require(obj, key, path) else null


func opt_object(obj: Dictionary, key: String, path: String) -> Variant:
	return as_object(obj[key], join(path, key)) if obj.has(key) else {}


func req_array(obj: Dictionary, key: String, path: String) -> Variant:
	return as_array(obj[key], join(path, key)) if _require(obj, key, path) else null


func req_number(obj: Dictionary, key: String, path: String, min_value := -INF,
		max_value := INF, min_exclusive := false) -> float:
	if not _require(obj, key, path):
		return 0.0
	return as_number(obj[key], join(path, key), min_value, max_value, min_exclusive)


func opt_number(obj: Dictionary, key: String, path: String, default: float,
		min_value := -INF, max_value := INF, min_exclusive := false) -> float:
	if not obj.has(key):
		return default
	return as_number(obj[key], join(path, key), min_value, max_value, min_exclusive, default)


func req_int(obj: Dictionary, key: String, path: String, min_value := -INF,
		max_value := INF) -> int:
	if not _require(obj, key, path):
		return 0
	return as_int(obj[key], join(path, key), min_value, max_value)


func req_string(obj: Dictionary, key: String, path: String,
		allowed: PackedStringArray = []) -> String:
	if not _require(obj, key, path):
		return ""
	return as_string(obj[key], join(path, key), allowed)


func opt_string(obj: Dictionary, key: String, path: String, default := "") -> String:
	return as_string(obj[key], join(path, key)) if obj.has(key) else default


func opt_bool(obj: Dictionary, key: String, path: String, default: bool) -> bool:
	return as_bool(obj[key], join(path, key), default) if obj.has(key) else default
