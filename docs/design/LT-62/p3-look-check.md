# LT-62 P3 look check (S13, replaces the invalid S8 images)

Real window renders (`--resolution`, canvas_items stretch, gl_compatibility), seed 4242,
`--fixed-fps 60`, frame 120. Two separate runs with one seed do not render the same frame (the
sim state drifts), so each size/sanity pair is one process: pause the tree, freeze shader `TIME`,
then grab the same frame under three SanityFx set-ups:

- `bug`: the 82f01b3 copy rect (board + margin in base units), grabbed first;
- `after`: this branch (copy rect scaled to render-target pixels);
- `before`: release-0.5.0 pass (no BackBufferCopy, full-screen rect, 6b8ae0c shader).

Pixel diffs (before vs after; `bug` is the control that must differ):

| window | s100 | s50 | s25 | s0 | bug vs before (s0) |
|---|---|---|---|---|---|
| 1200x675 (scale 1) | after only (before timed out) | 0 | 0 | 0 | 0 (scale 1: no bug) |
| 1600x900 | 0 | 0 | 0 | 0 | 14.8 % px changed, max 57 |
| 1600x1000 (letterboxed) | 0 | 0 | 0 | 0 | 15.3 % px changed, max 58 |
| 1400x900 (letterboxed) | 0 | - | - | 0 | 8.1 % px changed |
| 1200x675 -> 1600x900 resize | - | 0 | - | 0 | 9.3 % px changed |

Identical before/after files are expected (diff 0). The `bug` diff is small here only because
the frozen frame leaves earlier valid pixels in the back buffer; a fresh run shows the full
black area (S9 probe). `p3-probe-1600x900-s0.png` is that fresh run with this branch: the board
is fully rendered.
