# LT-106: enemy trait hooks and status registry (LT-96 S10)

Spec: LT-96 §4 S10; owner decisions D1 (S12 dropped: no `on_hit` through a shot pipeline) and
D6 (tower debuffs go through the LT-105 channel). Prior work: LT-97 (trait honesty,
`PENDING_TRAITS`), LT-105 (tower modifier channel, guard G12), LT-111 (wave multipliers in
`_enter`). Acceptance: golden byte-identical; tick cost within 5 %; a new enemy-only trait is
one file plus one catalog line.

## 1. Today

- Schema: `EnemyDef.TRAITS` (`enemy_def.gd:22-33`), `pack` special-cased in `_parse_trait`
  (`:90-113`); `PENDING_TRAITS` = tower_harass, tower_lift, regen (`:38`).
- Readers: `pack` in `SpawnSystem.spawn_enemy` (`spawn_system.gd:43-61`, the one RNG draw at
  `:54`, SPAWN or SANITY for a fake); `boss` in `HallucinationSystem` (`:18`, `:56`).
- Statuses: free keys in `SimEnemy.status`; countdowns in `CombatSystem.IMMUNITY_KEYS`
  (`combat_system.gd:14`), bleed hard-coded in `tick_statuses` (`:669-690`).
- Markers: `EntityLayer.enemy_markers` (`entity_layer.gd:80-91`) reads `status` keys from
  presentation; order slow, vuln, bleed, sealed.
- The golden fixture (`tests/fixtures/golden_data/enemies.json`) carries all four data traits;
  cultist (harass) is in 4 waves, night_gaunt (lift) in 3, shoggoth (regen) in 1.

## 2. Decisions

**T1. One file per trait, one catalog line.** New dir `sim/core/traits/`:
- `enemy_trait.gd` (`class_name EnemyTrait`, RefCounted): virtual `id() -> String`,
  `params() -> PackedStringArray`, `hooks() -> int` (bitmask, 0 = none), `pending() -> bool`
  (false), `parse_params(r, params, path) -> Dictionary` (default: every name required,
  number >= 0, today's generic branch `enemy_def.gd:110-112`), and one no-op method per hook.
  Methods, not consts: a subclass cannot redeclare a parent const in Godot 4.
- `trait_catalog.gd` (`class_name TraitCatalog`): `const SCRIPTS := [PackTrait,
  TowerHarassTrait, TowerLiftTrait, RegenTrait, BossTrait]`. **This order is the catalog order**
  (= today's `TRAITS` key order). Static, lazily built `_by_id` of one shared instance each;
  `has(id)`, `get_trait(id)`, `ids()`, `pending_ids()`. Trait instances hold **no state** (one
  instance serves every sim); per-enemy trait state lives in `e.status` under keys prefixed with
  the trait id (T5).
- One file per trait: `pack_trait.gd`, `boss_trait.gd` (flag, `params()` empty, `hooks()` 0),
  `tower_harass_trait.gd`, `tower_lift_trait.gd`, `regen_trait.gd` (schema only, `pending()`
  true, `hooks()` 0; T7).

**T2. Validation stays in the config parse** (`EnemyDef.parse`, called by the loader).
`check_keys(traits, TraitCatalog.ids(), tp)`, then `TraitCatalog.get_trait(id).parse_params(..)`
after `r.check_keys(params, tr.params(), path)`. Pack's checks move verbatim into
`PackTrait.parse_params` (min/max ints >= 1, max >= min, spacing >= one tick). Every error path
and message stays byte-identical (`config_reject_test.gd:347-406` unchanged). `EnemyDef.TRAITS`
and `PENDING_TRAITS` go; `has_pending_traits()` reads `TraitCatalog`.

**T3. Hook dispatch data on `EnemyDef`, built once at parse.** `hooks: int` (OR of its live
traits' masks), `hook_traits: Array[EnemyTrait]` and `hook_params: Array[Dictionary]` (parallel),
**filled by walking `TraitCatalog.SCRIPTS` order, never the JSON key order**; pending and
zero-mask traits are left out. Dispatch: `if def.hooks & H: for i: if
hook_traits[i].hooks() & H: hook_traits[i].on_x(host, e, hook_params[i], ..)`.

**T4. Hook set and fixed call points.** Bits on `EnemyTrait`: `ON_SPAWN 1, ON_TICK 2,
ON_DAMAGED 4, ON_DEATH 8, ON_LEAK 16, NEAR_TOWER 32`. Order everywhere: enemies in id order
(`state.enemies` is append order = id order), then catalog order within one enemy.

| Hook | Call point | Who | Signature (`host`, `e`, `p` = params first) |
|---|---|---|---|
| `on_spawn` | end of `SpawnSystem._enter`, after `SPAWNED` | each entering enemy, real and fake | `(.., from_event: bool)`; false for a queued pack member |
| `near_tower` | slot 2, new pass between `_light.update_beam()` and `_combat.apply_auras()` (LT-105 §3 writer slot) | live enemies | `(..)`; writes towers only via `host.modify_tower` |
| `on_tick` | slot 2, new pass right after `_combat.tick_statuses()`, before `_ally.tick_allies()` | live enemies | `(..)` |
| `on_damaged` | `CombatSystem.apply_damage`, after `e.hp -= taken`, only if `e.hp > 0` | survivor of a hit | `(.., taken: float, source: String)` |
| `on_death` | `apply_damage`, after `_on_enemy_killed` (keeps the token draw first) | killed enemy, real and fake | `(.., source: String)` |
| `on_leak` | `SpawnSystem.leak`, after `LEAKED` | real leaks only (a fake dissolves) | `(..)` |

Rules: hooks run for fakes like for real enemies (a fake must look identical, LT-12) except
`on_leak`; any RNG a hook draws goes through `host.randi_range(e, real_stream, ..)` /
`host.randf(e, real_stream)`, which use SANITY for a fake (generalises pack's rule, LT-12 §2).
`on_damaged`/`on_death` must not call `apply_damage` on the same enemy (no re-entry). The two
per-tick passes live in a new `sim/core/systems/trait_system.gd` (`TraitSystem`:
`near_tower()`, `tick_traits()`), which computes `_any: int` = OR of `def.hooks` over
`config.enemies` at construction and returns at once when its bit is 0: today `_any` =
`ON_SPAWN`, so both passes cost one int test per tick. No `on_hit` (D1: S12 dropped); a
damage-shaping trait (shield, armor-on-hit) needs a new design.

**T5. `TraitHost` (`sim/core/traits/trait_host.gd`): the only API a trait sees.** Built once by
the facade after the systems; holds `SimContext` and method Callables (object id, no
RefCounted cycle, like `set_ally_compact`). Now: `tick()`, `randi_range`, `randf`,
`queue_pack_member(due_tick, def, is_fake, pack_of)` (-> `SpawnSystem`, appends to
`_pack_queue` exactly like `:60`), `modify_tower(t, power, interval, miss, no_miss, off)` (the
one `t.add_modifiers` call for all traits). Later traits add the method they need here (regen
needs none: it writes `e.hp` of its own enemy). Guard G4a's patterns (no `Simulation`, no
`x._private`, no `RandomNumberGenerator.new`) extend to `sim/core/traits/`.

**T6. Pack moves into `PackTrait.on_spawn` without moving its RNG draw.** New
`spawn_enemy`: early returns as today, then `return _enter(def, is_fake, 0, true)`.
`PackTrait.on_spawn(host, e, p, from_event)`: return if not `from_event`;
`count := host.randi_range(e, SPAWN, int(p.min), int(p.max))`; `e.pack_of = e.id`; queue
members `k = 1..count-1` at `tick + k * SimTime.ticks(p.spacing_s)` with pack_of `e.id`.
Why the stream is identical: today the draw comes right before `_enter`; now right after it.
`_enter` draws nothing (`next_id`, `_wave_mults`, `SimRoute`, `emit` only), so no draw moves
relative to any other draw; `pack` is catalog row 0, so no other `on_spawn` can draw before it.
Events: `SPAWNED {def}` is emitted before the draw in both versions and carries no `pack_of`.
`e.pack_of` today = `_state.next_id` read before `_enter` = `e.id`; same value, set a few
statements later inside the same call. Queued members re-enter through `_enter(.., false)` and
do not roll again. A new pinned test asserts the SPAWN/SANITY draw counts per spawn event.

**T7. Pending traits stay pending; harass and lift's writer seam is wired now.** tower_harass,
tower_lift and regen become catalog files with their schema, `pending()` true, no hooks.
Reasons: (a) wiring any of them changes the golden fixture runs (cultist, night_gaunt,
shoggoth spawn there), breaking the byte-identical acceptance; (b) their semantics are not
specified (harass `stop_seconds`: does the cultist stop, near which tower, radius?; lift
`drop_cells` with no tower move rules); (c) each becomes a probe-P2 content task: one trait
file + a golden regen. The `near_tower` pass and `host.modify_tower` exist now, so
`sim/core/traits/trait_host.gd` is the second `add_modifiers` caller and is added to
`G12_WRITERS` in this task (writer order: light, then traits by enemy id/catalog, then LT-32).

**T8. Statuses table and `SimEnemy.markers()`.** New `sim/core/status_rules.gd`
(`StatusRules`), `const ROWS`, row order = marker order:

| Status | Keys in `e.status` | Tick kind | Marker |
|---|---|---|---|
| `bleed` | `bleed_ticks`, `bleed_dps`, `bleed_pulse`, `bleed_source` | pulse via `apply_damage`, erase all at 0 | `bleed` |
| `banish_immune` | `banish_immune_ticks` | countdown, erase at 0 | `sealed` |
| `pull_immune` | `pull_immune_ticks` | countdown, erase at 0 | (none) |

Plus two modifier markers, not statuses: `slow` (`speed_mult < 0.999`), `vuln`
(`damage_taken_mult > 1.001`), always first. `const COUNTDOWN_KEYS: PackedStringArray =
["pull_immune_ticks", "banish_immune_ticks"]` (today's order; decrements of independent keys
commute, but keep it); `CombatSystem.IMMUNITY_KEYS := StatusRules.COUNTDOWN_KEYS`, so the
`tick_statuses` loop is unchanged (no Dictionary walk on the hot path). `SimEnemy.markers() ->
PackedStringArray` = today's `enemy_markers` body driven by ROWS (`marker != ""` and
`int(status.get(ticks_key, 0)) > 0`); output byte-identical. `EntityLayer.enemy_markers` is
deleted; `entity_layer.gd:258` calls `e.markers()`. New guard G14: no `.status` read under
`res://scenes`, `res://ui`. A trait with a visible timer adds one ROWS row (its marker).

**T9. Hot-path cost.** `apply_damage`: one `e.def.hooks & ON_DAMAGED` (and `& ON_DEATH` on a
kill) int test; no Array, Dictionary or Callable created per hit; nothing runs for an enemy
without hooks. `_enter`: one int test per entry. Per tick: two `_any` tests. `markers()` is
presentation-only (it allocates one PackedStringArray, as today).

## 3. EDIT MAP (code slice)

| File | Function (lines) | Change |
|---|---|---|
| `sim/core/traits/` (new) | `enemy_trait.gd`, `trait_catalog.gd`, `trait_host.gd`, `pack_trait.gd`, `boss_trait.gd`, `tower_harass_trait.gd`, `tower_lift_trait.gd`, `regen_trait.gd` | T1, T5, T6, T7 |
| `sim/core/status_rules.gd` (new) | `ROWS`, `COUNTDOWN_KEYS` | T8 |
| `sim/core/systems/trait_system.gd` (new) | `_init(ctx, host)`, `near_tower`, `tick_traits` | T4 |
| `sim/defs/enemy_def.gd` | `TRAITS`, `PENDING_TRAITS`, `has_pending_traits` (:22-50); `parse` (:78-88); `_parse_trait` (:90-113) | T2, T3: catalog-driven parse, `hooks`/`hook_traits`/`hook_params` |
| `sim/core/systems/spawn_system.gd` | `spawn_enemy` (:34-61), `_enter` (:90-120), `leak` (:153-169); add `set_trait_host`, `queue_pack_member` | T6; on_spawn, on_leak dispatch |
| `sim/core/systems/combat_system.gd` | `IMMUNITY_KEYS` (:13-14), `apply_damage` (:98-114); add `set_trait_host` | T8; on_damaged, on_death (T4) |
| `sim/core/simulation.gd` | `_init` (:33-51), `step` slot 2 (:75-91) | build host + TraitSystem, wire; two passes; slot comment |
| `sim/core/sim_enemy.gd` | `status` doc (:37-41); add `markers()` | T8 |
| `sim/core/hallucination_system.gd` | `BOSS_TRAIT` (:18) | `= BossTrait.ID`-style read via catalog id |
| `scenes/board/entity_layer.gd` | `enemy_markers` (:80-91), caller (:258) | delete; `e.markers()` |
| `scenes/board.gd` | doc (:11) | name `SimEnemy.markers` |
| `tests/architecture_guard_test.gd` | `G12_WRITERS` (:934); G4a scope; new G14 | T7, T5, T8 |

Read before editing: `SpawnSystem.release_pack_members` (:73-83), `dissolve_fakes` (:172-180),
`CombatSystem._on_enemy_killed` (:121-128), `tick_statuses` (:669-690), `SimTower.add_modifiers`
(`sim_tower.gd:73-79`), `SimContext.randi_range`/`next_id`, `GameConfig.from_dicts` (where
`EnemyDef.parse` runs), `tests/enemy_traits_test.gd` (whole, 140 lines).

## 4. Behaviours for the tests slice (each with a control)

1. Golden: `tests/golden_replay_test.gd` and `golden_trace_test.gd` pass with no regen (control:
   draw the pack count before `_enter` on `randi()` of COMBAT instead -> golden fails).
2. Pack draw: one SPAWN draw per real pack spawn event, one SANITY draw per fake one, none for a
   queued member's entry and none for a non-pack enemy (control: drop the `from_event` check).
3. Pack shape unchanged: pack_of = first id, member due ticks `tick + k*spacing`
   (`pack_spawn_test.gd` passes unchanged).
4. Catalog order: a def whose JSON lists traits in reverse gets `hook_traits` in catalog order
   (control: build from the JSON key order).
5. Hook order and gating with a test-only trait (`tests/fixtures/probe_trait.gd`, injected
   into a hand-built `EnemyDef`): each hook fires at its point, enemies in id order;
   `on_damaged` not on the killing hit; `on_death` after the token drop; `on_leak` never for a
   fake; `near_tower` before `apply_auras` (sees light's channel values, auras see its write).
6. Skip: with no def carrying a hook bit, `TraitSystem` passes visit no enemy (control: remove
   the `_any` test, counter > 0).
7. Parse: every `config_reject_test` trait path/message unchanged; pending ids =
   tower_harass, tower_lift, regen; `has_pending_traits` per enemy as before.
8. Markers: `SimEnemy.markers()` returns today's lists and order (move
   `tower_attack_visuals_test.gd:143-312` to it); `IMMUNITY_KEYS == StatusRules.COUNTDOWN_KEYS`.
9. Guards: G12 callers = light_system + trait_host; G14 catches a planted `e.status` read in
   `ui/`; G4a catches `Simulation` in a trait file.

## 5. Measure plan (tick-cost slice)

Arms: A = `release-0.9.0` (eb6444d), B = this branch tip, two worktrees, same `$GODOT`.
Command: `$GODOT --headless --path . -s res://tools/bot_runs.gd -- --seeds=10 --out=<scratch>`
(all strategies; packs, bleed and banish all hit the changed paths). 3 runs per arm,
interleaved A B A B A B, one background script; per run `uptime` and `/usr/bin/time -p`
(real, user, sys). Verdict: median `user` B/A <= 1.05 (`real` too, if `user` agrees). Arm
check (cheap, tells the arms apart): `$GODOT --headless -s` a 3-line probe printing
`TraitCatalog.ids()`: B prints 5 ids, A errors. Also: `RUN` lines of A and B identical
(`diff`), a second proof that behaviour did not change. Golden runs in the verify slice.

## 6. Open questions for the owner

**Q1. Pending traits (tower_harass, tower_lift, regen).**
- **Stay pending: schema files now, behaviour in their own content tasks (Recommended).**
  Benefit: golden stays byte-identical; each trait gets a spec (harass/lift semantics are
  undefined) and a deliberate golden regen. Risk: the seam for tower writers stays untested by
  a real trait until the harass task.
- Wire regen now (enemy-only, simplest). Benefit: one real `on_tick` user. Risk: golden regen
  in this task; balance shift (shoggoth) without a balance pass.

**Q2. Trait registry shape.**
- **One file per trait + one line in `TraitCatalog.SCRIPTS` (Recommended).** Benefit: the
  line sets the catalog (dispatch) order explicitly; no directory scan, export-safe. Risk:
  two edits per trait (file + line).
- Auto-discover files in `sim/core/traits/`. Benefit: truly one file. Risk: order from file
  names, and `DirAccess` on exported `.gd`/`.gdc` is fragile.

**Q3. Add `trait_host.gd` to G12 now (T7)?**
- **Yes: `modify_tower` exists now, unused (Recommended).** Benefit: the harass task is one
  trait file. Risk: dormant code, covered only by the probe-trait test.
- No: the harass task adds `modify_tower` and the G12 line. Benefit: no dormant code. Risk:
  harass touches 3 files instead of 1.

**Q4. Hooks on fakes.**
- **All hooks run for fakes except `on_leak`; their RNG on SANITY (Recommended).** Benefit: a
  fake behaves like the real enemy (LT-12), real streams untouched. Risk: a future harassing
  fake debuffs towers for real; that task decides whether harass skips fakes.
- Hooks never run for fakes. Benefit: fakes cannot affect towers. Risk: a fake pack would no
  longer be a pack (today it is), so pack needs an exception.
