<!-- SPDX-License-Identifier: MIT -->
# HouseStyle — shared gallery spine

The single source of truth for the gallery's look — *The Tide · Woven · The Atlas* — paired
with the `HouseStyle` Julia module that encodes these values as constants. Each piece depends on
the module by path so colours / ramp / fonts / footer come from ONE place. **If a value in this
doc and the module ever disagree, that is a bug.** `test/runtests.jl` is the executable guard —
it pins the palette, ramp, font paths, footer, and digest against this doc.

Coherence ≠ uniformity: a kinetic press, a redacted document, and a map should *feel* different —
they share this spine so the gallery reads as authored by one hand, not assembled.

## Using the module

In a piece's `Project.toml`:

    [deps]
    HouseStyle = "f1a9b3c2-0d4e-4a6b-9c8d-7e2f1a0b3c4d"

    [sources]
    HouseStyle = { path = "../_housestyle" }

Then `using HouseStyle` and reference `HouseStyle.PAPER`, `HouseStyle.RAMP.body`,
`HouseStyle.fraunces("9pt-Regular")`, `HouseStyle.plexmono()`, `HouseStyle.footer("Woven")`,
`HouseStyle.digest_rows(rows)`.

Nothing is exported by design — always use the qualified `HouseStyle.X` form. `using HouseStyle: PAPER`
will not work, and that is intentional: the qualifier keeps every borrowed value visibly sourced from the spine.

## 0. The canonical register line

> **Measure once, then — knead · weave · place — many.**

| Piece | Verb | Register word |
|---|---|---|
| The Tide | knead | *force* |
| Woven | weave | *two readings* |
| The Atlas | place | *place* |

## 1. Type

- **Serif** (display, mastheads, editorial body, the kept words): **Fraunces** — select the right
  **optical size by file path** (display opsz for mastheads, text opsz for body), and the right
  **weight** (Light/Regular/Medium/SemiBold/Bold/Black).
- **Mono** (labels, captions, stats, axis ticks, footers, the Atlas place-labels): **IBM Plex Mono**.

Both families are pinned under `examples/fonts/`. Body sets **ragged-right** (no justify — out of
engine scope).

### Fixed √2 size ramp (pt) — pick the tier by role, never an in-between value

| Tier | pt | Role |
|---|---|---|
| caption | 9 | footers, source lines, captions, axis/graticule ticks, the metrics readout |
| body | 11 | paragraph prose, abstracts, column text, the Atlas necklace labels |
| subhead | 16 | section/panel headers, major-settlement labels |
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
| **BRASS** | `#9A7B4F` | the signature — mastheads' structural rule, hairlines that carry meaning, the footer middot, the Tide's lit word + tide-rule, the Atlas hero dot + leaders |
| **BRASS-INK** | `#6E5226` | brass-coloured **text/marks** where `#9A7B4F` is too light on paper (small labels, a lit word needing more contrast). Same hue, darker — a *role*, not a new colour. |

### Data layer (encode ONLY — never identity work)

`BLUE #2E5E8C` (data) · `GREEN #3E7A54` (good) · `RED #A33A2A` (problem) · `GRAY #6B7280`
(structure/captions). Used only to encode meaning; never as a piece's identity colour.

### Named palette deviations (declared, per the spine rule)

- **The Tide** flies a *sunset-shore* flag: field `#F2DFC6` (warm dusk peach) · text `#34232C`
  (deep plum-brown) · sunset coral `#E37C4B` for the wavy tide-line + the lit word "kneads". Body
  face is **Libre Caslon Text** (not Fraunces). Theme = the tide kneading the shore; warm/dusk so it
  stays distinct from the blue water of The Atlas.
- **The Atlas** uses a water layer: fill `#DCE3E5`, hairline `#9FB2BA`. Land = PAPER, coast = INK.
  Its editorial serif (masthead "The Atlas" + water/hydrography labels) is **Newsreader** (italic
  for water), not Fraunces — the one pinned family outside the Fraunces/Plex Mono spine besides the
  Tide's Libre Caslon and the chrome's Hanken Grotesk.
- **Woven** flies a *type-specimen* flag: off-white `#F6F6F4` · near-black `#161616` · vermillion
  `#C8341F`; chrome in **Hanken Grotesk**.

## 3. Hairlines & rules

Stroke vocabulary is exactly **0.25 / 0.5 / 0.75 px**, plus a **1.0 px BRASS** structural rule
(masthead underline, neat-line). 0.75 px is reserved for the single most important contour
(the Atlas coastline). Meaningful hairlines are BRASS; neutral separators are GRAY.

## 4. Footer & margins

- **Footer text:** `TextMeasure.jl · <piece>` (middot U+00B7) — e.g. `· The Tide` / `· Woven` /
  `· The Atlas`. IBM Plex Mono, **caption 9 pt**, BRASS middot, GRAY text, baseline on the inner
  margin, bottom-left. Motion pieces carry it in a caption line; no separate rule. *Named
  caption-face deviation:* the **louder pieces set captions in Hanken Grotesk** — Woven (chrome) and
  The Tide (caption + credit, bronze middot). The quiet pieces keep Plex Mono.
- **Outer margin:** **36 px** on print/still pieces. *Named deviation:* The Tide uses a **48 px**
  field margin so the wall has room to press inward without the block touching the paper edge.

## 5. Determinism & sign-off (shared discipline)

- **Golden = hash the computed layout/placement table** (deterministic, machine-independent), never
  the rendered pixels or video bytes (Cairo/ffmpeg are not byte-stable). The MonospaceBackend stays
  the deterministic test backend.
- **Green ≠ visual sign-off.** Every piece's definition of done includes the operator opening the
  actual PNG/MP4 and confirming it matches the claim.
