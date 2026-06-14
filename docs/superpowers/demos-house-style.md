<!-- SPDX-License-Identifier: MIT -->
# TextMeasure.jl Demos — House Style

**Single source of truth for the greenfield demo gallery** — *The Glyph Wave · The Press ·
Erasure · The Atlas*. Every piece MUST use these exact values: no ranges, no per-demo drift.
A Julia constants module (`examples/_housestyle/`) mirrors this file verbatim; pieces import the
module rather than re-typing hexes. **If a value here and the module ever disagree, that is a bug.**

*Supersedes the prior five-piece house style (#E/#F/#G/#H/#K, Liberation Serif / DejaVu Sans /
white bg). The old gallery and its `PRODUCT.md`/`DESIGN.md` rubric are retired; the canonical
design doc for this gallery is `docs/superpowers/specs/2026-06-13-demo-gallery-greenfield-design.md`.*

Coherence ≠ uniformity: a painting-in-type, a kinetic press, a redacted document, and a map should
*feel* different — they share this spine so the gallery reads as authored by one hand, not assembled.

## 0. The canonical register line (quote verbatim in every SPEC)

> **Measure once, then — shape · press · weave · place — many.**

| Piece | Verb | Register word |
|---|---|---|
| The Glyph Wave | shape | *image* |
| The Press | press | *force* |
| Woven | weave | *two readings* |
| The Atlas | place | *place* |

## 1. Type

- **Serif** (display, mastheads, editorial body, the kept words): **Fraunces** — select the right
  **optical size by file path** (display opsz for mastheads, text opsz for body), and the right
  **weight** (Light/Regular/Medium/SemiBold/Bold/Black). Add the two missing OFL statics (Medium,
  Bold) to `examples/fonts/` for the Glyph Wave's 6-step ramp.
- **Mono** (labels, captions, stats, axis ticks, footers, the Erasure redaction field + toy, the
  Atlas place-labels): **IBM Plex Mono**.

Both families are pinned under `examples/fonts/`. Body sets **ragged-right** (no justify — out of
engine scope).

### Fixed √2 size ramp (pt) — pick the tier by role, never an in-between value

| Tier | pt | Role |
|---|---|---|
| caption | 9 | footers, source lines, captions, axis/graticule ticks, the metrics readout |
| body | 11 | paragraph prose, abstracts, column text, the Atlas necklace labels |
| subhead | 16 | section/panel headers, the Erasure kept words, major-settlement labels |
| title | 22 | region/section titles |
| deck | 31 | decks |
| display | 44 | mastheads only |

Display-to-body contrast = **4×**; title-to-body = **2×**. Locked — do not soften. (Caption 9 is
the documented floor; do **not** use 8.)

## 2. Palette

### Identity layer (carries every piece)

| Name | Hex | Role |
|---|---|---|
| **PAPER** | `#F4EFE6` | the off-white field (NEVER `#FFFFFF`, never `#FBFAF7`) |
| **INK** | `#1A1714` | warm near-black — body, primary contour |
| **BRASS** | `#9A7B4F` | the signature — mastheads' structural rule, hairlines that carry meaning, the footer middot, the Press's lit word + tide-rule, the Atlas hero dot + leaders |
| **BRASS-INK** | `#6E5226` | brass-coloured **text/marks** where `#9A7B4F` is too light on paper (small labels, a lit word needing more contrast). Same hue, darker — a *role*, not a new colour. |

### Data layer (encode ONLY — never identity work)

`BLUE #2E5E8C` (data) · `GREEN #3E7A54` (good) · `RED #A33A2A` (problem) · `GRAY #6B7280`
(structure/captions). Used only to encode meaning; never as a piece's identity colour.

### Named palette deviations (declared, per the supersede rule)

- **The Glyph Wave** flies the painting's own flag: `prussian #1B3A5B · foam #EDE6D6 · indigo
  #5E7A9B · snow #B9C2C9 · boat #C8A36B` (the 5 Hokusai inks). The masthead/footer keep BRASS.
- **The Atlas** uses a water layer: fill `#DCE3E5`, hairline `#9FB2BA`. Land = PAPER, coast = INK.

## 3. Hairlines & rules

Stroke vocabulary is exactly **0.25 / 0.5 / 0.75 px**, plus a **1.0 px BRASS** structural rule
(masthead underline, neat-line). 0.75 px is reserved for the single most important contour
(the Atlas coastline). Meaningful hairlines are BRASS; neutral separators are GRAY.

## 4. Footer & margins

- **Footer text:** `TextMeasure.jl · <piece>` (middot U+00B7) — e.g. `· The Glyph Wave` / `· The
  Press` / `· Erasure` / `· The Atlas`. IBM Plex Mono, **caption 9 pt**, BRASS middot, GRAY text,
  baseline on the inner margin, bottom-left. Motion pieces carry it in a caption line; no separate
  rule.
- **Outer margin:** **36 px** on print/still pieces. *Named deviation:* The Press uses a **48 px**
  field margin so the wall has room to press inward without the block touching the paper edge.

## 5. Determinism & sign-off (shared discipline)

- **Golden = hash the computed layout/placement table** (deterministic, machine-independent), never
  the rendered pixels or video bytes (Cairo/ffmpeg are not byte-stable). The MonospaceBackend stays
  the deterministic test backend. Mirror `asteroid_tui`'s golden harness.
- **Green ≠ visual sign-off.** Every piece's definition of done includes the operator opening the
  actual PNG/MP4 and confirming it matches the claim.
