<!-- SPDX-License-Identifier: MIT -->
# TextMeasureLayouts (`examples/layouts`)

Shared layout utilities for the TextMeasure.jl demos milestone. Houses `shape_pack` (#C)
— a shape-conforming text-layout consumer — and (stretch) `knuth_plass` (#K).

Consumed by per-demo projects via `Pkg.develop(path="../layouts")`. Long-term migration
target: a registered `TextMeasureLayouts.jl` sibling package.

> The `Manifest.toml` is intentionally **not** committed (per-demo manifests stay
> gitignored). Reproducibility comes from `Pkg.instantiate()` at run/CI time against the
> committed `Project.toml`.

## `shape_pack`

```julia
using TextMeasure, TextMeasureLayouts
prep = prepare(MonospaceBackend(), "…prose…")
pk = shape_pack(prep, polygon_chord_fn(my_polygon); line_advance=prep.metrics.line_advance)
```

`shape_pack(prep, chord_fn; line_advance, min_chord_width=24, overflow_strategy=:widest_row)`
packs the `:word` segments of `prep` into the region described by `chord_fn`, walking
horizontal bands of height `line_advance` from the top down, and returns a `PackedLayout`
of word `Placement`s in reading order. A full-width rectangle chord_fn reproduces
`layout(prep; max_width=w)` (newline-free text).

- **`chord_fn`** — a closure `(y_top, y_bottom) -> Vector{Tuple{Float64,Float64}}` (or an
  `AbstractChordFn`) returning the available, sorted, disjoint intervals in a band. Empty
  ⇒ skip the band; the widest interval is used when several are returned.
- **Overflow strategies** — `:widest_row` (place at the band's left edge + record in
  `overflowed`), `:skip` (drop + record, back-fill the band with later words), `:reject`
  (abort: empty `placements`, offending + later word indices in `overflowed`).
- **Helpers** — `polygon_chord_fn(::Vector{Point2{Float64}})` (scanline of a 2-D polygon)
  and `raster_chord_fn(::BitMatrix, cell_size)` (cell-grid silhouettes).

All coordinates share `chord_fn`'s frame and `prep.metrics` units.

## Run the tests

```bash
julia --project=examples/layouts examples/layouts/test/runtests.jl
```
