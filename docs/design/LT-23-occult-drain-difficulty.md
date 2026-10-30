# LT-23 — Occult upkeep, madness hostility and difficulty (design note)

Status: draft · 2026-10-31 · branch `feat/LT-23-occult-drain-difficulty`

## 0. What exists today and what this task adds

**Today** (`release-0.2.0`): sanity moves only through `Simulation._add_sanity`
(`sim/core/simulation.gd:404-425`): build cost (Elder Sign −8), Necronomicon casts (−2 per
cast, slot 5), horror drain (shoggoth 0.5/s, slot 6, one summed `SANITY_CHANGED "horror"`
per tick), regen (+12 between waves, +0.5 per mundane kill). MADNESS is latched (LT-13):
while in it, `_add_sanity` applies nothing except the exit reasons `buyout` /
`auto_restore`. `TowerDef.Level.sanity_per_second` is parsed (`sim/defs/tower_def.gd`, `>= 0`)
and set only on Corrupted Seal (0.2), but no sim code reads it. Madness changes only occult
towers (×2 damage, astray shots 40/35/25); enemies are the same in every sanity state.

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
1. **Upkeep**: every occult tower on the board drains `sanity_per_second` while a wave runs.
2. **Stronger occult towers** (data only), so occult becomes the better buy per gold and
   upkeep is its price. Then enemy difficulty can rise until mundane leaks.
3. **Madness hostility**: in MADNESS every enemy moves faster and takes less damage.
4. Bot harness: a `mixed` strategy, an upkeep-aware guard, sanity-pressure metrics.

```
slot 2 _apply_auras ── _apply_madness_buff        (speed_mult, damage_taken_mult x madness.*)
slot 6 _horror_drain ── _upkeep_drain              (one SANITY_CHANGED "upkeep" per tick)
```

Cross-task: LT-24 (parallel) adds the upgrade command; its sim code lands first. Upkeep
reads `t.stats()`, so an upgraded tower drains its new level's value with no extra code,
provided LT-24 keeps `stats()` as "the level/branch the tower is at" (must confirm, §6).
Owner decision already made: no friendly fire in madness (unchanged here).

---

## 1. Passive drain (upkeep)

### 1.1 Model

| Question | Decision | Why |
|---|---|---|
| Unit | config `sanity_per_second` per level; applied per tick as `sps * SimTime.DT` | same as horror drain; `DT`-scaled so the rate does not depend on the tick rate |
| Summation | one sum over `state.towers` (id order) per tick; one `_add_sanity(-sum, "upkeep", 0)` | one event per tick, not one per tower (30 events/s per tower would flood the buffer); id order keeps float sums deterministic |
| Which towers | every tower whose current level (`t.stats()`) has `sanity_per_second > 0` | only occult levels may set it (validation, §5.3) |
| "Active" | while on the board, whether or not an enemy is in range (Q3) | owner's wording "each one on the board drains constantly"; a readable, strategic cost (you pay for owning, not for firing; the per-cast cost already covers firing) |
| Phase | WAVE and NONE (no WaveDirector: test harness); not BUILD, not DONE (Q1) | a human reading tower info in a 25 s build phase is not punished; bots call waves at once, so bot and human runs compare |
| Level scaling | per level in `towers.json`: L1 < L2 < branches; Corrupted branches carry their GDD extra on top | data, not code; L3 Corrupted Seal's existing 0.2 becomes "L2 value + 0.2" |
| Start / stop | a tower built between steps drains from the next step; a sold tower stops at once (it is gone from `state.towers`) | no timers, no state on the tower |
| Slot | slot 6, after `_horror_drain` | sanity work stays in one slot; a cast in slot 5 of the same tick is paid first |
| Event | `SANITY_CHANGED {delta, sanity, reason: "upkeep"}`, `id = 0`, plus `SANITY_STATE_CHANGED` when a threshold is crossed (both from `_add_sanity`) | existing event and path; nothing new for scenes to learn |
| RNG | none | no stream shifts; seeded runs without occult towers are bit-identical to today |

### 1.2 Madness latch and exit rules

Upkeep goes through `_add_sanity`, so the latch needs no special case:

| Exit rule | What upkeep does |
|---|---|
| any, sanity reaches 0 by upkeep | `SANITY_STATE_CHANGED → MADNESS` in that tick; from then on upkeep applies nothing and emits nothing |
| `permanent` (default) | no upkeep for the rest of the run (latched at 0) |
| `buyout` | `buy_sanity()` sets 30; upkeep resumes on the next WAVE tick, no grace (Q4). With 1.0/s of upkeep the player is back in madness after 30 s unless towers are sold |
| `auto_restore` | sanity is set to 30 at wave clear (slot 8); the build phase has no upkeep; it resumes when the next wave starts |

### 1.3 Read API for the HUD

`Simulation.upkeep_per_second() -> float`: the sum the next WAVE tick would drain per
second (`sum of t.stats().sanity_per_second`), regardless of phase and latch. Pure read.

---

## 2. Occult power (data, all values tunable by S5)

Goal: occult beats mundane per gold so upkeep is a price worth paying. Numbers are the
starting point for S5, not a balance claim.

| Tower / level | Field | Today | Proposed |
|---|---|---|---|
| Necronomicon L1 | damage / fire_interval | 40 / 4 s | **70 / 3 s** (23.3 DPS per target, ×2.3) |
| | sanity_per_cast | 2 | **1** (Q2) |
| | sanity_per_second | 0 | **0.15** |
| Necronomicon L2 | damage / fire_interval / cast / sps | 55 / 4 / 2 / 0 | **95 / 3 / 1 / 0.2** |
| Pure Rite (a) | damage / interval / cast / sps | 70 / 5 / 2 / 0 | **120 / 4 / 1 / 0.2** (not madness_affected, unchanged) |
| Corrupted Rite (b) | damage / interval / cast / sps | 82.5 / 4 / 4 / 0 | **142.5 / 3 / 2 / 0.4** (×1.5 of L2, GDD) |
| Elder Sign L1 | range / slow / damage_taken_multiplier / sps | 2 / 0.3 / 1.25 / 0 | **2.5 / 0.35 / 1.5 / 0.1** |
| Elder Sign L2 | same | 2.5 / 0.3 / 1.25 / 0 | **3 / 0.35 / 1.5 / 0.15** |
| Pure Ward (a) | same | 3.5 / 0.3 / 1.25 / 0 | **4 / 0.35 / 1.5 / 0.15** |
| Corrupted Seal (b) | same | 2.5 / 0.3 / 1.25 / 0.2 | **3 / 0.35 / 1.5 / 0.35** (+0.2 over L2, GDD), strip_armor 1 |

Unchanged: gold costs (pinned, `config_valid_test`), Elder Sign build/upgrade sanity cost 8,
AoE radius 1.5, Rifleman/Harpooner stats.

Per gold after the change: Reader 0.16 DPS/gold single target, ~0.4 with a blast on 2-3
enemies; Elder Sign ×1.5 on every hit in a 2.5-cell aura, so it multiplies the riflemen
around it (that is the mixed build's reason to exist).

Rough upkeep for an occult build in wave 4 (1 rifleman, 3 signs, 3 readers): 3×0.1 + 3×0.15
= 0.75/s upkeep + casts 3 × (1 per 3 s) = 1.0/s → 1.75/s, ~95 per 55 s wave (if every Reader
always has a target), against +12 between-waves regen. That
is the intended squeeze: the bot (and the player) must stop adding occult towers or mix in
mundane ones (each mundane kill gives +0.5).

---

## 3. Madness hostility (former LT-20)

| Question | Decision | Why |
|---|---|---|
| Stats | speed ×`enemy_speed_multiplier` (1.2) and damage taken ×`enemy_damage_taken_multiplier` (0.8 = effective HP ×1.25) (Q5) | both are existing per-tick modifiers (`SimEnemy.speed_mult`, `damage_taken_mult`), so no HP bookkeeping; faster also means less time in range of every tower |
| Not chosen | armor bonus (flat: −2 is −20 % of a Rifleman hit, −3 % of a Reader blast, punishes mundane, not the madness builder); max HP on spawn (does not reach enemies already on the map, must be undone on exit); leak damage (decides runs in one step) | |
| Size | flat while in MADNESS, no ramp (Q5) | readable; S5 can tune the two numbers |
| Who | every live enemy, already on the map and new spawns, from the first tick slot 2 sees `sanity_state == MADNESS` (Q6) | a modifier rebuilt each tick has no "already on the map" special case |
| Fakes | buffed exactly like real enemies | LT-12 owner decision: behaviour must never tell a fake (auras and blasts already treat them alike) |
| Stacking | multiplies after Elder Sign: speed 0.65 × 1.2 = 0.78, damage taken 1.5 × 0.8 = 1.2 | one rule (product); signs stay useful in madness |
| Horror drain | unaffected; in MADNESS the latch already makes it a no-op | no double punishment through sanity |
| Removal | the tick after leaving MADNESS (`reset_modifiers` in slot 1, `_apply_madness_buff` checks the state) | buyout lands between ticks, so the next step has no buff; auto_restore lands in slot 8 before BUILD |
| Entry tick | the tick that reaches 0 (slot 5 cast or slot 6 upkeep/horror) has already run slot 2, so the buff starts on the next tick | fixed order, pinned by a test |
| Config | `sanity.json` `madness.enemy_speed_multiplier`, `madness.enemy_damage_taken_multiplier` | the madness block already holds all madness rules |

**Sanity feedback layer (presentation only, Q7):**
- Board: in MADNESS every enemy (real and fake alike) is drawn with a hostile tint
  (`COLOR_ENEMY` lerped to a madness red by `sanity_fx.madness`, the existing smoothed 0..1
  grade) and a dark outline, so it reads as "the world turned on me" and also fixes the
  carried-over "enemies barely visible in Madness".
- HUD: in MADNESS a line under the sanity bar: "The world turns hostile: enemies +20 % speed,
  −20 % damage taken" (numbers from config).
- Sanity bar: while `upkeep_per_second() > 0` the label shows the rate,
  `Sanity 63  Whispers  −0.45/s` (in BUILD: `paused`), so the constant drain is visible.

---

## 4. Difficulty targets and knobs (S5)

Bots (10 seeds, 1000-1009, `tools/bot_runs.gd`, with LT-24 upgrades). Strategies:

| Bot | Build order | Guard |
|---|---|---|
| mundane | rifleman, rifleman, harpooner (unchanged) | none |
| occult | 1 rifleman, then elder_sign / reader alternating | if `sanity − sanity_cost − upkeep_after × 60 s < 25` the bot **saves gold** (builds nothing, or upgrades an occult tower via LT-24) instead of building a rifleman; at most 3 riflemen per run, so it stays an occult build (today's fallback makes it ~80 % riflemen) |
| mixed (new) | rifleman, rifleman, elder_sign, rifleman, harpooner, reader repeated | same guard with floor 40 (stays above Fraying) |
| madness | reader / elder_sign alternating, no guard (unchanged) | none |

Targets (Q8):

| Bot | Wins | Mean HP left (of 20) | Sanity pressure |
|---|---|---|---|
| mundane | ≥ 8/10 | 10-18, and ≥ 6/10 runs lose ≥ 1 HP | stays Lucid (expected) |
| occult | ≥ 8/10 | ≥ mundane's mean − 2 | min sanity < 40 (Fraying) in ≥ 7/10 runs; MADNESS reached in ≤ 3/10; ≤ 10 % of time in MADNESS; ≥ 5 fakes per run |
| mixed | ≥ 9/10 | ≥ mundane's mean | min sanity in [20, 70) in ≥ 7/10 runs |
| madness | ≤ 2/10 | — | reaches MADNESS by wave 3 |

New per-run metrics (harness): `min_sanity`, `madness_tick` (first tick in MADNESS or −1),
`upkeep_drained` and `cast_drained` (sums of `SANITY_CHANGED` by reason), HP lost per wave.

**Knobs S5 may turn:** occult level/branch stats in `towers.json` (damage, fire_interval,
range, slow, damage_taken_multiplier, aoe_radius, sanity_per_cast, sanity_per_second);
the two madness enemy multipliers; enemy `hp` (one multiplier per type) and wave counts of
waves 3-5. **Not without the owner:** economy (pinned), tower gold costs, Rifleman/Harpooner
stats (Q9), thresholds, `damage_multiplier`, `shot_split`, `exit_rule`, Elder Sign sanity cost.
Each pinned value S5 changes updates `config_valid_test` in the same commit.

---

## 5. Edit map (code slice)

### 5.1 Read for context
- `sim/core/simulation.gd`: `step` 63-97, `_add_sanity` 404-425, `_horror_drain` 427-449
  (the pattern to copy), `_apply_auras` 469-507, `_fire_towers` 510-569.
- `sim/core/sim_enemy.gd` 23-36 (modifiers, `reset_modifiers`); `sim/core/sim_state.gd` (Phase).
- `sim/core/wave_director.gd` `_clear_wave` 127-140 (auto_restore order).
- `scenes/sanity_fx.gd` `tick`/`_apply` 77-134; `scenes/board.gd` `_draw_enemies` 246-272.
- LT-24's diff of `sim_tower.gd` / `simulation.gd` (upgrade command, `stats()`).

### 5.2 Change
| Path | Lines | Change |
|---|---|---|
| `sim/core/simulation.gd` | 63-97 `step` | slot 2: `_apply_madness_buff()` after `_apply_auras()`; slot 6: `_upkeep_drain()` after `_horror_drain()`; update the slot comments |
| | new after 449 | `_upkeep_drain()`: return in BUILD/DONE; sum `t.stats().sanity_per_second * SimTime.DT` in id order; `_add_sanity(-sum, "upkeep", 0)` if sum > 0 |
| | new | `upkeep_per_second() -> float` (§1.3) |
| | new after 507 | `_apply_madness_buff()`: if `sanity_state == MADNESS`, every live enemy `speed_mult *=`, `damage_taken_mult *=` the two config values |
| `sim/defs/sanity_config.gd` | 88-130 `Madness` | `MADNESS_FIELDS` + `enemy_speed_multiplier`, `enemy_damage_taken_multiplier`; vars; `opt_number(..., 1.0, 0.0, INF, true)` (optional, default 1 = off, must be > 0) |
| `sim/defs/tower_def.gd` | 79-114 `Level.parse` | `sanity_per_second > 0` on a non-occult kind: error "only occult towers drain sanity per second" (same shape as the `madness_affected` check) |
| `data/towers.json` | occult levels/branches | §2 values |
| `data/sanity.json` | `madness` | `"enemy_speed_multiplier": 1.2, "enemy_damage_taken_multiplier": 0.8` |
| `scenes/board.gd` | 246-272 `_draw_enemies` | madness tint + outline from `game.sanity_fx.madness`, same for every enemy |
| `ui/sanity_bar.gd` | 57-81 `_draw` | upkeep rate in the label (§3) |
| `ui/hud.gd` | 21-80 | madness hostility line, visible in MADNESS |
| `tools/bot_runs.gd` | 1-30, 60-142 | `mixed` strategy, upkeep-aware guard (§4), new metrics; header comment |
| `docs/GDD.md` | §5.3 drains, §5.4, §6 table | upkeep per occult tower, madness hostility, new occult numbers |

### 5.3 Config validation
- `towers.json` `sanity_per_second`: `>= 0` (exists); `> 0` only on occult towers (new).
- `sanity.json` `madness.enemy_speed_multiplier`, `madness.enemy_damage_taken_multiplier`:
  optional, number, `> 0`, default 1.0. Unknown keys in `madness` stay rejected.
- `config_reject_test` gets one case per new rule; `config_valid_test` pins the new data.

### 5.4 Must confirm (code slice)
1. LT-24's `SimTower.stats()` after its merge returns the branch at L3; upkeep and the
   madness buff need nothing else from it. Whether LT-24's bot upgrades live in
   `bot_runs.gd` (merge the `mixed` strategy into its shape).
2. Existing tests that assert exact sanity with real-data occult towers present
   (`occult_tower_test.gd` 310-350, 392, 431; `madness_test.gd` ~260; `sanity_test.gd`) run
   in phase NONE, so they now see upkeep: give them a config with `sanity_per_second = 0`
   (one helper in `tower_test_base.gd`) rather than folding upkeep into their expectations.
3. `occult_tower_test` asserts L1 Elder Sign numbers through the config (not literals);
   check none hard-codes 1.25 / 0.3 / 40 / 4.
4. `config_reject_test` text fixtures still find their anchor strings in the edited JSON.

---

## 6. Behaviours the tests slice pins (one line each)

1. One occult tower in WAVE: sanity falls by `sps` per 30 ticks (±1e-4), one
   `SANITY_CHANGED {reason: "upkeep", id: 0}` per tick.
2. Two occult towers: one upkeep event per tick whose delta is the sum.
3. BUILD and DONE: no upkeep event, sanity unchanged with occult towers on the board.
4. Phase NONE (ScriptedSpawner): upkeep applies.
5. Only mundane towers, or none: no upkeep event.
6. Built between steps → drains from the next step; sold → no upkeep from the next step.
7. Upgraded tower (LT-24) drains its new level's `sanity_per_second`.
8. Upkeep reaching 0 emits `SANITY_STATE_CHANGED → MADNESS`; later ticks emit no upkeep.
9. `buyout`: after `buy_sanity()` the next WAVE tick drains again; `auto_restore`: no upkeep
   in the following BUILD, upkeep again in the next wave.
10. MADNESS: every live enemy has `speed_mult` × 1.2 and `damage_taken_mult` × 0.8 (config
    values) and moves/takes damage accordingly; outside MADNESS both are 1 without auras.
11. The buff reaches an enemy that was on the map before MADNESS and one spawned after.
12. A fake and a real enemy of the same def in MADNESS have identical modifiers.
13. With an Elder Sign: modifiers are the product (sign × madness).
14. The tick that enters MADNESS has no buff; the next tick has it; the tick after a
    buyout has none.
15. Horror drain in MADNESS stays a no-op (unchanged latch).
16. Same seed + command log → identical events with upkeep and buff (determinism test).
17. Config: `sanity_per_second` > 0 on a mundane level rejected; madness multipliers ≤ 0 or
    non-number rejected; absent → 1.0 and no buff.
18. `upkeep_per_second()` equals the sum of current levels' `sanity_per_second`, also in BUILD.
19. Render: in MADNESS the board tints every enemy the same (real and fake), sanity bar
    label shows the upkeep rate.

**Candidate controls** (revert the code, the named test must fail):
C1 drop the BUILD/DONE check (3); C2 call `_add_sanity` per tower (2); C3 read
`def.levels[0]` instead of `stats()` (7); C4 subtract from `state.sanity` directly, bypassing
the latch (8); C5 skip fakes in `_apply_madness_buff` (12); C6 apply the buff only at spawn
(11); C7 remove the occult-only `sanity_per_second` check (17).

---

## 7. Open questions for the owner

**Q1. Does upkeep run in the build phase?**
*Today* nothing drains sanity between waves; the build phase lasts up to 25 s and gives
+12 sanity at its start. *Change:* each occult tower drains its rate. *Example:* 4 occult
towers at 0.15/s; a player who uses the full 25 s build phase loses 15 sanity in it if
upkeep runs, 0 if it does not. *Options:* (a) **only during waves (recommended):** thinking
time is free, between-waves regen keeps its meaning, bot runs (which call the wave at once)
compare with human runs; the cost is only "per second of combat". (b) always: rushing waves
becomes a sanity tactic on top of the gold bonus, and a slow player crashes into madness
while reading tooltips.

**Q2. Necronomicon cast cost next to upkeep.**
*Today* each cast costs 2 sanity, so a Reader with targets costs 0.5/s. *Change:* upkeep adds
a constant cost. *Example:* with upkeep 0.15/s and the faster 3 s cast, keeping cost 2 makes
a busy Reader cost 0.82/s; cost 1 makes 0.48/s; cost 0 makes 0.15/s. *Options:* (a) **lower to
1 (recommended):** firing still costs sanity (more enemies → more drain, which the player
feels), the total stays near today's level so upkeep does not double the squeeze. (b) keep 2:
occult crashes into madness by wave 3 with the new fire rate (playtest occult already hits 0
in wave 4 without upkeep). (c) 0, upkeep only: fully predictable cost, but a Reader standing
idle costs the same as one blasting a wave.

**Q3. Does a tower drain when nothing is in range?**
*Today* a Reader with no target does not cast and costs nothing. *Change:* upkeep is a
cost for owning the tower. *Example:* an Elder Sign at the last bend sees enemies 20 s of a
55 s wave; "always" drains 0.1 × 55 = 5.5, "only with an enemy in range" 2. *Options:* (a)
**always while on the board during a wave (recommended):** matches your idea ("each one on the
board drains constantly"), easy to read and plan, makes selling a real decision. (b) only
while an enemy is in range: cheaper for badly placed towers, hard to predict on the HUD.

**Q4. Upkeep right after leaving madness (buyout / auto_restore rules).**
*Today* the default exit rule is `permanent` (this question does not matter for it). Under
`buyout` (150 gold → sanity 30) or `auto_restore` (sanity 30 after the wave), sanity starts
falling again at once. *Example:* 6 occult towers draining 1.0/s total: a 150-gold buyout
buys 30 s before madness returns. *Options:* (a) **no grace (recommended):** the exit rule
stays a rescue that only works if the player also sells occult towers; no extra rule.
(b) a grace period (e.g. 10 s without upkeep): buyout feels fairer, one more config number
and timer.

**Q5. What madness does to enemies, and how much.**
*Today* enemies are identical in every sanity state. *Change:* in madness every enemy is
faster and tougher. *Example (recommended numbers):* speed ×1.2 and damage taken ×0.8:
a cultist walks 1.2 cells/s instead of 1.0 and needs 75 damage instead of 60; a Deep One
pack crosses a Rifleman's range 17 % sooner. *Options:* (a) **speed ×1.2 and damage taken
×0.8, flat while in madness (recommended):** both act on enemies already on the map and stop
the moment madness ends; numbers tuned by S5. (b) the same, growing each wave spent in madness
(e.g. +10 % per wave): madness gets worse the longer it lasts, harder to tune and to read.
(c) also +1 leak damage: a strong "lose" lever, but one leak more or less then decides runs.

**Q6. Enemies already on the map when madness starts.**
*Today* —. *Change:* the buff applies to every live enemy from the next tick. *Example:*
sanity hits 0 in the middle of wave 4 with 12 hybrids on the path: all 12 speed up at once.
*Options:* (a) **all enemies at once (recommended):** "the world turns hostile" is felt in
that moment, and it ends the same way on buyout. (b) only enemies spawned after: gentler,
but half the wave looks unaffected and the change is hard to see.

**Q7. How visible madness hostility is.**
*Today* madness shows a red screen grade, maximum flicker and a torn sanity bar; enemies are
hard to see in it (carried-over finding). *Change:* *Options:* (a) **red tint and dark
outline on every enemy plus a HUD line "The world turns hostile: enemies +20 % speed, −20 %
damage taken" (recommended):** cause and effect are explicit and enemies become easier to
see. (b) tint only, no text: more atmospheric, the player may not know why they leak.
(c) text only: clear, but the board does not feel different.

**Q8. Difficulty targets for the bots** (10 seeds, with tower upgrades from LT-24).
*Today* every sane strategy wins 10/10; mundane keeps 20/20 HP; occult 10.8 HP; deliberate
madness 0/10. *Change (recommended targets):* mundane wins ≥ 8/10 with mean HP 10-18 and
≥ 6/10 runs losing HP; occult wins ≥ 8/10, mean HP ≥ mundane − 2, sanity below 40 in ≥ 7/10
runs, madness in ≤ 3/10; a new mixed bot wins ≥ 9/10 with HP ≥ mundane; deliberate madness
wins ≤ 2/10. *Consequence:* S5 tunes until all four hold or reports which cannot. *Options:*
(a) **these numbers (recommended)**; (b) stricter (mundane ≤ 7/10 wins): more tension, but
the first-time player loses more often; (c) looser (only "mundane loses some HP").

**Q9. May S5 weaken the mundane towers?**
*Today* Rifleman/Harpooner stats are untouched since 0.1; earlier nerfs (Rifleman 10 → 6)
had no effect because the mundane bot owns ~30 towers. *Change:* S5 raises enemy HP and late
wave counts after the occult buff. *Example:* if mundane still keeps 20/20 HP at enemy HP
×1.6 while occult starts losing, the only remaining lever is mundane stats. *Options:*
(a) **only occult stats, madness multipliers, enemy HP and wave 3-5 counts; if the targets
cannot be met, S5 stops and reports (recommended):** mundane balance stays a separate owner
call. (b) S5 may also lower Rifleman/Harpooner damage by up to 20 %: more likely to meet the
targets in one pass, changes the feel of the "safe" towers without your review.
