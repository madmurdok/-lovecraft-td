class_name ChokepointMetricTest
extends GdUnitTestSuite
## LT-130 §8 (docs/design/LT-130-p1-generator.md §4, §8, §9 Q2, §10; LT-18 §8): the chokepoint
## metric on hand-made fixtures (GenMap.from_rows). Expected numbers are worked out from the
## geometry in the comments, not read from the code.
##
## Hex lane fixture (`_lane`): 3 text rows, the route along row 1 from S (x = 27) to L (x = 0),
## islands only in rows 0 and 2. Row 1 text (x, 1) is axial (x, 1); rows 0 and 2 text (x, y)
## sit half a cell left of it, one row pitch away, so 4 d^2 = (2 (xi - xc) - 1)^2 + 3 and
## "within R = 3" means xi - xc in [-2, 3]: a route cell xc sees islands xi in [xc - 2, xc + 3],
## an island xi sees route cells xc in [xi - 3, xi + 2] (exposure 6 away from the ends).
##
## Controls (code revert -> failing test), described for the verify slice:
##  T4: chokepoints() counts a cell without the K test (every CHANNEL route cell)
##      -> test_c1_removing_one_cluster_fails_c1_only fails (no C1 after the removal).
##  T5: c2_max_blind returns 0 -> test_c2_nine_blind_cells_fail_eight_pass fails.
##  T6: c3_convergence skips the same-cell check
##      -> test_c3_different_last_chokepoints_fail fails.
##  T7: c5_detours builds the field without blocking the chokepoint (RouteField.build(m))
##      -> test_c5_detour_two_and_six fails (deltas 0, 0).
##  S20 integer disc: disc() back to LightRules.in_cast_radius(grid.centre(b), r,
##      grid.centre(cell)) -> test_hex_disc_r3_is_37_on_every_interior_cell fails
##      (rows with 33 / 35).

const LANE_W := 28


func _at(m: GenMap, x: int, y: int) -> Vector2i:
	return m.grid.cell_of_text(x, y)


## The hex lane: islands in rows 0 and 2 at the text x listed, rock elsewhere.
func _lane(islands: Array) -> GenMap:
	var side := ""
	for x in LANE_W:
		side += "." if islands.has(x) else "^"
	return GenMap.from_rows("hex", [side, "L" + "#".repeat(LANE_W - 2) + "S", side])


func _range(from: int, to: int) -> Array:
	return range(from, to + 1)


func _ints(a: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(a)
	return out


## Default thresholds except C2 (the C1 fixture has long blind stretches by design).
func _c1_params() -> MapGenParams:
	var p := MapGenParams.p1_small()
	p.c2_g = 1000
	return p


# --- R disc (S20: integer range test) ---------------------------------------------------------

## Hex cells within 3 steps: 1 + 6 + 12 + 18 = 37; the ring-3 corners lie exactly 3 apart and
## no ring-4 cell is within sqrt(12) > 3, so the R = 3 disc is the 3-step ball on every row.
func test_hex_disc_r3_is_37_on_every_interior_cell() -> void:
	var m := GenMap.blank("hex", 32, 18)
	var bad: Array[String] = []
	var checked := 0
	for c in m.grid.cells():
		var t := m.grid.text_of(c)
		if t.x < 3 or t.x > 28 or t.y < 3 or t.y > 14:
			continue
		checked += 1
		var n := ChokepointMetric.disc(m, c, 3.0).size()
		if n != 37:
			bad.append("(%d,%d)=%d" % [t.x, t.y, n])
	assert_int(checked).is_equal(26 * 12)
	assert_array(bad).override_failure_message("R=3 disc not 37 at " + ", ".join(bad)).is_empty()


func test_hex_disc_matches_the_step_ball() -> void:
	var m := GenMap.blank("hex", 32, 18)
	for t: Vector2i in [Vector2i(10, 6), Vector2i(10, 7), Vector2i(15, 9)]:
		var c := _at(m, t.x, t.y)
		for r: int in [2, 3]:
			var ball := 0
			for b in m.grid.cells():
				if m.grid.steps(b, c) <= r:
					ball += 1
			assert_int(ChokepointMetric.disc(m, c, float(r)).size()).is_equal(ball)
		assert_int(ChokepointMetric.disc(m, c, 2.0).size()).is_equal(19)


## Square: dx^2 + dy^2 <= 9 -> 7 + 2 * 5 + 2 * 5 + 2 * 1 = 29; <= 6.25 -> 5 + 2 * 5 + 2 * 3 = 21.
func test_square_disc_counts() -> void:
	var m := GenMap.blank("square", 24, 16)
	var c := Vector2i(10, 8)
	assert_int(ChokepointMetric.disc(m, c, 3.0).size()).is_equal(29)
	assert_int(ChokepointMetric.disc(m, c, 2.5).size()).is_equal(21)


func test_disc_counts_only_islands() -> void:
	var m := _lane([5, 6])
	# route cell x = 4 sees islands x in [2, 7] of rows 0 and 2: 5 and 6, twice
	assert_int(ChokepointMetric.disc(m, _at(m, 4, 1), 3.0).size()).is_equal(4)


# --- T4 / C1 -----------------------------------------------------------------------------------

## Two clusters of 2 islands per side row (x 5-6 and 18-19). A route cell xc has >= K = 3 islands
## of exposure >= E = 4 in its disc iff it sees both cells of a cluster: xc in [a - 2, a + 2], so
## chokepoints are x 3..7 and 16..20. Route positions are 27 - x: 7..11 and 20..24; greedy
## spacing S = 6 from the entry takes 7 and 20 -> 2 = M. Every chokepoint is a cut (one lane),
## so C5 passes; C3 is n/a; length 27 fits C4; C6 needs cost >= 9 (S is at 27); no island is near
## L or in a HUD row (C7).
func test_c1_two_spaced_clusters_pass() -> void:
	var m := _lane([5, 6, 18, 19])
	var rep := ChokepointMetric.evaluate(m, _c1_params())
	var want: Array[Vector2i] = []
	for x in [20, 19, 18, 17, 16, 7, 6, 5, 4, 3]:
		want.append(_at(m, x, 1))
	assert_array(rep.chokepoints[0]).is_equal(want)
	assert_int(rep.spaced[0]).is_equal(2)
	assert_array(rep.reasons).is_empty()
	assert_bool(rep.passed).is_true()
	assert_int(ChokepointMetric.exposure(m.grid, _at(m, 5, 0), rep.routes[0], 3.0)).is_equal(6)


func test_c1_removing_one_cluster_fails_c1_only() -> void:
	var m := _lane([5, 6])
	var rep := ChokepointMetric.evaluate(m, _c1_params())
	assert_int(rep.chokepoints[0].size()).is_equal(5)
	assert_int(rep.spaced[0]).is_equal(1)
	assert_array(rep.reasons).is_equal(PackedStringArray(["C1"]))
	assert_bool(rep.passed).is_false()


func test_c1_spaced_is_greedy_from_the_entry() -> void:
	assert_int(ChokepointMetric.c1_spaced(PackedInt64Array([1, 2, 7, 8, 13]), 6)).is_equal(3)
	assert_int(ChokepointMetric.c1_spaced(PackedInt64Array([1, 6]), 6)).is_equal(1)
	assert_int(ChokepointMetric.c1_spaced(PackedInt64Array(), 6)).is_equal(0)


func test_entry_and_lighthouse_are_never_chokepoints() -> void:
	var p := _c1_params()
	p.choke_k = 0
	p.choke_e = 0
	var rep := ChokepointMetric.evaluate(_lane([]), p)
	var cells: Array = rep.chokepoints[0]
	assert_int(cells.size()).is_equal(LANE_W - 2)
	assert_bool(cells.has(rep.routes[0][0])).is_false()
	assert_bool(cells.has(rep.routes[0].back())).is_false()


# --- T5 / C2 -----------------------------------------------------------------------------------

## Islands at x <= A and x >= B: route cell xc is blind iff [xc - 2, xc + 3] misses both, i.e.
## xc in [A + 3, B - 4]: B - A - 6 cells. A = 4: B = 19 -> 9 blind, B = 18 -> 8 (G = 8).
func test_c2_nine_blind_cells_fail_eight_pass() -> void:
	var p := MapGenParams.p1_small()
	var nine := ChokepointMetric.evaluate(_lane(_range(0, 4) + _range(19, LANE_W - 1)), p)
	assert_int(nine.max_blind[0]).is_equal(9)
	assert_bool(nine.reasons.has("C2")).is_true()
	var eight := ChokepointMetric.evaluate(_lane(_range(0, 4) + _range(18, LANE_W - 1)), p)
	assert_int(eight.max_blind[0]).is_equal(8)
	assert_bool(eight.reasons.has("C2")).is_false()


# --- T6 / C3 -----------------------------------------------------------------------------------

## Square Y: entries at (9,0) and (9,6), branches down / up x = 4 to the trunk (0..4, 3), L at
## (0,3). Each route has 13 cells: index 3 = (6,0) or (6,6) (cost 9), 9 = (3,3) (cost 3),
## 11 = (1,3) (cost 1). Common cells: the trunk, 5 -> share 5 * 100 / 13 = 38 %.
func _y() -> GenMap:
	return GenMap.from_rows("square", [
		"^^^^#####S",
		"^^^^#^^^^^",
		"^^^^#^^^^^",
		"L####^^^^^",
		"^^^^#^^^^^",
		"^^^^#^^^^^",
		"^^^^#####S",
	])


func _c3(m: GenMap, chokes: Array, floor_cells: int, share_pct := 50) -> Dictionary:
	var p := MapGenParams.p1_small()
	p.floor_cells = floor_cells
	p.c3_share_pct = share_pct
	var f := RouteField.build(m)
	var routes := []
	for e in m.entries:
		routes.append(f.route(e))
	return ChokepointMetric.c3_convergence(m, routes, chokes, f, p)


func test_c3_shared_last_chokepoint_passes() -> void:
	var m := _y()
	var out := _c3(m, [PackedInt64Array([3, 9]), PackedInt64Array([3, 9])], 2)
	assert_bool(out["ok"]).is_true()
	assert_that(out["last_shared"]).is_equal(Vector2i(3, 3))
	assert_int(out["share_pct"]).is_equal(38)


func test_c3_different_last_chokepoints_fail() -> void:
	var m := _y()
	var out := _c3(m, [PackedInt64Array([3]), PackedInt64Array([3])], 2)
	assert_bool(out["ok"]).is_false()
	assert_that(out["last_shared"]).is_equal(GenMap.NO_CELL)


## A shared chokepoint inside the floor (cost 1 < floor 2) does not count: the last ones before
## the floor are the branch cells, which differ.
func test_c3_chokepoint_inside_the_floor_does_not_count() -> void:
	var m := _y()
	var out := _c3(m, [PackedInt64Array([3, 11]), PackedInt64Array([3, 11])], 2)
	assert_bool(out["ok"]).is_false()


func test_c3_share_over_the_limit_fails() -> void:
	var m := _y()
	var out := _c3(m, [PackedInt64Array([3, 9]), PackedInt64Array([3, 9])], 2, 30)
	assert_bool(out["ok"]).is_false()
	assert_int(out["share_pct"]).is_equal(38)


func test_c3_one_entry_is_not_applicable() -> void:
	var rep := ChokepointMetric.evaluate(_lane([5, 6, 18, 19]), _c1_params())
	assert_int(rep.shared_share_pct).is_equal(-1)
	assert_bool(rep.reasons.has("C3")).is_false()


# --- C4 ----------------------------------------------------------------------------------------

func test_c4_lengths_and_ratio() -> void:
	var p := MapGenParams.p1_small()  # 20..40, longest * 100 <= shortest * 140
	assert_bool(ChokepointMetric.c4_lengths(_ints([20, 28]), p)).is_true()
	assert_bool(ChokepointMetric.c4_lengths(_ints([20, 29]), p)).is_false()
	assert_bool(ChokepointMetric.c4_lengths(_ints([19]), p)).is_false()
	assert_bool(ChokepointMetric.c4_lengths(_ints([41]), p)).is_false()
	assert_bool(ChokepointMetric.c4_lengths(_ints([40]), p)).is_true()


# --- T7 / C5 -----------------------------------------------------------------------------------

## Square lane L (0,1) .. S (11,1) with a bypass over x 3..7, `up` rows above it: blocking (5,1)
## (route index 6) forces up, 4 across, down: +2 * up cells. (1,1) and (9,1) have no way around.
func _bypass(up: int) -> GenMap:
	var rows := ["^^^#####^^^^"]
	for i in up - 1:
		rows.append("^^^#^^^#^^^^")
	rows.append("L##########S")
	rows.append("^^^^^^^^^^^^")
	return GenMap.from_rows("square", rows)


func _detours(m: GenMap, positions: Array, stop_at_d := -1) -> Array[int]:
	var f := RouteField.build(m)
	var r := f.route(m.entries[0])
	return ChokepointMetric.c5_detours(m, f, r, PackedInt64Array(positions), {}, stop_at_d)


func test_c5_detour_two_and_six() -> void:
	assert_array(_detours(_bypass(1), [6])).is_equal([2])
	assert_array(_detours(_bypass(3), [6])).is_equal([6])


func test_c5_cut_cells_report_cut() -> void:
	var cut := ChokepointMetric.CUT
	assert_array(_detours(_bypass(1), [2, 6, 10])).is_equal([cut, 2, cut])


## stop_at_d walks from the L end and stops at the first cut or >= D; the rest are SKIPPED.
func test_c5_early_exit_from_the_lighthouse_end() -> void:
	var sk := ChokepointMetric.SKIPPED
	assert_array(_detours(_bypass(1), [2, 6, 10], 4)).is_equal([sk, sk, ChokepointMetric.CUT])
	assert_array(_detours(_bypass(3), [2, 6], 4)).is_equal([sk, 6])


## Owner Q2: a route passes with at least one chokepoint that is cut or >= D.
func test_c5_passes_needs_one_cut_or_long_detour() -> void:
	var cut := ChokepointMetric.CUT
	assert_bool(ChokepointMetric.c5_passes(_ints([2]), 4)).is_false()
	assert_bool(ChokepointMetric.c5_passes(_ints([6]), 4)).is_true()
	assert_bool(ChokepointMetric.c5_passes(_ints([4]), 4)).is_true()
	assert_bool(ChokepointMetric.c5_passes(_ints([cut]), 4)).is_true()
	assert_bool(ChokepointMetric.c5_passes(_ints([2, 2, 6]), 4)).is_true()
	assert_bool(ChokepointMetric.c5_passes(_ints([]), 4)).is_false()


## Three parallel channel rows, L and S on the middle one: a barricade anywhere on the middle row
## costs exactly +2 (around through row 0), so with every route cell a chokepoint (K = E = 0)
## the map fails C5 at D = 4 and passes at D = 2.
func test_c5_evaluate_two_cell_detours_everywhere() -> void:
	var m := GenMap.from_rows("square", ["############", "L##########S", "############"])
	var p := MapGenParams.p1_small()
	p.choke_k = 0
	p.choke_e = 0
	var rep := ChokepointMetric.evaluate(m, p)
	assert_int(rep.chokepoints[0].size()).is_equal(10)
	var twos: Array[int] = []
	for i in 10:
		twos.append(2)
	assert_array(rep.detour_deltas[0]).is_equal(twos)
	assert_bool(rep.reasons.has("C5")).is_true()
	p.c5_d = 2
	assert_bool(ChokepointMetric.evaluate(m, p).reasons.has("C5")).is_false()


# --- C6 ----------------------------------------------------------------------------------------

## floor_cells 6 + c6_extra 3: the route needs a cell at cost >= 9 cells (the entry is the
## farthest cell of a one-lane route).
func test_c6_floor_room() -> void:
	var p := MapGenParams.p1_small()
	for steps: int in [9, 8]:
		var m := GenMap.from_rows("hex", ["L" + "#".repeat(steps - 1) + "S"])
		var f := RouteField.build(m)
		assert_bool(ChokepointMetric.c6_floor_room(f.route(m.entries[0]), f, p)) \
			.override_failure_message("steps %d" % steps).is_equal(steps >= 9)


# --- C7 ----------------------------------------------------------------------------------------

## L at text (0,1) = axial (0,1). Islands: text (3,0) (3 steps from L, top row), text (0,2) =
## axial (-1,2) (its SW neighbour, 1 step) and text (3,2) (3 steps, bottom row).
func test_c7_hidden_cells() -> void:
	var m := GenMap.from_rows("hex", ["^^^.^", "L###S", ".^^.^"])
	var p := MapGenParams.p1_small()  # hud rows 0, L cover 1
	assert_array(ChokepointMetric.c7_clickable(m, p)).is_equal([_at(m, 0, 2)])
	assert_bool(ChokepointMetric.evaluate(m, p).reasons.has("C7")).is_true()
	p.c7_hud_rows = 1
	assert_array(ChokepointMetric.c7_clickable(m, p)).is_equal([_at(m, 3, 0), _at(m, 0, 2)])
	p.c7_hud_rows = 0
	p.c7_l_cover = 0
	assert_array(ChokepointMetric.c7_clickable(m, p)).is_empty()


# --- report ------------------------------------------------------------------------------------

func test_unreached_entry_is_s1_and_skips_the_rules() -> void:
	var rep := ChokepointMetric.evaluate(GenMap.from_rows("hex", ["L#^#S"]),
		MapGenParams.p1_small())
	assert_array(rep.reasons).is_equal(PackedStringArray(["S1"]))
	assert_bool(rep.passed).is_false()
	assert_array(rep.lengths).is_empty()
