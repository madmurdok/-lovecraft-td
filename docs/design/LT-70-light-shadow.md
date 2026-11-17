# LT-70 — Light and shadow: Searchlight vs Elder Sign (design note, S1)

Status: approved direction, Q1-Q4 answered (§9) · branch `feat/LT-70-light-shadow` (on top
of LT-69 9b633ea: the flare lights the whole map).

Owner (verbatim): "башня что светит и башня что замедляет - пересекаются по функциям";
"можем ли мы уравнять их между собой, но сделать так что прожектор замедляет и приносит бафы и
плюшки для обычных башен и дебафы для оккультных, а знак соответственно тоже замедляет но
баффит окультные и дебаффит обычные?"; "а если знак снимает броню, то можно прожектору усилить
замедление?". Answers already given: conflict **"Гасят друг друга (Recommended)"**, shadow
strength **"Зеркально свету (Recommended)"**.

LT-30 (`docs/design/LT-30-beam-addendum.md`) stays the spec of what "lit" does to a tower
and to an enemy; this note adds two new *sources* (Searchlight light for towers and enemies,
Elder Sign shadow for towers) and one new tower state (shadowed). Both work at night only,
like the beam (Q2).

## 1. Today / change

**Today.** Both towers are support levels (damage 0) handled by the one aura loop
`Simulation._apply_auras` (`sim/core/simulation.gd` 1398-1460): every live enemy inside
gets `speed_mult × (1 − slow)` and `damage_taken_mult × multiplier` (strongest of the
covering auras, no stacking).

| tower (`data/towers.json`) | L1 | L2 | L3 a | L3 b |
|---|---|---|---|---|
| Searchlight (125-142), mundane, $80 | r3, slow 0.2, reveal | r3.5, 0.25, reveal | Signal lamp r5, 0.25, reveal | Blinding r3.5, 0.4, **×1.2 taken**, reveal |
| Elder Sign (40-58), occult, $100 | r2.5, slow 0.35, ×1.5 | r3, 0.35, ×1.5 | Pure Ward r4, 0.35, ×1.5 | Corrupted r3, 0.35, ×1.5, strip 1 |

Both slow, Blinding also marks: the overlap the owner names. Neither changes other towers.
"Lit" comes only from the lighthouse: `_update_beam` (1269-1289) sets `SimTower.lit`
(`sim/core/sim_tower.gd` 29-31) per tower centre and `SimEnemy.lit` per live enemy (route
position at the start of the tick) from `_lit_now` (1260: `_flaring() or _lit_by(...)`),
emits `TOWER_LIT {lit}` on a tower flip; by day (`_beam_on` 1241 false: BUILD, DONE) every
flag is false. Readers (all `kind`-gated for towers; numbers from `economy.json`
`lighthouse.beam` 27-29 → `EconomyConfig.BeamConfig` 55-58):

- `_fire_towers` 1539-1543 occult damage × `occult_power_mult` 0.7; 1578-1580 mundane no
  miss roll (`mundane_ignore_miss`); 1616-1619 mundane interval × `mundane_fire_interval_mult` 0.8.
- `_apply_auras` 1439-1445 lit occult aura: slow, taken bonus, strip × 0.7.
- `_cast_banish` 1640 banish cells and damage × 0.7; `_summon` 1686-1687 unit dps × 0.7
  for the unit's life.
- Enemies: `_madness_buff_blocked` 1478 (lit → no madness buff when
  `beam.enemy.cancel_madness_buff`); `_apply_flare_slow` 1381 (lit and flaring → × 0.5).
- UI: `scenes/board.gd` 615-617 corner mark; `ui/tower_panel.gd` 175-200 `*` cells, status
  line, special lines, "no misses"; `ui/tower_info.gd` 323-402 (`beam_text`,
  `beam_percent`, `lit_values`, `lit_effects`, `lit_line`).

**Change.**
- **Searchlight = LIGHT.** At night every other tower whose centre is within the
  Searchlight's range of its centre is lit, by exactly the beam rule (mundane ×0.8 interval +
  no misses; occult ×0.7), and every live enemy in that radius is lit in the beam sense (Q1).
  It keeps `reveal_fakes` and becomes the main slow (0.3 / 0.35 / a 0.35 / b 0.5). The
  Blinding ×1.2 taken is removed: "marks foes" belongs to the sign.
- **Elder Sign = SHADOW**, the mirror. At night every other tower within its range is
  shadowed: occult power ×1.3; mundane interval ×1.25 and +0.10 miss chance. It keeps ×1.5
  taken and Corrupted Seal's strip; its slow drops 0.35 → 0.2. Signs shadow other signs (Q4).
- **Cancel.** A tower that is lit (beam, flare or Searchlight) *and* shadowed is neither.
- **Render.** Lit towers get a warm tint, shadowed ones a cold violet tint (Q2); in BUILD a
  faint preview tint shows what a placed or hovered caster would do at night.

## 2. Rules

### 2.1 State

`SimTower` keeps `lit` and gains `shadowed` (both bool, both *net*, never both true).
`on = _beam_on()` (night: WAVE and NONE), the same gate as the beam (Q2):

```
light_any  = on and (_lit_now(dirs, k, c) or in_cast(t.centre(), "casts_light", t.id))
shadow_any = on and in_cast(t.centre(), "casts_shadow", t.id)
t.lit      = light_any  and not shadow_any
t.shadowed = shadow_any and not light_any
e.lit      = on and (_lit_now(dirs, k, p) or in_cast(p, "casts_light", -1))   # live enemies
```

`in_cast(p, key, skip_id)`: some tower `o` with `o.id != skip_id` whose current level has
`effects[key] > 0` and `in_cast_radius(o.centre(), o.stats().range_cells, p)`. The radius
test is one public static `Simulation.in_cast_radius(c: Vector2, range_cells: float,
p: Vector2) -> bool` (`|p − c|² <= range²`, the `_apply_auras` test, boundary inclusive),
shared with the board's BUILD preview (§5) so the two cannot drift.

Keeping `lit` as the net flag means every existing reader (§1 list) keeps its meaning with
no edit; only the shadow readers are new. Rejected: one enum field (`light_state`), which
rewrites every `t.lit` site for no behavioural gain.

The casting tower is chosen by two new flag effects on the level (§3), not by
`reveal_fakes` / `kind`: the Resonator's Tuned branch reveals fakes and must not light.

**Enemies have no shadow.** Shadow is a tower state only; the sign's effect on enemies is
its aura (slow, ×1.5 taken, strip). An enemy inside both a Searchlight and a sign is lit.
(Making a sign un-light enemies would turn it into a madness amplifier next to a
Searchlight, which no answer asked for.)

### 2.2 Where it is computed

In `_update_beam` (slot 2, first). Once per tick, collect the casters (towers in id order
with either flag; few). The tower loop ORs the beam test with the casters; the enemy loop
(after the existing `if not on: return`, so by day nothing changes) ORs the beam test with
the light casters. O((towers + enemies) × casters).

### 2.3 Effects of `shadowed` (new tower readers)

Config `economy.shadow` (§3):
- `_fire_towers` damage: occult × `shadow.occult_power_mult` (1.3), at the same place as
  the lit ×0.7 (before madness ×2, before crit). Includes Resonator beam damage.
- `_fire_towers` miss: a shadowed mundane shot rolls `_roll_miss(extra)` with chance
  `min(1, threshold().miss_chance + shadow.mundane_miss_chance_add)`. At Lucid this adds a
  COMBAT draw where today there is none (see 2.5).
- `_fire_towers` interval: mundane × `shadow.mundane_fire_interval_mult` (1.25), decided at
  the shot like the lit one.
- `_apply_auras`: a shadowed occult aura (Elder Sign in another sign's radius) scales slow,
  taken bonus and strip by 1.3, the same formula as 1439-1445 with `pm` from the state.
- `_cast_banish`: `power` 1.3 when shadowed (banish cells and damage).
- `_summon`: unit dps × 1.3 when the circle is shadowed at summon time, for the unit's life
  (mirror of "lit at summon time", LT-52 §3).
- A mundane support tower (Searchlight) is unchanged by either state, as today.

Two helpers so the call sites cannot drift: `_power_mult(t) -> float` (occult: 0.7 lit,
1.3 shadowed, else 1.0; mundane 1.0) and `_interval_mult(t)` (mundane: 0.8 lit, 1.25
shadowed, else 1.0).

### 2.4 Enemies lit by a Searchlight (Q1)

`e.lit` is the one enemy flag, so a Searchlight-lit enemy gets every beam enemy-lit rule
with no new code path:
- **Madness buff cancelled** (`_madness_buff_blocked`, when `beam.enemy.cancel_madness_buff`).
- **Flare slow: no new effect.** `_apply_flare_slow` acts only while a flare burns, and then
  every enemy on the map is already lit (LT-69). A Searchlight never slows through "lit"; its
  slow is its aura (`_apply_auras`), which works day and night as today. Enemy slow inside a
  Searchlight while flaring = (1 − 0.3) × 0.5, as for any aura enemy under a flare today.
- Fakes inside are lit like reals (the beam rule); the reveal stays the aura's job.

The lit radius equals the slow and reveal radius (same `range_cells`, same start-of-tick
position), so "inside the Searchlight" means one thing for an enemy.

### 2.5 Tick order

Unchanged slots (`step` 94-125): 1 reset → 2 `_update_beam` (beam + light + shadow: tower
flags and enemy `lit`) → `_apply_auras` (reads the tower flags for Elder Sign strength;
applies the Searchlight slow) → madness buff (reads `e.lit`) → flare slow → statuses,
allies, flare countdown → 3 move → 4 leak → 5 `_fire_towers` (reads the tower flags).
Flags are fixed for the whole tick before anything reads them. A tower built, upgraded or
sold between ticks changes casters from the next slot 2 (as the beam today). No
circularity: the cast radius is the level's range, which no state scales.

### 2.6 Determinism

No new RNG stream. Flags depend only on tower centres, levels, enemy positions and the beam
state, computed in id order; the OR is order-free. The one new draw: a shadowed mundane
shot at Lucid/Whispers now draws on COMBAT (today chance 0 → no draw, `_roll_miss`
2200-2205). It happens inside `_fire_towers` in id order, so replays stay deterministic;
seeds *with an Elder Sign covering a mundane tower* diverge from today's runs (expected; bot
baselines move).

### 2.7 Light/shadow and the flare

The flare lights every tower (LT-69), so during a flare every shadowed tower is neutral
(cancel): a shadowed occult battery drops from ×1.3 to ×1.0 for 5-7 s, a shadowed rifle
loses its penalty. This follows the owner's cancel rule; no special case.

## 3. Numbers and config

| key | today | proposed | why |
|---|---|---|---|
| `searchlight` L1 `slow` | 0.2 | **0.3** | the main slow now (owner: "прожектору усилить замедление") |
| `searchlight` L2 `slow` | 0.25 | **0.35** | = Elder Sign's old slow; the slow moves to the light tower |
| Signal lamp (a) `slow` | 0.25 | **0.35** | keeps L2's slow; the branch buys radius 5 = wide reveal *and* a wide light (more towers and enemies lit) |
| Blinding beam (b) `slow` | 0.4 | **0.5** | the hard-slow branch |
| Blinding beam `damage_taken_multiplier` | 1.2 | **removed** | marking is the sign's job (overlap) |
| `searchlight` every level | — | **`casts_light: 1`** | light radius = level range (3 / 3.5 / 5 / 3.5) |
| `elder_sign` every level `slow` | 0.35 | **0.2** | the sign trades slow for exposure and shadow |
| `elder_sign` taken / strip | ×1.5 / Corrupted 1 | unchanged | owner |
| `elder_sign` every level | — | **`casts_shadow: 1`** | shadow radius = level range (2.5 / 3 / 4 / 3) |
| light multipliers | `lighthouse.beam.mundane` 0.8 + no miss, `occult` 0.7, `enemy.cancel_madness_buff` | **reused** | "same rule as the lighthouse beam": one place to tune light |
| `shadow.mundane.fire_interval_mult` (new) | — | **1.25** | mirror of 0.8 (1/0.8): −20 % fire rate |
| `shadow.mundane.miss_chance_add` (new) | — | **0.10** | mirror of "never misses" |
| `shadow.occult.power_mult` (new) | — | **1.3** | mirror of 0.7 (1 + 0.3) |
| roles (≤ 24 chars, `ROLE_MAX_CHARS`) | "Reveals fakes, slows" / "Aura: slows and exposes"; Signal "Wide reveal"; Blinding "Slows hard, marks foes" | "Lights towers, slows" / "Shadow aura, exposes"; "Wide light, reveal"; "Slows hard" | texts follow the change |

Shadowed Elder Sign (inside another sign): slow 0.26, taken ×1.65, strip 1.3.

**Where the shadow numbers live: `economy.json` top-level `shadow` block** (not under
`lighthouse`: no lighthouse involved), mirroring `lighthouse.beam.mundane/occult`:

```json
"shadow": {
  "mundane": { "fire_interval_mult": 1.25, "miss_chance_add": 0.1 },
  "occult":  { "power_mult": 1.3 }
}
```

Which tower casts is a **tower effect flag** (`casts_light`, `casts_shadow`), so the lab can
switch a caster off per level by patching `towers.json`, and a future tower can cast without
code. Rejected: a tower effect carrying the multipliers (every Elder Sign level would repeat
three numbers; mirror tuning would drift).

**Validation** (`config_reject_test` / `config_valid_test`):
- `EconomyConfig.FIELDS` gains `"shadow"`; the block is **optional** (absent → `shadow`
  null → shadowed towers get ×1.0 / +0, the flag still computed: the lab's "shadow off" arm).
  Present: `check_keys` exactly `mundane`/`occult` and their keys; `fire_interval_mult` > 0,
  `power_mult` > 0 (exclusive, like the beam's), `miss_chance_add` in [0, 1].
- `TowerDef.Level.EFFECTS` gains `casts_light: 1.0`, `casts_shadow: 1.0`; both in
  `FLAG_EFFECTS` (0 or 1). A level with `damage > 0`, a banish or a summon may not cast
  (add to `NOT_WITH_BANISH`, `NOT_WITH_SUMMON`; new error "casts_light needs a support
  level (damage 0)"). One level may not set both flags.

## 4. Interactions

| case | rule |
|---|---|
| day (BUILD, DONE) | no light, no shadow, no enemy lit from a Searchlight (Q2); the Searchlight slow and reveal and the sign aura work as today |
| Summoning Circle | shadowed at summon time → unit dps ×1.3 for its life (mirror); lit ×0.7 as today; units spawned before keep theirs |
| Silver Key | shadowed: banish cells ×1.3, Corrupted damage ×1.3 (the `power` term, 1640) |
| Resonator | shadowed: damage ×1.3 after `sanity_factor`, before madness ×2; Tuned's `reveal_fakes` does **not** light (flag-driven, §2.1) |
| Necronomicon | ×1.3 damage (the main beneficiary) |
| Elder Sign in light (beam / flare / Searchlight) | lit occult aura ×0.7 as today; its own shadow *casting* is unchanged (radius and the fact of shadow do not depend on its state) |
| Elder Sign in another sign's radius | shadowed: its aura ×1.3 (Q4 "Да, как любую башню"); see §6.1 |
| self | a caster never affects itself (`o.id != t.id`); else every sign would be a flat ×1.3 |
| Searchlight in light / shadow / other Searchlights | flags set (tint shown), no effect: mundane support towers are never scaled (today's rule) |
| madness | Searchlight-lit enemies skip the madness buff (Q1, §2.4); a shadowed mundane shot in MADNESS: threshold miss + 0.10, astray rules unchanged |
| flare | no new enemy effect from Searchlight light (§2.4); every tower lit while flaring cancels shadow (§2.7) |
| fakes | lit like reals inside a Searchlight; reveal unchanged; shadow reveals nothing |
| enemies and shadow | none: an enemy in a sign and a Searchlight is lit (§2.1) |
| auras overlap with enemies | unchanged: strongest slow / taken / strip across covering auras, so Searchlight 0.3 and Elder Sign 0.2 → 0.3 |
| stats table `*` | shadowed cells use the same `LIT_MARK` `*` in a shadow colour; values from `_power_mult`/`_interval_mult` numbers of the state |
| events | `TOWER_LIT` payload becomes `{lit, shadowed}`, emitted when either flips (at most one per tower per tick). No new event type: old readers of `data.lit` keep working. Enemy `lit` has no event (as today) |

## 5. Render and UI

**Tower tint (Q2).** `scenes/board.gd` `_draw_tower` 605-617 draws the plate
`draw_rect(r, COLOR_TOWER)`; it becomes `draw_rect(r, plate_color(t))`:
- lit → `COLOR_TOWER.lerp(LIT_TINT, 0.45)`, `LIT_TINT := Color(1.0, 0.82, 0.5)` (warm);
- shadowed → `COLOR_TOWER.lerp(SHADOW_TINT, 0.5)`, `SHADOW_TINT := Color(0.42, 0.32, 0.68)`
  (cold violet, darker);
- neither, or both cancelled → `COLOR_TOWER` (no tint).
`static func plate_color(t)` so the tests read it without drawing.

**Tint alongside the corner mark (recommended), not instead of it.** The lit dot (615-617)
stays and the shadowed tower gets a matching dark violet dot with a pale rim
(`SHADOW_MARK_COLOR`). Why: the tint sits under the lighting pass, and a beam over the tile
already washes a plate warm (LT-28 added the dark letter plate for exactly that), so a lit
tint in a beam reads as "beam tile"; the dot is a second, shape-based cue that survives the
wash and colour blindness. Risk: one more mark per tower; the dot is 3.5 px, as today.
Replacing the dot with the tint alone would be less clutter but leave lit-vs-beam-washed
ambiguous.

**BUILD preview (my recommendation; the owner asked for visibility, not for a day preview).**
By day nothing is lit or shadowed (Q2), so the player could not see what a caster will do.
While BUILD and the board's `selected_cell` holds a caster — a hovered build-list
Searchlight/Elder Sign in the picker (`ui/tower_picker.gd` 320-330, L1 range) or a placed one
open in the tower panel (`ui/tower_panel.gd` 134-139, its current range) — every *other*
tower with `Simulation.in_cast_radius(caster centre, range, tower centre)` gets the same tint
at weight 0.2 (faint). Board var `selected_cast := ""` ("light" / "shadow" / ""), set next
to `selected_range` and cleared with it (`tower_picker.gd` 212-213, 223-224; `tower_panel.gd`
97; `lighthouse_panel.gd` 42). The preview shows that one caster's effect only (no beam, no
cancel against other casters): it answers "what does this tower touch". Not shown at night,
where the real tint is on.

Other render:
- Auras: the Searchlight disc (`_draw_searchlight` 647+) and the Elder Sign ward ring
  (`_draw_auras` 628-645) already show each radius, which is now also the light/shadow radius.
  Add: the ward ring gets a faint dark fill (`WARD_COLOR` alpha ~0.06) so "shadow area" reads
  as the opposite of the lit disc. No per-tower link lines.
- Enemies lit by a Searchlight need no new mark (an enemy's lit state has no mark today).

UI:
- `ui/tower_info.gd`: `lit_values` / `lit_effects` / `lit_line` / `beam_percent` take the
  multipliers as parameters (light from `beam`, shadow from `shadow`) instead of reading
  `beam` directly; new `NOW_SHADOW := "* In shadow now: "`; lines "fire −20%, +10% misses" /
  "+30% power". ROWS: `"beam"` label "In beam" → **"In light"**, new row `["shadow",
  "In shadow"]` ("−20%" mundane firing, "+30%" occult, `—` support). New effect texts for
  `casts_light` "Lights towers and foes at night" and `casts_shadow` "Shadows towers at
  night" (`_effect_text`, `special_short`).
- `ui/tower_panel.gd` 175-200: pick light or shadow numbers by `t.lit` / `t.shadowed`;
  `kind_lines` gets the Fraying line "+10% misses in shadow" when shadowed.
- `ui/stats_table.gd` 109-110: `COLOR_SHADOW` for col-0 cells marked by a shadowed tower
  (a `shadow` bool next to `lit` in `set_columns`).

## 6. Bot and balance lab

`tools/bot_runs.gd` today: no strategy builds the Searchlight; `occult`, `mixed`, `madness`
build Elder Signs (`MIXED_ORDER` 80-81, `_order` 294-321, `BRANCH_PICK` 85-97). `_best_cell`
(440-462) scores a cell by the path cells in its L1 range (cached per def in
`_score_cache`) and takes the first free one, so in `mixed` a sign lands next to riflemen.

**New strategy `light` (Q3).** Order: rifleman, rifleman, searchlight, harpooner, rifleman,
repeated (`LIGHT_ORDER`); `BRANCH_PICK` `{rifleman a, harpooner a, searchlight b}`; no cap
guard (no occult). Appended to `STRATEGIES` (the lab reads that list).

**Light/shadow-aware placement (Q3), every strategy.** `_best_cell(sim, id)` keeps the cached
path score and adds a cast term computed against the towers on the board now:

```
score'(cell) = path_score(cell) + CAST_WEIGHT × cast_term(id, cell)
```

- Caster being placed (level 0 has `casts_light` / `casts_shadow`), range r = its L1 range:
  for each existing firing tower `o` (`o.stats().acts()`) with
  `in_cast_radius(cell centre, r, o.centre())`: light: +1 if `o` mundane, −1 if occult;
  shadow: +1 if occult, −1 if mundane.
- Firing tower being placed: for each existing caster `o` with
  `in_cast_radius(o.centre(), o.stats().range_cells, cell centre)`: mundane: +1 per light
  caster, −1 per shadow caster; occult: the opposite.
- `CAST_WEIGHT := 3` (path cells one affected tower is worth; tunable const).
- Pick the highest `score'` among free cells with `path_score > 0`; ties keep the cached
  order (path score, then row-major), so the pick stays deterministic.
- Flags are read from the config, so under a variant without `casts_*` (the `lt70_old` arm)
  the term is 0 and placement is exactly today's: the lab arms differ only by the data.

Cost: about 121 buildable cells × towers on board per build, a few times a night; no cache
for the cast term (it depends on the board).

`RUN` json gains `lit_tower_ticks` and `shadow_tower_ticks` (sum over ticks of towers with
the flag) and `shadowed_mundane_builds` (mundane towers placed inside a sign): the cheap
observations that tell the arms apart (0 shadow ticks in a sign strategy = "measured
nothing"; `shadowed_mundane_builds` > 0 in `mixed` = placement did not work).

Expect `occult`/`madness` to gain (×1.3 on readers, signs clustering), `mixed` to keep its
riflemen out of shadow, sign strategies to leak more (slow 0.35 → 0.2).

Lab plan (after the code slice, `tools/balance/balance.py`, 20 seeds, all strategies):
- `baseline` (the new numbers) vs `lt70_old` (patch: Searchlight slows 0.2/0.25/0.25/0.4 +
  b ×1.2, sign slow 0.35, no `casts_*` flags, no `shadow` block) → the effect of the change.
- `lt70_shadow_off` (no `shadow` block) → the shadow's share alone.
- `lt70_no_sign_stack` (a lab-only check of §6.1: `shadow.occult.power_mult` 1.15) → how much
  sign stacking is worth.
- Tunables in order: `shadow.occult.power_mult` (1.2/1.3/1.4), sign slow (0.2/0.25),
  Searchlight L1 slow (0.25/0.3). Target stays LT-56: each strategy loses ≥ 10/20.

### 6.1 Balance risks / revisit later

Owner (Q4): "Да, как любую башню, но отметим что это сказывается на балансе и возможно стоит
пересмотреть в будущем".
- **Sign stacking.** Two signs in each other's radius shadow each other: slow 0.26, taken
  ×1.65, Corrupted strip 1.3, and both shadow the occult towers around them. Pure Ward r4
  makes chains easy, and the smart bot placement (§6) will seek them. Revisit if the lab
  shows `occult`/`madness` winning more than `baseline` mundane by a wide margin; the cheap
  fix is "signs are immune to shadow" (one `def.id`/flag check in `in_cast`).
- **Shadowed Necronomicon in MADNESS:** ×1.3 × madness ×2 = ×2.6 per hit.
- **Searchlight as the default pick:** slow 0.5 (b) + reveal + anti-madness (Q1) + mundane
  buff. Watch the `light` strategy's win rate against `mundane`.

## 7. Edit map

| file (lines) | function / key | change |
|---|---|---|
| `data/towers.json` 40-58 | `elder_sign` | slow 0.2 every level; `casts_shadow: 1`; role |
| `data/towers.json` 125-142 | `searchlight` | slows §3; `casts_light: 1`; drop b's ×1.2; roles |
| `data/economy.json` after `lighthouse` (14-40) | `shadow` | new block §3 |
| `sim/defs/economy_config.gd` 6-7, 55-58, 90-142 | `FIELDS`, new `ShadowConfig` class (`mundane_fire_interval_mult`, `mundane_miss_chance_add`, `occult_power_mult`), `parse`, new `_parse_shadow` | optional block + validation |
| `sim/defs/tower_def.gd` 140-170, 228-300 | `EFFECTS`, `FLAG_EFFECTS`, `NOT_WITH_BANISH`, `NOT_WITH_SUMMON`, `Level.parse` | two flags; support-only and not-both checks |
| `sim/core/sim_tower.gd` 29-31 | `lit` doc; new `shadowed` | net flags |
| `sim/core/sim_enemy.gd` 30 | `lit` | doc: beam, flare or a Searchlight |
| `sim/core/sim_event.gd` 15-17 | `TOWER_LIT` doc | payload `{lit, shadowed}` |
| `sim/core/simulation.gd` 1264-1289 | `_update_beam` | casters once per tick; tower net flags and enemy `lit` with the Searchlight term, all under `on`; event on either flip |
| `sim/core/simulation.gd` new, near 1354-1378 | `static in_cast_radius(c, range, p)`, `_in_cast(p, key, skip_id, casters)`, `_power_mult(t)`, `_interval_mult(t)` | helpers §2.1, §2.3 |
| `sim/core/simulation.gd` 1398-1460 | `_apply_auras` | doc; `pm` from `_power_mult(t)` |
| `sim/core/simulation.gd` 1462-1479 | `_apply_madness_buff`, `_madness_buff_blocked` | docs only ("lit" now includes a Searchlight) |
| `sim/core/simulation.gd` 1484-1621 | `_fire_towers` | damage, miss, interval via helpers; shadow miss add |
| `sim/core/simulation.gd` 1622-1677, 1678-1695 | `_cast_banish`, `_summon` | `power` via `_power_mult` |
| `sim/core/simulation.gd` 2200-2205 | `_roll_miss` | optional `extra` chance, clamp 1, still no draw at 0 |
| `scenes/board.gd` 20-50, 165-171 | consts `LIT_TINT`, `SHADOW_TINT`, `SHADOW_MARK_COLOR`; var `selected_cast` | §5 |
| `scenes/board.gd` 522-547 | `_draw` | BUILD preview tint on towers in the selected caster's radius |
| `scenes/board.gd` 605-617 | `_draw_tower`, new `static plate_color(t)` | tint + shadow dot |
| `scenes/board.gd` 628-645 | `_draw_auras` | ward dark fill |
| `ui/tower_picker.gd` 212-224, 320-330 | hover/clear | set/clear `board.selected_cast` from the def's L1 flags |
| `ui/tower_panel.gd` 97, 134-139 | close / refresh | set/clear `board.selected_cast` from the tower's level |
| `ui/lighthouse_panel.gd` 42 | open | clear `selected_cast` |
| `ui/tower_info.gd` 14-16, 120-150, 196-224, 323-402, 411-500 | consts, `kind_lines`, `ROWS`, `row_values`, beam/lit functions, effect texts | §5 |
| `ui/tower_panel.gd` 157-201 | `_refresh_table` | light vs shadow |
| `ui/stats_table.gd` 69-73, 109-110 | `set_columns` | shadow colour |
| `tools/bot_runs.gd` 14-35, 71-97 | header doc, `STRATEGIES`, `LIGHT_ORDER`, `BRANCH_PICK`, `CAST_WEIGHT` | `light` strategy |
| `tools/bot_runs.gd` 294-321 | `_order` | `light` branch |
| `tools/bot_runs.gd` 440-462 | `_best_cell`, new `_cast_term(sim, id, cell)` | §6 placement |
| `tools/bot_runs.gd` 164-290 | `_play` RUN json | three counters §6 |
| `tools/balance/variants/` | `lt70_old.json`, `lt70_shadow_off.json`, `lt70_no_sign_stack.json` | §6 |
| `docs/GDD.md` 99, 163-164, 184, 350-360 | tower rows, lighthouse section | **left to the code slice** |

Read only: `_lit_now` 1260, `_lit_by` 1360-1378, `_beam_on` 1241, `_is_lit` 1354 (point
query, beam only; stays so), `_apply_flare_slow` 1381, `step` 94-125, `shot_kind`
(`board.gd` 268-272), `selected_dead_zone` (`board.gd` 549-558).

## 8. Behaviours for the tests slice

Tests set `shadow` numbers through the test config where a deterministic outcome is needed
(e.g. `miss_chance_add` 1.0 → every shadowed mundane shot misses).

1. At night a tower within a Searchlight's range (centre to centre, inclusive) is lit
   without the beam; at range + 0.01 it is not; the Searchlight itself is not.
2. At night a tower within an Elder Sign's range is `shadowed`; the sign itself is not;
   another sign in range is shadowed (Q4).
3. By day (BUILD) the same layouts give `lit` false and `shadowed` false (Q2).
4. Cancel: lit by beam / flare / Searchlight and shadowed → `lit` false, `shadowed` false.
5. Shadowed mundane: cooldown = interval × 1.25; with `miss_chance_add` 1.0 every shot
   misses at Lucid; with 0.1 at Lucid exactly one COMBAT draw per shot (none unshadowed).
6. Shadowed occult: Necronomicon damage ×1.3; Resonator ×1.3 after sanity factor; Silver
   Key banish cells ×1.3; Circle unit dps ×1.3 at summon, kept after the sign is sold.
7. Elder Sign in another sign's radius: slow 0.26, taken ×1.65; lit Elder Sign ×0.7 as before.
8. A Searchlight in light or shadow keeps slow and reveal; Searchlight slows 0.3/0.35/0.35/0.5;
   Blinding no longer raises damage taken; Elder Sign slows 0.2.
9. Q1: at night a live enemy (real and fake) inside a Searchlight is `lit` and, in MADNESS,
   skips the madness buff; outside it gets the buff; by day not lit; inside a Searchlight
   and a sign it is lit; with no flare its speed is only the aura slow (no flare ×0.5).
10. `TOWER_LIT {lit, shadowed}` once per flip of either, id order; none while unchanged.
11. Config: `shadow` absent loads (×1.0); bad `power_mult` 0, `miss_chance_add` 1.5, unknown
    key rejected; `casts_light` on a damage level, both flags on one level, value 2 rejected.
12. Render: `plate_color` warm for lit, violet for shadowed, `COLOR_TOWER` for neither and for
    cancelled; BUILD preview: with `selected_cast` "shadow" on a cell, towers in its radius
    get the faint tint, the rest none; no preview at night.
13. UI: shadowed panel shows `*` cells with ×1.25 interval / ×1.3 damage, "* In shadow now"
    line, "In shadow" row.
14. Bot: placing an Elder Sign with two equal-path-score cells, one covering a rifleman,
    picks the other; a Searchlight picks the one covering the rifleman; with `casts_*`
    removed from the config the pick is today's; `light` strategy builds a Searchlight third.
15. Same seed, Elder Sign over a rifle: identical event logs on two runs.

Existing tests that pin today's numbers move with §3: `searchlight_test` (0.2, 0.4, ×1.2),
`occult_tower_test`, `branch_effects_test`, `beam_test` 494-509, `madness_buff_test`,
`stats_panel_test`, `tower_info_test`, `stats_rows_test` (new row), `bot_upgrade_test`.

Controls (revert the code, the named test must fail; 9, the ninth because the bot placement
is a separate test file and the lab's validity rests on it):
1. drop the Searchlight term from the tower `light_any` → 1;
2. drop the `o.id != t.id` check → 2 (sign shadows itself);
3. drop the `on and` gate from `shadow_any` → 3;
4. drop `and not shadow_any` from `lit` → 4;
5. drop the shadow interval mult → 5 (cooldown);
6. drop the shadow miss add → 5 (misses at 1.0);
7. `_power_mult` returns 1.0 for shadowed → 6 (Necronomicon; also fails the Circle case);
8. drop the Searchlight term from enemy `lit` → 9 (madness buff applies inside);
9. drop the cast term from `_best_cell` → 14 (sign takes the rifleman cell).

## 9. Questions (resolved)

Owner answers (verbatim):

**Q1. Does a Searchlight light enemies too (beam sense: they skip the madness buff)?**
Answer: **"Башни и врагов"**. → §2.1, §2.4: enemies in its radius are `lit` at night (madness
buff cancelled; flare slow unchanged, it is flare-only); enemies have no shadow.
Options asked: A. Towers only (Recommended); B. Towers and enemies.

**Q2. Do Searchlight light and Elder Sign shadow work during the build phase (day)?**
Answer: **"Только  ночью но надо как-то визуально показывать бафф/дебаф на башнях. Возможно
оттенком башен?"** → §2.1 (gated by `_beam_on`), §5 (warm / violet plate tint alongside the
corner dots; BUILD preview tint, my recommendation).
Options asked: A. Always, except after the game ends (Recommended); B. Only at night, like
the beam.

**Q3. Bot changes for the lab?**
Answer: **"Light и умная расстановка"**. → §6: `light` strategy and the cast term in
`_best_cell` for every strategy.
Options asked: A. New `light` strategy, placement as is (Recommended); B. A plus
light/shadow-aware placement; C. No bot change.

**Q4. Does an Elder Sign shadow another Elder Sign?**
Answer: **"Да, как любую башню, но отметим что это сказывается на балансе и возможно стоит
пересмотреть в будущем"**. → §4, §6.1 (sign stacking named as a balance risk to revisit).
Options asked: A. Yes, any other tower (Recommended); B. Signs are immune to shadow.
