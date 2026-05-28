# F2 — DOIInfograph adaptive layout engine (`examples/doi_infograph/layout/`)

> Wave 2 demo · second of the #F1 → #F2 → #F3 serial chain.

## Scope

The measurement work. Given a `PaperMetadata` and a CairoMakie `Figure` (with a fixed page size), produce a composed page.

### Adaptive primitives (each measurement-driven)

- **Title autoshrink** — binary search over `fontsize` such that `measure(b, title, fontsize) ≤ title_box_width` and line count ≤ 2.
- **Author overflow** — accumulate measured author widths until next would exceed the row; append "et al." atomically.
- **TLDR autosize** — fontsize chosen so measured line-count × line-advance fills (not exceeds) the TLDR box height.
- **Drop cap** — T-glyph measured to know wrap offset for the first paragraph's first three lines.
- **Body text wrap around figure pillar** — text column on the left at fixed width; figure pillar on the right at full body height.
- **Concept pill wrap** — pills measured as atomic segments; greedy fit into the pill strip width with row wrap.
- **Citation sparkline** — Unicode block characters chosen so the sparkline's measured width matches the surrounding caption's measured width within ±1 glyph.

Body justification uses greedy `layout` by default. If #K ships, opt into K-P via `infograph(doi; justification=:knuth_plass)`. If `:knuth_plass` is requested but #K is not shipped, silently fall back to greedy with a one-time `@warn` per Julia session. The valid `template` values are `:editorial` (default; the single composed-cover template described); other values throw `ArgumentError`.

## Acceptance

- **Property test (synthetic):** generate 100 random titles of lengths in `[10, 200]` chars; for every one, title autoshrink terminates with a fontsize where the title fits in ≤ 2 lines at the title box width. No exceptions.
- **Integration test against #F1 cached fixtures:** run `infograph` end-to-end against the six cached `PaperMetadata` objects produced by #F1; verify each renders without error and yields a `CairoMakie.Figure`. This catches regressions at the #F1↔#F2 seam (e.g., inverted-index sort stability) that the synthetic test misses.
- **Comparative test:** Sycamore renders smaller than Attention in the same title box (verifiable assertion on fontsize delta).
- **Author overflow test:** Sycamore (78 authors) emits "et al."; Attention (8 authors) fits all eight.
- Sparkline length matches measured caption width within ±1 glyph across all three acceptance DOIs that have citation timelines.

## Depends on / Blocks

- **Depends on:** #F1, #C.
- **Blocks:** #F3.

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#F2 — DOIInfograph adaptive layout engine."
- **Conventions:** `CLAUDE.md`.

## Suggested labels

`demos-milestone` · `wave-2` · `examples` · `demo`
