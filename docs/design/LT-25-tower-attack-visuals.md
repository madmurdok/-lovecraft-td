# LT-25 — Visually distinct tower attacks (visual spec)

Status: draft for owner review · 2026-10-31 · branch `feat/LT-25-distinct-tower-attacks`
Source: playtest 0.1 finding 4 (`docs/playtest-0.1.md`): "Towers all look like they shoot
the same; the difference is unclear even in the demo."

Grey-box only: shapes, colours, motion. No sprites, no final art (art style is undecided
and is neither pixel art nor 1920s engraving). Everything is drawn with `draw_*` calls in
`scenes/board.gd`, as today.

## 0. What exists today

- `Board.on_event` turns every `SHOT` into one `"shot"` effect: a 2 px pale-yellow line
  from the tower centre to `data.to`, 0.12 s (`SHOT_SECONDS`). Rifleman, harpooner and
  Necronomicon all draw this line; only the harpoon line is longer (its `to` is the line
  end at full range). An empty astray shot (`astray: true`, `hits: []`) draws the LT-14
  wavering bolt off its aim point.
- Elder Sign never fires (damage 0): it has no attack visual at all. Its range ring shows
  only while the tower is selected.
- Towers are identical grey squares with the first letter of their name.
- Enemies show no effect: nothing on screen says "slowed" or "takes more damage".
- A mundane miss (Fraying/Madness, LT-12 §4: `miss: true`, `hits: []`) draws exactly like a
  hit.

### Effect data the sim already gives the render

| Effect | Source | Where the render reads it | Event? |
|---|---|---|---|
| shot shape | `t.stats().effects` has `pierce` (line) / `aoe_radius` (blast) / neither (single) | `game.sim.tower_by_id(ev.id).stats()` | `SHOT` (`def`, `target`, `hits`, `to`, `miss`, `astray`) |
| AoE radius | `stats().effects.aoe_radius` (1.5) | same | — |
| slow | `SimEnemy.speed_mult < 1` (Elder Sign aura, rebuilt every tick in slot 2) | `e.speed_mult` in `_draw_enemies` | none (state) |
| damage-taken | `SimEnemy.damage_taken_mult > 1` (same aura) | `e.damage_taken_mult` | none (state) |
| bleed | **not in the sim**: `bleed_dps`/`bleed_seconds` (harpooner L3 branch a, Barbed) are parsed but not applied; LT-24 adds upgrades but still does not apply them | — | — |
| pull | **not in the sim**: `pull_cells` (Chain harpoon) parsed, not applied | — | — |

Slow and damage-taken are per-tick state, not events; after `sim.step()` they hold that
tick's aura values, so reading them at draw time is correct. Auras cover fakes too, so the
markers are identical on real and fake enemies: render isolation (LT-12 §1,
`tests/render_isolation_test.gd`) is unaffected. Nothing in this spec reads `is_fake`.

## 1. Attack look per tower

The shot kind is chosen from the tower's **current stats**, not its def id, so LT-23
(occult power) and LT-24 (upgrades/branches) change it automatically:
`pierce > 0` -> `"harpoon"`, `aoe_radius > 0` -> `"wave"`, otherwise `"tracer"`; a support
level (damage 0 with `slow`/`damage_taken_multiplier`) -> aura (drawn from state, §1.3).

Each tower body gets a 2 px border and letter in its attack colour (body stays grey), so
the eye links the effect to its source.

Colours below are pre-darkness values; the world is under a `CanvasModulate` of
(0.30, 0.32, 0.42), so every effect colour uses channels > 1 (as `COLOR_ASTRAY` does) to
stay bright away from lights. No effect adds a `PointLight2D` (the LT-8 cap of 12 tower
lights is untouched).

### 1.1 Rifleman — fast tracer

- Shape: a short bright dash, 0.35 cell long, 2 px, travelling from the tower centre to
  `to`; a muzzle dot (r = 0.12 cell) at the tower for the first 0.05 s.
- Colour: hot white-yellow `Color(2.2, 2.0, 1.2)`.
- Motion: the dash covers the whole distance in 0.08 s, then a hit spark at `to`
  (4 short rays, 0.15 cell, 0.1 s) on each hit enemy. Total 0.18 s.
- Reads as: quick, small, frequent. At x2 (one shot per 0.4 s real) the dash never
  overlaps its own previous one. Several riflemen: many thin dashes, never a solid line.

### 1.2 Harpooner — piercing harpoon

- Shape: a harpoon head (filled triangle, 0.3 cell long, 0.18 wide) pointing along the
  line, trailing a 1 px rope back to the tower.
- Colour: cold steel `Color(1.3, 1.6, 1.9)`; rope at alpha 0.6.
- Motion: the head travels tower -> line end (`to`, full range) in 0.22 s at constant
  speed; as it passes each enemy in `hits`, a cross tick (0.25 cell, 3 px) appears on that
  enemy and stays 0.3 s ("pierced"). The rope fades over the last 0.1 s. Total ~0.32 s.
- Reads as: slower, heavier, a straight line through several enemies; the cross ticks
  count how many it pierced. At x2 (0.8 s real) still no overlap.

### 1.3 Elder Sign — ward aura (no projectile)

- Shape: a ring at the aura radius (`stats().range_cells`) plus 5 short dashes on the ring
  that rotate slowly (one turn in 12 s), centred on the tower.
- Colour: pale sea-green `Color(0.9, 2.0, 1.6)`.
- Motion: idle alpha 0.25 (dashes 0.4); while at least one drawn enemy is inside the radius
  (by `_last_pos`, presentation only) the ring rises to alpha 0.6 and pulses
  (0.45-0.6 at 1.5 Hz). Two overlapping signs draw two rings; the enemy marker (§2) is not
  doubled, which matches the sim (auras do not stack).
- Reads as: a zone, never a shot. Independent of game speed (rotation uses effects time).

### 1.4 Necronomicon Reader — dark wave

- Shape, two parts:
  1. a tendril from the tower to `to`: 3 px polyline with a slow S-wave (2 bends), 0.15 s;
  2. at `to`, a blast: a near-black disc `Color(0.05, 0, 0.08, 0.55)` with a bright violet
     rim `Color(1.8, 0.6, 2.4)` 3 px, expanding from 0.2 cell to `aoe_radius` over 0.45 s
     while the fill fades to 0. Each enemy in `hits` gets a violet flash (circle outline,
     0.3 cell, 0.2 s).
- Motion: total ~0.6 s; the largest and slowest effect on the board, once per 4 s
  (2 s real at x2).
- Reads as: rare, big, round, dark with a glowing edge. The dark fill alone would vanish
  under the darkness; the rim carries it.

### 1.5 Sound (optional, out of scope for this task)

No sound in LT-25. Suggested later cues: rifle crack, harpoon thunk, low hum when an enemy
enters a ward, a reversed whoosh for the wave.

### 1.6 Load rules

- Effects keep real-time durations at x2 (readability); towers simply fire twice as often.
- Per tower at most 2 live effects of its attack kind; a third replaces the oldest. This
  bounds the effect list when many towers fire at x2. Death/dissolve/leak flashes are
  unchanged and not capped.
- Draw order (bottom to top): map, phantom, auras (§1.3), towers, enemies with markers,
  attack effects. Attacks over enemies so a pierce or blast is never hidden.

## 2. Effect markers on enemies

Each effect has its own channel on the enemy, so all of them combine on one enemy without
covering each other or the HP bar:

| Effect | Channel | Look | Condition |
|---|---|---|---|
| slow | ground, under the body | dashed sea-green ring r = 0.34 cell, 6 dashes, same colour as the Elder Sign | `e.speed_mult < 0.999` |
| damage-taken | body outline | 2 px violet outline `Color(1.6, 0.7, 2.2)` on the body circle | `e.damage_taken_mult > 1.001` |
| bleed | below the body | 2 red drops (r = 0.06 cell) dripping down 0.2 cell, loop 0.5 s | `e.status.get("bleed_ticks", 0) > 0` (field added by the task that applies bleed, §4) |
| pull | one-shot line | a 2 px steel chain (dashed) from the enemy back to the harpooner, 0.3 s | `SHOT` `data.pulled` contains the enemy id (field added later, §4) |

- Markers take the enemy's alpha: the revealed-fake 0.35 and the LT-14 flicker dip apply to
  them as to the body, so markers never make a flickering enemy steadier than its body.
- An enemy with all four: green dashed ring on the ground, violet outline, red drops below,
  chain line to the tower; HP bar above, untouched.
- The marker set is a pure function `Board.enemy_markers(e) -> PackedStringArray`
  (`"slow"`, `"vuln"`, `"bleed"`), so tests pin it without drawing.

## 3. Madness and astray variants

Facts: `madness_affected` defaults to `kind == "occult"` and config rejects it on mundane
towers, so in Madness only the Necronomicon (not Pure Rite) shoots astray; Elder Sign never
fires. `astray: true` is set the same whether the shot centred on a real enemy, a fake, or
nothing (LT-12 §1), so the variant may depend on `astray` and on `hits` being empty, never
on what was hit.

- **Astray wave with hits** (centred on some enemy, real or fake): the same wave, but the
  tendril uses the LT-14 astray waver (5 px amplitude, 3 half-waves) and the rim colour is
  `COLOR_ASTRAY` (bright magenta-white) instead of violet. Reads as "the rite went wrong",
  without telling which kind of enemy it struck.
- **Astray wave, empty** (`hits: []`): the wavering tendril to the `astray_end` spot (as
  today) and a small fizzle ring there, max radius 0.5 cell (not `aoe_radius`: a full-size
  blast next to enemies would look like it should have hit them), 0.3 s.
- **Generic fallback** for any other tower with `astray: true` (none today): the current
  LT-14 bolt, unchanged.
- **Mundane miss** (`miss: true`, Fraying/Madness; not an astray shot): rifle dash ends
  0.4 cell to the side of the aim point and runs 0.5 cell past it, no spark; harpoon flies
  its line, no cross ticks, the head drops (alpha to 0) at the end. See Q4.

## 4. Edit map

All production changes are in `scenes/board.gd` (304 lines today). No sim change is
needed for rifleman, harpooner, Elder Sign, Necronomicon, slow or damage-taken.

| File | Lines | Change |
|---|---|---|
| `scenes/board.gd` | 11-35 (consts) | per-kind colours/durations (`TRACER_*`, `HARPOON_*`, `WARD_*`, `WAVE_*`, `MARK_*`), `MAX_FX_PER_TOWER := 2` |
| `scenes/board.gd` | 80-106 `on_event` | SHOT: `shot_kind(t)` dispatch; effect dict gains `tower` (id), `hits` (ids), `radius` (wave), `miss`, `astray`, `pulled`; per-tower cap; astray-empty branch keeps `astray_end` and adds `radius = 0.5` for a wave tower |
| `scenes/board.gd` | new `shot_kind(t: SimTower) -> String` | `"harpoon"` / `"wave"` / `"tracer"` from `t.stats().effects`; `"aura"` for support levels |
| `scenes/board.gd` | new `enemy_markers(e: SimEnemy) -> PackedStringArray` | §2 conditions |
| `scenes/board.gd` | 189-203 `_draw` | call `_draw_auras(s)` before the tower loop |
| `scenes/board.gd` | 238-243 `_draw_tower` | border/letter in the attack colour |
| `scenes/board.gd` | 246-271 `_draw_enemies` | `_draw_markers(px, e, color.a)` after the body, before the HP bar |
| `scenes/board.gd` | 274-288 `_draw_effects` | kinds `tracer`, `harpoon`, `wave`, `pull`; remove `shot` |
| `scenes/board.gd` | 291-304 `_draw_astray` | factor the waver polyline into `_waver_points(a, b, seed)` for reuse by the astray wave |
| `scenes/board.gd` | new `_draw_tracer`, `_draw_harpoon`, `_draw_wave`, `_draw_auras`, `_draw_markers` | §1-§3 |
| `tests/` | new `tests/tower_attack_visuals_test.gd` | §5 |

Read only: `sim/core/simulation.gd` `_fire_towers` (510-569, SHOT fields) and
`_apply_auras` (469-497); `sim/core/sim_enemy.gd` 23-36 (modifiers, `status`);
`sim/core/sim_tower.gd` `stats()`; `scenes/game.gd` `advance` (106-118: events, then
`tick_effects(delta)` with real delta); `scenes/lighting.gd` `_sync_tower_lights` (73-88,
no change); `tests/sanity_feedback_test.gd` 109-122 (pattern: synthetic `SimEvent` into
`board.on_event`).

### Sim field additions (for the task that applies bleed/pull; not in LT-25 unless Q1 = C)

- **Bleed:** `SimEnemy.status["bleed_ticks"]: int` (ticks left) and `["bleed_dps"]`; ticked
  in slot 2, damage through `apply_damage(..., "bleed")`. State, not an event. Render-safe:
  set on every enemy the harpoon hits, fakes included.
- **Pull:** `SHOT` gains `"pulled": Array[int]` (ids moved back by `pull_cells`), present
  only when the level has `pull_cells`. Render-safe for the same reason (applies to every
  hit enemy). `prev_distance` should be set to the pulled distance so interpolation does
  not slide the enemy backwards through a tick.

Overlap with parallel tasks: LT-24 touches `ui/` and `sim/` (`upgrade_tower`,
`TOWER_UPGRADED`), not `board.gd` draw code; stats-based dispatch follows upgrades with no
extra wiring. LT-26 (beam) touches `scenes/lighting.gd`. LT-28 polishes UI only. Expected
conflicts: none beyond `board.gd` constants if LT-24 adds a selection highlight there.

## 5. Behaviours the tests slice must pin

Synthetic `SimEvent`s into `game.board.on_event`, as in `sanity_feedback_test.gd`:

1. Rifleman SHOT with hits -> last effect kind `"tracer"`.
2. Harpooner SHOT -> `"harpoon"`, its `to` is the event's `to`, `hits` copied.
3. Necronomicon SHOT with hits -> `"wave"`, `radius == stats().effects.aoe_radius`.
4. `shot_kind` of an Elder Sign tower is `"aura"`; a SHOT is never needed for it.
5. `enemy_markers`: `speed_mult 0.7` -> `["slow"]`; `damage_taken_mult 1.25` -> `["vuln"]`;
   both -> both; neither -> empty; `status.bleed_ticks 3` -> contains `"bleed"`.
6. SHOT with `pulled: [id]` -> a `"pull"` effect from that enemy to the tower.
7. Necronomicon SHOT `astray: true` with hits -> `"wave"` with `astray` true; with
   `hits: []` -> `"astray"` with `radius <= 0.5`.
8. Fake parity: the same SHOT data aimed at a fake and at a real enemy yields the same kind
   and fields (`render_isolation_test.gd` must still pass unchanged).
9. Rifleman miss (`miss: true`, `hits: []`) -> `"tracer"` with `miss` true and end point
   not equal to `to` (only if Q4 = A).
10. Cap: 10 SHOTs from one tower without `tick_effects` -> at most 2 effects of that tower.

Candidate controls (revert code, test must fail): (a) dispatch always returns `"tracer"`
-> 2, 3 fail; (b) wave radius fixed at 1.0 -> 3 fails; (c) slow condition removed from
`enemy_markers` -> 5 fails; (d) `pulled` ignored -> 6 fails; (e) astray flag dropped from
the wave effect -> 7 fails; (f) per-tower cap removed -> 10 fails. Six controls, one test
binary (`tests/tower_attack_visuals_test.gd`), one build.

## 6. Screenshot plan for verify

Run the game windowed (not headless: draws need a renderer) from a debug build, capture
`get_viewport().get_texture().get_image().save_png()` into the scratchpad, one per shot:

1. Lucid, x1: one of each tower on the first map firing at wave 2 (all four looks at once).
2. Same scene at x2 with ~8 towers firing: still four readable kinds, no solid lines.
3. An enemy inside an Elder Sign: aura bright, slow ring + violet outline on the enemy.
4. `-- --sanity=0` (Madness): Necronomicon astray waves, magenta rim, one empty fizzle.
5. `-- --sanity=30` (Fraying): rifle and harpoon misses visible (if Q4 = A).
6. Bleed/pull: a test-only scene with a synthetic enemy (`status.bleed_ticks`) and a
   synthetic SHOT with `pulled`, since the sim does not produce them yet (if Q1 = A).

Owner acceptance: play one run and confirm each tower's attack and effect is
distinguishable at a glance.

## Open questions

**Q1. Bleed and pull markers while the sim does not apply bleed or pull.**
*Today:* the Barbed (bleed) and Chain harpoon (pull) branches exist in `towers.json`, but
the sim ignores `bleed_dps`/`pull_cells`; LT-24 makes those branches reachable but still
does not apply them. So in play no enemy can ever bleed or be pulled.
*Change:* the task asks for bleed and pull markers.
*Example:* a player upgrades a harpooner to Barbed after LT-24; the tooltip says "Bleed 6/s
for 3 s" but nothing happens and nothing shows.
- **A (recommended):** LT-25 draws both markers from the fields in §4
  (`status.bleed_ticks`, `SHOT.pulled`) and tests them with synthetic data; the task that
  applies bleed/pull only has to fill those fields. Cheap (~30 lines). Risk: the sim author
  may want a different field shape, and the markers cannot be seen in play until then.
- **B:** leave bleed/pull out of LT-25; the task that applies them adds the markers. Clean,
  no unused code. Risk: acceptance of LT-25 is narrower than written.
- **C:** apply bleed and pull in the sim inside LT-25. Visible in play now. Risk: gameplay
  change in a visual task, rebalancing (LT-23) and bot numbers shift, larger scope.

**Q2. When the Elder Sign aura is shown.**
*Today:* nothing; the range ring appears only while the tower is selected.
*Change:* the sign needs a visible "attack".
*Example:* three signs on the path bend: three faint rings all the time, one of them bright
when a cultist walks through it.
- **A (recommended):** always faint (alpha 0.25), bright and pulsing while an enemy is
  inside. The zone reads before anything enters it. Risk: several signs add ring clutter.
- **B:** only while an enemy is inside. Least clutter. Risk: the player cannot see where
  the ward covers until it is already in use.
- **C:** only when selected (as today), plus the enemy markers. Minimal. Risk: the playtest
  complaint stays for the sign.

**Q3. One marker or two for slow and damage-taken.**
*Today:* both come only from the Elder Sign and always appear together.
*Change:* §2 gives them separate markers (green ground ring, violet outline).
*Example:* an enemy in a ward shows both; the same enemy outside shows neither.
- **A (recommended):** two markers. Ready for Corrupted Seal / LT-23 or later slows that
  apply only one of them. Risk: today they are redundant, slightly busier.
- **B:** one combined "warded" marker. Simpler look now. Risk: needs splitting when the two
  effects diverge.

**Q4. Should a mundane miss look different from a hit.**
*Today:* at Fraying and Madness 15 % of rifle and harpoon shots miss (LT-12 §4), but they
draw exactly like hits; the player only sees enemies not dying.
*Change:* §3 draws a miss as a deflected tracer / a harpoon with no impact ticks.
*Example:* at Fraying a rifleman fires 10 times; about 1-2 dashes visibly fly past the
cultist with no spark.
- **A (recommended):** show misses. Makes the Fraying penalty readable, which is the point
  of the mechanic. Risk: makes low sanity feel more punishing.
- **B:** keep misses identical to hits. Unease without explanation. Risk: players read it as
  a bug or as "damage feels random".
