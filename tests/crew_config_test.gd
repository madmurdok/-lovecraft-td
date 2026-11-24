class_name CrewConfigTest
extends ConfigTestBase
## LT-32 §2.1: data/crew.json, the optional crew block. Absent -> crew off without an error;
## `enabled: false` -> parsed and validated but off; the post def is synthetic and never a
## tower; each malformed field and the cross-file checks (kind = tower id, frame >= 0, the
## reserved "post" tower id) are rejected with crew.json errors.

const CREW := "crew.json"


## A copy of res://data with crew.json (shipped text, then `fn(root)`), loaded.
func _load_crew(fn := Callable()) -> ConfigLoadResult:
	return load_edited(func(dir: String) -> void:
		write_file(dir, CREW, FileAccess.get_file_as_string("res://data/" + CREW))
		if fn.is_valid():
			edit(dir, CREW, fn))


func test_shipped_crew_json_loads_with_crew_on_and_a_synthetic_post_def() -> void:
	var r := _load_crew()
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	var c := r.config
	assert_bool(c.crew_on()).is_true()
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + CREW))
	assert_array(c.crew.crews.keys()).is_equal(shipped["crews"].keys())
	for kind: String in c.crew.crews:
		assert_bool(c.towers.has(kind)).override_failure_message(kind).is_true()
		assert_int(c.crew.crews[kind].per_tower).is_equal(int(shipped["crews"][kind]["per_tower"]))
		assert_int(c.crew.crews[kind].hire).is_equal(int(shipped["crews"][kind]["hire"]))
		assert_object(c.crew.post_of(kind)).is_same(c.crew.post)
	var p := c.crew.post
	assert_int(p.crew).is_equal(int(shipped["post"]["crew"]))
	assert_str(p.def.id).is_equal(CrewConfig.POST_ID)
	assert_str(p.def.kind).is_equal("mundane")
	assert_int(p.def.cost).is_equal(0)
	assert_int(p.def.levels.size()).is_equal(1)
	assert_float(p.def.levels[0].damage).is_equal(float(shipped["post"]["damage"]))
	assert_float(p.def.levels[0].range_cells).is_equal(float(shipped["post"]["range"]))
	assert_float(p.def.levels[0].fire_interval).is_equal(float(shipped["post"]["fire_interval"]))
	assert_bool(c.towers.has(CrewConfig.POST_ID)).is_false()


func test_absent_file_is_crew_off_and_enabled_false_is_parsed_but_off() -> void:
	var absent := load_edited(func(_dir: String) -> void: pass)
	assert_bool(absent.ok).is_true()
	assert_object(absent.config.crew).is_null()
	assert_bool(absent.config.crew_on()).is_false()
	var off := _load_crew(func(root: Dictionary) -> void: root["enabled"] = false)
	assert_bool(off.ok).override_failure_message("\n".join(off.errors)).is_true()
	assert_object(off.config.crew).is_not_null()
	assert_bool(off.config.crew_on()).is_false()


## Each malformed field is rejected with a crew.json error at its path.
func test_each_malformed_field_is_rejected() -> void:
	var cases := [
		["", "stray", func(r: Dictionary) -> void: r["stray"] = 1],
		["enabled", "", func(r: Dictionary) -> void: r.erase("enabled")],
		["post", "", func(r: Dictionary) -> void: r.erase("post")],
		["crews", "", func(r: Dictionary) -> void: r.erase("crews")],
		["post", "crew", func(r: Dictionary) -> void: r["post"]["crew"] = 0],
		["post.damage", "", func(r: Dictionary) -> void: r["post"]["damage"] = 0],
		["post.damage", "missing", func(r: Dictionary) -> void: r["post"].erase("damage")],
		["post", "stray", func(r: Dictionary) -> void: r["post"]["stray"] = 1],
		["crews.rifleman", "per_tower", func(r: Dictionary) -> void:
			r["crews"]["rifleman"]["per_tower"] = 0],
		["crews.rifleman", "hire", func(r: Dictionary) -> void: r["crews"]["rifleman"]["hire"] = -1],
		["crews.rifleman", "stray", func(r: Dictionary) -> void: r["crews"]["rifleman"]["stray"] = 1],
	]
	for c: Array in cases:
		var r := _load_crew(c[2])
		assert_bool(r.ok).override_failure_message("%s accepted" % [c[0]]).is_false()
		var found := false
		for e in r.errors:
			if e.begins_with(CREW + ": ") and (c[0] == "" or e.contains(c[0])) \
					and (c[1] == "" or e.contains(c[1])):
				found = true
		assert_bool(found).override_failure_message("%s / %s not in:\n%s" % [c[0], c[1],
			"\n".join(r.errors)]).is_true()


## Cross-file checks: every crew kind is a tower id, its frame (cost - per_tower x hire) is
## >= 0, no tower is named "post"; they run with enabled false too.
func test_cross_checks_reject_unknown_kinds_negative_frames_and_a_post_tower() -> void:
	for enabled in [true, false]:
		var unknown := _load_crew(func(r: Dictionary) -> void:
			r["enabled"] = enabled
			r["crews"]["no_such_tower"] = {"name": "Ghosts", "per_tower": 1, "hire": 1})
		assert_rejected(unknown, CREW, "crews.no_such_tower", "unknown tower")
		var dear := _load_crew(func(r: Dictionary) -> void:
			r["enabled"] = enabled
			r["crews"]["rifleman"]["hire"] = 1000)
		assert_rejected(dear, CREW, "crews.rifleman", "exceeds the tower's cost")
	var post_tower := load_edited(func(dir: String) -> void:
		write_file(dir, CREW, FileAccess.get_file_as_string("res://data/" + CREW))
		edit(dir, "towers.json", func(root: Dictionary) -> void:
			var t: Dictionary = root["towers"]["rifleman"].duplicate(true)
			t["glyph"] = "Z"
			root["towers"][CrewConfig.POST_ID] = t))
	assert_rejected(post_tower, CREW, "post", "reserved")
	# Frame exactly 0 is allowed.
	var towers: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/towers.json"))
	var cost := int(towers["towers"]["rifleman"]["cost"])
	var zero := _load_crew(func(r: Dictionary) -> void:
		r["crews"]["rifleman"]["per_tower"] = 1
		r["crews"]["rifleman"]["hire"] = cost)
	assert_bool(zero.ok).override_failure_message("\n".join(zero.errors)).is_true()
