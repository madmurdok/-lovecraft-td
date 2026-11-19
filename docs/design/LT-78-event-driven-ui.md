# LT-78: event-driven UI, GameCommands, DebugArgs, G6 (B11)

Block B11 of `docs/design/LT-65-architecture-review.md` (§3.5, §3.8, §4 G6, §5). Owner Q3:
"Полностью на событиях". Panels stop being refreshed every frame from `Game.advance`; a
panel changes only when a sim event, a command or a presentation signal says something it
shows may have changed. Base: `release-0.5.0` at a8ac581.

## 0. Today, in one paragraph

`Game.advance` (scenes/game.gd:187-209) runs every frame and calls `hud.refresh()`,
`picker.refresh()`, `tower_panel.refresh()` and `lighthouse_panel.refresh()` unconditionally;
`_after_command` (316-322) does the same after each command. Each `refresh()` re-reads every
field from `sim.state` and the rule queries (`can_*`, `early_night_luck`, `tower_mults`, ...).
`SanityBar._process` (ui/sanity_bar.gd:41-43) redraws every frame. `SidePanel` already reacts
only to UI signals (`visibility_changed`, `hovered_changed`). Events reach the UI through one
drain (`Game._consume_events`, 325-343), consumed today only by board, sanity_fx,
relic_tokens and the OUTCOME branch. Every displayed state field has a writer that emits an
event (checked: `grep` of the writers in `sim/`), except three timers:
`build_ticks_left` (wave_director.gd:43), `flare_ticks_left` and `flare_cooldown_ticks`
(`_count_down_flare`, simulation.gd:1552).

## 1. Model: event invalidates, query reads

Each panel gets:
- `const REFRESH_ON: Dictionary[SimEvent.Type, int]`: event type -> bitmask of its field
  groups (constants `G_PURSE`, `G_PHASE`, ...).
- `on_event(ev)`: `_dirty |= REFRESH_ON.get(ev.type, 0)` and nothing else.
- `flush()`: if visible and `_dirty != 0`, rebuild only the dirty groups, from the same rule
  queries as today; `_dirty = 0`. Called by Game once after a drain, never per event, so a
  command that emits several events (call_wave: WAVE_STARTED, then `night_luck` is set)
  is read in its final state.
- `refresh()`: full sync of every group (today's body, split). Called on open, on
  `visibility_changed` to visible, and by the HUD in `Game._ready`. Tests may keep calling it.
- `on_stepped()`: only for groups that show a running timer (§1.1).

Values come from queries, not from event payloads: the payload is not a second source of the
rules (`can_build` alone depends on gold, phase, outcome and occupancy).

Game drives it: `_consume_events` passes every event to `hud`, `picker`, `tower_panel`,
`lighthouse_panel` (`on_event`), then `_flush_ui()` calls `flush()` on each. `advance` calls
`_consume_events` + `_flush_ui` only when `steps > 0` or the drain is non-empty, and
`on_stepped()` only when `steps > 0`. `toggle_speed`/`toggle_pause` emit a new Game signal
`speed_changed` that the HUD maps to `G_SPEED`. The board keeps its per-frame
`queue_redraw` (render, out of scope).

### 1.1 Timers and countdowns (the hard part)

Three fields tick: the day countdown ("night falls in 31 s", and "Light the lamp (luck ×1.62)",
whose luck is derived from the same whole seconds), and the flare button ("Flare burning" /
"Flare 12 s" / "Flare (2 oil)" and its `disabled`).

| Option | How | Benefit | Risk |
|---|---|---|---|
| A. Sim event per tick | `TIMER {kind, ticks_left}` every tick | purest | ~30 events/s for the whole run; every golden digest and bucket changes; log noise for bot and replays. Rejected. |
| B. Coarse sim events | `COUNTDOWN {kind, seconds}` at each whole-second change of a timer, plus `FLARE_ENDED`, `FLARE_READY` | every UI change is a sim event; replay shows timer state | sim code that exists only for the UI; ~(build seconds x days + cooldown seconds x flares) new events; all 10 `bot/*` and `frame_path` digests re-pinned (§2) |
| **C. Presentation clock (recommended)** | Timers start and stop on existing events (BUILD_STARTED, WAVE_STARTED, WAVE_CLEARED, FLARE_FIRED, OUTCOME). While a timer group is active, `on_stepped()` (only on frames with `steps > 0`) re-reads the timer query and rewrites the label only when the whole-second value or the burn/cooldown/ready state changed; it deactivates itself when the timer reads 0 | no sim change, golden byte-identical; idle frames do nothing; no copy of the countdown rule (reads `build_ticks_left`, `flare_burn()`, `flare_cooldown_ticks`) | not "pure": the timer groups run on every stepped frame while a timer runs (an int compare); flare end and cooldown end are not sim facts |
| C+. C plus two boundary events | as C, plus `FLARE_ENDED` and `FLARE_READY` sim events for the two flare transitions | the flare button's state flips are sim facts, testable in the sim | re-pins every bot run that fires a flare (§2) for a change the UI does not need |

Recommendation: C. Owner question Q1.

## 2. New sim events

Recommended option C adds **no** sim event; golden digests stay byte-identical. The candidate
events of the other options, for the owner's decision:

| Event | Payload, id | Emit site | Frequency | Golden / command log |
|---|---|---|---|---|
| `FLARE_ENDED` (B, C+) | `{}`, id 0 | `_count_down_flare` (simulation.gd:1552), when `flare_ticks_left` goes 1 -> 0 | 1 per flare | appended to the enum (values of old types unchanged); changes `events`, `events_sha`, buckets of every bot run that fires a flare (bots fire by default, `bot_runs.gd:111`: up to all 10 `bot/*` runs). `frame_path` and `no_tree_loop` fire no flare: unchanged. `final_sha` unchanged (no new state). No command-log change (not a command). |
| `FLARE_READY` (B, C+) | `{}`, id 0 | same function, `flare_cooldown_ticks` 1 -> 0 (by day too) | 1 per flare | as above |
| `COUNTDOWN` (B only) | `{kind: "day" \| "flare_cooldown", seconds}`, id 0 | `WaveDirector.tick` after the decrement (wave_director.gd:43); `_count_down_flare` | 1 per second of each running timer: `build_phase_seconds` x days + cooldown seconds x flares | every `bot/*` run and `frame_path` (it has days) change; `final_sha` unchanged; no command-log change |

Any accepted event also gets: an enum comment, a sim unit test, a G6 classification, and one
`scripts/golden-regen.sh` re-pin committed with it.

## 3. Panel field table

Abbreviations: PH = phase events (BUILD_STARTED, WAVE_STARTED, WAVE_CLEARED); OUT = OUTCOME;
CAP = SANITY_CAP_CHANGED; SST = SANITY_STATE_CHANGED; SAN = SANITY_CHANGED; CLK = the
presentation clock of §1.1 (option C). "Now" is always: polled every frame from
`Game.advance` (and after each command) unless stated.

### HUD (ui/hud.gd, ui/sanity_bar.gd)

| # | Field | Current source | Event that will update it |
|---|---|---|---|
| 1 | `gold_label` | `state.gold` | GOLD_CHANGED |
| 2 | `relics_label` text | `relics_text` | RELICS_CHANGED |
| 3 | `relics_label` tooltip | `relics_tooltip` | RELICS_CHANGED |
| 4 | `hp_label` | `state.lighthouse_hp` | LEAKED |
| 5 | `phase_label` | `phase_text(state)` incl. `build_ticks_left` | PH, CLK (day) |
| 6 | `call_wave_button.disabled` | `can_call_wave()` | PH, OUT |
| 7 | `call_wave_button.text` | `early_night_luck()` | PH, OUT, CLK (day) |
| 8 | `sell_relics_button.text` | `relics_value()` | RELICS_CHANGED |
| 9 | `sell_relics_button.disabled` | `can_sell_relics()` | RELICS_CHANGED, PH, OUT |
| 10 | `luck_label` visible/text | `phase`, `night_luck` | PH (luck is set by call_wave in the same drain) |
| 11 | `speed_button` | `game.chosen_speed` | NEW Game signal `speed_changed` |
| 12 | `pause_button` | `game.paused` | `speed_changed` |
| 13 | `buyout_button.visible` | `buyout_applies()` | SST |
| 14 | `buyout_button.disabled` | `can_buy_sanity()` | SST, GOLD_CHANGED, CAP, OUT |
| 15 | `buyout_button.text` | config | static (sync only) |
| 16 | `hostile_label` visible/text/position | `sanity_state`, config, layout | SST; position also on `sanity_bar.item_rect_changed` |
| 17 | `flare_button.visible` | `phase` | PH |
| 18 | `flare_button.disabled` | `can_fire_flare()` | PH, OUT, OIL_CHANGED, FLARE_FIRED, CLK (cooldown end) |
| 19 | `flare_button.text` | `flare_ticks_left`, `flare_cooldown_ticks` | FLARE_FIRED, CLK (burn end, cooldown seconds, ready) |
| 20 | `flare_button.tooltip` | `flare_seconds()` | LIGHTHOUSE_UPGRADED |
| 21 | `oil_label` (footer) | `state.oil`, `oil_cap()` | OIL_CHANGED |
| 22 | flare/oil positions | minimum sizes | after rows 17-21 rewrite text (same flush) |
| 23 | `sanity_bar` fill, label, cap block, colour | `state.sanity`, `sanity_cap`, `sanity_state` (`_draw`) | SAN, CAP, SST -> `queue_redraw()` |
| 24 | `sanity_bar` Fraying/Madness distortion | `_process` every frame | `set_process(true)` only while FRAYING/MADNESS, toggled on SST (decor animation, Q3) |
| 25 | `fps_label` | wall clock, checked every frame | a 0.25 s `Timer` child (wall-clock by nature, Q3) |
| 26 | `frame_label` (`--frame-stats`) | wall clock, every frame | same Timer |
| 27 | `sandbox_label` | `game.sandbox` | static (set in `_ready`) |

### Tower picker (ui/tower_picker.gd; per row, every def)

| # | Field | Current source | Event |
|---|---|---|---|
| 28 | row `disabled` | `can_build(id, cell)` | GOLD_CHANGED, PH, OUT, TOWER_BUILT, TOWER_SOLD |
| 29 | cost colour (poor) | same | same |
| 30 | trait text/colour (`!` mad mark) | `would_drive_mad_build` | CAP, SST, + row 28's |
| 31 | row dim | row 28 | row 28's |
| 32 | row tooltip | rows 28, 30 | rows 28 + 30 |
| 33 | `title_label` text/colour | first non-gold refusal, `phase` | row 28's |

Row names, DPS and trait base texts come from config: static, built in `_ready`.

### Tower panel (ui/tower_panel.gd, for `tower_id`)

| # | Field | Current source | Event |
|---|---|---|---|
| 34 | `title_label` | level, L3 branch name | TOWER_UPGRADED |
| 35 | `role_label` | def / branch role | TOWER_UPGRADED |
| 36 | `lit_label` text/colour/visible | `t.lit`, `t.shadowed` | TOWER_LIT |
| 37 | `stats_table` columns and lit marks | `row_values(..., sanity)`, `lit_values` | TOWER_UPGRADED, TOWER_LIT, SAN |
| 38 | `stats_table.max_width` | `side_panel.scroll.size` | `scroll.resized` (layout, not sim) |
| 39 | `special_label` (incl. live DPS at sanity) | `special_lines`, `live_dps_text(sanity)` | TOWER_UPGRADED, TOWER_LIT, SAN |
| 40 | `kind_label` | `tower_mults` (light state) | TOWER_LIT, TOWER_UPGRADED |
| 41 | `upgrade_title` / `max_label` visible | `upgrade_branches` | TOWER_UPGRADED |
| 42 | upgrade buttons visible/text/disabled, mad warning | `can_upgrade`, `would_drive_mad_upgrade` | TOWER_UPGRADED, GOLD_CHANGED, PH, OUT, CAP, SST |
| 43 | upgrade info labels | target role | TOWER_UPGRADED |
| 44 | priority buttons visible/text/disabled/mark | `has_targeting`, `target_priority`, `can_set_target_priority` | TARGET_PRIORITY_SET, TOWER_UPGRADED, OUT |
| 45 | `sell_button` text/disabled | `can_sell_tower`, `sell_refund` | PH, OUT, TOWER_UPGRADED |
| 46 | board range ring / cast preview | level stats | TOWER_UPGRADED |
| 47 | auto-close when the tower is gone | `tower_by_id == null` | TOWER_SOLD (id == `tower_id`) |

### Lighthouse panel (ui/lighthouse_panel.gd)

| # | Field | Current source | Event |
|---|---|---|---|
| 48 | `title_label` | `lighthouse_level` | LIGHTHOUSE_UPGRADED |
| 49 | `stats_label` (beams, coverage) | `beam_count()` | LIGHTHOUSE_UPGRADED |
| 50 | `upgrade_button` text/disabled | `lighthouse_upgrade_cost`, `can_upgrade_lighthouse` | LIGHTHOUSE_UPGRADED, GOLD_CHANGED, PH, OUT |
| 51 | `oil_label` (stock, flare line) | `state.oil`, `flare_seconds()` | OIL_CHANGED, LIGHTHOUSE_UPGRADED |
| 52 | `oil_button` text/disabled | `oil_for_flare`, `can_buy_oil` | OIL_CHANGED, GOLD_CHANGED, PH, OUT |

### Side panel (ui/side_panel.gd)

| # | Field | Current source | Event |
|---|---|---|---|
| 53 | `idle_label` text/visible | view visibility | already UI signals (`visibility_changed`); no change |
| 54 | picker card (title, role, table, special, kind, path) | config, on `hovered_changed` | already a UI signal; static per def |
| 55 | scroll reset | `_update_idle` | already a UI signal |

55 fields. After B11 the UI consumes every type except SPAWNED, ALLY_SUMMONED, ALLY_GONE,
which the board reads from state for drawing (G6 `UNCONSUMED_OK`).

## 4. Initial sync and missed events

- A panel opened mid-game runs `refresh()` (full sync from queries) in `open_for`/`open` and on
  `visibility_changed` to visible. Hidden panels ignore events (`flush` returns at once and
  clears `_dirty`), so there is no backlog to replay and no stale state to miss: every open
  starts from the truth.
- The HUD is always visible; `Game._ready` drains (BUILD_STARTED, `--sanity` events) and calls
  `hud.refresh()` once.
- A missed event can only be a missing `REFRESH_ON` entry. The coverage test (§7, B2) proves
  there is none: after every frame and every command of a scripted whole game it snapshots each
  visible panel (a generic walk over its Controls: text, tooltip, visible, disabled, modulate,
  font colour override), calls `refresh()`, snapshots again, and requires equality. A stale
  field fails with its node path, the frame and the events of that drain. A second assertion
  requires that every snapshotted node path changed at least once through `flush`/`on_stepped`,
  unless it is in a pinned `STATIC_OK` list (rows 15, 27, row names, card nodes): a new field
  nobody exercised fails the test until it is covered or listed.

## 5. GameCommands and DebugArgs

**`scenes/game_commands.gd`, `class_name GameCommands extends RefCounted`.** Holds `sim`,
`debug: DebugArgs` and `after: Callable` (Game's `_after_command`). Moves verbatim from
game.gd: `build`, `sell`, `upgrade`, `set_target_priority`, `call_wave`, `sell_relics`,
`buy_sanity`, `upgrade_lighthouse`, `buy_oil`, `buy_flare_oil`, `fire_flare`, `skip_ahead`
(sandbox check through `debug.sandbox`). `flare_oil_to_buy` is deleted: its callers
(lighthouse_panel.gd:97, sim_rule_queries_test, flare_oil_ui_test) call `sim.oil_for_flare()`.
No rule logic. Stays in Game: the frame driver, `toggle_speed`/`toggle_pause` (clock, not sim),
`_unhandled_key_input` (calls `commands.skip_ahead()`), composition, `close_panels`,
`_on_cell_clicked`. Callers use `game.commands.build(...)`: 11 sites in `ui/` (hud 4,
lighthouse 3, tower_panel 3, picker 1) and 16 test files plus `GoldenRuns._dispatch`
(tests/golden_runs.gd:249-256; the command log is unchanged, so `frame_path` stays identical).

**`scenes/debug_args.gd`, `class_name DebugArgs extends RefCounted`.** Moves the constants
`REVEAL_FAKES_ARG`, `SANITY_ARG`, `FRAME_STATS_ARG`, `SANDBOX_ARG`, `MUTE_ARG`, `SANDBOX_GOLD`;
`static func parse(args, debug_build := OS.is_debug_build()) -> DebugArgs` with fields
`sandbox`, `reveal_fakes`, `frame_stats`, `mute`, `sanity` (-1 when absent);
`static func apply_mute(args) -> bool` (was `Game.apply_mute_arg`, unchanged behaviour: any
build, never unmutes); `static func sanity_value(args) -> float` (was `Game.debug_sanity_arg`).
`debug_build` as a parameter makes the release-build path testable for the first time.
`SKIP_KEY` and `UI_LAYER` stay in Game.

**Seam.** `Game.setup(config, p_seed, args := OS.get_cmdline_user_args())` keeps its signature;
it becomes `debug = DebugArgs.parse(args)`, then the same steps in the same order (sandboxed
config, sim, spawner, reveal fakes, `DebugArgs.apply_mute(args)`, forced sanity, frame stats),
then `commands = GameCommands.new(sim, debug, _after_command)`. `GameFixture.make_game` and G8
are untouched. `Game.sandbox` and `Game.frame_stats` stay fields (tests set them directly).
Test references move from `Game.X_ARG`/`Game.apply_mute_arg`/`Game.debug_sanity_arg` to
`DebugArgs` in mute_arg_test, sanity_feedback_test, render_isolation_test, frame_stats_test,
lt62_fps_test.

## 6. Guard G6 (tests/architecture_guard_test.gd)

Static scans with the existing `_code_lines` / `_gd_files` helpers:
- **G6a** `drain_events(` is called only in `scenes/game.gd`, `tools/` and `tests/`.
- **G6b** every `SimEvent.Type` key (enumerated from the enum) is named as
  `SimEvent.Type.<KEY>` in some file under `scenes/` or `ui/` (a `match` arm, an `if`, or a
  `REFRESH_ON` key), or is in the pinned `UNCONSUMED_OK = [SPAWNED, ALLY_SUMMONED, ALLY_GONE]`.
  Both ways: a listed type that is consumed also fails, so the list stays exact.
- **G6c** no `func _process(` / `func _physics_process(` in `ui/` except a pinned
  `PROCESS_OK = ["res://ui/sanity_bar.gd"]` (decor, gated by `set_process`).
- **G6d** `scenes/game.gd` contains no `.refresh()` call on `hud`, `picker`, `tower_panel` or
  `lighthouse_panel` except the one `hud.refresh()` in `_ready`.

Fails today on: G6b (17 types unconsumed), G6d (`advance`, `_after_command`). G6a and G6c
pass today and pin the state (sanity_bar's gating itself is pinned by B6, not by the scan).

## 7. Edit map (in order; green between steps)

1. NEW `scenes/debug_args.gd`. `scenes/game.gd` consts 9-27, `setup` 57-75,
   `apply_mute_arg` 79-85, `debug_sanity_arg` 88-98 -> DebugArgs; migrate the 5 test files.
2. NEW `scenes/game_commands.gd`. game.gd `skip_ahead` 158-168, forwarders 213-298 -> it;
   `_ready` 101-142 builds `commands`; `_unhandled_key_input` 149-155. Migrate `ui/` callers
   (hud.gd `_ready` 87-112 button wiring, lighthouse_panel.gd `_ready` 17-29 and 97,
   tower_panel.gd 240-250, tower_picker.gd 300-303), the 16 test files and golden_runs.gd
   249-256. Golden must stay identical here.
3. `ui/hud.gd` `refresh` 155-195 and `_refresh_flare` 198-222: split into groups,
   add `REFRESH_ON`, `on_event`, `flush`, `on_stepped` (day and flare timers); `_refresh_fps`
   226-235 -> Timer callback; `_ready` adds the Timer and the `speed_changed` connection.
   `ui/sanity_bar.gd` `_process` 41-43: gate with `set_process` from the HUD's SST handler,
   `queue_redraw` from the SAN/CAP/SST groups.
4. `ui/tower_picker.gd` `refresh` 229-276 (one group), `REFRESH_ON`, `on_event`, `flush`;
   `open_for` 205-213 unchanged (already calls `refresh`).
5. `ui/tower_panel.gd` `refresh` 104-142, `_refresh_table` 163-213, `_refresh_priority`
   216-237: groups; TOWER_SOLD close; `scroll.resized` -> table width.
6. `ui/lighthouse_panel.gd` `refresh` 62-105: groups.
7. `scenes/game.gd` `advance` 187-209 (drop the four `refresh()` calls; drain + flush only when
   `steps > 0` or events; `on_stepped` when `steps > 0`), `toggle_speed`/`toggle_pause`
   301-312 (emit `speed_changed`), `_after_command` 316-322 (drain + flush), `_consume_events`
   325-343 (route to the four panels' `on_event`).
8. tests: G6 in architecture_guard_test.gd; NEW `tests/ui_event_refresh_test.gd` (§8);
   NEW `tests/support/ui_snapshot.gd` (the Control walk); fps_readout_test, lt62_fps_test,
   frame_stats_test move from "advance updates the label" to the Timer callback.

## 8. Behaviours to pin, proof, controls

| # | Behaviour | Proof | Control (a code revert; the test must fail) |
|---|---|---|---|
| B1 | No panel work on an idle frame | Each panel counts flushed groups and `on_stepped` rewrites (`refresh_count`), SanityBar counts `queue_redraw`. With picker, tower or lighthouse view open: 120 `advance(1/60)` while paused, and 120 `advance(0.0)` unpaused: all counters unchanged, sanity bar LUCID | restore the four unconditional `refresh()` calls in `advance` |
| B2 | Every field follows its events | §4 coverage test: scripted whole game on golden data (build, upgrade both branches, priority, sell, lighthouse upgrade, buy oil, flare, sell relics, call_wave, `debug_set_sanity` into madness, a buyout config variant), snapshot == snapshot after `refresh()` at every step; every node path changed or `STATIC_OK` | (a) drop GOLD_CHANGED from the picker's `REFRESH_ON`; (b) drop LEAKED from the HUD's |
| B3 | Countdowns tick without sim events | in B2's run: `phase_label` seconds and flare text equal a fresh `refresh()` every frame; `on_stepped` rewrites the day label at most once per whole second | make `on_stepped` a no-op |
| B4 | Hidden panel opened mid-game is current | close the lighthouse view, buy oil and upgrade via commands, reopen: snapshot equals expected texts | remove `refresh()` from `LighthousePanel.open` |
| B5 | Sold tower closes its panel | sell via `commands.sell`, panel hidden after the drain | drop the TOWER_SOLD close branch |
| B6 | Sanity bar animates only while distorted | `is_processing()` false in LUCID/WHISPERS, true in FRAYING/MADNESS after the SST event | remove the `set_process` gating (always on) |
| B7 | DebugArgs parse and the setup seam | `DebugArgs.parse` table test incl. `debug_build=false` drops every debug flag but `--mute`; `sandbox_game_test`, `mute_arg_test`, `sanity_feedback_test` green via `GameFixture.make_game(..., args)` | make `parse` ignore `debug_build` |
| B8 | G6 | the four scans | G6b: remove `SimEvent.Type.LEAKED` from the HUD's `REFRESH_ON` |
| B9 | Behaviour unchanged | golden replay byte-identical (option C); `scene_game_test`, `side_panel_test`, `lighthouse_ui_test`, `flare_oil_ui_test`, `stats_panel_test`, `relic_ui_test`, `reserve_ui_test` | n/a (G5 is its own proof) |

8 controls (B2 has two). The coverage test and the idle test run 5x (timers and frames).

## 9. Owner questions

1. **Timer display.**
   (a) Presentation clock, no new sim events (option C) **(recommended)**. Benefit: golden
   byte-identical, no sim code for the UI, no per-tick events. Risk: timer fields run on
   stepped frames while a timer is active; flare end/ready are not sim facts.
   (b) C plus `FLARE_ENDED`/`FLARE_READY` (C+). Benefit: flare transitions become sim events.
   Risk: re-pin of every bot run that fires a flare, for no UI need.
   (c) Coarse `COUNTDOWN` per whole second + the two flare events (B). Benefit: every UI change
   is a sim event. Risk: sim code only for the UI; all `bot/*` and `frame_path` digests re-pinned.
2. **Where values come from.**
   (a) Event marks groups dirty; the flush reads rule queries **(recommended)**. Benefit: one
   source of rules (LT-65 Q5), order-safe within a drain. Risk: panels still read state, only
   when told to.
   (b) Values from event payloads into a UI model. Benefit: no state reads at all. Risk: copies
   `can_*` rules into the UI (G1 spirit), payload gaps become bugs.
3. **Per-frame exceptions (FPS/frame-stats readouts, sanity-bar distortion).**
   (a) FPS/frame labels on a 0.25 s Timer; distortion `_process` only while FRAYING/MADNESS
   **(recommended)**. Benefit: zero work on an idle LUCID frame. Risk: two pinned exceptions in G6.
   (b) Move the distortion into a shader (`TIME`), no `_process` in `ui/` at all. Benefit: no
   exception. Risk: rewrites LT-14's torn-slice drawing; bigger than B11.
4. **Command callers.**
   (a) Migrate every caller to `game.commands.X` in one go **(recommended)**, like Q6 "Перевести
   всех сразу". Benefit: Game is composition + frame driver only. Risk: ~63 mechanical edits in
   16 test files.
   (b) Keep one-line forwarders on Game. Benefit: tiny diff. Risk: two names for each command, and
   the forwarders are what §3.8 asked to remove.

## 10. Owner decisions (2026-11-19)

1. Timer display: "Часы в UI, без новых событий симуляции (Recommended)" (option C, golden
   byte-identical).
2. Values: "Событие помечает группу, панель читает запросы правил (Recommended)".
3. Per-frame exceptions: "FPS по таймеру 0.25 с, искажение — только в FRAYING/MADNESS
   (Recommended)".
4. Command callers: approved with the note as "перевести всех вызывающих на game.commands.X
   сразу" (option a).

Note approved: "Утверждаю (Recommended)".
