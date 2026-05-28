# F2 — DOIInfograph adaptive layout engine (`examples/doi_infograph/layout/`)

> Wave 2 demo · second of the #F1 → #F2 → #F3 serial chain.

## Scope

The measurement work. Given a `PaperMetadata` and a CairoMakie `Figure` (with a fixed page size), produce a composed page.

### Adaptive primitives (each measurement-driven)

**Reminder about the `measure` contract:** `measure(b::AbstractMeasurementBackend, text)` returns the run's advance width in **px** at the backend's own fontsize — fontsize is baked into the backend at construction (`MakieBackend(face; fontsize, px_per_unit)`), NOT a third argument to `measure`. Binary search over fontsize therefore means **constructing a new backend per iteration** (or mutating fontsize via a re-construction helper), not calling `measure(b, text, fs)`.

- **Title autoshrink** — binary search over a sequence of backends `MakieBackend(face; fontsize=fs_i, px_per_unit=1)` for `fs_i ∈ [fs_min, fs_max]` such that `measure(b_i, title) ≤ title_box_width` and `prepare(b_i, title)` then `layout(prep; max_width=title_box_width)` yields a line count ≤ 2. Bounds: `fs_min = 14.0`, `fs_max = 48.0`; ~6 binary-search iterations to ±0.5 px.
- **Author overflow** — accumulate measured author widths until next would exceed the row; append "et al." atomically.
- **TLDR autosize** — fontsize chosen so measured line-count × line-advance fills (not exceeds) the TLDR box height. **Bounds:** `fs_min = 9.0`, `fs_max = 14.0` (body-text range; never grows into display sizes even if TLDR is one short sentence). Search terminates at the largest `fs` where the laid-out block height is ≤ box height; if `fs_max` already fits, return `fs_max` (no further growth).
- **Drop cap** — uses a separate `MakieBackend` constructed at `dropcap_fontsize ≈ 3 × body_fontsize`. Wrap offset = `measure(dropcap_backend, first_letter_of_first_paragraph)` + a configurable gutter (default 4px). Drop cap applies only to the first paragraph's first three lines (per the `cover.toml` schema in #H — same pattern here).
- **Body text wrap around figure pillar** — text column on the left at fixed width; figure pillar on the right at full body height.
- **Concept pill wrap** — pills measured as atomic segments; greedy fit into the pill strip width with row wrap.
- **Citation sparkline** — Unicode block characters chosen so the sparkline's measured width matches the surrounding caption's measured width within ±1 glyph.

Body justification uses greedy `layout` by default. If #K ships, opt into K-P via `infograph(doi; justification=:knuth_plass)`. If `:knuth_plass` is requested but #K is not shipped, silently fall back to greedy with a one-time `@warn` per Julia session. The valid `template` values are `:editorial` (default; the single composed-cover template described); other values throw `ArgumentError`.

## Acceptance

- **Property test (synthetic):** generate 100 random titles of lengths in `[10, 200]` chars; for every one, title autoshrink terminates with a fontsize where the title fits in ≤ 2 lines at the title box width. No exceptions.
- **Integration test against #F1 cached fixtures:** run `infograph` end-to-end against the six cached `PaperMetadata` objects produced by #F1; verify each renders without error and yields a `CairoMakie.Figure`. This catches regressions at the #F1↔#F2 seam (e.g., inverted-index sort stability) that the synthetic test misses.
- **Comparative test:** Sycamore renders smaller than Attention in the same title box (verifiable assertion on fontsize delta).
- **Author overflow test:** Sycamore (>50 authors — exact count varies by source) emits "et al."; Attention (8 authors) fits all eight.
- Sparkline length matches measured caption width within ±1 glyph across all three acceptance DOIs that have citation timelines.

## Depends on / Blocks

- **Depends on:** #F1, #C.
- **Blocks:** #F3.

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#F2 — DOIInfograph adaptive layout engine."
- **Conventions:** `CLAUDE.md`.

## Suggested labels

`demos-milestone` · `wave-2` · `examples` · `demo`
