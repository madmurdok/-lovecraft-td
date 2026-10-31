# LT-33: sim / presentation boundary audit

Scope: `release-0.2.0` (main checkout), plus committed `sim/` and `data/` of
`feat/LT-23-occult-drain-difficulty` and `feat/LT-27-day-night-relics` (read with `git show` /
`git diff release-0.2.0...<branch>`; LT-27 `ui/` was not read, another agent is editing it).
Read-only; no code changed.

## Summary verdict

**The rules layer is already view-independent. A camera/view change needs no rules rewrite.**

- Every `sim/` script `extends RefCounted`. `sim/` has no Node, CanvasItem, Control, Viewport,
  Input, Camera, Color, Time/OS, signals, `preload`, or scene/ui class references (grep over
  `sim/`, release and both branches).
- All sim geometry is in **cell units**, on the grid plane, with Euclidean distances: ranges,
  aoe, pierce line, horror radius, route positions. `data/*.json` has only cells and seconds,
  no pixels. Seconds are turned into ticks inside the sim (`SimTime.ticks`, `units_per_tick`).
- Hits, misses, astray shots, targeting, costs, phases and outcome are all decided inside
  `Simulation.step()` or a command, at a tick. Shot animations (tracer travel, harpoon
  `_pass_times`) are cosmetic and never feed back.
- LT-27: a relic is credited **at a sim tick** (`arrive_tick = drop_tick + ticks(token_fly_seconds)`,
  `_settle_tokens` slot 6b; LT-27 `simulation.gd:706,717`), not by an animation callback.
  Day-only selling is gated in the sim (`_day_only`, LT-27 `simulation.gd:659`).

What breaks on a view change is **presentation only**: pixel picking and the pixel layout of the
HUD and side panel (both derived from `Board.CELL`). On top of that, a handful of contract leaks:
UI re-derives two rules, one private sim call from scenes, and `SimState` is open (including
`is_fake`) and protected only by convention plus a name grep.

Counts: **blocker 0, should-fix 7, fine 12.**

## Findings

| # | file:line | layer | what is coupled | why it matters for a camera/view change | severity | proposed fix |
|---|---|---|---|---|---|---|
| 1 | scenes/board.gd:95-108 (`_unhandled_input`, `cell_at`, `cell_origin`), :16 `CELL := 40.0` | scenes | Turning a screen position into a cell is `floori(local / CELL)` in Node2D local pixels | With an angled or 3D camera, picking becomes a ray/plane projection. This is the only input path into commands. | should-fix | Put a view interface in front of it, e.g. `View.cell_at_screen(pos) -> Vector2i` and `View.cell_to_world(cell)`, so `Game` gets cells only. The board stays the only owner of pixels. |
| 2 | ui/side_panel.gd:48-52 (`panel_rect` = `BOARD_ORIGIN.x + map.width * Board.CELL`); ui/hud.gd:27; scenes/game.gd:9,64 (`BOARD_ORIGIN`) | ui / scenes | UI layout is computed from the board's pixel size and origin | When the board is a perspective viewport, the panel and HUD geometry no longer follow from the grid width × 40 px | should-fix | The UI lays itself out from the viewport (anchors or containers). The world view fills what is left. Nothing in `ui/` names `Board.CELL`. |
| 3 | ui/hud.gd:67-68 (`call_wave_button.disabled = phase != BUILD or outcome != NONE`) | ui | The UI decides whether a command is available, using its own copy of the rule. The sim has no `can_call_wave()`. | Not a view issue as such, but it is rule logic in `ui/`. A new view has to copy it again, and the copy drifts (e.g. LT-27's day/night). | should-fix | Add `Simulation.can_call_wave() -> CommandResult` (the sim already enforces this in `call_wave`), and have the UI read it the way it reads `can_build` / `can_upgrade`. |
| 4 | ui/tower_panel.gd:169-172 `_drives_mad` (release); LT-23 ui/tower_info.gd:50 `drives_mad(st, delta)` | ui | The UI predicts the sanity rule "the cost takes the pool or cap to <= 0 -> MADNESS" | This is a rule re-derived outside the sim. LT-23 already had to rewrite it (pool -> cap). Every view or UI copy has to follow each rules change. | should-fix | Add a sim query such as `Simulation.would_start_madness(def_id / tower_id, branch) -> bool`, or put the predicted sanity state in the `can_*` result. The UI only reads it. |
| 5 | scenes/game.gd:43 `sim._add_sanity(forced - sim.state.sanity, "debug", 0)` | scenes | Scenes call a private sim method (debug `--sanity`) | It bypasses the command API and the command log, so a replay of `command_log` does not reproduce the debug run. Any new front end must copy this call. | should-fix | Add a public `Simulation.debug_set_sanity(v)` that is logged and emits the usual events, and call that. A guard (below) then bans `sim._` outside `sim/`. |
| 6 | sim/core/simulation.gd:32-34 (`state`, `config`, `events` public vars); sim/core/sim_state.gd:3 ("read-only" by comment); sim/core/sim_enemy.gd:14 `is_fake` public field | sim (contract) | The view reads the whole mutable `SimState`, including the hidden `is_fake` and, on LT-27, the private `_ghost_tokens` | A new 3D view, with models, shadows, animation and LOD, is exactly where a fake can leak or the state can get written. Today only a name grep (`render_isolation_test`) stops it. | should-fix | Keep the reads, but add the write/leak guard below. Longer term, give the view a read-only snapshot (`Simulation.view()` -> per-entity view records without `is_fake`), so the fake rule is enforced by the type, not by a grep. |
| 7 | LT-27 data/economy.json:11 `token_fly_seconds`; LT-27 sim/core/relic_token.gd:10 (`arrive_tick`, "flying to the HUD stash") | data / sim | The rule's credit delay is named and documented after a screen-space animation, a flight to the HUD | The sim side is correct: it is tick-based. The risk is the LT-27 view. If the token flight is a Tween with its own timer, it desyncs from the credit at x2, on pause, or when the HUD moves on a camera change. LT-27 `ui/` is unverified here. | should-fix | Rename or re-document it as a rule delay (`relic_credit_seconds`). Require the view to animate from `(tick + alpha - drop_tick) / (arrive_tick - drop_tick)`, never from its own timer. Check this in the LT-27 review. |
| 8 | scenes/lighting.gd:49-82,151 (`Board.CELL` px math for lights and fog) | scenes | Light radii and positions are in board pixels | They belong to the 2D view and get replaced with it. No rule reads them. | fine | Goes away with the view. Keep using cell-unit constants (`*_CELLS`) as the source. |
| 9 | scenes/lighting.gd:68-69 (`beam.rotation += BEAM_SPEED * delta`) | scenes | The beam turns on frame time, ignoring pause and x2 speed | Visual only today, so fine. LT-26 makes the beam a rule. Its design (`docs/design/LT-26-lighthouse-beam.md`) already puts the direction in sim ticks as unit vectors on the grid plane, with the render interpolating. | fine | Implement LT-26 as designed. Do not reuse the frame-time rotation as the rule. |
| 10 | sim/core/sim_clock.gd:21-30 (`MAX_STEPS_PER_FRAME = 8`, excess dropped) | sim | Real frame time -> step count | Below ~3.75 fps the game runs slower in wall time. Outcomes per tick are unchanged and commands are logged by tick. | fine | None. Optionally move `SimClock` to `scenes/` (it is a frame driver), but it is pure and tested. |
| 11 | sim/core/sim_route.gd:33-50, sim/core/simulation.gd:451-470, 725-757 (`_line_end`, `_line_hits`), sim/defs/map_def.gd:12 | sim | `Vector2` / `Vector2i` geometry, rows top-to-bottom (y grows down) | These are math types on the grid plane, not screen axes. y-down is only row order. Line and AoE tests are rotation-symmetric. | fine | Write the mapping into the view once: grid (x, y) -> world (x, 0, y), keeping handedness so LT-26's turn sign reads the same. |
| 12 | sim/core/simulation.gd:130 (flyers: `SimRoute.straight`, no altitude) | sim | Flyers are planar; the sim has no height | In an angled view a flyer is drawn above the ground. Its range and picking must stay at its ground projection. | fine | Altitude is visual-only in the view. If height ever matters, it becomes a sim field first. |
| 13 | sim/core/simulation.gd:480-483 `enemy_position(e, alpha)` | sim | A render-interpolation query lives in the sim | It is read-only, in cell units, and independent of the view | fine | None. |
| 14 | sim/core/simulation.gd:659-685 (hits decided and damage applied in the firing tick); scenes/board.gd:173-257 (`_shot_fx`, `_pass_times`, `astray_end`) | sim / scenes | The SHOT event carries `to` (cells), `hits`, `miss` and `astray`. The board only animates. | Hit and miss never depend on an animation, and nothing is credited "on landing" of a projectile | fine | None. |
| 15 | scenes/board.gd:88,161,287-328 (`_fx_rng`, `ward_alpha`, phantom path); LT-23 board.gd madness tint reads `sanity_fx.madness` | scenes | Presentation RNG and smoothing are read by the board only | No feedback into the sim (`_fx_rng` is never the sim's RNG) | fine | None. |
| 16 | scenes/game.gd:192-200 `_on_cell_clicked` | scenes | Chooses picker vs tower panel from `tower_at` / `is_buildable` | This routes the UI. The sim checks again (`can_build`, `tower_by_id`). | fine | None. It moves behind the view interface from #1. |
| 17 | sim/core/sim_enemy.gd:16 `revealed` (never set in `sim/`); scenes/board.gd:443 reads it | sim / scenes | A dead field the renderer reads | No effect today | fine | Remove it, or set it from the future Searchlight "Revealing" rule (GDD §111) in the sim. |
| 18 | ui/tower_info.gd:168-169 `_dps` = damage / fire_interval (seconds) | ui | Display math in seconds; the sim fires on `max(1, ticks(fire_interval))` | Display only. It can differ from the real rate for intervals that are not whole ticks. | fine | Optionally expose `Simulation.dps_of(level)` from ticks. |
| 19 | data/*.json (release, LT-23, LT-27) | data | Units: cells (`range`, `aoe_radius`, `pull_cells`, `drop_cells`, `horror_radius_cells`) and seconds | No px, no angles, no screen positions. Unknown keys are rejected by `ConfigReader.check_keys`. | fine | Keep the rule: no pixel keys in `data/`. |

### Sim <-> presentation coupling points (question 5)

Commands in, events out, read-only queries are the coupling **in practice**, with these exact points:

1. **Commands**, through `Game`, which forwards to the sim: `build_tower`, `sell_tower`,
   `upgrade_tower`, `set_target_priority`, `call_wave`, `buy_sanity`, plus LT-27 `sell_relics`.
   Each one validates itself (`can_*`, `OUTCOME_REACHED`, `_day_only`).
2. **Events**: `drain_events()` once per frame in `Game._consume_events` -> `board.on_event`,
   `sanity_fx.on_event`, end screen.
3. **Queries**: `can_*`, `upgrade_branches`, `upgrade_target`, `sell_refund`, `early_call_bonus`,
   `has_targeting`, `tower_by_id`, `enemy_by_id`, `enemy_position(alpha)`, `debug_is_fake`.
4. **Direct state reads** (wide): `sim.state.*` and `sim.config.*` from board, lighting,
   sanity_fx, hud, side panel and tower panel. These are not limited to queries (#6).
5. **Frame driver**: `Game._process -> SimClock.advance(delta) -> sim.step()`, and `clock.alpha()`
   for interpolation. Pause and speed live in `Game` and `SimClock`.
6. **Leaks outside the contract**: `game.gd:43` private `_add_sanity` (#5); `debug_reveal_fakes`
   set from `game.gd:38` (allowed, debug-gated, cannot change an outcome); rule copies in UI (#3, #4).

### What the existing guards enforce and miss (question 6)

Enforced:
- `tests/sim_determinism_test.gd:112` `test_no_sim_script_extends_node_or_uses_scene_tree`:
  no `sim/` script contains `extends Node` (this also catches Node2D/Node3D), `SceneTree`,
  `get_tree(`, `Time.`, `OS.`, or unseeded `randomize/randi/randf`.
- `tests/render_isolation_test.gd`: no script outside `sim/` and `tests/` names `is_fake`,
  `live_fakes_in_range`, `spawn_fake`, `_hallucinations` or `HallucinationSystem` (LT-27 adds
  `_ghost_tokens`, `GHOST_LOOT`). `debug_reveal_fakes` is assigned only behind
  `OS.is_debug_build()`. A Game started without the flag does not reveal.
- `tools/bot_runs.gd`: whole runs drive `Simulation` + `WaveDirector` directly, with no Game,
  Board or UI. This proves that every rule is reachable through the sim API.
- `tests/sim_clock_test.gd`: step count per real second is the same at any frame rate.

Missed:
- In `sim/`: `extends Control/CanvasItem/Resource`, `Color`, `Input`, `Viewport`, `Camera*`,
  `Engine.`, `ProjectSettings`, `Tween`, `signal`/`await`, `preload`/`load("res://scenes|ui|shaders")`,
  references to presentation class_names (`Board`, `Game`, `Hud`, `Lighting`, ...). All absent
  today, but no guard keeps them out.
- Presentation calling sim internals (`sim._*`; `game.gd:43` would fail such a check today), or
  writing `sim.state.* =` / `+=`.
- Rules copied into `ui/` (#3, #4). A grep cannot catch these. A query-first convention plus review is needed.
- No proof that the sim runs **without a SceneTree**: gdUnit and `bot_runs.gd` (`extends SceneTree`)
  both run inside one.
- No equivalence check between the frame-driven path (`Game.advance` with uneven deltas, pause,
  x2) and the bot path. This is the check that would catch frame-rate dependence or UI-only gating.
- Data: no check against pixel or screen keys beyond `check_keys`. That is enough while every key
  is declared in a `FIELDS` list.

## Boundary rule

`sim/` and `data/` are the game. They know cells, ticks and seeds, and nothing about pixels,
seconds of animation, screens, cameras, input devices, colours or the scene tree. Every `sim/`
script extends `RefCounted` and references only engine value and container types plus other
`sim/` classes. Presentation (`scenes/`, `ui/`, any future 3D view) talks to the sim only through
commands (`Simulation` public methods that validate themselves and are logged), drained events,
and read-only queries. It never calls `_`-prefixed members, never writes `state`, and never
decides whether an action is allowed or what it will cause: when the UI needs to know,
the sim gets a `can_*` / prediction query. All screen math (cell <-> pixel or world, picking,
layout, animation timing) lives in the view, and an animation that shows a rule's timing is
driven by the sim's ticks (`tick + alpha`), never by its own timer.

## Proposed automated guard

New file `tests/sim_boundary_test.gd` (gdUnit, same scan helpers as `render_isolation_test`):

1. **Allowlist of types in `sim/`.** Collect every `class_name` declared under `sim/` (the own
   classes). Strip comments and strings. Then every PascalCase identifier in `sim/*.gd` must be
   either an own class or in a fixed engine allowlist: `RefCounted, Vector2, Vector2i, Array,
   Dictionary, String, StringName, Callable, RandomNumberGenerator, PackedStringArray,
   PackedInt64Array, PackedByteArray, PackedFloat32Array, FileAccess, DirAccess, JSON, RegEx`
   (compute the actual list from today's code once and pin it). Anything else fails with
   `file:line`. That catches Color, Node*, Control, Input, Camera*, Viewport, Tween, Engine,
   ProjectSettings, Board, Game, Hud, and every future engine type, without having to name them.
2. **Forbidden tokens in `sim/`**: `\bsignal\b`, `\bawait\b`, `\bpreload\(`,
   `load\("res://(scenes|ui|shaders|assets)`, `func _(process|physics_process|input|unhandled_input|ready|draw)\b`,
   `get_node\(`, `\$[A-Za-z]`.
3. **Presentation side** (`scenes/`, `ui/`, `tools/`): no `\bsim\._\w+` and no
   `\.state\.\w+\s*(=(?!=)|\+=|-=)` or `\.config\.\w+\s*=(?!=)`. Fails today on
   `scenes/game.gd:43`, so fix #5 first.
4. **No SceneTree needed**: `tools/sim_no_tree.gd` `extends MainLoop` (not SceneTree). It runs
   one seeded bot strategy for a whole game through `Simulation` only and prints a state hash
   (tick, gold, sanity, lighthouse_hp, outcome, `command_log` size). Run it from the test runner
   with `godot --headless --script` and compare the hash with the same run inside gdUnit.
   (Check feasibility: `class_name` globals load under a custom MainLoop in Godot 4.)
5. **Frame-path equivalence** (catches frame-rate dependence and UI-only gating): drive a `Game`
   (`setup` + `_ready`, no window) with uneven deltas (1/144, 1/30, 0.2, jitter from a fixed
   seed), pause/resume and x2. Issue a fixed command list through `Game.build/upgrade/call_wave`
   at fixed ticks. In a second run, drive the same commands on a bare `Simulation` with
   `step()`. Assert identical `command_log`, final state and event sequence. Control: make
   `Game.advance` call `sim.step()` once extra on a long frame, and the test must fail.

Items 1 to 3 are cheap static scans in the existing test run. Items 4 and 5 are runtime proofs,
one test each.
