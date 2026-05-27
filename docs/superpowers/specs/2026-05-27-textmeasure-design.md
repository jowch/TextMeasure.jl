# TextMeasure.jl — Design

**Date:** 2026-05-27
**Status:** Approved for planning

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
- One v1 measurement-backend extension: `FreeTypeBackend` (weak dep on
  FreeTypeAbstraction.jl).

**Out of scope (separate downstream packages / future work):**
- Any consumer that *uses* layouts: `MakieRepel.jl` (ggrepel-style label repulsion),
  treemap label fitting, annotation/textbox rendering. TextMeasure produces
  line-broken geometry; it never renders, and never decides *why* the geometry is wanted.
- A dedicated Makie backend. The FreeType backend uses the same library Makie uses
  under the hood (FreeTypeAbstraction.jl), so measuring with the same font matches
  Makie's rendering without a Makie dependency. A Makie-native backend can be added
  later if a concrete need appears.
- A browser/canvas (WGLMakie) backend.
- UAX #14 line-breaking, CJK segmentation, hyphenation, and text justification.

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
│   └── TextMeasureFreeTypeExt.jl     # weak dep: FreeTypeAbstraction.jl
└── test/                             # pure-layout tests via MonospaceBackend
```

### Data flow

```
prepare(str, backend)  ──[backend calls]──▶  Prepared          (once, expensive)
layout(prep; max_width, align, lineheight) ─▶ Layout           (many times, pure)
```

`prepare` is the only phase that calls the backend. `layout` is pure arithmetic over
the cached `Prepared` and can be re-run freely at different widths/alignments.

## The backend contract

Dispatch is via abstract-type subtypes. A backend is a struct holding its font
configuration (font, size, DPI as applicable). It must implement exactly two methods:

```julia
abstract type AbstractMeasurementBackend end

# (1) advance width of a single text run, in pixels
measure(backend::AbstractMeasurementBackend, run::AbstractString)::Float64

# (2) vertical metrics for the backend's configured font, in pixels
font_metrics(backend::AbstractMeasurementBackend)::FontMetrics
```

Font, fontsize, and DPI are **backend state**, fixed at construction — the engine
itself never knows about fonts. The canonical unit everywhere downstream of the
backend is **pixels**, at the backend's configured DPI.

Backends shipped in v1:

```julia
MonospaceBackend(; fontsize=12, advance_ratio=0.6, lineheight=1.2)  # core, zero-dep
FreeTypeBackend(; font="Inter", fontsize=12, dpi=72)                # extension
```

`MonospaceBackend.measure` returns `length(graphemes(run)) * advance_ratio * fontsize`.
It is deterministic and dependency-free, making it the test backend as well as a
usable draft-quality fallback.

> Note: `measure` is a common name and is exported; consumers with a clash may need
> to qualify it as `TextMeasure.measure`.

## Core types

```julia
struct FontMetrics
    ascent       :: Float64   # pixels above baseline
    descent      :: Float64   # pixels below baseline (positive)
    line_advance :: Float64   # font's natural baseline-to-baseline distance, pixels
end

# one measured segment of the source string
struct Segment
    str                  :: String
    width                :: Float64   # pixels
    is_break_opportunity :: Bool      # may a line break occur before this segment?
end

# produced by prepare() — caches the expensive measurement
struct Prepared
    segments :: Vector{Segment}
    metrics  :: FontMetrics
end

# one laid-out line
struct Line
    str      :: String
    width    :: Float64   # trimmed line width, pixels
    x        :: Float64   # horizontal alignment offset, pixels
    baseline :: Float64   # baseline y; top line = 0, increasing downward
end

# produced by layout() — pure arithmetic over Prepared
struct Layout
    lines :: Vector{Line}
    size  :: NTuple{2,Float64}   # (width, height) of the laid-out block, pixels
end
```

## Public API

```julia
prepare(str::AbstractString, backend::AbstractMeasurementBackend)::Prepared

layout(prep::Prepared;
       max_width  :: Real   = Inf,
       align      :: Symbol = :left,          # :left | :center | :right
       lineheight :: Real   = 1.0             # multiplier on metrics.line_advance
      )::Layout

# Baseline-to-baseline distance used for stacking lines:
#     line_advance_used = lineheight * prep.metrics.line_advance
# (lineheight = 1.0 reproduces the font's natural spacing)
```

Exports: `prepare`, `layout`, `measure`, `font_metrics`, `Prepared`, `Layout`, `Line`,
`Segment`, `FontMetrics`, `AbstractMeasurementBackend`, `MonospaceBackend`.

## Segmentation & line-break policy (v1)

- `prepare` splits the string into segments at **break opportunities**, which occur at
  **whitespace (space, tab)** and at explicit `\n` (always a hard break).
- Within a word, text is treated as **Unicode grapheme clusters** (via the `Unicode`
  stdlib) so multi-codepoint clusters (e.g. `"2σ"`, emoji + modifier) never split.
- `layout` greedily packs segments onto a line until the next would exceed `max_width`,
  then breaks. Trailing whitespace is trimmed from each line's reported `width`.
- A single segment wider than `max_width` overflows onto its own line rather than
  looping forever; `size[1]` reports the true overflow width so a consumer can decide
  to grow or clip.

**v1 non-goals (documented limitations):** UAX #14 line-breaking, CJK (spaceless)
segmentation, hyphenation, and justification.

## Error & edge handling (all in the pure layer)

- Empty string → `Layout` with zero lines and `size = (0, 0)`.
- `max_width ≤ 0` or `NaN` → treated as `Inf` (no wrap) rather than erroring.
- Backend returning a negative width → clamped to 0.
- Backend returning `NaN` → defensive error at `prepare` time, with a message naming
  the offending run (covers the degenerate-font case).
- Whitespace-only string → one line, trimmed width 0, height = one `line_advance`.

## Testing strategy

- **Layout layer (pure):** tested with `MonospaceBackend` — deterministic, no font deps,
  no rendering. Covers wrapping, alignment offsets, trailing-whitespace trimming,
  multiline via `\n`, over-wide-token overflow, and all edge cases above.
- **FreeType extension:** a thin separate test, gated behind the weak dep — measure a
  known string and assert the width is positive, finite, and stable across two calls.

## Example consumers (illustrative, not part of this package)

**Label repel (MakieRepel.jl):** `prepare` each label once; call `layout(p; max_width=Inf).size`
to get single-line bboxes; feed bboxes to its own force solver. On camera pan/zoom only
the (pure) `layout` + solver re-run — no font calls.

**Wrapped annotation box:** `prepare` once; `layout(p; max_width=160, align=:left)`;
render a background rect from `lay.size` and one `text!` per `lay.lines` entry using each
line's `x` and `baseline`. Changing width/alignment is a pure re-layout.
