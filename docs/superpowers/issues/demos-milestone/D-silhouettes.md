# D — `examples/silhouettes/`

> Wave 1 unblocker · shared example utility (used only by #E).

## Scope

Procedural shape generators for the asteroid demo.

- `asteroid_polygon(rng::AbstractRNG; n::Int=12, lumpiness::Float64=0.4) -> Vector{GeometryBasics.Point2{Float64}}` — polar Perlin noise via CoherentNoise.jl. `n ∈ [6, 32]` controls vertex count around the polar circle (default 12 yields chunky asteroid shapes). `lumpiness ∈ [0.0, 1.0]` is the fractional radius noise amplitude — `0.0` = perfect circle, `1.0` = wildly irregular star-shape. Returns CCW-ordered vertices.
- `voronoi_shatter(polygon::Vector{Point2{Float64}}, impact::Point2{Float64}; n_shards::Int=4) -> Vector{Vector{Point2{Float64}}}` — DelaunayTriangulation.jl seeded near `impact` (jittered seeds within `min(width, height) / 4` of impact), clipped to parent with GeometryOps.jl. `n_shards ∈ [2, 8]`; default 4.
- `rasterize(polygon::Vector{Point2{Float64}}, cell_size::Real) -> BitMatrix` — `cell_size > 0` is the width and height of one terminal cell in polygon-coordinate units. Returns a BitMatrix with `true` indicating cells inside the polygon (point-in-polygon test on each cell center).

## Acceptance

- Shape validity smoke tests (CCW orientation, simple polygons, no self-intersections).
- `voronoi_shatter(poly, pt; n=4)` returns 4 polygons whose union equals `poly` within numerical tolerance and whose pairwise intersections are zero-measure.
- `rasterize` produces expected BitMatrix for known polygon + cell_size combinations (e.g., unit square → all-true BitMatrix at any cell_size dividing 1).

## Depends on / Blocks

- **Depends on:** nothing.
- **Blocks:** #E only.

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#D — `examples/silhouettes/`."
- **External Julia deps:**
  - `CoherentNoise.jl` — Perlin/simplex noise functions.
  - `DelaunayTriangulation.jl` — Voronoi tessellation.
  - `GeometryOps.jl` — pure-Julia polygon clipping (no GEOS C dep).
  - `GeometryBasics.jl` — `Point2{Float64}` type pinned for downstream Makie interop.
- **Conventions:** `CLAUDE.md`.

## Suggested labels

`demos-milestone` · `wave-1` · `examples` · `shared-utility`
