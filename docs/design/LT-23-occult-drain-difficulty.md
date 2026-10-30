# LT-23 — Occult sanity reserve, madness hostility and difficulty (design note)

Status: draft (rev. 2: reservation model) · 2026-10-31 · branch `feat/LT-23-occult-drain-difficulty`

Rev. 2: the owner replaced the constant drain with a fixed amount per tower: "оккультные
башни не пожирают рассудок постоянно, а просто отнимают фиксированную сумму от шкалы
рассудка … каждая башня с культистом отнимает 5 единиц разума, а чтец некрономикона −10
сразу (точный баланс нужно искать)". Owner decisions: **"Резерв: уменьшает максимум
(Recommended)"** (while an occult tower stands, it reserves part of the bar, lowering max
sanity; regen cannot pass the lowered cap; selling returns the reserve) and **"Убрать, только
фиксированная сумма (Recommended)"** (no per-cast sanity cost for the Reader).

## 0. What exists today and what this task adds

**Today** (`release-0.2.0`): sanity moves only through `Simulation._add_sanity`
(`sim/core/simulation.gd:404-425`), clamped to `[0, sanity.max]`: build cost (Elder Sign −8,
`sanity_cost`, and −8 per upgrade, `upgrade_sanity_cost`), Necronomicon casts (−2 per cast,
`sanity_per_cast`, slot 5), horror drain (shoggoth 0.5/s, slot 6), regen (+12 between waves,
+0.5 per mundane kill). MADNESS is latched (LT-13): while in it, `_add_sanity` applies nothing
except the exit reasons `buyout` / `auto_restore`. `TowerDef.Level.sanity_per_second` is
parsed but unused. Madness changes only occult towers (×2 damage, astray shots 40/35/25);
enemies are the same in every sanity state.

Playtest 0.1 (`docs/playtest-0.1.md`, tuning pass 2, committed data):

| Strategy | Wins | HP left (of 20) | Sanity at wave ends |
|---|---|---|---|
| mundane | 10/10 | 20.0 | 100 every wave |
| occult | 10/10 | 10.8 | 100 / 86 / 15 / 1 / 0 |
| madness | 0/10 | 0.0 | 84 / 52 / 0 |

Re-run on `release-0.2.0` for this note (10 seeds, load averages 56.7 before, 514.4 after;
identical results): same table, and the tower counts show the occult bot is not occult:
per run it builds **27.4 riflemen, 4 Elder Signs, 3 Readers** (its sanity guard falls back to
a rifleman), the mundane bot 27.5 riflemen + 13 harpooners, the madness bot 4.6 signs +
5.1 readers. Occult's lost HP (9-11 in every seed) comes from a build that is ~80 %
riflemen with fewer harpooners.

Missed targets: mundane never loses HP (it first leaks at enemy HP ×2.5, where both occult
bots die in wave 1), and occult is worse than mundane. The cause is per-gold strength:
a Rifleman deals 12.5 DPS for 50 gold (0.25 DPS/gold), a Necronomicon Reader 10 DPS per
target for 150 gold (0.07 single, ~0.17 with its blast on 2-3 enemies). As long as occult
is the weaker buy, no enemy or wave tuning can make mundane leak while occult survives.

**This task** adds:
1. **Sanity reserve**: every occult tower on the board lowers the sanity cap by its level's
   `sanity_reserve`; current sanity drops by the same amount (Q1); selling returns it.
   Per-cast, per-second and one-off build sanity costs are removed.
2. **Stronger occult towers** (data only), so occult is the better buy per gold and the
   reserve is its price. Then enemy difficulty can rise until mundane leaks.
3. **Madness hostility**: in MADNESS every enemy moves faster and takes less damage.
4. Bot harness: a `mixed` strategy, a reserve-aware guard, sanity-pressure metrics.

```
command build/upgrade/sell ── _reserve_changed(t, delta) ── cap, then sanity (SANITY_CAP_CHANGED, SANITY_CHANGED "reserve"/"release")
slot 2 _apply_auras ── _apply_madness_buff        (speed_mult, damage_taken_mult × madness.*)
_add_sanity ── clamps to [0, state.sanity_cap]    (regen never passes the cap)
```

Cross-task:
- **LT-24** (in progress, sim code lands first): upgrades only in the build phase, a "role"
  line in the tower panel, sell refund 70 % of all gold spent. The reserve hooks into its
  upgrade command (delta of the two levels' reserves) and its sell (full reserve back,
  not 70 %). Its panel shows "Reserves N sanity" for occult towers.
- **LT-26** (merged design, `docs/design/LT-26-lighthouse-beam.md`): "lit occult: −30 % power
  and half passive drain" assumed a drain that no longer exists; what it maps to is Q7.
  "Enemies in the beam lose the madness buff" is unchanged and fits §3 (a per-tick modifier).
- **LT-27** (in progress): day/night economy, money instead of gold. Nothing here depends on
  the currency; edit-map rows that touch `_add_gold` / "gold" follow LT-27's names.
- Owner decision already made: no friendly fire in madness (unchanged here).

---

## 1. Sanity reserve

### 1.1 Config

| Field | Today | Rev. 2 |
|---|---|---|
| `sanity_reserve` (new, per level and branch in `towers.json`) | — | the **total** reserve of a tower at that level (L2's value is not added to L1's); `>= 0`; `> 0` only on occult towers |
| `sanity_cost` (tower), `upgrade_sanity_cost` (level) | Elder Sign 8 / 8 | **removed** (Q5): the reserve is the one sanity price |
| `sanity_per_cast` | Reader 2, Corrupted Rite 4 | **removed** (owner decision) |
| `sanity_per_second` | parsed, unused (Corrupted Seal 0.2) | **removed**: no constant drain; "Corrupted" branches carry a larger reserve instead |

Removed keys leave the schema, so a `towers.json` that still has them fails to load with the
usual "unknown key" error (no silent ignore). The `config_reject_test` text fixtures that rely
on them move to `sanity_reserve`.

### 1.2 State and the rule

- New `SimState.sanity_cap: float` = `sanity.max − Σ reserve of standing towers`, floored at
  0. Starts at `sanity.max`. Changes only on build, upgrade, sell (player commands, between
  ticks); never per tick, no RNG.
- `_add_sanity` clamps to `[0, sanity_cap]` instead of `[0, max]`, so every regen stops at
  the cap. Horror drain is unchanged.
- **Build** of a tower with reserve `r` (order inside the command):
  1. `sanity_cap −= r` → `SANITY_CAP_CHANGED {delta: −r, cap, reason: "build"}`, id = tower.
  2. `sanity −= r` (Q1) through `_add_sanity(−r, "reserve", tower_id)` → `SANITY_CHANGED`
     and, if a threshold is crossed, `SANITY_STATE_CHANGED`. If the cap fell below current
     sanity some other way, the clamp covers it in the same call.
  3. Reaching 0 enters MADNESS (latched), as any other drain does (Q3: the build is allowed).
- **Upgrade** (LT-24, build phase only): `delta = new_level.reserve − old_level.reserve`;
  same two steps with reason `"upgrade"`; a negative delta is handled as a release.
- **Sell**: `sanity_cap += r` (`SANITY_CAP_CHANGED {delta: +r, reason: "sell"}`), then
  `_add_sanity(+r, "release", tower_id)`: the bar gets the reserve back up to the cap. The full
  reserve returns, unlike the 70 % gold refund.
- **Latch**: `"reserve"` and `"release"` are not exit reasons, so in MADNESS a build or sell
  moves the cap only; current sanity stays 0 and the player stays mad (Q4).
- **Thresholds** stay absolute (Lucid ≥ 70 of 100, not of the cap) (Q2): reserving 40
  means the player cannot be Lucid again until those towers are sold.

Example (Elder Sign 5, Reader 10; no other changes): start 100/100. Build a Reader: cap 90,
sanity 90. Build two Signs: cap 80, sanity 80. Horror drains 15: sanity 65 (Whispers). Wave
clear +12: 77, then +0.5 kills stop at 80. Sell the Reader: cap 90, sanity 90.

### 1.3 Exit rules

| Exit rule | With the reserve |
|---|---|
| `permanent` | unchanged; building/selling in MADNESS moves only the cap |
| `buyout` | sets sanity to `min(restore_sanity, sanity_cap)`. If that is 0 (cap 0), `can_buy_sanity()` refuses with a new `CommandResult.NO_SANITY_ROOM` (appended), so no gold is paid for nothing (Q6) |
| `auto_restore` | same `min(restore_sanity, cap)`; does nothing when the cap is 0 |

`restore_sanity` keeps its validation (`> 0` for these rules); the cap is runtime only.

### 1.4 Read API for the HUD

- `state.sanity_cap` (read-only for scenes, like `state.sanity`).
- `Simulation.sanity_reserve_of(def_id, level := 0) -> float` for the build/upgrade preview
  (picker and LT-24 panel: "Reserves 10 sanity", "Upgrade: +5 reserve").
- Sanity bar: the reserved part (`cap..max`) is drawn as a dark hatched block at the right
  end; the threshold marks stay at their absolute positions.

---

## 2. Occult power and reserves (data, all values tunable by S5)

| Tower / level | Field | Today | Proposed |
|---|---|---|---|
| Necronomicon L1 | damage / fire_interval | 40 / 4 s | **70 / 3 s** (23.3 DPS per target, ×2.3) |
| | sanity_reserve | (2 per cast) | **10** |
| Necronomicon L2 | damage / fire_interval / reserve | 55 / 4 | **95 / 3 / 15** |
| Pure Rite (a) | damage / interval / reserve | 70 / 5 | **120 / 4 / 18** (not madness_affected, unchanged) |
| Corrupted Rite (b) | damage / interval / reserve | 82.5 / 4 | **142.5 / 3 / 25** (×1.5 of L2, GDD) |
| Elder Sign L1 | range / slow / damage_taken_multiplier / reserve | 2 / 0.3 / 1.25 / (8 once) | **2.5 / 0.35 / 1.5 / 5** |
| Elder Sign L2 | same | 2.5 / 0.3 / 1.25 / (8 once) | **3 / 0.35 / 1.5 / 8** |
| Pure Ward (a) | same | 3.5 / 0.3 / 1.25 / (8 once) | **4 / 0.35 / 1.5 / 10** |
| Corrupted Seal (b) | same | 2.5 / 0.3 / 1.25 / (8 once + 0.2/s) | **3 / 0.35 / 1.5 / 15**, strip_armor 1 |

Unchanged: gold costs (pinned, `config_valid_test`), AoE radius 1.5, Rifleman/Harpooner stats.

Per gold after the change: Reader 0.16 DPS/gold single target, ~0.4 with a blast on 2-3
enemies; Elder Sign ×1.5 on every hit in a 2.5-cell aura, so it multiplies the riflemen
around it (that is the mixed build's reason to exist).

Budget: today's occult bot (4 Signs, 3 Readers) would reserve 50: cap 50, never Lucid, fakes
every wave (Whispers), Fraying after ~10 horror drain. Reaching MADNESS needs a reserve of
100 (e.g. 6 Readers + 8 Signs) or horror drain with a cap near 0, so madness becomes a choice
of how far to build, not an accident of a long wave.

---

## 3. Madness hostility (former LT-20)

| Question | Decision | Why |
|---|---|---|
| Stats | speed ×`enemy_speed_multiplier` (1.2) and damage taken ×`enemy_damage_taken_multiplier` (0.8 = effective HP ×1.25) (Q8) | both are existing per-tick modifiers (`SimEnemy.speed_mult`, `damage_taken_mult`), so no HP bookkeeping; faster also means less time in range of every tower |
| Not chosen | armor bonus (flat: −2 is −20 % of a Rifleman hit, −3 % of a Reader blast, punishes mundane, not the madness builder); max HP on spawn (does not reach enemies already on the map, must be undone on exit); leak damage (decides runs in one step) | |
| Size | flat while in MADNESS, no ramp (Q8) | readable; S5 can tune the two numbers |
| Who | every live enemy, already on the map and new spawns, from the first tick slot 2 sees `sanity_state == MADNESS` (Q9) | a modifier rebuilt each tick has no "already on the map" special case |
| Fakes | buffed exactly like real enemies | LT-12 owner decision: behaviour must never tell a fake; LT-26: lit fakes lose it like lit reals |
| Stacking | multiplies after Elder Sign: speed 0.65 × 1.2 = 0.78, damage taken 1.5 × 0.8 = 1.2 | one rule (product); signs stay useful in madness |
| Beam (LT-26) | a lit enemy skips the buff that tick (LT-26 D4); LT-26's slice adds the check | per-tick modifier makes it a one-line condition |
| Horror drain | unaffected; in MADNESS the latch already makes it a no-op | no double punishment |
| Removal | the tick after leaving MADNESS (`reset_modifiers` in slot 1) | buyout lands between ticks; auto_restore lands in slot 8 before BUILD |
| Entry tick | MADNESS reached in a command (build between ticks) → buff from the next step; reached in slot 6 (horror) → buff from the next tick | fixed order, pinned by a test |
| Config | `sanity.json` `madness.enemy_speed_multiplier`, `madness.enemy_damage_taken_multiplier` | the madness block already holds all madness rules |

**Sanity feedback layer (presentation only, Q10):**
- Board: in MADNESS every enemy (real and fake alike) is drawn with a hostile tint
  (`COLOR_ENEMY` lerped to a madness red by `sanity_fx.madness`, the existing smoothed 0..1
  grade) and a dark outline, so it reads as "the world turned on me" and also fixes the
  carried-over "enemies barely visible in Madness".
- HUD: in MADNESS a line under the sanity bar: "The world turns hostile: enemies +20 % speed,
  −20 % damage taken" (numbers from config).
- Sanity bar: the reserved block (§1.4) and `Sanity 63 / 80` in the label when the cap is
  below max.

---

## 4. Difficulty targets and knobs (S5)

Bots (10 seeds, 1000-1009, `tools/bot_runs.gd`, with LT-24 upgrades in the build phase):

| Bot | Build order | Guard |
|---|---|---|
| mundane | rifleman, rifleman, harpooner (unchanged) | none |
| occult | 1 rifleman, then elder_sign / reader alternating; upgrades occult towers when it cannot build | builds/upgrades occult only while `cap − reserve_delta ≥ 30` and `sanity − reserve_delta ≥ 20`; otherwise **saves gold** (no rifleman fallback; at most 3 riflemen per run, so it stays an occult build) |
| mixed (new) | rifleman, rifleman, elder_sign, rifleman, harpooner, reader repeated | same guard with cap floor 60 |
| madness | reader / elder_sign alternating, no guard (unchanged) | none: keeps building until the cap reaches 0 |

Targets (Q11):

| Bot | Wins | Mean HP left (of 20) | Sanity pressure |
|---|---|---|---|
| mundane | ≥ 8/10 | 10-18, and ≥ 6/10 runs lose ≥ 1 HP | stays Lucid (expected) |
| occult | ≥ 8/10 | ≥ mundane's mean − 2 | cap ≤ 50 by wave 4; min sanity < 40 (Fraying) in ≥ 7/10 runs; MADNESS in ≤ 2/10; ≥ 5 fakes per run |
| mixed | ≥ 9/10 | ≥ mundane's mean | min sanity in [20, 70) in ≥ 7/10 runs |
| madness | ≤ 2/10 | — | reaches MADNESS by wave 3 |

New per-run metrics (harness): `min_sanity`, `final_cap`, `cap_per_wave`, `madness_tick`
(first tick in MADNESS or −1), `reserve_peak`, HP lost per wave, towers by kind and level.

**Knobs S5 may turn:** occult level/branch stats in `towers.json` (damage, fire_interval,
range, slow, damage_taken_multiplier, aoe_radius, `sanity_reserve`); the two madness enemy
multipliers; enemy `hp` (one multiplier per type) and wave counts of waves 3-5. **Not without
the owner:** economy (pinned; LT-27 owns it), tower gold costs, Rifleman/Harpooner stats
(Q12), thresholds, `damage_multiplier`, `shot_split`, `exit_rule`, `restore_sanity`. Each
pinned value S5 changes updates `config_valid_test` in the same commit.

---

## 5. Edit map (code slice)

### 5.1 Read for context
- `sim/core/simulation.gd`: `step` 63-97, `build_tower` 174-193, `sell_tower` 199-212,
  `can_buy_sanity`/`buy_sanity`/`auto_restore_sanity` 233-273, `_add_sanity` 404-425,
  `_apply_auras` 469-507, `_fire_towers` 510-569 (the cast-cost lines).
- LT-24's upgrade command and sell refund (after its merge; line numbers will move).
- `sim/core/sim_enemy.gd` 23-36 (modifiers); `sim/core/sim_state.gd`; `sim/core/sim_event.gd`.
- `scenes/sanity_fx.gd` 77-134; `scenes/board.gd` `_draw_enemies` 246-272;
  `ui/sanity_bar.gd` 41-81; LT-24's tower panel.

### 5.2 Change
| Path | Lines | Change |
|---|---|---|
| `sim/core/sim_state.gd` | after `sanity` | `var sanity_cap := 0.0` |
| `sim/core/sim_event.gd` | enum | append `SANITY_CAP_CHANGED` |
| `sim/core/simulation.gd` | 9-21 `CommandResult` | append `NO_SANITY_ROOM` |
| | 39-51 `_init` | `state.sanity_cap = config.sanity.max_sanity` |
| | 63-97 `step` | slot 2: `_apply_madness_buff()` after `_apply_auras()`; slot comments (no cast cost in slot 5) |
| | 174-193 `build_tower` | replace the `sanity_cost` branch with `_change_reserve(t, stats.sanity_reserve, "build")` after `TOWER_BUILT` and the gold change |
| | 199-212 `sell_tower` | `_change_reserve(t, −reserve, "sell")` after the refund |
| | LT-24 upgrade | `_change_reserve(t, new − old, "upgrade")`; drop its `upgrade_sanity_cost` use if any |
| | 233-273 | `can_buy_sanity`: `NO_SANITY_ROOM` when `min(restore, cap) <= 0`, checked after NOT_IN_MADNESS; `buy_sanity`/`auto_restore_sanity` restore to `min(restore_sanity, sanity_cap)` |
| | 404-425 `_add_sanity` | clamp to `state.sanity_cap`; doc comment |
| | 510-569 `_fire_towers` | remove the `sanity_per_cast` payment |
| | new | `_change_reserve(t, delta, reason)` (§1.2: cap event, then `_add_sanity(−delta, delta > 0 ? "reserve" : "release", t.id)`); `sanity_reserve_of(def_id, level)`; `_apply_madness_buff()` |
| `sim/defs/tower_def.gd` | 5, 14, 19-28 | drop `sanity_cost` from `FIELDS` and the var |
| | 79-114 `Level` | `LEVEL_FIELDS`: drop `upgrade_sanity_cost`, `sanity_per_cast`, `sanity_per_second`; add `sanity_reserve` (`opt_number`, default 0, `>= 0`); `> 0` on a non-occult kind → error "only occult towers reserve sanity" |
| `sim/defs/sanity_config.gd` | 88-130 `Madness` | `MADNESS_FIELDS` + `enemy_speed_multiplier`, `enemy_damage_taken_multiplier`; `opt_number(..., 1.0, 0.0, INF, true)` (default 1 = off, `> 0`) |
| `data/towers.json` | occult levels/branches | §2 values; remove the dropped keys |
| `data/sanity.json` | `madness` | `"enemy_speed_multiplier": 1.2, "enemy_damage_taken_multiplier": 0.8` |
| `scenes/board.gd` | 246-272 | madness tint + outline, same for every enemy |
| `ui/sanity_bar.gd` | 41-81 | reserved block, `n / cap` label |
| `ui/hud.gd` | 21-80 | madness hostility line; buyout button disabled on `NO_SANITY_ROOM` |
| `ui/tower_picker.gd`, LT-24 panel | build/upgrade preview | "Reserves N sanity" / "+N reserve" from `sanity_reserve_of` |
| `tools/bot_runs.gd` | 1-30, 60-142 | `mixed`, reserve guard and occult fallback (§4), new metrics; merge with LT-24's upgrading bots |
| `docs/GDD.md` | §5.3, §5.4, §6 | reserve instead of build/cast/second costs; madness hostility; new occult numbers |

### 5.3 Config validation
- `towers.json` `sanity_reserve`: optional number `>= 0`; `> 0` only on occult towers.
- `sanity_cost`, `upgrade_sanity_cost`, `sanity_per_cast`, `sanity_per_second`: unknown keys
  (rejected).
- `sanity.json` `madness.enemy_speed_multiplier`, `madness.enemy_damage_taken_multiplier`:
  optional, number, `> 0`, default 1.0.
- No cross-check of total reserve against `sanity.max` (a board can legally reserve it all).
- `config_reject_test`: one case per new rule and one per removed key; `config_valid_test`
  pins the new data (replaces `test_tower_sanity_cost_default_and_explicit`).

### 5.4 Must confirm (code slice)
1. LT-24's upgrade command and sell after merge: where the reserve delta goes; that
   `stats()` returns the branch at L3.
2. Tests built on the removed costs: `occult_tower_test.gd` 56-75 (Elder Sign build sanity
   event), 310-350, 392, 431 (casts); `madness_test.gd` ~260; `sanity_test.gd` (clamp to max).
   They become reserve tests or go; list each in the code slice report.
3. LT-27's renames (gold → money) before touching `build_tower`/`sell_tower` lines.
4. `config_reject_test` text fixtures still find their anchor strings in the edited JSON.
5. `scenes/game.gd:42` debug `--sanity` path goes through `_add_sanity`, so it now clamps
   to the cap (fine at run start: cap = max).

---

## 6. Behaviours the tests slice pins (one line each)

1. Building an occult tower with reserve r: cap −r and sanity −r; events in order
   `TOWER_BUILT`, gold change, `SANITY_CAP_CHANGED {−r, "build"}`, `SANITY_CHANGED {−r, "reserve"}`.
2. Mundane towers and reserve-0 levels emit no cap event and change no sanity.
3. Regen (between waves, mundane kill) stops at the cap; `SANITY_CHANGED` delta is the part applied.
4. Sell returns the full reserve: cap +r, sanity +r up to the cap, reason `"release"`.
5. Upgrade (build phase, LT-24) changes cap and sanity by the reserve delta of the two levels.
6. A build that takes sanity to 0 enters MADNESS (`SANITY_STATE_CHANGED`) and latches.
7. In MADNESS, build and sell move only the cap; sanity stays 0, state stays MADNESS.
8. Thresholds use absolute sanity: cap 60 → state never LUCID.
9. `buyout`/`auto_restore` restore to `min(restore_sanity, cap)`; cap 0 → `can_buy_sanity()`
   is `NO_SANITY_ROOM`, no gold paid; `auto_restore` changes nothing.
10. No sanity change on a Necronomicon cast (cost removed).
11. Config: `sanity_reserve > 0` on a mundane level rejected; each removed key rejected;
    madness multipliers ≤ 0 rejected; absent → 1.0 and no buff.
12. MADNESS: every live enemy has `speed_mult` ×1.2 and `damage_taken_mult` ×0.8 (config
    values) and moves/takes damage accordingly; outside MADNESS both are 1 without auras.
13. The buff reaches an enemy that was on the map before MADNESS and one spawned after.
14. A fake and a real enemy of the same def in MADNESS have identical modifiers.
15. With an Elder Sign: modifiers are the product (sign × madness).
16. The step after the command that enters MADNESS has the buff; the step after a buyout has none.
17. Same seed + command log (build, sell, upgrade) → identical events (determinism).
18. Render: in MADNESS the board tints every enemy the same (real and fake); the sanity bar
    draws the reserved block for cap < max.

**Candidate controls** (revert the code, the named test must fail):
C1 lower only the cap on build, not current sanity (1); C2 clamp `_add_sanity` to `max`
instead of the cap (3); C3 return 70 % of the reserve on sell (4); C4 add `"release"` to
`MADNESS_EXIT_REASONS` (7); C5 restore `restore_sanity` without the cap (9); C6 skip fakes
in `_apply_madness_buff` (14); C7 remove the occult-only `sanity_reserve` check (11).

---

## 7. Open questions for the owner

**Q1. Does building take the reserve from current sanity too, or only from the cap?**
*Today* an Elder Sign takes 8 sanity once; regen can win it back. *Change:* the tower lowers
the cap while it stands. *Example:* sanity 60 of 100, build a Reader (reserve 10). (a) cap 90,
sanity 50; (b) cap 90, sanity stays 60. *Options:* (a) **take it from both (recommended):**
every build costs something you feel at once, whatever your sanity is; matches "отнимают
фиксированную сумму". (b) cap only: a player already low on sanity builds occult towers for
free until regen hits the lowered cap; the cost shows up only for a calm player.

**Q2. Are the thresholds measured on the full bar or on the lowered cap?**
*Today* Lucid is 70+, Whispers 40-69, Fraying 1-39 of 100. *Change:* towers lower the cap.
*Example:* reserves total 40, cap 60, sanity 60. (a) absolute: Whispers, fakes every 15 s
for as long as those towers stand. (b) relative: 60/60 = 100 % → Lucid, no fakes.
*Options:* (a) **absolute (recommended):** heavy occult means living with hallucinations,
which is the price you described; one rule, nothing to rescale. (b) relative: the reserve
only shrinks the buffer, a big occult board looks calm until something drains.

**Q3. May a build take sanity to 0 (straight into madness)?**
*Today* yes: an Elder Sign at sanity 8 or less drops it to 0 and madness starts.
*Change:* the same with reserves. *Example:* sanity 7, build a Reader (10): sanity 0, MADNESS
(permanent by default). *Options:* (a) **allow it, with a warning on the build preview
("this tower will drive you mad") (recommended):** deliberate madness stays a strategy;
no new refusal rule. (b) refuse the build when reserve ≥ current sanity: no accidental
madness, but the madness strategy needs horror drain to finish the job.

**Q4. Selling an occult tower while in madness.**
*Today* madness under the default `permanent` rule never ends. *Change:* selling returns the
reserve. *Example:* in madness, cap 30; sell a Reader. (a) cap 40, sanity stays 0, still
mad. (b) cap 40, sanity 10, madness ends. *Options:* (a) **cap only, stay mad
(recommended):** `permanent` keeps meaning permanent; selling still widens the room a later
buyout or auto restore can fill. (b) sanity back too: selling becomes a free exit from
madness that bypasses the exit rule.

**Q5. Elder Sign's one-off build cost (8 sanity).**
*Today* building or upgrading an Elder Sign takes 8 sanity once. *Change:* it also reserves
5 (L1). *Example:* (a) a Sign costs 5 while it stands, returned on sell; (b) 8 lost for good
plus 5 reserved. *Options:* (a) **remove the one-off cost, the reserve is the only sanity
price (recommended):** one rule for every occult tower, as you described ("fixed amount").
(b) keep both: Signs cost more than Readers per unit of reserve, two numbers to explain.

**Q6. Buyout or auto restore when the cap is low.**
*Today* buyout (exit rule `buyout`, 150 gold) and auto restore set sanity to 30.
*Change:* sanity cannot exceed the cap. *Example:* cap 20 → restore to 20; cap 0 → nothing
to restore. *Options:* (a) **restore to min(30, cap); refuse the buyout at cap 0 so no gold is
paid for nothing (recommended):** honest and simple. (b) the exit rule temporarily ignores the
cap: restores 30 even with a full reserve, then regen cannot keep it there, a confusing bar.
Only matters if the exit rule is switched from the default `permanent`.

**Q7. The lighthouse beam's "half drain" for lit occult towers (LT-26).**
*Today (LT-26 decision)*: a lit occult tower has −30 % power and half the passive drain.
*Change:* there is no passive drain any more. The beam rotates, so a tower is lit for a
fraction of each turn (about 8-31 % by lighthouse level, LT-26 §2). *Example:* Reader reserve 10. (a) the beam does
nothing to sanity; lit Reader just −30 % power. (b) reserve 5 while lit, 10 while dark: the
cap jumps by 5 every few seconds, and every time it falls current sanity is clamped down, so
the beam would *cost* sanity. (c) a fixed discount at build time from how often the cell is
lit (e.g. lit 30 % of the time → reserve 10 × (1 − 0.5 × 0.3) = 8.5): stable, but a number the
player cannot predict. *Options:* (a) **no sanity effect; LT-26's measure slice may soften the
−30 % instead (recommended):** keeps the reserve readable. (b) moving cap: messy and
punishing. (c) build-time discount: keeps the trade, adds geometry to the build preview.

**Q8. What madness does to enemies, and how much.**
*Today* enemies are identical in every sanity state. *Change:* in madness every enemy is
faster and tougher. *Example (recommended numbers):* speed ×1.2 and damage taken ×0.8:
a cultist walks 1.2 cells/s instead of 1.0 and needs 75 damage instead of 60; a Deep One
pack crosses a Rifleman's range 17 % sooner. *Options:* (a) **speed ×1.2 and damage taken
×0.8, flat while in madness (recommended):** both act on enemies already on the map and stop
the moment madness ends; numbers tuned by S5. (b) the same, growing each wave spent in madness
(e.g. +10 % per wave): madness gets worse the longer it lasts, harder to tune and to read.
(c) also +1 leak damage: a strong "lose" lever, but one leak more or less then decides runs.

**Q9. Enemies already on the map when madness starts.**
*Today* madness does not touch enemies. *Change:* the buff applies to every live enemy from
the next tick. *Example:* sanity hits 0 in the middle of wave 4 with 12 hybrids on the path:
all 12 speed up at once. *Options:* (a) **all enemies at once (recommended):** "the world turns
hostile" is felt in that moment, and it ends the same way on buyout. (b) only enemies spawned
after: gentler, but half the wave looks unaffected and the change is hard to see.

**Q10. How visible madness hostility and the reserve are.**
*Today* madness shows a red screen grade, maximum flicker and a torn sanity bar; enemies are
hard to see in it (carried-over finding); the bar always spans 0-100. *Options:* (a) **red
tint and dark outline on every enemy, a HUD line "The world turns hostile: enemies +20 % speed,
−20 % damage taken", and a dark hatched "reserved" block at the right end of the sanity bar
with `63 / 80` in its label (recommended):** cause and effect are explicit, enemies become
easier to see. (b) tint and reserved block only, no text: more atmospheric, the player may
not know why they leak. (c) text only: clear, but the board does not feel different.

**Q11. Difficulty targets for the bots** (10 seeds, with tower upgrades from LT-24).
*Today* every sane strategy wins 10/10; mundane keeps 20/20 HP; occult 10.8 HP (and the occult
bot is really ~80 % riflemen); deliberate madness 0/10. *Change (recommended targets):* mundane
wins ≥ 8/10 with mean HP 10-18 and ≥ 6/10 runs losing HP; a true occult bot (≤ 3 riflemen)
wins ≥ 8/10, mean HP ≥ mundane − 2, cap ≤ 50 by wave 4, sanity below 40 in ≥ 7/10 runs,
madness in ≤ 2/10; a new mixed bot wins ≥ 9/10 with HP ≥ mundane; deliberate madness wins
≤ 2/10. *Consequence:* S5 tunes until all four hold or reports which cannot. *Options:*
(a) **these numbers (recommended)**; (b) stricter (mundane ≤ 7/10 wins): more tension, but
the first-time player loses more often; (c) looser (only "mundane loses some HP").

**Q12. May S5 weaken the mundane towers?**
*Today* Rifleman/Harpooner stats are untouched since 0.1; earlier nerfs (Rifleman 10 → 6)
had no effect because the mundane bot owns ~40 towers. *Change:* S5 raises enemy HP and late
wave counts after the occult buff. *Example:* if mundane still keeps 20/20 HP at enemy HP
×1.6 while occult starts losing, the only remaining lever is mundane stats. *Options:*
(a) **only occult stats and reserves, madness multipliers, enemy HP and wave 3-5 counts; if
the targets cannot be met, S5 stops and reports (recommended):** mundane balance stays a
separate owner call. (b) S5 may also lower Rifleman/Harpooner damage by up to 20 %: more
likely to meet the targets in one pass, changes the feel of the "safe" towers without your
review.
