# LT-24/S2 — behaviours for the tests slice

Code at the S2 commit. Numbers refer to the design note §6 list; only S2 items (1-14).
Each line: behaviour — implementing function.

1. L1 -> L2 for `levels[1].upgrade_cost`: level 1, gold down by the cost, `spent` up by it — `Simulation.upgrade_tower`.
2. L2 -> L3 with "a"/"b": level 2, `branch` set, `stats()` is that branch — `upgrade_tower`, `SimTower.stats`.
3. Rejections in order OUTCOME_REACHED, NO_SUCH_TOWER, MAX_LEVEL, NEED_BRANCH, BAD_BRANCH ("c" at L2, "a" at L1), NOT_BUILD_PHASE, NOT_ENOUGH_GOLD; each changes nothing — `Simulation.can_upgrade` (+ `upgrade_target` returning null).
4. Refused in `Phase.WAVE` even with gold; allowed in BUILD (paused too) and `Phase.NONE`; build/sell unchanged in WAVE — `can_upgrade`.
5. OK emits TOWER_UPGRADED {def, cell, level, branch, cost}, then GOLD_CHANGED "upgrade", then (Elder Sign) SANITY_CHANGED "upgrade" delta -8 — `upgrade_tower`.
6. `command_log` gets `[tick, "upgrade", id, branch]`; replay gives the same run — `upgrade_tower` (the test's replay helper must add an `"upgrade"` case, like build_phase_test's `match c[1]`).
7. Upgrade sanity cost can push to 0 / MADNESS; in MADNESS nothing applies — `upgrade_tower` -> `_add_sanity`.
8. Sell refunds `roundi(0.7 x spent)` incl. upgrades (Rifleman L3 119, Harpooner L2 88) — `sell_refund` (unchanged), `upgrade_tower` adds to `spent`.
9. New stats from the next shot; running `cooldown_ticks` kept — `upgrade_tower` does not touch cooldown; `_fire_towers` reads `stats()`.
10. Pure Ward aura reaches 3.5 cells; Pure Rite in MADNESS no x2/astray; Corrupted Rite cast costs 4 — `SimTower.stats` (branch) through existing combat code.
11. `role` on tower and branch parses (stripped); absent -> ""; non-string, empty/blank, > 60 chars (`TowerDef.ROLE_MAX_CHARS`), and `role` on any `levels[]` entry ("not allowed on levels") rejected with path — `TowerDef.parse_role`, `TowerDef.Level.parse(..., is_branch)`.
12. `has_pending()` true for Marksman, Militia, Barbed, Chain harpoon, Corrupted Seal; false for all L1/L2, Pure Ward, Pure Rite, Corrupted Rite — `TowerDef.Level.has_pending`, `PENDING`.
13. Bots never buy a branch that `has_pending()` nor one missing from `BRANCH_PICK`; cheapest upgrade first, ties -> lower id; occult guard skips an upgrade leaving sanity < 25; no upgrade before 5 towers — `bot_runs._next_upgrade`, `_act`.
    **Correction:** with today's config and seeds 1000-1002, occult and madness lose at wave 3 and buy L2s only (no L3 reached); mundane buys L2s only. "occult/madness buy L3s" does not hold on real runs; pin the L3 choice on `_next_upgrade` with a constructed sim (towers at L2, enough gold, BUILD) instead.
14. `--upgrades=0` RUN lines are byte-identical to the pre-LT-24 harness (verified, seeds=3: 9/9 identical); the `upgrades`/`upgrade_gold` keys are omitted then. No upgrade during a wave: the sim refuses it, `_act` stops the round — `_act`, `can_upgrade`.

Must confirm (§6), checked against the code:
1. Outside `sim/`, only `bot_runs._best_cell` reads `levels[0]` (scoring); `tests/occult_tower_test.gd:211` sets `level = 1` directly (still valid). UI not checked beyond grep: no `.level` reads in ui/ or scenes/.
2. `scenes/board.gd:81` `match ev.type` has no exhaustive default; an unknown type falls through.
3. No test asserts `CommandResult.size()` / `SimEvent.Type.size()`.

## S3 (UI) behaviours

15. `TowerInfo.lines` gives, for every tower x (L1, L2, a, b), a line per non-zero stat and effect built from config: `Damage <d> every <i> s (<dps> DPS)` + `Range <r> cells`, or `Support (no damage)` + `Aura radius <r> cells`; sanity drains; effect lines in `EFFECT_GROUPS` order; kind lines last. A config edit changes the text; DPS = damage / fire_interval only (Militia 24) — `TowerInfo.lines`, `effect_lines`, `_dps`.
16. A line whose key (or one key of its pair) is in `TowerDef.Level.PENDING` ends with ` (coming soon)`; removing the key from `PENDING` drops the suffix; an effect key outside `EFFECT_GROUPS` renders as `key: value` — `TowerInfo.effect_lines`, `_drain_text`.
17. Kind lines: mundane damage towers get `Kills restore <regen_mundane_kill> sanity` and `May miss while Fraying (<fraying miss %>%)`; occult damage towers get `In madness: x<damage_multiplier> damage, shots go astray` or `Unaffected by madness` (Pure Rite). **Deviation from §3:** support towers (damage 0, Elder Sign) get no madness line, since madness changes shots only — `TowerInfo.kind_lines`.
18. `num` prints up to 2 decimals, trailing zeros dropped (`3.5`, `82.5`, `0.2`, `12`, `25.71`); `cost_text(80, 8)` = `80 gold + 8 sanity`, `cost_text(40, 0)` = `40 gold`; the currency word is `TowerInfo.CURRENCY` — `TowerInfo.num`, `cost_text`.
19. `delta_lines(from, to)`: one `Range a → b · Damage a → b · Interval a → b s · DPS a → b` line of changed stats only (aura: `Aura radius`), then the new/changed effect lines (a pair shown whole), then `Unaffected by madness` when the flag flips off; identical levels → empty — `TowerInfo.delta_lines`.
20. Role is the first line: build view info under each tower button (`picker.infos[id]`), tower view `role_label` (tower role at L1/L2, branch role at L3) and the first line of each branch button's info; no role line when `role` is empty (`role_label.visible` false) — `TowerPicker._ready`, `TowerPanel.refresh`, `_refresh_upgrade`.
21. Side panel rect = `SidePanel.panel_rect(map)` = x 960..1152, y 48..648 in the base viewport (from `Game.BOARD_ORIGIN` + `map.width × Board.CELL` and the project viewport size), never intersects the board rect; content is in a vertical-only `ScrollContainer`, so long content (build view, L2 branches) scrolls instead of growing past 648 — `SidePanel._ready`, `panel_rect`.
22. Exactly one view is shown: `idle_label` (`Click a cell to build, a tower to upgrade.`) iff neither `picker.visible` nor `tower_panel.visible`; the panel itself is hidden on OUTCOME — `SidePanel._update_idle`, `Game._consume_events`.
23. Build buttons read `<Name> - <cost_text>` (Elder Sign shows `+ 8 sanity`), disabled with ` (<reason>)` from `TowerInfo.REASONS` when `can_build` refuses — `TowerPicker.refresh`.
24. Tower view: L1 shows only `upgrade_buttons[""]` (`Upgrade to L2 - <cost>`), L2 only `upgrade_buttons["a"/"b"]` named by the branch `name`, L3 none and `max_label` (`Max level`) visible; title `<Name>  L<n>` (+ ` · <branch name>` at L3) — `TowerPanel.refresh`.
25. Upgrade buttons are disabled when `can_upgrade` is not OK with ` (wave in progress)` (NOT_BUILD_PHASE), ` (not enough gold)`, ` (run over)`; `refresh()` (every frame and after each command) enables them again when the cause goes (wave ends, gold rises) — `TowerPanel._refresh_upgrade`.
26. An enabled upgrade with `upgrade_sanity_cost > 0` gets ` (drives you mad!)` when `sanity - cost <= 0` and the state is not MADNESS; it stays enabled — `TowerPanel._drives_mad`.
27. Clicking an upgrade/branch button calls `Game.upgrade(id, branch)`; the tower view stays on the same tower, `board.selected_range` equals the new `t.stats().range_cells`, the sell text shows the new refund (`Sell (+119 gold)` for a Rifleman L3) — `TowerPanel._on_upgrade_pressed`, `refresh`, `Game.upgrade`.
28. Cancel, a click on water/path, selling, or the tower disappearing → idle view; clicks on the panel never reach the board — `TowerPanel.close`, `TowerPicker.close`, `Game._on_cell_clicked`.
29. Board: one pip per level (1-3) along the bottom of the tower square, the branch letter (`a`/`b`) top-right at L3 — `Board._draw_tower` (render-only, check by screenshot).

UI tests updated in S3 (spec changed popups → side panel): `tests/scene_game_test.gd` — `_game.sell_panel` → `_game.tower_panel` everywhere, `test_clicking_a_tower_opens_sell_panel_and_selling_refunds` renamed `..._opens_tower_view_and_selling_refunds`. `picker.visible` keeps meaning "build view shown", so the other picker assertions and `tests/window_scale_test.gd` are unchanged.
