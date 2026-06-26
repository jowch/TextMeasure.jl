# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

TextMeasure.jl is a backend-agnostic text **layout engine**: measure once, lay out many times.
Inspired by [pretext.js](https://github.com/chenglou/pretext), but driven by FreeType/Makie
instead of an HTML canvas. **Out of scope** (downstream or deliberately omitted): rendering,
repel/treemap/annotation consumers, UAX-#14 line-breaking, CJK, hyphenation, justification,
rotation.

## Commands

```bash
# Run the full test suite, logging to a per-agent file (see "Test logs" below)
mkdir -p test-logs
julia --project -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"

# Iterate on a single test file in a REPL (test/Project.toml has the deps the exts need)
julia --project=test -e 'using TextMeasure, Test, FreeTypeAbstraction, Makie; include("test/test_layout.jl")'

# Instantiate deps after a fresh clone
julia --project -e 'using Pkg; Pkg.instantiate()'
```

Each `test/test_*.jl` is a self-contained `@testset` aggregated by `test/runtests.jl`.
Don't mutate the shared global Julia env for spikes — use a temp scratch env.

### Test logs

The suite is slow to spin up, so **grep an existing log before re-running** — a fresh
`Pkg.test()` is only needed after changing code the log doesn't already cover.

Write each run to `test-logs/<session-id>.log` (gitignored), keyed by `$CLAUDE_CODE_SESSION_ID`
so parallel/multi-agent runs don't clobber each other's output. That var is set in both
interactive and background sessions; prefer it over `$CLAUDE_JOB_DIR`, which only exists in
background jobs.

## Architecture

Two phases, deliberately split so the expensive one runs once:

1. **`prepare(backend, text) -> Prepared`** (`src/prepare.jl`) — the *only* phase that touches
   the font engine. Tokenizes `text` into `:word` / `:space` / `:newline` `Segment`s and calls
   `measure` on each run, caching widths alongside `FontMetrics`.
2. **`layout(prep; max_width, align, lineheight) -> Layout`** (`src/layout.jl`) — pure arithmetic
   over cached widths; call it freely with different widths/alignments. Greedy line-breaking:
   breaks at whitespace/`\n`, words are atomic (an over-wide word overflows its own line), trims
   leading/trailing whitespace per line. `line_top(lay, ln)` converts a line's baseline to its
   top-left y (block top = 0, increasing downward).

### Backend contract (`src/backend.jl`)

A backend subtypes `AbstractMeasurementBackend` and implements two **non-exported** methods
(define as `TextMeasure.measure` / `TextMeasure.font_metrics`):

- `measure(backend, text)::Float64` — advance width of ONE run in px, summing glyph advances
  with **NO kerning** (this is what makes results match Makie exactly). No line breaks.
- `font_metrics(backend)::FontMetrics` — `ascent` / `descent` (positive, below baseline) /
  `line_advance` in px.

### Backends

- **`MonospaceBackend`** (`src/monospace.jl`) — zero-dep, built in. Each grapheme cluster is
  `advance_ratio * fontsize` wide. Deterministic, so it's also the test backend.
- **`FreeTypeBackend`** / **`MakieBackend`** — container structs live in `src/backend_containers.jl`,
  but their keyword constructors and `measure`/`font_metrics` methods are supplied by **package
  extensions** (`ext/TextMeasure{FreeType,Makie}Ext.jl`), gated on weakdeps. They're inert until
  the user runs `using FreeTypeAbstraction` / `using Makie`. Their advance/metric math is one
  shared source — `ext/shared_metrics.jl` (`_advance_units` / `_face_metrics`), `include`d by both
  — so the two cannot drift. `MakieBackend` should be used with `px_per_unit = 1` to match Makie's
  markerspace geometry.
- **`FigletBackend`** (`ext/TextMeasureFigletExt.jl`, gated on `FIGlet`) — `measure` returns widths
  in **character cells, not pixels** (FIGlet glyphs live on a fixed integer grid), so it has no
  `fontsize` and no `measure_bounds`. Inert until `using FIGlet`.

### Types (`src/types.jl`)

`FontMetrics`, `Segment`, `Prepared`, `Line`, `Layout`. All result structs are read-only by
convention. `Line.str`/`width` are whitespace-trimmed; `Line.baseline` uses block-top = 0.

### Downstream library (`TextMeasureLayouts/`)

Shape-conforming packing (`shape_pack`) and optimal/greedy paragraph justification (`knuth_plass`
/ `greedy_justify`) are **consumers** of a `Prepared`, not core engine surface (justification is
out of scope — see "What this is"). They live in the top-level **`TextMeasureLayouts/`** sibling
package — its own `Project.toml`, registrable separately, depending on registered `TextMeasure` —
and are used by the Tide / Woven demos.

## Conventions

- Adding a backend = subtype `AbstractMeasurementBackend` + implement the two methods. If it needs
  a heavy dep, add it as a weakdep in `Project.toml` and put the methods in a new `ext/` extension,
  mirroring the existing two.
- The shared gallery house style (palette, type ramp, fonts, footer rules) lives in
  `examples/_housestyle/README.md`, mirrored by the `HouseStyle` module in the same directory.
