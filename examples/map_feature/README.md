# MapFeature — CairoMakie state map-feature page (#G)

A demo of [TextMeasure.jl](../..) + [TextMeasureLayouts](../layouts): a US-state silhouette
rendered as a cartographic map (capital, cities, landmarks, natural features) with **editorial
prose that wraps around the silhouette as an irregular obstacle** — the pretext.js *Dynamic
Layout* pattern applied to real geography. National Geographic / Smithsonian feature aesthetic.

## Quickstart (Vermont — fully offline, no network)

```bash
julia --project=examples/map_feature -e 'using Pkg; Pkg.instantiate()'
julia --project=examples/map_feature examples/map_feature/render_vermont.jl   # writes vermont.png + vermont.pdf
```

Vermont renders entirely from the **bundled** shapefile `data/vermont.{shp,shx,dbf}` (≈26 KB,
1634 vertices, subset from the US Census `cb_2023_us_state_500k` file) and the bundled POIs +
ACS stats in `data/pois.toml`. No Census endpoint is contacted.

## How the wrap works

`complement_chord_fn(polygon, page_bounds)` (in `src/complement_chord_fn.jl`) is the inverse of
`TextMeasureLayouts.polygon_chord_fn`: instead of the intervals *inside* a polygon, it returns
the **negative-space** intervals *around* it — `[page_left, env_left] ∪ [env_right, page_right]`
per band, where `[env_left, env_right]` is the silhouette's horizontal envelope at that band.
Feeding that to `shape_pack` flows the body text into the white space beside the state, so the
column hugs the silhouette's facing edge and never crosses the map. It is **pure interval
arithmetic** — no `GeometryOps` boolean ops (0.1.40's are unreliable; see #D).

The CRS reprojection (geographic lon/lat → page-pixel space, `src/projection.jl`) happens
**before** `shape_pack`, via `Proj.Transformation` to NAD83 / CONUS Albers (`EPSG:5070`).

## Other states

`fetch_state_shapefile("CA")` downloads the all-US Census state file via `CensusACS.jl`
(`get_tiger_shapefile`, curl over FTP) and extracts the requested state; ACS stats come from
`CensusACS.get_acs5(...)` which **requires `ENV["CENSUS_API_KEY"]`** (and network). Only
**single-part CONUS states (Vermont verified)** are in scope this milestone — multi-part states
(CA/FL/HI) lose their islands, and Hawaii needs its own equal-area projection (not `EPSG:5070`).

## Tests

`Pkg.test()` asserts tier-1 invariants only (no pixel diffing): `PackedLayout` bbox **non-overlap**
with the map envelope (checked independently of `complement_chord_fn`), POI-label pairwise
non-overlap, and **`pdftotext` selectability** of the exported PDF against a committed token-set
floor golden (`test/goldens/`). Renders use the pinned fonts **DejaVu Sans** (display) +
**Liberation Serif** (body) — the same set CI installs, so the golden is reproducible.
