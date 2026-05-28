# SPDX-License-Identifier: MIT
# Part of TextMeasure.jl examples — see repository LICENSE (MIT).
"""
    Silhouettes

Procedural 2-D shape utilities for the asteroid demo (#E): silhouette generation,
Voronoi fracture, and rasterization to a terminal cell grid. Shared example
utility; depended on via `Pkg.develop` by `examples/asteroid_tui/`.
"""
module Silhouettes

using Random: AbstractRNG
import CoherentNoise as CN
import DelaunayTriangulation as DT
import GeometryOps as GO
import GeometryBasics as GB

const P2 = GB.Point2{Float64}

export asteroid_polygon, voronoi_shatter, rasterize

# Orient an open ring CCW (GeometryOps.signed_area > 0 == CCW, y-up).
_orient_ccw(pts::Vector{P2}) = GO.signed_area(GB.Polygon(pts)) < 0 ? reverse(pts) : pts

"""
    asteroid_polygon(rng; n=12, lumpiness=0.4) -> Vector{Point2{Float64}}

Procedural asteroid silhouette via polar Perlin noise. `n ∈ [6, 32]` vertices
around the polar circle; `lumpiness ∈ [0.0, 1.0]` is the fractional radius noise
amplitude (`0.0` = unit circle, `1.0` = wildly irregular). Returns an **open**
CCW ring (n vertices, no duplicated closing vertex). The radius is kept strictly
positive, so the polygon is star-shaped about the origin and hence simple.
"""
function asteroid_polygon(rng::AbstractRNG; n::Int=12, lumpiness::Float64=0.4)
    6 <= n <= 32 || throw(ArgumentError("n must be in [6, 32], got $n"))
    0.0 <= lumpiness <= 1.0 || throw(ArgumentError("lumpiness must be in [0.0, 1.0], got $lumpiness"))
    field = CN.perlin_2d(seed = rand(rng, UInt32))
    phase = 2π * rand(rng)
    pts = Vector{P2}(undef, n)
    for k in 0:(n - 1)
        θ = 2π * k / n
        nz = CN.sample(field, cos(θ + phase), sin(θ + phase))  # ∈ [-1, 1]
        r = max(1.0 + lumpiness * nz, 0.05)                    # strictly positive ⇒ star-shaped ⇒ simple
        pts[k + 1] = P2(r * cos(θ), r * sin(θ))
    end
    return _orient_ccw(pts)
end

# Sutherland–Hodgman clip of a (possibly concave) subject ring against the half-plane
# { x : dot(x - m, nrm) < 0 }. The strict `<` keep predicate and crossing test are consistent,
# so a vertex landing exactly on the boundary is never emitted twice. Returns an open ring
# (possibly empty).
function _clip_halfplane(poly::Vector{P2}, m::P2, nrm::NTuple{2,Float64})
    out = P2[]
    n = length(poly)
    for i in 1:n
        a = poly[i]; b = poly[mod1(i + 1, n)]
        da = (a[1] - m[1]) * nrm[1] + (a[2] - m[2]) * nrm[2]
        db = (b[1] - m[1]) * nrm[1] + (b[2] - m[2]) * nrm[2]
        da < 0 && push!(out, a)
        if (da < 0) != (db < 0)
            t = da / (da - db)
            push!(out, P2(a[1] + t * (b[1] - a[1]), a[2] + t * (b[2] - a[2])))
        end
    end
    return out
end

# Clip a (possibly concave) subject ring against a CONVEX clip ring ⇒ subject ∩ clip.
# Folds the half-plane clip over each directed edge of the CCW-oriented convex clip (interior is
# to the left of each edge; inward normal of edge (ex,ey) is (ey,-ex) under our `< 0` convention).
# Returns an open ring (possibly empty).
#
# DEVIATION from issue #D ("clipped to parent with GeometryOps.jl"): we do NOT use
# GeometryOps for the cell-clip. GeometryOps 0.1.40's polygon `intersection` is unreliable
# for clipping Voronoi cells to a polygon, verified against the live env:
#   • silently DROPS genuinely-overlapping cells (square parent, n_shards=4 → only 3 shards);
#   • throws `convert` MethodError on edge-adjacent OPEN rings and on full containment;
#   • `difference` threw a BoundsError on some asteroid shards.
# 0.1.40 is the LATEST registered GeometryOps (no 0.1.41/0.2.x exists), so there is no
# upstream fix or upgrade path. Voronoi cells are guaranteed CONVEX, so Sutherland–Hodgman
# (convex clip region, arbitrary simple subject) is exact, self-contained, and avoids a
# dep bump that would cascade into #C/#G's coordinated GeometryOps/GeometryBasics pins.
# GeometryOps is still used for orientation (`signed_area`), point-in-polygon (`contains`),
# and the acceptance partition check (with closed rings, which dodge the adjacency errors).
function _clip_to_convex(subject::Vector{P2}, clip::Vector{P2})
    cc = _orient_ccw(clip)
    out = subject
    nc = length(cc)
    for i in 1:nc
        a = cc[i]; b = cc[mod1(i + 1, nc)]
        ex, ey = b[1] - a[1], b[2] - a[2]
        out = _clip_halfplane(out, a, (ey, -ex))
        isempty(out) && return out
    end
    return out
end

# Append (parent ∩ convex_region) to `shards` as an open CCW ring, when it has positive area.
function _push_clipped!(shards::Vector{Vector{P2}}, parent_pts::Vector{P2}, region_pts::Vector{P2})
    clipped = _clip_to_convex(parent_pts, region_pts)
    length(clipped) >= 3 && push!(shards, _orient_ccw(clipped))
    return shards
end

# Deterministic seed placement: golden-angle spiral within `span` of impact (pure ⇒ reproducible).
# `sqrt((k+0.5)/n)` spreads seeds evenly over the disc rather than clustering them at the center.
function _seed_points(impact::P2, n::Int, span::Real)
    ga = π * (3 - sqrt(5))
    return P2[P2(impact[1] + span * sqrt((k + 0.5) / n) * cos(k * ga),
                 impact[2] + span * sqrt((k + 0.5) / n) * sin(k * ga)) for k in 0:(n - 1)]
end

# n_shards == 2: the 2-site Voronoi diagram is the perpendicular bisector of p and q.
# DelaunayTriangulation requires ≥3 generators, so we split analytically: clip the parent
# against each of the two complementary half-planes (closer-to-p / closer-to-q) by Sutherland–
# Hodgman. `dot(x - m, q - p) < 0` is the half closer to p.
function _bisector_split(polygon::Vector{P2}, p::P2, q::P2)
    m = P2((p[1] + q[1]) / 2, (p[2] + q[2]) / 2)
    d = (q[1] - p[1], q[2] - p[2])
    shards = Vector{Vector{P2}}()
    for nrm in (d, (-d[1], -d[2]))
        half = _clip_halfplane(polygon, m, nrm)   # parent ∩ half-plane
        length(half) >= 3 && push!(shards, _orient_ccw(half))
    end
    return shards
end

"""
    voronoi_shatter(polygon, impact; n_shards=4) -> Vector{Vector{Point2{Float64}}}

Fracture `polygon` into `n_shards ∈ [2, 8]` shards via a Voronoi tessellation
(`DelaunayTriangulation`) seeded near `impact`, with each convex cell clipped to
the parent by Sutherland–Hodgman. Shards partition the parent:
their union equals the parent and pairwise interiors are disjoint (within
numerical tolerance). Each shard is an open CCW ring. Concave parents may split
a cell into multiple pieces, so `length(result) ≥ n_shards` **when every seed's
clipped Voronoi cell intersects the parent** (true for a centroid/interior impact
with moderate lumpiness); a pathological concave parent with a far off-center
impact can leave a seed's cell entirely outside the parent, yielding fewer shards.
Seed placement is deterministic (golden-angle spiral within `min(w,h)/4` of
`impact`), so the result is reproducible for given arguments.
"""
function voronoi_shatter(polygon::Vector{P2}, impact::P2; n_shards::Int=4)
    2 <= n_shards <= 8 || throw(ArgumentError("n_shards must be in [2, 8], got $n_shards"))
    xs = first.(polygon); ys = last.(polygon)
    w = maximum(xs) - minimum(xs); h = maximum(ys) - minimum(ys)
    seeds = _seed_points(impact, n_shards, min(w, h) / 4)   # within min(w,h)/4 of impact
    return n_shards == 2 ?
        _bisector_split(polygon, seeds[1], seeds[2]) :
        _voronoi_clip(polygon, seeds)
end

function _voronoi_clip(polygon::Vector{P2}, seeds::Vector{P2})
    tri = DT.triangulate([(p[1], p[2]) for p in seeds])
    xs = first.(polygon); ys = last.(polygon)
    pad = max(maximum(xs) - minimum(xs), maximum(ys) - minimum(ys))
    bx0, bx1 = minimum(xs) - pad, maximum(xs) + pad
    by0, by1 = minimum(ys) - pad, maximum(ys) + pad
    clip_pts = [(bx0, by0), (bx1, by0), (bx1, by1), (bx0, by1)]   # CONVEX bbox ⇒ finite cells
    clip_nodes = [1, 2, 3, 4, 1]                                  # CCW
    vorn = DT.voronoi(tri; clip=true, clip_polygon=(clip_pts, clip_nodes))
    shards = Vector{Vector{P2}}()
    for i in DT.each_polygon_index(vorn)
        cs = DT.get_polygon_coordinates(vorn, i)
        cell = P2[P2(c[1], c[2]) for c in cs]
        length(cell) > 1 && cell[1] == cell[end] && pop!(cell)
        _push_clipped!(shards, polygon, cell)   # clip parent against this convex cell
    end
    return shards
end
"""
    rasterize(polygon, cell_size) -> BitMatrix

Rasterize `polygon` (open or closed ring of `Point2{Float64}`) onto a grid of
square cells `cell_size` units wide. `raster[row, col]` is `true` when the cell
**center** is inside the polygon. `row == 1` is the **top** of the bounding box
(y-down, matching `layout`'s block-top frame); `col == 1` is the **left**.
Correctness assumes cell centers do not land exactly on polygon edges (where the
point-in-polygon predicate is ambiguous); choose `cell_size` accordingly.
"""
function rasterize(polygon::Vector{P2}, cell_size::Real)
    cell_size > 0 || throw(ArgumentError("cell_size must be > 0, got $cell_size"))
    xs = first.(polygon); ys = last.(polygon)
    xmin, xmax = minimum(xs), maximum(xs)
    ymin, ymax = minimum(ys), maximum(ys)
    ncols = max(1, ceil(Int, (xmax - xmin) / cell_size))
    nrows = max(1, ceil(Int, (ymax - ymin) / cell_size))
    poly = GB.Polygon(polygon)
    raster = falses(nrows, ncols)
    for row in 1:nrows, col in 1:ncols
        cx = xmin + (col - 0.5) * cell_size   # col 1 == left
        cy = ymax - (row - 0.5) * cell_size   # row 1 == top (y-down)
        raster[row, col] = GO.contains(poly, P2(cx, cy))
    end
    return raster
end

end # module
