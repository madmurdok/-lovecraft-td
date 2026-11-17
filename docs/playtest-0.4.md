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

## Owner playtest (LT-60)

Run 1, 2026-11-02, release-0.4.0 at 894bb72, `-- --frame-stats`, seed 2727173648. Machine load at exit 28.18 18.22 9.26 (outside load; FPS not judged from this run).

Owner, verbatim: "сложно тестить маяк и другие штуки, потому что с текущим уровнем сложности - тупо не успеваешь развиться и что-то крутое построить."

Decision: "Песочница + задача на баланс (Recommended)" -> LT-67 (`--sandbox` launch flag), LT-68 (ease the early game after LT-63). Lighthouse, flare and Summoning Circle verdicts wait for a replay with these.
