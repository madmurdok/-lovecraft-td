# LT-27 — Day/night economy: relics drop at night, sold for money by day (design note)

Status: decisions taken (owner, 2026-10-31) · branch `feat/LT-27-day-night-relics`

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
through `_add_gold` (`GOLD_CHANGED {delta, gold, reason}`). RNG: `SimRng.Stream {SPAWN,
COMBAT, SANITY, MADNESS}`, stream i seeded `run_seed × 16 + i`, so appended streams never
change the existing ones. Baseline kill gold for the 5 MVP waves (packs at their mean of 5):
≈ 60 + 140 + 360 + 440 + 565 = 1565; wave bonuses 400; start 200.

Playtest 0.1 finding 7: gold from kills has no lore; the owner named the loot Relics
(creature bones, fragments, amber). Lamp oil stays a future lighthouse resource (LT-26 §5).

**This task** splits the economy into two resources tied to two phases:

- **Night** = the wave phase. The lighthouse burns, towers fire, kills drop **relics**: a
  token falls at the kill and flies to the HUD stash in ~2 s. Relics cannot be spent.
- **Day** = the build phase, **40 s**. Relics are **sold for money** with one button; money
  buys towers, upgrades (LT-24), lighthouse levels (LT-26) and the madness buyout. Lighting
  the lamp early makes valuable drops likelier for that night.

```
NIGHT (WAVE n)                          DAWN (WAVE_CLEARED)            DAY (BUILD, 40 s)
kill → RELIC_DROPPED (token, kind)      tokens in flight settle        sell_relics() → $
  real:  +2 s → RELICS_CHANGED (stash)  fakes dissolve                 build / upgrade / sell
  ghost: +1 s → RELIC_VANISHED          dawn wage → $, luck reset      "Light the lamp" early
                                                                         → luck × for night n+1
```

## 1. Relics

### 1.1 Kinds, prices, drop tables (D1)

Four kinds (data, tunable):

| Kind (id) | Name shown | Price ($) | Lore |
|---|---|---|---|
| `bone` | Bone fragment | 5 | Neither man nor fish |
| `amber` | Amber | 15 | Hardened deep-sea resin with something inside |
| `idol` | Idol fragment | 50 | A shard of a green soapstone idol |
| `star_stone` | Star-stone of Mnar | 200 | The rarest find; the five-pointed grey stone |

Every kill rolls **one** drop (a Deep One pack is 5 kills, 5 rolls). The kind is drawn from
the enemy's table of integer weights (shares of 1000). The star-stone is the owner's 4th
relic with a 0.1 % chance: weight 1 in every table.

| Enemy | bone | amber | idol | star_stone | Mean $ (today's gold) |
|---|---|---|---|---|---|
| Cultist of Dagon | 999 | 0 | 0 | 1 | 5.2 (5) |
| Deep One | 749 | 250 | 0 | 1 | 7.7 (8) |
| Innsmouth Hybrid | 699 | 250 | 50 | 1 | 9.9 (10) |
| Night-gaunt | 399 | 500 | 100 | 1 | 14.7 (15) |
| Shoggoth | 0 | 0 | 999 | 1 | 50.2 (60) |
| Dagon (post-MVP) | config | | | | |

Hybrid is the owner-approved example (70 / 25 / 5 %, the star-stone's 0.1 % taken from
bone). The other rows keep each enemy's mean within ~0.3 of today's reward (Shoggoth −10,
one per run), so LT-23/S5 starts from about today's income; luck now moves a run's total
by roughly ±10 %.

```jsonc
// data/economy.json
"relics": {
  "bone":       { "name": "Bone fragment",      "price": 5 },
  "amber":      { "name": "Amber",              "price": 15 },
  "idol":       { "name": "Idol fragment",      "price": 50 },
  "star_stone": { "name": "Star-stone of Mnar", "price": 200 }
},
"token_fly_seconds": 2.0,        // kill -> stash credit (real) / flight length (both)
"ghost_vanish_seconds": 1.0,     // kill -> ghost token dissolves; < token_fly_seconds
"early_night_luck_per_second": 0.02
// replaces "early_call_gold_per_second" (removed)

// data/enemies.json: "reward": 10  ->  "drops": { "bone": 699, "amber": 250, "idol": 50, "star_stone": 1 }
// data/waves.json:   "build_phase_seconds": 25 -> 40
```

Validation: at least one kind; `name` non-empty; `price` int ≥ 0; each enemy's `drops`
keys are known kinds (cross-file check in `sim/config.gd`, next to the waves' enemy-id
check), weights int ≥ 0, sum > 0; `ghost_vanish_seconds` > 0 and < `token_fly_seconds`;
`early_night_luck_per_second` ≥ 0. Kind order = config order (sale events, HUD rows).

### 1.2 The roll and early-night luck (D1, D6)

- New stream `SimRng.Stream.LOOT` (appended) rolls real drops. Fakes roll their token's
  kind on a second appended stream `GHOST_LOOT`, so hallucinations never shift real loot
  and existing SPAWN/COMBAT/SANITY/MADNESS sequences are unchanged.
- Roll: `w'[k] = w[k] × luck` for every kind except the cheapest kind in that enemy's table
  (`w'` = `w` for it); pick with `randf() × Σw'` over config order. One `randf()` per drop.
- **Luck** (`state.night_luck`, 1.0 by default): `call_wave()` sets it to
  `1 + early_night_luck_per_second × whole seconds left` and the dawn resets it to 1.0.
  It replaces today's early-call money bonus.
- Example, hybrid, lamp lit with 30 s of 40 left: luck 1.6 → amber 400, idol 80,
  star-stone 1.6, bone 699; P(star-stone) 0.1 % → 0.14 %; mean $9.9 → $11.7 (+18 %). Lit at
  once (40 s): luck 1.8, mean $12.2 (+22 %). A cultist only gains star-stone odds (1 → 1.8).
- `early_night_luck() -> float` (replaces `early_call_bonus()`): the luck `call_wave()`
  would set now; 1.0 outside BUILD.

### 1.3 Tokens: drop, flight, credit (D2, D3)

Sim side, deterministic in ticks. Credit happens **on arrival**, not at the kill, so
`state.relics` cannot reveal a fake before its token dissolves.

- Every kill (real and fake alike, slot 5) creates a token: `RelicToken {id, kind, at:
  Vector2, drop_tick, arrive_tick}` in `state.relic_tokens`; ids from a separate
  `state.next_token_id` (entity ids are untouched). `arrive_tick = drop_tick +
  ticks(token_fly_seconds)` for both kinds of enemy.
- Event `RELIC_DROPPED {token, kind, at, arrive_tick}` — identical shape and values for
  real and fake (kind comes from LOOT or GHOST_LOOT with the same table and luck).
- Whether a token is a ghost lives only in `Simulation._ghost_tokens:
  Dictionary[int, bool]` (sim-private).
- New slot 6b `_settle_tokens()` (after `_horror_drain`, before spawning), tokens in id
  order:
  - ghost at `drop_tick + ticks(ghost_vanish_seconds)`: removed, `RELIC_VANISHED {token}`;
    credits nothing.
  - real at `arrive_tick`: removed, `_add_relics(kind, 1, "kill", token)` →
    `RELICS_CHANGED {kind, delta, count, reason, token}`.
- Dawn (`WaveDirector._clear_wave`, right after `dissolve_fakes`): `settle_all_tokens()`
  vanishes every ghost and credits every real token at once, so a day starts with none in
  flight. A night lost keeps whatever is in flight uncredited (the run is over).
- Leaks drop nothing. One drop per enemy (multi-kills, two towers on one enemy).
- `DIED` data `{source, reward}` becomes `{source}` (the def no longer has one value;
  identical for real and fake).

**Render isolation.** Nothing the render reads differs between a real and a ghost token
before the ghost's vanish tick: same event shape, same `arrive_tick`, same kind
distribution, `state.relic_tokens` holds both, `state.relics` changes only at arrival
(after the vanish tick). The fake is revealed at the vanish tick, by the vanish itself,
mid-flight: the owner's "token-ghost melts in flight". `render_isolation_test.gd` adds
`\b_ghost_tokens\b` and `\bGHOST_LOOT\b` to `FORBIDDEN`. A new sim test pins "a real and a
ghost token have equal `RELIC_DROPPED` data and leave `state.relics` unchanged until the
vanish tick".

### 1.4 Selling (D4)

Fixed price per kind, sold only by day, one button, no limits.

```
func relic_price(kind: String) -> int            ## config price; 0 for an unknown kind
func relics_value() -> int                       ## stash at today's prices
func can_sell_relics(kind := "") -> CommandResult
func sell_relics(kind := "") -> CommandResult    ## "" = every kind
```

Checks in order: outcome set → `OUTCOME_REACHED`; not day (§3) → `NOT_BUILD_PHASE`
(reused); unknown kind or nothing to sell → `NO_RELICS` (new, appended to `CommandResult`).
On OK: `command_log.append([tick, "sell_relics", kind])`; per non-empty kind in config
order `RELICS_CHANGED {kind, delta: -n, count: 0, reason: "sell"}`, then one
`GOLD_CHANGED {delta: Σ price × n, reason: "relic_sale"}`. Whole stacks only. The UI uses
`""`; per-kind sale stays in the sim for a later market (`relic_price` is the only place a
price is read).

## 2. Money

Shown as **"$"** (1920s New England dollars). **Internally money stays `gold`**
(`state.gold`, `_add_gold`, `GOLD_CHANGED`, `NOT_ENOUGH_GOLD`, `starting_gold`,
`sell_refund`, `buyout_cost`): ~190 test references in 18 files, and LT-23/24/26 code slices
landing on `simulation.gd` already call these. A rename can be a backlog task after 0.2.

| Use / source | Currency | Rule |
|---|---|---|
| Build tower | money | day only |
| Upgrade tower (LT-24) | money | day only (LT-24 decision) |
| Lighthouse level (LT-26) | money | **day only**, like other upgrades (D7); LT-26's "Relics" / "during a wave" wording is superseded |
| Sell tower refund | money | 70 %, day only |
| Madness buyout | money | any phase, also at night (D5) |
| Wave bonus | money | renamed **"Dawn wage"**, paid at dawn, formula unchanged |
| Early night | luck | §1.2; no money |
| Kill | relics | §1.3 |

Start: $200, no relics. **Consequence for LT-23/S5:** kill income was spent mid-wave
(the bots re-check every second during a wave); now it is spent at the next dawn, and the
early-call money (≤ $50 per day) becomes luck. The run gets harder; 0.1 bot tables are
not comparable; LT-23/S5 measures after LT-27/S5, over 10 seeds per strategy (loot is
random now).

## 3. Phase rules

- **Day = BUILD**, 40 s (`build_phase_seconds`); "Light the lamp" (old "Call wave") ends it
  early and sets the night's luck.
- **Night = WAVE.** One helper `_day_only() -> CommandResult` returns `NOT_BUILD_PHASE` when
  `state.phase == WAVE` (not `!= BUILD`, so unit tests without a WaveDirector, phase NONE,
  are unaffected). Used by `can_build` (as its **last** check, keeping "first failing reason
  in `CommandResult` order"), `sell_tower`, `can_sell_relics`, LT-24 `can_upgrade`, LT-26
  lighthouse upgrade. The single helper is the seam for the crew layer (§7), which will
  whitelist night deployment there.
- Allowed at night: `buy_sanity`, pause, speed; LT-27's night controls end there. More night
  agency comes from separate tasks (D5): an active lighthouse ability (lighthouse beam
  backlog task), tower target priority (new small 0.2.0 task), the crew layer (next
  release, §7).
- Pause allows every day action (LT-4 §1.3). DONE: outcome WON already set.

## 4. Presentation (grey-box, S6)

- **Lighting** (`scenes/lighting.gd`): `AMBIENT` → `AMBIENT_NIGHT` (today's
  `Color(0.30, 0.32, 0.42)`) and `AMBIENT_DAY = Color(0.80, 0.80, 0.76)`. Render-only
  `night` 0..1 eases toward 1 in WAVE, 0 in BUILD/DONE (`1 - exp(-delta / 0.6)`, runs while
  paused); `CanvasModulate.color = AMBIENT_DAY.lerp(AMBIENT_NIGHT, night)`; beam,
  lighthouse glow and tower lights × `night` (the lamp is dark by day; LT-26 cones follow
  the same factor); fog lighter by day. Reads `state.phase` only.
- **Relic tokens** (`scenes/board.gd` or a new `scenes/relic_tokens.gd` on the UI layer):
  on `RELIC_DROPPED` a small kind-coloured token pops at `at` (bone white, amber orange,
  idol green, star-stone pale blue with a glint), hangs ~0.3 s, then flies to the HUD relic
  counter so it lands at `arrive_tick` (progress from `game.sim.state.tick` and the clock's
  alpha, so ×2 speed and pause stay in sync). On `RELIC_VANISHED` it fades and shrinks where
  it is (same dissolve style as `FAKE_DISSOLVED`). A star-stone drop also gets a brief chime
  and a larger glint (same for ghost and real).
- **HUD** (`ui/hud.gd`): `Money: $240` (node `GoldLabel` keeps its name); new `RelicsLabel`
  `Relics: 12 (≈ $96)` with a per-kind tooltip; phase text `Day 3 — night falls in 31 s` /
  `Night 3 of 5` / `Dawn. All nights survived`; `Light the lamp (luck ×1.6)` disabled at
  night; new `SellRelicsButton` `Sell relics (+$96)`, enabled by day with a non-empty
  stash; `Restore ($150)`; at night a `Luck ×1.6` line while luck > 1.
- **Tower picker / side panel:** `Rifleman — $50`; refusals `not enough money`,
  `only by day`; `Sell (+$35)`.
- **End screen:** `Relics left unsold: 7`, and `Star-stones found: 1` when > 0.

## 5. Bots (`tools/bot_runs.gd`)

- In BUILD: `sell_relics()`, buy as today (LT-24 "wide then deep"), then `call_wave()` at
  once (maximum luck). At night: only `buy_sanity()` (occult strategy).
- `RUN` JSON: `"gold"` (final money) kept; adds `"relics_sold"` ($ from sales), `"drops"`
  (count per kind), `"star_stones"`, `"wage"`. Default `--seeds=10` stays the comparison
  unit; header comment updated (randomised loot, day/night rules).

## 6. Must confirm, edit map, behaviours

### Must confirm (code slices)
1. `sim/config.gd` is where waves' enemy ids are cross-checked; the `drops` kind check goes
   there.
2. Nothing outside `sim/` and tests reads `EnemyDef.reward` or `DIED.data.reward` (design
   time: `simulation.gd` 147, 455 and tests only).
3. Replay dispatchers in tests (`build_phase_test.gd` ~146, `madness_test.gd` ~604) get a
   `"sell_relics"` arm.
4. LT-24/S2 and LT-26 code: their phase refusals go through `_day_only()`.
5. `board.on_event`, `sanity_fx.on_event` ignore unknown event types (appended
   `RELIC_DROPPED`, `RELIC_VANISHED`, `RELICS_CHANGED`).
6. The scene can map a sim tick to screen time (`game.clock` alpha) for token flight.

### Edit map — S5 (sim + data + bots; lands after LT-24/S2 and LT-23/S2)

| Path | Function / place | Change |
|---|---|---|
| `sim/defs/economy_config.gd` | `FIELDS`, `parse`, new inner `RelicKind {id, name, price}` | `relics`, `token_fly_seconds`, `ghost_vanish_seconds`, `early_night_luck_per_second`; drop `early_call_gold_per_second` |
| `sim/defs/enemy_def.gd` | `FIELDS`, `parse`, vars | `reward` → `drops: Dictionary[String, int]` (ordered as config kinds) |
| `sim/defs/waves_config.gd` | — | none (40 s is data) |
| `sim/config.gd` | `load_from_dir` cross-checks | `drops` kinds known |
| `sim/core/sim_rng.gd` | `Stream` | append `LOOT`, `GHOST_LOOT` |
| `sim/core/sim_state.gd` | vars | `relics: Dictionary[String, int]`, `relic_tokens: Array[RelicToken]`, `next_token_id`, `night_luck := 1.0`; doc: `gold` = money |
| `sim/core/relic_token.gd` | new | `RelicToken` (id, kind, at, drop_tick, arrive_tick) |
| `sim/core/sim_event.gd` | `Type` | append `RELIC_DROPPED`, `RELIC_VANISHED`, `RELICS_CHANGED` |
| `sim/core/simulation.gd` | `CommandResult` | append `NO_RELICS` |
| | `_init` | seed `state.relics` (every kind 0) |
| | `step` | slot 6b `_settle_tokens()`; slot comments |
| | `apply_damage` (DIED emit) | data `{source}` |
| | `_on_enemy_killed` | real and fake: `_drop_token(e)`; real no longer `_add_gold` |
| | new | `_roll_drop(def, stream)`, `_drop_token(e)`, `_settle_tokens()`, `settle_all_tokens()`, `_add_relics()`, `_day_only()` |
| | `can_build`, `sell_tower` | `_day_only()` (last check in `can_build`) |
| | LT-24 `can_upgrade`, LT-26 lighthouse upgrade | `_day_only()` |
| | `call_wave` | set `state.night_luck`; no money |
| | `early_call_bonus` | → `early_night_luck()` |
| | new after `buy_sanity` | `relic_price`, `relics_value`, `can_sell_relics`, `sell_relics` |
| | doc comments | `award_wave_bonus` (dawn wage), `_add_gold` (money) |
| `sim/core/wave_director.gd` | `_clear_wave` | `sim.settle_all_tokens()` after `dissolve_fakes`; reset `night_luck` to 1.0 before `_begin_build` |
| `data/economy.json`, `enemies.json`, `waves.json` | | §1.1 |
| `tools/bot_runs.gd` | header, `_act`, `_play` | §5 |
| `tests/relic_test.gd` | new | behaviours below |
| existing tests | `gold_test`, `sim_damage_test`, `harpoon_test`, `occult_tower_test` (kill gold), `build_phase_test` (early-call money → luck; 25 → 40 s where read from data), `config_valid/reject_test` (`reward` → `drops`), `render_isolation_test` (§1.3) | update |

### Edit map — S6 (UI, texts, GDD)

| Path | Change |
|---|---|
| `scenes/lighting.gd` | §4 day/night ambient, `night` factor |
| `scenes/relic_tokens.gd` (new) or `scenes/board.gd` `on_event` | §4 tokens |
| `ui/hud.gd` | `$` texts, `RelicsLabel`, `SellRelicsButton`, phase texts, "Light the lamp", luck line |
| `scenes/game.gd` | `sell_relics()` wrapper (shape of `call_wave`), `_after_command` |
| `ui/tower_picker.gd`, `ui/sell_panel.gd` (or LT-24 side panel) | `$`, `not enough money`, `only by day`, `Sell (+$N)` |
| `ui/end_screen.gd` | unsold relics, star-stones |
| `tests/scene_game_test.gd`, `tests/lighting_test.gd` | text/node updates, ambient by phase, token pops and vanishes |
| `docs/GDD.md` | §4 core loop (day/night), §5.1 "Money and relics" (kinds, tables, luck), §5.4 buyout in money, §7 Reward → drops, §8 day 40 s + early-night luck, §9 HUD |
| `README.md` | gold wording |

### Behaviours the tests slice pins (one line each)
1. A real kill emits `RELIC_DROPPED`; `state.relics` is unchanged until `arrive_tick`, then `RELICS_CHANGED {reason: "kill"}` adds one of that kind; money never changes on a kill.
2. A fake kill emits `RELIC_DROPPED` with the same data shape; at `drop_tick + ghost_vanish` `RELIC_VANISHED`; nothing is ever credited.
3. Real and ghost tokens are indistinguishable before the vanish tick (event data keys/values, `state.relic_tokens` entries, `state.relics`).
4. Leaks drop nothing; a multi-kill or two towers on one enemy drop one token per enemy.
5. Drop distribution: over 10 000 rolls with a fixed seed each kind's share is within tolerance of its weight; weight 0 never drops.
6. Luck: `call_wave` with s seconds left sets `night_luck = 1 + rate × s`; it scales every kind except the table's cheapest; dawn resets it to 1.0.
7. Stream independence: the same seed and commands give the same real drops with hallucinations on and off (GHOST_LOOT), and SPAWN/COMBAT/SANITY/MADNESS draws are unchanged versus a run with loot disabled.
8. Dawn: tokens in flight are settled (real credited, ghosts vanished) before `BUILD_STARTED`.
9. `sell_relics()` by day: one `RELICS_CHANGED` per non-empty kind in config order, then one `GOLD_CHANGED {reason: "relic_sale"}` = Σ price × count; stash 0. `sell_relics("amber")` sells only amber.
10. `sell_relics` at night → `NOT_BUILD_PHASE`; empty stash / unknown kind → `NO_RELICS`; nothing changes on refusal (no event, no log).
11. `build_tower`, `sell_tower` at night → `NOT_BUILD_PHASE`; `can_build` with no money at night returns `NOT_ENOUGH_GOLD` (order); `buy_sanity` works at night.
12. Day lasts `build_phase_seconds` (40 s from data); dawn wage formula unchanged; `call_wave` pays no money.
13. Config: unknown `drops` kind, negative/float weight, all-zero table, missing `drops`, `ghost_vanish_seconds ≥ token_fly_seconds` → rejected with the path.
14. Replay with `sell_relics` and `call_wave` reproduces state and events.
15. Lighting: night colour in a wave, day colour in BUILD after the fade.
16. HUD: money, relics value; "Sell relics" enabled only by day with a non-empty stash; render isolation scan forbids `_ghost_tokens`, `GHOST_LOOT`.

### Candidate controls (revert the fix; the test must fail)
- C1 credit at the kill instead of at arrival → 1, 3.
- C2 ghost tokens credited (no `_ghost_tokens` check in `_settle_tokens`) → 2.
- C3 fakes roll on `LOOT` instead of `GHOST_LOOT` → 7.
- C4 luck applied to the cheapest kind too (or not at all) → 6.
- C5 `settle_all_tokens` removed from `_clear_wave` → 8.
- C6 `_day_only()` removed from `can_sell_relics` / `can_build` → 10, 11.
- C7 drops kind cross-check removed from `sim/config.gd` → 13.
- C8 lighting `night` ignores phase → 15.

### Controls (S8)

Nine controls, one more than the usual cap: the eight design candidates plus one per UI
behaviour the tests slice was asked to pin (token flight on ticks; no "gold" in texts).
Godot controls need no build; each runs one test file in seconds. Revert in a throwaway
worktree, run only the named file; the named test must fail.

| # | Production revert | Must fail |
|---|---|---|
| C1 | `simulation.gd` `_drop_token`: for a real enemy call `_add_relics(tok.kind, 1, "kill", tok.id)` right away and do not append the token to `state.relic_tokens` (credit at the kill) | `relic_test` `test_real_kill_drops_a_token_credited_only_at_its_arrive_tick`, `test_real_and_ghost_tokens_are_indistinguishable_before_the_vanish_tick` |
| C2 | `simulation.gd` `_settle_tokens`: `if _ghost_tokens.has(tok.id):` → `if false:` (ghosts settle like real tokens) | `relic_test` `test_fake_kill_drops_a_ghost_token_that_vanishes_and_credits_nothing` |
| C3 | `simulation.gd` `_drop_token`: roll on `SimRng.Stream.LOOT` for fakes too | `relic_test` `test_a_real_drop_draws_once_on_loot_and_a_fake_once_on_ghost_loot_only`, `test_fakes_never_shift_the_real_drops` |
| C4 | `simulation.gd` `_roll_drop`: `if kind != cheapest:` → `if true:` (luck scales the cheapest kind too) | `relic_test` `test_luck_scales_every_kind_but_the_cheapest` |
| C5 | `wave_director.gd` `_clear_wave`: delete `sim.settle_all_tokens()` | `relic_test` `test_dawn_settles_tokens_in_flight_before_the_day_starts` |
| C6 | `simulation.gd` `can_sell_relics`: delete the `_day_only()` check | `relic_test` `test_sell_relics_refusals_change_nothing` |
| C7 | `config.gd` `load_from_dir`: delete the `_check_drops(c)` call | `relic_test` `test_config_rejects_bad_drop_tables_with_the_path` |
| C8 | `lighting.gd` `night_target`: `return 1.0` whatever the phase | `lighting_test` `test_ambient_is_day_by_day_and_night_after_the_fade_at_night` |
| C9 | `relic_tokens.gd` `progress`: `var now := float(game.sim.state.tick)` (drop the clock's alpha) | `relic_ui_test` `test_token_flight_follows_sim_ticks_and_the_clock_alpha` |

Also pinned without a dedicated control (each revert overlaps one above or an existing
suite): the luck-exempt kind ignores weight-0 kinds
(`test_the_luck_exempt_kind_is_the_cheapest_that_can_drop`), day length 40 s, replay of
`sell_relics` + early night, and "no player-facing gold" (`relic_ui_test`
`test_no_player_facing_text_says_gold`; a revert of `TowerInfo.REASONS` NOT_ENOUGH_GOLD to
"not enough gold" fails it).

## 7. Future layer: crew (design only, next release; D5)

Owner, verbatim: "Мне кажется что продажа только днем, и возможно имеет смысл закупать не
башни а юнитов. Ну типа - закупили 10 гарпунщиков, на каждую башню положено по 2 человека,
4х разместили ( сделали 2 башни ) а 6 придержали до ночи. Если есть нужда - ставим еще 3
гарпунные башни (или даже не башни а пункты обороны, которые бьют хуже чем башни, а в башни
они автоматически апгрейдятся днем/или вариант что днем они снова возвращаются в резерв )".

**Model sketch.** Money hires **crew** by day (riflemen, harpooners, later occultists) into
a **reserve**. A tower needs a crew (e.g. 2 harpooners) plus its build cost; crew in the
reserve can be **deployed at night** as a **defence post** on a free buildable cell (weaker
than a tower: e.g. 60 % damage, no upgrades, cheap or free). At dawn a post either becomes a
tower if the day's money covers the build cost, or its crew returns to the reserve. This
gives night agency without breaking "money only by day".

**What LT-27 already provides (no crew code here):**
- All spending goes through `_add_gold(-cost, reason, id)`; a hire is one more reason.
- All phase gating goes through `_day_only()`; night deployment is one whitelisted command.
- `can_build` keeps its check order; a crew check can be appended as one more reason.
- Towers keep `spent` (money) for refunds; crew would be refunded to the reserve separately.

**Open questions for the crew task:**
1. Crew per tower kind, and whether occult towers need crew at all (cultists? scholars?).
2. Hire price per unit vs. today's tower cost (does a tower become crew + a cheaper frame?).
3. Post stats (damage share, range, targeting) and whether a post can be built on any
   buildable cell.
4. Dawn rule: auto-upgrade post → tower (if money suffices) vs. always back to reserve vs.
   player chooses.
5. Can crew die or desert (losses at night, sanity effects on crew)?
6. Selling a tower: crew back to reserve, money refund at 70 % of the frame only?
7. Upkeep: crew wage at dawn vs. one-time hire.
8. UI: reserve panel, night deployment flow; bots' deployment policy.

## 8. Decisions (owner, 2026-10-31)

### D1. Relic kinds and values
Owner: "Три тира со случайным дропом, можно добавить еще четвертую реликвию, с 0.1%
вероятности выпадания, но ценой 200$". → Three tiers (bone $5, amber $15, idol $50) with
random drops per enemy (tables in §1.1, tunable defaults) plus the star-stone of Mnar,
0.1 % per drop, $200. Seeded `LOOT` stream; bot comparisons over 10 seeds.

### D2. How relics reach the stash
Owner: "Может пусть падают и через пару секунд уходят в HUD счетчики?" → A token drops at
the kill and flies to the HUD counter in ~2 s (`token_fly_seconds`); the sim credits the
stash on arrival, in ticks (§1.3), which keeps it deterministic and keeps fakes hidden
until their token dissolves.

### D2b. Tokens from fakes
Owner chose: "Токен-призрак тает на лету (Recommended)". → Fakes emit the same drop event;
the token dissolves mid-flight (`ghost_vanish_seconds`) and never reaches the counter.
Render isolation per §1.3.

### D3. Do fakes add relics to the stash
Owner chose: "Ничего не роняют (Recommended)". → Fakes credit nothing (today's LT-12 rule);
only the ghost token is shown.

### D4. Selling
Owner chose: "Фикс. цена, одна кнопка (Recommended)". → Fixed prices, one "Sell relics"
button, by day only (§1.4).

### D5. Night actions
Buyout allowed at night; building, selling towers and upgrades by day only. Owner: "надо
подумать что-нибудь еще, а то получается что у нас днем фаза планирования, а если что-то
идет не так - то мы никак не контроллируем. Это неправильно." Follow-ups, outside LT-27's
code: active lighthouse ability → lighthouse beam backlog task; tower target priority → new
small 0.2.0 task; crew → owner chose "Вписать в дизайн LT-27, реализация — след. релиз
(Recommended)" (§7).

### D6. Day length and early night
Owner: "Можно сделать таймер секунд 40, а за \"раннюю ночь\" давать бонус в виде
увеличенных вероятностей ценного дропа". → Day 40 s; lighting the lamp early sets
`night_luck = 1 + 0.02 × seconds left` (≤ ×1.8), multiplying the weights of every kind but
the cheapest in each table for that night; no money bonus (§1.2).

### D7. LT-26 lighthouse upgrade
Costs money and is bought by day only, like other upgrades.
