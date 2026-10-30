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

## Tuning pass (before the native playtest)

### Method

Owner decision "Растянуть волны в LT-15". Five iterations of `tools/bot_runs.gd` (10 seeds x
3 bots per variant); from iteration 2 on, 3-4 variants per iteration ran in parallel from
copies of `data/` via the new `--data=<dir>` harness option. Wall time per variant
126-211 s (`user` 101-145 s, so computing, not waiting), with the
shared machine at `load averages` between 25 and 389 (`uptime` before the final iteration:
`192.76 205.79 139.72`). Values pinned by `tests/config_valid_test.gd` (economy, enemy stats,
tower costs, Elder Sign sanity cost, sanity thresholds/regen, madness numbers, wave 1 group 1,
the wave 2 Deep One delay, 5 waves, 25 s build phase) were not touched.

### Changed values (`data/waves.json` only)

Spawn window = time from wave start to its last spawn event.

| Wave | Old content | New content | Spawn window old -> new |
|---|---|---|---|
| 1 | 8 cultists @1.2 s | + 4 cultists @2.5 s from 12 s | 8.4 s -> 19.5 s |
| 2 | 10 cultists @1.0 s; 1 Deep One pack at 8 s | 12 cultists @2.2 s; packs at 8 s and 24 s | 9 s -> 24.2 s |
| 3 | 2 packs @6 s; 4 hybrids @2 s from 3 s | 4 packs @7 s; 9 hybrids @3 s from 3 s | 9 s -> 27 s |
| 4 | 6 hybrids @1.8 s; 3 night-gaunts @3 s from 5 s | 6 hybrids @1.8 s, + 4 @3 s from 14 s; 4 night-gaunts @4 s from 4 s, + 4 @4 s from 20 s | 11 s -> 32 s |
| 5 | 1 shoggoth; 6 cultists @1 s from 1 s | 1 shoggoth; 16 cultists @2 s from 1 s; 6 hybrids @4 s from 10 s; 2 packs @10 s from 20 s; 3 night-gaunts @5 s from 15 s | 6 s -> 31 s |

Reasons: a 20-32 s spawn window outlasts the 15 s Whispers fake interval, so fakes now spawn in
Whispers and Fraying waves; the extra enemies keep the per-second pressure of the stretched waves
near the old one. Wave 1's first group (8 cultists @1.2 s), wave 4's first group (6 hybrids @1.8 s) and wave 2's
Deep One at 8 s stay as the tests pin them (`config_valid_test`, and the text fixtures of
`config_reject_test`, which also need `"count": 8` to occur once in `waves.json`). This deviates from GDD §8's wave table (counts are higher); the GDD is not
edited here.

### Final bot table (committed data)

Run on the committed `data/`: `real 76.10 user 70.19 sys 0.93`, `uptime` before:
`load averages: 11.63 93.98 109.45`. Full suite after the change: 408 test cases, 0 failures
(`real 34.30 user 25.40 sys 5.26`).

| Strategy | Win rate | Mean waves cleared | Lighthouse HP left (of 20) | Mean final gold | Fakes / run | Astray / run | Missed / run | Shots / run | Lucid / Whispers / Fraying / Madness | Seconds / run |
|---|---|---|---|---|---|---|---|---|---|---|
| mundane | 10/10 | 5.0 | 20.0 | 143 | 0 | 0 | 0 | 987 | 100 / 0 / 0 / 0 % | 227 |
| occult | 10/10 | 5.0 | 10.8 | 189 | 11.7 | 22.0 | 71.1 | 697 | 51 / 10 / 15 / 24 % | 305 |
| madness | 10/10 | 5.0 | 8.6 | 262 | 12.4 | 86.4 | 0 | 136 | 32 / 16 / 6 / 46 % | 316 |

Mean sanity at each wave end:

| Strategy | W1 | W2 | W3 | W4 | W5 |
|---|---|---|---|---|---|
| mundane | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| occult | 100.0 | 86.0 | 38.8 | 0.0 | 0.0 |
| madness | 84.0 | 52.0 | 0.0 | 0.0 | 0.0 |

### Targets

- **Waves spawn for ~20-40 s: met** (19.5-32 s).
- **Fakes in Whispers/Fraying waves: met** (0 -> ~12 fakes per occult or madness run; the
  mundane bot never leaves Lucid, so it sees none).
- **Deliberate madness ends worse than occult: met** for HP (8.6 vs 10.8; baseline 13 vs 13),
  **but it still wins 10/10 (target "loses most runs": missed)**.
- **Mundane wins but loses some HP: missed** (20/20 in every variant tried).
- **Occult wins cleaner than mundane: missed** (occult leaks ~9 HP; mundane none).

### Variants tried and not kept

Rows from iterations 2-4 ran on slightly different bases (iteration 1's waves, or the final waves
with rifleman 8 and Elder Sign x1.5); the effects are the direction, not exact deltas.

| Change on top of the stretched waves | Effect (vs the final table) | Why not kept |
|---|---|---|
| Rifleman L1 damage 10 -> 8 / 7 / 6, Harpooner L1 18 -> 15 / 14 | mundane still 20/20 HP (29-31 towers overkill every wave) | no effect on the target; weakens the occult bot's riflemen |
| Rifleman 5, Harpooner 12 | mundane 15 HP (the shoggoth's armor 5 cancels the rifleman), occult bot 0/10 | an armor wall, not a balance; kills the occult bot |
| Necronomicon Reader L1 damage 40 -> 30, Elder Sign x1.5 | occult bot 1/10 (only 1 rifleman before collapse) | breaks the occult strategy |
| Elder Sign damage taken x1.25 -> x1.5 (with rifleman 8) | madness bot 13.1 HP, better than occult 8.0 | rewards the madness bot |
| Reader sanity per cast 2 -> 1 | occult reaches Madness only in wave 5 (7% of time), madness bot 15.8 HP | madness bot gets stronger; GDD value |
| Madness fake interval 6 -> 3 | ~2x fakes for the madness bot, HP unchanged | fakes cost occult AoE nothing (blast hits reals around a fake) |
| 2 shoggoths in wave 5, +gaunts/cultists | mundane still 20/20; horror only dips its sanity to ~90 | no effect on the targets |
| Madness damage x2 -> x1.25 (**pinned**, measurement only) | madness bot 9/10, 4.3 HP | needs an owner decision |
| Madness damage x2 -> x1.0 (**pinned**, measurement only) | madness bot 6/10, 2.0 HP | needs an owner decision |

### Harness fix

`tools/bot_runs.gd` read the raw fake flag of `SimEnemy`, which `render_isolation_test` forbids
outside `sim/` (the baseline commit left that test failing). It now sets
`debug_reveal_fakes = OS.is_debug_build()` and counts fakes through `sim.debug_is_fake()`; it
also takes `--data=<dir>` to run a config copy.

### Why two targets are out of reach in config alone

- **Madness:** the GDD's madness is a net damage buff for occult towers (x2 damage, 60% of shots
  on a real enemy = x1.2; AoE centred on a fake still hits real enemies around it), and its other
  penalties (15% miss, fakes drawing fire) hit only mundane towers, which a deliberate-madness
  build does not own. Making it lose most runs needs a pinned value changed (`damage_multiplier`,
  `shot_split`) or a rule change; even x1.0 loses only 4/10.
- **Mundane HP loss / occult cleaner:** a greedy mundane build places ~30 L1 towers along a
  40-cell route and nothing leaks; the occult builds own fewer, shorter-range towers and leak
  ~9-12 HP. Weakening mundane L1 enough to leak only works through the shoggoth's armor and
  breaks the occult bot first. The pinned economy (200 start, 50+10n, rewards) sets the tower
  count; L2/L3 upgrades are not in the sim, so the bots cannot spend differently.
