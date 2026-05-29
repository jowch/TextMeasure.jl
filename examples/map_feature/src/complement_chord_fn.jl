# SPDX-License-Identifier: MIT
#
# complement_chord_fn — negative-space chord function for text-AROUND-obstacle layout (#G).
# Inverse of TextMeasureLayouts.polygon_chord_fn (which returns intervals INSIDE the polygon).
# Pure interval arithmetic on the polygon's per-band horizontal projection — deliberately
# AVOIDS GeometryOps boolean ops (0.1.40's intersection/difference are broken; see #D).

"""
    complement_chord_fn(polygon::Vector{Point2{Float64}},
                        page_bounds::NTuple{4,Float64}) -> Function

Build a `shape_pack` `chord_fn` that flows text through the **white space around**
`polygon`. `page_bounds = (left, top, right, bottom)` is the editorial text region in
page-pixel **block-top** coords (y increases downward); `polygon` must already be in that
same frame (project geography first — see [`PageProjection`](@ref)).

Returns a closure `(y_top, y_bottom) -> Vector{Tuple{Float64,Float64}}`. Per band:

- band center `yc ∉ [top, bottom]` ⇒ `[]` (outside the text column);
- `polygon` not crossed at `yc` ⇒ `[(left, right)]` (full-width line — e.g. above/below the
  silhouette; the caller is responsible for reserving any non-text rectangles such as a map
  panel in those bands, see `MapFeature`'s render combinator);
- otherwise the polygon's horizontal **envelope** `[env_l, env_r]` (min/max edge-crossing at
  `yc`) is carved out, yielding `[(left, env_l), (env_r, right)]` — each non-empty interval
  emitted, zero-width dropped, sorted ascending & pairwise-disjoint (the `shape_pack` contract).

The envelope (not the exact inside-runs) is used on purpose: text is kept out of the polygon's
full horizontal extent in each band, so concavities on the silhouette's facing edge still steer
the column but text never lands in an interior notch of the map.

**Scope:** `polygon` is treated as a single closed ring (last vertex implicitly joins the
first). Multi-part geographies (islands/holes) are out of scope this milestone — pass a single
outer ring (e.g. Vermont). See `load_state_shapefile`.
"""
function complement_chord_fn(polygon::Vector{Point2{Float64}}, page_bounds::NTuple{4,Float64})
    left, top, right, bottom = Float64.(page_bounds)
    n = length(polygon)
    return function (y_top::Real, y_bottom::Real)
        yc = (Float64(y_top) + Float64(y_bottom)) / 2
        (yc < top || yc > bottom) && return Tuple{Float64,Float64}[]
        env_l = Inf; env_r = -Inf; crossed = false
        if n >= 2
            @inbounds for i in 1:n
                x1 = polygon[i][1]; y1 = polygon[i][2]
                j = i == n ? 1 : i + 1
                x2 = polygon[j][1]; y2 = polygon[j][2]
                if (y1 <= yc) != (y2 <= yc)        # half-open crossing (matches PolygonChordFn)
                    x = x1 + (yc - y1) / (y2 - y1) * (x2 - x1)
                    x < env_l && (env_l = x)
                    x > env_r && (env_r = x)
                    crossed = true
                end
            end
        end
        crossed || return Tuple{Float64,Float64}[(left, right)]
        el = clamp(env_l, left, right)
        er = clamp(env_r, left, right)
        out = Tuple{Float64,Float64}[]
        (el - left) > 0 && push!(out, (left, el))
        (right - er) > 0 && push!(out, (er, right))
        return out
    end
end
