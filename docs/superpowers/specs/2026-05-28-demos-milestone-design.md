# Demos Milestone — TextMeasure in action

**Date:** 2026-05-28 (revised round 3)
**Status:** Awaiting reviewer convergence + user review.
**Branch:** `worktree-demos-milestone-brainstorm`

## Summary

Four demos — one terminal action game and three CairoMakie print artifacts — plus two cross-cutting issues (demo health CI; an optional Knuth–Plass stretch). Together they exercise TextMeasure.jl's `prepare`/`layout` split across multiple backends and downstream layout consumers. The library gains one small addition (`Prepared` segment-slice helper) plus a `FigletBackend` shipped as a weakdep extension on **the existing `FIGlet.jl` package** (kdheepak, MIT, on JuliaRegistries) — the third instance of the established `FreeTypeBackend` / `MakieBackend` weakdep-ext pattern. Shared utilities (`shape_pack`, silhouettes) live in `examples/` with a documented migration path to `TextMeasureLayouts.jl`. Per-demo `Project.toml`/`Manifest.toml` keep TextMeasure's own dependency graph clean.

## Motivation

TextMeasure has no shipped demos. The library's selling point — *measure once, lay out many times* — is invisible until you watch the same `Prepared` consumed by many downstream layouts. The chosen demos exercise this in three escalating ways:

1. **Tachikoma ASCII Asteroid Blaster (#E).** First-of-its-kind in terminal space — independent prior-art review found no measurement-driven shape-conforming text packing or measure-once-layout-many primitive in any surveyed TUI framework (ncurses / ratatui / notcurses / Textual / lipgloss / Charm / Tachikoma). The combination of procedural silhouette + shape-packed prose + word-boundary fracture + variable-width figlet + low-Hz rotation reflow appears to have zero precedent in TUI; chenglou's pretext.js itself is browser-only. The asteroid demo's pitch is therefore: *the first measurement-driven editorial-typography demo in a terminal*, with the measure-once-layout-many split as its load-bearing primitive.
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
- **Windows TUI support for #E.** Linux and macOS only for v1; Windows is out of scope due to ANSI / raw-mode / sigwinch fragility on Windows terminals. (Windows for the CairoMakie demos is undefined and depends on contributor capacity; see #J for the CI matrix gate.)
- **Time estimates.** Issues describe scope and acceptance criteria; effort and sequencing are expressed by dependency graph and waves, not weeks.

## Assumed contributor profile

The acceptance criteria below assume a contributor comfortable with: Julia package extensions and `Pkg.develop` path chains; basic CairoMakie internals; one chosen TUI framework's event loop (Tachikoma OR a substituted Plan B per #E); HTTP+JSON3 API clients; basic property-based testing. The spec does not pre-assume familiarity with GeometryOps/DelaunayTriangulation, Shapefile parsing, FIGfont format, or Knuth–Plass — each is documented inline where it first appears.

## Architecture

### Library additions

One small addition to TextMeasure proper, kept narrow and convention-respecting:

**`Prepared` segment-slice helper (`subprep`).** Existing field order `Prepared(segments, metrics)` is preserved (the current struct's auto-generated positional constructor). We add:

```julia
Prepared(; segments::Vector{Segment}, metrics::FontMetrics) = Prepared(segments, metrics)
subprep(prep::Prepared, r::AbstractUnitRange) = Prepared(prep.segments[r], prep.metrics)
```

A kwargs constructor (low risk, no positional ambiguity) plus a named `subprep` helper. We **do not override `Base.getindex`** — that violates collection semantics (`prep[i]` should naturally return a `Segment`, the contained element type, not a sub-`Prepared`). Motivation: the asteroid demo's word-boundary fracture (#E) needs sub-`Prepared`s to re-pack halves of an already-measured paragraph without re-measuring. `shape_pack` (#C) consumes `prep.segments` directly and does NOT need `subprep`.

### `FigletBackend` ships as a weakdep extension on `FIGlet.jl`

The existing **`FIGlet.jl`** package (kdheepak, MIT-licensed, version 0.2.2, on JuliaRegistries, Julia 1.10+) already provides what a from-scratch sibling package would have: a pure-Julia `.flf` parser, an `Artifacts`-managed bundled font collection (`FIGletFonts-0.5.0`), the `FIGletFont` / `FIGletHeader` / `FIGletChar` types, `readfont(name)` / `readfont(io)` loaders, and a `render` function. We **don't build our own** — we depend on it.

The integration mirrors `FreeTypeBackend` and `MakieBackend` exactly:

- Container struct `FigletBackend` added to `src/backend_containers.jl` alongside the existing two.
- `FIGlet` declared as a `[weakdeps]` entry in TextMeasure's `Project.toml`, with `TextMeasureFigletExt = "FIGlet"` in `[extensions]`.
- `ext/TextMeasureFigletExt.jl` provides the keyword constructor + `TextMeasure.measure` + `TextMeasure.font_metrics`, activating when the user does `using FIGlet`.

This makes `FigletBackend` the **third example of the canonical weakdep-extension backend pattern** that CLAUDE.md describes — and the third instance is now against a *real, registered, externally-maintained* package, which is the most realistic teaching scenario for backend authors. The asteroid demo (#E) does `Pkg.develop(path="../..")` for TextMeasure and adds `FIGlet` as a regular dep (`Pkg.add("FIGlet")`); `using TextMeasure, FIGlet` triggers the ext.

**Migration path flag for `examples/layouts/`.** `shape_pack` (#C) and (stretch) `knuth_plass` (#K) are the most-reused utilities across demos. For the milestone they live in `examples/layouts/` as a shared module loaded by per-demo Project.tomls via `Pkg.develop`. The intended long-term home is a separate registered package **`TextMeasureLayouts.jl`** — flagged here as a known migration so downstream users have an install path. Defer the actual extraction to a post-milestone task. During the milestone, downstream consumers install via `Pkg.develop(path=…)` against a path inside this repo.

### Shared utilities (`examples/layouts/`, `examples/silhouettes/`)

`examples/layouts/shape_pack.jl` — `shape_pack(prep::Prepared, chord_fn; line_advance, min_chord_width=24) -> PackedLayout`. See #C for the contract.

(Stretch) `examples/layouts/knuth_plass.jl` — optimal whole-paragraph line breaks consuming the same `Prepared.segments`. See #K.

`examples/silhouettes/` — `asteroid_polygon(rng; n, lumpiness)`, `voronoi_shatter(polygon, impact; n_shards)`, `rasterize(polygon, cell_size)`. See #D.

### Per-demo structure

Each demo lives in `examples/<demo>/` with its own `Project.toml` / `Manifest.toml`. TextMeasure is depended on via `Pkg.develop(path="../..")`. Demo-specific dependencies (Tachikoma, CairoMakie, HTTP, etc.) never enter TextMeasure's own dependency graph. Each demo gets a short `README.md` explaining how to run it.

## Issues

Issues #A–#J are in scope for this milestone. #K is a stretch issue.

### #A — `Prepared` segment-slice helper (library)

Add `Prepared(; segments, metrics)` kwargs constructor and `subprep(prep, r)` named function. Existing positional `Prepared(segments, metrics)` field order preserved. **No `Base.getindex` override.** Tested in `test/test_types.jl` (constructor round-trip) and `test/test_prepare.jl` (fracture-style slice test).

**Acceptance:**
- `Prepared(; segments=s, metrics=m).segments == s` and `.metrics == m`.
- `subprep(prep, 1:length(prep.segments)) == prep` semantically.
- Slicing at a word boundary, calling `layout` on both halves, confirms widths sum back correctly.
- Slicing across `:newline` or `:space` segments preserves segment integrity (the segments end up in the side they're indexed into; no segments dropped or duplicated).
- Export `subprep` from TextMeasure.
- Updated `CHANGELOG.md` entry.

**Blocks:** #E only (#C uses `prep.segments` directly).

### #B — `FigletBackend` weakdep extension on `FIGlet.jl`

A single, tight piece of work: wire TextMeasure to the existing `FIGlet.jl` package via the canonical ext pattern.

- `src/backend_containers.jl` gains a `FigletBackend` struct alongside `FreeTypeBackend` and `MakieBackend`. Shape: `struct FigletBackend{F} <: AbstractMeasurementBackend; font::F; letter_gap::Int; end` where `F` is opaque to TextMeasure (it's `FIGlet.FIGletFont` once the ext is loaded, but the container doesn't name the type). **Two deliberate departures from FreeType/Makie conventions:** no `fontsize` field (FIGlet glyphs live on a fixed integer cell grid — `measure` returns cell counts, not pixels); `letter_gap :: Int` not `Float64` (integer cell counts). The ext preamble documents both.
- TextMeasure's `Project.toml` adds `FIGlet = "3064a664-84fe-4d92-92c7-ed492f3d8fae"` under `[weakdeps]` and `TextMeasureFigletExt = "FIGlet"` under `[extensions]`.
- `ext/TextMeasureFigletExt.jl` provides:
  - Keyword constructor `FigletBackend(; font::Union{String,FIGlet.FIGletFont}=FIGlet.DEFAULTFONT, letter_gap::Int=0)` — string → `FIGlet.readfont(name)`; `FIGletFont` → use directly. Mirrors the `font` parameter pattern in the existing exts; no separate `font_data` escape hatch needed because `FIGlet.readfont(io)` already handles user-supplied data.
  - `TextMeasure.measure(b::FigletBackend, text::AbstractString) -> Float64` summing per-character widths using `get(b.font.font_characters, c, b.font.font_characters[' '])` (missing-glyph fallback to space-width — `font_characters` is a `Dict{Char,FIGletChar}` and non-ASCII glyphs may be absent) and reading width from `size(thechar, 2)` (`thechar` is constructed as `Matrix{Char}(undef, height, width)`, so dim-2 is width — confirmed from `src/FIGlet.jl`). Plus `letter_gap * (length(text) - 1)`. Integer-valued cell counts, returned as `Float64` to honor the `measure` return-type contract.
  - `TextMeasure.font_metrics(b::FigletBackend) -> FontMetrics` derived from `b.font.header.height` (line advance) and `b.font.header.baseline` (ascent; descent = height − baseline).
  - **Does not implement `measure_bounds`** — Figlet is plain monospace-cell text with no styled-text analog (unlike Makie's `RichText`), so the 2-D bounded primitive does not apply.
  - Heavy commentary as a teaching artifact, explicitly framed as "the third example of the canonical weakdep-extension backend pattern" with cross-references to the existing two exts.

**Why we don't build our own parser/font store.** `FIGlet.jl` already ships exactly that — pure-Julia parser, bundled `FIGletFonts-0.5.0` Artifact, MIT license — under active-enough maintenance. Forking would be pure cost. The teaching value sits in `ext/TextMeasureFigletExt.jl` regardless of where the parser lives.

**Acceptance:**
- Deterministic test widths for known strings against `FIGlet.DEFAULTFONT` (`"Standard"`) and at least one other bundled font (e.g., `"Small"`): `using TextMeasure, FIGlet; measure(FigletBackend(), "hello") == <pinned value>`.
- The extension is correctly registered: importing `FIGlet` after `TextMeasure` activates the ext (verifiable via `Base.get_extension(TextMeasure, :TextMeasureFigletExt) !== nothing`).
- `FigletBackend` passes backend conformance tests (cell-space measurement, integer-valued widths returned as `Float64`, ascent/descent matches `FIGletHeader` fields).
- `Project.toml`'s `[compat]` block pins a `FIGlet = "0.2"` lower bound.
- The ext file's preamble explains the pattern; `AbstractMeasurementBackend`'s docstring cross-references all three exts.
- CI runs an integration test against the actual published `FIGlet.jl`.
- `CHANGELOG.md` entry under "Added."

**Blocks:** #E.

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
- `chord_fn(y_top::Real, y_bottom::Real) -> Vector{Tuple{Float64,Float64}}` returns the horizontal intervals **where text can be placed** in the band `[y_top, y_bottom]` (block-top coord frame, matching `layout`).
- **Relationship to pretext.js.** Inspired by pretext's per-band scanline approach (`wrap-geometry.ts`) but **the signatures differ**: pretext's `getPolygonIntervalForBand` returns a single envelope `Interval | null` representing an OBSTACLE; pretext then subtracts obstacle envelopes from the base column via `carveTextLineSlots` to compute available slots. Our `chord_fn` returns available intervals directly, which lets the same primitive serve both text-INSIDE-shape (asteroid TUI, where the silhouette IS the available area) and text-AROUND-obstacle (DOIInfograph figure pillar, map feature, cover) use cases without the subtract step. Disjoint runs are preserved (a concave silhouette can have multiple runs within a band).
- Returned `(left, right)` pairs are **sorted ascending and pairwise disjoint** (callers can assume non-overlapping runs).
- An empty vector means no chord intersects this band (skip the band).
- **Multi-interval packing policy:** when a band has multiple disjoint intervals, `shape_pack` packs into the **widest** one and ignores the others; words are never split across disjoint intervals. Bands where the widest interval is below `min_chord_width` are skipped.
- A typed callable `AbstractChordFn` with dispatched `chord_intervals(shape, y_top, y_bottom)` is **the preferred long-term API**; for milestone-1 a plain `Function` closure is acceptable, but the helper constructors below return typed wrappers to ease the future migration.

**Two `chord_fn` constructors as helpers:**
- `polygon_chord_fn(polygon::Vector{GeometryBasics.Point2{Float64}}) :: PolygonChordFn` — scanline intersection of a 2-D polygon. (`Point2{Float64}` pinned to GeometryBasics for downstream interop with Makie's plotting types.)
- `raster_chord_fn(raster::BitMatrix, cell_size::Real) :: RasterChordFn` — for cell-grid silhouettes (Tachikoma).

**Overflow strategies:** `:widest_row` (default — render in the widest available row, accept overflow), `:skip` (drop the segment, add to `overflowed`), `:reject` (return empty `PackedLayout` with all subsequent segments in `overflowed`).

**Acceptance:**
- Pack into rectangle of width `w` produces the same line breaks as `layout(prep; max_width=w)`.
- Pack into circle (smoke test on known font + text).
- Pack into concave U-shape; slivers below `min_chord_width` are dropped.
- `overflowed` correctly populated when a word exceeds the widest available chord.
- Coord-frame consistency: `placements[i].y` matches the corresponding `layout` baseline calculation for rectangular packs (within floating tolerance).
- **Relative perf baseline:** packing Vermont's state polygon at 300 DPI (~600 scanlines × ~30 edges) produces a `PackedLayout` and the wall-clock is recorded as a committed timing baseline. Subsequent CI runs flag regressions of >2× against this baseline. Absolute target intentionally unspecified — the baseline is comparative.

**Blocks:** #E, #F2, #G, #H. Flagged for eventual migration to `TextMeasureLayouts.jl` sibling package.

### #D — `examples/silhouettes/`

Three exports:

- `asteroid_polygon(rng::AbstractRNG; n::Int=12, lumpiness::Float64=0.4) -> Vector{GeometryBasics.Point2{Float64}}` — polar Perlin noise (CoherentNoise.jl). `n ∈ [6, 32]` controls vertex count around the polar circle (default 12 yields chunky asteroid shapes). `lumpiness ∈ [0.0, 1.0]` is the fractional radius noise amplitude — `0.0` = perfect circle, `1.0` = wildly irregular star-shape. Returns CCW-ordered vertices.
- `voronoi_shatter(polygon::Vector{Point2{Float64}}, impact::Point2{Float64}; n_shards::Int=4) -> Vector{Vector{Point2{Float64}}}` — DelaunayTriangulation.jl seeded near `impact` (jittered seeds within `min(width, height) / 4` of impact), clipped to parent with GeometryOps.jl. `n_shards ∈ [2, 8]`; default 4.
- `rasterize(polygon::Vector{Point2{Float64}}, cell_size::Real) -> BitMatrix` — `cell_size > 0` is the width and height of one terminal cell in polygon-coordinate units. Returns a BitMatrix with `true` indicating cells inside the polygon (point-in-polygon test on each cell center).

**Acceptance:**
- Shape validity smoke tests (CCW orientation, simple polygons, no self-intersections).
- `voronoi_shatter(poly, pt; n=4)` returns 4 polygons whose union equals `poly` within numerical tolerance and whose pairwise intersections are zero-measure.

**Blocks:** #E only.

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

**Plan B for Tachikoma.** Tachikoma is the primary substrate. If it proves unworkable (upstream API churn, abandonment, fundamental fit issue), the fallback is a manual game-loop built on **`REPL.Terminals`** (stdlib — `TTYTerminal`, raw-mode toggle) **+ `Base.RawFD` + `termios` ioctl + manual ANSI escape codes**, double-buffered into a cell raster. The demo's core (`shape_pack` against a cell raster + FigletBackend measurement) is renderer-agnostic; only the event loop and draw plumbing would need rework. (`REPL.TerminalMenus` is **not** the Plan B — it's a blocking menu API, not a raw-mode-polling game-loop substrate. `TermInterface.jl` is unrelated — it's the JuliaSymbolics expression-interface package, not a terminal library.)

**Cross-platform scope:** Linux and macOS only for v1. Windows is OOS due to ANSI / raw-mode / sigwinch fragility.

**Julia compat:** Tachikoma.jl requires Julia 1.12+, which is higher than TextMeasure's 1.11 floor. Because each demo carries its own `Project.toml`/`Manifest.toml`, `examples/asteroid_tui/Project.toml` will set `julia = "1.12"` independently of TextMeasure proper. This does not affect TextMeasure's published compat.

**Acceptance:**
- Hit one asteroid, observe legible split into two shard-prose chunks (**"legible" defined operationally:** every glyph from the original prose appears in exactly one shard's render, in original order, with no character drops or duplicates).
- ≥30fps on Linux/macOS in a 120×40 terminal during steady-state play with ~5 asteroids (measured via wall-clock between frame swaps).
- Debug overlay correctly highlights every measured word.
- Respawn flash + invulnerability works as described.
- Headless tick-loop test in CI (no actual terminal needed): boot game, run 60 ticks of a scripted scenario, snapshot the cell buffer, checksum against a committed golden.

**Depends:** #A, #B, #C, #D.

### #F1 — DOIInfograph data layer (`examples/doi_infograph/data/`)

**Scope:** API clients for OpenAlex and CrossRef; thin wrapper over the existing `SemanticScholar.jl` for the `tldr` field; abstract reconstruction from OpenAlex's inverted index; opt-in `og:image` scraping; offline-cached responses for the acceptance DOIs.

**Existing packages we depend on** (verified directly against JuliaRegistries / GitHub at design time): `SemanticScholar.jl` (tmthyln, registered, UUID `f2f2c3a1-78ca-4323-b152-8442c77f9dcc`, v1.0.0) is the existing client for Semantic Scholar — **we depend on it directly rather than wrapping S2 ourselves**. `Pitaya` (naustica, GitHub-only, UUID `0b12f483-…`, stale 2021) is the only existing Julia CrossRef client; cited as prior art but we still write our own thin `CrossRefClient` against current HTTP.jl. No `OpenAlex.jl` exists.

- `OpenAlexClient(; mailto::String)` — `HTTP.jl` + `JSON3.jl`. Reconstruct abstract from `abstract_inverted_index`: emit one `(word, position)` pair per occurrence (handles multi-position words like `"of" → [2, 34, 49, …]`), sort globally by position, join with single spaces. Edge cases: **duplicate positions** (rare but observed) are resolved by stable sort with word order; **position gaps** (rare) are tolerated as missing words and yield extra inter-word spacing. **Reconstruction is content-equivalent, not byte-equivalent** — the inverted index drops case-folding info, mangles entities, and removes some punctuation; exact-bytes recovery is not achievable.
- `CrossRefClient(; mailto)` — fallback metadata and references. Mirrors Pitaya's `works(doi="…")` API shape on current HTTP.jl.
- Semantic Scholar `tldr` comes from **`SemanticScholar.jl`** directly — `fetch_doi_metadata` adapts its `Paper`/`fetch` response into our `PaperMetadata`'s `tldr` field. **Coverage caveat:** S2 product docs note TLDRs are "currently limited to computer science and biomedical domains." Slot-3 (PLOS ONE general OA) and slot-6 (no-abstract) may legitimately lack `tldr`; the data layer surfaces this as `tldr::Nothing`.
- `fetch_doi_metadata(doi; fetch_figure=false)` returns a `PaperMetadata` struct with fields: `title::String`, `authors::Vector{AuthorRef}` (where `AuthorRef` is a small struct with `given`, `family`, optional `affiliation`), `abstract::Union{String,Nothing}`, `tldr::Union{String,Nothing}`, `citation_count::Int`, `citations_by_year::Vector{Tuple{Int,Int}}` (year, count), `concepts::Vector{Tuple{String,Float64}}` (name, score), `oa_status::Symbol` (∈ `:gold, :green, :hybrid, :closed, :unknown`), `oa_url::Union{String,Nothing}`, `figure_url::Union{String,Nothing}` (`nothing` when `fetch_figure=false` or scrape failed), `pp::Union{String,Nothing}` (printed page range as a string, e.g., `"505–510"`; `nothing` if unavailable), `journal::Union{String,Nothing}`, `year::Union{Int,Nothing}`, `doi::String`.
- `fetch_figure=false` by default — to respect publisher ToS. When opt-in, scrapes `og:image` from publisher page with explicit `User-Agent: TextMeasure.jl/<version> mailto=<user>` header.
- **All six** acceptance DOIs (see #F3) have their JSON responses **cached to `examples/doi_infograph/data/cache/`** for offline + reproducible CI.

**Acceptance:**
- All six acceptance DOIs round-trip via offline cache.
- Abstract reconstruction from OpenAlex inverted index is **content-equivalent** to the canonical published text on the three DOIs that have abstracts (every non-stop-word token appears in order; whitespace/punctuation differences tolerated).
- `fetch_figure=false` is the default; opt-in path documented in the demo README with publisher-ToS note.
- Rate-limit handling: 429 → exponential backoff with `Retry-After` honored.

**Blocks:** #F2.

### #F2 — DOIInfograph adaptive layout engine (`examples/doi_infograph/layout/`)

**Scope:** the measurement work. Given a `PaperMetadata` and a CairoMakie `Figure` (with a fixed page size), produce a composed page.

**Adaptive primitives (each is a measurement-driven choice the spec calls out by name):**
- **Title autoshrink** — binary search **over backends constructed at different fontsizes** (NOT via a third arg to `measure`, which doesn't exist — `measure(b, text)` returns px at the backend's own baked-in fontsize). Bounds: `fs_min = 14.0`, `fs_max = 48.0`; ~6 iterations to ±0.5 px. Constraint: `measure(b_fs, title) ≤ title_box_width` and line count ≤ 2 from `layout(prepare(b_fs, title); max_width=title_box_width)`.
- **Author overflow** — accumulate measured author widths until next would exceed the row; append "et al." atomically.
- **TLDR autosize** — fontsize chosen so measured line-count × line-advance fills (not exceeds) the TLDR box height. **Bounds:** `fs_min = 9.0`, `fs_max = 14.0` (body-text range; never grows into display sizes even if TLDR is one short sentence).
- **Drop cap** — uses a SEPARATE `MakieBackend` at `dropcap_fontsize ≈ 3 × body_fontsize` (display-size, distinct from body backend). Wrap offset = `measure(dropcap_backend, first_letter)` + configurable gutter (default 4 px) for the first paragraph's first three lines.
- **Body text wrap around figure pillar** — text column on the left at fixed width; figure pillar on the right at full body height.
- **Concept pill wrap** — pills measured as atomic segments; greedy fit into the pill strip width with row wrap.
- **Citation sparkline** — Unicode block characters chosen so the sparkline's measured width matches the surrounding caption's measured width within ±1 glyph.

Body justification uses greedy `layout` by default. If #K ships, opt into K-P via `infograph(doi; justification=:knuth_plass)`. If `:knuth_plass` is requested but #K is not shipped (i.e., `examples/layouts/knuth_plass.jl` is absent at runtime), silently fall back to greedy with a one-time `@warn` per Julia session. The valid `template` values are `:editorial` (default; the single composed-cover template described in this issue); other values are reserved for future templates and currently throw `ArgumentError`.

**Acceptance:**
- **Property test (synthetic):** generate 100 random titles of lengths in [10, 200] chars; for every one, title autoshrink terminates with a fontsize where the title fits in ≤ 2 lines at the title box width. No exceptions.
- **Integration test against #F1 cached fixtures:** run `infograph` end-to-end against the six cached `PaperMetadata` objects produced by #F1; verify each renders without error and yields a `CairoMakie.Figure`. This catches regressions at the #F1↔#F2 seam (e.g., inverted-index sort stability) that the synthetic test misses.
- **Comparative test:** Sycamore renders smaller than Attention in the same title box (verifiable assertion on fontsize delta).
- **Author overflow test:** Sycamore (>50 authors — exact count varies by source) emits "et al."; Attention (8 authors) fits all eight.
- Sparkline length matches measured caption width within ±1 glyph across all three acceptance DOIs that have citation timelines.

**Depends:** #F1, #C.

### #F3 — DOIInfograph 6-up grid + Pluto wrapper (`examples/doi_infograph/`)

**Scope:** the gif-able / README-hero exhibit.

- `grid_infograph(dois::Vector{String}) -> CairoMakie.Figure` composes a 2×3 (or 3×2) grid of infographs for six canonical demonstration DOIs. The actual DOI list lives at `examples/doi_infograph/data/canonical_dois.toml` (the file is the source of truth; the spec commits slots 1–2 by exact DOI and slots 3–6 by selection criterion):
  1. **`10.1038/s41586-019-1666-5`** — Sycamore quantum supremacy (Nature, hybrid OA, long title, >50 authors — Nature lists 77, Semantic Scholar 76).
  2. **`10.48550/arXiv.1706.03762`** — Attention Is All You Need (arXiv preprint of the NeurIPS paper, green OA, short title, 8 authors).
  3. *Criterion: PLOS ONE OA paper with CC-BY license and abstract reliably present via OpenAlex or CrossRef.* Implementation picks a specific DOI and records it in `canonical_dois.toml`.
  4. *Criterion: arXiv preprint with title length ≥ 80 characters and no journal-deposited abstract* (low or zero citation count is fine — this slot stresses title autoshrink and no-abstract degradation).
  5. *Criterion: Nature Genetics or similar GWAS paper with ≥ 80 authors* — exercises author-overflow.
  6. *Criterion: paper with no OpenAlex `abstract_inverted_index` AND no Semantic Scholar `tldr`* (CrossRef has only title + authors). This slot tests the deepest graceful-degradation path; #F3's slot-6 acceptance bullet covers the visual render.
- Pluto notebook (`Demo.jl`): paste a DOI, render single infograph, slider for page width drives layout reflow, "Export PDF" button.

**Acceptance:**
- The 6-up grid renders as a single composed `CairoMakie.Figure` with the six panels in a 2×3 (or 3×2) grid. It exports to a **single-page composite PDF** (the grid as one page) and a **single composite PNG** (used as the README hero). The composite PDF is linked beside the PNG in the README for per-panel detail (small-PNG-in-README readability concern). For per-paper PDFs, callers loop `infograph(doi)` over the six DOIs and save each separately — that's a documented usage pattern, not a built-in grid_infograph option.
- All six papers produce legible, composed infographics — no overlapping text, no clipped figures.
- **Slot 6 (no abstract + no TLDR) graceful render:** the abstract/TLDR slot displays the concept pills strip enlarged + a small "abstract unavailable" caption in muted type. The page does not contain empty whitespace where the abstract would go. Explicit acceptance bullet — this case is not hand-waved.
- Pluto slider reflows the layout within ~500ms of slider change (with CairoMakie's static render).
- Cached API responses make the Pluto demo runnable offline.

**Depends:** #F2.

### #G — CairoMakie Map Feature Page (`examples/map_feature/`)

**Reframed scope.** State silhouette is rendered as a **real cartographic map** (cities, POIs, capital, landmarks, geographic features). Editorial prose **wraps around the silhouette as an irregular obstacle** (the pretext.js *Dynamic Layout* pattern). National Geographic / Smithsonian state-feature spread aesthetic.

`map_feature(state_polygon::Vector{GeometryBasics.Point2{Float64}}, stats::Dict{Symbol,Any}, points_of_interest::Vector{POI}) -> CairoMakie.Figure`.

`POI` schema: `struct POI; name::String; coord::Tuple{Float64,Float64}; kind::Symbol; end` where `kind ∈ (:city, :capital, :landmark, :feature)` controls icon glyph + label weight.

Layout:
- State map fills the right ~55% of the page (silhouette + cartographic content inside).
- Editorial prose wraps around the silhouette on the left using `shape_pack` driven by a `complement_chord_fn(polygon, page_bounds)` helper (NOT `polygon_chord_fn` — that returns intervals INSIDE the polygon, which would pack text into the state shape). `complement_chord_fn` returns `[page_left, polygon_left_edge] ∪ [polygon_right_edge, page_right]` per band. Owned by `#G`'s source tree, shared with `#H`. Polygon coordinates passed in must already be in page-pixel space; the CRS reprojection (TIGER lat/lon → Albers/Mercator pixels via GeoMakie) happens before `shape_pack` is called.
- Magazine masthead at top, byline at bottom.
- Sidebar callouts (population, GDP, capital) as big-number stats.

**Data layer:**
- US Census Tiger/Line shapefiles (state polygons) — public-domain US gov't data, accessed via **`CensusACS.jl`** (registered, UUID `5cdc1628-db7d-4f1a-9a42-d0831b0d3a5e`, v0.1.0). That package provides both shapefile download (2023 state/county 500k geographies) and `get_acs(...)` state stats — covers both our shapefile and sidebar-callout needs without building a TIGER client from scratch.
- **A minimal Vermont shapefile is bundled in-repo** (`examples/map_feature/data/vermont.shp` + sidecar files, ~50KB) as a fast-path fallback so the demo's quickstart is runnable even if `CensusACS.jl`'s download endpoint is unreachable.
- For other states, fetched on first run via `CensusACS.jl`; cached to `~/.julia/scratchspaces/...`.
- POIs from a curated `examples/map_feature/data/pois.toml`. **Target depth: 8–15 POIs per acceptance state**, drawn from the state's Wikipedia article and hand-edited for typography. Composition per state: 1 capital + 3–5 cities (population-ranked) + 2–4 landmarks (natural + cultural) + 1–2 geographic features (mountain range, lake, river).

**Acceptance:**
- Vermont (quickstart) renders entirely from bundled data, no network required.
- Additional acceptance states (California, Texas, Florida, Hawaii — varying silhouette complexity from simple → highly irregular) produce legible map feature pages with cached Census data.
- Editorial text flows around the state silhouette without overlapping the map.
- POI labels on the map are placed without overlap using simple offset placement (note: harder repel cases are out of scope here; user's in-flight ggrepel-style package will handle them).
- Pages export cleanly to PDF with selectable text (verified by extracting text from the exported PDF and checking it matches input strings).

**Depends:** #C.

### #H — CairoMakie "Newer Yorker" correctness exhibit (`examples/cover/`)

**Reframed pitch.** The demo whose job is to **prove the library is correct**, not just gif-able. The honest acceptance test is **"no manual offsets"** — change the SVG inset's position by 3 pixels, re-render, every other element re-aligns correctly because every offset was measurement-derived, not hardcoded.

Hand-set editorial cover: title in display type, body text flowing around an SVG illustration inset (uses `shape_pack`), drop cap, pull-quote callouts. No data ingest; static content from `cover.toml`. Body justification uses greedy `layout` (or K-P if #K shipped).

**`cover.toml` schema:**

```toml
[meta]
title    = "..."             # display title
subtitle = "..."             # optional
byline   = "..."             # author/credit line

[layout]
page_size = "letter"         # "letter" | "a4" | "tabloid"
margin_px = 36               # uniform page margin

[inset]
svg_path   = "data/x.svg"    # path relative to the cover.toml file
x_px       = 240             # top-left corner in page coords (excl. margin)
y_px       = 120
width_px   = 200
height_px  = 280

[[body]]                     # array-of-tables — paragraphs in order
paragraph = """..."""
dropcap   = true             # optional; applies only to the FIRST paragraph

[[body]]
paragraph = """..."""

[[pull_quote]]               # array-of-tables — zero or more callouts
text         = "..."
attribution  = "..."         # optional
x_px         = 60
y_px         = 480
width_px     = 180
```

The three acceptance fixture files (`cover-v1.toml`, `cover-v2.toml`, `cover-v3.toml`) vary the `inset` block (position + size) while keeping `meta` and `body` similar enough to verify the layout adapts without manual code changes.

**Acceptance:**
- The demo ships with three `cover-v1.toml`, `cover-v2.toml`, `cover-v3.toml` files where the SVG inset is at different positions/sizes. All three produce visually composed PDFs with no manual layout code changes between renders.
- **Property test (random insets, catches author-tuned-TOML blind spots):** generate 20 random SVG inset positions within the page bounds (inset width/height also randomized within reasonable ranges). For each, render the cover and verify the "no manual offsets" invariants hold: (a) drop cap baseline aligns with paragraph baseline within ±0.5px, (b) pull-quote callouts do not overlap body text or the SVG inset (bbox intersection check), (c) body wrap honors the inset boundary at every line. If any of the 20 fail, the test fails.
- Drop cap's baseline aligns with paragraph baseline within ±0.5px (measured from rendered PDF).
- Pull-quote callouts do not overlap body text or the SVG inset (verified by bbox intersection check on rendered PDF).
- SVG inset is rendered as native CairoMakie vector content, not a bitmap.
- PDF text is selectable (font embedding verified).

**Depends:** #C.

### #I — README hero, gallery, release hygiene

Cross-cutting integration work:
- README hero: the **6-up DOIInfograph grid PNG** (committed binary). A **high-resolution PDF version of the same grid is linked beside the PNG** so users can inspect per-panel detail that GitHub's PNG rendering may shrink.
- README's "Backends" section updated to include `FigletBackend` — activated by `using FIGlet` (kdheepak's existing FIGlet.jl, install via `Pkg.add("FIGlet")`).
- `examples/README.md` as the gallery index — each demo with one-line pitch, screenshot, run instructions.
- Each `examples/<demo>/README.md` exists with run instructions and a `Project.toml` / `Manifest.toml` ready for `julia --project=. -e 'using Pkg; Pkg.instantiate()'`.
- `CHANGELOG.md` updated with one entry per shipped issue.
- Documenter.jl integration: a `docs/` build (basic — landing page + each public API page + link to the gallery). GitHub Pages deploy workflow optional (see Open Questions).
- License headers on every file in `examples/`. Match parent (MIT) unless a sibling package needs a different license.
- Version bump to 0.2.0 with summary in CHANGELOG.

**Acceptance:**
- README hero PNG loads in GitHub view; high-res PDF link works.
- All `examples/<demo>/README.md` files exist and accurately describe the run flow.
- `CHANGELOG.md` reflects every shipped issue.
- `docs/build/` succeeds locally and in CI.
- License audit passes (every `examples/` file has a header; sibling-package licenses verified).
- Version 0.2.0 tagged after this issue lands.

**Depends:** all completed demos.

### #J — Demo health CI + golden snapshots + property tests + license gate

New cross-cutting issue addressing the "demos rot silently" failure mode. Without this, the demos drift the moment a dependency moves.

**Scope:**
- **Weekly scheduled GitHub Actions workflow** that boots each demo in CI:
  - **#E asteroid:** headless tick-loop, 60 ticks, snapshot cell buffer, checksum vs committed golden.
  - **#F3 DOIInfograph:** render the 6-up grid from cached responses, extract text from exported PDF, checksum.
  - **#G map feature:** render Vermont's page from bundled data (no network), checksum exported PDF text.
  - **#H newer yorker:** render `cover-v1.toml`, checksum exported PDF text.
- **Failure-to-issue plumbing:** the workflow searches for an open issue with a canonical title (e.g., `[demo-health] {demo-name} regression`); reopens or comments on it if found, opens a new one only if missing. **Auto-closes the issue on the next successful run.** This prevents maintainer fatigue from a flaky upstream filing 50 issues a year.
- **CI matrix gate** (regular CI, not weekly): Linux and macOS for all demos; Windows for the CairoMakie demos (#F3, #G, #H) only — the asteroid TUI's Linux-and-macOS-only scope is enforced by a CI exclusion. Includes a font-pinning step: install a minimal known font set (`DejaVu Sans`, `Liberation Serif`) on each runner before CI runs the demos that depend on them.
- **Property tests** in regular CI:
  - Autoshrink property test (from #F2): 100 random title lengths all fit.
  - Cover random-inset property test (from #H): 20 random insets all uphold invariants.
  - `shape_pack` invariants (from #C): every `Placement.segment_index ∈ [1, length(prep.segments)]`; placements per band do not exceed band's chord intervals; overflowed segments do not have placements.
- **License audit gate** in regular CI: every file in `examples/` has a license header.

**Acceptance:**
- Weekly health-check workflow at `.github/workflows/demo_health.yml`; runs successfully against all four demos.
- Workflow correctly dedupes against existing issues; auto-closes on green.
- Property tests added to `test/` and run on every PR.
- CI matrix runs on Linux and macOS; CairoMakie demos additionally tested on Windows (asteroid TUI excluded from Windows).
- Font pinning step succeeds on every runner before demo execution.
- License audit gate fails CI if any `examples/` file lacks a header.

**Depends:** completed demos (acceptance criteria reference each).

### #K [STRETCH] — Knuth–Plass justification utility + comparison demo

Two pieces, shipped only if appetite remains after #A–#J:

1. **`examples/layouts/knuth_plass.jl`** — port of pretext.js's `kp.ts`. Consumes `Prepared.segments`; emits optimal line breaks minimizing total badness. Same input as `layout` and `shape_pack`; different output algorithm.
2. **`examples/justification/`** — separate demo: three columns of the same paragraph (greedy from `layout`, greedy with hyphenation off, K-P), with river visualizers overlaid. Direct port of pretext.js's `justification-comparison` demo.

**Decoupling from #F/#H:** #F2 and #H ship with greedy `layout` body justification by default. If #K lands, opt-in via `infograph(doi; justification=:knuth_plass)` and `cover(toml; justification=:knuth_plass)`. The non-stretch demos are NOT load-bearing on #K.

**Acceptance:**
- K-P produces measurably lower total badness than greedy on a canonical test paragraph.
- River overlay correctly identifies known rivers in greedy output that K-P avoids.
- Comparison demo renders all three columns side-by-side as a single PDF.

## Dependency graph & build waves

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

**Wave 1 — Unblockers (all parallel):** #A, #B, #C, #D. All four are independent; ship them concurrently. #C is on the critical path because it blocks the most downstream issues.

**Wave 2 — Demos (parallel after wave 1):**
- #E asteroid TUI — depends on all four wave-1 items.
- #F1 → #F2 → #F3 — strict serial chain (data layer → adaptive layout → 6-up grid + Pluto). #F1 only depends on no internal issue; #F2 needs #C as well.
- #G map feature page — depends on #C.
- #H correctness exhibit — depends on #C.

**Wave 3 — Integration (after wave 2):** #I (README, gallery, release hygiene) and #J (demo health CI) both depend on all completed demos. #J's regression findings feed back into the demos that own them, not into #J's own backlog.

**Stretch:** #K Knuth–Plass — can interleave with wave 2 if appetite. If shipped before #F2/#H polish, both #F2 and #H opt into it via a kwarg.

## If scope must shrink

The minimum value-proof subset that still demonstrates measure-once-layout-many: **#A + #C + a single hardcoded DOI infograph (a slice of #F1+#F2+#F3) + the README hero PNG (a slice of #I).** This ships one composed PDF demonstrating `prepare` once → `shape_pack` for the abstract → `layout` for the title, with no API client and no Pluto wrapper. Everything else defers. This is the fall-back escape hatch, not the planned path.

## Risks

**R1. `pick()` per-glyph behavior on Makie `text!` plots.** Not actually needed by the asteroid TUI (Tachikoma handles input directly), so this risk is closed for the milestone but flagged for any future Makie-based asteroid variant.

**R2. CrossRef abstract availability + Semantic Scholar TLDR coverage.** DOIInfograph relies on OpenAlex `abstract_inverted_index`. Graceful degradation when OpenAlex also lacks one — Semantic Scholar TLDR promoted to the abstract slot at enlarged size, **fetched via the existing registered `SemanticScholar.jl` package, not a bespoke wrapper.** S2's TLDR coverage is limited to CS + biomedical domains per their docs; slot 3 (general OA) and slot 6 (no-abstract) may legitimately lack `tldr`. Slot 6 of the 6-up grid (no abstract + no TLDR) has its own explicit graceful render path (concept pills enlarged + "abstract unavailable" caption); see #F3 acceptance.

**R3. K-P implementation effort.** Stretch status preserved; #F/#H decoupled.

**R4. `og:image` scraping legality + reliability.** `fetch_figure=false` default in #F1; geometric placeholder fallback; opt-in path documented with explicit ToS note.

**R5. Tachikoma maturity.** Pin a specific version in #E's `Project.toml`; **Plan B documented in #E:** `REPL.Terminals` (stdlib) + `Base.RawFD` + `termios` + manual ANSI as the actual fallback substrate (not REPL.TerminalMenus, and not TermInterface.jl which is a symbolic-expression package).

**R6. Tachikoma upstream churn beyond version pin.** A 4-month-old TUI framework will not have a long support window. #J's weekly health-check workflow catches breakage within a week; the maintainer issue is auto-filed (and auto-closes on next green).

**R7. Cross-platform.** #E scoped to Linux + macOS only. CairoMakie demos work on all three OSes but require system Cairo + Pango + fonts. #J's CI matrix gates Linux + macOS for all demos and adds Windows for the CairoMakie demos; font pinning in CI prevents per-runner font drift.

**R8. Figlet font licensing — closed.** Resolved by depending on `FIGlet.jl` (MIT-licensed, kdheepak) which ships its own bundled `FIGletFonts-0.5.0` Artifact. We don't redistribute fonts ourselves; the licensing concern moves upstream.

**R9. API rate limits.** Mitigated by offline caching of acceptance-DOI responses in #F1. Live use respects `Retry-After`; uses `mailto=` polite pool.

**R10. US Census Tiger/Line shapefile distribution.** #G fetches state shapefiles + ACS stats via the registered **`CensusACS.jl`** (UUID `5cdc1628-…`, v0.1.0) — that package handles the TIGER download endpoint. #G additionally bundles a minimal Vermont shapefile in-repo as a fast-path fallback if CensusACS's endpoint is unreachable. Other states fetched on demand via `CensusACS.jl` and cached to `~/.julia/scratchspaces/`.

**R11. PDF text selectability vs outlined paths.** Acceptance criteria in #F3, #G, #H explicitly verify text selectability by extracting text from the exported PDF and matching against input strings.

**R12. Demo rot.** Addressed by #J (weekly health-check CI + golden snapshots + license-audit gate + dedup auto-issue plumbing).

**R13. Polygon scanline performance at print resolution.** #C includes a relative perf-regression bullet: pack Vermont's polygon at 300 DPI, record the wall-clock as a committed timing baseline, CI flags regressions of >2× against it. Absolute targets intentionally unspecified.

**R14. Pluto + CairoMakie + slider sluggishness.** #F3 acceptance is "reflow within ~500ms," not "instant"; cache the rendered figure and only re-layout (not re-render the figure asset) on slider change.

## Open questions

- **#K go/no-go.** Decide after #A–#J land.
- **Sibling-package promotion timing.** `TextMeasureLayouts.jl` registers on JuliaRegistries when? Probably post-milestone, gated on demand.
- **Documenter.jl hosting.** GitHub Pages from the docs build? `#I` ships skeleton only; deploy workflow deferred to a follow-up.

## External Julia packages this milestone depends on (verified)

Quick reference, with UUIDs and roles. Every entry was verified against its GitHub Project.toml during the round-4 reviewer pass:

| Package              | UUID                                       | Where               | Role                                                                |
|----------------------|--------------------------------------------|---------------------|---------------------------------------------------------------------|
| `FIGlet`             | `3064a664-84fe-4d92-92c7-ed492f3d8fae`     | `#B` weakdep        | `.flf` parser + bundled `FIGletFonts-0.5.0` Artifact                |
| `SemanticScholar`    | `f2f2c3a1-78ca-4323-b152-8442c77f9dcc`     | `#F1` regular dep   | TLDR field — used directly, NOT re-wrapped                          |
| `CensusACS`          | `5cdc1628-db7d-4f1a-9a42-d0831b0d3a5e`     | `#G` regular dep    | TIGER shapefile download + ACS state stats                          |
| `Tachikoma`          | (Kahli Burke / kahliburke, registered)     | `#E` regular dep    | Pure-Julia TUI substrate (primary; Plan B = `REPL.Terminals`)       |
| `CoherentNoise`      | (lazarusA, registered)                     | `#D` regular dep    | Perlin noise for `asteroid_polygon`                                 |
| `DelaunayTriangulation` | (JuliaGeometry, registered)             | `#D` regular dep    | Voronoi for `voronoi_shatter`                                       |
| `GeometryOps`        | (JuliaGeo, registered)                     | `#D`, `#G` reg dep  | Pure-Julia polygon clipping / union / intersection / area           |
| `Shapefile`          | (JuliaGeo, registered)                     | `#G` regular dep    | Parsing bundled Vermont fixture                                     |
| `GeoMakie`           | (MakieOrg, registered)                     | `#G` regular dep    | CRS projection (TIGER → Albers/Mercator pixels)                     |
| `CairoMakie`         | (MakieOrg, registered)                     | `#F3`,`#G`,`#H` dep | PDF render target                                                   |
| `Pluto`              | (registered)                               | `#F3` regular dep   | Slider-driven reflow demo                                           |

**Prior art we cite but don't depend on:**
- `Pitaya` (naustica, GitHub-only, UUID `0b12f483-…`, stale 2021) — the only existing Julia CrossRef client. Stale; we write our own thin client against current HTTP.jl.
- `AsteroidShapeModels.jl` (Astroshaper, registered) — loads 3D OBJ asteroid meshes for thermophysical simulation. Unrelated to our procedural 2-D `asteroid_polygon`; flagged for disambiguation only.

## Next steps

1. Reviewer convergence pass on this round-3 revision.
2. On reviewer convergence, user reviews the spec.
3. On user approval, invoke the writing-plans skill to produce a detailed implementation plan for #A–#D (the wave-1 unblockers).
4. Land #A and #B first (library + sibling package), then #C and #D (plumbing). Demos #E–#H land in parallel after.
