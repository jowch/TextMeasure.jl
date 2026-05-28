# RichText bounding-box measurement — design

**Date:** 2026-05-27
**Issue:** #1 — Support measuring Makie `rich` / `RichText` (per-span fonts, sizes, sub/superscript)
**Status:** design approved, ready for implementation plan

## Problem

TextMeasure tokenizes a single `AbstractString` under one font/size, so it cannot measure
Makie `RichText` (`Makie.rich(...)`), where individual spans carry their own `font`,
`fontsize`, `color`, and baseline shifts (`subscript`/`superscript`).

The driving consumer is [MakieTextRepel.jl](https://github.com/jowch/MakieTextRepel.jl), a
ggrepel-style label-repel utility. Its solver treats each label as a single axis-aligned
bounding box (AABB) and pushes overlapping boxes apart. For `RichText` labels it currently
falls back to Makie's own `full_boundingbox(plot, :pixel)`, which pulls an unstable
Makie-internal dependency and is render-adjacent rather than the clean measure-once path.

## Goal and correctness bar

Compute, **without a render pass**, the pixel bounding box of a `RichText` — its overall
`(width, height)`.

The correctness bar is **equality with Makie's own layout output**. This is not an abstract
"a correct box" requirement: MakieTextRepel hands the `RichText` straight to Makie's `text!`
to *draw* it, so the box the solver reserves must equal the box Makie will occupy, or labels
overlap or clip. We therefore reproduce Makie's geometry independently (same no-kerning
advance sums and the same per-span constants Makie uses), so the consumer can drop the
`full_boundingbox` fallback while getting the same answer. This mirrors the existing
plain-string contract, where `measure` sums advances with **no kerning** specifically to
match Makie exactly.

## Scope

In scope:
- Single-line `RichText` with arbitrary nesting of spans.
- Per-span `font`, `fontsize`, `offset` resolution with inheritance from the parent/default.
- `subscript` / `superscript` baseline shifts and `0.66` scale (Makie's hardcoded constants).
- Mixed fonts (bold / italic) — these are simply spans with a different `:font`/`:fontsize`,
  so they fall out of the same tree walk for free.

Out of scope (v1):
- **Multi-line `RichText`.** Makie 0.24.x's rich-text `lineheight` is a hardcoded stub
  (`(i-1)*20` px), not metrics-driven, so multi-line vertical spacing in Makie itself is
  unreliable. Repel labels are typically single-line. v1 detects an embedded `\n` in the
  `RichText` and throws a clear `ArgumentError`; multi-line is a documented follow-up.
- Line-breaking / wrapping of rich text at a `max_width`. Rich text never re-layouts at
  varying widths in the known consumer, so the measure-once / layout-many split adds no value
  here — a single one-shot function is used instead.
- Color, justification, rotation (not needed for an AABB).
- `subsup` / `leftsubsup` stacked two-child spans — deferred unless the golden test set needs
  them; if added later they slot into the same walk.

## Architecture

Follows pretext's layering philosophy: keep the uniform-string primitive **untouched** and add
a styling layer beside it. The plain-string `Segment` / `Prepared` / `layout` path is not
modified.

Two pieces, split along the existing "font engine vs pure arithmetic" seam (the same split as
`prepare` vs `layout`):

### Core (`src/`, pure, no font engine)

A new file (e.g. `src/bounds.jl`) adds:

- **`StyledRun`** — one measured, already-positioned run:

  ```julia
  struct StyledRun
      x        :: Float64   # left edge (advance origin) on the line, px
      baseline :: Float64   # baseline y; Makie convention, +y up; root baseline = 0
      width    :: Float64   # advance width (sum of glyph advances, no kerning), px
      ascent   :: Float64   # ascent above baseline at this run's resolved size, px (>= 0)
      descent  :: Float64   # descent below baseline at this run's resolved size, px (>= 0)
  end
  ```

  This is the backend-agnostic seam. A future generic mixed-font input (e.g. styled runs for
  the FreeType or Monospace backends) reuses it without touching the rich-text/Makie code.

- **`TextBounds`** — the result:

  ```julia
  struct TextBounds
      origin :: NTuple{2,Float64}   # (xmin, ymin) in the walk's coordinate space
      size   :: NTuple{2,Float64}   # (width, height) — what the solver reads
  end
  ```

  Lightweight, so core stays dependency-free. The Makie extension can convert to a
  GeometryBasics `Rect2` at its boundary if a consumer wants to diff against
  `full_boundingbox` directly; core does not depend on GeometryBasics.

- **`bounds(::AbstractVector{StyledRun}) -> TextBounds`** — pure union of each run's box,
  `[x, x+width] × [baseline-descent, baseline+ascent]`:

  ```
  xmin = minimum(r.x for r in runs)
  xmax = maximum(r.x + r.width for r in runs)
  ymin = minimum(r.baseline - r.descent for r in runs)
  ymax = maximum(r.baseline + r.ascent for r in runs)
  TextBounds((xmin, ymin), (xmax - xmin, ymax - ymin))
  ```

  Empty input returns `TextBounds((0.0, 0.0), (0.0, 0.0))`. This is a noun accessor — it does
  no measuring, analogous to how `layout` is pure over what `prepare` already measured.

### Makie extension (`ext/TextMeasureMakieExt.jl`, font-touching, Makie-specific)

- **`measure_bounds(backend::MakieBackend, rt::Makie.RichText) -> TextBounds`** — the public
  verb. It measures, so it sits beside `measure` (1D advance) as its 2D counterpart.

  It walks the `RichText` tree mirroring Makie's `process_rt_node!` / `new_glyphstate`
  (`Makie/src/basic_recipes/text.jl`):
  - Carry a glyph state `(x, baseline, size, font)` seeded from the backend's resolved
    `font`/`fontsize` (`Makie.to_font`, as the plain path already does).
  - Per span, resolve `font`/`fontsize`/`offset` from the span's attributes, inheriting the
    parent value when absent (`_get_font`/`_get_fontsize`/`_get_offset` semantics). `offset` is
    a fraction of the span's fontsize.
  - Apply the hardcoded type constants: `:sup` → size `× 0.66`, baseline `+ 0.40·parent_size`;
    `:sub` → size `× 0.66`, baseline `− 0.25·parent_size`; `:span` → unchanged.
  - For each character in a string leaf, advance `x` by `hadvance(get_extent(font, char))
    × size`, using `find_font_for_char` fallback when the span's font lacks the glyph (mirror
    Makie). Sum advances with **no kerning**.
  - Emit one `StyledRun` per contiguous styled run (a string leaf under one glyph state),
    with `ascent`/`descent` from that run's resolved font/size.
  - Throw `ArgumentError` if a `\n` is encountered (out of scope, see above).

  Then delegate to core `bounds(runs)`.

  Reuses the existing `MakieBackend` advance/metric helpers (`_pixel_size`, FTA
  `get_extent`/`hadvance`/`ascender`/`descender`). Keep in sync with the FreeType extension's
  metric math per the existing convention, though only the Makie extension handles `RichText`
  (a Makie type).

### Open implementation question (resolved empirically by the golden test)

Whether per-**run** font ascender/descender suffice, or Makie's tight box needs per-**glyph**
extents. Makie's `height_insensitive_boundingbox_with_advance` uses `ext.ascender`/
`ext.descender` (the name suggests font-global, per font/size — which would make per-run
metrics sufficient and align with the existing `FontMetrics` model). The golden test is the
arbiter: if it reveals per-glyph granularity is required, the walk drops to per-glyph extents
without changing the public API or the `StyledRun`/`bounds` seam.

## Testing — golden test vs live Makie

New `test/test_richtext.jl`, aggregated by `test/runtests.jl`, using the `Makie` dependency
already declared in `test/Project.toml`.

For each sample `RichText`, build a real Makie `text` plot at a fixed `fontsize`/`font` with
`px_per_unit = 1` (matching the `MakieBackend` convention in CLAUDE.md), obtain Makie's pixel
bounding box (`Makie.boundingbox(plot, :pixel)` / `full_boundingbox` — exact call pinned during
implementation), and assert `measure_bounds(MakieBackend(...), rt).size` matches Makie's
`(width, height)` within a small absolute tolerance.

Sample set (single-line):
- plain `rich("Hello")`
- bold span, italic span (different `:font`)
- mixed `:fontsize` span
- `superscript`, `subscript`
- a nested combination (e.g. `rich("x", superscript("2"), " + ", rich("y"; font=:bold))`)

This pins the version-fragile Makie constants (`0.66`, `+0.40`, `−0.25`, lineheight stub) and
catches drift if a future Makie version changes them. Document the Makie version the constants
are validated against.

## Risks

- **Version fragility.** The `0.66`/`+0.40`/`−0.25` constants are unexported Makie internals
  and could change across versions. Mitigation: the golden test fails loudly on drift; the
  pinned/validated Makie version is documented.
- **Per-glyph vs per-run metrics.** Resolved empirically by the golden test (see above).
- **Multi-line.** Explicitly out of scope and guarded by an `ArgumentError`, so it cannot fail
  silently.

## Files touched

- `src/bounds.jl` — new: `StyledRun`, `TextBounds`, `bounds`.
- `src/TextMeasure.jl` — include + export `StyledRun`, `TextBounds`, `bounds`, `measure_bounds`
  (and `measure_bounds` stub/generic declaration so the extension can add a method).
- `ext/TextMeasureMakieExt.jl` — new `measure_bounds(::MakieBackend, ::RichText)` method.
- `test/test_richtext.jl` — new golden test; registered in `test/runtests.jl`.
- `CHANGELOG.md` — note the new capability.
```
