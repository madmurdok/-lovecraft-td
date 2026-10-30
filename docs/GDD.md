# Lovecraft TD — Game Design Document (MVP)

Status: draft for review · 2026-10-29

## 1. Pitch

One night in Innsmouth. Things climb out of the sea and walk the streets toward the
lighthouse. The player holds the line until dawn. The Old Ones cannot be killed,
only delayed. Power comes from forbidden knowledge, and knowledge costs the mind.

## 2. Platform and tech

- Engine: Godot 4 (GDScript), 2D.
- Targets: desktop first; HTML5 (web) export for quick playtests by link.
- Simulation (waves, enemies, towers, sanity, economy) is separate from rendering:
  plain scripts with no scene dependencies, driven by a fixed tick. Scenes only display state.
- All balance numbers live in JSON configs under `data/` (towers, enemies, waves, sanity, economy).
  No balance constant in code.

## 3. MVP scope

- 1 map: Innsmouth harbor, one fixed enemy path from the docks to the lighthouse.
  Grid 24×14 cells, path ~40 cells, ~120 buildable cells.
- 10 waves, wave 10 = boss Dagon.
- 5 towers, each with 3 levels and a branch at level 3.
- 6 enemy types (5 + boss).
- Sanity system with hallucinations and madness mode.
- Placeholder art (art style decided after the prototype; not pixel art, not engraving).
- Out of scope: campaign, story screens, saves, multiple maps, localization, mobile controls.

## 4. Core loop

1. Build phase: place/upgrade/sell towers on free grid cells next to the path.
2. Wave phase: enemies walk the path; towers fire; sanity changes.
3. Between waves: income + sanity regen, back to build.
4. Win: survive wave 10 (dawn). Lose: lighthouse HP reaches 0.

## 5. Resources

### 5.1 Gold (defaults)

| Parameter | Value |
|---|---|
| Starting gold | 200 |
| Wave completion bonus | 50 + 10 × wave number |
| Kill reward | per enemy, see §7 |
| Sell refund | 70% of total spent |
| Early wave call | bonus gold = 2 × seconds left on the build timer |

### 5.2 Lighthouse

- HP 20. An enemy that reaches it deals its `leak_damage` (§7) and disappears.

### 5.3 Sanity

Global pool, 0..100, starts at 100.

**Drains**
- Building an Elder Sign: −8 (one-off, per level).
- Each Necronomicon cast: −2.
- Horror: a large enemy (shoggoth, Dagon) within 3 cells of any tower drains
  `horror_drain` per second while visible (shoggoth 0.5/s, Dagon 0.6/s).
- Corrupted level-3 branches add their own costs (§6).

**Regen**
- Between waves: +12.
- Kill by a mundane damage tower (rifleman, harpooner): +0.5.
- Cap 100.

**Thresholds**

| Sanity | State | Effect |
|---|---|---|
| 100–70 | Lucid | none |
| 69–40 | Whispers | audio whispers, UI jitter; fake enemies spawn at 1 per 15 s |
| 39–1 | Fraying | fake enemies 1 per 6 s; mundane towers miss 15% of shots; phantom path flickers on screen |
| 0 | Madness | see §5.4 |

**Hallucinations affect gameplay.** A fake enemy looks exactly like a real one
(type picked from the current wave), walks the path, draws tower fire and has HP,
but deals no leak damage and gives no reward. The player cannot tell which is which.

- A fake has the same HP as a real enemy of its type.
- Fakes spawn only during a wave, never in the build phase.
- A wave ends when its real enemies are gone; all remaining fakes dissolve at that moment.

### 5.4 Madness

- Triggered when sanity hits 0.
- Occult towers deal ×2 damage, but each shot goes astray: 60% hit a random real
  enemy in range, 25% hit a fake enemy, 15% hit an empty cell. Net output ≈ ×1.2,
  spread unpredictably. No friendly fire. Ratios live in `sanity.json` (`madness.shot_split`).
- Fraying effects stay at maximum.
- Duration: until the end of the game (default).
- Exit rule is a config switch for rebalancing:
  - `permanent` (default): no exit.
  - `buyout`: spend gold to restore sanity to 30 (cost 150).
  - `auto_restore`: after the current wave ends, sanity resets to 30.

## 6. Towers

Placement: any free buildable grid cell. Path cells and water are not buildable.
Upgrades: L1 → L2 (stat bump) → L3 with a choice of two branches.
Mundane towers' L3 branches are "specialisations"; occult towers' L3 branches are
"pure" (safe) vs "corrupted" (stronger, costs sanity).

| Tower | Kind | Cost | Role | L3 branch A | L3 branch B |
|---|---|---|---|---|---|
| Rifleman | mundane | 50 | single target, steady DPS | Marksman: long range, crits | Militia: two shooters, faster fire |
| Harpooner | mundane | 70 | piercing line shot, good vs packs | Barbed: bleed DoT | Chain harpoon: pulls target back along the path |
| Searchlight | mundane | 80 | beam that slows 40%, no damage | Blinding: stuns 1 s every 6 s | Revealing: fake enemies in the beam are shown as fake |
| Elder Sign | occult | 100 + 8 sanity | aura: −30% speed, +25% damage taken | Pure Ward: larger aura | Corrupted Seal: enemies inside lose armor, −0.2 sanity/s while active |
| Necronomicon Reader | occult | 150 | AoE blast every 4 s, −2 sanity per cast | Pure Rite: slower, unaffected by madness (no ×2, no astray shots) | Corrupted Rite: ×1.5 damage, −4 sanity per cast |

Note: the Revealing branch is the only counter to hallucinations in the MVP, and it is gated behind L3.

Exact damage/range/rate per level live in `data/towers.json`.

Towers have no HP in the MVP: enemy effects only disable or slow
a tower for a few seconds. Keep the tower model open for adding HP, destruction and
repair later (a `disable` effect today, a `damage` effect later).

## 7. Enemies

| Enemy | HP | Speed | Armor | Leak dmg | Reward | Trait |
|---|---|---|---|---|---|---|
| Cultist of Dagon | 60 | 1.0 | 0 | 1 | 5 | Stops at an adjacent tower for 2 s and halves its fire rate for 5 s |
| Innsmouth Hybrid | 140 | 0.9 | 2 | 1 | 10 | Armored mid-tier walker |
| Deep One | 90 | 1.6 | 0 | 1 | 8 | Spawns in packs of 4–6 |
| Night-gaunt | 110 | 1.3 | 0 | 2 | 15 | Flies straight to the lighthouse ignoring the path; from wave 6 on it may lift a tower and drop it 2 cells away (disabled 3 s) |
| Shoggoth | 900 | 0.5 | 5 | 5 | 60 | Horror drain 0.5/s; regenerates 1% HP/s |
| Dagon (boss) | 6000 | 0.4 | 8 | 20 | — | Horror drain 0.6/s; every 15 s summons 3 Deep Ones; leaking = instant loss |

Speed is in cells per second. Armor is flat damage reduction per hit.

## 8. Waves (default plan)

| Wave | Content |
|---|---|
| 1 | 8 cultists |
| 2 | 10 cultists, 1 pack of Deep Ones |
| 3 | 2 packs of Deep Ones, 4 hybrids |
| 4 | 6 hybrids, 3 night-gaunts |
| 5 | 1 shoggoth + escort of cultists |
| 6 | 3 packs of Deep Ones, 5 night-gaunts |
| 7 | 2 shoggoths, 8 hybrids |
| 8 | mixed: everything except Dagon, dense |
| 9 | 3 shoggoths, 6 night-gaunts, 3 packs |
| 10 | Dagon + periodic summons |

- Build phase between waves: 25 s timer, or start early with the "call wave" button for the bonus.
- Game speed: ×1 / ×2, plus pause (building is allowed while paused).

## 9. Controls and UI

- Mouse: click a buildable cell → tower picker; click a tower → upgrade / branch / sell.
- HUD: gold, lighthouse HP, sanity bar with threshold marks, wave counter, call-wave button, speed toggle.
- Sanity effects show up in the HUD too: jitter at Whispers, a distorted sanity bar while Fraying.

## 9a. Art pipeline

Most of the horror comes from light and shaders, not from sprite detail, so that
layer is built from milestone 1 on, independent of the final art:

- Godot 2D lighting: darkness outside light sources, the lighthouse beam, tower lights.
- Shaders: sea fog, screen distortion / chromatic aberration / vignette driven by sanity,
  flicker on all enemies while Fraying (never only on fakes: that would reveal them), UI jitter.

Assets needed for the MVP:

| Group | Count |
|---|---|
| Map | 1 hand-painted harbor background (fixed path, no tileset) + buildable-cell overlay |
| Towers | 5 × 4 looks (L1, L2, L3a, L3b) = 20 sprites |
| Enemies | 6, each with walk + death animation |
| UI | ~20 icons, HUD frame, sanity bar |
| VFX | shots, harpoon, AoE rite, Elder Sign aura, fake dissolve |

- Animation: cutout (parts + Skeleton2D) by default, so walk/death cycles do not need
  frame-by-frame drawing and work with any art source.
- Milestones 1–3 use vector/procedural placeholders with the final silhouettes' sizes.
- Art source (AI generation + cleanup, freelance artist, asset packs) is decided at the
  style test. AI-generated content must be disclosed on Steam.
- Already excluded: pixel art, 1920s engraving.

### Candidate styles

| # | Style | Why it fits | Risk |
|---|---|---|---|
| 1 | Silhouettes with glowing accents ("shadow theatre"): black shapes, light only from eyes, lanterns, runes, the lighthouse beam | Works with the darkness/light layer for free; cheap to draw; a fake enemy is easy to make indistinguishable; reads well at ×2 | Units of the same size can blur together; needs strong outline shapes per enemy |
| 2 | Textured dark gouache painting: muted palette, visible brush strokes | Rich atmosphere; suits a hand-painted harbor background | Most drawing work per sprite; detail may turn to mud under fog and distortion |
| 3 | Stylised 3D pre-render (Blender → sprites) | Consistent lighting and angles; animations re-rendered cheaply | Needs 3D skills; can look generic or "plasticky" without a strong shader pass |
| 4 | Hybrid: painted background (2) with silhouette units (1) | Atmosphere from the map, readability from the units | Two styles must agree in value range and edge softness |

Current favourite: 1 (or 4). Not a decision; the style test decides.

### Tools

- Krita (painterly, default); Inkscape or Affinity for vector work; Procreate if an iPad is used.
- Godot Skeleton2D for cutout animation: draw each unit as separate parts (head, torso, limbs).
- Laigter to generate normal maps, so sprites react to 2D lights.

### Style test (before milestone 4)

- Per style: one Deep One (walk + death), one rifleman tower (L1) and a lighthouse
  map fragment.
- Shown in the running game, not as stills: real fog, 2D lighting and sanity shaders.
- Judged in three sanity states (Lucid, Fraying, Madness) and at game speed ×1 and ×2.
- Criteria: enemy type readable at a glance; real and fake enemies identical;
  the tower stands out from the background; the mood holds under the shaders;
  the cost of producing the full asset list (§9a table).
- Outcome: the owner picks one style and the art source; record both here.

## 10. Data layout (proposal)

```
data/
  towers.json     # per tower: kind, cost, sanity_cost, levels[1..3], branches{a,b}
  enemies.json    # per enemy: hp, speed, armor, leak_damage, reward, traits
  waves.json      # per wave: spawn groups with type, count, interval, delay
  sanity.json     # thresholds, drains, regen, hallucination rates, madness.exit_rule
  economy.json    # starting gold, wave bonus, sell ratio, early-call bonus
  map.json        # grid rows (. buildable, # path, ~ water, S start, L lighthouse); path derived S -> L
```

## 11. Risks

- **Hallucinations can feel unfair.** Losing to something the player could not
  tell apart. Mitigation: fake enemies never leak, Revealing searchlight exists,
  whispers telegraph the threshold. Validate in the first playtest.
  Fakes do not drain sanity (no horror spiral), so an attentive player may notice a
  shoggoth that does not drain: accepted trade-off. Bosses are never picked as fakes.
- **Madness as a deliberate strategy.** ×2 occult damage may make crashing sanity
  on purpose optimal. Mitigation: astray shots cut the net gain to ≈ ×1.2, plus permanent default; tune `madness.shot_split`.
- **Permanent madness may make the rest of the run a lottery.** That is why the exit rule is switchable.
- **Scope creep.** L3 branches double tower content; keep branch effects to one
  stat or flag each.

## 12. Milestones

1. Grey-box: grid, path, waves, 2 mundane towers, gold, lighthouse HP. Is the base loop fun?
2. Sanity: pool, occult towers, thresholds, fake enemies, madness. Does it add tension?
3. Content: all towers/enemies/upgrades/branches, 10 waves, Dagon.
4. Presentation: style test (§9a) and final art, audio, HUD polish, web export.

## Topics for further discussion (auto-analysis)

All findings from the 2026-10-29 pass were resolved in the body of the document.

- **Night-gaunt spawn point.** Flyers start at the path entry `S` for now (LT-4 design,
  owner decision 2026-10-29). Check a separate `F` spawn cell on the map (approach from
  the sea) when flyers arrive with the Content milestone.

- **Map v2: islands and a changing path** (owner idea 2026-10-30, design task LT-18,
  after the LT-15 playtest). Replace the square grid with one fixed path by:
  - Cells: hexes (equal neighbour distance, fairer range circles) or an organic
    Voronoi-like layout; likely a hex/graph logic grid with Voronoi only as the look.
  - Buildable "islands" with the enemy path running between them; the next path is
    shown in advance (build phase) and changes from wave to wave.
  - A seeded, deterministic generator that guarantees chokepoints: every path segment
    must pass a metric (e.g. enough buildable cells within tower range of a point on
    it); layouts that fail are rejected and regenerated.
  - Open: path-change rule that does not punish earlier placement (free sell on change,
    partial shifts only); impact on route distance, range and placement in the sim;
    conflict with the hand-painted harbor background (§9a).
