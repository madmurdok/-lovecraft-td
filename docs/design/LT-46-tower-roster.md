# LT-46 — Tower roster: 5 mundane + 5 occult, two branches each (design note)

Status: draft for owner review · 2026-11-01 · branch `docs/LT-46-tower-roster`. Line numbers
are `main` at `10eea26` (0.3.0 bump).

Source: owner, 0.3 planning: "Нужна вариативность, штук 5 обычных башен и штук 5
оккультных. И по 2 ветки прокачки у каждой". The owner chose five of the new towers
(Dynamite crew LT-47, Coast battery LT-48, Tillinghast Resonator LT-50, Silver Key Gate LT-51,
Summoning Circle LT-52); the fifth mundane tower (LT-49) is chosen at this review (§7 Q1).
Ideas not taken are recorded in `docs/GDD.md` §6.1 "Parked tower ideas" ("Остальные решения
запиши в документы, может вернемся к ним").

---

## 0. What exists today and what this task adds

**Today** (`data/towers.json`, `sim/defs/tower_def.gd`, `sim/core/simulation.gd`):
- 4 towers: Rifleman, Harpooner (mundane), Elder Sign, Necronomicon Reader (occult). Each has
  L1 + L2 in `levels` and L3 branches `a`/`b` (`TowerDef.LEVEL_COUNT = 2`, `BRANCH_IDS`).
- Level fields: `upgrade_cost`, `range`, `damage`, `fire_interval`, `sanity_reserve`,
  `madness_affected`, `effects` (numeric only; allowed keys and max values in
  `TowerDef.Level.EFFECTS`, `tower_def.gd:92-96`).
- The sim applies `pierce` (line shot), `aoe_radius` (blast at the target), `slow` and
  `damage_taken_multiplier` (aura of a `damage <= 0` tower). `crit_chance`,
  `crit_multiplier`, `shooters`, `bleed_*`, `pull_cells`, `strip_armor` are parsed but in
  `Level.PENDING` (`tower_def.gd:101-102`): LT-29 wires them.
- Every attack is instant (no projectile entity). "Support tower" means `damage <= 0` in five
  places (§5, "Support checks").
- Flyers: `EnemyDef.flying` only picks a straight route S → L (`spawn_enemy`,
  `simulation.gd:146`). No tower is ground-only; every tower hits flyers.
- Enemy traits `tower_harass`, `tower_lift`, `regen` are parsed (`enemy_def.gd:22-24`) but
  not applied yet. Dagon is in GDD §7, not in `data/enemies.json`.
- `SimEnemy.revealed` exists (`sim_enemy.gd:16`) and the board draws it
  (`board.gd:455`), but nothing in the sim sets it: **there is no counter to hallucinations
  in data today.** GDD §6 lists a Searchlight tower with a Revealing branch; it was never
  added to `towers.json` (it is now a parked idea, and a candidate for LT-49, §7 Q1).
- The board draws a tower as its name's first letter (`board.gd:416`, `t.def.name.left(1)`):
  Silver Key and Summoning Circle (and Searchlight) would all be "S".
- LT-30 (lighthouse beam in the sim, in progress) adds `SimTower.lit` / `SimEnemy.lit`: lit
  mundane towers fire with `fire_interval × 0.8` and never miss; lit occult towers lose 30 %
  "power" (LT-23 Q7: no sanity effect).

**This task adds** a design only: the roster of 10, starting numbers, the shared sim pieces
and which task builds each, and the edit map for LT-47..LT-52. No code.

---

## 1. Roster and roles

| # | Tower | Kind | Task | Role line (≤ 24 chars) | Niche |
|---|---|---|---|---|---|
| 1 | Rifleman | mundane | (exists) | Steady single target | cheap all-rounder, sanity regen from kills |
| 2 | Harpooner | mundane | (exists) | Pierces a line of foes | lines of walkers, packs |
| 3 | Dynamite crew | mundane | LT-47 | Fused blast, ground only | packs, cheap AoE; blind to flyers |
| 4 | Coast battery | mundane | LT-48 | Long-range heavy gun | armor, big HP, flyers far out; dead zone up close |
| 5 | 5th mundane | mundane | LT-49 | per §7 Q1 | recommended: Searchlight, reveals fakes |
| 6 | Elder Sign | occult | (exists) | Aura: slows and exposes | force multiplier |
| 7 | Necronomicon Reader | occult | (exists) | Area blast, uses sanity | heavy AoE |
| 8 | Tillinghast Resonator | occult | LT-50 | Beam grows as you fray | sustained, armor-ignoring single target; rewards low sanity |
| 9 | Silver Key Gate | occult | LT-51 | Sends foes back the path | buys time, anti-leak, anti-runner |
| 10 | Summoning Circle | occult | LT-52 | Summons a fighting ghoul | blocks ground enemies, harassers |

Glyphs (board letter, §4 piece P11): R, H, D, **B** (Battery), S (Searchlight) / E, N, T,
**K** (Key), **C** (Circle).

### 1.1 Counters matrix

`++` strong, `+` fine, `−` weak, `×` cannot. Enemy numbers from `data/enemies.json`; Dagon
from GDD §7. Fakes: whether the tower helps against hallucinations.

| Tower | Cultist (60, harass) | Hybrid (210, armor 2) | Deep One (pack 4-6, fast) | Night-gaunt (flyer, leak 2) | Shoggoth (3600, armor 5, regen) | Dagon (boss) | Fakes |
|---|---|---|---|---|---|---|---|
| Rifleman | ++ | + | + | + | − (armor halves 10) | − | − (wastes shots) |
| Harpooner | + | + | ++ | + | + | + | − |
| Dynamite crew | ++ | + | ++ | × | + | + | − |
| Coast battery | − (overkill, dead zone) | ++ | − (slow vs fast) | ++ (long straight line) | ++ | ++ | − |
| Searchlight (Q1 rec.) | + (slow) | + | + | + | + | + | ++ (reveals) |
| Elder Sign | + | + | ++ | + (only where the line crosses) | + | + | − |
| Necronomicon Reader | ++ | ++ | ++ | + | + | + | − |
| Tillinghast Resonator | − (overkill) | ++ | − (one target) | + | ++ (ignores armor) | ++ | + (Pure branch reveals) |
| Silver Key Gate | + | ++ | ++ | ++ | × (L1-L2, Pure) / + (Corrupted) | × | − |
| Summoning Circle | ++ (holds harassers) | + | + (holds one) | × (ghoul) / ++ (Byakhee) | − (ghoul dies fast) | − | − |

Gaps after the roster: anti-flyer on the mundane side = Rifleman, Harpooner, Battery;
anti-armor = Battery AP, Resonator, Corrupted Seal; hallucinations = Searchlight (Q1) and
Resonator Pure.

---

## 2. Numbers per tower

Placeholders for the measure slices of each task and for LT-45 (difficulty); reference DPS:
Rifleman L1 10 / 0.8 s = 12.5 DPS for $50 (0.25 DPS/$). New fields are listed in §2.3.

### 2.1 Existing towers (unchanged numbers; branch effects wired by LT-29)

| Tower | Branch a | Branch b | Fit with this roster |
|---|---|---|---|
| Rifleman | Marksman: range 5, dmg 18, 0.7 s, `crit_chance 0.2`, `crit_multiplier 2` | Militia: 2 shooters, 0.5 s, dmg 12 | **Q1 B/C:** Militia becomes "Gangsters" (`burst_targets 3`, see §2.2 LT-49); LT-29 then wires the burst instead of `shooters`. Decide before LT-29 S1. |
| Harpooner | Barbed: `bleed_dps 6`, `bleed_seconds 3` | Chain harpoon: `pull_cells 1.5` | bleed status reused by Dynamite b; pull = the "push back along the route" primitive reused by Silver Key (P5) |
| Elder Sign | Pure Ward: range 4, reserve 14 | Corrupted Seal: `strip_armor 1`, reserve 30 | strip_armor stacks with Battery AP (moot) and Resonator (moot): both ignore armor; it helps every other tower |
| Necronomicon Reader | Pure Rite: not madness_affected, reserve 22 | Corrupted Rite: dmg 150, reserve 45 | none |

### 2.2 New towers (JSON in the `towers.json` shape)

**Dynamite crew (LT-47)**, mundane, ground only, `cost 90`, glyph D.

| Level | upgrade_cost | range | damage | fire_interval | effects |
|---|---|---|---|---|---|
| L1 | — | 3.5 | 45 | 2.5 | `aoe_radius 1.0`, `fuse_seconds 1.0` |
| L2 | 70 | 4 | 60 | 2.4 | `aoe_radius 1.2`, `fuse_seconds 1.0` |
| a "Demolition man" — "Huge charge, long fuse" | 120 | 4 | 110 | 3.0 | `aoe_radius 1.5`, `fuse_seconds 1.2` |
| b "Shrapnel charges" — "Blast makes foes bleed" | 120 | 4 | 60 | 2.2 | `aoe_radius 1.3`, `fuse_seconds 1.0`, `bleed_dps 8`, `bleed_seconds 3` |

Rules: the crew throws at the point where its target will be after `fuse_seconds` at its
current speed (`distance + units_per_tick × speed_mult × fuse_ticks`, clamped to the route;
§7 Q5); the charge explodes there after the fuse and hits every live ground enemy (fakes
too) within `aoe_radius` at that tick. Enemies that slowed, sped up or got pushed back meanwhile
can be outside. A mundane miss (Fraying) is a dud: no blast, cooldown spent. Flyers are never
targeted and never hit by the blast. 18 DPS per enemy in the blast at L1: a Deep One pack
caught whole takes 72-108.

**Coast battery (LT-48)**, mundane, `cost 120`, glyph B. Hits flyers (§7 Q6).

| Level | upgrade_cost | range | min_range | damage | fire_interval | effects |
|---|---|---|---|---|---|---|
| L1 | — | 7 | 2 | 70 | 3.0 | — |
| L2 | 90 | 8 | 2 | 95 | 3.0 | — |
| a "AP shells" — "Ignores armor" | 150 | 8 | 2 | 140 | 3.2 | `ignore_armor 1` |
| b "HE shells" — "Shells splash" | 150 | 7 | 2 | 100 | 3.0 | `aoe_radius 1.0` |

Rules: enemies closer than `min_range` (cell-centre distance, strictly less) are not
candidates; instant hit as today. Vs Shoggoth: 65 per hit / 3 s = 21.7 DPS, three times a
Rifleman (5 / 0.8 = 6.25). One miss in Fraying loses 3 s of fire, so the lighthouse beam's
"no misses" is worth most here.

**Tillinghast Resonator (LT-50)**, occult, `cost 130`, glyph T. A beam: very short
`fire_interval`, small hits, armor ignored, damage scaled by sanity.

| Level | upgrade_cost | range | damage | fire_interval | sanity_reserve | effects |
|---|---|---|---|---|---|---|
| L1 | — | 3 | 3 | 0.2 | 8 | `ignore_armor 1`, `sanity_scaling 2` |
| L2 | 100 | 3.5 | 4 | 0.2 | 14 | `ignore_armor 1`, `sanity_scaling 2` |
| a Pure "Tuned Resonator" — "Steady; shows fakes" | 160 | 3.5 | 6 | 0.2 | 20 | `ignore_armor 1`, `sanity_scaling 1`, `reveal_fakes 1`; `madness_affected false` |
| b Corrupted "Open Resonator" — "Feeds on lost sanity" | 160 | 3.5 | 4.5 | 0.2 | 45 | `ignore_armor 1`, `sanity_scaling 4` |

Rules: damage per hit × `1 + sanity_scaling × (1 − sanity / sanity.max)` (§7 Q2). L1 DPS
15 at sanity 100, 24 at 70, 33 at 40, 42 at 10, 45 × madness ×2 at 0 (then astray, and
enemies take ×0.37). Corrupted at sanity 30 (cap ≤ 55 with its own reserve): 4.5 × 3.8 / 0.2
= 85 DPS. The beam keeps its target while it stays in range and live (no re-pick each 0.2 s,
so it reads as one beam); `target_priority` picks a new one. `fire_interval 0.2` = 6 ticks
exactly (`SimTime.TICK_RATE = 30`). Pure's `reveal_fakes`: a fake hit by the beam becomes
`revealed` (P8).

**Silver Key Gate (LT-51)**, occult, `cost 140`, glyph K. No damage (except Corrupted).

| Level | upgrade_cost | range | damage | fire_interval | sanity_reserve | effects |
|---|---|---|---|---|---|---|
| L1 | — | 3 | 0 | 6 | 10 | `banish_cells 4`, `banish_max_hp 500`, `banish_immune_seconds 8` |
| L2 | 110 | 3.5 | 0 | 5 | 16 | `banish_cells 5`, `banish_max_hp 500`, `banish_immune_seconds 8` |
| a Pure "Gate of Slumber" — "Banishes three at once" | 180 | 3.5 | 0 | 5 | 22 | `banish_cells 5`, `banish_targets 3`, `banish_max_hp 500`, `banish_immune_seconds 8` |
| b Corrupted "Ultimate Gate" — "Farther, hurts, any size" | 180 | 3.5 | 60 | 5 | 45 | `banish_cells 8`, `banish_max_hp 4000`, `banish_immune_seconds 8` |

Rules: every `fire_interval` the gate picks (by `target_priority`) up to `banish_targets`
(default 1) live enemies in range with `max_hp ≤ banish_max_hp` and no banish immunity, and
moves each back `banish_cells` along its own route (distance clamped at 0; flyers along their
straight line). Each gets `banish_immune_seconds` of immunity, so two gates cannot lock one
enemy. Corrupted also deals `damage` (after the move; armor applies). No candidate: no cast,
the gate stays ready. Banishing a Deep One (1.6 cells/s) 4 cells buys 2.5 s; a cultist 4 s.
Corrupted on a Shoggoth: 8 cells = 16 s more on the map, during which it regenerates 1 %/s
(~576 HP) and keeps its horror drain near towers: a real trade-off (§7 Q4).

**Summoning Circle (LT-52)**, occult, `cost 160`, glyph C. Allied units (P10).

| Level | upgrade_cost | range | fire_interval | sanity_reserve | effects |
|---|---|---|---|---|---|
| L1 | — | 2.5 | 10 | 12 | `summon_max 1`, `summon_hp 120`, `summon_dps 15`, `summon_lifetime 20`, `summon_speed 1.5` |
| L2 | 120 | 3 | 9 | 20 | `summon_max 2`, `summon_hp 150`, `summon_dps 18`, `summon_lifetime 20`, `summon_speed 1.5` |
| a Pure "Bound ghouls" — "Three sturdier ghouls" | 180 | 3 | 8 | 26 | `summon_max 3`, `summon_hp 200`, `summon_dps 20`, `summon_lifetime 20`, `summon_speed 1.5` |
| b Corrupted "Byakhee" — "Winged, hits flyers" | 180 | 4 | 10 | 45 | `summon_max 1`, `summon_hp 150`, `summon_dps 45`, `summon_lifetime 20`, `summon_speed 3`, `summon_flying 1` |

Rules: every `fire_interval`, if fewer than `summon_max` of its units live, the circle
summons one at its centre. A unit moves straight (free position, not on the route) at
`summon_speed` toward the nearest enemy it may engage within the circle's `range` + 1 (its
leash); a ghoul engages ground enemies only, a Byakhee any. On contact (≤ 0.4 cells) it
**holds** that enemy (enemy `speed_mult × 0` in slot 2; one unit holds one enemy) and both
trade damage: the unit deals `summon_dps` (armor applies per tick-hit, see P10), the enemy
deals its contact damage to the unit (§7 Q3). The unit is gone at 0 HP or after
`summon_lifetime`; it then returns to the leash/next target. Fakes are engaged like real
ones (it cannot tell). Kills credit source `summoning_circle` (occult: no sanity regen).
Ghoul (120 HP, 15 DPS) vs cultist (10 contact DPS): kills it in 4 s, survives. Vs Shoggoth
(50 contact DPS): holds it 2.4 s.

**LT-49, recommended option (§7 Q1 B): Coast Guard searchlight**, mundane support,
`cost 80`, glyph S, `damage 0`.

| Level | upgrade_cost | range | effects |
|---|---|---|---|
| L1 | — | 3 | `reveal_fakes 1`, `slow 0.2` |
| L2 | 60 | 3.5 | `reveal_fakes 1`, `slow 0.25` |
| a "Signal lamp" — "Wide reveal" | 100 | 5 | `reveal_fakes 1`, `slow 0.25` |
| b "Blinding beam" — "Slows hard, marks foes" | 100 | 3.5 | `reveal_fakes 1`, `slow 0.4`, `damage_taken_multiplier 1.2` |

Rules: an aura like Elder Sign's (same `_apply_auras` path); in addition every live fake
inside becomes `revealed` for good (P8). Revealed fakes are dropped from every tower's target
candidates, so towers stop wasting shots on them. No kills, so no sanity regen.

Rifleman branch b under Q1 B/C, "Gangsters" — "Tommy guns, 3 targets": upgrade 80, range
3, damage 7, fire_interval 0.2, `burst_targets 3` (each shot goes to the next of up to 3
targets in range, round robin). 35 DPS spread; armor 2 cuts it to 25, armor 5 to 10.

Option A (Q1), standalone "Tommy-gun gang" LT-49: cost 90, range 2.5, damage 7,
fire_interval 0.2, `burst_targets 3`; a "Drum magazine" (dmg 7, 0.15 s) / b "Chicago
typewriter" (range 3, `burst_targets 5`).
Option C (Q1), "Net thrower" LT-49: cost 70, range 3, damage 5, fire_interval 4,
`root_seconds 1.5`, `aoe_radius 0.6` (ground only); a "Weighted nets" (`root_seconds 2.5`,
`aoe_radius 1.0`) / b "Hooked nets" (`bleed_dps 6`, `bleed_seconds 3`).

### 2.3 New config fields

| Field | Where | Meaning | First task |
|---|---|---|---|
| `glyph` | tower (optional, 1 char) | board letter; default `name.left(1)` | LT-47 |
| `targets` | tower (`"all"` default, `"ground"`) | flyers are not candidates and not hit by its blasts | LT-47 |
| `fuse_seconds` | effects | delayed blast (P2) | LT-47 |
| `min_range` | level field (≥ 0, < range) | dead zone | LT-48 |
| `ignore_armor` | effects (0/1) | `apply_damage` skips armor for this hit | LT-48 |
| `sanity_scaling` | effects | §2.2 Resonator formula | LT-50 |
| `reveal_fakes` | effects (0/1) | aura (Searchlight) or hit (Resonator) reveals fakes | LT-49 or LT-50 |
| `banish_cells`, `banish_targets`, `banish_max_hp`, `banish_immune_seconds` | effects | Silver Key | LT-51 |
| `summon_max`, `summon_hp`, `summon_dps`, `summon_lifetime`, `summon_speed`, `summon_flying` | effects | Summoning Circle | LT-52 |
| `burst_targets` | effects | Gangsters / Tommy-gun (Q1) | LT-29 or LT-49 |
| `root_seconds` | effects | Net thrower (Q1 C only) | LT-49 |
| `contact_dps` | enemy (optional) | damage an enemy deals to a unit holding it; default `leak_damage × 10` (Q3) | LT-52 |

All effect keys are numeric (0/1 for flags) so they fit `Level.EFFECTS` as it is.

---

## 3. Sanity and the lighthouse beam per tower

Sanity (LT-23): occult towers only reserve the cap (`sanity_reserve`); kills by a mundane
tower with damage give `regen.mundane_kill` (+0.5); Fraying mundane shots miss 15 %;
`madness_affected` occult towers deal ×2 and shoot astray in Madness. Beam (LT-26 D2/D3,
LT-30): lit mundane `fire_interval × 0.8` and no misses; lit occult −30 % power, no sanity
effect (LT-23 Q7).

| Tower | Sanity | Madness | Lit by the beam ("power" for occult) |
|---|---|---|---|
| Rifleman, Harpooner | +0.5 per kill; miss 15 % in Fraying | unaffected | ×0.8 interval, no misses |
| Dynamite crew | +0.5 per kill, so a blast that kills 5 cultists gives +2.5: the best sanity regen in the game | unaffected | ×0.8 interval, no duds; the fuse is not shortened |
| Coast battery | +0.5 per kill | unaffected | ×0.8 interval, no misses (biggest gain: one miss = 3 s lost) |
| Searchlight (Q1 B) | no damage: no regen; reveals fakes, so it is the answer to Whispers/Fraying | unaffected | no effect (support; LT-30 modifiers apply only to firing). Accepted: the beam does not stack with a light tower. |
| Gangsters / Tommy gun (Q1) | +0.5 per kill; each bullet rolls its miss | unaffected | ×0.8 interval, no misses |
| Elder Sign, Reader | reserve (5-45) | as today | as LT-26 |
| Resonator | reserve 8/14/20/45; **reads current sanity**: low sanity = more damage. The Corrupted reserve 45 alone keeps sanity ≤ 55, i.e. ≥ ×2.8 | ×2 and astray; Pure branch not madness_affected | damage ×0.7 |
| Silver Key Gate | reserve 10/16/22/45 | astray: banishes a random real / fake in range, or nothing; Corrupted damage ×2 | `banish_cells × 0.7` (Corrupted damage ×0.7 too) |
| Summoning Circle | reserve 12/20/26/45 | units deal `summon_dps × damage_multiplier`; no astray (a unit bites what it holds) | `summon_dps × 0.7` for units of a circle lit at summon time |

---

## 4. Shared sim pieces

Assumed order: LT-29 → LT-47 → LT-48 → LT-49 → LT-50 → LT-51 → LT-52, one at a time. All of
them change `_fire_towers` (`simulation.gd:1001-1062`); in parallel they conflict there, so
**run them sequentially** (or the orchestrator rebases each on the previous one).

| # | Piece | Built by | Reused by | Notes |
|---|---|---|---|---|
| P1 | `_fire_towers` split: target candidates (`_candidates(t, s)`: range, `min_range`, `targets`, revealed fakes), hit set (`_shot_hits`), damage per hit | LT-47 (refactor first, behaviour-neutral, existing tests green) | all | keeps each later task to one new branch in the dispatch |
| P2 | Delayed blast: `SimState.blasts` (`{id, tower, at: Vector2, detonate_tick, damage, radius, ground_only, effects}`), settled in a new slot 5b after `_fire_towers`; events `SHOT {fuse: true, to, detonate_tick}` and `BLAST {hits}` | LT-47 | none in this roster (later: mortar, Dagon spit) | like `relic_tokens` (`sim_state.gd:27`): tick-scheduled, id order |
| P3 | `targets: "ground"` filter | LT-47 | LT-52 (ghoul), LT-49 C (net) | |
| P4 | `min_range` | LT-48 | — | |
| P5 | Push back along the route: `_push_back(e, cells)` sets `distance` and `prev_distance` (no render slide), clamps at 0 | LT-29 (`pull_cells`) | LT-51 | if LT-51 lands first, it builds it |
| P6 | Enemy status timers (`SimEnemy.status`, ticked in slot 2): bleed | LT-29 | LT-47 b (bleed), LT-51 (`banish_immune_ticks`), LT-49 C (`root_ticks`) | |
| P7 | `ignore_armor` in `apply_damage` (new optional parameter) | LT-48 | LT-50 | |
| P8 | Reveal fakes: set `e.revealed`; P1 drops revealed fakes from candidates | LT-49 (Q1 B) or LT-50 | LT-50 a | render already draws `revealed` |
| P9 | "Acting" towers without damage: replace `damage > 0` as "has an attack" with `TowerDef.Level.acts()` (damage > 0 or banish or summon) | LT-51 | LT-52 | five call sites, §5 "Support checks" |
| P10 | Allied units: `SimAlly` (`id, tower, pos: Vector2, hp, dps, flying, expires_tick, held_id`), `SimState.allies`; move in slot 3, hold in slot 2, trade damage in slot 5; events `ALLY_SUMMONED / ALLY_GONE`; render circle + HP bar | LT-52 | LT-32 only if its night "defence posts" fight on the path; posts that act from a cell are towers with weaker levels and need none of this | unit damage: per tick `dps × DT`, armor per tick would zero it, so armor applies once per second as `max(0, dps − armor)` |
| P11 | `glyph` field, board uses it | LT-47 | LT-49..52 | |
| P12 | Burst at N targets (`burst_targets`) | LT-29 (if Militia → Gangsters) or LT-49 (A) | — | a geometric sector is not needed; if wanted later, reuse LT-30's trig-free cone test |
| P13 | Sanity scaling | LT-50 | — | reads `state.sanity` / `config.sanity.max` |
| P14 | Beam render kind (`shot_kind` "beam": a held line while the target stays) | LT-50 | — | SHOT every 6 ticks; the board keeps one fx per tower instead of adding one per SHOT |
| P15 | Picker with 10 towers | first task where `ui/tower_picker.gd` overflows the side panel (likely LT-49/LT-50) | — | must-confirm in each task by screenshot; fix = two groups (Mundane / Occult) |

---

## 5. Edit map per task

Common to every tower task (read for context: `_fire_towers` 1001-1062, `_pick_target`
1064-1073, `apply_damage` 157-173, `TowerDef.Level.parse` `tower_def.gd:113-151`,
`board.shot_kind` `board.gd:144-153`, `tower_info._effect_text` `ui/tower_info.gd:219+`):
- `data/towers.json`: add the tower (§2.2).
- `sim/defs/tower_def.gd`: new keys in `Level.EFFECTS` (92-96); new level fields in
  `LEVEL_FIELDS` (78-79) and `Level.parse`; tower fields in `FIELDS` (5) and `parse` (22-52).
- `ui/tower_info.gd`: `EFFECT_GROUPS` (40-44) and `_effect_text` (219+) lines for the new
  keys; `_dps` (210-211) if the DPS line is wrong for the tower.
- `tools/bot_runs.gd`: `BRANCH_PICK` (52-57) and `_order` (214-231) so at least one strategy
  builds the tower (the measure slice compares with/without).
- `tests/config_valid_test.gd:16-28`: pins 4 towers and their ids; each task adds its id.
- `scenes/board.gd`: `shot_kind` (144-153), `_shot_fx` (180-218), `attack_color` (395),
  `_draw_effects` (483-503) for the new attack look.

**Support checks** (`damage <= 0` means "no attack"; P9 changes them): `has_targeting`
`simulation.gd:352-353` (→ `ui/tower_panel.gd:145-150`), `_apply_auras` 939, `_fire_towers`
1008, `board.shot_kind` 146, `ui/tower_info.gd` 76, 129, 134, 150, 192, 211.

### LT-47 Dynamite crew
- P1 refactor of `_fire_towers` (1001-1062) first, behaviour-neutral.
- `sim/defs/tower_def.gd`: `glyph`, `targets` (tower fields), `fuse_seconds`.
- `sim/core/sim_state.gd` (~27): `blasts` array; `sim/core/simulation.gd`: in `_fire_towers`
  a `fuse_seconds` level queues a blast at the predicted point (`SimRoute.position_at`,
  `sim_route.gd:33`); new `_settle_blasts()` called in `step()` (80-119) after `_fire_towers`;
  ground filter in the candidates and in the blast hits (`enemies_near` 701-713 + `def.flying`).
- `sim/core/sim_event.gd` (6-15): append `BLAST`.
- Bleed on hits (b) through LT-29's status (P6).
- `scenes/board.gd`: `_draw_tower` (408-425) uses `glyph`; a "dynamite" fx: arc to the point,
  fuse spark, blast ring on `BLAST`.
- Must confirm: `render_isolation_test` / `sim_boundary_test` accept the new state array.

### LT-48 Coast battery
- `tower_def.gd`: `min_range` level field (validate `< range`), `ignore_armor` key.
- `simulation.gd`: `min_range` in P1 candidates; `apply_damage(enemy_id, amount, source,
  ignore_armor := false)` (157-173); HE uses the existing `aoe_radius` branch.
- `ui/tower_info.gd`: "Dead zone: 2 cells" line; `scenes/board.gd`: range ring shows the dead
  zone (selected tower draw, `selected_range` 85).

### LT-49 fifth mundane (per Q1)
- B (Searchlight): `tower_def.gd` `reveal_fakes`; `_apply_auras` (935-968): aura detection
  also on `reveal_fakes`, set `e.revealed` for fakes inside; P1 candidates skip revealed fakes;
  `Simulation.debug_is_fake` untouched (render isolation, LT-12 §1). Rifleman branch b →
  Gangsters in `towers.json`, `burst_targets` in `_fire_towers` if LT-29 did not build it.
- A (Tommy-gun gang): `burst_targets` in `_fire_towers`, round-robin index in `SimTower`.
- C (Net thrower): `root_seconds` status (P6), `speed_mult = 0` in slot 2.

### LT-50 Tillinghast Resonator
- `tower_def.gd`: `sanity_scaling`, `reveal_fakes` (if not there).
- `simulation.gd` `_fire_towers`: damage × scaling factor before the madness ×2; keep the
  target (`SimTower.locked_id`, `sim_tower.gd` ~22) while live and in range; `ignore_armor`
  (P7); Pure sets `revealed` on a fake it hits (P8).
- `scenes/board.gd`: "beam" shot kind (P14); `ui/tower_info.gd`: "×1.6 at current sanity" line
  (needs the live sanity: `lines()` 74 gets it via `SanityConfig` today — add a state arg).

### LT-51 Silver Key Gate
- P9: `TowerDef.Level.acts()`; replace the support checks listed above.
- `simulation.gd` `_fire_towers`: banish dispatch → `_push_back` (P5) for up to
  `banish_targets` candidates with `max_hp ≤ banish_max_hp` and no immunity (P6 status);
  `SHOT {banish: true, hits, from, to}` per enemy; Corrupted then `apply_damage`.
- `scenes/board.gd`: enemy "folds" at the old spot and reappears (fx from SHOT `from`/`to`).
- Must confirm: `_leak` (1147) and `_check_outcome` unaffected (distance only decreases).

### LT-52 Summoning Circle
- New `sim/core/sim_ally.gd`; `sim_state.gd`: `allies`; `enemy_def.gd` (5, 31-66): optional
  `contact_dps`.
- `simulation.gd` `step()` (80-119): slot 2 `_hold_enemies()` (held → `speed_mult = 0`),
  slot 3 `_move_allies()`, slot 5 `_summon()` + `_ally_combat()`; `_compact` (1212) drops
  gone allies; kills via `apply_damage(..., "summoning_circle")`.
- `sim_event.gd`: append `ALLY_SUMMONED`, `ALLY_GONE`.
- `scenes/board.gd`: draw allies (new `_draw_allies` beside `_draw_enemies` 443).
- Ground-only engagement for ghouls via P3.

### References and how they were found
GDScript is not indexed by g-mesh; all by grep: `damage <= 0|damage > 0|has_targeting`
(support checks above), `"pierce"|"aoe_radius"` and tower ids across `sim scenes ui tools`
(only `simulation.gd`, `board.gd`, `tower_info.gd`, `bot_runs.gd` use them), `flying` (only
`spawn_enemy` and `EnemyDef`), `revealed` (only `sim_enemy.gd:16`, `board.gd:455`),
`towers.size()` in `tests/` (only `config_valid_test.gd:16,28` pin the count;
`scene_game_test.gd:95` follows config), `name.left(1)` (`board.gd:416`).

---

## 6. Behaviours each tower task pins (one line each, for its tests slice)

- Dynamite: blast lands at the predicted point after `fuse_seconds`; an enemy pushed out of the
  radius before detonation is not hit; never targets nor hits a flyer; a Fraying dud spends the
  cooldown with no blast; a lit crew never duds.
- Battery: no shot at an enemy inside `min_range` while one outside is in range; AP ignores
  armor 5 (control: remove `ignore_armor` → 135 instead of 140).
- Resonator: damage at sanity 40 is ×2.2 of L1 base; keeps its target while live; Pure reveals
  a fake it hits; lit → ×0.7.
- Silver Key: enemy distance −4 cells; immune for 8 s; Shoggoth untouched below Corrupted;
  distance never below 0.
- Summoning: summons up to `summon_max`; held enemy does not move; ghoul ignores flyers,
  Byakhee engages them; unit gone at lifetime end.
- Searchlight (Q1 B): a fake in the aura becomes revealed; no tower targets a revealed fake.

---

## 7. Open questions for the owner

### Q1. Fifth mundane tower (LT-49)

**Today:** mundane = Rifleman, Harpooner, plus Dynamite and Coast battery (chosen). Nothing in
the game reveals fakes (the GDD's Searchlight was never built), and the mundane side has no
crowd control. Owner idea: "Возможно гангстеры - будут апгрейдом стрелков".
**Change:** pick the fifth.
**Example:** wave 5 in Fraying: a fake spawns every 6 s and every tower shoots fakes as much
as real enemies.
- **B. Gangsters replace Militia as Rifleman branch b; 5th = Coast Guard searchlight
  (Recommended).** + The only answer to hallucinations, no sanity cost, fits the coast theme;
  Gangsters (3-target bursts) do what Militia did, with more character. − A support tower
  deals no damage (no kill regen); a second "light" next to the lighthouse beam; LT-29 must
  wire `burst_targets` instead of `shooters` (decide before LT-29 S1).
- **A. Tommy-gun gang as a standalone 5th tower.** + Strong vs packs, flavourful; Rifleman
  keeps Militia. − Overlaps Dynamite and Harpooner (both anti-pack); still no fake counter.
- **C. Gangsters replace Militia; 5th = Net thrower (roots ground enemies).** + Mundane crowd
  control without sanity; reuses statuses. − Overlaps Elder Sign's slow; still no fake
  counter outside the Resonator's Pure branch.

### Q2. Which sanity the Resonator reads

**Today:** thresholds are on the full bar (LT-23 Q2); occult reserves lower the cap.
**Change:** the Resonator's damage grows as sanity falls; which number?
**Example:** cap 60 (reserves 40), sanity 60.
- **Current sanity on the full bar (Recommended):** ×1.8 (scaling 2). + Same scale as the
  thresholds the player sees; reserves of other occult towers feed it (occult synergy).
  − Building occult towers alone raises its damage, so the occult player gets it "for free".
- **Fraction of the cap:** 60/60 = full → ×1.0. + Only real losses (horror, fakes) count.
  − Hard to read: the same bar position gives different damage.
- **Threshold steps** (Lucid ×1, Whispers ×1.5, Fraying ×2.5, Madness ×3). + Easiest to read.
  − Jumps at 70/40; no reward for small losses.

### Q3. Summoned units: how they fight

**Today:** enemies have no attack; nothing in the sim can damage a unit.
**Change:** ghouls hold enemies; something must end the hold.
**Example:** a ghoul grabs a Shoggoth.
- **HP + enemy contact damage = `leak_damage × 10`, optional `contact_dps` per enemy
  (Recommended).** Ghoul holds a Shoggoth 2.4 s, a cultist dies first. + Big enemies break
  through, no new data needed. − A new damage path (units take damage) to test.
- **Lifetime only, no HP.** Ghoul holds anything for its 20 s. + Simplest. − A $160 circle
  stops a Shoggoth for 20 s every 10 s: degenerate vs bosses.
- **HP + explicit `contact_dps` required for every enemy.** + Full control. − Five new numbers
  to balance now, more with Dagon.

### Q4. Banish limits on big enemies

**Today:** no tower moves enemies backwards (LT-29's pull will, 1.5 cells).
**Change:** Silver Key moves an enemy 4-8 cells back.
**Example:** a Shoggoth 5 cells from the lighthouse.
- **HP cap per level: L1/L2/Pure ≤ 500, Corrupted ≤ 4000, Dagon never (Recommended).**
  + Shoggoth is a Corrupted-only target, with the regen/horror trade-off. − A number the
  player must learn (shown in the info panel).
- **Anyone, same distance.** + Simple. − Two gates loop a Shoggoth with immunity 8 s.
- **Anyone, distance ÷ (max_hp / 500).** + Smooth. − Hard to read.

### Q5. Dynamite aim

**Today:** every attack is instant.
**Change:** the charge explodes after 1 s.
**Example:** a Deep One at 1.6 cells/s moves 1.6 cells during the fuse; blast radius 1.0.
- **Aim where the target will be after the fuse (Recommended).** + Hits steady walkers; a
  slow (Elder Sign) or a pull in the meantime makes it miss: a readable interplay. − Fast
  enemies still dodge when slowed after the throw.
- **Aim at its current position.** + Simple, "dumb crew" flavour. − Misses every Deep One:
  the tower fails at its own niche (packs).

### Q6. Coast battery vs flyers

**Today:** every tower hits flyers.
**Change:** a naval gun could be ground/sea only.
**Example:** wave 4 has 16 Night-gaunts flying the straight line S → L.
- **Hits flyers (Recommended).** + The long straight line suits its 7-8 range; mundane anti-
  flyer beyond Rifleman/Harpooner. − Dynamite is the only ground-only tower.
- **Ground only.** + Two ground-only towers, flyers matter more. − Mundane players have weak
  answers to wave 4.
