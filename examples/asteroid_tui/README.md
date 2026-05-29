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

The suite checks three things independently:

- **Render regression** — a deterministic, seeded showcase scene is drawn to a
  `CellBuffer` and checksummed against a committed golden (`test/golden/frame60.sha256`);
  a human-readable snapshot of the 116×36 frame lives at `test/golden/frame60.txt`.
- **Glyph preservation** (`test/test_fracture.jl`) — when an asteroid is hit, `subprep`
  slices its already-measured prose so every word survives in exactly one shard, in
  original order (`rebuilt == original`).
- **Tick-loop determinism / physics** (`test/test_game.jl`) — seeded `tick!` over the
  game core (motion, charge, projectiles, respawn, invulnerability).

### The golden frame

The committed snapshot (`test/golden/frame60.txt`) is a 116×36 showcase scene: a
large dominant asteroid whose descriptive prose is **shape-packed inside its
silhouette** as a rounded text-mass, a smaller intact drifter receding to the upper
right, and the player's ship hunting below — each asteroid labelled by a closed
`┌─ d:… v:… ─┐` callout box joined to its body by a connector leader, with short
motion trails behind the moving bodies and a thrust plume under the ship. Every
body carries a nonzero velocity so the still telegraphs motion. The scene is tuned
for legibility — no overlapping labels, no off-screen clipping. Open
`test/golden/frame60.txt` to view the full frame.
