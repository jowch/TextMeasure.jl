<!-- SPDX-License-Identifier: MIT -->
# Demo Gallery — greenfield redesign

*Design doc for a four-piece demo gallery for TextMeasure.jl. Supersedes the prior
five-piece gallery (#E/#F/#G/#H/#K), which was competent-but-generic: each old piece rendered a
*result* while hiding the constraint it had to satisfy, so nothing read as exact and nothing was
memorable. This gallery throws that out and starts from "make a beautiful or genuinely useful
**object** that happens to be powered by measure-once / lay-out-many," with the engine invisible
underneath.*

Per-piece detail lives in each piece's own `examples/<piece>/SPEC.md`; this doc is the spine, the
shared infrastructure, the dependencies, and the build/test plan that ties them together.

## 1. What the gallery is for

The README claims TextMeasure.jl is a backend-agnostic *measure-once, lay-out-many*, exact text
layout engine. The gallery makes you **believe** it — not by proving exactness with `Δ=0.0px`
readouts (too technical; the old gallery's failure was the opposite — generic), but by making
objects whose beauty or usefulness is only possible *because* the measurement is exact, with the
proof living in the craft.

Two audiences, both served: the **design-literate browser** (judges craft in two seconds) and the
**skeptical graphics/Julia engineer** (trusts the code if the artifacts look hand-assembled and
exact). The Atlas in particular doubles as a real-world credibility proof: it runs on the author's
own **MakieTextRepel.jl**, a genuine downstream consumer of the measurement contract.

## 2. The four pieces — one spine, four registers

Each piece makes one capability tangible as a real artifact; together they spell the tagline.
Coherence is by **shared house style** (§3), not uniformity — a film, a painting, a redacted
document, and a map should *feel* different.

| Piece | Register | The object | What it proves | Detail |
|---|---|---|---|---|
| **The Glyph Wave** | *image* | Hokusai's *Great Wave* rendered entirely in tone-mapped type | text conforms to a shape; per-run size/weight/colour from an image (`shape_pack`) | `examples/glyph_wave/SPEC.md` |
| **The Press** | *force / time* | Whitman kneaded by a wall pressing from rotating axes (looping MP4) | one `prepare`, `shape_pack` re-laid every frame into a moving region | `examples/breathing_column/SPEC.md` |
| **Erasure** | *subtraction* | the project's own MIT License redacted to a found poem (+ interactive toy) | exact per-word position from `prep.segments`; survivors stay anchored | `examples/erasure/SPEC.md` |
| **The Atlas** | *place* | a zoom-dive over the California coast, labels placed live as you fall in | measure once, re-place every frame — driven by the viewport (MakieTextRepel) | `examples/atlas/SPEC.md` |

> **Measure once, then — wave · press · erase · place — many.**

Two of four are looping motion pieces (Press, Atlas — both 12 s / 360-frame seamless loops), two are
stills (Glyph Wave; Erasure hero), with Erasure also shipping an interactive monospace toy.

### Per-piece capsule (full detail in the linked SPECs)

- **The Glyph Wave** — hybrid `shape_pack` flow + per-run sampling; **weight** carries tone
  (6-step Fraunces ramp — *decided: add Medium + Bold OFL statics*), **size** whispers (13–21pt,
  capped 1.6×), **colour** snaps to 5 Hokusai inks, all kept collinear (anti-mud). Met CC0 image
  committed as a downsized asset; summed-area table for O(1) per-run sampling. Text = the
  **PD Strange-1906** Hokusai credo (the famous Smith-1988 wording is in copyright — avoided).
  Golden = hash the per-run layout table, not the PNG. *Named palette deviation: flies the
  painting's own flag.* Difficulty M.
- **The Press** — a wall presses in from a rotating edge (E→S→W→N), the BitMatrix mask loses those
  cells, `shape_pack` re-kneads Whitman into what's left. Built directly (no `Silhouettes` → short
  dep tail). 12 s loop, smoothstep with a held beat + one two-sided pinch; readability floored at 32
  CPL / 6 lines on a fixed baseline grid; "rocking" lit in brass via stable `segment_index`. Still =
  long-exposure with the press's path ghosted. Difficulty M.
- **Erasure** — hero static (Fraunces survivors on brass underlays + a brass reading thread, over a
  wall of ink redaction bars) + an interactive monospace tap-to-keep toy (every toggle redraws over
  cached geometry — the measure-once proof, and deterministic so it's the golden artifact). Exact
  per-word x derived by re-walking `prep.segments` under `:left` (no kerning → shares `layout`'s
  arithmetic; there is no per-word accessor). Curated found poem; "surprise me" heuristic is clearly
  non-engine. Difficulty S.
- **The Atlas** — zoom-dive on MakieTextRepel (already reactive: animate axis limits → re-solve every
  frame for free). **Geometric (log-width) zoom for constant perceived velocity + smoothstep
  ease-in-out per half** → seamless loop (see §3 easing note). LoD by pop/rank with hysteresis +
  sticky placement to damp reshuffle. 10m Natural Earth coastline (PD) + a **curated, source-tagged
  `towns.csv`** (NE lacks the hero coastal towns — *decided: curate honestly*). Plain `Axis` + a
  `cos φ0` affine (no GeoMakie). Golden = per-frame placement-table hashes at 6 sampled frames.
  Difficulty M.

## 3. The shared spine (house style)

All four obey `docs/superpowers/demos-house-style.md`: **PAPER** off-white (never pure white) +
warm **INK** near-black + **BRASS** signature; **Fraunces** (serif display/text optical sizes) ×
**IBM Plex Mono** (labels/captions/the toy); the **√2 type ramp** (9·11·16·22·31·44pt, no in-between
sizes); brass-middot footer; the 0.25/0.5/0.75px hairline vocabulary. Data colours (blue/green/red/
gray) only ever encode, never do identity work.

**Named deviations** (declared, per the supersede rule): the Glyph Wave flies Hokusai's
Prussian-blue/foam palette; the Atlas uses a slate-blue water fill. Both are subject deviations, not
spine breaks — same fonts, ramp, and brass signature hold.

**Easing convention for both motion pieces:** geometric/log interpolation of the animated quantity
(view-width for the Atlas; wall-depth is already perceptually linear for the Press) + `smoothstep`
ease so velocity is zero at loop endpoints → seamless, non-nauseating loops. Never linear.

## 4. Shared infrastructure (build once)

1. **House-style module** — the locked constants as Julia values (colours, font paths, the √2 ramp,
   footer/caption helpers), so coherence is by construction. Extract from the existing demos' shared
   style code.
2. **Render + golden harness** — Makie → PNG/SVG/PDF for stills, `record()` → MP4/GIF for loops, and
   the **golden discipline**: hash the *computed layout/placement table* (deterministic,
   machine-independent), never the rendered pixels/video bytes (Cairo/ffmpeg aren't byte-stable). The
   monospace backend stays the deterministic test backend. Mirror `asteroid_tui`'s golden harness.
3. **Fonts** — add two Fraunces OFL static weights (Medium ~500, Bold ~700) to `examples/fonts/` for
   the Glyph Wave's 6-step ramp; everything else uses the already-pinned Fraunces + Plex Mono.

## 5. Dependencies & assets

- **MakieTextRepel.jl** (the author's own MIT package; sibling-path dep) — the Atlas's label placer.
- **JuliaImages** stack (`Images`, `Colors`, `ImageTransformations`, `IntegralArrays`) — Glyph Wave
  image pipeline.
- **GeoJSON.jl** + `GeoInterface` + `CSV.jl` — Atlas basemap (no GeoMakie).
- **Committed assets** (hermetic build, no fetch): Met CC0 Great Wave (downsized PNG); clipped 10m
  Natural Earth coastline/land GeoJSON + curated `towns.csv`; all with a `SOURCE.txt` provenance
  note. Per-demo `Manifest.toml` stays gitignored (Project.toml + instantiate only).
- **No new core-library surface.** Every piece is a consumer under `examples/`; the engine is
  unchanged. Justify / CJK / hyphenation / glyph-rotation remain out of scope and unused.

## 6. The engine-vs-orchestration line (honesty)

Each piece states, in code and caption, what the engine does vs what the demo writes:
- **Engine:** `prepare`/`measure` (exact advances, no kerning, matches Makie), `layout`,
  `shape_pack`/`RasterChordFn`, per-run size/weight/colour via Makie.
- **Orchestration (ours):** Glyph Wave's image sampling + tone→type mapping; the Press's wall
  schedule + mask; Erasure's word curation + segment re-walk; the Atlas's camera + LoD + basemap. The
  Atlas adds a third honest layer: **MakieTextRepel places** (not part of TextMeasure), the **demo
  drives the camera** (not part of MakieTextRepel).

## 7. Build & review plan

Recommended sequence (the actual task-by-task plan comes from `writing-plans`):
1. **Shared infrastructure first** (§4) — house-style module + render/golden harness + the 2 font
   weights. This is the foundation all four lean on.
2. **Erasure as the vertical slice** (difficulty S, fully in-contract) — proves the shared harness
   end to end with the least other risk.
3. **The other three in parallel** — each independent, under its own `examples/` dir, on its own
   branch (the established one-branch-per-demo pattern).

**Per-piece definition of done:** golden test green (layout/placement-table hash); the
design-reviewer scores the *rendered artifact* ≥8 on every house-style axis; and — per standing
practice — the operator **opens the actual PNG/MP4 and visually signs off** (a green test is not a
visual sign-off). Each motion piece also passes a 3-frame stub for its riskiest unknown (the Press:
`Placement`→Makie baseline/anchor mapping; the Atlas: reactive re-solve timing under `record`).

## 8. Open items carried into the plan

- Glyph Wave: confirm `fontsize`-as-vector in the pinned Makie (else sub-group by weight×size bucket).
- The Press: `Placement`→`text!(space=:pixel)` baseline/anchor + y-flip — eyeball one frame before
  trusting goldens; optional directory rename `breathing_column/` → `press/`.
- Erasure: ship hero + interactive toy (recommended) vs hero only; build-then-judge the brass reading
  thread.
- The Atlas: reactive-solve timing under `record` (strategy A vs B); finalize the curated town list.
