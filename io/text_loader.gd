class_name TextLoader
extends RefCounted
## LT-103 §2.4: the file IO of presentation-only data files (data/effect_text.json), outside
## ui/ like ConfigLoader. These files are never part of GameConfig (golden_data/ does not
## mirror them); the reader validates what it gets (EffectText.validate).


## Reads and parses the JSON file at `path`: {"data": the parsed root (null on failure),
## "errors": Array[String]}. Duplicate object keys are errors too (JSON.parse keeps the last
## one silently; ConfigLoader.find_duplicate_keys finds them in the text).
static func read_json(path: String) -> Dictionary:
	var errors: Array[String] = []
	var data: Variant = null
	if not FileAccess.file_exists(path):
		errors.append("%s: file not found" % path)
		return {"data": data, "errors": errors}
	var text := FileAccess.get_file_as_string(path)
	var open_error := FileAccess.get_open_error()
	if open_error != OK:
		errors.append("%s: cannot read: %s" % [path, error_string(open_error)])
		return {"data": data, "errors": errors}
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s: invalid JSON at line %d: %s" % [path, json.get_error_line() + 1,
			json.get_error_message()])
		return {"data": data, "errors": errors}
	data = json.data
	if typeof(data) == TYPE_DICTIONARY:
		for dup_path in ConfigLoader.find_duplicate_keys(text):
			errors.append("%s: %s: duplicate key" % [path, dup_path])
	return {"data": data, "errors": errors}
