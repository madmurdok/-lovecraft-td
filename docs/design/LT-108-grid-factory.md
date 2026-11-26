# LT-108: grid factory and polygon tile drawing (LT-96 S13)

Spec: LT-96 §4 S13; owner decision D9 "Сначала гексы, потом пути (Recommended)". Prior work:
LT-77 (GridTopology, `"grid"` map key, Q4 "tiles from `polygon()` in B4"), LT-35 (BoardView,
`cell_polygon`, `cell_rect` as its bbox), LT-90 (primitive warm-up in FxLayer). Acceptance: the
square grid looks unchanged (at most a 1 px line shift, documented); adding hex is one sim class
+ map data + one factory line. Owner decisions in §10 (cell_rect deleted, a real `HexGrid`
shipped unregistered). Later: LT-109 (route source), LT-110 (view transform, layers in
cell units) build on this; nothing here decides them.

**Status (LT-129, release 0.15.0).** `HexGrid` is now registered in `MAKERS`: `"grid": "hex"`
builds a `HexGrid`. Statements below that hex "stays a config error" or ships unregistered
describe LT-108's own state and are kept as the record.

**LT-91 reconciliation.** LT-91 is already cancelled, folded into LT-108 by the owner ("Слить в
LT-108, LT-91 отменить (Recommended)"). LT-108 absorbs all of it: tiles, sea fog, selection,
the leak frame, the guard, the square tolerance and the hex check (now a real HexGrid, §2 F5). Nothing stays in LT-91.
Its line numbers (board.gd:556, 605, 692, 1239-1244, 874-876) predate the LT-84 layer split;
the current sites are in §3.

## 1. Today

- `MapDef.parse` (`sim/defs/map_def.gd:28-31`) reads `"grid"` (default `"square"`), errors on
  any other value, then hard-codes `m.grid = SquareGrid.new(m.width, m.height)`.
- `BoardView.cell_polygon` (`scenes/board/board_view.gd:66-71`) maps `grid.polygon` to world
  pixels; `cell_rect` (`:74-81`) is its bbox. Every board layer draws tiles with
  `draw_rect(view.cell_rect(c)...)`, and the tower plate lays out its letter, pips and marks from
  `r.position` of that rect. On hex, all of these become overlapping rectangles.
- The leak frame (`fx_layer.gd:338-341`) is a hand-built square: `from - Vector2(0.5, 0.5)`,
  side `cells_to_px(1.0)`. G3 only bans the `+` form, so the guard does not see it.

## 2. Decisions

**F1. Factory: a new `sim/rules/grid_factory.gd`.**
```gdscript
class_name GridFactory
const MAKERS := {"square": SquareGrid}   # hex later: "hex": HexGrid
static func kinds() -> PackedStringArray       # MAKERS keys, sorted
static func make(kind: String, width: int, height: int) -> GridTopology  # null if unknown
```
- Map data names the topology through the existing optional `"grid"` key (LT-77 Q3). No new
  key and no data change. The frozen golden map is untouched.
- `MapDef.parse` does `m.grid = GridFactory.make(grid_kind, w, h)`. On null it reports
  `unknown grid "x" (expected "square")`, with the list built from `kinds()` (today's text,
  byte for byte), and falls back to `"square"` so that later parsing still runs.
- Every topology takes `(width, height)`. Hex reads the same `rows` text as odd-r offset rows
  (LT-77 §3). If a later look such as jittered hex needs more input (a seed), LT-64 adds an
  optional parameter then (Q1).
- G10 exempts `sim/rules/*grid*.gd`, so the factory sits in the topology home. Its
  `home_scanned == 2` assert becomes `== 4` (grid_topology, grid_factory, square_grid,
  hex_grid). Registering hex in `MAKERS` later needs no guard edit.

**F2. Polygon drawing helpers in BoardView** (geometry stays in the view; layers only draw).
- `cell_polygon(cell, inset_px := 0.0)`: each vertex `p' = c + (p - c) * (a - inset) / a`, where
  `c` is the cell centre in world pixels and `a = cells_to_px(0.5)` is the apothem. This holds
  for any tiling with unit neighbour spacing (LT-77 frame), square and hex. It is exact for
  square: `(±20 * 16) / 20 = ±16`, so multiply first and divide second, giving exactly
  `bbox.grow(-inset)`.
- `cell_centre(cell) -> Vector2`: `cell_to_world(grid.centre(cell))`, used for text and mark
  anchors.
- `static fill_cell(ci: CanvasItem, cell, color, inset_px := 0.0)`:
  `ci.draw_colored_polygon(cell_polygon(cell, inset_px), color)`.
- `static outline_cell(ci, cell, color, width_px, inset_px := 0.0)`: a ring of n non-overlapping
  quads `[outer[i], outer[i+1], inner[i+1], inner[i]]`. `outer` is the polygon at
  `inset - w/2` and `inner` at `inset + w/2`. Each quad is one `draw_colored_polygon`, giving a
  centred line with mitred corners, the same band as today's centred `draw_rect` outline (the
  layers already rely on centring, see `entity_layer.gd:136-138`). These helpers take a
  CanvasItem because MapLayer and SeaFog are plain `Node2D` inner classes, not BoardLayers.
  BoardView remains the only place that knows the polygon.
- `cell_rect` is **deleted** (owner, Q4). Its only callers are the six layer sites in §3 and
  `tests/board_view_test.gd:183, 192, 195, 268`, which are rewritten against `cell_polygon`
  (§6 item 3). `picker_overlay_test.gd:73` has its own `_cell_rect` helper, which is not a
  caller and stays. The header comment `board_view.gd:12-13` is updated.

**F3. Text and marks anchor to the centre.** Each offset is today's offset re-expressed from the
centre. All are integers, so the square result is pixel-identical:

| Mark | Today | Becomes |
|---|---|---|
| tower plate fill / frame (w 2) | `r = cell_rect.grow(-6)` | `fill_cell(…, 6)`, `outline_cell(…, 2.0, 6)` |
| state border (w) | `r.grow(w/2 + 1)`, outline | `outline_cell(…, w, 6 - (w/2 + 1))` |
| letter plate 15x19 | `r.position + (4, 4)` | `c + (-10, -10)` |
| glyph (tower and ghost) | `r.position + (8, 20)` | `c + (-6, 6)` (`EntityLayer.GLYPH_OFFSET`, shared with overlay) |
| lit / shadow mark | `r.position + (r.size.x - 6, 6)` | `c + (8, -8)` |
| level pips 4x4 | `r.position + (3 + 6i, r.size.y - 6)` | `c + (-11 + 6i, 8)` |
| branch letter | `r.position + (r.size.x - 9, 11)` | `c + (5, -3)` |
| lighthouse "L" | `lh.position + (9, 24)`, `lh = grow(-4)` | `c + (-7, 8)` |

Whether these marks look right inside a hex plate is LT-64's look question (Q3).

**F5. `HexGrid`, shipped now and not in `MAKERS`** (owner, Q6). New file
`sim/rules/hex_grid.gd`, `class_name HexGrid extends GridTopology`, `_init(w, h)`. It is pure,
immutable and has no trig. `R = 1 / sqrt(3.0)` and `H = sqrt(3.0) / 2` are computed once in the
constructor, and `sqrt` is exact-rounded, so the values are deterministic. Map data cannot
select it (`"grid": "hex"` stays a config error), so golden, balance and play do not change.
Tests and the verify probe build it directly. Registering it later is the one factory line.
- **Id (owner, Q7 "Axial id"):** axial `(q, r)` in `Vector2i`, as in LT-77 §3. Text cell
  (column x, row y) maps to `q = x - (y - (y & 1)) / 2` and `r = y` (odd-r rows, so the `rows`
  text keeps its shape). GDScript `/` on ints truncates toward zero, but `y - (y & 1)` is even
  and ≥ 0, so the division is exact.
- **Orientation: pointy-top.** This is stated, not a new question. Axial ids work with either
  orientation, but only pointy-top keeps the `rows` text's rows as straight horizontal rows of
  hexes. Flat-top would make every text row zig-zag and would need a different map format,
  which is a map-format decision for LT-64/LT-18, not this task. This is also LT-77 §3's sketch.
- **Size:** the LT-77 unit, so neighbour centres are 1 apart and the flat-to-flat width is 1
  (40 px). The apothem is 0.5, so F2's inset formula holds unchanged. The circumradius is `R`
  and the row pitch is `H`. `range`, `speed` and `reach` keep their meaning (LT-77 §1).
- `kind()`: `"hex"`. `centre(c)`: `(c.x + 0.5 * c.y + 0.5, R + c.y * H)`. For axial ids this
  equals the odd-r offset layout: `(r - (r & 1)) / 2 + (r & 1) / 2 = r / 2`.
- `neighbours(c)`: the fixed axial offsets in the order E, NE, NW, W, SW, SE (screen
  counter-clockwise from east): (+1,0) (+1,-1) (0,-1) (-1,0) (-1,+1) (0,+1). No parity is
  involved. Only in-bounds cells are returned.
- `distance`: Euclidean distance between centres, using 64-bit scalars like SquareGrid.
  `steps`: `(|dq| + |dr| + |dq + dr|) / 2`.
- `polygon(c)`: 6 corners, screen-clockwise from the top: `(cx, cy - R)`,
  `(cx + 0.5, cy - R/2)`, `(cx + 0.5, cy + R/2)`, `(cx, cy + R)`, `(cx - 0.5, cy + R/2)`,
  `(cx - 0.5, cy - R/2)`.
- `cell_at(p)`: shift by the (0, 0) centre `(0.5, R)`, then compute fractional axial
  `q = x - y / sqrt3` and `r = y * 2 / sqrt3` (constants from the constructor). Cube rounding
  follows, with the fixed tie rule "re-derive the component with the largest rounding error".
  The result may be outside the board, as in SquareGrid.
- Storage goes through the text cell: `contains(c)` means the text cell is inside `w x h`.
  `cells()` lists axial ids in text row-major order. `index(c)` is `y * w + x` of the text cell,
  and `cell_count` is `w * h`.
- `bounds()`: `Rect2(0, 0, w + (0.5 if h > 1 else 0.0), (h - 1) * H + 2 * R)`.
- G3 (one cell centre) gains a second home: `G3_HOME` becomes a list
  `[square_grid.gd, hex_grid.gd]`. The code slice sets the home-hit count to what the two files
  actually contain (square: 2).

**F6. MapDef reads the text through the topology** (follows from Q7). Two non-abstract methods
go on `GridTopology`, with identity defaults, so SquareGrid does not change:
`cell_of_text(x: int, y: int) -> Vector2i` and `text_of(cell) -> Vector2i` (column, row). HexGrid
overrides both with the odd-r <-> axial maps above and uses them in `contains` and `index`.
MapDef changes in two places:
- The `parse` rows loop (`map_def.gd:40-59`) stores `_kinds` and the S/L cells under
  `grid.cell_of_text(x, y)`. It is moved into `MapDef._read_rows(r, rows)` so a test can run it
  on a hand-set HexGrid (hex cannot come from data, since it is not in `MAKERS`).
- The five `_derive_path` errors (`:81-112`) print `grid.text_of(cell)` for the row and the
  column instead of `cell.y`/`cell.x`. On square the identity keeps every message byte for
  byte.

So a hex map is the same `rows` text plus `"grid": "hex"`, once registered. Square gets the
same cells, `_kinds`, path and error texts, and golden does not change.

**F4. Leak frame from the lighthouse polygon.** `LEAKED` stores `"cell": lighthouse` in the
effect. The draw becomes `outline_cell(self, fx["cell"], COLOR_LEAK, 4.0)`. The primitive moves
from `draw_rect` to `draw_colored_polygon`, which LT-90's `_draw_warmup` already warms, so no
new cold primitive appears.

## 3. Sites (grep `grep -rn "cell_rect(" --include='*.gd' scenes ui tools`, plus
`grep -rn "draw_rect\|cells_to_px(1" scenes ui`, triaged by role; `cell_rect` is deleted
after these move)

| # | Site | Role | Becomes |
|---|---|---|---|
| 1 | `scenes/board.gd:217-219` MapLayer tile fill + grid line (w 1) | tile | `fill_cell`, then `outline_cell(…, 1.0)`, **same per-cell order** (the next tile's fill covers half of the previous line, as today) |
| 2 | `scenes/board.gd:220-221` spawn mark | tile inset 4 | `fill_cell(…, COLOR_START, 4)` |
| 3 | `scenes/board.gd:222-225` lighthouse mark + "L" | tile inset 4 + text | `fill_cell(…, 4)`, text at `c + (-7, 8)` |
| 4 | `scenes/lighting.gd:304` SeaFog quads | tile | `fill_cell`. The shader reads `VERTEX` (`shaders/sea_fog.gdshader:14`), not UV, so a polygon is safe. |
| 5 | `scenes/board/phantom_layer.gd:31` phantom path | tile inset 2 | `fill_cell(…, 2)` |
| 6 | `scenes/board/entity_layer.gd:131-156` `_draw_tower` | plate + marks | F3 table |
| 7 | `scenes/board/overlay_layer.gd:18` selection outline (w 2) | tile outline | `outline_cell(…, 2.0)` |
| 8 | `scenes/board/overlay_layer.gd:20-22` ghost glyph | text | `c + GLYPH_OFFSET` |
| 9 | `scenes/board/fx_layer.gd:131` / `:338-341` leak frame | hand-built tile | F4 |

Not cell-derived, left as is: HP bars (`entity_layer.gd:263-299`), `board_view.gd:25`
(`world_rect_for`), `ui/sanity_bar.gd`, `ui/side_panel.gd:66`, `scenes/sanity_fx.gd:142`.
Tests: `board_view_test.gd:172-196, 268` are rewritten (§6 item 3). `picker_overlay_test.gd:73`
(its own `_cell_rect`) stays.

## 4. Guard G15 (in `tests/architecture_guard_test.gd`, after G10)

"Tiles from the polygon." Scan `sim/`, `tools/`, `scenes/` and `ui/` (comments and strings
blanked, statements joined, via `_find_joined` like G3/G10) for three forms:
- `\bcell_rect\b` anywhere, with no home. The method is gone, so no definition or call can
  come back (`_cell_rect` in tests does not match: `\b` does not split `_c`);
- `-\s*Vector2\(\s*0\.5\s*,\s*0\.5\s*\)`, the hand-built cell corner (G3 owns the `+` form);
- `\b[A-Z]\w*Grid\.new\(` outside `sim/rules/grid_factory.gd` (topologies are built only by
  the factory; `tests/` stays exempt).

The guard is tested like the others. Probes: `view.cell_rect(c).grow(-2)`,
`func cell_rect(cell)`, `p - Vector2(0.5, 0.5)`, `SquareGrid.new(w, h)` and `HexGrid.new(3, 3)`,
each caught. Clean near-misses: `view.cell_polygon(c)`, `_cell_rect(c)` and `outline_cell(` are
not hits. The factory home has the 1 `SquareGrid.new` hit, and more than 40 files must be
scanned.

## 5. Square pixel equivalence: risk and check

- **Fills** (tiles, fog, phantom, spawn, lighthouse, plate): the same four vertices, drawn
  without antialiasing (`draw_colored_polygon` and `draw_rect` are both non-AA). Expected
  identical at 1200x675. At 1920x1080 (stretch 1.6, origin y 76.8 px) edges land on fractional
  pixels, but the vertices still match, so coverage should match too. A different
  triangulation diagonal does not change the covered union.
- **Outlines** (grid w 1, selection w 2, frame w 2, state border, leak w 4): the ring quads span
  the same band as a centred `draw_rect`. Risk: Godot's own outline geometry (corner overlap,
  half-pixel snapping) may differ. Possible results are a ≤1 px shift of a line, and, at alpha
  < 1 (selection 0.8), corner pixels that today are drawn twice. Accepted and documented (Q5).
- **Text and marks**: integer offsets give the same positions.
- **Cost**: an outline is 4 polygons instead of 1 rect. MapLayer redraws only on `set_map`;
  EntityLayer redraws every frame, adding ~6 calls per tower. If verify's `--frame-stats` p95
  moves by more than noise, one fallback is a single
  `RenderingServer.canvas_item_add_triangle_array` per outline.

**Verify screenshots.** Use a throwaway probe in the scratchpad, never committed. It runs the
game windowed: `godot --path <tree> --resolution WxH -- --mute --sanity=30` for both 1200x675
and 1920x1080, on the baseline (`release-0.10.0` checkout) and the branch, from the same
scripted state. That state has towers L1 and L3 with a branch letter, one lit, one shadowed, one
selected with its range ring, the phantom path, and a leak frame frozen by holding its ttl. The
probe saves `get_viewport().get_texture().get_image().save_png()`. The fog shader animates with
`TIME`, so pair A hides `Lighting.fog` and is compared exactly, and pair B (fog on) is checked by
eye. A pixel diff reports the count and bbox of differing pixels per pair. Pass: fills 0;
differences only on line pixels, each within 1 px of the baseline line; all numbers written in
`complete_slice`. One hex screenshot is attached for the owner: the probe sets
`view.grid = HexGrid.new(w, h)` on MapLayer and EntityLayer over the same map rows. It is a look
check only, since the hex map is not playable.

## 6. Behaviours for the tests slice (each with a control)

1. `GridFactory.make("square", 5, 4)` is a SquareGrid equal in `cells()`, `bounds()` and
   `kind()` to `SquareGrid.new(5, 4)`. `make("hex", …)` is null and `kinds()` is `["square"]`,
   which pins that hex is unregistered. Control: map `"square"` to null.
2. `MapDef.parse` builds its grid through the factory (G15's third form, §4). An unknown grid,
   `"hex"` included, keeps today's error text (`map_def_test.gd:152`). Control: restore
   `m.grid = SquareGrid.new(...)` in map_def.gd, so G15 fails.
3. Square `cell_polygon(c, d)` equals the corners of
   `Rect2(c * TILE, TILE²).grow(-d)` exactly, for d ∈ {0, 2, 4, 6} over every cell. This
   replaces `board_view_test` §4. The tiling test sums the polygon areas to `W * H * TILE²`
   and checks that right neighbours share an edge. Line 268 compares the lighthouse polygon's
   corners. Control: drop the `(a - inset) / a` scale.
4. `outline_quads(cell, w, inset)` returns n quads (4 on square, 6 on hex) that together cover
   exactly the area of `inset - w/2` minus `inset + w/2`, with no pairwise overlap
   (`Geometry2D.intersect_polygons` is empty). Control: swap inner and outer.
5. `tests/hex_grid_test.gd`, mirroring `square_grid_test.gd`:
   - interior neighbours are the 6 axial offsets in the pinned order; neighbourhood is
     symmetric; edge and corner cells stay in bounds;
   - `distance` to every neighbour ≈ 1 (1e-9); `steps` equals hex hops (hand-checked pairs);
   - `polygon` has 6 corners in the pinned order;
   - `cell_at(centre(c)) == c` for every cell, and points nudged 0.4 toward each neighbour
     centre land in that neighbour;
   - `text_of(cell_of_text(x, y)) == (x, y)` for every text cell; hand-checked pairs on even
     and odd rows (for example text (0, 1) -> axial (0, 1), text (0, 2) -> axial (-1, 2));
   - `cells()` is text row-major, `index` inverts it, and `bounds` and `kind() == "hex"` hold.
   Controls: drop the `(y & 1)` term in `cell_of_text`; replace `0.5 * c.y` with 0 in `centre`.
5b. MapDef on hex: `_read_rows` on a hand-set `HexGrid.new(4, 3)` with a 3-row text whose path
   is only connected under hex adjacency. `kind_at`, `spawn` and `lighthouse` are axial, the
   path is derived, and an orphan path cell's error names the text column. On square, the
   existing `map_def_test` errors stay unchanged. Control: store under `Vector2i(x, y)` in the
   loop.
6. Hex drawing geometry: with `view.grid = HexGrid.new(5, 4)`, each `cell_polygon` has
   6 points, neighbour tiles intersect with area 0, the polygon areas sum to
   `cell_count * (sqrt(3) / 2) * TILE²` (each hex is `sqrt(3)/2` cell units²), and the inset apothem
   equals `a - d`. Control: make `cell_polygon` return the bounding box.
7. Tower anchors: a pure `EntityLayer.tower_anchors(centre) -> Dictionary`, where each F3
   anchor equals today's `r.position + offset` for a square cell. Control: change one offset.
8. `LEAKED` adds an effect with `"cell" == map.lighthouse`. Control: drop the key.
9. G15 as in §4, G10 home count `== 4`, and G3 with 2 homes and 3 hits. Controls (one
   group): put back the `fx_layer.gd` `from - Vector2(0.5, 0.5)` rect, and separately a
   `view.cell_rect(` call in phantom_layer, so that both forms fail.

Controls chosen (8): items 1, 2, 3, 4, 5 (the `cell_of_text` parity), 5b, 6, 9. Item 5's second
control and items 7-8 are reverted only if the verify budget allows.

Not pinned by a test: the draw calls themselves (render-only, §5 screenshots) and MapLayer's
fill-then-outline order (checked by screenshot).

## 7. Alternatives

- **Factory as a static `GridTopology.make` on the abstract base.** Benefit: no new file. Risk:
  a base that names its subclasses (a cyclic class_name reference), and the base file changes
  for every new topology.
- **A `MAKERS` dictionary inside MapDef.** Benefit: smallest change. Risk: MapDef holds topology
  knowledge, and tests or tools that want a grid by name go through map parsing.
- **Outlines with a closed `draw_polyline`.** Benefit: 1 call. Risk: a butt joint where the
  line starts and ends (a notch at w 2 and 4). Closing it by repeating points draws alpha
  twice.
- **Keep `draw_rect` when the polygon is an axis-aligned rect.** Benefit: square is
  byte-identical by construction. Risk: two code paths, and the square path is the only one
  exercised in play, so hex drawing stays untested.

## 8. EDIT MAP (code slice)

Edit:
- `sim/rules/grid_factory.gd` (new): F1.
- `sim/rules/hex_grid.gd` (new): F5. Model it on `sim/rules/square_grid.gd:1-76`.
- `sim/rules/grid_topology.gd` (after `:56`): `cell_of_text`/`text_of` with identity defaults
  (F6).
- `sim/defs/map_def.gd:28-31` (`parse`): factory call, error text from `kinds()`, fallback.
  `:40-59`: rows loop -> `_read_rows`, using `grid.cell_of_text`. `:75-112` (`_derive_path`):
  error coordinates via `grid.text_of` (F6).
- `scenes/board/board_view.gd:66-81`: `cell_polygon(cell, inset_px)`, `cell_centre`,
  `outline_quads`, static `fill_cell`/`outline_cell`; **delete `cell_rect` (`:74-81`)**; update
  the header comment `:12-13`.
- `scenes/board.gd:206-226` (`MapLayer._draw`): sites 1-3.
- `scenes/lighting.gd:301-304` (`SeaFog._draw`): site 4.
- `scenes/board/phantom_layer.gd:21-31` (`_draw`): site 5.
- `scenes/board/entity_layer.gd:34` (`LETTER_PLATE` -> centre offsets, `GLYPH_OFFSET`),
  `:130-157` (`_draw_tower`, plus a new `tower_anchors`): site 6.
- `scenes/board/overlay_layer.gd:13-22` (`_draw`): sites 7-8.
- `scenes/board/fx_layer.gd:129-132` (`on_event` LEAKED), `:338-341` (`_draw_effects` leak): site 9.
- `tests/architecture_guard_test.gd`: G3 home list (`:118`, home count `:144`); G10 home count
  (`:291`); new G15 after G10 (`:297`).
- `tests/board_view_test.gd:5` (header), `:172-196` (§4 rewritten on `cell_polygon`), `:268`.
- New tests: `tests/hex_grid_test.gd`, the hex case in `tests/map_def_test.gd` (5b), plus GridFactory, inset, outline and hex-drawing tests
  in `board_view_test.gd` or a new `grid_factory_test.gd` (the tests slice decides).

Read for context: `sim/rules/grid_topology.gd:1-56`, `sim/rules/square_grid.gd:44-53`
(`polygon`), `scenes/board/board_layer.gd` (`view`), `fx_layer.gd:72-91, 299-310` (LT-90
warm-up), `tests/board_view_test.gd:176-196` (bbox tests that must stay green),
`tests/architecture_guard_test.gd:112-148` (G3, `_find_joined` usage),
`tests/square_grid_test.gd` (outline to mirror), `sim/defs/map_def.gd` `_derive_path`
(walks `grid.neighbours`; it must work with hex unchanged).

Not touched (LT-109/LT-110 stay open): path derivation and `_ground_route`. Layers keep pixel
widths and insets, so LT-110 can move the cell -> world map behind a transform inside BoardView
without revisiting the call sites.

## 9. Open questions for the owner (all answered in §10)

1. **Factory shape.** **A: `GridFactory` file with `MAKERS` (Recommended).** Benefit: hex is one
   line, and the error text and G10 count follow the table. Risk: one more small file.
   B: static on `GridTopology` (cyclic reference). C: dictionary in MapDef (topology knowledge
   in MapDef).
2. **Outline primitive.** **A: ring of quads via `draw_colored_polygon` (Recommended).**
   Benefit: exact mitred corners on any polygon. Risk: 4 calls per outline, and a possible 1 px
   or corner-alpha difference on square. B: closed `draw_polyline` (notch at the seam).
   C: keep `draw_rect` for square (two paths).
3. **Tower marks on hex.** **A: centre offsets equal to today, hex fit left to LT-64
   (Recommended).** Benefit: square is pixel-identical, and the layout is in one place for
   LT-64. Risk: pips may poke out of an inset hex plate until LT-64 adjusts them. B: design a
   hex-safe layout now (changes square looks).
4. **`cell_rect`.** **A: keep it as a bbox in BoardView, guarded (Recommended).** Benefit:
   existing tests stay, and UI anchoring is possible later. Risk: an unused production method.
   B: delete it and rewrite `board_view_test` §4.
5. **Square tolerance.** **A: fills identical, outlines ≤1 px shift and corner alpha accepted
   and reported (Recommended).** Benefit: matches the task's acceptance. Risk: a visible corner
   pixel on the 0.8-alpha selection. B: require byte-identical screenshots (would force
   alternative C of Q2).
6. **Hex proof.** **A: test-only stub hex topology in `tests/support/` (Recommended).** Benefit:
   no shipped hex before LT-64 picks the look. Risk: the stub can drift from the real HexGrid.
   B: ship `HexGrid` now, unregistered in `MAKERS`.
7. **Hex orientation and cell id** (new, from Q6). **A: pointy-top, odd-r offset ids `(column,
   row)` (Recommended).** Benefit: MapDef, the `rows` text and S/L parsing work unchanged, so
   hex really is one class + data + factory line. Risk: neighbour offsets depend on row
   parity, and `steps`/`cell_at` convert through axial internally. This deviates from LT-77
   §3's axial id. B: pointy-top axial ids, as LT-77 §3 sketched. Benefit: simpler neighbour
   math. Risk: MapDef must convert row and column to axial, so hex touches MapDef as well.
   C: flat-top, odd-q columns. Benefit: may suit an angled view better (LT-64). Risk: `rows`
   text no longer reads as rows of cells, and the map format and editor view change.

## 10. Owner decisions (2026-11-21)

1. Factory: "GridFactory + MAKERS (Recommended)".
2. Outlines: "Кольцо из quad'ов (Recommended)".
3. Tower marks: "Смещения как сейчас, гекс в LT-64 (Recommended)".
4. cell_rect: "Удалить". `cell_rect` is deleted and its tests are rewritten on `cell_polygon`;
   G15 bans `cell_rect` everywhere (§2 F2, §4, §6 item 3).
5. Square tolerance: "Заливки 1:1, контуры ≤1 px (Recommended)".
6. Hex proof: "HexGrid сейчас, без MAKERS". A real `sim/rules/hex_grid.gd` ships unregistered
   (§2 F5, §6 items 5-6).
7. Hex orientation and cell id: "Axial id". HexGrid uses axial ids (LT-77 §3) and is
   pointy-top (§2 F5). MapDef converts the text through `GridTopology.cell_of_text`/`text_of`
   (§2 F6); square is unchanged.
