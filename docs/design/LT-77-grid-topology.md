# LT-77: GridTopology (cell geometry behind one interface)

Status: design, for owner review. Branch `feat/LT-77-grid-topology` from `release-0.5.0` (d9d744f).
Source decisions: LT-65 note §7 Q4, "Полный интерфейс GridTopology" (centre, neighbours,
distance, cell polygon) and "Отдельный блок до B4, с дизайном (Recommended)". BoardView
(LT-35, LT-65 §3.3) is built on this next. LT-64 (hex vs Voronoi, angled view) stays undecided;
this note only makes sure either can plug in.

## 0. What exists today (release-0.5.0)

- `SimGrid.centre(cell)` (`sim/rules/sim_grid.gd`, LT-76) is the one centre rule:
  `Vector2(cell.x + 0.5, cell.y + 0.5)`. G3 pins it for `sim/` and `tools/`.
- `MapDef` (`sim/defs/map_def.gd`) holds `width`, `height`, `_kinds` (row-major
  `PackedByteArray`), `NEIGHBOURS` (:12, RIGHT, DOWN, LEFT, UP), `in_bounds` (:125),
  `kind_at` (:130), `is_buildable` (:137), the path walk `_derive_path` (:71) and
  `_path_neighbours` (:117).
- `SimRoute.from_cells` (`sim/core/sim_route.gd` :12) sums rounded euclidean step lengths
  between consecutive cells; `position_at` (:33) lerps between `_centre` points (:49).
- All range tests are euclidean in **cell units** between continuous points: `enemies_near`
  (simulation.gd :966), `_horror_drain` (:1113), `LightRules.in_cast_radius` / `covers`,
  `TowerRules.in_dead_zone`, `_lit_by` (:1517), `_line_hits` (:2026). They use a cell only
  to get its centre.
- Hand-written grid logic outside sim: board.gd `cell_at` floori (:232), `in_bounds` (:224,
  :555, :674), phantom walk with its own 4 dirs and a `width x height` loop (:505-530), map
  layer loop (:1212); lighting.gd `+ Vector2(0.5, 0.5)` (:85, :141, :176, :209) and the sea
  fog loop (:296); board.gd `+ Vector2(0.5, 0.5)` (:278, :562); bot_runs.gd `_best_cell`
  loop and `Vector2(c - p).length()` (:479-486); golden_runs.gd buildable-cell loop (:204).
- Backlog intent: LT-18 owner direction (2026-10-31) is "sim on a hex grid, rendered as
  jittered Voronoi polygons", islands, a telegraphed per-wave path chosen by path weight,
  flood spread by weight, barricades. LT-64 asks for an angled view and the hex cost.

## 1. The contract

One abstract class `GridTopology` (`sim/rules/grid_topology.gd`, `@abstract`, RefCounted, pure,
immutable after construction) and one implementation `SquareGrid` (`sim/rules/square_grid.gd`).

**Frame.** "Cell units" stay the world frame of the sim: the frame of `SimRoute.position_at`,
`SimTower.centre()`, every `range_cells`, `UNITS_PER_CELL`. The unit is fixed as **the distance
between the centres of two neighbouring cells** (square: the edge; hex: the flat-to-flat width).
So `range`, `speed` and `reach` keep their meaning across topologies and need no data change.

| Method | Returns | Square | Notes |
|---|---|---|---|
| `centre(cell: Vector2i)` | `Vector2` | `(x + 0.5, y + 0.5)` | the one centre rule (G3 home) |
| `neighbours(cell)` | `Array[Vector2i]` | RIGHT, DOWN, LEFT, UP | fixed order, in-bounds only |
| `distance(a, b)` | `float` | `sqrt(dx² + dy²)` of the centres | euclid between centres, 64-bit scalars |
| `steps(a, b)` | `int` | `abs(dx) + abs(dy)` | graph hops on an empty board; no caller today (Q2) |
| `polygon(cell)` | `PackedVector2Array` | 4 corners, (x,y) (x+1,y) (x+1,y+1) (x,y+1) | cell units; screen-clockwise |
| `cell_at(p: Vector2)` | `Vector2i` | `(floori(p.x), floori(p.y))` | may be outside; inverse of polygon |
| `contains(cell)` | `bool` | `0 <= x < w`, `0 <= y < h` | replaces `MapDef.in_bounds` |
| `cells()` | `Array[Vector2i]` | row-major, y then x | cached; order is a contract (below) |
| `index(cell)` / `cell_count()` | `int` | `y * w + x` / `w * h` | storage slot for per-cell arrays |
| `bounds()` | `Rect2` | `(0, 0, w, h)` | world rect in cell units |
| `kind()` | `String` | `"square"` | for the config check and error text |

**Cell id: keep `Vector2i`.** Square uses (x, y); hex uses axial (q, r), which is also a pair of
ints; Voronoi-as-look (LT-18 direction) keeps the hex id. Only a pure Voronoi graph would want an
int id, and it can encode it as `Vector2i(i, 0)`. Changing the id type would touch
`state.tower_at`, every event payload with `"cell"`, `command_log`, golden digests and ~40 UI
and test sites for no gain now (Q1).

**Two distances, by caller.**
- Euclid between continuous points (enemy at `position_at`, tower centre, lighthouse centre):
  range, cast, horror, dead zone, beam, line hits. These are **not** topology methods; they take
  `centre()` points and stay `dx*dx + dy*dy <= r*r` in the world frame.
- `distance(a, b)` between two cells' centres: route step lengths, the bot's placement score.
- `steps(a, b)`: graph hops for future generators, flood spread and chokepoint metrics (LT-18).
  The path itself is found by walking `neighbours`, never by `steps`.

**Determinism (golden replay byte-identical).**
- No trig anywhere in `sim/` (true today, not guarded; G11 below). Hex constants come from
  `sqrt(3.0)` computed once in the constructor (IEEE sqrt is exact-rounded, so deterministic).
- `centre` keeps today's exact expression, `Vector2(cell.x + 0.5, cell.y + 0.5)`. Half-integers
  are exact in float32, so centre differences equal today's int differences bit for bit.
- `distance` computes `float(b.x) - a.x` style 64-bit scalars like `in_cast_radius`, never
  `Vector2.length()` (float32 path).
- `cells()` order is row-major and pinned: the bot's tie-break ("row-major kept",
  bot_runs.gd :491, :499) and the golden `frame_run` PLAN (buildable-cell index) depend on it.
- `neighbours` order is pinned (today's `NEIGHBOURS`). The path walk only uses it as a set,
  but presentation randomness indexes into it.
- No RNG, no state, no mutation after construction; one instance per `MapDef`.

## 2. Who uses it (each current site -> method)

| Site | Today | Becomes |
|---|---|---|
| sim_grid.gd `SimGrid.centre` | static `+0.5` | `SquareGrid.centre`; file deleted |
| map_def.gd :12 `NEIGHBOURS`, :117 `_path_neighbours` | own 4 offsets | `grid.neighbours(cell)` filtered by `kind_at` |
| map_def.gd :125 `in_bounds`, :130 `kind_at` | `y * width + x` | `grid.contains`, `grid.index`; `in_bounds` removed |
| map_def.gd :22 `parse` (`_kinds.resize`), :82/:107 loops | `w * h`, `for y/for x` | `grid.cell_count()`, `grid.cells()` |
| sim_route.gd :12 `from_cells`, :26 `straight`, :49 `_centre` | int deltas, `SimGrid` | `from_cells(grid, cells)`: points = `grid.centre`, step = `roundi(grid.distance(a, b) * U)` |
| sim_tower.gd :50 `centre()` | `SimGrid.centre(cell)` | returns `pos`, set once in `build_tower` from `grid.centre(cell)` |
| simulation.gd :84, :222 route setup | `SimRoute.from_cells/straight` | pass `config.map.grid` |
| simulation.gd :961 `enemies_in_range` | `SimGrid.centre` | `state.map.grid.centre` |
| simulation.gd :1518 `_lit_by` | `SimGrid.centre(lighthouse)` | `config.map.grid.centre` |
| light_rules.gd :18 `covers(cell, r, p)` | `SimGrid.centre` | `covers(grid, cell, r, p)` |
| bot_runs.gd :479-486 `_best_cell` | loop + `Vector2(c - p).length()` | `grid.cells()` + `grid.distance(c, p)` |
| bot_runs.gd :524, :533 | `SimGrid.centre` | `_cfg.map.grid.centre` |
| board.gd :224, :555, :674 | `map.in_bounds` | `map.grid.contains` |
| board.gd :233 `cell_at(local)` | `floori(local / CELL)` | `grid.cell_at(local / CELL)` (`/ CELL` leaves in B4) |
| board.gd :278, :562 | `+ Vector2(0.5, 0.5)` | `grid.centre(cell)` |
| board.gd :504-530 `_new_phantom` | own dirs, w x h loop | `grid.cells()`, `grid.neighbours(cur)` (FX rng only) |
| board.gd :1212 map layer | w x h loop | `grid.cells()`; tiles stay `draw_rect` until B4 (Q4) |
| lighting.gd :85, :141, :209 | `+ Vector2(0.5, 0.5)` | `grid.centre` |
| lighting.gd :176 `flare_cover_cells` | centre + 4 hand corners | `grid.centre`, corners of `grid.bounds()` |
| lighting.gd :296 sea fog | w x h loop | `grid.cells()` |
| hud.gd :178, :291, side_panel.gd :64 | `map.width * CELL` | unchanged here; B4 (BoardView `world_rect` from `grid.bounds()`) |
| golden_runs.gd :204-208 | w x h loop | `grid.cells()` (same order, same PLAN indices) |
| tests: light_rules_test :9-12, sim_rule_queries_test :388, scene_game_test :160, light_shadow_render_test :32 | `SimGrid`, `in_bounds`, bare `SimTower.new()` | `SquareGrid`, `contains`, set `t.pos` |

`MapDef.width/height` stay as the parsed text dimensions (input to `SquareGrid`); outside `MapDef`
they are read only by hud/side_panel, which B4 moves to `bounds()`.

## 3. Hex and Voronoi (sketch only; LT-64/LT-18 decide)

**Hex (pointy-top, axial (q, r) in `Vector2i`).**
- `neighbours`: six fixed offsets (+1,0) (+1,-1) (0,-1) (-1,0) (-1,+1) (0,+1).
- `centre`: `(q + r * 0.5 + o.x, r * H + o.y)` with `H = sqrt(3) / 2`; neighbour spacing is 1.
- `polygon`: six corners at `centre ± (0, 1/sqrt(3))`, `± (0.5, 1/(2 sqrt(3)))`: constants, no trig.
- `cell_at`: axial fractional coords then cube rounding (integer ties broken by a fixed rule).
- `steps`: `(|dq| + |dr| + |dq + dr|) / 2`; `distance`: euclid of centres.
- `cells`/`index`: "odd-r" offset rows, so `data/map.json`'s `rows` text still works: row y,
  column x maps to `q = x - (y - (y & 1)) / 2`. `bounds`: `(0, 0, w + 0.5, (h - 1) * H + 2/sqrt(3))`.

**Voronoi as look over hex** (the LT-18 direction): `polygon(cell)` returns the hex corners moved
by a seeded jitter shared between neighbours (one jitter per shared vertex, so tiles still meet).
Logic, ids, centres and neighbours stay hex. This is a `JitteredHex` subclass or a presentation
decorator; nothing in the sim calls `polygon`.

**Pure Voronoi graph** (only if LT-64 rejects hex logic): ids `Vector2i(i, 0)`; sites, Delaunay
adjacency and polygons generated offline by the map tool and stored in the map data (no
Voronoi math in the sim); `cell_at` = nearest site (bucketed); `steps` = BFS. Range in "cells"
becomes approximate, since sites are not evenly spaced.

**What stays square-specific in the sim today, and the cost to change later.**

| Item | Where | Cost when hex lands |
|---|---|---|
| Map text format (`rows` chars, "column %d" errors) | map_def.gd parse/_derive_path | Low: offset rows; error text per topology |
| One fixed path, walked once at parse | map_def.gd, `_ground_route` | Medium: LT-18 per-wave routes; `e.route` per enemy already exists |
| Route step length from centre distance | sim_route.gd | None after LT-77 (hex steps are all 1.0) |
| Range in cell units, euclid | simulation.gd, rules | None in code; balance: a hex cell is 0.866 of a square's area, so the same radius covers ~15% more cells (retune in the lab) |
| Beam directions (8 dirs, `sqrt(0.5)`) | simulation.gd :1495-1503 | None: world frame, not grid |
| `tower_at` keyed by cell | sim_state.gd | None with `Vector2i` ids |
| Bot placement score | bot_runs.gd | None after LT-77 |
| Tile drawing, picking, overlays | board.gd, lighting.gd | B4 BoardView + `polygon`; angled view is LT-64 |

## 4. Where it lives and who owns it

- `sim/rules/grid_topology.gd` (abstract) and `sim/rules/square_grid.gd`: rules, pure static
  data, no Node/Color/signals (LT-33). Presentation and the bot read it read-only (LT-33 allows
  reading sim types; G1 does not cover it).
- `MapDef` owns it: `var grid: GridTopology`, created in `parse` right after `width`/`height` are
  read, before the rows loop. Everyone reaches it as `config.map.grid` / `state.map.grid`.
- `data/map.json`: an optional `"grid"` key, default `"square"`, the only accepted value now;
  any other value is a config error (`unknown grid "hex"`). The frozen golden copy
  (`tests/fixtures/golden_data/map.json`) is not edited. See Q3.

## 5. Guard (extends G3 from LT-76; in `tests/architecture_guard_test.gd`)

| # | Contract | Check (code lines, comments/strings blanked, statements joined) | Scope |
|---|---|---|---|
| G3 (moved) | One cell centre | `.x + 0.5`, `0.5 + .y`, `+ Vector2(0.5, 0.5)` only in `sim/rules/square_grid.gd` (2 hits) | `sim/`, `tools/`, and now `scenes/`, `ui/` |
| G10 | One topology | outside `sim/rules/*grid*.gd`: no `Vector2i\.(LEFT\|RIGHT\|UP\|DOWN)`; no `for \w+ in [\w.]*\.(width\|height)\b`; no `\.in_bounds\(`; no `NEIGHBOURS`; no `Vector2\(\s*\w+\s*-\s*\w+\s*\)\.length\(\)` | `sim/`, `tools/`, `scenes/`, `ui/` |
| G11 | Trig-free sim | no `\b(sin\|cos\|tan\|atan2?\|asin\|acos\|deg_to_rad\|rotated\|angle)\(` under `sim/` | `sim/` |

Each has probe strings (every form caught) and a scan-count floor, like G1/G3. `tests/` stays
exempt (fixtures build maps by hand). G2 (`CELL` only in BoardView) remains B4's.
`floori(` with `/ CELL` (pixel picking) also belongs to G2 in B4.

## 6. Edit map for the square implementation (in order)

1. **New** `sim/rules/grid_topology.gd`: `@abstract class_name GridTopology`, the methods of §1
   as `@abstract func`, doc comments stating the frame, the order contracts and determinism.
2. **New** `sim/rules/square_grid.gd`: `SquareGrid extends GridTopology`, `_init(w, h)`, cached
   `_cells`; `centre` with the exact `SimGrid` expression; `distance` in 64-bit scalars.
3. `sim/defs/map_def.gd`: `FIELDS` (:9) add `"grid"` (optional); `parse` (:22-68) read `grid`
   (`opt_string`, default `"square"`, reject others), build `m.grid = SquareGrid.new(w, h)`
   after :28, `_kinds.resize(m.grid.cell_count())` (:34); delete `NEIGHBOURS` (:12);
   `_derive_path` (:71-114) loops -> `grid.cells()`; `_path_neighbours` (:117-122) ->
   `grid.neighbours`; delete `in_bounds` (:125-126); `kind_at` (:130-133) -> `grid.contains`,
   `grid.index`.
4. `sim/core/sim_route.gd`: `from_cells(grid, cells)` (:12-23) stores `_points` (centres) and
   steps `roundi(grid.distance(a, b) * UNITS_PER_CELL)`; `straight(grid, a, b)` (:26-28);
   `position_at` (:33-46) lerps `_points`; delete `_centre` (:49-50).
5. `sim/core/sim_tower.gd`: `var pos: Vector2` (centre, set once); `centre()` (:50-51) returns it.
6. `sim/core/simulation.gd`: :84 and :222 pass `config.map.grid` / `state.map.grid`;
   `build_tower` (:274-292) sets `t.pos = state.map.grid.centre(cell)`; :961 and :1518 ->
   `grid.centre`; `_in_cast` (:1406-1413) -> `LightRules.covers(config.map.grid, ...)`.
7. `sim/rules/light_rules.gd` `covers` (:18-19): add the `grid` parameter.
8. Delete `sim/rules/sim_grid.gd` (+ `.uid`).
9. `tools/bot_runs.gd`: `_best_cell` (:473-499), `_cast_term` (:510-528), `_in_shadow_radius`
   (:532-533).
10. `scenes/board.gd`: :224, :232-242 (`cell_at` via `grid.cell_at`; `origin_of` unchanged until
    B4), :278, :504-530, :555, :562, :674-677, :1212-1213. `scenes/lighting.gd`: :85, :141,
    :175-181, :209, :296-299.
11. Tests: `tests/golden_runs.gd` :204-208; `light_rules_test.gd` :9-12 (moves to the new
    suite); `sim_rule_queries_test.gd` :388; `scene_game_test.gd` :160;
    `light_shadow_render_test.gd` :32; `architecture_guard_test.gd` G3 (:68-97) + G10 + G11.

**Behaviours to pin (new `tests/square_grid_test.gd` + `map_def_test.gd`):**
1. `centre` equals `(x + 0.5, y + 0.5)` incl. negative cells (moved from light_rules_test).
2. `neighbours` of an interior cell: the 4 in pinned order; of a corner: 2; never out of bounds.
3. `distance` of (0,0)-(3,4) is 5.0; symmetric; 0 on itself.
4. `steps` of (0,0)-(3,4) is 7; symmetric.
5. `polygon` has 4 corners in pinned order; `cell_at(centre(c)) == c` and every corner's
   inward nudge maps back to `c`; `cell_at` of a point left/above the board is outside.
6. `contains` matches `0 <= x < w, 0 <= y < h`; `cells()` is row-major, size `w*h`, and
   `index(cells()[i]) == i`.
7. `bounds()` is `(0, 0, w, h)`.
8. `map.json` without `"grid"` loads as square; `"grid": "square"` loads; `"grid": "hex"`
   errors `unknown grid`; unknown-key check still rejects other keys.
9. A route's length and `position_at` samples equal the pre-change values (pin numbers for the
   real path and the flyer S->L route, computed before the change).
10. `SimTower.centre()` after `build_tower` equals `grid.centre(cell)`.

**Proof plan.**
- Golden replay (`tests/golden_replay_test.gd`): digests byte-identical, **no re-pin**. A re-pin
  in this task is a finding.
- Bot RUN lines identical: `tools/bot_runs.gd` all strategies x seeds on live `data/`, diff
  against a run from `release-0.5.0`.
- Suites: square_grid_test, map_def_test, sim_movement_test, light_rules_test,
  sim_rule_queries_test, architecture_guard_test, sim_boundary_test, scene_game_test,
  lighting_test, map_layer_test, light_shadow_render_test, hallucination_test; then the full
  suite once in verify.
- Controls (one per behaviour, revert code, never tests): (a) `centre` returns `x + 0.4` ->
  golden and square_grid_test fail; (b) `cells()` column-major -> golden frame_run and
  square_grid_test fail; (c) `neighbours` adds a diagonal -> map_def_test path walk fails
  (forks); (d) `from_cells` steps by `steps()` instead of `distance()` -> golden fails on the
  flyer route (S->L is diagonal); (e) MapDef accepts `"hex"` -> map_def_test fails; (f) G10/G11:
  reintroduce `Vector2i.LEFT` in board.gd and a `sin(` in sim -> guard fails.

## 7. Owner questions

1. **Cell id type.**
   - (a) Keep `Vector2i` for every topology **(recommended)**. Benefit: no churn in state,
     events, logs, digests; hex axial fits. Risk: a pure Voronoi graph encodes `Vector2i(i, 0)`,
     which is a little odd.
   - (b) An opaque int id now. Benefit: fits any graph. Risk: rewrites `tower_at`, events,
     command log, golden digests and ~40 call sites for a topology not chosen.
2. **`steps` (graph distance) in the interface now.**
   - (a) Yes, implemented and tested, no caller yet **(recommended)**. Benefit: the contract
     already says "path steps vs euclid", which is exactly where hex differs. Risk: ~10 lines
     with no production caller until LT-18.
   - (b) Only euclid `distance` now. Benefit: no unused code. Risk: the first generator/flood
     code adds it ad hoc, maybe outside the topology.
3. **How MapDef picks the topology.**
   - (a) Optional `"grid"` key, default `"square"`, other values rejected **(recommended)**.
     Benefit: the format is ready for hex; golden copy untouched. Risk: a key with one legal
     value for now.
   - (b) Implicit square, no key until hex lands. Benefit: zero data change. Risk: the hex task
     then changes the format and the loader at once.
4. **Draw tiles from `polygon()` in LT-77 or in B4.**
   - (a) In B4 (BoardView), LT-77 only moves logic reads **(recommended)**. Benefit: LT-77 stays
     pixel-identical, easy to prove; B4 owns all drawing. Risk: `polygon` has only tests as
     callers until B4.
   - (b) In LT-77 (map layer, sea fog, selection outline). Benefit: the polygon is proven by
     real use at once. Risk: rendering changes (polyline vs rect edges) mixed into a logic
     refactor, and B4 touches the same lines again.
5. **Tower centre: cached `pos` or computed.**
   - (a) `SimTower.pos` set once in `build_tower` **(recommended)**. Benefit: `centre()` stays
     cheap and topology-free; towers never move. Risk: a tower built outside `build_tower`
     (one test today) must set it.
   - (b) `SimTower` keeps a grid reference. Benefit: no cached field. Risk: every tower holds
     the map's topology; tests building towers need a grid.
