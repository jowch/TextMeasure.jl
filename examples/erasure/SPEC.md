# ERASURE — a poem hiding in the Terms of Service

A blackout / found-poem demo for TextMeasure.jl. A page of real source prose is laid
out by the engine; all but a handful of words are struck out with solid ink bars; the
survivors — frozen in their **exact measured positions** — read top-to-bottom as a poem.
The hook is the double-take: *there is a poem inside the legal boilerplate*, and it was
already there, sitting at those coordinates, before we redacted anything.

---

## 1. Medium — **BOTH** (recommended)

Ship two things off one core:

1. **Hero static render** (the gallery piece): one perfected found poem, rendered to
   **SVG + PNG + PDF** via the FreeType/Makie backend with real Fraunces × Plex Mono
   glyphs. This is the screenshot. It is curated, not generated — one poem, made to land.
2. **Interactive tap-to-keep toy** (the "play"): the same source page rendered with the
   **MonospaceBackend** to a grid-aligned terminal/SVG field; clicking a word toggles it
   between *kept* and *blacked*. The poem (kept words, in reading order) updates live in a
   margin readout. Lets a visitor discover *their own* poem in the same ToS.

Why both: the static render proves the craft; the toy proves the mechanism is real and
cheap (every toggle is a redraw over **already-cached geometry** — no re-measure). The
monospace toy is also deterministic, so it doubles as the golden-tested artifact.

**Interactive loop** (toy):
```
load source text ──► prepare(backend, text)        # measure once
                 ──► layout(prep; max_width, :left) # geometry once
   ┌─────────────────────────────────────────────┐
   │ render field: every word in place;           │
   │   kept = ink on brass underlay               │
   │   blacked = solid ink bar                     │
   │ user clicks word w  ──► toggle kept[w]        │  ← O(1), no measure/layout
   │ recompute poem = kept words in reading order  │
   │ repaint margin readout                        │
   └─────────────────────────────────────────────┘
```
Nothing in the loop calls the font engine again. That is the whole point of measure-once.

---

## 2. Blackout visual language

Surveyed four idioms:

| idiom | reference | fit here |
|---|---|---|
| **Solid ink bars (redaction)** | declassified-document / FOIA aesthetic | **CHOSEN.** Hard rectangles. Reads instantly as "censored." Sits perfectly on exact word rects — the bar *is* `[x, x+width]`. |
| Marker scribble | Austin Kleon, *Newspaper Blackout* (2010) | Beautiful but hand-drawn/organic; fights the engine's crisp geometry and the brass/ink house style. Use only as a texture accent, not the primary. |
| Connective routes/boxes | Kleon's later style; *A Humument* (Tom Phillips) | Adopt the **idea** (guide the eye word→word) without the painterly overlay. |
| Dimming to ghost | Mary Ruefle, *A Little White Shadow* (white-out) | Too soft; loses the redaction punch and the high-contrast screenshot. |

**Decision: solid ink redaction bars + a thin brass "reading thread."** This marries
the FOIA/redaction look (instantly legible, screenshot-strong, geometry-native) with
*A Humument*'s connective gesture (the eye is *led* through the survivors).

**A blacked word** renders as a solid `ink` rectangle covering exactly the word's run:
`x` → `x + word.width`, vertically `baseline − ascent` → `baseline + descent` (i.e. the
full line band), with a 1px ink bleed at each end so adjacent bars on a line merge into
one continuous censor bar (this is the authentic redacted-line look). Spaces between two
blacked words are filled too; spaces adjacent to a kept word are left paper.

**A kept word** renders as Fraunces ink glyphs sitting on a soft **brass underlay**
(a rounded brass rectangle, ~8% opacity fill + brass hairline) sized to the word rect +
2px padding. It reads as "spared / illuminated," not censored.

**The reading thread**: a thin (1px) brass curve connects the trailing edge of each kept
word to the leading edge of the next kept word *in reading order* (left-to-right, then
down to the next line) — a hand-routed-looking Catmull-Rom through the kept-word anchor
points. This is the *A Humument* eye-guide, rendered as brass. It makes the poem's path
through the page physically visible: the survivors are beads, the thread is the poem.

---

## 3. Source text + the composed poem

Two candidates, both real and legal. **Candidate A is recommended** (the ToS angle is the
strongest single joke and is on-genre for the project's own world).

### Candidate A (RECOMMENDED) — the MIT License

Public domain–equivalent, ships in half the repos on earth, and *this project's own
LICENSE* — so the demo redacts the very text that governs it. Source paragraph (verbatim,
the standard MIT permission + warranty clauses):

> Permission is hereby granted, free of charge, to any person obtaining a copy of this
> software and associated documentation files (the "Software"), to deal in the Software
> without restriction, including without limitation the rights to use, copy, modify,
> merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
> permit persons to whom the Software is furnished to do so. THE SOFTWARE IS PROVIDED "AS
> IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED. IN NO EVENT SHALL THE AUTHORS BE
> LIABLE FOR ANY CLAIM, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE.

**Kept words, in reading order** (each appears in the source above, in this order):

> **Permission** · **granted** · **to deal** · **without restriction** ·
> **to use** · **modify** · **merge** · **distribute** · **the Software** ·
> **without warranty** · **of any kind** · **the authors** · **liable** ·
> **arising from** · **the Software**

Reads as:

> *Permission granted: to deal*
> *without restriction —*
> *to use, modify, merge, distribute*
> *the Software*
> *without warranty of any kind,*
> *the authors liable*
> *arising from the Software.*

The found poem turns a liability *disclaimer* into a tiny anxious confession — the license
swears it owes you nothing, and the survivors quietly admit the authors are *liable,
arising from the Software*. The boilerplate was hiding the opposite of what it says.

### Candidate B — *Frankenstein* (Mary Shelley, 1818, public domain)

From Chapter 4, Victorian-novel register (à la *A Humument*). Source (verbatim):

> It was on a dreary night of November that I beheld the accomplishment of my toils. With
> an anxiety that almost amounted to agony, I collected the instruments of life around me,
> that I might infuse a spark of being into the lifeless thing that lay at my feet. I saw
> the dull yellow eye of the creature open; it breathed hard, and a convulsive motion
> agitated its limbs.

**Kept words, in reading order:**

> **dreary night** · **I beheld** · **anxiety** · **almost** · **agony** ·
> **a spark of being** · **the lifeless thing** · **open** · **it breathed**

Reads as:

> *dreary night, I beheld —*
> *anxiety almost agony —*
> *a spark of being*
> *the lifeless thing*
> *open; it breathed.*

Genuinely eerie, on-genre for erasure's literary tradition. But it lacks the wink; the ToS
piece is funnier *and* shows the engine doing something practical, so A wins for the hero.

> Use **A** for the gallery hero; ship **B** as a second built-in source the toy can switch
> to (the literary register shows the medium isn't a one-joke pony).

---

## 4. The one bold move + why exact position matters

**Bold move:** render the *entire* MIT License page, fully redacted into a wall of solid
black censor bars — a convincing FOIA-leak texture — and let **only the ~15 survivors**
glow on their brass underlays, strung on the brass reading thread. From across the room it
reads as a redacted government document; up close, a poem. One image, two readings.

**Why exact position is load-bearing here (the engine doing real work):** the survivors
must sit at *precisely* the coordinates they occupied in the original paragraph — same
line, same x, same baseline — or the illusion collapses. "deal" has to be exactly where
"deal" was; the brass thread only looks hand-routed because it threads real, non-uniform
gaps. If positions were faked or re-flowed, the bars wouldn't tile into clean censor lines
and the kept words wouldn't align with the holes punched in them. TextMeasure guarantees
this: the blacked-out layout and the survivor layout are **the same layout** — we draw the
bars and the kept glyphs from one geometry pass, so a survivor is, by construction, in its
original measured spot. The redaction and the poem are the same coordinate system.

---

## 5. Aesthetic

Shared house spine (paper / ink / brass; Fraunces × IBM Plex Mono).

- **Field / paper:** warm paper `#F4EFE6`; generous margins; one column, `max_width`
  ≈ 60–66 ch of body. Faint deckle/paper grain optional (texture, not content).
- **Body (the source, → ink bars):** **IBM Plex Mono**, **body 11** / `lineheight 1.5`.
  Monospace is the correct redaction face — it makes the censor bars rhythmic and even,
  the way a real typewritten-then-redacted document looks, and it's the literal face of
  the interactive grid toy.
- **Kept words:** **Fraunces** (optical display, **subhead 16**, weight 500–600),
  `ink` `#1A1714` on the brass underlay. The serif survivors lifting out of the monospace
  redaction field is the entire visual thesis: *art rising out of machinery*.
- **Brass `#9A7B4F`** is reserved for the **kept-word underlay + the reading thread**
  only — brass = "this word survived." Never on the bars. This makes brass mean *spared*,
  consistent with the gallery's brass-as-accent rule.
- **Masthead:** small Plex Mono caps — `ERASURE — found in the MIT License` — plus a
  faux file stamp (`DECLASSIFIED` / `EXHIBIT A`) in brass to push the redaction gag.
- **Margin readout** (toy): the kept words re-set cleanly as the poem, Fraunces, so the
  hidden poem and the buried poem appear side by side.

Yes — **kept words get the brass accent** (underlay + thread). That is the device that
distinguishes survival from censorship.

---

## 6. Engine mechanics + honest gaps

**Calls used (all in-contract):**
```julia
prep = prepare(backend, source_text)          # measures every run once, NO kerning
lay  = layout(prep; max_width, align=:left)    # greedy wrap; left-align is required (see note)
# per line: line.str, line.width, line.x, line.baseline, line_top(lay, line)
# block:    lay.size, lay.metrics (ascent/descent/line_advance)
```

**Honest gap — there is no per-word accessor, and the demo must derive it.**
`layout` joins each line's runs into a single trimmed `Line.str`/`width`; it does **not**
expose an x/width per word. The prompt's "you know the exact x/width of every word"
overstates the public API. But the geometry *is* recoverable in-contract, because
`layout` is pure left-to-right accumulation of the cached `Segment` widths with **no
kerning**:

- `prep.segments` is the ordered `:word`/`:space`/`:newline` run list, each with its exact
  measured `width`.
- The demo re-walks that same sequence with the *same greedy rule* `layout` uses (it's ~40
  lines, reproduced in the demo's `pack.jl`-style helper) to assign each word a
  `(line_index, x0, x1)`. Because there is no kerning and `align=:left`, the accumulated x
  for a word equals exactly the x `layout` would place it at — they share the arithmetic.
  The re-walk **must reproduce `layout`'s per-line whitespace trim** — the pending-space
  handling that drops leading/trailing spaces at each line's start and end — or the
  blacked-bar tiling drifts by a space-width at line edges (a kept word at a line edge
  would land a space off its hole). To guarantee the two arithmetic paths can't silently
  diverge, a **golden assertion** checks the re-walk's per-word line assignment *agrees
  with* `layout(prep).lines`: same line count, and the trimmed `Line.str` reconstructed
  from the words the re-walk assigns to each line equals `layout`'s `Line.str` for that
  line, line for line.
- `x1 = x0 + word.width`; vertical band = `[line_top, line_top + ascent + descent]` from
  `line.baseline` / `lay.metrics`. That rect is the blackout bar; that anchor is the kept
  word.

> **Constraint:** the survivor-position guarantee holds for **`align=:left`** only. With
> `:center`/`:right` the per-word x still derives from the line's `x` offset + prefix sum,
> but the hero piece is specified left-aligned (it's a "document"), so this is exact and
> simple. Document this in the demo, don't paper over it.

**What the engine does NOT do (curation is not measurement):** choosing *which* words to
keep is **authoring/curation**, not an engine capability. The hero poem (§3) is
hand-curated. The toy's selection is the user's clicks. An optional tiny generative
heuristic for "surprise me" (clearly labeled non-engine): walk words left→right/top→down,
keep a word with probability `p` (≈0.06), with a soft rule to avoid two kept words
touching and to bias toward content words (skip a short stop-word list) — this is the
*subtractive procgen* idea behind mkremins' generator, ported as ~15 lines of demo code.
It produces *a* poem, rarely *the* poem; the hero stays curated. **The toy must default to
revealing the curated hero poem first** — "surprise me" is a secondary action the visitor
opts into, so a garbage random poem can never undercut the hero on first contact. Also out
of engine scope and deliberately not used: justify, CJK, hyphenation, glyph rotation.

**Before locking the hero render**, verify on a rendered line that adjacent blacked runs
*plus the inter-word space between them* tile into **one continuous censor bar** — i.e. no
slivers of paper show between consecutive bars (the 1px ink bleed + filled inter-blacked
spaces from §2 must actually close every gap).

---

## 7. Coherence note

Same spine as the final four:

> Measure once, then — shape · press · erase · place — many.

The **Glyph Wave** = *shape* (image): it shapes text by an image's tone. **The Press** =
*press* (force): it presses one prepared text into a moving region over time. **Erasure** =
*erase* (subtraction): it erases from a fixed grid to reveal meaning. **The Atlas** = *place*
(place): it places labels by measured extent. Four verbs over one shared paper-ink-brass,
Fraunces × Plex Mono identity, each showing a different thing *measure-once, lay-out-many*
buys you.

---

## References (verified)

- Austin Kleon, *Newspaper Blackout* (2010) — daily newspaper + permanent marker; eliminate
  the words you don't need. https://austinkleon.com/newspaperblackout/
- Mary Ruefle on blackout/erasure (white-out method, *A Little White Shadow*, 1889 source).
  https://austinkleon.com/2020/03/23/mary-ruefle-on-the-joy-of-blackout-poetry/ ·
  https://www.wavepoetry.com/products/a-little-white-shadow
- Tom Phillips, *A Humument: A Treated Victorian Novel* (over W. H. Mallock's *A Human
  Document*, 1892) — connective routes between surviving words.
  https://www.tomphillips.co.uk/works/humument · https://en.wikipedia.org/wiki/A_Humument
- Max Kreminski (mkremins), *blackout* — bookmarklet turning any web page into procedurally
  generated blackout poetry (subtractive procedural generation).
  https://mkremins.github.io/blackout/ · https://github.com/mkremins/blackout
- Blackout poetry (overview). https://en.wikipedia.org/wiki/Blackout_poetry
