# K — Knuth–Plass justification utility + comparison demo [STRETCH]

> Stretch · ships only if appetite remains after #A–#J.

## Scope

Two pieces:

1. **`examples/layouts/knuth_plass.jl`** — port of pretext.js's `kp.ts`. Consumes `Prepared.segments`; emits optimal line breaks minimizing total badness. Same input as `layout` and `shape_pack`; different output algorithm.
2. **`examples/justification/`** — separate demo: three columns of the same paragraph (greedy from `layout`, greedy with hyphenation off, K-P), with river visualizers overlaid. Direct port of pretext.js's `justification-comparison` demo.

### Decoupling from #F/#H

#F2 and #H ship with greedy `layout` body justification by default. If #K lands, opt-in via `infograph(doi; justification=:knuth_plass)` and `cover(toml; justification=:knuth_plass)`. **The non-stretch demos are NOT load-bearing on #K.** If #K is requested by a demo but absent at runtime, demos silently fall back to greedy with a one-time `@warn`.

## Acceptance

- K-P produces measurably lower total badness than greedy on a canonical test paragraph.
- River overlay correctly identifies known rivers in greedy output that K-P avoids.
- Comparison demo renders all three columns side-by-side as a single PDF.

## Depends on / Blocks

- **Depends on:** `examples/layouts/` directory from #C.
- **Blocks:** nothing.
- **Optional consumers (if #K ships):** #F2, #H.

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#K [STRETCH] — Knuth–Plass justification utility + comparison demo."
- **Pretext.js reference:** `pages/demos/justification-comparison` and `kp.ts` in https://github.com/chenglou/pretext.
- **Algorithm reference:** Knuth & Plass, "Breaking Paragraphs into Lines," *Software: Practice and Experience*, vol. 11 (1981).
- **Conventions:** `CLAUDE.md` — justification is "Not in scope" for the library itself; K-P lives downstream in `examples/`.

## Suggested labels

`demos-milestone` · `stretch` · `examples` · `optional`
