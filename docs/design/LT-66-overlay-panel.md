# LT-66: side panel as an overlay, monster card, scrollable map

Status: design (LT-66/S1); owner answered Q1-Q5 and the revealed-fake question (§0a); the body
below follows those answers.
Owner request (2026-11-02): "тк у нас карта будет переделываться, я полагаю что можно сделать
боковое меню - оверлеем, которое показывается только если мы кликаем на башню (с инфой о башне)
или на монстра (инфа о монстре) или же в режиме дня - оно просто появляется, а карта становится
со скроллом". Follow-up: "засчет того что панель будет оверлеем - можно там добавить рендж для
башен, в таблицу".
Builds on: LT-35 (BoardView, LT-65 §3.3), LT-61 (build list in the panel), LT-113 (card fits
under the list), LT-84 (SelectionModel), LT-12 (fakes never tell), LT-78 (UI follows events).
Depends on LT-85 (`docs/design/LT-85-view-snapshot.md`, approved with the full snapshot, option
B): the monster card and every new read go through `game.snapshot`; LT-66/S2 starts after LT-85
is merged.
Fits ahead of LT-64 (angled view), LT-110 (one view transform) and LT-18 (Map v2); see §8.

## 0a. Owner decisions (2026-11-25, verbatim)

| # | Question | Owner's answer |
|---|---|---|
| Q1 | Overlay width | "304 px" (option B; names get 142 px) |
| Q2 | Day content with nothing selected | "Текст-подсказка, как сейчас (Recommended)" |
| Q3 | Dusk and close controls | "Скрывать в сумерки, закрывать по Esc или клику по пустому месту (Recommended)" |
| Q4 | Scroll input and zoom | "пункт 2, но давай про зум оставим заметку что будем делать потом зумирование" (option B: keys + right/middle drag + wheel/trackpad + edge pan; no zoom now; zoom later, §6.4) |
| Q5 | Pan when the overlay hides | "Плавно за 0.25 с" (ease back over 0.25 s) |
| LT-85 Q2 | Revealed fake on the monster card | "Да, как на карте (Recommended)" |

## 0. Today (measured from the code)

| Thing | Value | Where |
|---|---|---|
| Base viewport | 1200 x 675, `canvas_items` stretch, aspect keep | `project.godot` :13-18 |
| HUD bar | 0..48 px | `BoardView.ORIGIN.y` |
| Board (24 x 14 cells at 40 px) | x 0..960, y 48..608 | `BoardView.world_rect()` |
| Footer strip | y 608..675, full width (FPS, crew button, oil + flare at x 952) | `hud.gd` :106, :390 |
| Side panel | x 960..1200, y 48..675, **240 px**, inner 224 (margin 8) | `SidePanel.panel_rect` :63-69 |
| Build list columns | Name 110, $ 30+4, DPS 34, Trait 46 = 224 | `tower_picker.gd` :55-60 |
| Map columns 22-23 | water (`~`); lighthouse at column 21 (x 840..880) | `data/map.json` |
| Enemy body | 0.25 cells (10 px) radius; drawn position kept in `Board.last_pos` | `look_catalog.gd` :29, `entity_layer.gd` :283-347 |
| Board input | left click -> `cell_at_screen` -> `cell_clicked` / `outside_clicked` | `board.gd` :123-134 |

The task text says 192 px; the panel has been 240 px since LT-59. With today's map everything
right of x = 880 is water, so a 304 px overlay (from x 896) covers only sea. Scrolling is
small for today's map and becomes real with Map v2 (§8).

## 1. Overlay width and the Rng column (decided: 304 px)

The overlay keeps today's vertical extent (y 48..675, over the footer's right end), so the
LT-113 fit (tallest L1 card under a 10-row list, unscrolled) is untouched. Width
`SidePanel.PANEL_W = 304`, inner 288:

| Column | Name | $ | gap | DPS | gap | Rng | Trait | Sum |
|---|---|---|---|---|---|---|---|---|
| px | 142 | 30 | 4 | 34 | 4 | 28 | 46 | 288 |

Rng is `TowerText.range_text` of the L1 (`"3"`, `"3.5"`, `"2–7"` with a dead zone; ~22 px at
12 px). The 4 px gap after DPS has the same reason as `COST_GAP`: "15–45" and "2–7" must not
read as one number. Name is derived as `inner - (sum of the other columns)`, so it is not a
separate constant. Names gain 32 px over today; LT-113's whole-name pins only get easier.

```
304 px
+----------------------------------------------+
| Build here                               [x] |
| MUNDANE                $   DPS  Rng  Trait   |
| Rifleman             $60    12    3  -       |
| Harpooner            $90    20    4  Ground  |
| Coast Battery       $130 15–45  2–7  Blind 2 |
| OCCULT                                       |
| Elder Sign           $80     -  2.5  Res 2   |
+----------------------------------------------+
```

`panel_rect()` becomes `Rect2(base_w - PANEL_W, hud_h, PANEL_W, base_h - hud_h)` = (896, 48,
304, 627) and stops depending on the map.

## 2. When the overlay shows (decided: Q2 A, Q3 A)

The overlay is `SidePanel` itself: same node, same views (idle, picker + card, tower,
lighthouse, crew, and the new monster card), no longer bound to the board's right edge. It is a
Control on the UI layer with `MOUSE_FILTER_STOP`, so a click on it never reaches the board.

| Moment / input | Day (BUILD) | Night (WAVE) |
|---|---|---|
| Dawn (`BUILD_STARTED`) | overlay shows, idle text (as today) | - |
| Dusk (`WAVE_STARTED`) | - | all views close, overlay hides |
| Click a tower / the lighthouse | its card | overlay shows with its card |
| Click a monster (§4) | (no monsters by day) | overlay shows with the monster card |
| Click a buildable cell | build list | crew on: reserve-post list (today's LT-32 night picker); crew off: as empty |
| Click path / water / off the map | views close, idle text, overlay stays | views close, overlay hides |
| Esc | open view closes, idle text | open view closes, overlay hides |
| HUD crew button | crew view | overlay shows with the crew view |
| The shown monster dies, leaks or dissolves | - | card closes, overlay hides |
| The shown tower is sold / lifted away | idle (today) | overlay hides |
| Outcome | overlay hides (today) | overlay hides (today) |

Rule: **by day the overlay is always shown and "close" means idle; by night the overlay is
shown exactly while a view is open.** One function decides it, `SidePanel.sync_visible()`:
`visible = outcome == NONE and (phase == BUILD or any view open)`, with phase and outcome read
from `game.snapshot` (LT-85 option B bans `.state` in presentation). It is called from
`_update_idle` (every view's `visibility_changed` already lands there) and from the phase
events. Esc moves from `TowerPicker._input` to `SidePanel._input` and closes whichever view is
open. No "×" button and no toggle key (Q3 A).

## 3. Board placement under the overlay

The board stays left-anchored at x = 0 as today (pan 0). With the overlay hidden at night the
strip right of the map (x 960..1200) would show the clear colour; `MapLayer` therefore draws a
**sea backdrop** (`Board.COLOR_WATER`) over the whole play rect, below the tiles. Today's map
edges are water, so the board reads as open sea to the window edge, and panning past the map's
edge (the margin in §6) shows sea, not void. The backdrop is in the board's canvas, so the night
`CanvasModulate` darkens it like the water tiles.

Not chosen: centring the map when it fits (x 120..1080): by day the 304 px overlay would cover
184 px including land, so the player would pan every day.

## 4. Night click: monster vs tower

Picking order on a left click (Board `_unhandled_input`), in screen coordinates:

1. **Monster:** among the enemies drawn this frame (`Board.last_pos`, cell units, filled by
   `EntityLayer` from `EnemyRecord.position(alpha)` after LT-85), the one whose centre is
   nearest to the click within `PICK_RADIUS = max(look radius, 0.5)` cells (20 px; a body is
   10 px and a Deep One moves 64 px/s). Ties: lower id. Emits `enemy_clicked(id)`.
2. **Cell:** otherwise today's `cell_at_screen` -> `cell_clicked`, or `outside_clicked`.

Where a flyer is over a tower, the monster wins inside its 20 px and the tower is picked
anywhere else on its tile. The game is pausable (HUD pause), which is the answer for a fast
target.

Selection follows the monster: `SelectionModel` gains `enemy_id` (0 = none) written only through
a new `show_enemy(id)` (guard G7 extends to it); `OverlayLayer` draws the selection ring around
`last_pos[enemy_id]` each frame. The hit test uses only drawn positions and the look radius.

## 5. Monster card

```
+----------------------------------------------+
| Deep One                                     |
| Ground · comes in packs of 4–6               |
| HP       92 / 135                            |
| Speed    0.8 cells/s  (base 1.6)             |
| Armour   0   (base 0)                        |
| Leak     1 lighthouse HP                     |
| Drain    -        (Shoggoth: 2.5/s near towers)
| Traits   Pack 4–6                            |
| Now      slowed · vulnerable · lit           |
| Madness  faster, takes more damage           |  <- only while madness_buffed
+----------------------------------------------+
  revealed fake: title "Deep One (hallucination)", body as above (owner: "Да, как на карте")
```

Source: `game.snapshot.enemy(id) -> EnemyRecord` (LT-85 §3.1, §7). Field by field:

| Card line | `EnemyRecord` field | Note |
|---|---|---|
| title | `def.name`; suffix " (hallucination)" iff `revealed` | the same rule the board draws (LT-49) |
| Ground / Flying | `def.flying` | |
| pack line, Traits | `def.traits` keys and params | definition only; a trait that acts only on real enemies (tower lift) is shown from the def, never from its effect |
| HP | `hp`, `max_hp` | |
| Speed | `speed` (now), `base_speed` in "(base X)" | `base_speed` is wave-scaled, without per-tick modifiers (LT-85 §7) |
| Armour | `armor` (effective), `def.armor` in "(base X)" | |
| Leak | `def.leak_damage` | def value, not the outcome |
| Drain | `def.horror_drain` | def value, never "draining now" (fakes never drain) |
| Now | `markers`, `lit` | |
| Madness | `madness_buffed` | real and fake alike |

Never shown: anything not on the record (`is_fake`, `status`, `pack_of`, loot, targeting);
the record has none of them by shape (LT-85 D1, G16), so this is enforced by type, not by care.
`debug_is_fake_id` is not called by the card (the board's magenta outline stays the only debug
tell). Drops are left out.

Refresh: `game.snapshot` is rebuilt on frames with sim steps (LT-85 D3), so
`MonsterCard.on_stepped()` runs from `Game.advance` after that rebuild, beside
`hud.on_stepped()`, and rebuilds only when its shown key (rounded HP, speed, armour, markers,
lit, `madness_buffed`, `revealed`) changed. No `_process` in `ui/` (G6c). It closes on `DIED`,
`LEAKED` or `FAKE_DISSOLVED` for its id, or when `snapshot.enemy(id)` returns null. No adapter
model: LT-66/S2 starts after LT-85 is merged.

## 6. Scrollable map (camera pan)

### 6.1 Pan in BoardView

Pan lives in BoardView, the LT-35 coordinate layer that already holds the origin (guard G2):

- `var pan := Vector2.ZERO` (screen offset, base units); `origin()` returns `ORIGIN + pan`;
  `cell_at_screen` and `cell_to_screen` use `origin()`, so picking and drawing cannot disagree.
- `play_rect() -> Rect2`: the fixed screen frame the board may occupy (0,48 .. 1200,608). It
  does not move with the pan.
- `world_rect()`: the map's rect on screen *at the current pan* (as today at pan 0).
- `clamp_pan(p, visible: Rect2) -> Vector2` (pure) and `set_pan(p)`: stores and emits `panned`.
  `Board` moves its node to `view.origin()` on `panned`, so every layer, `Lighting` (a board
  child) and the sea backdrop follow with no per-layer change.
- Clamp, per axis, with `B = world_rect_for(grid)` (the map at pan 0), `M = B` grown by
  `PAN_MARGIN = 20` px and `V` = the visible rect (`play_rect` minus the overlay while it
  shows): if `B` fits in `V` the pan on that axis is 0 (today: vertical always, 560 = 560;
  horizontal at night); otherwise the pan keeps `M` covering `V` (`M.left + pan <= V.left`,
  `M.right + pan >= V.right`). Today by day (overlay from x 896): horizontal pan -84..+20 px.
- **Auto-reveal:** when a view opens for a cell or a monster under the overlay, the pan moves
  by the least amount that brings that cell (or the monster's position) inside `V`. The range
  ring is not chased.

### 6.2 Input (decided: Q4 B)

`scenes/board/board_camera.gd` (new, `RefCounted`, owned by `Board`) turns input into pan:

| Input | Effect | Arrives in |
|---|---|---|
| Arrows, WASD (held) | 640 px/s | `Board._unhandled_key_input` (press/release) + `tick` |
| Right- or middle-button drag | 1:1 with the mouse | `Board._unhandled_input` |
| Mouse wheel / Shift+wheel | 40 px (one cell) per notch, vertical / horizontal | `Board._unhandled_input` (over the overlay the GUI takes the wheel first, so the lists scroll) |
| Trackpad two-finger swipe (`InputEventPanGesture`) | both axes, delta x 40 px | `Board._unhandled_input` |
| **Edge pan** | 480 px/s after a 0.3 s dwell | `tick(delta, mouse_pos)` |
| Left click | never pans (select only) | |

**Edge pan zones (the risk named for option B, handled):** the zones are 16 px strips along
the inside edges of the **visible rect `V`**, not the window. While the overlay shows, the right
zone is the strip x 880..896 just left of the overlay, never the overlay itself; the cursor over
any Control (HUD bar, footer, overlay) never edge-pans, checked with
`get_viewport().gui_get_hovered_control() == null`. A zone pans only along an axis that has
travel (so today: left/right by day, nothing at night, never vertical). The 0.3 s dwell means
crossing the strip on the way to the build list does not pan; no edge pan while a mouse button
is held, while the window is unfocused, or while the cursor is outside the window.

`tick(delta, mouse_pos)` is called from `Board.tick_effects(delta)` (already once per frame from
`Game.advance`) with the viewport mouse position in base units. Both arguments are injectable,
so tests drive key pan, edge pan and the ease (§6.3) with fixed deltas and positions.

### 6.3 Ease back when the overlay hides (decided: Q5, 0.25 s)

When `V` changes (overlay shows or hides), the camera computes the clamped target
`clamp_pan(pan, V)`. If it differs from `pan`, it starts an ease: `_from = pan`, `_to = target`,
`_t = 0`; each `tick(delta)` advances `_t += delta / EASE_SECONDS` (0.25) and sets
`pan = _from.lerp(_to, smoothstep(0, 1, _t))`, ending exactly on `_to` at `_t >= 1`. Only
`tick`'s `delta` drives it (no `Tween`, no wall clock), so a test calls `tick(0.125)` twice and
reads exact values. Any user pan input during the ease cancels it and applies the clamp to the
new pan at once. Because `set_pan` moves `Board.position` on every step, picking stays exact
mid-ease. Opening the overlay (by day at dawn, or a night click) does not ease the map away:
the auto-reveal moves only as much as needed, instantly.

### 6.4 Later: zoom (after LT-110)

No zoom in LT-66 (owner: "про зум оставим заметку что будем делать потом зумирование").
Zoom is a scale in the view; today every layer turns cells into pixels itself (~97 call sites,
LT-96 S15), and line widths and fonts would scale case by case. After LT-110 the view is one
matrix and zoom is a scale in it: `screen = T(ORIGIN + pan) * S(zoom) * P * cells`. The wheel
is taken by pan here, so zoom will need Ctrl/Cmd+wheel and pinch (`InputEventMagnifyGesture`);
`clamp_pan` already works on the transformed map rect. A follow-up task should be filed after
LT-110 ("Map zoom: Ctrl/Cmd+wheel and pinch, 2-3 steps").

Consumers that mean "the screen frame", not "the map", switch from `world_rect()` to
`play_rect()`: the HUD bar height and footer top (`hud.gd` :94, :106), the frame-stats label
(:192), and `SanityFx`'s copy rect (:130, :145; fixed, so no recompute on pan). The HUD's
right-anchored items (oil + flare at :390, the sandbox label :203, the madness line :346-350)
anchor to `SidePanel.panel_rect().position.x - MARGIN` (x 888), so the overlay never covers them
and they never move. `RelicTokens` already uses `cell_to_screen`, so tokens follow the pan.

## 7. Picking under scroll

There is one input path to a cell (`cell_at_screen`) and one to a monster (`Board.last_pos` in
cells, compared after `view.screen_to_cells(p)`, a new inverse of `cell_to_screen` for points).
Both subtract `origin()`, the same value `Board.position` is set from, so a pan (or an ease
step) cannot make picking and drawing disagree. Tests pin the round trip over the clamp range.

## 8. Fit with LT-64 (angled view), LT-110 (view transform) and LT-18 (Map v2)

- **LT-64 / LT-110.** LT-110 turns the view into one matrix (projection) under which layers draw
  in cell units. Pan is a screen-space translation applied after it: `screen = T(ORIGIN + pan) *
  P * cells`; `cell_at_screen` inverts the whole matrix. The clamp works on the projected map's
  bounding rect, so it holds for an angled view without change. Zoom is a scale in the same
  matrix (§6.4). Monster picking compares in cells after the inverse, which an angled view keeps
  correct as long as the inverse is exact (for a perspective projection LT-64 must pick by
  ground plane).
- **LT-18 (Map v2).** A larger or island map only changes `grid.bounds()`; pan travel (and
  edge-pan reach) grow by themselves. The telegraphed route by day may later want "pan to the
  spawn" (a `set_pan` call); the hex grid already picks through `grid.cell_at`. With 304 px the
  overlay covers 7.6 columns' worth of a wider map's right edge by day; the pan covers it.

## 9. Behaviours tests must pin

1. At dawn the overlay is visible with the idle text; at `WAVE_STARTED` every view closes and it hides.
2. Night: a click on a tower opens the overlay with its tower card; Esc hides the overlay; a click on water hides it.
3. Day: Esc and a click on water close the open view, and the overlay stays visible with the idle text.
4. Night: a click within 0.5 cells of a drawn enemy opens its monster card (nearest of two wins); a click on the same tile 0.6 cells away opens the tower/cell instead.
5. The monster card closes and the night overlay hides when its enemy dies, leaks or dissolves.
6. A real and a fake enemy of one kind with equal records (except id) produce identical card text in every label; a revealed fake differs only by the " (hallucination)" title suffix.
7. The monster card's Speed/Armour lines show `speed`/`base_speed` and `armor`/`def.armor`, and the Madness line shows iff `madness_buffed`.
8. The build list has heads $ · DPS · Rng · Trait; each row's Rng equals `TowerText.range_text` of its L1; Name is 142 px; no horizontal scrollbar; LT-113's whole-name and card-fit pins still hold.
9. The overlay rect is (896, 48, 304, 627); a click on it never reaches the board.
10. For pans across the clamp range: `cell_at_screen(cell_to_screen(c)) == c` for every cell, `Board.position == view.origin()`, and a click at a cell's screen centre opens that cell.
11. Clamp: with the map fitting on an axis the pan is 0 there; otherwise the map plus margin always covers the visible rect.
12. Arrow/WASD, right/middle drag, wheel, Shift+wheel and a pan gesture each move the pan by the expected amount; a left click never pans.
13. Edge pan: the cursor in the 16 px strip left of the overlay pans right after 0.3 s and not before; the cursor over the overlay, the HUD or the footer never pans; no pan along an axis without travel.
14. Ease: hiding the overlay with pan -84 gives pan == the smoothstep midpoint after `tick(0.125)` and exactly 0 after a second `tick(0.125)`; user input mid-ease cancels it.
15. Opening a view for a cell or monster under the overlay pans it into the visible rect.
16. HUD flare, oil, madness and sandbox labels never intersect the overlay rect; SanityFx's copy rect equals `play_rect` at any pan.
17. The monster card's HP text follows damage on stepped frames, with no `_process` in `ui/` (G6c still green).

## 10. Suggested controls (revert the code, the named test must fail)

| # | Revert | Fails |
|---|---|---|
| C1 | Drop the hide on `WAVE_STARTED` in `SidePanel.sync_visible` | 1 |
| C2 | Route every click to `cell_at_screen` (remove the enemy hit test) | 4 |
| C3 | Card title ignores `revealed` | 6 |
| C4 | Remove the Rng head and cell from `TowerPicker` | 8 |
| C5 | `cell_at_screen` uses `ORIGIN` instead of `origin()` | 10 |
| C6 | Edge-pan zones on the window edges instead of `V` (so the overlay's area pans) | 13 |
| C7 | Ease jumps to the target at once (drop the lerp) | 14 |
| C8 | Monster card ignores `DIED` for its id | 5 |

C1-C4 and C8 land in the S2 test files; C5-C7 in the S3 ones; group by test binary. The
fake-equality of the record itself is pinned by LT-85's control 2, not repeated here.

## 11. Edit map and code slices

Line numbers are on `release-0.13.0` at 0c6f17b, **before LT-85**. LT-85/S3 rewrites
`game.gd`, `entity_layer.gd`, `overlay_layer.gd` and `tower_panel.gd` readers, so both slices
re-locate by function name after LT-85 merges.

### S2: overlay + monster card + Rng column (opus; after LT-85 is merged)

| File | Function (lines) | Change |
|---|---|---|
| `ui/side_panel.gd` | consts :12-18, `panel_rect` :63-69 | `PANEL_W = 304`; rect from the viewport only, no map arg (test callers updated) |
| | `_ready` :72-124 | add `MonsterCard` view; connect its `visibility_changed` |
| | `_update_idle` :186-192 | idle also hides under the monster card; call `sync_visible()` |
| | new `sync_visible`, `_input` | §2 rule from `game.snapshot` phase/outcome; Esc closes the open view |
| `ui/monster_card.gd` (new) | `open_for(id)`, `close`, `on_event`, `on_stepped`, `_rebuild` | §5; reads only `game.snapshot.enemy(id)` |
| `ui/tower_picker.gd` | consts :55-60, `HEADS` :77-84 | `DPS_GAP = 4`, `RNG_W = 28`; Name derived (142); Rng head, tooltip "Range in cells; 2–7 = can't fire within 2" |
| | `_row` :256-301 | Rng cell from `TowerText.range_text(s)` after DPS |
| | `_input` :510-513 | removed (SidePanel owns Esc) |
| `scenes/board.gd` | signals :35-36, `_unhandled_input` :123-134 | `enemy_clicked(id)`; §4 hit test first; new `enemy_at_screen(p)` |
| `scenes/board/board_view.gd` | new `screen_to_cells(p)` | inverse of `cell_to_screen` for points |
| `scenes/board/selection_model.gd` | :14-52 | `enemy_id`, `show_enemy(id)`; `clear` resets it |
| `scenes/board/overlay_layer.gd` | `_draw` :13-30 | ring around `board.last_pos[enemy_id]` |
| `scenes/game.gd` | `_ready` :68-112 | wire `enemy_clicked`; keep `monster_card` ref |
| | `advance` :144-166 | `side_panel.monster_card.on_stepped()` after the snapshot rebuild, beside `hud.on_stepped()` |
| | `_consume_events` :193-221 | forward events to the card; phase events -> `side_panel.sync_visible()` |
| | `close_panels` :232-237, `_on_cell_clicked` :246-255 | also close the card; new `_on_enemy_clicked(id)` |
| `ui/hud.gd` | :203-204, :346-350, :390 | right anchors at `SidePanel.panel_rect().position.x - MARGIN` |
| `tests/architecture_guard_test.gd` | G7 :151-166 | `show_enemy` covered by G7's write rule |
| tests to adapt | `side_panel_test` :111-126, `picker_overlay_test` :4, :112, :471, :520, `tower_picker_groups_test` :238, :405, :523 | `panel_rect()` signature; "never covers the board" becomes "inside the overlay rect"; inner width 288 |

Read only: `docs/design/LT-85-view-snapshot.md` §3.1, §3.4, §7 and the merged `sim/view/`
records; `entity_layer.gd` `_draw_enemies` (fills `last_pos`); `look_catalog.gd` :29,
`enemy_row`; `ui/text/tower_text.gd` `range_text` :216; `ui/tower_panel.gd` `open_for`/`close`
:129-149 (the pattern for the card); `docs/design/LT-12-hallucinations.md` §1.

### S3: camera pan, edge pan, ease, picking under scroll (opus)

| File | Function (lines) | Change |
|---|---|---|
| `scenes/board/board_view.gd` | :15-17, `origin` :33-34, `cell_at_screen` :38-42, `cell_to_screen` :51-52 | `pan`, `PAN_MARGIN`; both use `origin()` |
| | new `play_rect`, `clamp_pan`, `set_pan`, signal `panned` | §6.1 |
| `scenes/board/board_camera.gd` (new) | `input(event)`, `key_input(event)`, `tick(delta, mouse_pos)`, `set_visible_rect(v)`, `reveal(cells_pos)` | §6.2 inputs incl. edge pan zones in `V` with dwell; §6.3 ease; auto-reveal |
| `scenes/board.gd` | `_ready` :89-106, `_unhandled_input` :123-134, new `_unhandled_key_input`, `tick_effects` :161-165 | own the camera; follow `panned`; pass non-left mouse events and keys; `camera.tick(delta, mouse)` |
| | `MapLayer` :203+ | sea backdrop over `play_rect` (world coords) below the tiles |
| `scenes/game.gd` | `_on_cell_clicked` :246-255, `_on_enemy_clicked` (S2) | `board.camera.reveal(...)` after opening a view |
| `ui/side_panel.gd` | `sync_visible` (S2) | on a visibility change, `board.camera.set_visible_rect(V)` (starts the ease) |
| `ui/hud.gd` | `board_rect` :568-571 and users :94, :106, :192 | `play_rect()` |
| `scenes/sanity_fx.gd` | `board_rect` :130-131 | `play_rect()` |
| tests to adapt | `board_view_test` :142-160, :319-338; `scene_game_test` :159-161; `ui_polish_test` :67; `side_panel_test` :615-714 (`world_rect` anchors) | frame vs map rect; pan 0 keeps old values |
| `tests/architecture_guard_test.gd` | G2 :68-110 | rule unchanged (ORIGIN only in BoardView); add `play_rect`, `screen_to_cells` to the allowed-calls comment |

Read only: `scenes/lighting.gd` `setup`/`_ready` :64-106 (board child: follows the node);
`scenes/sanity_fx.gd` `_update_copy_rect` :140-148; `scenes/relic_tokens.gd` `board_to_layer`
:84-85.

Order: LT-85 merged -> S2 -> S3 (both touch `board.gd`, `game.gd`, `hud.gd`). Tests slice after
both, then verify with screenshots (day with the Rng column, night with the monster card, day
panned), every window with `-- --mute`.
