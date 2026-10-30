# LT-24 — Tower info panel and upgrades (design note)

Status: draft · 2026-10-31 · branch `feat/LT-24-tower-info-upgrades`

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
- Branch effects the sim does **not** apply yet: `crit_chance`/`crit_multiplier`
  (Marksman), `shooters` (Militia), `bleed_dps`/`bleed_seconds` (Barbed), `pull_cells`
  (Chain harpoon), `strip_armor` (Corrupted Seal), and `sanity_per_second` (Corrupted
  Seal; owned by LT-23). Effects that already work through `stats()`: `range`, `damage`,
  `fire_interval`, `sanity_per_cast`, `madness_affected` (Pure Rite), `pierce`,
  `aoe_radius`, `slow`, `damage_taken_multiplier`. See Open question 1.
- `tools/bot_runs.gd` never upgrades (its header says so); LT-23/S5 tunes with these bots
  and needs upgrades.

**This task adds**: `can_upgrade` / `upgrade_tower` in the sim (levels and branches,
gold + sanity cost, logged, an event), refund over all gold spent, a config-driven text
formatter for tower stats and effects, stats in the build picker, a tower panel with
upgrade/branch/sell buttons, and an upgrade strategy in the bot harness.

```
click tower ─ TowerPanel.open_for(id) ─ rows from TowerInfo.lines(stats) ─ buttons:
   [Upgrade to L2]  or  [Branch A] [Branch B]  or  "Max level"     [Sell] [Cancel]
      └─ Game.upgrade(id, branch) ─ Simulation.upgrade_tower ─ TOWER_UPGRADED,
                                    GOLD_CHANGED "upgrade", SANITY_CHANGED "upgrade"
```

---

## 1. Tower model: level and branch

`SimTower` gains `var branch := ""` (`""` below L3, `"a"`/`"b"` at L3). `level` stays a
0-based index: 0 = L1, 1 = L2, 2 = L3 (the branch). `stats()` becomes:

```
if level >= TowerDef.LEVEL_COUNT: return def.branches[branch]
return def.levels[level]
```

Player-facing text adds 1 (`L1`..`L3`); the sim and events use the index. `TowerDef`
needs no change (unless Open question 5 adds a `role` string).

Cooldown on upgrade: the current `cooldown_ticks` is kept; the new `fire_interval` applies
from the next shot. No free shot, no reset, nothing to exploit, deterministic.

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
| 6 | `state.gold < target.upgrade_cost` | `NOT_ENOUGH_GOLD` |

The three new values are **appended** to `CommandResult` after `NOT_IN_MADNESS` so
existing values never shift (LT-4 convention).

**When allowed:** any phase, paused or not, exactly like `build_tower` (GDD §4 lists
upgrades with building; LT-4 §1.3 pause-building). See Open question 3.

**Sanity:** only gold is checked, like build. `target.upgrade_sanity_cost` is paid through
`_add_sanity(-cost, "upgrade", t.id)`: allowed at any sanity, clamped at 0, can push the
player into MADNESS; while in MADNESS the latch applies nothing (same as a build there).
Today only Elder Sign has an upgrade sanity cost (8 per level, GDD §5.3 "−8 per level").

**On OK, in this order:**
1. `t.level += 1`; at L3 `t.branch = branch`; `t.spent += target.upgrade_cost`.
2. `command_log.append([tick, "upgrade", tower_id, branch])`.
3. `TOWER_UPGRADED` (new `SimEvent.Type`, appended after `FAKE_DISSOLVED`), id = tower,
   data `{"def", "cell", "level": <new index>, "branch", "cost": <gold>}`.
4. `GOLD_CHANGED {reason: "upgrade"}` via `_add_gold(-cost, "upgrade", t.id)`.
5. `SANITY_CHANGED {reason: "upgrade"}` when `upgrade_sanity_cost > 0` (and not latched).

The tower keeps its id, cell, `build_tick` and `status`.

**Refund:** unchanged formula `roundi(t.spent * sell_refund_ratio)`; `spent` now includes
upgrades, which is GDD §5.1 "70 % of total spent" and what `SimTower.spent` was declared
for. Rounding is applied once to the total (not per purchase). Sanity is never refunded.
Examples at 0.7: Rifleman L3 = 50 + 40 + 80 = 170 → 119; Harpooner L2 = 70 + 55 = 125 →
87.5 → 88; Elder Sign L3 = 100 + 80 + 140 = 320 → 224 (24 sanity spent, none back).
See Open question 4.

## 3. Info text from config (`ui/tower_info.gd`, new)

A static, pure formatter `TowerInfo` (no nodes; unit-testable) used by both panels:

- `lines(def: TowerDef, s: TowerDef.Level, sanity: SanityConfig) -> PackedStringArray`
- `delta_lines(from: TowerDef.Level, to: TowerDef.Level) -> PackedStringArray`
- `cost_text(gold: int, sanity_cost: float) -> String` → `"40 gold"`, `"80 gold + 8 sanity"`

Every number comes from `TowerDef` / `SanityConfig`; no number is written in UI code.

**Stat lines** (omitted when the field is 0/absent):

| Field | Text | Example |
|---|---|---|
| damage + fire_interval | `Damage <d> every <i> s (<dps> DPS)` | `Damage 10 every 0.8 s (12.5 DPS)` |
| damage 0 | `Support (no damage)` | Elder Sign |
| range | `Range <r> cells` / support: `Aura radius <r> cells` | `Aura radius 2 cells` |
| sanity_per_cast | `−<n> sanity per cast` | Necronomicon |
| sanity_per_second | `−<n> sanity/s while on the board` | Corrupted Seal (LT-23 applies it) |

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

**Kind lines** (from kind, `madness_affected` and `sanity.json`):
- mundane: `Kills restore <regen_mundane_kill> sanity`; `May miss while Fraying
  (<fraying.miss_chance>%)`.
- occult, `madness_affected`: `In madness: x<damage_multiplier> damage, shots go astray`.
- occult, not `madness_affected`: `Unaffected by madness`.
- build sanity cost on the picker: `Costs <sanity_cost> sanity to build`.

Numbers print with up to 2 decimals, trailing zeros dropped (`3.5`, `82.5`, `0.2`).
LT-27 renames gold; `TowerInfo` keeps the currency word in one constant so LT-27 edits one
line here.

## 4. Where it is shown and the UI flow

**Build picker** (`ui/tower_picker.gd`, popup at the clicked buildable cell): each tower
row keeps its button (`"<Name> - <cost>"` + disabled reason, as today) and gets a smaller
label under it with the L1 `lines()` joined by ` · ` (one or two wrapped lines, max width
~260 px, tunable). Sanity build cost is in the button text: `Elder Sign - 100 gold + 8
sanity`.

**Tower panel** (today `SellPanel`; class renamed to `TowerPanel`, file
`ui/tower_panel.gd`, node name `TowerPanel`; see edit map), popup at the clicked tower:

```
Rifleman  L2                          ← title: name, level, branch name at L3
Damage 14 every 0.7 s (20 DPS)        ← lines(current stats)
Range 3.5 cells
Kills restore 0.5 sanity · May miss while Fraying (15%)
── Upgrade ──
[Marksman - 80 gold]                  ← one button per upgrade_branches(t)
  Range 3.5 → 5 · Damage 14 → 18 · 20% chance to deal x2 damage
[Militia - 80 gold]
  Damage 14 → 12 · every 0.7 → 0.5 s · 2 shooters
[Sell (+63 gold)]   [Cancel]
```

- L1: one button `Upgrade to L2 - <cost>` with its `delta_lines` under it.
- L2: two branch buttons named by the branch `name`, each with its delta and effects.
- L3: no upgrade buttons; the title shows the branch name, a line `Max level`.
- A button is disabled when `can_upgrade` is not OK, with the reason appended as the
  picker does: `NOT_ENOUGH_GOLD` → `(not enough gold)`, `OUTCOME_REACHED` → `(run over)`.
  `REASONS` move to one shared table (in `TowerInfo`) used by both panels.
- Occult upgrade with a sanity cost: when `state.sanity - cost <= 0` and not in MADNESS,
  the button stays enabled and gets ` (drives you mad!)` appended. In MADNESS the cost
  text stays (the latch makes it free; no special wording).
- `refresh()` runs every frame and after each command (as today), so affordability and the
  refund track gold live; after an upgrade the panel stays open on the same tower, and
  the board's `selected_range` is re-read from `t.stats()` so the ring grows.
- Clicking a button calls `Game.upgrade(tower_id, branch)` (new, like `Game.sell`).
- Board (`scenes/board.gd` `_draw_tower`): a minimal level mark (1-3 pips; `a`/`b` letter
  at L3) so the player sees upgraded towers. Distinct looks belong to LT-25.

Placement (popup vs fixed side panel): Open question 2.

## 5. Bot harness upgrades (`tools/bot_runs.gd`)

Rule, "wide then deep" (deterministic; one purchase per loop iteration, as today):

1. Next purchase = the strategy's next **build** while the board has fewer than
   `BUILD_FIRST = 5` towers (tunable).
2. Otherwise next purchase = the **cheapest upgrade** (gold) among this run's towers that
   are not at L3; ties → lower tower id. L3 branch per strategy and tower from
   `BRANCH_PICK` (below). If every tower is at L3, next purchase = the next build.
3. Buy it if `can_*` is OK; otherwise stop for this round (the bot saves for it, it does
   not skip to something cheaper). Then, in BUILD, `call_wave()` as today.
4. Sanity guard (`occult` only, unchanged threshold 25): an upgrade whose
   `upgrade_sanity_cost` would leave sanity < 25 is skipped this round (the next candidate
   is taken). `madness` has no guard.

`BRANCH_PICK` (tunable; GDD flavour: pure for the careful bot, corrupted for the mad one):

| Strategy | rifleman | harpooner | elder_sign | necronomicon_reader |
|---|---|---|---|---|
| mundane | a Marksman | a Barbed | — | — |
| occult | a Marksman | — | a Pure Ward | a Pure Rite |
| madness | — | — | b Corrupted Seal | b Corrupted Rite |

- New flag `--upgrades=0` turns rule 2 off, reproducing the LT-15 / 0.1 baseline for
  before/after comparison in LT-23/S5. Default on.
- `RUN` JSON gains `"upgrades": {"rifleman_L2": n, "rifleman_a": n, ...}` and
  `"upgrade_gold": <total>`; header comment updated (drop "No upgrades or sells").
- Placement is unchanged (L1 range scoring).

The rule is a starting point for LT-23/S5, which may tune `BUILD_FIRST` and `BRANCH_PICK`;
see Open question 6.

---

## 6. Must confirm, edit map, behaviours

### Must confirm (code slices)
1. Nothing outside `sim/` reads `SimTower.level` or `def.levels[...]` for a placed tower
   except `SellPanel.open_for` (`t.stats()`); `bot_runs._best_cell` reads `levels[0]` for
   scoring only (fine).
2. No consumer switches on `SimEvent.Type` exhaustively (board `on_event`, `sanity_fx`):
   the appended `TOWER_UPGRADED` must be ignored safely.
3. No test asserts `CommandResult.size()` or `SimEvent.Type.size()`.
4. `scene_game_test.gd` finds the sell panel by name/class (`SellPanel`, `SellButton`):
   S3 updates those references with the rename.
5. LT-23 branch state at S2 start: if LT-23/S2 has landed, merge `release-0.2.0` first;
   otherwise LT-23/S2 rebases on LT-24/S2 (see below).

### Edit map — S2 (sim command + bots)
Read for context: `simulation.gd` `build_tower` 169-194, `sell_tower` 196-215,
`can_buy_sanity` / `buy_sanity` 230-261 (check-then-command style), `_add_gold` 388-397,
`_add_sanity` 398-425; `tower_def.gd` 1-17; `tests/gold_test.gd` 116-190 (sell tests);
`tests/sim_test_base.gd`.

| Path | Lines | Change |
|---|---|---|
| `sim/core/sim_tower.gd` | 3-4, 10-11, 19-20 | doc comment; `var branch := ""`; `stats()` per §1 |
| `sim/core/sim_event.gd` | 6-8 | append `TOWER_UPGRADED` |
| `sim/core/simulation.gd` | 9-21 | append `MAX_LEVEL`, `NEED_BRANCH`, `BAD_BRANCH` (comments) |
| | after 215 | `upgrade_branches`, `upgrade_target`, `can_upgrade`, `upgrade_tower` per §2 |
| | 196-198, 285-288 | doc comments: refund covers upgrades (formula unchanged) |
| | 494 | comment: `strip_armor` still not applied (or wired, per Q1) |
| `tools/bot_runs.gd` | 1-26 | header, `BUILD_FIRST`, `BRANCH_PICK`, `--upgrades` flag |
| | 60-111 | track `upgrades` / `upgrade_gold` (from `TOWER_UPGRADED` events); add to RUN |
| | 113-141 | `_act` picks build vs upgrade per §5; new `_next_upgrade(sim, strat)` |
| `tests/upgrade_test.gd` | new | §6 behaviours 1-12 (tests slice) |

LT-23 conflict: LT-23/S2 also edits `simulation.gd` (passive drain, madness buff) after
LT-24/S2. LT-24/S2 touches only the enum tail, a new block after `sell_tower` and doc
comments, so the overlap is the enum tail at most. LT-23's drain should read
`t.stats().sanity_per_second`, which then covers Corrupted Seal through the branch.

### Edit map — S3 (UI)
Read for context: `ui/tower_picker.gd` (all, 89 lines), `ui/sell_panel.gd` (all, 72),
`scenes/game.gd` 27-28, 84-91, 121-131, 160-186; `scenes/board.gd` `_draw_tower` 238-245;
`tests/scene_game_test.gd` 32-75, 92-136.

| Path | Lines | Change |
|---|---|---|
| `ui/tower_info.gd` | new | `TowerInfo` formatter + shared `REASONS` per §3 |
| `ui/tower_picker.gd` | 1-15, 23-45, 66-77 | `REASONS` → `TowerInfo`; info label per row; sanity in text |
| `ui/sell_panel.gd` → `ui/tower_panel.gd` | all | `TowerPanel`: title, stat lines, upgrade/branch buttons, sell, reasons, ring refresh (`git mv`, keep `.uid` consistent) |
| `scenes/game.gd` | 27-28, 88-91, 115-116, 163-165, 173-174, 184 | `sell_panel` → `tower_panel`; new `upgrade(id, branch)` after 131 |
| `scenes/board.gd` | 238-245 | level pips / branch letter |
| `tests/scene_game_test.gd` | 120-136 + new | rename refs; upgrade via UI; disabled reason |
| `tests/tower_info_test.gd` | new | §6 behaviours 13-16 |

### Behaviours the tests slice pins (one line each)
1. L1 → L2 for `levels[1].upgrade_cost`: level 1, gold down by the cost, `spent` up by it.
2. L2 → L3 with `"a"`/`"b"`: level 2, `branch` set, `stats()` is that branch (range, damage).
3. Rejections in table order, each changing nothing (gold, level, events, `command_log`):
   `OUTCOME_REACHED`, `NO_SUCH_TOWER` (sold id), `MAX_LEVEL`, `NEED_BRANCH`, `BAD_BRANCH`
   (`"c"`, and `"a"` at L1), `NOT_ENOUGH_GOLD` (gold = cost − 1 refused, = cost accepted).
4. OK emits `TOWER_UPGRADED {def, cell, level, branch, cost}` then `GOLD_CHANGED
   {reason: "upgrade"}`, then for Elder Sign `SANITY_CHANGED {reason: "upgrade", delta: −8}`.
5. `command_log` gets `[tick, "upgrade", id, branch]`; a replay of the log gives the same
   events and state (determinism).
6. Upgrade works in BUILD, during a wave and at any sanity; an upgrade sanity cost can push
   sanity to 0 / MADNESS; in MADNESS it applies nothing.
7. Sell after upgrades refunds `roundi(0.7 × total spent)` (Rifleman L3 → 119,
   Harpooner L2 → 88).
8. An upgraded tower fights with the new stats from the next shot: L2 Rifleman's `SHOT`
   damage is 14 and its next cooldown is `ticks(0.7)`; the running cooldown is kept.
9. Pure Ward's aura covers an enemy at 3.5 cells that L1 did not reach at 2.
10. Pure Rite in MADNESS: no x2, no `astray`; Corrupted Rite casts cost 4 sanity.
11. Bots: with upgrades on, every strategy buys at least one upgrade over 10 seeds; with
    `--upgrades=0` the RUN lines equal the pre-LT-24 harness for the same seeds.
12. Bots pick branches per `BRANCH_PICK` (madness only `b`, occult never `b`).
13. `TowerInfo.lines` for each of the 4 towers × 4 stats (L1, L2, a, b) has a line for
    every non-zero stat and every effect key, built from config (a config edit changes text).
14. Unknown effect key renders as `key: value` without error.
15. Tower panel: L1 shows one upgrade button, L2 two branch buttons by branch name, L3
    none + `Max level`; a button is disabled with `(not enough gold)` when unaffordable and
    enabled once gold arrives (refresh).
16. Clicking a branch button upgrades the tower, the panel stays open, the ring radius
    equals the new range, the sell text shows the new refund.

Controls (revert → test must fail): `stats()` ignoring `branch` (2, 9); `spent` not
increased (7); gold check removed (3); event order swapped (4); `--upgrades=0` still
upgrading (11); `refresh` not re-reading `can_upgrade` (15).

---

## 7. Open questions for the owner

1. **Branch effects the sim does not apply yet.** *Today* six L3 effects are only parsed:
   Marksman's crits, Militia's second shooter, Barbed's bleed, Chain harpoon's pull,
   Corrupted Seal's armor strip (its sanity drain is LT-23). After this task a player can
   buy them, but they would do nothing beyond their plain stats. *Example:* Barbed costs
   100 gold and has exactly L2's damage and range; without bleed it is 100 gold for
   nothing; Militia without its second shooter is just a faster, weaker-hitting L2.
   *Options:*
   (a) **Recommended:** keep LT-24 to the upgrade command and UI, and open a new task
   "L3 branch effects" (5 mechanics, own design note, before LT-23/S5 tuning). The panel
   marks an unapplied effect `(coming soon)` so the player is not misled. *Consequence:*
   LT-24 stays small; tuning waits for the new task or tunes without those branches
   (bots skip them meanwhile).
   (b) Wire all five in LT-24/S2. *Consequence:* complete branches in one task, but
   LT-24 doubles (bleed and pull are new mechanics with their own tests and design
   questions, e.g. does a pull stack, does bleed ignore armor) and delays LT-23.
   (c) Hide unapplied branches (L3 not offered for those towers yet). *Consequence:*
   nothing misleading, but Rifleman and Harpooner stop at L2 for now.
2. **Where the info is shown.** *Today* both panels are small popups next to the clicked
   cell; the playtest finding says "side panel". *Change (recommended):* keep the popups
   and add the stat/effect lines and upgrade buttons in them (§4). *Example:* click a
   Rifleman → popup beside it shows its stats, two branch buttons and Sell.
   *Consequence:* minimal layout work, info right where the player looks; the popup gets
   taller (~10 lines) and may cover nearby towers. *Alternative:* a fixed panel on the
   right edge of the screen for both build and tower info. *Consequence:* never covers the
   board, room for more text, but needs screen space (LT-22 scaling, LT-28 polish) and
   moves the eye away from the cell.
3. **When upgrades are allowed.** *Today* building and selling work in any phase, also
   paused. *Change (recommended):* upgrades too, any time. *Example:* mid-wave a shoggoth
   approaches; the player pauses and upgrades a Harpooner. *Consequence:* consistent with
   build/sell, gold earned mid-wave is spendable at once. *Alternative:* BUILD phase only.
   *Consequence:* more planning tension, but a rule that differs from building and makes
   pause less useful.
4. **Refund of upgrades.** *Today* only build cost exists; refund = 70 % of it. *Change
   (recommended):* 70 % of all gold spent (build + upgrades), rounded once (GDD §5.1).
   *Example:* Rifleman to Marksman costs 170 total → sell for 119. Sanity spent is never
   refunded. *Consequence:* re-placing an upgraded tower loses 30 % of the investment.
   *Alternative:* refund 70 % of build cost only (Marksman → 35). *Consequence:* upgrades
   become a hard commitment, but contradicts the GDD and the existing `spent` field.
5. **Role line ("what a tower does" in words).** *Today* `towers.json` has no description;
   GDD §6 has a role per tower ("single target, steady DPS"). *Change (recommended):* stats
   and effects only, generated from config (§3). *Example:* Harpooner shows "Damage 18
   every 1.6 s · Range 4 cells · Line shot: hits every enemy on a 1-cell-wide line".
   *Consequence:* always true to config, no text to maintain. *Alternative:* add an
   optional `"role"` string per tower and per branch in `towers.json`, shown as the
   first line. *Consequence:* friendlier, but a schema change and text that can drift
   from the numbers.
6. **Bot upgrade rule.** *Today* bots only build. *Change (recommended):* "wide then
   deep" (§5): build 5 towers, then put every next purchase into the cheapest upgrade,
   pure branches for the `occult` bot, corrupted for `madness`; `--upgrades=0` keeps the
   old baseline. *Example:* mundane bot: 3 riflemen + 2 harpooners, then 5 × L2, then
   Marksman/Barbed, then the 6th tower. *Consequence:* simple and deterministic, but one
   fixed rule; LT-23/S5 may tune `BUILD_FIRST`. *Alternative:* upgrade only when the
   next build is unaffordable (opportunistic). *Consequence:* closer to "spend everything",
   but builds dominate and bots rarely reach L3, so tuning sees little of the branches.
