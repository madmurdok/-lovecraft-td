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

## Owner playtest (LT-60)

Run 1, 2026-11-02, release-0.4.0 at 894bb72, `-- --frame-stats`, seed 2727173648. Machine load at exit 28.18 18.22 9.26 (outside load; FPS not judged from this run).

Owner, verbatim: "сложно тестить маяк и другие штуки, потому что с текущим уровнем сложности - тупо не успеваешь развиться и что-то крутое построить."

Decision: "Песочница + задача на баланс (Recommended)" -> LT-67 (`--sandbox` launch flag), LT-68 (ease the early game after LT-63). Lighthouse, flare and Summoning Circle verdicts wait for a replay with these.
