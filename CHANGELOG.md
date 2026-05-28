# Changelog

All notable changes to TextMeasure.jl are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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

[Unreleased]: https://github.com/jowch/TextMeasure.jl/tree/main
