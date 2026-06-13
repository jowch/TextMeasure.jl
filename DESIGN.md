<!-- SPDX-License-Identifier: MIT -->
# DESIGN.md — Craft rubric for the demo gallery

*Scope: the five-piece gallery (#E #F #G #H #K). This is the **scoring rubric** the
design-reviewer subagent applies. It sits on top of two documents and never contradicts
them silently:*

- [`docs/superpowers/demos-house-style.md`](docs/superpowers/demos-house-style.md) — the
  **locked constants** (type ramp, palette, footer, hairlines). These are hard values.
- [`PRODUCT.md`](PRODUCT.md) — the **one claim** each piece must make tangible.

**Supersede rule:** a piece MAY deviate from a house-style constant only if this file names
the specific value, the piece it applies to, and *why* the deviation serves the claim. An
unexplained deviation is a defect, not a choice.

## North star

> **Authored by one hand, exact to the pixel, memorable in one detail.**

The gallery is the proof that a *measurement* library measures correctly. Therefore the
overriding aesthetic value is **earned exactness**: every alignment looks deliberate because
it is computed, not nudged. Restraint over decoration. One bold move per piece, executed
precisely, beats five timid ones. Coherence ≠ uniformity: a TUI, a magazine, and a map
should *feel* different while sharing the spine.

This is **editorial/print-compositor** discipline, not dashboard or "AI-slop" aesthetics.
Banned on sight: Inter/Roboto/Arial/system-font defaults, purple-on-white gradients, evenly
distributed timid palettes, centered-everything layouts, drop-shadow soup, emoji as
iconography.

## How to score (for the reviewer)

Score the **final rendered artifact's screenshot** — not the mockup, not the code — on each
of the five axes below, 0–10. **PASS requires ≥ 8 on every axis.** A single axis < 8 fails
the piece and forces another iteration. For each axis, cite the specific pixel/region that
drove the score; "looks nice" is not a score.

Anchor points: **10** = a working compositor would ship it. **8** = ships, with a nit you
had to hunt for. **6** = a literate viewer notices something off in 2s. **≤ 4** = the claim
is undermined (looks like the measurement is wrong).

### Axis 1 — TYPE
Type ramp obeyed exactly (caption 9 / body 11 / subhead 16 / title 22 / deck 31 / display
44 pt — the √2 scale; no in-between sizes). Display-to-body 4×, title-to-body 2× contrast
held. Correct face per role: **Fraunces** (display optical size for mastheads, text optical
size for body / #K columns) for serif roles; **IBM Plex Mono** for captions, labels, stats,
axis ticks, footers, and the #E TUI. Body ragged-right except #K. **Fails < 8 if:** an
off-ramp size appears, contrast is softened, Fraunces/Plex-Mono roles are swapped, the wrong
Fraunces optical size is used (display opsz in body, or text opsz in a masthead), or
rivers/widows/orphans mar a column.

### Axis 2 — PALETTE
Two layers honored. **Identity** = PAPER off-white (never `#FFFFFF`) + INK warm near-black +
BRASS signature; brass carries mastheads, structural rules, and the footer middot. **Data**
= BLUE/GREEN/RED/GRAY used ONLY to encode (BLUE=data, GREEN=good, RED=problem,
GRAY=structure), never for identity. Alpha values for hairlines/rules as specified.
**Fails < 8 if:** a pure-white surface appears, any unlisted hue shows up, a data color does
identity work or is used off-meaning, the signature brass is absent from a piece, or a
rule's weight/alpha/color is eyeballed instead of spec.

### Axis 3 — COMPOSITION
36 px outer margin on print pieces; content sits on a visible underlying grid; alignments
are exact (shared baselines, flush edges, true optical centering where used). The one bold
spatial move (asymmetry, overlap, a dominant masthead) is intentional and balanced.
**Fails < 8 if:** an element is a few px off its grid line, margins drift, or the layout is
inert/centered-by-default with no point of view.

### Axis 4 — RESTRAINT / HIERARCHY
One clear focal point; the eye knows where to land first. No decoration that doesn't carry
information. Negative space is used as a material. **Fails < 8 if:** two elements compete for
first read, or anything is ornamental-only (a gradient, a shadow, a chip that means nothing).

### Axis 5 — FINISH
The pixel-level tell that the measurement is exact: chip widths hug their text, bars end
where their labels do, silhouette prose kisses the boundary with no overflow/no gap, TUI
cells align, footer baseline sits on the inner margin line. **Fails < 8 if:** any seam,
half-cell, 1px misalignment, clipped glyph, or "almost lines up" is visible at 1× zoom.

## Per-piece design direction (the one memorable move)

These are the bold-but-disciplined directions each piece commits to. The reviewer checks the
piece *delivers* its move, not merely that it's inoffensive.

- **#E Asteroid TUI** — *living type.* The memorable thing is prose that visibly **reflows
  as the silhouette rotates** and **fractures on a word boundary** on impact. Phosphor-CRT
  restraint: near-black field, accents only for state. Motion must read as physics, not
  decoration. (TUI exempt from px footer; bottom border row carries the footer string.)
- **#F DOI Infographic** — *data you can measure with a ruler.* The move is bars and chips
  whose lengths are visibly text-derived; a reader could verify a width by eye. BLUE data,
  GRAY structure.
- **#G California Silhouette** — *text as the shape.* The move is prose filling the
  California outline so the negative space *is* the state, GREEN fill, with the boundary
  hugged flush.
- **#H The Newer Yorker** — *print fidelity.* The move is a masthead-led editorial spread
  ("A Correctness Exhibit", RED data-subtitle) with a skyline inset, holding a real
  magazine's baseline discipline. Display-44 masthead (ink wordmark over a brass structural
  rule) is the single focal point.
- **#K Knuth–Plass** — *the honest justify.* The move is optimal-fit justified columns with
  even colour and controlled rivers (RED river overlay as the diagnostic), the only piece
  that earns full-justify because correct measurement makes it possible.

## What "done" looks like

Every piece: claim from `PRODUCT.md` legible at a glance, ≥ 8 on all five axes from an
independent reviewer, golden test green, and the five sitting together as one authored set.
