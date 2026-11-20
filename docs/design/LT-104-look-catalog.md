# LT-104: look catalog (LT-96 S8, owner decision D4)

Status: design (S1). Base: `release-0.9.0` at `d9c494b` (LT-103 merged). No production code here.
D4: "По режиму атаки + data/looks.json (Recommended)": the look is derived from the attack mode;
an optional, presentation-only `data/looks.json` overrides it, enemies (and bosses) included.

## 1. What exists

- `Board.shot_kind(t)` (`scenes/board.gd:146-163`): one `match` on `Level.mode()` plus two
  modifiers (`reveal_fakes`, `min_range`) -> 10 look ids: tracer, harpoon, wave, aura,
  searchlight, dynamite, shell, beam, banish, summon. 30+ test assertions use it.
- Colour: `EntityLayer.attack_color(kind)` (`entity_layer.gd:108-133`) maps the id to `Board.*_COLOR`,
  `WARD_COLOR`, `SEARCHLIGHT_COLOR`, `SUMMON_COLOR`; tower frame + glyph use it (`_draw_tower`).
- Builder: `FxLayer._shot_fx` (`fx_layer.gd:146-214`) builds the effect dict per id; renderer:
  `_draw_effects` (`:300-331`) dispatches on `fx["kind"]` to `_draw_tracer` ... `_draw_blast`,
  each reading its colour constant directly (`Board.TRACER_COLOR` etc., 30 sites).
- Area renderers on the entity layer: `_draw_auras` (aura / searchlight), `_draw_allies` (summon ring).
- Cap: `MAX_FX_PER_TOWER = 2` per tower (`_add_attack_fx`, `:223-234`); banish uses
  `maxi(2, banish_targets())`; beam drops its previous beam first (`_drop_beam`), so 1 held.
- Enemies: every enemy is the same `COLOR_ENEMY` circle r 0.25 cell (`_draw_enemies`, `:238-292`);
  status markers (slow, vuln, bleed, sealed) are keyed by sim status, not by look.
- Presentation data precedent: `data/effect_text.json` via `TextLoader.read_json` +
  `EffectText.use/table/errors/validate`; `Main._ready` refuses to start on its errors.
- No shipped enemy has the `boss` trait (`grep boss data/*.json`: none). Fakes copy their def
  (`spawn_enemy(def_id, true)`); bosses are never mimicked (`HallucinationSystem.BOSS_TRAIT`).

## 2. Decisions

### 2.1 `LookCatalog` (`scenes/board/look_catalog.gd`, static, `extends RefCounted`)

Built-in rows live in code (they name draw code); `data/looks.json` only adds variants of them
and assigns looks to ids. Rows are built once in a static func (`_builtin()`, cached in a static
var), not as a `const` Dictionary: a const referring to `Board.*_COLOR` while `Board` calls the
catalog risks a cyclic-parse error in Godot 4.

**Tower look entry** (one per id; today's 10 ids keep their names):

| field | meaning | built-in values |
|---|---|---|
| `color` | attack colour: tower frame + glyph, the effect's primary colour | today's constant per id |
| `fx` | builder + renderer pair in FxLayer (`""` = no SHOT effect) | tracer, harpoon, wave, shell, beam, dynamite, banish; `""` for aura, searchlight, summon |
| `area` | entity-layer area renderer (`""` none) | `ward` (aura), `searchlight`, `summon_ring` (summon) |
| `modes` | `EffectCatalog.Mode`s the `fx`/`area` can draw | tracer [SINGLE, BURST]; shell [SINGLE, BURST, BLAST]; wave [BLAST]; harpoon [LINE]; beam [BEAM]; dynamite [FUSE]; banish [BANISH]; aura, searchlight [AURA]; summon [SUMMON] |
| `cap` | live attack effects per tower | 2 for all (`MAX_FX_PER_TOWER` stays as the default) |
| `marker` | tower tile style | `frame` (attack-colour frame + glyph) for all |

`fx` is one name for a builder (branch of `_shot_fx`) and its renderer (`_draw_*`): they are a
pair in code (the renderer reads fields only its builder writes), so a look cannot mix them.
Secondary colours (wave fill, beam core, smoke, stick, astray) stay constants.

**Enemy look entry**: `color` (body), `radius` (cells), `ring` (bool: a dark 2 px rim).
Built-in: `enemy` {COLOR_ENEMY, 0.25, false}; `boss` {COLOR_ENEMY, 0.36, true} (Q2). Marker
geometry follows the radius: every marker radius / HP-bar offset becomes `radius + (today's
value - 0.25)`, so it is unchanged at 0.25. Madness lerps `look.color -> COLOR_ENEMY_MAD`;
revealed, flicker and status markers apply to every look alike.

### 2.2 Derivation from Mode (default)

`derived_tower_look(s: TowerDef.Level) -> String` is today's `shot_kind` body moved verbatim.
`derived_enemy_look(def: EnemyDef) -> String`: `boss` if `def.traits.has("boss")` else `enemy`.

`tower_look(t: SimTower) -> String`: `o := towers.get(t.def.id)`; if `o` and
`t.stats().mode() in row(o).modes` -> `o`, else derived. The mode check means an override on a
tower whose branch changes mode (e.g. adds pierce) falls back to the derived look there instead
of feeding SHOT fields to the wrong builder. `enemy_look(e)`: `enemies.get(e.def.id)` else
derived. Keyed by def id only: a fake and a real of one def look alike (render isolation holds;
the catalog never reads `is_fake`). Not cached on the tower: level/branch change on upgrade;
the cost is one `mode()` + two dict reads, the same order as today's `shot_kind`.

`Board.shot_kind(t)` stays as a one-line wrapper over `tower_look(t)` (keeps the test surface);
`EntityLayer.attack_color(id)` wraps `LookCatalog.color(id)` (BLACK for unknown, as today).

### 2.3 `data/looks.json`: schema, loading, validation

```json
{
  "looks":   { "pale_tracer": { "base": "tracer", "color": [1.2, 2.0, 2.4], "cap": 3 },
               "spawn_body":  { "base": "enemy",  "color": [0.4, 0.7, 0.9], "radius": 0.3 } },
  "towers":  { "rifleman": "pale_tracer" },
  "enemies": { "deep_one": "spawn_body", "shoggoth": "boss" }
}
```

- Every section optional. A variant copies its `base` row (a built-in id; tower or enemy kind
  follows the base) and overrides only `color` ([r,g,b] or [r,g,b,a], each 0..4, HDR as the
  constants), `cap` (int 1..8, tower looks) or `radius` (0.15..0.5, enemy looks) / `ring` (bool).
  `fx`, `area`, `modes`, `marker` are not data: a new renderer is code (one row + one `_draw_*`).
- Variant ids must not shadow a built-in id (Q4). `towers.<id>` names a tower look, `enemies.<id>`
  an enemy look (built-in or variant).
- Loading mirrors `EffectText`: `PATH`, `use(table)` (tests; `null` resets), `table()` lazy
  via `TextLoader.read_json`, `errors()`, `validate(t)`. **Missing file = empty table, no error**
  (the file is optional). Invalid file: each problem `push_error`s, table = {} (all derived).
- `check_config(config: GameConfig) -> Array[String]`: unknown tower/enemy ids; a tower override
  whose look's `modes` match none of that tower's levels/branches (a dead override).
- `Main._ready` (`scenes/main.gd:23-40`), after the `EffectText` check: refuse to start on
  `LookCatalog.errors() + check_config(result.config)` (Q1).
- The sim never loads it: not in `ConfigLoader`, not in `GameConfig`, not mirrored in
  `tests/fixtures/golden_data/`. A guard forbids `LookCatalog` / `looks.json` under `sim/`.
- Ship `data/looks.json` as `{"looks": {}, "towers": {}, "enemies": {}}`: the schema is
  discoverable and shipped visuals stay unchanged.

### 2.4 Caps (fx pooling limits) per look

`_add_attack_fx(fx, cap)` keeps its per-tower count (all of the tower's live attack effects,
whatever look: a tower has one look at a time). `cap = row(fx.look).cap`; the banish builder
keeps `maxi(cap, banish_targets())`; the beam builder keeps "drop own beam, then add" (a builder
rule, not data). BLAST / death / dissolve / leak flashes stay uncapped.

### 2.5 Where the look reaches the effect

`_shot_fx` writes `fx["kind"] = row.fx` (drives `_draw_effects`, unchanged strings for built-ins),
`fx["look"] = id`, `fx["color"] = row.color`. Each `_draw_*` reads
`fx.get("color", Board.X_COLOR)` instead of the constant (hand-built dicts in `lt62_fps_test`
keep working). `on_event` branches on `fx["kind"]` (builder), astray fizzle on `kind == "wave"`
as today. BLAST: colour from the look of `ev.data["tower"]` if alive, else of the def
`ev.data["def"]` (a sold tower), else `DYNAMITE_COLOR`. Allies: ring and claw colour from the
look of `a.source` (tower def id, survives a sale). Shipped output is pixel-identical: with an
empty `looks.json` every row resolves to today's constant, radius and cap; no shipped boss.

## 3. EDIT MAP (code slice)

| file | function | lines | change |
|---|---|---|---|
| `scenes/board/look_catalog.gd` | new | - | rows, `derived_*`, `tower_look`, `enemy_look`, `row`/`enemy_row`/`color`/`ally_color(def_id)`, `use/table/errors/validate/check_config` |
| `data/looks.json` | new | - | empty sections |
| `scenes/board.gd` | header doc | 9-17 | mention LookCatalog |
| `scenes/board.gd` | `shot_kind` | 139-163 | body -> `LookCatalog.tower_look(t)`; ladder moves to `derived_tower_look` |
| `scenes/board/entity_layer.gd` | `attack_color` | 107-133 | -> `LookCatalog.color(kind)` |
| same | `_draw_auras` | 197-218 | switch on `row.area`; ward colour from the row |
| same | `_draw_searchlight` | 221-235 | take the colour as an argument |
| same | `_draw_enemies` | 238-292 | body colour/radius/ring from `enemy_row(enemy_look(e))`; marker radii offset by radius |
| same | `_draw_allies` | 295-317 | ring when `row.area == "summon_ring"`; colours via `ally_color(a.source)` |
| `scenes/board/fx_layer.gd` | `on_event` | 93-131 | cap from row; branches on builder; BLAST colour |
| same | `_shot_fx` | 146-214 | `kind = row.fx`; write `look`, `color` |
| same | `_add_attack_fx` | 223-234 | default cap stays `MAX_FX_PER_TOWER` |
| same | `_draw_tracer`, `_harpoon`, `_wave`, `_beam`, `_banish`, `_shell`, `_charge`, `_stick`, `_blast` | 369-392, 395-430, 433-456, 459-488, 491-528, 531-578, 581-618, 638-652, 655-673 | `Board.X_COLOR` -> `fx.get("color", Board.X_COLOR)` (`_stick` gets it as an argument) |
| `scenes/main.gd` | `_ready` | 23-40 | refuse to start on look errors |
| `io/text_loader.gd` | doc | 3-5 | list looks.json |

Read first: `ui/text/effect_text.gd` `use`/`table`/`errors` (31-66) as the loader pattern;
`sim/defs/enemy_def.gd` TRAITS (23-33); `sim/core/sim_ally.gd` fields; `Level.mode()` in
`sim/defs/tower_def.gd`. `_draw_warmup` (290-298) keeps `TRACER_COLOR` (alpha 0.01, invisible).

## 4. Behaviours for the tests slice (one control each; pick 6-8)

1. Empty table: `tower_look` == `derived_tower_look` for every level/branch of shipped and golden
   towers; `enemy_look` == `enemy` for every shipped enemy; colours equal today's constants.
   Re-point `effect_mode_test` to `derived_tower_look` (a future override must not break it).
2. Tower override: a tracer variant on rifleman -> `shot_kind` is the variant, the SHOT fx has
   `kind` "tracer" and the variant colour, `attack_color` returns it. Control: ignore overrides.
3. Mode check: override on a tower whose L3 branch adds `pierce` -> L1/L2 variant, L3 "harpoon".
   Control: drop the `modes` check.
4. Cap: variant `cap: 3` keeps 3 live fx after 4 SHOTs; built-ins keep 2; banish keeps
   `max(cap, targets)`. Control: `_add_attack_fx` ignores the row cap.
5. Enemy look: an override changes the body colour/radius row; a real and a fake of one def get
   the same look; a def with `boss` trait derives `boss`. Control: `enemy_look` ignores `boss`.
6. Validation: each rejection names its path (unknown root/field, bad/unknown base, built-in id
   shadowed, bad colour, cap/radius out of range, tower look under `enemies` and vice versa,
   duplicate key); `check_config` flags unknown ids and a dead override. Control: `validate` returns [].
7. Missing file -> no errors, all derived; real `data/looks.json` -> no errors and
   `check_config(real config)` empty; Main refuses to start on an invalid table.
8. BLAST and ally colours follow the tower look (incl. a sold tower via def id).
   Control: BLAST hard-codes `DYNAMITE_COLOR`.
9. Guard: no `sim/` file references `LookCatalog` / `looks.json` (control: a throwaway reference).
Must stay green unchanged: `tower_attack_visuals_test`, `render_isolation_test`, `board_layers_test`.

## 5. Frame-time comparison (measure slice)

- Probe: LT-62 Appendix B `probe3.gd` (`docs/design/LT-62-fps-real-play.md:506`), main scene,
  boot-fit window, occult bot, `--seed=4242 --sanity=<0|100> --frame-stats --mute
  --audio-driver Dummy --probe-secs=60`.
- Arms (each in its own detached worktree): A = `release-0.9.0` tip; B = LT-104 tip with the
  shipped empty `looks.json`; C = B plus a throwaway `looks.json` overriding every tower and
  enemy (exercises the override path). 3 runs per arm x sanity, interleaved A B C, launch gated
  on 1-min load < 25; record `uptime` and `/usr/bin/time -p` per run.
- Report median and p90 frame interval per arm; "not worse" = B and C within the A-vs-A spread
  of the repeats. Arm tell: the probe prints `ResourceLoader.exists("res://scenes/board/look_catalog.gd")`
  (false in A) and, in C, `LookCatalog.tower_look` of one tower (the variant id).
- Cheap side check (headless, no window): 100k calls of `Board.shot_kind` over all shipped
  towers, A vs B, `Time.get_ticks_usec`.

## 6. Open questions for the owner

- **Q1 Invalid `looks.json`.** (a) Refuse to start, like `effect_text.json` (Recommended). Benefit:
  a typo never ships silently. Risk: a cosmetic file can block the game. (b) Warn, use derived
  looks. Benefit: never blocks. Risk: a broken override goes unnoticed.
- **Q2 Built-in boss look.** (a) `boss` = same colour, radius 0.36, dark rim, markers scaled
  (Recommended). Benefit: a boss reads as one with no data; no shipped boss, so nothing changes
  today. Risk: the first boss's look is a code default, not a designed one. (b) No built-in boss;
  bosses look like enemies until `looks.json` names one. Benefit: no guess. Risk: a boss shipped
  without an entry looks like a cultist.
- **Q3 Override granularity.** (a) Per tower id, applied to the levels whose mode the look draws
  (Recommended). Benefit: one line per tower, upgrades that change mode stay correct. Risk: no
  per-level/branch look. (b) Keys per level/branch (`"rifleman.L3a"`). Benefit: full control.
  Risk: more entries to keep in sync with tower ids.
- **Q4 Built-in ids in data.** (a) Variants only; built-ins are not recoloured in place
  (Recommended). Benefit: built-in colours stay where tests pin them. Risk: recolouring all
  tracers takes one variant plus one assignment per tower. (b) Allow `looks.tracer.color`.
  Benefit: one line recolours a whole look. Risk: shipped visuals drift from the pinned constants.
