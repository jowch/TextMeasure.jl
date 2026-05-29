# SPDX-License-Identifier: MIT
#
# Data layer: bundled offline Vermont fixture + POI/stats TOML; optional CensusACS fetch for
# other states (network + CENSUS_API_KEY). See the plan's verified-API-facts for CensusACS quirks.

import Shapefile
import TOML
import CensusACS

_pkgdata(f) = joinpath(pkgdir(MapFeature), "data", f)

# Shoelace area magnitude of a part's point range (for picking the outer ring).
function _part_area(pts, rng)
    a = 0.0
    n = length(rng)
    @inbounds for k in 1:n
        p = pts[rng[k]]; q = pts[rng[mod1(k + 1, n)]]
        a += p.x * q.y - q.x * p.y
    end
    return abs(a) / 2
end

"""
    _shape_to_ring(geom) -> Vector{Point2{Float64}}

Outer ring of a `Shapefile.Polygon`, as a single closed ring's vertices. Multi-part shapes
(islands/holes) are reduced to the **largest part by area** — i.e. the mainland outer
boundary. Holes and secondary islands are dropped. **Single-part states (Vermont) are the
verified path this milestone; multi-part states (CA/FL/HI) are out of scope** (their islands
would be lost, and a per-band multi-ring envelope is future work).
"""
function _shape_to_ring(geom)
    pts = geom.points
    parts = geom.parts
    if length(parts) <= 1
        rng = collect(1:length(pts))
    else
        bounds = vcat(Int.(parts) .+ 1, length(pts) + 1)
        ranges = [bounds[k]:(bounds[k+1] - 1) for k in 1:(length(bounds) - 1)]
        rng = collect(ranges[argmax(_part_area(pts, r) for r in ranges)])
    end
    return Point2{Float64}[Point2{Float64}(pts[i].x, pts[i].y) for i in rng]
end

"""
    load_state_shapefile(path; postal=nothing) -> Vector{Point2{Float64}}   # (lon,lat)

Read a state polygon ring from a shapefile. If `postal` is given and the file has multiple
features (e.g. the all-US Census file), select the matching `STUSPS` row; otherwise take the
first feature (the single-feature bundled fixture).
"""
function load_state_shapefile(path::AbstractString; postal::Union{Nothing,AbstractString}=nothing)
    tbl = Shapefile.Table(path)
    shapes = Shapefile.shapes(tbl)
    idx = if postal === nothing || length(shapes) == 1
        1
    else
        j = findfirst(==(uppercase(postal)), tbl.STUSPS)
        j === nothing && throw(ArgumentError("state $postal not found in $path"))
        j
    end
    return _shape_to_ring(shapes[idx])
end

"""    load_vermont() -> Vector{Point2{Float64}}   — the bundled offline fixture (no network)."""
load_vermont() = load_state_shapefile(_pkgdata("vermont.shp"))

"""    load_pois(path=data/pois.toml) -> Vector{POI}"""
function load_pois(path::AbstractString=_pkgdata("pois.toml"))
    t = TOML.parsefile(path)
    return POI[POI(p["name"], (Float64(p["lon"]), Float64(p["lat"])), Symbol(p["kind"]))
               for p in t["poi"]]
end

"""    load_stats(path=data/pois.toml) -> Dict{Symbol,Any}"""
function load_stats(path::AbstractString=_pkgdata("pois.toml"))
    t = TOML.parsefile(path)
    s = t["stats"]; m = t["meta"]
    return Dict{Symbol,Any}(
        :population        => s["population"],
        :median_income_usd => s["median_income_usd"],
        :capital           => s["capital"],
        :masthead          => m["masthead"],
        :subtitle          => m["subtitle"],
        :byline            => m["byline"],
    )
end

"""
    fetch_state_shapefile(postal; year=2023, dir=mktempdir()) -> Vector{Point2{Float64}}

Download the all-US Census state file via `CensusACS.get_tiger_shapefile` (FTP/curl), unzip,
and extract `postal`'s ring. **REQUIRES NETWORK.** For Vermont prefer [`load_vermont`]
(offline). Only single-part CONUS states are verified — see `_shape_to_ring` scope.
"""
function fetch_state_shapefile(postal::AbstractString; year::Int=2023, dir::AbstractString=mktempdir())
    cwd = pwd()
    try
        cd(dir)
        CensusACS.get_tiger_shapefile(year, "state") || error("Census shapefile download failed")
        zip = joinpath(dir, "cb_$(year)_us_state_500k.zip")
        run(`unzip -o -q $zip -d $dir`)
        return load_state_shapefile(joinpath(dir, "cb_$(year)_us_state_500k.shp"); postal=postal)
    finally
        cd(cwd)
    end
end
