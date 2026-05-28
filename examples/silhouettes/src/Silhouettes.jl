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

asteroid_polygon(::AbstractRNG; n::Int=12, lumpiness::Float64=0.4) = error("not implemented")
voronoi_shatter(::Vector{P2}, ::P2; n_shards::Int=4) = error("not implemented")
rasterize(::Vector{P2}, ::Real) = error("not implemented")

end # module
