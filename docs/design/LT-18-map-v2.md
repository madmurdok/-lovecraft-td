# LT-18: Map v2 (hex islands, weighted routes, barricades, flood)

Status: approved by the owner 2026-11-26 (decisions in §13). Branch `docs/LT-18-map-v2` from `release-0.14.0` (7201d97).
Source: GDD "Topics for further discussion" -> "Map v2: islands and a changing path"; owner
direction 2026-10-31 (fixed, not re-opened here); owner ideas on flood, barricades, water
"обтекание", pockets and spawn gradient (quoted in §6-§7). Prior work reused: LT-77
(`GridTopology`, `steps`, `Vector2i` axial ids), LT-108 (`GridFactory`, polygon tiles, a real
`HexGrid` shipped unregistered), LT-96 S14 = LT-109 (route source and mutable map state, blocked
on this note), LT-32 (crew reserve and night posts), LT-33 (boundary rule). Geometry cost of hex,
Voronoi polygons and the angled view: **LT-64 covers geometry cost**; this note does not estimate it.

Acceptance (LT-18): chosen cell model (§2), path-change rule (§4), chokepoint metric (§8),
generator approach (§9), migration impact (§10), prototype plan (§11). Options with benefit and
risk where a decision is open; owner questions in §12.

## 0. Owner direction (fixed)

1. Sim on a hex grid, rendered as jittered Voronoi polygons.
2. Buildable islands for towers; the enemy path runs between them. Towers never block the path;
   only barricades do.
3. Before each wave the monsters highlight the route they plan to take.
4. Route choice by path weight: route cost = length + breach cost from barricade durability; enemies
   take the cheapest, so a long detour also leads to breaking.
5. A seeded deterministic generator that guarantees chokepoints.

## 1. What exists today (release-0.14.0)

- `GridTopology` (`sim/rules/grid_topology.gd`) with `SquareGrid` and `HexGrid` (pointy-top axial,
  odd-r text rows, `steps`, `polygon`, `cell_at`); `GridFactory.make(kind, w, h)`. `"grid": "hex"`
  is not registered yet (LT-108 §10). World frame: 1 unit = neighbour centre distance, so
  `range`/`speed` keep their meaning; `UNITS_PER_CELL = 30000`, 30 ticks/s.
- `MapDef` (`sim/defs/map_def.gd`): kinds `.` buildable, `#`/`S` path, `~` water, `L`; exactly one
  `S` and one `L`; `_derive_path` walks one non-forking path into `path`. `state.map` is that
  config object (immutable).
- `SpawnSystem._ground_route` (`sim/core/systems/spawn_system.gd`): one `SimRoute` for every ground
  enemy; flyers get `SimRoute.straight(S, L)`. `move()` clamps distance to `route.length`; `leak()`
  fires at the end. Each enemy already holds its own `e.route`, so per-enemy routes cost nothing.
- `SimRoute.from_cells(grid, cells)`: integer cumulative lengths from `grid.distance`; on hex every
  step is exactly 1.0 cell = 30000 units.
- RNG streams `SPAWN, COMBAT, SANITY, MADNESS, LOOT, GHOST_LOOT, CRIT, LIFT`; new streams are
  appended last (`sim/core/sim_rng.gd`).
- Crew (LT-32): reserve men deploy **posts** at night on a free buildable cell; dawn returns them.
- Traits that read the map: `tower_lift` (drop cell by `grid.steps` + `is_buildable`),
  `tower_harass` (schema only, pending: its "near which tower" rule is still open).

## 2. Cell model

**Logic: hex, axial `Vector2i`** (LT-77 D1, existing `HexGrid`). **Look: jittered Voronoi**, a
presentation decorator over `HexGrid.polygon` (one seeded jitter per shared vertex so tiles meet;
LT-77 §3). Nothing in `sim/` reads the jittered polygon; picking uses the hex `cell_at`, so a click
near a jittered edge may pick the neighbour (LT-64 decides the tolerance).

**Terrain kinds** (per cell, fixed for the run; replaces today's path/buildable/water split):

| Kind | Text | Walk (ground) | Build tower | Barricade | Flood water | Notes |
|---|---|---|---|---|---|---|
| `SEA` | `~` | no | no | no | source | map edge; flyers and entries start here |
| `CHANNEL` | `#` | yes | no | yes | yes | the walkable network between islands |
| `ISLAND` | `.` | no | yes | no | no | high ground; posts too |
| `ROCK` | `^` | no | no | no | no | filler, shapes channels and pockets |
| `ENTRY` | `S` | yes | no | no | yes | a channel cell on the sea edge; 1..4 per map |
| `LIGHTHOUSE` | `L` | yes (goal) | no | no | no | one per map |

Today's square text maps read the same way: `#`/`S` = CHANNEL/ENTRY, `.` = ISLAND, `~` = SEA, so a
one-path square map is a channel network with one route (§10, golden stays byte-identical).

Channels are 1-2 cells wide. Islands are never walked, so towers can never block; that is the
owner's rule 2 enforced by terrain, not by a placement check.

## 3. Route weight and the route field

**One integer cost per step**, in sim units:

- Walking a step: `UNITS_PER_CELL` (hex: every step is 1.0).
- Entering a cell with a live barricade: `+ breach_cost(b)`, where
  `breach_cost(b) = ceil(barricade.weight_cells * b.hp / b.max_hp * UNITS_PER_CELL)`.
  `weight_cells` is data (`data/barricades.json`); e.g. a fresh barricade with `weight_cells = 8`
  costs like 8 extra cells of walking, a half-broken one 4.

**Route field.** One reverse Dijkstra from `L` over CHANNEL/ENTRY cells gives, for every walkable
cell, its cost to the lighthouse and its next hop. A route from any cell (an entry, a flood spawn
cell, a pocket) is "follow the next hops", turned into a `SimRoute` with `from_cells`. One field per
plan serves every entry and every flood-spawned Deep One.

**Determinism.** Integer costs only; the heap orders by `(cost, grid.index(cell))`; next-hop ties
are broken by the pinned `neighbours` order. No floats, no RNG. On a one-path map the field yields
exactly today's `path`, so the golden replay does not move.

**Which enemies use it.** Every ground enemy of one entry follows the same route in a wave (one
highlighted line per entry; the telegraph is honest). Per-enemy-type weights (a shoggoth that breaks
faster prefers breaching) are possible later but give several lines per entry; not proposed.
Flyers ignore the field and barricades (straight line, as today).

### 3.1 When the route is planned (decision)

- **(a) Planned at dawn, re-planned on every day change, frozen when the wave starts
  (recommended).** During the build phase the highlighted routes update live as the player
  builds, sells or repairs barricades (a `planned_routes()` prediction query, LT-33). At
  `call_wave`/timer the field freezes for the whole wave. An enemy whose frozen route crosses a
  barricade stops at it and breaks it; a barricade deployed at night on a frozen route is breached,
  off it is ignored. Benefit: the line shown is the line walked; one Dijkstra per change; no
  mid-wave rerouting to explain. Risk: a night barricade on the route is a guaranteed stall (bounded
  by its HP and the count cap, §5).
- (b) Re-plan whenever a barricade is placed or destroyed. Benefit: "smart" monsters. Risk: the
  telegraph lies once the wave starts; enemies turn around mid-channel (looks buggy); every reroute
  is a new route object per live enemy, with a "where on the new route am I" projection.
- (c) Frozen plan, but enemies that reach a barricade re-check: breach vs. detour from here.
  Benefit: fewer pointless stalls. Risk: still breaks the telegraph; harder to read.

## 4. Path-change rule (why routes change, and fairness to placement)

Islands are fixed for the run and towers are never on the path, so a route change never destroys or
displaces a tower; it can only make a tower less useful. Routes change from wave to wave through
three sources:

1. **Entry per wave.** Each wave group names an entry (`"entry": "north"`), or `"any"`, drawn at dawn
   on a new `ROUTE` stream (appended after `LIFT`). Drawn at dawn, so it is known for the whole
   build phase.
2. **Barricades** (player-made; §5) re-weight the graph.
3. **Flood** (§6) puts Deep Ones on new start cells inside the network.

Fairness options:

- **(a) Convergence guarantee, no refund change (recommended).** The generator guarantees that all
  entries' routes share the final approach and at least one shared chokepoint (§8 C3), and the
  next wave's entries and routes are shown all day. Benefit: early towers at the shared funnel never
  lose value; no economy exploit; reading the next route is the skill. Risk: if the shared part is
  too large, every run plays as "turtle the funnel"; the metric bounds it (C3 max share).
- (b) Full refund on sell during the build phase after the route changed. Benefit: zero punishment.
  Risk: free repositioning every wave; placement stops mattering; bots and players exploit it.
- (c) Discounted move (pay 20 % to move a tower to another island cell by day). Benefit: middle
  ground. Risk: a new command, UI and refund rule for a problem (a) may already solve.

## 5. Barricades

Owner idea: "можем добавить баррикады - которые можно ставить на пути и монстры вынуждены будут их
ломать, баррикады задерживают воду и не дают спавнить глубоководных близко к маяку."

**Rules (proposed).**
- Placed on a CHANNEL cell that is not an entry, not the lighthouse, not within `floor_cells` of `L`
  (§6.2), not occupied by a live enemy. One per cell. An entity in `state` (`SimBarricade`: id,
  cell, hp, max_hp), not a tower.
- **Breaking.** A ground enemy whose route enters a barricade cell stops half a cell before it
  (`move()` clamps to `barricade_distance - UNITS_PER_CELL / 2` while it stands) and deals
  `breach_dps` (new `EnemyDef` field; default 1x its leak damage per second x data factor) to it.
  At 0 HP the barricade is removed (`BARRICADE_BROKEN`) and the queue walks on. Flyers ignore it.
- **Water.** A live barricade adds its weight to flood spreading (§6.1).
- **No infinite stall.** HP is finite and every ground enemy damages it; a hard count cap
  (`max_count`, e.g. 3, +1 per lighthouse level); no repair at night; repair by day costs money
  pro rata. A wave timer is not needed while every blocked enemy deals damage.

**Placement (decision).**
- **(a) Built by day for money, persist until broken (recommended).** Benefit: plays with the
  telegraph (place, watch the route and flood forecast change); one new command; reuses the build
  phase. Risk: a new money sink to balance against towers.
- (b) Deployed at night from the crew reserve (2 men, like a post; men return when it breaks or at
  dawn). Benefit: reuses LT-32; an emergency answer to a surprise. Risk: with the frozen route
  (§3.1a) a night barricade on the route is a near-free stall; the flood is already computed when
  the night starts, so it cannot "hold water".
- (c) Both: day barricades for money; night "sandbags" from the reserve with half HP, gone at dawn.
  Benefit: both play styles. Risk: two variants to balance and explain; do after (a) proves fun.

**Fakes (hallucinations, LT-12).** Fakes stop at a barricade like real enemies but deal no damage.
Risk: a barricade whose HP does not drop reveals the fakes; see Q8.

## 6. Flood and Deep Ones

Owner idea: "глубоководные приходят с наводнением - вода наползает и отходя оставляет глубоководных.
При повышении сложности - глубоководные спавнятся все ближе и ближе к маяку."
And: "надо сделать обтекание водой баррикад тоже на базе веса (те объем воды наводнения один, но
если есть баррикады на пути - то он тратится на обтекание по длинному маршруту и тем самым меньше
проникает в нашу оборону. Плюс ... "карманы" ... туда затечет вода и наспавнит глубоководных, но им
придется выбираться из "карманов" обратно. Плюс ... спавн должен быть градиентным, те чем дальше от
моря несет наводнение волны - тем меньше глубоководных спавнится)".

### 6.1 Spreading: priority flood with one volume

A wave's flood has a **volume `V`** (in cells, data per wave). Water starts at every SEA cell next to a
CHANNEL/ENTRY cell and spreads over CHANNEL/ENTRY only (never ISLAND, ROCK, L):

1. Dijkstra from the sea with water step cost = 1 cell, plus a live barricade's
   `water_weight_cells` (scaled by its HP fraction, like §3) when entering its cell.
2. Cells are taken in order of `(water_cost, index)`; each taken cell consumes its **capacity**
   (1; a pocket basin cell may be 2, "deep water", Q6) from `V`. Stop when `V` is spent or the next
   cell is inside the floor (§6.2).
3. The flooded set is that prefix. Intact barricade cells are not flooded.

Why this matches the idea: one volume; water fills the cheapest cells first across every branch at
once, so a barricade pushes the cells behind it to the back of the queue and the volume is spent on
the detour and other branches instead ("тратится на обтекание"). Pockets are near the sea and cheap,
so they fill early and soak up volume.

Alternative: **reach budget** (flood every cell with `water_cost <= V`). Benefit: simpler; a
barricade's weight cuts reach exactly by its weight. Risk: not one volume; pockets soak up nothing,
which loses the owner's pocket debuff. Not recommended.

### 6.2 Floor (how close water may reach)

- **(a) Floor in route cost to `L` (recommended):** no cell with route-field cost
  `< floor_cells` is flooded or spawned on (data, e.g. 6). Benefit: a guaranteed minimum walk for
  the fastest Deep One (speed 1.6: 6 cells = 3.75 s inside the defence); scales with the real route,
  not the straight line. Risk: a barricade near `L` changes the field and so moves the floor; this is
  why barricades are also banned inside the floor (§5).
- (b) Floor in hex steps from `L`. Benefit: fixed ring, easy to draw. Risk: a ring 6 steps away may
  be 15 route cells away or 6; uneven danger.

Difficulty: `V` grows per wave (data) and with a difficulty multiplier (LT-23 difficulty, LT-111
wave mults), so the front creeps toward `L` and stops at the floor.

### 6.3 Spawn gradient

The wave's `deep_ones` count `N` is split across **bands** of the flooded set by water cost (band = 2
cells of water cost). Band `k` of `B` gets weight `B - k` (linear falloff: most near the sea, few at the
front). Counts by largest remainder (deterministic, no RNG); the cell inside a band by a draw on a new
`FLOOD` stream (appended last). Each spawned Deep One gets the route from its cell (§3 field), so
those in pockets walk out the long way. The `pack` trait spacing applies per band.

Falloff options: linear (recommended: readable), exponential (sharper, few near the front), or
"front only" (all at the front; strongest, opposes the owner's gradient). Data key `falloff`.

### 6.4 Timeline and telegraph

- **Day:** the flood forecast (cells that would flood with today's barricades) is shown as a faint
  outline, and updates live when a barricade is built (`flood_preview()` query).
- **Wave start + `flood.at_s`:** water rises over `rise_s` (e.g. 3 s, drawn by sim ticks); the
  flooded set is computed at rise start and frozen (night barricades do not change it).
- **Peak:** Deep Ones spawn on the set (§6.3), `FLOOD_PEAK` event. Water recedes over `fall_s`.
- Water has no other rule effect (no slow, no damage). Option for later: enemies in water x1.2 speed.

### 6.5 Flood and towers (decision)

- **(a) No effect: islands never flood (recommended).** Benefit: "islands are islands"; zero new
  tower state; posts are safe too. Risk: the flood is only a spawn mechanic, no tension for builds.
- (b) "Low ground" island cells (a generator flag) flood too; a tower there is disabled while wet
  (rise + peak + fall). Benefit: a placement trade-off (low cells near the channel are best but
  flood). Risk: new kind, new disabled state, harsher with bigger `V`.
- (c) Towers in or next to flooded cells fire x0.5 while wet. Benefit: soft. Risk: a modifier source
  that interacts with light rules (LT-70); unclear to read.

### 6.6 Which waves flood

Waves that list Deep Ones keep them as spawn groups at the entries today. Proposed: a wave gets an
optional `"flood": {volume, deep_ones, at_s}` block; its Deep Ones come from the flood instead of
from an entry. Waves 2, 3, 5 and 6 (GDD §8) list Deep Ones and are the candidates. Dagon's summons (boss) stay as they are.

## 7. Pockets

Generator-made dead-end channel basins off the main network, opening toward the sea side (2-6 cells,
ending in ROCK). They fill early (cheap water cost) and absorb volume; Deep Ones left there must walk
out to the main channel, so they arrive later and spread out. Pockets are CHANNEL, so barricades may
be placed in their mouths: a barricaded pocket stops absorbing volume (a real trade-off). Count and
size are generator parameters (§9) and a lab knob.

## 8. Chokepoint metric

Inputs: the map, its route field with no barricades, a reference tower range `R` (data, default the
rifleman's), and for every entry its route `r_e`. Definitions:

- `exposure(b, r)` for a buildable cell `b`: number of route cells of `r` whose centre lies within
  `R` of `b`'s centre (euclid, world frame; how long a tower on `b` sees the route).
- A **chokepoint** on route `r`: a route cell `p` with at least `K` buildable cells `b` within `R` of
  `p` and `exposure(b, r) >= E`.

Constraints a map must pass (all thresholds in data, tuned in the lab):

| # | Constraint | Default | Why |
|---|---|---|---|
| C1 | every entry route has `>= M` chokepoints, spaced `>= S` route cells apart | M 2, S 6, K 3, E 4 | the owner's "guarantee chokepoints" |
| C2 | no stretch of `> G` route cells with no buildable cell within `R` | G 8 | no blind channels |
| C3 | all entry routes share the last chokepoint before the floor; shared route share `<= 50 %` | | fairness (§4a) without "one lane" |
| C4 | route lengths within `[Lmin, Lmax]`; max/min across entries `<= 1.4` | 20-40 | wave timing stays balanced |
| C5 | for each chokepoint, the best detour around one barricade there is `>= D` cells longer | D 4 | a barricade is a real choice, not free |
| C6 | flood floor reachable: some channel cell at route cost `>= floor + 3` from `L` per entry | | flood has room |
| C7 | every buildable cell is reachable by a click (not hidden under `L`/UI) | | LT-64 view |

The metric is a pure function in `sim/rules/` (shared by the generator, tests and the balance lab).
Report per map: chokepoints per route, max blind stretch, shared share, detour deltas.

## 9. Generator

Pure, in `sim/rules/map_generator.gd`; seeded by a **map seed** (its own `RandomNumberGenerator`,
not a run stream, so map choice never shifts combat rolls); output a `MapDef` (kinds, entries, `L`,
grid). Retries with `seed * 1000 + attempt` until §8 passes; an attempt cap fails loudly.

Options:
- **(a) Skeleton graph, then dress (recommended).** Place `L` near one side, 1-4 entries on the
  sea edge; build a channel skeleton: shortest corridors entry -> `L`, then 1-2 extra links that make
  loops (route alternatives, C5), then pockets near the sea; rasterize corridors on hex (width 1-2,
  jittered); islands = the regions between channels, split into 4-12 cell islands; ROCK fills thin
  slivers. Benefit: chokepoints and loops are built in, not hoped for; low reject rate; every knob
  maps to a gameplay idea. Risk: maps may look "drawn by rules"; more code than noise.
- (b) Noise heightmap: threshold into sea/low/high, keep the component that links entries to `L`,
  repair, reject by metric. Benefit: natural shapes. Risk: high reject rates, chokepoints by luck,
  hard to tune; long channels without cover.
- (c) Hand-made templates + seeded variation (jitter island edges, swap pocket sets, pick entries).
  Benefit: full control; a painted background per template stays possible (§9a). Risk: little
  variety; every template is authored work.

**Map per run or fixed?** Proposed: a map seed per run (shown on the end screen, replayable), with a
fixed seed list for the campaign/tests. Golden and tests keep text maps.

**Art (§9a conflict).** A generated map cannot use one hand-painted harbour background. Proposed:
terrain textures per kind on the Voronoi polygons (sea, channel mud, island grass/rock, rock), plus
props; LT-64 covers its geometry cost. §9a "1 hand-painted background" changes to "4 terrain
textures + props" (Q10).

## 10. Migration impact

All of this is LT-109 (S14) plus follow-ups. Production sites from `grep` of `is_buildable`,
`map.path`, `map.spawn`, `map.lighthouse`, `_ground_route`, `kind_at` (13 files):

| Area | File | Change |
|---|---|---|
| Map | `sim/defs/map_def.gd` | new kinds; `entries` instead of `spawn`; `_derive_path` -> connectivity check (every entry reaches `L`); `path` removed (kept as entry 0's route for one-path maps) |
| Rules (new) | `sim/rules/route_field.gd`, `flood_rules.gd`, `chokepoint_metric.gd`, `map_generator.gd` | pure, integer, tested alone |
| State | `sim/core/sim_state.gd` | `barricades`, `barricade_at`, `route_field` (current plan), `planned_entries`, `flood_cells`; `state.map` stays config, mutable parts live in state |
| RNG | `sim/core/sim_rng.gd` | append `ROUTE`, `FLOOD` after `LIFT` |
| Spawn | `spawn_system.gd` | `_ground_route` -> route per entry from the field; flood spawns; `move()` clamps at a live barricade; breach damage; flyers unchanged |
| Waves | `wave_director.gd`, `waves_config.gd` | plan at `_begin_build`, freeze at wave start; group `"entry"`; wave `"flood"` |
| Defs | `enemy_def.gd`, new `data/barricades.json` | `breach_dps`; barricade cost, HP, weights, cap |
| Facade | `simulation.gd` | `build_barricade`/`repair_barricade`/`remove_barricade` + `can_*`; queries `planned_routes()`, `flood_preview()`; events `ROUTE_PLANNED`, `BARRICADE_*`, `FLOOD_RISE/PEAK/RECEDE` |
| Other sim | `light_system.gd`, `crew_system.gd`, `trait_host.gd` | read `L` and `is_buildable` only; unchanged except `spawn` -> entries |
| View | `sim/view/*` | snapshot: barricades (hp), flood cells and phase, planned routes |
| Scenes | `board.gd`, `fx_layer.gd`, `phantom_layer.gd`, `lighting.gd`, `game.gd`, `ui/lighthouse_panel.gd` | route highlight layer, flood layer (tick-driven), barricade sprites and picker entry; phantom walk on channels; sea fog from SEA cells; Voronoi look and angled view are LT-64 |
| Bots | `tools/bot/bot_placement.gd`, `bot_runs.gd` | score cells by exposure to planned routes (§8 `exposure`), a barricade policy |
| Tests | ~46 test files touch maps | one-path text maps keep working: the field on a one-path map gives today's cells, so golden stays byte-identical (a test pins it). New tests: field ties, barricade weight switch, flood volume/pockets/floor, gradient counts, generator determinism, metric |

Balance: hex range covers ~15 % more cells (LT-96 D9, already planned); new levers `weight_cells`,
`V`, `floor_cells`, falloff; lab maps come from fixed seeds.

## 11. Prototype plan (grey)

Grey-box, no art: flat-coloured jittered polygons, a toggle for plain hexes, lines for routes,
translucent blue for water, grey blocks for barricades, letters for towers. Launch with
`-- --mute`. Built on the pure rules files (they survive), with a throwaway debug scene and a
headless tool script.

| Step | Shows | Pass if |
|---|---|---|
| P1 generator + metric (headless + viewer) | 20 seeds side by side; chokepoints, loops, pockets marked; metric report per map; reject rate and time over 1000 seeds | maps read at a glance; reject rate < 30 %; < 200 ms per map; same seed -> same map digest |
| P2 routes + barricades | next-wave routes highlighted in the build phase; placing a barricade re-draws them live; one case where enemies detour, one where they breach (weight vs. detour length); breach stall and break | the owner can predict the route before the wave; no infinite stall in 50 bot runs |
| P3 flood | forecast outline by day; rise -> peak -> spawn -> recede; volume ladder over 6 waves approaching the floor; pockets soaking volume and Deep Ones walking out; a barricade shrinking the flood | the gradient is visible; barricades visibly keep water away from `L` |
| P4 bot smoke | the lab bot plays 20 seeds x 6 waves | wave reached / lighthouse HP left per seed (non-saturating metric), seeds with no chokepoint win/loss spread flagged |

Out of the prototype: final look, angled view, sounds, tower re-balance, night sandbags.

Suggested order after approval: LT-108 hex registration -> P1 -> LT-109 (route field + entries,
golden unchanged) -> P2 barricades -> P3 flood -> generator into the real game.

## 12. Owner questions

1. Route planning (§3.1): (a) plan by day, freeze at wave start **(recommended)**; (b) re-plan on each
   barricade change; (c) frozen plan, re-check at the barricade.
2. Path-change fairness (§4): (a) convergence guarantee, no refund change **(recommended)**; (b) full
   refund after a change; (c) paid tower move.
3. Barricade placement (§5): (a) by day for money **(recommended)**; (b) at night from the crew
   reserve; (c) both.
4. Barricade limits: cap 3 (+1 per lighthouse level), repair by day only, breach damage per enemy
   type. Keep or change?
5. Flood on towers (§6.5): (a) islands never flood **(recommended)**; (b) low-ground cells, wet
   towers disabled; (c) wet towers x0.5.
6. Flood model (§6.1): one volume, priority flood, pockets absorb **(recommended)** vs. reach
   budget. Deep pocket cells with capacity 2: yes or no?
7. Floor (§6.2): in route cost to `L` **(recommended)** vs. hex steps; default 6 cells?
8. Fakes at barricades: no damage (risk: reveals fakes) vs. visible fake damage that is refunded
   when the fake dissolves.
9. Entries per wave: authored in `waves.json` with `"any"` drawn at dawn **(recommended)** vs. always
   random.
10. Map per run: generated per run seed with a fixed campaign list **(recommended)** vs. a few
    templates (keeps painted backgrounds, §9a).
11. Generator (§9): (a) skeleton graph **(recommended)**; (b) noise; (c) templates.
12. Which waves flood (§6.6): the Deep Ones of waves 2, 3, 5, 6 move to the flood?

## 13. Owner decisions (2026-11-26)

- Questions 1, 2, 3, 5, 6, 7, 9, 10, 11: the recommended options, "Принять все (Recommended)".
  Q6's deep pocket cells (capacity 2) and Q7's default floor of 6 cells stay as proposed and are
  tuned in the prototype.
- Q4 barricade limits (cap 3, +1 per lighthouse level, repair by day only, breach damage per
  enemy type): "Оставить".
- Q8 fakes at barricades: "Не бьют" (fakes deal no barricade damage; the tell is accepted).
- Q12 flood waves: "Да, все четыре" (the Deep Ones of waves 2, 3, 5, 6 move to the flood; wave 2
  is checked in the balance lab).
