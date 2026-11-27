# LT-130: Map v2 grey prototype P1, generator + chokepoint metric

Design note for LT-18 §11 step P1. Builds on LT-18 §2 (cell model), §3 (route field), §7
(pockets), §8 (metric), §9 option (a) skeleton graph; §13's owner decisions are fixed. HexGrid is
registered in `GridFactory` since LT-129. No production code changes outside new `sim/mapgen/`
files, one guard allowlist line and one export filter.

Acceptance (LT-18 §11 P1): maps read at a glance (owner reviews a 20-seed screenshot); reject
rate < 30 %; < 200 ms per map; same seed -> same map digest (test).

## 1. File layout

| File | Slice | Role |
|---|---|---|
| `sim/mapgen/map_rng.gd` (`MapRng`) | code | the map's own PCG32 (one `RandomNumberGenerator`); `randi_range` only |
| `sim/mapgen/map_gen_params.gd` (`MapGenParams`) | code | generator knobs + §8 thresholds, code defaults, `from_dict` for the tool |
| `sim/mapgen/gen_map.gd` (`GenMap`) | code | the output struct: grid, terrain per cell, entries, `L`, pockets, links; `rows()`, `to_map_dict()`, `digest()`, `from_rows()` (fixtures) |
| `sim/mapgen/route_field.gd` (`RouteField`) | code | §3 reverse Dijkstra from `L`, integer, no barricades yet; LT-109 adds the breach weight here |
| `sim/mapgen/chokepoint_metric.gd` (`ChokepointMetric`, `MetricReport`) | code | §8 C1-C7, pure static |
| `sim/mapgen/map_generator.gd` (`MapGenerator`, `GenResult`) | code | §9(a) skeleton -> rasterize -> islands -> metric -> retry |
| `tools/mapgen/mapgen_report.gd` + `scripts/mapgen-report.sh` | tool | headless report, kept (balance lab uses it later) |
| `tools/proto/map_viewer.gd` + `.tscn` | tool | throwaway grey viewer, excluded from export |

Architecture guards, how each new file obeys:

- **Sim boundary** (`tests/sim_boundary_test.gd`): `sim/mapgen/` files are `RefCounted`, static or
  plain data; engine types only from `ENGINE_ALLOWLIST` (`String.sha256_text()` for the digest);
  no `preload`, `signal`, `await`, `Time`, `OS`. Draws only as `_rng.randi_range(...)` (a dotted
  call, allowed). `RandomNumberGenerator` may be named only in `SIM_RNG_HOMES`, so
  `res://sim/mapgen/map_rng.gd` is **appended to `SIM_RNG_HOMES`** (one guard line). `SimRng` is
  not reused: its streams are seeded from the run seed and the map must not shift combat
  rolls (§9).
- **G10** (one topology): the new files have no "grid" in their names, so they get no topology
  exemption: no neighbour offsets, no `for x in .width` loops, no bounds tests. Everything goes
  through `grid.cells() / neighbours / steps / distance / index / text_of / contains`.
- **G15**: grids only via `GridFactory.make(kind, w, h)`, never `HexGrid.new(`.
- **G3 / G2**: centres only from `grid.centre()`; the viewer has its own scale names (no `CELL`,
  `BOARD_ORIGIN`, `ORIGIN`). **G11**: no trig in `sim/`; the viewer (tools/) may use it, but
  the jitter needs none (§6).
- **G1 / G7 / boundary #2**: the tools read only `sim/mapgen/` and `sim/rules/` classes, no Simulation, no
  selection, no rule copies.

## 2. Public APIs

```gdscript
# MapGenerator (static)
static func generate(map_seed: int, p: MapGenParams) -> GenResult
static func attempt(attempt_seed: int, p: MapGenParams) -> GenMap   # one try, no metric

# GenResult
var map: GenMap            # accepted map, or null when the cap was hit
var report: MetricReport   # metric of the accepted map (of the last attempt on failure)
var attempts: int          # 1 + rejected attempts
var rejects: Array[PackedStringArray]  # reason codes per rejected attempt, in order
var error: String          # "" or "attempt cap 50 reached (seed 17): C1 x41, C5 x9"

# ChokepointMetric (static)
static func evaluate(m: GenMap, p: MapGenParams) -> MetricReport
```

**Inputs.** `map_seed: int`; `MapGenParams` holds `grid_kind` ("hex" default, "square"
accepted since everything goes through `GridTopology`), `width`, `height`, entry count range,
loops, pockets, widths and every §8 threshold (§4). All integers except `tower_range: float`.

**Output: a `GenMap` struct, not a `MapDef`.** Today's `MapDef` knows 3 kinds, exactly one `S`
and validates one non-forking path (`_derive_path`); a generated network with 2-3 entries, loops
and pockets fails that parse. Changing `MapDef` is LT-109 (golden, 46 test files). So `GenMap`
carries the LT-18 §2 terrain enum (`SEA, CHANNEL, ISLAND, ROCK, ENTRY, LIGHTHOUSE`, a
`PackedByteArray` indexed by `grid.index`) and emits `to_map_dict()` in the map.json shape
(`width`, `height`, `grid`, `rows` in the §2 legend `~ # . ^ S L`). LT-109's MapDef v2 parses
that dict with no generator change; the enum then moves into `MapDef` and `GenMap` keeps the
generator-only extras (pockets, links, skeleton nodes for the viewer).

**Reject path.** Attempt `a` (0-based) is seeded `map_seed * 1000 + a` (§9). Reason codes:

- `S1` structural: some entry does not reach `L` in the route field (a rasterizer bug or a
  carve blocked by the sea band); `S2`: fewer entries placed than drawn (no free sea-edge row).
- `C1`..`C7`: the metric's failed rules, each code with a detail string in the report.

`generate` loops until the report passes or `attempt_cap` (default 50) attempts ran; on the cap
it returns `map = null` and a non-empty `error` ("fails loudly": the tool prints it and exits 1;
the sim has no logger). Never returns a failing map.

## 3. RNG and determinism

- **One `RandomNumberGenerator` per attempt** inside `MapRng`, `seed = map_seed * 1000 +
  attempt`; draws only `randi_range(from, to)` (PCG32 bounded integer: platform-independent).
  No `randf`, no global `randi()`, no `hash()` of Variants.
- **Fixed draw order.** The generator's steps (§9 algorithm below) draw in a pinned order;
  a draw happens whenever a choice has 2+ candidates, never conditionally on anything but map
  state. Candidate lists come from `grid.neighbours()` (pinned order) or ascending
  `grid.index`.
- **No Dictionary or set iteration.** Per-cell data lives in `Packed*Array`s indexed by
  `grid.index`; a Dictionary is used for lookups only, never iterated. Sorting only on unique
  integer keys (`sort_custom` is unstable).
- **Integers in the generator and field.** Costs in sim units (`SimTime.UNITS_PER_CELL`).
  The only float is the metric's range test, `LightRules.in_cast_radius(grid.centre(b), R,
  grid.centre(p))` (the game's own boundary-inclusive range test; IEEE `+ * sqrt`, no trig, so
  identical on every platform). A test pins the R = 3 disc size so a rounding change at the
  ring-3 corners shows.
- **Heap.** `RouteField` uses a binary heap of `cost * cell_count + index` in a
  `PackedInt64Array`: ordered by `(cost, grid.index)` as §3 pins. Next hop of a cell = the first
  neighbour in `neighbours()` order with `cost == cost(cell) - step_cost` (§3's tie rule).
- **Digest.** `GenMap.digest() = canonical().sha256_text()`, with
  `canonical() = "mapv2|<kind>|<w>x<h>|" + "\n".join(rows()) + "|E:" + entries + "|P:" + pockets`,
  entries and pocket cells as text coords `x,y` in ascending `grid.index`. The seed is not in the
  digest: it identifies the map, not how it was found.

**Generator steps (one attempt), draw order as listed:**

1. Grid via `GridFactory.make`. Every cell starts as land (ISLAND).
2. Sea band: per text row ascending, depth `randi_range(sea_min, sea_max)` (1-2) cells from the
   east edge become SEA (`text_of(cell).x >= w - depth`).
3. `L`: text x in `[1, 2]`, y in the middle half; drawn x then y.
4. Entries: `k = randi_range(entries_min, entries_max)`; the rows are split into `k` bands, one
   row drawn per band; the entry is the first non-sea cell west of the sea in that row (ENTRY).
5. Funnel node `F` (shared final approach, C3): `funnel_steps` (default floor + 3) steps from
   `L` toward the entries' mean row; one waypoint per entry, jittered `±3` rows around the
   entry-to-`F` midpoint.
6. Corridors: a greedy carve walk `entry -> waypoint -> F -> L`: each step moves to a neighbour
   with `steps(n, target) == steps(cur, target) - 1`, one draw among the 1-2 candidates; with
   `wide_pct` chance (one draw) one more neighbour of the step is carved (width 2).
7. Loops: `loops` (1-2) links, each between a cell of the middle third of corridor `i` and of
   corridor `i + 1` (a single-entry map gets a second waypoint -> `F` bypass instead).
8. Pockets: `pockets` (1-3) spurs of `randi_range(2, 6)` cells, from a corridor cell within 4
   steps of the sea, carved away from other channel cells; the next cell becomes ROCK. A spur
   that would touch another channel is dropped (draws already spent, so the order is unchanged).
9. Islands: land components in ascending index (BFS over `neighbours`); a component of more than
   `island_max` (12) cells is split by multi-source BFS from `ceil(size / 8)` drawn seed cells,
   the boundary cells between regions become ROCK; components below `island_min` (4) become ROCK.
10. `RouteField.build`, then `S1`/`S2` checks, then `ChokepointMetric.evaluate`.

## 4. §8 rules -> functions

All `static` on `ChokepointMetric`; `routes` = one `Array[Vector2i]` per entry from the field
(entry ... `L`); `build` = ISLAND cells. Precomputation, once per map: `disc[p]` = buildable
cells within `R` of route cell `p` (O(route cells x cells), ~15k range tests per route).

| Rule | Function | Needs | Defaults (`MapGenParams`) |
|---|---|---|---|
| exposure | `exposure(grid, b, route, R) -> int` | route cells, R | `tower_range` 3.0 (rifleman L1) |
| chokepoint | `chokepoints(grid, route, build, p) -> PackedInt32Array` (route positions) | discs, exposure per `b` | K 3, E 4 |
| C1 | `c1_chokepoints(chokes_per_route, p)` | chokepoint positions | M 2, S 6 |
| C2 | `c2_max_blind(route, discs) -> int` | discs | G 8 |
| C3 | `c3_convergence(routes, chokes, field, p) -> {last_shared, share_pct}` | routes, field costs | floor 6, share <= 50 % |
| C4 | `c4_lengths(routes, p)` | route lengths | Lmin 20, Lmax 40, ratio `max*100 <= min*140` |
| C5 | `c5_detours(m, field, route, positions, cache, stop_at_d) -> Array[int]`, `c5_passes(deltas, D)` | a re-run `RouteField.build(m, [p])` per chokepoint, from the L end, stopping at the first qualifying one | D 4; per route at least one chokepoint is `cut` or `>= D` (Q2) |
| C6 | `c6_floor_room(routes, field, p)` | field costs | some route cell at cost `>= (floor + 3)` cells |
| C7 | `c7_clickable(m, p)` | grid, `L` | P1 proxy: no ISLAND in the top `hud_rows` text rows (0) or within `l_cover` steps of `L` (1); LT-64 replaces it |

Definitions the code must keep:
- C3: "last chokepoint before the floor" = the chokepoint with the smallest field cost
  `>= floor_cells` on each route; all routes must name the same cell. Share = cells common to
  every route / the shortest route's length. **With one entry C3 is not applicable** (always
  passes, reported "n/a"): a single route is 100 % shared by definition.
- C5: delta = (entry cost with `p` blocked) - (entry cost) in cells; a chokepoint with no detour
  at all (a cut cell) reports `cut` (-1); chokepoints left unmeasured after the early exit
  report `skipped` (-2). Q2 decided: a route passes when at least one chokepoint is `cut` or
  `>= D`; the others are unconstrained.
- C4 integer ratio, no float division. C2 counts consecutive route cells whose disc is empty.

`MetricReport` (per map): `passed`, `reasons: PackedStringArray`, and per route: `length`,
`chokepoints` (cells), `max_blind`, `detour_deltas` (int or -1 = cut), plus `shared_share_pct`
and `last_shared` cell. The tool prints exactly these (§8 "report per map").

## 5. Headless tool

`scripts/mapgen-report.sh [args]` -> `uptime`, then `/usr/bin/time -p "$GODOT" --headless --path .
-s res://tools/mapgen/mapgen_report.gd -- <args>`, same re-import guard and `SCRIPT ERROR` check
as `scripts/golden-regen.sh`. Args (after `--`):

- `--from 1 --count 1000` seed range; `--kind hex --width 24 --height 16`; `--params f.json`
  (optional overrides through `MapGenParams.from_dict`); `--maps` print one line per map;
  `--out report.json`.

Output:
- per map (with `--maps`): `seed attempts digest[0:12] len=[..] chokes=[..] blind=[..]
  share=.. detours=[..] reasons-of-rejected-attempts`;
- summary: seeds, accepted, cap failures, **reject rate = rejected attempts / all attempts**,
  first-attempt pass rate, reject histogram by code, **time per map** (accepted map incl. its
  retries, `Time.get_ticks_usec` around `generate`) mean / p95 / max, and the slowest seed;
- the wrapper's `uptime` line and `time -p` real / user / sys (tools/ may use `Time`).

Pass if reject rate < 30 %, p95 < 200 ms, no cap failure. 1000 seeds at ~50-100 ms each is
1-2 minutes: the verify slice runs it with `run_in_background`.

## 6. Grey viewer (throwaway)

`tools/proto/map_viewer.tscn` + `map_viewer.gd` (a `Node2D` drawing in `_draw`, no `_process`).
Launch: `"$GODOT" --path . res://tools/proto/map_viewer.tscn -- --mute [--from 1]
[--screenshot out.png]`; it calls `DebugArgs.apply_mute` like `game.gd`, though it plays no
sound.

- 20 seeds side by side (5 x 4), each map scaled into its tile, seed and pass/attempts above it.
- Flat-coloured polygons per terrain; **H** toggles plain hexes (`grid.polygon`) vs jittered
  ones: each shared vertex is moved by an offset hashed from its rounded position (no RNG, so
  neighbours meet; LT-18 §2). Routes as polylines through `grid.centre`, one colour per entry;
  chokepoints as rings; pockets hatched; links (loops) dashed; `F` marked. **N / P** page the
  next / previous 20 seeds.
- `--screenshot`: waits two frames, saves the viewport PNG, quits (the owner's 20-seed review).

Kept out of the game: nothing under `scenes/`, `ui/` or `sim/` references `tools/proto/`;
`export_presets.cfg` `exclude_filter` gains `tools/proto/*`; the guards scan tools/ anyway (G1,
G2, G3, G7, G10, G15 apply). Deleted when the generator enters the real game (LT-18 §11 last
step); the report tool stays.

## 7. Edit map

**Code slice (pure rules + tests):**
- New: the six `sim/mapgen/` files of §1, and `tests/map_generator_test.gd`,
  `tests/chokepoint_metric_test.gd`, `tests/route_field_test.gd`.
- Change `tests/sim_boundary_test.gd` lines 53-54: append `"res://sim/mapgen/map_rng.gd"` to
  `SIM_RNG_HOMES`.
- Read for context: `GridTopology` (all abstract signatures), `HexGrid.neighbours / steps /
  text_of / cell_of_text`, `GridFactory.make`, `LightRules.in_cast_radius`,
  `SimRoute.from_cells` (the field's route output is what LT-109 will feed it),
  `SimRng._init` (seeding pattern), `SimTime.UNITS_PER_CELL`, `MapDef.parse` (the dict shape
  `to_map_dict` must match).

**Tool slice (after the code slice merges):**
- New: `tools/mapgen/mapgen_report.gd`, `scripts/mapgen-report.sh`, `tools/proto/map_viewer.gd`,
  `tools/proto/map_viewer.tscn`.
- Change `export_presets.cfg` line 11: `exclude_filter="addons/gdUnit4/*, tests/*, tools/proto/*"`.
- Read: `tools/golden/regen.gd` `_initialize` (SceneTree tool pattern), `scripts/golden-regen.sh`,
  `scenes/debug_args.gd` `apply_mute`.
- Then: tune `MapGenParams` defaults until 1000 seeds pass §5's bar (double/halve first, per the
  lab rule), and produce the 20-seed screenshot for the owner.

The cut: the code slice proves determinism and every rule on hand-made fixtures; it does not
claim the reject rate or timing. The tool slice measures those and may only change
`MapGenParams` defaults and the generator's step parameters, not the metric's definitions.

## 8. Tests and controls

| # | Behaviour pinned | Test | Control (revert in code, test must fail) |
|---|---|---|---|
| T1 | same seed -> same digest | `generate(s)` twice, digests equal; digests of seeds 1, 2, 3 pinned as constants computed by the code once | seed `MapRng` from a static call counter instead of the seed |
| T2 | seed matters | 20 seeds -> >= 19 distinct digests | ignore `map_seed` (always seed 0 + attempt) |
| T3 | field ties | symmetric diamond fixture: next hop is the first neighbour in `neighbours()` order; a one-corridor fixture yields exactly its cells | take the last equal-cost neighbour |
| T4 | C1 chokepoints | fixture passes; same with the islands of one stretch removed -> `C1` only | count a chokepoint without the `K` test |
| T5 | C2 blind stretch | 9-cell blind stretch -> `C2` (8 passes) | `c2_max_blind` returns 0 |
| T6 | C3 convergence | two entries with different last chokepoints -> `C3`; one entry -> n/a | skip the same-cell check |
| T7 | C5 detour | loop of +6 passes, +2 -> `C5`; cut cell reported `cut` | re-run the field without blocking `p` |
| T8 | reject path | impossible params (`M = 99`): `map == null`, `attempts == cap`, every reject lists `C1`, `error` non-empty | return the last attempt when the cap is hit |
| -  | C4, C6, C7 | one pass + one fail fixture each | no control: single integer comparisons, low risk |
| -  | structure | 50 seeds: one `L`, entries next to SEA, every entry reaches `L`, island sizes 4-12, pockets dead ends of 2-6 | (covered by T8's machinery; no extra control) |
| -  | R disc | hex R = 3 around an interior cell: count pinned (computed via `LightRules`, expected 37) | none: a pin of the game's own range test |

Fixtures are text rows through `GenMap.from_rows(kind, rows)`, so they read like map.json.
8 controls (T1-T8), all in the new test files, one throwaway worktree build. No timing in unit
tests (the tool measures it).

## 9. Open questions for the owner

**Q1. P1 map size and entry count.** Decided (S25): "p1_large 32x18", option (c) is the default preset.
- (a) 24 x 16 hex, 1-3 entries **(recommended)**: today's 24-wide board, routes of 20-30 cells fit
  C4; 3 entries keep the 20-seed screen readable. Risk: 4-entry maps untested until later.
- (b) 24 x 14 (today's exact size), 1-3 entries. Benefit: same screen as now. Risk: less room for
  loops and pockets, higher reject rate.
- (c) 32 x 18, 1-4 entries. Benefit: the full §2 range. Risk: routes near Lmax 40; LT-64 view
  cost; slower maps.

**Q2. C5 at a cut chokepoint (no detour exists).**

**Decided (owner):** "Хотя бы одно узкое место на маршрут": every route needs at least one
chokepoint where a one-cell barricade either cuts the route or forces a detour `>= D`; all other
chokepoints are unconstrained (no per-chokepoint `>= D` requirement). This replaces the options
below, which are kept for the record.

- (a) Cut passes, but every route needs at least one chokepoint with a detour `>= D`
  **(recommended)**: forced breaches are fine (§3), and loops still give the barricade a real
  choice somewhere. Risk: one more rule to tune.
- (b) Cut always passes. Benefit: simplest, lowest reject rate. Risk: maps with no detour at
  all; barricades become pure stall walls.
- (c) Every chokepoint needs a detour. Benefit: always a choice. Risk: dense loops, maps look
  like nets, high reject rate.

**Q3. Where the thresholds live in P1.**
- (a) `MapGenParams` code defaults + an optional JSON override for the tool; move to `data/` with
  ConfigLoader when the generator enters the game **(recommended)**. Benefit: no loader or
  golden-data churn during a throwaway step. Risk: §8 says "in data"; it is deferred, not
  dropped.
- (b) `data/mapgen.json` through ConfigLoader now. Benefit: lab-ready immediately. Risk: config
  schema and tests for knobs that may still change shape in P2/P3.

## 10. Deviations from this note (S8)

Found while coding the rules (LT-130/S8); the code is the reference.

1. Chokepoint candidates are CHANNEL route cells only: ENTRY and L take no barricade.
2. Route length = steps (route cells - 1). C3 share = cells common to every route * 100 / the
   shortest route's cell count. C1 spacing is counted greedily from the entry end.
3. The trunk L -> F is carved once and shared; corridors run entry -> waypoint -> F.
4. Added after step 9: ISLAND cells in the C7 zone (top `c7_hud_rows` rows, within `c7_l_cover`
   steps of L) become ROCK before the small-island pass; otherwise C7 rejects almost every map.
   C7 still bites on fixtures.
5. A drawn entry next to an already placed entry is not placed (-> S2).
6. `chokepoints(m, route, discs, expo, p)` returns route positions as `PackedInt64Array`
   (`PackedInt32Array` is not on the sim engine allowlist); discs are precomputed once per map
   (`disc_table`), `exposures` derives every exposure from them.
7. Island split: `max(2, ceil(size / island_seed_div))` seeds, repeated until no component is
   larger than `island_max`; the boundary is the cells next to a lower-numbered region.
8. `GenMap.from_rows(kind, rows)` returns null on an unknown kind, ragged rows, a character
   outside the legend or not exactly one L. `MapGenParams.from_dict(d, base)` returns
   `{params, errors}` (unknown key, wrong type, range errors).
9. §8 T1 / T8: with the defaults at the time of S8 `generate` hit the cap, so pin digests of
   `attempt` (or of accepted maps once tuned), and T8 asserts every reject *contains* `C1`.
10. C6 cannot fail while C4 holds: the route includes its entry, its highest-cost cell, so C6 ==
    `length >= floor_cells + c6_extra` (9) <= `c4_lmin` (20). Kept as written for when the
    floor or flood rules change (S15 F3).
11. (S20) "within R" is tested on integer cell deltas (`ChokepointMetric.within`: hex
    `(2dq + dr)^2 + 3dr^2 <= 4R^2`, square `dx^2 + dy^2 <= R^2`), not on float32 centres, which
    dropped ring-3 corners on some rows. `LightRules.in_cast_radius` in the game has the same
    row dependence on hex; not changed here.
12. (S20) A pocket's first cell may touch at most one of the two cells flanking its mouth;
    touching both made it a through cell and a barricade bypass.
13. (S20) `MapGenParams.check()` also bounds `attempt_cap <= MapRng.ATTEMPT_STRIDE` (1000; the
    seed formula is unchanged), `sea_max <= width - 6`, `c4_lmin <= c4_lmax`,
    `c7_hud_rows < height` and the counts in `NON_NEGATIVE`; `generate` refuses params failing
    `check()` (map null, attempts 0, error "params: ...").
14. (S25) Owner decision "sim/mapgen/ до мерджа LT-130 (Recommended)": the generator lives in its
    own block `sim/mapgen/`, not `sim/rules/`; the six files of §1 moved there with `git mv`
    (`class_name` unchanged). The seam is the map dict read by `MapDef.parse`
    (`GenMap.to_map_dict()`). `res://sim/mapgen/map_rng.gd` is in `SIM_RNG_HOMES`; the guards that
    scan `res://sim` cover the new folder as it is.
15. (S25) Owner decision "p1_large 32x18": `p1_large` is the default preset
    (`MapGenParams.default_preset()`; `MapGenerator.generate` without params, `mapgen_report.gd`,
    `scripts/mapgen-report.sh`, `tools/proto/map_viewer.gd`). The field initialisers stay the
    p1_small values, and `from_dict` without a base starts from them (pinned tests).
16. (S25) p1_large p95 is 373 ms per accepted map (rerun under load: 750 ms), above the 200 ms
    budget. Owner decision "Решить в задаче про острова (Recommended)": accepted deviation,
    deferred to LT-141 (segment-level chokepoints).

## 11. Measurements (S24)

Lab rules: only `MapGenParams` defaults and step parameters, never metric definitions; x2 and /2
first, then bisect. Probes ran through `--params` JSON (no code edits); seeds 1..N, sample sizes
below. Columns: reject = attempt-level reject %, 1st = first-attempt pass %, att = mean attempts,
ms mean/p95/max per accepted map, chk = chokepoints per route (median).

Baseline (small, 40 seeds, loaded): reject 31 %, 1st 65 %, chk 22 of ~23 route cells, every
reject is C3 (+ S2).

| knob (small, 200 seeds unless noted) | x2 / up | /2 / down | note |
|---|---|---|---|
| `choke_e` 4 | 8: reject 96 %, 22 attempts, 8 chk, 7 cap failures (40 seeds) | 2: reject 31 %, unchanged | bisect 6: 28.8 %, 5: 27.5 %, 7: 58 % |
| `choke_k` 3 | 6: reject 32 %, chk 20 | 1: unchanged | no use alone |
| `tower_range` 3.0 | 6.0: unchanged, slower (more cells in range) | 1.5: hits the cap (40 seeds); 2.0: reject 34 %, chk 15 | breaks C1/C5 once combined with E>=5 |
| `funnel_steps` 9 | 18: reject 64 % (S1, C3) | 4: 37.5 % | bisect 7: 23.4 %, 8: 26.7 % |
| `waypoint_jitter` 3 | 6: 26.7 % | 1: 28.8 % | noise-level |
| `wide_pct` 30 | 60: 25.4 % | 15: 27.0 % | noise-level alone; with E6 + F7: 60 gives 39 % |
| loops 1-2 | 2-4: 28.3 % (on F7+E6) | 0-1: 25.7 % | kept 1-2 (0-1 slower: 118 vs 78 ms at 1000 seeds) |

Combinations (small, 200 seeds): F7+E6 29.1 %, F7+E5 23.7 %, F7+E6+K6 51.9 %, F7+R2 38.3 %,
F7+E6+R2 and F6+E6+R2 hit the cap (100 %). Large (1000 seeds, F7): E3 21.5 %, E5 21.9 %, E6 26.0 %,
E7 59.1 %, E8 99.4 % (750 cap failures), E5+K6 27.3 %, E5+R2 85.2 %.

Chosen defaults: `funnel_steps` 9 -> 7, `choke_e` 4 -> 5 (both presets; large uses the same).

Final, 1000 seeds each, no cap failure, reject = attempt-level:

| preset | reject | 1st pass | att | ms mean / p95 / max | chk/route | reasons |
|---|---|---|---|---|---|---|
| p1_small | 23.0 % (< 30 ok) | 76.5 % | 1.30 | 77.8 / 139.6 / 8629 | 21 | S2 27, C3 272 |
| p1_large | 21.9 % (< 30 ok) | 79.1 % | 1.28 | 149.4 / 373.2 / 1342 | 30 | S2 56, C3 225, C5 1 |

Timing record: these are the lowest-load runs (load1 9.7 -> 34 -> 5.8; `user` 62 s small,
~130 s large for 1000 seeds, i.e. about 62 / 130 ms of CPU per map). A repeat of the same
defaults ran at load 25-46 (screenshots and another suite alongside): small 182 / 447 ms, large
311 / 750 ms, so p95 is load-dominated; `user` shows the real cost.

Findings against the bar:
- Reject < 30 % met on both presets.
- Small: p95 140 ms in the quiet run, mean 78 ms (small max 8.6 s is one seed with many retries).
  Re-time at load < 10 in the verify slice.
- Large: p95 373 ms and mean 149 ms; bar (< 200 ms) NOT met by tuning. Cause: ~30 chokepoints per
  route and C5 runs one route field per chokepoint. K/E/R cannot lower the count without failing
  C1/C5/C3 (E7: 59 % reject, E8: cap failures, R2: 85 %). The count is high because the metric
  counts almost every CHANNEL cell on a 30-step route as a chokepoint; a faster C5 (cache fields
  per route, early exit) or a looser definition is an owner decision, not a tuning one.
- The viewer's `--screenshot` waited 4 frames and saved a blank image for the small preset; now 20.
- Screenshots: `docs/design/LT-130/p1-small.png`, `p1-large.png` (seeds 1-20, defaults above).

### Verify re-time (S26)

Tip cde8334, `scripts/mapgen-report.sh --preset <p> --seeds 1000`, run alone after the suite on a
quiet machine (load1 2.4 at the start, 5.2 at the end of the large run).

| preset | reject | 1st pass | cap failures | ms mean / p95 / max | real / user / sys s | reasons |
|---|---|---|---|---|---|---|
| p1_small | 23.0 % (299 / 1299) | 76.5 % | 0 | 65.7 / 136.5 / 448.7 (seed 596) | 66.97 / 65.64 / 0.42 | S2 27, C3 272 |
| p1_large | 21.9 % (281 / 1281) | 79.1 % | 0 | 114.0 / 241.6 / 745.7 (seed 421) | 115.77 / 113.52 / 0.62 | S2 56, C3 225, C5 1 |

Bars: reject < 30 % met on both presets; p1_small p95 136.5 ms < 200 ms met. p1_large p95 241.6 ms
is over 200 ms: the accepted deviation of §10 item 16 (LT-141), not a regression. Reject counts are
identical to S24 (same code and seeds); `user` is close to `real`, so the times are CPU, not waiting.
