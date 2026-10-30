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
