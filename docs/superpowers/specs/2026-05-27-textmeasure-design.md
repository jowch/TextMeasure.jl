# TextMeasure.jl — Design

**Date:** 2026-05-27
**Status:** Approved for planning (revised after parallel design review)

## Purpose

TextMeasure.jl is a standalone, backend-agnostic text **layout computation engine**
for Julia. It separates two concerns that are usually tangled together:

- **Measurement** — asking a font engine "how wide is this run of glyphs?"
  This is expensive and backend-specific. It is abstracted behind an interface and
  supplied by pluggable backends.
- **Layout** — line-breaking, wrapping to a width, multiline stacking, alignment,
  and bounding-box composition. This is pure arithmetic, backend-agnostic, and fast.

The design ports the architectural lesson of [pretext.js](https://github.com/chenglou/pretext):
a `prepare()` phase that touches the font engine **once** and caches segment widths,
and a `layout()` phase that is pure arithmetic and can be called thousands of times
(e.g. in a solver loop, or on every camera change in a plot) with zero font calls.

The hard, fiddly, genuinely-reusable part — correct line-breaking — lives in the core
exactly once, so downstream consumers never re-derive it.

## Scope

**In scope:**
- The `prepare` / `layout` engine and its public types.
- The `AbstractMeasurementBackend` contract.
- An in-core, zero-dependency `MonospaceBackend` (also serves as the deterministic
  test backend).
- `FreeTypeBackend` — extension (weak dep: FreeTypeAbstraction.jl). Accurate measurement
  from a font file/FTFont, with no Makie dependency; keeps TextMeasure useful to any
  consumer (Luxor, raw Cairo, SVG generators).
- `MakieBackend` — extension (weak dep: Makie). A thin wrapper that resolves Makie's
  font object and the scene's `px_per_unit` (DPI), then delegates to the same
  summed-advance measurement as `FreeTypeBackend`. Its measurements match what Makie's
  `text!`/`textlabel` will render, which is what the downstream MakieRepel.jl needs.

**Out of scope (separate downstream packages / future work):**
- Any consumer that *uses* layouts: `MakieRepel.jl` (ggrepel/adjustText-style label
  repulsion), treemap label fitting, annotation/textbox rendering. TextMeasure produces
  line-broken geometry; it never renders, and never decides *why* the geometry is wanted.
- A browser/canvas (WGLMakie/Bonito) backend. The contract supports it (canvas
  `measureText` → run width; `fontBoundingBoxAscent/Descent` → vertical metrics, with
  `line_advance` synthesized), but it is deferred.
- UAX #14 line-breaking, CJK (spaceless) segmentation, hyphenation, justification, and
  text rotation (rotation is an affine transform of the returned box, computed by the
  caller — see "Consumer notes").

## Architecture

### Package structure

```
TextMeasure.jl                        # standalone, NO Makie/FreeType in core deps
├── src/
│   ├── TextMeasure.jl                # module + exports
│   ├── backend.jl                    # AbstractMeasurementBackend + the contract
│   ├── types.jl                      # Segment, Prepared, Line, Layout, FontMetrics
│   ├── prepare.jl                    # tokenize + measure → Prepared   (touches backend)
│   ├── layout.jl                     # greedy wrap, align, bbox         (pure, no backend)
│   └── monospace.jl                  # MonospaceBackend — zero-dep fallback, in core
├── ext/
│   ├── TextMeasureFreeTypeExt.jl     # weak dep: FreeTypeAbstraction.jl → FreeTypeBackend
│   └── TextMeasureMakieExt.jl        # weak dep: Makie            → MakieBackend
└── test/                             # pure-layout tests via MonospaceBackend
```

`Project.toml` must declare `[weakdeps]` (FreeTypeAbstraction, Makie) with their UUIDs,
an `[extensions]` table (`TextMeasureFreeTypeExt = "FreeTypeAbstraction"`,
`TextMeasureMakieExt = "Makie"`), and `[compat]` bounds for both (required for
registration). Extension module name = file name = `[extensions]` key (Julia ≥ 1.9).

### Data flow

```
prepare(backend, text) ──[backend calls]──▶  Prepared          (once, expensive)
layout(prep; max_width, align, lineheight) ─▶ Layout           (many times, pure)
```

`prepare` is the only phase that calls the backend. `layout` is pure arithmetic over
the cached `Prepared` and can be re-run freely at different widths/alignments.

## The backend contract

Dispatch is via abstract-type subtypes. A backend is a struct holding its font
configuration (font, size, DPI as applicable). It must implement exactly two methods,
**which are not exported** — backends implement them as `TextMeasure.measure` /
`TextMeasure.font_metrics` (the symbols clash with Measures.jl, StatsBase, and
Distributions, and are interface methods, not application-facing calls):

```julia
abstract type AbstractMeasurementBackend end

# (1) advance width of a single text run, in pixels.
#     `text` is one run — no line breaks; prepare() owns segmentation.
TextMeasure.measure(backend::AbstractMeasurementBackend, text::AbstractString)::Float64

# (2) vertical metrics for the backend's configured font, in pixels
TextMeasure.font_metrics(backend::AbstractMeasurementBackend)::FontMetrics
```

Font, fontsize, and DPI are **backend state**, fixed at construction — the engine
itself never knows about fonts. The canonical unit everywhere downstream of the
backend is **pixels**, at the backend's configured DPI.

**Measurement semantics (important).** A run's width is the **sum of its glyphs'
advances, with no kerning**. This is deliberate: Makie's own text layout advances the
pen identically (`x += hadvance`, no kerning), so summed advances **reproduce Makie's
rendered run width exactly**. Adding kerning would make measurements *diverge* from
Makie, so backends must not apply it. (Because v1 only ever breaks at whitespace,
inter-segment kerning is moot anyway.)

> **Verified empirically (spike, Makie 0.24.10, fontsize 24, TeX Gyre Heros Makie):**
> `fontsize · Σ hadvance(get_extent(face, c))` equals `Makie.text_bb(str, font, fontsize)`
> width to **0.0% relative difference** across kerning-heavy strings (`AVATAR`, `Wm. iii`,
> `fjord`, `Aconcagua`, …). `Makie.to_font("TeX Gyre Heros Makie")` returns an `FTFont`
> directly. Metrics for this font: ascent 22.728, descent 5.232, line_advance 27.96 px —
> note `line_advance == ascent + descent` here (zero line gap), which is why
> `line_advance` is read as its own field rather than assumed larger.

### Backends

```julia
# core, zero-dep — also the deterministic test backend
MonospaceBackend(; fontsize=12, advance_ratio=0.6, lineheight_ratio=1.2)
#   measure(b, text) = length(graphemes(text)) * advance_ratio * fontsize
#   font_metrics(b)  = FontMetrics(0.8*fontsize, 0.2*fontsize, lineheight_ratio*fontsize)

# extension (weak dep FreeTypeAbstraction) — struct + methods live in the extension
FreeTypeBackend(; font="Inter", fontsize=12, dpi=72)
#   measure: pixel_size * Σ hadvance(get_extent(face, glyph)),  pixel_size = fontsize*dpi/72
#   font_metrics: ascent = ascender(face)*pixel_size, descent = -descender(face)*pixel_size,
#                 line_advance = (face.height / units_per_EM) * pixel_size
#   guard: if face.height == 0 (some bitmap/odd fonts) → line_advance = ascent + descent
#          (Makie divides face.height directly with no guard, so in the rare height==0 case
#           this is a deliberate, safer divergence from Makie rather than a match.)

# extension (weak dep Makie) — struct + methods live in the extension
MakieBackend(; font=<Makie default>, fontsize=12, px_per_unit=1.0)
#   font: resolved via Makie.to_font(font) → an FTFont. Makie.NativeFont === FreeTypeAbstraction.FTFont,
#         so this loads the IDENTICAL font object Makie's own text! would. Default font =
#         Makie.to_font(Makie.automatic) (TeX Gyre Heros Makie). Then uses the same summed-advance /
#         face-metrics path as FreeTypeBackend, with pixel_size = fontsize * px_per_unit.
#   px_per_unit (default 1.0): LEAVE AT 1.0 to match Makie's markerspace/scene geometry. Makie computes
#         its text layout — and the markerspace boundingbox(::Text) a repel solver compares against — at
#         px_per_unit = 1 (fontsize is already in px); px_per_unit is applied only later at rasterization.
#         Folding in e.g. CairoMakie's default 2.0 would make every box 2× too large vs Makie's own boxes.
#         Set it >1 only if you want device-pixel dimensions of an exported bitmap. It is a Makie *Screen*
#         property — not on the Scene, not auto-discoverable pre-render — hence a plain constructor arg.
```

`FreeTypeBackend` and `MakieBackend` exist only after their weak dep is loaded
(`using FreeTypeAbstraction` / `using Makie`).

> Note: `lineheight_ratio` (a backend constructor kwarg that sets the font's natural
> `line_advance`) is distinct from `layout`'s `lineheight` kwarg (a multiplier applied
> on top of `line_advance`). Effective spacing is their product.

**Known v1 limitation:** Makie performs per-character font *fallback* (substituting a
different font for glyphs missing from the primary font). A single-font backend cannot
replicate this, so labels containing such glyphs may measure slightly off — both in run
width and, if the fallback font is taller, in the vertical metrics (`font_metrics` always
reports the primary font's ascent/descent/line_advance). Negligible and acceptable for
label-repel use; documented.

## Core types

```julia
struct FontMetrics
    ascent       :: Float64   # pixels above baseline
    descent      :: Float64   # pixels below baseline (positive)
    line_advance :: Float64   # font's natural baseline-to-baseline distance, pixels
end

# internal measurement artifact (NOT exported)
struct Segment
    str   :: String
    width :: Float64          # pixels; 0 for newline segments
    kind  :: Symbol           # :word | :space | :newline
end

# produced by prepare() — caches the expensive measurement
struct Prepared
    segments :: Vector{Segment}
    metrics  :: FontMetrics
end

# one laid-out line
struct Line
    str      :: String        # trimmed of leading/trailing whitespace
    width    :: Float64        # trimmed line width, pixels
    x        :: Float64        # horizontal alignment offset, pixels
    baseline :: Float64        # baseline y; block top = 0, increasing downward
end

# produced by layout() — pure arithmetic over Prepared
struct Layout
    lines   :: Vector{Line}
    size    :: NTuple{2,Float64}   # (width, height) of the laid-out block, pixels
    metrics :: FontMetrics         # echoed from Prepared so a Layout-only holder
                                   # can convert baseline↔top-left and center optically
end
```

All structs are immutable. Callers must not mutate `prep.segments` (it is shared
across repeated `layout` calls).

## Public API

```julia
prepare(backend::AbstractMeasurementBackend, text::AbstractString)::Prepared

layout(prep::Prepared;
       max_width  :: Real   = Inf,
       align      :: Symbol = :left,          # :left | :center | :right
       lineheight :: Real   = 1.0             # multiplier on metrics.line_advance
      )::Layout

# convenience: top-left y of a line (block top = 0); `ln` must be a line of `lay`
line_top(lay::Layout, ln::Line) = ln.baseline - lay.metrics.ascent
```

Exports: `prepare`, `layout`, `line_top`, `Prepared`, `Layout`, `Line`, `FontMetrics`,
`AbstractMeasurementBackend`, `MonospaceBackend`. (`measure`, `font_metrics`, and
`Segment` are **not** exported.)

## Layout geometry

Let `la = lineheight * metrics.line_advance` (effective baseline-to-baseline distance).
For `N` laid-out lines indexed `i = 0 … N-1`:

```
baseline_i = ascent + i * la
size[2] (height) = ascent + (N-1) * la + descent          # = ascent+descent for N=1
size[1] (width)  = maximum trimmed line width over all lines (0 if no lines)
line_top_i = baseline_i - ascent = i * la                  # top line's top = 0
```

The first line's baseline sits at `ascent` (not 0) so its ascenders are not clipped
above the block. `align` sets each line's `x`: `0` for `:left`,
`(size[1] - line.width)/2` for `:center`, `size[1] - line.width` for `:right`.

## Segmentation & line-breaking semantics (v1)

**Tokenizing (`prepare`).** The string is split into a sequence of `Segment`s:
- maximal runs of non-whitespace characters → `:word` segments (measured, atomic);
- maximal runs of space/tab → `:space` segments (measured);
- each `\n` → a `:newline` segment (width 0, hard break).

A v1 word is **atomic**: it is never broken internally (no mid-word breaking, no
hyphenation). CJK and other spaceless scripts therefore do not wrap in v1 (documented
non-goal). `MonospaceBackend` counts grapheme clusters when estimating a run's width,
but grapheme clustering plays no role in *layout* because words are atomic.

**Wrapping (`layout`, greedy).** Walk the segments accumulating the current line:
- `:newline` → flush the current line; start a new line (always a hard break).
- `:word` → if the current line is non-empty and adding the pending `:space` plus this
  word would exceed `max_width`, break *before* this word (the pending space is
  consumed — it belongs to neither line); otherwise append the pending space + word.
- `:space` → held as pending; folded into width only if a word follows it on the same
  line.

**Trimming.** Leading and trailing whitespace are excluded from each line's `str` and
`width`. Interior multiple spaces are **preserved** (not collapsed) — measurement is
lossless. The space *at* a wrap point is consumed (counted in neither line).

**Invariant.** Every non-empty paragraph produces ≥ 1 line, and **every line contains
at least one segment** — so a single word wider than `max_width` occupies its own line
(it overflows rather than looping forever), and `size[1]` reports its true overflow
width (so a consumer can detect "does not fit even wrapped").

**Hard-break / blank-line rules (defined, predictable):** the string is effectively
split on `\n` into paragraphs, each of which soft-wraps to ≥ 1 line. Consequences,
stated explicitly:
- `"a\nb"` → 2 lines.
- `"a\n"` → 2 lines; the second is empty (width 0, consumes one `la` of height). A
  trailing `\n` *does* produce a trailing empty line — no special-casing.
- `"\n"` → 2 empty lines; `"\n\n"` → 3 empty lines.
- A whitespace-only paragraph, or an empty paragraph produced by a `\n` split (interior
  or trailing), → one line with `str=""`, `width=0`. **The sole exception is the
  whole-string empty input `""`**, which yields *zero* lines (see Error & edge handling).
  So every input except `""` produces ≥ 1 line; `"\n"` → 2 lines because the newline
  separates two empty paragraphs, whereas `""` is no content at all.

## Error & edge handling (all in the pure layer)

- Empty string `""` → `Layout` with zero lines, `size = (0, 0)` (still carries `metrics`).
  This is the *only* zero-line input; every other input yields ≥ 1 line.
- `max_width ≤ 0` or `NaN` → treated as `Inf` (no wrap).
- Backend returning a negative width → clamped to 0.
- Backend returning `NaN` → defensive error raised at `prepare` time, naming the
  offending run (covers the degenerate-font case).
- Whitespace-only string (no `\n`) → one line, `width = 0`, `height = ascent + descent`.

## Consumer notes (documentation, not API)

- `Layout.size` is an **unplaced extent**, not a positioned rectangle. Anchoring,
  padding, and centering are the consumer's coordinate decisions. (MakieRepel computes
  the box origin as `anchor + offset - align .* size` and clips its leader line to the
  box edge itself.)
- **Rotation**: a consumer needing a rotated label's footprint computes the AABB from
  `size` and angle θ: `w' = |w·cosθ| + |h·sinθ|`, `h' = |w·sinθ| + |h·cosθ|`.
- For optical (cap-height) centering rather than full-box centering, use
  `metrics.ascent`/`metrics.descent` (now available directly on `Layout`).

## Testing strategy

- **Layout layer (pure):** tested with `MonospaceBackend` — deterministic, no font deps,
  no rendering. Covers wrapping, alignment offsets, trailing/leading-whitespace trimming,
  interior-space preservation, the space-at-wrap-point rule, multiline via `\n`,
  blank-line and trailing-`\n` behavior, the over-wide-token overflow + `size[1]`
  reporting, baseline/height arithmetic, and all numeric edge cases above.
- **FreeType / Makie extensions:** thin tests gated behind the weak deps — measure a
  known string and assert width is positive, finite, and stable across two calls, plus
  one **golden-value** assertion against a known FreeTypeAbstraction output to catch
  silent unit/DPI regressions. For the Makie extension, additionally assert that
  `MakieBackend(px_per_unit=1)` reproduces Makie's markerspace `boundingbox(::Text)`
  width for a known string (the property MakieRepel relies on).

## Example consumers (illustrative, not part of this package)

**Label repel (MakieRepel.jl):** `prepare` each label once with a `MakieBackend`; call
`layout(p; max_width=Inf).size` for single-line bboxes; feed bboxes to its own force
solver. On camera pan/zoom only the (pure) `layout` + solver re-run — no font calls.
Optical centering uses `layout(...).metrics.ascent/descent`.

**Wrapped annotation box:** `prepare` once; `layout(p; max_width=160, align=:left)`;
render a background rect from `lay.size` + padding and one `text!` per `lay.lines` entry,
positioned with `line_top(lay, ln)` (top-left) or `ln.baseline` (baseline align).
Changing width/alignment is a pure re-layout.
