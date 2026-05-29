# SPDX-License-Identifier: MIT
import GeometryBasics as GB
import TextMeasure

const P2 = GB.Point2{Float64}

mutable struct Ship
    x::Float64; y::Float64          # cell coords (col, row), continuous
    φ::Float64                       # heading, radians (0 = up)
    vx::Float64; vy::Float64
    charge::Int                      # 0..5 charge stage
    alive::Bool
    invuln::Int                      # remaining invulnerability ticks (>0 ⇒ blinking)
end

mutable struct Asteroid
    poly::Vector{P2}                 # unit-ish silhouette (Silhouettes frame)
    x::Float64; y::Float64           # center in cell coords
    vx::Float64; vy::Float64
    ω::Float64                       # spin rad/tick
    θ::Float64                       # accumulated rotation
    radius::Float64                  # cell radius (for collision + scale)
    prep::TextMeasure.Prepared       # measured prose (measure once!)
    age::Int                         # ticks since spawn (re-raster cadence)
end

mutable struct Shard
    poly::Vector{P2}
    x::Float64; y::Float64           # center in cell coords
    vx::Float64; vy::Float64
    prep::TextMeasure.Prepared       # subprep slice — NOT re-measured
    ttl::Int                         # ticks to live
    radius::Float64
end

mutable struct Beam
    active::Bool
    x::Float64; y::Float64           # origin (ship tip)
    φ::Float64
    length::Int                      # cells (onomatopoeia repeats)
    ttl::Int
end
