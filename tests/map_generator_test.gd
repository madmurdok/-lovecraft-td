class_name MapGeneratorTest
extends GdUnitTestSuite
## LT-130 §8 (docs/design/LT-130-p1-generator.md §2, §3, §8, §9 Q1, §10): the P1 generator,
## its RNG, its output struct and its params. Digest pins were computed by running the code once
## (LT-130/S21 probe), never typed from a report. No timing here (the report tool measures it).
##
## Controls (code revert -> failing test), described for the verify slice:
##  T1: MapRng seeds its RandomNumberGenerator from a static call counter instead of the seed
##      -> test_digests_are_pinned fails.
##  T2: MapRng.attempt_seed ignores map_seed (returns `attempt`)
##      -> test_seed_matters fails (one digest for all 20 seeds).
##  T8: generate returns the last attempt's map when the cap is hit
##      -> test_impossible_params_hit_the_cap fails (map not null).
##  S20 pocket mouth: _spur_cell_ok never counts flanks (`continue` for every flank)
##      -> test_structure_of_attempts fails (a pocket's first cell bridges two network cells).

## sha256 of canonical(), p1_small, computed by the code at commit 92a3ff5.
const ATTEMPT0_DIGESTS := {
	1: "6fb04083179f2309de0e523bd9a32d39d194ebd4f5c3613c66c5fd93fc861c68",
	2: "caab0228194f1eaa74b880d1c483eece447f84e534e2af45ddbb924342d79a0b",
	3: "dc884a323eba3208d8c1fc395f3aa8c662c0b41e9b6079e0833566413acfcc12",
}
const GENERATE_DIGESTS := {
	1: "6fb04083179f2309de0e523bd9a32d39d194ebd4f5c3613c66c5fd93fc861c68",
	2: "9949c06c35705753ea7993086314ea59c71aa774d664f4f3658c7eb8fb4c9743",
	3: "dc884a323eba3208d8c1fc395f3aa8c662c0b41e9b6079e0833566413acfcc12",
}
const T := GenMap.Terrain
## Structure test: attempt 0 of seeds 1..STRUCT_SEEDS, for p1_small and p1_large each.
const STRUCT_SEEDS := 25


# --- T1 / T2 determinism ---------------------------------------------------------------------

func test_same_seed_same_map() -> void:
	var p := MapGenParams.p1_small()
	var a := MapGenerator.generate(4, p)
	var b := MapGenerator.generate(4, p)
	assert_object(a.map).is_not_null()
	assert_str(a.map.digest()).is_equal(b.map.digest())
	assert_int(a.attempts).is_equal(b.attempts)


func test_digests_are_pinned() -> void:
	var p := MapGenParams.p1_small()
	for s: int in ATTEMPT0_DIGESTS:
		var m := MapGenerator.attempt(MapRng.attempt_seed(s, 0), p)
		assert_str(m.digest()).override_failure_message("attempt 0 of seed %d" % s) \
			.is_equal(ATTEMPT0_DIGESTS[s])
	for s: int in GENERATE_DIGESTS:
		var res := MapGenerator.generate(s, p)
		assert_object(res.map).is_not_null()
		assert_str(res.map.digest()).override_failure_message("generate seed %d" % s) \
			.is_equal(GENERATE_DIGESTS[s])
		assert_bool(res.report.passed).is_true()
		assert_int(res.rejects.size()).is_equal(res.attempts - 1)
		# an accepted map: every entry reaches L (no S1)
		var f := RouteField.build(res.map)
		for e in res.map.entries:
			assert_bool(f.reaches(e)).is_true()


func test_seed_matters() -> void:
	var p := MapGenParams.p1_small()
	var seen := {}
	for s in range(1, 21):
		seen[MapGenerator.attempt(MapRng.attempt_seed(s, 0), p).digest()] = true
	assert_int(seen.size()).is_greater_equal(19)


func test_attempt_seed_formula() -> void:
	assert_int(MapRng.attempt_seed(7, 3)).is_equal(7003)
	assert_int(MapRng.attempt_seed(0, 0)).is_equal(0)


## A choice with one candidate draws nothing (§3), so it does not shift the next draw.
func test_pick_of_one_draws_nothing() -> void:
	var a := MapRng.new(42)
	var b := MapRng.new(42)
	assert_int(a.pick(1)).is_equal(0)
	assert_int(a.pick(0)).is_equal(0)
	assert_int(a.randi_range(0, 1 << 30)).is_equal(b.randi_range(0, 1 << 30))


# --- T8 reject path ----------------------------------------------------------------------------

func test_impossible_params_hit_the_cap() -> void:
	var parsed := MapGenParams.from_dict({"c1_m": 99, "attempt_cap": 5})
	assert_array(parsed["errors"]).is_empty()
	var res := MapGenerator.generate(1, parsed["params"])
	assert_object(res.map).is_null()
	assert_int(res.attempts).is_equal(5)
	assert_int(res.rejects.size()).is_equal(5)
	var with_c1 := 0
	for r in res.rejects:
		# a metric reject lists C1 (M = 99 is unreachable); a structural one (S1/S2) skips the metric
		assert_bool(r.has("C1") or r.has("S1") or r.has("S2")) \
			.override_failure_message("reject %s" % r).is_true()
		if r.has("C1"):
			with_c1 += 1
	assert_int(with_c1).is_greater(0)
	assert_str(res.error).starts_with("attempt cap 5 reached (seed 1)")
	assert_object(res.report).is_not_null()


func test_params_failing_check_are_refused() -> void:
	var p := MapGenParams.p1_small()
	p.attempt_cap = 5000
	var res := MapGenerator.generate(1, p)
	assert_object(res.map).is_null()
	assert_int(res.attempts).is_equal(0)
	assert_str(res.error).starts_with("params:")


# --- structure ---------------------------------------------------------------------------------

func test_structure_of_attempts() -> void:
	var problems: Array[String] = []
	var pockets := 0
	for p: MapGenParams in [MapGenParams.p1_small(), MapGenParams.p1_large()]:
		for s in range(1, STRUCT_SEEDS + 1):
			var m := MapGenerator.attempt(MapRng.attempt_seed(s, 0), p)
			pockets += m.pockets.size()
			var tag := "%dx%d seed %d: " % [p.width, p.height, s]
			for msg in _structure_problems(m, p):
				problems.append(tag + msg)
	assert_int(pockets).is_greater(STRUCT_SEEDS)  # the pocket checks saw real pockets
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func _structure_problems(m: GenMap, p: MapGenParams) -> Array[String]:
	var out: Array[String] = []
	var g := m.grid
	var lights := 0
	var entry_cells := 0
	for row in m.rows():
		lights += row.count("L")
		entry_cells += row.count("S")
	if lights != 1 or m.kind_at(m.lighthouse) != T.LIGHTHOUSE:
		out.append("%d lighthouses" % lights)
	if entry_cells != m.entries.size() or m.entries.size() > m.entries_drawn \
			or m.entries_drawn < p.entries_min or m.entries_drawn > p.entries_max:
		out.append("entries %d of %d drawn, %d S cells" % [m.entries.size(), m.entries_drawn,
			entry_cells])
	for e in m.entries:
		var by_sea := false
		for n in g.neighbours(e):
			by_sea = by_sea or m.kind_at(n) == T.SEA
		if not by_sea:
			out.append("entry %s not next to the sea" % g.text_of(e))
	for size in _island_sizes(m):
		if size < p.island_min or size > p.island_max:
			out.append("island of %d cells" % size)
	var in_pocket := {}
	for pocket: Array in m.pockets:
		for c: Vector2i in pocket:
			in_pocket[c] = true
	for pocket: Array in m.pockets:
		out.append_array(_pocket_problems(m, p, pocket, in_pocket))
	return out


## ISLAND components counted here (BFS over neighbours), independent of the generator's own.
func _island_sizes(m: GenMap) -> Array[int]:
	var g := m.grid
	var seen := {}
	var sizes: Array[int] = []
	for c in g.cells():
		if seen.has(c) or m.kind_at(c) != T.ISLAND:
			continue
		var queue: Array[Vector2i] = [c]
		seen[c] = true
		var head := 0
		while head < queue.size():
			var cur := queue[head]
			head += 1
			for n in g.neighbours(cur):
				if not seen.has(n) and m.kind_at(n) == T.ISLAND:
					seen[n] = true
					queue.append(n)
		sizes.append(queue.size())
	return sizes


## A pocket is a dead-end spur: 2-6 CHANNEL cells in a chain; cell i > 0 touches only its chain
## neighbours; the first cell opens on the network through a mouth whose walkable non-pocket
## cells are pairwise adjacent (S20: touching both flanks would make it a through cell).
func _pocket_problems(m: GenMap, p: MapGenParams, pocket: Array, in_pocket: Dictionary) \
		-> Array[String]:
	var out: Array[String] = []
	var g := m.grid
	var name := "pocket at %s" % g.text_of(pocket[0])
	if pocket.size() < p.pocket_len_min or pocket.size() > p.pocket_len_max:
		out.append("%s has %d cells" % [name, pocket.size()])
	for i in pocket.size():
		var c: Vector2i = pocket[i]
		if m.kind_at(c) != T.CHANNEL:
			out.append("%s cell %d not CHANNEL" % [name, i])
		var walk: Array[Vector2i] = []
		for n in g.neighbours(c):
			if m.is_walkable(n):
				walk.append(n)
		if i == 0:
			var mouth: Array[Vector2i] = []
			for n in walk:
				if not in_pocket.has(n):
					mouth.append(n)
			if mouth.is_empty():
				out.append("%s has no mouth" % name)
			for a in mouth:
				for b in mouth:
					if g.steps(a, b) > 1:
						out.append("%s bridges %s and %s" % [name, g.text_of(a), g.text_of(b)])
			continue
		var want: Array[Vector2i] = [pocket[i - 1]]
		if i + 1 < pocket.size():
			want.append(pocket[i + 1])
		if walk.size() != want.size() or not want.all(func(x: Vector2i) -> bool: return walk.has(x)):
			out.append("%s cell %d touches %s" % [name, i, walk])
	return out


# --- params (§9 Q1, §10 items 8 and 13) --------------------------------------------------------

func test_presets() -> void:
	var small := MapGenParams.p1_small()
	assert_str(small.grid_kind).is_equal("hex")
	assert_int(small.width).is_equal(24)
	assert_int(small.height).is_equal(16)
	assert_int(small.entries_min).is_equal(1)
	assert_int(small.entries_max).is_equal(3)
	assert_array(small.check()).is_empty()
	var large := MapGenParams.p1_large()
	assert_str(large.grid_kind).is_equal("hex")
	assert_int(large.width).is_equal(32)
	assert_int(large.height).is_equal(18)
	assert_int(large.entries_min).is_equal(1)
	assert_int(large.entries_max).is_equal(4)
	assert_array(large.check()).is_empty()


func test_from_dict_applies_keys_over_the_base() -> void:
	var parsed := MapGenParams.from_dict({"loops_max": 1, "tower_range": 2, "c5_d": 5.0},
		MapGenParams.p1_large())
	assert_array(parsed["errors"]).is_empty()
	var p: MapGenParams = parsed["params"]
	assert_int(p.width).is_equal(32)  # from the base
	assert_int(p.loops_max).is_equal(1)
	assert_float(p.tower_range).is_equal(2.0)  # JSON int for a float knob
	assert_int(p.c5_d).is_equal(5)  # JSON int-valued float for an int knob
	assert_array(p.to_dict().keys()).is_equal(Array(MapGenParams.KEYS))


func test_from_dict_rejects_unknown_keys_and_wrong_types() -> void:
	for d: Dictionary in [{"nope": 1}, {"width": "wide"}, {"grid_kind": 3}, {"c1_m": 2.5},
			{"tower_range": "far"}]:
		var parsed := MapGenParams.from_dict(d)
		assert_object(parsed["params"]).override_failure_message(str(d)).is_null()
		assert_array(parsed["errors"]).override_failure_message(str(d)).is_not_empty()
	var unknown: PackedStringArray = MapGenParams.from_dict({"nope": 1})["errors"]
	assert_str(unknown[0]).contains("nope")


## One violation per check() rule (S20 F4 / F5); each names the knob it rejects.
func test_check_bounds() -> void:
	var cases := {
		"attempt_cap": {"attempt_cap": 1001},
		"sea_max": {"sea_max": 19},
		"waypoint_jitter": {"waypoint_jitter": -1},
		"c4_lmin": {"c4_lmin": 41},
		"c7_hud_rows": {"c7_hud_rows": 16},
		"choke_k": {"choke_k": -1},
		"grid_kind": {"grid_kind": "tri"},
		"entries": {"entries_min": 3, "entries_max": 2},
	}
	for knob: String in cases:
		var parsed := MapGenParams.from_dict(cases[knob])
		var errors: PackedStringArray = parsed["errors"]
		assert_object(parsed["params"]).override_failure_message(knob).is_null()
		assert_str("; ".join(errors)).override_failure_message(knob + ": " + str(errors)) \
			.contains(knob)


func test_check_edges_are_accepted() -> void:
	for d: Dictionary in [{"attempt_cap": 1000}, {"sea_max": 18}, {"waypoint_jitter": 0},
			{"c4_lmin": 40}, {"c7_hud_rows": 15}, {"choke_k": 0}]:
		var parsed := MapGenParams.from_dict(d)
		assert_array(parsed["errors"]).override_failure_message(str(d)).is_empty()


# --- GenMap ------------------------------------------------------------------------------------

func test_from_rows_rejects_bad_fixtures() -> void:
	assert_object(GenMap.from_rows("tri", ["L#S"])).is_null()
	assert_object(GenMap.from_rows("hex", ["L#S", "##"])).is_null()  # ragged
	assert_object(GenMap.from_rows("hex", ["L#X"])).is_null()  # not in the legend
	assert_object(GenMap.from_rows("hex", ["##S"])).is_null()  # no L
	assert_object(GenMap.from_rows("hex", ["L#L"])).is_null()  # two L
	assert_object(GenMap.from_rows("hex", [])).is_null()


func test_from_rows_round_trip() -> void:
	var rows := ["~.#S", "L^#S"]
	var m := GenMap.from_rows("hex", rows)
	assert_array(Array(m.rows())).is_equal(rows)
	assert_array(m.entries).is_equal([m.grid.cell_of_text(3, 0), m.grid.cell_of_text(3, 1)])
	assert_that(m.lighthouse).is_equal(m.grid.cell_of_text(0, 1))
	assert_int(m.kind_at(m.grid.cell_of_text(0, 0))).is_equal(T.SEA)
	assert_int(m.kind_at(m.grid.cell_of_text(1, 0))).is_equal(T.ISLAND)
	assert_int(m.kind_at(m.grid.cell_of_text(1, 1))).is_equal(T.ROCK)
	assert_dict(m.to_map_dict()).is_equal({"width": 4, "height": 2, "grid": "hex", "rows": rows})


## §3: digest = sha256 of "mapv2|<kind>|<w>x<h>|" + rows + "|E:" + entries + "|P:" + pockets,
## coords as text "x,y" in ascending index.
func test_digest_hashes_the_canonical_text() -> void:
	var m := GenMap.from_rows("hex", ["~.#S", "L^#S"])
	var got := m.canonical()
	assert_str(got).starts_with("mapv2|hex|4x2|~.#S\nL^#S|E:")
	assert_bool(got.find("3,0") > 0 and got.find("3,0") < got.find("3,1")).is_true()
	assert_str(got).ends_with("|P:")
	assert_str(m.digest()).is_equal(got.sha256_text())
	assert_str(GenMap.from_rows("hex", ["~^#S", "L^#S"]).digest()).is_not_equal(m.digest())
