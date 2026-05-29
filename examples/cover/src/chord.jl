# SPDX-License-Identifier: MIT
#
# RectExclusionChordFn — a self-contained inset-exclusion chord function for #H.
# Returns the page content interval MINUS the x-footprints of a set of rectangular
# "holes" (the SVG inset, the drop-cap box, and each pull-quote box) for every band
# they vertically intersect. This is the negative-space chord_fn that makes body text
# flow around the inset with NO manual offsets. Holes are in the body-LOCAL frame
# (y=0 == body_top); content x is absolute page x.
#
# NOTE: deliberately NOT shared via TextMeasureLayouts (that module is #C/#K's; a shared
# negative-space helper would collide with #K). #G builds its own complement separately.

# Available sub-intervals of `full` after removing `holes` (each clamped to full).
# Returns sorted, pairwise-disjoint intervals (the shape_pack chord_fn contract).
function _subtract_interval(full::Tuple{Float64,Float64},
                            holes::Vector{Tuple{Float64,Float64}})
    fl, fr = full
    fr <= fl && return Tuple{Float64,Float64}[]
    hs = Tuple{Float64,Float64}[]
    for (hl, hr) in holes
        l = max(hl, fl); r = min(hr, fr)
        r > l && push!(hs, (l, r))
    end
    isempty(hs) && return [full]
    sort!(hs; by = first)
    # merge overlapping/abutting holes
    merged = Tuple{Float64,Float64}[]
    cl, cr = hs[1]
    for k in 2:length(hs)
        l, r = hs[k]
        if l <= cr
            cr = max(cr, r)
        else
            push!(merged, (cl, cr)); cl, cr = l, r
        end
    end
    push!(merged, (cl, cr))
    # emit the gaps between merged holes within [fl, fr]
    out = Tuple{Float64,Float64}[]
    cursor = fl
    for (hl, hr) in merged
        hl > cursor && push!(out, (cursor, hl))
        cursor = max(cursor, hr)
    end
    cursor < fr && push!(out, (cursor, fr))
    return out
end

"""
    RectExclusionChordFn(content_left, content_right, region_bottom, holes, gutter)

`AbstractChordFn` returning, for each band, the content interval
`[content_left, content_right]` minus the x-footprint of every `hole::BBox` whose
vertical extent (expanded by `gutter` on all sides) intersects the band. Bands at or
below `region_bottom` (body-local y) return `[]` (text stops at the content bottom).
Holes are in the body-local frame; content x is absolute page x. The returned
intervals are sorted ascending and pairwise disjoint.
"""
struct RectExclusionChordFn <: AbstractChordFn
    content_left  :: Float64
    content_right :: Float64
    region_bottom :: Float64
    holes         :: Vector{BBox}
    gutter        :: Float64
end

function chord_intervals(f::RectExclusionChordFn, y_top::Real, y_bottom::Real)
    yt = Float64(y_top); yb = Float64(y_bottom)
    yt >= f.region_bottom && return Tuple{Float64,Float64}[]
    g = f.gutter
    holes = Tuple{Float64,Float64}[]
    for h in f.holes
        if yb > h.top - g && yt < h.bottom + g          # band overlaps the (gutter-expanded) hole
            push!(holes, (h.left - g, h.right + g))
        end
    end
    return _subtract_interval((f.content_left, f.content_right), holes)
end
