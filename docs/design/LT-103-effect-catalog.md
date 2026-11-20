# LT-103: EffectCatalog, Level.mode and effect text in data/

Spec: LT-96 §4 S7, owner decisions D1 "1-2 башни, S7-S10 без S12 (Recommended)" and
D5 "В файле в data/". Behaviour-preserving: `tower_text_test` and `stats_rows_test` strings
identical, golden byte-identical, `data/towers.json` unchanged. Afterwards a new effect key
is 1 catalog row + 1 text entry + its behaviour.

## 1. What exists (at `ec70038`)

| List | Where | Used by |
|---|---|---|
| `EFFECTS` (key -> max) | `sim/defs/tower_def.gd:140-150` | parse, `config_valid_test`, `tower_text_test` |
| `CAST_EFFECTS`, `BANISH_KEYS`, `NOT_WITH_BANISH`, `SUMMON_KEYS`, `SUMMON_REQUIRED`, `NOT_WITH_SUMMON`, `FLAG_EFFECTS`, `PENDING` | `tower_def.gd:155-183` | `Level.parse` 243-330, `_check_cast/_summon/_banish` 333-385, `has_pending` |
| `POWER_SCALED_EFFECTS` (+ `damage_taken_multiplier` special) | `sim/rules/tower_rules.gd:152-169` | `powered_effects` |
| `neutral()` by `_multiplier` suffix, `is_pending` | `ui/model/tower_stats_model.gd:9-21` | text, delta lines |
| `EFFECT_GROUPS`, `ROW_EFFECT_KEYS`, `_effect_text` match, `special_short` ladder | `ui/text/tower_text.gd:28-37,172,302-360,412-467` | side panel, tower panel, picker |

Three attack ladders (all on shipped data agree; they differ on combos no level has):

| Ladder | Order |
|---|---|
| `Board.shot_kind` `scenes/board.gd:145-162` | support (searchlight if reveal_fakes) > banish > summon > beam > pierce > fuse > min_range "shell" > aoe > tracer; ignores burst |
| `CombatSystem.fire_towers` `sim/core/systems/combat_system.gd:213-279` | support skip > banish > summon; aim: burst > beam > single; shape: fuse > pierce > aoe > point |
| `TowerText.attack_text` `ui/text/tower_text.gd:199-215` | summon > banish > aura > beam > burst > pierce "Line" > aoe "Blast" > Single (fuse+aoe reads "Blast") |

Combat has two axes (aim, shape); board and text have one. No single precedence reproduces
all three for burst+shape, beam+shape or beam+burst. Shipped levels (data/ and golden_data/
are byte-identical) never combine them; parse already rejects fuse+pierce.

## 2. Decisions

### 2.1 EffectCatalog (`sim/defs/effect_catalog.gd`, class `EffectCatalog`)

GDScript `const ROWS := {key: {...}}` (schema, not balance: stays code, sim reads no files).
Absent fields take the default. Row order = today's `EFFECTS` order (2.5).

| Field | Default | Replaces |
|---|---|---|
| `max` | `INF` | `EFFECTS` values |
| `flag` | false | `FLAG_EFFECTS` (0 or 1; implies max 1) |
| `whole` | false | the "whole number >= 1" checks on `summon_max`, `banish_targets` |
| `neutral` | 0.0 | `TowerStatsModel.neutral` (1.0 for the two `_multiplier` keys) |
| `power` | `""` | `POWER_SCALED_EFFECTS` (`"mult"`), `damage_taken_multiplier` (`"taken"`) |
| `mode` | none | the attack ladders (2.2); set on 7 keys |
| `requires` | `[]` | `BANISH_KEYS`, `SUMMON_KEYS`, `SUMMON_REQUIRED`, fuse needs aoe, banish needs max_hp: error at this key "needs Y > 0" |
| `not_with` | `[]` | `NOT_WITH_BANISH`, `NOT_WITH_SUMMON`, `CAST_EFFECTS` pair, fuse vs pierce/pull, reveal vs fuse: error at this key "cannot combine with Y" |
| `pending` | false | `PENDING` (empty today) |

`requires`/`not_with` reproduce today's message and path for every pair: the error is
reported at the row's own key naming the other (summon: `summon_hp` "needs summon_max > 0",
`pierce` "cannot combine with summon_max"; fuse: `fuse_seconds` row has
`not_with: [pierce, pull_cells, ...]`; `reveal_fakes` row has `fuse_seconds`; `casts_shadow`
row has `casts_light`). "Family" from the spec is `requires` (the owner key), not a field.
Rules on stats stay as code in `Level.parse`: `sanity_scaling` needs damage, casts need damage
0, `min_range`, `fire_interval` with banish/summon.

API (static): `has(key)`, `keys()`, `row(key)`, `max_of`, `neutral(key)` (unknown key: the
old suffix rule, so `frost_aura` still reads 0), `is_flag`, `is_pending`, `pending_keys()`,
`power_of(key)`, `mode_order()` (keys with `mode`, sorted by `Mode`, cached in a static var).
`TowerDef.Level` keeps `is_beam/is_banish/is_summon/...` unchanged (they read keys).

### 2.2 Level.mode is in: one precedence

`enum Mode { AURA, BANISH, SUMMON, BEAM, BURST, LINE, FUSE, BLAST, SINGLE }` in
`EffectCatalog`; the enum order is the precedence, written once. Row `mode`: banish_cells
BANISH, summon_max SUMMON, sanity_scaling BEAM, burst_targets BURST, pierce LINE,
fuse_seconds FUSE, aoe_radius BLAST.

`Level.mode() -> int`: `AURA` when `not acts()`; else the first `mode_order()` key with a
value > 0; else `SINGLE`. A method, not a field cached at parse: tests set effects and stats
after parse (`dynamite_test.gd:130`, `coast_battery_test.gd:80`, `branch_effects_test.gd:710`,
`tower_role_test.gd:131`) and must keep seeing the new mode. Cost: <= 7 dict reads per shot,
the same as the ladders it replaces.

To make one precedence true for every config parse accepts, the catalog adds (Q1):
`burst_targets.not_with += [pierce, aoe_radius, fuse_seconds, sanity_scaling]`,
`sanity_scaling.not_with += [pierce, aoe_radius, fuse_seconds]`. No shipped, golden or test
level has these combos (grep of `tests/*.gd`), so golden and suites do not move.

Consumers switch on `mode()`:
- combat: dispatch AURA skip / BANISH / SUMMON; aim BURST ranked, BEAM `_beam_target`, else
  `_pick_target`; shape FUSE / LINE / BLAST / point. Values (`pierce` width, `aoe_radius`)
  still read from `effects`.
- `Board.shot_kind` keeps its signature and strings: AURA -> "searchlight" if reveal_fakes
  else "aura"; BANISH, SUMMON, BEAM same names; LINE "harpoon"; FUSE "dynamite";
  BLAST -> "shell" if `min_range > 0` else "wave"; BURST, SINGLE -> "shell" if `min_range > 0`
  else "tracer". LT-104 replaces this `match` with its look catalog keyed by `mode()` plus the
  two modifiers (min_range, reveal_fakes).
- `TowerText.attack_text`: the mode's label from the text file (FUSE reads "Blast").
- `trait_text` (picker Trait cell) is a property list, not a mode; it stays as is.

Pin before deletion (S2 step 1, tests slice keeps it): `tests/effect_mode_test.gd` holds
frozen copies of the three old ladders. (a) For every level and branch of `data/towers.json`
and `tests/fixtures/golden_data/towers.json`: new board kind, combat (aim, shape) and attack
label equal the old ones. (b) Synthetic grid: every subset of the 7 mode keys x
min_range {0, 2} x damage {0, 10} x reveal_fakes {0, 1}, companions filled (aoe for fuse,
max_hp for banish, hp/lifetime/speed for summon), parsed through `TowerDef.parse`: either
rejected, or all three new mappings equal the old ladders.

### 2.3 ALLY_CONTACT and the summon leash are not keys

`AllySystem.ALLY_CONTACT` (0.4) and leash = range + 1 (`combat_system.gd:379`) stay sim
constants: no designer asked to tune them, and a key needs a text entry and a guard row for
nothing. A later task can add `summon_leash` as one optional row, default = today (Q2).

### 2.4 Effect text in `data/effect_text.json`

Presentation-only, never loaded by `GameConfig` (like D4's `data/looks.json`), so
`golden_data/` does not mirror it. Read by `io/text_loader.gd` (IO stays in `io/`, LT-102)
on first use; `EffectText.use(table)` injects one for tests. Display order, grouping and the
"a table row says it" flag are presentation and live here, not in the sim catalog (LT-33
boundary; the spec listed them on the row, Q3).

```json
{
  "modes": {"AURA": "Aura", "BANISH": "Banish", "FUSE": "Blast", "...": "..."},
  "lines": [
    {"keys": ["pierce"], "in_row": true, "text": "Pierce: {pierce}-cell-wide line"},
    {"keys": ["slow"], "text": "Slows enemies {slow|pct}%"},
    {"keys": ["crit_chance", "crit_multiplier"],
     "text": "{crit_chance|pct}% crit, x{crit_multiplier} damage"},
    {"keys": ["banish_cells", "banish_targets"], "defaults": {"banish_targets": 1},
     "text": [{"when": {"key": "banish_targets", "gt": 1},
               "text": "Banish {banish_targets} foes {banish_cells|cells}"},
              {"text": "Banish {banish_cells|cells} back"}]}
  ],
  "short": [
    {"key": "aoe_radius", "text": "r {aoe_radius}", "keep_case": true},
    {"key": "crit_chance", "defaults": {"crit_multiplier": 1},
     "text": "{crit_chance|pct}% crit ×{crit_multiplier}"},
    {"key": "banish_targets", "when": {"key": "banish_targets", "gt": 1},
     "text": "{banish_targets} foes"}
  ]
}
```

- `lines`: in display order (today's `EFFECT_GROUPS`); the first key leads; a line shows when
  any of its keys is active (`EffectCatalog.neutral`). `in_row`: skipped by `special_lines`
  (today's `ROW_EFFECT_KEYS`: pierce, summon_flying).
- `short`: the picker's Special cell parts in their own order (it differs from `lines`);
  shown when `when` holds, default "the key is active". Joined ", "; the first letter is
  upper-cased unless the first part has `keep_case` (today's `begins_with("r ")`).
- A missing value reads the entry's `defaults`, else 0. This keeps today's asymmetry: long
  crit reads `x0` without a multiplier, short reads `×1`.
- Unknown keys keep the code fallback `key: value`; `COMING_SOON` stays in code.

Formatter `ui/text/effect_text.gd` (class `EffectText`, static, pure apart from the lazy load):
`format(template, values, defaults) -> String`; placeholders `{key}` or `{key|op}`, ops:
`num` (default, `TowerText.num`), `pct` (v x 100), `pct_over1` ((v - 1) x 100), `plus1`
(1 + v, the "x of" multiplier), `cells` (`TowerText.cells_text`),
`plural:one:many` ("unit"/"units" by v == 1). Plus `long_lines(effects, skip_in_row) ->
Array[{lead, text}]`, `short_text(effects) -> String`, `mode_label(mode) -> String`.
`TowerText.effect_lines`, `special_delta_lines`, `special_short`, `special_lines`,
`attack_text` keep their signatures and call it.

### 2.5 Guards (`tests/effect_catalog_test.gd`, `tests/effect_text_test.gd`)

1. Every catalog key is in exactly one `lines` entry; every key named in the file is a
   catalog key; every placeholder names a key and a known op; every `Mode` has a label.
2. Catalog sanity: `requires`/`not_with` name catalog keys; `flag` rows have max 1; each
   `Mode` other than AURA/SINGLE is on exactly one row.
3. Equivalence with the deleted constants (frozen as sets in the test): flags, casts, banish
   and summon key sets, both not-with sets, summon required, power-scaled, row keys,
   `EFFECT_GROUPS` (as ordered list of sets).
4. The mode pin (2.2).

Check sequence: `config_reject_test` pins error *counts* (`errors.size()` 1, 2, 4, 5), and
today some checks zero a value after an error (reveal_fakes, casts_shadow, flags, whole
numbers), which changes later checks. So `Level.parse` keeps today's phases in today's order
(fuse, flags, reveal, sanity, cast, banish, summon) with today's zeroing; each phase only
reads its key list from the catalog (`requires_of(k)`, `keys_not_with(k)`, in catalog order).
Catalog row order = today's `EFFECTS` order, so within-phase order moves least. Pin:
`config_reject_test` and the 6 `*_config_test` files unchanged and green.

### 2.6 Friendly to LT-104 and LT-105

LT-104 reads `Level.mode()` and `EffectCatalog.Mode`; S2 leaves `shot_kind` a pure static
`match` it can lift out. LT-105 touches `tower_rules.gd`/`combat_system.gd`: S2 keeps
`TowerRules.powered_effects(s, power)` and `effective(...)` signatures (only the loop source
changes) and touches only `fire_towers`' dispatch lines, not the damage/cooldown math.

## 3. EDIT MAP

### S2 "catalog replaces lists and ladders"

Change:
- new `sim/defs/effect_catalog.gd`: `Mode`, `ROWS` (29 keys), API of 2.1.
- `sim/defs/tower_def.gd:139-183`: drop `EFFECTS` .. `PENDING`; 236-241 `has_pending` via
  `EffectCatalog.pending_keys()`; 243-330 `Level.parse`: `check_keys` against
  `EffectCatalog.keys()`, max from row; every phase and 333-385 `_check_cast/_summon/
  _banish` keep their order and zeroing, lists from the catalog (2.5); add `mode()`.
- `sim/rules/tower_rules.gd:149-169`: `powered_effects` loops rows with `power`.
- `sim/core/systems/combat_system.gd:213-235, 263-279, 306-308`: dispatch on `s.mode()`.
- `scenes/board.gd:139-162`: `shot_kind` as `match s.mode()` (strings unchanged).
- `ui/model/tower_stats_model.gd:9-21`: `neutral`, `is_pending` delegate to the catalog.
- `ui/text/tower_text.gd:199-215`: `attack_text` via mode (labels inline until S3).
- tests naming removed constants: `tower_text_test.gd:203-205,452`,
  `tower_role_test.gd:116,141,151`, `config_valid_test.gd:340-345` -> catalog API.
- new `tests/effect_mode_test.gd` (written first, green against the old ladders), catalog
  guards 2.5 items 2-3.
Read for context: `TowerDef.Level` helpers 190-233; `combat_system.gd` `_cast_banish`
338-384, `_summon` 385-397; `scenes/board/entity_layer.gd:166,199,297`,
`fx_layer.gd:147` (shot_kind callers); `sim/config_reader.gd:58` `check_keys`.

### S3 "effect text in data/ with formatter"

Change:
- new `data/effect_text.json` (all of `_effect_text`, `special_short`, mode labels).
- new `io/text_loader.gd`, new `ui/text/effect_text.gd` (2.4).
- `ui/text/tower_text.gd:27-37` drop `EFFECT_GROUPS`; 61-80 `effect_lines`; 119-160
  `special_delta_lines` (groups from the file); 171-172 drop `ROW_EFFECT_KEYS`; 199-215
  labels; 299-360 `special_short`, `special_lines`; 405-467 drop `_keys_dict`, `_effect_text`.
- new `tests/effect_text_test.gd` (guard 2.5 item 1, formatter ops).
Read for context: `num`, `cells_text` (40-50); callers `ui/side_panel.gd:130`,
`ui/tower_panel.gd:258-268`, `ui/tower_picker.gd:198`; `tests/tower_text_test.gd`,
`tests/stats_rows_test.gd` (must pass unedited apart from S2's constant renames).

## 4. Behaviours the tests slice must pin (one control each)

1. Mode pin on shipped + golden levels and the synthetic grid (control: swap BEAM/BURST in
   `Mode`).
2. New exclusions reject burst+pierce/aoe/fuse/sanity_scaling and beam+pierce/aoe/fuse with
   "cannot combine with" (control: drop one `not_with`).
3. `mode()` follows effects set after parse (control: cache mode at parse).
4. Power scaling: slow, strip_armor, banish_cells, summon_dps x power, taken by
   `powered_taken_mult`, shooters unchanged (control: drop `power` on `summon_dps`).
5. Every catalog key has exactly one text line; a key missing from the file fails the guard
   (control: delete the `strip_armor` entry).
6. Formatter ops `pct`, `pct_over1`, `plus1`, `cells`, `plural`, `defaults` (long `x0` vs
   short `×1` crit), `when` variants (banish_targets 1 vs 2), `keep_case` (control: break
   `plural`).
7. `in_row` keys absent from `special_lines`, present in `effect_lines` (control: drop
   `in_row` on pierce).
8. Unknown key fallback `frost_aura: 2.5` and neutral by suffix for unknown `_multiplier`.
Plus unchanged: `tower_text_test`, `stats_rows_test`, `tower_attack_visuals_test`,
`config_reject_test`, the 6 `*_config_test`, golden replay byte-identical, fire_towers tick
cost within 5 %.

## 5. Open questions for the owner

**Q1. How to get one precedence (Level.mode)?**
- **Reject the combos the ladders disagree on: burst or beam with a shot shape, beam with
  burst (Recommended).** Benefit: one enum, combat/board/text cannot drift, LT-104 keys looks
  on it directly. Risk: a burst harpoon or a blast beam needs a new `Mode` value first.
- Two axes, `mode` (look/shape) + `aim` (single/burst/beam), only beam+shape rejected.
  Benefit: keeps burst+shape open. Risk: two enums to keep in step; looks still need a rule.
- Mode only for board and text; combat keeps its own ladder. Benefit: no config change.
  Risk: not one precedence; the drift stays in the sim.

**Q2. ALLY_CONTACT and the summon leash as effect keys?**
- **No, they stay sim constants (Recommended).** Benefit: no unused knobs or text. Risk: a
  circle with a different leash later needs one row then.
- Yes, optional `summon_leash`/`summon_contact`, absent = today. Benefit: tunable per level
  now. Risk: two rows and two text lines nobody uses yet.

**Q3. Display order, grouping and "said by a row" in the text file, not in the catalog?**
- **In `data/effect_text.json` (Recommended).** Benefit: sim catalog holds no presentation
  (LT-33); text edits never touch `sim/`. Risk: a new key edits two files (as D5 implies).
- In the catalog rows, as the spec listed. Benefit: one place per key. Risk: presentation
  fields in `sim/defs`.

**Q4. Text file format?**
- **JSON with templates, ops and `when` variants (2.4) (Recommended).** Benefit: same tooling
  as the other `data/` files, duplicate-key check reused. Risk: a small template language to
  maintain.
- Godot translation CSV (key -> string, logic stays in code). Benefit: localisation-ready.
  Risk: variants and grouping stay in code, so a new key still edits `tower_text.gd`.

## Owner decisions (2026-11-20)

- Q1: "Отклонять спорные комбо (Recommended)" — reject burst/beam with a shot shape and beam with burst; one `Mode` enum.
- Q2: "Да, опциональные ключи" — ALLY_CONTACT and the summon leash become optional effect keys
  (`summon_contact` / `summon_leash`, absent = today's constants), each with a catalog row and a text entry.
  This overrides the note's recommendation; the S2 edit map must add them.
- Q3: "В data/effect_text.json (Recommended)".
- Q4: "JSON с шаблонами (Recommended)".
