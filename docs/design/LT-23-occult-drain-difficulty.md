# LT-23 — Occult sanity reserve, madness hostility and difficulty (design note)

Status: rev. 3, owner decisions recorded · 2026-10-31 · branch
`feat/LT-23-occult-drain-difficulty`. The code slice is based on `feat/LT-24-tower-info-upgrades`
(LT-24 S2/S3 done); line numbers below are that branch's.

History: rev. 1 proposed a constant per-tower drain. The owner replaced it: "оккультные
башни не пожирают рассудок постоянно, а просто отнимают фиксированную сумму от шкалы
рассудка … каждая башня с культистом отнимает 5 единиц разума, а чтец некрономикона −10
сразу (точный баланс нужно искать)", then chose **"Резерв: уменьшает максимум
(Recommended)"** and **"Убрать, только фиксированная сумма (Recommended)"** (no per-cast
cost). Rev. 2 worked that out as a reserve; rev. 3 records the answers to its 12 questions
(§7) and reworks §1-§6 to match.

## 0. What exists today and what this task adds

**Today** (`release-0.2.0` + LT-24): sanity moves only through `Simulation._add_sanity`
(`simulation.gd:477-498`), clamped to `[0, sanity.max]`: build cost (Elder Sign −8,
`sanity_cost`) and upgrade cost (`upgrade_sanity_cost`, paid in `upgrade_tower`), Necronomicon
casts (−2, `sanity_per_cast`, slot 5), horror drain (shoggoth 0.5/s, slot 6), regen (+12
between waves, +0.5 per mundane kill). MADNESS is latched (LT-13): while in it, `_add_sanity`
applies nothing except the exit reasons `buyout` / `auto_restore`. `sanity_per_second` is
parsed and listed in LT-24's `TowerDef.Level.PENDING` (not applied). Madness changes only
occult towers (×2 damage, astray shots 40/35/25); enemies are the same in every state.

Playtest 0.1 (`docs/playtest-0.1.md`, tuning pass 2), re-run on `release-0.2.0` for this note
(10 seeds, load averages 56.7 before, 514.4 after; identical results):

| Strategy | Wins | HP left (of 20) | Sanity at wave ends | Towers per run |
|---|---|---|---|---|
| mundane | 10/10 | 20.0 | 100 every wave | 27.5 riflemen, 13 harpooners |
| occult | 10/10 | 10.8 | 100 / 86 / 15 / 1 / 0 | 27.4 riflemen, 4 signs, 3 readers |
| madness | 0/10 | 0.0 | 84 / 52 / 0 | 4.6 signs, 5.1 readers |

The occult bot is ~80 % riflemen (its sanity guard falls back to a rifleman). Mundane never
loses HP (it first leaks at enemy HP ×2.5, where both occult bots die in wave 1), and occult
is worse than mundane because of per-gold strength: a Rifleman deals 0.25 DPS/gold, a
Reader 0.07 single target (~0.17 with its blast on 2-3 enemies).

**This task** adds:
1. **Sanity reserve**: every occult tower on the board lowers the sanity **cap** by its
   level's `sanity_reserve`; current sanity is cut only when it is above the new cap; selling
   raises the cap again. Per-cast, per-second and one-off sanity costs are removed.
2. **Stronger occult towers** (data), so occult is the better buy per gold.
3. **Madness hostility**: in MADNESS every enemy moves ×1.2 and takes ×0.8 damage.
4. Bot harness: a true occult bot, a `mixed` bot, a cap-aware guard, new metrics.

```
build/upgrade/sell ── _change_reserve(t, delta, reason) ── SANITY_CAP_CHANGED, then clamp (SANITY_CHANGED "reserve")
_add_sanity ── clamps to [0, state.sanity_cap]   (regen never passes the cap)
slot 2 _apply_auras ── _apply_madness_buff        (skips enemies for which _madness_buff_blocked(e); LT-30 hook)
```

Cross-task:
- **LT-24**: upgrades only in the build phase, `role` line, sell refund 70 % of all gold. The
  reserve hooks into `upgrade_tower` and `sell_tower`; the reserve is never part of the 70 %.
- **LT-26** (merged design): its D3 "lit occult: −30 % power and half passive drain" loses its
  drain half (Decision Q7: lit occult gets only −30 % power); its `occult.drain_mult` config key
  is obsolete and its beam task (LT-30) should not add it. LT-26 D4 "enemies in the beam lose
  the madness buff" stays; LT-30 fills `_madness_buff_blocked(e)` (§3). LT-26's note is not
  edited here.
- **LT-27** (day/night economy, money instead of gold) lands after this code; nothing here
  depends on the currency.
- Owner decision already made: no friendly fire in madness (unchanged).

---

## 1. Sanity reserve

### 1.1 Config (`towers.json`)

| Field | Before | After |
|---|---|---|
| `sanity_reserve` (new, per level and branch) | — | the **total** reserve of a tower at that level (not added to lower levels); optional number `>= 0`, default 0; `> 0` only on occult towers |
| `sanity_cost` (tower), `upgrade_sanity_cost` (level) | Elder Sign 8 / 8 | **removed** (Q5) |
| `sanity_per_cast` | Reader 2, Corrupted Rite 4 | **removed** (owner decision) |
| `sanity_per_second` | parsed, PENDING (Corrupted Seal 0.2) | **removed**, and dropped from LT-24's `PENDING` and `has_pending()` |

Removed keys leave the schema, so a file that still has them fails with the usual unknown-key
error.

### 1.2 State and rules

- `SimState.sanity_cap: float` = `sanity.max − Σ reserve of standing towers`, floored at 0;
  starts at `sanity.max`. It changes only in build, upgrade and sell (commands, between
  ticks); no per-tick work, no RNG.
- `_add_sanity` clamps to `[0, sanity_cap]`, so every regen stops at the cap. Horror drain is
  unchanged.
- **Cap only** (Q1): a build with reserve `r` lowers the cap by `r`; current sanity changes
  only if it is above the new cap, and then drops to the cap.
- **Order inside `build_tower`**: `TOWER_BUILT`, `GOLD_CHANGED`, then `_change_reserve(t, r,
  "build")`: `SANITY_CAP_CHANGED {delta: −r, cap, reason: "build"}` (id = tower), then, if
  `sanity > cap`, `_add_sanity(cap − sanity, "reserve", t.id)` → `SANITY_CHANGED "reserve"`
  and `SANITY_STATE_CHANGED` if a threshold is crossed.
- **Upgrade** (`upgrade_tower`, build phase only): delta = target reserve − current reserve,
  reason `"upgrade"`, same steps. A negative delta raises the cap (like a sell).
- **Sell** (Q4): the cap rises by the tower's reserve (`SANITY_CAP_CHANGED {+r, "sell"}`);
  current sanity does not change (regen refills it up to the new cap). In MADNESS the player
  stays mad.
- **Cap to 0** (Q3): allowed. If the new cap is 0, sanity is clamped to 0 → MADNESS
  (latched). The build/upgrade preview warns ("This tower will drive you mad") when
  `cap − delta <= 0` outside MADNESS. With the cap above 0 a build never enters MADNESS on its
  own; horror drain still can.
- **Latch**: `"reserve"` is not an exit reason. In MADNESS sanity is 0, so the clamp has
  nothing to do and the cap moves alone.
- **Thresholds** stay absolute (Q2): Lucid ≥ 70 of 100, whatever the cap. A reserve above 30
  means the player cannot be Lucid until those towers are sold.

Example (Elder Sign 5, Reader 10): start 100/100. Reader: cap 90, sanity 90 (clamped). Two
Signs: cap 80, sanity 80. Horror drains 30: sanity 50 (Whispers). Another Reader: cap 70,
sanity stays 50 (no immediate cost, Q1). Wave clear +12: 62; kills stop at 70. Sell a
Reader: cap 80, sanity 70, regen continues.

### 1.3 Exit rules (Q6)

| Exit rule | With the reserve |
|---|---|
| `permanent` | unchanged; builds and sells in MADNESS move only the cap |
| `buyout` | sets sanity to `min(restore_sanity, sanity_cap)`; at cap 0, `can_buy_sanity()` returns a new `CommandResult.NO_SANITY_ROOM` (appended after `BAD_BRANCH`), checked after `NOT_IN_MADNESS`, before `NOT_ENOUGH_GOLD`: no gold paid for nothing |
| `auto_restore` | sets `min(restore_sanity, cap)`; does nothing at cap 0 |

### 1.4 Read API for the HUD

- `state.sanity_cap` (read-only for scenes, like `state.sanity`).
- `Simulation.reserve_of(t: SimTower) -> float` (its current level's reserve) and
  `Simulation.reserve_delta(def_id, from: TowerDef.Level, to: TowerDef.Level) -> float` for previews; LT-24's
  `TowerInfo` shows "Reserves 10 sanity" and "Upgrade: +5 reserve" instead of the removed cost
  lines.

---

## 2. Occult power and reserves (data, tunable by S5)

| Tower / level | Field | Before | Proposed |
|---|---|---|---|
| Necronomicon L1 | damage / fire_interval / reserve | 40 / 4 s / (2 per cast) | **70 / 3 s / 10** (23.3 DPS per target, ×2.3) |
| Necronomicon L2 | same | 55 / 4 / (2 per cast) | **95 / 3 / 15** |
| Pure Rite (a) | same | 70 / 5 / (2 per cast) | **120 / 4 / 18** (not madness_affected, unchanged) |
| Corrupted Rite (b) | same | 82.5 / 4 / (4 per cast) | **142.5 / 3 / 25** (×1.5 of L2, GDD) |
| Elder Sign L1 | range / slow / damage_taken_multiplier / reserve | 2 / 0.3 / 1.25 / (8 once) | **2.5 / 0.35 / 1.5 / 5** |
| Elder Sign L2 | same | 2.5 / 0.3 / 1.25 / (8 once) | **3 / 0.35 / 1.5 / 8** |
| Pure Ward (a) | same | 3.5 / 0.3 / 1.25 / (8 once) | **4 / 0.35 / 1.5 / 10** |
| Corrupted Seal (b) | same | 2.5 / 0.3 / 1.25 / (8 once + 0.2/s) | **3 / 0.35 / 1.5 / 15**, strip_armor 1 (still PENDING in LT-24, so bots skip it) |

Unchanged: gold costs (pinned), AoE radius 1.5. Rifleman/Harpooner stats start unchanged;
S5 may lower their damage by up to 20 % (Q12).

Per gold: Reader 0.16 DPS/gold single target, ~0.4 with a blast on 2-3 enemies; Elder Sign
×1.5 on every hit in a 2.5-cell aura, so it multiplies the riflemen near it (the mixed build).

Budget: 4 Signs + 3 Readers reserve 50 → cap 50: never Lucid, fakes every 15 s (Whispers).
Fraying needs a reserve above 60 or horror drain under a low cap; MADNESS needs a reserve of
100 (e.g. 6 Readers + 8 Signs) or horror drain to 0.

---

## 3. Madness hostility (former LT-20)

| Question | Decision |
|---|---|
| Stats (Q8) | speed ×`madness.enemy_speed_multiplier` (1.2), damage taken ×`madness.enemy_damage_taken_multiplier` (0.8 = effective HP ×1.25), both per-tick modifiers (`SimEnemy.speed_mult`, `damage_taken_mult`); flat while in MADNESS, no ramp |
| Not used | armor bonus (punishes Riflemen far more than Readers), max HP at spawn (misses enemies on the map, must be undone), leak damage (decides runs in one step) |
| Who (Q9) | every live enemy, on the map and new spawns, from the first slot 2 that sees `sanity_state == MADNESS` |
| Fakes | buffed exactly like real enemies (LT-12: behaviour never tells a fake) |
| Stacking | product after Elder Sign: speed 0.65 × 1.2 = 0.78, damage taken 1.5 × 0.8 = 1.2 |
| Beam hook (LT-26 D4, LT-30) | `_apply_madness_buff` skips `e` when `_madness_buff_blocked(e)` is true; it returns false in this task; LT-30 makes it "e is lit" (real and fake alike) |
| Horror drain | unaffected; latched in MADNESS anyway |
| Removal | the tick after leaving MADNESS (`reset_modifiers` in slot 1) |
| Entry tick | MADNESS reached in a command (cap to 0) → buff from the next step; reached in slot 6 (horror) → from the next tick |
| Config | `sanity.json` `madness` block; optional, `> 0`, default 1.0 (off) |

**Feedback layer (Q10, presentation only):**
- Board: in MADNESS every enemy (real and fake alike) gets a hostile tint (`COLOR_ENEMY`
  lerped to a madness red by `sanity_fx.madness`, the existing smoothed grade) and a dark
  outline; this also fixes the carried-over "enemies barely visible in Madness".
- HUD: in MADNESS a line under the sanity bar: "The world turns hostile: enemies +20 % speed,
  −20 % damage taken" (numbers from config).
- Sanity bar: the reserved part (`cap..max`) as a dark hatched block at the right end;
  label `Sanity 63 / 80` when the cap is below max; threshold marks stay absolute.

---

## 4. Difficulty targets and knobs (S5)

**Cap-only consequence (Q1).** A player whose sanity is already below the new cap pays no
immediate sanity for an occult tower; the cost is only that regen stops lower. In bot runs
nothing drains sanity except horror (shoggoth, wave 5) once casts are gone, so a bot's
sanity sits at its cap almost all the time and "sanity pressure" is the cap. Accounting:
- Bot guards and targets are stated on the **cap** (and on time per sanity state), not on
  current sanity; `min_sanity` stays as a metric for horror dips.
- The "free build while low" case does not arise for bots before wave 5; S5 records how much
  reserve was built while `sanity < cap − reserve` (`free_reserve`) so the size of the effect
  is visible, and the owner replay judges it for humans.
- Deliberate madness is reached only by reserving the whole bar (cap 0) or horror drain under
  a low cap; the madness bot therefore builds until the cap is 0.

Bots (10 seeds, 1000-1009, `tools/bot_runs.gd`, with LT-24 upgrades in the build phase):

| Bot | Build order | Guard |
|---|---|---|
| mundane | rifleman, rifleman, harpooner (unchanged) | none |
| occult | 1 rifleman, then elder_sign / reader alternating; upgrades occult towers when it cannot build | builds/upgrades occult only while `cap − reserve_delta ≥ 30`; otherwise saves gold (no rifleman fallback; at most 3 riflemen per run) |
| mixed (new) | rifleman, rifleman, elder_sign, rifleman, harpooner, reader repeated | same guard with cap floor 60 |
| madness | reader / elder_sign alternating, upgrades occult, no guard | keeps building until the cap is 0 |

Targets (Q11, "Как предложено (Recommended)"; sanity terms restated on the cap):

| Bot | Wins | Mean HP left (of 20) | Sanity pressure |
|---|---|---|---|
| mundane | ≥ 8/10 | 10-18, ≥ 6/10 runs lose ≥ 1 HP | stays Lucid |
| occult | ≥ 8/10 | ≥ mundane's mean − 2 | cap ≤ 50 by wave 4; cap or sanity < 40 (Fraying) in ≥ 7/10 runs; MADNESS in ≤ 2/10; ≥ 5 fakes per run |
| mixed | ≥ 9/10 | ≥ mundane's mean | lowest cap in [20, 70) in ≥ 7/10 runs |
| madness | ≤ 2/10 | — | MADNESS (cap 0) by wave 3 |

New per-run metrics: `min_sanity`, `final_cap`, `cap_per_wave`, `madness_tick` (−1 if
never), `reserve_peak`, `free_reserve`, HP lost per wave, towers by kind and level.

**Knobs S5 may turn:** occult level/branch stats (damage, fire_interval, range, slow,
damage_taken_multiplier, aoe_radius, `sanity_reserve`); the two madness multipliers; enemy
`hp` (one multiplier per type) and wave counts of waves 3-5; Rifleman/Harpooner `damage`
down to −20 % of today's per level/branch (Q12: "Да, до −20% урона"). **Not:** economy (LT-27
owns it), gold costs, mundane range/fire_interval, thresholds, `damage_multiplier`,
`shot_split`, `exit_rule`, `restore_sanity`. Each pinned value S5 changes updates
`config_valid_test` in the same commit.

---

## 5. Edit map (code slice, on `feat/LT-24-tower-info-upgrades`)

### 5.1 Read for context
- `sim/core/simulation.gd`: `_init` 43-55, `step` 67-101, `build_tower` 174-199,
  `sell_tower` 200-216, `upgrade_target`/`can_upgrade`/`upgrade_tower` 228-286,
  `can_buy_sanity`/`buy_sanity`/`auto_restore_sanity` 303-342, `_add_sanity` 477-498,
  `_apply_auras` 542-580, `_fire_towers` 583-645.
- `sim/defs/tower_def.gd` (LT-24): `FIELDS` 5, `parse` 23-53, `Level` 75-160 incl. `PENDING`
  104-118.
- `ui/tower_info.gd` 36-140, `ui/tower_panel.gd` 75-131, `ui/tower_picker.gd` 57-70.
- `tools/bot_runs.gd` (LT-24): header 1-30, `_order` 144-159, `_next_upgrade` 185-210.

### 5.2 Change
| Path | Lines | Change |
|---|---|---|
| `sim/core/sim_state.gd` | after `sanity` | `var sanity_cap := 0.0` |
| `sim/core/sim_event.gd` | 6-8 | append `SANITY_CAP_CHANGED` after `TOWER_UPGRADED` |
| `sim/core/simulation.gd` | 9-25 | append `NO_SANITY_ROOM` to `CommandResult` |
| | 43-55 `_init` | `state.sanity_cap = config.sanity.max_sanity` (before the start clamp) |
| | 67-101 `step` | slot 2: `_apply_madness_buff()` after `_apply_auras()`; slot 5 comment (no cast cost) |
| | 174-199 `build_tower` | replace the `sanity_cost` block (195-196) with `_change_reserve(t, reserve, "build")`; doc comment |
| | 200-216 `sell_tower` | `_change_reserve(t, −reserve_of(t), "sell")` after the refund; doc comment |
| | 262-286 `upgrade_tower` | replace the `upgrade_sanity_cost` block (281-282) with `_change_reserve(t, new − old, "upgrade")` (old read before `t.level += 1`); doc comment |
| | 303-342 | `can_buy_sanity`: `NO_SANITY_ROOM` when `min(restore, cap) <= 0`; `buy_sanity`/`auto_restore_sanity` target `min(restore_sanity, sanity_cap)` |
| | 477-498 `_add_sanity` | clamp to `state.sanity_cap` |
| | 583-645 `_fire_towers` | remove the `sanity_per_cast` payment (637-638) and its doc lines 579-580 |
| | new | `_change_reserve(t, delta, reason)` (§1.2), `reserve_of(t)`, `reserve_delta(...)`, `_apply_madness_buff()`, `_madness_buff_blocked(e) -> bool` (returns false; LT-30 hook) |
| `sim/defs/tower_def.gd` | 5, 18, 31 | drop `sanity_cost` from `FIELDS`, the var and its parse |
| | 75-160 `Level` | `LEVEL_FIELDS`: drop `upgrade_sanity_cost`, `sanity_per_cast`, `sanity_per_second`, add `sanity_reserve`; vars; parse (`opt_number`, default 0, `>= 0`; `> 0` on non-occult → "only occult towers reserve sanity"); remove `sanity_per_second` from `PENDING` and its branch in `has_pending()`; L1 error text for `upgrade_cost` only |
| `sim/defs/sanity_config.gd` | `Madness` | `MADNESS_FIELDS` + the two multipliers; `opt_number(..., 1.0, 0.0, INF, true)` |
| `data/towers.json` | occult levels/branches | §2 values; remove dropped keys |
| `data/sanity.json` | `madness` | `"enemy_speed_multiplier": 1.2, "enemy_damage_taken_multiplier": 0.8` |
| `ui/tower_info.gd` | 42-48, 60-75, 122-140 | `cost_text` gold only; "Reserves N sanity" line; delta "Reserve +N"; remove per-cast/drain lines and `_drain_text` |
| `ui/tower_panel.gd` | 108-131 | `_drives_mad` on the cap: `cap − delta <= 0` outside MADNESS |
| `ui/tower_picker.gd` | 65 | cost text gold only, reserve line, same warning on build |
| `ui/sanity_bar.gd` | `_draw` | reserved block, `n / cap` label |
| `ui/hud.gd` | `refresh` | madness hostility line; buyout disabled on `NO_SANITY_ROOM` |
| `scenes/board.gd` | `_draw_enemies` | madness tint + outline, same for every enemy |
| `tools/bot_runs.gd` | header, `STRATEGIES`, `_order`, `_next_upgrade`, `_play` | `mixed`; cap guard (§4); occult saves gold instead of a rifleman fallback; madness builds to cap 0; new metrics |
| `docs/GDD.md` | §5.3, §5.4, §6 | reserve instead of build/cast costs; madness hostility; occult numbers |

### 5.3 Config validation
- `sanity_reserve`: optional number `>= 0`; `> 0` only on occult towers.
- `sanity_cost`, `upgrade_sanity_cost`, `sanity_per_cast`, `sanity_per_second`: unknown keys.
- madness multipliers: optional number `> 0`, default 1.0.
- No check of total reserve against `sanity.max` (a board may reserve it all).
- `config_reject_test`: one case per new rule and per removed key; `config_valid_test` pins
  the new data (replaces `test_tower_sanity_cost_default_and_explicit`).

### 5.4 Must confirm (code slice)
1. Tests on removed costs (all on the LT-24 branch): `occult_tower_test.gd` (13 references:
   build sanity event, casts), `madness_test.gd` (per-cast), `config_valid_test.gd`,
   `config_reject_test.gd` (4 each), LT-24 upgrade/info tests that read `upgrade_sanity_cost`
   or the drain line. Each becomes a reserve test or goes; list them in the report.
2. `config_reject_test` text fixtures still find their anchor strings in the edited JSON.
3. `scenes/game.gd` debug `--sanity` goes through `_add_sanity`: clamps to the cap (cap = max
   at run start).

---

## 6. Behaviours the tests slice pins (one line each)

Confirmed against the S2 code (`sim/core/simulation.gd` unless named). S2 notes: the cap is
recomputed from the standing towers (`max − Σ reserve_of`, floored at 0), so a test that
wants a given cap builds towers or edits a level's `sanity_reserve` on the loaded config,
never `state.sanity_cap` directly; `SANITY_CAP_CHANGED.delta` is the change actually applied
(smaller than the reserve when the floor at 0 bites), and no event is emitted when the cap
does not move.

1. Build with reserve r at full sanity: cap −r, sanity clamped to the cap; events `TOWER_BUILT`,
   `GOLD_CHANGED`, `SANITY_CAP_CHANGED {−r, cap, "build"}` (id = tower), `SANITY_CHANGED
   "reserve"` (id = tower) — `build_tower` → `_change_reserve`.
2. Build with reserve r when sanity ≤ cap − r: cap −r, sanity unchanged, no `SANITY_CHANGED` —
   `_change_reserve`.
3. Mundane towers and reserve-0 levels: no cap event, no sanity change — `_change_reserve`
   (returns on delta 0); config side `TowerDef.Level.parse`.
4. Regen (between waves, mundane kill) stops at the cap — `_add_sanity` (clamp to
   `state.sanity_cap`).
5. Sell: cap + reserve (`SANITY_CAP_CHANGED {+r, "sell"}` after `GOLD_CHANGED`), sanity
   unchanged; in MADNESS the state stays MADNESS — `sell_tower` → `_change_reserve`.
6. Upgrade (build phase): cap changes by target − current reserve (`"upgrade"`); clamp as in
   1/2; a lower target reserve raises the cap — `upgrade_tower` (`reserve_delta` read before
   `t.level += 1`) → `_change_reserve`.
7. A build/upgrade that takes the cap to 0 sets sanity 0 and enters MADNESS (latched);
   reserves summing above `max` keep the cap at 0 and a sell raises it only once the sum is
   below `max` — `_change_reserve`.
8. Thresholds are absolute: cap 60 → state never LUCID — `sanity_state_for` (unchanged) +
   `_add_sanity` clamp.
9. `buyout`/`auto_restore` restore `min(restore_sanity, cap)`; at cap 0 `can_buy_sanity()` is
   `NO_SANITY_ROOM` (after `NOT_IN_MADNESS`, before `NOT_ENOUGH_GOLD`), no gold paid;
   `auto_restore` changes nothing — `restore_target`, `can_buy_sanity`, `buy_sanity`,
   `auto_restore_sanity`.
10. A Necronomicon cast changes no sanity — `_fire_towers` (no `"cast"` reason any more).
11. Config: `sanity_reserve` > 0 on a mundane level/branch rejected ("only occult towers
    reserve sanity"), < 0 rejected; `sanity_cost`, `upgrade_sanity_cost`, `sanity_per_cast`,
    `sanity_per_second` rejected as unknown fields; madness multipliers ≤ 0 rejected; absent →
    1.0, no buff — `TowerDef.parse`, `TowerDef.Level.parse`, `SanityConfig.Madness.parse`.
12. MADNESS: every live enemy has `speed_mult` ×1.2 and `damage_taken_mult` ×0.8 (config) and
    moves / takes damage accordingly; outside MADNESS both are 1 without auras —
    `_apply_madness_buff` (slot 2, after `_apply_auras`), `SimEnemy.reset_modifiers`.
13. The buff reaches an enemy already on the map and one spawned after — `_apply_madness_buff`
    (loops over `state.enemies` every tick).
14. A fake and a real enemy of the same def have identical modifiers in MADNESS —
    `_apply_madness_buff` (no `is_fake` check); `_madness_buff_blocked` returns false.
15. With an Elder Sign the modifiers are the product — `_apply_auras` then
    `_apply_madness_buff` (both multiply).
16. The step after a command that enters MADNESS has the buff; the step after a buyout has none
    — `step` slot 2 reads `sanity_state`.
17. Same seed + command log (build, upgrade, sell) → identical events (determinism) — no RNG
    in the reserve path.
18. `sanity_per_second` is no longer in `PENDING`; a Corrupted Seal is still pending
    (strip_armor) — `TowerDef.Level.PENDING`, `has_pending`.
19. Render (S3): in MADNESS every enemy gets the same tint (real and fake); the bar draws the
    reserved block when cap < max; the panel warns when a build/upgrade takes the cap to 0.
    S2 already moved `ui/tower_panel.gd` `_drives_mad` to the cap (`cap − delta <= 0`
    outside MADNESS) and `ui/tower_info.gd` to "Reserves N sanity" / "Reserve +N" lines.
20. Bots (`tools/bot_runs.gd`): occult/mixed never build or upgrade an occult item that would
    leave `sanity_cap` below 30 / 60 (`_cap_allows`); the occult bot falls back to a
    rifleman only while it has built fewer than 3, then upgrades or saves (`_order`, `_act`);
    the mixed bot skips a blocked occult item (`_act`); RUN lines carry `min_sanity`,
    `final_cap`, `cap_per_wave`, `madness_tick`, `reserve_peak`, `free_reserve`,
    `hp_lost_per_wave`, `towers_final` (`_play`).

**Controls** (revert the code, the named test must fail):
C1 also subtract r from current sanity on build (2); C2 clamp `_add_sanity` to `max` (4);
C3 add the reserve back to sanity on sell (5); C4 restore `restore_sanity` without the cap
(9); C5 skip fakes in `_apply_madness_buff` (14); C6 apply the buff only at spawn (13);
C7 remove the occult-only reserve check (11).

---

## 7. Decisions (owner, 2026-10-31)

| # | Question | Answer (verbatim) | Effect in this note |
|---|---|---|---|
| Q1 | Reserve from current sanity too, or only the cap? | "Только с потолка" | cap only; sanity clamped only above the new cap (§1.2); consequence for bots and targets in §4 |
| Q2 | Thresholds on the full bar or the cap? | "От полной шкалы (Recommended)" | absolute thresholds |
| Q3 | May a build take sanity to 0? | "Можно, с предупреждением (Recommended)" | allowed; preview warns when the cap would reach 0 |
| Q4 | Selling in madness | "Растёт потолок, безумие остаётся (Recommended)" | sell raises only the cap, in every state |
| Q5 | Elder Sign one-off cost 8 | "Убрать, только резерв (Recommended)" | `sanity_cost` / `upgrade_sanity_cost` removed |
| Q6 | Buyout / auto restore under a low cap | "До минимума из 30 и потолка (Recommended)" | `min(restore_sanity, cap)`; `NO_SANITY_ROOM` at cap 0 |
| Q7 | LT-26 "half drain" for lit occult | "Ничем, только −30% силы (Recommended)" | no sanity effect from the beam; LT-26's `drain_mult` obsolete (§0) |
| Q8 | Madness enemy buff | "Скорость ×1.2, урон по ним ×0.8 (Recommended)" | §3; plus LT-26 D4: lit enemies lose it, hook for LT-30 |
| Q9 | Enemies already on the map | "Усиливаются все сразу (Recommended)" | every live enemy from the next tick |
| Q10 | Visibility | "Оттенок + строка в HUD + блок резерва (Recommended)" | §3 feedback layer |
| Q11 | Bot targets | "Как предложено (Recommended)" | §4 table, sanity terms on the cap |
| Q12 | May S5 weaken mundane towers? | "Да, до −20% урона" | Rifleman/Harpooner damage down to −20 % is an S5 knob |
