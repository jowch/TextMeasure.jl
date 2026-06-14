<!-- SPDX-License-Identifier: MIT -->
# SPEC — The Glyph Wave

*Gallery piece · register: **image**. An input painting reproduced entirely in measured type:
each word run's size, weight, and colour is taken from the tone beneath it, so Hokusai's
**Great Wave** emerges from readable prose. Reads as text at arm's length; as the wave across
the room.*

Status: **refined, pre-plan.** Consolidates three research passes (tone-mapping algorithm,
Julia image pipeline, Makie rendering + text provenance). All external facts verified; URLs at
foot.

## The one bold move (checkable)

> Every word stays a real, in-order word of a continuous passage. The image is built **only**
> by re-weighting / re-sizing / re-colouring that prose against a silhouette mask — never by
> breaking, rotating, warping, or reordering type. You can read the whole text top-to-bottom,
> and the Great Wave is unmistakable at squint distance.

This is what separates it from a word-cloud: **frequency is irrelevant; position-in-painting is
everything**, and the text stays literature you can read. Acceptance tests (binary):
1. **Reading test** — concatenating placements in returned order reproduces the source verbatim
   (only optional faint-sky thinning may drop runs, and only as a flagged subset; also exempt
   any `overflowed`-flagged runs, since `:widest_row` over-wide handling perturbs reading order
   — a second source beyond faint-sky thinning — *or* assert `overflowed` is empty for the
   chosen text/sizes).
2. **Squint test — HARD merge gate (not advisory).** Downsample the render to 64 px wide + blur;
   the claw + Fuji silhouette must be identifiable (mask IoU vs a reference silhouette ≥ threshold).
   This gate must pass to merge.
3. **No-mud test** — every word is collinear: `sign(weight_rank−mid) == sign(size_bucket−mid)
   == sign(ink_darkness−median)`. No dark-ink/light-weight or pale-ink/heavy-weight words.
4. **Baseline test** — all baselines lie on the uniform `line_advance` grid (no vertical jitter).

## Source

Hokusai, *Under the Wave off Kanagawa* (the Great Wave), the Met, **object 45434, CC0 /
public-domain** (verified via the Met API: `isPublicDomain: true`). Commit a downsized asset —
`examples/glyph_wave/assets/great_wave.png` (downsample `primaryImageSmall`
`…/web-large/DP130155.jpg`, 188 KB) + an `assets/SOURCE.txt` (object id, CC0, URL, date). Do
**not** fetch at build (hermetic/CI), do **not** commit the 2.3 MB original.

## Pipeline (all orchestration — does **not** touch the engine)

### 1. Image → tone fields
JuliaImages stack: `FileIO`/`ImageIO` (load), `Images`/`ImageTransformations` (`imresize`),
`Colors` (`Lab`, `colordiff`), `IntegralArrays` (summed-area table). Arrays index `[row,col] =
[y,x]`, **y-down — same convention as `line_top`**, so no y-flip when aligning to the canvas.
- **Luminance** `lum = Float64.(Gray.(work))` (Rec.601 luma on gamma-encoded sRGB — the
  perceptual ink/foam map we want).
- **Summed-area table** `iL = IntegralArray(lum)` → O(1) box-mean luminance for thousands of
  run-boxes (`iL[i0..i1, j0..j1]/n`). The cost mitigation that makes per-run sampling cheap.
- **Palette — hardcode 5 inks, snap in CIELAB.** `prussian #1B3A5B · foam #EDE6D6 · indigo
  #5E7A9B · snow #B9C2C9 · boat #C8A36B` (tune against the committed master). Snap sampled
  colour to nearest ink by `colordiff(·,·; metric=DE_AB())` on precomputed `Lab`. (k-means
  extraction kept as an **offline** sanity script, not a runtime dep — woodblock-scan noise
  drifts clusters.)
- **Mask (BitMatrix for `RasterChordFn`)** — `mask = lum_grid .< INK_CUTOFF` (start `0.62`,
  tune by eye; foam-claws + upper-left sky are brightest → become holes → text only flows in
  ink). One canonical `canvas_px→image_px` scale via normalized `[0,1]²` coords keeps mask,
  sampler, and canvas in agreement.

### 2. Layout — hybrid `shape_pack` flow + per-run sampling
Running prose flowed by `shape_pack`/`RasterChordFn` into the wave silhouette, each emitted
`Placement` assigned size/weight/colour from the painting at its centre. Reading order is
preserved by construction (`shape_pack` returns left-to-right, top-to-bottom). `fill=:all`
(wrap both sides of the trough/Fuji negative space), `overflow=:widest_row`.

**Merged-`Prepared` plumbing — the RISKIEST Glyph Wave unknown; prototype FIRST.** `shape_pack`
honours ONE `FontMetrics`/`line_advance` for *all* placements, so a merged `Prepared` can carry
per-**segment** widths (each word measured from its assigned size bucket) but only a **single**
`FontMetrics`. The round-trip — hand-construct that merged `Prepared` and flow it through
`shape_pack` cleanly — is the riskiest unknown in the whole piece and must be prototyped ahead of
everything else, including the `fontsize`-as-vector probe. Explicit build task: hand-construct the
merged `Prepared` with per-segment widths drawn per bucket and a single `FontMetrics` whose
`line_advance = lineheight × size_max`. **Vertical-air tradeoff (stated):** one
`line_advance = size_max` gives small words extra vertical air — an *airy grid* — which we accept
(uniform baseline pitch is non-negotiable; see §3).

**Measure-at-chosen-size (critical):** a run's advance scales with fontsize, so:
1. Quantise size into **K=4 buckets**; `prepare(backend, text)` once per bucket (4 prepares —
   the engine's "measure once" honoured).
2. **Pre-pass** dry-run `shape_pack` at median size → nominal (x,y) per word → sample luminance
   → assign each word its bucket *before* the real pack.
3. **Real pack** flows the merged `Prepared` above (per-segment width from each word's assigned
   bucket; single `FontMetrics`, `line_advance = lineheight × size_max`) so tall buckets never
   collide.

### 3. Tone ramp
- **Weight = primary tone carrier** (the typographic analogue of ASCII ink-density ramps);
  **size = secondary, compressed.** Response curve `d = (1−L)^γ`, **γ≈0.45** (perceptual, not
  linear). Snap colour first, then derive `d` from the *snapped ink's* luminance so hue and tone
  agree (the anti-mud rule).
- **Weight steps → Fraunces statics.** Ideal ramp = 6 (Light·Regular·Medium·SemiBold·Bold·
  Black); **only 4 are pinned today** (Light·Regular·SemiBold·Black across 3 opsz in
  `examples/fonts/`). → **open decision below.** Fallback genuinely held in reserve if interior
  tone washes out: posterize to **3 steps** (Light/SemiBold/Black, γ→0.7) + 4×4 Bayer dither on
  the weight-bucket boundary (typographic halftone, no extra size variance). **We will ship a
  crisp 3-tone over a muddy 6-tone if it comes to it** — clarity of silhouette beats nominal
  ramp depth.
- **Size:** `size_min 13 pt → size_max 21 pt` (ratio **1.6**, capped — size whispers, weight
  shouts), 4 buckets. `lineheight = 1.0`, uniform baseline grid (non-negotiable; wobbling
  baselines are the #1 word-cloud tell).

### 4. Render (Makie)
`MakieBackend(px_per_unit=1)`; `space=:pixel`, `markerspace=:pixel`, manual axis limits.
- **Group runs by weight → one `text!` per weight (~4 calls)**, vectorising position/text/colour
  (per-glyph colour vector is documented). `font` is **scalar per call** → select a static
  weight by **file path** per group (Makie has no variable-font axis selection — confirmed). A
  per-run-loop of `text!` is the one thing to avoid.
- ⚠ **`fontsize`-as-vector is unconfirmed** in the pinned Makie — 1-line empirical test before
  relying on per-run sizing inside a weight group; if it fails, sub-group by (weight × size
  bucket) → ≤16 calls, still cheap.
- **PNG, not SVG** (SVG embeds every glyph path → blows up). Target **3000×2000** (3:2),
  `px_per_unit` set explicitly (CairoMakie `save` defaults to 1).
- **Golden test = hash the computed per-run layout table** `(font,x,y,fontsize,colour,str)`
  **before rendering** — deterministic, machine-independent, and it tests the actual engine
  output. **Do NOT** sha256 the PNG (Cairo/FreeType output is not byte-stable across machines).
  Treat the PNG as a visually-verified artifact (open it — green ≠ visual sign-off).
- Performance: 2–6 k runs as ~4 vectorised calls → single-digit-second draw, ~1–5 MB PNG
  (order-of-magnitude; benchmark on the build machine).

## The text (copyright-checked)

Hokusai's credo, postscript to *One Hundred Views of Mount Fuji* (1834). **The famous lyrical
wording is Smith 1988 — IN COPYRIGHT. Do NOT use it.** Use the **PD E. F. Strange, 1906**
translation (translator d. 1929; no notice):

> "At the age of six I had a fancy for reproducing form; for fifty years I made many book
> illustrations, but even at seventy I had little skill. Only when I reached the age of
> seventy-three did I begin to understand how rightly to represent animals, birds, insects,
> fish, plants. At ninety I shall be better; at a hundred I shall be sublime; at a hundred and
> ten I shall give life to every line, to every dot. Let no one mock at these words!"

The credo (~95 words) is the **focal legible passage** (verified clean). **Bulk-fill** the rest
of the canvas drawing **only from E. F. Strange-1906's own public-domain prose** — its body text,
thousands of words — seeded so lines aren't identical. **Never** lift an in-copyright passage that
Strange merely *quotes inside* his book; pull from his own prose, not his quotations. (Japanese
original is PD; a fresh paraphrase is also legal if a more lyrical cadence is wanted.)

## Aesthetic & coherence

**Named deviation:** *#GlyphWave flies the painting's own flag* — abandons paper/ink/brass for
Hokusai's Prussian-blue-and-foam palette (declared, the way #G declares California). It still
belongs: every gallery piece is one body of meaningful text laid out with measured type —
Whitman's breathing press, the MIT-license erasure, the California atlas — this is that same
spine pointed at an image instead of a page.

**Register line (canonical):**

> Measure once, then — shape · press · erase · place — many.

with: The Glyph Wave = shape (image) · The Press = press (force) · Erasure = erase (subtraction)
· The Atlas = place (place).

## Honest engine-vs-orchestration line

**Engine (in-contract):** `prepare`/`measure` (exact advances, no kerning, matches Makie),
`shape_pack`/`RasterChordFn`, per-run size/weight/colour (Makie paints). **Orchestration (we
write):** image load + summed-area sampling, the luminance→size/weight + colour-snap mapping,
the foam mask, the size-bucket merge. **No out-of-contract asks** — zero glyph rotation/warp,
no justify, no CJK. No new core-library surface.

## Difficulty & risk

**M.** Riskiest unknown = the **merged-`Prepared` round-trip** (per-segment widths under a single
`FontMetrics` flowed through `shape_pack`) — prototyped FIRST (§2, build step 0) before anything
else. Next: legibility-vs-fidelity tuning; mitigated because the mask silhouette carries
recognizability even if interior tone is soft, with the posterize+dither fallback genuinely in
reserve (we ship crisp 3-tone over muddy 6-tone if needed). Secondary: Makie draw time/file size
at high run count (vectorise + PNG).

## Decisions

1. **Tone-ramp depth — DECIDED: 6-step.** Add 2 intermediate Fraunces OFL static weights
   (Medium ~500, Bold ~700) to the 4 already pinned → clean 6-step Light→Black ink ramp. Build
   step: source the two static `.ttf` from the Fraunces OFL family, drop them in
   `examples/fonts/`, register their paths in the weight ramp. Posterize+Bayer-dither stays as
   the interior-washout fallback only.

### Still to confirm during build
- `fontsize`-as-vector in the pinned Makie (1-line empirical test) before locking per-run
  sizing inside a weight group; if it fails, sub-group by (weight × size bucket) → ≤16 `text!`
  calls. **Sequence this probe AFTER the merged-`Prepared` prototype** (§2) — the round-trip is
  the riskier unknown and gates whether per-run sizing is even reachable.

## Build sequence (for the plan)

0. **Merged-`Prepared` prototype FIRST (riskiest unknown):** hand-construct a merged `Prepared`
   (per-segment widths per bucket; single `FontMetrics`, `line_advance = lineheight × size_max`)
   and prove it flows through `shape_pack` cleanly — ahead of the `fontsize`-as-vector probe.
1. `assets/` fetch script + committed master + `SOURCE.txt`.
2. Image module: load → luminance + summed-area table → palette snap → mask.
3. Tone-map module: pre-pass sampling → per-word (size bucket, weight, colour), with the
   collinearity + acceptance-property checks.
4. Pack module: K-bucket prepares → merged `Prepared` (per step 0) → `shape_pack`.
5. Render module: group-by-weight `text!` → PNG; layout-table hash golden. (`fontsize`-as-vector
   probe lands here, only after step 0.)
6. Tune constants against the committed master (visual sign-off, not just green).

## Sources

- Met object 45434 (CC0, verified): https://collectionapi.metmuseum.org/public/collection/v1/objects/45434 · https://www.metmuseum.org/hubs/open-access
- Strange 1906 (PD credo): https://archive.org/details/hokusaioldmanmad00strauoft
- Bourke, ASCII grey-scale ramps: https://paulbourke.net/dataformats/asciiart/
- Harri, *ASCII characters are not pixels*: https://alexharri.com/blog/ascii-rendering
- Colors.jl colour differences: http://juliagraphics.github.io/Colors.jl/stable/colordifferences/
- IntegralArrays.jl: https://github.com/JuliaImages/IntegralArrays.jl
