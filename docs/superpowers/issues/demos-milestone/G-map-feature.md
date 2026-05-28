# G — CairoMakie Map Feature Page (`examples/map_feature/`)

> Wave 2 demo · the geo/editorial crossover exhibit.

## Scope

State silhouette rendered as a **real cartographic map** (cities, POIs, capital, landmarks, geographic features). Editorial prose **wraps around the silhouette as an irregular obstacle** (pretext.js *Dynamic Layout* pattern applied to real geography). National Geographic / Smithsonian state-feature spread aesthetic.

```julia
map_feature(state_polygon::Vector{GeometryBasics.Point2{Float64}},
            stats::Dict{Symbol,Any},
            points_of_interest::Vector{POI}) -> CairoMakie.Figure
```

`POI` schema: `struct POI; name::String; coord::Tuple{Float64,Float64}; kind::Symbol; end` where `kind ∈ (:city, :capital, :landmark, :feature)` controls icon glyph + label weight.

### Layout

- State map fills the right ~55% of the page (silhouette + cartographic content inside).
- Editorial prose wraps around the silhouette on the left (uses `shape_pack` with a **complement chord function** built from the state polygon — see `complement_chord_fn` note below — so the body flows in the *negative space* around the state shape, not inside it).
- Magazine masthead at top, byline at bottom.
- Sidebar callouts (population, GDP, capital) as big-number stats.

**`complement_chord_fn` (G owns this helper):** `shape_pack`'s `chord_fn` contract (#C) returns *available* intervals where text can be placed. For text-INSIDE-shape (asteroid TUI), the helper `polygon_chord_fn` returns intervals inside the polygon. For text-AROUND-obstacle (this issue + #H + #F2), we need the opposite: intervals representing the page's left/right white space, with the polygon's horizontal projection subtracted.

```julia
complement_chord_fn(polygon::Vector{Point2{Float64}}, page_bounds::NTuple{4,Float64})
```

returns a closure `(y_top, y_bottom) -> Vector{Tuple{Float64,Float64}}` that, per band, computes the polygon's [left_edge, right_edge] envelope and yields `[page_left, left_edge] ∪ [right_edge, page_right]` (each non-empty interval emitted as a tuple, dropping zero-width intervals). This helper lives in this issue's source tree (`examples/map_feature/src/complement_chord_fn.jl`) and is shared with #H (which wraps body text around the SVG inset).

**Coordinate-system note:** polygon coords passed to `complement_chord_fn` must already be in the **page pixel coordinate space** (same frame as `line_advance` / `FontMetrics`). The CRS reprojection (TIGER lat/lon → Albers or screen-pixels via GeoMakie) happens BEFORE `shape_pack` is called, in `map_feature`.

### Data layer

- US Census Tiger/Line shapefiles (state polygons) — public-domain US gov't data.
- **`CensusACS.jl`** (registered, technocrat, UUID `5cdc1628-db7d-4f1a-9a42-d0831b0d3a5e`, v0.1.0) is the existing Julia client for Census data. It provides:
  - **shapefile download** for 2023 state/county 500k geographies (covers our state-polygon need;  obviates building a TIGER client from scratch),
  - **`get_acs(...)`** for state population / income / housing stats (covers our sidebar-callout need).
  Depend on it for both shapefile fetch and state stats. The bundled Vermont shapefile becomes a **fast-path fallback** only (so `examples/map_feature` quickstart still works fully offline), not the primary load path.
- **A minimal Vermont shapefile is bundled in-repo** (`examples/map_feature/data/vermont.shp` + sidecar files, ~50KB) so the demo's quickstart is runnable without any network round-trip — even if `CensusACS.jl`'s download endpoint is unreachable.
- For other states, fetched at first run via `CensusACS.jl`; cached to `~/.julia/scratchspaces/...` to avoid repo bloat.
- POIs from a curated `examples/map_feature/data/pois.toml`. **Target depth: 8–15 POIs per acceptance state**, drawn from the state's Wikipedia article and hand-edited for typography. Composition per state: 1 capital + 3–5 cities (population-ranked) + 2–4 landmarks (natural + cultural) + 1–2 geographic features (mountain range, lake, river).

## Acceptance

- **Vermont (quickstart) renders entirely from bundled data, no network required.**
- Additional acceptance states (California, Texas, Florida, Hawaii — varying silhouette complexity from simple → highly irregular) produce legible map feature pages with cached Census data.
- Editorial text flows around the state silhouette without overlapping the map.
- POI labels on the map are placed without overlap using simple offset placement (harder repel cases out of scope; user's in-flight ggrepel-style package will handle them).
- Pages export cleanly to PDF with selectable text (verified by extracting text from the exported PDF and checking it matches input strings).

## Depends on / Blocks

- **Depends on:** #C.
- **Blocks:** #I, #J.

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#G — CairoMakie Map Feature Page."
- **External deps:**
  - `CairoMakie.jl` — render target.
  - `CensusACS.jl` (registered, UUID `5cdc1628-db7d-4f1a-9a42-d0831b0d3a5e`) — shapefile download + ACS state stats.
  - `Shapefile.jl` — parsing the bundled Vermont fixture (CensusACS handles the parsing of its own downloads).
  - `GeoMakie.jl` — used for the projection step (TIGER lat/lon → page pixel space) before handing polygons to `shape_pack`. Target projection: Albers Equal Area Conic for CONUS states; Mercator pixel-space for Hawaii.
  - `GeometryOps.jl` (transitive via #C / #D) — polygon manipulation for `complement_chord_fn`.
  - `HTTP.jl` — only if a non-CensusACS endpoint is fetched (e.g., a Wikipedia POI scrape if not hand-curated in TOML).
- **Census API:** accessed via `CensusACS.jl`, not directly — that package wraps the TIGER endpoint.
- **Conventions:** `CLAUDE.md`.

## Suggested labels

`demos-milestone` · `wave-2` · `examples` · `demo` · `juliageo`
