# Playtest 0.4

## Staggered pack spawn (LT-63): balance check

Pack members now enter one by one, 0.5 s apart (`pack.spacing_s`), instead of stacked in one cell. Check: AoE towers may lose value against packs, and the LT-45 target must still hold: every bot strategy loses at least 10 of 20 runs with the flare on (`docs/playtest-0.3.md`, LT-45; balance lab LT-56).

Tool: `tools/balance/balance.py baseline flare_off --seeds=20 --jobs=6`, seeds 1000..1019, all 9 strategies. Before = release-0.4.0 at 328e842, after = feat/LT-63-staggered-pack-spawn at 957f40a, both measured in this slice with the same lab. The before arm reproduces the LT-45 final table of `docs/playtest-0.3.md` cell for cell (both flare rows), so the lab and the base are unchanged since LT-45; it was still re-run here for a same-session comparison.

Cells are losses out of 20 (before / after / delta). Target: >= 10.

| flare | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle | met before | met after |
|---|---|---|---|---|---|---|---|---|---|---|---|
| on (default) | 18/20/+2 | 15/18/+3 | 16/19/+3 | 13/14/+1 | 13/19/+6 | 20/20/+0 | 20/20/+0 | 20/20/+0 | 20/20/+0 | 9/9 | 9/9 |
| off | 10/18/+8 | 18/18/+0 | 9/16/+7 | 20/20/+0 | 5/17/+12 | 17/18/+1 | 20/20/+0 | 20/20/+0 | 20/20/+0 | 7/9 | 9/9 |

Wins/losses of the same runs:

| arm | flare | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle |
|---|---|---|---|---|---|---|---|---|---|---|
| before | on | 2/18 | 5/15 | 4/16 | 7/13 | 7/13 | 0/20 | 0/20 | 0/20 | 0/20 |
| before | off | 10/10 | 2/18 | 11/9 | 0/20 | 15/5 | 3/17 | 0/20 | 0/20 | 0/20 |
| after | on | 0/20 | 2/18 | 1/19 | 6/14 | 1/19 | 0/20 | 0/20 | 0/20 | 0/20 |
| after | off | 2/18 | 2/18 | 4/16 | 0/20 | 3/17 | 2/18 | 0/20 | 0/20 | 0/20 |

## Target check (flare on)

Met by all 9 strategies after the change (9/9; before 9/9). Smallest margin: madness, 14 losses of 20 (was 13). No strategy falls below 10. Flare off (not the target) improves from 7/9 to 9/9: mixed and demolition, which missed it before, now lose 16 and 17 of 20.

Reading: staggering makes the game harder for every strategy that had room to move (losses never decrease anywhere). The AoE-heavy bots (demolition +6, mixed +3, occult +3 with flare on) lose most; that is consistent with packs no longer stacking in one cell for blasts.

## Machine state

| arm | uptime at start (load avg) | uptime at end | /usr/bin/time -p |
|---|---|---|---|
| before (2 variants x 9 x 20) | 10.13 12.72 18.56 | 59.06 118.94 83.44 | real 557.59 user 2233.72 sys 21.91 |
| after (2 variants x 9 x 20) | 59.06 118.94 83.44 | 70.97 115.24 96.18 | real 371.43 user 1833.18 sys 10.64 |

6 Godot processes at a time; the machine was heavily loaded from outside during the after arm (load 59-119 on 8 cores), user/real 0.66 vs 0.91. Outcomes are deterministic per seed; timings are not comparable.

## Whole-map flare (LT-69): balance check

The flare now lights the whole map for 5/6/7 s by lighthouse level (was a 6/8/10 cell circle for 5 s); the bot fires it at 4 or more live enemies anywhere. Target unchanged: every strategy loses at least 10 of 20 runs with the flare on.

Tool: `tools/balance/balance.py baseline flare_off --seeds=20 --jobs=6`, seeds 1000..1019, all 9 strategies, after = feat/LT-69-whole-map-flare at 9b633ea. The before arm was not re-run: it is the LT-63 "after" row above (957f40a). That base predates LT-68 (starting gold 300, lighter wave 3, `release-0.4.0` 3e3f54e), so the delta mixes the LT-68 and LT-69 effects and is not a clean flare-only A/B.

Cells are losses out of 20 (before / after / delta). Target: >= 10.

| flare | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle | met before | met after |
|---|---|---|---|---|---|---|---|---|---|---|---|
| on (default) | 20/18/-2 | 18/10/-8 | 19/19/+0 | 14/8/-6 | 19/18/-1 | 20/19/-1 | 20/20/+0 | 20/20/+0 | 20/20/+0 | 9/9 | 8/9 |
| off | 18/1/-17 | 18/8/-10 | 16/14/-2 | 20/20/+0 | 17/5/-12 | 18/9/-9 | 20/19/-1 | 20/20/+0 | 20/20/+0 | 9/9 | 5/9 |

Wins/losses of the after runs:

| flare | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle |
|---|---|---|---|---|---|---|---|---|---|
| on | 2/18 | 10/10 | 1/19 | 12/8 | 2/18 | 1/19 | 0/20 | 0/20 | 0/20 |
| off | 19/1 | 12/8 | 6/14 | 0/20 | 15/5 | 11/9 | 1/19 | 0/20 | 0/20 |

## Target check (flare on, LT-69)

8 of 9 strategies have at least 10 losses with the flare on. Madness fails: 8 losses of 20 (12 wins), margin -2 (was 14). Smallest margin among the passing ones: occult, exactly 10 (margin 0). Flare off (not the target) falls from 9/9 to 5/9. The LT-68 second part (flare on, survive waves 1..3 in >= 15 of 20) is met by 8/9: gate fails it, losing in wave 3 in 17 runs (`e3`, 0 wins either way); gate is a flare-independent strategy (also 20/20 losses with the flare off), so this is an LT-68 early-game matter, not a flare one.

Reading: the whole-map flare is a clear buff for the strategies that rely on it: occult -8 and madness -6 losses with the flare on, and the flare off arm shows the strategies without the flare also got easier (mundane 18 to 1, demolition 17 to 5), which points at LT-68 (more gold, lighter wave 3) rather than at the flare. Madness is the one strategy below target and needs tuning (flare cooldown/oil cost or its enemy-count trigger), or a separate check on a clean LT-68 base to split the two effects.

## Machine state (LT-69)

| arm | uptime at start (load avg) | uptime at end | /usr/bin/time -p |
|---|---|---|---|
| after (2 variants x 9 x 20) | 115.44 69.47 86.68 | 33.63 66.85 88.28 | real 1580.06 user 3333.93 sys 53.30 |

6 Godot processes at a time; the machine was heavily loaded from outside (load 108-115 at start on 8 cores), user/real 0.33 (baseline) and 0.46 (flare_off), so the processes were mostly waiting. Outcomes are deterministic per seed; timings are not comparable.

## Light vs shadow (LT-70): balance check

The Searchlight now lights towers and enemies in its radius at night and slows harder (0.3 / 0.35 / 0.5 on Blinding; Blinding's x1.2 damage taken is gone). The Elder Sign shadows towers in its radius at night (occult x1.3, mundane interval x1.25, +10% miss), keeps x1.5 damage taken, slows 0.2. Light and shadow cancel; there is a new bot strategy `light`, and placement accounts for both. Target: every strategy loses at least 10 of 20 runs with the flare on.

Tool: `tools/balance/balance.py baseline flare_off lt70_old --seeds=20 --jobs=6`, seeds 1000..1019, all 10 strategies, feat/LT-70-light-shadow at f7d938b. `lt70_old` = pre-LT-70 numbers as far as patches allow (Searchlight slows 0.2/0.25/0.25/0.4, Elder Sign slow 0.35, no light/shadow flags; the old x1.2 damage taken cannot be patched in). "LT-69" column = the whole-map flare section's "after" row (9b633ea, 9 strategies, no `light`). These numbers are input for LT-71, the balance pass.

Cells are losses out of 20. Target: >= 10.

| arm | flare | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle | light | met |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| LT-69 (previous) | on | 18 | 10 | 19 | 8 | 18 | 19 | 20 | 20 | 20 | n/a | 8/9 |
| baseline | on | 18 | 13 | 20 | 10 | 18 | 19 | 20 | 20 | 20 | **1** | 9/10 |
| baseline | off | 1 | 12 | 20 | 16 | 5 | 9 | 19 | 20 | 20 | 0 | (not target) |
| lt70_old | on | 18 | 10 | 19 | 8 | 18 | 19 | 20 | 20 | 20 | 20 | 8/10 |

(LT-69 flare off, for reference: 1 / 8 / 14 / 20 / 5 / 9 / 19 / 20 / 20.)

## Target check (flare on, loss criterion)

Baseline: 9/10 strategies lose >= 10. Miss: `light`, 1 loss of 20 (19 wins; short by 9). Smallest margin among the met ones: madness, exactly 10 (margin 0); next occult 13. The lab's own `met` column reads 7/10 because it also applies LT-68's early-wave criterion (below).

## Early-wave losses (LT-68, survive waves 1-3 in >= 15 of 20, flare on)

| arm | early ok (all runs) | strategies under 15/20 |
|---|---|---|
| baseline | 170/200 (85%) | mixed 7/20, gate 3/20 |
| flare_off | 200/200 (100%) | none |
| lt70_old | 183/200 (92%) | gate 3/20 |

Baseline mixed loses mostly in wave 3 (13 of 20; waves 3.4.5: 13.5.2); gate loses 17 of 20 in wave 3. Both pass the loss-count target; they fail only the early criterion. For lt70_old, mixed falls from e7 to e20 (its losses move to wave 5), so the LT-70 change makes `mixed` die earlier.

## Reading

lt70_old reproduces LT-69 cell for cell on all 9 old strategies, so the lab and base are unchanged and the deltas below are LT-70 alone. LT-70 changes: occult +3, mixed +1 (but 20 losses in earlier waves), madness +2 (now exactly on target), the rest 0. The new `light` strategy is the whole target miss: with LT-70 it wins 19 of 20 flare on (20/20 flare off), whereas on the old numbers the same strategy loses 20/20, so the stronger Searchlight (light + harder slow) is what makes it win.

## Machine state

| run | uptime at start (load avg) | uptime at end | /usr/bin/time -p |
|---|---|---|---|
| 3 variants x 10 x 20 | 317.85 395.83 473.76 | 584.67 584.96 572.62 | real 2361.65 user 4590.29 sys 47.35 |

6 Godot processes at a time. The machine was extremely loaded from outside (load 300-580): user/real 0.33-0.37, i.e. runs were mostly waiting. Outcomes are deterministic per seed; timings are not comparable with LT-63/LT-69.

## LT-71 tuning variants

Measurement slice LT-71/S1. Tool: `tools/balance/balance.py lt71_sl_slow_weak lt71_sl_cost120 lt71_sl_range_small lt71_flare_cost12 lt68_w3soft lt71_combo --seeds=20 --jobs=4`, seeds 1000..1019, 10 strategies, flare on, branch `balance/LT-71-light-shadow-tuning` at 058de50. Baseline not re-run: it is the "baseline / on" row of the LT-70 section (same data). `data/` is unchanged; variants live in `tools/balance/variants/lt71_*.json`.

Variants: `sl_slow_weak` Searchlight slow 0.2/0.25 (a 0.25, b 0.4); `sl_cost120` Searchlight cost 80 -> 120; `sl_range_small` Searchlight range 2.5/3/4/3; `flare_cost12` flare 8 -> 12 oil; `lt68_w3soft` (existing); `combo` = slow 0.2/0.25/0.25/0.4 + cost 100 + range 3/3/4.5/3.5 + flare 12 oil + w3soft.

Cells are losses out of 20 (target >= 10); `eN` = runs that survived waves 1-3 (target >= 15). Strategies not in the table (mundane, demolition, battery, resonator, circle, occult for the three Searchlight-only variants) are cell-for-cell equal to baseline.

| variant | light | madness | occult | mixed | gate | mundane | loss-target met | lab `met` (loss + early) |
|---|---|---|---|---|---|---|---|---|
| baseline (LT-70) | 1 | 10 | 13 | 20 e7 | 20 e3 | 18 | 9/10 | 7/10 |
| sl_slow_weak | 14 | 10 | 13 | 20 e7 | 20 e3 | 18 | 10/10 | 8/10 |
| sl_cost120 | 7 | 10 | 13 | 20 e7 | 20 e3 | 18 | 9/10 | 7/10 |
| sl_range_small | 5 | 10 | 13 | 20 e7 | 20 e3 | 18 | 9/10 | 7/10 |
| flare_cost12 | 17 | 11 | 11 | 20 e13 | 20 e14 | 19 e16 | 10/10 | 8/10 |
| lt68_w3soft | 1 | 10 | 13 | 20 e7 | 20 e3 | 18 | 9/10 | 7/10 |
| combo | 17 | 11 | 11 | 20 e13 | 20 e14 | 19 e16 | 10/10 | 8/10 |

Non-saturating metric (mean waves survived, light / madness / mixed / gate): baseline not printed for light; sl_slow_weak 4.2 / 4.5 / 2.5 / 2.2; sl_cost120 4.5 / 4.5 / 2.5 / 2.2; sl_range_small 4.8 / 4.5 / 2.5 / 2.2; flare_cost12 3.3 / 4.5 / 2.6 / 2.8; combo 4.1 / 4.5 / 2.6 / 2.8. Early-wave ok overall: 170/200 for baseline and all Searchlight-only variants, 183/200 for flare_cost12 and combo.

Findings:
- `lt68_w3soft` is a null variant: the committed `data/waves.json` wave 3 already has deep_one 4, hybrid 8, so it reproduces baseline exactly (and the combo's wave patch is a no-op). A softer wave 3 needs new numbers (e.g. 3/6) to be tested. Gate and mixed still die in wave 3 (17 and 13 of 20 losses).
- Searchlight-only variants change only `light` (the other strategies build no Searchlight). Weaker slow 14, cost 120 7, small range 5 losses: only the slow reduction reaches 10; cost and range are too weak alone.
- `flare_cost12` is the only variant that moves the early waves (e7 -> e13 mixed, e3 -> e14 gate; the flare is spent less in early waves, evidently), and it also lifts `light` to 17 losses and madness to 11. Cost: mundane early e16 (was 20; still >= 15) and occult falls 13 -> 11 (margin 1).
- Still missing in every variant: mixed (e13) and gate (e14) are under 15 of 20 early. Smallest loss margin in combo/flare_cost12: madness 11 and occult 11 (margin 1), at the edge of the lab's noise (+-2-3).
- These variants are nudges, not double/halve probes (CLAUDE.local.md); the next step should be flare cost 16 (x2) and Searchlight slow 0.15, then bisect, and a real wave 3 reduction for gate/mixed.

Recommendation: ship `lt71_flare_cost12` (flare 12 oil), the simplest variant that meets the loss criterion for all 10 strategies (light 17, madness 11) and improves early waves; `combo` gives identical numbers, so its extra Searchlight changes are not needed. Side effects: occult margin shrinks to 1 and mundane loses a little early survival (e16); the early criterion is still unmet for mixed and gate (1 short for gate), so wave 3 needs a further cut.

### Machine state (LT-71)

| run | uptime at start (load avg) | uptime at end | /usr/bin/time -p |
|---|---|---|---|
| 6 variants x 10 x 20, --jobs=4 | 600.75 384.87 402.20 | 187.71 222.06 350.33 | real 4707.29 user 9496.50 sys 105.12 |

Load far above 200 at start, so 4 Godot processes at a time; user/real about 2.0 over 4 jobs (per-run 0.33-0.79), i.e. runs were partly waiting. Outcomes are deterministic per seed; timings are not comparable.

## Owner playtest (LT-60)

Run 1, 2026-11-02, release-0.4.0 at 894bb72, `-- --frame-stats`, seed 2727173648. Machine load at exit 28.18 18.22 9.26 (outside load; FPS not judged from this run).

Owner, verbatim: "сложно тестить маяк и другие штуки, потому что с текущим уровнем сложности - тупо не успеваешь развиться и что-то крутое построить."

Decision: "Песочница + задача на баланс (Recommended)" -> LT-67 (`--sandbox` launch flag), LT-68 (ease the early game after LT-63). Lighthouse, flare and Summoning Circle verdicts wait for a replay with these.

Run 2, 2026-11-18, release-0.4.0 at 23eb4d8 (after LT-69 whole-map flare, LT-70 light vs shadow,
LT-71 balance pass). Owner, verbatim: "В целом баланс норм, правда волн стоит делать побольше, но
это потом будем делать". More waves filed as a backlog task.

## LT-71 sensitivity sweep (x2/div2)

Measurement slice LT-71/S4, branch `balance/LT-71-light-shadow-tuning` at 058de50, seeds 1000..1019, flare on, 10 strategies. Variants `tools/balance/variants/lt71x_*.json` (untracked). Cells: losses of 20; `eN` = runs surviving waves 1-3 (target >= 15); `(m)` = mean waves survived (non-saturating metric). Strategies not listed are stated as equal to baseline or move little. `data/` is unchanged; the owner picks the numbers.

Baseline (this run): mundane 18 (3.2), occult 13 (4.3), mixed 20 e7 (2.5), madness 10 (4.5), demolition 18 (4.0), battery 19 (3.6), resonator 20 (3.1), gate 20 e3 (2.2), circle 20 (3.1), light 1 (5.0). Loss-target 9/10 (light), early target misses: mixed e7, gate e3. Both mixed and gate die in wave 3 (13 and 17 of 20), so wave 3 is the early-wave lever.

### Round 1: x2 / div2 per parameter (7 variants x 10 strategies, plus 4 Searchlight variants on `light` only, since only `light` builds a Searchlight, per S1)

| parameter (base) | div2 | x2 | what moves |
|---|---|---|---|
| flare oil cost (8) | 4: light 0 (5.0), madness 14 (4.3), occult 13, mundane 12, early ok 200/200 | 16: light 4 (4.6), madness 7 (4.7), occult 12, mixed e11, gate e6, circle e17, early 174/200 | big lever on everything: cheaper flare lifts early waves (mixed/gate pass) but light stops losing; dearer flare helps light only partly (4 of 10) and breaks madness (7) |
| Searchlight cost (80) | 40: light 0 (5.0) | 160: light 1 (5.0) | no effect on light outcome: cost is not a lever |
| Searchlight slow, speed left (0.7 / 0.65 / 0.65 / 0.5) | slow .65/.675/.675/.75: light 0 (5.0) | speed left capped at 1 (no slow): light 18 (3.3) | the only Searchlight lever; ranges from 0 to 18 losses |
| shadow occult bonus (+0.3) | +0.15: occult 17 (4.2), madness 14 (4.3); others equal baseline | +0.6: occult 4 (4.8), madness 5 (4.8); others equal baseline | moves only occult and madness; stronger shadow bonus makes them easier for the player. div2 pushes madness to 14, occult to 17 |
| wave 3 deep_one/hybrid (4/8) | 2/4: mixed e20, gate e20, all early 200/200; light 11 (3.9), madness 8 (4.6), occult 16 | 8/16: early 50/200, nearly everyone loses in wave 3 | decisive for the early criterion; also pulls light down to 11 |

Reading: flare cost and Searchlight slow are the two levers on `light`; wave 3 is the only lever that fixes mixed/gate early; shadow bonus is the only clean lever on occult/madness.

### Round 2: bisect (5 variants x 10 + 1 on light)

Wave 3 bisected between 4/8 (mixed e7, gate e3) and 2/4 (all e20): 3/6 gives mixed e20, gate e16 (barely), early 196/200 alone, madness 9, light 1.
Slow bisected between 0.3 (1 loss) and none (18): .15/.175/.175/.25 on light alone gives 12 losses (4.2), a clean midpoint.

| variant | loss/early met | notes |
|---|---|---|
| w3 3/6 + flare 12 | 9/10 | light 16 (3.4), madness 7 (4.7), occult 13, gate e20, mixed e20 |
| w3 2/4 + flare 12 | 8/10 | madness 8, occult 8 |
| w3 3/6 + flare 12 + slow .15/.175/.175/.25 | 9/10 | light 18 (3.2); slow adds little once flare is 12; madness 7 is the only miss |
| w3 2/4 + flare 12 + slow | 8/10 | occult 8 and madness 8 miss |

### Round 3: shadow bonus on the best set (w3 3/6, flare 12, slow .15/.175/.175/.25)

| variant | met | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle | light |
|---|---|---|---|---|---|---|---|---|---|---|---|
| shadow +0.15 (A) | 10/10 | 19 | 16 | 20 | 10 | 19 | 20 | 20 | 20 | 20 | 18 |
| shadow +0.22 | 9/10 | 19 | 14 | 20 | 8 | 19 | 20 | 20 | 20 | 20 | 18 |

All early ok 200/200 (every strategy e20); mean waves: mixed 3.0, gate 3.0, madness 4.5, occult 4.2, light 3.2.

### Candidates

- **A (meets the target, 10/10 losses and every early cell e20):** wave 3 deep_one 3 / hybrid 6, flare 12 oil, Searchlight slow 0.15 / 0.175 (branch a) 0.175 / (branch b) 0.25 (level 0 / level 1 as .15/.175), shadow occult power_mult 1.15. Side effects: madness sits exactly on 10 (margin 0, noise +-2-3, so a rerun may show 8-12); occult 16 (4.2); mundane/demolition 19; mixed and gate now die in wave 4 (3.0 mean); the whole set is four changes, so each lever matters less alone.
- **B (simpler, 9/10):** wave 3 3/6 + flare 12 only. Misses only madness (7 losses, 4.7). Add shadow +0.15 alone to B if the slow is unwanted: not run without the slow, expected to behave like A since slow changed only `light` (16 vs 18 losses).
- Notes: the slow reduction is optional for the target (light is already 16 with flare 12); shadow +0.15 is what lifts madness 7 -> 10. If the owner wants a margin for madness, try shadow +0.1 (not run).

### Machine state (LT-71 S4)

| round | uptime at start (load avg) | uptime at end | /usr/bin/time -p |
|---|---|---|---|
| 1: 7 variants x 10 x 20, jobs 6 | 102.80 173.34 312.54 | 169.58 254.09 319.15 (end of both parts) | real 3341.12 user 9262.96 sys 75.95; light-only part real 312.89 user 897.88 sys 7.56 |
| 2: 5 variants x 10 + 1 light-only | 156.71 247.31 315.60 | 71.83 280.38 386.14 | real 2501.02 user 6301.62 sys 63.64 (first part) |
| 3: 2 variants x 10 x 20 | 57.36 266.97 379.51 | 67.30 159.78 279.15 | real 1291.37 user 2579.31 sys 35.79 |

User/real 0.35-0.5 over 6 jobs: partly waiting on an externally loaded machine. Outcomes are deterministic per seed; timings are not comparable.

### LT-71 candidate A recheck (40 seeds)

Owner chose "A + перепроверка madness (Recommended)". `lt71x_cand_sh115`, 40 seeds, `--jobs=6`,
load 76 -> 150, real 1368 s, user 2930 s.

| strategy | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle | light |
|---|---|---|---|---|---|---|---|---|---|---|
| losses / 40 | 39 | 33 | 40 | 21 | 39 | 40 | 40 | 40 | 40 | 38 |
| mean waves survived | 3.1 | 4.2 | 3.0 | 4.5 | 3.1 | 4.0 | 3.2 | 3.0 | 3.0 | 3.1 |

All 10 strategies meet the target (>= 20/40), and every run survives waves 1-3 (400/400).
Madness passes at 21/40, a thin margin. Wave 4 is now where most runs end (255 of 370 losses).


## More waves (LT-72)

Option B of `docs/design/LT-72-more-waves.md` (10 waves, owner decisions of 2026-11-21) measured
in the balance lab, commit `47833be` + the new variants. Variants: `lt72_b` (option B table),
`lt72_b_late_x2` / `lt72_b_late_d2` (`hp_mult` of waves 6-10 x2 = 3.2/3.7/4.0/4.8/5.4, /2 =
0.8/0.925/1.0/1.2/1.35), next to `baseline` (today's 5 waves). 20 seeds, all 10 strategies, flare
on, `--jobs=5`. Early = waves 1..5 (owner decision), target >= 10/20 losses.

Machine: `uptime` at start `14:55 load averages: 98.00 104.59 88.50`, at end `17:01 load averages:
163.90 143.12 148.53` (another agent and other users loaded the machine all the time).
`/usr/bin/time -p`: real 7538.34, user 4866.83, sys 69.14 (user/real 0.65 over 5 processes, per row
0.19-0.25: the runs were mostly waiting for CPU). **9 of 40 jobs hit the lab's 1320 s per-process
timeout** (`lt72_b/light`, `lt72_b_late_x2/{occult,madness,light}`,
`lt72_b_late_d2/{occult,madness,battery,resonator,light}`); their cells hold only the seeds that
finished (11-19 of 20, in seed order), so those cells are incomplete, not 0-win results.

Losses of 20 (a cell is wins/losses; `eN` = runs surviving waves 1..5):

| variant | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle | light | met | s/run | user/real |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| baseline | 1/19 e1 no | 4/16 e4 no | 0/20 e0 no | 10/10 e10 no | 1/19 e1 no | 0/20 e0 no | 0/20 e0 no | 0/20 e0 no | 0/20 e0 no | 2/18 e2 no | 0/10 | 27.0 | 0.25 |
| lt72_b | 0/20 e3 no | 0/20 e20 **yes** | 0/20 e2 no | 0/20 e20 **yes** | 0/20 e4 no | 0/20 e20 **yes** | 0/20 e18 **yes** | 0/20 e2 no | 0/20 e3 no | 0/15 e9 no | 4/10 | 31.6 | 0.23 |
| lt72_b_late_x2 | 0/20 e3 no | 0/15 e15 **yes** | 0/20 e2 no | 0/17 e17 **yes** | 0/20 e4 no | 0/20 e20 **yes** | 0/20 e18 **yes** | 0/20 e2 no | 0/20 e3 no | 0/17 e10 no | 4/10 | 33.0 | 0.19 |
| lt72_b_late_d2 | 0/20 e3 no | 0/11 e11 no | 0/20 e2 no | 0/17 e17 **yes** | 0/20 e4 no | 0/14 e14 no | 0/19 e17 **yes** | 0/20 e2 no | 0/20 e3 no | 7/5 e7 no | 2/10 | 24.7 | 0.20 |

Where runs end (losses in wave 1..10, mean waves survived in brackets):

| variant | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle | light | all losses by wave | early ok |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| baseline | 0.0.0.17.2.0.0.0.0.0 (3.2) | 0.0.0.0.16.0.0.0.0.0 (4.2) | 0.0.0.19.1.0.0.0.0.0 (3.0) | 0.0.0.0.10.0.0.0.0.0 (4.5) | 0.0.0.17.2.0.0.0.0.0 (3.2) | 0.0.0.1.19.0.0.0.0.0 (4.0) | 0.0.0.13.7.0.0.0.0.0 (3.4) | 0.0.0.19.1.0.0.0.0.0 (3.0) | 0.0.0.18.2.0.0.0.0.0 (3.1) | 0.0.0.17.1.0.0.0.0.0 (3.2) | 0.0.0.121.61.0.0.0.0.0 | 18/200 (9%) |
| lt72_b | 0.0.0.8.9.0.3.0.0.0 (3.9) | 0.0.0.0.0.0.18.2.0.0 (6.1) | 0.0.0.13.5.1.0.1.0.0 (3.5) | 0.0.0.0.0.9.11.0.0.0 (5.5) | 0.0.0.0.16.2.0.2.0.0 (4.4) | 0.0.0.0.0.18.2.0.0.0 (5.1) | 0.0.0.0.2.18.0.0.0.0 (4.9) | 0.0.0.15.3.2.0.0.0.0 (3.4) | 0.0.0.5.12.3.0.0.0.0 (3.9) | 0.0.0.0.6.7.0.1.0.1 (5.0) | 0.0.0.41.53.60.34.6.0.1 | 101/195 (52%) |
| lt72_b_late_x2 | 0.0.0.8.9.3.0.0.0.0 (3.8) | 0.0.0.0.0.3.12.0.0.0 (5.8) | 0.0.0.13.5.2.0.0.0.0 (3.5) | 0.0.0.0.0.9.8.0.0.0 (5.5) | 0.0.0.0.16.4.0.0.0.0 (4.2) | 0.0.0.0.0.20.0.0.0.0 (5.0) | 0.0.0.0.2.18.0.0.0.0 (4.9) | 0.0.0.15.3.2.0.0.0.0 (3.4) | 0.0.0.5.12.3.0.0.0.0 (3.9) | 0.0.0.0.7.10.0.0.0.0 (4.6) | 0.0.0.41.54.74.20.0.0.0 | 94/189 (50%) |
| lt72_b_late_d2 | 0.0.0.8.9.0.0.1.1.1 (4.2) | 0.0.0.0.0.0.1.10.0.0 (6.9) | 0.0.0.13.5.0.1.1.0.0 (3.6) | 0.0.0.0.0.0.15.2.0.0 (6.1) | 0.0.0.0.16.0.0.0.3.1 (4.8) | 0.0.0.0.0.0.0.0.13.1 (8.1) | 0.0.0.0.2.0.3.4.10.0 (7.1) | 0.0.0.15.3.0.2.0.0.0 (3.5) | 0.0.0.5.12.0.1.2.0.0 (4.2) | 0.0.0.0.5.0.0.0.0.0 (7.5) | 0.0.0.41.52.0.23.20.27.3 | 80/173 (46%) |

Lighthouse HP left (mean/median):

| variant | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle | light |
|---|---|---|---|---|---|---|---|---|---|---|
| baseline | 0.2/0.0 | 0.5/0.0 | 0.0/0.0 | 1.9/0.5 | 0.1/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.7/0.0 |
| lt72_b | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 |
| lt72_b_late_x2 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 |
| lt72_b_late_d2 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 0.0/0.0 | 5.1/1.0 |

Reading:

- Meets >= 10/20 losses (every run of an arm that finished is lost, 0 wins, in `lt72_b` and
  `lt72_b_late_x2`; `/2` has 7 wins only for `light`): all three B arms lose >= 10 in every strategy
  that was played to the end. The two-part target (also survive waves 1..5 in 15 of 20) is met by 4/10
  strategies in `lt72_b` and `x2`, 2/10 in `/2`; mundane, mixed, demolition, gate, circle, light still die in
  waves 4-5 (early ok 52% / 50% / 46% of runs, baseline 9%).
- Runs reach waves 6-10: loss waves in `lt72_b` are 41/53/60/34/6/0/1 in waves 4/5/6/7/8/9/10, mean
  waves survived (over lost runs, all strategies) 4.56 vs baseline 3.41; `/2` reaches 5.25 (waves 8-9 reached by
  battery, resonator) and is the only arm with wins (7 `light` wins). The finale (wave 10) is reached by 1 run in `lt72_b`, 0 in `x2`, 3 in `/2` (plus those 7 wins).
- Early waves 1..5 are now the wall again for 6 strategies (wave 4 is the new "hybrid 12 + gaunt 10"
  wave, not much easier than old wave 4 for mundane/mixed/gate): all 94-101/195 early survivors come from
  occult, madness, battery, resonator and light. The 6 early-dying strategies are the same in all three B arms
  because waves 1..5 are identical.
- Late `hp_mult` is a weak lever against bots that get past wave 5: x2 moves losses from waves 7-8 to
  6-7 (mean 4.41 vs 4.56), /2 pushes them to waves 8-9 (5.25). Next step (not run): bisect between `/2`
  (too weak, only arm with wins) and `lt72_b` (all lost) at `hp_mult` waves 6-10 x0.7
  (1.12/1.3/1.4/1.68/1.89), and rerun the 9 timed-out jobs with a larger per-process timeout or fewer jobs
  under lower load (unchanged waves 1..5 need no re-run for the 6 early-dying strategies).
- Caveat: the "lighthouse HP left" table cannot separate arms (every run lost, 0.0), as LT-116 noted; the
  wave reached in "Where runs end" is the metric that moves.

### Round 1, completed cells

The 9 jobs that hit the lab's 1320 s per-process timeout were rerun (one `balance.py` call per
variant with `--strategies=`, 20 seeds, `--jobs=4`; the lab has no per-process timeout flag, the limit
is `120 + 60 x seeds` and was not raised, the rerun simply finished under a lower load: `uptime` 18:27
load 8.95, 153 / 215 / 578 s real). All 9 cells now hold 20 runs (`eN` = survived waves 1..5; recomputed
from the loss-wave columns where the lab's own `eN` counted waves 1..4 because the variant's last
loss wave was 7):

| cell | wins/losses | early ok | losses by wave 1..10 (mean waves) | meets two-part target |
|---|---|---|---|---|
| lt72_b / light | 0/20 | 11/20 | 0.0.0.0.9.9.0.1.0.1 (4.8) | no |
| lt72_b_late_x2 / occult | 0/20 | 20/20 | 0.0.0.0.0.4.16 (5.8) | yes |
| lt72_b_late_x2 / madness | 0/20 | 20/20 | 0.0.0.0.0.9.11 (5.5) | yes |
| lt72_b_late_x2 / light | 0/20 | 11/20 | 0.0.0.0.9.11.0 (4.5) | no |
| lt72_b_late_d2 / occult | 0/20 | 20/20 | 0.0.0.0.0.0.2.18.0.0 (6.9) | yes |
| lt72_b_late_d2 / madness | 0/20 | 20/20 | 0.0.0.0.0.0.17.3.0.0 (6.2) | yes |
| lt72_b_late_d2 / battery | 0/20 | 20/20 | 0.0.0.0.0.0.0.0.17.3 (8.2) | yes |
| lt72_b_late_d2 / resonator | 0/20 | 18/20 | 0.0.0.0.2.0.3.4.11.0 (7.1) | yes |
| lt72_b_late_d2 / light | 11/9 | 11/20 | 0.0.0.0.9.0.0.0.0.0 (7.3), HP left 4.3/1.0 | no (9 losses) |

With these, round 1 meets the two-part target for 4/10 strategies in all three arms (occult, madness,
battery, resonator; `/2` had 2/10 only because of the incomplete cells). `light` and the six early-dying
strategies stay below it.

## More waves (LT-72), round 2: waves 4-5 `hp_mult`

Owner decision: "Ранние волны 4-5 ×2/÷2 (Recommended)". Variants: `lt72_b_early_x2` / `lt72_b_early_d2` =
`lt72_b` with `hp_mult` of waves 4 and 5 (0-based 3, 4) set to 2.0 / 0.5 (they are 1.0, i.e. unset, in
`lt72_b`); everything else identical. 20 seeds, all 10 strategies, flare on, `--jobs=4`, target >= 10/20
losses and survive waves 1..5 in >= 15/20. Machine: `uptime` at start `18:03 load averages: 10.82 20.16
27.12`, at end of the main run `18:27 load 8.95 47.53 72.68`; `/usr/bin/time -p` for the main run: real
1407.36, user 3220.57, sys 32.40 (user/real 2.3 over 4 processes; s/run 10.2 and 15.2, no timeouts).

Losses of 20 (wins/losses, `eN` = survived waves 1..5):

| variant | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle | light | met |
|---|---|---|---|---|---|---|---|---|---|---|---|
| lt72_b (round 1) | 0/20 e3 | 0/20 e20 | 0/20 e2 | 0/20 e20 | 0/20 e4 | 0/20 e20 | 0/20 e18 | 0/20 e2 | 0/20 e3 | 0/20 e11 | 4/10 |
| lt72_b_early_x2 | 0/20 e0 | 0/20 e1 | 0/20 e0 | 0/20 e2 | 0/20 e0 | 0/20 e0 | 0/20 e0 | 0/20 e0 | 0/20 e0 | 0/20 e0 | 0/10 |
| lt72_b_early_d2 | 0/20 e20 | 0/20 e20 | 0/20 e20 | 0/20 e20 | 0/20 e20 | 0/20 e20 | 0/20 e20 | 0/20 e20 | 0/20 e20 | 0/20 e20 | 10/10 |

Where runs end (losses in wave 1..10, mean waves survived in brackets):

| variant | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle | light | all losses by wave | early ok |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| early_x2 | 0.0.0.17.3.0.0.0.0.0 (3.1) | 0.0.0.1.18.0.1.0.0.0 (4.0) | 0.0.0.19.1.0.0.0.0.0 (3.0) | 0.0.0.0.18.2.0.0.0.0 (4.1) | 0.0.0.18.2.0.0.0.0.0 (3.1) | 0.0.0.1.19.0.0.0.0.0 (4.0) | 0.0.0.16.4.0.0.0.0.0 (3.2) | 0.0.0.19.1.0.0.0.0.0 (3.0) | 0.0.0.18.2.0.0.0.0.0 (3.1) | 0.0.0.17.3.0.0.0.0.0 (3.1) | 0.0.0.126.71.2.1.0.0.0 | 3/200 (2%) |
| early_d2 | 0.0.0.0.0.17.2.1.0.0 (5.2) | 0.0.0.0.0.0.18.2.0.0 (6.1) | 0.0.0.0.0.13.6.1.0.0 (5.4) | 0.0.0.0.0.8.12.0.0.0 (5.6) | 0.0.0.0.0.13.5.2.0.0 (5.5) | 0.0.0.0.0.13.5.2.0.0 (5.5) | 0.0.0.0.0.20.0.0.0.0 (5.0) | 0.0.0.0.0.20.0.0.0.0 (5.0) | 0.0.0.0.0.18.2.0.0.0 (5.1) | 0.0.0.0.0.15.1.3.0.1 (5.5) | 0.0.0.0.0.137.51.11.0.1 | 200/200 (100%) |

Lighthouse HP left: 0.0/0.0 in every cell of both arms (every run lost; the metric does not separate
arms, as in round 1). Waves reached is the metric that moves: mean waves survived over the 10 strategies
3.47 (x2) vs 5.49 (/2) vs 4.56 (`lt72_b`, round 1).

Reading:

- `x2` is too strong: early ok 2% (3/200), 197 of 200 runs die in waves 4-5, mean 3.47 waves; target met by 0/10.
- `/2` meets the two-part target for 10/10 strategies: 0 wins, 20 losses everywhere, early ok 200/200,
  losses fall in waves 6-8 (137/51/11), one run dies in wave 10. It is
  not "too weak" by the target (no wins), but waves 4-5 become a non-event, so the early game loses its
  threat; the intended value is the largest `hp_mult` that still meets the target.
- Waves 4-5 are the lever: 1.0 -> 0.5 moves early ok from 52% to 100% and adds 0.9 mean waves; 1.0 -> 2.0 drops it to 2%.
- Proposed bisect (not run): `hp_mult` of waves 4-5 = 0.7 (between `/2` = meets 10/10 and `lt72_b` at 1.0 =
  meets 4/10); if 0.7 still meets >= 8/10, try 0.85, else 0.6. The late waves 6-10 stay at the `lt72_b` values.

## More waves (LT-72), round 3: owner's pick "4-5 ×0.7 + (4-5 ÷2 & 6-10 ÷2)"

Variants: `lt72_b_early_07` = `lt72_b` with `hp_mult` of waves 4-5 = 0.7 (waves 6-10 as `lt72_b`: 1.6/1.85/2.0/2.4/2.7);
`lt72_b_early_d2_late_d2` = `lt72_b_early_d2` (waves 4-5 = 0.5) with waves 6-10 halved (0.8/0.925/1.0/1.2/1.35, as `lt72_b_late_d2`).
20 seeds, all 10 strategies, flare on, `--jobs=5`, target >= 10/20 losses and survive waves 1..5 in >= 15/20.
Machine: `uptime` at start `19:58 load averages: 3.68 4.31 12.65`, at end `20:17 load 4.63 11.34 14.52`;
`/usr/bin/time -p`: real 1169.23, user 4603.01, sys 28.78 (user/real 3.9 over 5 processes: CPU-bound, no waiting; no timeouts).

Cells (wins/losses, `eN` = survived waves 1..5):

| variant | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle | light | met |
|---|---|---|---|---|---|---|---|---|---|---|---|
| early_07 | 0/20 e20 yes | 0/20 e20 yes | 0/20 e18 yes | 0/20 e20 yes | 0/20 e20 yes | 0/20 e20 yes | 0/20 e20 yes | 0/20 e16 yes | 0/20 e20 yes | 1/19 e20 yes | 10/10 |
| early_d2_late_d2 | 0/20 e20 yes | 0/20 e20 yes | 0/20 e20 yes | 0/20 e20 yes | 2/18 e20 yes | 0/20 e20 yes | 0/20 e20 yes | 0/20 e20 yes | 0/20 e20 yes | 20/0 e20 no | 9/10 |

Where runs end (losses in wave 1..10, mean waves survived in brackets):

| variant | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle | light | all losses by wave | early ok |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| early_07 | 0.0.0.0.0.17.2.1.0.0 (5.2) | 0.0.0.0.0.0.19.1.0.0 (6.0) | 0.0.0.0.2.10.7.1.0.0 (5.3) | 0.0.0.0.0.8.12.0.0.0 (5.6) | 0.0.0.0.0.14.3.3.0.0 (5.5) | 0.0.0.0.0.15.4.1.0.0 (5.3) | 0.0.0.0.0.18.2.0.0.0 (5.1) | 0.0.0.1.3.16.0.0.0.0 (4.8) | 0.0.0.0.0.19.1.0.0.0 (5.0) | 0.0.0.0.0.17.1.1.0.0 (5.4) | 0.0.0.1.5.134.51.8.0.0 | 194/200 (97%) |
| early_d2_late_d2 | 0.0.0.0.0.0.0.2.18.0 (7.9) | 0.0.0.0.0.0.0.20.0.0 (7.0) | 0.0.0.0.0.0.12.8.0.0 (6.4) | 0.0.0.0.0.2.17.1.0.0 (6.0) | 0.0.0.0.0.0.0.1.8.9 (8.6) | 0.0.0.0.0.0.0.0.14.6 (8.3) | 0.0.0.0.0.0.0.4.9.7 (8.2) | 0.0.0.0.0.0.20.0.0.0 (6.0) | 0.0.0.0.0.0.0.20.0.0 (7.0) | no losses, 20 wins (10.0) | 0.0.0.0.0.2.49.56.49.22 | 200/200 (100%) |

Lighthouse HP left (mean/median): all 0.0/0.0 except early_07 `light` 0.1/0.0 and early_d2_late_d2 demolition 0.7/0.0, `light` 16.6/17.0
(the only arm where the metric separates anything: `light` wins with HP to spare).
Totals: early_07 1 win / 199 losses, mean waves survived 5.32 (mean of the 10 strategy means), early ok 97%, target met 10/10;
early_d2_late_d2 22 wins / 178 losses, mean waves 7.54, early ok 100%, target met 9/10 (`light` wins 20/20).

Reading: with the early waves tamed, `early_07` still ends 85% of runs in waves 6-7 (134/51 of 199) and has
one win, so it is a close-to-minimal fix: the two-part target for every strategy, gate is the weakest early
(e16, 3 deaths in wave 5, 1 in wave 4). `early_d2_late_d2` pushes deaths to waves 7-10 (every wave 7-10 has
22-56 losses, wave 10 reached by 22 runs) but `light` is unbeatable (20/20 wins) and demolition wins 2.

### Proposed shipped list (lab proposes, owner picks)

- Waves 4-5 `hp_mult` 0.7, waves 6-10 as `lt72_b` (1.6/1.85/2.0/2.4/2.7) = `lt72_b_early_07`: meets the two-part target for
  10/10 strategies, 97% early ok, but only 1 win in 200 runs, deaths concentrated in waves 6-7 (the "some wins" part is thin).
- Suggested middle value to measure next (not run): `lt72_b_early_07` with waves 6-10 `hp_mult` x0.8 (1.28/1.48/1.6/1.92/2.16), between
  `early_07` (1 win, mean 5.3 waves) and `early_d2_late_d2` (22 wins, 20 of them `light`, mean 7.5 waves): it should
  give a few wins for several strategies and reach waves 8-10 without handing `light` a free win. If the owner wants no further run, ship `early_07`.

## More waves (LT-72), round 4: `lt72_b_early_07_late_08`

Variant: `lt72_b_early_07` with waves 6-10 `hp_mult` x0.8 = 1.28/1.48/1.6/1.92/2.16 (waves 4-5 = 0.7).
20 seeds, all 10 strategies, flare on, `--jobs=4`. Machine: `uptime` at start `20:34 load averages: 4.41 13.87
19.89`, at end `20:50 load 17.50 32.60 40.08` (a GDScript suite ran meanwhile); `/usr/bin/time -p`: real 946.61,
user 2479.64, sys 18.90 (user/real 2.6 over 4 processes, s/run 13.6, no timeouts, no incomplete cells).

| strategy | wins/losses | early ok (e) | met | deaths by wave 1..10 (mean waves) |
|---|---|---|---|---|
| mundane | 0/20 | 20 | yes | 0.0.0.0.0.7.7.6.0.0 (6.0) |
| occult | 0/20 | 20 | yes | 0.0.0.0.0.0.17.3.0.0 (6.2) |
| mixed | 0/20 | 18 | yes | 0.0.0.0.2.10.6.2.0.0 (5.4) |
| madness | 0/20 | 20 | yes | 0.0.0.0.0.2.18.0.0.0 (5.9) |
| demolition | 0/20 | 20 | yes | 0.0.0.0.0.3.2.6.9.0 (7.0) |
| battery | 0/20 | 20 | yes | 0.0.0.0.0.0.5.12.3.0 (6.9) |
| resonator | 0/20 | 20 | yes | 0.0.0.0.0.7.13.0.0.0 (5.7) |
| gate | 0/20 | 16 | yes | 0.0.0.1.3.16.0.0.0.0 (4.8) |
| circle | 0/20 | 20 | yes | 0.0.0.0.0.14.5.1.0.0 (5.3) |
| light | 6/14 | 20 | yes | 0.0.0.0.0.2.2.9.1.0 (7.7) |
| all | 6/194 | 194/200 (97%) | 10/10 | 0.0.0.1.5.61.75.39.13.0 |

Totals: 6 wins (all `light`) / 194 losses, mean waves survived 6.09 (mean of the 10 strategy means), early ok 97%,
target met 10/10. Lighthouse HP left: 0.0 everywhere except `light` 2.6/0.0. Nobody reaches the wave-10 finale
(no death in wave 10, no run beyond wave 9 except the 6 `light` wins).

### Summary of rounds (20 seeds x 10 strategies, flare on)

| arm | wins / 200 | mean waves | early ok | target met |
|---|---|---|---|---|
| baseline (today's 5 waves) | 18 | 3.41 | 9% | 0/10 |
| lt72_b | 0 | 4.56 | 52% | 4/10 |
| lt72_b_late_x2 | 0 | 4.41 | 50% | 4/10 |
| lt72_b_late_d2 (round 1, cells completed) | 11 | 5.25 | 46% (before completion) | 4/10 |
| lt72_b_early_x2 | 0 | 3.47 | 2% | 0/10 |
| lt72_b_early_d2 | 0 | 5.49 | 100% | 10/10 |
| lt72_b_early_07 | 1 | 5.32 | 97% | 10/10 |
| lt72_b_early_d2_late_d2 | 22 | 7.54 | 100% | 9/10 |
| **lt72_b_early_07_late_08** | 6 | 6.09 | 97% | 10/10 |

Mean waves are as the lab reports them (over lost runs, round-1 rows) or per-strategy means averaged (rounds 2-4); compare
within a round, not across. Proposal: `lt72_b_early_07_late_08` is the only arm that meets the two-part target for 10/10
strategies, has wins (6, all `light`) and ends runs in waves 6-9; the owner picks the shipped numbers.

## LT-117 tower_lift (0.11.0)

Night gaunts lift a tower and drop it 2 cells away, disabled for 3 s (`night_gaunt.traits.tower_lift`, from wave 6; gaunts first appear in wave 7, 56 of them in waves 7-10). Playtest 0.4 is still the open lab log (its last section is LT-72 round 4), so the table goes here. Plan: `docs/design/LT-117-tower-lift.md` §8.

Arms: `baseline` (shipped data, lift on) vs `lt117_lift_off` (`from_wave: 11`, never active in 10 waves). `python3 tools/balance/balance.py baseline lt117_lift_off --seeds=20 --jobs=6`, seeds 1000..1019, 10 strategies, flare on, commit `cb12597`. RUN lines carry the new `lifts` field (count of `TOWER_LIFTED`).

Control: mean `lifts` is 0.00 in every `lt117_lift_off` row and above 0 in baseline for 5 of 10 strategies (below), so the arms differ. The other 5 strategies (occult, madness, resonator, gate, circle) are lifted 0 times in 20 runs each: they build nothing under the gaunts' flight line, or die before wave 7 reaches them.

| strategy | wins/losses (on / off) | mean waves survived (on / off) | lighthouse HP mean/median (on / off) | mean lifts per run (on) |
|---|---|---|---|---|
| mundane | 0/20 / 0/20 | 5.9 / 6.0 | 0.0/0.0 / 0.0/0.0 | 1.10 |
| occult | 0/20 / 0/20 | 6.2 / 6.2 | 0.0/0.0 / 0.0/0.0 | 0.00 |
| mixed | 0/20 / 0/20 | 5.4 / 5.4 | 0.0/0.0 / 0.0/0.0 | 0.65 |
| madness | 0/20 / 0/20 | 5.9 / 5.9 | 0.0/0.0 / 0.0/0.0 | 0.00 |
| demolition | 0/20 / 0/20 | 7.0 / 7.0 | 0.0/0.0 / 0.0/0.0 | 2.45 |
| battery | 0/20 / 0/20 | 6.9 / 6.9 | 0.0/0.0 / 0.0/0.0 | 1.60 |
| resonator | 0/20 / 0/20 | 5.7 / 5.7 | 0.0/0.0 / 0.0/0.0 | 0.00 |
| gate | 0/20 / 0/20 | 4.8 / 4.8 | 0.0/0.0 / 0.0/0.0 | 0.00 |
| circle | 0/20 / 0/20 | 5.3 / 5.3 | 0.0/0.0 / 0.0/0.0 | 0.00 |
| light | 5/15 / 6/14 | 7.5 / 7.7 | 2.2/0.0 / 2.6/0.0 | 2.75 |
| all | 5/195 / 6/194 | 6.06 / 6.09 | | 0.86 |

Losses per wave (waves 1..10, on / off, all strategies summed; waves 1-5 are 0.0.0.1.5 in both):

| wave | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|
| deaths, lift on | 61 | 76 | 39 | 12 | 1 |
| deaths, lift off | 61 | 75 | 39 | 13 | 0 |

Per strategy, rows differ only in `mundane` (wave 7/8: 8/5 on, 7/6 off) and `light` (waves 8-10: 10/0/1 on, 9/1/0 off); the other 8 strategies have identical rows.

Machine state: wall 2867 s for 400 runs, `/usr/bin/time -p` real 2867.47, user 5307.33, sys 47.39 (user/real 1.85 over 6 jobs); uptime at start `load averages: 26.10 16.15 10.57`, load peaked above 500 during the run (other agents), end `109.14 158.22 225.69`. Timings (s/run 38.1 vs 23.7) are not comparable between arms; the outcomes are seeded and do not depend on load.

Reading:

- The lift is lab-invisible: losses 195 vs 194 of 200, mean waves survived 6.06 vs 6.09, both inside the ±2-3 noise. The one-run shifts (`mundane` wave 8 vs 7, `light` wave 10 vs 8) are the only differences, and they are the strategies that get lifted most often besides `demolition` and `battery`.
- Lifts do happen (0.86 per run on average, 2.75 for `light`, 2.45 for `demolition`), but gaunts arrive when most runs are already dying in waves 6-8 (150 of 195 losses), and a 3 s disable of one tower does not change the outcome of a run.
- Lighthouse HP does not separate the arms either: only `light` ever wins, 2.2 vs 2.6 mean.
- Caveat from the plan: the bot rebuilds into a slot a lift emptied, which softens the effect on the lab; a player who must react by hand may feel it more.
- No re-tune from the lab. If the owner wants the lift to bite, the lab proposal is "double or halve X", not a nudge: `disable_seconds` 3 -> 6 (x2) with 1.5 as the weak arm, then `drop_cells` 2 -> 4 / 1; bisect after the first pair. Inertness control against a pre-LT-117 build (2 seeds, byte-identical RUN lines) was not run in this slice.
