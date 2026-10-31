# LT-30 — Lighthouse beam in the sim: design addendum (S1)

Status: draft for owner review · 2026-11-01 · branch `feat/LT-30-lighthouse-beam`

LT-30 implements `docs/design/LT-26-lighthouse-beam.md` (§7). LT-26 was written before
LT-23, LT-24, LT-27 and LT-33/34/36 landed; this addendum records what changed since
(§0), adds the active night ability the owner asked for (§1), re-maps LT-26 D3 onto the
sanity reserve (§2), gives the edit map for S2/S4/S5/S7 (§3) and the owner questions (§4).
LT-26 stays the spec for everything this note does not override.

## 0. What LT-26 says that the code has since changed

| LT-26 says | Today (code / later decision) | LT-30 does |
|---|---|---|
| Lighthouse upgrade paid in **Relics**, allowed **during a wave** (§1.2) | LT-27 D7: lighthouse levels cost **money** (internal `gold`, `_add_gold`), **by day only** (`_day_only()`, `simulation.gd:823`) | `can_upgrade_lighthouse()` checks `_day_only()`; cost through `_add_gold(-cost, "lighthouse", 0)` |
| "Adds a target kind *lighthouse* to LT-24's upgrade command" (§1.2) | `upgrade_tower(tower_id: int, branch: String)` (`simulation.gd:300`) is tower-only; every command is logged and replayed through `REPLAY_ARGS` / `replay_command` (LT-34/36, `simulation.gd:470-506`) | A separate command `upgrade_lighthouse()` on the same pattern (`can_*` + command + log entry + `REPLAY_ARGS["upgrade_lighthouse"] = []`). A magic tower id would break `NO_SUCH_TOWER` and `tower_by_id` callers; the pattern, not the method, is "LT-24's command" |
| Occult drain × `drain_mult` while lit; `occult.drain_mult` key (§1.3, §1.4, D3) | LT-23 removed `sanity_per_second`; sanity is a **reserve** that lowers the cap; Q7 "Ничем, только −30% силы": `drain_mult` obsolete | Not added (§2) |
| Madness enemy buff "still open there" (stats, max HP problem, §4) | Settled (LT-23 §3, Q8/S13): per-tick `speed_mult × 1.7`, `damage_taken_mult × 0.37`, fakes alike; hook `_madness_buff_blocked(e)` already exists (`simulation.gd:986`, returns false) | The hook returns `e.lit` (only when `beam.enemy.cancel_madness_buff`); no max-HP issue |
| Non-goal: the beam does not slow enemies (§0) | Owner (LT-27 D5): night needs agency, "active lighthouse ability" | The flare (§1) slows lit enemies **only while the player fires it**; the passive beam still never slows |
| Render turns `atan2(sim dir)`, interpolated (§1.1) | LT-33 boundary rule: animation driven by `tick + alpha`, no own timer; `tests/sim_boundary_test.gd` bans presentation writes to `state`/`config` and calls to `sim._*` | Same as LT-26, plus a public query for directions (§3.2) |
| Day/night not mentioned | LT-27: night = WAVE; by day the lamp is dark (render only, `lighting.gd:105`) | Beam rotates and lights **only at night** (§3.1, decision B1) |
| Mundane miss from `sanity.json` `miss_chance` 0.15 | Unchanged (fraying, madness) | As LT-26 |
| `Vector2` is 32-bit, keep two floats (§1.1) | Unchanged; `Vector2` is in the guard's `ENGINE_ALLOWLIST` but still 32-bit | Base direction as two `float` fields |

## 1. Active night ability

### Today

At night the player can only buy sanity back (`buy_sanity`), pause and change speed
(LT-27 §3). LT-31 (target priority) adds one per-tower setting. The beam turns on its own.

### Options

**A. Flare ("Сигнальная вспышка"), paid with relics (recommended).** A night-only command
`fire_flare()`. For `flare.seconds` (3 s) every beam **stops turning** and **widens**
(`half_width_ratio × flare.width_mult`, 2.0 → cone ~52° instead of ~27°); every enemy lit
during the flare moves at `× flare.enemy_speed_mult` (0.5) on each lit tick. All other
beam effects use the same widened, frozen cones (mundane buff, occult debuff, madness
cancel). Cost: `flare.cost_relics` (3) relics from the stash, cheapest kind first (config
order breaks ties); cooldown `flare.cooldown_seconds` (20 s) from the activation.
- Skill: the player times the flare for when a beam lies across the path; more beams
  (L2/L3) make the flare worth more, so it also sells the upgrade.
- Relics are the one resource that sits idle at night (sold only by day); spending them
  is "tomorrow's money for tonight". The first night has an empty stash until tokens land.
- Numbers: enemies walk ~1 cell/s; at distance 8 the frozen cone is ~8 cells wide, so an
  enemy inside for the whole flare loses ~1.5 cells; 3 relics ≈ $15 in bones (a Rifleman
  is $50); a 60 s night fits ~3 flares. All tunable in S7.

**B. Blinding pulse, paid with sanity.** `pulse()`: every live enemy within `reach_cells`
of the lighthouse (all around, not only in cones) stops for 1.5 s. Cost 10 sanity from the
current pool; refused in MADNESS (the latch would make it free) and when sanity < cost;
cooldown 30 s.
- Strong and easy to read, but ignores the beam (no reason to upgrade), re-introduces a
  per-use sanity price that the owner removed in LT-23 ("только фиксированная сумма"), and
  pushes the player toward Fraying (misses) exactly when things go wrong.

**C. Overcharge, paid with money.** `overcharge()`: for 8 s the lighthouse runs at the next
level's beam count (L3 → 8 beams, 61 % coverage). $40, cooldown 30 s. Money at night has
one precedent (the buyout).
- Cheapest to build (no new effect, only `beam_count`), works as "try before you buy", but
  feels indirect: no visible push-back on the enemies, and spends the day's currency.

### Recommendation: A, paid with relics

New command result values (appended after `BAD_ARGS`, values never shift):
`NOT_NIGHT` (flare by day: phase BUILD or DONE; phase NONE allowed so unit tests without a
WaveDirector work, mirroring `_day_only`), `ON_COOLDOWN`. Not enough relics reuses
`NO_RELICS`. Order in `can_fire_flare()`: `OUTCOME_REACHED`, `NO_FLARE` (block absent →
disabled; also appended), `NOT_NIGHT`, `ON_COOLDOWN`, `NO_RELICS`.

State: `state.flare_ticks_left`, `state.flare_cooldown_ticks` (both count down in slot 2;
the cooldown also by day). Events: `FLARE_FIRED {ticks, cooldown}` (id 0), then one
`RELICS_CHANGED {reason: "flare"}` per kind paid (existing `_add_relics`). Log entry
`[tick, "fire_flare"]`. Fakes are slowed exactly like real enemies (LT-12 §1).

Config (`economy.json` `lighthouse.flare`, optional):

```jsonc
"flare": {
  "cost_relics": 3,          // int >= 1, cheapest kinds first
  "cooldown_seconds": 20,    // > seconds
  "seconds": 3,              // > 0
  "width_mult": 2.0,         // >= 1, multiplies half_width_ratio during the flare
  "hold_beams": true,        // beams stop turning during the flare
  "enemy_speed_mult": 0.5    // (0, 1], lit enemies during the flare
}
```

## 2. Re-map of "lit occult: −30 % power and half passive drain"

**What "passive drain" is now:** nothing. LT-23 removed `sanity_per_second`; an occult tower
costs sanity only as a **reserve** that lowers the cap at build/upgrade/sell (commands
between ticks, no per-tick work). The only per-tick sanity loss left is horror drain from
real enemies near towers (`_horror_drain`, `simulation.gd:785`), not from occult towers.

| Option | What the beam does to sanity | Consequence |
|---|---|---|
| **R1. Nothing; −30 % power only (recommended, already decided: LT-23 Q7 "Ничем, только −30% силы")** | none | The beam is a pure trade: mundane buff vs occult debuff. No `drain_mult` key |
| R2. Lit occult towers release half their reserve while lit | cap rises by `r/2` while lit, falls back after | Cap flickers every second; regen fills the raised cap and is clamped away again (hidden sanity loss); breaks LT-23's "cap moves only in commands" |
| R3. Lit enemies drain half horror | `_horror_drain` × 0.5 for lit enemies | Moves the occult trade onto enemies; overlaps D4 (madness cancel); a new rule nobody asked for |

LT-30 implements R1: `beam.occult` has only `power_mult` (Necronomicon damage × 0.7 before
the madness ×2; Elder Sign slow × 0.7, damage-taken bonus `1 + (m − 1) × 0.7`). No owner
question: Q7 is recorded verbatim.

## 3. Edit map

Line numbers are the worktree's at `10eea26`. Found with `grep -n "^func "` outlines and
`grep -rn -i "beam\|lighthouse"` over `scenes ui tools tests docs/GDD.md` (GDScript is not
indexed by g-mesh). Callers relied on: `upgrade_tower` ← `game.gd:154`,
`tower_panel.gd:173` (via `game.upgrade`), `bot_runs.gd:252,264`, `replay_command`;
`_madness_buff_blocked` ← `_apply_madness_buff` only; `REPLAY_ARGS` ← `replay_command`,
`tests/sim_boundary_api_test.gd:433` (`BAD_ENTRIES` must cover every key);
`lighting.beam` ← `tests/lighting_test.gd:73-94`.

### 3.1 S2 — sim code (beam state, upgrade, modifiers, flare)

Read for context: LT-26 §1.1 (lit test, rotation), `simulation.gd` `step` (80-115),
`_apply_auras` (935-968), `_apply_madness_buff` (971-983), `_fire_towers` (1001-1062),
`can_upgrade`/`upgrade_tower` (273-320, the pattern), `can_sell_relics`/`sell_relics`
(539-578, relic spending), `_add_relics` (917-933), `_day_only` (823-828).

| File | Change |
|---|---|
| `sim/defs/economy_config.gd` (6-7 `FIELDS`, 19, 65-68) | `lighthouse` keys `["hp", "beam", "flare"]`; new inner classes `BeamConfig` (pattern, turn_t, reach_cells, half_width_ratio, sweep_edges, levels[{beams, upgrade_cost}], mundane{fire_interval_mult, ignore_miss}, occult{power_mult}, enemy{cancel_madness_buff}) and `FlareConfig` (§1). Validation per LT-26 §1.3 minus `drain_mult`; `beams` in {1,2,4,8}, non-decreasing; `upgrade_cost` > 0 from L2; `beam` required, `flare` optional |
| `data/economy.json` | `lighthouse.beam` per LT-26 §1.3 without `occult.drain_mult`; costs 120 / 250 **in money**; `lighthouse.flare` per §1 |
| `sim/core/sim_state.gd` (after 40) | `lighthouse_level := 0`, `beam_dx/beam_dy` (start `-1, 0`), `prev_beam_dx/prev_beam_dy` (render interpolation, like `prev_distance`), `beam_sign := 1.0` (sweep direction), `flare_ticks_left`, `flare_cooldown_ticks` |
| `sim/core/sim_tower.gd` (after 22) | `var lit := false` (persistent; `TOWER_LIT` on flip) |
| `sim/core/sim_enemy.gd` (23-37) | `var lit := false`, reset in `reset_modifiers()` |
| `sim/core/sim_event.gd` (6-14) | append `LIGHTHOUSE_UPGRADED {level, beams, cost}`, `TOWER_LIT {lit}`, `FLARE_FIRED {ticks, cooldown}` |
| `sim/core/simulation.gd` `CommandResult` (9-32) | append `NOT_NIGHT`, `ON_COOLDOWN`, `NO_FLARE` after `BAD_ARGS` |
| `simulation.gd` `step` (80-115) | slot 2 first: `_update_beam()` (rotate unless held, compute `lit` for towers and live enemies, count down flare timers), then `_apply_auras`, `_apply_madness_buff`, `_apply_flare_slow()` |
| new `_update_beam`, `_beam_dirs() -> Array` (pairs), `_is_lit(px, py) -> bool`, `_beam_on() -> bool` | LT-26 §1.1, trig-free; `_beam_on` = phase not BUILD/DONE (B1); off → every `lit` false, direction held |
| new public `beam_count()`, `beam_directions(alpha) -> Array[Vector2]` (render only, interpolated prev→current), `lighthouse_upgrade_cost() -> int` (0 at max), `can_upgrade_lighthouse()`, `upgrade_lighthouse()`, `can_fire_flare()`, `fire_flare()` | commands log `[tick, "upgrade_lighthouse"]` / `[tick, "fire_flare"]` |
| `REPLAY_ARGS` + `replay_command` (470-506) | `"upgrade_lighthouse": []`, `"fire_flare": []` + match arms |
| `_apply_auras` (935-968) | per aura tower, if `t.lit`: slow × `power_mult`, mult `1 + (m−1) × power_mult`, before the `maxf` |
| `_madness_buff_blocked` (986-988) | `return config.economy.beam.cancel_madness_buff and e.lit` |
| `_fire_towers` (1001-1062) | occult & `t.lit`: `damage *= power_mult` (before the madness ×2); mundane & `t.lit` & `ignore_miss`: skip `_roll_miss()` (no COMBAT draw); cooldown `ticks(fire_interval × fire_interval_mult)` when lit at the shot |
| new `_pay_relics(n)` near `_add_relics` | cheapest price first, ties config order; `RELICS_CHANGED "flare"` |

Must confirm in S2: `t.lit` is computed with the tower centre and the enemy position at
the start of the tick (as auras); lit test uses `half_width_ratio × width_mult` during a
flare; a held beam still writes `prev_beam_* = beam_*` so the render does not jump.

### 3.2 S4 — render, UI, bots

Read for context: LT-33 "Boundary rule"; `scenes/lighting.gd` (`_ready` 67-87,
`_process` 89-92, `_apply_night` 105-115, `_beam_texture` 167-184); `scenes/game.gd`
(`advance` 119-136, commands 140-183, `_on_cell_clicked` 230-238); `ui/side_panel.gd`
`_ready` (55-90); `ui/tower_panel.gd` (pattern, 67-180); `ui/hud.gd` `_ready`/`refresh`
(35-210, buyout button as the pattern for a night-only button).

| File | Change |
|---|---|
| `scenes/lighting.gd` | drop `BEAM_SPEED`, `BEAM_REACH_CELLS`, `BEAM_HALF_ANGLE` constants and the `_process` rotation; `beams: Array[PointLight2D]` sized by `sim.beam_count()`; each `rotation = beam_directions(game.clock.alpha())[i].angle()`; reach and half angle from `config.economy.beam` (`atan(half_width_ratio)`, trig fine in render); texture rebuilt per width (flare widens) or scaled |
| `scenes/game.gd` | `upgrade_lighthouse()`, `fire_flare()` forwarders; `_on_cell_clicked`: `cell == sim.state.map.lighthouse` → lighthouse panel |
| new `ui/lighthouse_panel.gd` (in `side_panel.gd`) | level, beams, coverage %, upgrade button (`can_upgrade_lighthouse`, `lighthouse_upgrade_cost`) |
| `ui/hud.gd` | "Flare (3 relics)" button, enabled by `can_fire_flare()`, cooldown seconds left |
| `scenes/board.gd` `_draw_tower` (408-426) | lit marker from `t.lit`; enemies need none (the cone shows it) |
| `tools/bot_runs.gd` (header 1-41, `_play` 98-212, `_act` 242-279, `_next_upgrade` 281-305) | flags `--lighthouse=0` (never upgrade the lighthouse) and `--flare=0`; day policy: lighthouse level next when its cost ≤ the cheapest tower upgrade (tunable); night policy: `fire_flare()` when ≥ 3 live enemies are lit; RUN keys `lighthouse_level`, `flares`, `lit_shots` |
| `docs/GDD.md` §5.2 (89-91), 335-340 | beam rules, flare, "drain half" removed |

Boundary: all reads go through `state.*`, `tower.lit`, public queries; no `sim._*`, no
writes to `state`/`config` (the guard scans `tools/` too, so the beam-off arm is a
`--data=<dir>` variant, not an in-memory config edit).

### 3.3 S5 — tests

Read: `tests/sim_test_base.gd` (edit helpers), `tests/wave_test_base.gd`,
`tests/sim_boundary_api_test.gd` (`BAD_ENTRIES` 405-421, `_ready_sim` 423-432),
`tests/lighting_test.gd` (73-94), `tests/config_reject_test.gd` (69, 152, 223).

- New `tests/beam_test.gd`: lit inside/outside on both sides of a cone edge for 1/2/4 beams
  (points built from the config ratio ± ε, no trig); rotation determinism (same seed → same
  `beam_dx/dy` and events); dark by day; upgrade cost paid, `NOT_BUILD_PHASE` at night,
  `NOT_ENOUGH_GOLD`, `MAX_LEVEL`, beams follow level; each modifier; madness cancel for real
  and fake; flare: cost, cheapest first, cooldown, `NOT_NIGHT`, hold, width, slow.
- Update: `BAD_ENTRIES` (+2 keys), `_ready_sim` (night + relics), replay test with both new
  commands; `lighting_test.test_beam_rotates_over_time` drives sim ticks instead of frames;
  config reject rows for every new key.
- Controls (8; the two occult sites are separate code sites, so separate controls):
  lit always false; `fire_interval_mult` dropped; `ignore_miss` dropped; Necronomicon
  `power_mult` dropped; Elder Sign `power_mult` dropped; `_madness_buff_blocked` back to
  false; beam count ignores level; flare slow dropped.

### 3.4 S7 — bot measure

10 seeds per strategy, three arms: **on** (beam + lighthouse policy + flare), **beam-off**
(`--data=` variant with all beam multipliers 1.0, `ignore_miss` false, cancel off, flare
block removed; same purchases) → the beam's effect; **no-upgrade** (`--lighthouse=0`) → is
the upgrade worth its cost. Cheap observation telling arms apart: `lit_shots` > 0 and
`missed` differs between on and beam-off. Tune costs, multipliers, flare numbers.

## 4. Owner questions

### Q1. Which active night ability?

**Today:** at night the player can only buy sanity back, pause and change speed; the beam
turns by itself. **Change:** one new night command on a cooldown. **Example:** a pack of
Deep Ones walks the path; the beam is about to cross it.
- **A. Flare (recommended):** the player fires as the beam crosses the path: the beam stops
  for 3 s, doubles in width, enemies in it walk at half speed, riflemen in it fire 25 %
  faster. Benefit: skill (timing), uses the beam and makes upgrades worth more. Risk: at L1
  (one beam) a badly timed flare lights empty land.
- **B. Blinding pulse:** every enemy within 16 cells stops 1.5 s. Benefit: simple, always
  useful. Risk: ignores the beam and its upgrades; strongest option, harder to balance.
- **C. Overcharge:** for 8 s the lighthouse runs the next level's beams (L3 → 8). Benefit:
  cheapest to build, previews the upgrade. Risk: indirect, little feeling of control.

### Q2. What does the ability cost?

**Today:** relics pile up at night and become money at dawn; money buys everything by day
(buyout also at night); sanity is lost only to the reserve and horror. **Change:** one of
them pays for the ability. **Example:** night 3, stash 6 bones + 1 amber, $40 left, sanity
62 of cap 80.
- **Relics, 3 cheapest (recommended):** pays 3 bones (≈ $15 less at dawn). Benefit: uses the
  one resource idle at night; a clear "tonight vs tomorrow" trade. Risk: unavailable early
  in night 1 (empty stash).
- **Sanity, 10 from the current pool:** 62 → 52. Benefit: always available, thematic. Risk:
  the owner removed per-use sanity costs in LT-23; pushes toward Fraying (misses) when the
  player is already losing; must be refused in Madness.
- **Money, $40:** Benefit: one currency. Risk: competes with the day's builds; money then
  matters at night beyond the buyout.

### Q3. Is the beam dark by day? (decision B1)

**Today:** the render dims the beam by day (LT-27 §4); the sim has no beam. **Change:** the
sim beam either turns and lights only at night, or always. **Example:** a 40 s day; no
enemies walk, so towers do not fire either way.
- **Night only (recommended):** direction holds at dawn, `lit` clears; matches the picture;
  no tower shows a lit marker by day. Risk: none for gameplay (no enemies by day).
- **Always:** simpler rule (one less check). Risk: lit markers flash by day while the drawn
  beam is dark, so the picture and the rule disagree.
