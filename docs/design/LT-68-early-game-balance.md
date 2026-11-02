# LT-68: early-game balance after staggered packs

Status: proposal (S1, diagnosis + lab measurements). No `data/` change is made here.

## Problem

Owner: "сложно тестить маяк и другие штуки, потому что с текущим уровнем сложности - тупо не
успеваешь развиться и что-то крутое построить."

The game has 5 waves (nights). The current difficulty target (LT-45, `docs/playtest-0.3.md`) is
"every bot strategy loses at least 10 of 20 runs, flare on". It counts only *whether* a run is
lost, not *when*. LT-63 (`pack.spacing_s` 0.5: Deep One packs enter one by one) made every
strategy lose more (`docs/playtest-0.4.md`): with the flare on, 170 of 180 bot runs now end in
a loss. The target is still met, but it no longer tells us whether a player gets
to see the mid game (lighthouse upgrades, L3 towers, wave 4-5 enemies). That is what the owner is
missing.

## Diagnosis: where runs die

Tool: the balance lab (`tools/balance/balance.py`), which now also prints a "Where runs end"
table (added in this slice): losses per wave, wave 1..5. Seeds 1000..1019, all 9 bot strategies,
release-0.4.0 at 894bb72 (LT-63 included).

Baseline, flare on (the bot default), losses per wave summed over all 9 strategies (180 runs):

| wave 1 | wave 2 | wave 3 | wave 4 | wave 5 | won |
|---|---|---|---|---|---|
| 0 | 0 | **80** | 45 | 45 | 10 |

- **Wave 3 is the wall.** 80 of 180 runs (44%) end there; only 56% of runs ever see wave 4.
  Wave 3 is 6 Deep One packs (4-6 each, now entering one by one) plus 12 Innsmouth Hybrids
  (240 HP, armour 2), right after two easy waves.
- Who dies in wave 3: mundane 16/20, resonator 17, gate 20, circle 18, demolition 5, battery 4.
  occult, mixed and madness never die before wave 4; they lose late (Shoggoth, MADNESS).
- Waves 1-2 kill nobody in any variant. The early game is not "too many enemies at once"; it is
  "not enough built by wave 3".
- The lighthouse is a late purchase: in 123 of 180 baseline runs the bot never buys a
  lighthouse level (L2 costs 120, L3 250), because towers come first and gold is gone by wave 3.
- The flare costs money early: with the flare off, 73% of runs survive wave 3 (vs 56% with it
  on). Oil (10 gold per unit, 8 per flare) is bought from wave 2 on, competing with towers just
  before the wall.

## Candidates

Each candidate is a lab variant in `tools/balance/variants/` (`lt68_*`, `_nf` = flare off).
20 seeds x 9 strategies = 180 runs per row.

| variant | change | losses, flare on (of 180) | strategies meeting LT-45 (flare on) | died in waves 1..5 (flare on) | survived waves 1-3, on / off | runs that bought a lighthouse level |
|---|---|---|---|---|---|---|
| baseline | none | 170 | 9/9 | 0.0.80.45.45 | 56% / 73% | 57 (32%) |
| `lt68_gold300` | `starting_gold` 200 -> 300 | 161 | 9/9 | 0.0.52.61.48 | 71% / 97% | 68 (38%) |
| `lt68_bonus80` | `wave_bonus.base` 50 -> 80 | 169 | 9/9 | 0.0.53.35.81 | 71% / 82% | 96 (53%) |
| `lt68_w3soft` | wave 3: Deep One events 6 -> 4, Hybrids 12 -> 8 | 166 | 9/9 | 0.0.34.46.86 | 81% / 93% | 99 (55%) |
| **`lt68_gold300_w3soft`** | both of the first and third | **151** | **9/9** | **0.0.6.52.93** | **97% / 100%** | **119 (66%)** |

Per strategy, wins/losses of 20, flare on:

| variant | mundane | occult | mixed | madness | demolition | battery | resonator | gate | circle |
|---|---|---|---|---|---|---|---|---|---|
| baseline | 0/20 | 2/18 | 1/19 | 6/14 | 1/19 | 0/20 | 0/20 | 0/20 | 0/20 |
| lt68_gold300 | 3/17 | 7/13 | 2/18 | 2/18 | 3/17 | 2/18 | 0/20 | 0/20 | 0/20 |
| lt68_bonus80 | 2/18 | 1/19 | 1/19 | 2/18 | 4/16 | 1/19 | 0/20 | 0/20 | 0/20 |
| lt68_w3soft | 2/18 | 1/19 | 0/20 | 6/14 | 3/17 | 2/18 | 0/20 | 0/20 | 0/20 |
| lt68_gold300_w3soft | 2/18 | 9/11 | 1/19 | 10/10 | 4/16 | 2/18 | 1/19 | 0/20 | 0/20 |

Wave-3 losses per strategy for the recommended variant (flare on): all 0 except gate 6.

Reading:

- Each single lever moves only part of the wave-3 deaths into waves 4-5. More income at dawn
  (`bonus80`) mostly helps the late game (more lighthouse levels), not wave 3.
- Starting gold plus a lighter wave 3 together remove the wall: 97% of runs reach wave 4,
  two thirds of runs buy a lighthouse level, and the game is still lost 151 times of 180.
  Waves 4 and 5 now do the killing (52 and 93 losses), which is where the owner wants the
  difficulty.
- Flare off (not the bot default, not the target) gets easy with the recommended pair: mundane
  19/1, demolition 15/5, battery 11/9, occult 12/8 (5/9 strategies meet LT-45). Flare off
  is a bot that skips a whole mechanic; a human uses the flare.

## Recommendation

Apply `lt68_gold300_w3soft` to `data/`.

### Edit map

| file | key | old | new |
|---|---|---|---|
| `data/economy.json` | `starting_gold` | 200 | 300 |
| `data/waves.json` | `waves[2].groups[0].count` (wave 3, `deep_one`) | 6 | 4 |
| `data/waves.json` | `waves[2].groups[1].count` (wave 3, `hybrid`) | 12 | 8 |

Nothing else changes (intervals, delays, enemy stats, waves 1, 2, 4, 5). After the edit the
committed `data/` must equal the lab's patched copy of `lt68_gold300_w3soft` (check with
`balance.py lt68_gold300_w3soft --check` and a file diff), and the lab rerun on the new `data/`
(`baseline`, `flare_off`) must reproduce the row above.

### Proposed target (replaces LT-45)

> With the flare on (the bot default), at 20 seeds:
> 1. **Early game is survivable:** every strategy survives waves 1-3 in at least 15 of 20 runs.
> 2. **The game stays hard:** every strategy still loses at least 10 of 20 runs.

The recommended variant meets (2) for 9/9 strategies and (1) for 8/9: gate survives wave 3 in
14 of 20 (6 deaths), one run short. Gate is a test bot that builds only riflemen and Silver Key
Gates; it was the weakest bot before (20/20 wave-3 deaths at baseline). Baseline meets (1) for
5/9 strategies (occult, mixed, madness, demolition 5 wave-3 deaths, battery 4).

The lab reports both halves: the target column for (2), the `early ok` column and the per-wave
cells of "Where runs end" for (1).

## Risks and trade-offs

- **Wave 4 becomes the next cliff** for single-tower bots (mundane 7, resonator 17, gate 12,
  circle 15 deaths there). If the owner now hits wave 4 every time and dies, the next lever is
  wave 4 (20 Hybrids + 16 Night-gaunts), not more starting gold.
- **Bots are not players.** Bots call every wave at once, never sell, and build in a fixed
  order. A human who places better may find the change too easy; +100 starting gold is two extra
  riflemen (50 each), so it is small and easy to revert.
- **Flare-off bots become easy** (above). Acceptable while the flare is part of the intended play;
  if the flare-off row matters, keep a stricter target for it separately.
- **Two levers, not one.** Either alone leaves the wall at ~30% wave-3 deaths. A single-lever
  fallback is `lt68_w3soft` (81% survive waves 1-3, 166 losses, 9/9 LT-45).
- **Measurement:** one 20-seed run per variant (deterministic per seed; differences of 1-2 runs
  per cell are noise between variants that change loot). Machine was heavily loaded
  (load average 222 at start, 322 at end, `real 4920 s`, `user 14089 s`, `sys 204 s` for 10 variants
  x 9 strategies x 20 seeds, 8 Godot processes): timings are not comparable with earlier reports;
  outcomes are unaffected (the sim is tick-based).

## Open decisions for the owner

1. Adopt the recommended pair, a single lever (`lt68_w3soft`), or none?
2. Adopt the two-part target (survive waves 1-3 in >= 15/20; still lose >= 10/20)? Is gate's 14/20
   acceptable, or should the early target exclude the single-tower test bots?
3. Should the flare-off row keep its own target?

## Reproduce

```sh
godot --headless --import --path .   # once in a fresh checkout/worktree
python3 tools/balance/balance.py baseline flare_off lt68_gold300 lt68_gold300_nf lt68_bonus80 \
  lt68_bonus80_nf lt68_w3soft lt68_w3soft_nf lt68_gold300_w3soft lt68_gold300_w3soft_nf \
  --seeds=20 --jobs=8
```
