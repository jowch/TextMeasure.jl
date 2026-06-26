# Changelog

All notable changes to TextMeasureLayouts are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

First release of `TextMeasureLayouts` — shape-conforming layout utilities built on top of
TextMeasure's measure-once `Prepared`. Promoted from the in-repo `examples/layouts` package to
a top-level sibling; registration in the General registry is pending.

### Added

#### Shape-conforming packing

- `shape_pack(prep, chord_fn; line_advance, min_chord_width, overflow_strategy, fill)` — flows
  the `:word` segments of a `Prepared` into any 2-D region a `chord_fn` describes, walking
  horizontal bands from the top down. Supports multi-interval bands (text around interior holes
  / two-sided wrap) and `:widest_row` / `:skip` / `:reject` overflow strategies. Returns a
  `PackedLayout` of word `Placement`s in reading order.
- `AbstractChordFn` + `chord_intervals(f, y_top, y_bottom)` — the region protocol: return a
  band's available, sorted, disjoint x-intervals (empty ⇒ skip the band).
- `polygon_chord_fn(::Vector{Point2{Float64}})` / `PolygonChordFn` — scanline of a 2-D polygon.
- `raster_chord_fn(::BitMatrix, cell_size)` / `RasterChordFn` — cell-grid silhouettes.

#### Paragraph justification

- `knuth_plass(prep; max_width, stretch_ratio, shrink_ratio, lineheight)` — optimal
  whole-paragraph line breaking that minimizes total TeX-style badness; returns a
  `JustifiedLayout` (`JustifiedLine`s + `total_badness`).
- `greedy_justify(prep; max_width, …)` — greedy baseline with the identical geometry/badness
  model (its break set equals `layout`'s), for comparison.

#### Examples

- `examples/shape_pack_ascii.jl` — pours prose into a triangle (`polygon_chord_fn`) and a
  circle (`raster_chord_fn`), flush-justifying each band, rendered to ASCII (no graphics deps).
- `examples/optimal_linebreaks.jl` — `knuth_plass` vs `greedy_justify` on one paragraph,
  flush-justified, showing the lower total badness of the optimal breaks.

[Unreleased]: https://github.com/jowch/TextMeasure.jl/tree/main/TextMeasureLayouts
