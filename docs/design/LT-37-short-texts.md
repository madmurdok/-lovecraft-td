# LT-37 S1 copy design (read-only analysis)

## Char budget
- Panel width: viewport 1152x648 (project.godot, canvas_items, keep aspect). Board = 24 cells x 40 px = 960 (data/map.json, Board.CELL, BOARD_ORIGIN.x=0), so panel = 1152-960 = 192 base px. 1280x720 is exactly x1.111, so layout and wrapping are identical to base units.
- Content width = 192 - 2*MARGIN(8) = 176 px, minus a vertical scrollbar if one appears (~8-12 px; horizontal scroll disabled) -> ~165-176 px.
- Font: SidePanel.FONT_SIZE = 14, default Godot font, mixed-case English averages ~6.5-7 px/char at 14 px (ESTIMATE, not measured in a render).
- => about 25 chars per line (24 with scrollbar). **Budget: <= 24 chars per role line** (one visual line). Labels and buttons autowrap (AUTOWRAP_WORD_SMART), so overflow wraps rather than clips, but then it is no longer one line.
- Current roles are 11-52 chars (limit in code ROLE_MAX_CHARS=60), i.e. up to 3 wrapped lines each.
- Button text "Name -- $cost" already fits except Necronomicon Reader (28) and Corrupted Seal/Rite (22-23 ok); with " (not enough money)" or " (drives you mad!)" suffix it always wraps - left unchanged (state, not description).
- Recommend verifying the 24 budget by a render at 1280x720 in the code/verify slice (torpeek rule: verify by render).

## Where text is composed
- JSON: only `role` (tower: data/towers.json, branch: branches.x.role). Shown by: tower_picker.gd _ready (Info_<id> line 1, then TowerInfo.lines L1); tower_panel.gd refresh (role_label = def.role at L1/L2, branch role at L3) and _refresh_upgrade (upgrade_infos[b]: branch role line 1, then TowerInfo.delta_lines). No `description` field exists (FIELDS = name, role, kind, cost, levels, branches).
- Code (ui/tower_info.gd): _effect_text (per-effect sentences), _damage_text, kind_lines ("In madness...", "May miss while Fraying", "Kills restore"), lines ("Support (no damage)", "Aura radius", "Reserves N sanity"), delta_lines, REMOVED "Loses: ", COMING_SOON. These are the long sentences after the role; "descriptions" in the owner's sense include them.

## Tier A - roles (data/towers.json only; tests only need value-agnostic checks)
| where shown | current | proposed | chars (cur -> new) |
|---|---|---|---|
| Rifleman (tower): tower_picker Info_rifleman line 1; tower_panel Role L1/L2 | Single target, steady damage | Steady single target | 28 -> 20 |
| Marksman (a): upgrade_infos[a] line 1; Role at L3 | Long range and critical hits | Long range, crits | 28 -> 17 |
| Militia (b): upgrade_infos[b] line 1; Role at L3 | Two shooters, faster fire | 2 shooters, faster fire | 25 -> 23 |
| Harpooner (tower): picker; Role L1/L2 | Piercing line shot, good against packs | Pierces a line of foes | 38 -> 22 |
| Barbed (a): upgrade; Role L3 | Harpoons make enemies bleed | Enemies bleed | 27 -> 13 |
| Chain harpoon (b): upgrade; Role L3 | Pulls the target back along the path | Pulls target back | 36 -> 17 |
| Elder Sign (tower): picker; Role L1/L2 | Aura: slows enemies and makes them take more damage | Aura: slows and exposes | 51 -> 23 |
| Pure Ward (a): upgrade; Role L3 | Larger aura | Larger aura | 11 -> 11 |
| Corrupted Seal (b): upgrade; Role L3 | Enemies inside lose armor; reserves more sanity | Strips armor; +reserve | 47 -> 22 |
| Necronomicon Reader (tower): picker; Role L1/L2 | Area blast; reserves sanity while it stands | Area blast, uses sanity | 43 -> 23 |
| Pure Rite (a): upgrade; Role L3 | Slower, but unaffected by madness | Slower; ignores madness | 33 -> 23 |
| Corrupted Rite (b): upgrade; Role L3 | Stronger blasts, more sanity reserved | Bigger hits, +reserve | 37 -> 21 |

Tier A changes 11 of 12 texts (Pure Ward unchanged). All <= 24 chars.

## Tier B - composed effect/kind lines (ui/tower_info.gd; numbers kept, tests/tower_info_test.gd expectations must change)
Without this tier the panel still shows 40-55-char sentences after the short role, so "one short line" is only met for the role. Recommended, owner to decide (see open questions).
| key | current | proposed | chars |
|---|---|---|---|
| pierce (Rifleman n/a; Harpooner all levels) | Line shot: hits every enemy on a 1-cell-wide line | Pierce: 1-cell-wide line | 49 -> 24 |
| aoe_radius (Necronomicon) | Blast: hits all enemies within 1.5 cells of the target | Blast radius 1.5 cells | 54 -> 22 |
| slow (Elder Sign) | Slows enemies inside by 35% | Slows enemies 35% | 27 -> 17 |
| damage_taken_multiplier | Enemies inside take +50% damage | Foes take +50% damage | 31 -> 21 |
| crit (Marksman) | 20% chance to deal x2 damage | 20% crit, x2 damage | 28 -> 19 |
| bleed (Barbed) | Bleed: 6 damage/s for 3 s | Bleed 6/s for 3 s | 25 -> 17 |
| pull_cells (Chain harpoon) | Pulls the target 1.5 cells back along the path | Pulls back 1.5 cells | 46 -> 20 |
| strip_armor (Corrupted Seal) | Enemies inside lose 1 armor | Foes lose 1 armor | 27 -> 17 |
| madness line (occult dmg towers) | In madness: x<mult> damage, shots go astray | Madness: x<mult>, astray | 43 -> 24 |
| damage line (all dmg towers) | Damage 10 every 0.8 s (12.5 DPS) | Damage 10 / 0.8 s (12.5 DPS) | 32 -> 28 |

Not changed: "Range N cells", "Aura radius N cells", "Reserves N sanity", "Kills restore N sanity" (22), "Unaffected by madness" (21), "N shooters", delta lines ("Range a -> b . Damage ..." is a numeric row, already compact), "Loses: " prefix. "May miss while Fraying (N%)" (27) left; wraps to 2 lines.
Tier B = 10 string templates (9 effect/kind + damage line); the damage line is optional (32 -> 28 still wraps at 24 budget; recommend leaving it, so 9).

## Information dropped
- Harpooner "good against packs": implied by "Pierces a line of foes" (and Tier B line "Pierce: N-cell-wide line").
- Elder Sign: "makes them take more damage" -> "exposes"; the exact "+50% damage" line stays in the stats list. Slightly vaguer role, number intact.
- Necronomicon "while it stands": the stat line "Reserves N sanity" stays; "uses sanity" keeps the cost signal for choosing.
- Corrupted Seal/Rite "sanity reserved/more sanity": kept as "+reserve"; exact figure in "Reserves N sanity" and the upgrade delta "Reserve +16/+27". "reserve" is jargon-light: panel already prints "Reserves N sanity".
- Corrupted Seal "Enemies inside": implied by aura.
- Marksman "critical hits" -> "crits" (the stats line spells out chance and multiplier).
- Nothing a player needs to compare branches is removed; every number is in stats/delta lines. Tier B drops "inside"/"every enemy"/"of the target"/"along the path" qualifiers only.

## Edit map for the code slice
1. data/towers.json (Tier A): `role` at lines 5, 23, 41, 61 (tower roles) and 13, 16, 31, 34, 51 (unchanged), 54, 71, 74 (branch roles); 12 occurrences, 11 values replaced. Text only, no schema change. ROLE_MAX_CHARS (sim/defs/tower_def.gd:10) may be lowered 60 -> 24 so the budget is enforced by the loader; then tests/tower_role_test.gd (`x`*ROLE_MAX_CHARS tests use the constant, so they follow) and docs/design/LT-24-tower-info-upgrades.md line ~74 role table (update to new texts) need a check. Lowering is optional; owner call.
2. ui/tower_info.gd `_effect_text` (lines 219-241): replace 8 string literals per Tier B. `kind_lines` (~124-144): madness line. No change to tower_picker.gd, tower_panel.gd, side_panel.gd (they only print def.role / TowerInfo output; no code-side role composition).
3. tests/tower_info_test.gd: expected strings at ~lines 54, 59, 63, 97, 113, 152-154, 248, 359 (and any with "Slows enemies inside", "Enemies inside take", "Bleed:", "Enemies inside lose", "In madness") must be updated to the new templates; tests/side_panel_test.gd compares to def.role (value-agnostic, no change).
4. Verify slice: render picker and tower panel at 1280x720, confirm each role is one line (no wrap).

## Open questions
- Is Tier B (effect lines in code) in scope, or roles only? Roles alone fix "descriptions" in JSON; Tier B fixes the long lines players actually see below the role.
- 24-char budget is estimated; confirm by render before lowering ROLE_MAX_CHARS.
- Wording taste: "exposes" (Elder Sign) and "+reserve" (Corrupted ones) are terse jargon; alternatives: "Slows, +50% dmg taken" would hard-code a number in the role (roles are number-free by LT-24 §1), so avoided.
