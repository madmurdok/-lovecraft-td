# LT-109: route source and mutable map state for per-wave paths

Design note for LT-96 §4 S14 (A-X7, B-X8 route part). Builds on LT-18 §3 (route field), §3.1
(planned by day, frozen at wave start; owner decision Q1 (a)), §4 (entry per wave, `ROUTE`
stream after `LIFT`), §10 (migration) and LT-130 §10.14 (generator in `sim/mapgen/`, seam = the
map dict read by `MapDef.parse`). No production code in this slice.

Acceptance: the golden replay stays byte-identical on today's hand-written `data/map.json`
(and the frozen `tests/fixtures/golden_data/map.json`); LT-18 (Map v2) can later land in map,
spawn and dawn code only.

## 1. Today

### 1.1 How the path is built

1. `GameConfig._parse_map` (`sim/config.gd:173-175`) calls `MapDef.parse`
   (`sim/defs/map_def.gd:23-43`).
2. `MapDef._read_rows` (`map_def.gd:46-85`) reads the `. # ~ S L` legend into `_kinds`, finds
   exactly one `S` (`spawn`) and one `L` (`lighthouse`), then `_derive_path` (`map_def.gd:88-131`)
   walks S -> L over PATH neighbours, rejects forks, dead ends and orphan path cells, and sets
   `path: Array[Vector2i]` (S ... L inclusive) at line 131.
3. `Simulation._init` (`sim/core/simulation.gd:39`) sets `state.map = config.map`: the config
   object itself (G4b pins `simulation.gd` as its only writer). There is no mutable map state.
4. `SpawnSystem._init` (`sim/core/systems/spawn_system.gd:25-29`) builds one
   `_ground_route := SimRoute.from_cells(map.grid, map.path)` for the whole run.
5. `SpawnSystem._enter` (`spawn_system.gd:102-131`) gives every ground enemy that same object
   (line 120); a flyer gets a new `SimRoute.straight(grid, map.spawn, map.lighthouse)` (line 122).
   Every entry point funnels here: `spawn_enemy` (48-54; called by `WaveDirector._spawn_due`
   `wave_director.gd:128`, `ScriptedSpawner` `scripted_spawner.gd:20`, `HallucinationSystem`
   `hallucination_system.gd:49` for fakes, all through `Simulation.spawn_enemy` 143-144) and
   `release_pack_members` (76-90) for queued pack members (`PackTrait` -> `TraitHost` ->
   `queue_pack_member` 59-61).
6. After that the enemy only knows `e.route` (`sim_enemy.gd:12`) and `e.distance`; nothing
   reads `map.path` again in the sim.

`SimRoute` (`sim/core/sim_route.gd`) is immutable after `from_cells`/`straight`; the view keeps a
reference to it (`sim/view/enemy_record.gd:22,50`, "shared immutable route").

### 1.2 Every reader

Found with one recursive grep over `*.gd` outside `tests/` and `addons/` for
`map\.path|\.path\b|map\.spawn|map\.lighthouse|is_buildable|kind_at|_ground_route|\.route\b|
SimRoute|state\.map|config\.map` (g-mesh does not index GDScript), then sorted by role.

**Path / spawn (the route source)** — the only production readers of `map.path`/`map.spawn`:

| Site | Role |
|---|---|
| `spawn_system.gd:29` | builds the one ground route from `map.path` |
| `spawn_system.gd:122` | flyer straight line `map.spawn -> map.lighthouse` |
| `tools/bot/bot_placement.gd:24` | bot scores a cell by path cells in range (`for p in m.path`) |
| `scenes/board.gd:318` | draws the spawn marker (`m.spawn`) |

**Route consumers (per enemy, via `e.route`, unchanged by this task)**: `spawn_system.gd:151,168`
(move, leak), `push_back` 158-162; `combat_system.gd:76,182,303,395,400,477,499,593,624`;
`light_system.gd:268`; `ally_system.gd:105,138,155`; `sanity_system.gd:256`;
`economy_system.gd:165`; `trait_host.gd:31`; `simulation.gd:800` (render interpolation);
`sim/view/enemy_record.gd:50`.

**Buildability / kinds (the "buildable mask" candidates)**: sim `simulation.gd:164` (`can_build`),
`crew_system.gd:105` (post), `trait_host.gd:47` (lift target); presentation `scenes/game.gd:280`,
`scenes/board.gd:311`, `scenes/board/phantom_layer.gd:53,66`, `scenes/lighting.gd:368`; tools
`bot_placement.gd:21`; ~30 test files.

**Lighthouse cell** (static under LT-18 too): `light_system.gd:429`, `scenes/game.gd:276`,
`scenes/lighting.gd:207`, `scenes/board/fx_layer.gd:153`, `ui/lighthouse_panel.gd:54`.

**Tests that read `map.path`**: `map_def_test.gd`, `sim_movement_test.gd`, `square_grid_test.gd`,
`grid_factory_test.gd`, `map_layer_test.gd`, `hallucination_test.gd`, `bot_upgrade_test.gd:774`.
Four test files build a `SpawnSystem` straight from a `SimContext` without the facade
(`sim_spawn_test.gd`, `sim_combat_test.gd`, `wave_mult_test.gd`, `trait_hooks_test.gd`).

### 1.3 RNG and golden

`SimRng.Stream` (`sim/core/sim_rng.gd:11`) is `{SPAWN, COMBAT, SANITY, MADNESS, LOOT,
GHOST_LOOT, CRIT, LIFT}`, stream `i` seeded `run_seed * 16 + i` (stride 16, line 14). Appending
keeps every existing seed. **But** the golden dumpers iterate all streams:
`tests/golden_runs.gd:248` (`trace_final`, the `"rng"` array of every trace) and `:271`
(`state_text`, `rng%d=` lines of `final_sha` / `game_final_sha`), and
`tests/golden_trace_test.gd:131` asserts `rng.size() == Stream.size()`. A ninth stream, even
never drawn, adds a line to every final state: the digests move. §3.1 resolves this (Q2).

### 1.4 Day / night hooks

- `WaveDirector._begin_build` (`wave_director.gd:112-117`): BUILD for the next wave; called at
  `attach` (tick 0, before wave 1) and after each cleared wave that is not the last.
- `WaveDirector._clear_wave` (140-150) calls the LT-99 dawn hook `Simulation.on_dawn(n)`
  (`simulation.gd:653-663`), then `WAVE_CLEARED`, then `_begin_build`.
- `WaveDirector.start_wave` (86-100): WAVE starts (`call_wave` or the timer), `wave_index += 1`,
  `WAVE_STARTED`.

`on_dawn` does not run before wave 1, and it runs after the last wave (no next wave): the route
plan belongs to the build start, not to the dawn (Q4).

## 2. Design

```mermaid
flowchart LR
  MD[MapDef\nroute ids + route_provider()] --> RP[RouteProvider\nFixed today, Field later]
  WC[WavesConfig\ngroup.route] --> RS
  RP --> RS[RouteSystem\nplan_next / freeze]
  RNG[SimRng.ROUTE\nappended last] -. LT-18 "any" .-> RS
  RS -->|writes| ST[(SimState\nroute_next, route_now)]
  WD[WaveDirector] -->|_begin_build| F1[Simulation.on_build_start]
  WD -->|start_wave| F2[Simulation.on_wave_start]
  F1 --> RS
  F2 --> RS
  ST -->|route_now| SP[SpawnSystem\nroute cache by id]
  SP --> E[SimEnemy.route]
```

### 2.1 Route ids in `MapDef`

- `const DEFAULT_ROUTE := "main"`.
- `var routes: Dictionary[String, Array]` (id -> `Array[Vector2i]` S ... L): a v1 map (today's
  legend, one `S`) yields `{"main": path}`; set at the end of `_derive_path` (line 131) next to
  `path`. Lookup only, never iterated (order comes from `route_ids`).
- `var route_ids: PackedStringArray = []`: pinned order, `[0]` is the default; `["main"]` on v1.
- `path` and `spawn` stay as they are (alias of `routes["main"]` and its first cell): ~8 test
  files and the board read them; LT-18 decides their fate per §10.
- `func route_provider() -> RouteProvider`: `FixedRouteProvider.new(routes, route_ids)` on a v1
  map. LT-18's MapDef v2 returns a field-based provider here: the "which provider" decision is
  map code.
- `map.json` is unchanged (`FIELDS` stays `width, height, rows, grid`): ids are derived. Named
  entries (`"north"`) arrive with MapDef v2 (LT-18), which maps entry names to route ids.

### 2.2 `RouteProvider`

New pure files in `sim/rules/` (stateless rules, no RNG, like `grid_factory.gd`):

```gdscript
class_name RouteProvider extends RefCounted
## Route ids in pinned order; ids()[0] is the default route.
func ids() -> PackedStringArray
## start ... L of route `id` under the given extra entry cost per grid.index (sim units;
## empty = none; LT-18 passes barricade breach weights here). Empty for an unknown id or an
## unreachable start. Pure: no RNG, no state, same input -> same cells.
func cells(id: String, extra_cost: PackedInt64Array) -> Array[Vector2i]
```

- `FixedRouteProvider` (`sim/rules/fixed_route_provider.gd`): returns `routes[id]` as authored,
  ignores `extra_cost`. Holds any number of ids (tests use two).
- Later (LT-18, not here): `FieldRouteProvider` builds a `RouteField` from MapDef v2 terrain,
  entries and `L`. It consumes only MapDef (grid, kinds, entries, L), never `GenMap`: the seam is
  the map dict, so the P1 skeleton generator (LT-130) and the island-first generator (LT-141, 1-cell
  channels) both feed it unchanged. Today `RouteField.build` takes a `GenMap`; LT-18 adds a
  `build_on(grid, walkable, goal, extra_cost)` entry point (§3 out of scope).
- Providers never draw: resolving `"any"` is a `RouteSystem` draw on `ROUTE` (§2.6), so a
  provider swap never moves an RNG sequence.

### 2.3 Spawn route cache by id

`SpawnSystem` replaces `_ground_route` (line 14, 29) with:

- `_ground_cache: Dictionary[String, SimRoute]`, `_air_cache: Dictionary[String, SimRoute]`,
  `_cache_cells: Dictionary[String, Array]` (the cells each cached route was built from).
- `_route_for(id: String, flying: bool) -> SimRoute`: `id == ""` means the plan's default
  (`route_ids[0]`). Cells come from `_state.route_now.cells[id]`, or from
  `_config.map.routes[id]` when `route_now` is null (the four tests that build `SpawnSystem`
  without the facade keep working unchanged). A cached route is reused while its cells are
  equal (`==` on the arrays), so on the fixed map one ground `SimRoute` serves the whole run
  exactly as today; when a new plan changes a route's cells, a new `SimRoute` replaces the cache
  entry and enemies already walking keep theirs (immutable, the view relies on it).
- Flyer: `SimRoute.straight(grid, cells[0], cells[-1])`, cached by id too (today one per flyer;
  numerically identical, `SimRoute` has no mutators).
- `spawn_enemy(def_id, is_fake := false, route_id := "")` and `_enter(..., route_id)`; the pack
  queue entry gains a fifth field, the leader's route id, so members walk the leader's route.
  `Simulation.spawn_enemy` forwards the optional argument (120 test call sites need no change).
  Fakes from `HallucinationSystem` use `""` (default); LT-18 decides their route.

### 2.4 `waves_config` `"route"`

`WavesConfig.SpawnGroup`: `GROUP_FIELDS` gains `"route"`; `var route: String = ""` via
`opt_string`. `""` (absent) = the map's default route = today's behaviour. A group-level field,
as LT-18 §4 and Q9 have the entry per group (Q3 on the name). Validation needs the map, so a new
`GameConfig._check_routes` cross-check (`config.gd:119-121`): every non-empty `route` must be in
`map.route_ids`; `"any"` is rejected with "not supported before Map v2 (LT-18)" until LT-18
enables the draw. Skips a null map or null waves section, like `_check_drops`.

### 2.5 `SimState` additions and their writer

```gdscript
## LT-109: route plan of the wave in progress (frozen at WAVE_STARTED); spawns read it.
var route_now: RoutePlan
## LT-109: route plan of the next wave, made at the build start; the day telegraph reads it.
var route_next: RoutePlan
```

`RoutePlan` (`sim/core/route_plan.gd`, value type like `sim_route.gd`, never mutated after
`RouteSystem` builds it): `wave: int` (0 = the default plan), `group_routes: PackedStringArray`
(resolved route id per group of that wave), `cells: Dictionary[String, Array]` (id -> cells, every
id of `route_ids`; lookup only).

Writer: a new `RouteSystem` (`sim/core/systems/route_system.gd`), the only writer of both fields
(G4b). It holds `_provider = config.map.route_provider()`.

- `_init(ctx)`: `route_now = route_next = default plan` (wave 0, every id's cells from the
  provider with empty `extra_cost`). Draws nothing, emits nothing (LT-80 §3 construction rule).
- `plan_next(wave: int)`: builds `route_next` for `config.waves.waves[wave - 1]`: per group
  `g.route` or the default id; `"any"` -> (LT-18) one `ROUTE` draw per group, group order.
- `freeze()`: `route_now = route_next`.

The buildable mask (`var buildable: PackedByteArray` by `grid.index`, from `map.is_buildable`,
written by `RouteSystem._init` only; the three sim readers `simulation.gd:164`,
`crew_system.gd:105`, `trait_host.gd:47` switch to it) is designed but recommended **deferred**
(Q1): after LT-18's decisions islands never flood (Q5 a) and barricades stand on channel cells,
so buildability is static for the whole run and the mask would equal `map.is_buildable`.

### 2.6 When routes are (re)planned

- `Simulation.on_build_start(next_wave: int)` (new facade hook next to `on_dawn`): calls
  `_routes.plan_next(next_wave)`. `WaveDirector._begin_build` calls it first, before setting
  BUILD and emitting `BUILD_STARTED`. So: tick 0 before wave 1 (at `attach`), and after each
  dawn: `on_dawn` actions -> `WAVE_CLEARED` -> `on_build_start` -> `BUILD_STARTED`.
- `Simulation.on_wave_start()`: calls `_routes.freeze()`. `WaveDirector.start_wave` calls it after
  `wave_index += 1`, before `WAVE_STARTED` (both `call_wave` and the timer go through it).
- `_spawn_due` passes `s.route_now.group_routes[gi]` to `sim.spawn_enemy`.
- LT-18 adds re-planning during BUILD (barricade built/sold) as one more `plan_next` call from
  the barricade command, and a `ROUTE_PLANNED` event. **No new event in LT-109**: an event changes
  the golden event stream and G6b would need a UI consumer.
- Without a `WaveDirector` (`ScriptedSpawner`, tests) the default plan stays: today's behaviour.

### 2.7 RNG stream appended last

`enum Stream {SPAWN, COMBAT, SANITY, MADNESS, LOOT, GHOST_LOOT, CRIT, LIFT, ROUTE}`; header line
"ROUTE resolves a group's "any" route at the build start (LT-109), so a route draw never
reshuffles SPAWN". Indices 0-7 and their seeds (`run_seed * 16 + i`) are unchanged; `ROUTE` = 8
is seeded `run_seed * 16 + 8`, below the stride. No LT-109 code path draws it (no `"any"`).

Golden dumper rule (Q2, recommended): `GoldenRuns.PINNED_STREAMS := SimRng.Stream.ROUTE` (= 8,
the stream count the pinned files were made with). `trace_final` and `state_text` dump streams
`0 .. PINNED_STREAMS - 1` always, and a later stream only when its state differs from a fresh
`RandomNumberGenerator` seeded `run_seed * 16 + i` (i.e. once drawn). `golden_trace_test.gd:131`
asserts the same rule. Never-drawn `ROUTE` adds nothing, so every pinned file stays
byte-identical, and a run that draws it (LT-18) shows the line.

### 2.8 Bot

`tools/bot/bot_placement.gd:24` scores against `m.path`. It switches to a facade query
`Simulation.planned_route_cells() -> Array[Vector2i]`: the cells of every route used by
`route_next.group_routes`, deduplicated in `route_ids` then walking order. On the fixed map that
is exactly `map.path` (the score is a count, order-free), so bot runs and their golden digests
do not move. The score cache key gains the plan's identity (LT-18 changes routes per wave; today
one plan per run, no effect). Q5.

## 3. Byte-identical, and out of scope

**Why golden stays byte-identical.**

- Events: no new event type, no new emit; `on_build_start` / `on_wave_start` emit nothing.
- RNG: no draw on any stream from LT-109 code; `ROUTE` is appended (seeds 0-7 unchanged) and
  hidden from the dumps until drawn (§2.7).
- Routes: on the fixed map the default plan's cells are `map.path`; the cache reuses one
  `SimRoute.from_cells(grid, path)` (same constructor, same input) for every ground enemy, as
  `_ground_route` did; flyers get `straight(path[0], path[-1])` = `straight(spawn, lighthouse)`.
- Config: `map.json` and the frozen `golden_data` files are unchanged; absent `"route"` = `""`.
- State dumps (`state_text`, `SimNoTreeLoop.digest`) do not print the new fields.
- Command log: `spawn_enemy` is not a logged command; no command added.

The existing golden tests (`golden_replay_test.gd`, `golden_trace_test.gd`) are the pin; nothing
is regenerated.

**Out of scope** (LT-18 and later): barricades and `breach_cost` (only the `extra_cost` seam
exists), flood and Deep One flood spawns, `FieldRouteProvider` / `RouteField` on MapDef v2,
MapDef v2 terrain kinds and named entries, generator integration at runtime (map per run seed),
`"any"` draws, re-planning during BUILD, `ROUTE_PLANNED` and the route telegraph in the snapshot
/ board (LT-33), the buildable mask (if Q1 defers it), fakes' route choice.

## 4. Edit map

### 4.1 Changed functions

| File | Lines (at ab4ce94) | Change |
|---|---|---|
| `sim/defs/map_def.gd` | 1-20 header, vars | `DEFAULT_ROUTE`, `routes`, `route_ids`; doc lines |
| `sim/defs/map_def.gd` | 88-131 `_derive_path` | at 131 also set `routes = {DEFAULT_ROUTE: walk}`, `route_ids = [DEFAULT_ROUTE]` |
| `sim/defs/map_def.gd` | new after 151 | `route_provider()` |
| `sim/defs/waves_config.gd` | 64-81 `SpawnGroup` | `GROUP_FIELDS` + `"route"`, `var route := ""`, `opt_string` |
| `sim/config.gd` | 119-121 `_cross_checks` | append `_check_routes`; new `_check_routes` after `_check_drops` (217-) |
| `sim/core/sim_rng.gd` | 7-11 | append `ROUTE`; header line |
| `sim/core/sim_state.gd` | after 66 | `route_now`, `route_next` (+ `buildable` only if Q1 = b) |
| `sim/core/systems/spawn_system.gd` | 14, 25-29 | `_ground_route` -> caches; nothing built in `_init` |
| `sim/core/systems/spawn_system.gd` | 42-54 `spawn_enemy` | `route_id := ""` |
| `sim/core/systems/spawn_system.gd` | 57-61 `queue_pack_member`, 76-90 `release_pack_members` | carry the route id (5th field); `TraitHost.queue_pack_member` (`trait_host.gd:64`) and `PackTrait` (`pack_trait.gd:51`) pass the leader's `e.route_id` |
| `sim/core/systems/spawn_system.gd` | 102-131 `_enter` | `e.route = _route_for(route_id, def.flying)`; new `_route_for` |
| `sim/core/sim_enemy.gd` | 12 | `var route_id := ""` (pack members, later telegraph) |
| `sim/core/simulation.gd` | 35-58 `_init` | `_routes = RouteSystem.new(_ctx)` before `_spawn` |
| `sim/core/simulation.gd` | 142-144 `spawn_enemy` | forward `route_id` |
| `sim/core/simulation.gd` | after 663 | `on_build_start(next_wave)`, `on_wave_start()`, `planned_route_cells()` |
| `sim/core/wave_director.gd` | 86-100 `start_wave` | `sim.on_wave_start()` after `wave_index += 1` |
| `sim/core/wave_director.gd` | 112-117 `_begin_build` | `sim.on_build_start(s.wave_index + 1)` first |
| `sim/core/wave_director.gd` | 120-130 `_spawn_due` | pass `s.route_now.group_routes[gi]` |
| `tools/bot/bot_placement.gd` | 13-30 `best_cell` | `sim.planned_route_cells()` instead of `m.path` (Q5) |
| `tests/golden_runs.gd` | 243-253 `trace_final`, 261-271 `state_text` | `PINNED_STREAMS` rule (Q2) |
| `tests/golden_trace_test.gd` | 128-134 | same rule in the assertion |
| `tests/architecture_guard_test.gd` | 670-706 `G4B_OWNERS` | `"route_now"`, `"route_next"`: `["core/systems/route_system.gd"]` |

### 4.2 New files

| File | Folder rule it follows |
|---|---|
| `sim/rules/route_provider.gd` (`RouteProvider`) | pure rule, `RefCounted`; no "grid" in the name, so G10: no neighbour offsets or bounds loops (it does none) |
| `sim/rules/fixed_route_provider.gd` (`FixedRouteProvider`) | same |
| `sim/core/route_plan.gd` (`RoutePlan`) | state value type next to `sim_route.gd` |
| `sim/core/systems/route_system.gd` (`RouteSystem`) | G4a: names no `Simulation`, no private members, no `RandomNumberGenerator`/`SimRng`/`SimEvent.new`; draws via `_ctx.randi_range` (allowed API) |
| `tests/route_source_test.gd` | behaviours below |

Guard path lists: only `G4B_OWNERS` changes. `SIM_RNG_HOMES` is unchanged (no new
`RandomNumberGenerator` in `sim/`; the golden dumper's fresh generator is in `tests/`).
`ENGINE_ALLOWLIST` unchanged (`PackedInt64Array`, `PackedStringArray`, `Dictionary` already used
in `sim/`; the tests slice confirms with `test_sim_names_only_own_types_and_allowlisted_engine_types`).

### 4.3 Behaviours the tests slice pins

1. Golden replay and trace pass unchanged (no regen).
2. v1 `MapDef`: `route_ids == ["main"]`, `routes["main"] == path`; provider returns it for any
   `extra_cost`; unknown id -> empty.
3. `waves.json`: absent `route` -> `""`; unknown id -> config error naming the path
   `waves[i].groups[j].route`; `"any"` -> config error.
4. Spawn: a group with `route: "alt"` (two-route fixture map) walks `alt`; enemies of one route
   share one `SimRoute`; a flyer flies straight from its route's first cell to `L`.
5. A pack member walks its leader's route.
6. Plan timing: wave 1's plan exists at tick 0 (`route_next.wave == 1` after `attach`); a plan
   made by day reaches spawns only after `WAVE_STARTED` (stub provider whose cells change per
   call); enemies already walking keep their `SimRoute`.
7. RNG: `Stream.LIFT == 7`, `Stream.ROUTE == 8`; every stream's initial state equals a fresh
   generator seeded `run_seed * 16 + i`; a full run on the fixed map leaves `ROUTE` undrawn.
8. Dumper rule: a never-drawn later stream adds no `rng` entry; one draw adds it.
9. G4b: `RouteSystem` is the only writer of `route_now` / `route_next`.
10. `SpawnSystem` without the facade (`route_now == null`) uses `map.routes["main"]`.
11. Bot: `planned_route_cells()` == `map.path` as a set on the fixed map.

### 4.4 Proposed controls (7)

| # | Revert (production code) | Must fail |
|---|---|---|
| C1 | `_enter` ignores `route_id` (always default) | B4 "group alt walks alt" |
| C2 | `_route_for` builds a new `SimRoute` per spawn | B4 "share one SimRoute" |
| C3 | `start_wave` does not call `on_wave_start` | B6 "plan reaches spawns only after WAVE_STARTED" |
| C4 | plan moved from `_begin_build` into `on_dawn` | B6 "wave 1 plan at tick 0" |
| C5 | `ROUTE` inserted before `LIFT` | B7 enum/seed pin (and golden) |
| C6 | `state_text` dumps every stream unconditionally | golden replay (B1) |
| C7 | `_check_routes` dropped from `_cross_checks` | B3 unknown-id error |

C1, C2, C4 touch `spawn_system.gd`/`wave_director.gd` and run only `route_source_test.gd`; C5 and
C6 run `route_source_test.gd` + `golden_replay_test.gd`; group per the standing rule.

## 5. Open questions for the owner

**Q1. Buildable mask in `SimState`.**
- **Defer to the first rule that changes buildability (Recommended).** Benefit: no reader churn
  (3 sim, 4 scene, 1 tool, ~30 test sites) for a mask that equals `map.is_buildable` under the
  LT-18 decisions (islands never flood, barricades on channels). Risk: S14's list is not done
  to the letter; a later feature (wet towers) adds it then.
- Add it now, switch the 3 sim readers only. Benefit: the mutable-state slot exists. Risk:
  two answers to "is it buildable" (scenes still read `map`) until presentation follows.
- Add it now, sim and presentation (snapshot). Benefit: one answer everywhere. Risk: the widest
  edit of the task for no behaviour.

**Q2. Golden digests vs the new `ROUTE` stream.**
- **Dump streams 0-7 always, later ones only once drawn (Recommended).** Benefit:
  byte-identical, and `ROUTE` shows up the moment LT-18 draws it. Risk: a test-side rule to
  keep; a stream drawn and reset to its seed state would be hidden (impossible with PCG32 in
  practice).
- Add `ROUTE` only in LT-18, with the first draw. Benefit: no golden code change now. Risk:
  LT-18 meets the same digest problem and touches `sim_rng.gd`, against its "map, spawn, dawn
  only" goal.
- Append it and regenerate the golden files once (format-only change). Benefit: simplest
  code. Risk: breaks the acceptance "byte-identical"; a regen can hide a real drift.

**Q3. Waves field: name and level.**
- **Per group, named `"route"`, values = route ids (= entry names in MapDef v2)
  (Recommended).** Benefit: matches LT-18 Q9 (entry per group) and the S14 wording. Risk: LT-18
  §4 says `"entry"`; docs need one sentence that a route id is an entry name.
- Per group, named `"entry"`. Benefit: LT-18's word. Risk: an "entry" for a flood spawn or
  a pocket route reads wrong later.
- Per wave `"route"`. Benefit: one line per wave. Risk: no mixed waves (two entries in one
  night), which LT-18 §4 wants.

**Q4. Where routes are planned.**
- **New facade hook `on_build_start(next_wave)` called by `_begin_build` (Recommended).**
  Benefit: covers wave 1 and never plans past the last wave; the dawn order stays pinned.
  Risk: a second hook beside LT-99's `on_dawn`.
- Inside `on_dawn` plus one call at `attach`. Benefit: one hook. Risk: two call sites for one
  rule, and a plan after the last wave.
- Lazily at the first spawn of a wave. Benefit: no hook. Risk: the day telegraph (LT-33) has
  nothing to show by day.

**Q5. Bot scoring.**
- **Switch to `planned_route_cells()` now (Recommended).** Benefit: LT-18 does not touch tools;
  same scores on the fixed map. Risk: one facade query added before a real second route exists.
- Leave `m.path`; LT-18 changes the bot. Benefit: smaller LT-109. Risk: the bot scores a stale
  path on generated maps if LT-18 forgets it.

## 6. Owner decisions (2026-11-27)

Note approved: "Утвердить (Recommended)".

- Q1: "Отложить (Recommended)": no buildable mask in `SimState` in LT-109.
- Q2: "Дамп: потоки 0-7 всегда, новые — если тронуты (Recommended)".
- Q3: "Поле \"route\" у группы (Recommended)": per-group `"route"`, values = route ids (= entry names).
- Q4: "Новый хук on_build_start (Recommended)".
- Q5: "Перевести сейчас (Recommended)": the bot scores `planned_route_cells()` in LT-109.
