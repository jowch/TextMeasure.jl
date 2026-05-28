# H — CairoMakie "Newer Yorker" correctness exhibit (`examples/cover/`)

> Wave 2 demo · the correctness/taste exhibit.

## Pitch

The demo whose job is to **prove the library is correct**, not just gif-able. The honest acceptance test is **"no manual offsets"** — change the SVG inset's position by 3 pixels, re-render, every other element re-aligns correctly because every offset was measurement-derived, not hardcoded.

## Scope

Hand-set editorial cover: title in display type, body text flowing around an SVG illustration inset (uses `shape_pack`), drop cap, pull-quote callouts. No data ingest; static content from `cover.toml`.

### `cover.toml` schema

```toml
[meta]
title    = "..."             # display title
subtitle = "..."             # optional
byline   = "..."             # author/credit line

[layout]
page_size = "letter"         # "letter" | "a4" | "tabloid"
margin_px = 36               # uniform page margin

[inset]
svg_path   = "data/x.svg"    # path relative to the cover.toml file
x_px       = 240             # top-left corner in page coords (excl. margin)
y_px       = 120
width_px   = 200
height_px  = 280

[[body]]                     # array-of-tables — paragraphs in order
paragraph = """..."""
dropcap   = true             # optional; applies only to the FIRST paragraph

[[body]]
paragraph = """..."""

[[pull_quote]]               # array-of-tables — zero or more callouts
text         = "..."
attribution  = "..."         # optional
x_px         = 60
y_px         = 480
width_px     = 180
```

Body justification uses greedy `layout` by default (or K-P if #K shipped).

The three acceptance fixture files (`cover-v1.toml`, `cover-v2.toml`, `cover-v3.toml`) vary the `inset` block (position + size) while keeping `meta` and `body` similar enough to verify the layout adapts without manual code changes.

## Acceptance

- The demo ships with three `cover-v{1,2,3}.toml` files where the SVG inset is at different positions/sizes. All three produce visually composed PDFs with no manual layout code changes between renders.
- **Property test (random insets, catches author-tuned-TOML blind spots):** generate 20 random SVG inset positions within the page bounds (inset width/height also randomized within reasonable ranges). For each, render the cover and verify the "no manual offsets" invariants hold: (a) drop cap baseline aligns with paragraph baseline within ±0.5px **at the computed-layout level (not extracted from the rendered PDF)**, (b) pull-quote callouts do not overlap body text or the SVG inset (bbox intersection check **on the computed `PackedLayout` placements**, before rendering), (c) body wrap honors the inset boundary at every line. If any of the 20 fail, the test fails.

  *Why layout-time, not PDF-extraction-time:* CairoMakie's PDF output does not guarantee that text-run coordinates round-trip through `pdftotext`/`pdfminer` at sub-pixel precision (those tools return text content, not baseline coords). Verifying at layout time gives a deterministic check that the **measurement pipeline** is correct — which is what this exhibit is supposed to prove. The rendered PDF is checked separately for selectable text presence, not for coordinate fidelity.
- Drop cap's computed baseline aligns with paragraph baseline within ±0.5px (asserted from the `PackedLayout` returned by `shape_pack`, not from PDF inspection).
- Pull-quote callouts do not overlap body text or the SVG inset (verified by bbox intersection check on the computed `PackedLayout`).
- SVG inset is rendered as native CairoMakie vector content, not a bitmap.
- PDF text is selectable (font embedding verified).

## Depends on / Blocks

- **Depends on:** #C.
- **Blocks:** #I, #J.

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#H — CairoMakie 'Newer Yorker' correctness exhibit."
- **External deps:** `CairoMakie.jl`, `TOML` (stdlib).
- **Conventions:** `CLAUDE.md`.

## Suggested labels

`demos-milestone` · `wave-2` · `examples` · `demo` · `correctness-exhibit`
