class_name ConfigLoader
extends RefCounted
## LT-102 (D-2): the config file IO, outside sim/. Reads every file of GameConfig's section
## registry from one directory, parses the JSON and hands the roots and the read errors to
## GameConfig.from_dicts, which validates them. sim/ never touches FileAccess or JSON.

const DEFAULT_DIR := "res://data"


## Loads and validates every config file in `dir`. Never returns a partial config: on any
## error `result.ok` is false, `result.config` is null and `result.errors` lists every
## problem found across all files. A required file is always read (absent: "file not
## found"); an optional one only when it exists. `sections` replaces the registry (tests
## only, passed through to from_dicts); empty means GameConfig's own rows.
static func load_dir(dir: String = DEFAULT_DIR, sections: Array[Array] = []) \
		-> ConfigLoadResult:
	var roots := {}
	var read_errors := {}
	for entry: Array in GameConfig.section_files(sections):
		var file: String = entry[0]
		var required: bool = entry[1]
		if required or FileAccess.file_exists(dir.path_join(file)):
			_read(dir, file, roots, read_errors)
	return GameConfig.from_dicts(roots, read_errors, sections)


## Reads `<dir>/<file>`: on success `roots[file]` is the parsed root; every problem is a
## [path, message] pair appended to `read_errors[file]`. Duplicate keys are looked for only
## in a Dictionary root (from_dicts reports any other root as "root must be an object").
static func _read(dir: String, file: String, roots: Dictionary, read_errors: Dictionary) \
		-> void:
	var errors: Array = []
	var full := dir.path_join(file)
	if not FileAccess.file_exists(full):
		errors.append(["", "file not found (%s)" % full])
	else:
		var text := FileAccess.get_file_as_string(full)
		var open_error := FileAccess.get_open_error()
		if open_error != OK:
			errors.append(["", "cannot read (%s): %s" % [full, error_string(open_error)]])
		else:
			var json := JSON.new()
			if json.parse(text) != OK:
				errors.append(["", "invalid JSON at line %d: %s" % [json.get_error_line() + 1,
					json.get_error_message()]])
			else:
				roots[file] = json.data
				if typeof(json.data) == TYPE_DICTIONARY:
					# JSON.parse keeps the last of duplicate keys, so a duplicate id or field
					# would silently win; find them in the text instead.
					for dup_path in find_duplicate_keys(text):
						errors.append([dup_path, "duplicate key"])
	if not errors.is_empty():
		read_errors[file] = errors


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
