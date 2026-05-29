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
- `polygon` not crossed anywhere in the band ⇒ `[(left, right)]` (full-width line — e.g. above/
  below the silhouette; the caller is responsible for reserving any non-text rectangles such as a
  map panel in those bands, see `MapFeature`'s render combinator);
- otherwise the polygon's horizontal **envelope** `[env_l, env_r]` is carved out, yielding
  `[(left, env_l), (env_r, right)]` — each non-empty interval emitted, zero-width dropped, sorted
  ascending & pairwise-disjoint (the `shape_pack` contract).

The envelope is taken over the band's **full vertical span** `[y_top, y_bottom]` (not just the
center scanline): `env_l` is the leftmost and `env_r` the rightmost x of the boundary over the
whole band, computed **exactly** — `x` is linear in `y` along each edge, so the extremes occur
only at the band-boundary crossings (`y_top`, `y_bottom`) or at polygon vertices strictly inside
the band; no sampling. Because `shape_pack` calls with the band height = `line_advance`
(≈ a line's `ascent + descent`), a word packed flush to `env_l` then clears the silhouette across
its *entire* glyph height — not only at its baseline — so a slanted or concave facing edge cannot
poke through the text the way a center-only scanline would allow. The envelope (rather than the
exact inside-runs) keeps text out of the polygon's full horizontal extent, so the column follows
concavities on the facing edge but text never lands in an interior notch of the map.

**Scope:** `polygon` is treated as a single closed ring (last vertex implicitly joins the
first). Multi-part geographies (islands/holes) are out of scope this milestone — pass a single
outer ring (e.g. Vermont). See `load_state_shapefile`.
"""
function complement_chord_fn(polygon::Vector{Point2{Float64}}, page_bounds::NTuple{4,Float64})
    left, top, right, bottom = Float64.(page_bounds)
    n = length(polygon)
    return function (y_top::Real, y_bottom::Real)
        yt = Float64(y_top); yb = Float64(y_bottom)
        yc = (yt + yb) / 2
        (yc < top || yc > bottom) && return Tuple{Float64,Float64}[]
        env_l = Inf; env_r = -Inf; crossed = false
        if n >= 2
            # EXACT envelope over [yt, yb]: x is linear in y along each edge, so the boundary's
            # leftmost/rightmost x over the band occurs only at (i) edge crossings of the two band
            # boundaries yt/yb, or (ii) polygon vertices strictly inside (yt, yb). No sampling.
            @inbounds for ys in (yt, yb)
                for i in 1:n
                    y1 = polygon[i][2]
                    j = i == n ? 1 : i + 1
                    y2 = polygon[j][2]
                    if (y1 <= ys) != (y2 <= ys)            # half-open crossing (matches PolygonChordFn)
                        x1 = polygon[i][1]; x2 = polygon[j][1]
                        x = x1 + (ys - y1) / (y2 - y1) * (x2 - x1)
                        x < env_l && (env_l = x)
                        x > env_r && (env_r = x)
                        crossed = true
                    end
                end
            end
            @inbounds for i in 1:n
                yi = polygon[i][2]
                if yt < yi < yb                            # vertex strictly inside the band
                    xi = polygon[i][1]
                    xi < env_l && (env_l = xi)
                    xi > env_r && (env_r = xi)
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
