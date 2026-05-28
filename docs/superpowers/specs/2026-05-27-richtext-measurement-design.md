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
- `RichText` with arbitrary nesting of spans, **including embedded `\n` (multi-line)**.
- Per-span `font`, `fontsize`, `offset` resolution with inheritance from the parent/default.
- `subscript` / `superscript` baseline shifts and `0.66` scale (Makie's hardcoded constants).
- `subsup` / `leftsubsup` — stacked two-child sub+super spans (the consumer uses these).
- Mixed fonts (bold / italic) — these are simply spans with a different `:font`/`:fontsize`,
  so they fall out of the same tree walk for free.

Out of scope (v1):
- Line-breaking / wrapping of rich text at a `max_width`. Rich text never re-layouts at
  varying widths in the known consumer, so the measure-once / layout-many split adds no value
  here — a single one-shot function is used instead. (Multi-line via *explicit* `\n` is in
  scope; *automatic* wrapping is not.)
- Color, justification, rotation (not needed for an AABB).

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
  - `:subsup` / `:leftsubsup` — stacked two-child spans (exactly two children: sub, super).
    Both children are laid out from the **same parent x and baseline**, the sub shifted down
    and the super up (same offsets as `:sub`/`:sup`); x then advances by the **max** of the two
    children's widths. `:subsup` is left-aligned at the shared start x; `:leftsubsup` is
    right-aligned (Makie's `right_align!`). Makie forbids internal line breaks here. Exact
    horizontal placement is pinned by the golden test.
  - For each character in a string leaf, advance `x` by `hadvance(get_extent(font, char))
    × size`, using `find_font_for_char` fallback when the span's font lacks the glyph (mirror
    Makie). Sum advances with **no kerning**.
  - On `\n` in a string leaf, reset `x = 0` and drop the baseline by Makie's per-line spacing.
    **Note:** Makie 0.24.x's `apply_lineheight!` is a hardcoded stub — a flat `20` px per line
    (`oy - (i-1)*20`), independent of fontsize or `lineheight`, marked `# TODO: Lineheight` in
    Makie. We mirror that `20` px to match Makie's current bbox. This is the most fragile
    constant we depend on; the golden test guards it (see Risks).
  - Emit one `StyledRun` per contiguous styled run (a string leaf under one glyph state, on one
    line), with `ascent`/`descent` from that run's resolved font/size.

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

Sample set:
- plain `rich("Hello")`
- bold span, italic span (different `:font`)
- mixed `:fontsize` span
- `superscript`, `subscript`
- `subsup` and `leftsubsup` (stacked sub+super)
- multi-line: a `RichText` containing `\n` (pins the 20px line-spacing stub)
- a nested combination (e.g. `rich("x", superscript("2"), " + ", rich("y"; font=:bold))`)

This pins the version-fragile Makie constants (`0.66`, `+0.40`, `−0.25`, the `20`px line-spacing
stub) and catches drift if a future Makie version changes them. Document the Makie version the
constants are validated against.

### CI and version-drift detection

There is currently **no CI** in this repo (no `.github/`). The golden test only protects
locally until CI exists, so this feature adds CI infrastructure:

- **`.github/workflows/CI.yml`** — run `Pkg.test()` on supported Julia versions (compat floor
  1.11 and latest stable). The golden test runs against whatever Makie the compat bounds allow.
- **`.github/workflows/CompatHelper.yml`** — [CompatHelper.jl](https://github.com/JuliaRegistries/CompatHelper.jl),
  Julia's Dependabot equivalent. On a new Makie release it opens a PR widening `[compat]`; CI on
  that PR resolves the new Makie and runs the golden test. If Makie changed any mirrored constant
  (`0.66` / `0.40` / `0.25` / `20`px line spacing), the golden test fails on the compat-bump PR —
  turning silent geometry drift into a red PR at the moment of adoption. CompatHelper must be
  configured to manage **both** the root `[compat]` (Makie/FreeType are weakdeps) and the
  `test/` subdir; `test/Project.toml` currently has no `[compat]`, so add one and let CompatHelper
  maintain it for reproducibility.
- **Optional canary** — a weekly scheduled job that `Pkg.update()`s to the latest Makie and runs
  the golden test as `continue-on-error`, for early warning *before* a compat bump.

## Risks

- **Version fragility.** The `0.66`/`+0.40`/`−0.25` sub/sup constants and especially the `20`px
  multi-line spacing are unexported Makie internals and could change across versions; the `20`px
  stub is explicitly `# TODO`-marked in Makie and is the likeliest to change. Mitigation: the
  golden test fails loudly on drift, and CompatHelper + CI surface it on the Makie compat-bump PR
  (see CI section). The validated Makie version is documented in the test.
- **Per-glyph vs per-run metrics.** Resolved empirically by the golden test (see above).
- **No CI exists yet.** Until the workflows land, the golden test only runs locally and the
  drift-detection story above is inert. CI setup is therefore part of this feature's work.

## Files touched

- `src/bounds.jl` — new: `StyledRun`, `TextBounds`, `bounds`.
- `src/TextMeasure.jl` — include + export `StyledRun`, `TextBounds`, `bounds`, `measure_bounds`
  (and `measure_bounds` stub/generic declaration so the extension can add a method).
- `ext/TextMeasureMakieExt.jl` — new `measure_bounds(::MakieBackend, ::RichText)` method.
- `test/test_richtext.jl` — new golden test; registered in `test/runtests.jl`.
- `test/Project.toml` — add `[compat]` for Makie/FreeTypeAbstraction (for reproducibility +
  CompatHelper management).
- `.github/workflows/CI.yml`, `.github/workflows/CompatHelper.yml` — new CI + version-drift bot
  (and optional weekly canary job).
- `CHANGELOG.md` — note the new capability.
```
