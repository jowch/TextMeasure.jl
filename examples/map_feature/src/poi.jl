# SPDX-License-Identifier: MIT
#
# POI model + simple offset label placement with greedy de-overlap (#G).
# Hard repel / force-directed placement is out of scope (user's ggrepel-style pkg handles it).

"""
    POI(name, coord, kind)

A point of interest. `coord = (lon, lat)` in geographic degrees; `kind ∈
(:city, :capital, :landmark, :feature)` selects marker glyph + label weight at render.
"""
struct POI
    name  :: String
    coord :: Tuple{Float64,Float64}
    kind  :: Symbol
    function POI(name, coord, kind)
        k = Symbol(kind)
        k in (:city, :capital, :landmark, :feature) ||
            throw(ArgumentError("POI kind must be :city/:capital/:landmark/:feature, got $(repr(k))"))
        new(String(name), (Float64(coord[1]), Float64(coord[2])), k)
    end
end

"""    LabelBox(x, y, w, h)  — placed label AABB, page-pixel block-top (top-left origin)."""
struct LabelBox
    x :: Float64
    y :: Float64
    w :: Float64
    h :: Float64
end

_overlaps(a::LabelBox, b::LabelBox) =
    a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h

"""
    place_poi_labels(anchors, sizes; offset=7.0, margin=2.0, bounds=nothing)
        -> Vector{Union{LabelBox,Nothing}}

Greedy simple-offset placement. For each anchor (page-pixel marker position) and label
`(w,h)`, try candidate offsets (E, W, N, S, then diagonals) at `offset` px; accept the first
whose box (grown by `margin` for clearance) clears all already-placed boxes **and**, if
`bounds = (xmin, ymin, xmax, ymax)` is given, lies fully inside it. The bounds check makes
right-edge anchors fall through to their West (left-anchored) candidate instead of clipping
off the canvas. Returns one entry per anchor (`nothing` if every candidate fails — caller may
skip its label). Placement order is input order (deterministic).
"""
function place_poi_labels(anchors::AbstractVector{<:Point2}, sizes::AbstractVector{<:Tuple};
                          offset::Float64=7.0, margin::Float64=2.0,
                          bounds::Union{Nothing,NTuple{4,Float64}}=nothing)
    placed = LabelBox[]
    out = Vector{Union{LabelBox,Nothing}}(undef, length(anchors))
    inside(cx, cy, w, h) = bounds === nothing ||
        (cx >= bounds[1] && cy >= bounds[2] && cx + w <= bounds[3] && cy + h <= bounds[4])
    for (i, a) in enumerate(anchors)
        w, h = Float64(sizes[i][1]), Float64(sizes[i][2])
        ax, ay = Float64(a[1]), Float64(a[2])
        candidates = (
            (ax + offset,        ay - h/2),        # E
            (ax - offset - w,    ay - h/2),        # W
            (ax - w/2,           ay - offset - h), # N
            (ax - w/2,           ay + offset),     # S
            (ax + offset,        ay + offset),     # SE
            (ax - offset - w,    ay - offset - h), # NW
            (ax + offset,        ay - offset - h), # NE
            (ax - offset - w,    ay + offset),     # SW
        )
        chosen = nothing
        for (cx, cy) in candidates
            inside(cx, cy, w, h) || continue
            grown = LabelBox(cx - margin, cy - margin, w + 2margin, h + 2margin)
            if !any(p -> _overlaps(grown, p), placed)
                chosen = LabelBox(cx, cy, w, h); break
            end
        end
        out[i] = chosen
        chosen !== nothing && push!(placed, chosen)
    end
    return out
end
