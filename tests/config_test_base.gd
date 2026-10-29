class_name ConfigTestBase
extends GdUnitTestSuite
## Shared helpers for the config loader suites: builds config directories in user://
## (a copy of the real res://data, then edited) and checks error lists.

const FILES := ["towers.json", "enemies.json", "waves.json", "economy.json", "sanity.json"]
const ROOT := "user://config_tests"

var _counter := 0


func after() -> void:
	_rm_rf(ROOT)


## Fresh directory holding a copy of res://data.
func make_dir() -> String:
	_counter += 1
	var dir := "%s/%d_%d" % [ROOT, Time.get_ticks_usec(), _counter]
	DirAccess.make_dir_recursive_absolute(dir)
	for f: String in FILES:
		write_file(dir, f, FileAccess.get_file_as_string("res://data/" + f))
	return dir


func write_file(dir: String, file: String, text: String) -> void:
	var fa := FileAccess.open(dir.path_join(file), FileAccess.WRITE)
	assert_object(fa).is_not_null()
	fa.store_string(text)
	fa.close()


func read_file(dir: String, file: String) -> String:
	return FileAccess.get_file_as_string(dir.path_join(file))


## Parses `file`, lets `fn` mutate the root Dictionary, writes it back.
func edit(dir: String, file: String, fn: Callable) -> void:
	var data: Variant = JSON.parse_string(read_file(dir, file))
	assert_bool(data is Dictionary).is_true()
	fn.call(data)
	write_file(dir, file, JSON.stringify(data, "  "))


## Replaces exactly one occurrence of `old` in the file text.
func replace_text(dir: String, file: String, old: String, new: String) -> void:
	var text := read_file(dir, file)
	assert_int(text.count(old)).override_failure_message(
		"fixture text '%s' must occur exactly once in %s" % [old, file]).is_equal(1)
	write_file(dir, file, text.replace(old, new))


## Loads a fresh copy of the data after `fn.call(dir)` edited it.
func load_edited(fn: Callable) -> ConfigLoadResult:
	var dir := make_dir()
	fn.call(dir)
	return GameConfig.load_from_dir(dir)


## Load with one JSON file edited through `fn(root)`.
func load_json_edit(file: String, fn: Callable) -> ConfigLoadResult:
	return load_edited(func(dir: String) -> void: edit(dir, file, fn))


## Load with one text replacement in `file`.
func load_text_edit(file: String, old: String, new: String) -> ConfigLoadResult:
	return load_edited(func(dir: String) -> void: replace_text(dir, file, old, new))


## True if some error starts with "<file>: <path>: " (or "<file>: " when path is empty)
## and contains `fragment`.
func has_error(result: ConfigLoadResult, file: String, path: String, fragment := "") -> bool:
	var prefix := "%s: %s: " % [file, path] if not path.is_empty() else "%s: " % file
	for e in result.errors:
		if e.begins_with(prefix) and (fragment.is_empty() or e.contains(fragment)):
			return true
	return false


## Asserts the load was rejected with an error naming `file` and `path`.
func assert_rejected(result: ConfigLoadResult, file: String, path: String, fragment := "") -> void:
	assert_bool(result.ok).override_failure_message(
		"expected rejection (%s: %s) but config loaded ok" % [file, path]).is_false()
	assert_object(result.config).is_null()
	assert_array(result.errors).is_not_empty()
	assert_bool(has_error(result, file, path, fragment)).override_failure_message(
		"no error for '%s: %s' containing '%s'. Errors:\n%s"
		% [file, path, fragment, "\n".join(result.errors)]).is_true()


func _rm_rf(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_rm_rf(path.path_join(sub))
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(path)
