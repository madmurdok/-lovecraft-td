# LT-28 UI polish

Commits 314ee0c, 03b1338. Presentation only.

## Items

1. Picker and HUD buttons use `UiStyle.theme()`: every state box is an opaque
   `StyleBoxFlat`, and the disabled text is opaque (`UiStyle.COLOR_TEXT_DISABLED`).
2. A left click off the grid (`Board.outside_clicked`) closes the build and tower views
   (`Game.close_panels`) and clears the board selection.
3. The boot window fit is skipped when the launch args hold `--resolution` or
   `--position` (also the `=` forms), counting only args before a bare `--`
   (`Main.has_window_flag`).
4. The HUD `Footer` covers the strip below the board: opaque, `MOUSE_FILTER_IGNORE`, so a
   range ring crossing the bottom edge is drawn under it.
5. `TowerInfo`: a x1 multiplier prints no line; an effect the next level drops prints
   `Loses: <old line>` (no " (coming soon)").
6. The tower letter sits on a dark plate (`Board.LETTER_PLATE`, `COLOR_LETTER_PLATE`)
   inside the tile.
7. Relic tokens land beside the relic counter (`Hud.relic_landing()`), not on its text.
8. The HUD bar spans the width in three groups split by expanding gaps; at 1280x720 every
   item fits the strip, none overlaps another, none is squashed.
9. Sanity threshold marks are edge ticks (`SanityBar.MARK_TICK`) that stay out of the
   label's ink band.

Items 6 and 9 are draw calls, which are not observable headless. Their tests pin the
geometry the drawing uses (glyph ink read from the font atlas) and, for 6, that
`_draw_tower` draws the plate between the tile and the letter (a source check).

## Controls (LT-28 S2)

Each reverts code only; the named tests must fail. Run each file with GdUnitCmdTool.

| # | Revert | Test file | Tests that must fail |
|---|--------|-----------|----------------------|
| C1 | `ui/side_panel.gd`: `theme = UiStyle.theme(FONT_SIZE)` -> `var t := Theme.new(); t.default_font_size = FONT_SIZE; theme = t`, **and** `ui/hud.gd`: delete `add_child(footer)` | side_panel_test | `test_picker_and_hud_buttons_are_opaque_and_a_disabled_one_stays_legible`, `test_the_footer_covers_the_strip_below_the_board` |
| C2 | `scenes/game.gd`: delete `board.outside_clicked.connect(close_panels)` | scene_game_test | `test_a_click_below_the_board_closes_both_panels` |
| C3 | `scenes/main.gd` `has_window_flag`: delete `if a == "--": return false` (both lines) | window_scale_test | `test_other_flags_and_user_args_after_a_bare_dashdash_do_not_count` |
| C4 | `ui/tower_info.gd`: in `is_active` use `effects[key] != 0.0`, **and** delete the `for line in effect_lines(removed, false):` loop (both lines) | tower_info_test | `test_a_x1_multiplier_prints_no_effect_line`, `test_a_removed_effect_prints_loses_and_its_old_line`, `test_a_removed_pending_effect_has_no_coming_soon` |
| C5 | `scenes/board.gd` `_draw_tower`: delete the `draw_rect(... LETTER_PLATE ..., COLOR_LETTER_PLATE)` line | ui_polish_test | `test_the_tower_letter_sits_on_a_dark_plate_inside_its_tile` |
| C6 | `scenes/relic_tokens.gd` `target()`: `return game.hud.relics_label.get_global_rect().get_center()` | relic_ui_test | `test_tokens_land_beside_the_relic_counter_not_on_its_digits` |
| C7 | `ui/hud.gd`: `bar.custom_minimum_size = Vector2(0, Game.BOARD_ORIGIN.y - 4)` | ui_polish_test | `test_hud_groups_fit_1280x720_by_day_without_overlaps`, `test_hud_groups_fit_1280x720_with_buyout_and_luck_shown` |
| C8 | `ui/sanity_bar.gd`: `const MARK_TICK := 13.0` (the ticks meet: the old full-height line) | ui_polish_test | `test_sanity_ticks_stay_out_of_the_label_band` |

C1 and C4 group two reverts each in one test file; every named test must fail. C5 and C7
share a file but are separate runs.
