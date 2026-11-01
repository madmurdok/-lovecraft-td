class_name SimBoundaryTest
extends SimTestBase
## LT-34/S2: the sim / presentation boundary guard (docs/design/LT-33-sim-presentation-boundary.md,
## "Proposed automated guard"). Static scans of the sources found by path under res://:
##  1. sim/ uses only its own types and a pinned engine allowlist (no Node, Tween, Engine, OS,
##     Time, Input, Color, ...; all-capitals engine classes such as OS or IP too, LT-36), none
##     of the forbidden tokens (signal, await, get_tree, frame callbacks, global RNG, scene loads);
##  2. scenes/, ui/ and tools/ never reach a private Simulation member (`sim._x`, or any
##     `_name` declared in simulation.gd, static ones included) or write sim.state / sim.config:
##     no assignment at any depth, no mutator call (append, erase, ...), and none through a
##     local alias of SimState or of something inside it (LT-36); LT-42: nor a state-changing
##     method of a state class, nor through a typed state-class parameter, a getter, a class
##     field, a same-file call's parameter or an inner class (see _state_writes);
##  3. is_fake stays out of presentation (render_isolation_test is the main guard and must stay);
## and two runtime proofs: the sim plays a whole game without a SceneTree, and a Game driven
## by uneven frames ends in the state a bare Simulation reaches by stepping the same commands.

const SIM_DIR := "res://sim"
const PRESENTATION_DIRS := ["res://scenes", "res://ui", "res://tools"]
const SIMULATION := "res://sim/core/simulation.gd"
## Engine types sim/ may name today (computed from the code once and pinned, LT-34/S2).
const ENGINE_ALLOWLIST := [
	"Array", "Dictionary", "FileAccess", "JSON", "PackedByteArray", "PackedInt64Array",
	"PackedStringArray", "RandomNumberGenerator", "RefCounted", "RegEx", "String", "Variant",
	"Vector2", "Vector2i",
]
## Matched on the code of a sim file with comments and string literals blanked.
const SIM_FORBIDDEN_CODE := [
	"\\bsignal\\b",
	"\\bawait\\b",
	"\\bpreload\\b",
	"\\bget_tree\\b",
	"\\bget_node\\b",
	"\\bget_parent\\b",
	"\\bcreate_tween\\b",
	"\\bqueue_free\\b",
	"\\$[A-Za-z_]",
	"func\\s+_(process|physics_process|input|unhandled_input|unhandled_key_input|ready|draw|enter_tree|exit_tree|notification)\\b",
	"(?<![.\\w])(randf|randi|randf_range|randi_range|randfn|randomize|seed|rand_from_seed)\\s*\\(",
]
## Matched on the code with comments removed but string literals kept.
const SIM_FORBIDDEN_WITH_STRINGS := [
	"\\bload\\s*\\(\\s*\"res://(scenes|ui|shaders|assets|tools)",
	"\"res://(scenes|ui|shaders|assets)/",
]
## A member or index step of an access chain: `.x` or `[...]`.
const CHAIN := "(?:\\.\\w+|\\[[^\\]]*\\])"
## An assignment operator (not ==, <=, >=, !=).
const ASSIGN := "\\s*(?:=(?!=)|[-+*/%|&^]=|<<=|>>=)"
## LT-42 (S5): an Array method returning one of its elements (`towers.back()`), not a copy.
const ELEMENT_CALL := "\\.(?:back|front|get|pick_random|pop_back|pop_front|pop_at|min|max)" \
	+ "\\s*\\([^()]*\\)"
## An access chain that may take one element by a call: `.towers.back().def`.
const TAIL := CHAIN + "*(?:" + ELEMENT_CALL + CHAIN + "*)?"
## One element of a container: `[i]` or an ELEMENT_CALL.
const ELEMENT_STEP := "(?:\\[[^\\]]*\\]|" + ELEMENT_CALL + ")"
## Array / Dictionary / Object methods that change their receiver.
const MUTATORS := "(?:append|append_array|assign|clear|erase|fill|insert|merge|pop_at|pop_back" \
	+ "|pop_front|push_back|push_front|remove_at|resize|reverse|set|shuffle|sort|sort_custom)"
## Writes at any depth below sim.state / sim.config (LT-36: nested, `sim.state.map.x = 1`).
const WRITE_PATTERNS := [
	"\\.state" + CHAIN + "+" + ASSIGN,
	"\\.config" + CHAIN + "+" + ASSIGN,
]
const STEPS_AFTER_FRAMES := 3000

var _vp: SubViewport
var _state_types_cache := {}
var _mutators_cache := ""
var _sim_getters_cache: Array = []


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null


# --- scanning helpers ------------------------------------------------------------------

## Every .gd file below `dir` (a res:// path), sorted.
func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		if not sub.begins_with("."):
			out.append_array(_gd_files(dir.path_join(sub)))
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	out.sort()
	return out


## `line` without its `#` comment; string literals are blanked ("") unless `keep_strings`.
func _code_of(line: String, keep_strings := false) -> String:
	var out := ""
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				if keep_strings:
					out += line.substr(i, 2)
				i += 2
				continue
			if c == quote:
				quote = ""
				out += c
			elif keep_strings:
				out += c
			i += 1
			continue
		if c == "#":
			break
		if c == "\"" or c == "'":
			quote = c
		out += c
		i += 1
	return out


## [line number, code] pairs of a source text.
func _code_lines(text: String, keep_strings := false) -> Array:
	var out := []
	var lines := text.split("\n")
	for i in lines.size():
		out.append([i + 1, _code_of(lines[i], keep_strings)])
	return out


## `file:line: match` for every hit of `pattern` in the code lines.
func _find(file: String, code_lines: Array, pattern: String) -> Array[String]:
	var re := RegEx.create_from_string(pattern)
	var out: Array[String] = []
	for entry: Array in code_lines:
		for m in re.search_all(entry[1]):
			out.append("%s:%d: %s" % [file, entry[0], m.get_string()])
	return out


## Own type names: every class_name, `class X` and `enum X` declared under sim/.
func _own_types(files: Array[String]) -> Dictionary:
	var re := RegEx.create_from_string("(?m)^\\s*(?:class_name|class|enum)\\s+([A-Z]\\w*)")
	var own := {}
	for f in files:
		for m in re.search_all(FileAccess.get_file_as_string(f)):
			own[m.get_string(1)] = true
	return own


## PascalCase identifiers (a capital, then at least one lower-case letter somewhere; ALL_CAPS
## constants are not types) that are neither own types nor on the engine allowlist.
func _foreign_types(file: String, text: String, own: Dictionary) -> Array[String]:
	var re := RegEx.create_from_string("\\b[A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*\\b")
	var out: Array[String] = []
	for entry: Array in _code_lines(text):
		for m in re.search_all(entry[1]):
			var name := m.get_string()
			if not own.has(name) and not ENGINE_ALLOWLIST.has(name):
				out.append("%s:%d: %s" % [file, entry[0], name])
	return out


func _private_members_of_simulation() -> Array[String]:
	return _private_members_of(FileAccess.get_file_as_string(SIMULATION))


## `_name`s declared at the top level of `text` (func, static func, var, const), _init aside.
func _private_members_of(text: String) -> Array[String]:
	var re := RegEx.create_from_string("(?m)^(?:static\\s+)?(?:func|var|const)\\s+(_[a-z]\\w*)")
	var out: Array[String] = []
	for m in re.search_all(text):
		var name := m.get_string(1)
		if name != "_init" and not out.has(name):
			out.append(name)
	return out


func _presentation_files() -> Array[String]:
	var out: Array[String] = []
	for dir: String in PRESENTATION_DIRS:
		out.append_array(_gd_files(dir))
	return out


## LT-36 (F2): all-capitals identifiers naming an engine class, singleton or built-in type
## (OS, JSON, IP, AABB, ...), which the PascalCase scan skips, unless own or in `allow`.
## A member after a dot (Type.SHOT) and constants or enum values (SIGN, TYPE_INT) are not.
func _engine_caps(file: String, text: String, own: Dictionary, allow: Array) -> Array[String]:
	var builtin := {}
	for t in TYPE_MAX:
		builtin[type_string(t)] = true
	var re := RegEx.create_from_string("(?<![.\\w])[A-Z][A-Z0-9_]*\\b")
	var out: Array[String] = []
	for entry: Array in _code_lines(text):
		for m in re.search_all(entry[1]):
			var name := m.get_string()
			if own.has(name) or allow.has(name):
				continue
			if ClassDB.class_exists(name) or Engine.has_singleton(name) or builtin.has(name):
				out.append("%s:%d: %s" % [file, entry[0], name])
	return out


## LT-42: classes whose instances live inside sim.state / sim.config: SimState and GameConfig,
## then every own class named in a member (a class-level `var x: T`, `Array[T]`, ...) of one of
## them, transitively; inner classes as `Outer.Inner`. Type name -> source text ("" for inner
## ones). Locals (`var r: ConfigReader` inside a func) do not count.
func _state_types() -> Dictionary:
	if not _state_types_cache.is_empty():
		return _state_types_cache
	var texts := {}
	var cn := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	for f in _gd_files(SIM_DIR):
		var text := FileAccess.get_file_as_string(f)
		var m := cn.search(text)
		if m != null:
			texts[m.get_string(1)] = text
	var decl := RegEx.create_from_string("^\\s*var\\s+\\w+\\s*:\\s*([^=]+)")
	var word := RegEx.create_from_string("\\b[A-Z]\\w*")
	var inner := RegEx.create_from_string("(?m)^\\s*class\\s+(\\w+)")
	var todo: Array[String] = ["SimState", "GameConfig"]
	while not todo.is_empty():
		var t: String = todo.pop_back()
		if _state_types_cache.has(t) or not texts.has(t):
			continue
		_state_types_cache[t] = texts[t]
		for m in inner.search_all(texts[t]):
			_state_types_cache[t + "." + m.get_string(1)] = ""
		for s: Dictionary in _scopes(_code_lines(texts[t])):
			if s.kind != "class":
				continue
			for entry: Array in s.lines:
				var m := decl.search(entry[1])
				if m != null:
					for w in word.search_all(m.get_string(1)):
						todo.append(w.get_string())
	return _state_types_cache


## `(?:SimState|SimTower|TowerDef\.Level|...)`, longest first, for a type annotation.
func _state_type_pattern() -> String:
	var names: Array = _state_types().keys()
	names.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	return "(?:%s)(?![.\\w])" % "|".join(names.map(func(n: String) -> String:
		return n.replace(".", "\\.")))


## LT-42: `Array[<state type>]`, for a type annotation of a container of state objects.
func _state_array_pattern() -> String:
	return "Array\\[\\s*" + _state_type_pattern() + "\\s*\\]"


## LT-42 (S5): public, non-static funcs declared under sim/ (Simulation's queries) that return
## a state-class object ([0]: `tower_by_id -> SimTower`) or an Array of them ([1]:
## `enemies_in_range -> Array[SimEnemy]`), from their declared return types.
func _sim_getters() -> Array:
	if not _sim_getters_cache.is_empty():
		return _sim_getters_cache
	var one := RegEx.create_from_string("^\\s*" + _state_type_pattern() + "\\s*$")
	var many := RegEx.create_from_string("^\\s*" + _state_array_pattern() + "\\s*$")
	var head := RegEx.create_from_string(
		"(?m)^\\s*func\\s+([a-z]\\w*)\\s*\\([^)]*\\)\\s*->\\s*([^:\\n]+):")
	var direct: Array[String] = []
	var arrays: Array[String] = []
	for f in _gd_files(SIM_DIR):
		for m in head.search_all(FileAccess.get_file_as_string(f)):
			var n := m.get_string(1)
			if one.search(m.get_string(2)) != null and not direct.has(n):
				direct.append(n)
			elif many.search(m.get_string(2)) != null and not arrays.has(n):
				arrays.append(n)
	_sim_getters_cache = [direct, arrays]
	return _sim_getters_cache


## LT-42: MUTATORS plus the methods of the `_state_types()` classes that change their own
## object: a non-static method (not _init) that assigns a member, calls a mutator on one, or
## calls another such method of the same file. `(?:append|...|reset_modifiers|...)`.
func _mutators() -> String:
	if _mutators_cache != "":
		return _mutators_cache
	var found: Array[String] = []
	for t: String in _state_types():
		var text: String = _state_types()[t]
		if text == "":
			continue
		var scopes := _scopes(_code_lines(text))
		var members: Array[String] = []
		var var_re := RegEx.create_from_string("^\\s*var\\s+(\\w+)")
		for s: Dictionary in scopes:
			if s.kind == "class":
				for entry: Array in s.lines:
					var m := var_re.search(entry[1])
					if m != null:
						members.append(m.get_string(1))
		var own: Array[String] = []
		while true:
			var n := own.size()
			var heads: Array[String] = []
			if not members.is_empty():
				var mem := "(?<![.\\w])(?:self\\.)?(?:%s)" % "|".join(members)
				heads.append(mem + CHAIN + "*" + ASSIGN)
				heads.append(mem + CHAIN + "*\\." + MUTATORS + "\\s*\\(")
			if not own.is_empty():
				heads.append("(?<![.\\w])(?:self\\.)?(?:%s)\\s*\\(" % "|".join(own))
			for s: Dictionary in scopes:
				if s.kind != "func" or s.is_static or s.name == "_init" or own.has(s.name):
					continue
				for p in heads:
					if not _find("", s.lines.slice(1), p).is_empty():
						own.append(s.name)
						break
			if own.size() == n:
				break
		for n in own:
			if not found.has(n):
				found.append(n)
	_mutators_cache = MUTATORS if found.is_empty() \
		else "(?:%s|%s)" % [MUTATORS, "|".join(found)]
	return _mutators_cache


## LT-42: the scopes of a source (code lines): [0] the script's class body, then one per inner
## `class` body and one per func (static and inner-class ones too), in order. A line belongs to
## the innermost scope its indentation is in. Each scope: {kind ("class"/"func"), name, lines,
## owner (index of its class scope; -1 for [0]), indent, params (names), is_static}.
## A func's params are read from its header line only.
func _scopes(code: Array) -> Array:
	var scopes: Array = [{kind = "class", name = "", lines = [], owner = -1, indent = -1,
		params = [], is_static = false}]
	var class_re := RegEx.create_from_string("^\\s*class\\s+(\\w+)")
	var func_re := RegEx.create_from_string("^\\s*(static\\s+)?func\\s+(\\w+)\\s*\\(([^)]*)")
	var param_re := RegEx.create_from_string("^\\s*(\\w+)")
	var stack: Array[int] = [0]
	for entry: Array in code:
		var line: String = entry[1]
		if line.strip_edges() == "":
			scopes[stack.back()].lines.append(entry)
			continue
		var indent := line.length() - line.lstrip(" \t").length()
		while scopes[stack.back()].indent >= indent:
			stack.pop_back()
		var c := class_re.search(line)
		var f := func_re.search(line)
		if c != null or f != null:
			var owner := 0
			for k in range(stack.size() - 1, -1, -1):
				if scopes[stack[k]].kind == "class":
					owner = stack[k]
					break
			var params: Array[String] = []
			if f != null:
				for p in f.get_string(3).split(","):
					var m := param_re.search(p)
					if m != null:
						params.append(m.get_string(1))
			stack.append(scopes.size())
			scopes.append({kind = "class" if c != null else "func",
				name = c.get_string(1) if c != null else f.get_string(2), lines = [],
				owner = owner, indent = indent, params = params,
				is_static = f != null and f.get_string(1) != ""})
		scopes[stack.back()].lines.append(entry)
	return scopes


## LT-42: a head naming a state object: one of `names` (also `self.name`, S5), or a call of
## one of `getters` (also `obj.getter()`, `game.sim.tower_by_id(id)`). "" when both are empty.
func _alias_head(names: Array, getters: Array) -> String:
	var alts: Array[String] = []
	if not names.is_empty():
		alts.append("(?<![.\\w])(?:self\\.)?(?:%s)" % "|".join(names))
	if not getters.is_empty():
		alts.append("(?<![\\w.])(?:[\\w.]*\\.)?(?:%s)\\s*\\([^()]*\\)" % "|".join(getters))
	return "" if alts.is_empty() else "(?:%s)" % "|".join(alts)


## LT-42: an expression whose value is a state object: `sim.state` / `.config` or a `head`
## (`_alias_head`), then a TAIL (`.towers[0]`, `.towers.back().def`), or one element of a
## container `elems` (`ts[0]`, `ts.back()`; S5). With `whole_container`, `elems` itself too
## (the source of a `for`).
func _state_value(head: String, elems: String, whole_container := false) -> String:
	var alts: Array[String] = [
		"(?:[\\w.]*\\.(?:state|config)%s)%s" % ["" if head == "" else "|" + head, TAIL]]
	if elems != "":
		alts.append(elems + ("(?:%s%s)?" if whole_container else "%s%s") % [ELEMENT_STEP, TAIL])
	return "(?:%s)" % "|".join(alts)


## LT-42: what writes through `head`: an assignment below it, or a mutator call on it or on
## anything below it (also past an element call: `s.towers.back().level = 3`).
func _write_patterns(head: String, mut: String) -> Array[String]:
	return [
		head + CHAIN + "+" + ASSIGN,
		head + CHAIN + "*" + ELEMENT_CALL + CHAIN + "+" + ASSIGN,
		head + TAIL + "\\." + mut + "\\s*\\(",
	]


## LT-36 (F3): names bound to SimState / GameConfig or to something inside them in one scope
## (code lines): `var s := game.sim.state[.x...]` (or `.config`), `s: SimState` (a var or a
## parameter; LT-42: any `_state_types()` class, `t: SimTower`) and `for t in sim.state.towers:`,
## also through `known` names and calls of `getters` (`var s := s0.x`, `for t in get_s().towers:`).
## LT-42 (S5): also a plain assignment in the scope (`var s = null` then `s = sim.state`), an
## element call (`var t := sim.state.towers.back()`), and an element of / a `for` over a
## container `elems` (`_containers`).
## A call ends the chain: `var c := sim.state.towers.duplicate()` is a copy, not an alias.
## Returns `known` plus the names found.
func _state_aliases(code_lines: Array, known: Array = [], getters: Array = [],
		elems := "") -> Array[String]:
	var names: Array[String] = []
	names.assign(known)
	var typed := RegEx.create_from_string("\\b(\\w+)\\s*:\\s*" + _state_type_pattern())
	while true:
		var head := _alias_head(names, getters)
		var src := _state_value(head, elems)
		var res: Array[RegEx] = [
			RegEx.create_from_string("\\bvar\\s+(\\w+)[^=]*=\\s*" + src + "\\s*$"),
			RegEx.create_from_string("^\\s*(?:self\\.)?(\\w+)\\s*=(?!=)\\s*" + src + "\\s*$"),
			RegEx.create_from_string("\\bfor\\s+(\\w+)(?:\\s*:\\s*\\w+)?\\s+in\\s+"
				+ _state_value(head, elems, true) + "\\s*:"),
			typed,
		]
		var found := names.size()
		for entry: Array in code_lines:
			for re in res:
				for m in re.search_all(entry[1]):
					var n := m.get_string(1)
					if n != "self" and not names.has(n):
						names.append(n)
		if names.size() == found:
			break
	return names


## LT-42 (S5): names in one scope holding a container of state objects: `ts: Array[SimTower]`
## (a var or a parameter) and `var es := game.sim.enemies_in_range(...)` (an Array getter).
## Their elements are aliases; the container itself is not (it may be a fresh Array).
func _containers(code_lines: Array, array_getters: Array) -> Array[String]:
	var res: Array[RegEx] = [
		RegEx.create_from_string("\\b(\\w+)\\s*:\\s*" + _state_array_pattern())]
	if not array_getters.is_empty():
		res.append(RegEx.create_from_string("\\bvar\\s+(\\w+)[^=]*=\\s*"
			+ _alias_head([], array_getters) + "\\s*$"))
	var out: Array[String] = []
	for entry: Array in code_lines:
		for re in res:
			for m in re.search_all(entry[1]):
				if not out.has(m.get_string(1)):
					out.append(m.get_string(1))
	return out


## LT-42: [callee, args] for every call on `line` of a name in `funcs` (`f(...)`,
## `self.f(...)`); args split at top-level commas, a call spanning lines cut at the line end.
func _calls(line: String, funcs: Dictionary) -> Array:
	var out := []
	var re := RegEx.create_from_string("(?:(?<=self\\.)|(?<![.\\w]))(\\w+)\\s*\\(")
	for m in re.search_all(line):
		if not funcs.has(m.get_string(1)):
			continue
		var args: Array[String] = []
		var cur := ""
		var depth := 0
		for k in range(m.get_end(), line.length()):
			var c := line[k]
			if c == "(" or c == "[" or c == "{":
				depth += 1
			elif c == ")" or c == "]" or c == "}":
				if depth == 0:
					break
				depth -= 1
			elif c == "," and depth == 0:
				args.append(cur)
				cur = ""
				continue
			cur += c
		args.append(cur)
		out.append([m.get_string(1), args])
	return out


## Every write to sim.state / sim.config in a presentation source: an assignment at any depth
## or a mutator call (LT-42: also a method of a state class that changes its object,
## `t.reset_modifiers()`), directly or through an alias (`_state_aliases`). Aliases are scoped
## (`_scopes`): a func sees its own and its class's; LT-42 adds, all within this file:
##  - a class field (declared in the class body) assigned an alias in a func (`s = sim.state`,
##    `self.s = ...`) is an alias in every func of that class, also as `self.s`;
##  - a func returning an alias (`return sim.state`) or declared `-> <state type>` is a getter:
##    `get_s().gold = 1`, `var s := get_s()`; so are Simulation's queries (`_sim_getters`):
##    `var t := game.sim.tower_by_id(id)`, `game.sim.enemy_by_id(id).reset_modifiers()`;
##  - elements of a state container (`_containers`, or an Array getter call such as
##    `game.sim.enemies_in_range(...)`) are aliases: `ts[0].level = 3`, `for e in ts:`;
##  - a parameter of a func this file calls with an alias in that position (`f(sim.state)`)
##    is an alias inside that func;
##  - an inner class's funcs see its own fields, not the outer script's.
func _state_writes(file: String, text: String) -> Array[String]:
	var code := _code_lines(text)
	var mut := _mutators()
	var out: Array[String] = []
	for p: String in _write_patterns("\\.(?:state|config)", mut):
		out.append_array(_find(file, code, p))
	var scopes := _scopes(code)
	var var_re := RegEx.create_from_string("^\\s*var\\s+(\\w+)")
	var returns_one := RegEx.create_from_string("->\\s*" + _state_type_pattern())
	var returns_many := RegEx.create_from_string("->\\s*" + _state_array_pattern())
	var names: Array = []
	var members: Array = []
	var funcs := {}
	var getters: Array[String] = []
	getters.assign(_sim_getters()[0])
	var array_getters: Array[String] = []
	array_getters.assign(_sim_getters()[1])
	for i in scopes.size():
		var s: Dictionary = scopes[i]
		names.append([])
		var mem: Array[String] = []
		if s.kind == "class":
			for entry: Array in s.lines:
				var m := var_re.search(entry[1])
				if m != null:
					mem.append(m.get_string(1))
		else:
			if not funcs.has(s.name):
				funcs[s.name] = i
			if returns_one.search(s.lines[0][1]) != null and not getters.has(s.name):
				getters.append(s.name)
			elif returns_many.search(s.lines[0][1]) != null and not array_getters.has(s.name):
				array_getters.append(s.name)
		members.append(mem)
	var conts: Array = []
	for i in scopes.size():
		var c := _containers(scopes[i].lines, array_getters)
		if scopes[i].kind == "func":
			for n in conts[scopes[i].owner]:
				if not c.has(n):
					c.append(n)
		conts.append(c)
	var elems_of := func(i: int) -> String:
		return _alias_head(conts[i], array_getters)
	var changed := true
	while changed:
		changed = false
		for i in scopes.size():
			var s: Dictionary = scopes[i]
			var inherited: Array = names[s.owner] if s.kind == "func" else []
			var known: Array = inherited.duplicate()
			for n in names[i]:
				if not known.has(n):
					known.append(n)
			for n in _state_aliases(s.lines, known, getters, elems_of.call(i)):
				if not known.has(n):
					names[i].append(n)
					known.append(n)
					changed = true
			if s.kind != "func":
				continue
			var src := _state_value(_alias_head(known, getters), elems_of.call(i))
			var field_re := RegEx.create_from_string(
				"^\\s*(?:self\\.)?(\\w+)\\s*=(?!=)\\s*" + src + "\\s*$")
			var return_re := RegEx.create_from_string("^\\s*return\\s+" + src + "\\s*$")
			var arg_re := RegEx.create_from_string("^\\s*" + src + "\\s*$")
			for k in range(1, s.lines.size()):
				var line: String = s.lines[k][1]
				var m := field_re.search(line)
				if m != null and members[s.owner].has(m.get_string(1)) \
						and not names[s.owner].has(m.get_string(1)):
					names[s.owner].append(m.get_string(1))
					changed = true
				if return_re.search(line) != null and not getters.has(s.name):
					getters.append(s.name)
					changed = true
				for call: Array in _calls(line, funcs):
					var callee: Dictionary = scopes[funcs[call[0]]]
					for a in mini(call[1].size(), callee.params.size()):
						var p: String = callee.params[a]
						if arg_re.search(call[1][a]) != null \
								and not names[funcs[call[0]]].has(p):
							names[funcs[call[0]]].append(p)
							changed = true
	for i in scopes.size():
		var s: Dictionary = scopes[i]
		var known: Array = names[i].duplicate()
		if s.kind == "func":
			known.append_array(names[s.owner])
		var heads: Array[String] = []
		var head := _alias_head(known, getters)
		if head != "":
			heads.append(head)
		if elems_of.call(i) != "":
			heads.append(elems_of.call(i) + ELEMENT_STEP)
		for h in heads:
			for p in _write_patterns(h, mut):
				out.append_array(_find(file, s.lines, p))
	return out


# --- the scanner itself (so a silent scanner cannot pass the scans) ----------------------

func test_the_scanner_blanks_comments_and_strings_and_flags_engine_types() -> void:
	var own := {"Simulation": true, "Type": true}
	var text := "var a: Simulation\nvar t: Tween  ## Node in a comment\nvar s := \"Control # x\" # Input\n" \
		+ "var c := Color(1, 0, 0)\nvar o := Type.SHOT\nvar v: Vector2i\nvar q := 'it\\'s Node'\n"
	var hits := _foreign_types("f.gd", text, own)
	assert_array(hits).is_equal(["f.gd:2: Tween", "f.gd:4: Color"])
	assert_array(_find("f.gd", _code_lines("var x = get_tree() # signal"), "\\bsignal\\b")).is_empty()
	assert_array(_find("f.gd", _code_lines("var x = get_tree()"), "\\bget_tree\\b")).has_size(1)
	assert_array(_find("f.gd", _code_lines("var x = r.randf()"), SIM_FORBIDDEN_CODE[10])).is_empty()
	assert_array(_find("f.gd", _code_lines("var x = randf()"), SIM_FORBIDDEN_CODE[10])).has_size(1)
	assert_array(_find("f.gd", _code_lines("var s = load(\"res://ui/hud.gd\")", true),
		SIM_FORBIDDEN_WITH_STRINGS[0])).has_size(1)
	assert_array(_find("f.gd", _code_lines("game.sim._add_sanity(1)"), "\\bsim\\._\\w+")).has_size(1)
	assert_array(_find("f.gd", _code_lines("g.state.gold += 5"), WRITE_PATTERNS[0])).has_size(1)
	assert_array(_find("f.gd", _code_lines("if g.state.gold == 5:"), WRITE_PATTERNS[0])).is_empty()
	assert_array(_find("f.gd", _code_lines("g.config.sanity.max = 1"), WRITE_PATTERNS[1])).has_size(1)


func test_the_caps_scan_flags_all_caps_engine_names_but_not_constants() -> void:
	var text := "var a := OS.get_name()\nvar b := JSON.new()\nvar c := IP.get_singleton()\n" \
		+ "const SIGN := 1\nvar t := TYPE_INT\nvar m := S.MADNESS\nvar d: AABB\n" \
		+ "var e := 1 # OS\nvar f := \"JSON\"\nvar g := MAX_TICKS + REPLAY_ARGS.size()\n"
	assert_array(_engine_caps("f.gd", text, {}, [])).is_equal(
		["f.gd:1: OS", "f.gd:2: JSON", "f.gd:3: IP", "f.gd:7: AABB"])
	assert_array(_engine_caps("f.gd", text, {"IP": true}, ["JSON"])).is_equal(
		["f.gd:1: OS", "f.gd:7: AABB"])


func test_the_write_scan_flags_nested_writes_mutator_calls_and_aliases() -> void:
	for text: String in [
		"sim.state.map.width = 3",
		"game.sim.state.relics[\"x\"] += 1",
		"sim.state.towers[0].level = 3",
		"sim.state.gold |= 1",
		"sim.state.towers.append(t)",
		"game.sim.state.relics.erase(k)",
		"sim.state.set(\"gold\", 1)",
		"sim.state.tower_at[c].sort_custom(f)",
		"sim.config.towers.clear()",
		"func f() -> void:\n\tvar st := game.sim.state\n\tst.gold = 1",
		"func f() -> void:\n\tvar st: SimState = sim.state\n\tst.towers.push_back(t)",
		"func f() -> void:\n\tvar tw := sim.state.towers\n\ttw.clear()",
		"func f() -> void:\n\tvar m := sim.state.map\n\tm.width -= 1",
		"static func f(s: SimState) -> void:\n\ts.gold -= 1",
		"func f() -> void:\n\tfor t in sim.state.towers:\n\t\tt.level = 3",
		"func f() -> void:\n\tvar s := sim.state\n\tfor t: SimTower in s.towers:\n\t\tt.level = 3",
		"var s: SimState\nfunc f() -> void:\n\ts.relics.merge(r)",
	]:
		assert_array(_state_writes("f.gd", text)).override_failure_message(
			"not flagged:\n" + text).is_not_empty()
	for text: String in [
		"if sim.state.map.width == 3: pass",
		"if sim.state.gold >= 3 and sim.state.gold <= 9 and sim.state.gold != 4: pass",
		"var n := sim.state.towers.size() + sim.state.relics.keys().size()",
		"var x := \"sim.state.gold = 1\"  # sim.state.towers.clear()",
		"func f() -> void:\n\tvar s := sim.state\n\tvar g := s.gold\n\tlabel.text = str(s.gold)",
		"func f() -> void:\n\tvar s := sim.state\nfunc g() -> void:\n\ts.text = \"x\"",
		"func f() -> void:\n\tvar c := sim.state.towers.duplicate()\n\tc.clear()",
		"func f() -> void:\n\tvar s := sim.state\n\ts = other\n\tlabels.append(s)",
		"var states := 1\nstates.clear()\nnode.state_text = \"a\"",
	]:
		assert_array(_state_writes("f.gd", text)).override_failure_message(
			"falsely flagged:\n" + text).is_empty()


## LT-42: one case per alias form the guard follows; each must be flagged.
func test_the_write_scan_follows_the_lt42_alias_forms() -> void:
	for text: String in [
		# a state class's own mutating method (`_mutators`), on an alias and on a getter call
		"func f() -> void:\n\tvar s := sim.state\n\ts.enemies[0].reset_modifiers()",
		"func f() -> void:\n\tgame.sim.enemy_by_id(id).reset_modifiers()",
		# Simulation getters (`_sim_getters`): one object, and an Array of them
		"func f() -> void:\n\tvar t := game.sim.tower_by_id(id)\n\tt.level = 3",
		"func f() -> void:\n\tgame.sim.tower_by_id(id).level = 3",
		"func f() -> void:\n\tfor e in game.sim.enemies_in_range(c, 2.0):\n\t\te.hp = 0",
		"func f() -> void:\n\tvar es := game.sim.enemies_in_range(c, 2.0)\n\tes[0].hp = 0",
		# a getter of this file, by its return and by its declared state return type
		"func get_s():\n\treturn sim.state\nfunc f() -> void:\n\tget_s().gold = 1",
		"func get_t() -> SimTower:\n\treturn null\nfunc f() -> void:\n\tvar t := get_t()\n"
			+ "\tt.level = 3",
		# a class field assigned an alias inside a func, plain and through self
		"var s\nfunc _ready() -> void:\n\ts = sim.state\nfunc f() -> void:\n\ts.gold = 1",
		"var s\nfunc _ready() -> void:\n\tself.s = sim.state\nfunc f() -> void:\n\tself.s.gold = 1",
		# typed params: a state class, an inner one, an Array of them (index, element call, for)
		"func f(t: SimTower) -> void:\n\tt.level = 3",
		"func f(l: TowerDef.Level) -> void:\n\tl.damage = 1.0",
		"func f(ts: Array[SimTower]) -> void:\n\tts[0].level = 3",
		"func f(ts: Array[SimTower]) -> void:\n\tts.back().level = 3",
		"func f(ts: Array[SimTower]) -> void:\n\tfor t in ts:\n\t\tt.level = 3",
		# a param of a func this file calls with an alias (`_calls`), plain and through self
		"func f() -> void:\n\tg(sim.state)\nfunc g(x) -> void:\n\tx.gold = 1",
		"func f() -> void:\n\tself.g(1, sim.state.towers[0])\nfunc g(a, x) -> void:\n\tx.level = 3",
		# an inner class's field, assigned in one of its funcs and written in another
		"class Inner:\n\tvar s\n\tfunc a() -> void:\n\t\ts = sim.state\n\tfunc b() -> void:\n"
			+ "\t\ts.gold = 1",
		# element tails (ELEMENT_CALL): direct, and into an alias
		"func f() -> void:\n\tsim.state.towers.back().level = 3",
		"func f() -> void:\n\tsim.state.towers.front().level = 3",
		"func f() -> void:\n\tsim.state.towers.get(0).level = 3",
		"func f() -> void:\n\tsim.state.enemies.pop_front().hp = 0",
		"func f() -> void:\n\tvar t := sim.state.towers.back()\n\tt.level = 3",
		# a local declared empty and assigned an alias later (`_state_aliases`)
		"func f() -> void:\n\tvar s = null\n\ts = sim.state\n\ts.gold = 1",
	]:
		assert_array(_state_writes("f.gd", text)).override_failure_message(
			"not flagged:\n" + text).is_not_empty()


## LT-42: near misses of the forms above; none may be flagged.
func test_the_write_scan_skips_the_lt42_near_misses() -> void:
	for text: String in [
		# an enum nested in a state class is not that class
		"func f(st: SimState.SanityState) -> void:\n\tst.x = 1",
		# ConfigReader is only a func-local in sim/, not a member of the config
		"func f(r: ConfigReader) -> void:\n\tr.x = 1",
		"func f() -> void:\n\tvar r: ConfigReader = ConfigReader.new(p)\n\tr.x = 1",
		# an Array param of state objects may be a fresh Array: changing it is no state write
		"func f(ts: Array[SimTower]) -> void:\n\tts.clear()",
		"func f(ts: Array[SimTower]) -> void:\n\tts.append(t)",
		# a func-local (not a class field) assigned an alias stays in its func
		"func f() -> void:\n\tvar s\n\ts = sim.state\nfunc g() -> void:\n\ts.gold = 1",
		# an inner class's funcs see its own fields, not the outer script's
		"var s\nfunc a() -> void:\n\ts = sim.state\nclass Inner:\n\tvar s\n\tfunc b() -> void:\n"
			+ "\t\ts.gold = 1",
		# a func this file calls with no alias: its param is none
		"func f() -> void:\n\tg(label)\nfunc g(x) -> void:\n\tx.text = \"a\"",
	]:
		assert_array(_state_writes("f.gd", text)).override_failure_message(
			"falsely flagged:\n" + text).is_empty()


func test_the_private_member_scan_includes_static_functions() -> void:
	var text := "var _a := 1\nconst _b := 2\nfunc _c() -> void:\nstatic func _d() -> int:\n" \
		+ "func _init() -> void:\nconst _E := 3\n\tvar _local := 4\nfunc pub() -> void:\n"
	assert_array(_private_members_of(text)).is_equal(["_a", "_b", "_c", "_d"])


func test_the_scans_cover_the_expected_files() -> void:
	var sim_files := _gd_files(SIM_DIR)
	assert_array(sim_files).contains([SIMULATION, "res://sim/config.gd",
		"res://sim/core/sim_state.gd", "res://sim/defs/tower_def.gd"])
	var pres := _presentation_files()
	assert_array(pres).contains(["res://scenes/game.gd", "res://scenes/board.gd",
		"res://ui/hud.gd", "res://ui/tower_panel.gd", "res://tools/bot_runs.gd"])
	for f in pres:
		assert_bool(f.begins_with("res://sim/") or f.begins_with("res://tests/")).is_false()
	assert_array(_private_members_of_simulation()).contains(["_add_sanity", "_spawner",
		"_change_reserve", "_reserve_drives_mad"])
	assert_dict(_own_types(sim_files)).contains_keys(["Simulation", "GameConfig", "CommandResult",
		"Phase", "SanityState"])


# --- 1: what sim/ may use ----------------------------------------------------------------

func test_sim_names_only_own_types_and_allowlisted_engine_types() -> void:
	var files := _gd_files(SIM_DIR)
	var own := _own_types(files)
	var bad: Array[String] = []
	for f in files:
		bad.append_array(_foreign_types(f, FileAccess.get_file_as_string(f), own))
	assert_array(bad).override_failure_message(
		"sim/ names types outside its own classes and the allowlist:\n" + "\n".join(bad)).is_empty()


func test_the_engine_allowlist_is_not_stale() -> void:
	# Every allowlisted engine type is still used somewhere in sim/ (shrink the list when not).
	var files := _gd_files(SIM_DIR)
	var used := {}
	var re := RegEx.create_from_string("\\b[A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*\\b")
	var caps := RegEx.create_from_string("(?<![.\\w])[A-Z][A-Z0-9_]*\\b")  # JSON (LT-36)
	for f in files:
		for entry: Array in _code_lines(FileAccess.get_file_as_string(f)):
			for m in re.search_all(entry[1]) + caps.search_all(entry[1]):
				used[m.get_string()] = true
	for t: String in ENGINE_ALLOWLIST:
		assert_bool(used.has(t)).override_failure_message("%s is allowlisted but unused" % t).is_true()


func test_sim_names_no_all_caps_engine_class_outside_the_allowlist() -> void:
	var files := _gd_files(SIM_DIR)
	var own := _own_types(files)
	var bad: Array[String] = []
	for f in files:
		bad.append_array(_engine_caps(f, FileAccess.get_file_as_string(f), own, ENGINE_ALLOWLIST))
	assert_array(bad).override_failure_message(
		"sim/ names an all-capitals engine class or singleton outside the allowlist:\n"
		+ "\n".join(bad)).is_empty()


func test_sim_uses_no_forbidden_tokens() -> void:
	var bad: Array[String] = []
	for f in _gd_files(SIM_DIR):
		var text := FileAccess.get_file_as_string(f)
		var code := _code_lines(text)
		var with_strings := _code_lines(text, true)
		for p: String in SIM_FORBIDDEN_CODE:
			bad.append_array(_find(f, code, p))
		for p: String in SIM_FORBIDDEN_WITH_STRINGS:
			bad.append_array(_find(f, with_strings, p))
	assert_array(bad).override_failure_message(
		"sim/ uses presentation or engine-runtime constructs:\n" + "\n".join(bad)).is_empty()


# --- 2: what scenes/, ui/ and tools/ may touch -------------------------------------------

func test_presentation_calls_no_private_simulation_member() -> void:
	var private := _private_members_of_simulation()
	var by_name := "\\.(%s)\\b" % "|".join(private)
	var bad: Array[String] = []
	for f in _presentation_files():
		var code := _code_lines(FileAccess.get_file_as_string(f))
		bad.append_array(_find(f, code, "\\bsim\\._\\w+"))
		bad.append_array(_find(f, code, by_name))
	assert_array(bad).override_failure_message(
		"presentation reaches a private Simulation member (use a public command/query):\n"
		+ "\n".join(bad)).is_empty()


func test_presentation_writes_no_sim_state_or_config() -> void:
	var bad: Array[String] = []
	for f in _presentation_files():
		bad.append_array(_state_writes(f, FileAccess.get_file_as_string(f)))
	assert_array(bad).override_failure_message(
		"presentation writes sim.state / config (directly, nested, by a mutator call or "
		+ "through an alias):\n" + "\n".join(bad)).is_empty()


# --- 3: the is_fake leak guard stays ------------------------------------------------------

func test_the_is_fake_leak_guard_is_kept_and_presentation_is_clean() -> void:
	var guard := FileAccess.get_file_as_string("res://tests/render_isolation_test.gd")
	assert_str(guard).contains("test_no_script_outside_sim_and_tests_can_tell_a_fake")
	assert_str(guard).contains("\"\\\\bis_fake\\\\b\"")
	var bad: Array[String] = []
	for f in _presentation_files():
		bad.append_array(_find(f, _code_lines(FileAccess.get_file_as_string(f)), "\\bis_fake\\b"))
	assert_array(bad).is_empty()


# --- 4: the sim needs no SceneTree ---------------------------------------------------------

func test_a_whole_game_runs_without_a_scene_tree() -> void:
	var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var in_process := SimNoTreeLoop.run()
	assert_float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)).is_equal(nodes_before)
	assert_str(in_process).contains("outcome=")
	assert_bool(in_process.contains("outcome=0")).override_failure_message(
		"the bot game reached no outcome: " + in_process).is_false()
	assert_bool(in_process.begins_with("CONFIG ERROR")).is_false()
	# The same game in a process whose main loop is a plain MainLoop (no SceneTree at all).
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", "res://tests/sim_no_tree_loop.gd"],
		out, true)
	var text := "\n".join(PackedStringArray(out))
	assert_int(code).override_failure_message("exit %d:\n%s" % [code, text]).is_equal(0)
	var digest := ""
	for line in text.split("\n"):
		if line.begins_with(SimNoTreeLoop.MARKER):
			digest = line.trim_prefix(SimNoTreeLoop.MARKER).strip_edges()
	assert_str(digest).override_failure_message("no digest in:\n" + text).is_equal(in_process)


# --- 5: a frame-driven run equals direct stepping ------------------------------------------

## [tick, command, args...] issued through Game once sim.state.tick has reached `tick`.
## Builds name a buildable-cell index (see _cells); upgrade / priority name the def built.
const PLAN := [
	[0, "build", "rifleman", 0],
	[0, "build", "harpooner", 3],
	[200, "upgrade", "rifleman", ""],
	[400, "call_wave"],
	[700, "set_target_priority", "harpooner", "strongest"],
]

var _cells: Array[Vector2i] = []


## Buildable cells of the real map, row-major.
func _load_cells(config: GameConfig) -> void:
	var sim := Simulation.new(config, 7)
	_cells.clear()
	for y in sim.state.map.height:
		for x in sim.state.map.width:
			if sim.state.map.is_buildable(Vector2i(x, y)):
				_cells.append(Vector2i(x, y))


func _tower_of(game: Game, def_id: String) -> int:
	for c: Array in PLAN:
		if c[1] == "build" and c[2] == def_id:
			return game.sim.state.tower_at[_cells[int(c[3])]]
	return -1


func _dispatch(game: Game, c: Array) -> int:
	match c[1]:
		"build": return game.build(c[2], _cells[int(c[3])])
		"upgrade": return game.upgrade(_tower_of(game, c[2]), c[3])
		"set_target_priority": return game.set_target_priority(_tower_of(game, c[2]), c[3])
		"call_wave": return game.call_wave()
	return -1


func _frame_run(config: GameConfig, frame_seed: int) -> Game:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1152, 648)
	add_child(_vp)
	var game := Game.new()
	game.setup(config, 7)
	_vp.add_child(game)
	game.set_process(false)  # advance() below is the body of Game._process
	await get_tree().process_frame
	_load_cells(config)
	game.sim.debug_set_sanity(70.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = frame_seed
	var next := 0
	var shadow := SimClock.new()  # grants the ticks a frame owes; Game must step exactly that many
	var expected := 0
	for frame in STEPS_AFTER_FRAMES:
		while next < PLAN.size() and game.sim.state.tick >= int(PLAN[next][0]):
			var r := _dispatch(game, PLAN[next])
			assert_int(r).override_failure_message("%s -> %d" % [PLAN[next], r]).is_equal(0)
			next += 1
		if frame == 50:
			game.toggle_pause()
		elif frame == 70:
			game.toggle_pause()
		elif frame == 150 or frame == 600:
			game.toggle_speed()
		# Uneven frames: fast, slow, hitches (the clock caps catch-up at 8 steps).
		var delta: float = [1.0 / 144.0, 1.0 / 30.0, 0.2, 1.0 / 60.0][rng.randi() % 4] \
			* rng.randf_range(0.5, 1.5)
		shadow.speed = game.clock.speed
		expected += shadow.advance(delta)
		game.advance(delta)
		if game.sim.state.outcome == SimState.Outcome.NONE:
			assert_int(game.sim.state.tick).override_failure_message(
				"frame %d: Game stepped %d ticks, the clock granted %d" % [frame,
				game.sim.state.tick, expected]).is_equal(expected)
		if game.sim.state.tick >= 1800 or game.sim.state.outcome != SimState.Outcome.NONE:
			break
	return game


func _state_digest(sim: Simulation) -> String:
	var parts: Array[String] = [SimNoTreeLoop.digest(sim), "cap=%s st=%d phase=%d relics=%s" % [
		sim.state.sanity_cap, sim.state.sanity_state, sim.state.phase, str(sim.state.relics)]]
	for e in sim.state.enemies:
		parts.append("e%d:%s:%s:%d" % [e.id, e.def.id, e.hp, e.distance])
	for t in sim.state.towers:
		parts.append("t%d:%s:%d:%s:%s" % [t.id, t.def.id, t.level, t.target_priority, t.cell])
	return "\n".join(parts)


func test_a_frame_driven_game_equals_direct_stepping() -> void:
	var config := real_config()
	var game: Game = await _frame_run(config, 1234)
	var sim := game.sim
	var log: Array = sim.state.command_log
	var names: Array = log.map(func(c: Array) -> String: return c[1])
	assert_array(names).contains(["debug_set_sanity", "build", "upgrade", "call_wave",
		"set_target_priority"])
	assert_int(sim.state.tick).is_greater(700)  # the run really advanced through its plan
	assert_int(sim.state.towers.size()).is_equal(2)
	# The same log on a bare sim: step to each entry's tick, apply it, step to the end.
	var bare := Simulation.new(config, 7)
	bare.set_spawner(WaveDirector.new(config.waves))
	for entry: Array in log:
		while bare.state.tick < int(entry[0]):
			bare.step()
		assert_int(bare.replay_command(entry)).is_equal(Simulation.CommandResult.OK)
	while bare.state.tick < sim.state.tick:
		bare.step()
	assert_array(bare.state.command_log).is_equal(log)
	assert_str(_state_digest(bare)).is_equal(_state_digest(sim))


func test_each_frame_pattern_equals_the_replay_of_its_own_command_log() -> void:
	# Different frame jitter lands a command on a different tick; each run must equal its replay.
	var config := real_config()
	for frame_seed in [1, 99]:
		var game: Game = await _frame_run(config, frame_seed)
		var bare := Simulation.new(config, 7)
		bare.set_spawner(WaveDirector.new(config.waves))
		for entry: Array in game.sim.state.command_log:
			while bare.state.tick < int(entry[0]):
				bare.step()
			bare.replay_command(entry)
		while bare.state.tick < game.sim.state.tick:
			bare.step()
		assert_str(_state_digest(bare)).override_failure_message("frame seed %d" % frame_seed) \
			.is_equal(_state_digest(game.sim))
		_vp.queue_free()
		_vp = null
