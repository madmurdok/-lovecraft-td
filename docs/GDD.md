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

Two phases (LT-27): **day** = build, **night** = wave.

1. Day (40 s): sell the relics found last night for money; place/upgrade/sell towers on
   free grid cells next to the path. "Light the lamp" ends the day early and makes
   valuable drops likelier that night (§8).
2. Night: the lighthouse burns, enemies walk the path, towers fire, sanity changes. Kills
   drop relics: a token falls at the kill and flies to the HUD stash in ~2 s. Building,
   selling and upgrading wait for the day; the madness buyout works at night too.
3. Dawn: tokens still in flight reach the stash, fakes dissolve, the dawn wage is paid,
   sanity regen, back to day.
4. Win: survive the last night. Lose: lighthouse HP reaches 0.

## 5. Resources

### 5.1 Money and relics (defaults)

Two resources tied to the two phases (LT-27). **Relics** drop at night and cannot be spent;
by day they are sold for **money** (shown as "$", 1920s New England dollars; `gold` in code
and data). Money buys towers, upgrades, lighthouse levels and the madness buyout.

| Parameter | Value |
|---|---|
| Starting money | $200, no relics |
| Dawn wage (wave completion) | 50 + 10 × wave number |
| Kill | one relic drop per enemy, see the tables below and §7; no money |
| Sell relics | by day, one button, the whole stash at fixed prices |
| Sell tower refund | 70% of total spent, by day only |
| Early night ("Light the lamp") | luck, no money (§8) |

Relic kinds (`economy.json` `relics`):

| Kind | Price | Lore |
|---|---|---|
| Bone fragment | $5 | Neither man nor fish |
| Amber | $15 | Hardened deep-sea resin with something inside |
| Idol fragment | $50 | A shard of a green soapstone idol |
| Star-stone of Mnar | $200 | The rarest find; the five-pointed grey stone, 0.1 % per drop |

Each kill rolls one kind from the enemy's integer weights (`enemies.json` `drops`, shares
of 1000):

| Enemy | bone | amber | idol | star-stone | Mean |
|---|---|---|---|---|---|
| Cultist of Dagon | 999 | 0 | 0 | 1 | $5.2 |
| Deep One | 749 | 250 | 0 | 1 | $7.7 |
| Innsmouth Hybrid | 699 | 250 | 50 | 1 | $9.9 |
| Night-gaunt | 399 | 500 | 100 | 1 | $14.7 |
| Shoggoth | 0 | 0 | 999 | 1 | $50.2 |

- **Luck**: lighting the lamp with s whole seconds left on the day timer sets the night's
  luck to 1 + 0.02 × s (up to ×1.8 at 40 s). It multiplies the weight of every kind except
  the cheapest kind in each enemy's table; dawn resets it to ×1. Example: a hybrid at luck
  ×1.6 drops amber 400, idol 80, star-stone 1.6 against bone 699 (mean $9.9 → $11.7).
- **Tokens**: the stash is credited when a token lands (`token_fly_seconds` 2 s). A fake
  enemy's token dissolves in flight (`ghost_vanish_seconds` 1 s) and credits nothing.

### 5.2 Lighthouse

- HP 20. An enemy that reaches it deals its `leak_damage` (§7) and disappears.

### 5.3 Sanity

Global pool, 0..100, starts at 100.

**Reserve (LT-23)**
- Every occult tower on the board lowers the sanity **cap** by its level's
  `sanity_reserve` (Elder Sign 5 / 8 / Pure Ward 10 / Corrupted Seal 15; Necronomicon
  Reader 10 / 15 / Pure Rite 18 / Corrupted Rite 25; tunable). Cap = 100 − reserves,
  floored at 0.
- Current sanity drops only when it is above the new cap (then to the cap); selling
  raises the cap again and leaves current sanity alone (in Madness too).
- A cap of 0 empties sanity and so starts Madness. Thresholds stay on the full bar: a
  reserve above 30 means no Lucid until those towers are sold.
- Occult towers have no build, upgrade, per-cast or per-second sanity cost.

**Drains**
- Horror: a large enemy (shoggoth, Dagon) within 3 cells of any tower drains
  `horror_drain` per second while visible (shoggoth 0.5/s, Dagon 0.6/s).

**Regen**
- Between waves: +12.
- Kill by a mundane damage tower (rifleman, harpooner): +0.5.
- Up to the cap (100 minus reserves).

**Thresholds**

| Sanity | State | Effect |
|---|---|---|
| 100–70 | Lucid | none |
| 69–40 | Whispers | audio whispers, UI jitter; fake enemies spawn at 1 per 15 s |
| 39–1 | Fraying | fake enemies 1 per 6 s; mundane towers miss 15% of shots; phantom path flickers on screen |
| 0 | Madness | see §5.4 |

**Hallucinations affect gameplay.** A fake enemy looks exactly like a real one
(type picked from the current wave), walks the path, draws tower fire and has HP,
but deals no leak damage and credits no relic (its token melts in flight). The player cannot tell which is which.

- A fake has the same HP as a real enemy of its type.
- Fakes spawn only during a wave, never in the build phase.
- A wave ends when its real enemies are gone; all remaining fakes dissolve at that moment.

### 5.4 Madness

- Triggered when sanity hits 0.
- Occult towers deal ×2 damage, but each shot goes astray: 40% hit a random real
  enemy in range, 35% hit a fake enemy, 25% hit an empty cell. Net output ≈ ×0.8,
  spread unpredictably, so crashing sanity on purpose costs damage. No friendly fire. Ratios live in `sanity.json` (`madness.shot_split`).
- Fraying effects stay at maximum.
- The world turns hostile (LT-23): every enemy, real and fake, moves ×1.2 and takes
  ×0.8 damage while in Madness (`madness.enemy_speed_multiplier`,
  `enemy_damage_taken_multiplier`); on top of Elder Sign auras; gone the tick after
  Madness ends.
- Duration: until the end of the game (default).
- Exit rule is a config switch for rebalancing:
  - `permanent` (default): no exit.
  - `buyout`: spend money to restore sanity to min(30, cap) (cost $150), any phase, night
    included; refused at cap 0.
  - `auto_restore`: after the current wave ends, sanity resets to min(30, cap).

## 6. Towers

Placement: any free buildable grid cell. Path cells and water are not buildable.
Upgrades: L1 → L2 (stat bump) → L3 with a choice of two branches.
Mundane towers' L3 branches are "specialisations"; occult towers' L3 branches are
"pure" (safe) vs "corrupted" (stronger, reserves more sanity).

| Tower | Kind | Cost | Role | L3 branch A | L3 branch B |
|---|---|---|---|---|---|
| Rifleman | mundane | 50 | single target, steady DPS | Marksman: long range, crits | Militia: two shooters, faster fire |
| Harpooner | mundane | 70 | piercing line shot, good vs packs | Barbed: bleed DoT | Chain harpoon: pulls target back along the path |
| Searchlight | mundane | 80 | beam that slows 40%, no damage | Blinding: stuns 1 s every 6 s | Revealing: fake enemies in the beam are shown as fake |
| Elder Sign | occult | 100, reserves 5 | aura: −35% speed, +50% damage taken | Pure Ward: larger aura | Corrupted Seal: enemies inside lose armor, reserves 15 |
| Necronomicon Reader | occult | 150, reserves 10 | AoE blast every 3 s | Pure Rite: slower, unaffected by madness (no ×2, no astray shots) | Corrupted Rite: ×1.5 damage, reserves 25 |

Note: the Revealing branch is the only counter to hallucinations in the MVP, and it is gated behind L3.

Exact damage/range/rate per level live in `data/towers.json`.

Towers have no HP in the MVP: enemy effects only disable or slow
a tower for a few seconds. Keep the tower model open for adding HP, destruction and
repair later (a `disable` effect today, a `damage` effect later).

## 7. Enemies

| Enemy | HP | Speed | Armor | Leak dmg | Drops | Trait |
|---|---|---|---|---|---|---|
| Cultist of Dagon | 60 | 1.0 | 0 | 1 | bone | Stops at an adjacent tower for 2 s and halves its fire rate for 5 s |
| Innsmouth Hybrid | 140 | 0.9 | 2 | 1 | bone, amber, idol | Armored mid-tier walker |
| Deep One | 90 | 1.6 | 0 | 1 | bone, amber | Spawns in packs of 4–6 |
| Night-gaunt | 110 | 1.3 | 0 | 2 | amber, bone, idol | Flies straight to the lighthouse ignoring the path; from wave 6 on it may lift a tower and drop it 2 cells away (disabled 3 s) |
| Shoggoth | 900 | 0.5 | 5 | 5 | idol | Horror drain 0.5/s; regenerates 1% HP/s |
| Dagon (boss) | 6000 | 0.4 | 8 | 20 | — | Horror drain 0.6/s; every 15 s summons 3 Deep Ones; leaking = instant loss |

Speed is in cells per second. Armor is flat damage reduction per hit. Drops: the likely
relic kinds, most likely first (weights in §5.1); every enemy also has the 0.1 %
star-stone.

## 8. Waves (default plan)

| Wave | Content |
|---|---|
| 1 | 12 cultists |
| 2 | 12 cultists, 2 packs of Deep Ones |
| 3 | 6 packs of Deep Ones, 12 hybrids |
| 4 | 20 hybrids, 16 night-gaunts |
| 5 | 1 shoggoth + escort: 29 cultists, 11 hybrids, 4 packs of Deep Ones, 6 night-gaunts |
| 6 | 3 packs of Deep Ones, 5 night-gaunts |
| 7 | 2 shoggoths, 8 hybrids |
| 8 | mixed: everything except Dagon, dense |
| 9 | 3 shoggoths, 6 night-gaunts, 3 packs |
| 10 | Dagon + periodic summons |

Waves 1–5 are the MVP's `data/waves.json` (spawn intervals and delays live there, tuned in
LT-15); waves 6–10 are the post-MVP plan.

- Day (build phase) between nights: 40 s timer (`waves.json` `build_phase_seconds`), or
  end it early with "Light the lamp" for that night's luck (1 + 0.02 × whole seconds
  left, §5.1); no money bonus.
- Game speed: ×1 / ×2, plus pause (every day action is allowed while paused).

## 9. Controls and UI

- Mouse: click a buildable cell → tower picker; click a tower → upgrade / branch / sell.
- HUD: money (`Money: $240`), relics (`Relics: 12 (≈ $96)`, per-kind tooltip), lighthouse
  HP, wave counter, phase (`Day 3 — night falls in 31 s` / `Night 3 of 5` / `Dawn. All
  nights survived`), `Light the lamp (luck ×1.6)` (day only), `Sell relics (+$96)` (day,
  non-empty stash), `Luck ×1.6` at night while luck > 1, sanity bar with threshold marks,
  speed toggle, pause.
- Day and night read at a glance: grey daylight with the lamp dark by day, darkness with
  the beam and tower lights at night (a short fade between them). Relic tokens pop at
  the kill and fly to the relic counter; a fake's token melts in flight.
- Side panel: costs as `Rifleman — $50`; refusals `not enough money`, `only by day`;
  `Sell (+$35)` by day. End screen: relics left unsold, and star-stones found.
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
  towers.json     # per tower: kind, cost, levels[1..2] (sanity_reserve), branches{a,b}
  enemies.json    # per enemy: hp, speed, armor, leak_damage, drops (relic weights), traits
  waves.json      # per wave: spawn groups with type, count, interval, delay
  sanity.json     # thresholds, drains, regen, hallucination rates, madness.exit_rule
  economy.json    # starting money, dawn wage, sell ratio, relics, token timings, night luck
  map.json        # grid rows (. buildable, # path, ~ water, S start, L lighthouse); path derived S -> L
```

## 11. Risks

- **Hallucinations can feel unfair.** Losing to something the player could not
  tell apart. Mitigation: fake enemies never leak, Revealing searchlight exists,
  whispers telegraph the threshold. Validate in the first playtest.
  Fakes do not drain sanity (no horror spiral), so an attentive player may notice a
  shoggoth that does not drain: accepted trade-off. Bosses are never picked as fakes.
- **Madness as a deliberate strategy.** ×2 occult damage may make crashing sanity
  on purpose optimal. Mitigation: astray shots cut the net output to ≈ ×0.8 (a loss, not a gain), plus permanent default; tune `madness.shot_split`.
- **Permanent madness may make the rest of the run a lottery.** That is why the exit rule is switchable.
- **Scope creep.** L3 branches double tower content; keep branch effects to one
  stat or flag each.

## 12. Milestones

1. Grey-box: grid, path, waves, 2 mundane towers, money, lighthouse HP. Is the base loop fun?
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

- **Lighthouse beam as a game rule** (playtest 0.1 finding 8, design task LT-26, decided
  2026-10-31). Today the beam is only a picture. Decided in
  `docs/design/LT-26-lighthouse-beam.md`: the beam lives in the sim and keeps rotating; the
  lighthouse is upgradeable and its levels add beams 1 → 2 → 4. Lit mundane towers fire 25 %
  faster and never miss; lit occult towers lose 30 % power but drain half (LT-23); lit enemies
  lose the Madness buff (LT-23). Lamp oil stays a later beam resource.
