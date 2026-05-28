# Demos Milestone — TextMeasure in action

**Date:** 2026-05-28
**Status:** Brainstorming complete; awaiting user review.
**Branch:** `worktree-demos-milestone-brainstorm`

## Summary

Four demos — one terminal action game and three CairoMakie print artifacts — that exercise TextMeasure.jl's `prepare`/`layout` split across two backends. The library gains two small additions (`Prepared` segment-slice constructor and a built-in `FigletBackend` exemplary teaching artifact). Everything else lives in `examples/`, each demo with its own `Project.toml`/`Manifest.toml` pointing at TextMeasure via `Pkg.develop` — the main package's dependency list stays clean.

## Motivation

TextMeasure has no shipped demos. The library's selling point — *measure once, lay out many times* — is invisible until you watch the same `Prepared` consumed by many downstream layouts. The chosen demos exercise this in escalating ways:

1. **Tachikoma ASCII Asteroid Blaster** — `prepare` once per asteroid at spawn; `shape_pack` re-runs at ~5–7Hz as it tumbles; word-boundary fracture at impact re-packs subranges of the same `Prepared` into new shard silhouettes. The ship's HUD is itself a shape-packed block of physics state, re-packed every frame as values update.
2. **CairoMakie DOIInfograph** — adaptive paper-cover generator that handles arbitrary DOIs gracefully (title autoshrink, author packing-to-overflow, TLDR autosize, abstract reflow around a hero figure). Measurement is invisible-but-essential plumbing. The demo loop is *the diversity of papers all looking composed in the same template*.
3. **CairoMakie State Atlas Page** — state polygon filled with prose narrating its stats. Same `shape_pack` as the asteroid game, applied to genuinely irregular geometry. Shape-pack is visibly load-bearing because state silhouettes have no rectangular fallback.
4. **CairoMakie "Newer Yorker" cover** — deliberate-flourishes typographic exhibit (drop caps, text-around-illustration). The taste-piece; shape-pack visible by design.

(Stretch) **Knuth–Plass Justification Comparison** — port of pretext.js's `justification-comparison` demo. Two layout algorithms consuming the same `Prepared.segments`, side-by-side with river overlays. Makes "measure once, lay out many ways" literal.

## Non-goals

This milestone deliberately omits:

- **Justification in the library itself.** Knuth–Plass lives in `examples/layouts/`, consumed by demos. CLAUDE.md's exclusion stands.
- **Hyphenation, UAX-#14 line-breaking, CJK, bidi, rotation in the layout API.** All out of scope per CLAUDE.md.
- **PDF figure extraction.** DOIInfograph uses scraped `og:image` as the figure source; full pdffigures2-style extraction is downstream.
- **Authentication for closed-access papers.** Graceful degradation: missing abstract → use Semantic Scholar `tldr`; missing figure → use a geometric placeholder seeded by DOI hash.
- **Tachikoma sixel/kitty pixel-graphics mode.** Demo lives entirely in monospace cell mode; FigletBackend supplies variable-width measurement at the cell level.

## Architecture

### Library additions

Two small additions to TextMeasure proper:

**`Prepared` segment-slice constructor.** Today `Prepared(segments, metrics)` is the only entry. We add `Prepared(metrics, segments)` (positional, exposed) plus `Base.getindex(prep::Prepared, r::AbstractUnitRange) -> Prepared` returning a new `Prepared` over a segment subrange, preserving `metrics`. Motivation: `examples/layouts/shape_pack.jl` and the asteroid demo's word-boundary fracture both need to lay out subranges of an already-measured paragraph without re-measuring.

**`FigletBackend`** — new built-in (zero-dependency) backend, following the same in-tree pattern as `MonospaceBackend`. Pure-Julia `.flf` parser. 4–6 bundled figlet fonts (`standard`, `small`, `mini`, `banner`, optionally `lean`, `slant`). Implements `measure` (cell width = sum of per-character glyph widths + letter_gap) and `font_metrics` (in cells). The implementation file is heavily commented as a teaching artifact — referenced from the `AbstractMeasurementBackend` docstring as the canonical "how to write a backend" example.

### Shared utilities (downstream, in `examples/`)

`examples/layouts/` — layout algorithms that consume `Prepared.segments`:

- `shape_pack.jl` — `shape_pack(prep, chord_fn; line_advance, min_chord_width=24) -> Vector{(seg, x, y)}`. Pretext.js-validated per-band scanline: intersect line-band with chord function, pick widest run per band, greedy fit pre-measured segments, drop slivers below `min_chord_width`. `chord_fn(y) -> Vector{(left, right)}` is the only shape contract.
- (Stretch) `knuth_plass.jl` — optimal whole-paragraph line breaks via the 1981 K-P algorithm. Consumes the same `Prepared.segments`; emits line breaks instead of layout placements (consumer composes with its own rendering).

`examples/silhouettes/` — procedural shape generators:

- `asteroid_polygon(rng; n=12, lumpiness=0.4)` via polar Perlin noise (CoherentNoise.jl).
- `voronoi_shatter(polygon, impact; n_shards)` via DelaunayTriangulation.jl seeded near impact, clipped to parent with GeometryOps.jl.
- `rasterize(polygon, cell_size)` for the TUI demo.

### Per-demo structure

Each demo lives in `examples/<demo>/` with its own `Project.toml` / `Manifest.toml`. TextMeasure is depended on via `Pkg.develop(path="../..")`. Demo-specific dependencies (Tachikoma, CairoMakie, HTTP, etc.) never enter TextMeasure's own dependency graph. Each demo gets a short `README.md` explaining how to run it.

## Issues

Issues #A–#I are in scope for this milestone. #J is a stretch issue, shipped only if appetite remains after #I.

### #A — `Prepared` segment-slice constructor (library)

Add the positional constructor `Prepared(metrics::FontMetrics, segments::Vector{Segment})` (currently only the field-order constructor is auto-generated by the struct) and `Base.getindex(prep::Prepared, r::AbstractUnitRange) -> Prepared`. Test in `test/test_types.jl` and `test/test_prepare.jl`.

**Acceptance:**

- `prep[1:end] == prep` semantically (same metrics, same segments).
- Slicing at a word boundary, calling `layout` on both halves, confirms widths sum back correctly (fracture-style test).
- No new public exports.

**Effort:** ~0.5 day. **Blocks:** #C, #E.

### #B — `FigletBackend` (library, built-in, exemplary)

New `src/figlet.jl` containing the `FigletBackend` struct, keyword constructor `FigletBackend(; font="small", letter_gap=0)`, `measure`, and `font_metrics`. Pure-Julia `.flf` parser in `src/figlet_parser.jl`. Bundle 4–6 fonts as static assets under `src/figlet_fonts/` (raw `.flf` files); parse at first use, cache per-process.

**Implementation file is heavily commented** — every nontrivial choice gets a sentence explaining why. Referenced from `AbstractMeasurementBackend`'s docstring: "See `src/figlet.jl` for an end-to-end example of building a backend without an external dependency."

**Acceptance:**

- Deterministic test widths for known strings against each bundled font.
- Passes whatever backend conformance tests exist (including `measure_bounds` if applicable — Figlet glyphs have a 1-D advance, so `measure_bounds` is trivially `(width, ascent+descent)`).
- README backends section updated to list `FigletBackend`.
- `test/test_figlet.jl` mirrors the pattern of `test/test_monospace.jl`.

**Effort:** ~2–3 days incl. font bundling. **Blocks:** #E.

### #C — `examples/layouts/shape_pack.jl`

Reusable shape-conforming layout. Algorithm: pretext.js-validated per-band scanline (see `wrap-geometry.ts` in the pretext.js repo). Interface: `shape_pack(prep, chord_fn; line_advance, min_chord_width=24) -> Vector{(segment, x, y)}` where `chord_fn(y) -> Vector{(left, right)}` is the only shape contract. Pure arithmetic over `prep.segments`; no rendering.

Includes two `chord_fn` constructors as helpers:

- `polygon_chord_fn(polygon)` — scanline intersection of a 2-D polygon.
- `raster_chord_fn(raster)` — for cell-grid silhouettes (Tachikoma).

**Acceptance:**

- Pack into rectangle of width `w` produces same line breaks as `layout(prep; max_width=w)`.
- Pack into circle (smoke test on known font + text).
- Pack into concave U-shape; slivers below `min_chord_width` are dropped.
- Word wider than any chord at any row is detected; default is render at widest row, caller flag can reject.

**Effort:** 2–3 days. **Blocks:** #E, #F, #G, #H.

### #D — `examples/silhouettes/`

Three exports: `asteroid_polygon`, `voronoi_shatter`, `rasterize` as described under Architecture.

**Acceptance:**

- Smoke tests on shape validity (CCW orientation, simple polygons, no self-intersections).
- `voronoi_shatter(poly, pt; n=4)` returns 4 polygons whose union equals `poly` within numerical tolerance and whose pairwise intersections are zero-measure.

**Effort:** 1–2 days. **Blocks:** #E.

### #E — Tachikoma ASCII Asteroid Blaster (`examples/asteroid_tui/`)

**Visual direction (locked through brainstorming):**

- **Ship silhouette: Arwing** — wedge nose, swept-back wings, thruster glyphs at base. Physics state (x, y, φ, v) packed via `shape_pack` into the wedge interior. Re-packed every frame as values update.
- **Asteroid silhouettes: varied** — dagger, crescent, lumpy potato, multi-lobed peanut. Generated per spawn from `asteroid_polygon`. Descriptive prose packed inside.
- **Stat tags above each asteroid** in flipped-bracket format: `┌─ d:142m  ETA:3.4s  v:0.21µ ─┐`. Single-line, ends point down.
- **Beam: onomatopoeia** (`PEW` repeated) length-scaled to (gun → target) distance: `floor(dist / measure(b, "PEW "))`.
- **Charge: 5 stages**, asterisk at ship tip growing from `·` → `*` → `─*─` → `\*/` → full sunburst over hold time ~0.15s → ~1.5s. Beam length on release scales with charge.
- **Respawn:** ship blows up on hit; respawns with ~2s invulnerability at ~3Hz blink, intangible, player can reposition during the window.
- **Debug overlay (`?`):** every measured word's bbox drawn in cyan.

**Mechanics (locked):**

- Asteroids rotate at angular velocity sampled from `[-0.4, +0.4]` rad/s. Silhouette re-rasterizes every ~5 frames; `shape_pack` re-runs against the new cell raster; word widths in `Prepared` are reused (no re-measurement).
- Word-boundary fracture on impact: find the placed segment nearest impact, snap back to start of its `:word`, slice the `Prepared` at that index, re-pack each half into a child silhouette (Voronoi shatter seeded at impact).
- Each asteroid carries a prose template drawn from a pool of ≥50 descriptions (procedurally varied: class × material × callsign × spin rate).
- **No HP/ammo system.** Death is binary: hit → explode → respawn.

**Crayons.jl is not used.** Tachikoma handles ANSI colors natively in its own renderer.

**Acceptance:**

- Hit one asteroid, observe legible split into two shard-prose chunks (no orphaned words).
- ≥30fps on a 120×40 terminal during steady-state play with ~5 asteroids.
- Debug overlay correctly highlights every measured word.
- Respawn flash + invulnerability works as described.

**Effort:** ~1 week. **Depends:** #A, #B, #C, #D.

### #F — CairoMakie DOIInfograph (`examples/doi_infograph/`)

**Visual direction (locked through brainstorming):**

- **Layout:** top strip (journal + date + OA-status glyph), body section split — text column LEFT (title autoshrink → authors with overflow-to-"et al." → drop-cap abstract → TLDR pull-quote → concept pill strip), hero figure FULL-HEIGHT pillar on the RIGHT, bottom strip (cites + sparkline + pp + DOI).
- **Adaptive measurement work:** title autoshrinks via binary search over `measure(b, title)` against the title box; authors pack until the running width overflows, then "et al." appears; TLDR autosizes to fill its box; concept pills wrap naturally.
- **Body justification uses K-P internally** (`examples/layouts/knuth_plass.jl` from #J if shipped, else greedy `layout`). Demo prefers K-P when present.
- **Citation sparkline** uses Unicode block characters; its length is chosen to match the measured width of the surrounding "N cites" label.

**Data layer:**

- Primary: OpenAlex (`https://api.openalex.org/works/doi:{DOI}?mailto=…`). Reconstruct abstract from `abstract_inverted_index` (flatten, sort by position, join).
- Fallback: CrossRef for references and as backup metadata.
- Semantic Scholar (`/graph/v1/paper/DOI:{DOI}?fields=tldr,…`) for the TLDR pull-quote.
- Hero figure: scrape `og:image` from the publisher page (Springer, PLOS, eLife expose it reliably). Fallback: a geometric placeholder seeded by DOI hash.
- **Graceful degradation:** missing abstract → enlarge TLDR into the abstract slot; missing figure → placeholder; missing authors → "Anonymous".

**API:** `infograph(doi::String; template=:editorial) -> CairoMakie.Figure`. `save("out.pdf", fig)` produces the print artifact.

**Pluto notebook wrapper** (`examples/doi_infograph/Demo.jl`): DOI text input, live render, `@bind page_width Slider(...)` reflows the layout, "Export PDF" button.

**Acceptance:**

- Three real DOIs (Sycamore quantum supremacy, Attention Is All You Need, one PLOS OA paper) all produce legible, composed infographics.
- Title autoshrink fires (verifiable: Sycamore renders smaller than Attention in the same title box).
- Author overflow fires (Sycamore: "et al." appears; Attention: all 8 names fit).
- Sparkline length matches measured caption width within ±1 glyph.
- PDF exports cleanly (vector text, no rasterization).

**Effort:** ~1 week. **Depends:** #C. **Optional:** consumes `examples/layouts/knuth_plass.jl` from #J if shipped.

### #G — CairoMakie State Atlas Page (`examples/state_atlas/`)

`atlas_page(state_polygon::Vector{Point2}, stats::Dict{Symbol,Any}) -> CairoMakie.Figure`.

State silhouette (real geometry from US-states shapefile via `Shapefile.jl` / `GeoMakie.jl`) is filled with prose narrating `stats` — e.g., *"California — 39.5M population · $3.5T GDP · 23 electoral votes · founded 1850 · 5th-largest economy on Earth · capital Sacramento."* Prose packed via `shape_pack(prep, polygon_chord_fn(state_polygon); ...)`.

Editorial chrome around the silhouette:

- Display header: state name in large display type.
- Stats sidebar: numerical highlights (population, GDP, electoral votes) as big-number callouts.
- Small bar chart or sparkline (historical population, founding → present).

**Data layer:** US Census API for state stats; state polygons from `Shapefile.jl` (US Census Tiger/Line shapefiles).

**Acceptance:**

- 3–5 real US states with real census data produce legible atlas pages.
- Text fills each state silhouette without orphaned narrow rows.
- Pages export cleanly to PDF.

**Effort:** ~4–5 days. **Depends:** #C.

### #H — CairoMakie "Newer Yorker" cover (`examples/cover/`)

Pure typographic exhibit. Hand-set editorial cover: title in display type, body text flowing around an SVG illustration inset (uses `shape_pack`), drop cap, pull-quote callouts. No data ingest; static content from `cover.toml`. The purpose is to be visually compelling, not workflow-useful.

Body justification uses K-P internally if shipped, else greedy `layout`.

**Acceptance:**

- Visually compelling PDF that someone would describe as "tasteful."
- SVG inset is rendered as native CairoMakie vector content, not a bitmap.
- Drop cap, pull-quote, body wrap all measured precisely (no manual offsets).

**Effort:** ~2–3 days. **Depends:** #C. **Optional:** consumes `examples/layouts/knuth_plass.jl` from #J if shipped.

### #I — README hero + examples gallery

Replace the current `README.md` example with:

- A hero gif (asteroid fracture or DOI infograph generation) at the top.
- A short example block (current one is fine; can stay).
- A new "Examples" section linking each demo with one-line descriptions + screenshot.

Also: `examples/README.md` as the gallery index — each demo with a one-line pitch, screenshot, and run instructions.

**Acceptance:**

- README hero gif loads in GitHub view.
- All `examples/<demo>/README.md` files exist and explain how to run.

**Effort:** ~0.5–1 day. **Depends:** all demos.

### #J [STRETCH] — Knuth–Plass justification utility + comparison demo

Two pieces, shipped only if appetite remains after #A–#I:

1. **`examples/layouts/knuth_plass.jl`** — port of pretext.js's `kp.ts`. Consumes `Prepared.segments`; emits optimal line breaks minimizing total badness. Same input as `layout` and `shape_pack`; different output algorithm.
2. **`examples/justification/`** — separate demo: three columns of the same paragraph (greedy from `layout`, greedy with hyphenation off, K-P), with river visualizers overlaid. Direct port of pretext.js's `justification-comparison` demo.

**Acceptance:**

- K-P produces measurably lower total badness than greedy on a canonical test paragraph.
- River overlay correctly identifies known rivers in greedy output that K-P avoids.

**Effort:** ~2–3 days. **If shipped:** consumed by #F and #H.

## Dependency graph

```
#A ─┐
    ├─→ #C ─┬─→ #E
            ├─→ #F ─┐
            ├─→ #G ─┤
            └─→ #H ─┤
                    │
#B ─→ #E            │
                    │
#D ─→ #E            ├─→ #I (depends on all demos)
                    │
#J (stretch) ──optional consumer──→ #F, #H
```

## Build sequencing

1. **Week 1:** #A (0.5d) → #C (2–3d) in series; #B (2–3d) and #D (1–2d) in parallel. End of week 1: all plumbing landed.
2. **Week 2:** #E (asteroid TUI, ~1 week).
3. **Week 3:** #F (DOIInfograph) and #G (State Atlas) in parallel.
4. **Week 4:** #H (Newer Yorker) and #I (README + gallery).
5. **Stretch:** #J during weeks 3–4 if capacity allows; if it lands before #F/#H polish, both consume it.

**Estimated total:** 3–4 weeks of focused work for #A–#I.

## Risks

**R1. `pick()` per-glyph behavior on Makie `text!` plots.** Earlier research claimed `pick()` returns a per-glyph index on `text!` — useful for click-to-shoot in the asteroid TUI but only verified via Makie docs, not empirically. **Action:** ~10-line spike before committing #E's hit-test design. Fallback: track per-segment positions explicitly from `shape_pack` output and DIY rectangle hit-test.

**R2. CrossRef abstract availability.** Confirmed unreliable (Sycamore lacks one; PLOS OA lacks one). DOIInfograph relies on OpenAlex `abstract_inverted_index` as the abstract source. **Action:** ensure graceful degradation when OpenAlex also has no abstract — promote Semantic Scholar TLDR into the abstract slot at enlarged size.

**R3. K-P implementation effort.** Pretext.js K-P is ~200–300 lines of dynamic programming with performance care. Porting to Julia is straightforward but non-trivial. **Action:** confirm appetite before scheduling #J.

**R4. `og:image` scraping reliability.** Springer, PLOS, eLife expose `og:image` reliably; some publishers don't. **Action:** ship the geometric placeholder fallback first; treat `og:image` as a bonus path.

**R5. Tachikoma maturity.** Announced Feb 2026; 146★. Active development but newer than the alternatives. **Action:** pin a version in the asteroid demo's `Project.toml`; track upstream changes.

## Open questions

- **Hero gif checked in vs. CI-generated.** Checked in is simpler; CI-generated keeps the repo lean. Probably check it in for now and re-evaluate later.
- **License headers.** Each demo file gets a license header. Match parent (MIT)? Confirm before shipping.
- **#J go/no-go.** Decide after #A–#I to land or defer.

## Next steps

1. User reviews this spec.
2. On approval, invoke the writing-plans skill to produce a detailed implementation plan for #A–#D (the unblockers).
3. Land #A and #B first (library additions); then #C and #D (plumbing). Demos #E–#H land in parallel after.
