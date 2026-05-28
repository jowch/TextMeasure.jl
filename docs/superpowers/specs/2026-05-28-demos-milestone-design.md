# Demos Milestone — TextMeasure in action

**Date:** 2026-05-28 (revised after first reviewer round)
**Status:** Awaiting second reviewer round + user review.
**Branch:** `worktree-demos-milestone-brainstorm`

## Summary

Four demos — one terminal action game and three CairoMakie print artifacts — plus two cross-cutting issues (demo health CI; an optional Knuth–Plass stretch). Together they exercise TextMeasure.jl's `prepare`/`layout` split across multiple backends and downstream layout consumers. The library gains one small addition (`Prepared` segment-slice helper). The figlet backend ships as a sibling package (`examples/TextMeasureFiglet/`) rather than in-tree — honoring CLAUDE.md's weakdep/sibling pattern. Shared utilities (`shape_pack`, silhouettes) live in `examples/` with a documented migration path to `TextMeasureLayouts.jl`. Per-demo `Project.toml`/`Manifest.toml` keep TextMeasure's own dependency graph clean.

## Motivation

TextMeasure has no shipped demos. The library's selling point — *measure once, lay out many times* — is invisible until you watch the same `Prepared` consumed by many downstream layouts. The chosen demos exercise this in three escalating ways:

1. **Tachikoma ASCII Asteroid Blaster (#E).** First-of-its-kind in terminal space — independent prior-art review found no measurement-driven shape-conforming text packing in any surveyed TUI framework (ncurses / ratatui / notcurses / Textual / lipgloss / Charm / Tachikoma). The combination of procedural silhouette + shape-packed prose + word-boundary fracture + variable-width figlet + low-Hz rotation reflow appears to have zero precedent in TUI; chenglou's pretext.js itself is browser-only. The asteroid demo's pitch is therefore: *the first measurement-driven editorial-typography demo in a terminal*, with the measure-once-layout-many split as its load-bearing primitive.
2. **CairoMakie DOIInfograph (#F1–#F3).** Adaptive paper-cover generator that handles arbitrary DOIs gracefully. README hero is the **6-up grid**: Sycamore quantum supremacy, Attention Is All You Need, a PLOS OA paper, a long-title math preprint, an 80+ author paper, and a paper with no abstract — all composed by the same template. The grid *is* the proof of adaptiveness; measurement is invisible-but-essential plumbing.
3. **CairoMakie Map Feature Page (#G).** State silhouette rendered as a real cartographic map (cities, POIs, capital, landmarks) — editorial prose wraps around the silhouette as an irregular obstacle. `shape_pack` does the text-around-figure work (the pretext.js *Dynamic Layout* pattern applied to a real geographic shape). National Geographic / Smithsonian state-feature aesthetic. Honest editorial form with a real JuliaGeo connection.
4. **CairoMakie "Newer Yorker" correctness exhibit (#H).** Hand-set editorial cover where the acceptance test is *"no manual offsets — change the SVG inset by 3px and everything still aligns correctly"*. The demo's job is to prove the library is **correct** (drop-cap baselines, body wraps, pull-quote collisions all measurement-driven), not just gif-able.

(Stretch) **Knuth–Plass Justification Comparison (#K).** Port of pretext.js's `justification-comparison` demo. Two layout algorithms consuming the same `Prepared.segments`, side-by-side with river overlays. Decoupled from #F/#H: they ship with greedy justification by default; K-P is a separate showcase exhibit if appetite remains.

## Non-goals

- **Justification in the library itself.** Knuth–Plass lives in `examples/layouts/`, consumed by demos. CLAUDE.md's exclusion stands.
- **Hyphenation, UAX-#14 line-breaking, CJK, bidi, rotation in the layout API.** Out of scope per CLAUDE.md.
- **PDF figure extraction (pdffigures2-style).** DOIInfograph uses opt-in `og:image` scraping with a geometric placeholder fallback. Full PDF figure extraction is downstream.
- **Authentication for closed-access papers.** Graceful degradation: missing abstract → enlarged Semantic Scholar `tldr`; missing figure → placeholder.
- **Tachikoma sixel/kitty pixel-graphics mode.** Demo lives entirely in monospace cell mode; FigletBackend supplies variable-width measurement at the cell level.
- **Windows TUI support for #E.** Linux and macOS only for v1; Windows is out of scope due to ANSI / raw-mode / sigwinch fragility on Windows terminals.

## Architecture

### Library additions

One small addition to TextMeasure proper, kept narrow and convention-respecting:

**`Prepared` segment-slice helper (`subprep`).** Existing field order `Prepared(segments, metrics)` is preserved (the current struct's auto-generated positional constructor). We add:

```julia
Prepared(; segments::Vector{Segment}, metrics::FontMetrics) = Prepared(segments, metrics)
subprep(prep::Prepared, r::AbstractUnitRange) = Prepared(prep.segments[r], prep.metrics)
```

A kwargs constructor (low risk, no positional ambiguity) plus a named `subprep` helper. We **do not override `Base.getindex`** — that violates collection semantics (`prep[i]` should naturally return a `Segment`, the contained element type, not a sub-`Prepared`). Motivation: the asteroid demo's word-boundary fracture (#E) needs sub-`Prepared`s to re-pack halves of an already-measured paragraph without re-measuring. `shape_pack` (#C) consumes `prep.segments` directly and does NOT need `subprep`.

### Sibling packages (this repo, registerable later)

**`examples/TextMeasureFiglet/`** — a proper Julia package with its own `Project.toml`, depending on TextMeasure via path. Implements the `FigletBackend` (#B). Bundled figlet fonts live here (not in TextMeasure's published assets). The package's source file is the exemplary teaching artifact for "how to write a backend in a sibling package." Registerable on JuliaRegistries post-milestone if there's demand. The asteroid demo (#E) uses `Pkg.develop(path="../TextMeasureFiglet")`.

**Migration path flag for `examples/layouts/`.** `shape_pack` (#C) and (stretch) `knuth_plass` (#K) are the most-reused utilities across demos. For the milestone they live in `examples/layouts/` as a shared module loaded by per-demo Project.tomls via `Pkg.develop`. The intended long-term home is a separate registered package **`TextMeasureLayouts.jl`** — flagged here as a known migration so downstream users have an install path. Defer the actual extraction to a post-milestone task.

### Shared utilities (`examples/layouts/`, `examples/silhouettes/`)

`examples/layouts/shape_pack.jl` — `shape_pack(prep::Prepared, chord_fn; line_advance, min_chord_width=24) -> PackedLayout`. See #C for the contract.

(Stretch) `examples/layouts/knuth_plass.jl` — optimal whole-paragraph line breaks consuming the same `Prepared.segments`. See #K.

`examples/silhouettes/` — `asteroid_polygon(rng; n, lumpiness)`, `voronoi_shatter(polygon, impact; n_shards)`, `rasterize(polygon, cell_size)`. See #D.

### Per-demo structure

Each demo lives in `examples/<demo>/` with its own `Project.toml` / `Manifest.toml`. TextMeasure is depended on via `Pkg.develop(path="../..")`. Demo-specific dependencies (Tachikoma, CairoMakie, HTTP, etc.) never enter TextMeasure's own dependency graph. Each demo gets a short `README.md` explaining how to run it.

## Issues

Issues #A–#J are in scope for this milestone. #K is a stretch issue, shipped only if appetite remains.

### #A — `Prepared` segment-slice helper (library)

Add `Prepared(; segments, metrics)` kwargs constructor and `subprep(prep, r)` named function. Existing positional `Prepared(segments, metrics)` field order preserved. **No `Base.getindex` override.** Tested in `test/test_types.jl` (constructor round-trip) and `test/test_prepare.jl` (fracture-style slice test).

**Acceptance:**

- `Prepared(; segments=s, metrics=m).segments == s` and `.metrics == m`.
- `subprep(prep, 1:length(prep.segments)) == prep` semantically.
- Slicing at a word boundary, calling `layout` on both halves, confirms widths sum back correctly.
- Export `subprep` from TextMeasure.
- Updated CHANGELOG entry.

**Effort:** ~0.5 day. **Blocks:** #E only (#C uses `prep.segments` directly).

### #B — `TextMeasureFiglet.jl` sibling package (`examples/TextMeasureFiglet/`)

New sibling package at `examples/TextMeasureFiglet/` with its own `Project.toml` depending on TextMeasure via `path = "../.."`. Contains:

- `src/TextMeasureFiglet.jl` — the package module, exporting `FigletBackend`.
- `src/figlet_parser.jl` — pure-Julia `.flf` parser handling hardblanks, smushing rules, comment headers, codetag fonts.
- `src/backend.jl` — `FigletBackend` struct, keyword constructor `FigletBackend(; font="small", letter_gap=0)`, `TextMeasure.measure`, `TextMeasure.font_metrics`.
- `src/fonts/` — bundled `.flf` files with **per-font license audit**. Only fonts with MIT-redistribution-compatible licenses ship. Other fonts are user-supplied at construction (`FigletBackend(font_data=read("custom.flf", String))`).
- `LICENSES.md` — per-font license documentation.
- Heavy commentary in `src/TextMeasureFiglet.jl` as the canonical "how to write a backend in a sibling package" teaching artifact, referenced from `AbstractMeasurementBackend`'s docstring.

**Acceptance:**

- Deterministic test widths for known strings against each bundled font.
- `LICENSES.md` exists; each shipped font has a verified MIT-compatible license cited. Fonts without compatible licenses are excluded with a note.
- Passes backend conformance tests (cell-space measurement, integer widths, ascent/descent matches font header).
- The sibling package's README explains the pattern; AbstractMeasurementBackend docstring points here.
- CI matrix includes a test for this sibling package using `Pkg.develop`.

**Effort:** 3–4 days incl. font bundling + license audit. **Blocks:** #E.

### #C — `examples/layouts/shape_pack.jl`

Reusable shape-conforming layout. Algorithm: pretext.js-validated per-band scanline (see `wrap-geometry.ts` in chenglou/pretext). Returns a typed struct, not a bare tuple-vector.

**Interface:**

```julia
struct Placement
    segment_index :: Int          # index into the source Prepared.segments
    x             :: Float64
    y             :: Float64       # block-top coord frame (matches `layout`)
end

struct PackedLayout
    placements :: Vector{Placement}
    overflowed :: Vector{Int}      # segment indices wider than any chord at any row
    metrics    :: FontMetrics      # echoed from Prepared
end

shape_pack(prep::Prepared, chord_fn; line_advance, min_chord_width=24,
           overflow_strategy::Symbol=:widest_row) -> PackedLayout
```

**`chord_fn` contract.**

- `chord_fn(y::Real) -> Vector{Tuple{Float64,Float64}}` returns per-band horizontal intervals at the band whose **top** is `y` (block-top coord frame, matching `layout`).
- Returned `(left, right)` pairs are **sorted ascending and pairwise disjoint** (callers can assume non-overlapping runs).
- An empty vector means no chord at this y (skip the band).
- A typed callable `AbstractChordFn` with dispatched `chord_intervals(shape, y)` is **the preferred long-term API**; for milestone-1 a plain `Function` closure is acceptable, but the helper constructors below return typed wrappers to ease the future migration.

**Two `chord_fn` constructors as helpers:**

- `polygon_chord_fn(polygon::Vector{Point2}) :: PolygonChordFn` — scanline intersection of a 2-D polygon (callable returning `chord_intervals`).
- `raster_chord_fn(raster::BitMatrix, cell_size::Real) :: RasterChordFn` — for cell-grid silhouettes (Tachikoma).

**Overflow strategies:** `:widest_row` (default — render in the widest available row, accept overflow), `:skip` (drop the segment, add to `overflowed`), `:reject` (return empty `PackedLayout` with all subsequent segments in `overflowed`).

**Acceptance:**

- Pack into rectangle of width `w` produces the same line breaks as `layout(prep; max_width=w)`.
- Pack into circle (smoke test on known font + text).
- Pack into concave U-shape; slivers below `min_chord_width` are dropped.
- `overflowed` correctly populated when a word exceeds the widest available chord.
- Coord-frame consistency: `placements[i].y` matches the corresponding `layout` baseline calculation for rectangular packs (within floating tolerance).

**Effort:** 2–3 days. **Blocks:** #E, #F2, #G, #H. **Note:** flagged for eventual migration to `TextMeasureLayouts.jl` sibling package.

### #D — `examples/silhouettes/`

Three exports:

- `asteroid_polygon(rng; n=12, lumpiness=0.4)` — polar Perlin noise (CoherentNoise.jl).
- `voronoi_shatter(polygon, impact; n_shards)` — DelaunayTriangulation.jl seeded near impact, clipped to parent with GeometryOps.jl.
- `rasterize(polygon, cell_size)` — for the TUI demo.

**Acceptance:**

- Shape validity smoke tests (CCW orientation, simple polygons, no self-intersections).
- `voronoi_shatter(poly, pt; n=4)` returns 4 polygons whose union equals `poly` within numerical tolerance and whose pairwise intersections are zero-measure.

**Effort:** 1–2 days. **Blocks:** #E only.

### #E — Tachikoma ASCII Asteroid Blaster (`examples/asteroid_tui/`)

**Pitch:** First measurement-driven editorial-typography demo in terminal space (prior-art review found no shape-conforming text packing or measure-once-layout-many primitive in any surveyed TUI framework). The composition — procedural silhouette + shape-packed prose + word-boundary fracture + variable-width figlet + low-Hz rotation reflow — has no precedent in TUI; pretext.js itself is browser-only.

**Visual direction (locked through brainstorming):**

- **Ship: Arwing** — wedge nose, swept-back wings, thruster glyphs at base. Physics state (x, y, φ, v) packed via `shape_pack` into the wedge interior; re-packed every frame as values update.
- **Asteroids: varied silhouettes** — dagger, crescent, lumpy potato, multi-lobed peanut. Generated per spawn from `asteroid_polygon`. Descriptive prose packed inside.
- **Stat tags above each asteroid** in flipped-bracket format: `┌─ d:142m  ETA:3.4s  v:0.21µ ─┐`. Ends point down.
- **Beam: onomatopoeia** (`PEW` repeated) length-scaled to `floor(dist / measure(b, "PEW "))`.
- **Charge: 5 stages**, asterisk at ship tip growing from `·` → `*` → `─*─` → `\*/` → full sunburst over hold ~0.15s → ~1.5s.
- **Respawn:** ship blows up on hit; respawns with ~2s invulnerability at ~3Hz blink, intangible, player can reposition.
- **Debug overlay (`?`):** every measured word's bbox drawn in cyan.

**Mechanics (locked):**

- Asteroids rotate at ω sampled from `[-0.4, +0.4]` rad/s. Silhouette re-rasterizes every ~5 frames; `shape_pack` re-runs against the new cell raster; word widths in the `Prepared` are reused (no re-measurement).
- Word-boundary fracture on impact: nearest placed segment → snap back to start of its `:word` → `subprep` slice → re-pack each half into a child silhouette (`voronoi_shatter` seeded at impact).
- Prose pool: ≥50 procedurally varied templates (class × material × callsign × spin rate).
- **No HP/ammo system.** Hit → explode → respawn.

**Crayons.jl is not used.** Tachikoma handles ANSI colors natively in its own renderer.

**Plan B for Tachikoma.** If Tachikoma proves unworkable (API churn, abandonment, fundamental fit issue), fall back to **REPL.TerminalMenus + manual ANSI escape codes + `TermInterface.jl` for raw-mode input**. The demo's core (shape_pack against a cell raster + FigletBackend measurement) is renderer-agnostic; only the event loop and double-buffered draw would need rework. ~2–3 days of extra work for the swap.

**Cross-platform scope:** Linux and macOS only for v1. Windows is OOS due to ANSI / raw-mode / sigwinch fragility.

**Acceptance:**

- Hit one asteroid, observe legible split into two shard-prose chunks (no orphaned words; "legible" defined as: every glyph from the original prose appears in exactly one shard's render, in original order, with no character drops or duplicates).
- ≥30fps on Linux/macOS in a 120×40 terminal during steady-state play with ~5 asteroids (measured via wall-clock between frame swaps).
- Debug overlay correctly highlights every measured word.
- Respawn flash + invulnerability works as described.
- Headless tick-loop test in CI (no actual terminal needed): boot game, run 60 ticks of a scripted scenario, snapshot the cell buffer, checksum against a committed golden.

**Effort:** 2–2.5 weeks. **Depends:** #A, #B, #C, #D.

### #F1 — DOIInfograph data layer (`examples/doi_infograph/data/`)

**Scope:** API clients for OpenAlex, CrossRef, Semantic Scholar; abstract reconstruction from OpenAlex's inverted index; opt-in `og:image` scraping; offline-cached responses for the acceptance DOIs.

- `OpenAlexClient(; mailto::String)` — `HTTP.jl` + `JSON3.jl`. Reconstruct abstract from `abstract_inverted_index` (flatten, sort by position, join).
- `CrossRefClient(; mailto)` — fallback metadata and references.
- `SemanticScholarClient()` — for the `tldr` field.
- `fetch_doi_metadata(doi; fetch_figure=false)` returns a `PaperMetadata` struct (title, authors, abstract, tldr, citation_count, citations_by_year, concepts, oa_status, oa_url, figure_url, pp, journal, year, doi).
- `fetch_figure=false` by default — to respect publisher ToS. When opt-in, scrapes `og:image` from publisher page with explicit `User-Agent: TextMeasure.jl/<version> mailto=<user>` header.
- Three acceptance DOIs (Sycamore, Attention, one PLOS OA) have their JSON responses **cached to `examples/doi_infograph/data/cache/`** for offline + reproducible CI.

**Acceptance:**

- All three acceptance DOIs round-trip via offline cache.
- Abstract reconstruction from OpenAlex inverted index matches the canonical published text on the three DOIs.
- `fetch_figure=false` is the default; opt-in path documented in the demo README with publisher-ToS note.
- Rate-limit handling: 429 → exponential backoff with `Retry-After` honored.

**Effort:** 4–5 days. **Blocks:** #F2.

### #F2 — DOIInfograph adaptive layout engine (`examples/doi_infograph/layout/`)

**Scope:** the measurement work. Given a `PaperMetadata` and a CairoMakie `Figure` (with a fixed page size), produce a composed page.

**Adaptive primitives (each is a measurement-driven choice the spec calls out by name):**

- **Title autoshrink** — binary search over `fontsize` such that `measure(b, title, fontsize) ≤ title_box_width` and line count ≤ 2.
- **Author overflow** — accumulate measured author widths until next would exceed the row; append "et al." atomically.
- **TLDR autosize** — fontsize chosen so measured line-count × line-advance fills (not exceeds) the TLDR box height.
- **Drop cap** — T-glyph measured to know wrap offset for the first paragraph's first three lines.
- **Body text wrap around figure pillar** — text column on the left at fixed width; figure pillar on the right at full body height.
- **Concept pill wrap** — pills measured as atomic segments; greedy fit into the pill strip width with row wrap.
- **Citation sparkline** — Unicode block characters chosen so the sparkline's measured width matches the surrounding caption's measured width within ±1 glyph.

Body justification uses greedy `layout` by default. If #K ships, opt into K-P via `infograph(doi; justification=:knuth_plass)`.

**Acceptance:**

- **Property test:** generate 100 random titles of lengths in [10, 200] chars; for every one, title autoshrink terminates with a fontsize where the title fits in ≤ 2 lines at the title box width. No exceptions.
- **Comparative test:** Sycamore renders smaller than Attention in the same title box (verifiable assertion on fontsize delta).
- **Author overflow test:** Sycamore (78 authors) emits "et al."; Attention (8 authors) fits all eight.
- Sparkline length matches measured caption width within ±1 glyph across all three acceptance DOIs.

**Effort:** 4–5 days. **Blocks:** #F3. **Depends:** #F1, #C.

### #F3 — DOIInfograph 6-up grid + Pluto wrapper (`examples/doi_infograph/`)

**Scope:** the gif-able / README-hero exhibit.

- `grid_infograph(dois::Vector{String}) -> CairoMakie.Figure` composes a 2×3 (or 3×2) grid of infographs for the six canonical demonstration DOIs:
  1. Sycamore quantum supremacy (Nature, hybrid OA, long title, 78 authors)
  2. Attention Is All You Need (NeurIPS, green OA, short title, 8 authors)
  3. PLOS ONE OA paper (CC BY, abstract present)
  4. A long-title math preprint (arXiv, no journal abstract, very long title)
  5. A genome-wide association study (Nature Genetics, 80+ authors)
  6. A paper with no available abstract (CrossRef has only title + authors)
- Pluto notebook (`Demo.jl`): paste a DOI, render single infograph, slider for page width drives layout reflow, "Export PDF" button.

**Acceptance:**

- The 6-up grid renders as a single composed figure that exports to a single multi-page PDF (one paper per page) and a single composite PNG for README hero.
- All six papers produce legible, composed infographics — no overlapping text, no clipped figures.
- Pluto slider reflows the layout within ~500ms of slider change (with CairoMakie's static render).
- Cached API responses make the Pluto demo runnable offline.

**Effort:** 2–3 days. **Depends:** #F2.

### #G — CairoMakie Map Feature Page (`examples/map_feature/`)

**Reframed scope.** State silhouette is rendered as a **real cartographic map** (cities, POIs, capital, landmarks, geographic features). Editorial prose **wraps around the silhouette as an irregular obstacle** (the pretext.js *Dynamic Layout* pattern). National Geographic / Smithsonian state-feature spread aesthetic.

`map_feature(state_polygon, stats::Dict, points_of_interest::Vector{POI}) -> CairoMakie.Figure`.

Layout:

- State map fills the right ~55% of the page (silhouette + cartographic content inside).
- Editorial prose wraps around the silhouette on the left (uses `shape_pack` with the state polygon as an obstacle, so the body flows in the negative space around the state shape).
- Magazine masthead at top, byline at bottom.
- Sidebar callouts (population, GDP, capital) as big-number stats.

**Data layer:**

- US Census Tiger/Line shapefiles (state polygons) — public-domain US gov't data. **Fetched at first run** via the Census's TIGER API; cached to `~/.julia/scratchspaces/...` to avoid repo bloat. Mirror fallback documented in the README.
- POIs from a curated `examples/map_feature/data/pois.toml` (small handcrafted dataset for the 3–5 acceptance states).
- Census API for state stats (cached for offline CI).

**Acceptance:**

- 3–5 US states (California, Texas, Florida, Vermont, Hawaii — varying silhouette complexity from simple → highly irregular) produce legible map feature pages.
- Editorial text flows around the state silhouette without overlapping the map.
- POI labels on the map are placed without overlap (note: this can use simple offset placement, as the user's in-flight ggrepel-style package will handle the harder repel cases — out of scope here).
- Pages export cleanly to PDF with selectable text (verified by extracting text from the exported PDF and checking it matches input strings).

**Effort:** 4–5 days. **Depends:** #C.

### #H — CairoMakie "Newer Yorker" correctness exhibit (`examples/cover/`)

**Reframed pitch.** The demo whose job is to **prove the library is correct**, not just gif-able. The honest acceptance test is **"no manual offsets"** — change the SVG inset's position by 3 pixels, re-render, every other element re-aligns correctly because every offset was measurement-derived, not hardcoded.

Hand-set editorial cover: title in display type, body text flowing around an SVG illustration inset (uses `shape_pack`), drop cap, pull-quote callouts. No data ingest; static content from `cover.toml`. Body justification uses greedy `layout` (or K-P if #K shipped).

**Acceptance:**

- **The "no manual offsets" test:** the demo ships with three `cover-v1.toml`, `cover-v2.toml`, `cover-v3.toml` files where the SVG inset is at different positions/sizes. All three produce visually composed PDFs with no manual layout code changes between renders.
- Drop cap's baseline aligns with paragraph baseline within ±0.5px (measured from rendered PDF).
- Pull-quote callouts do not overlap body text or the SVG inset (verified by bbox intersection check on rendered PDF).
- SVG inset is rendered as native CairoMakie vector content, not a bitmap.
- PDF text is selectable (font embedding verified).

**Effort:** 2–3 days. **Depends:** #C.

### #I — README hero, gallery, release hygiene

Cross-cutting integration work:

- README hero: the **6-up DOIInfograph grid PNG** (committed binary, not CI-generated — CI for image generation is too heavy for the milestone).
- README's "Backends" section updated to include `TextMeasureFiglet.jl` sibling package with install path.
- `examples/README.md` as the gallery index — each demo with one-line pitch, screenshot, run instructions.
- Each `examples/<demo>/README.md` exists with run instructions and a `Project.toml` / `Manifest.toml` ready for `julia --project=. -e 'using Pkg; Pkg.instantiate()'`.
- `CHANGELOG.md` updated with one entry per shipped issue.
- Documenter.jl integration: a `docs/` build (basic — landing page + each public API page + link to the gallery). This is new infrastructure for this repo; budget includes GitHub Actions workflow.
- License headers on every file in `examples/`. Match parent (MIT) unless a sibling package needs a different license.
- Version bump to 0.2.0 with summary in CHANGELOG.

**Acceptance:**

- README hero PNG loads in GitHub view.
- All `examples/<demo>/README.md` files exist and accurately describe the run flow.
- `CHANGELOG.md` reflects every shipped issue.
- `docs/build/` succeeds locally and in CI.
- License audit passes (every `examples/` file has a header; sibling-package licenses verified).
- Version 0.2.0 tagged after this issue lands.

**Effort:** 1–2 days. **Depends:** all completed demos.

### #J — Demo health CI + golden snapshots + property tests

New cross-cutting issue addressing Reviewer 4's "demos rot silently" critique (R12). Without this, the demos drift the moment a dependency moves.

**Scope:**

- Weekly scheduled GitHub Actions workflow that boots each demo in CI:
  - **#E asteroid:** headless tick-loop, 60 ticks, snapshot cell buffer, checksum vs committed golden.
  - **#F3 DOIInfograph:** render the 6-up grid from cached responses, extract text from exported PDF, checksum.
  - **#G map feature:** render Vermont's page from cached data, checksum exported PDF text.
  - **#H newer yorker:** render `cover-v1.toml`, checksum exported PDF text.
- Failure files a GitHub issue automatically (via standard actions).
- **Property tests** in regular CI:
  - **Autoshrink property test** (from #F2): 100 random title lengths all fit.
  - **`shape_pack` invariants**: every `Placement.segment_index ∈ [1, length(prep.segments)]`; placements per band do not exceed band's chord intervals; overflowed segments do not have placements.
- **License audit gate** in regular CI: every file in `examples/` has a license header; `TextMeasureFiglet`'s `LICENSES.md` exists and references each shipped font.

**Acceptance:**

- Weekly health-check workflow lives at `.github/workflows/demo_health.yml`; runs successfully against all four demos.
- Property tests added to `test/` and run on every PR.
- License audit gate fails CI if any `examples/` file lacks a header.

**Effort:** 2–3 days. **Depends:** completed demos (acceptance criteria reference each).

### #K [STRETCH] — Knuth–Plass justification utility + comparison demo

Two pieces, shipped only if appetite remains after #A–#J:

1. **`examples/layouts/knuth_plass.jl`** — port of pretext.js's `kp.ts`. Consumes `Prepared.segments`; emits optimal line breaks minimizing total badness. Same input as `layout` and `shape_pack`; different output algorithm.
2. **`examples/justification/`** — separate demo: three columns of the same paragraph (greedy from `layout`, greedy with hyphenation off, K-P), with river visualizers overlaid. Direct port of pretext.js's `justification-comparison` demo.

**Decoupling from #F/#H:** #F2 and #H ship with greedy `layout` body justification by default. If #K lands, opt-in via `infograph(doi; justification=:knuth_plass)` and `cover(toml; justification=:knuth_plass)`. The non-stretch demos are NOT load-bearing on #K.

**Acceptance:**

- K-P produces measurably lower total badness than greedy on a canonical test paragraph.
- River overlay correctly identifies known rivers in greedy output that K-P avoids.
- Comparison demo renders all three columns side-by-side as a single PDF.

**Effort:** 4–5 days (port: 2–3 days; comparison demo with river overlays: 2 days).

## Dependency graph

```
#A ─→ #E
#B ─→ #E
#D ─→ #E
                      ┌──→ #E
#C ─→ ┬──→ #F2 → #F3 ─┤
      ├──→ #G ────────┤
      └──→ #H ────────┤
                      ├──→ #I (depends on all completed demos)
                      └──→ #J (depends on all completed demos)
#F1 ─→ #F2

#K (stretch) ──optional consumer──→ #F2, #H
```

#A is independent and only blocks #E. #C is the critical-path utility (blocks #E, #F2, #G, #H). #F1 → #F2 → #F3 must be in sequence; everything else parallelizes.

## Build sequencing

**Honest estimate: ~6 weeks full-time, ~9–12 weeks part-time.**

- **Week 1:** #A (0.5d) + #B (3–4d) + #C (2–3d) + #D (1–2d) — all in parallel. End of week 1: all plumbing landed.
- **Weeks 2–3:** #E (asteroid TUI, 10–12 days) as the main thread; #F1 (data layer, 4–5d) and #G (map feature, 4–5d) as side-threads.
- **Weeks 4–5:** #F2 (DOI layout engine, 4–5d) → #F3 (grid + Pluto, 2–3d); #H (correctness exhibit, 2–3d) in parallel.
- **Week 6:** #J (demo health CI, 2–3d) + #I (README, gallery, release hygiene, 1–2d) + (optional) #K (K-P stretch, 4–5d).

## Smallest viable milestone (if time gets cut to 1 week)

Per Reviewer 2: if the contributor has only 1 week, ship #A + #C + #F1-lite (one hardcoded DOI, no full client) + a single-paper DOIInfograph + README hero PNG. Defers asteroid, map feature, correctness exhibit, demo health CI, K-P. Proves "measure once, lay out many" with one beautiful PDF. ~5–6 days.

This is the **fall-back if scope must shrink mid-flight**, not the planned path.

## Risks

**R1. `pick()` per-glyph behavior on Makie `text!` plots.** Earlier research claimed `pick()` returns a per-glyph index on `text!` — useful for click-to-shoot in some Makie demos. Not actually needed by the asteroid TUI (Tachikoma handles input directly), so this risk is closed for the milestone but flagged for any future Makie-based asteroid variant.

**R2. CrossRef abstract availability.** Confirmed unreliable. DOIInfograph relies on OpenAlex `abstract_inverted_index`. Mitigation: graceful degradation when OpenAlex also lacks one — Semantic Scholar TLDR promoted to the abstract slot at enlarged size. Covered in #F1 / #F2 acceptance.

**R3. K-P implementation effort.** Pretext.js K-P is ~200–300 lines of dynamic programming with performance care. Realistic 4–5 days for port + river-overlay visualizer. Stretch status preserved; #F/#H decoupled.

**R4. `og:image` scraping legality + reliability.** Springer, PLOS, eLife expose `og:image` reliably; some publishers don't, and ToS may forbid automated scraping. Mitigation: `fetch_figure=false` default in #F1; geometric placeholder fallback; opt-in path documented with explicit ToS note.

**R5. Tachikoma maturity.** Announced Feb 2026, 146★. Pin a specific version in #E's `Project.toml`; vendor a minimal API-compat shim in `examples/asteroid_tui/compat/` if breaking changes appear upstream. **Plan B documented in #E:** REPL.TerminalMenus + manual ANSI fallback.

**R6. Tachikoma upstream churn beyond version pin.** A 4-month-old TUI framework will not have a long support window for an old pinned version. If Tachikoma releases a breaking 0.x bump and the asteroid demo's pin becomes unbuildable on a current Julia, the demo rots. Mitigation: #J's weekly health-check workflow catches this within a week; the maintainer issue is auto-filed.

**R7. Cross-platform silence.** #E scoped to Linux + macOS only for v1. CairoMakie demos (#F3, #G, #H) work on all three OSes but require system Cairo + Pango + fonts — `fontconfig` config may differ. Mitigation: CI matrix should cover at least Linux and macOS for the CairoMakie demos; document Windows-specific font setup in `examples/<demo>/README.md` if attempted.

**R8. Figlet `.flf` license incompatibility.** Many canonical figlet fonts (`standard.flf`, `slant.flf`, `banner.flf`) ship under the original Figlet license or have GPL-incompatible-with-MIT-redistribution terms. **Mitigation:** #B's acceptance includes a license audit; only fonts with MIT-compatible licenses are bundled. Other fonts are user-supplied at runtime via `FigletBackend(; font_data=read("custom.flf", String))`. Acceptance includes `LICENSES.md` documenting every shipped font.

**R9. API rate limits.** Mitigated by offline caching of acceptance-DOI responses in #F1. Live use respects `Retry-After`; uses `mailto=` polite pool.

**R10. US Census Tiger/Line shapefile distribution.** Public-domain US gov't data, but file sizes are large (tens of MB per state). **Mitigation:** #G fetches at first run from the Census's TIGER API, caches to `~/.julia/scratchspaces/`. Mirror fallback URL documented in `examples/map_feature/README.md`.

**R11. PDF text selectability vs outlined paths.** CairoMakie's PDF backend can produce non-selectable text if fonts aren't properly embedded. **Mitigation:** #F3, #G, #H acceptance criteria explicitly verify text selectability by extracting text from the exported PDF and matching against input strings.

**R12. Demo rot.** Addressed by #J (weekly health-check CI + golden snapshots).

**R13. Polygon scanline performance at print resolution.** `shape_pack`'s `polygon_chord_fn` is O(rows × edges). At 300 DPI on a 11×17" page, that's thousands of scanlines × hundreds of edges. **Mitigation:** #C profiling pass after the milestone if `shape_pack` is the bottleneck; budget not included in #C scope but flagged.

**R14. Pluto + CairoMakie + slider sluggishness.** Pluto's reactive model + CairoMakie's heavy static-export pipeline → tens of milliseconds per slider tick at minimum. **Mitigation:** #F3 acceptance is "reflow within ~500ms," not "instant"; cache the rendered figure and only re-layout (not re-render the figure asset) on slider change.

## Open questions

- **#K go/no-go.** Decide after #A–#J land.
- **Sibling-package promotion timing.** `TextMeasureFiglet.jl` and `TextMeasureLayouts.jl` register on JuliaRegistries when? Probably post-milestone, gated on demand.
- **Documenter.jl hosting.** GitHub Pages from the docs build? Add a deploy workflow in #I, or defer?

## Next steps

1. Re-dispatch the four reviewers against this revised spec to check convergence.
2. On reviewer convergence, user reviews the spec.
3. On user approval, invoke the writing-plans skill to produce a detailed implementation plan for #A–#D (the unblockers).
4. Land #A and #B first (library + sibling package), then #C and #D (plumbing). Demos #E–#H land in parallel after.
