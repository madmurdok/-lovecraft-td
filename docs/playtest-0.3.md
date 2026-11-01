# Playtest 0.3

## Difficulty pass (LT-45)

Owner, playtest 0.2.1: "Всё ещё довольно легко, но напряжение появляется". Target: "Нам нужно чтобы
боты проигрывали не меньше 10 партий из 20", i.e. every bot strategy loses at least 10 of 20 runs
(flare on, the bot default). Tool: the LT-56 balance lab (`tools/balance/balance.py`), seeds
1000.., upgrades on. Each cell is `wins/losses`. Search variants were lab patches; only the final
pair was written to `data/` (checked: the committed `data/` equals the lab's patched copy of the
final variant, file by file).

### Baseline (20 seeds, release ccf8dea, same sim as 834a1c4)

| flare | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle |
|---|---|---|---|---|---|---|---|---|---|
| on | 10/10 | 20/0 | 20/0 | 15/5 | 14/6 | 2/18 | 0/20 | 0/20 | 0/20 |
| off | 20/0 | 20/0 | 20/0 | 8/12 | 20/0 | 5/15 | 1/19 | 0/20 | 1/19 |

What the baseline logs showed:

- Sanity drops only through tower reserves (the cap) and horror, and only the Shoggoth has
  horror (`horror_drain` 0.5/s within 3 cells of a tower). So the occult bot sits at cap 36-48 with
  sanity 21-31 at worst, and loses HP only in wave 1 (won runs end at 16.8 HP of 20).
- For the madness bot MADNESS is a cliff: every run that reaches it (wave 5) loses or ends at 1-2 HP;
  every run that stays at cap 30 wins at 20 HP.
- mixed (cap 76-86) and demolition lose HP in waves 3-5 (hybrids, the Shoggoth wave) but win.
- resonator, gate and circle die in waves 2-3; nothing in waves 4-5 changes them.

So two levers are needed: one for the occult side (sanity) and one for the mundane side (late waves).

### Steps

Rounds 1-3: 10 seeds (1000-1009), strategies mundane, occult, mixed, madness, demolition, 6 jobs.
The 10-seed baseline subset is mundane 6/4, occult 10/0, mixed 10/0, madness 7/3, demolition 8/2.

| round | variant | mundane | occult | mixed | madness | demolition | why / reading |
|---|---|---|---|---|---|---|---|
| 1 | Shoggoth horror_drain 1.5 | 6/4 | 8/2 | 10/0 | 6/4 | 8/2 | sanity lever, mild: occult and madness enter MADNESS late in wave 5, still win |
| 1 | horror_drain 3.0 | 3/7 | 4/6 | 0/10 | 4/6 | 6/4 | occult/mixed/madness reach MADNESS in all runs; demolition untouched |
| 1 | hybrid/deep_one/night_gaunt hp x1.25 | 0/10 | 6/4 | 2/8 | 5/5 | 1/9 | wave 3 becomes the wall; mundane collapses, occult barely moves |
| 1 | relic prices x0.8 | 1/9 | 6/4 | 3/7 | 9/1 | 1/9 | less gold means fewer occult towers, so the madness bot gets easier |
| 1 | wave 5 counts x1.3 | 1/9 | 10/0 | 10/0 | 6/4 | 7/3 | the AoE occult bots eat bigger crowds |
| 2 | drain 3.0 + hybrid/deep/gaunt hp x1.1 | 1/9 | 1/9 | 1/9 | 3/7 | 3/7 | 5/5 met, three values changed |
| 2 | drain 2.5 + hp x1.1 | 1/9 | 2/8 | 1/9 | 6/4 | 4/6 | |
| 2 | drain 3.0 + relic prices ~x0.9 | 1/9 | 4/6 | 0/10 | 6/4 | 3/7 | economy again helps the madness bot |
| 2 | drain 3.0 + hybrid hp 240 | 1/9 | 2/8 | 0/10 | 3/7 | 4/6 | 5/5 met with two values; hybrids alone carry demolition |
| 3 | drain 2.0 + hybrid 240 | 1/9 | 7/3 | 9/1 | 6/4 | 4/6 | mixed stays out of MADNESS (min sanity ~7) |
| 3 | drain 2.0 + hybrid 225 | 2/8 | 8/2 | 10/0 | 7/3 | 7/3 | |
| 3 | drain 3.0 + hybrid 225 | 2/8 | 3/7 | 0/10 | 5/5 | 4/6 | |
| 3 | **drain 2.5 + hybrid 240** | 1/9 | 2/8 | 2/8 | 4/6 | 4/6 | mildest pair meeting 5/5 without zeroing mixed |

mixed has a cliff between drain 2.0 (no MADNESS, 9-10 wins of 10) and 2.5 (MADNESS in wave 5).
Every hybrid bump moves mundane from 6/4 to 1-2 wins of 10: it loses in wave 4 (20 hybrids).

### Final values (data/enemies.json)

| value | was | now | effect |
|---|---|---|---|
| shoggoth `horror_drain` | 0.5 | 2.5 | the Shoggoth near the towers costs 2.5 sanity/s; a slow kill drives an occult board into MADNESS in wave 5 |
| hybrid `hp` | 210 | 240 | waves 3-5 (12 / 20 / 18 hybrids) need more damage; armour 2 unchanged |

Both are levers a human feels too: the finale becomes a race to kill or hold the Shoggoth away
from the towers, and the hybrid waves need more damage.

### Final table (20 seeds x 9 strategies, data/ as committed)

| flare | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle | met |
|---|---|---|---|---|---|---|---|---|---|---|
| on (default) | 2/18 | 5/15 | 4/16 | 7/13 | 7/13 | 0/20 | 0/20 | 0/20 | 0/20 | 9/9 |
| off | 10/10 | 2/18 | 11/9 | 0/20 | 15/5 | 3/17 | 0/20 | 0/20 | 0/20 | 7/9 |

Fallback measured in the same run: drain 3.0 + hybrid 240, flare on: 2/18, 4/16, 0/20, 6/14,
6/14, 0/20 x4 (9/9). Rejected: mixed 0/20.

Where runs are lost (flare on): mundane wave 4 (16 of 18), occult and madness wave 5 (all runs
reach MADNESS), mixed wave 5 (18 of 20 reach MADNESS), demolition waves 4-5, battery waves 3-5,
resonator/gate/circle wave 3.

Trade-offs:

- mundane drops from 10/20 to 2/20 wins. It already met the target; any hybrid increase large enough
  for demolition hits it the same way (they share rifleman, rifleman, X). It still wins sometimes.
- battery goes from 2/20 to 0/20, so all four single-tower bots after battery are now 0/20.
- With the flare off, mixed (11/9) and demolition (15/5) still miss the target: the flare's oil
  (about 160 gold a run) buys these bots fewer towers than it saves them. Flare off is not the bot
  default, so it is not the target; noted for a later flare/oil pass.

### Machine state

| run | uptime at start (load avg) | uptime at end | /usr/bin/time -p |
|---|---|---|---|
| round 1 (5 variants x 5 x 10) | 51.65 35.41 40.87 | 164.98 153.61 113.81 | real 688.80 user 2140.81 sys 21.48 |
| round 2 (4 x 5 x 10) | 131.95 145.43 112.79 | 109.19 149.83 135.40 | real 619.62 user 1679.04 sys 16.33 |
| round 3 (4 x 5 x 10) | 68.76 136.16 130.95 | 24.21 70.82 102.40 | real 310.95 user 1519.09 sys 11.40 |
| final (3 x 9 x 20) | 15.67 64.29 98.94 | 11.41 25.61 60.89 | real 562.90 user 2938.10 sys 18.26 |

8 cores, 6 Godot processes at a time. Outcomes are deterministic per seed; timings are not
comparable between rounds (round 1-2 under heavy outside load, user/real 0.40-0.58 per process;
final 0.88-0.94).

### Tests

`tests/config_valid_test.gd` pins the Shoggoth's horror_drain (now 2.5); hybrid hp is read from the
raw JSON. Run: the config tests, `wave_director`, `bot_upgrade`, `sanity`, `madness_buff`,
`madness`, `sim_damage`, `sim_outcome`, `sim_determinism`, `hallucination` and the eight per-tower
config tests: 20 files, 353 cases, 0 failures (real 66.01, user 57.14). No full suite.
