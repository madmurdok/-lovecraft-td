# LT-4 — Simulation core (design note)

Status: draft for owner review · 2026-10-29 · branch `feat/LT-4-simulation-core`

## 0. What exists today and what this task adds

**Today** (`release-0.1.0`): the game boots (`scenes/main.gd`), loads and validates the five
JSON configs into a `GameConfig` (`sim/config.gd`) and stops there. Nothing moves; there is
no grid, no path, no enemy, no lighthouse HP at runtime. `economy.json` already holds
`lighthouse.hp = 20`; `enemies.json` holds speed (cells/s), armor, leak damage, `flying` and
traits (`pack`, `tower_lift`, ...).

**This task** adds a plain-script simulation (no `Node`, no scene) that a scene or a test
advances one fixed tick at a time: a 24×14 grid read from a new data file, one fixed path,
enemies walking it, leaks hitting the lighthouse, win/lose. Everything is driven by a seed
and is replayable. No towers, no waves, no sanity yet: those are later tasks, and §6 shows
where each one plugs in.

```
GameConfig (LT-3) ──► Simulation.new(config, seed)
                         │ step()  ← called N times per frame by SimClock (scene side, LT-7)
                         ├─ state  (read-only for scenes: grid, enemies, hp, tick, outcome)
                         └─ drain_events()  (one-shot facts: spawned, leaked, died, outcome)
```

---

## 1. State model and the fixed-tick API

### 1.1 Tick rate and time

- **Decision:** the sim advances in fixed steps of `SimTime.TICK_RATE = 30` ticks per second,
  `DT = 1/30 s`. `step()` always advances exactly one tick; it never takes a `delta`.
- **All durations become integer ticks at load/spawn time:** `SimTime.ticks(seconds) =
  roundi(seconds * TICK_RATE)`. Example: a spawn interval of 1.2 s is 36 ticks; the build
  timer 25 s is 750 ticks. Per-second *rates* (regen 1 %/s, horror drain 0.5/s) stay floats
  and are multiplied by `DT` each tick.
- **Consequence:** timers are exact counters (no "fired at 1.19999 s" drift), and a test can
  say "this happens on tick 300".
- `TICK_RATE` is a resolution of the engine, not a balance number, so it lives in code
  (GDD §2 forbids *balance* constants in code). Changing it does not change game balance.
- **Rejected:** variable `dt` from `_process` (frame-rate dependent, not replayable);
  Godot's `_physics_process` (ties the sim to a Node and the engine's physics rate).

### 1.2 Who calls `step()`: `SimClock` (pure) + a thin Node driver (LT-7)

- `SimClock` (pure script) turns real frame time into a number of steps:
  `advance(real_delta) -> int`. It keeps an accumulator; `speed` is 0 (pause), 1 or 2;
  it returns `floor(accumulator / DT)` steps and keeps the remainder.
- **Catch-up cap:** at most `MAX_STEPS_PER_FRAME = 8` steps per frame; excess time is
  dropped (the game slows down for a moment instead of freezing in a "spiral of death"
  after a long hitch, e.g. window drag).
- **Example:** 60 fps at ×1 → steps alternate 0,1,0,1... (30/s). 144 fps → mostly 0, a 1
  every ~5 frames. ×2 at 60 fps → 1 step per frame. Pause → 0, accumulator frozen.
- **Frame-rate independence:** 60 frames of 1/60 s and 30 frames of 1/30 s both give 30
  steps; the sim never sees the frame rate.
- **Render smoothness:** `SimClock.alpha()` (remainder / DT, 0..1) lets the renderer
  interpolate between an enemy's previous and current position (each enemy keeps
  `prev_distance`), so 30 Hz motion looks smooth at 144 Hz.
- The Node that calls `clock.advance()` and `sim.step()` in `_process` is a ~15-line
  `SimRunner` in LT-7; LT-4 ships only the pure, tested `SimClock`.

### 1.3 Player commands (pause-building)

- GDD §8 allows building while paused, and in pause no tick runs. So commands
  (build/sell/upgrade/call wave — LT-5/LT-6) are applied **immediately, between ticks**
  through `Simulation` methods, never mid-tick (single thread, so "between ticks" is
  guaranteed). Each command is appended to `state.command_log` with the current tick, so
  a run is replayable from `(seed, command_log)`.
- LT-4 only creates the log; no commands exist yet.
- **Rejected:** a command queue drained at the next tick start (a tower built in pause would
  not appear until unpause).

### 1.4 State

`SimState` (RefCounted, plain fields; owned by `Simulation`):

| Field | Type | LT-4 | Notes |
|---|---|---|---|
| `tick` | int | yes | completed steps; first `step()` runs tick 1 |
| `outcome` | enum NONE/WON/LOST | yes | once not NONE, `step()` is a no-op |
| `lighthouse_hp` | int | yes | from `economy.lighthouse_hp` |
| `map` | `MapDef` | yes | immutable grid + path (§3) |
| `enemies` | `Array[SimEnemy]` | yes | spawn order = id order |
| `next_id` | int | yes | shared id counter for every entity |
| `command_log` | Array | yes | §1.3 |
| `phase`, `wave_index`, `build_ticks_left` | | LT-5 | |
| `gold`, `towers`, `tower_at: Dictionary[Vector2i,int]` | | LT-6 | |
| `sanity`, `sanity_state` | | LT-10/13 | |

`SimEnemy` (RefCounted): `id`, `def: EnemyDef`, `hp`, `max_hp`, `route: SimRoute`,
`distance: int`, `prev_distance: int`, `base_units_per_tick: int`, `is_fake: bool`,
`revealed: bool`, `spawn_tick`, plus per-tick modifiers reset every tick and rebuilt by
effect systems (`speed_mult = 1.0`, `damage_taken_mult = 1.0`, `armor_bonus = 0.0`) and
`status: Dictionary` for trait timers (stun, harass stop) added by later tasks.

**Entity ids:** one counter, starting at 1, shared by enemies, towers and (later)
projectiles; never reused after removal. Example: enemies 1, 2, 3 spawn; 2 dies; the next
spawn is 4. Consequence: an event "enemy 2 died" can never be confused with a newer
entity, and the renderer can key its nodes by id.

---

## 2. How scenes read the sim: direct read-only state + an event buffer

- **Continuous things** (positions, HP bars, lighthouse HP, gold, sanity): the scene reads
  `sim.state` directly every frame. Read-only by convention; nothing is copied.
  `sim.enemy_position(e, alpha) -> Vector2` gives a position in **cell units** (the
  renderer multiplies by its pixel cell size; pixels never enter the sim).
- **One-shot things** (spawned, leaked, died, outcome; later shot fired, shot missed,
  fake dissolved, tower lifted, sanity state changed): each system appends a `SimEvent`
  (`type`, `tick`, `id`, `data: Dictionary`) to `sim.events`. The scene calls
  `sim.drain_events()` once per frame and gets every event since the last drain, also
  when several ticks ran in that frame. Tests drain the same buffer to assert on facts.
- **Example:** tick 412: enemy 7 reaches the lighthouse → `{type: LEAKED, tick: 412, id: 7,
  data: {damage: 1, hp_after: 19}}`. The renderer frees node 7 and plays a splash; the HUD
  shakes the HP counter.
- **Consequence:** the sim has zero Node/scene references and runs the same in tests,
  headless CI and the game. VFX (LT-7/LT-8) are pure consumers.
- **Rejected:** Godot signals on the sim (listeners run *inside* the tick and could mutate
  state mid-iteration; ordering across connections is implicit); copying a full snapshot
  every tick (allocation churn in GDScript for no gain while one thread owns the state).
- Rule for later tasks: the sim never reads anything the renderer computes (no Area2D,
  no collision, no node positions). Range checks are math on cell coordinates.

---

## 3. Grid, path, movement

### 3.1 Map data: new `data/map.json`

- **Today:** no map data. GDD §10 lists five files; the map is content, not code.
- **Change:** a sixth file `data/map.json`, loaded and validated by `GameConfig` like the
  others into `config.map: MapDef`:

```json
{
  "width": 24, "height": 14,
  "rows": [
    "~~~~~~~~~~~~~~~~~~~~~~~~",
    "S#####.......~~~~~~~~~~~",
    ".....#..................",
    "... 14 rows of 24 chars in total, ending at L ..."
  ]
}
```

  Legend: `.` buildable, `#` path, `~` water (not buildable, not walkable), `S` path
  start (docks, a path cell), `L` lighthouse (path end, not buildable).
- **The path is derived, not listed:** the loader walks from `S` through 4-neighbouring `#`
  cells to `L`. Validation rejects: wrong row count/length, unknown char, not exactly one
  `S` and one `L`, a path cell with more than two path neighbours (fork), a `#` not on the
  walk (orphan), a walk that does not reach `L`. Errors use the LT-3 format
  (`map.json: rows[3]: ...`).
- **Consequence:** one source of truth that a human can edit and see; path length and the
  "~40 path / ~120 buildable" targets are checkable by eye. The placeholder layout is
  drawn by the code slice to GDD §3 targets; the owner can redraw it without code.
- GDD §10 gets one line for `map.json` (doc change in the same task).
- **Rejected:** map in code (violates GDD §2 spirit, owner cannot edit); an explicit
  waypoint list next to the rows (two sources of truth that can disagree); a Godot
  TileMap (scene dependency; GDD §9a says the map is a painted background anyway).

### 3.2 Position along a route: integer fixed-point distance

- A `SimRoute` is a polyline of cell centres with precomputed cumulative lengths.
  The ground route = the map path (S → L, each step 1 cell long). An enemy's position is
  one integer: `distance` along its route in **sub-cell units**,
  `SimTime.UNITS_PER_CELL = 30_000` (so 1 cell/s = 1000 units/tick at 30 Hz).
- **Speed:** at spawn `base_units_per_tick = roundi(def.speed * UNITS_PER_CELL / TICK_RATE)`.
  Each tick: `distance += roundi(base_units_per_tick * speed_mult)`, clamped to the route
  length. `speed_mult` is 1.0 in LT-4; slows/stuns/aura (LT-6/LT-11) set it per tick;
  chain-harpoon pull-back subtracts distance.
- **Example:** path of 41 cells → length 40 cells = 1 200 000 units. Cultist (1.0 cell/s,
  1000 units/tick) spawned on tick 10 leaks on tick 10 + 1200 = 1210, i.e. exactly 40 s.
  Deep One 1.6 → 1600 units/tick → 750 ticks = 25 s. Slowest speed in data (0.4) has a
  rounding error ≤ 0.04 %.
- **Consequence:** arrival ticks are exact integers, so the acceptance test "reaches the
  lighthouse in the expected number of ticks" is an equality, not a tolerance, and
  identical on desktop and web.
- **Rejected:** float distance (`distance += speed * DT`): 1/30 is not representable, the
  sum after 1200 ticks may be 39.9999999 and arrive one tick late, platform-dependent in
  principle; cell-by-cell stepping (jerky, speeds like 1.6 cells/s need fractional
  carry anyway, which is the fixed-point scheme in disguise).

### 3.3 Order inside one tick

An enemy spawned in tick *s* first moves in tick *s+1*. `step()` runs, in this fixed order:

1. `tick += 1`; reset per-tick enemy modifiers.
2. Effect systems (LT-6/11: auras, slows, stuns) — empty in LT-4.
3. **Movement** (all live enemies in id order).
4. **Leaks**: every enemy with `distance == route length` leaks (§5).
5. Towers fire / damage (LT-6, LT-11, LT-13) — empty in LT-4.
6. Sanity drains/regen and threshold state (LT-10) — empty in LT-4.
7. **Spawning** (the spawner, §6).
8. Remove dead/leaked enemies (compaction after all systems, so no system iterates a
   list that shrinks under it).
9. **Outcome check** (§5).

### 3.4 Armor and damage

- `Simulation.apply_damage(enemy_id, amount, source)`: `taken = max(0, amount - armor) *
  damage_taken_mult`, where `armor = max(0, def.armor + armor_bonus)` (Corrupted Seal sets a
  negative bonus later). `hp -= taken`; at `hp <= 0` the enemy is marked dead and a `DIED`
  event carries `source` and `reward` (gold is credited by LT-6, sanity +0.5 by LT-10).
- **Example:** Hybrid (armor 2) hit for 10 → takes 8; hit for 1 → takes 0.
- LT-4 has no towers, so only tests call `apply_damage`; it is in the core because every
  damage source (towers, madness, AoE) must go through one armor rule.
- Floor at 0 follows GDD §7 literally ("flat reduction per hit") — see open question Q4.

---

## 4. Determinism

- **Claim:** same build + same configs + same seed + same command log → identical event
  stream and final state, every run and on desktop and web.
- **RNG ownership:** `Simulation` owns all randomness. No system calls the global
  `randi()`/`randf()`. It holds one `RandomNumberGenerator` per **stream**
  (`SPAWN`, `COMBAT`, `SANITY`, `MADNESS`), seeded from the run seed as
  `seed * 16 + stream_index` (each `RandomNumberGenerator` hashes its seed internally).
  Access: `sim.rng(SimRng.SPAWN)`.
  - **Why streams:** when LT-12 starts rolling hallucinated misses (COMBAT), pack sizes
    (SPAWN) for the same seed do not change, so seed-pinned tests from earlier tasks keep
    passing. **Rejected:** one shared RNG (every new feature reshuffles every other
    random outcome).
- **Iteration order:** enemies and towers are `Array`s in id order; removal only in step 8;
  ties (e.g. two targets at equal distance) break by lower id. No iteration over a
  `Dictionary` whose order depends on hashing; no reliance on Node/tree order.
- **Floats:** GDScript `float` is 64-bit IEEE; `+ - * / sqrt` are bit-identical across
  platforms. Positions along routes are integers (§3.2). `Vector2` is 32-bit and is used
  only for output positions and later range checks, never accumulated. Avoid `sin/cos/pow`
  in gameplay math (libm may differ desktop vs web); range checks compare squared
  distances.
- Test: run two sims with seed 42 for N ticks with a spawner that uses the RNG (pack sizes)
  → identical event lists; a third with seed 43 → different pack sizes (control that the
  RNG is actually consulted).

---

## 5. Lighthouse HP, win and lose

- `lighthouse_hp` starts at `config.economy.lighthouse_hp` (20).
- **Leak:** an enemy at the end of its route is removed; if it is real,
  `hp = max(0, hp - def.leak_damage)`; if it is a fake (LT-12), no damage (GDD §5.3 "fakes
  never leak"). Event `LEAKED {damage, hp_after, fake}`. All leaks of the tick are
  processed (an HP counter that stops at 0 mid-tick would make the event log depend on
  array order).
- **Lose:** at step 9, `hp == 0` → `outcome = LOST`, event `OUTCOME {result: lost}`.
- **Win:** at step 9, spawner `is_exhausted()` **and** no live *real* enemy **and**
  `hp > 0` → `WON`. Fakes do not block the win (they dissolve with the wave, GDD §5.3).
- **Same tick:** lose is checked first, so a last-enemy leak that kills the lighthouse is
  a loss.
- After the outcome, `step()` returns immediately (tick does not advance), so a driver
  that keeps calling it is harmless.
- **Example:** HP 2, two cultists leak on tick 900 → hp 0 (two `LEAKED` events, hp_after
  1 then 0), `OUTCOME lost` on tick 900, tick 901 never runs.

---

## 6. Plug-in points for later tasks

The rule: later tasks **add** a system to a slot in §3.3 or a field to the state; they do
not change movement, leaks, ids, events or the outcome check.

| Task | Plugs in via |
|---|---|
| **LT-5 waves / build phase** | Implements `SimSpawner` (`tick(sim)`, `is_exhausted()`) as `WaveDirector` from `WavesConfig`; adds `phase` BUILD/WAVE, build timer in ticks, call-wave command. Replaces LT-4's `ScriptedSpawner` (a list of `[tick, enemy_id]`, used by tests). "Win after the last wave" is already the outcome rule (exhausted + no real enemies). |
| **`pack` trait** | The spawner calls `sim.spawn_enemy(def_id)`; for a def with `pack`, one spawn event spawns `rng(SPAWN).randi_range(min, max)` enemies in the same tick (layout: Q5). |
| **LT-6 towers, targeting, gold** | `towers` array + `tower_at` occupancy; `MapDef.is_buildable(cell)`; target query `sim.enemies_in_range(cell, range_cells)` (id-ordered, includes fakes); damage via `apply_damage`; gold from `DIED.reward` (real only). Slows set `speed_mult` in slot 2. |
| **LT-10 sanity** | `SanitySystem` in slot 6; reads `horror_drain` and tower positions; `regen_mundane_kill` from `DIED.source`. Fractional sanity 0<s<1 vs madness threshold is decided there (open item from LT-3). |
| **LT-11 occult towers** | Elder Sign aura in slot 2 (`speed_mult`, `damage_taken_mult`, `armor_bonus`); Necronomicon AoE in slot 5. |
| **LT-12 fakes** | `spawn_enemy(def_id, is_fake = true)`; fakes walk, take shots and have HP like real ones; leak = no damage (already in LT-4's leak rule); dissolve all fakes when the wave ends (`FAKE_DISSOLVED` events); misses roll on `COMBAT`. Renderer never sees `is_fake`, only `revealed` (Revealing searchlight). |
| **LT-13 madness** | Shot resolution in slot 5 reads `sanity_state`; the 60/25/15 split rolls on `MADNESS`; "random real enemy in range" uses the same range query with a filter. |
| **Night-gaunt (flying)** | Already in LT-4 as a route: a 2-point `SimRoute` from the spawn cell straight to the lighthouse (length `sqrt`, rounded to units, at spawn). Lift (`tower_lift`, from wave 6) is an LT-6+ system that moves a tower in `tower_at` and sets its disable timer, rolling the drop cell on `SPAWN`. |
| **Dagon summons, shoggoth regen** | Per-enemy trait systems in slot 2/5; summons call `spawn_enemy` at the summoner's distance on the ground route. |
| **LT-7 rendering/HUD** | `SimRunner` Node: `clock.advance(delta)` → `sim.step()` ×N; reads state + `drain_events()`; interpolates with `clock.alpha()`. |
| **LT-8 lighting/fog** | Pure render; reads tower cells/kinds and enemy positions; needs nothing from the sim beyond state. |

---

## 7. Open questions (each with my recommendation)

1. **Tick rate.** 30 Hz (recommended: smooth enough with interpolation, half the GDScript
   cost of 60, every config duration so far is a multiple of 1/30 s) vs 60 Hz.
2. **Map file.** New `data/map.json` with ASCII rows, path derived by walking from `S`
   (recommended) vs rows + explicit waypoint list. Either way GDD §10 gains a sixth file.
3. **Where flyers start.** Night-gaunts spawn at the path start `S` and fly straight to `L`
   (recommended; the map has a single entry) vs a separate `F` spawn cell in the map.
4. **Armor floor.** `max(0, damage − armor)` as GDD §7 says (recommended; Dagon armor 8
   then shrugs off weak shots, which is the design) vs a minimum damage per hit, which
   would be a new config value.
5. **Pack layout.** All 4–6 Deep Ones spawn on the same tick at the same spot and overlap
   (recommended: piercing harpoon is "good vs packs"; the renderer spreads them visually) vs
   staggered by a spacing value (new config field `pack.spacing_cells`). Final call can
   wait for LT-5.
6. **Win and lose on the same tick → loss** (recommended) vs win.
7. **Dagon "leaking = instant loss".** Today it holds only because leak_damage 20 = HP 20.
   Recommended: an explicit `instant_loss` trait added with Dagon's content task, so a
   later HP rebalance cannot silently break it. LT-4 does nothing.
8. **Commands apply immediately between ticks** (recommended; makes pause-building work)
   vs queued until the next tick.

**Owner decisions (2026-10-29):** all eight answered as recommended. Design note approved
("Одобряю (Recommended)"); armor "Как в GDD, может быть 0"; pack "Все в одной точке и в
один такт"; flyers: "Пока будет S но давай отметим проверить вариант с точкой F" — flyers
start at `S` now; a separate `F` spawn cell is to be checked later (GDD open topics).

**Superseded (LT-63, 2026-11-02):** Q5 pack layout. Owner: members stacked on one spot hide
each other ("убиваешь их, а они исчезают а под ними еще одни"); chosen "Разнести по времени
в симе (Recommended)". `spawn_enemy` still rolls the size at once (same stream and order);
the first member enters now, member k enters k x `pack.spacing_s` later (slot 7, before the
spawner). A wave is not cleared, and the run not won, while a real member is queued.

---

## 8. Edit map for the code slice (LT-4/S2)

### Read for context

- `sim/config.gd:23` `GameConfig.load_from_dir` (where to add the map block, after the
  sanity block ~line 68); `:76` `_read_json`; `:156` `_read_id_map` (error style).
- `sim/config_reader.gd:51` `error`, `:59` `check_keys`, `:111` `as_int`, `:123`
  `as_string`, `:153` `req_object`, `:161` `req_array`, `:179` `req_int`.
- `sim/defs/economy_config.gd:16` `parse` (small def pattern to copy; `lighthouse_hp` :13).
- `sim/defs/enemy_def.gd:18` `TRAITS`, `:29` `parse` (speed, armor, `flying`, `pack`).
- `sim/defs/waves_config.gd:57` `SpawnGroup` (for LT-5 awareness only).
- `tests/config_test_base.gd:5` `FILES`, `:17` `make_dir`, `:38` `edit`,
  `:54` `load_edited` (reuse for map tests and to build sim test configs).

### Create

| Path | What |
|---|---|
| `data/map.json` | 24×14 placeholder harbor per §3.1 (~40 path, ~120 buildable). |
| `sim/defs/map_def.gd` | `class_name MapDef`: `enum Kind {BUILDABLE, PATH, WATER}`, `width`, `height`, `spawn: Vector2i`, `lighthouse: Vector2i`, `path: Array[Vector2i]`; `static parse(r, root) -> MapDef` (validation §3.1, path walk); `kind_at(cell)`, `is_buildable(cell)`, `in_bounds(cell)`. Lighthouse cell is not buildable. |
| `sim/core/sim_time.gd` | `class_name SimTime`: `TICK_RATE = 30`, `DT`, `UNITS_PER_CELL = 30000`; `static ticks(seconds) -> int`, `static units_per_tick(speed_cells_per_s) -> int`. |
| `sim/core/sim_clock.gd` | `class_name SimClock`: `speed` (0/1/2), `MAX_STEPS_PER_FRAME = 8`, `advance(real_delta) -> int`, `alpha() -> float`. |
| `sim/core/sim_route.gd` | `class_name SimRoute`: `from_cells(Array[Vector2i])`, `straight(a, b)`; `length: int` (units); `position_at(distance: int) -> Vector2` (cell units). |
| `sim/core/sim_enemy.gd` | `class_name SimEnemy` fields per §1.4; `reset_modifiers()`. |
| `sim/core/sim_event.gd` | `class_name SimEvent`: `enum Type {SPAWNED, LEAKED, DIED, OUTCOME}`, `type`, `tick`, `id`, `data`. |
| `sim/core/sim_state.gd` | `class_name SimState` fields per §1.4; `enum Outcome {NONE, WON, LOST}`. |
| `sim/core/sim_rng.gd` | `class_name SimRng`: `enum Stream {SPAWN, COMBAT, SANITY, MADNESS}`; builds the per-stream `RandomNumberGenerator`s from a seed (§4). |
| `sim/core/sim_spawner.gd` | `class_name SimSpawner` base: `tick(sim)`, `is_exhausted() -> bool`. |
| `sim/core/scripted_spawner.gd` | `class_name ScriptedSpawner extends SimSpawner`: `[tick, enemy_id]` entries, spawns on matching tick (pack applies). |
| `sim/core/simulation.gd` | `class_name Simulation`: `_init(config: GameConfig, seed: int)`, `state`, `set_spawner(s)`, `step()` (order §3.3), `spawn_enemy(def_id, is_fake := false) -> int` (pack expansion, flyer route), `apply_damage(id, amount, source)`, `enemy_by_id(id)`, `enemy_position(e, alpha) -> Vector2`, `rng(stream)`, `drain_events() -> Array[SimEvent]`. Private `_move()`, `_leak()`, `_compact()`, `_check_outcome()`. |

No `extends Node` anywhere under `sim/`.

### Change

| Path | What |
|---|---|
| `sim/config.gd` | `const MAP_FILE := "map.json"`, `var map: MapDef`, parse block in `load_from_dir`. |
| `tests/config_test_base.gd:5` | add `"map.json"` to `FILES` (else every copied test dir lacks the map and all config tests fail). |
| `docs/GDD.md` §10 | add `map.json` line. |
| `scenes/main.gd` | none (LT-7 creates the runner). |

### Behaviours the tests slice pins (one line each)

1. Cultist (1.0 cells/s) spawned on tick *s* on a path of length *L* cells leaks on tick exactly *s + 30·L*, not one tick earlier.
2. Deep One (1.6) leaks on tick *s + ceil(L·30000 / 1600)*.
3. Flying enemy follows a straight route; leak tick from the rounded euclidean length.
4. Leak removes the enemy and lowers HP by `leak_damage`; `LEAKED` event carries damage and hp_after.
5. HP reaching 0 sets `LOST` with one `OUTCOME` event; further `step()` calls do not advance `tick`.
6. HP never goes below 0 when several leaks land in one tick; all leaks are still reported.
7. Win: spawner exhausted, no live real enemy, HP > 0 → `WON`; lose takes precedence on the same tick.
8. A fake enemy that leaks deals no damage and does not block the win.
9. Same seed → identical event list and state after N ticks; different seed → different pack sizes; pack size always in [min, max].
10. Armor: damage − armor applied, floored at 0; `hp <= 0` → `DIED` with reward, enemy removed after the tick.
11. Entity ids are unique, increasing and not reused after removal.
12. `SimClock`: 60×(1/60 s) and 30×(1/30 s) both yield 30 steps; ×2 doubles steps; pause yields 0; at most 8 steps per frame; `alpha()` in [0,1).
13. `SimTime.ticks` / `units_per_tick` rounding (1.2 s → 36; 1.6 cells/s → 1600).
14. `map.json` loads (24×14, path from S to L, lighthouse not buildable); rejects wrong size, unknown char, missing/duplicate S or L, fork, orphan `#`, disconnected path — with LT-3-style error paths.
15. Existing config suites still pass with `map.json` in the data set.
16. No script under `sim/` extends `Node` or references `SceneTree` (source scan).
