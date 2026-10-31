# LT-24 — Tower info panel and upgrades (design note)

Status: decisions recorded · 2026-10-31 · branch `feat/LT-24-tower-info-upgrades`

## 0. What exists today and what this task adds

**Today** (`release-0.2.0` at `9df2ba0`):
- `data/towers.json` has L1 + L2 in `levels` and two L3 branches `a`/`b` per tower, with
  `upgrade_cost`, `upgrade_sanity_cost` (Elder Sign only), stats and `effects`.
  `TowerDef` / `TowerDef.Level` (`sim/defs/tower_def.gd`) parse all of it.
- `SimTower.level` (index into `def.levels`, always 0) and `SimTower.spent` (gold paid,
  the refund base) exist; `SimTower.stats()` returns `def.levels[level]`. Every combat
  path (`_fire_towers`, `_apply_auras`, `enemies_in_range`) reads `t.stats()`, so a tower
  whose `stats()` returns its new level fights with the new numbers with no other change.
- No upgrade command, no event, no UI. `TowerPicker` (popup at a buildable cell) shows
  `"<Name> - <cost> gold"`; `SellPanel` (popup at a clicked tower) shows the name and a
  Sell button and draws the range ring.
- Parsed but **not applied** by the sim: `crit_chance`/`crit_multiplier` (Marksman),
  `shooters` (Militia), `bleed_dps`/`bleed_seconds` (Barbed), `pull_cells` (Chain
  harpoon), `strip_armor` (Corrupted Seal), and `sanity_per_second` (Corrupted Seal; owned
  by LT-23). Applied through `stats()`: `range`, `damage`, `fire_interval`,
  `sanity_per_cast`, `madness_affected` (Pure Rite), `pierce`, `aoe_radius`, `slow`,
  `damage_taken_multiplier`. Wiring the first group is a separate backlog task (Decision 1).
- `tools/bot_runs.gd` never upgrades; LT-23/S5 tunes with these bots and needs upgrades.
- Screen (LT-22): viewport 1152×648, `stretch/mode = canvas_items` (default aspect keep).
  HUD bar 48 px on top (`Game.BOARD_ORIGIN = (0, 48)`); board 24×14 cells × 40 px =
  960×560 at x 0..960, y 48..608. Free area: **x 960..1152 (192 px) × y 48..648**, plus a
  40 px strip under the board.

**This task adds**: `can_upgrade` / `upgrade_tower` in the sim (levels and branches, gold
+ sanity cost, BUILD phase only, logged, an event); refund over all gold spent; an
optional `role` string per tower and branch in `towers.json`; a config-driven text
formatter; one fixed side panel on the right for build info and selected-tower info with
upgrade/branch/sell buttons; an upgrade strategy in the bot harness.

```
click cell  ─ SidePanel.show_build(cell)  ─ per tower: role, L1 lines, [Build] button
click tower ─ SidePanel.show_tower(id)    ─ role, current lines, upgrade/branch buttons, [Sell]
   [Upgrade to L2]  or  [Branch A] [Branch B]  or  "Max level"
      └─ Game.upgrade(id, branch) ─ Simulation.upgrade_tower ─ TOWER_UPGRADED,
                                    GOLD_CHANGED "upgrade", SANITY_CHANGED "upgrade"
```

---

## 1. Tower model and config

**SimTower** gains `var branch := ""` (`""` below L3, `"a"`/`"b"` at L3). `level` stays a
0-based index: 0 = L1, 1 = L2, 2 = L3 (the branch). `stats()` becomes:

```
if level >= TowerDef.LEVEL_COUNT: return def.branches[branch]
return def.levels[level]
```

Player-facing text adds 1 (`L1`..`L3`); the sim and events use the index. Cooldown on
upgrade: the current `cooldown_ticks` is kept; the new `fire_interval` applies from the
next shot (no free shot, nothing to exploit, deterministic).

**`role` (Decision 5).** Optional string on each tower object and on each branch object;
not allowed on `levels[]` entries (an L2 is "the same tower, stronger"). Validation in
`TowerDef.parse` / `Level.parse`: if present it must be a string, non-empty after
`strip_edges()`, at most 24 characters (LT-37: render-checked at 1280x720, one visual line in the
192 px panel). Errors go through `ConfigReader.error` with the usual path
(`towers.rifleman.role`, `towers.rifleman.branches.a.role`, `towers.rifleman.levels[1].role:
not allowed on levels`). Absent → `""`, the panel shows no role line. Role text carries no
numbers (numbers come from stats, so they cannot drift).

Seed texts (English, from GDD §6):

| Tower | role | branch a role | branch b role |
|---|---|---|---|
| rifleman | `Steady single target` | Marksman: `Long range, crits` | Militia: `2 shooters, faster fire` |
| harpooner | `Pierces a line of foes` | Barbed: `Enemies bleed` | Chain harpoon: `Pulls target back` |
| elder_sign | `Aura: slows and exposes` | Pure Ward: `Larger aura` | Corrupted Seal: `Strips armor; +reserve` |
| necronomicon_reader | `Area blast, uses sanity` | Pure Rite: `Slower; ignores madness` | Corrupted Rite: `Bigger hits, +reserve` |

**Pending effects (Decision 1).** `TowerDef.Level` gets
`const PENDING: PackedStringArray = ["crit_chance", "crit_multiplier", "shooters",
"bleed_dps", "bleed_seconds", "pull_cells", "strip_armor", "sanity_per_second"]`: config
keys that parse but the sim does not apply yet, and `func has_pending() -> bool` (true when
any of them is non-zero on this level). The branch-effects backlog task and LT-23 remove
keys from `PENDING` as they wire them; the UI and bots read only this list, so nothing
else changes then.

## 2. Upgrade command (sim)

Same style as `build_tower` / `sell_tower`: a `can_*` check that changes nothing, then the
command; a rejection changes nothing (no gold, no event, no `command_log` entry).

```
func can_upgrade(tower_id: int, branch := "") -> CommandResult
func upgrade_tower(tower_id: int, branch := "") -> CommandResult
func upgrade_target(t: SimTower, branch := "") -> TowerDef.Level   ## null when none
func upgrade_branches(t: SimTower) -> PackedStringArray            ## [""], ["a","b"] or []
```

**Checks, in this order** (first failing one is returned):

| # | Condition | Result |
|---|---|---|
| 1 | outcome set | `OUTCOME_REACHED` |
| 2 | no tower with that id (unknown or sold) | `NO_SUCH_TOWER` |
| 3 | tower is at L3 | `MAX_LEVEL` (new) |
| 4 | L2 → L3 and `branch` is `""` | `NEED_BRANCH` (new) |
| 5 | `branch` is not `""`/`"a"`/`"b"`, or non-empty for L1 → L2 | `BAD_BRANCH` (new) |
| 6 | `state.phase == WAVE` | `NOT_BUILD_PHASE` (existing value, reused) |
| 7 | `state.gold < target.upgrade_cost` | `NOT_ENOUGH_GOLD` |

The three new values are **appended** to `CommandResult` after `NOT_IN_MADNESS` so
existing values never shift (LT-4 convention). `NOT_BUILD_PHASE`'s comment gains
"upgrade: during a wave".

**When allowed (Decision 3).** Only outside a wave: refused while `phase == WAVE`; allowed
in `BUILD`, paused or not. `Phase.NONE` (no `WaveDirector`: unit tests with
`ScriptedSpawner`) has no build phase to wait for, so it is allowed there, the same way
`build_tower` works without a director; `DONE` is followed by the outcome in the same tick,
so check 1 covers it. Phase is checked before gold so the UI shows "wave in progress"
rather than "not enough gold" mid-wave.

*Build and sell keep their any-phase rule.* No conflict with upgrades: selling an upgraded
tower mid-wave refunds 70 % (§2 refund), and a rebuilt tower is L1, so build/sell cannot
smuggle an upgrade into a wave. The asymmetry is intended (a new tower mid-wave is a
reaction; deepening the defence is planning). LT-27 later makes BUILD the "day"; this rule
then reads "upgrade by day", with no further change.

**Sanity:** only gold is checked, like build. `target.upgrade_sanity_cost` is paid through
`_add_sanity(-cost, "upgrade", t.id)`: allowed at any sanity, clamped at 0, can push the
player into MADNESS; while in MADNESS the latch applies nothing (same as a build there).
Today only Elder Sign has an upgrade sanity cost (8 per level, GDD §5.3).

**On OK, in this order:**
1. `t.level += 1`; at L3 `t.branch = branch`; `t.spent += target.upgrade_cost`.
2. `command_log.append([tick, "upgrade", tower_id, branch])`.
3. `TOWER_UPGRADED` (new `SimEvent.Type`, appended after `FAKE_DISSOLVED`), id = tower,
   data `{"def", "cell", "level": <new index>, "branch", "cost": <gold>}`.
4. `GOLD_CHANGED {reason: "upgrade"}` via `_add_gold(-cost, "upgrade", t.id)`.
5. `SANITY_CHANGED {reason: "upgrade"}` when `upgrade_sanity_cost > 0` (and not latched).

The tower keeps its id, cell, `build_tick` and `status`. A branch with pending effects can
be bought (the player sees "(coming soon)", §3); it gets its plain stats.

**Refund (Decision 4).** Unchanged formula `roundi(t.spent * sell_refund_ratio)`; `spent`
now includes upgrades (GDD §5.1 "70 % of total spent"). Rounding once, on the total.
Sanity is never refunded. At 0.7: Rifleman L3 = 50 + 40 + 80 = 170 → 119; Harpooner L2 =
70 + 55 = 125 → 87.5 → 88; Elder Sign L3 = 100 + 80 + 140 = 320 → 224 (24 sanity, none back).

Currency: all code uses today's `state.gold` / `_add_gold` API; LT-27 migrates it.

## 3. Info text from config (`ui/tower_info.gd`, new)

A static, pure formatter `TowerInfo` (no nodes; unit-testable):

- `lines(def: TowerDef, s: TowerDef.Level, sanity: SanityConfig) -> PackedStringArray`
- `delta_lines(from: TowerDef.Level, to: TowerDef.Level) -> PackedStringArray`
- `cost_text(gold: int, sanity_cost: float) -> String` → `"40 gold"`, `"80 gold + 8 sanity"`
- `REASONS: Dictionary` (CommandResult → text), shared by build and tower views.

Every number comes from `TowerDef` / `SanityConfig`; no number is written in UI code.
The role line is not part of `lines()`; the panel prints `def.role` / branch `role` first.

**Stat lines** (omitted when the field is 0/absent):

| Field | Text | Example |
|---|---|---|
| damage + fire_interval | `Damage <d> every <i> s (<dps> DPS)` | `Damage 10 every 0.8 s (12.5 DPS)` |
| damage 0 | `Support (no damage)` | Elder Sign |
| range | `Range <r> cells` / support: `Aura radius <r> cells` | `Aura radius 2 cells` |
| sanity_per_cast | `−<n> sanity per cast` | Necronomicon |
| sanity_per_second | `−<n> sanity/s while on the board` | Corrupted Seal |

**Effect lines** (keys of `TowerDef.Level.EFFECTS`):

| Key(s) | Text |
|---|---|
| `pierce` | `Line shot: hits every enemy on a <p>-cell-wide line` |
| `aoe_radius` | `Blast: hits all enemies within <r> cells of the target` |
| `slow` | `Slows enemies inside by <30>%` |
| `damage_taken_multiplier` | `Enemies inside take +<25>% damage` |
| `crit_chance` + `crit_multiplier` | `<20>% chance to deal x<2> damage` |
| `shooters` | `<2> shooters` |
| `bleed_dps` + `bleed_seconds` | `Bleed: <6> damage/s for <3> s` |
| `pull_cells` | `Pulls the target <1.5> cells back along the path` |
| `strip_armor` | `Enemies inside lose <1> armor` |
| unknown key (future) | `<key>: <value>` (never crashes, never hides a config value) |

A line whose key (or one of its pair) is in `TowerDef.Level.PENDING` gets ` (coming soon)`
appended, e.g. `Bleed: 6 damage/s for 3 s (coming soon)`. DPS ignores pending effects
(Militia shows 24 DPS, not 48).

**Kind lines** (from kind, `madness_affected` and `sanity.json`):
- mundane: `Kills restore <regen_mundane_kill> sanity`; `May miss while Fraying
  (<fraying.miss_chance>%)`.
- occult, `madness_affected`: `In madness: x<damage_multiplier> damage, shots go astray`.
- occult, not `madness_affected`: `Unaffected by madness`.

Numbers print with up to 2 decimals, trailing zeros dropped (`3.5`, `82.5`, `0.2`). The
currency word is one constant (`"gold"`) so LT-27 edits one line.

## 4. Fixed side panel and UI flow (Decision 2)

**One fixed panel on the right edge** replaces both popups: `SidePanel`
(`ui/side_panel.gd`, new, `PanelContainer` in the `UI` CanvasLayer), rect
**x 960..1152, y 48..648** (192×600 in viewport units). It is laid out in the base
1152×648 viewport, so `canvas_items` stretch scales it with the window and it never
overlaps the 960 px board. Position and width come from `Game.BOARD_ORIGIN` + board width
(`map.width × Board.CELL`), not literals, so a board change moves it. Content sits in a
`ScrollContainer` (vertical only); labels use autowrap at the panel width and a smaller
font (14 px, tunable). Opaque background (fixes the "semi-transparent picker" carry-over
for this panel; LT-28 owns the rest of the polish).

The panel has three views, one visible at a time; it is always shown:

**Idle** (nothing selected): `Click a cell to build, a tower to upgrade.`

**Build** (buildable cell selected; replaces `TowerPicker`'s popup, the class stays and
becomes the build view inside the panel, so `game.picker`, `picker.buttons`, `picker.cell`
and the button text format keep working):

```
Build
[Rifleman - 50 gold]
  Single target, steady damage        ← role
  Damage 10 every 0.8 s (12.5 DPS)    ← lines(L1)
  Range 3 cells · Kills restore 0.5 sanity
[Elder Sign - 100 gold + 8 sanity]
  Aura: slows enemies and ...
  ...
[Cancel]
```
Disabled buttons keep today's `(<reason>)` suffix from `TowerInfo.REASONS`.

**Tower** (tower selected; `SellPanel` is renamed `TowerPanel`, `ui/tower_panel.gd`, the
tower view inside the panel; `game.sell_panel` → `game.tower_panel`, `sell_button` kept):

```
Rifleman  L2                       ← name, level; at L3 also the branch name
Single target, steady damage       ← tower role (L3: branch role)
Damage 14 every 0.7 s (20 DPS)
Range 3.5 cells
Kills restore 0.5 sanity
May miss while Fraying (15%)
── Upgrade ──
[Marksman - 80 gold]
  Long range and critical hits     ← branch role
  Range 3.5 → 5 · Damage 14 → 18
  20% chance to deal x2 damage (coming soon)
[Militia - 80 gold]
  ...
[Sell (+63 gold)]
[Cancel]
```

- L1: one button `Upgrade to L2 - <cost>` with its `delta_lines`.
- L2: two branch buttons named by the branch `name`, each with role, delta and effects.
- L3: no upgrade buttons; a line `Max level`.
- Disabled when `can_upgrade` is not OK, with the reason appended:
  `NOT_BUILD_PHASE` → `(wave in progress)`, `NOT_ENOUGH_GOLD` → `(not enough gold)`,
  `OUTCOME_REACHED` → `(run over)`.
- Occult upgrade with a sanity cost: when `state.sanity - cost <= 0` and not in MADNESS,
  the button stays enabled with ` (drives you mad!)` appended.
- `refresh()` runs every frame and after each command (as today): affordability, phase
  and refund track live; when a wave ends the buttons enable by themselves.
- After an upgrade the tower view stays on the same tower and the board's
  `selected_range` is re-read from `t.stats()` (the ring grows).
- `Cancel`, clicking water/path, selling, or the tower disappearing → Idle view (today
  these close the popup). End screen → panel hidden.
- Clicking a button calls `Game.upgrade(tower_id, branch)` (new, like `Game.sell`).
- Board (`scenes/board.gd` `_draw_tower`): a minimal level mark (1-3 pips; `a`/`b` letter
  at L3). Distinct looks belong to LT-25.

## 5. Bot harness upgrades (`tools/bot_runs.gd`, Decision 6)

"Wide then deep" (deterministic; one purchase per loop iteration, as today):

1. Next purchase = the strategy's next **build** while the board has fewer than
   `BUILD_FIRST = 5` towers (tunable).
2. Otherwise next purchase = the **cheapest upgrade** (gold) among this run's towers that
   can still be upgraded by the bot; ties → lower tower id. The L3 branch comes from
   `BRANCH_PICK`. A tower whose picked branch `has_pending()` stops at L2 for the bot
   (Decision 1: bots skip those branches). If no tower can be upgraded further, next
   purchase = the next build.
3. Buy it if the command returns OK; otherwise stop for this round (the bot saves for it,
   it does not skip to something cheaper). During a wave an upgrade is refused
   (`NOT_BUILD_PHASE`), so the bot waits for BUILD; in BUILD it spends first, then
   `call_wave()` as today.
4. Sanity guard (`occult` only, unchanged threshold 25): an upgrade whose
   `upgrade_sanity_cost` would leave sanity < 25 is skipped this round (next candidate).
   `madness` has no guard.

`BRANCH_PICK` (tunable; pure for the careful bot, corrupted for the mad one). With today's
`PENDING`, the bold ones are taken; the others hold the tower at L2:

| Strategy | rifleman | harpooner | elder_sign | necronomicon_reader |
|---|---|---|---|---|
| mundane | a Marksman (pending) | a Barbed (pending) | — | — |
| occult | a Marksman (pending) | — | **a Pure Ward** | **a Pure Rite** |
| madness | — | — | b Corrupted Seal (pending) | **b Corrupted Rite** |

Consequence for LT-23/S5: the mundane bot reaches only L2 until the branch-effects task
lands; the tuning report should say so.

- New flag `--upgrades=0` turns rule 2 off, reproducing the pre-LT-24 baseline for
  before/after comparison in LT-23/S5. Default on.
- `RUN` JSON gains `"upgrades": {"rifleman_L2": n, "elder_sign_a": n, ...}` and
  `"upgrade_gold": <total>`; header comment updated (drop "No upgrades or sells").
- Placement is unchanged (L1 range scoring).

---

## 6. Must confirm, edit map, behaviours

### Must confirm (code slices)
1. Nothing outside `sim/` reads `SimTower.level` or `def.levels[...]` for a placed tower
   except `SellPanel.open_for` (`t.stats()`); `bot_runs._best_cell` reads `levels[0]` for
   scoring only.
2. No consumer switches on `SimEvent.Type` exhaustively (board `on_event`, `sanity_fx`):
   the appended `TOWER_UPGRADED` must be ignored safely.
3. No test asserts `CommandResult.size()` or `SimEvent.Type.size()`.
4. `config_valid_test.gd` / `config_reject_test.gd` cover `towers.json` keys: S2 adds the
   `role` cases there.
5. `scene_game_test.gd` uses `picker.buttons`, `picker.cell`, `picker.visible`,
   `sell_panel.*` (lines 74-145): S3 keeps `picker.*` names and maps `sell_panel` →
   `tower_panel`; "picker hidden" assertions become "build view hidden".
6. LT-23 state at S2 start: if LT-23/S2 has landed, merge `release-0.2.0` first;
   otherwise LT-23/S2 rebases on LT-24/S2.

### Edit map — S2 (sim command, config role, bots)
Read for context: `simulation.gd` `build_tower` 169-194, `sell_tower` 196-215,
`can_buy_sanity` / `buy_sanity` 230-261 (check-then-command style), `_add_gold` 388-397,
`_add_sanity` 398-425; `sim/config_reader.gd` `opt_string` 193; `tests/gold_test.gd`
116-190; `tests/sim_test_base.gd`; `tests/config_reject_test.gd` (case table format).

| Path | Lines | Change |
|---|---|---|
| `sim/defs/tower_def.gd` | 5, 10-16, 19-24 | `role` in `FIELDS`, `var role`, parse + validate (§1) |
| | 48-60, 68-75 | `Level`: `role` in `LEVEL_FIELDS`, `var role`, allowed only when called for a branch (new `is_branch` arg), `PENDING`, `has_pending()` |
| `data/towers.json` | all | seed `role` strings (§1 table) |
| `sim/core/sim_tower.gd` | 3-4, 10-11, 19-20 | doc comment; `var branch := ""`; `stats()` per §1 |
| `sim/core/sim_event.gd` | 6-8 | append `TOWER_UPGRADED` |
| `sim/core/simulation.gd` | 9-21 | append `MAX_LEVEL`, `NEED_BRANCH`, `BAD_BRANCH`; `NOT_BUILD_PHASE` comment |
| | after 215 | `upgrade_branches`, `upgrade_target`, `can_upgrade`, `upgrade_tower` per §2 |
| | 196-198, 285-288 | doc comments: refund covers upgrades (formula unchanged) |
| | 494 | comment: `strip_armor` is in `TowerDef.Level.PENDING` |
| `tools/bot_runs.gd` | 1-26 | header, `BUILD_FIRST`, `BRANCH_PICK`, `--upgrades` flag |
| | 60-111 | count `upgrades` / `upgrade_gold` from `TOWER_UPGRADED`; add to RUN |
| | 113-141 | `_act` picks build vs upgrade per §5; new `_next_upgrade(sim, strat)` |
| `tests/upgrade_test.gd` | new | behaviours 1-10 (tests slice) |
| `tests/config_valid_test.gd`, `tests/config_reject_test.gd` | append | behaviours 11-12 |

LT-23 conflict: LT-23/S2 also edits `simulation.gd` (passive drain, madness buff) after
LT-24/S2, and `tower_def.gd` if it touches `sanity_per_second`. LT-24/S2 touches the enum
tail, a block after `sell_tower`, doc comments, and adds `PENDING`; LT-23 removes
`"sanity_per_second"` from `PENDING` when it applies the drain and reads
`t.stats().sanity_per_second`, which then covers Corrupted Seal through the branch.

### Edit map — S3 (UI)
Read for context: `ui/tower_picker.gd` (all, 89 lines), `ui/sell_panel.gd` (all, 72),
`ui/hud.gd` `_ready` 21-57 (layout style), `scenes/game.gd` 9, 27-28, 76-98, 121-131,
160-186; `scenes/board.gd` `_draw_tower` 238-245; `tests/scene_game_test.gd` 32-145.

| Path | Lines | Change |
|---|---|---|
| `ui/tower_info.gd` | new | `TowerInfo` formatter, `REASONS`, pending marking (§3) |
| `ui/side_panel.gd` | new | fixed right panel, scroll, idle/build/tower views (§4) |
| `ui/tower_picker.gd` | 1-15, 23-45, 48-65, 66-89 | build view: role + info per row, sanity in text; `open_for`/`close` switch views instead of moving a popup; drop `_panel_position` |
| `ui/sell_panel.gd` → `ui/tower_panel.gd` | all | `TowerPanel` tower view: title, role, lines, upgrade/branch buttons, sell, reasons, ring refresh (`git mv`, keep `.uid` consistent) |
| `scenes/game.gd` | 27-28, 84-91, 115-116, 163-165, 173-174, 178-186 | create `SidePanel` holding picker + tower panel; `sell_panel` → `tower_panel`; new `upgrade(id, branch)` after 131 |
| `scenes/board.gd` | 238-245 | level pips / branch letter |
| `tests/scene_game_test.gd` | 77-145 + new | renamed refs; upgrade via UI; phase/gold reasons; panel rect |
| `tests/tower_info_test.gd` | new | behaviours 15-17 |

### Behaviours the tests slice pins (one line each)
1. L1 → L2 for `levels[1].upgrade_cost`: level 1, gold down by the cost, `spent` up by it.
2. L2 → L3 with `"a"`/`"b"`: level 2, `branch` set, `stats()` is that branch (range, damage).
3. Rejections in table order, each changing nothing (gold, level, events, `command_log`):
   `OUTCOME_REACHED`, `NO_SUCH_TOWER` (sold id), `MAX_LEVEL`, `NEED_BRANCH`, `BAD_BRANCH`
   (`"c"`, and `"a"` at L1), `NOT_BUILD_PHASE`, `NOT_ENOUGH_GOLD` (cost − 1 refused, cost OK).
4. Phase: refused in WAVE with `NOT_BUILD_PHASE` even with enough gold; allowed in BUILD
   (also paused) and in `Phase.NONE`; build and sell still succeed in WAVE.
5. OK emits `TOWER_UPGRADED {def, cell, level, branch, cost}` then `GOLD_CHANGED
   {reason: "upgrade"}`, then for Elder Sign `SANITY_CHANGED {reason: "upgrade", delta: −8}`.
6. `command_log` gets `[tick, "upgrade", id, branch]`; replaying the log gives the same
   events and state.
7. An upgrade sanity cost can push sanity to 0 / MADNESS; in MADNESS it applies nothing.
8. Sell after upgrades refunds `roundi(0.7 × total spent)` (Rifleman L3 → 119, Harpooner L2 → 88).
9. An upgraded tower fights with the new stats from the next shot: L2 Rifleman's damage is
   14 and its next cooldown is `ticks(0.7)`; the running cooldown is kept.
10. Pure Ward's aura covers an enemy at 3.5 cells that L1 did not reach; Pure Rite in
    MADNESS: no x2, no `astray`; Corrupted Rite casts cost 4 sanity.
11. Config: `role` on tower and branch parses; absent → `""`; non-string, empty/blank,
    over 24 chars, and `role` on a `levels[]` entry are each rejected with their path.
12. `has_pending()`: true for Marksman, Militia, Barbed, Chain harpoon, Corrupted Seal;
    false for every L1/L2, Pure Ward, Pure Rite, Corrupted Rite (real config).
13. Bots: with upgrades on, `occult` and `madness` buy L3s (Pure Ward/Pure Rite,
    Corrupted Rite) and never a branch that `has_pending()`; `mundane` buys L2s only.
14. Bots: `--upgrades=0` RUN lines equal the pre-LT-24 harness for the same seeds; no
    upgrade is issued during a wave.
15. `TowerInfo.lines` for each of the 4 towers × 4 stats (L1, L2, a, b) has a line for
    every non-zero stat and effect, built from config (a config edit changes the text).
16. Pending keys get ` (coming soon)`; removing a key from `PENDING` removes the suffix;
    an unknown effect key renders as `key: value`.
17. Role is the first line in both views (tower role, branch role at L3 and on branch
    buttons); no role line when `role` is empty.
18. Side panel rect is x 960..1152, y 48..648 in the base viewport and does not intersect
    the board rect; long content scrolls instead of growing past 648.
19. Tower view: L1 one upgrade button, L2 two branch buttons by branch name, L3 none +
    `Max level`; disabled with `(wave in progress)` during a wave and `(not enough gold)`
    when unaffordable, enabled again by `refresh()` when the cause goes.
20. Clicking a branch button upgrades the tower, the tower view stays, the ring radius
    equals the new range, the sell text shows the new refund; Cancel/sell → idle view.

Controls (revert → test must fail): `stats()` ignoring `branch` (2, 10); `spent` not
increased (8); phase check removed (4); event order swapped (5); `role` allowed on levels
(11); `has_pending` ignoring `PENDING` in the bot (13); pending suffix dropped (16);
`refresh` not re-reading `can_upgrade` (19).

---

## 7. Decisions (owner, 2026-10-31)

1. **Branch effects the sim does not apply yet:** "Отдельная задача в бэклог". Wiring
   crits, second shooter, bleed, pull and armor strip is a separate backlog task (created
   by the orchestrator). LT-24 shows those effects marked "(coming soon)" (`PENDING`, §1,
   §3); the player may still buy such a branch (plain stats); bots skip those branches (§5).
2. **Where the info is shown:** "Фиксированная панель справа". One fixed panel on the right
   edge (x 960..1152 of the 1152×648 base viewport, scaled by `canvas_items` stretch, never
   over the board) holds both build info and selected-tower info (§4).
3. **When upgrades are allowed:** "Только в фазе постройки". Upgrades are refused during a
   wave with `NOT_BUILD_PHASE`; build and sell keep their any-phase rule (no conflict
   found; reasoning in §2).
4. **Refund of upgrades:** "70% от всего потраченного (Recommended)". Refund =
   `roundi(0.7 × (build + upgrades))`; sanity never refunded (§2).
5. **Role line:** "Добавить строку-роль в конфиг". Optional, validated `role` per tower and
   per branch in `towers.json`, first line in the panel, English seed texts from GDD §6
   (§1).
6. **Bot upgrade rule:** "Сначала вширь, потом вглубь (Recommended)". Build 5 towers, then
   the cheapest upgrade, branches per `BRANCH_PICK`, `--upgrades=0` for the old baseline (§5).

Also noted: LT-27 later turns gold into a day/night economy (build phase = day); LT-24
uses today's gold API and LT-27 migrates it.
