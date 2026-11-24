class_name EffectText
extends RefCounted
## LT-103 §2.4: the player-facing effect text from data/effect_text.json (presentation
## only; the sim catalog, EffectCatalog, holds no text, display order or grouping).
## Static and pure apart from the lazy load on first use; EffectText.use(table) injects a
## table (tests). The file:
##   modes  {Mode name: label}: the Attack cell of each EffectCatalog.Mode
##   lines  [{keys, text, in_row?, defaults?}] in display order: one long line per entry,
##          shown when any of its keys is active (the first key leads); `in_row`: a table
##          row says it already, so special_lines skips it
##   short  [{key, text, when?, keep_case?, defaults?}] in their own order: the parts of the
##          picker's Special cell, shown when `when` holds (default: `key` is active); joined
##          ", ", first letter upper-cased unless the first part has `keep_case`
## `text` is a template, or (lines only) a list of {text, when?} variants, the first whose
## `when` holds wins. `when` is {"key": k, "gt": n}: the value of k > n. A template has
## placeholders {key} or {key|op}; a missing value reads the entry's `defaults`, else 0.
## Ops (OPS): num (the default, TowerText.num), pct (v x 100), pct_over1 ((v - 1) x 100),
## plus1 (1 + v), cells (TowerText.cells_text), plural:one:many (`one` when v == 1).
##   tips   [{key, text}] (optional, LT-122): the hover explanation of the line of `key`,
##          shown when `key` is active. Its placeholders name TIP_VALUES (numbers the sim
##          reads from data/economy.json, TowerText.tip_values), not effect keys.

const PATH := "res://data/effect_text.json"
const OPS := ["num", "pct", "pct_over1", "plus1", "cells", "plural"]
const _LINE_FIELDS := ["keys", "text", "in_row", "defaults"]
const _SHORT_FIELDS := ["key", "text", "when", "keep_case", "defaults"]
const _VARIANT_FIELDS := ["text", "when"]
const _TIP_FIELDS := ["key", "text"]
## LT-122: the placeholders a `tips` template may name (TowerText.tip_values fills them).
const TIP_VALUES := ["shadow_occult_power_mult", "shadow_mundane_fire_interval_mult",
	"shadow_mundane_miss_chance_add"]

static var _table := {}
static var _loaded := false
static var _errors: Array[String] = []


## Replaces the table (tests): returns validate(table). An invalid table is used as {} (every
## key falls back to `key: value`). `table` null: the next use loads PATH again.
static func use(table: Variant) -> Array[String]:
	if table == null:
		_table = {}
		_loaded = false
		_errors = []
		return _errors
	_errors = validate(table)
	_table = table if _errors.is_empty() else {}
	_loaded = true
	return _errors


## The table in use, loaded from PATH on first use. A file that does not read or validate
## fails loudly: each problem goes to push_error (Main refuses to start on errors()), and
## the table is {}.
static func table() -> Dictionary:
	if not _loaded:
		_loaded = true
		var r := TextLoader.read_json(PATH)
		var errs: Array[String] = r["errors"]
		if r["data"] != null:
			errs.append_array(validate(r["data"]))
		_errors = errs
		_table = r["data"] if errs.is_empty() else {}
		for e in errs:
			push_error("EffectText: " + e)
	return _table


## The problems found when the table was loaded or injected (empty: it is valid).
static func errors() -> Array[String]:
	table()
	return _errors


## The `lines` entries in display order.
static func lines() -> Array:
	return table().get("lines", [])


## The keys of every `in_row` line (a table row says them: Attack "Line", Hits "All").
static func in_row_keys() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in lines():
		if entry.get("in_row", false):
			for key: String in entry["keys"]:
				out.append(key)
	return out


## The long line of `entry` (a `lines` entry) for `effects`.
static func line_text(entry: Dictionary, effects: Dictionary) -> String:
	var defaults: Dictionary = entry.get("defaults", {})
	var text: Variant = entry["text"]
	if text is String:
		return format(text, effects, defaults)
	for variant: Dictionary in text:
		if not variant.has("when") or _holds(variant["when"], effects, defaults):
			return format(variant["text"], effects, defaults)
	return ""


## The picker's Special cell parts for `effects`, joined; "" when none applies.
static func short_text(effects: Dictionary) -> String:
	var parts := PackedStringArray()
	var keep_case := false
	for entry: Dictionary in table().get("short", []):
		var defaults: Dictionary = entry.get("defaults", {})
		var shown: bool = _holds(entry["when"], effects, defaults) if entry.has("when") \
			else TowerStatsModel.is_active(effects, entry["key"])
		if not shown:
			continue
		if parts.is_empty():
			keep_case = entry.get("keep_case", false)
		parts.append(format(entry["text"], effects, defaults))
	if parts.is_empty():
		return ""
	var t := ", ".join(parts)
	return t if keep_case else t.substr(0, 1).to_upper() + t.substr(1)


## LT-122: the hover explanations of the tips whose key is active in `effects`, in table
## order, joined by a blank line; a tip naming a value `values` lacks (its config block is
## absent) is left out. "" when none applies.
static func tip_text(effects: Dictionary, values: Dictionary) -> String:
	var parts := PackedStringArray()
	for entry: Dictionary in table().get("tips", []):
		if not TowerStatsModel.is_active(effects, entry["key"]):
			continue
		var tpl: String = entry["text"]
		var complete := true
		for key in _placeholder_keys(tpl):
			if not values.has(key):
				complete = false
		if complete:
			parts.append(format(tpl, values))
	return "\n\n".join(parts)


## The Attack cell label of an EffectCatalog.Mode.
static func mode_label(mode: int) -> String:
	var name: String = EffectCatalog.Mode.find_key(mode)
	return table().get("modes", {}).get(name, name.capitalize())


## `template` with each {key} / {key|op} replaced by the formatted value of `key` in
## `values` (else `defaults`, else 0).
static func format(template: String, values: Dictionary, defaults := {}) -> String:
	var out := ""
	var from := 0
	while true:
		var i := template.find("{", from)
		var j := template.find("}", i) if i >= 0 else -1
		if j < 0:
			break
		out += template.substr(from, i - from) \
			+ _apply(template.substr(i + 1, j - i - 1), values, defaults)
		from = j + 1
	return out + template.substr(from)


## Every problem with `t` as an effect text table (empty: valid): the shape above; every
## catalog key in exactly one `lines` entry; every key named a catalog key; every
## placeholder a catalog key with a known op; every Mode labelled.
static func validate(t: Variant) -> Array[String]:
	var errs: Array[String] = []
	if not t is Dictionary:
		errs.append("root must be an object")
		return errs
	var modes: Variant = t.get("modes")
	if not modes is Dictionary:
		errs.append("modes: must be an object")
	else:
		for name: String in EffectCatalog.Mode.keys():
			if not modes.get(name) is String:
				errs.append("modes.%s: missing label" % name)
		for name: Variant in modes:
			if not EffectCatalog.Mode.has(name):
				errs.append("modes.%s: not an EffectCatalog.Mode" % name)
	var count := {}
	var line_list: Variant = t.get("lines")
	if not line_list is Array:
		errs.append("lines: must be an array")
	else:
		for i in line_list.size():
			var at := "lines[%d]" % i
			var e: Variant = line_list[i]
			if not _check_entry(e, at, _LINE_FIELDS, errs):
				continue
			var keys: Variant = e.get("keys")
			if not keys is Array or keys.is_empty():
				errs.append(at + ".keys: must be a non-empty array")
			else:
				for k: Variant in keys:
					if _check_key(k, at + ".keys", errs):
						count[k] = count.get(k, 0) + 1
			if e.has("in_row") and not e["in_row"] is bool:
				errs.append(at + ".in_row: must be true or false")
			_check_text(e.get("text"), at + ".text", true, errs)
	for k: String in EffectCatalog.keys():
		var n: int = count.get(k, 0)
		if n != 1:
			errs.append("lines: effect key \"%s\" is in %d lines (needs exactly 1)" % [k, n])
	var short_list: Variant = t.get("short")
	if not short_list is Array:
		errs.append("short: must be an array")
	else:
		for i in short_list.size():
			var at := "short[%d]" % i
			var e: Variant = short_list[i]
			if not _check_entry(e, at, _SHORT_FIELDS, errs):
				continue
			_check_key(e.get("key"), at + ".key", errs)
			if e.has("keep_case") and not e["keep_case"] is bool:
				errs.append(at + ".keep_case: must be true or false")
			if e.has("when"):
				_check_when(e["when"], at + ".when", errs)
			_check_text(e.get("text"), at + ".text", false, errs)
	if t.has("tips"):
		_check_tips(t["tips"], errs)
	return errs


## LT-122: `tips` is an array of {key: effect key, text: template over TIP_VALUES}, one per key.
static func _check_tips(tips: Variant, errs: Array[String]) -> void:
	if not tips is Array:
		errs.append("tips: must be an array")
		return
	var seen := {}
	for i in tips.size():
		var at := "tips[%d]" % i
		var e: Variant = tips[i]
		if not _check_entry(e, at, _TIP_FIELDS, errs):
			continue
		var key: Variant = e.get("key")
		if _check_key(key, at + ".key", errs):
			if seen.has(key):
				errs.append("%s.key: \"%s\" has another tip" % [at, key])
			seen[key] = true
		if e.get("text") is String:
			_check_template(e["text"], at + ".text", errs, TIP_VALUES)
		else:
			errs.append(at + ".text: must be a template")


static func _value(key: String, values: Dictionary, defaults: Dictionary) -> float:
	return float(values[key]) if values.has(key) else float(defaults.get(key, 0.0))


static func _holds(when: Dictionary, values: Dictionary, defaults: Dictionary) -> bool:
	return _value(when["key"], values, defaults) > float(when["gt"])


## One placeholder's text: `spec` is "key" or "key|op[:arg...]".
static func _apply(spec: String, values: Dictionary, defaults: Dictionary) -> String:
	var bar := spec.find("|")
	var key := spec if bar < 0 else spec.substr(0, bar)
	var op := PackedStringArray(["num"]) if bar < 0 else spec.substr(bar + 1).split(":")
	var v := _value(key, values, defaults)
	match op[0]:
		"pct":
			return TowerText.num(v * 100.0)
		"pct_over1":
			return TowerText.num((v - 1.0) * 100.0)
		"plus1":
			return TowerText.num(1.0 + v)
		"cells":
			return TowerText.cells_text(TowerText.num(v))
		"plural":
			return op[1] if v == 1.0 else op[2]
	return TowerText.num(v)


## An entry must be an object with only `fields`; its `defaults` name catalog keys.
static func _check_entry(e: Variant, at: String, fields: Array, errs: Array[String]) -> bool:
	if not e is Dictionary:
		errs.append(at + ": must be an object")
		return false
	for f: Variant in e:
		if f not in fields:
			errs.append("%s.%s: unknown field" % [at, f])
	if e.has("defaults"):
		var d: Variant = e["defaults"]
		if not d is Dictionary:
			errs.append(at + ".defaults: must be an object")
		else:
			for k: Variant in d:
				_check_key(k, at + ".defaults", errs)
				if not (d[k] is float or d[k] is int):
					errs.append("%s.defaults.%s: must be a number" % [at, k])
	return true


static func _check_key(k: Variant, at: String, errs: Array[String]) -> bool:
	if k is String and EffectCatalog.has(k):
		return true
	errs.append("%s: \"%s\" is not an effect key" % [at, k])
	return false


static func _check_when(w: Variant, at: String, errs: Array[String]) -> void:
	if not w is Dictionary or w.size() != 2 or not w.has("key") or not w.has("gt"):
		errs.append(at + ": must be {\"key\": <effect key>, \"gt\": <number>}")
		return
	_check_key(w["key"], at + ".key", errs)
	if not (w["gt"] is float or w["gt"] is int):
		errs.append(at + ".gt: must be a number")


static func _check_text(text: Variant, at: String, variants: bool, errs: Array[String]) -> void:
	if text is String:
		_check_template(text, at, errs)
	elif variants and text is Array and not text.is_empty():
		for i in text.size():
			var v_at := "%s[%d]" % [at, i]
			if not _check_entry(text[i], v_at, _VARIANT_FIELDS, errs):
				continue
			if text[i].has("when"):
				_check_when(text[i]["when"], v_at + ".when", errs)
			_check_text(text[i].get("text"), v_at + ".text", false, errs)
	else:
		errs.append(at + (": must be a template or a list of variants" if variants
			else ": must be a template"))


## The keys named by the placeholders of `tpl` (a closed "{...}" each), in order.
static func _placeholder_keys(tpl: String) -> PackedStringArray:
	var out := PackedStringArray()
	var from := 0
	while true:
		var i := tpl.find("{", from)
		var j := tpl.find("}", i) if i >= 0 else -1
		if j < 0:
			return out
		out.append(tpl.substr(i + 1, j - i - 1).get_slice("|", 0))
		from = j + 1
	return out


## `values`, when given (a tip), is the set of names a placeholder may use instead of the
## effect catalog's keys.
static func _check_template(tpl: String, at: String, errs: Array[String],
		values: Array = []) -> void:
	var from := 0
	while true:
		var i := tpl.find("{", from)
		if i < 0:
			return
		var j := tpl.find("}", i)
		if j < 0:
			errs.append("%s: unclosed \"{\" in \"%s\"" % [at, tpl])
			return
		var spec := tpl.substr(i + 1, j - i - 1)
		var bar := spec.find("|")
		var key := spec if bar < 0 else spec.substr(0, bar)
		if values.is_empty():
			_check_key(key, at, errs)
		elif key not in values:
			errs.append("%s: \"%s\" is not a tip value (%s)" % [at, key, ", ".join(values)])
		if bar >= 0:
			var op := spec.substr(bar + 1).split(":")
			if op[0] not in OPS:
				errs.append("%s: unknown op \"%s\"" % [at, op[0]])
			elif op.size() != (3 if op[0] == "plural" else 1):
				errs.append("%s: \"%s\" takes %s" % [at, op[0],
					"two words (plural:one:many)" if op[0] == "plural" else "no argument"])
		from = j + 1
