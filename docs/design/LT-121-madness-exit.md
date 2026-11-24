# LT-121: a way out of madness

Owner playtest: "Где-то после 5ой волны - ииграешь уже чисто в безумии, неясен механизм как
выкарабкаться из него". The owner confirmed the state was MADNESS. Owner decisions: exit rule
"B: восстановление с гистерезисом"; lab "Лаба: ×2 и ÷2 от 150 (Recommended)", read as ×2 / ÷2
variants of the exit parameters.

## 1. Today

**Entry.** `SanitySystem.sanity_state_for` (sim/core/systems/sanity_system.gd:163-174): MADNESS
iff sanity <= 0. There are two ways to reach 0, both through `SanitySystem.add` (:181-197):
- **Cap** (`change_reserve`, :134-150): cap = 100 minus every standing occult tower's
  `sanity_reserve` (L1 5-12, L2 8-20, L3 a 14-26, L3 b 30-45, data/towers.json). Sanity above
  the cap drops to it. A cap of 0 means madness.
- **Horror** (`horror_drain`, :204-224): only the shoggoth drains, 2.5/s while it is within 3
  cells of any tower. Shoggoths come in waves 7, 9 and 10 (two in wave 10). Speed 0.5 on a
  ~41-cell path is ~80 s of possible drain, so one shoggoth can drain far more than 100.

**Restore** (data/sanity.json `regen`): +12 per cleared wave (`award_wave_sanity`, :154) and
+0.5 per real kill by a mundane tower (combat_system.gd `_on_enemy_killed`, :141-151). Both are
limited by the cap.

**Why the player is stuck.** `add` latches MADNESS: only `MADNESS_EXIT_REASONS` (:10, "buyout",
"auto_restore") move sanity while mad, and `exit_rule` is "permanent", so neither fires. All
regen is thrown away, and the HUD shows no way out.

## 2. The rule: exit_rule "recover"

A new value in `SanityConfig.Madness.EXIT_RULES`, plus a new field `madness.exit_sanity`
(baseline **20**).

- **Enter:** unchanged: sanity <= 0 means MADNESS.
- **While mad (recover only):** `add` no longer drops changes. Every reason applies as usual:
  between_waves, mundane_kill, horror (a shoggoth undoes progress), reserve (the cap clamps)
  and debug. Sanity rises from 0, but the state stays MADNESS, with all its effects.
- **Exit:** the state leaves MADNESS on the first `add` that leaves sanity >= `exit_target()`.
  The new state is then `sanity_state_for(sanity)`: FRAYING at 20. The check runs in `add`,
  the only place sanity changes, so the exit can come mid-wave on a kill or at dawn on the
  regen.
- **Target:** `exit_target() = min(exit_sanity, sanity_cap)`. A cap below 20 lets the player
  out at the cap. At cap 0 there is no exit until an occult tower is sold.
- **Hysteresis:** entry is at 0 and exit at `exit_sanity`. After leaving, the player goes mad
  again only at 0, so the gap is the whole `exit_sanity`.
- **Other rules unchanged:** "permanent", "buyout" and "auto_restore" behave as today
  (`MADNESS_EXIT_REASONS` still gates them). Under "recover", `buyout_applies()` is false (no
  button), `auto_restore_sanity()` does nothing, and `restore_sanity` and `buyout_cost` are
  unused.
- **Config:** `exit_sanity` is an optional number with default 20, in the range (0, max];
  `<= 0` is rejected when exit_rule is "recover". It is optional so that
  tests/fixtures/golden_data/sanity.json (frozen, "permanent") still parses. data/sanity.json
  ships `"exit_rule": "recover", "exit_sanity": 20`.

**Arithmetic check (baseline 20).** Madness halves kills (enemies move ×1.7 and take ×0.37
damage), so assume mundane towers make 25-50 % of a wave's real kills. Real enemies per wave are
36, 49, 55, 55 for waves 5-8.
- Mixed build: 0.5 × (9..27) kills + 12 = **+16..+25 per wave**. A player who goes mad in wave
  5-6 is out by the dawn after the next wave, so wave 6-7.
- Occult-only build: +12 per dawn, out in **2 dawns**.
- Shoggoth waves (7, 9, 10): horror can take it back to 0, so recovery slips one wave.
- Cap < 20: out at the cap. Cap 0: never (needs a sell, which the HUD must say).
- At `exit_sanity` 40 (×2) the occult build needs 4 dawns, which is close to permanent. At 10
  (÷2) madness is about a one-night event.

## 3. HUD

- **Sanity bar** (ui/sanity_bar.gd): while MADNESS under "recover", draw an exit mark at
  `exit_target()/max`, in a distinct colour, next to the threshold ticks (`mark_ratios`
  :81-89, `_draw` :91-119). The label changes from "Sanity 7  Madness" to
  "Sanity 7 / 20 to recover" (`label_text` :72-78). This adds nothing to LT-120's tooltip; give
  LT-120 the new rule for its text.
- **Madness line** under the bar (ui/hud.gd `hostile_text` :409-422, shown by
  `_refresh_sanity` :317-325): a second line "Recover at 20 sanity: +12 each dawn, +0.5 per
  mundane kill". At cap 0 it reads "No room to recover: sell an occult tower". Both are built
  from config, never literals.
- Refresh: SANITY_CHANGED and SANITY_CAP_CHANGED already map to G_SANITY (hud.gd:72-74).
- Nothing goes in the bottom panel (LT-119's oil button).

## 4. Edit map

| file | function / place | change |
|---|---|---|
| sim/defs/sanity_config.gd | `Madness` (:85-136): `MADNESS_FIELDS` :90, `EXIT_RULES` :93, vars :100-103, `parse` :106-136 | add "recover", `exit_sanity` (`opt_number`, default 20) and its > 0 check |
| sim/core/systems/sanity_system.gd | `add` :181-197 | under recover skip the latch; the next state comes from `_next_state(old, s)` |
| same | new `exit_target()` next to `restore_target` :113-115; new `_next_state` next to `sanity_state_for` :163 | stay MADNESS while s < exit_target |
| sim/core/simulation.gd | forwarder next to `sanity_state_for` :714 | `exit_target()` for the UI and bot |
| data/sanity.json | `madness` | `"exit_rule": "recover", "exit_sanity": 20` |
| ui/sanity_bar.gd | `label_text` :72-78, `mark_ratios`/`_draw` :81-119 | exit mark and label |
| ui/hud.gd | `hostile_text` :409-422, `_refresh_sanity` :317-325 | recover line |
| tools/bot_runs.gd | loop :238-239, RUN dict :315-330 | `madness_entries`, `madness_exits` |
| tools/balance/balance.py | next to `hp_cell`/`hp_table` :347-377, `report` :379 | "Seconds in madness" table (mean/median of `seconds.madness`) |
| tests/config_valid_test.gd | `test_madness_rules` :288 | pin "recover" and 20 |
| tests/madness_test.gd | `test_regen_and_drain_change_nothing_in_madness` :399 and any test that reaches MADNESS without `_rule(...)` | pin `_rule(sim, "permanent")`: the shipped default changes |
| docs/GDD.md | §5 :145-150 | default rule "recover" |

Read for context: `change_reserve`, `auto_restore_sanity`, `buyout_applies` (sanity_system.gd);
`Simulation.on_dawn` :623; combat_system.gd `_on_enemy_killed`; madness_test.gd `_rule` :33.

## 5. Lab plan (later slice)

The arms below run at 20 seeds. Patches apply to `sanity.json` (the keys exist in data after
§4):

| variant | patch `{"sanity.json": ...}` |
|---|---|
| `baseline` | data as shipped: recover, exit_sanity 20 |
| `lt121_permanent` (control) | `{"madness": {"exit_rule": "permanent"}}` |
| `lt121_exit_x2` / `lt121_exit_d2` | `{"madness": {"exit_sanity": 40}}` / `10` |
| `lt121_dawn_x2` / `_d2` | `{"regen": {"between_waves": 24}}` / `6` |
| `lt121_kill_x2` / `_d2` | `{"regen": {"mundane_kill": 1.0}}` / `0.25` |

After the first round, bisect between too weak and too strong (2-3 steps). The regen arms
also change sane play, so the `mundane` row is their control and must not move much.

Metrics: losses of 20 (target: lose >= 10) and, because losses saturate, **seconds in madness
per run** (mean/median) plus `madness_exits`, the wave reached ("Where runs end") and lighthouse
HP left. Rows that matter: occult, mixed, madness, resonator, gate, circle.

## 6. Must confirm / tests

Must confirm:
- C1: horror drain while mad under recover. Proposed: it applies, so a shoggoth costs
  progress. The alternative is gains only, which is simpler to read.
- C2: the golden digests do not move, because the fixture is frozen at "permanent" and
  `exit_sanity` is optional. Check this before claiming it.
- C3: is the cap-0 dead end acceptable with a "sell an occult tower" hint?

Behaviours tests must pin:
1. Under recover, a mundane kill and the dawn regen raise sanity while the state stays MADNESS
   (SANITY_CHANGED is emitted, SANITY_STATE_CHANGED is not).
2. Sanity reaching exactly `exit_sanity` leaves MADNESS for `sanity_state_for(s)`. At
   `exit_sanity - ε` the state stays MADNESS.
3. After the exit, sanity going down to 1 is FRAYING, not MADNESS; only 0 re-enters.
4. Cap < exit_sanity: the exit happens at the cap. Cap 0: no exit. A sell then a regen exits.
5. Horror drain lowers sanity while mad, within [0, cap] (per C1).
6. The other rules are unchanged: permanent, buyout and auto_restore tests pinned explicitly.
   Under recover, no buyout button, `buy_sanity` returns NO_BUYOUT, and `auto_restore` does
   nothing.
7. Config: "recover" accepted; `exit_sanity` <= 0 or > max rejected; missing means 20.
8. HUD: the exit mark and the "/ 20 to recover" label only in MADNESS under recover; the cap-0
   hint.
9. Lab: `madness_exits` counts MADNESS -> other transitions; the table skips runs without
   `seconds`.
