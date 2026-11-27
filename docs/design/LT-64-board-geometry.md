# LT-64: board geometry (coordinate layer, angled view, hex)

Status: approved by the owner 2026-11-26 (decisions in §6.1 and §9.1). Branch `docs/LT-64-board-geometry` from `release-0.14.0`
(7201d97). §0-§6 are the pre-prototype design (S1); §7 holds the prototype results (S2/S3),
§8 the recommendation, §9 the questions still open.

Owner's idea (verbatim): "В финальной версии графики мне хочется чтобы вид был не 100% сверху,
а как бы под углом, в перспективе. Нужно заложить это наверное заранее? + мы же хотим сетку на
гексах + вороной?"

Scope: geometry, coordinates and view cost only. Map v2 gameplay (islands, path rule,
generator, flood, barricades) is LT-18, designed in parallel elsewhere; this note only prices
what hex/Voronoi costs the geometry, and leaves gameplay rules to LT-18.

Prior work this builds on (not re-derived): LT-33 (boundary audit, findings 1, 2, 12, 19),
LT-35 (`BoardView`, guard G2), LT-77 (`GridTopology`, hex/Voronoi sketch §3), LT-108
(`GridFactory`, polygon tiles, guard G15, a real `HexGrid` shipped unregistered), LT-96 S15 /
LT-110 (view transform), LT-62 (frame-rate method and machine).

## 0. Short answer

- **"Lay it in early?"** Mostly already laid. Since LT-35/LT-108 no code outside
  `BoardView` knows `CELL` or the board origin (G2), picking has one entry
  (`cell_at_screen`), and tiles come from `GridTopology.polygon` (G15). What is *not* laid
  is the **meaning** of each pixel call: today every call assumes "the board is a flat
  top-down rectangle", so `cells_to_px(r)` is a circle, `cell_to_world(dir) * k` is a
  screen direction, text sits on the tile. An angled view needs each site to say whether it
  draws **on the ground**, **upright** (a figure standing on a point), or **in height**
  (a lift above the ground). That split is the one piece worth doing before the view
  choice (§1.3), because it is option-agnostic and pixel-identical at tilt 0.
- **Hex logic** is ~70 % done: `HexGrid` exists and is tested; path walk, route length,
  ranges, bot placement and the balance lab are topology-agnostic. What is left is mostly
  look (tower plate marks), map data, balance retune and test fixtures (§3).
- **Recommended order:** superseded by §8 (after the prototypes): coordinate-layer split ->
  view (b2, the owner's pick; a focused FPS re-measure is a check) -> hex look and tile art with
  LT-18; hex logic registration runs in parallel as LT-18's first step.

## 1. One presentation coordinate layer

### 1.1 What exists (release-0.14.0)

`scenes/board/board_view.gd` (`BoardView`, LT-35) is the single holder of `CELL := 40.0`
(:19) and `ORIGIN = (0, HUD_H)` (:21). Frames: cell units (sim) -> world (board node's local
canvas, `cell_to_world` = `p * CELL`, :96) -> screen (base viewport 1200x675, `origin()` =
`ORIGIN + pan`, :50). Picking: `cell_at_screen` (:84) = `grid.cell_at(screen_to_cells(p))`.
Tiles: `cell_polygon`/`fill_cell`/`outline_cell` (:118-157) from `GridTopology.polygon`.
Pan: `clamp_pan` (:56) over the axis-aligned `world_rect_for` (:39).

Draw order today is node order under `Board` (`scenes/board.gd:100-114`): `MapLayer`
(behind) -> `Lighting` (CanvasModulate, PointLight2Ds, sea fog) -> `PhantomLayer` ->
`EntityLayer` -> `FxLayer` -> `OverlayLayer`. Inside `EntityLayer._draw`
(`entity_layer.gd:89-98`): auras, then **all towers in snapshot order, then all enemies,
then allies**. There is no depth sort: top-down, nothing overlaps its neighbour cell, so
none was needed.

### 1.2 Edit map: every site that turns cells into pixels, by role

Counts per file (`cell_to_world` / length `cells_to_px|px_to_cells` / screen calls / tile
helpers): entity_layer 7/21/0/5, fx_layer 36/32/0/1, overlay_layer 2/4/0/2, lighting 3/4/0/1,
board.gd 1/0/5/5, board_camera 0/3/3/0, phantom_layer 0/0/0/1, relic_tokens 0/0/1/0,
hud 0/0/2/0, side_panel 0/0/2/0, sanity_fx 0/0/1/0. No site outside `board_view.gd` names
`CELL` or `ORIGIN` (G2 holds).

Roles: **G** ground (lies on the board plane: should foreshorten with the view), **U**
upright (a figure or label anchored at a ground point: position projects, shape stays in
screen pixels), **H** height (an offset above the ground: screen-up, never foreshortened),
**S** screen (UI frame, pan, input: independent of the board plane), **P** picking.

| Site | Role | What it does | Under an angled view |
|---|---|---|---|
| `board_view.gd:19-157` | core | the whole map cells <-> pixels | gains `project`/`unproject`/`depth` (§1.3) |
| `board.gd:97, :133` `position = view.origin()` | core | board node canvas = translation only | becomes the ground transform (option a) |
| `board.gd:159` `cell_at_screen` | P | click -> cell (the only command input) | inverse projection; upright hit first (below) |
| `board.gd:170-186` `enemy_at_screen` | P | nearest drawn enemy within `PICK_RADIUS` cells of the ground point | must hit the **drawn body** (upright, above the foot), not the ground point |
| `board.gd:296-305` MapLayer sea rect | G | water backdrop = bounds grown by play rect | bounds become a projected quad; take its bbox |
| `board.gd:310-316` MapLayer tiles, spawn, lighthouse | G | `fill_cell`/`outline_cell` | foreshortened tiles, free under a transform |
| `board.gd:317` "L" string at `cell_centre + (-7, 8)` | U | lighthouse letter | label in screen px at projected centre |
| `lighting.gd:99, :112, :114, :184, :192, :257-258` light positions | G | lighthouse glow, flare, beams, tower lights at cell centres | positions project; light **shape** should foreshorten (ellipse) |
| `lighting.gd:111, :188, :201, :211, :253` `texture_scale` from `cells_to_px` | G | light radius in cells | same; verify Light2D honours a non-uniform parent transform (prototype a) |
| `lighting.gd:136` WarmLight at `FxLayer.WARMUP_RECT` | S-ish | first-frame shader warm-up (LT-92) | unaffected (only must stay on screen) |
| `lighting.gd:347` sea-fog mask `fill_cell` | G | per-cell fog mask image | foreshortens with the ground |
| `phantom_layer.gd:31` `fill_cell` | G | build preview tile | ground |
| `overlay_layer.gd:19-20` enemy select ring | U/G | ring around the drawn enemy | ellipse at the foot (G) or ring round the body (U): owner look choice |
| `overlay_layer.gd:22` cell outline | G | selected tile | ground |
| `overlay_layer.gd:24-25` glyph at `cell_centre + GLYPH_OFFSET` | U | tower letter on the selection | label |
| `overlay_layer.gd:28-33` range arc, dead-zone disc/dashes | G | range rings in cells | must become ellipses (G); `draw_arc` cannot draw one in a flat frame |
| `entity_layer.gd:42-44, :159-161` `GLYPH_OFFSET`, `PIP_OFFSET`, `STATE_MARK_OFFSET`, `tower_anchors` | U | tower letter, level pips, marks in px from the centre | labels; on hex also LT-108 Q3 (plate marks in a hex plate) |
| `entity_layer.gd:165-198` `_draw_tower` plate (`fill_cell`, `outline_cell`, letter plate rect) | G + U | the tower **is** a tile today | plate = G footprint; a future tower sprite = U |
| `entity_layer.gd:200-236` `_draw_post` crew figures | U | stick figures in px | upright, depth-sorted |
| `entity_layer.gd:238-280` auras, searchlight cone | G | rings/cones on the board | ground |
| `entity_layer.gd:283-345` enemies (`cell_to_world(p)`, body radius, `:331` slash dir, `:336` HP bar above) | U (+H for the bar) | discs at the sim point | upright; HP bar is H; depth-sorted with towers |
| `entity_layer.gd:347-370` allies, `:352` leash ring, `:358` hold line | U / G | allies and their leash | figure U, leash ring and line G |
| `fx_layer.gd:362-364` death mark | G | disc where an enemy died | ground |
| `fx_layer.gd:374-466` astray, tracer, harpoon (`:429-430`, `:447-449` dir offsets, `:458` chain) | G between U anchors | shots from tower to target | endpoints are U anchors (muzzle, body), the line itself is a screen segment |
| `fx_layer.gd:475-528` wave, beam (`:528` ray dirs) | G | ground waves and beams | ground |
| `fx_layer.gd:536-565` banish | G | | ground |
| `fx_layer.gd:577-626` shell (`:585` `Vector2(0, -cells_to_px(0.25))` lift) | H | lobbed shell | the lift is height: screen-up, not foreshortened |
| `fx_layer.gd:628-668, :687-702` charge arc, `_arc_lift` | H | arc bulge built from `cell_to_world(_arc_lift)` | height in cells today: becomes a pure screen-up term |
| `fx_layer.gd:669-686` lift (LT-117) | H | tower lift | height |
| `fx_layer.gd:721-740` blast rings | G | AoE ring | ellipse |
| `fx_layer.gd:386-401` waver/wave amplitudes in px | S | decoration | unchanged |
| `board_camera.gd:42, :55-69, :161-170` pan, clamp | S | screen pan over `world_rect_for` | bbox of the projected map |
| `board_camera.gd:83, :94` wheel step `cells_to_px` | S | pan speed | unchanged (or per-row scale) |
| `board_camera.gd:194-195` `reveal` | S over U | pans a ground point into view | uses `project` |
| `relic_tokens.gd:84-86` `board_to_layer` | U -> S | token starts at a kill point | start at the projected body, not the foot |
| `hud.gd:574-576`, `side_panel.gd:72, :224-226`, `sanity_fx.gd:71, :131` | S | play frame, HUD height | unchanged (LT-33 finding 2 already fixed) |

Totals: roughly 60 G calls, 30 U calls, 6 H calls, 10 S/P calls. LT-96 counted 97 lines
under `scenes/`; that matches (several lines hold two calls).

### 1.3 The option-agnostic step: name the role in `BoardView`

Add to `BoardView`, with an **identity projection** first (pixel-identical, so the LT-108
style "fills 1:1, outlines <= 1 px" check proves it):

- `project(p_cells: Vector2, h_cells := 0.0) -> Vector2` (world px): a ground point,
  optionally lifted by `h` screen-up. Used by every U and H site.
- `unproject(screen: Vector2) -> Vector2` (cell units on the ground plane): the one inverse;
  `screen_to_cells` becomes it, `cell_at_screen` stays `grid.cell_at(unproject(p))`.
- `depth(p_cells) -> float`: the draw-order key (ground y after projection; ties by id).
  `EntityLayer._draw` draws towers, enemies, allies and posts in one list sorted by
  `depth`, so a figure in front covers one behind. Visual only: the sim never sees it.
- `ring(ci, centre_cells, r_cells, color, width)`: a range/aura/blast ring as a polygon
  through `project`, so it becomes an ellipse under any view (replaces `draw_arc` at G
  rings: overlay :29-33, entity auras, fx blasts).
- Picking order in `Board._unhandled_input`: upright bodies first (screen distance to the
  drawn body rect, in px), then the ground cell. Today `enemy_at_screen` measures in cell
  units at the foot; at tilt 0 the two agree.
- Pan bounds: `world_rect_for` = bbox of the projected map corners.
- Guard (extends G2): under `scenes/` and `ui/` outside `board_view.gd`, no
  `cell_to_world(` with a direction argument times a scalar for U/H use (the `:331`,
  `:447-449`, `:585`, `:635` forms); the H sites take `project(p, h)`.

Benefit: the view choice then touches `BoardView` and the layer split only; every site
already says what it is. Risk: ~100 call sites touched for zero visible change; worth it
only if an angled view is really wanted (the owner's message says it is). The depth sort
costs one sort of ~50-150 records per frame (negligible next to ~750 draw calls, LT-62), but
measure it with the prototypes anyway.

**How LT-110 fits.** LT-110 (LT-96 S15: "layers draw in cell units under one canvas
transform held by `BoardView`") is the implementation of option (a) for the **G** sites
only: the ground layers drop `cell_to_world`/`cells_to_px` and draw in cell units under
`view.ground_xform`; rings become ellipses and fog/lights foreshorten for free. Its own
stated risk ("line widths and text must stay in pixels") is exactly the U/H split: U and H
cannot live under that transform. So LT-110 should be re-scoped as "G sites under one
transform; U/H through `project`", and stays blocked until the view is picked. Under (c)
LT-110 is not needed; under (b) it is replaced by the 3D plane.

## 2. Angled-view options

Constraints for all three: GL Compatibility renderer, web export (WebGL 2), Intel Iris Plus
at a boot-fit 2390x1344 window where today's game runs ~37-43 fps median with 720-835 draw
calls (LT-62, focused window). Any option that adds a full-screen pass or breaks 2D batching
eats into that.

### (a) 2.5D: oblique projection of the 2D board, y-sorted figures

What changes: the `Board` node's transform becomes `origin * tilt` with `tilt` an affine
`Transform2D` (y scaled by cos(tilt), optional small skew; orthographic, no vanishing
point). G layers (map, fog, lights, phantom, auras, rings, ground fx) stay children and
foreshorten for free. U and H items move to one `UprightLayer` (a sibling not under the tilt)
drawing at `project(p, h)`, depth-sorted. Picking uses the affine inverse.

- Benefit: cheapest real angle; one matrix; 2D lighting, fog shader, SanityFx and 2D
  batching unchanged; web-safe; matches LT-110 directly; hex and Voronoi tiles work as is.
- Risk: no true perspective (far rows are not smaller). Thick `draw_line`s under the tilt
  get thinner when horizontal (width is in local space); text under the tilt is squashed
  (hence the U layer). Light2D under a non-uniform parent transform foreshortens its
  texture (verified in the prototype, §7.1). Vertical tap targets shrink by cos(tilt): at 40 px
  cells and 45° a row is ~28 px.

Prototype spec (throwaway worktree, never merged):
1. `--tilt=<deg>` debug arg; screenshots at 0, 30, 45, 60 deg, 1200x675 and boot-fit, night,
   sanity 100 and 0. Launch with `-- --mute`.
2. Square map and the same map on the unregistered `HexGrid` (register it in the
   prototype's `MAKERS` only).
3. One tower in front of an enemy and one behind (depth order visible), a range ring
   (ellipse), the beam sweeping (lights foreshortened or not: the key visual check), sea fog.
4. Mouse hover outlines the picked cell, and a debug dot at `project(unproject(mouse))`
   must sit under the cursor on every cell (picking proof); log a round-trip check over all
   `grid.cells()` at the start.
5. Frame stats on (`--frame-stats`) so the measure slice can run LT-62's focused-window
   method on it unchanged; bot on, ~30 live enemies.

### (b) True 3D scene with a tilted camera

What changes: two variants.
- **(b1) Full 3D**: board as meshes, towers/enemies as `Sprite3D` billboards or models,
  `Camera3D` with perspective; lights become `OmniLight3D`/`SpotLight3D`; fog and
  `CanvasModulate` darkness become 3D materials or environment; all ~740 lines of
  `fx_layer` immediate drawing become `ImmediateMesh`/particles. Effectively a rewrite of
  presentation; the sim and `BoardView`'s contract survive (picking = ray/ground-plane hit
  -> cell units).
- **(b2) Hybrid**: today's 2D board rendered into a `SubViewport`, textured onto one ground
  quad in a 3D scene with a tilted perspective camera; U items as `Sprite3D` billboards at
  ground points (or drawn 2D at `camera.unproject_position`). Keeps all 2D drawing and 2D
  lights.
- Benefit: real perspective and a camera that can tilt, zoom, orbit; models from the
  "stylised 3D pre-render" path (GDD §9a style 3) could become real-time.
- Risk: (b1) is the largest cost in this note and drops 2D batching (GL Compatibility has
  no 3D batching; every object a draw call) on a GPU that already sits at ~40 fps; 3D
  shadows/lights in Compatibility are limited. (b2) adds a full-resolution render target
  plus a sampled, mip-mapped pass each frame (fill rate on Iris Plus is the worry), and
  text/thin lines on the plane blur at grazing angles unless the viewport is
  over-sampled. Both: SanityFx's `BackBufferCopy` rect (LT-62/S13 quirk) needs rechecking
  with a 3D layer under it; web export of 3D in Compatibility works but is heavier to load.

Prototype spec: build **(b2) only** (b1 is not worth a prototype before the owner says
"we need a free camera"):
1. The current `Board` in a `SubViewport` sized to the map's pixel size, on a quad; a
   `Camera3D` with `--tilt=<deg>` and `--fov=<deg>`; same screenshots as (a).
2. Enemies and towers as billboards at their ground points, depth from the camera.
3. Picking by ray-plane hit -> uv -> world px -> cells; hover outline and the round-trip
   check as in (a).
4. SanityFx on at sanity 0 (the screen pass over a 3D layer), night lighting, fog.
5. Frame stats on; the measure slice compares (b2) and (a) at the same tilt.

### (c) Flat logic, angle-drawn 2D art

What changes: no projection in code. `BoardView` keeps the top-down map (perhaps with a
non-square cell, `CELL_Y < CELL_X`, which is (a) with zero skew). The angle exists only in
the art: a painted background or tile sprites with a visible front face, towers and enemies
drawn in 3/4 view, taller than a cell and anchored at their foot. Code needs only the §1.3
split: depth sort, foot anchors, upright picking, H offsets.

- Benefit: the cheapest code; the common 2D TD look (3/4 sprites on a painted map); little
  frame-rate risk beyond the sort (procedural front strips cost +8 % draw calls, §7.2); fits every GDD §9a style; works with Skeleton2D cutout.
- Risk: range rings and tiles stay circles and regular hexes, so they contradict angled
  art unless tiles are hidden under painting; Map v2's generated islands rule out one
  hand-painted background (GDD open issue), so hexes need per-tile angled sprites, which
  is the most art work. "Perspective" is only implied.

Prototype spec:
1. `CELL_Y = 0.75 * CELL_X` toggle plus the §1.3 depth sort and foot anchors, nothing else.
2. Placeholder angled art, procedural: each tile gets a darker front-face strip, each tower
   a box (top + front face) ~1.5 cells tall, enemies as tall ellipses on a foot shadow.
3. Square and hex maps; overlap cases as in (a) item 3; hover/picking as in (a) item 4,
   including a click on a tall tower's top that overlaps the cell behind it.
4. Frame stats on.

### Comparison

| | (a) oblique 2.5D | (b2) 2D board on a 3D plane | (b1) full 3D | (c) angle only in art |
|---|---|---|---|---|
| True perspective | no | yes | yes | no |
| Code beyond §1.3 | LT-110 (G sites, ~60) + U layer | SubViewport + camera + billboards | presentation rewrite | none |
| 2D lights / fog / SanityFx | kept (Light2D under tilt: verified, §7.1) | kept | rebuilt | kept |
| Frame-rate risk on Iris Plus | low | medium (extra full-res pass; §7.2 shows no gap, unfocused) | high | low (+8 % draws with procedural front strips, §7.2) |
| Art cost | upright sprites only | upright sprites only | models | most (angled tiles) |

Provisional lean: (a), possibly combined with (c)-style 3/4 sprites in the U layer;
(b2) as the fallback if (a)'s orthographic tilt looks too flat. Decided only after the
measure slice.

## 3. Hex logic grid, Voronoi as look

Owner direction (LT-77 §8, LT-18, GDD "Map v2"): hex logic underneath, jittered Voronoi
polygons on top, axial `Vector2i` ids, pointy-top (LT-108 Q7).

### 3.1 Cost by area

| Area | State today | Remaining cost |
|---|---|---|
| Neighbours, distance, steps, centre, polygon, picking (`cell_at`, cube rounding) | `sim/rules/hex_grid.gd`, `tests/hex_grid_test.gd` | none |
| Registration | `GridFactory.MAKERS` has only `"square"` (`grid_factory.gd:9`) | 1 line + a config test |
| Map data / parse | `cell_of_text`/`text_of` (odd-r rows) exist; `map_def.gd` errors say "column %d" (:103, :116) | low: per-topology error text; a hex `data/map.json` (or a second map file) |
| Path walk | `map_def.gd:136` walks `grid.neighbours` | none for one fixed path; per-wave paths are LT-18/LT-109 |
| Route length | `sim_route.gd:22` sums `grid.distance` (hex steps all 1.0) | none |
| Range, cast, horror, dead zone, beam, line hits | euclid in cell units, world frame | none in code; balance: same radius covers ~15 % more cells (LT-77 §3) |
| Beam directions | 8 world directions | none (look: 8 rays over 6 hex axes; owner's call) |
| Traits by `steps` (`trait_host.gd:41-47`, LT-117 drop) | topology-agnostic | balance: a ring of N steps has 6N cells on hex vs 4N on square |
| Bots | `bot_placement.gd:20-25` uses `grid.cells()`/`distance`; strategies hold no cells | none |
| Balance lab | variants deep-merge into `data/*.json` | none in code: a `grid_hex` variant can patch `map.json` (`grid`, `rows`); runs per README (~8-15 CPU-min per variant at 20 seeds) |
| Tile drawing, fog, phantom, selection | `fill_cell`/`outline_cell` from `polygon` (LT-108) | none |
| Tower plate marks | px offsets `entity_layer.gd:42-44` sized for a square plate (LT-108 Q3 deferred here) | low: centred layout inside the hex apothem |
| Viewport fit | 24x14 squares = 960x560 px, exactly the 560 px play height | hex 24x14 = 24.5 x 12.4 cells (980x496 px at 40 px): fits; with a tilt there is room to grow `CELL` |
| Tests | 49 test files hold 251 literal cells; `board_view_test`, `board_camera_test`, `board_layers_test` load `res://data` | medium if the shipped map turns hex: point those tests at a frozen square map fixture (like `tests/fixtures/golden_data`); add hex tests for parse, picking round-trip on every cell, plate layout |
| Golden replay | frozen square copy | none; an optional hex golden run later |
| Voronoi look | LT-77 §3: `polygon` = hex corners moved by a seeded jitter per shared vertex | low-medium: a `JitteredHex` decorator in presentation (not sim), seeded per map; tiles still meet; picking stays hex (a click near a jittered edge may pick the neighbour: max error = jitter amplitude; keep it < ~15 % of the apothem or pick by polygon test) |

Estimate: registering hex and making the current map hex-playable is ~1 small task plus a
test-fixture task and a balance-lab pass. The real Map v2 cost (generator, per-wave routes,
islands) belongs to LT-18/LT-109, not to the grid.

### 3.2 Hexes under the angled view

- Pointy-top under a vertical squash reads as a wide, flat hex; rows interlock left-right,
  which reads naturally from a low camera. Flat-top would give long horizontal edges and
  column stacks: keep pointy-top (already decided).
- (a)/(b): tiles foreshorten with the ground; picking composes `unproject` with
  `HexGrid.cell_at`, nothing new. In (b) far rows shrink: the far row's tap target sets the
  minimum `CELL`.
- (c): hex tiles stay regular on screen; angled hex tile sprites with a front face are the
  art cost.
- Voronoi jitter is applied in cell units before projection, so it foreshortens too.
- Upright towers taller than one row cover the hex behind them: picking must take the
  tower body first (§1.3), or the tile behind becomes hard to click.

## 4. Ties to GDD §9a (art pipeline)

- §9a's MVP map is "1 hand-painted harbor background (fixed path, no tileset)". Hex Map v2
  with generated islands conflicts with one painted background (GDD Map v2 open point):
  generated maps need tile art (per-hex terrain, Voronoi edges), drawn for the chosen view.
  So the view must be chosen **before** tile art is commissioned.
- The style test (§9a, before milestone 4) should be run **at the chosen tilt**, with the
  depth sort on: a silhouette style (1) reads differently from 3/4 than from above.
- Cutout animation (Skeleton2D) and Laigter normal maps work for (a) and (c) and for (b2)
  billboards; (b1) would replace them with 3D models (style 3, "3D pre-render", becomes
  real-time 3D).
- 2D lighting and shader layer (§9a "built from milestone 1 on") survive (a), (b2) and (c);
  (b1) rebuilds it.

## 5. Recommended order (provisional, pending measurements)

Superseded by §8.2; kept as the pre-prototype reasoning.

1. **Coordinate-layer split** (§1.3): `project`/`unproject`/`depth`/`ring`, U/G/H roles,
   depth-sorted entity draw, upright picking; identity projection, pixel-identical at tilt
   0; guard extension. Benefit: every later option plugs in. Risk: ~100 sites for no
   visible change.
2. **Prototypes** (a) and (c) in throwaway worktrees, (b2) only if the owner wants true
   perspective; then a **measure slice**: screenshots and focused-window FPS by LT-62's
   method, square and hex.
3. **Owner picks the view**; LT-110 re-scoped to it (G under one transform for (a)).
4. **Hex**: register `HexGrid`, hex map data, plate marks, frozen square fixture for tests,
   balance-lab pass. Can run in parallel with 2-3; it lands with LT-18's first slice.
5. Style test (§9a) at the chosen tilt, then tile art.

## 6. Open questions for the owner

1. **Perspective or tilt?** Is an orthographic tilt (a: no vanishing point, far rows same
   size) enough, or must far rows look smaller (b2)? Benefit of (a): cheap and safe on the
   web/Iris Plus. Risk: may look "flat-ish" next to the reference images in the owner's head.
2. **Do the coordinate-layer split (§5 step 1) now**, before the prototypes, or prototype
   first with hacks and split only after a view is picked? Now: the prototypes become
   small and honest. Later: no ~100-site churn if the owner drops the angled view.
3. **Free camera?** Any need to rotate/orbit/zoom the camera in the final game? Only "yes"
   justifies (b1).
4. **Range-ring look under tilt**: ellipse on the ground (correct) or screen circle (easier
   to read)?
5. **Hex in the shipped map before LT-18** (a hex version of today's harbour) or only with
   Map v2?

### 6.1 Owner answers before the prototypes (2026-11-26)

- Q1 perspective or tilt: "a, b2 и c, решить по скринам (Recommended)": prototype (a), (b2)
  and (c); the choice is made from screenshots and FPS.
- Q3 free camera: "Только зум": no rotation or orbit, so (b1) is dropped; zoom must work in
  the chosen view.
- Q2 coordinate-layer split: "После прототипов (Recommended)": prototypes use throwaway hacks;
  the split is a separate task after a view is picked.
- Q4 (range ring) and Q5 (hex before Map v2) are answered at the final review (§9).

After the prototypes (2026-11-26):
- View: "в общем лучше всего b2": (b2), the 2D board on a tilted 3D plane, is the chosen
  view; (a) and (c) are not pursued (§8).

## 7. Prototype results

Prototypes (S2) live on the throwaway branch `proto/LT-64-views` @3577952 (never merged):
`--view=a|b2|c`, `--tilt` (default 45°), `--fov` (default 50°, b2), `--zoom`. Screenshots (S3)
are in `docs/design/LT-64/`: `baseline`, `a`, `b2`, `c` (zoom 1) and `*-zoom` (zoom 2), all
at t = 15 s, 5 towers, 10 live enemies, night 1, sanity 100, 2390x1344 window scaled to
1400 px. Square map only.

### 7.1 What the screenshots show

| Option | Look | Seen in the shots | Prototype caveats (S2) |
|---|---|---|---|
| baseline | top-down | reference | - |
| (a) oblique, tilt 45° | the board squashed to ~0.7 height; upright tower cards and enemy discs; reads as "the same map, shorter", not as an angle | ground layers foreshorten for free: the beam cone, tower glow and fog shrink vertically (Light2D under the tilt works; was "unverified" in §2a). Range rings, shots and fx stay flat on the ground; tracers hit enemy feet | clicking an upright tower picks the ground cell under the cursor (the cell behind), i.e. the §1.3 upright-first picking is needed |
| (b2) 2D board on a 3D plane, tilt 45°, fov 50° | the only option that reads as a perspective view: a trapezoid board, far rows smaller, grid converging | at zoom 2 the beam, glow and tile lines stay sharp on the plane (no blur visible at 45°); 2D lights and fog render unchanged inside the SubViewport | figures are drawn on the root canvas at `unproject_position`, so they are **not darkened by night or lit by Light2D** (brighter than in a/c); auras and allies omitted; pan disabled; at zoom 1 the map is cut at the bottom and sides (camera fit by depth) |
| (c) flat logic, `CELL_Y = 0.75`, procedural angled art | 3/4 boxes and tall ellipses; depth reads well | the tile front strips turn the whole board into horizontal bands (visually noisy); 1.5-cell tower boxes hide the glyph of the tower behind (H is hidden in both shots) | no status markers on enemies; the angle is only implied by the art |

All three: picking round-trip (cell centre -> screen -> cell) 0 mismatches over 336 cells at
zoom 1. Not done vs the §2 specs: hex map, hover outline / debug dot, tilt sweep (30/45/60),
b2 supersampling study, interactive zoom keys (only the `--zoom` start value was exercised).

### 7.2 Frame rate and draw calls (relative, unfocused)

The FPS below is **not** an LT-62 measurement: the screen was locked, the window was never
focused (focused share 0.00 in every arm), and macOS throttles unfocused windows. The numbers
compare the arms with each other only roughly; they are not comparable with LT-62's
37-43 fps. Probe: bot build (rifleman x2, harpooner x6 per build phase), seed 4242,
2390x1344, 10 s warm-up + 90 s, two rounds (the second in reverse order), load1 < 25 before
each arm, same wave span in all arms.

| Arm | fps median (r1 / r2) | p10 (r1 / r2) | draw calls median |
|---|---|---|---|
| baseline | 18.5 / 18.0 | 16.7 / 16.0 | ~1950 |
| (a) | 19.3 / 18.8 | 16.8 / 17.0 | ~1950 |
| (b2) | 20.8 / 21.7 | 19.0 / 19.7 | ~1950 |
| (c) | 18.4 / 18.0 | 15.7 / 16.2 | ~2100 (+8 %) |

Reading: no option shows a cost against the baseline that clears this noise. Draw calls do
not depend on focus and are the one firm number: the 3D plane adds none, (c)'s front strips
add 8 %. (b2)'s higher fps must not be read as "faster": its figures skip lighting and it
draws no auras or allies. A focused re-measure by LT-62's method is a follow-up (§8.3) and
gates the view implementation.

### 7.3 Focused re-measure (LT-127)

Replaces §7.2's unfocused numbers. (An earlier run on a busy machine, load1 up to 68, lost
focus in three arms and is discarded; this is the re-run on a quiet machine.) Method as §7.2 /
LT-62 ("How it was measured"): bot build (rifleman x2, harpooner x6 per phase), seed 4242,
boot-fit window 2390x1344, 10 s warm-up + 90 s, `-- --mute`, two rounds (second reversed),
`caffeinate -d -i`, load1 < 10 before each arm (waits up to 30 min). The probe calls
`window_move_to_foreground()` at start and every 5 s while unfocused and records per-frame
focus. Wave span 1-3 in every arm. Focused share was 1.00 in every arm, so no retries.

| Arm | Round | Focused share | fps median | p10 | Draw calls median | Load1 before / after | time -p real / user / sys |
|---|---|---|---|---|---|---|---|
| baseline | 1 | 1.00 | 16.7 | 11.4 | 1951 | 9.2 / 8.8 | 110.0 / 43.5 / 26.4 |
| b2 | 1 | 1.00 | 16.4 | 11.9 | 1952 | 8.8 / 17.7 | 110.1 / 53.1 / 32.1 |
| a | 1 | 1.00 | 14.6 | 10.8 | 1948 | 9.8 / 16.1 | 108.4 / 52.6 / 31.4 |
| a | 2 | 1.00 | 15.7 | 10.7 | 1948 | 9.7 / 13.3 | 107.2 / 46.6 / 28.0 |
| b2 | 2 | 1.00 | 18.8 | 11.0 | 1947 | 8.4 / 20.7 | 107.0 / 45.1 / 28.3 |
| baseline | 2 | 1.00 | 17.7 | 12.2 | 1950 | 9.0 / 13.3 | 107.9 / 41.5 / 25.4 |

Machine state: load1 was gated below 10 at each start (waits 0-635 s) but climbed to 13-21
during several arms (other processes; the 5/15-min averages stayed high, 15-122 at the
starts). `user+sys` is ~70-85 s of ~108 s real, so the run is CPU-bound, not waiting. Noise is
about +-1.5 fps (baseline 16.7 / 17.7; b2 16.4 / 18.8). The focused fps (15-19) is still below
LT-62's 37-43 because the bot builds more towers by wave 3. Draw calls are the firm number:
~1950 in all arms, the 3D plane adds none.

Verdict: **b2 goes.** Mean of two rounds: baseline 17.2, b2 17.6, a 15.2 fps; p10 11.8 / 11.5 /
10.8. b2 costs nothing measurable against baseline; (a) is slightly lower (about 2 fps, near the
noise) so there is no case for falling back to (a). Caveat unchanged: b2's figures skip lighting
and draw no auras or allies, so its fps is not a claim that it is faster.

Web (LT-127/S3): the b2 view works in the web export (Godot 4.7.2 web template, gl_compatibility,
Chrome on ANGLE/Metal, Intel Iris Plus): the 3D plane in the SubViewport draws the trapezoid
board (`docs/design/LT-64/b2-web.png`) and the picking round-trip is 0 mismatches of 336 cells.
The HTML `args` config did not select the view; a throwaway proto patch (not committed) reads
`?view=b2` from `window.location.search` via `JavaScriptBridge` on web. Blocker for web play:
the in-game FPS label reads 1-3 for b2 against 7 for the flat game (same page, same session;
rAF ~3/s with the tab visible and focused), so b2 looks about 3x heavier than flat in the browser,
and both are far below desktop; the machine was busy (load1 48 at the end), so treat it as
indicative only. Web is not a target of the view decision; if it
becomes one, b2 needs a render-cost pass first (SubViewport size / `--ss`, plane resolution).

## 8. Recommendation: view (b2)

Owner's pick after the screenshots: (b2) (§6.1). This section says what (b2) needs to ship.

### 8.1 What (b2) needs to become shippable

| Gap seen in the prototype | Work | Cost |
|---|---|---|
| Figures not darkened by night, not lit by Light2D (brighter than the board) | draw the U layer (towers, enemies, crew, labels) inside the board SubViewport as a depth-sorted upright pass under the same `CanvasModulate` and lights, or give the root-canvas U layer the darkness colour and a light sample per figure; the first keeps one lighting model | medium |
| Auras and allies omitted | auras are G: draw them in the SubViewport (they then foreshorten with the plane); allies and leash: U figure + G ring/line, as in §1.2 | low |
| Pan disabled; map cut at the bottom and sides at zoom 1 | camera fit to the projected map bbox (near row sets the width), pan as a camera move along the ground plane clamped to that bbox (replaces `clamp_pan` over `world_rect_for`); zoom = camera distance with min/max; wheel/keys as today | medium |
| Upright click picks the cell behind | the §1.3 order: hit the drawn body first (screen rect), then ray-plane -> cell | low (in the coordinate-layer task) |
| Fx endpoints at feet, H lifts (shell, arc, LT-117 lift) | endpoints at `project(p, h)`; ground fx stay in the SubViewport | low-medium |
| Unmeasured: focused FPS, web export, SanityFx over 3D | focused re-measure (§8.3), one web-export smoke, `BackBufferCopy` check at sanity 0 | low (measure) |
| Far rows smaller | far-row tap target sets the minimum `CELL` and the tilt/fov; settle tilt (30-60°) and fov with a sweep | low |
| Text and thin lines on the plane at grazing angles | sharp at 45° zoom 2; if a lower tilt blurs, oversample the SubViewport or move text to the U layer | low, only if seen |

Benefit: the only option that reads as perspective; every G site keeps drawing in 2D inside
the SubViewport, so LT-110's ~60-site canvas transform is not needed; 2D lights, fog and the
light/shader layer of GDD §9a survive; zoom is natural (camera distance); no extra draw calls.
Risk: one full-resolution render target per frame (fill rate on Iris Plus and WebGL 2,
unmeasured focused); the lit U pass is the one new rendering piece; camera fit/pan is new
code with input edge cases; if the focused re-measure shows a real cost, the fallback is (a)
with the same coordinate layer.

Considered, not chosen:
- (a) oblique 2.5D: cheapest and Light2D verified, but reads as a squashed top-down map.
  Stays the fallback if (b2) fails the FPS or web check.
- (c) angle only in art: banded board, tall boxes hide the tower behind, most tile art, +8 %
  draws. Its 3/4 upright sprites remain a style option for (b2)'s U layer.

### 8.2 Order (coordinate layer -> view -> hex)

1. **Coordinate-layer split** (§1.3) first: pixel-identical at identity, so it lands without
   the view. Under (b2) `project` = `camera.unproject_position` of a ground point, `unproject` = the
   ray-plane hit, `depth` = camera distance; the G/U/H roles are the same.
2. **View (b2)**: the §8.1 work, after the focused re-measure shows no blocking cost.
3. **Hex look** after the view: per GDD §9a the style test runs in the running game, and tile
   art (per-hex terrain, Voronoi edges) must be drawn for the chosen view; Map v2's generated
   islands rule out the single painted harbour of §9a's MVP list, so the view precedes any
   tile art. Hex **logic** is not blocked by the view: LT-18's approved order (§11, decisions
   §13) starts with LT-108 hex registration and grey prototypes P1-P4 that are flat and
   exclude the angled view, so that track runs in parallel. The two meet at the Voronoi look
   (LT-18 §10 assigns "Voronoi look and angled view" to LT-64).

### 8.3 Follow-up tasks to create (not created by this slice)

| Proposed title | Scope |
|---|---|
| BoardView coordinate roles: project/unproject/depth/ring | §1.3: identity projection, G/U/H/S/P roles at every site of §1.2, one depth-sorted entity draw, upright-first picking, `ring` replacing ground `draw_arc`, guard extending G2; pixel-identical check as in LT-108 |
| Focused FPS re-measure of the LT-64 view prototypes | LT-62 method on `proto/LT-64-views` @3577952 with an unlocked, awake screen: baseline, b2 (and a as the fallback) at boot-fit, two rounds, load gate, `uptime` and `time -p`; plus one web-export smoke of b2; gate for the view task |
| Angled view (b2): board SubViewport on a zoom-only 3D camera | §8.1: plane + Camera3D, lit upright pass with auras and allies, camera fit, zoom and pan bounds, upright-first and ray-plane picking, fx endpoints and lifts, SanityFx check, tilt/fov sweep vs far-row tap target, hex tile check |
| LT-110 rewording | "Ground layers stay in 2D inside the (b2) board SubViewport": no canvas transform; close as superseded unless the (a) fallback is taken, then re-scope to "G sites under one transform, U/H through `project`" |

## 9. Open questions for the owner

**Q4. Range-ring look under the (b2) camera.**
1. **Ellipse on the ground (Recommended).** Benefit: shows exactly which tiles are in range
   (the sim measures on the ground); free under (b2), where rings are drawn on the plane.
   Risk: a flatter, less familiar shape; far-row rings are smaller on screen.
2. Screen circle around the tower's foot. Benefit: the familiar TD look, easy to read at a
   glance. Risk: lies about range: at 45° it overstates depth reach by ~40 %, so towers
   look able to hit cells they cannot; under (b2) it must move out of the SubViewport into
   a screen-space layer.
3. Ellipse plus highlighted in-range tiles. Benefit: unambiguous even on hex/Voronoi tiles.
   Risk: one more overlay to draw and tune; busier board during build.

**Q5. Hex before Map v2 or only with it** (the (b2) view is independent of the grid: hex
tiles are drawn in the SubViewport and foreshorten with the plane).
1. **Hex logic registered as LT-18's first step; the shipped harbour stays square until the
   Map v2 generator replaces it (Recommended).** Benefit: follows LT-18's approved order
   (LT-108 registration -> P1), no balance retune of a map that will be replaced, tests stay
   on the square fixture. Risk: no player-facing hex until Map v2 ships; plate marks and hex
   look get tested only in grey prototypes.
2. A hex version of today's harbour first. Benefit: hex range and balance tested early in
   the real game and lab. Risk: a balance pass and test-fixture work on a map Map v2 throws
   away; the tile look would be redone after the view.
3. Hex only together with the full Map v2. Benefit: one switch, one retune. Risk: the
   largest single change; hex picking, plate marks and the view meet for the first time at
   the end.

### 9.1 Owner decisions (2026-11-26)

- Q4: "Эллипс на земле (Recommended)": the range ring is a ground ellipse under the (b2) camera.
- Q5: "Логика гексов первым шагом LT-18 (Recommended)": hex logic is registered as LT-18's
  first step (LT-108); the harbour map stays square until Map v2.
- Note: "Утвердить, завести 4 задачи в бэклог (Recommended)": the §8.3 follow-ups go to the
  backlog as LT-126 (coordinate roles), LT-127 (focused FPS re-measure + web smoke),
  LT-128 (b2 view, depends on LT-126 and LT-127); LT-110 is reworded as the (a) fallback,
  gated on LT-127.
