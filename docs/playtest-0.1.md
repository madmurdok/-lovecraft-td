# Playtest 0.1

## Baseline: headless bot runs

### Method

`tools/bot_runs.gd` plays the placeholder balance in `data/` (unchanged) with three scripted
bots, 10 seeds each (1000-1009), 30 runs in total. Run:
`$GODOT --headless --path . -s res://tools/bot_runs.gd -- --seeds=10 [--out=<json>]`.
The bot builds a `Simulation` with a `WaveDirector`, builds the next item of its order as soon
as it can pay, re-checks every second, and calls `call_wave()` at once in every build phase
(waiting earns nothing but a smaller early-call bonus). Placement is greedy: the free cell
with the most path cells inside the tower's L1 range. No upgrades, no sells (the sim has no
upgrade command), so this measures L1 towers only.

- **mundane**: rifleman, rifleman, harpooner repeated; never occult.
- **occult**: one rifleman, then Elder Sign / Necronomicon Reader alternating; builds a
  rifleman instead when an occult build would leave sanity below 25; tries `buy_sanity()` (refused:
  `exit_rule` is `permanent`).
- **madness**: Reader / Elder Sign alternating, no guard, never buys sanity.

Timing: 10 x 3 runs took 74 s wall (`real 74.17 user 62.41 sys 0.82`); `uptime` before:
`load averages: 76.88 106.90 152.32` (machine heavily loaded, `user` close to `real` so the
process was computing, not waiting).

### Results

| Strategy | Win rate | Mean waves cleared (of 5) | Lighthouse HP left (of 20) | Mean final gold | Fakes / run | Astray shots / run | Missed shots / run | Shots / run |
|---|---|---|---|---|---|---|---|---|
| mundane | 10/10 | 5.0 | 20.0 | 189 | 0 | 0 | 0 | 464 |
| occult | 10/10 | 5.0 | 13.0 | 194 | 0 | 7.0 | 3.9 | 194 |
| madness | 10/10 | 5.0 | 13.0 | 234 | 0 | 21.4 | 0 | 72 |

Mean sanity at each wave end (after between-waves regen):

| Strategy | W1 | W2 | W3 | W4 | W5 |
|---|---|---|---|---|---|
| mundane | 100.0 | 100.0 | 100.0 | 100.0 | 93.0 |
| occult | 100.0 | 96.5 | 81.5 | 53.6 | 0.0 |
| madness | 90.0 | 84.0 | 54.0 | 24.0 | 0.0 |

Share of simulated time per sanity state:

| Strategy | Lucid | Whispers | Fraying | Madness | Seconds / run |
|---|---|---|---|---|---|
| mundane | 100% | 0% | 0% | 0% | 181 |
| occult | 64.4% | 15.3% | 16.0% | 4.3% | 262 |
| madness | 44.1% | 18.0% | 19.5% | 18.4% | 260 |

### Observations

- **Every strategy wins every seed**; the 5-wave placeholder balance cannot be lost by these
  bots. Results barely vary by seed (the means above are near-identical per run), so the
  baseline says little about difficulty, only about the sanity curve.
- **Hallucinations never appear (0 fakes in 30 runs)**, confirming the suspicion: fakes spawn
  only while real spawns of the wave are unfired, and waves finish spawning in about 6-11 s,
  while Whispers waits 15 s for its first fake. Only Fraying (6 s) could produce one, and the bots reach
  it just when wave 5 starts (a 6 s spawn window).
- **Mundane play never touches sanity** (100 until a small dip in wave 5 from the
  Shoggoth's horror); the occult path is the only one that moves it.
- **Occult costs sanity fast**: Reader casts cost 2 per cast, so occult drops from 100 to 0 across
  waves 3-5 and ends the final wave in Madness (4% of time). Deliberate madness spends ~18% of the run in Madness.
- **Madness is not punishing yet**: damage x2 offsets astray shots (21 astray shots per
  madness run, 0 misses since occult never misses), and the madness bot keeps more gold (234) than the
  occult bot. The lighthouse loses 7 HP in both occult-based runs (leaks, probably flyers or
  the Shoggoth) but never falls.
- **Mundane overkill**: 19 L1 mundane towers (about 460 shots per run) hold the lighthouse at 20/20, so
  the economy (200 start gold plus wave bonuses) is generous for a 5-wave run.
