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
- Editorial prose wraps around the silhouette on the left (uses `shape_pack` with the state polygon as an obstacle, so the body flows in the negative space around the state shape).
- Magazine masthead at top, byline at bottom.
- Sidebar callouts (population, GDP, capital) as big-number stats.

### Data layer

- US Census Tiger/Line shapefiles (state polygons) — public-domain US gov't data.
- **A minimal Vermont shapefile is bundled in-repo** (`examples/map_feature/data/vermont.shp` + sidecar files, ~50KB) so the demo's quickstart is runnable without any network round-trip.
- For other states, fetched at first run via the Census's TIGER API; cached to `~/.julia/scratchspaces/...` to avoid repo bloat. Mirror fallback URL documented in the README.
- POIs from a curated `examples/map_feature/data/pois.toml`. **Target depth: 8–15 POIs per acceptance state**, drawn from the state's Wikipedia article and hand-edited for typography. Composition per state: 1 capital + 3–5 cities (population-ranked) + 2–4 landmarks (natural + cultural) + 1–2 geographic features (mountain range, lake, river).
- Census API for state stats (cached for offline CI).

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
- **External deps:** `CairoMakie.jl`, `Shapefile.jl`, `GeoMakie.jl`, `HTTP.jl` (for Census fetching).
- **Census API:** US TIGER (Topologically Integrated Geographic Encoding and Referencing) — public domain.
- **Conventions:** `CLAUDE.md`.

## Suggested labels

`demos-milestone` · `wave-2` · `examples` · `demo` · `juliageo`
