<!-- SPDX-License-Identifier: MIT -->
# SPEC — #L · THE TIDE  *(was The Press / The Breathing Column)*

*A block of Whitman that **reflows as a wall presses in from rotating directions** — type kneaded
from different axes like dough. The text never moves; the **region** moves, and the prose
re-packs to fill whatever shape is left. One `prepare()`, hundreds of `shape_pack()` calls a loop,
forever.*

> **One claim:** *Measurement is cached once; re-flowing the same text into a brand-new region
> shape every frame is pure arithmetic.* The press squeezes the field; `shape_pack` re-kneads the
> dough; nothing touches the font engine after frame 0.

**Name decision.** Adopt **THE PRESS** (was *The Breathing Column*). "Breathing" implied a single
1-D width sine — a column inhaling. This piece is bigger and more physical: a *press/knead* from
**rotating axes**. "The Press" carries the metaphor (a thing that compresses), the craft (type,
printing — a *press*), and the screenshot. The old breath-only direction is **superseded** by this
spec; the verified PD source text, house values, migrating-brass-word idea, and long-exposure
thumbnail thinking are carried forward.

---

## ⚑ LOCKED DESIGN (2026-06-13 → 2026-06-14) — overrides the sections below where they conflict

Designed live with the operator across 2026-06-13/14. The **engine mechanic** in the body of this
spec stands (one `prepare`; `shape_pack` re-flows a moving region every frame; per-band justify).
The **theme, text, palette, choreography, and wall treatment pivoted completely** through live
iteration and are re-locked below (final choreography: a **6-direction counterclockwise sweep**, a
**smooth continuous swell**, **1200 frames @ 60 fps**). Where the body still says
*Whitman / "rocking" / bronze letterpress platen*, **this section supersedes it.** Still holds:
readability floors §3, wall-as-force §5, claim/honesty §1/§8.

- **THEME — the tide kneading the shore (NOT Whitman).** The text block is the *shore/sand*; the
  advancing wall is the *sea*. A warm sunset scene: the tide leans in and **kneads** the block from
  rotating sides. **Renamed "The Tide"** (it stopped being "The Press" once the theme became the
  sea); gallery verb is now **knead**, register word stays *force*.
- **TEXT — original elevated prose, set as one JUSTIFIED paragraph (no found quote).** After
  auditioning verified PD candidates (Whitman, Michelet, Ruskin, Hugo, Keats, Dickinson, Donne,
  Hopkins…), the operator chose **original authored prose** over a sourced quote — a deliberate
  trade (loses the "found-text" authenticity Woven has, in exchange for total control of rhythm).
  **Do not present it as a quotation or attribute a source.** Locked text:
  > At evening the sea comes in slow and warm, taking its time. Tide after tide it leans gently
  > against the shore and kneads—smoothing the soft sand, folding the gilded edge under, drawing
  > back in a bright hush before it comes again. Nothing it shapes will stay, and nothing needs to.
  > What the low sun gilds, the quiet dusk lets go; and the seam between water and land is traced,
  > and traced again, and left to glow a little while in copper and rose.
  Prose (no hard `\n`) means it **wraps and justifies on every line** — justify is full-time now (the
  paragraph's last line stays ragged, as normal). This resolves the verse problem where justify
  barely fired.
- **IDENTITY — sunset shore (declared palette deviation; the gallery's warm sibling).** Field
  **`#F2DFC6`** (warm dusk peach) · text **`#34232C`** (deep plum-brown, the wet shore) · accent
  **`#E37C4B`** (sunset coral — the tide-line + the one lit word). This warm/dusk temperature is
  what keeps The Tide distinct from the two *blue* water pieces (Glyph Wave, Atlas) and from
  Woven's hard vermillion-on-white. Replaces the earlier letterpress-bronze idea entirely.
- **THE WALL — a wavy coral TIDE-LINE, bare (no fill).** The advancing cut is a low-amplitude sine
  (`A ≈ 8px`, `λ ≈ 2·line_advance`) knocked into the BitMatrix, so `shape_pack` re-flows + justifies
  the prose flush to an **undulating** margin. **Cardinals (W/E)** rake a vertical wavy edge;
  **diagonals (SW/SE/NW/NE)** rake a **single straight diagonal** whose depth ramps to its deepest at
  the last line (no diagonal-to-vertical bend — the bottom is the *most* kneaded). The coral curve is
  drawn from the **known wall geometry** (not the placements), **over-long and alpha-faded to
  transparent at the block's top/bottom edges** so it reads as a much longer wave that's opaque only
  where it laps the shore — its ends never pop. On **W/E** it fades in *early* (full opacity by
  `b≈6px`, just before the text first reflows) from a slightly larger margin offset, so the tide
  visibly arrives before the text feels it; the **corners** fade where the wedge tapers shallow (so
  the line never clips the type). A *filled* sea-side wash was tried and rejected (read as a boxy
  rectangle; the bare line is more evocative). In motion the line **undulates** (phase per frame).
- **LIT WORD — `kneads`, in coral.** The single accent glyph (replaces "rocking"). Rendered with a
  **tight em-dash** (`kneads—smoothing`): the token is split at the `—` so only `kneads` is coral and
  `—smoothing` stays ink, placed flush-adjacent. It is the needle riding the knead.
- **BODY FACE — Libre Caslon Text (Old Standard dropped).** Operator picked Caslon on the page
  (darker/sturdier). Pinned at `examples/fonts/LibreCaslonText/` with PROVENANCE (instanced wght=400
  from the google/fonts variable; OFL; off Impeccable's ban list). Body 11px.
- **CAPTION — Hanken Grotesk (declared §4 deviation).** A **single** line, muted plum-gray text,
  **coral** middot, bottom-left: `TextMeasure.jl · The Tide`. The `prepare ×1 · shape_pack ×480 /
  loop` claim line was **dropped** (operator: not helpful in the still). No credit line (text is
  original, unsourced). Two of four pieces now set sans captions — the emergent thread for the
  louder siblings; registered in `demos-house-style.md`.
- **MECHANIC.** **6-direction counterclockwise sweep** `W → SW → SE → E → NE → NW` → back to rest
  (N/S dropped — text can't rake to a horizontal edge, so those beats read weak). Each press is **one
  continuous smooth swell** — `depth(u) = smootheststep(2·min(u, 1−u))` (7th-order; a flat-but-moving
  crest that eases *almost* to a stop at full reach but never literally holds, zero velocity at the
  troughs) — presses run back-to-back for a relentless ebb-and-flow. **20 s @ 60 fps = 1200 frames**
  (200/press), one `prepare`, **1200 `shape_pack` calls**; `depth==0` exactly at every trough incl.
  the loop boundary ⇒ seamless + total recede (no leftover line). Per-band justify rewrites
  `Placement.x` only — **no new engine surface**; showcased surface stays **`shape_pack`** (distinct
  from Woven's KP). Grow-to-fit the region height so the deepest bite never silently truncates words.
- **ASPECT** — page ~**3:2** (423×274 data px), trimmed from an earlier 4:3 so the block + tide fill
  the frame with little dead vertical space.
- **STILL (LOCKED)** — the SW-press peak (a true frame of the loop), at
  `examples/tide/tide-hero.png` (scale 8, sunset, verified by eye). **THUMBNAIL** (built) — the
  ghosted long-exposure: the solid SW-peak frame + a few earlier `shape_pack` SW tide-states ghosted
  behind (the coral tide-line trails + the lit "kneads" only, not the full body), at
  `examples/tide/tide-thumb.png`. **LOOP** — `examples/tide/tide-loop.mp4` (scale 4, 60 fps, CRF 18).
  Render convention: **stills scale 8, loop scale 4**.
- **GOLDEN** = hashed layout tables (MonospaceBackend, deterministic) at structurally-distinct
  frames **including ≥1 diagonal frame** so the kneaded-band justify path is pinned; never
  pixels/video bytes. Per-band justify + the wavy mask are deterministic arithmetic, hashed too.

---

## 0. The piece in one breath

A paragraph of Whitman sits on warm paper inside a soft rectangular field. From one edge, a
**wall** of negative space presses inward — the text region shrinks against it, and the prose
re-packs into the surviving L/T/narrow shape. The wall reaches full compression, **holds a beat**
(the kneaded dough, pressed flat), then releases as the *next* wall — rotated 90° — begins its
press from a new edge. Over one loop the press walks **right → bottom → left → top** and returns to
rest, so the block is kneaded from all four axes and ends exactly where it began. One word —
**"rocking"** — is lit in brass; you watch it get shoved line-to-line and shape-to-shape as the
walls knead through it. A faint brass **tide-rule** draws the live wall edge: the instrument doing
the pressing. Nothing else moves.

---

## 1. Medium & form factor

**Recommendation: a recorded, seamlessly-looping MP4 (+ a GIF derivative) authored from a Makie
scene, *shipped as a loop*, not a live window.** (Same rationale as every motion piece in the
gallery: a loop is a committable, golden-testable, screenshot-gradable artifact; a live window is
not — DESIGN.md grades the *rendered artifact*.) Provide an optional `--live` wall-clock target for
hallway demos, but the shippable deliverable is the loop. Backend for real glyphs =
`MakieBackend(px_per_unit = 1)` per CLAUDE.md.

**Honesty of the claim.** The loop is genuinely driven by per-frame re-packing: each frame calls
`shape_pack(prep, chord_fn; …)` with a *new* region mask. Assert it (frame-count test: N frames ⇒
N `shape_pack` calls, exactly one `prepare`).

---

## 2. Choreography — the full loop

| Parameter | Value | Why |
|---|---|---|
| **Period** | **12.0 s** | Four presses × ~3 s each (anticipate→press→**hold**→release). Slow enough to read as a deliberate physical knead, not a resize jitter; short enough to loop without boredom. |
| **fps** | **30** → **360 frames/loop** | Integer frames per period ⇒ seamless loop by construction (frame 360 ≡ frame 0). |
| **Loop closure** | Phase-0 = phase-2π; the 4-press walk returns the region to the identical rest rectangle | Start and end frames are *byte-identical* region masks ⇒ no crossfade, no bounce needed. |

### The four-beat press cycle (one wall = 3 s = 90 frames)

The press walks the compass in order **E → S → W → N** (right, bottom, left, top), one wall at a
time, each a self-contained anticipate/press/hold/release gesture:

```
phase within one 90-frame press (depth d ∈ [0, d_max]):
  0–15%   anticipate   d eases UP from 0 a hair, then the wall "loads" (squash-&-stretch tell)
  15–55%  press        d → d_max via smoothstep (slow-in/slow-out)
  55–75%  HOLD          d = d_max, velocity 0  ← the held breath / pressed dough — the screenshot beat
  75–100% release       d → 0 via smoothstep; as it returns to rest the NEXT wall begins anticipating
```

- **One wall at a time**, *except* a deliberate **single pinch**: on the **3rd press (W, from the
  left)**, hold a *shallow* residual wall from the top (≈25 % of `d_max`) so the region is squeezed
  from **two sides at once** for that one beat — the one moment the dough is caught in a corner.
  This is the variation that keeps four identical presses from reading mechanical; it happens once
  per loop and is the most compressed frame.
- **Easing = smoothstep** (`3t²−2t³`) on depth, **not** raw sine and **not** triangle. Smoothstep
  gives slow-in/slow-out *and* a true zero-velocity dwell at `d_max` (the **HOLD**) — the "held
  breath" that makes it read as a press, not an oscillation. (Disney's *slow in/slow out*: motion
  without easing "looks artificial"; *squash & stretch* sells weight/mass — the anticipation load +
  the held flat are exactly those two principles.)
- **Direction of travel** of the wall edge is always *into* the block then back out — never a
  random resize. Each press has a clear physical reading: a flat wall advancing, pausing against
  resistance, and withdrawing.

### How deep the wall goes (release threshold)

The wall stops at **`d_max` = the depth that leaves the region at its minimum readable size**
(§3) — it presses until the text is as tight as legibility allows, *holds there*, then releases.
It never presses past the floor (no illegible soup); the floor *is* the dramatic limit.

---

## 3. Readability under compression (the central risk)

The whole piece dies if a pressed frame becomes unreadable. Hard floors, enforced as clamps on the
region mask *before* it's handed to `shape_pack`:

| Bound | Value | Rationale |
|---|---|---|
| **Min region width** | **`floor_w` = width of 32 characters** at body size (≈ `32 × measure("0")`), never below | 32 CPL is the low end of the readable band; below ~45 CPL rhythm degrades, below ~30 it breaks. We floor at 32 so the *tightest* press still reads as prose, not a stack of fragments. Bringhurst 45–75 CPL; WCAG ≤ 80; we deliberately ride the narrow edge as the drama, but never fall off it. |
| **Min region height** | enough for **≥ 6 baselines** at the current `line_advance` | Below ~6 lines the block stops reading as a paragraph and starts reading as a label. |
| **Baseline grid** | **single fixed `line_advance`, shared across every frame & every shape** | `shape_pack(…; line_advance)` takes one advance; we pass the *same* value all loop. Lines stay parallel and on a fixed grid no matter how the wall intrudes — the press changes *which words sit on which band*, never the leading. This is the legibility anchor: the eye always has a stable grid. |
| **Lineheight** | **1.45×** body (`line_advance = 1.45 × 11 pt` in px) | Slightly open so the fixed grid reads as a grid even when lines get short and ragged under compression. |
| **`min_chord_width`** | **= `floor_w`** passed straight into `shape_pack`'s `min_chord_width` | The engine already refuses to place into a horizontal interval narrower than this; reusing our readability floor means the packer itself enforces the bound — no band ever gets a sliver too thin to hold a word. |
| **Over-wide word** | **let it honestly poke past the wall** (`overflow_strategy = :widest_row`) | Whitman has no monster words, so this is rare; when a band is momentarily too tight, the engine overflows the word rather than dropping it. We accept the poke as *honest physical behavior* — the dough resisting the press — not as a bug to hide. Never silently truncate. |

**Net:** as the wall presses, the region goes narrow/tall or short/wide, but every frame is a
real ≥32-CPL, ≥6-line paragraph on a fixed grid. The text is always Whitman you can read; the press
only re-kneads *where the words sit*.

---

## 4. The brass "rocking"

One token — **"rocking"** (the poem's own word for the motion) — is the only brass glyph; every
other word is INK. It is the **needle of the instrument**:

- **Tracking.** Tag the segment index of "rocking" pre-`prepare`; each frame, find its `Placement`
  in the returned `PackedLayout` (x, y on the fixed grid). This is demo orchestration over
  `shape_pack`'s returned `placements`, not an engine feature (§6).
- **Most visible at the HOLD.** At full compression the region is narrowest and the lines re-pack
  hardest, so "rocking" is most dramatically displaced exactly when the motion pauses — the eye has
  a still beat to find the one brass word in its new home. We choreograph so a wall's HOLD lands
  with "rocking" **shoved onto a fresh line/band** relative to rest — the screenshot moment: the
  word visibly *migrated* under the press and is now sitting alone-ish at a new altitude, lit.
- **The dramatic squeeze.** On the **left-wall press (#3, the pinch)** the region narrows enough
  that "rocking" — which sits comfortably mid-line at rest — gets pushed to **start its own band**.
  That's the beat we freeze for the still: brass word, kneaded to a new line, held.
- It returns to its rest position by frame 360, so the needle swings out and back — a measuring
  tool's pointer made of one lit word.

---

## 5. The field & composition

House spine, minimal deviation:

- **Field:** PAPER `#F4EFE6`, full bleed. The text region is a soft rectangle floating in a
  generous paper margin (**outer margin 48 px** — *declared named deviation* from the house margin,
  kept because the wall needs room to press *inward*) so the wall has room to press *inward* without
  the block ever touching the paper edge — the compression reads against paper, not against a frame.
- **The wall: REQUIRED, non-negotiable.** An **invisible** wall (text just avoids empty space)
  reads as "a paragraph randomly resizing" — it kills the piece. The brass **tide-rule** is the
  *entire device* that converts negative space into **perceived force**, so it ships: draw the live
  wall edge as a **BRASS `#9A7B4F`** *tide-rule* / press-platen edge with two tiny surveyor's ticks
  (house §5 registration motif). On the pinch frame, both active wall edges are ruled. **Budget the
  contrast so a cold viewer reads "something is pressing in" from a single still pinch frame** — even
  if that means the *active* (advancing) edge is rendered **heavier than 0.5 px**; the *inactive*
  hairlines stay in the house 0.25 / 0.5 / 0.75 px vocabulary. This is the *instrument doing the
  pressing*; it makes the negative space legible as a **force**, which is the entire metaphor.
  **Verify the wall reads as force at the visual-signoff gate.**
- **Type — body:** **Fraunces text optical size** (`Fraunces9pt-Regular.ttf`), **body 11 pt**, INK
  `#1A1714`, leading 1.45×, ragged (no justify — out of scope; raggedness *is* the visible kneaded
  surface). Align `:left` within each band (the packer's `fill = :widest`).
- **The lit word:** same face/size, **BRASS `#9A7B4F`** (drop to **BRASS-INK `#6E5226`** if
  `#9A7B4F` lacks contrast on paper) — the only non-ink glyphs.
- **Caption (Plex Mono, 9 pt, GRAY text, BRASS middot):** yes — it earns its place by stating the
  claim. `prepare ×1 · shape_pack ×360 / loop`, baseline-pinned bottom-left. Credit line in the
  same mono caption: `Walt Whitman · Out of the Cradle Endlessly Rocking · 1859` (PD — no
  permission line needed).
- **No** masthead/title — restraint; the motion is the focal element. Type ramp touched: **caption
  9 + body 11 only** (two-tier, like the rest of the gallery's quiet pieces).

---

## 6. The gallery STILL (the thumbnail)

A still can't show the knead, so **show the trace of the press** — a long-exposure:

> **The thumbnail is the pinch frame (most-compressed, two-sided) drawn SOLID in ink, with 3–4
> earlier press-states ghosted behind it** — each ghost a *real* `shape_pack` at an intermediate
> depth/direction, its wall edge faintly brass-ruled, fanning out toward rest. The ghosts read as
> the wall's path *into* the block; the solid frame is the held compression. The brass "rocking"
> appears **twice** — solid (front, in its squeezed new band) and ghosted (back, near its rest
> position) — so the eye reads the word's migration *as a path*. One lit word caught mid-knead,
> the press frozen behind it as ghosts.

GHOST styling: GRAY `#6B7280` @ alpha 0.10–0.18, increasing toward the front (structure, so gray,
not ink). Built from the same `shape_pack` calls — the thumbnail is the loop, sampled and stacked.

*Rejected:* a clean 3–4-up filmstrip (reads as "four different resizes," loses the single-block
identity and the *continuity* of a knead) and a single un-ghosted compressed frame (reads as "a
narrow paragraph," doesn't say *it moves*). The ghosted long-exposure keeps the one-block identity
*and* encodes motion + direction in a still.

---

## 7. The one bold move

> **A wall of negative space physically kneads a block of Whitman from rotating axes — the text
> re-packs to fill the surviving shape every frame, with "rocking" lit in brass riding the press
> like a needle — and the most-compressed two-sided HOLD freezes as the still: one brass word
> shoved to a new line, the press's path ghosted behind it.**

It's the screenshot-able beat *and* the thesis: measurement is cached once; the dough is re-kneaded
into a new shape 360 times a loop, live, on a fixed grid, in brass.

---

## 8. Engine mechanics + honest gaps

**In-contract:**

1. `prep = prepare(MakieBackend(font=Fraunces9pt-Regular, fontsize=11px, px_per_unit=1), TEXT)` —
   **called ONCE.** Only font-touching call; widths cached.
2. Per frame `f ∈ 0:359`:
   - `t = f/360`; derive **active wall(s)** + **depth(s)** from the four-beat smoothstep schedule
     (§2), clamped to the readability floors (§3).
   - Build the frame's **region mask** = field-rectangle **minus** the wall rectangle(s) → a
     `chord_fn` (`PolygonChordFn` for the rectilinear L/notch shapes, or `RasterChordFn` if we want
     a softer platen). The mask is the *only* thing that changes frame-to-frame.
   - `packed = shape_pack(prep, chord_fn; line_advance = 1.45×11px, min_chord_width = floor_w,
     overflow_strategy = :widest_row, fill = :widest)` — **pure arithmetic, every frame. This is
     the demo.**
   - Draw each `Placement` (segment str at x,y); brass for the "rocking" segment; draw the live wall
     hairline + ticks; redraw static caption/credit.
3. Thumbnail: pinch-frame `packed` solid + 3–4 earlier `packed`s ghosted (§6).

Everything driving the press is **the region mask into `shape_pack`** — squarely the engine's
`shape_pack(prep, chord_fn; line_advance, min_chord_width, …)` surface. No justify, hyphenation,
CJK, or rotation of glyphs (the *region* rotates which axis it's pressed from; glyphs never
rotate). Words atomic; over-wide-word-overflow handled by `:widest_row`.

**Honest gaps (orchestration on top of the engine, not library features) — flag in code:**

- **Brass-word tracking** = find the chosen segment's `Placement` in returned `placements` each
  frame. The packer returns positions; *which* one is "rocking" and lighting it brass is demo
  bookkeeping.
- **The wall schedule / smoothstep / pinch / seamless-loop / ghost compositing** = pure demo-side
  animation math (Makie `record` + Observables), zero library surface.
- **Region-mask construction** (field minus wall → chord function) = demo geometry; the engine
  consumes a `chord_fn`, it doesn't author the shape.

No new library surface — consistent with PRODUCT.md ("does not grow new library surface to look
impressive"). The piece *uses* `shape_pack` exactly as built.

---

## 9. Source text (public domain — verified)

**Walt Whitman — opening invocation of *Out of the Cradle Endlessly Rocking* (1859, public
domain).** The poem is *about* rocking, risings and fallings, the sea's pressure — the form enacts
the content, and it literally contains **"rocking"** (the brass word) and **"the fitful risings and
fallings."** No monster words ⇒ overflow stays graceful at the narrow floor. Set as one
prose-wrapped block, honoring the poet's hard line-breaks as `\n` so the packer reflows *within*
each verse-line:

```
Out of the cradle endlessly rocking,
Out of the mocking-bird's throat, the musical shuttle,
Out of the Ninth-month midnight,
Over the sterile sands and the fields beyond, where the child
leaving his bed wander'd alone, bareheaded, barefoot,
Down from the shower'd halo,
Up from the mystic play of shadows twining and twisting as if
they were alive,
Out from the patches of briers and blackberries,
From the memories of the bird that chanted to me,
From your memories sad brother, from the fitful risings and
fallings I heard,
```

(Rejected for copyright: Mary Oliver, d. 2019; Wendell Berry, b. 1934 — both in copyright. Genesis
KJV is PD but carries no breath/press metaphor.)

---

## 10. Coherence with the gallery

> The Press shares the spine — PAPER/INK/**BRASS**, **Fraunces × IBM Plex Mono**, the √2 ramp
> (caption-9 / body-11), brass-middot footer, surveyor's-tick registration. The gallery's register
> line:
>
> > Measure once, then — shape · press · erase · place — many.
>
> reads across the four siblings: The Glyph Wave = shape (image) · The Press = press (force) ·
> Erasure = erase (subtraction) · The Atlas = place (place). **The Press is text shaped by *force
> over time*** — the same cached measurement re-flowed into a moving region, the gallery's one piece
> that proves "measure once, lay out many" by literally doing the *many*, live, in brass.

---

## 11. Build notes (from the feasibility pass)

- **Build the wall mask directly — do NOT route through `Silhouettes.rasterize`.** The region is a
  rectangle minus an axis-aligned wall block; the BitMatrix is `mask = trues(nrows,ncols)` with the
  active edge's cells knocked out (≈15 lines), then `raster_chord_fn(mask, cell)` reused verbatim
  from `shape_pack.jl`. Avoiding `Silhouettes` keeps the dep set to just
  `TextMeasure` + `TextMeasureLayouts` + `Makie` — dropping the `CoherentNoise`/`DelaunayTriangulation`/
  `GeometryOps` tail, the known load-time lever. (Use `RasterChordFn`, not `PolygonChordFn`, for the
  rectilinear masks — simpler and exact for rect-minus-rect.)
- **`fill = :widest` is correct *because* every wall is flush to a field edge.** Each frame's mask is
  rectangle **minus a wall block flush to one (or, on the pinch, two) edge(s)**, so every horizontal
  band has **≤ 1 available interval** — a flush wall just shortens the band from one side; it never
  carves a hole that leaves two separate runs of open space on the same band, *including* the
  two-sided pinch (two flush walls still leave a single central interval per band). With ≤ 1 interval
  per band, "widest interval" *is* "the only interval," so `fill = :widest` fills it. **Invariant to
  hold:** if any future frame ever splits a band into two *comparable* intervals (e.g. a wall that is
  NOT flush to an edge — a free-floating notch), `:widest` would silently drop the smaller run;
  switch **that** frame to `fill = :all`.
- **Brass tracking is robust via stable `segment_index`.** `prep.segments` is fixed (prepared once);
  precompute `rocking_idx = {i : segments[i] is the word "rocking"}`, then each frame partition the
  returned `placements` by `pl.segment_index ∈ rocking_idx` into the brass `text!` group vs the ink
  group. No per-frame search; all instances of "rocking" light (the poem repeats it — reads well).
- **Reuse map:** lift `raster_chord_fn`/`RasterChordFn` and the `shape_pack` call verbatim; mirror
  the per-frame *structure* of `asteroid_tui/pack.jl` (`pack_prose_into`) but write a fresh Makie
  renderer (asteroid's `draw.jl` is terminal-`CellBuffer` only, unusable here). New code = wall mask
  generator + depth/edge schedule + Makie loop + brass partition + ghost compositing.
- **Golden = layout-table hashes at 5 structurally distinct frames** (rounded `(segment_index,
  x, y)` rows, sha256 — mirrors the asteroid golden's checksum approach): `t=0` (rest rectangle),
  and mid-press peaks for each edge `t≈N/8, 3N/8` (the **vertical** case — the risky one), `5N/8,
  7N/8`. Plus non-vacuous asserts: placements count > threshold at rest, ≥1 brass index present, and
  — **conditionally** — `!isempty(overflowed)` at peak compression (pins that graceful over-wide
  handling is exercised). **Caveat:** at `floor_w = 32 ch` Whitman has no monster words, so the
  overflow set may *legitimately* be empty and this assert would fail by correct design. Before
  committing it, **pre-check by running `layout` at `floor_w` once** to see whether any word actually
  overflows. If none does, either (a) gate the assert behind that pre-check (skip when empty), or
  (b) construct one golden frame whose band is *deliberately* narrower than the longest word so the
  overflow path is genuinely exercised — don't assert `!isempty(overflowed)` unconditionally.
- **Alignment is the one thing to eyeball, not just green-test:** `Placement.y` is a baseline in a
  y-down block-top frame; confirm `text!(space=:pixel, align=(:left,:baseline))` + the y-flip lands
  glyphs exactly where cached advances predict (brass word and body neither overlap nor gap) by
  opening one rendered frame before trusting any golden.
- **Directory:** spec lives at `examples/breathing_column/`; on build, rename to `examples/press/`
  to match the adopted name (or keep — cosmetic).

---

## References (verified)

- **Optimal line length (CPL floors):** [UXPin — 50–75 CPL / Bringhurst 45–75](https://www.uxpin.com/studio/blog/optimal-line-length-for-readability/),
  [Baymard — line length & readability](https://baymard.com/blog/line-length-readability) (WCAG ≤ 80 CPL Latin).
- **Easing / dwell / squash-&-stretch / anticipation** (slow-in/out reads natural, squash sells
  weight/mass — the press's load + held-flat): [CGSpectrum — 12 Principles of Animation](https://www.cgspectrum.com/blog/12-principles-of-animation),
  [IxDF — Disney's 12 principles for UI](https://www.interaction-design.org/literature/article/ui-animation-how-to-apply-disney-s-12-principles-of-animation-to-ui-design).
- **Kinetic typography — tasteful vs. gimmick** ("reserve kinetic type for one clear moment;
  motion must clarify, not delay meaning"): [Raw.Studio](https://raw.studio/blog/stop-scrolling-kinetic-typography-is-redefining-ux/),
  [Digital Silk — Kinetic Typography 2026 & UX risk](https://www.digitalsilk.com/digital-trends/kinetic-typography/).
- **Looping / cinemagraph craft** (short seamless loop; start ≡ end; ease at extremes, avoid
  constant velocity): [Wikipedia — Cinemagraph](https://en.wikipedia.org/wiki/Cinemagraph),
  [Dark Skies — animation loops guide](https://darkskiesfilm.com/how-to-make-an-animation-loop/).
- **Reflow / balanced-wrap vocabulary** (why ragged reflow reads; balance vs. let-it-rag): [MDN —
  text-wrap](https://developer.mozilla.org/en-US/docs/Web/CSS/text-wrap),
  [Chrome for Developers — text-wrap: balance](https://developer.chrome.com/docs/css-ui/css-text-wrap-balance).
- **Source text (PD, lines verified):** [Out of the Cradle Endlessly Rocking — Poetry Lovers'
  Page](https://www.poetryloverspage.com/poets/whitman/out_of_the_cradle_endlessly_rocking.html),
  [poets.org](https://poets.org/poem/out-cradle-endlessly-rocking).
