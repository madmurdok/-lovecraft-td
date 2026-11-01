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
