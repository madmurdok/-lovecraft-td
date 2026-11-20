# LT-105: tower modifier channel (LT-96 S9, owner decision D6)

Spec: `LT-96-extensibility-synthesis.md` §4 S9, §6 D6 "Башня с модификатором, канал S9
(Recommended)". Acceptance: golden byte-identical; light goes through the channel; UI numbers
come from the same channel. Line numbers below are from `ec70038` (before LT-103); the code slice
rebases on LT-103 first and finds each site by the function names given.

## 1. Today

- The light effect is recomputed at every read from `t.lit` / `t.shadowed` (set in slot 2 by
  `LightSystem.update_beam`): `LightSystem.power_mult(t)` / `interval_mult(t)` wrap
  `TowerRules.power_mult` / `interval_mult`; `CombatSystem.fire_towers` calls
  `TowerRules.miss_add` / `ignore_miss` directly. Reads: `apply_auras` (:169),
  `fire_towers` damage (:246), miss (:283-285), interval (:322), `_cast_banish` (:343),
  `_summon` (:388).
- `SimTower.status` (:40-41) is dead: never written; only `tests/golden_runs.gd:280` reads it
  (dumps `canon(t.status)` = `{}` into every `final_sha`).
- UI: the placed-tower panel reads `Simulation.tower_mults(id)` only for the kind line
  (`ignore_miss`, `miss_add`); its numbers (`TowerText.lit_values`, `lit_line`,
  `TowerStatsModel.lit_effects`) recompute `TowerRules.light_effect` from `t.shadowed`.
- Precedent: `SimEnemy.reset_modifiers()` (speed_mult, damage_taken_mult, ...) runs in slot 1 of
  `Simulation.step`, and slot-2 systems compose into it.

## 2. Decisions

**D1. Where.** Plain fields on `SimTower` (as on `SimEnemy`), replacing `status`:
`power_mult := 1.0`, `interval_mult := 1.0`, `miss_add := 0.0`, `ignore_miss := false`,
`disabled := false`. Methods: `reset_modifiers()`, `add_modifiers(power, interval, miss,
no_miss := false, off := false)` (the only write path), `modifiers() -> Dictionary` (the five
keys). No timers in the channel: a timed effect (harass for 3 s) keeps its timer with its owner
and rewrites the channel every tick while active. That is why `status` goes away.

**D2. When.** `Simulation.step` slot 1 resets every tower next to `e.reset_modifiers()`. Writers
run in slot 2 in a fixed order, all before the first reader (`apply_auras`):
reset (slot 1) -> light (`update_beam`) -> [LT-106 traits] -> [LT-32 crew] -> `apply_auras`
reads -> slot 5 `fire_towers` / `_cast_banish` / `_summon` read. Between ticks the channel holds
the last tick's values, exactly as `lit` / `shadowed` do now (the UI reads it there). A tower
built between ticks starts neutral, as it starts unlit today. No new SimEvent (events_sha
unchanged); `TOWER_LIT` stays the visual signal.

**D3. Light is the first writer.** In `update_beam`'s tower loop, after `lit` / `shadowed` are
set (every tick, not only on a flip), `_write_light_mods(t, lit, shadowed)` calls
`t.add_modifiers(TowerRules.power_mult(..), interval_mult(..), miss_add(..), ignore_miss(..))`,
only when `lit or shadowed` (a neutral write is a no-op, so skipping it is exact and cheaper).
The kind gates stay inside those `TowerRules` functions. `LightSystem.power_mult(t)` and
`interval_mult(t)` are deleted (combat is their only caller).

**D4. Composition of several writers.**

| field | compose | why |
|---|---|---|
| `power_mult` | multiply (`*=`) | a crew x1.2 and a lit x0.7 must both act; max would hide a debuff |
| `interval_mult` | multiply | same |
| `miss_add` | sum | additive chance, as `shadow.mundane_miss_chance_add` already is; the existing `minf(1.0, ..)` in `_roll_miss` clamps |
| `ignore_miss` | OR | wins over any `miss_add`: no COMBAT draw (today's rule; lit and shadowed never coexist) |
| `disabled` | OR | any writer can switch a tower off |

Writer order is part of determinism once two non-neutral multipliers meet (float `*` is not
associative): light, then traits in enemy-id order, then crew posts in tower-id order.

**D5. Float exactness (golden).** Every reader keeps its expression and operand order and only
swaps the source: `TowerRules.shot_damage(s, factor, t.power_mult)` (= `s.damage * factor *
power`), `fire_interval(s, t.interval_mult)`, `pm != 1.0` in `apply_auras`, `shot_damage(s, 1.0,
t.power_mult)` in `_cast_banish`, `unit_dps(s, t.power_mult)`, `_roll_miss(t.miss_add)`. The
channel value equals the old function value bit for bit: reset literals are `1.0` / `0.0`, and
with one writer `1.0 * x == x`, `0.0 + x == x` exactly in IEEE double. Banish / summon cooldowns
(`:375`, `:393`) keep `s.fire_interval` unscaled (Q4). The mundane-only miss gate
(`t.def.kind == "mundane"`) stays in `fire_towers`. `tests/golden_runs.gd` `state_text` keeps
its tower column, printing `canon({})` literally (Q5): the channel is derived from `lit` /
`shadowed`, which are already dumped.

**D6. `disabled` (no writer yet, so golden-safe).** In `fire_towers`, after the cooldown
decrement and before `s.acts()`: `if t.disabled: continue`. The cooldown keeps counting; no
target, no RNG draw, no `burst_index` / `locked_id` change. `apply_auras` skips a disabled aura.
Its `casts_light` / `casts_shadow` keep working (they are computed in `update_beam` before any
later writer; making them depend on `disabled` would need a second light pass). Live summoned
allies stay. See Q2.

**D7. UI read path.** `Simulation.tower_mults(id)` returns `t.modifiers()` (five keys).
`TowerRules.effective_with(s, cfg, fx: Dictionary, sanity := -1.0)` holds today's body of
`effective` (reads `fx["power_mult"]`, `fx["interval_mult"]`); `effective(def, s, cfg, lit,
shadowed, sanity)` becomes `effective_with(s, cfg, light_effect(def, cfg, lit, shadowed),
sanity)`, so the picker / stats table (towers not built, hypothetical lit) keep their numbers
and tests. `TowerStatsModel.lit_numbers`, `lit_effects`, `beam_percent` and `TowerText.lit_values`,
`lit_line` gain `fx := {}` (empty: `state_effect(def, cfg, shadow)` as now). `TowerPanel.
_refresh_table` fetches `game.sim.tower_mults(t.id)` once and passes it to all of them and to
`kind_lines`. So the panel shows the numbers the sim fires with. Which lines get the lit mark and
the "lit / shadowed" wording stays keyed on `t.lit` / `t.shadowed` (Q3). `effective` ignores
`disabled`; showing it is the future writer's task.

**D8. Guard.** A G4b-style check in `architecture_guard_test.gd`: the five channel fields are
assigned only in `sim/core/sim_tower.gd`, nowhere else in `res://sim`, `res://ui`,
`res://scenes` (tests excluded), with a planted-write probe.

## 3. Future writers (not designed here)

- **LT-106 (S10) enemy traits:** a `near_tower` hook pass in slot 2 between `update_beam` and
  `apply_auras`, enemies in id order; harass = `add_modifiers(1.0, 1.0, +x)`, lift =
  `add_modifiers(1.0, 1.0, 0.0, false, true)`; the timer lives in the enemy's trait state.
- **LT-32 crew:** a post is a tower whose level effect is a buff; a pass after traits, posts in
  tower-id order, calls `add_modifiers` on the towers in its radius. The panel then needs
  generic wording for a non-light modifier (Q3).

## 4. Edit map (code slice)

Read for context first: `SimEnemy.reset_modifiers` (`sim/core/sim_enemy.gd:41-45`),
`TowerRules.power_mult` .. `light_effect` (`sim/rules/tower_rules.gd:15-65`).

| file | function (lines at ec70038) | change |
|---|---|---|
| `sim/core/sim_tower.gd` | `var status` (:40-41) | replace by the five fields, `reset_modifiers`, `add_modifiers`, `modifiers` (D1, D4) |
| `sim/core/simulation.gd` | `step` (:66-79) | slot 1: `for t in state.towers: t.reset_modifiers()`; slot-2 comment names the writer order |
| `sim/core/simulation.gd` | `tower_mults` (:588-594) | `return t.modifiers()` |
| `sim/core/systems/light_system.gd` | `update_beam` (:242-268) | call new `_write_light_mods(t, lit, shadowed)` per tower each tick (D3) |
| `sim/core/systems/light_system.gd` | `power_mult`, `interval_mult` (:345-357) | delete |
| `sim/core/systems/combat_system.gd` | `apply_auras` (:143-206) | `pm := t.power_mult` (:169); skip `t.disabled` auras when collecting |
| same | `fire_towers` (:207-324) | `disabled` check (D6); `t.power_mult` (:246); `t.miss_add`, `t.ignore_miss` (:283-285); `t.interval_mult` (:322) |
| same | `_cast_banish` (:338-384), `_summon` (:385-397) | `t.power_mult` (:343, :388); cooldowns (:375, :393) untouched |
| `sim/rules/tower_rules.gd` | `effective` (:121-150) | split into `effective_with` + wrapper (D7) |
| `ui/model/tower_stats_model.gd` | `beam_percent` (:95-108), `lit_numbers` (:111-138), `lit_effects` (:140-155) | optional `fx` |
| `ui/text/tower_text.gd` | `lit_values` (:264-275), `lit_line` (:276-293) | optional `fx`, passed through |
| `ui/tower_panel.gd` | `_refresh_table` (:228-276) | one `tower_mults` read, passed to all (D7) |
| `tests/golden_runs.gd` | `state_text` (:261-282) | `canon(t.status)` -> `canon({})` with a comment |
| `tests/sim_rule_queries_test.gd` | `test_tower_mults_follow_the_tower_state` (:187-205) | expected dicts gain `"disabled": false` |
| `tests/stats_panel_test.gd` | pokes at :323, 333, 348, 360, 377, 403, 479 | after `t.lit = ..`, also `t.reset_modifiers(); t.add_modifiers(..light_effect..)` via one helper (or `sim.step()`) |

After the LT-103 rebase, prove the site list complete: `grep -rn "_light.power_mult\|
_light.interval_mult\|TowerRules.miss_add\|TowerRules.ignore_miss\|\.status\b" sim ui scenes
tools` must show no sim reader left (EffectCatalog handlers, if LT-103 moved aura / banish code
into them, read `t.power_mult` the same way). `tools/bot_runs.gd` and `entity_layer.gd` read
`t.lit` for strategy / visuals only: unchanged.

## 5. Behaviours the tests slice must pin (each with a control)

1. Reset per tick: a tower given `add_modifiers(2.0, 3.0, 0.5, true, true)` reads neutral after
   one `step()` in the dark. Control: drop the slot-1 reset.
2. Light writes the channel through `step()`: lit / shadowed mundane and lit occult get the
   `TowerRules` values (beam and shadow config with distinct numbers). Control: drop
   `_write_light_mods`.
3. Combat reads the channel, not the flags: set the channel by hand, call
   `sim._combat.fire_towers()` directly; damage = `s.damage * factor * power_mult`, cooldown =
   `cooldown_ticks(fire_interval * interval_mult)`; same for an aura's slow, a gate's damage, a
   circle's unit DPS. Control: revert one site to `TowerRules.*(t.lit, ..)`.
4. Composition: two `add_modifiers` calls multiply power / interval in call order (values where
   `(a*b)*c != a*(b*c)` bitwise), sum `miss_add`, OR the bools. Control: `*=` -> `=`.
5. `ignore_miss` wins over `miss_add > 0`: COMBAT stream state unchanged after the shot.
6. `disabled`: no SHOT, no COMBAT / MADNESS draw, cooldown still counts down, fires on the first
   enabled tick; a disabled aura applies nothing. Control: drop the `disabled` check.
7. UI from the channel: with the channel set by hand away from `light_effect`, the panel's lit
   values and kind line show the channel's numbers; `tower_mults == t.modifiers()`. Control: the
   panel back to `state_effect`.
8. `effective(def, s, cfg, lit, shadowed, sanity) == effective_with(s, cfg, light_effect(..),
   sanity)` bit for bit over every tower level, lit / shadowed / neutral.
9. Guard D8 passes and its planted write fails.
10. Golden replay and trace byte-identical (existing suites, no regen).

## 6. Open questions for the owner

- **Q1. `ignore_miss` as a fifth field.** (Recommended) Keep it a bool, OR-composed. Benefit:
  today's "lit never misses, no COMBAT draw" stays explicit and exact. Risk: S9 named four
  fields; one more key in `tower_mults`. Alternative: encode as `miss_add = -INF` (chance <= 0,
  no draw): four fields, but a magic value the UI must special-case.
- **Q2. `disabled` semantics.** (Recommended) Cooldown keeps counting, auras off, light / shadow
  casting stays, summoned allies stay. Benefit: no light-pass ordering cycle; re-enable is
  immediate. Risk: a "lift" trait cannot also darken a lantern tower. Alternative: freeze the
  cooldown too (longer lockout, one more rule).
- **Q3. Panel marking.** (Recommended) Numbers from the channel, "lit / shadowed" wording and the
  `*` mark still keyed on `t.lit` / `t.shadowed`. Benefit: no text change now. Risk: a later
  crew buff changes numbers without a mark until LT-32 adds generic wording. Alternative: mark
  whenever the channel is non-neutral (new wording now, more UI tests touched).
- **Q4. `interval_mult` on gate / circle cooldowns.** (Recommended) Not applied, as today.
  Benefit: zero behaviour change. Risk: a future "slow the tower" trait would not slow casts and
  summons; decide in LT-106. (Applying it is also golden-safe today: both are occult, light
  gives them 1.0.)
- **Q5. Golden dump column.** (Recommended) Keep `canon({})` in the old `status` slot. Benefit: no
  regen, digests prove identity. Risk: the dump does not show the channel (it is derived from
  the dumped `lit` / `shadowed`). Alternative: dump the channel and regenerate (loses the
  byte-identical proof).
