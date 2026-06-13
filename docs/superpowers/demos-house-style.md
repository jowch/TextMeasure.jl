# TextMeasure.jl Demos — House Style

Single source of truth for the demo gallery (#E #F #G #H #K). All five demos MUST use
these exact values — no ranges, no per-demo drift. Redesigned 2026-06-13 under
[Impeccable](https://github.com/pbakaus/impeccable) + frontend-design guidance, anchored
by [`DESIGN.md`](../../DESIGN.md) (the craft rubric) and [`PRODUCT.md`](../../PRODUCT.md)
(what each piece must prove). Supersedes the 2026-05-28 spine (Liberation Serif / DejaVu
Sans / pure-white / three co-equal accents), which read disciplined-but-generic.

**Concept: "editorial instrument."** A compositor's eye (high-contrast editorial serif)
metered by a measuring tool (fixed-pitch mono). Coherence ≠ uniformity: a map, a magazine,
and a TUI differ — but they share this spine so the gallery reads as *authored by one
hand*, exact to the pixel, memorable in one detail.

## 1. Type — two faces, contrast axis

- **Serif** (display / title / deck / body / editorial): **Fraunces** (OFL). Use its
  **display** optical size for mastheads (loud, high-contrast, light WONK) and its **text**
  optical size for body / #K columns (calmed, justifies cleanly).
- **Mono** (caption / label / stat / axis / footer / **#E TUI**): **IBM Plex Mono** (OFL).
  The fixed pitch *is* the concept — every advance exact.

**Sourcing (determinism).** Static TTFs are pinned in `examples/fonts/` (committed, with
each family's `OFL.txt`) — no system fonts, no variable-axis instances, so glyph advances and
goldens stay reproducible. **Load by file path, not family name:** these static instances
split weights/optical sizes into separate name-table families (`Fraunces 9pt`,
`Fraunces 9pt Black`, `IBM Plex Mono Medm`, …), so there is no single "Fraunces" family to
select — path-loading is the only deterministic selector. Pinned files:

- Body / small → `Fraunces/Fraunces9pt-{Regular,Italic,SemiBold,Black}.ttf` (text opsz)
- Subhead / title / deck → `Fraunces/Fraunces72pt-{Regular,Black}.ttf`
- Masthead → `Fraunces/Fraunces144pt-{Light,Regular,Black}.ttf` (display opsz)
- Mono (caption/label/stat/footer/TUI) → `IBMPlexMono/IBMPlexMono-{Regular,Italic,Text,Medium,SemiBold,Bold}.ttf`

Fixed size ramp (pt) — re-founded on **√2 (≈1.414)**, the ISO-216 paper ratio (the type
scale shares the proportion of the page it prints on). Pick the tier by role, never an
in-between value. Locked contrast anchors: **title = 2× body, display = 4× body.**

| Tier    | pt | Face | Role |
|---------|----|------|------|
| caption | 9  | IBM Plex Mono | footers, source lines, axis/figure notes (legibility floor) |
| body    | 11 | Fraunces text | paragraph prose, abstracts, column text |
| subhead | 16 | Fraunces | panel/section headers, stat labels, column titles |
| title   | 22 | Fraunces | article/panel title (e.g. DOI panel headlines) **(2× body)** |
| deck    | 31 | Fraunces | section decks / secondary display |
| display | 44 | Fraunces display | mastheads only: CALIFORNIA, "The Newer Yorker", main figure title **(4× body)** |

Display-to-body contrast = **4×**; title-to-body = **2×**. Locked — do not soften.

Body sets **ragged-right** by default (no full-justify) **except #K**, whose justified
columns *are* the demo.

## 2. Palette — two layers, OKLCH-tuned, locked

Identity comes from paper + ink + one signature; the old blue/green/red are demoted to
**data encoding only** (a bar, a winner, a correctness flag *inside* a demo), never
identity decoration.

### Identity layer

| Name | Hex | RGBA | Role |
|------|-----|------|------|
| PAPER (background) | `#FBFAF7` | `RGBA(0.984, 0.980, 0.969, 1)` | every surface — off-white stock, faint chroma toward brass. **Never `#FFFFFF`.** |
| INK (text) | `#1E1C1A` | `RGBA(0.118, 0.110, 0.102, 1)` | body / titles — warm near-black |
| BRASS (signature) | `#B5793C` | `RGBA(0.710, 0.475, 0.235, 1)` | mastheads, structural rules, footer middot, registration/measurement marks. The one color threading all five pieces. |

### Data layer (encoding-only — NOT identity)

| Name | Hex | RGBA | Used by |
|------|-----|------|---------|
| BLUE (data/neutral) | `#2E6FB5` | `RGBA(0.180, 0.435, 0.710, 1)` | #F citation bars + tag chips; #H skyline inset base tone |
| GREEN (good/winner) | `#2E7D4F` | `RGBA(0.180, 0.490, 0.310, 1)` | #G silhouette fill; #K K–P column label; #F green-OA label |
| RED (problem/attention) | `#C0432F` | `RGBA(0.753, 0.263, 0.184, 1)` | #H "A Correctness Exhibit" subtitle; #K river overlays |
| GRAY (structure) | `#6B7280` | `RGBA(0.420, 0.447, 0.502, 1)` | captions/footers body, hairline rules (alpha 0.15–1.0 per §5) |

PAPER, INK, BRASS + the four data colors are the ONLY colors. No other hues anywhere. A
data color used for identity (or off its assigned meaning) is a defect.

## 3. Footer (all print pieces #F #G #H #K)

- **Text**: `TextMeasure.jl · <demo name>` (middot U+00B7, single spaces) — e.g.
  `TextMeasure.jl · DOI Infographic` / `· California` / `· The Newer Yorker` / `· Knuth–Plass`
- **Font/size**: IBM Plex Mono, 9 pt (caption tier)
- **Color**: text in GRAY `#6B7280`; the **middot in BRASS** `#B5793C` (the signature's
  smallest appearance)
- **Position**: bottom-left, baseline on the inner margin line
- **Outer margin**: **36 px on all four sides** of every print piece (content inside this box)
- **TUI #E**: no px footer; reserve the bottom border row for the same string (mono, ink on
  paper-equivalent cell, brass middot).

## 4. Caption / figure-note style

- Font: IBM Plex Mono · Size: 9 pt (caption tier) · Color: GRAY `#6B7280`
- Align: **LEFT**, anchored to the left edge of the content block it describes (never page-centered)
- Leading: 1.3×
- Applies to: #K figure note, #G footer, #F per-panel DOI/source line, #H byline.

## 5. Rules / hairlines (shared)

- Hairline (separators/gutters): 0.5 px, GRAY `#6B7280` @ alpha **0.15**
- Structural rules (masthead underline, pull-quote rules): 1.0 px, **BRASS `#B5793C` @ alpha
  1.0** (the signature does the structural work; reserve GRAY @ 1.0 for non-signature rules)
- Chart baselines (#F bars): 1 px GRAY @ alpha **0.25**
- Registration / measurement marks (optional per piece): BRASS, 0.5 px — crop-mark /
  surveyor's-tick motif reinforcing the "instrument" concept. Use sparingly; restraint over
  decoration.
