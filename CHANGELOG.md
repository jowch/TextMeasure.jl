# Changelog

All notable changes to TextMeasure.jl are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

> The release tag (v0.2.0) is **deferred** until the Asteroid TUI demo (#E, draft
> PR [#26](https://github.com/jowch/TextMeasure.jl/pull/26)) lands; the work below
> stays under `[Unreleased]` until then.

### Added

#### Engine

- `subprep(prep, r)` + `Prepared(; segments, metrics)` kwargs constructor: slice a
  `Prepared` over a segment sub-range, reusing measured widths (no re-measurement).
- `FigletBackend`: measurement backend for FIGlet ASCII-art fonts, shipped as a weakdep
  extension on `FIGlet.jl` (loaded on `using FIGlet`). Measures in **character cells**
  (not pixels); `letter_gap::Int`. The third example of the canonical weakdep-ext pattern.
- `measure_bounds(::MakieBackend, ::RichText) -> TextBounds`: pixel bounding box of Makie
  `rich` text (per-span fonts/sizes, sub/superscript, `subsup`/`leftsubsup`, multi-line),
  reproduced without a render pass and validated against Makie via a golden test. Plus the
  pure `TextBounds` result type. Mirrors Makie 0.24.x layout constants.
- `AbstractMeasurementBackend` contract: backends implement `measure` (advance width of
  one run in px, no kerning) and `font_metrics` (ascent/descent/line_advance).
- `MonospaceBackend`: zero-dependency, deterministic backend; also used as the test backend.
- `FreeTypeBackend`: accurate measurement via FreeTypeAbstraction (loaded as a package
  extension on `using FreeTypeAbstraction`).
- `MakieBackend`: measurement matching Makie's `text!` at `px_per_unit = 1` (loaded as a
  package extension on `using Makie`).
- `prepare(backend, text)`: tokenizes text into word/space/newline segments and measures
  each run once — the only phase that touches the font engine.
- `layout(prep; max_width, align, lineheight)`: pure greedy line-breaking over a `Prepared`,
  producing aligned lines and overall block extent.
- `line_top(lay, ln)`: top-left y of a laid-out line (block top = 0).

#### Examples / demos

A gallery of measurement-driven layout demos under [`examples/`](examples/) (indexed by
[`examples/README.md`](examples/README.md)), each a self-contained Julia project:

- **`examples/layouts`** — `TextMeasureLayouts`: shared `shape_pack` shape-conforming text
  packing (#C) with multi-interval per-band packing (#C2, unblocks two-sided wrap), plus the
  stretch `knuth_plass` / `greedy_justify` justification utilities (#K).
- **`examples/silhouettes`** — `Silhouettes` (#D): procedural asteroid polygons, Voronoi
  shatter, and rasterization built on `DelaunayTriangulation`/`GeometryOps`.
- **`examples/doi_infograph`** — DOIInfograph (#F): adaptive, measurement-driven
  academic-paper infographic generator; the README hero is a 6-up grid of six papers composed
  by one template (offline from a committed API cache).
- **`examples/map_feature`** — MapFeature (#G): a CairoMakie state map-feature page with
  editorial prose wrapping around the silhouette as an irregular obstacle (Vermont, offline).
- **`examples/cover`** — Cover (#H): the "Newer Yorker" correctness exhibit — a vector-PDF
  editorial cover whose every offset is measurement-derived (no manual offsets).
- **`examples/justification`** — a greedy-vs-Knuth–Plass justification comparison exhibit
  with river detection (#K).

In progress: the **Asteroid TUI** demo (#E) — draft PR
[#26](https://github.com/jowch/TextMeasure.jl/pull/26), not yet on `main`.

[Unreleased]: https://github.com/jowch/TextMeasure.jl/tree/main
