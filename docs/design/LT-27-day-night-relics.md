# LT-27 — Day/night economy: relics drop at night, sold for money by day (design note)

Status: draft for owner review · 2026-10-31 · branch `feat/LT-27-day-night-relics`

Owner idea (verbatim): "учитывая то что у нас теперь валюта - реликвии, то имеет смысл сделать
2 фазы: день и ночь. Ночью - маяк работает и мы стреляем врагов, с них падают реликвии( разной
ценности ) а днем - у нас фаза когда мы продаем реликвии, получаем деньги и можем за них нанимать
стрелков/гарпунщиков и тп и тд - те это фаза строительства".

## 0. What exists today and what this task adds

**Today** (`release-0.2.0`): one currency, gold.

| Source / sink | Where | Rule |
|---|---|---|
| Start | `economy.starting_gold` | 200 |
| Kill | `Simulation._on_enemy_killed` → `_add_gold(e.def.reward, "kill")` | cultist 5, deep_one 8, hybrid 10, night_gaunt 15, shoggoth 60; fakes pay nothing |
| Wave bonus | `WaveDirector._clear_wave` → `award_wave_bonus(n)` | 50 + 10 × n |
| Early call | `call_wave` → `early_call_bonus()` | 2 × whole seconds left on the 25 s build timer |
| Sell tower | `sell_tower` → `sell_refund(t)` | `roundi(spent × 0.7)` |
| Build | `build_tower` | tower cost, any phase (also mid-wave, also paused) |
| Buyout | `buy_sanity` | `madness.buyout_cost` 150, any phase |

Phases (`wave_director.gd`): BUILD 25 s → WAVE n → BUILD → … → DONE. Every gold change goes
through `_add_gold` and emits `GOLD_CHANGED {delta, gold, reason}`. Gold income at
baseline for the 5 MVP waves (packs at their mean of 5): kills ≈ 60 + 140 + 360 + 440 + 565
= 1565, wave bonuses 400, start 200.

Playtest 0.1 finding 7: gold from kills has no lore; the owner named the loot Relics
(creature bones, fragments, amber). Lamp oil stays a future lighthouse resource (LT-26 §5).

**This task** splits the economy into two resources, tied to the two phases:

- **Night** = the wave phase. The lighthouse burns, towers fire, kills drop **relics** into
  the keeper's stash. Relics cannot be spent.
- **Day** = the build phase. Relics are **sold for money**; money buys towers, upgrades
  (LT-24), lighthouse levels (LT-26) and the madness buyout.

```
NIGHT (WAVE n)                      DAWN (WAVE_CLEARED)          DAY (BUILD)
kill → RELICS_CHANGED +1 amulet     fakes dissolve               sell_relics() → money
       (stash, not spendable)       wage (old wave bonus) → $    build / upgrade / sell towers
                                    sanity regen                 "Light the lamp" → night n+1
```

## 1. Relics

### 1.1 Kinds and values (Open question 1)

Recommended: **one relic kind per enemy, one piece per kill, price = today's reward.** The
economy totals stay exactly as today, so LT-23/S5 tunes from a known baseline; "different
value" is carried by the kind.

| Enemy | Relic (id) | Name shown | Price ($) | Lore line |
|---|---|---|---|---|
| Cultist of Dagon | `amulet` | Tarnished amulet | 5 | Cheap gold-plated tin with the sign of Dagon |
| Deep One | `scale` | Deep One scale | 8 | Iridescent, cold to the touch |
| Innsmouth Hybrid | `bone` | Hybrid bone | 10 | Neither man nor fish |
| Night-gaunt | `horn` | Night-gaunt horn | 15 | Curved, faintly warm |
| Shoggoth | `amber` | Shoggoth amber | 60 | Hardened protoplasm with something still moving inside |
| Dagon (post-MVP) | `idol` | Idol of the Deep | config | Boss relic, same rules |

Config (data, all tunable):

```jsonc
// data/economy.json
"relics": {
  "amulet": { "name": "Tarnished amulet", "price": 5 },
  "scale":  { "name": "Deep One scale",   "price": 8 },
  "bone":   { "name": "Hybrid bone",      "price": 10 },
  "horn":   { "name": "Night-gaunt horn", "price": 15 },
  "amber":  { "name": "Shoggoth amber",   "price": 60 }
}
// data/enemies.json: "reward": 5  →  "relic": "amulet"   (optional "relic_count", default 1)
```

Validation: at least one kind; `name` non-empty string; `price` int ≥ 0; every enemy's
`relic` names a known kind (cross-file check in `sim/config.gd`, same place waves' enemy
ids are checked); `relic_count` int ≥ 0. Kind order = config order (deterministic: sale
events, HUD rows).

### 1.2 Drop rules

- **Real kill at night:** `relic_count` pieces of `def.relic` go **straight into the
  stash** (`state.relics[kind] += n`) in the kill tick, through a new `_add_relics(kind, n,
  reason, id)` that emits `RELICS_CHANGED {kind, delta, count, reason}`. No map pickup
  (Open question 2).
- **Fakes** (LT-12): drop nothing, as they pay no gold today (Open question 3).
- **Leaks:** an enemy that reaches the lighthouse drops nothing (as today).
- **Pack enemies:** each Deep One of a pack is one kill, one scale.
- **Boss:** same rule; its kind and price are config. "Leaking = instant loss" ends the run
  before dawn, so a boss relic only counts when the boss is killed.
- **Multi-kill / two towers on one enemy:** one drop per enemy (`_on_enemy_killed` already
  runs once per enemy).
- **`DIED` data** `{source, reward}` becomes `{source, relic, relic_count}` from the def
  (identical for real and fake enemies, LT-12 §1 rule A).
- Relics carry over between days; unsold relics at the end of the run are worth nothing
  (end screen shows them for flavour).

### 1.3 Selling (Open question 4)

Recommended: **fixed price per kind, sold only by day, no limits.**

```
func relic_price(kind: String) -> int                ## config price; 0 for an unknown kind
func relics_value() -> int                           ## stash total at today's prices
func can_sell_relics(kind := "") -> CommandResult
func sell_relics(kind := "") -> CommandResult        ## "" = every kind
```

Checks, in this order: outcome set → `OUTCOME_REACHED`; `phase == WAVE` →
`NOT_BUILD_PHASE` (reused); unknown kind, or nothing to sell (that kind, or the whole stash
for `""`) → `NO_RELICS` (new, appended to `CommandResult`).

On OK: `command_log.append([tick, "sell_relics", kind])`; for each sold kind in config
order `RELICS_CHANGED {kind, delta: -n, count: 0, reason: "sell"}` then one
`GOLD_CHANGED {delta: Σ price × n, reason: "relic_sale"}`. A whole stack is sold; there is
no count argument (with fixed prices a partial sale changes nothing). The sim supports
per-kind sales; the 0.2 UI offers one "Sell relics" button (§4).

`phase == WAVE` rather than `!= BUILD` keeps sim unit tests without a WaveDirector
(phase NONE) working unchanged.

### 1.4 Market hook (not built)

`relic_price(kind)` is the single place a price is read. A later market (daily price roll,
or demand that drops as you sell one kind) replaces its body and adds config; no other code
changes. Not in 0.2 unless the owner picks it in Q4.

## 2. Money

**Name:** shown as **"$"** (1920s New England dollars): `Money: $200`, `Rifleman — $50`.
Text only; trivially changed.

**Internally money stays `gold`:** `state.gold`, `_add_gold`, `GOLD_CHANGED`,
`NOT_ENOUGH_GOLD`, `economy.starting_gold`, `early_call_gold_per_second`, `sell_refund`,
`buyout_cost`. Reasons: ~190 test references in 18 files, and LT-23/LT-24/LT-26 code slices
(landing in parallel on `simulation.gd`) already call `_add_gold` / `NOT_ENOUGH_GOLD`; a
rename now conflicts with all three for zero player-visible gain. Doc comments and the GDD
say "gold (money)". A mechanical rename can be a backlog task after 0.2.

| Use / source | Currency | Change |
|---|---|---|
| Build tower | money | day only (Open question 5) |
| Upgrade tower (LT-24) | money | day only (LT-24 decision) |
| Lighthouse level (LT-26) | money | LT-26 note says "Relics (LT-27 currency; internal gold)" and "during a wave": its code already uses `_add_gold`, so only the wording and the phase rule follow this note |
| Sell tower refund | money | 70 % unchanged; day only (Q5) |
| Madness buyout | money | unchanged, **any phase** (an emergency at night) |
| Wave bonus | money | renamed **"Dawn wage"** ("the harbour board pays the keeper"), paid at dawn as today, formula unchanged |
| Early call | money | kept as **"Light the lamp early"** bonus (Open question 6) |
| Kill | relics | §1.2 |

Starting stash: money 200, relics 0. Example, wave 3 at baseline: the night drops 30 scales
and 12 bones (stash value $360); at dawn the wage pays $80; selling gives $360; the day
starts with leftover + $440, the same total as today, but none of it is spendable until
dawn.

**Consequence (for LT-23/S5):** today kill gold arrives mid-wave and the bots spend it at
once (they re-check every second during a wave). With the split, the money of night n is
spent only at dawn n. Same totals, later spending: the run gets harder, and the 0.1 bot
tables are not comparable before/after. LT-23/S5 measures after LT-27/S5 (the task order
already says so).

## 3. Day length and phase rules

- **Day = BUILD**, timed by `waves.build_phase_seconds` (25 s) as today; the HUD button
  "Light the lamp" (old "Call wave") ends it early for the bonus (Open question 6).
- Config switch either way: `build_phase_seconds: 0` = **untimed day** (the night starts only
  when the player lights the lamp; the early bonus is 0). Built in S5 regardless of the
  default, because it costs one branch in `WaveDirector.tick` / `_begin_build` and one in
  `early_call_bonus`.
- **Night = WAVE.** Refused at night with `NOT_BUILD_PHASE`: `build_tower` (via
  `can_build`), `sell_tower`, `sell_relics`, LT-24 `upgrade_tower`, LT-26 lighthouse
  upgrade. Allowed: `buy_sanity`, pause, speed (Open question 5). `can_build`'s phase check
  goes **last** so its documented "first failing reason in `CommandResult` order" holds.
- **Pause** still allows every day action (LT-4 §1.3).
- **DONE** (after the last night): outcome WON is already set; nothing to buy.

## 4. Presentation (grey-box)

- **Lighting** (`scenes/lighting.gd`): `AMBIENT` becomes `AMBIENT_NIGHT` (today's
  `Color(0.30, 0.32, 0.42)`) plus `AMBIENT_DAY = Color(0.80, 0.80, 0.76)` (overcast). A
  render-only `night := 0.0..1.0` eases toward 1 in WAVE, 0 in BUILD/DONE
  (`lerp` with `1 - exp(-delta / DAY_FADE_SECONDS)`, `DAY_FADE_SECONDS = 0.6`, runs while
  paused). `CanvasModulate.color = AMBIENT_DAY.lerp(AMBIENT_NIGHT, night)`; beam energy
  and tower-light energy × `night` (the lighthouse is dark by day; LT-26's sim-driven cones
  follow the same factor); fog alpha lerps toward a lighter day value. Reads `state.phase`
  only; nothing depends on the enemy kind.
- **HUD** (`ui/hud.gd`):
  - `Money: $240` (node `GoldLabel` keeps its name; tests find it by name).
  - `Relics: 12  (≈ $96)` — new `RelicsLabel`; tooltip lists kinds: `5 amulets × $5`.
  - Phase text: `Day 3 — night falls in 18 s` / `Day 3` (untimed) / `Night 3 of 5` /
    `Dawn. All nights survived`.
  - `Light the lamp (+$36)` (old call-wave button), disabled at night.
  - `Sell relics (+$96)` — new `SellRelicsButton`, enabled by day with a non-empty stash.
  - `Restore ($150)` buyout.
- **Tower picker / side panel:** `Rifleman — $50`; refusal texts `not enough money`,
  `only by day` (`NOT_BUILD_PHASE`); `Sell (+$35)`. LT-24's side panel uses the same words.
- **Kill feedback:** HUD relic counter ticks; no pop at the death spot (§1.2, Q2/Q3).
- **End screen:** adds `Relics left unsold: 7` (flavour).

## 5. Bots (`tools/bot_runs.gd`)

- `_act` in BUILD: `sim.sell_relics()` first, then buy as today (LT-24 "wide then deep"
  rule), then `call_wave()` at once (untimed day: same call ends the day).
- At night: only `buy_sanity()` (occult strategy, as today); builds are refused, so the
  bot no longer re-checks the build order mid-wave.
- `RUN` JSON: keeps `"gold"` (final money); adds `"relics_sold": <money from sales>`,
  `"relics_left": <unsold value>`, `"wage": <sum of dawn wages>`. Header comment updated.
- No compatibility flag for the old one-currency rules (they are code, not data): the
  before/after comparison is by commit.

## 6. Must confirm, edit map, behaviours

### Must confirm (code slices)
1. `sim/config.gd` is where enemy ids from `waves.json` are cross-checked; the relic-kind
   check goes next to it.
2. Nothing outside `sim/` and tests reads `EnemyDef.reward` or `DIED.data.reward` (grep at
   design time: only `simulation.gd` 147, 455 and tests).
3. Every replay dispatcher (`build_phase_test.gd` ~146, `madness_test.gd` ~604) gets a
   `"sell_relics"` arm if the tests replay it.
4. LT-24/S2 and LT-26 code: their build-phase refusal returns `NOT_BUILD_PHASE` (align if
   they added their own value).
5. `scenes/board.gd` `on_event` and `sanity_fx.on_event` ignore unknown event types (the
   appended `RELICS_CHANGED`).

### Edit map — S5 (sim, after LT-24/S2 and LT-23/S2 on `simulation.gd`)

| Path | Function / place | Change |
|---|---|---|
| `sim/defs/economy_config.gd` | `FIELDS`, `parse`, new inner `RelicKind {id, name, price}` | `relics` block, ordered `relic_kinds: Array[RelicKind]`, `relic_by_id` |
| `sim/defs/enemy_def.gd` | `FIELDS`, `parse`, vars | `reward` → `relic: String`, `relic_count: int` (opt, default 1) |
| `sim/config.gd` | `load_from_dir` cross-checks | enemy `relic` must be a known kind |
| `sim/core/sim_state.gd` | vars | `relics: Dictionary[String, int]` (every kind, 0); doc: `gold` = money |
| `sim/core/sim_event.gd` | `Type` | append `RELICS_CHANGED` after the last value at landing time |
| `sim/core/simulation.gd` | `CommandResult` | append `NO_RELICS` |
| | `_init` | seed `state.relics` from config |
| | `apply_damage` (DIED emit) | data `{source, relic, relic_count}` |
| | `_on_enemy_killed` | `_add_relics(def.relic, def.relic_count, "kill", e.id)` replaces `_add_gold` |
| | new after `_add_gold` | `_add_relics(kind, delta, reason, id)` |
| | `can_build`, `sell_tower` | `phase == WAVE` → `NOT_BUILD_PHASE` (last check in `can_build`) |
| | LT-24 `can_upgrade`, LT-26 lighthouse upgrade check | same phase rule if not already there |
| | new after `buy_sanity` | `relic_price`, `relics_value`, `can_sell_relics`, `sell_relics` (§1.3) |
| | `early_call_bonus` | 0 when the day is untimed |
| | doc comments | `call_wave`, `award_wave_bonus` (dawn wage), `_add_gold` (money) |
| `sim/core/wave_director.gd` | `tick`, `_begin_build`, header | untimed day when `build_phase_seconds == 0` (no countdown, `build_ticks_left` stays 0) |
| `sim/defs/waves_config.gd` | `build_phase_seconds` validation | allow 0 |
| `data/economy.json`, `data/enemies.json` | | §1.1 |
| `tools/bot_runs.gd` | header, `_act`, `_play` | §5 |
| `tests/relic_test.gd` | new | tests slice, behaviours below |
| existing tests | `gold_test`, `sim_damage_test`, `config_valid/reject_test`, `harpoon_test`, `occult_tower_test` kill-gold asserts | kill now changes relics, not gold; config tests read `relic` |

### Edit map — S6 (UI, texts, GDD)

| Path | Change |
|---|---|
| `scenes/lighting.gd` | §4 day/night ambient, `night` factor, beam/tower-light/fog scaling |
| `ui/hud.gd` | `$` texts, `RelicsLabel`, `SellRelicsButton`, phase texts, "Light the lamp" |
| `scenes/game.gd` | `sell_relics()` wrapper (same shape as `call_wave`), `_after_command` |
| `ui/tower_picker.gd` | `$` cost text, `not enough money`, `only by day` |
| `ui/sell_panel.gd` (or LT-24's side panel) | `Sell (+$N)` |
| `ui/end_screen.gd` | unsold relics line |
| `tests/scene_game_test.gd`, `tests/lighting_test.gd` | text/node updates; day/night ambient test |
| `tests/render_isolation_test.gd` | unchanged (the HUD reads `state.relics`, which never says which kill was fake) |
| `docs/GDD.md` | §4 core loop (day/night), §5.1 "Money and relics" (table + relic table), §5.4 buyout in money, §7 Reward → Relic column, §8 build phase → day, §9 HUD |
| `README.md` | any gold wording |

### Behaviours the tests slice pins (one line each)
1. A real kill at night adds `relic_count` of `def.relic` to the stash and emits `RELICS_CHANGED {kind, delta, count, reason: "kill"}`; money is unchanged.
2. A fake killed drops nothing (no `RELICS_CHANGED`); a leaked enemy drops nothing.
3. Two towers killing one enemy in one tick, and a harpoon multi-kill, drop one relic set per enemy.
4. `DIED` data is `{source, relic, relic_count}` and identical for a real and a fake of one def.
5. `sell_relics()` by day sells every kind in config order: one `RELICS_CHANGED` per non-empty kind, then one `GOLD_CHANGED {reason: "relic_sale"}` with Σ price × count; stash is 0.
6. `sell_relics("scale")` sells only scales; other kinds stay.
7. `sell_relics` at night → `NOT_BUILD_PHASE`, nothing changes (no event, no log entry).
8. `sell_relics` with an empty stash or unknown kind → `NO_RELICS`, nothing changes.
9. `build_tower` and `sell_tower` at night → `NOT_BUILD_PHASE`; by day OK; `can_build` with no money at night still returns `NOT_ENOUGH_GOLD` (order).
10. `buy_sanity` at night still works.
11. Dawn wage (`award_wave_bonus`) and early-call bonus still pay money with today's formulas.
12. Untimed day (`build_phase_seconds: 0`): BUILD never ends by itself (run 10 000 ticks); `call_wave` starts the night; `early_call_bonus()` is 0.
13. Config: unknown relic kind on an enemy, missing `relic`, negative/float price, empty `relics` → rejected with the path.
14. Replay: a command log with `sell_relics` reproduces state and events (determinism).
15. Lighting: ambient is the night colour during a wave and the day colour in BUILD after the fade (scene test, advance > fade).
16. HUD: money, relics value, "Sell relics" enabled only by day with a non-empty stash.

### Candidate controls (revert the fix, the test must fail)
- C1 `_on_enemy_killed` pays `_add_gold` again instead of relics → 1.
- C2 drop the `is_fake` early return in `_on_enemy_killed` → 2.
- C3 drop the night check in `can_sell_relics` → 7.
- C4 drop the night check in `can_build` → 9.
- C5 sell kinds in reverse order / emit per-kind `GOLD_CHANGED` → 5.
- C6 untimed-day branch removed from `WaveDirector.tick` → 12.
- C7 enemy `relic` cross-check removed from `sim/config.gd` → 13.
- C8 lighting: `night` factor ignores phase (always night) → 15.

## 7. Open questions for the owner

### Q1. What relics exist and how much is each worth?
**Today:** each enemy kind pays a fixed gold reward on kill (cultist 5, Deep One 8, hybrid
10, Night-gaunt 15, Shoggoth 60). **Change:** kills drop relics instead; the question is how
"different value" is expressed.
**Example:** wave 3 kills 30 Deep Ones and 12 hybrids.
- **A. One relic kind per enemy, price = today's reward (Recommended).** 30 scales × $8 +
  12 bones × $10 = $360, exactly today's 360 gold. Benefit: economy unchanged, so LT-23
  tuning starts from a known baseline; each kind has its own lore line. Risk: fully
  predictable; "value" is only which enemy you killed.
- **B. Three tiers (bone $5, amber $15, idol $50) with random drops per enemy** (e.g. a
  hybrid drops bone 70 %, amber 25 %, idol 5 %). The same wave pays $300–$450 depending on
  luck. Benefit: excitement of a rare drop. Risk: income varies run to run, harder to tune
  and to compare bot runs; needs a new RNG stream.

### Q2. Do relics go straight to the stash, or fall on the map?
**Today:** gold is added to the counter the instant an enemy dies. **Change:** relics need a
way into the stash.
**Example:** a Deep One pack of 5 dies on the far bend.
- **A. Straight into the stash, the HUD counter ticks (Recommended).** +5 scales at once.
  Benefit: no extra clicks during the night; simplest. Risk: "падают" is not literally
  seen.
- **B. They lie on the map all night and the keeper gathers them at dawn.** 5 scale tokens
  stay on the bend until dawn, then fly to the stash. Benefit: you see the night's haul
  pile up. Risk: a token appears only for real kills, so the player sees at once which
  dead enemy was a hallucination (unless Q3 B); more render work.
- **C. They lie on the map and must be clicked to collect, at night.** Benefit: active
  play. Risk: clicking during combat in a tower defense; missed tokens are lost money; same
  fake tell as B.

### Q3. Do hallucinated enemies drop relics?
**Today:** a killed fake pays no gold (LT-12). **Change:** none needed, but a fun variant
exists.
**Example:** in Fraying, 6 of 40 kills are fakes that would drop 6 amulets.
- **A. Fakes drop nothing (Recommended, today's rule).** Benefit: no change to the approved
  LT-12 design. Risk: none new.
- **B. Fakes drop "false relics" that crumble to dust at dawn.** At night the stash shows
  46 pieces; at dawn 6 crumble ("…they were never there"). Benefit: strong theme — madness
  literally costs money, and Q2 B/C become safe. Risk: the night stash lies to the player;
  the sim must hide which relics are false (one more forbidden name in the render
  isolation test).

### Q4. How does selling work?
**Today:** nothing is sold. **Change:** relics turn into money by day.
**Example:** the day starts with 12 bones and 1 amber.
- **A. Fixed price, one "Sell relics (+$180)" button, by day only (Recommended).** Benefit:
  one click, nothing to learn; the market hook is kept for later. Risk: selling is a
  ritual, not a decision (no reason to hold).
- **B. Daily market:** each dawn prices roll ±30 % per kind (bones $7–$13 today, amber
  $42–$78); the player may hold a kind for a better day. Benefit: a real day-phase
  decision. Risk: more UI (per-kind rows), bot policy, harder tuning; luck in income.
- **C. Auto-sell at dawn:** a "Dawn ledger" shows what was sold. Benefit: zero clicks.
  Risk: the owner's "phase when we sell" becomes a summary, not an action.

### Q5. What may the player do at night?
**Today:** build and sell towers in any phase, mid-wave too; LT-24 already restricts
upgrades to the build phase. **Change:** money only comes by day.
**Example:** wave 4, a Night-gaunt column breaks through; the player has $60 left from
the day.
- **A. Night: no building, selling towers or upgrades; the madness buyout stays allowed
  (Recommended).** The $60 waits for dawn; a buyout ($150) can still be bought. Benefit:
  day and night are truly different phases, matches LT-24; buyout stays an emergency
  button. Risk: harder (no panic builds); leftover money is idle at night.
- **B. Everything allowed at night as today** (money spent at night, only relic sales by
  day). Benefit: forgiving. Risk: the day/night split is only about relics; LT-24's
  "upgrades only by day" would look arbitrary.
- **C. A plus no buyout at night.** Benefit: strictest. Risk: a player in madness mid-wave
  has no way out until dawn.

### Q6. How long is the day?
**Today:** 25 s timer; "Call wave" ends it early and pays $2 per second left (up to $50).
Building is allowed while paused, so the timer only pressures players who do not pause.
**Change:** the day now also has selling.
**Example:** the player sells, builds two towers and lights the lamp with 14 s left.
- **A. Keep the 25 s timer + "Light the lamp" early bonus (Recommended).** +$28. Benefit:
  keeps the pressure the owner asked for (finding 3: "no tension"); bots and tuning
  unchanged. Risk: a day with selling and LT-24 upgrades in 25 s may feel rushed without
  pause.
- **B. Untimed day: night starts only when the player lights the lamp; no early bonus.**
  Benefit: calm shopping, reading LT-24's side panel. Risk: −$0–50 per day of income;
  no time pressure at all.

Either way S5 builds the config switch (`build_phase_seconds: 0` = untimed), so the
answer only sets the default.
