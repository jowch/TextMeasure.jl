# Changelog

All notable changes to TextMeasure.jl are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

> The first release tag (v0.1.0) is **deferred** until the greenfield demo gallery
> ([#30](https://github.com/jowch/TextMeasure.jl/pull/30)) lands; the work below
> stays under `[Unreleased]` until then. Nothing has been tagged or registered yet.

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

A focused **three-piece** gallery under [`examples/`](examples/) (indexed by
[`examples/README.md`](examples/README.md)) on one shared house-style spine —
*measure once, then **knead · weave · place** — many.* Each piece is a self-contained Julia
project with its own `Project.toml`, README, and a deterministic golden test that hashes the
**computed** layout table (never pixels):

- **`examples/tide`** — *The Tide* (**knead**): a wavy coral tide-line kneads a justified prose
  block; the engine re-flows the prose into the wave's wake every frame (one `shape_pack` per
  frame over cached widths). Looping MP4 + hero still.
- **`examples/woven`** — *Woven* (**weave**): the project's own MIT license faded to a Plex Mono
  ghost, with two found poems woven through it in place — exact per-word positions recovered by
  re-walking the prepared segments.
- **`examples/atlas`** — *The Atlas* (**place**): a seamless zoom-dive over the California Central
  Coast; every place-label measured by TextMeasure and placed collision-free by
  [MakieTextRepel.jl](https://github.com/jowch/MakieTextRepel.jl) (`solve_cluster`), re-solved and
  warm-started every frame. Stateless opacity, deterministic two-pass placement, geography-aware
  seeding, altitude-scaled cloud areals. Looping MP4 + hero still.

Shared infrastructure (libraries, not standalone demos):

- **`examples/layouts`** — `TextMeasureLayouts`: shared `shape_pack` shape-conforming text packing
  with multi-interval per-band packing (unblocks two-sided wrap), plus the `knuth_plass` /
  `greedy_justify` justification utilities. Consumed by The Tide and Woven.
- **`examples/_housestyle`** — `HouseStyle`: the shared spine (palette, type ramp, pinned font
  helpers, golden-digest helper).
- **`examples/fonts`** — the pinned OFL font families used across the pieces.

### Changed

- Replaced the original multi-wave demo plan (the retired `cover` / `doi_infograph` /
  `justification` / `map_feature` / `silhouettes` / `breathing_column` examples) with the
  three-piece greenfield gallery above. Tracking issues for the old plan were closed as not
  planned; see [#30](https://github.com/jowch/TextMeasure.jl/pull/30).

[Unreleased]: https://github.com/jowch/TextMeasure.jl/tree/main
