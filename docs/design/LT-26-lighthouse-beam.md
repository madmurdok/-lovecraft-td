# LT-26 — Lighthouse beam: buffs mundane towers, weakens occult (design note)

Status: approved · 2026-10-31 · branch `docs/LT-26-lighthouse-beam-design`

Source: playtest 0.1 finding 8 (`docs/playtest-0.1.md`): "the lighthouse beam drives back
darkness and gives the defenders confidence: buffs mundane towers in it, weakens occult
ones". Lamp oil (finding 7, LT-27) is kept as a future beam resource. Owner decisions: §6.

## 0. What exists today and what this task adds

**Today** the beam is render-only. `scenes/lighting.gd` creates a `PointLight2D` cone at
the lighthouse cell and turns it in `_process` by `BEAM_SPEED = 0.45 rad/s` (one turn in
about 14 s), `BEAM_REACH_CELLS = 16`, `BEAM_HALF_ANGLE = 0.24 rad` (cone about 27° wide).
The sim (`sim/core/simulation.gd`) knows nothing about it: no tower is ever "lit".

Geometry of the current map (`data/map.json`, 24×14): the lighthouse `L` is at cell
(21, 10), bottom right; all land lies up and to the left of it, inside a quarter turn
(from "west" to "north"). The path entry `S` (0, 1) is 23.5 cells away, outside the
16-cell reach: the entry stays in darkness, the last third of the path is reachable.

**Coverage:** one beam of 0.48 rad turning a full circle lights a given tower (within reach)
0.48 / 2π = **7.6 %** of the time. Beams are evenly spaced, so the lighthouse levels give:

| Lighthouse level | Beams | Spacing | Coverage per tower |
|---|---|---|---|
| L1 (start) | 1 | — | 7.6 % |
| L2 | 2 | 180° | 15.3 % |
| L3 | 4 | 90° | 30.6 % |
| (not used) 8 beams | 8 | 45° | 61 %: near-global buff, kept out of the default levels |

**This task (the follow-up implementation)** moves the beam into the sim: beam directions
are sim state, turned in the fixed tick; every tick each tower and each enemy gets a `lit`
flag; lit mundane towers get a buff, lit occult towers a debuff, lit enemies lose LT-23's
Madness buff; the lighthouse becomes an upgradeable structure whose levels add beams; the
render layer draws the cones from the sim instead of its own timer.

Non-goals: the beam does not damage, slow or reveal enemies (the Searchlight's Revealing
branch stays the only fake counter); the player does not aim the beam; oil is not
implemented here (§5).

```
command upgrade(lighthouse)  ─► state.lighthouse_level += 1  (LT-24 upgrade command, between ticks)
step slot 2 _update_beam ─► rotate base dir; beam i = base dir rotated by i × spacing;
                             tower.lit / enemy.lit for every tower and live enemy
step slot 2 _apply_auras ─► Elder Sign strength × occult multiplier if lit
step slot 2/3 LT-23 buff ─► Madness enemy buff skipped for lit enemies
step slot 5 _fire_towers ─► fire interval / damage / miss roll use lit modifiers
step slot 6 sanity       ─► LT-23 passive drain × drain multiplier for lit occult towers
render  lighting.gd      ─► one cone per beam, rotation = atan2(sim dir), interpolated
```

---

## 1. Beam model in the sim

### 1.1 Directions without trig

LT-4 §4 forbids `sin/cos/atan2/pow` in gameplay math (libm may differ desktop vs web).
So beam directions are **unit vectors**, not angles:

- `state.beam` holds one base direction as two 64-bit `float`s (`Vector2` is 32-bit, LT-4 §4)
  and `beam_count` (from the lighthouse level).
- **Beam i** = base direction rotated by `i × 2π / beam_count`, built without trig:
  2 beams → negate; 4 beams → add the two perpendiculars `(−y, x)` and `(y, −x)`; 8 beams
  → the 45° rotation with `c = s = sqrt(0.5)`. So `beam_count` is validated to 1, 2, 4 or 8.
- **Lit test** for a point `p` (tower centre, or enemy route position), lighthouse centre `L`,
  `v = p − L`, beam direction `d`: `|v|² ≤ reach²` and `v·d > 0` and
  `cross(v, d)² ≤ k² · (v·d)²`, where `k = tan(half angle)` is a **config number**
  (`half_width_ratio`; 0.245 matches today's 0.24 rad). Lit = inside **any** beam; overlaps
  do not stack. Only `+ − * / sqrt`, so bit-identical everywhere.
- **Turning:** each tick rotate the base direction by a fixed small rotation `(c, s)` from a
  config rational `t`: `c = (1 − t²)/(1 + t²)`, `s = 2t/(1 + t²)` (exact, no libm; the angle
  per tick is `2·atan(t)`), then renormalise with `sqrt`. Today's speed 0.45 rad/s =
  0.015 rad/tick → `t = 0.0075`. A negative `t` turns the other way.
- **Pattern switch** `pattern`: `"rotate"` (default, full turn as today) or `"sweep"`
  (base direction swings back and forth across the land arc, reversing `t` when it crosses
  an edge vector from config). Both use the same lit test, so the measure slice can compare
  them; the default stays the owner's choice.
- Start of the run: the base direction points left (as `lighting.gd` does today, `PI`), so
  the first sweep goes over land.
- Render: `lighting.gd` draws `beam_count` cones; each `rotation = atan2(d.y, d.x)` (trig is
  fine in render), interpolated between the previous and current tick like enemy positions
  (LT-4 §1.2). The cone texture's half angle and reach come from the same config, so what
  the player sees is exactly what the sim lights.

### 1.2 Lighthouse upgrades

- The lighthouse is a **special upgradeable structure**: it is not a `SimTower` (no shots,
  cannot be sold or built), but it is a valid target of LT-24's upgrade command. LT-26 adds a
  target kind "lighthouse" to that command; its exact API (method name, rejection reasons,
  logging) follows LT-24's design note.
- `state.lighthouse_level` (0 = L1). Upgrade checks: next level exists, enough Relics
  (LT-27 currency; internal `gold`), allowed in build phase and during a wave, also while
  paused (LT-4 §1.3). Paid through `_add_gold`; event `LIGHTHOUSE_UPGRADED {level, beams}`.
  The new beams appear on the next tick, evenly spaced from the current base direction.
- No refund (the lighthouse is never sold). Lighthouse HP does not change with level.
- UI: clicking the lighthouse cell opens LT-24's side panel with level, beam count,
  coverage and the upgrade button.

### 1.3 Config

New `beam` block inside the existing `lighthouse` block of `data/economy.json` (already loaded,
holds `hp`); `EconomyConfig` gets a `BeamConfig` with validation in `config_reader.gd`.
Costs and multipliers are tunable placeholders for the measure slice:

```jsonc
"lighthouse": {
  "hp": 20,
  "beam": {
    "pattern": "rotate",             // "rotate" | "sweep"
    "turn_t": 0.0075,                // ~0.015 rad/tick = 0.45 rad/s, one turn in 14 s
    "reach_cells": 16,
    "half_width_ratio": 0.245,       // tan of the half angle (0.24 rad today)
    "sweep_edges": [[-1, 0], [0, -1]], // only for "sweep": land arc of the current map
    "levels": [
      { "beams": 1 },
      { "beams": 2, "upgrade_cost": 120 },
      { "beams": 4, "upgrade_cost": 250 }
    ],
    "mundane": { "fire_interval_mult": 0.8, "ignore_miss": true },
    "occult":  { "power_mult": 0.7, "drain_mult": 0.5 },
    "enemy":   { "cancel_madness_buff": true }
  }
}
```

Validation: `beams` in {1, 2, 4, 8} and non-decreasing; `upgrade_cost` > 0 from L2 on;
`half_width_ratio` > 0; multipliers > 0; `pattern` known. Adding an 8-beam level later is a
data change only.

### 1.4 Where the modifiers apply (existing code)

- `SimTower` gets `var lit := false`; `SimEnemy` gets `var lit := false` (reset with the
  other per-tick modifiers in slot 1). Both written in slot 2, before `_apply_auras`.
- **Mundane, lit** (`_fire_towers`): the cooldown set after a shot uses
  `ticks(fire_interval × fire_interval_mult)` (decided at the shot, so a tower that leaves the
  beam keeps its shorter cooldown once; tests pin it); `ignore_miss` skips `_roll_miss()` (the
  COMBAT stream is then not consumed for that shot: deterministic and seed-stable).
- **Occult, lit**: Necronomicon damage × `power_mult` (before the madness ×2); Elder Sign in
  `_apply_auras`: slow × `power_mult`, damage-taken bonus `1 + (mult − 1) × power_mult`.
  LT-23's passive drain (`sanity_per_second`) × `drain_mult` for the ticks the tower is lit.
- **Enemy, lit**: LT-23's Madness enemy buff is not applied that tick (§4).
- Events: `TOWER_LIT {lit}` when a tower's flag flips (render marker, LT-24 panel). No event
  for enemies (too frequent; the render layer reads `lit` from state if it needs it).

---

## 2. Example with today's numbers

While lit (L1 towers):

| Tower (L1) | Dark | Lit | Change while lit |
|---|---|---|---|
| Rifleman, Lucid | 10 dmg / 0.8 s = 12.5 DPS | 10 / 0.64 s = 15.6 DPS | +25 % |
| Rifleman, Fraying (15 % miss) | 10.6 DPS | 15.6 DPS (no misses) | +47 % |
| Necronomicon Reader | 40 AoE / 4 s = 10 DPS per target | 28 AoE = 7 DPS | −30 % |
| Elder Sign | slow 30 %, +25 % damage taken | slow 21 %, +17.5 % | −30 % strength |

Averaged over a turn, by lighthouse level (coverage from §0):

| Effect | L1 (7.6 %) | L2 (15.3 %) | L3 (30.6 %) |
|---|---|---|---|
| Rifleman, Lucid | +1.9 % | +3.8 % | +7.6 % |
| Rifleman, Fraying | +3.6 % | +7.2 % | +14.4 % |
| Reader damage | −2.3 % | −4.6 % | −9.2 % |
| Occult passive drain (×0.5 while lit) | −3.8 % | −7.6 % | −15.3 % |

So at L1 the beam is mostly flavour; the lighthouse upgrades are what make it matter, and
they cost Relics that would otherwise go to towers. If L3 still feels weak, the measure slice
raises the multipliers or the cone width, not the beam count (8 beams = 61 % coverage, a
near-global buff).

---

## 3. Sanity

Two links, both decided (§6):

- **Misses:** lit mundane towers ignore the Fraying/Madness miss chance (`sanity.json`
  `miss_chance` 0.15): the beam matters more the lower sanity falls.
- **Madness world pushed back:** enemies inside a beam lose LT-23's Madness enemy buff (§4).

The beam adds no sanity regen and no drain of its own; the sanity pool moves only through the
halved occult drain while lit (§1.4).

## 4. Interplay with LT-23 (parallel)

LT-23 makes occult towers much stronger, adds a constant per-tower sanity drain
(`sanity_per_second`, parsed but unused today) and makes enemies stronger in Madness
(LT-20 folded in).

- **Occult trade:** a lit occult tower is weaker (`power_mult` 0.7) but drains half
  (`drain_mult` 0.5) while lit. Example with a hypothetical LT-23 drain of 0.3/s per tower,
  L3 lighthouse: 3 occult towers drain 0.9/s = 54 sanity over a 60 s wave dark; with 30.6 %
  of the time lit, about 46.
- **Madness enemy buff:** a lit enemy loses it for the ticks it is lit. This **depends on
  LT-23's buff design, still open there**:
  - Which stats: if the buff is speed, the lit test runs before `_move` (slot 2 already is);
    if it is HP or armor, a lit enemy uses base armor for hits that tick, and a max-HP buff
    cannot be taken away per tick (it would need "bonus HP shield" semantics). LT-26's code
    slice follows whatever LT-23 decides; if the buff is max HP, LT-26 needs a follow-up
    decision.
  - Fakes: the rule is "whatever LT-23 buffs, a lit beam removes", for real and fake enemies
    alike. If LT-23 buffs fakes too, lit fakes lose it too; the render layer must show the
    loss the same way for both, so the beam never tells fakes apart (LT-12 §1).
- **Order:** LT-26 implementation starts after LT-23's code slice and LT-24's upgrade command
  merge (both change `_fire_towers`, `_apply_auras`, the sanity slot and the command API).
  LT-26's measure slice runs after LT-23's tuning, so the beam is balanced against the new
  occult strength, not against today's weak occult towers.

## 5. Lamp oil (future resource)

Owner's idea: buy oil to make the lighthouse shine brighter. LT-27 settled one currency,
Relics; amber is folded into Relics' lore, so oil would be the first second resource.
Decided: **hooks only** in LT-26. The beam block already carries every number oil would
raise (`reach_cells`, `half_width_ratio`, `turn_t`, the multipliers), so a later "Lamp oil"
task adds a `brightness` factor that scales them, without touching the lit test or the
level/beam-count model. Sketch for that task (not built here): spend Relics on oil in the
build phase → the next wave the cones are 1.5× wider. Open there: oil bought vs. dropped by
enemies, burn per wave vs. per second, what happens at zero oil (dim beam, never off).

---

## 6. Decisions (owner, 2026-10-31)

### D1. Beam control: lighthouse levels add beams

Chosen: **"Уровни добавляют лучи 1→2→4"** (the owner's own idea). The beam keeps rotating
automatically as today (full turn, 14 s); the lighthouse is upgradeable through LT-24's
upgrade command and its levels add beams 1 → 2 → 4 (coverage 7.6 % → 15 % → 30 %). The owner
also asked about levels up to 4× or 8× beams and about tuning rotation speed and pattern;
8 beams (~61 %) was flagged as a near-global buff. Result: beam count per level, rotation
speed and pattern stay in config (§1.3); default levels stop at 4 beams; costs are tunable
placeholders. Rejected: player-aimed beam, automatic sweep over land as the default (kept as
a config pattern), aiming with oil.

### D2. Mundane towers in the beam

Chosen: **"+25% скорострельности и без промахов (Recommended)"**. Lit mundane towers fire
25 % faster (`fire_interval × 0.8`) and never miss.

### D3. Occult towers in the beam

Chosen: **"−30% силы, но дренаж вдвое меньше (Recommended)"**. Lit occult towers have −30 %
power (Reader damage, Elder Sign slow and damage-taken bonus) and their LT-23 passive drain
is halved while lit.

### D4. Sanity and madness

Chosen: **"Враги в луче теряют усиление безумия"**. Enemies inside a beam lose LT-23's
Madness enemy buff while lit. Depends on LT-23's buff design (stats, fakes included or not),
see §4.

### D5. Lamp oil

Chosen: **"Позже, сейчас только задел (Recommended)"**. No oil in LT-26; config hooks only
(§5).

---

## 7. Proposed follow-up task

**Title:** Lighthouse beam in the sim: upgradeable lighthouse, beams buff mundane, weaken
occult, cancel the Madness buff

**Description:** Implement LT-26's design note: beam directions as sim state with the
trig-free lit test and rotation (§1.1); lighthouse as an upgradeable structure through
LT-24's upgrade command, levels adding beams 1 → 2 → 4 (§1.2); config block
`economy.json` `lighthouse.beam` with validation (§1.3); per-tower and per-enemy `lit` flag;
mundane buff, occult debuff and halved LT-23 drain, Madness enemy buff cancelled for lit
enemies (§1.4, §4); render of `beam_count` cones from the sim, lit marker, lighthouse panel;
bot policy for lighthouse upgrades. **Depends on** LT-24 (upgrade command, code slice merged)
and LT-23 (passive drain and Madness enemy buff, code slice merged; measure after LT-23
tuning).

**Acceptance criteria:**
- Beam directions, `lighthouse_level` and `lit` live in the sim; `lighting.gd` has no timer of
  its own; same seed + command log → identical events (including lighthouse upgrades).
- Lit test and rotation use only `+ − * / sqrt`; geometry tests pin inside/outside on both
  sides of a cone edge, for 1, 2 and 4 beams.
- Lighthouse upgrade through LT-24's command: cost paid, rejected without Relics or at max
  level, beam count follows the level.
- Mundane buff, occult debuff, drain multiplier and Madness-buff cancel are config-driven and
  validated; each has a test with a control (revert the modifier → its test fails).
- Bots upgrade the lighthouse; 10-seed table per strategy with beam on vs. a control arm
  (beam modifiers set to 1.0), so the beam's effect is measured, not assumed.
- Owner replay: the cones read on screen, the lighthouse upgrade feels worth its cost.

**Rough slicing:**
1. S1 implement (opus): sim beam state, lit test, rotation and pattern, config + reader,
   lighthouse level and upgrade target in LT-24's command, modifiers in `_apply_auras` /
   `_fire_towers` / sanity slot / LT-23 Madness buff.
2. S2 verify (opus): review the sim diff against this note.
3. S3 implement (sonnet, with an edit map): `lighting.gd` draws the cones from the sim with
   interpolation, lit marker on towers, lighthouse panel with the upgrade button (LT-24 UI).
4. S4 tests (opus): geometry for 1/2/4 beams, rotation determinism, upgrade command, each
   modifier, Madness-buff cancel (real and fake per LT-23); 6-8 controls.
5. S5 measure (sonnet): bot lighthouse-upgrade policy, 10-seed tables per strategy, tune
   multipliers and costs; control arm with beam modifiers at 1.0.
6. S6 verify (opus): fresh agent, full suite, controls in a throwaway worktree.
