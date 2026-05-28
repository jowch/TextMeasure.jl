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

const GI = GO.GI
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

voronoi_shatter(::Vector{P2}, ::P2; n_shards::Int=4) = error("not implemented")
rasterize(::Vector{P2}, ::Real) = error("not implemented")

end # module
