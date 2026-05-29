<!-- SPDX-License-Identifier: MIT -->
# Asteroid TUI (#E) — Tachikoma ASCII Asteroid Blaster

The headline demo for [TextMeasure.jl](../../): a terminal asteroid blaster whose
prose is **shape-packed** into procedural silhouettes, fractured on word
boundaries when you hit one, and reflowed live as asteroids rotate — all driven by
*measure-once, layout-many*.

It composes the wave-1 building blocks:

- **`subprep`** (TextMeasure #A) — slice an already-measured paragraph at a word
  boundary without re-measuring, for impact fracture.
- **`FigletBackend`** (TextMeasure #B) — variable-width figlet measurement at the
  terminal cell level (display type).
- **`shape_pack` / `raster_chord_fn`** (TextMeasureLayouts #C) — pack words into a
  cell-grid silhouette.
- **`asteroid_polygon` / `voronoi_shatter` / `rasterize`** (Silhouettes #D) —
  procedural shapes, fracture, and rasterization to the cell grid.

## Architecture

The game core is **renderer-agnostic**: a pure `tick!(state, input)` advances
physics and a pure `draw!(buf, state)` paints a `CellBuffer` (a `Char` grid + 256
-color + bold mask). The interactive Tachikoma renderer drains that `CellBuffer` to
the screen; the CI test drains it to a checksum. Nothing in the core touches a
terminal, so the headline behavior is fully testable headless.

## Run (interactive)

```bash
julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.instantiate()'
julia --project=examples/asteroid_tui examples/asteroid_tui/run.jl
```

Requires Julia ≥ 1.12 (Tachikoma). Linux/macOS only (ANSI / raw-mode). Controls:
arrows/`wasd` move & turn, space charges (release to fire), `?` toggles the debug
overlay, `q` quits.

## Test (headless)

```bash
julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()'
```

The suite drives a deterministic, seeded 60-tick scenario, checksums the resulting
`CellBuffer` against a committed golden (`test/golden/frame60.sha256`), and asserts
**glyph preservation**: when an asteroid is hit, `subprep` slices its already
-measured prose so every word survives in exactly one shard, in original order
(`test/test_fracture.jl`). A human-readable snapshot of the full 120×40 golden
frame lives at `test/golden/frame60.txt`.

### One asteroid from the golden frame

A single asteroid, prose shape-packed inside its silhouette under its stat tag
(excerpt of `test/golden/frame60.txt`, verbatim):

```text
┌─ d:078m v:0.18µ ─┐

   S-type
  drifter
  ZL-139
  composed of
 shock-veined
 ore, ancient
 and cold,
  spinning at
  0.07 rad per
   second.
```
