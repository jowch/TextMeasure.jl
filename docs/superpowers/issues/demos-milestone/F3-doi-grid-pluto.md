# F3 — DOIInfograph 6-up grid + Pluto wrapper (`examples/doi_infograph/`)

> Wave 2 demo · the gif-able / README-hero exhibit.

## Scope

- `grid_infograph(dois::Vector{String}) -> CairoMakie.Figure` composes a 2×3 (or 3×2) grid of infographs for six canonical demonstration DOIs. The actual DOI list lives at `examples/doi_infograph/data/canonical_dois.toml` (the file is the source of truth; the spec commits slots 1–2 by exact DOI and slots 3–6 by selection criterion):
  1. **`10.1038/s41586-019-1666-5`** — Sycamore quantum supremacy (Nature, hybrid OA, long title, >50 authors — exact count varies by source: Nature lists 77, Semantic Scholar 76).
  2. **`10.48550/arXiv.1706.03762`** — Attention Is All You Need (arXiv preprint of the NeurIPS paper, green OA, short title, 8 authors).
  3. *Criterion: PLOS ONE OA paper with CC-BY license and abstract reliably present via OpenAlex or CrossRef.* Implementation picks a specific DOI and records it in `canonical_dois.toml`.
  4. *Criterion: arXiv preprint with title length ≥ 80 characters and no journal-deposited abstract* (low or zero citation count is fine — this slot stresses title autoshrink and no-abstract degradation).
  5. *Criterion: Nature Genetics or similar GWAS paper with ≥ 80 authors* — exercises author-overflow.
  6. *Criterion: paper with no OpenAlex `abstract_inverted_index` AND no Semantic Scholar `tldr`* (CrossRef has only title + authors). Tests the deepest graceful-degradation path; #F3's slot-6 acceptance bullet covers the visual render.

- Pluto notebook (`examples/doi_infograph/Demo.jl`): paste a DOI, render single infograph, slider for page width drives layout reflow, "Export PDF" button.

## Acceptance

- The 6-up grid renders as a single composed `CairoMakie.Figure` with the six panels in a 2×3 (or 3×2) grid. It exports to a **single-page composite PDF** (the grid as one page) and a **single composite PNG** (used as the README hero). The composite PDF is linked beside the PNG in the README for per-panel detail. For per-paper PDFs, callers loop `infograph(doi)` over the six DOIs and save each separately — a documented usage pattern, not a built-in `grid_infograph` option.
- All six papers produce legible, composed infographics — no overlapping text, no clipped figures.
- **Slot 6 (no abstract + no TLDR) graceful render:** the abstract/TLDR slot displays the concept pills strip enlarged + a small "abstract unavailable" caption in muted type. The page does not contain empty whitespace where the abstract would go.
- Pluto slider reflows the layout within ~500ms of slider change (cache the rendered figure; only re-layout, not re-render the figure asset, on slider change).
- Cached API responses make the Pluto demo runnable offline.

## Depends on / Blocks

- **Depends on:** #F2.
- **Blocks:** #I, #J.

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#F3 — DOIInfograph 6-up grid + Pluto wrapper."
- **External deps:** `CairoMakie.jl`, `Pluto.jl`.
- **Conventions:** `CLAUDE.md`.

## Suggested labels

`demos-milestone` · `wave-2` · `examples` · `demo` · `readme-hero`

## Open questions for the planner

- Specific DOIs for slots 3–6 (criteria given). Pick and record in `canonical_dois.toml`.
