# SPDX-License-Identifier: MIT
#
# PageProjection — reproject geographic (lon,lat) rings to page-pixel block-top space.
# Uses Proj.Transformation (GeoMakie's underlying engine); we project BEFORE shape_pack so
# complement_chord_fn receives page-pixel polygons (per the issue's coordinate-system note).

import Proj

"""
    PageProjection(geo_ref, region; dest="EPSG:5070")

Affine fit of a geographic ring (`Vector{Point2{Float64}}` of `(lon, lat)`) into a page
rectangle `region = (left, top, right, bottom)` (page-pixel, block-top). `geo_ref` defines
the projected bounding box; build once from the state polygon, then apply to that polygon
AND its POIs with the SAME transform via [`project_point`](@ref). Aspect ratio is preserved
(uniform scale = the binding dimension); the result is centered in `region`; projected-north
maps to page-top (y-flip).

**CRS scope.** `dest` defaults to `"EPSG:5070"` (NAD83 / CONUS Albers Equal-Area) — the
**verified** path, used for Vermont (the offline quickstart) and other CONUS states. Non-CONUS
states are out of scope this milestone: Hawaii in particular needs its own equal-area / per-island
projection (NOT EPSG:5070, and NOT EPSG:3759 which is a single Hawaii SPCS *zone* in US-feet,
≈Oʻahu only). Passing a CONUS polygon through `EPSG:5070` is what the tests cover.
"""
struct PageProjection
    trans   :: Proj.Transformation
    scale   :: Float64
    px0     :: Float64    # page-x mapped to the projected-x minimum (after centering)
    py0     :: Float64    # page-y mapped to the projected-y maximum (top, after centering)
    pxmin   :: Float64
    pymax   :: Float64
end

function PageProjection(geo_ref::Vector{Point2{Float64}}, region::NTuple{4,Float64};
                        dest::AbstractString="EPSG:5070")
    left, top, right, bottom = Float64.(region)
    trans = Proj.Transformation("EPSG:4326", dest; always_xy=true)
    proj = [trans(p[1], p[2]) for p in geo_ref]      # (x,y) projected meters, y-up
    pxs = first.(proj); pys = last.(proj)
    pxmin, pxmax = extrema(pxs); pymin, pymax = extrema(pys)
    pw = max(pxmax - pxmin, eps()); ph = max(pymax - pymin, eps())
    rw = right - left; rh = bottom - top
    scale = min(rw / pw, rh / ph)                    # uniform ⇒ aspect preserved
    offx = left + (rw - scale * pw) / 2              # center the scaled bbox in region
    offy = top + (rh - scale * ph) / 2
    return PageProjection(trans, scale, offx, offy, pxmin, pymax)
end

"""    project_point(pp, geo) -> Point2{Float64}   # (lon,lat) -> page-pixel block-top"""
function project_point(pp::PageProjection, geo::Point2{Float64})
    x, y = pp.trans(geo[1], geo[2])
    px = pp.px0 + (x - pp.pxmin) * pp.scale          # x grows right
    py = pp.py0 + (pp.pymax - y) * pp.scale          # y-flip: north(max y) -> top(min page-y)
    return Point2{Float64}(px, py)
end

"""    project_polygon(pp, ring) -> Vector{Point2{Float64}}"""
project_polygon(pp::PageProjection, ring::Vector{Point2{Float64}}) =
    [project_point(pp, p) for p in ring]
