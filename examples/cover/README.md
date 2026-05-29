<!-- SPDX-License-Identifier: MIT -->
# Cover — the "Newer Yorker" correctness exhibit (#H)

A hand-set editorial cover rendered to a **vector PDF** with CairoMakie: display
title, drop cap, body text flowing around an SVG illustration inset, and a
pull-quote callout. Its job is to prove TextMeasure.jl is **correct** — the honest
acceptance test is *"no manual offsets"*: move the inset and re-render, and every
other element re-aligns because every offset is measurement-derived.

## How it works

- `compose_cover(config)` is **pure** — it computes every text baseline, the body
  `PackedLayout` (wrapped around an inset-exclusion `chord_fn` built in `chord.jl`),
  the drop-cap placement, and pull-quote boxes. No rendering.
- `render_cover(path)` is the only CairoMakie layer; it replays the composed
  placements with `text!`/`poly!`/`lines!`.
- Correctness is asserted on the computed `ComposedCover` (drop-cap baseline ±0.5px,
  bbox non-overlap, body-wrap-honors-inset), **not** on PDF coordinates — CairoMakie
  PDF coords don't round-trip at sub-pixel precision. The PDF is checked only for
  selectable text + font embedding + zero raster images (vector inset).

## Two-sided wrap

Body text flows on **both sides** of the inset in the same scanline bands, using
`shape_pack`'s `fill=:all` mode (every disjoint interval per band is packed
left-to-right). A centered illustration gets text down its left *and* right margins
at once; slide or resize it and the column rebalances with no code change. The
correctness invariants (no overlap, baseline alignment, wrap-honors-inset) hold
regardless. The `compose.jl` flag `TWO_SIDED_WRAP`/`FILL_MODE` selects `:all` vs the
single-sided `:widest`.

## Run it

```bash
julia --project=examples/cover -e 'using Pkg; Pkg.instantiate()'
# render a fixture to PDF (+ PNG):
julia --project=examples/cover examples/cover/render.jl examples/cover/data/cover-v1.toml /tmp/cover-v1.pdf
# tests (invariants + 20-inset property test + PDF golden):
julia --project=examples/cover -e 'using Pkg; Pkg.test()'
```

The three `data/cover-v{1,2,3}.toml` fixtures share `meta`/`body` and vary only the
`[inset]` block — proving the layout adapts with no code change.

## Pinned fonts

Renders use **DejaVu Sans** + **Liberation Serif** (resolved by family name) so the
exported-PDF-text golden reproduces in CI (#J pins the same set). Fonts are code
constants, not TOML fields, for that reason.

## SVG support (intentionally minimal, fails loud)

`data/skyline.svg` uses only straight-line primitives — `rect`, `circle`, `ellipse`,
`line`, `polyline`, `polygon`, and `path` with `M/L/H/V/Z`. Béziers, arcs, transforms,
gradients, `<g>`/`<use>`, and CSS are **not** supported and the parser **throws
`ArgumentError`** on them (a future asset edit straying out of the subset breaks the
parse rather than silently dropping shapes). Each primitive becomes a Makie
`poly!`/`lines!` ring, guaranteeing native vector output (never a bitmap).
