<!-- SPDX-License-Identifier: MIT -->
# Asteroid TUI (#E) — Tachikoma ASCII Asteroid Blaster

The headline demo for [TextMeasure.jl](../../): a terminal asteroid blaster whose
prose is **shape-packed** into procedural silhouettes, fractured on word
boundaries when you hit something, and reflowed live as asteroids rotate —
all driven by *measure-once, layout-many*.

It composes the wave-1 building blocks:

- **`subprep`** (TextMeasure #A) — slice an already-measured paragraph at a word
  boundary without re-measuring, for impact fracture.
- **`FigletBackend`** (TextMeasure #B) — variable-width figlet measurement at the
  terminal cell level (ship/asteroid display type).
- **`shape_pack` / `raster_chord_fn`** (TextMeasureLayouts #C) — pack words into a
  cell-grid silhouette.
- **`asteroid_polygon` / `voronoi_shatter` / `rasterize`** (Silhouettes #D) —
  procedural shapes, fracture, and rasterization to the cell grid.

## Run

```bash
julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.instantiate()'
julia --project=examples/asteroid_tui examples/asteroid_tui/run.jl
```

Requires Julia ≥ 1.12 (Tachikoma). Linux/macOS only (ANSI / raw-mode).

> Status: scaffold during the planning gate. Core + renderer land during
> implementation.
