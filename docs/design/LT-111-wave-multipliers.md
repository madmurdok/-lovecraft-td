# LT-111: per-wave hp_mult / speed_mult (design note)

Source: LT-96 §4 block S16, owner decision D11 "Множители hp_mult/speed_mult на волну (S16)"
(HP-cap semantics decided here). Rule LT-100 (`sim/config.gd` header): a new mechanic's config
is an optional key; absent means off. LT-12 §2: a fake enters through the same
`SpawnSystem.spawn_enemy` / `_enter` path as a real enemy.

## 1. Data

`waves.json`, each wave object: optional `hp_mult` and `speed_mult` next to `groups`.
Absent = 1.0. Example: `{"hp_mult": 1.5, "speed_mult": 1.1, "groups": [...]}`.
Balance-lab variants can set them with the existing patch format
(`"waves": {"4": {"hp_mult": 2}}`), so the lab needs no code to test them.

**Validation** (`WavesConfig.Wave.parse`): both go into `WAVE_FIELDS` (otherwise
`check_keys` rejects them as unknown); `r.opt_number(obj, key, path, 1.0, 0.0, 10.0, true)`,
so 0 or below, above 10, and non-numbers are config errors at `waves[i].hp_mult`. JSON has no
NaN/INF. The upper bound only catches typos (`150` for `1.5`); see Q2.

## 2. Where the multiplier applies

Only in `SpawnSystem._enter`, the one place an enemy gets its HP and speed:

```
var m := _wave_mults()            # [hp_mult, speed_mult] of the current wave
e.hp = def.hp * m[0]
e.max_hp = e.hp
e.base_max_hp = def.hp            # Q1: what the caps read
e.base_units_per_tick = SimTime.units_per_tick(def.speed * m[1])
```

`_wave_mults()` reads `_state.wave_index` (1-based, "current or last started wave") and
returns that wave's pair when `1 <= wave_index <= waves.size()`, else `[1.0, 1.0]` (before
wave 1, ScriptedSpawner and facade test spawns, a null `waves`).

- **Fakes:** same `_enter`, so a fake gets the same multiplier with no extra code (LT-12:
  a fake must not be told apart by its HP bar or pace).
- **Pack members** queued by LT-63 resolve the wave at entry. Equivalent to resolving at
  `spawn_enemy`: a real member always enters before its wave can clear
  (`has_queued_real_members`), fake members are dropped at dawn, and `debug_end_night`
  clears the queue. No queue-entry change.
- **Debug/sandbox spawns in BUILD** use the last started wave's multiplier (wave_index keeps
  it). Acceptable for a debug tool; noted, not special-cased.
- **Untouched:** bounty/drop, leak damage, armor, sanity, the runtime per-tick
  `SimEnemy.speed_mult` (slows). Name the parsed fields `hp_mult`/`speed_mult` on `Wave`;
  the local in `_enter` must not be confused with `SimEnemy.speed_mult`.
- The pending `regen` trait (`hp_percent_per_second`) would read `max_hp`, so it scales with
  the wave. Right by intent; note it for whoever implements regen.

## 3. Rounding of units_per_tick

One rounding: `units_per_tick(def.speed * speed_mult)` = `roundi(speed x 1000)`. Resolution
0.001 cell/s, error <= 0.0005 cell/s, same as any hand-written speed. Rejected:
`roundi(units_per_tick(def.speed) * speed_mult)` (two roundings, can differ by 1 unit/tick).
`move()` keeps its own per-tick `roundi(base_units_per_tick * e.speed_mult)` unchanged.

HP is not rounded (`hp`/`max_hp` are floats today; `60 * 1.15` may be `68.99999999999999`).
Rounding to whole HP would add `roundf` on the 1.0 path too and change a fixture with a
fractional `hp`; not worth it (Q3).

## 4. Golden byte-identical with the fields absent

Unconditional multiply, no branch. IEEE 754 multiplication by 1.0 is exact for every finite
double (`x * 1.0 == x`, same bits), so `def.hp * 1.0` and `def.speed * 1.0` give the very
same inputs as today; `max_hp == base_max_hp == def.hp`, so both cap comparisons return what
they return now. `tests/fixtures/golden_data/waves.json` has no multipliers, and
`GoldenRuns.state_text` lists enemy fields explicitly (a new `base_max_hp` field is not
printed). Expected: golden trace and replay suites green with no re-pin.

## 5. HP caps (pull_max_hp, banish_max_hp): base HP (Q1)

Recommended: the caps compare the enemy's **base** max HP (before `hp_mult`), a new field
`SimEnemy.base_max_hp`. Reason, from today's data: Ultimate Gate is "any size",
`banish_max_hp` 4000, shoggoth 3600 HP. Compared on scaled HP, a wave with `hp_mult >= 1.112`
silently makes the shoggoth unbanishable; the 500 caps flip a hybrid (240) at `>= 2.09`.
A cap is a size class of the enemy type; a difficulty multiplier should not switch tower
roles on and off at hidden thresholds.

Why a field and not `e.def.hp`: tests size enemies through `tower_test_base.put()`, which
sets `e.max_hp = hp` on a 60-HP cultist (silver_key_test, branch_effects_test pin the caps
at 400/500/501/4000 that way). `put()` sets `base_max_hp = hp` too, so those suites keep
their meaning unchanged. `SimEnemy.new()` in tests leaves both at 0.0, as `max_hp` is now.

## (1) EDIT MAP (one code slice)

Edit:
- `sim/defs/waves_config.gd:29-49` `Wave`: `WAVE_FIELDS += hp_mult, speed_mult`; fields
  `var hp_mult := 1.0`, `var speed_mult := 1.0`; parse with `opt_number` as §1.
- `sim/core/sim_enemy.gd:7-8`: add `var base_max_hp: float` with a doc line (cap size, §5).
- `sim/core/systems/spawn_system.gd:92-108` `_enter`: §2 block; new private
  `_wave_mults()` right after it; extend the `_enter` doc comment (LT-111).
- `sim/core/systems/combat_system.gd:396-404` `_banishable` and `:616-620` (pull cap in the
  harpoon block): `e.max_hp` / `target.max_hp` -> `base_max_hp`; doc comments at 397, 600.
- `tests/tower_test_base.gd:25-36` `put()`: also `e.base_max_hp = hp`; doc line.
- `docs/GDD.md:303`: "per wave: spawn groups ...; optional hp_mult / speed_mult (LT-111)".
Read only: `sim/core/sim_time.gd:36-37` `units_per_tick`; `sim/config_reader.gd:188-191`
`opt_number`; `sim/core/wave_director.gd:153-154` `_current_wave` (same indexing);
`tests/wave_test_base.gd:14-31` `wconfig` (packs only groups: tests need a per-wave dict).

## (2) Behaviours for the tests slice

1. A wave with `hp_mult: 2` spawns enemies with `hp == max_hp == 2 x def.hp`; its
   `speed_mult: 1.5` gives `base_units_per_tick == units_per_tick(def.speed x 1.5)`.
2. A wave without the fields: `hp == def.hp`, `base_units_per_tick == units_per_tick(def.speed)`
   (and wave N+1 with fields after wave N without: per-wave, not sticky).
3. A fake spawned during a scaled wave (via `spawn_enemy(id, true)` at that wave_index) has the
   same HP and speed as a real one.
4. A queued pack member gets the multiplier of its wave.
5. Spawns before wave 1 (wave_index 0) use 1.0.
6. Cap rule: an enemy whose base HP is under the cap but scaled HP is over it is still
   banished / pulled (e.g. shoggoth at `hp_mult 1.5` vs Ultimate Gate 4000).
7. Config: `hp_mult`/`speed_mult` of 0, -1, 11, `"x"` are rejected with the path
   `waves[i].hp_mult`; 1.0 and 10 load; absent loads as 1.0.
8. Golden trace/replay suites unchanged (run in verify, no re-pin).
Controls: drop the multiply in `_enter` (1, 3, 4 fail); read `max_hp` in the caps (6 fails);
drop the range in `opt_number` (7 fails); multiply speed after rounding is not a control.

## (3) Open questions for the owner

- **Q1. HP caps compare base or scaled HP?** *Base, new `base_max_hp` (Recommended).*
  Benefit: tower roles ("any size", "<= 500 HP") stay a property of the enemy type, no hidden
  cliffs (shoggoth at x1.112). Risk: the tooltip "Max 500 HP" then means base HP; a x2
  cultist wave shows bars of 120 HP while the cap reasons in 60. *Scaled (`max_hp`, no
  combat change)*: benefit: the number means what it says, zero combat edits; risk: control
  towers silently lose targets as waves scale.
- **Q2. Validation range?** *(0, 10] (Recommended).* Benefit: catches typos, allows the lab's
  x2/x/2 steps comfortably. Risk: a deliberate x12 needs a one-line bound change.
  *Only > 0*: no ceiling, typos load.
- **Q3. Round scaled HP to whole numbers?** *No (Recommended).* Benefit: zero float ops on
  the 1.0 path beyond the exact multiply; golden certainly identical. Risk: an HP readout
  could show 68.99999 where text formats raw floats (bars use the ratio, unaffected).
  *Yes, `roundf`*: clean numbers; risk: changes enemies with a fractional base `hp`.
