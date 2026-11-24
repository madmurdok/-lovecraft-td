# LT-117: night-gaunt `tower_lift` trait

Status: design (S1). Base: `release-0.11.0` at `6bff0be`. No production code here.
Spec: GDD §7 enemy table ("from wave 6 on it may lift a tower and drop it 2 cells away
(disabled 3 s)"); LT-4 §"Night-gaunt" (`docs/design/LT-4-sim-core.md:274`); LT-106 trait hooks
(`docs/design/LT-106-trait-hooks.md`); LT-105 tower modifier channel; LT-72 ten waves.
Acceptance: `tower_lift` works from wave 6 per its data; a lab table (wins, wave reached, losses
per wave) with and without it in the playtest doc; the owner decides any re-tune.

## 0. Today (facts this note relies on)

- Data: `data/enemies.json:30` `night_gaunt.traits.tower_lift = {from_wave: 6, drop_cells: 2,
  disable_seconds: 3}`; gaunt `flying: true`, speed 1.3, hp 165. The frozen copy
  `tests/fixtures/golden_data/enemies.json:30` carries the same entry.
- `sim/core/traits/tower_lift_trait.gd` (1-15): schema only, `pending() == true`, no hook.
  It is in `TraitCatalog._rows()` (`trait_catalog.gd:17`), so it is in `pending_ids()`
  (pinned by `tests/trait_hooks_test.gd:283-284`).
- **No implemented tower-targeting trait exists.** `tower_harass_trait.gd` is pending too
  (schema only; its header says the content task "wires near_tower + host.modify_tower").
  The patterns to copy are therefore: `pack_trait.gd:43-51` (a hook that draws through
  `host.randi_range`) and `LightSystem.update_beam` (the first channel writer of slot 2).
- Hooks: `EnemyTrait.NEAR_TOWER` (`enemy_trait.gd:18`, doc 76-79): "slot 2, after the light
  writer and before apply_auras; writes towers only through host.modify_tower". Dispatched by
  `TraitSystem.near_tower` (`trait_system.gd:23-34`), called from `Simulation.step`
  (`simulation.gd:91`), live enemies in id order, catalog order within an enemy. A pass returns
  at once unless some def in the config carries the bit (`_any`).
- Tower channel: `SimTower.disabled` (`sim_tower.gd:51`) = "no shot, cast or aura; the cooldown
  keeps counting"; reset every tick (`reset_modifiers`, 62-68); "No timers here: a timed effect
  keeps its timer with its owner and rewrites the channel every tick while active" (40-46).
  Only writers: `light_system.gd`, `trait_host.gd` (guard G12, `architecture_guard_test.gd:987`).
- Moving a tower: `state.tower_at` has one writer, `core/simulation.gd`
  (`architecture_guard_test.gd:596`, G4b). `SimTower.pos` says "set once when built (towers
  never move)" (`sim_tower.gd:15`). Traits see the sim only through `TraitHost` (G4a also covers
  `sim/core/traits/`, `architecture_guard_test.gd:546`).
- Grid: `GridTopology.steps(a, b)` (`grid_topology.gd:30`) is the topology's step count:
  Manhattan on the shipped square grid (`square_grid.gd:44-45`), hex steps on `HexGrid`
  (`hex_grid.gd:56-60`, not registered in `GridFactory` yet). `cell_at(p)` (38),
  `MapDef.is_buildable` (`map_def.gd:150`, out-of-bounds reads as water, the lighthouse is a
  path cell).
- Flight: a flyer's route is `SimRoute.straight(grid, map.spawn, map.lighthouse)`
  (`spawn_system.gd:121-122`). On the shipped map (24x14, S (0,1), L (21,10)) the line crosses 28
  cells, **18 of them buildable** (computed from `data/map.json`: (1,2) (2,2) (3,2) (4,3) (6,3)
  (6,4) (7,4) (8,4) (11,6) (13,6) (13,7) (14,7) (15,7) (15,8) (16,8) (17,8) (19,9) (20,9)).
- Waves (`data/waves.json`): gaunts in waves 4, 5, 7 (8), 8 (22), 9 (10), 10 (16). **Wave 6 has
  no gaunts**, so `from_wave: 6` first bites in wave 7: 56 gaunts can lift in waves 7-10.
- Golden data (`tests/fixtures/golden_data/waves.json`) has 5 waves: the trait never activates
  there (§3).
- Disable time: `SimTime.ticks(3)` = 3 x `TICK_RATE` (30, `sim_time.gd:25`) = 90 ticks.

## 1. Semantics

Recommended rule in one paragraph: a real night-gaunt, from wave `from_wave` on, lifts **once**
the first tower it flies over (the tower on the cell under the gaunt's position) that is not
already lifted; the tower lands on a free buildable cell exactly `drop_cells` steps away, drawn
uniformly on a new seeded stream `LIFT`; it is disabled for `disable_seconds` from the lift tick;
the gaunt flies on unchanged.

### Q1. Which tower, how often

| option | rule | benefit | risk |
|---|---|---|---|
| **A (recommended)** | Over a tower: `cell_at(gaunt position)` holds a tower (`tower_at`) whose lift timer is 0. Once per gaunt (`e.status["tower_lift_done"]`). | No new constant or data key; topology-agnostic; the flight line is fixed and visible, so the player can plan around it (counterplay). | Strength depends on map geometry (18 buildable cells under today's line); bots that build under the line get hit hard. |
| B | Nearest tower within a reach radius (new `reach_cells` param), once per gaunt; ties lower tower id. | Hits regardless of exact line; tunable. | New data key and validation; more lifts, harsher; less readable for the player. |
| C | A, but every tower it passes (no once-per-gaunt). | Strongest "swarm" feel. | 22 gaunts in wave 8 could chain-lift the whole line; hard to balance. |

A tower whose lift timer is running cannot be lifted again (no juggling); the gaunt keeps its
one lift for the next tower on its line.

### Q2. Where it drops (`drop_cells`)

`drop_cells` = `GridTopology.steps(from, to)`, so it means "N moves on this grid" on square
(Manhattan) and hex alike. A candidate cell `c` must be: `grid.contains(c)`,
`map.is_buildable(c)` (so never path, lighthouse, water or off the board), not in `tower_at`,
and not the tower's own cell. Candidates are enumerated in `grid.cells()` order (row-major on
the square grid) so the draw is reproducible.

| option | pick among the ring | benefit | risk |
|---|---|---|---|
| **A (recommended)** | Uniform draw, `host.randi_range(e, SimRng.Stream.LIFT, 0, n - 1)`, on a **new stream appended** to `SimRng.Stream`. | Matches GDD/LT-4 ("drop it 2 cells away", "rolling the drop cell"); no drift artefact; existing streams keep their seeds, so a lift never reshuffles pack sizes, misses or loot. | The player cannot predict the cell; tests must seed or pin a one-candidate board. |
| B | Deterministic "carried forward": the candidate closest to `from_centre + heading * drop_cells` (heading = spawn -> lighthouse), ties lower `grid.index`. | No RNG at all; predictable. | Lands on the flight line again, so the next gaunt carries it on: a conveyor toward the lighthouse. |
| C | Draw on `SPAWN` (LT-4's original wording). | No new stream. | Every lift shifts later pack-size draws: the lab A/B arms would differ in more than the lift. |

### Q3. No free cell at `drop_cells`

| option | rule | benefit | risk |
|---|---|---|---|
| **A (recommended)** | Try rings `drop_cells, drop_cells-1, ..., 1`; none free: the tower stays on its cell and is still disabled (event `to == from`). | Never farther than the data says; the lift always "costs" the player the disable. | A boxed-in tower is "shaken" rather than moved (a small rules wrinkle to explain). |
| B | Rings outward (`drop_cells+1`, ...). | Always moves. | Can fling a tower far away on a crowded board. |
| C | No free cell: no lift at all, gaunt keeps its lift. | Simplest. | Packing towers becomes an unintended immunity. |

### Q4. `disable_seconds` and the timer's owner

Recommended: the timer lives on the **tower** (new `SimTower.lift_ticks_left: int`), set to
`SimTime.ticks(disable_seconds)` at the lift; a tower pass in `TraitSystem.near_tower`, after
the enemy loop, calls `host.modify_tower(t, 1.0, 1.0, 0.0, false, true)` and decrements for
every tower with `lift_ticks_left > 0`. The lift tick counts as tick 1, so the tower is disabled
for exactly 90 ticks. The gaunt's death does not end it (GDD: "disabled 3 s").
Benefit: independent of the gaunt's fate; the channel rule ("timer with its owner, rewrite every
tick") holds with the tower as owner. Risk: one new tower field (not in any digest; keep it out of
`SimNoTreeLoop.digest` and the trace final line).
Alternative: timer in the gaunt's `e.status`, rewritten by its own `near_tower` (only live enemies
run hooks) — killing the gaunt frees the tower early. Benefit: rewards killing gaunts; no tower
field. Risk: a 3 s debuff that may last 1 tick; harder to read.

### What moves and what stays

- Moves: `t.cell`, `t.pos = grid.centre(new)`, `state.tower_at` (erase old, set new), all in one
  facade method `Simulation._lift_tower` (the only `tower_at` writer). Range, light cover,
  shadow, auras and targeting all read `t.cell` / `t.centre()` each tick, so they follow.
- Unchanged: `id`, `def`, `level`, `branch`, `spent` (sell refund), `build_tick`,
  `target_priority`, `burst_index`, `cooldown_ticks` (keeps counting while disabled),
  sanity reserve (the tower still exists; no `SANITY_CAP_CHANGED`).
- `locked_id`: unchanged; `CombatSystem` already drops a lock that is not among the candidates
  (`combat_system.gd:453-462`).
- `lit` / `shadowed`: recomputed by the next tick's `update_beam` (slot 2 runs light before
  traits), so a one-tick lag, invisible because the tower is disabled anyway.
- Allies of a moved Summoning Circle keep their `home`/leash at the old spot until they expire
  (recommended: no change; allies are lifetime-bound). Alternative: re-home them (an
  `AllySystem` write from the facade; more code, more golden surface).
- The gaunt: flies on, speed and route unchanged; it is not "carrying" anything after the tick.
- Fakes (LT-12): **a fake gaunt never lifts** (recommended). Benefit: hallucinations never move
  real towers or real streams (LT-12 rule for streams). Risk: none in the data; a visual-only fake
  lift is possible later.
- Phase: gaunts exist only at night, so lifts never meet build/sell (day-only commands).
- Wave gate: `host.wave()` (= `state.wave_index`) `< from_wave` returns before any read, draw or
  event.
- Param validation: override `parse_params` so `from_wave` and `drop_cells` are integers >= 1 and
  `disable_seconds` a number >= one tick (same shape as `pack_trait.gd`'s `spacing_s` check).

### Event

Append `TOWER_LIFTED` to `SimEvent.Type` (after `ALLY_GONE`, `sim_event.gd:28`; appended so old
values keep their ints): id = the tower, data `{from, to, by (gaunt id), ticks}`. Emitted by
`Simulation._lift_tower`. The UI and the bot counter read it.

## 2. Crew interaction (LT-32, assumed)

**Assumed, to be confirmed against `docs/design/LT-32-crew.md` when it lands:** the tower moves
with its crew as one unit. The crew stays attached to the tower id; nothing returns to the
reserve, nothing is re-posted. `Simulation.step`'s slot-2 comment already reserves the crew
writer slot after the traits ("[LT-32 crew posts]", `simulation.gd:84-86`); a crew writer that
reads `t.cell` per tick follows the move for free. If LT-32 ties crew to cells rather than tower
ids, `_lift_tower` is the one place to move them.

**Posts (LT-32 Q3b, owner decision (a)):** a night post (`t.post`) is never a lift target;
`TowerLiftTrait.near_tower` returns before marking the gaunt DONE, so it keeps its lift.

## 3. Determinism

- RNG: only `host.randi_range(e, SimRng.Stream.LIFT, ...)` (seeded sim RNG; G4a bans
  `RandomNumberGenerator.new` in traits). `LIFT` is appended to `SimRng.Stream`
  (`sim_rng.gd:11`), so existing streams keep their seeds (`STREAM_SEED_STRIDE` 16 leaves room).
  Fakes never reach the draw (they never lift), so `SANITY` is untouched. One
  `randi_range(0, n-1)` call per lift whenever the chosen ring has n >= 1 candidates; with
  n == 1 Godot's `randi_range(0, 0)` leaves the stream state unchanged (probed on 4.7.2, LT-117
  review), which is still deterministic across platforms and replays.
- Tick order: slot 2, `near_tower` pass: light (update_beam) -> enemy traits in enemy id order
  (the lift) -> tower lift-timer pass (disable writes) -> [LT-32 crew] -> `apply_auras`. Two
  gaunts lifting in one tick: the lower id goes first, the second sees the updated `tower_at`.
- Replay: lifts are sim-internal (no command), so replays of command logs reproduce them.
- Goldens: `golden_data` has 5 waves and `wave_index` never reaches 6, so with the gate first the
  trait reads nothing, draws nothing, emits nothing. `_any` gains `NEAR_TOWER` in golden runs
  (the gaunt def now has the bit), which runs the dispatch loop and the (empty) tower pass but
  changes no output: **every golden event stream is unchanged** (`events_sha`, `buckets`, trace
  event lines).
- **But a new stream changes the golden final lines.** `GoldenRuns` writes every stream state in
  `SimRng.Stream.values()` order into the digest final text (`tests/golden_runs.gd:271-272`) and the
  trace final line (`:247-249`). Appending `LIFT` (Q2-A) adds an 8th never-drawn state, so
  `final` / `final_sha` and each trace's last line change while all events stay identical.
  Q8 (owner): (a, recommended) approve a regen limited to that: `scripts/golden-regen.sh` in the
  same commit as the stream, and the verify slice checks that `events`, `events_sha`, `buckets` and
  every trace line except `final` are unchanged (README: "a new mechanic" is a valid regen
  reason). (b) No regen: draw on an existing stream (Q2-C, `SPAWN`), goldens byte-identical, but
  lifts shift later pack sizes in the lab's "on" arm.
- Frozen fixtures: none has a wave >= 6 with gaunts (`tests/fixtures/*`). Tests that run full
  bot games on `res://data` (`sim_boundary_test.gd:971-1054`, `bot_upgrade_test.gd`) compare a
  run with its own replay, not pinned numbers, so they stay green with lifts on.
- Pins that must change: `trait_hooks_test.gd:283-284` (`pending_ids` loses `tower_lift`).
  `enemy_traits_test.gd:63-90` turns green by itself (hooks != 0 counts as read).

## 4. Presentation (minimum)

- Lift visual: on `TOWER_LIFTED`, `fx_layer.on_event` (`fx_layer.gd:94-133`) adds a short
  "lift" effect (an arc from the old to the new cell centre, ~0.5 s, reusing `_arc_point` /
  `_arc_lift`, 639-655) and calls `_drop_beam(id)` (229-232; a Resonator beam stores its origin).
- Disabled look: `EntityLayer.plate_color` / `state_border` (`entity_layer.gd:110-138`) get a
  dim tint when `t.disabled` (the channel's last-tick value). Generic: tower_harass will reuse
  it. LT-104 keeps status marks keyed by sim state, not by look, so no look-catalog row.
- Tower light: `lighting.gd:_sync_tower_lights` (203-219) caches `position` at creation; update
  it on `TOWER_LIFTED` (or reposition on every sync).
- Selection: `tower_panel.gd` opens by tower id and sets the selection cell (`:123`); on
  `TOWER_LIFTED` for the open tower, set the cell again (that file is already a G7 selection
  writer) and refresh `G_TABLE` (`REFRESH_ON`, 29-41). The panel's text shows "disabled" already
  (`tower_text.gd:271-279`).
- Text: there is no enemy card in the UI today (no enemy card, bestiary or wave preview under
  `ui/` or `scenes/`). GDD §7 row: replace "may lift" with the rule: "From wave 6, lifts the first
  tower it flies over and drops it 2 cells away; the tower is off for 3 s." LT-37 short text for
  a future card: `Lift: tower 2 cells away, off 3 s` (numbers from params).

## 5. Counterplay

Keep key towers off the straight spawn -> lighthouse flight line (it never changes).
Kill gaunts early with anti-air near the docks, and spread coverage so one tower off for 3 s
opens no hole.

## 6. Edit map

Change:

| file | lines | change |
|---|---|---|
| `sim/core/traits/tower_lift_trait.gd` | 1-15 | `pending()` false; `hooks()` = `NEAR_TOWER`; `parse_params` (ints >= 1); `near_tower`: fake / done / wave gates, tower under the gaunt, ring candidates, draw, `host.lift_tower` |
| `sim/core/traits/trait_host.gd` | 8-15, append after 39 | reads: `wave()`, `tower_under(e)`, `drop_candidates(t, steps)` (or `grid()` + `is_free_buildable(c)`); write: `lift_tower(t, to, ticks, by)` via a Callable to the facade (like `queue_pack_member`) |
| `sim/core/systems/trait_system.gd` | 23-34 | after the enemy loop: tower lift-timer pass (`modify_tower` off, decrement) |
| `sim/core/simulation.gd` | 53 (host ctor), new `_lift_tower` near `sell_tower` 212-229 | move `cell`/`pos`/`tower_at`, set `lift_ticks_left`, emit `TOWER_LIFTED`; update the slot-2 comment 80-86 |
| `sim/core/sim_tower.gd` | 15, after 51 | fix "towers never move"; add `lift_ticks_left` (a timer field, not part of the channel) |
| `sim/core/sim_rng.gd` | 11 | append `LIFT` (Q2-A only) |
| `tests/fixtures/golden_digests.json`, `golden_trace/` | regenerated | final lines only (Q8-a) |
| `sim/core/sim_event.gd` | 22-28 | append `TOWER_LIFTED` with its doc comment |
| `scenes/board/fx_layer.gd` | 94-133, 229-232, 639-655 | lift arc fx; drop beam |
| `scenes/board/entity_layer.gd` | 110-138 | disabled tint |
| `scenes/lighting.gd` | 203-219 | move tower light |
| `ui/tower_panel.gd` | 29-41, 117-125, 144 | follow the lifted tower; refresh |
| `tools/bot_runs.gd` | 51-60 (header), 274-297 | RUN line field `lifts` (count of drained `TOWER_LIFTED`) |
| `tools/balance/variants/lt117_lift_off.json` | new | `from_wave: 11` for night_gaunt (no lift in 10 waves) |
| `docs/GDD.md` | 197 | rule text (§4) |
| `docs/design/LT-4-sim-core.md` | 274 | point to this note; stream is `LIFT`, not `SPAWN` |
| `tests/trait_hooks_test.gd` | 280-284 | pending ids without `tower_lift` |

Read for context (no change expected): `enemy_trait.gd` 1-79; `pack_trait.gd` 35-51;
`enemy_def.gd` 26-36, 90-100 (hook_traits build); `sim_context.gd` 25-37; `grid_topology.gd`
14-56; `square_grid.gd` 26-45; `map_def.gd` 143-151; `spawn_system.gd` 121-122; `sim_route.gd`
29-35; `combat_system.gd` 188, 447-462 (t.cell readers, lock check); `architecture_guard_test.gd`
546-600 (G4), 975-1072 (G12); `tests/enemy_traits_test.gd` 20-90; `tests/golden_runs.gd` (final
line, stream list).

Call sites relied on (grep; GDScript is not indexed by g-mesh): `TraitSystem.near_tower` called
only at `simulation.gd:91`; `TraitHost.new` only at `simulation.gd:53`; `tower_at` writes only in
`simulation.gd` (`build_tower` 187, `sell_tower` 220); `add_modifiers` callers `light_system.gd`
and `trait_host.gd` (G12 list); `tower_lift` string: `enemies.json:30`, golden copy `:30`,
`trait_catalog.gd:17` (class), `trait_hooks_test.gd:282-284`; `t.cell` readers in UI:
`entity_layer.gd:148-156`, `overlay_layer.gd:38-61`, `lighting.gd:214`, `tower_panel.gd:123`;
`tower_at` read by the bot: `bot_placement.gd:35`.

## 7. Behaviours the tests must pin

1. A real gaunt over a tower in wave >= `from_wave` moves it to a free buildable cell at exactly `drop_cells` steps.
2. Below `from_wave`: no move, no `TOWER_LIFTED`, and the `LIFT` stream state is unchanged.
3. A fake gaunt never lifts (and draws nothing).
4. One lift per gaunt: a gaunt that lifted passes over a second tower without lifting it.
5. A tower with a running lift timer is not lifted again; the gaunt lifts the next tower instead.
6. Drop cell is never path, lighthouse, water, off-board, occupied or the own cell.
7. Ring fallback: no free cell at `drop_cells` -> nearest smaller ring; none -> stays, still disabled, `to == from`.
8. Disabled for exactly `SimTime.ticks(disable_seconds)` ticks from the lift tick: no shot, cast or aura; cooldown keeps counting.
9. The gaunt dying does not end the disable.
10. Level, branch, `spent`, target priority and sanity cap unchanged; sell refund unchanged.
11. `tower_at` and `t.pos` agree with `t.cell` after a lift; ranges are measured from the new cell.
12. Two lifts in one tick resolve in gaunt id order against the updated board.
13. Same seed, same lifts (two runs byte-identical); replaying the command log reproduces them.
14. `TOWER_LIFTED` data `{from, to, by, ticks}`.
15. Golden events unchanged (5-wave golden data): `events_sha`, `buckets`, trace event lines; only the final lines change with Q8-a, nothing with Q8-b.
16. Hex topology: `drop_cells` uses hex steps (a `HexGrid` board in the test).
17. Param validation: non-integer or 0 `drop_cells` / `from_wave` rejected with the param path.

Controls (revert the fix, the test must fail): gate removed (2), fake check removed (3),
once-per-gaunt flag removed (4), timer guard removed (5), timer pass removed (8), ring filter
without `is_buildable` (6).

## 8. Lab plan

- Arms: `baseline` (shipped 10 waves, lift on after implementation) vs `lt117_lift_off`
  (`from_wave: 11`, never active in 10 waves). 20 seeds (1000..1019), all strategies:
  `python3 tools/balance/balance.py baseline lt117_lift_off` (run `godot --headless --import
  --path .` once in a fresh worktree first).
- Report from the existing tables: wins/losses, "where runs end" (losses per wave 1..10 and mean
  waves survived, `balance.py` `waves_table`), lighthouse HP left (`hp_table`; does not
  saturate), plus mean `lifts` per run per strategy from the new RUN field.
- Control that tells the arms apart: `lifts` > 0 in `baseline` and == 0 in `lt117_lift_off`.
  Inertness control: `lt117_lift_off` RUN lines equal those of a pre-LT-117 build
  (`release-0.11.0`) on 2 seeds x all strategies (byte-identical except the new `lifts` key).
- Caveat: the bot rebuilds into a slot a lift emptied (`bot_placement.gd:35`), so lifts also
  change the bot's later builds; report it, do not fix it here.
- Results go into the playtest doc (a new LT-117 section; `docs/playtest-0.4.md` unless the
  owner names a new file). If a knob needs tuning later: double/halve first
  (`disable_seconds` 6 / 1.5, `drop_cells` 4 / 1), then bisect; never nudge. The owner picks the
  numbers.

## 9. Owner decisions

| # | question | recommendation |
|---|---|---|
| Q1 | Which tower, how often | A: the tower under the gaunt, once per gaunt, not while already lifted |
| Q2 | Drop cell choice | A: uniform draw on a new appended `LIFT` stream among free buildable cells at exactly `drop_cells` steps |
| Q3 | No free cell | A: shrink the ring to 1; none: stays, still disabled |
| Q4 | Disable timer owner | On the tower: 90 ticks regardless of the gaunt's death |
| Q5 | Fake gaunts | Never lift |
| Q6 | Allies of a moved Circle | Keep the old home until they expire |
| Q7 | Wave 6 has no gaunts (effective from wave 7) | Keep the data; note it in the playtest section |
| Q8 | Golden regen for the new `LIFT` stream (final lines only) | a: approve, events must stay byte-identical |
