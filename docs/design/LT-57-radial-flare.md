# LT-57 — Radial flare: design note (S1)

Status: draft for the owner · branch `feat/LT-57-radial-flare` (release-0.3.0 tip 7851dd3)

Owner (verbatim): "Мне кажется вспышка должна работать не по конусу а во все стороны - такой
массовый засвет. И стоить оно должно дороже, не 10$ а все 50 или даже 100, тк это массовый
бафф".
Owner answers already given: cost **"Масло, но дороже"** (day-time oil buying stays; the flare
spends more oil, ~$50-100 worth; the tank grows); area **"Круг вокруг маяка (Recommended)"**.

LT-30 (`docs/design/LT-30-beam-addendum.md` §1) stays the spec for oil buying, the command
pattern and the events; this note overrides only the flare's area, its numbers and the bot.

## 1. Today / change

**Today** (`data/economy.json` `lighthouse.oil` / `lighthouse.flare`, `simulation.gd`
`fire_flare` 606-618, `_beam_half_width` 1183-1188, `_update_beam` 1194-1214):
for `seconds` 3 s every beam stops turning (`hold_beams`) and its half-width doubles
(`width_mult` 2.0: cone ~27° → ~52°); every enemy lit then moves at ×0.5
(`enemy_speed_mult`). Cost 2 oil × $10 = **$20**; tank `cap` 6, `start` 2; cooldown 20 s.
"Lit" is one flag per tower/enemy; a flare only changes which cells the cones cover.
Measured on `data/map.json` (lighthouse (21,10), 40 path cells, 121 buildable), averaged
over 720 held directions: the widened cone covers **4.4 path / 12.3 build cells** at L1
(1 beam), 8.7 / 24.7 at L2, 17.5 / 49.4 at L3. Mostly sea at L1: the flare is a lottery on
where the beam happened to point.

**Change:** while a flare burns, everything within `radius` cells of the lighthouse cell
centre is lit, in every direction; outside the circle the beams light as usual. Beams keep
turning and keep their width (`width_mult`, `hold_beams` are removed). "Lit" means exactly
what it means today, so every lit rule (§3) applies inside the circle with no new code path:
`_update_beam` computes `lit = in_some_beam or (flaring and |v|² <= radius²)`.

## 2. Numbers

| key | today | proposed | why |
|---|---|---|---|
| `flare.radius_cells` (new, per lighthouse level) | — | **[6, 8, 10]** | path/build cells inside: 13/15, 18/30, 23/43 (of 40/121). L1: 3× today's average path cover and certain instead of a lottery; L3 ≈ 1.3× today's 4-beam flare. Growing keeps the lighthouse upgrade selling the flare (LT-30 §1.1 rationale). Covers the last loop before the lighthouse, where leaks happen. Validation: one entry per `beam.levels`, each in [0, `beam.reach_cells`] (0 = flare lights nothing, for the `beam_off` arm) |
| `flare.seconds` | 3 | **5** | "массовый": an enemy at speed 1.0 inside the circle for the whole flare loses 2.5 cells at ×0.5 (today 1.5) |
| `flare.enemy_speed_mult` | 0.5 | 0.5 | unchanged |
| `flare.cost_oil` | 2 | **6** | $60 at $10/oil: the owner's $50-100 band, low end; ≈ one dawn wage (50 + 10n = $60-$100), 1.2 Riflemen ($50) |
| `oil.price` | $10 | $10 | owner: buy oil by day, "дороже" via more oil, not a dearer unit |
| `oil.cap` | 6 | **12** | two flares; refill $120 ≈ one late wage, cannot be stockpiled for the finale |
| `oil.start` | 2 | **0** | 6 free oil would be $60 free against $200 start gold; the LT-56 goal (bots lose ≥ 10/20) wants harder, not easier. The HUD shows "Flare (6 oil)" disabled "No oil" on night 1, which points at the lighthouse panel |
| `flare.cooldown_seconds` | 20 | **30** | a night runs ~60 s: at most two flares, so one night cannot burn the whole tank on a single wave's tail |
| `flare.width_mult`, `flare.hold_beams` | 2.0, true | **removed** | the circle replaces the widening; `FLARE_FIELDS` rejects them (old variants fail loudly) |

All are S6 tunables (balance lab, `tools/balance/README.md`); Q1 sets the price band.

## 3. What "lit" does inside the circle (unchanged rules, wider reach)

- **Enemies** (live, fakes alike): ×`enemy_speed_mult` while the flare burns
  (`_apply_flare_slow`, unchanged), lose the Madness buff (`_madness_buff_blocked`).
- **Mundane towers:** `fire_interval ×0.8`, `ignore_miss` (no miss roll).
- **Occult towers:** `power_mult ×0.7`: Elder Sign aura strength, Reader/Resonator damage,
  Silver Key banish distance and damage (`_cast_banish` 1564), Summoning Circle: a unit
  summoned during the flare keeps `summon_dps ×0.7` for its whole life (`_summon` 1610,
  "lit at summon time", LT-52 §3). Q2 asks whether towers are lit by the flare at all.
- **Fakes / reveal:** fakes are slowed like reals and stay targetable; the flare does not
  reveal (the Searchlight's Revealing branch stays the fake counter, LT-26 non-goal). Q3.
- `TOWER_LIT` flips fire for towers entering/leaving the circle (first/last flare tick), as
  for beams today.

## 4. Render and UI

- **Render** (`scenes/lighting.gd`): a new `flare_light: PointLight2D` at the lighthouse
  centre, radial gradient texture (bright core → 0 at the rim), `texture_scale` from
  `flare_radius() × 2 × CELL / TEX_SIZE`, warm `BEAM_COLOR`; energy eases in over 0.15 s and
  out over the last 0.5 s of `flare_ticks_left`, × `night`. The cone widening in
  `_sync_beams` 118-140 is removed. Optional faint rim ring in `scenes/board.gd` so the edge
  reads on lit sea. Tower lit corner marks (board.gd 608) already show who is lit.
- **HUD** (`ui/hud.gd` `_refresh_flare` 185-206): "Flare (6 oil)" / "Flare burning" /
  "Flare 12 s" unchanged in form; tooltip "Lights everything within 6 cells for 5 s".
- **Lighthouse panel** (`ui/lighthouse_panel.gd` `refresh` 59-91):
  `Lamp oil: 4 / 12` · `Flare: 6 oil, radius 6 cells, 5 s; fired at night.` · next level
  line `Upgrade: 2 beams, flare radius 8 ($120)`. The buy button becomes
  **"Buy oil for a flare ($60)"**: a new `game.buy_flare_oil()` calls `sim.buy_oil()` up to
  `min(cost_oil, cap - oil)` times and stops at the first refusal (each unit stays one logged
  `buy_oil`, so sim, replay and bots are untouched); label shows the reason when refused.
  Six clicks per flare at one unit each would be the alternative; rejected.

## 5. Bot (`tools/bot_runs.gd`)

- `BOT_OIL_TARGET := 4` (70) → `config.economy.flare.cost_oil` (one flare; two would cost
  $120 by day, more than most wages).
- `FLARE_MIN_LIT := 3` (71) → `FLARE_MIN_IN_CIRCLE := 4`: `_night_flare` (385-393) counts live
  enemies (reals and fakes, as a player sees them) with `sim.in_flare_radius(p)`, not `e.lit`
  (before firing they are not lit by the circle yet). 4 because a flare now costs 3×.
- RUN keys unchanged (`flares`, `oil_bought`, `oil_gold`, `lit_shots`).

## 6. Edit map

| file (lines) | change |
|---|---|
| `data/economy.json` `lighthouse.oil`/`flare` (31-39) | §2 numbers; drop `width_mult`, `hold_beams`; add `radius_cells` |
| `sim/defs/economy_config.gd` `FLARE_FIELDS` 16-17, `FlareConfig` 79-88, `_parse_flare` 229-242, the `lighthouse` parse 128-141 | `radius_cells: Array[float]`; `_parse_flare` gets `c.beam` (parsed first, 128-130) to validate size == `beam.levels.size()` and each in [0, `reach_cells`] |
| `sim/core/simulation.gd` `fire_flare` doc 602-605, `_beam_half_width` 1181-1188, `_update_beam` 1190-1214, `_is_lit` 1277-1280 | drop the width/hold branches; new public `flare_radius() -> float` (`radius_cells[lighthouse_level]`) and `in_flare_radius(p: Vector2) -> bool` (`_flaring()` not required: the bot asks before firing); `lit = _lit_by(...) or (_flaring() and in_flare_radius)` for towers and enemies; `_is_lit` the same |
| `sim/core/simulation.gd` `_apply_flare_slow` 1302-1311 | doc only (lit already includes the circle) |
| `scenes/lighting.gd` `_ready` 65, `_apply_night` 100-111, `_sync_beams` 114-140 | §4 render |
| `scenes/game.gd` after `buy_oil` 196-201 | `buy_flare_oil()` |
| `ui/lighthouse_panel.gd` 3-6, 34, 59-91; `ui/hud.gd` 182-199 | §4 texts |
| `tools/bot_runs.gd` 54-61, 70-71, 335-337, 383-393 | §5 |
| `tools/balance/variants/beam_off.json` | `flare: {radius_cells: [0,0,0], enemy_speed_mult: 1.0}` |
| `docs/GDD.md` 355 | flare paragraph (radial, oil, numbers) |
| tests: `beam_test.gd` 672-723 (hold/width tests replaced), `lighthouse_config_test.gd` 157-196, `lighthouse_ui_test.gd` 88, `bot_upgrade_test.gd` 571-591 | per §7 |

Read only: `_lit_by` 1285-1299, `_madness_buff_blocked` ~1400, `_fire_towers` lit branch
1458-1502, `_cast_banish` 1549-1564, `_summon` 1600-1615, `_apply_auras` 1326-1365.

## 7. Behaviours for the tests slice

1. Flaring: a tower / live enemy at distance ≤ radius, outside every beam, is lit; at
   radius + 0.01 it is not (boundary inclusive, `<=`).
2. Not flaring: the same point is unlit (circle off); beam-lit points stay lit either way.
3. Radius follows the lighthouse level: [6, 8, 10] at L1-L3 (a point at 7 lit only from L2).
4. Beams keep turning while a flare burns (base direction changes tick to tick).
5. Lit-in-circle effects: enemy speed ×0.5 and no Madness buff; a mundane tower fires at
   ×0.8 interval with no miss draw; an occult tower at ×0.7 (Silver Key banish distance one
   case). Fakes inside are slowed and still targetable (Q3 recommended).
6. `TOWER_LIT` true on the first flare tick for a tower in the circle, false after the last.
7. `fire_flare` pays `cost_oil` 6; `NO_OIL` at 5; cooldown 30 s; tank `OIL_FULL` at 12.
8. Config: `radius_cells` wrong length / > reach / negative rejected; `width_mult`,
   `hold_beams` rejected as unknown keys.
9. `game.buy_flare_oil()`: buys `min(6, cap - oil)` units, stops at the first refusal
   (poor: buys what it can afford), one `buy_oil` log entry per unit.
10. Bot: fires at 4 live enemies in the circle (none lit by a beam), not at 3; tops oil up to
    `cost_oil`.

Controls (revert → must fail): the `or in_flare_radius` term (1, 3); the radius index by level
(3); `buy_flare_oil` loop bound (9); bot count source (10).

## 8. Open questions

**Q1. Flare price.** Today a flare costs 2 oil = $20. Change: more oil per flare (your
answer); the band is $50-100. Example: on night 3 the wage is $80; at $60 the player buys a
flare and has $20 left, at $100 the flare costs more than the whole wage. Consequence: the
price decides whether a flare competes with a tower ($50-160) or with a lighthouse level ($120).
- **6 oil = $60, tank 12 (Recommended)** — benefit: affordable from one wage, still 3× today;
  risk: may stay too cheap, S6 can raise it.
- **8 oil = $80, tank 16** — benefit: a real choice against a tower every night; risk: bots
  and new players may never fire it.
- **10 oil = $100, tank 20** — benefit: matches "даже 100", a rare big moment; risk: one flare
  per two nights at early wages, the feature may go unused.

**Q2. Does the flare light towers, or only enemies?** Today lit towers inside the (widened)
cone get the lit modifiers: mundane fire faster and never miss, occult work at ×0.7. Change:
the circle covers 15-43 buildable cells, so many towers flip at once. Example: an Elder Sign
and a Summoning Circle by the lighthouse loop: a flare slows the enemies but weakens both for
5 s, and units summoned then stay at ×0.7 dps for life.
- **Same rule: towers and enemies lit (Recommended)** — benefit: one "lit" rule, the
  lighthouse stays "light helps mundane, hurts occult", no new code path; risk: occult
  players get less from a $60 flare.
- **Enemies only; towers keep their beam state** — benefit: a pure enemy debuff, neutral for
  occult; risk: it is no longer the "бафф" you named, and adds a second kind of lit.
- **Towers too, but the flare never debuffs occult** — benefit: a buff for everyone; risk:
  an exception to the lit rule, and Summoning Circle's "lit at summon" needs a special case.

**Q3. Does the flare reveal hallucinations (fakes)?** Today nothing in the lighthouse reveals
fakes; only the Searchlight's Revealing branch does (for good). Change: a mass light reads
like it should expose them. Example: in MADNESS three fakes walk the last loop; with reveal,
a flare drops them from every tower's targets.
- **No reveal, fakes slowed like reals (Recommended)** — benefit: the Searchlight keeps its
  role, no new rule; risk: "засвет" that does not expose illusions may feel odd.
- **Reveal fakes inside the circle for good** — benefit: strong, thematic answer to Madness;
  risk: makes the Revealing Searchlight branch near-useless and Madness much easier.
- **Fakes untargetable only while the flare burns** — benefit: a short, contained effect;
  risk: a new timed state on enemies, more code and tests.

**Q4. Radius by lighthouse level.** Today the flare widens every beam, so a higher level
already makes it bigger. Change: the circle needs its own size. Example: at 6 cells the
circle covers 13 of 40 path cells; at 10, 23.
- **Grows: 6 / 8 / 10 cells at L1 / L2 / L3 (Recommended)** — benefit: the lighthouse
  upgrade also buys a bigger flare; risk: at L3 the flare covers most of the late path and
  may trivialise the end, S6 checks.
- **Fixed 8 cells** — benefit: one number, simple to read; risk: the upgrade no longer
  improves the flare, and L1 gets a large flare early.
