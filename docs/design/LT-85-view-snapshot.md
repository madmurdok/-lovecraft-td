# LT-85: read-only snapshot for presentation (LT-65 B12, LT-33 finding 6)

Status: design (slice S1), approved. No code changed. Branch `release-0.13.0`.

## 0. Owner decisions

- Q1 (scope, §6): **"Полный снимок, G16 запрещает .state"**, option B: entities and scalars
  are both in the snapshot, and G16 bans `.state` in presentation code.
- Design doc: **"Утверждаю (Recommended)"**.
- LT-66 Q2 (whether the monster card shows a revealed fake): **"Да, как на карте (Recommended)"**.
  This is LT-66's decision; LT-85 only supplies the `revealed` field.

Sources: `docs/design/LT-65-architecture-review.md` §5 B12; `docs/design/LT-33-sim-presentation-boundary.md`
finding 6; LT-12 (fakes), LT-35 (BoardView), LT-84 (board layers, SelectionModel), LT-38 / LT-62
(frame-time diagnoses). Read inventory by grep plus a per-function scan of `scenes/` and `ui/`
(g-mesh has no GDScript plugin: it indexes go, python, rust and typescript only).

## 1. Decisions in short

| # | Decision | Why |
|---|---|---|
| D1 | `Simulation.snapshot() -> SimSnapshot`: a fresh, pure copy of the **entities** presentation draws or inspects (enemies, towers, allies), as typed records `EnemyRecord`, `TowerRecord`, `AllyRecord` under `sim/view/`. No record holds a `SimEnemy`/`SimTower`/`SimAlly`, and `EnemyRecord` has no `is_fake` and no `status`. | The fake rule then holds by shape: a presentation script has no handle that can reach `is_fake`. |
| D2 | The scalars presentation reads (`tick`, `phase`, `outcome`, `gold`, `sanity`, `oil`, `map`, ...; §3.4) are copied into the same `SimSnapshot` (owner Q1 = B). Presentation does not read `sim.state` at all. | There is one read source, the guard is a single `\.state\b` rule, and it is the cleanest base for the LT-64 view. The cost is the migration: 95 scalar read lines in 16 files (§2.2) and the UI tests that poke state (§2.3). |
| D3 | `Game` owns one shared snapshot, `game.snapshot`, rebuilt only on frames where the sim changed (steps > 0 or a command applied). `Game.refresh_snapshot()` exists for tests. `Simulation.snapshot()` itself keeps no cache. | Every reader in a frame shares one build. The build count is about the tick rate (30/s, 60/s at x2), never one per reader. The sim stays free of cache state, so determinism and golden traces are unaffected. |
| D4 | Records keep the previous and current position, so frames between ticks interpolate with the clock alpha and need no rebuild. `EnemyRecord.position(alpha)` follows the route exactly as `Simulation.enemy_position` does today. | No visual change, and existing position assertions keep passing. |
| D5 | Rule-derived numbers the UI would otherwise re-derive are computed in the sim at build time: effective speed (cells/s), effective armour, `madness_buffed`, `markers`. | Guard G1 (no rule copies in `ui/`), and LT-66's card needs them. |
| D6 | The debug reveal becomes an id query, `Simulation.debug_is_fake_id(id) -> bool` (same gate: `debug_reveal_fakes`), not a record field. | No field on any record differs between a real enemy and a fake. |
| D7 | Tower queries that take a `SimTower` get id-based forms for presentation: `upgrade_branches_of(id)`, `upgrade_target_of(id, branch)`, `has_targeting_of(id)`, `sell_refund_of(id)`. The `SimTower` forms stay for sim, bots and tests. | Matches the existing presentation pattern (`can_upgrade(id)`, `tower_mults(id)`). |
| D8 | New guard G16 (architecture guard). Code in `scenes/` and `ui/` must not name: `.state` (any member access); `SimState` except its enums; `SimEnemy`, `SimAlly`, `SimTower`, `SimBlast` or `RelicToken`; any entity-returning query. The `render_isolation_test` name scan stays as a second check. | The record shape (D1) plus the reach guard (D8) is the type-level enforcement LT-33 #6 asked for. Because `.state` is banned outright, no alias tracking is needed. |

Naming: "view" is already the BoardView (`view.cell_to_world` in every board layer), so the
snapshot is `SimSnapshot` and the records are `*Record`.

## 2. What presentation reads today

### 2.1 Live entity reads (all migrate)

| file:line | function | reads |
|---|---|---|
| scenes/board/entity_layer.gd:89-102 | `_draw` | `game.sim.state`, `s.towers` (94) |
| scenes/board/entity_layer.gd:103-114 | `ward_alpha(t: SimTower)` | `t.centre()`, `t.stats().range_cells` |
| scenes/board/entity_layer.gd:123-158 | `plate_color`, `_plate_tint`, `state_border` (static, `SimTower`) | `t.lit`, `t.shadowed`, `t.disabled` |
| scenes/board/entity_layer.gd:165-199 | `_draw_tower` | `t.post`, `t.cell`, `t.def.glyph`, `t.lit`, `t.shadowed`, `t.level`, `t.branch` |
| scenes/board/entity_layer.gd:200-237 | `_draw_post` | `t.cell`, `t.crew`, `t.lit`, `t.shadowed` |
| scenes/board/entity_layer.gd:238-282 | `_draw_auras`, `_draw_searchlight` | `s.towers` (239), `t.centre()`, `t.stats()` |
| scenes/board/entity_layer.gd:283-348 | `_draw_enemies` | `s.enemies` (288), `is_live()`, `sim.enemy_position(e, alpha)` (291), `LookCatalog.enemy_look(e)` (294), `e.revealed` (299, 330), `e.markers()` (308), `sim.debug_is_fake(e)` (335), `e.hp / e.max_hp` (340), `e.id` |
| scenes/board/entity_layer.gd:349-375 | `_draw_allies` | `s.towers` (350), `s.allies` (356), `sim.ally_position(a, alpha)` (359), `a.source`, `a.held_id`, `a.flying`, `a.hp`, `a.max_hp` |
| scenes/board/fx_layer.gd:97-149 | `on_event` | `sim.tower_by_id(ev.id)` (100), `t.stats()` (108, 115), `t.id` (117) |
| scenes/board/fx_layer.gd:164-238 | `_shot_fx(t: SimTower, ...)` | `t.id`, `t.centre()`, `t.stats().effects`; `sim.enemy_by_id` + `enemy_position(e, 1.0)` (188-190) |
| scenes/board/fx_layer.gd:260-271 | `_hit_positions` | `sim.enemy_by_id` + `enemy_position(e, 1.0)` (263-265) |
| scenes/board/fx_layer.gd:485-517 | `_draw_beam` | `sim.enemy_by_id` (489), `is_live()`, `enemy_position(e, alpha)` (491) |
| scenes/board/overlay_layer.gd:34-41 | `selected_dead_zone` | `sim.tower_at_cell(sel.cell)` (38), `t.stats()` |
| scenes/board/overlay_layer.gd:53-62 | `preview_cast(t: SimTower)` | `t.cell`, `t.centre()` |
| scenes/board/look_catalog.gd:144-159 | `tower_look(t: SimTower)`, `enemy_look(e: SimEnemy)` | `t.def.id`, `t.stats()`, `e.def` |
| scenes/board.gd:144-147 | `shot_kind(t: SimTower)` | forwards to `tower_look` |
| scenes/lighting.gd:203-223 | `_sync_tower_lights` | `sim.state.towers` (205), `t.id`, `t.cell` |
| ui/crew_panel.gd:87-95 | `on_duty` | `sim.state.towers`, `t.crew_kind`, `t.post`, `t.def.id`, `t.crew` |
| ui/tower_panel.gd:113 | `_ready` | `SimTower.TARGET_PRIORITIES` |
| ui/tower_panel.gd:129-138 | `open_for` | `sim.tower_by_id` (130), `t.cell` |
| ui/tower_panel.gd:178-235 | `_rebuild` | `sim.tower_by_id` (181), `t.stats()`, `t.level`, `t.def`, `t.post`, `t.crew_kind`, `t.id`; `upgrade_branches(t)` (186), `upgrade_target(t, ..)` (211), `sell_refund(t)` (226) |
| ui/tower_panel.gd:240-257 | `_refresh_upgrade(.., t: SimTower, ..)` | `t.id`, `t.level` |
| ui/tower_panel.gd:258-324 | `_refresh_table(t: SimTower, ..)` | `t.def`, `t.level`, `t.lit`, `t.shadowed`, `t.id`; `upgrade_target(t, ..)` (267), `has_targeting(t)` (322) |
| ui/tower_panel.gd:325-348 | `_refresh_priority(t: SimTower)` | `has_targeting(t)` (326), `t.target_priority`, `t.id` |

Events are not state reads: `SHOT`, `DIED`, `FAKE_DISSOLVED`, relic `TOKEN_*` and blast data
reach presentation through `drain_events` and stay as they are (relic tokens and blasts are
read only from events, never from `state.relic_tokens` / `state.blasts`).

### 2.2 Scalar and container reads (migrate too: owner Q1 = B)

These are 95 lines in 16 files (grep for `sim.state` and for its local aliases `s` / `st`). Line
numbers are on `release-0.13.0`. The function ranges come from the per-function scan.

| file | functions (range) | lines | fields |
|---|---|---|---|
| scenes/board.gd | `sync_map` 117-122 | 119, 120 | `map` |
| scenes/board/fx_layer.gd | `on_event` 97-149, `tick` 150-163, `_draw_charge` 610-650 | 136, 141, 142, 154, 612 | `map`, `tick` |
| scenes/board/overlay_layer.gd | `_draw` 13-33, `preview_cast` 53-62 | 17, 24, 57, 58, 61 | `map`, `phase` (alias `s`) |
| scenes/board/phantom_layer.gd | `_new_phantom` 47-75 | 49, 50, 67 | `map`, `tower_at` (alias `s`) |
| scenes/game.gd | `spike_context` 128-143, `_consume_events` 193-222, `open_crew_panel` 240-245, `_on_cell_clicked` 246-256 | 129, 133-136, 216, 242, 248, 250, 252-254 | `tick`, `sanity_state`, the `enemies`/`towers` counts, the whole state passed to `show_result`, `outcome`, `map`, `tower_at` |
| scenes/game_commands.gd | `skip_ahead` 28-37 | 31 | `phase` |
| scenes/lighting.gd | `setup` 64-73, `_ready` 83-106, `ease_night` 116-123, `_sync_beams` 141-167, `_sync_flare` 168-177, `_sync_tower_lights` 203-223 | 68, 84, 117, 144, 171, 217 | `phase`, `map` |
| scenes/relic_tokens.gd | `tick` 70-83, `progress` 94-103 | 78, 98 | `tick` |
| scenes/sanity_fx.gd | `tick` 95-105, `_snap` 106-113, `target_level` 114-129 | 96, 97, 107, 115, 116, 124 | `sanity`, `sanity_state` |
| ui/end_screen.gd | `show_result(won, s: SimState, ..)` 30-47 | 34, 37, 39, 40 | `waves_total`, `wave_index`, `relics` |
| ui/hud.gd | `on_stepped` 248-254, `_refresh_purse` 276-280, `_refresh_hp` 296-303, `_refresh_phase` 304-316, `_refresh_sanity` 325-342, `_refresh_flare` 370-404, `_cooldown_secs(s: SimState)` 421-425, `_flare_key` 426-432, `sanity_tooltip` 489-516, `phase_text(s: SimState)` 517-529, `relics_text` 535-542, `relics_tooltip` 560-568 | 249, 278, 298, 306, 311-314, 327, 328, 331, 373, 374, 376, 382, 384, 389, 422, 427, 428, 493, 518, 520, 521, 523, 537, 538, 563 | `build_ticks_left`, `gold`, `lighthouse_hp`, `phase`, `night_luck`, `outcome`, `sanity_state`, `oil`, `flare_ticks_left`, `flare_cooldown_ticks`, `sanity_cap`, `wave_index`, `waves_total`, `relics` |
| ui/lighthouse_panel.gd | `open` 52-58, `_refresh_head` 114-121, `_refresh_upgrade` 122-141, `_refresh_oil` 142-164 | 54, 117, 125, 150 | `map`, `lighthouse_level`, `oil` |
| ui/sanity_bar.gd | `fill_ratio` 64-69, `cap_ratio` 70-75, `label_text` 76-86, `_draw` 105-142 | 65, 66, 71, 77, 79-83, 108, 109 | `sanity`, `sanity_cap`, `sanity_state` |
| ui/side_panel.gd | `_ready` 72-126 | 73 | `map` |
| ui/tower_panel.gd | `_refresh_table` 258-324 | 260 | `sanity` |
| ui/tower_picker.gd | `_layout_rows` 182-207, `refresh` 358-426, `_refresh_posts` 468-494 | 185, 399, 410, 469 | `phase` |

Three static or typed signatures take `SimState` and change to `SimSnapshot`:
`Hud._cooldown_secs`, `Hud.phase_text` and `EndScreen.show_result`. Enum reads
(`SimState.Phase.*`, `SimState.Outcome.*`, `SimState.SanityState.*`, `Lighting.night_target(phase:
SimState.Phase)`, `WhisperAudio.set_state(s: SimState.SanityState)`) stay allowed.
Out of scope: `sim.config.*` reads (static data) and sim queries that return values
(`beam_directions`, `flare_burn`, `can_*`, `exit_target`, `crew_reserve`, ...).

### 2.3 Tests that poke state and then read presentation

32 test files build a `Game` and read or write `sim.state`. 23 of them write it (about 125
lines; most of the writes are in `picker_overlay_test` 21, `side_panel_test` 19,
`tower_picker_groups_test` 17, `sim_rule_queries_test` 12, `reserve_ui_test` 7,
`tower_attack_visuals_test` 5 and `sim_boundary_test` 5). After option B, a poke followed by a
panel or layer read sees the old snapshot, so these tests need a refresh.

- Helper: `Game.refresh_snapshot()` is public. `GameFixture` adds `static func sync(game)`
  as a one-line alias, so tests read the same everywhere. The rule: **after a block of
  `sim.state` / entity pokes, call `GameFixture.sync(game)` before the next presentation
  call.** Calls that already rebuild (`game.advance(..)` with a step, commands through
  `Game`/`GameCommands`) need no sync.
- Tests that poke the sim and assert only on the sim (`sim_rule_queries_test`, the
  `sim_boundary_test` frame runs, the `architecture_guard_test` probes) need no change. The
  slice confirms each one.
- A missed sync fails loudly: the assertion sees the old value. The exception is a test that
  asserts "unchanged". The verify slice reviews those by grep: a poke with no `sync` before an
  `is_equal` on a panel or label.

## 3. Record shapes

All under `sim/view/`, `extends RefCounted`, plain `var`s documented read-only. Built only by
`Simulation.snapshot()`; each `from_*` static lives in the record's file and is the only code
that touches the live object. Immutable config references (`EnemyDef`, `TowerDef`,
`TowerDef.Level`, `MapDef`, `SimRoute`) are allowed: they are shared by every instance of a
kind, so a real enemy and a fake of the same kind share them.

### 3.1 `EnemyRecord`

| field | type | from | used by |
|---|---|---|---|
| `id` | int | `e.id` | `last_pos`, events, LT-66 selection |
| `def` | EnemyDef | `e.def` | looks (`LookCatalog.enemy_look`), card: `name`, `flying`, `traits`, base `armor`, `horror_drain` (def value only) |
| `hp`, `max_hp` | float | live | HP bar, card |
| `speed` | float | `roundi(base_units_per_tick * speed_mult) * TICK_RATE / UNITS_PER_CELL` | card: speed now (slows, holds, madness) |
| `base_speed` | float | `base_units_per_tick * TICK_RATE / UNITS_PER_CELL` | card: speed with the wave multiplier, no per-tick modifiers |
| `armor` | float | `maxf(0, def.armor + armor_bonus)` (the combat formula) | card |
| `markers` | PackedStringArray | `e.markers()` | marker drawing (replaces the per-frame call) |
| `madness_buffed` | bool | `SimEnemy.madness_buffed`: set by `apply_madness_buff` in slot 2 (MADNESS, multipliers != 1, not `madness_buff_blocked(e)`), reset in slot 1; so it agrees with `speed` on the tick sanity enters or leaves MADNESS (S12, review SF1) | card |
| `lit` | bool | `e.lit` | card (optional), future view |
| `revealed` | bool | `e.revealed` | revealed-fake look (a game rule: a revealed fake is shown) |
| `prev_distance`, `distance` | int | live | interpolation |
| `_route` | SimRoute | `e.route` | `position(alpha)` |
| `pos` | Vector2 | `route.position_at(distance)` | `enemy_position(e, 1.0)` callers (fx hits, chains) |

Method `position(alpha) -> Vector2` = `_route.position_at(roundi(lerpf(prev_distance, distance, alpha)))`,
the exact `Simulation.enemy_position` formula (D4). Only live enemies are in the snapshot
(today every reader skips `not is_live()`).

Left out on purpose: `is_fake`, `status` (G14), `dissolved`/`dead`/`leaked` (never live),
`spawn_tick`, `pack_of`, `base_max_hp`, the per-tick multipliers themselves (`speed_mult`,
`damage_taken_mult`, `armor_bonus`: the derived `speed`, `armor`, `markers` cover them).

### 3.2 `TowerRecord`

`id`, `def: TowerDef`, `cell: Vector2i`, `centre: Vector2`, `level`, `branch`, `stats:
TowerDef.Level` (= `t.stats()`), `post`, `crew`, `crew_kind`, `lit`, `shadowed`, `disabled`,
`target_priority`, and `const TARGET_PRIORITIES = SimTower.TARGET_PRIORITIES`. Left out:
`cooldown_ticks`, `burst_index`, `locked_id`, `spent`, the modifier fields (the panel reads
`tower_mults(id)`), `lift_ticks_left`.

### 3.3 `AllyRecord`

`id`, `tower`, `source`, `prev_pos`, `pos`, `hp`, `max_hp`, `flying`, `held_id`;
`position(alpha) = prev_pos.lerp(pos, alpha)` (the `AllySystem.ally_position` formula). Live only.

### 3.4 `SimSnapshot`

Entities: `enemies: Array[EnemyRecord]`, `towers: Array[TowerRecord]` and `allies:
Array[AllyRecord]`, each live only and in id order. Lookups: `enemy(id)`, `tower(id)` and
`tower_at(cell)`, which return null when absent. They are backed by dictionaries built once per
snapshot. `tower_at(cell)` replaces `state.tower_at.has / [cell]`.

Scalars, copied from `SimState` (owner Q1 = B; this is the full list of what §2.2 reads):

| field | type | readers |
|---|---|---|
| `tick` | int | fx_layer, relic_tokens, game.spike_context |
| `outcome` | SimState.Outcome | game, hud |
| `phase` | SimState.Phase | overlay, lighting, game_commands, hud, tower_picker |
| `wave_index`, `waves_total` | int | hud.phase_text, end_screen |
| `build_ticks_left` | int | hud |
| `gold` | int | hud |
| `relics` | Dictionary[String, int] (a `duplicate()`) | hud, end_screen |
| `sanity`, `sanity_cap` | float | sanity_fx, sanity_bar, hud, tower_panel |
| `sanity_state` | SimState.SanityState | sanity_fx, sanity_bar, hud, game |
| `lighthouse_hp`, `lighthouse_level` | int | hud, lighthouse_panel |
| `night_luck` | float | hud |
| `oil`, `flare_ticks_left`, `flare_cooldown_ticks` | int | hud, lighthouse_panel |
| `map` | MapDef (shared reference, immutable config) | board, layers, lighting, side/lighthouse panel, game |

Not copied, because presentation does not read them: `crew` (it reads the `crew_reserve()`
query), the beam fields (it reads the `beam_directions(alpha)` query), `command_log`,
`next_*`, `relic_tokens`, `blasts`. A future reader adds a field together with its pin in the
shape test (§5.1).

## 4. Build and cost

Options considered:

| option | builds per second | staleness risk | verdict |
|---|---|---|---|
| (a) every reader calls `sim.snapshot()` | readers x frames: entity, fx, overlay, lighting, tower/crew panel ~ 4-6 per frame | none | rejected: multiplies the cost by the reader count |
| (b) cache inside `Simulation`, keyed by a version bumped on step / command / emit | <= ticks | a mutation that bumps nothing (test pokes, a new public mutator) serves stale data silently | rejected: the invalidation is spread over the sim and easy to miss |
| (c) **`Game` owns one snapshot, rebuilt on changed frames** | <= min(frames, ticks + commands) | only out-of-band writes; the fix is one explicit `refresh_snapshot()` | **chosen** |

Rebuild points in `Game`: in `advance()` right after the steps and before `_consume_events`
when `steps > 0`; in `_after_command()` before `_consume_events`; once in `setup()`/`_ready()`.
Event consumers (`fx_layer.on_event`) and panel flushes then read the post-step state, as
they read it today. Paused frames and frames between ticks reuse the snapshot; `alpha`
interpolation needs no rebuild (D4).

Scalars add about 20 field copies and one small `relics.duplicate()` per build, which is
negligible next to the records. With option B, the rebuild points carry more weight: every
HUD and panel read goes through `game.snapshot`, so a command must rebuild before
`_flush_ui` (it does, in `_after_command`). `Game.setup` must build the first snapshot before
any child's `_ready` or `setup` reads it (`Lighting.setup` reads `phase` at 68).

Cost reasoning (estimate, to be measured in verify): LT-38/LT-62 show 6-12 live enemies on
average (wave 4, draws 715-835) and GDScript work of 3-5 ms per frame against a 15-20 ms
frame dominated by render + present; `Board._draw` is ~3 ms. A snapshot of ~100 records
(late waves, ~20 towers, a few allies) is ~100 `RefCounted.new()` plus ~15 field copies each.
Part of it is moved, not added: `e.markers()` (a Dictionary walk) and the `enemy_position`
calls already run per frame per enemy today and move to once per tick. Budget for the
verify measure: `Simulation.snapshot()` at >= 60 enemies + 20 towers under 0.5 ms median on a
quiet machine (record `uptime` and `/usr/bin/time -p` with it), and the LT-62 bot run's frame
median within noise of the baseline (`-- --mute`).

`snapshot()` must be pure: no RNG draw, no state write, no event. It reads
`SimEnemy.madness_buffed` (a field) and `SimEnemy.markers()` (pure).

## 5. Enforcing "no fake leak" by shape

1. **Shape test** (new `tests/sim_snapshot_test.gd`): the script property names of
   `EnemyRecord`, `TowerRecord`, `AllyRecord`, `SimSnapshot` equal pinned allowlists (§3), no
   name contains `fake`, and no property's class is `SimEnemy`, `SimTower`, `SimAlly`,
   `SimState`, `Simulation` or a system (allowed object classes: `EnemyDef`, `TowerDef`,
   `TowerDef.Level`, `SimRoute`, `MapDef`, the record classes). Adding a field means editing
   the pin, which a review sees.
2. **Equality test**: spawn a real and a fake of one kind on the same tick (`spawn_enemy(id)`,
   `spawn_enemy(id, true)`), run ticks covering a slow aura, a MADNESS tick and a lit tick;
   at every tick the two `EnemyRecord`s are equal on every property except `id` (position
   via `position(0.5)` too). This is the "cannot tell real from fake" rule as a test, and it
   covers every field LT-66 adds later.
3. **Reach guard G16** goes in `tests/architecture_guard_test.gd` and has the usual
   planted-probe self-test. It scans `scenes/` and `ui/` code with comments and strings
   blanked (the `_code_lines` scan). The code must contain none of these:
   - `\.state\b`, any member access named `state`. On today's tree every match in
     presentation is `sim.state`: no other presentation object has a `.state` member
     (checked by grep). Aliases then cannot exist, because making one means writing
     `.state`. `.sanity_state` and `set_state(` do not match.
   - `\bSimState\b(?!\.(Phase|Outcome|SanityState)\b)`, the class except its enums.
   - `\b(SimEnemy|SimAlly|SimTower|SimBlast|RelicToken)\b`.
   - `\b(enemy_by_id|enemy_position|ally_by_id|ally_position|allies_of|tower_by_id|tower_at_cell|enemies_in_range|enemies_near|debug_is_fake)\s*\(`.
   - `\b(upgrade_branches|upgrade_target|has_targeting|sell_refund)\s*\(`, the SimTower
     forms; the `*_of` forms do not match because `\b` needs a word end.

   The probes, one per rule: `game.sim.state.gold`, `var s := game.sim.state`,
   `func f(s: SimState)`, `for e: SimEnemy in x`, `sim.enemy_by_id(3)`, `sim.sell_refund(t)`.
   It must not fire on `SimState.Phase.BUILD`, `sanity_fx.sanity_state`, `sell_refund_of(id)`
   or `debug_is_fake_id(id)`. `tools/` is out of the scan: bots are players with full rules
   access.
4. **`render_isolation_test`**: keep the `FORBIDDEN` name scan and the debug-gate tests;
   add `debug_is_fake_id` to `test_the_patterns_tell_a_fake_reference_from_the_debug_accessor`
   (must not match `\bis_fake\b`); `test_a_game_started_without_the_flag_does_not_reveal_fakes`
   also asserts `debug_is_fake_id` is false for a fake id. `sim_boundary_test.test_the_is_fake_leak_guard_is_kept_and_presentation_is_clean`
   additionally checks that `architecture_guard_test.gd` still contains the G16 test.

## 6. Owner questions

**Q1. Scope of the snapshot.** Decided: B (§0). The options are kept for the record.
- **(A) Entities only; scalars stay on `sim.state` (Recommended).** Benefit: closes the fake
  path completely (every enemy handle is a record); ~8 production files and ~8 test files;
  scalar test pokes keep working. Risk: presentation still reads `sim.state` for scalars, so
  "presentation never sees SimState" is not literally true; a future 3D view reads two sources.
- **(B) Full snapshot (entities and scalars); G16 bans `.state` in presentation.** Benefit:
  one read source, a one-line guard, the cleanest base for LT-64's view. Risk: ~60 more read
  sites in 17 files, and ~19 UI test files (~300 scalar pokes) need `refresh_snapshot()`
  after each poke; a missed one is a stale-UI test failure, not a silent bug, but it is churn.
- **(C) Records only for enemies.** Benefit: smallest change, still closes the fake path.
  Risk: towers and allies stay live objects in panels and layers, so B12 ("no live sim
  objects") is half done and G16 cannot ban `SimTower`.

**Q2. Revealed fakes on the LT-66 card.** The record carries `revealed` (the board already
draws a revealed fake differently, LT-49). Should the card say so ("Hallucination")?
- **(a) Yes, same as the board (Recommended).** Benefit: consistent with the board; the
  reveal is a rule the player earned. Risk: none for the fake rule (a revealed fake is
  meant to be told apart).
- **(b) No, the card ignores `revealed`.** Benefit: simpler card. Risk: the board and the card disagree.
Decided by the owner for LT-66 (§0): "Да, как на карте (Recommended)". LT-85 only guarantees that the field exists.

## 7. LT-66 monster card coverage

| card field | record field | real vs fake |
|---|---|---|
| name | `def.name` | same def |
| HP | `hp`, `max_hp` | same wave multiplier, same damage rules |
| speed | `speed` (now), `base_speed` | same `base_units_per_tick` and per-tick modifiers |
| armour | `armor` (effective), `def.armor` (base) | same |
| flying / ground | `def.flying` | same |
| traits | `def.traits` keys | same def. A trait that acts only on real enemies (e.g. `tower_lift_trait.gd:46` skips fakes) must be shown from the def, never from its live effect |
| madness buff | `madness_buffed` | applied to real and fake alike (`SanitySystem.apply_madness_buff`) |

Alignment with `docs/design/LT-66-overlay-panel.md` §5 (written in parallel):
- LT-66 asks for `def_id`; the record gives `def` (`def.id` is the same id, and the card
  needs the def's name, flying, base numbers and traits anyway).
- LT-66 calls the flag `mad_buffed`; this design calls it `madness_buffed`. LT-66/S2 uses
  the LT-85 name.
- LT-66 writes current speed as `def.speed * speed_mult`. The record's `speed` uses the
  units the sim moves by (`roundi(base_units_per_tick * speed_mult)`), which includes the
  wave's speed multiplier (LT-111) and the per-tick rounding; `base_speed` is the
  wave-scaled speed without per-tick modifiers. The card's "(base X)" should be `base_speed`,
  or `def.speed` if the owner wants the unscaled kind value.
- If LT-66/S2 lands first with its adapter (`ui/model/monster_card_model.gd` reading
  `SimEnemy`), G16 (S3) fails on it by design; S3 then switches the adapter to
  `game.snapshot.enemy(id)`, and the adapter goes on S3's edit list.

Not on the card: live horror drain (fakes drain nothing, `sanity_system.gd:254`), relic drops
(ghost loot), leak damage outcome. Showing any of those per enemy would tell a fake; the card
shows def values only. The equality test (§5.2) pins this for every record field.

## 8. Edit map

### Slice S2 (code, sim side): records, `snapshot()`, id queries

| file | change | lines |
|---|---|---|
| `sim/view/enemy_record.gd` (new) | `EnemyRecord` + `static from_enemy(e, buffed)` + `position(alpha)` | - |
| `sim/view/tower_record.gd` (new) | `TowerRecord` + `static from_tower(t)` | - |
| `sim/view/ally_record.gd` (new) | `AllyRecord` + `static from_ally(a)` + `position(alpha)` | - |
| `sim/view/sim_snapshot.gd` (new) | container: the §3.4 scalars, the entity arrays, and the lookups `enemy(id)`, `tower(id)`, `tower_at(cell)` | - |
| `sim/core/simulation.gd` | add `snapshot()` next to `enemy_position` | after 764-768 |
| `sim/core/simulation.gd` | add `upgrade_branches_of`, `upgrade_target_of` | after 260-282 |
| `sim/core/simulation.gd` | add `has_targeting_of` | after 359-366 |
| `sim/core/simulation.gd` | add `sell_refund_of` | after 687-690 |
| `sim/core/simulation.gd` | add `debug_is_fake_id(id)` | after 874-876 |

Read for context: `sim/core/sim_enemy.gd` (`markers`, `is_live`), `sim/core/sim_tower.gd:67-109`
(`stats`, `centre`), `sim/core/systems/sanity_system.gd:268-290`, `sim/core/systems/ally_system.gd:77-78`,
`sim/core/sim_route.gd:35-50`, `sim/core/systems/spawn_system.gd:102-131, 145-152` (speed units).
New `class_name`s are own types, so `sim_boundary_test`'s allowlist needs no change.

### Slice cut (option B)

| slice | scope | depends on | tests it migrates itself |
|---|---|---|---|
| S2 code, sim side | the records, `SimSnapshot` with its scalars, `snapshot()`, the `*_of(id)` queries, `debug_is_fake_id` (table above) | - | none (additive) |
| S3 code, `scenes/` | `Game.snapshot` and its rebuild points, `GameFixture.sync`, every `scenes/` reader (entities and scalars) | S2 | scene-side tests that break |
| S4 code, `ui/` + guard | every `ui/` reader, `Hud.phase_text`/`_cooldown_secs`, `EndScreen.show_result`, then G16 and the §5.4 edits | S3 | UI tests that break |
| tests | new `tests/sim_snapshot_test.gd` and the §9 behaviour tests not already written | S4 | - |
| verify | full suite, controls, 5x repeats, the cost measure (§4) | tests | - |

Test migration is **not a slice of its own**. A code slice that retypes a function or moves
a reader to the snapshot leaves the tests that call it red. Each code slice therefore fixes
the tests it breaks (retyped call sites, `GameFixture.sync` after pokes), so it can run its own
touched tests green before hand-off. The new behaviour tests (§9) go in the tests slice.
Splitting `scenes/` from `ui/` keeps each code slice to about 10 production files. Both share
the `Game` changes, so S4 waits for S3. G16 lands last, in S4, because it only passes once every
reader has moved.

### Slice S3 (code, `scenes/`): Game snapshot, scene readers

| file | function | lines | change |
|---|---|---|---|
| `scenes/game.gd` | vars, `setup`, `advance`, `_after_command` | 20-48, 49-67, 144-167, 185-191 | `snapshot: SimSnapshot` and `refresh_snapshot()`. Rebuild points as in §4; the first build in `setup` happens before the children read it |
| `scenes/game.gd` | `spike_context`, `_consume_events`, `open_crew_panel`, `_on_cell_clicked` | 128-143, 193-222, 240-245, 246-256 | snapshot scalars and counts; `snapshot.tower_at(cell)`; `show_result(won, snapshot, ..)` |
| `scenes/game_commands.gd` | `skip_ahead` | 28-37 | `snapshot.phase` |
| `scenes/board.gd` | `sync_map`, `shot_kind` | 117-122, 144-147 | `snapshot.map`, `TowerRecord` |
| `scenes/board/entity_layer.gd` | `_draw`, `ward_alpha`, `plate_color`, `_plate_tint`, `state_border`, `_draw_tower`, `_draw_post`, `_draw_auras`, `_draw_searchlight`, `_draw_enemies`, `_draw_allies` | 89-375 | `SimTower` -> `TowerRecord`, `SimEnemy` -> `EnemyRecord`, `SimState` param -> `SimSnapshot`; `t.stats()` -> `t.stats`, `t.centre()` -> `t.centre`, `e.markers()` -> `e.markers`; `enemy_position(e, alpha)` -> `e.position(alpha)`; `debug_is_fake(e)` -> `debug_is_fake_id(e.id)` |
| `scenes/board/fx_layer.gd` | `on_event`, `tick`, `_shot_fx`, `_hit_positions`, `_draw_beam`, `_draw_charge` | 97-149, 150-163, 164-238, 260-271, 485-517, 610-650 | `snapshot.tower(id)`, `snapshot.enemy(id)`, `.pos`, `.position(alpha)`, `snapshot.map`, `snapshot.tick` |
| `scenes/board/overlay_layer.gd` | `_draw`, `selected_dead_zone`, `preview_cast` | 13-33, 34-41, 53-62 | `snapshot.map`, `snapshot.phase`, `snapshot.tower_at(cell)`, `TowerRecord` |
| `scenes/board/phantom_layer.gd` | `_new_phantom` | 47-75 | `snapshot.map`, `snapshot.tower_at(c) != null` |
| `scenes/board/look_catalog.gd` | `tower_look`, `enemy_look` | 144-159 | record parameter types |
| `scenes/lighting.gd` | `setup`, `_ready`, `ease_night`, `_sync_beams`, `_sync_flare`, `_sync_tower_lights` | 64-73, 83-106, 116-123, 141-177, 203-223 | `snapshot.phase`, `snapshot.map`, `snapshot.towers` |
| `scenes/relic_tokens.gd` | `tick`, `progress` | 70-83, 94-103 | `snapshot.tick` |
| `scenes/sanity_fx.gd` | `tick`, `_snap`, `target_level` | 95-129 | `snapshot.sanity`, `snapshot.sanity_state` |
| `tests/support/game_fixture.gd` | `make_game` + new `sync(game)` | 29-41 | §2.3 helper |

Tests S3 migrates. Retyped call sites (`game.snapshot.tower(id)` / records):
`light_shadow_render_test` 26, `tower_attack_visuals_test` 27, `look_catalog_test` 13,
`look_render_test` 6, `effect_mode_test` 4, `board_layers_test` 3, `ui_polish_test` 1 (`plate_color`).
`GameFixture.sync` after pokes in scene tests: `tower_attack_visuals_test`, `light_shadow_render_test`,
`look_render_test`, `board_layers_test`, `map_layer_test`, `board_view_test`, `lighting_test`,
`scene_game_test`, `sanity_feedback_test`. Also `lt62_fps_test` (`spike_context`).

### Slice S4 (code, `ui/`): UI readers, then G16

| file | function | lines | change |
|---|---|---|---|
| `ui/hud.gd` | `on_stepped`, `_refresh_purse`, `_refresh_hp`, `_refresh_phase`, `_refresh_sanity`, `_refresh_flare`, `_cooldown_secs`, `_flare_key`, `sanity_tooltip`, `phase_text`, `relics_text`, `relics_tooltip` | 248-254, 276-280, 296-316, 325-342, 370-432, 489-529, 535-542, 560-568 | `game.snapshot.*`; the static functions take `SimSnapshot` |
| `ui/sanity_bar.gd` | `fill_ratio`, `cap_ratio`, `label_text`, `_draw` | 64-86, 105-142 | `snapshot` scalars |
| `ui/tower_picker.gd` | `_layout_rows`, `refresh`, `_refresh_posts` | 182-207, 358-426, 468-494 | `snapshot.phase` |
| `ui/tower_panel.gd` | `_ready`, `open_for`, `_rebuild`, `_refresh_upgrade`, `_refresh_table`, `_refresh_priority` | 113, 129-138, 178-348 | `snapshot.tower(id)`, `TowerRecord`, `snapshot.sanity`, the `*_of(id)` queries |
| `ui/lighthouse_panel.gd` | `open`, `_refresh_head`, `_refresh_upgrade`, `_refresh_oil` | 52-58, 114-164 | `snapshot.map`, `lighthouse_level`, `oil` |
| `ui/crew_panel.gd` | `on_duty` | 87-95 | `snapshot.towers` |
| `ui/side_panel.gd` | `_ready` | 72-126 (line 73) | `snapshot.map` |
| `ui/end_screen.gd` | `show_result` | 30-47 | `s: SimSnapshot` |
| `tests/architecture_guard_test.gd` | new G16 + probe self-test | after G14, 1087-1110 | §5.3 |
| `tests/render_isolation_test.gd`, `tests/sim_boundary_test.gd` | as §5.4 | 44-52, 90-98; 896-906 | |

Tests S4 migrates, adding `GameFixture.sync` after pokes: `picker_overlay_test` (21 pokes),
`side_panel_test` (19), `tower_picker_groups_test` (17), `reserve_ui_test` (7),
`lighthouse_ui_test` (4), `crew_ui_test` (4), `stats_panel_test` (3), `relic_ui_test` (3),
`crew_source_ui_test` (2), `ui_polish_test` (2), `sanity_tooltip_test` (1). S4 also confirms
that `sim_rule_queries_test`, `sim_boundary_test` and `architecture_guard_test` poke only the
sim and need nothing. `debug_is_fake(e)` and the SimTower forms of the tower queries stay for
`tools/bot_runs.gd` and the sim tests.

## 9. Behaviours to pin, with controls

| # | behaviour (one line) | control revert (must make the test fail) |
|---|---|---|
| 1 | Record property sets equal the pinned allowlists; no `fake` name, no live-object class | add `var src: SimEnemy` (or `var is_fake`) to `EnemyRecord` |
| 2 | A real and a fake of one kind spawned on one tick have equal records except `id`, every tick, through slow, MADNESS and lit ticks | in `from_enemy`, `revealed = e.revealed or e.is_fake` |
| 3 | `EnemyRecord.position(alpha)` equals `Simulation.enemy_position(e, alpha)` for alpha 0, 0.5, 1 across a route corner; `pos` equals alpha 1 | interpolate `prev_pos.lerp(pos, alpha)` instead of along the route |
| 4 | `madness_buffed` is true for live unlit enemies in MADNESS (real and fake), false when lit with `cancel_madness_buff`, false outside MADNESS; `speed`/`armor` match the combat formulas | drop `e.madness_buffed = true` in `apply_madness_buff`, or derive the flag from `state.sanity_state` at build time (fails on the tick MADNESS starts) |
| 5 | `snapshot()` is pure: a seeded run calling it every tick has the same state digest, command log and event sequence as one that never calls it | call `_sanity.apply_madness_buff()` inside `snapshot()` |
| 6 | `game.snapshot` reflects a command at once, before the panels flush: after a build through `Game`, `snapshot.gold` drops and `snapshot.tower_at(cell)` is set without a step, and the HUD money label shows the new gold. After `advance`, it shows the post-step state | remove the rebuild from `_after_command` |
| 7 | G16 fires on each planted probe (`game.sim.state.gold`, `var s := game.sim.state`, `: SimState`, `: SimEnemy`, `enemy_by_id(`, `sell_refund(t)`), stays quiet on the allowed forms, and is clean on the tree | restore `game.sim.state.gold` in `Hud._refresh_purse` |
| 8 | Every scalar field equals its `SimState` field after every tick of a seeded run (BUILD, WAVE, MADNESS, flare, lighthouse upgrade), and tower flags equal `SimTower`'s | in the snapshot build, copy `sanity_cap = s.sanity` |

`debug_is_fake_id` (true only with the debug flag, and only for a fake id) is pinned by the
migrated `render_isolation_test` / `hallucination_test` cases, so it has no separate control.
Tower plate and light rendering from `TowerRecord` flags is pinned by the migrated
`light_shadow_render_test`, with no separate control. Tests 1-5 and 8 go in
`tests/sim_snapshot_test.gd`, test 6 in `tests/game_fixture_test.gd` or
`ui_event_refresh_test.gd`, and test 7 in `architecture_guard_test.gd`.

## 10. Out of scope and risks

- Events (`SHOT`, `FAKE_DISSOLVED`, token data) are a second channel to presentation. They are
  already designed to be the same for real and fake except `FAKE_DISSOLVED`, which is the
  visible dissolve; no change here.
- `tools/` (bots) keeps reading live state: bots are players with full rules access, not
  presentation.
- Risk (option B): a UI test that pokes state and asserts that a label is *unchanged* passes
  with a missing `GameFixture.sync`. Verify greps for this (§2.3).
- Risk: a reader that runs outside `advance`/`_after_command` (e.g. a panel opened by
  input between frames) reads the snapshot of the last changed frame. Nothing changes the
  sim between frames except commands, which rebuild, so the data is current.
