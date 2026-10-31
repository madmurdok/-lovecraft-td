# Playtest 0.2: LT-23 difficulty tuning (S10)

Targets: `docs/design/LT-23-occult-drain-difficulty.md` §4 (stated on the sanity cap). Q12 allowed
Rifleman/Harpooner damage down to -20 %; it was **not used**. Tool: `tools/bot_runs.gd`, 10 seeds
(1000-1009) x 4 strategies (mundane, occult, mixed, madness), upgrades on, LT-27 economy.
Each table cell below is "wins, mean lighthouse HP left (of 20)". Variants were run with
`--data=<dir>` copies of `data/`; only the final one was applied to `data/`.

## Baseline (data/ as shipped at 4917d98)

| Bot | Wins | Mean HP | Runs losing >= 1 HP | Cap after wave 4 | Runs with cap/sanity < 40 | Runs reaching MADNESS | Fakes/run |
|---|---|---|---|---|---|---|---|
| mundane | 10/10 | 20.0 | 0 | 100 | 0 | 0 | 0 |
| occult | 10/10 | 19.0 | 10 | 50-59 | 2 | 0 | 11.3 |
| mixed | 10/10 | 20.0 | 0 | 72-80 | 0 | 0 | 3.0 |
| madness | 10/10 | 19.6 | 1 | 29-49 | 10 | 1 | 16.7 |

Too easy: mundane never loses HP, deliberate madness wins 10/10 (it rarely reaches cap 0: its
build runs out of gold first).

## Tuning steps

Findings that shaped the steps: (a) uniform enemy HP scaling hits the occult bot long before the
mundane one (x1.4: occult 1/10) because its rifleman + Elder Sign opening cannot clear wave 1-2
cultists, so cultist HP stays untouched; (b) the madness bot wins by tower power in waves 1-4 and is
in MADNESS only in wave 5, so only wave 5 plus the two madness multipliers can make it lose;
(c) Reader branch damage (a 170, b 90) changed nothing for either bot (branch towers arrive after
the losses) and was dropped; (d) Reader L1/L2 damage is what lets the occult bot hold wave 3-4.

| Step | Changed values (cumulative) | mundane | occult | mixed | madness |
|---|---|---|---|---|---|
| baseline | - | 10/10, 20.0 | 10/10, 19.0 | 10/10, 20.0 | 10/10, 19.6 |
| A | all enemy hp x2 | 2/10, 1.4 | 1/10, 1.0 | 2/10, 1.6 | 10/10, 8.6 |
| B | all enemy hp x1.4 | 10/10, 18.3 | 1/10, 1.1 | 10/10, 20.0 | 10/10, 15.8 |
| C | hybrid/deep_one/night_gaunt/shoggoth hp x1.5 (cultist 60 kept); Reader b reserve 45, Elder b reserve 30 | 10/10, 17.0 | 10/10, 8.9 | 10/10, 20.0 | 10/10, 16.0 |
| D | C + Reader a reserve 22, Elder a reserve 14 (+ discarded Reader a/b damage edits) | 10/10, 17.0 | 10/10, 8.9 | 10/10, 20.0 | 10/10, 13.8 |
| E | D without the damage edits; Reader L1 damage 100, L2 130; shoggoth hp 3600 | 10/10, 16.5 | 10/10, 19.0 | 10/10, 20.0 | 10/10, 12.8 |
| F | E + Reader L2 reserve 18; wave 5 counts: cultist 46, hybrid 18, deep_one 6, night_gaunt 10 | 10/10, 16.5 | 10/10, 19.0 | 10/10, 20.0 | 10/10, 11.0 |
| G | F with wave 5 counts x2 and madness 1.5 / 0.5 | 10/10, 16.5 | 10/10, 19.0 | 10/10, 20.0 | 5/10, 1.8 |
| H | F + madness speed 1.6, damage-taken 0.4 | 10/10, 16.5 | 10/10, 19.0 | 10/10, 20.0 | 7/10, 2.5 |
| **final** | F + madness speed 2.0, damage-taken 0.3 | 10/10, 16.5 | 10/10, 19.0 | 10/10, 20.0 | 0/10, 0.0 |

Madness multipliers 1.4/0.6 and 1.5/0.5 with the F counts (separate runs) left the madness bot at
9/10; only 2.0/0.3 reached 0/10.

## Final values (applied to data/)

| File | Value | Was | Now |
|---|---|---|---|
| enemies.json | hybrid hp | 140 | 210 |
| | deep_one hp | 90 | 135 |
| | night_gaunt hp | 110 | 165 |
| | shoggoth hp | 900 | 3600 |
| waves.json | wave 5 cultist / hybrid / deep_one / night_gaunt count | 29 / 11 / 4 / 6 | 46 / 18 / 6 / 10 |
| towers.json | Reader L1 / L2 damage | 70 / 95 | 100 / 130 |
| | Reader L2 / a / b sanity_reserve | 15 / 18 / 25 | 18 / 22 / 45 |
| | Elder Sign a / b sanity_reserve | 10 / 15 | 14 / 30 |
| sanity.json | madness enemy_speed_multiplier | 1.2 | 2.0 |
| | madness enemy_damage_taken_multiplier | 0.8 | 0.3 |

Rifleman/Harpooner untouched.

## Final table (10 seeds)

| Bot | Wins | Mean HP | Runs losing >= 1 HP | Cap after wave 4 | Runs with cap/sanity < 40 | Runs reaching MADNESS | Lowest cap | Fakes/run |
|---|---|---|---|---|---|---|---|---|
| mundane | 10/10 | 16.5 | 6 | 100 | 0 | 0 | 100 | 0 |
| occult | 10/10 | 19.0 | 10 | 36-56 (8 of 10 <= 50) | 10 | 0 | 32-36 | 20.5 |
| mixed | 10/10 | 20.0 | 0 | 64-76 | 0 | 0 | 64 | 9.9 |
| madness | 0/10 | 0.0 | 10 | 3-46 | 10 | 10 | 3-46 | 16.1 |

## Targets (§4)

- mundane: >= 8/10 wins, HP 10-18, >= 6/10 runs lose HP, Lucid: **met** (10/10, 16.5, 6/10).
- occult: >= 8/10 wins **met**; HP >= mundane - 2 **met** (19.0); cap <= 50 by wave 4 **8/10 runs** (borderline);
  cap/sanity < 40 in >= 7/10 **met** (10/10); MADNESS <= 2/10 **met** (0); >= 5 fakes **met** (20.5).
- mixed: >= 9/10 **met**; HP >= mundane mean **met**; lowest cap in [20, 70) in >= 7/10 **met** (10/10, 64).
- madness: <= 2/10 wins **met** (0/10). "MADNESS (cap 0) by wave 3" **not met**: the bot is in cap 0
  only from wave 4-5 (cap after wave 4 is 38-46 in most runs; it runs out of gold, and the bot is
  placement/gold-bound, not data-bound). It loses in wave 5 to the buffed enemies.
- Open: occult and mixed lose almost nothing, mixed none. Occult HP above mundane's is a bot-order effect
  (Reader opening), not tunable in data/.

## Machine state for timings

Baseline run: `uptime` load averages 62.92 32.31 38.44; `/usr/bin/time -p`: real 242.35, user 170.98, sys 2.01
(40 runs, one process).
Final run: load averages 80.60 168.46 113.84; real 182.28, user 138.93, sys 1.18.
`user` is 76-77 % of `real` under a heavily loaded machine (a parallel agent was running):
the process was computing, with some waiting for CPU. Outcomes are deterministic per seed; timings are not comparable.

## Tests

Tests that pinned tuned numbers now read them from the raw JSON files (and assert buff direction):
`tests/config_valid_test.gd` (enemy hp, Elder/Reader reserves, madness multipliers),
`tests/madness_buff_test.gd` (madness multipliers). 21 test files that read enemies, towers, waves or sanity
were run; all pass after the edit. The full suite is left to verify.

## S13: madness multiplier scan (LT-23)

Owner decision: "Найти промежуточное значение (Recommended)". Start point 1.6 / 0.4 gave 7/10 madness wins (step H).
Scan of madness enemy_speed_multiplier / enemy_damage_taken_multiplier, same 10 seeds (1000-1009), madness bot read from
full 4-bot runs on `--data=<copy of data/>` variants (other bots do not depend on these values and were identical).

| Pair (speed / damage taken) | Madness bot wins | Mean HP left | Wave of MADNESS |
|---|---|---|---|
| 1.6 / 0.4 (S10 step H) | 7/10 | 2.5 | 5 |
| 1.7 / 0.37 | 0/10 | 0.0 | 5 (10/10 runs) |
| 1.8 / 0.35 | 1/10 | 0.3 | 5 (10/10 runs) |
| 1.9 / 0.32 | 0/10 | 0.0 | 5 (10/10 runs) |
| 2.0 / 0.3 | 0/10 | 0.0 | 5 (10/10 runs) |

MADNESS starts at tick 6841-8537 in every run, i.e. during wave 5 (cap after wave 4 is 3-46). Win counts are
not monotonic (1.8/0.35 lets one seed win), so the mildest pair with <= 2/10 is **1.7 / 0.37** (0/10).

**Chosen: speed 1.7, damage taken 0.37** (was 2.0 / 0.3 in S10's final; applied to `data/sanity.json`).

### Final table (10 seeds, 1.7 / 0.37, data/ as committed)

| Bot | Wins | Mean HP | Runs losing >= 1 HP | Cap after wave 4 | Runs with cap/sanity < 40 | Runs reaching MADNESS | Lowest cap | Fakes/run |
|---|---|---|---|---|---|---|---|---|
| mundane | 10/10 | 16.5 | 6 | 100 | 0 | 0 | 100 | 0 |
| occult | 10/10 | 19.0 | 10 | 36-56 (8 of 10 <= 50) | 10 | 0 | 32-36 | 20.5 |
| mixed | 10/10 | 20.0 | 0 | 64-76 | 0 | 0 | 64 | 9.9 |
| madness | 0/10 | 0.0 | 10 | 3-46 | 10 | 10 | 3-46 | 18.1 |

The three non-madness rows are byte-identical to the S10 final table, as expected.

### Dropped target

The §4 target "madness bot reaches cap 0 by wave 3" is **dropped**. It is economically unreachable at current
prices: cap 0 needs about 1090 gold of occult reserve, and the bot has about 500 before wave 3. The owner chose to
tune the multipliers instead; the madness bot is now in MADNESS from wave 5 and loses there.

### Machine state

Scan (4 variants in parallel, one process each): `uptime` load averages 254.84 166.28 149.96;
`/usr/bin/time -p` per process: real 397-402, user 216-220, sys 1.84-1.87 (user about 54 % of real: CPU contention).
Final run: load averages 97.23 124.63 137.20; real 168.43, user 159.17, sys 1.57 (user 94 % of real: computing).
Outcomes are deterministic per seed; timings are not comparable.

### Tests

`tests/config_valid_test.gd` (16 cases) and `tests/madness_buff_test.gd` (11 cases): 0 failures, unchanged.

## S15: final table after the Reader damage fix (LT-23)

S14 verify found Pure Rite (120) and Corrupted Rite (142.5) below or near L2 (130) after S10 scaled L1/L2. S15 restores
the original ratios to L2 (x130/95): **Pure Rite 164** (fire_interval 4, madness-proof), **Corrupted Rite 195** (x1.5 of L2).
No other value changed. Same command and seeds as S13: `tools/bot_runs.gd --seeds=10` (1000-1009), no re-tuning.

| Bot | Wins | Mean HP | Runs losing >= 1 HP | Cap after wave 4 | Runs with cap/sanity < 40 | Runs reaching MADNESS | Lowest cap | Fakes/run |
|---|---|---|---|---|---|---|---|---|
| mundane | 10/10 | 16.5 | 6 | 100 | 0 | 0 | 100 | 0 |
| occult | 10/10 | 19.0 | 10 | 36-56 (8 of 10 <= 50) | 10 | 0 | 32-36 | 20.5 |
| mixed | 10/10 | 20.0 | 0 | 64-76 | 0 | 0 | 64 | 9.9 |
| madness | 5/10 | 1.7 | 10 | 3-46 | 10 | 10 | 0-46 | 19.9 |

The three non-madness rows are identical to S13. **The madness bot now wins 5/10 (was 0/10), above the <= 2/10 target**;
it reaches MADNESS in 10/10 runs at the same ticks (6841-8537). Not re-tuned: an owner decision.
Machine: `uptime` load 43.65 19.07 35.62; `/usr/bin/time -p` real 288.96, user 199.64, sys 1.88.

## S17: soften Reader L3 (LT-23)

Owner decision: "Смягчить третий уровень Чтеца". S15 left the madness bot at 5/10 wins (target <= 2/10). Only the Reader L3
`damage` changes (Pure Rite a, fire_interval 4; Corrupted Rite b, fire_interval 3); madness multipliers stay 1.7 / 0.37.
Ordering pins: Pure Rite >= 130 per shot (slower branch), Corrupted Rite DPS >= L2 (130/3). Scan: same command and seeds as S13,
3 variants in parallel (`--data=<copy>`), madness bot read from the full 4-bot output.

| Pair (a / b) | Madness bot wins | Mean HP left |
|---|---|---|
| 164 / 195 (S15) | 5/10 | 1.7 |
| 140 / 165 | 4/10 | 1.5 |
| 135 / 150 | 1/10 | 0.4 |
| 132 / 140 | 0/10 | 0.0 |

**Chosen: Pure Rite 135, Corrupted Rite 150** (strongest pair with <= 2/10). Corrupted Rite is no longer x1.5 of L2, by owner decision.
Applied to `data/towers.json`; nothing else changed.

### Final table (10 seeds, data/ as committed)

| Bot | Wins | Mean HP | Runs losing >= 1 HP | Cap after wave 4 | Runs reaching MADNESS | Lowest final cap | Fakes/run |
|---|---|---|---|---|---|---|---|
| mundane | 10/10 | 16.5 | 6 | 100 | 0 | 100 | 0 |
| occult | 10/10 | 19.0 | 10 | 36-56 | 0 | 32 | 20.5 |
| mixed | 10/10 | 20.0 | 0 | 64-76 | 0 | 64 | 9.9 |
| madness | 1/10 | 0.4 | 10 | 3-46 | 10 | 0 | 18.5 |

The three non-madness rows are identical to S15. The "Lowest final cap" column is the minimum `final_cap` over runs.

### Machine state

Scan: `uptime` load 18.48 8.89 11.81; `/usr/bin/time -p` per process real 270.1-270.5, user 225.1-225.6, sys 1.7 (3 in parallel).
Final run: load 131.90 117.24 63.38; real 208.80, user 196.32, sys 1.59 (user 94 % of real: computing).

### Tests

`config_valid_test` (20), `occult_tower_test` (26), `upgrade_test` (29), `bot_upgrade_test` (21): 0 failures.

## Owner playtest 0.2.1 (LT-39, 2026-10-31)

Build: `release-0.2.1` at 6774f64, run with `-- --frame-stats` (LT-38 overlay). Machine load
~230 during the session (`uptime` 20:27). Owner verdicts, verbatim:

- **Tower descriptions (LT-37):** "Можно еще короче, возможно сделать унифицированную таблицу так
  чтобы у всех башен было одинакого: дамаг/тип дамага/санити при убийстве/санити требуемое и тп"
- **Frame rate at low sanity (LT-38):** "Такое впечатление что кадр таки дольше, можешь выводить
  показатель фпс где-нибудь в углу?" This disagrees with the LT-38 S1 diagnosis (sanity 0 vs 100
  ~1-2 ms/frame on a quiet machine); no overlay numbers were given yet.
- **Tension after 0.2.0 tuning (LT-26 confirmation):** "Всё ещё довольно легко, но напряжение
  появляется"

Follow-ups: a unified tower stats table, an always-visible FPS readout plus a re-check of frame
time vs sanity with the owner's numbers, and another difficulty pass (tasks filed from LT-39).
