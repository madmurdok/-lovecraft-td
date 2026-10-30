# LT-26 — Lighthouse beam: buffs mundane towers, weakens occult (design note)

Status: draft for owner review · 2026-10-31 · branch `docs/LT-26-lighthouse-beam-design`

Source: playtest 0.1 finding 8 (`docs/playtest-0.1.md`): "the lighthouse beam drives back
darkness and gives the defenders confidence: buffs mundane towers in it, weakens occult
ones". Lamp oil (finding 7, LT-27) is kept as a future beam resource.

## 0. What exists today and what this task adds

**Today** the beam is render-only. `scenes/lighting.gd` creates a `PointLight2D` cone at
the lighthouse cell and turns it in `_process` by `BEAM_SPEED = 0.45 rad/s` (one turn in
about 14 s), `BEAM_REACH_CELLS = 16`, `BEAM_HALF_ANGLE = 0.24 rad` (cone about 27° wide).
The sim (`sim/core/simulation.gd`) knows nothing about it: no tower is ever "lit".

Geometry of the current map (`data/map.json`, 24×14): the lighthouse `L` is at cell
(21, 10), bottom right; all land lies up and to the left of it, inside a quarter turn
(from "west" to "north"). The path entry `S` (0, 1) is 23.5 cells away, outside the
16-cell reach: the entry stays in darkness, the last third of the path is reachable.

Two numbers that drive the control question:

- **Today's full turn:** a tower is inside the 0.48 rad cone for 0.48 / 2π = **7.6 %** of
  the time, and three quarters of every turn light only sea. A +25 % fire-rate buff at
  7.6 % uptime is **+1.9 %** average DPS: invisible.
- **A fixed (aimed) beam** lights the same towers 100 % of the time, so the buff is a
  placement rule the player can read and plan around.

**This task (the follow-up implementation)** moves the beam into the sim: its direction
is sim state, updated in the fixed tick; every tick each tower gets a `lit` flag; mundane
lit towers get a buff, occult lit towers a debuff; the render layer draws the cone from the
sim's direction instead of its own timer.

Non-goals: the beam does not damage, slow or reveal enemies (the Searchlight's Revealing
branch stays the only fake counter); oil is not implemented here (§5, Q5).

```
command aim_beam(cell)  ──► state.beam.target_dir           (between ticks, also while paused)
step slot 2 _update_beam ─► state.beam.dir turns toward target, then tower.lit for every tower
step slot 2 _apply_auras ─► Elder Sign strength × occult multiplier if lit
step slot 5 _fire_towers ─► fire interval / damage / miss chance use lit modifiers
step slot 6 sanity       ─► LT-23 passive drain × lit multiplier (if Q3 = A)
render  lighting.gd      ─► beam.rotation = atan2(sim dir), interpolated; lit marker on towers
```

---

## 1. Beam model in the sim

### 1.1 Direction without trig

LT-4 §4 forbids `sin/cos/atan2/pow` in gameplay math (libm may differ desktop vs web).
So the beam direction is a **unit vector**, not an angle:

- `state.beam.dir: Vector2` (64-bit components kept as two `float`s, not a `Vector2`, which
  is 32-bit; LT-4 §4) and `state.beam.target_dir`.
- **Lit test** for a tower centre `p`, lighthouse centre `L`, `v = p - L`:
  `|v|² ≤ reach²` and `v·dir > 0` and `cross(v, dir)² ≤ k² · (v·dir)²`, where
  `k = tan(half angle)` is a **config number** (`half_width_ratio`, e.g. 0.25 ≈ 14°). Only
  `+ - * /`, so bit-identical everywhere.
- **Turning** toward `target_dir` (aimed mode) or around (auto mode): rotate `dir` each tick
  by a fixed small rotation `(c, s)` derived from a config rational `t` by
  `c = (1 - t²)/(1 + t²)`, `s = 2t/(1 + t²)` (exact, no libm), then renormalise with `sqrt`.
  In aimed mode the beam stops turning when the next step would pass the target (sign of
  `cross(dir, target_dir)` flips) and snaps `dir = target_dir`.
- Render: `lighting.gd` sets `beam.rotation = atan2(dir.y, dir.x)` (trig is fine in render),
  interpolated between the previous and current tick like enemy positions (LT-4 §1.2).
  The cone texture's half angle is set from the same `half_width_ratio` so what the player
  sees is exactly what the sim lights.

### 1.2 Player command (if Q1 = C)

- `Simulation.aim_beam(cell: Vector2i) -> CommandResult`: sets `target_dir` to the unit
  vector from `L` to the cell centre. Rejected if the cell is `L` itself. Free, no cooldown,
  allowed in build phase, during a wave and while paused (LT-4 §1.3: commands apply between
  ticks; the turn itself only happens in ticks). Recorded in the command log like `build`.
- Input: a "Beam" button / hotkey `B` toggles aim mode; the next click on any cell sets the
  target; right-click cancels. A faint target line shows where the beam is turning to.
- Start of the run: the beam points at the path cell nearest the lighthouse at half reach
  (deterministic default from the map), so a player who never aims still gets a useful beam.

### 1.3 Config

New `beam` block inside the existing `lighthouse` block of `data/economy.json` (already loaded,
holds `hp`); `EconomyConfig` gets a `BeamConfig` with validation in `config_reader.gd`:

```jsonc
"lighthouse": {
  "hp": 20,
  "beam": {
    "mode": "aimed",                 // "aimed" | "sweep" | "rotate" (Q1 options, a switch)
    "reach_cells": 16,
    "half_width_ratio": 0.25,        // tan of the half angle (~14 deg)
    "turn_t": 0.01,                  // rotation rational: ~0.02 rad/tick = 0.6 rad/s
    "mundane": { "fire_interval_mult": 0.8, "ignore_miss": true },
    "occult":  { "power_mult": 0.7, "drain_mult": 0.5 }
  }
}
```

Keeping all three modes behind `mode` is cheap (same lit test, different turn rule) and lets
the bots measure Q1 instead of arguing it. Numbers are placeholders for the measure slice.

### 1.4 Where the modifiers apply (existing code)

- `SimTower` gets `var lit := false`, written once per tick in slot 2 before `_apply_auras`.
- **Mundane, lit** (`_fire_towers`): cooldown `ticks(fire_interval × fire_interval_mult)`;
  `ignore_miss` skips `_roll_miss()` (the COMBAT stream is then not consumed for that shot,
  which is a deterministic, seed-stable choice; tests pin it).
- **Occult, lit**: Necronomicon damage × `power_mult` (applied before the madness ×2);
  Elder Sign in `_apply_auras`: slow × `power_mult`, damage-taken bonus
  `1 + (mult − 1) × power_mult`. LT-23's passive drain (`sanity_per_second`) × `drain_mult`.
- Events: `BEAM_CHANGED {dir, target}` when the target is set, `TOWER_LIT {lit}` when a
  tower's flag flips (render marker, side panel from LT-24).

---

## 2. Example with today's numbers

| Tower (L1) | Dark | Lit (recommended numbers) | Change |
|---|---|---|---|
| Rifleman, Lucid | 10 dmg / 0.8 s = 12.5 DPS | 10 / 0.64 s = 15.6 DPS | +25 % |
| Rifleman, Fraying (15 % miss) | 10.6 DPS | 15.6 DPS (no misses) | +47 % |
| Necronomicon Reader | 40 AoE / 4 s = 10 DPS per target, −2 sanity/cast | 28 AoE = 7 DPS | −30 % |
| Elder Sign | slow 30 %, +25 % damage taken | slow 21 %, +17.5 % | −30 % strength |

A board of 6 riflemen and 2 Readers: aiming the beam at the riflemen and keeping the Readers
outside it is worth about +19 DPS in Lucid; aiming it at the Readers by mistake costs 6 DPS.

---

## 3. Sanity

The beam is the mundane answer to sanity pressure: "the light gives the defenders confidence".
The recommended link is through **misses**, not through the sanity pool: lit mundane towers
ignore the Fraying/Madness miss chance (`sanity.json` `miss_chance` 0.15). So the beam matters
more the lower sanity falls, without making sanity easier to keep. Other options in Q4.

## 4. Interplay with LT-23 (parallel)

LT-23 makes occult towers much stronger, adds a constant per-tower sanity drain
(`sanity_per_second`, parsed but unused today) and makes enemies stronger in Madness.

- **Recommended trade (Q3 = A):** a lit occult tower is weaker (`power_mult` 0.7) but also
  drains less (`drain_mult` 0.5). With LT-23's strong occult towers this turns the beam into a
  choice, not a pure penalty: light the occult cluster to slow the sanity slide at the cost of
  damage, or light the mundane line for DPS. Example with a hypothetical LT-23 drain of
  0.3/s per tower: 3 occult towers drain 0.9/s = 54 sanity over a 60 s wave; lit, 27.
- **Order:** LT-26 implementation starts after LT-23's code slice merges (both change
  `_fire_towers`, `_apply_auras` and the sanity slot); LT-26 multipliers apply on top of
  LT-23's final tower numbers. Its measure slice runs after LT-23's tuning, so the beam is
  balanced against the new occult strength, not against today's weak occult towers.
- **Madness enemy buff (LT-20 folded into LT-23):** the beam does not cancel it in the
  recommendation (Q4 option C would).

## 5. Lamp oil (future resource)

Owner's idea: buy oil to make the lighthouse shine brighter. LT-27 settled one currency,
Relics; amber is folded into Relics' lore, so oil would be the first second resource.
Recommended for now: **design hooks only** (Q5 = A). The beam block already carries every
number oil would raise (`reach_cells`, `half_width_ratio`, the multipliers, `turn_t`), so a
later "Lamp oil" task adds a `brightness` level that scales them, without touching the lit
test. Sketch for that task (not built here): in the build phase, spend 60 Relics on oil →
the next wave the cone is 1.5× wider and the mundane buff 1.4× stronger; oil burns out at
the wave end. Open there: oil bought vs. dropped by enemies, burn per wave vs. per second,
what happens at zero oil (dim beam, never off).

---

## 6. Open questions

### Q1. How is the beam controlled?

**Today:** the beam is a picture: it turns on its own, one full turn every 14 s, and changes
nothing in the game. **Change:** the beam becomes a game rule: towers inside it get buffs or
debuffs. How it moves decides whether that rule is luck or a decision.
**Example:** a rifleman 8 cells from the lighthouse, +25 % fire rate when lit.

- **C. Player-aimed (recommended).** You click "Beam" (or `B`), then a cell; the beam turns
  there at about 0.6 rad/s (a quarter turn in 2.6 s) and stays. The rifleman is lit 100 % of
  the time if you aim at it: +25 % DPS. Benefit: a readable, plannable choice each wave (light
  the mundane line, keep occult in the dark, re-aim when the Shoggoth arrives). Risk: one more
  thing to manage; bots need an aiming policy; a fixed beam on a fixed path becomes a "set
  once" choice until Map v2 (LT-18) changes the path per wave.
- **B. Automatic sweep over land.** The beam swings back and forth across the land quarter
  only (never the sea). The rifleman is lit about 30 % of the time: +7.5 % average. Benefit:
  no input, still noticeable, lively look. Risk: weak and random-feeling; the player can only
  place towers by the sweep, which is hard to read.
- **A. Automatic full turn as today.** Lit 7.6 % of the time: +1.9 % average. Benefit: no
  change in feel. Risk: the effect is invisible; the finding is not really addressed.
- **D. Automatic sweep, aiming costs oil.** B by default; spend oil to hold the beam on a
  spot for a wave. Benefit: links to the oil idea. Risk: needs the oil resource now (Q5),
  doubles the scope.

All modes stay behind a config switch, so the choice can be revisited after bot runs.

### Q2. What does the beam give mundane towers?

**Today:** mundane towers (Rifleman, Harpooner; later Searchlight) have fixed stats and miss
15 % of shots when sanity is below 40. **Change:** a lit mundane tower gets a bonus.
**Example:** Rifleman L1 deals 12.5 DPS in the dark, 10.6 DPS while Fraying.

- **A. +25 % fire rate and no misses (recommended).** Lit: 15.6 DPS in any sanity state
  (+25 % lucid, +47 % fraying). Benefit: ties "confidence" to the sanity system, matters most
  when things go wrong. Risk: mundane is already the stronger strategy (playtest: mundane
  never loses HP); needs LT-23's difficulty pass to land first.
- **B. +20 % damage only.** Lit: 15 DPS lucid, 12.7 fraying. Benefit: simplest, one number.
  Risk: no link to sanity; flat damage also pierces armor better, which shifts the Hybrid/
  Shoggoth balance.
- **C. +1 cell range.** Rifleman 3 → 4 cells. Benefit: visible on the range circle. Risk:
  range on a fixed path is worth very different amounts per spot; hard to tune.

### Q3. What does the beam do to occult towers?

**Today:** occult towers (Elder Sign, Necronomicon Reader) are unaffected by light; after
LT-23 they will be much stronger and drain sanity every second just by standing on the board.
**Change:** a lit occult tower is weakened.
**Example:** a Reader (40 AoE every 4 s) and a hypothetical LT-23 drain of 0.3 sanity/s.

- **A. −30 % power, but half the passive drain (recommended).** Lit Reader: 28 AoE, drains
  0.15/s. Benefit: the beam becomes a trade (damage vs. sanity), which gives the occult player
  a reason to use it too. Risk: if the drain is the main occult cost, lighting all occult
  towers may become the default; the measure slice must check it.
- **B. −40 % power, no drain change.** Lit Reader: 24 AoE. Benefit: a clean "light hurts the
  occult" rule. Risk: for the occult player the beam is only ever a penalty to point away.
- **C. Lit occult towers stop working.** Benefit: strongest, most legible rule. Risk: with an
  aimed beam the player just never lights them; with an automatic beam it is a random off
  switch that feels unfair.

### Q4. Does the beam touch sanity or madness directly?

**Today:** sanity falls from Elder Signs, Reader casts and horror (big enemies near towers),
and regenerates +12 between waves and +0.5 per mundane kill. **Change (options):**
**Example:** sanity 35 (Fraying), a lit rifleman line.

- **A. No direct effect; only through misses (recommended).** Lit riflemen stop missing (Q2 A);
  sanity itself moves as today. The beam works the same in Madness. Benefit: one clear rule,
  no new sanity source to balance against LT-23. Risk: none of the "light drives back the
  darkness" shows on the sanity bar.
- **B. Lit mundane towers regenerate sanity.** E.g. +0.05/s per lit mundane tower: 6 lit
  riflemen give +0.3/s, +18 over a 60 s wave. Benefit: the bar shows the light's effect. Risk:
  a new regen source works against LT-23's sanity pressure; a mundane board could cancel horror
  drain.
- **C. Enemies in the beam lose the LT-23 Madness buff.** Benefit: the light pushes back the
  madness world. Risk: touches LT-23's design; adds an enemy-side rule to an otherwise
  tower-side feature.

### Q5. Lamp oil: now or later?

**Today:** there is one currency (Relics after LT-27); the lighthouse has only HP.
**Change:** oil would be a resource that makes the beam brighter.
**Example:** 60 Relics → oil for one wave → cone 1.5× wider, mundane buff 1.4× stronger.

- **A. Later; hooks only (recommended).** This task keeps every beam number in config so a
  future "Lamp oil" task scales them; the GDD keeps oil as an idea. Benefit: LT-26 stays small
  and lands in 0.2.0. Risk: the beam has no economy decision until the oil task.
- **B. Now, as a Relics purchase per wave.** Benefit: the owner's idea in the game this release.
  Risk: a second economy lever on top of LT-23's rebalance makes both harder to tune; doubles
  the scope.
- **C. Now, as a resource dropped by enemies.** Benefit: lore fit (whale oil, deep-one fat).
  Risk: same as B plus a drop system.

---

## 7. Proposed follow-up task

**Title:** Lighthouse beam in the sim: aimed beam buffs mundane, weakens occult towers

**Description:** Implement LT-26's design note: beam direction as sim state with the
trig-free lit test, `aim_beam` command and input, per-tower `lit` flag, mundane/occult
modifiers from `economy.json` `lighthouse.beam`, LT-23 drain multiplier, render from the sim
direction with a lit marker, bot aiming policy. Depends on LT-23 (code slice merged; measure
after LT-23 tuning).

**Acceptance criteria:**
- Beam direction and `lit` live in the sim; `lighting.gd` has no timer of its own; same seed +
  command log → identical events (including `aim_beam`).
- Lit test uses only `+ - * / sqrt`; a cone-boundary test pins inside/outside on both sides.
- Mundane and occult modifiers, and the drain multiplier, are config-driven and validated;
  tests with controls (revert each modifier → its test fails).
- Bots aim the beam (mundane bot: at its towers' centroid; occult bot: per Q3); 10-seed table
  shows the beam's effect (beam on vs. `mode: rotate` as the control arm).
- Owner replay: the lit area reads on screen and the choice where to aim matters.

**Rough slicing:**
1. S1 implement (opus): sim beam state, lit test, turn rule, config + reader, modifiers in
   `_apply_auras` / `_fire_towers` / sanity slot, `aim_beam` command.
2. S2 verify (opus): review the sim diff against this note.
3. S3 implement (sonnet, with an edit map): `lighting.gd` reads the sim, interpolation, aim
   input (`B` + click), lit marker; side-panel line if LT-24 has landed.
4. S4 tests (opus): lit test geometry, turn/snap, each modifier, determinism with `aim_beam`;
   6-8 controls.
5. S5 measure (sonnet): bot aiming policy, 10-seed tables per strategy, tune multipliers;
   `mode: rotate` as the control arm.
6. S6 verify (opus): fresh agent, full suite, controls in a throwaway worktree.
