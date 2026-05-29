# TextMeasure.jl Demos — House Style

Single source of truth for the demo gallery (#E #F #G #H #K). All five demos MUST use
these exact values — no ranges, no per-demo drift. Authored by the design review pass
(2026-05-28), grounded in type-contrast / palette-discipline / spatial-composition /
depth / restraint principles. Coherence ≠ uniformity: a map, a magazine cover, and a TUI
should differ — but they share this spine so the gallery reads as authored, not assembled.

## 1. Type

- **Serif** (body / editorial / titles): `Liberation Serif`
- **Sans** (labels / captions / UI / stats / TUI): `DejaVu Sans`

Both are already pinned in the demos — no new font installs.

Fixed size ramp (pt) — pick the tier by role, never an in-between value:

| Tier    | pt | Role |
|---------|----|------|
| caption | 9  | footers, source lines, axis/figure captions |
| body    | 11 | paragraph prose, abstracts, column text |
| subhead | 14 | panel/section headers, stat labels, column titles |
| title   | 22 | article/panel title (e.g. DOI panel headlines) |
| display | 44 | mastheads only: VERMONT, "The Newer Yorker", main figure title |

Display-to-body contrast = **4×**; title-to-body = **2×**. Locked — do not soften.

Body sets **ragged-right** by default (no full-justify) **except #K**, whose justified
columns *are* the demo.

## 2. Palette — 3 accents + 1 gray, locked

| Name  | Hex | RGBA | Used by |
|-------|-----|------|---------|
| BLUE (neutral/data) | `#2B6CB0` | `RGBA(0.169, 0.424, 0.690, 1)` | #F citation bars + tag chips; #H skyline inset base tone |
| GREEN (good/winner) | `#1B7A3D` | `RGBA(0.106, 0.478, 0.239, 1)` | #G silhouette fill; #K K–P column label; #F green-OA label |
| RED (problem/attention) | `#C0392B` | `RGBA(0.753, 0.224, 0.169, 1)` | #H "A Correctness Exhibit" subtitle; #K river overlays |
| GRAY (captions/footers/rules) | `#6B7280` | `RGBA(0.420, 0.447, 0.502, 1)` | all footers, captions, hairline rules (alpha 0.15–1.0 per below) |

Background = pure white `#FFFFFF`. Body text = near-black `#1A1A1A` `RGBA(0.10,0.10,0.10,1)`.
These four are the ONLY accent colors. No other blues/greens/reds anywhere.

## 3. Footer (all print pieces #F #G #H #K)

- **Text**: `TextMeasure.jl · <demo name>` (middot U+00B7, single spaces) — e.g.
  `TextMeasure.jl · DOI Infographic` / `· Vermont` / `· The Newer Yorker` / `· Knuth–Plass`
- **Font/size**: DejaVu Sans, 9 pt (caption tier)
- **Color**: GRAY `#6B7280`
- **Position**: bottom-left, baseline on the inner margin line
- **Outer margin**: **36 px on all four sides** of every print piece (content inside this box)
- **TUI #E**: no px footer; reserve the bottom border row for the same string.

## 4. Caption / figure-note style

- Font: DejaVu Sans · Size: 9 pt (caption tier) · Color: GRAY `#6B7280`
- Align: **LEFT**, anchored to the left edge of the content block it describes (never page-centered)
- Leading: 1.3×
- Applies to: #K figure note, #G footer, #F per-panel DOI/source line, #H byline.

## 5. Rules / hairlines (shared)

- Hairline (separators/gutters): 0.5 px, GRAY `#6B7280` @ alpha **0.15**
- Structural rules (masthead underline, pull-quote rules): 1.0 px, GRAY @ alpha **1.0**
- Chart baselines (#F bars): 1 px GRAY @ alpha **0.25**
