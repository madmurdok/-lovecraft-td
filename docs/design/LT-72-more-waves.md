# LT-72: more waves (design note)

Source: owner, playtest 0.4 run 2 (`docs/playtest-0.4.md`, LT-60): "В целом баланс норм, правда
волн стоит делать побольше". GDD §1 already plans 10 waves (wave 10 = Dagon), §8 lists waves 6-10
as the post-MVP plan. Today `data/waves.json` has 5 waves; after LT-71 (candidate A, 40 seeds)
bots lose 370 of 400 runs, 255 of them in wave 4.

## 1. What limits the wave count today

Grep: `grep -rnE 'waves\.size\(\)|waves_total|wave_index|from_wave|waves_survived' sim scripts ui io tools tests scenes data`.

**Data only; no code assumes 5.** Every site reads the count from the config:

| site | what it does with the count |
|---|---|
| `sim/core/wave_director.gd:36, :67-71` | `waves_total = waves.size()`; DONE/WON after the last wave clears |
| `sim/core/systems/spawn_system.gd:138` | per-wave `hp_mult`/`speed_mult` for `1 <= wave_index <= size` |
| `sim/core/systems/economy_system.gd:121` | dawn wage `50 + 10 x n`, linear, no per-wave table |
| `sim/core/systems/sanity_system.gd:148` | +12 sanity every dawn, flat |
| `sim/core/hallucination_system.gd:28` | per-wave fake counter, keyed by `wave_index` |
| `ui/hud.gd:406-409`, `ui/end_screen.gd:34-37` | "Night n of N", "All N nights survived" |
| `tools/bot_runs.gd:297` | bot run cap = 6 min x wave count |

Relics drop per kill with per-night luck; nothing depends on the count. Day/night = BUILD/WAVE,
one pair per wave.

Not a limit, but changes meaning with more waves:

- **Lab "early" rule** (`tools/balance/balance.py:281-282`): early = first half of `nwaves`, and
  `nwaves` is the **highest wave any run reached**, not the config's count. With 10 waves and
  every run dead by wave 7, early = 1..4, not 1..5. The LT-68 two-part target moves with it (Q3).
- **Night-gaunt `tower_lift` "from_wave 6"** (`data/enemies.json:30`, GDD §7): the trait is
  pending (`tower_lift_trait.gd`, no hook), so wave 6+ will not activate it. Separate content task.
- **Dagon** (GDD wave 10) is not in the roster; a finale must use the shoggoth.
- HP caps (banish 4000, pull 500) compare base HP (LT-111 Q1), so `hp_mult` on a shoggoth does
  not switch banish off.

## 2. Pacing sanity table (from data, not the lab)

Proxy: wave HP (x `hp_mult`) / gold earned before the wave (start 300 + dawn wages + expected
relic value of all earlier kills; towers persist, so this is HP per gold invested). Deep One
pack = 5 (4-6). Ignores armor, regen (pending), speed, leaks, flyers, build-cell limits.
Computed by a one-off script (not committed).

Today: wave 1..5 = 2.4, 4.9, 5.5, **8.4**, **11.6**. The jump at wave 4 (x1.5) is the wall the bots
die on. Expected relic value per kill: cultist $5.2, Deep One $7.7, hybrid $9.9, night-gaunt
$14.7, shoggoth $50.2. Income grows with enemy count, so adding enemies alone keeps the ratio flat
(wave 9 of a 10-wave list earns ~3x the gold wave 5 earns today). **`hp_mult` is the only knob
that adds difficulty without adding income**; that is why late waves below lean on it.

## 3. Options

### A. Append the GDD plan (10 waves, 1-5 untouched)

Waves 6-10 from GDD §8: 6 = 3 packs + 5 gaunts; 7 = 2 shoggoths + 8 hybrids; 8 = dense mix;
9 = 3 shoggoths + 6 gaunts + 3 packs; 10 = boss stand-in (wave-5 roster, `hp_mult` 3.2).
Ratio 6..10 = 1.2, 3.4, 7.0 (`hp_mult` 1.4), 6.5 (1.9), 11.6 (3.2).

- Benefits: LT-71 numbers kept as shipped; matches the GDD text; the smallest diff to waves 1-5 (none).
- Risks: the wave-4/5 wall stays, so bots still die in wave 4-5 and the lab **cannot see waves
  6-10** (it would need a lighthouse-HP probe); after wave 5 the curve collapses (6 and 7 are
  far easier than 5), a mid-game boss then a lull; finale needs `hp_mult` 3.2.

### B. Re-paced 10 waves (recommended)

Waves 1-3 kept (LT-68/71 tuned). A lighter wave 4 is inserted, today's wave 4 becomes 5, the
ratio then rises ~+0.9 per wave to today's wave-5 ratio at the finale. Shoggoth first at 7,
two at 10.

| wave | groups: type count / interval / delay | hp_mult | speed_mult | HP | ratio |
|---|---|---|---|---|---|
| 1-3 | today's waves 1-3, verbatim | - | - | 720 / 2070 / 3465 | 2.4 / 4.9 / 5.5 |
| 4 | hybrid 12 / 2.5 / 0; night_gaunt 10 / 4 / 6 | - | - | 4530 | 5.1 |
| 5 | today's wave 4, verbatim | - | - | 7440 | 6.0 |
| 6 | cultist 30 / 1.5 / 0; deep_one 5 / 8 / 4; hybrid 14 / 3 / 6 | 1.6 | 1.1 | 13.7k | 7.7 |
| 7 | shoggoth 1 / 0 / 0; cultist 30 / 2 / 1; hybrid 16 / 3.5 / 8; night_gaunt 8 / 5 / 12 | 1.85 | - | 19.5k | 8.2 |
| 8 | hybrid 28 / 2 / 0; night_gaunt 22 / 3 / 4; deep_one 5 / 8 / 10 | 2.0 | - | 27.5k | 9.2 |
| 9 | today's wave 5 groups, verbatim | 2.4 | - | 39.3k | 10.1 |
| 10 | today's wave 5 groups with shoggoth count 2 / interval 30, night_gaunt count 16 | 2.7 | - | 56.6k | 11.6 |

- Benefits: one monotone ramp, no lull, no early wall; bots reach waves 5-8, so the lab measures
  the new waves directly; reuses LT-71 compositions; matches GDD's 10-wave count.
- Risks: today's wave 4 moves to 5, so the LT-71 "lose >= 10/20" result must be re-measured
  (fewer early deaths may drop the loss count); `hp_mult` 2-2.7 makes late enemies sponges
  (hybrid 650 HP): may feel grindy, and the proxy ignores build-cell limits (late gold may have
  nowhere to go, making 8-10 harder than the ratio says); a run roughly doubles in length (10 build phases of 40 s plus longer nights).

### C. Re-paced 7 waves (smaller step)

Waves 1-5 as in B; 6 = B's wave 7 (`hp_mult` 1.4); 7 = today's wave 5 (`hp_mult` 1.7). Ratio
2.4, 4.9, 5.5, 5.1, 6.0, 8.3, 11.6.

- Benefits: fewer new numbers to tune; run ~1.4x today's; same early-wall fix as B.
- Risks: still short of the GDD's 10; the owner may ask for more again; jump 6 -> 7 is x1.4.

## 4. Recommendation

**B.** It answers "more waves" with the GDD's count and turns the wave-4 wall into a ramp, which
is also what lets the lab see the new waves at all. The numbers above are starting points for
the lab; the owner picks the shipped ones.

## 5. Lab plan (measure slice)

The lab can run a whole wave list without touching `data/`: a patch value that is an array
replaces the array (`apply_patch`, `_check_type` list vs list), so
`"waves.json": {"waves": [ ...10 wave objects... ]}` works, `hp_mult`/`speed_mult` included.
Run `--check` first, then `--seeds=2` to see it runs.

Variants (`tools/balance/variants/`, committed with the measure slice):

| variant | content |
|---|---|
| `baseline` | today's 5 waves (re-run in the same session) |
| `lt72_b` | option B list (table above) |
| `lt72_b_late_x2` | B with `hp_mult` of waves 6-10 x2 (3.2, 3.7, 4.0, 4.8, 5.4) |
| `lt72_b_late_d2` | B with `hp_mult` of waves 6-10 /2 (0.8, 0.93, 1.0, 1.2, 1.35) |

Key knob = the late `hp_mult` ramp (the one difficulty lever that does not add income). Then
bisect between the "too weak" and "too strong" arms toward the target, 2-3 steps.
Command: `python3 tools/balance/balance.py baseline lt72_b lt72_b_late_x2 lt72_b_late_d2
--seeds=20 --jobs=6`, all 10 strategies, flare on, one background run; record `uptime` and
`/usr/bin/time -p`. Expect ~1.5-2 h (longer runs than LT-71's 1291 s for two 5-wave arms).

Metrics: losses of 20 (target >= 10), "Where runs end" (losses per wave, mean waves survived:
the non-saturating one), lighthouse HP left (separates only all-won arms), and from the logs
`hp_lost_per_wave` summed per wave (which waves leak). Because of §1 (early inferred from
runs), also state early-ok by hand as "survived waves 1..5" from `waves_survived` if the
table's header shows `nwaves` < 10. Result table goes to `docs/playtest-0.4.md`, section
"More waves (LT-72)".

If >= 80% of `lt72_b` runs end before wave 6, add `lt72_b_probe` (lighthouse `hp` 80, x4) to
see waves 6-10 leak.

## 6. Tests and goldens that change

- `tests/roster_snapshot_test.gd:12` `WAVE_COUNT := 5` -> 10 (the one designated pin, LT-98).
- `tests/config_valid_test.gd` `test_waves` pins waves[0] and waves[1] group 1: unchanged under
  B/C (waves 1-3 kept); under any option that edits waves 1-2 it changes.
- Count-generic, no change: `strategy_table_test.gd:557-561` (local named `five`, rename only),
  `scene_game_test.gd:256`, `wave_director_test.gd:28`, `wave_mult_test.gd` (needs >= 4 waves;
  comment line 23 says "real data has 5 waves"), `bot_upgrade_test.gd:525`.
- Goldens: none. `tests/golden_runs.gd:20` replays the frozen `tests/fixtures/golden_data`, not
  `data/`. Lab unit tests use fakes.

## 7. Owner questions

1. **Which wave list?** *B, re-paced 10 waves (Recommended)* / A, append GDD 6-10 / C, re-paced 7.
2. **How hard is the finale?** *Same HP-per-gold as today's wave 5, ratio 11.6 (Recommended)* /
   harder (the lab's x2 arm) / easier, a victory lap (/2 arm).
3. **Lab target on a 10-wave list?** *Keep "lose >= 10 of 20" and early = first half, waves
   1..5 (Recommended)* / early fixed at waves 1..3 (as LT-68 measured it) / drop the loss target,
   judge by wave reached only.
4. **Wave-10 boss?** *Two shoggoths with `hp_mult` as a stand-in now, Dagon later (Recommended)* /
   hold LT-72 until a Dagon task exists.

Note, no question: night-gaunt `tower_lift` (from wave 6) stays pending; a 10-wave list makes it
reachable, so a content task for it is worth filing.

## 8. Edit map (data slice, after the owner picks numbers)

1. `data/waves.json`: replace `waves` with the chosen list (the measure slice's winning variant
   array, verbatim); `build_phase_seconds` unchanged.
2. `tests/roster_snapshot_test.gd:12`: `WAVE_COUNT := 10` (or the chosen count).
3. `tests/strategy_table_test.gd:560-561`: rename `five` -> `n` (cosmetic, optional).
4. `tests/wave_mult_test.gd:23`: comment "(the real data has 5 waves)" -> "(the real data's waves)".
5. `docs/GDD.md` §8 (lines 205-221): table = shipped list; drop "waves 6-10 are the post-MVP
   plan"; note the wave-10 stand-in. §8 rows 1-3 are stale already (wave 3 is 3 packs + 6
   hybrids): fix with it.
6. `tools/balance/README.md`: "(30 for 5 waves)" and "waves 1..3 of 5" -> the new count;
   `tools/balance/balance.py:282` comment "5 waves -> the first 3".
7. Run `scripts/test.sh tests/roster_snapshot_test.gd tests/config_valid_test.gd
   tests/strategy_table_test.gd tests/wave_mult_test.gd`; the full suite is the verify slice's.

## 9. Owner decisions (2026-11-21)

1. Wave list: "B: 10 волн с новым темпом (Recommended)".
2. Finale: "Как сегодняшняя волна 5 (Recommended)".
3. Lab target: "≥10/20 поражений, ранние = 1..5 (Recommended)".
4. Wave-10 boss: "Два шоггота + hp_mult, Дагон потом (Recommended)".
