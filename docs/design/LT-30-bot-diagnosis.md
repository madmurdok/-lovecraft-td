# LT-30 S8 — why the beam/flare lower the bot win rate (diagnosis)

Inputs: the S7 measure (20 seeds x 4 strategies per arm, seeds 1000-1019) and a probe copy
of `tools/bot_runs.gd` (two extra flags: `--lhfix=1` described below, `--strats=`; plus
`tw_per_wave`). The probe re-ran the `on` arm and reproduced S7 exactly (37/80, mundane
3/20, seed 1000 lost with lh 2), so the sim is deterministic across runs. Data variants
change one key of `data/economy.json` each. Timing: every run had `user` ≈ 96% of `real`
(e.g. `on` 379 s real / 363 s user, load 6.3-8.6), so runs were CPU-bound, not waiting.

## Results (won / 20 per strategy)

| arm | change vs `on` | mundane | occult | mixed | madness |
|---|---|---|---|---|---|
| on | — | 3 | 14 | 7 | 13 |
| on_fix | bot: a refused lighthouse buy no longer ends the day's purchases | 10 | 14 | 7 | 13 |
| noupg | `--lighthouse=0` | **20** | 14 | 17 | 8 |
| none | `--lighthouse=0 --flare=0` | 20 | 20 | 20 | 5 |
| mund1 | mundane `fire_interval_mult` 1.0, `ignore_miss` false | 3 | — | 6 | — |
| pm1 | occult `power_mult` 1.0 | — | 19 | 17 | — |
| oil1 | oil `price` 10 → 1 | — | **20** | **20** | — |
| w1 | flare `width_mult` 1.0 | — | 14 | 11 | — |
| slow1 | flare `enemy_speed_mult` 1.0 | — | 7 | 15 | — |
| hold0 | flare `hold_beams` false | — | 2 | 7 | — |
| cancel0 | `cancel_madness_buff` false | — | 14 | 7 | 12 |
| noflare | `--flare=0` | 8 | 20 | 20 | 8 |

## Q1 — beam-off still has lit_shots ≈ 100 and ≈ 8 flares

**Not mis-invoked; the arm matches §3.4. The §3.4 check line is wrong.** `--data=boff`
differs from `data/` only in the six keys §3.4 lists (diffed with `json.tool`). §3.4 says
"same purchases, oil included", so the bot still buys oil and fires flares. Missed shots
rose from 2.1 to 3.7, so the override was applied. `lit_shots` measures geometry: it
counts shots by a tower inside a beam whether or not any modifier applies (the
`--lighthouse=0 --flare=0` arm still has 72). The line "flares > 0 only in on"
contradicts the arm's own definition. In beam-off the flare still costs oil (≈142 gold
per run) and still holds the beams (`hold_beams` is not neutralised).
What beam-off does measure: the lit modifiers when spending is the same. Beam-off beats on
(66% vs 46%) only through occult/mixed, where the 0.7 nerf goes away.
A "beam has no effect at all" arm is `none` plus neutral multipliers. Its cheap check is
"`missed` differs from on", not `lit_shots` or `flares`. **Doc fix (bug):** correct the
§3.4 check line and describe `lit_shots` as a geometric count.

## Q2 — why the upgrades and the flare lower the win rate

Sim defects ruled out:
- **Lit mundane modifiers.** The code applies `interval *= 0.8` at the shot and skips the
  miss roll (`_fire_towers`). mund1 (both off) gives mundane 3/20, the same as `on`, so they
  neither help nor hurt. They are worth almost nothing. The mundane bot stays lucid, so
  `missed` is 0 in every mundane run and `ignore_miss` has nothing to cancel. A tower is
  lit only for the share of the circle the beams cover: 2·atan(0.245) = 27.5° per beam, so
  7.6% / 15.3% / 30.6% of the time at 1/2/4 beams. That makes the average fire-rate gain
  +1.9% / +3.8% / +7.7%.
- **Flare side effects.** w1 changes nothing. slow1 and hold0 make occult worse (7, 2), so
  the slow and the hold help. cancel0 changes almost nothing (madness 13 → 12).

**Cause 1 (mundane): the bot buys the lighthouse before it builds towers. This is bot
policy, partly a bug.** Mundane L3 branches all have pending effects, so `_next_upgrade`
returns [] once every tower is L2. From then on `_lighthouse_next` is true ("or no tower
upgrade is left"), and the purchase loop puts the lighthouse ahead of every build.
- When the lighthouse is unaffordable, `upgrade_lighthouse()` is refused and the loop
  `break`s, so the bot builds nothing while it saves 120, then 250.
- Seed 1000: towers at wave ends are `on` [3, 5, 5] (lost in wave 4, 11 hp) and `noupg`
  [3, 5, 5, 8, 14] (won).
- Across 17 losing `on` runs the bot stays at 5 towers (4 rifle + 1 harpoon, all L2) with
  lh 1-2.
- The 370 gold of lighthouse is the price of about 7 riflemen, and buys a +7.7% fire rate
  at most.

Controls:
- `--lighthouse=0` alone flips mundane 3 → 20.
- on_fix, where a refused lighthouse buy lets the bot build, gives 3 → 10. Seed 1000
  stays lost because the lighthouse is affordable at that point and still outranks the
  builds.

**Cause 2 (occult, mixed): the LT-30 costs and the 0.7 nerf push near-limit economies
over the edge. This is balance.**
- oil1 (oil almost free, nothing else changed) flips occult 14 → 20 and mixed 7 → 20.
  The bot spends ≈140 gold per run on oil.
- pm1 also flips occult 14 → 19 and mixed 7 → 17. More beams light more occult towers
  at 0.7: noupg brings mixed to 17 by itself.
- Either change alone is enough, so these strategies sit at the margin.

**Madness** gains from the beam (none 5 → on 13). cancel0 does not explain the gain; the
flare's slow is the likely reason (not isolated).

## Fix proposal

**Bug, fix without asking:**
1. In `tools/bot_runs.gd`, fix the purchase order. Build when the next build is
   affordable. Buy the lighthouse only after the tower count reaches its target, or only
   when gold ≥ its cost + the next build. A refused lighthouse buy must fall through to
   builds, not `break`. on_fix already shows the fall-through alone is worth +7 mundane
   wins.
2. Correct the §3.4 check line and the `lit_shots` wording in
   `docs/design/LT-30-beam-addendum.md`.

**Balance, owner decides:** re-measure first with the fixed bot, then choose among:
- **(a) Make lighthouse levels worth their price:** cut the costs 120/250 (for example to
  60/120), or raise the mundane `fire_interval_mult` (0.8 gives only +1.9-7.7% on
  average). Benefit: the upgrade becomes a real choice. Risk: the beam may outclass towers
  for mundane builds.
- **(b) Make oil cheaper:** price 10 → 5, or start stock 2 → 4. Benefit: oil1 showed oil
  cost is the occult/mixed loss. Risk: flares get spammed, and madness, which gains from
  the flare, gets stronger.
- **(c) Soften the occult nerf:** `power_mult` 0.7 → 0.85. Benefit: keeps the
  light-vs-occult theme at lower cost. Risk: the beam's trade-off for occult builds gets
  weaker.
- **(d) Keep the numbers and treat the drops as the intended cost of LT-30.** Risk: the
  mundane and occult bots keep losing about a third more runs.

Throwaway probe and outputs: the scratchpad `lt30d/` folder (`zz_probe_lt30d.gd`,
`run.sh`, `run2.sh`, `agg.py`, `*.log`). The probe was removed from the worktree.
