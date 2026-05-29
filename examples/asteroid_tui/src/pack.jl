# SPDX-License-Identifier: MIT
import TextMeasure
using TextMeasureLayouts: shape_pack, raster_chord_fn
using Silhouettes: rasterize
import GeometryBasics as GB

"""
    PackedProse(rows, cols, cells)

A silhouette's packed interior text in **local cell coordinates** (row 1 = top of
the silhouette's bounding box). `cells :: Vector{Tuple{Int,Int,Char}}` is
`(row, col, char)` for every glyph, in reading order.
"""
struct PackedProse
    rows  :: Int
    cols  :: Int
    cells :: Vector{Tuple{Int,Int,Char}}
end

"""
    pack_prose_into(polygon, prep; scale, min_chord_width=3.0) -> PackedProse

Rasterize `polygon` (scaled to `scale` cells across its larger extent) to a cell
grid, then `shape_pack` the `:word` segments of `prep` (built with `CellBackend`)
into the silhouette at one row per line. Coordinates are integer cells.
"""
function pack_prose_into(polygon::Vector{GB.Point2{Float64}}, prep::TextMeasure.Prepared;
                         scale::Real, min_chord_width::Real=3.0)
    xs = [p[1] for p in polygon]; ys = [p[2] for p in polygon]
    span = max(maximum(xs) - minimum(xs), maximum(ys) - minimum(ys))
    span <= 0 && return PackedProse(1, 1, Tuple{Int,Int,Char}[])
    cell = span / scale                                   # polygon-units per cell
    raster = rasterize(polygon, cell)                     # BitMatrix, row 1 = top
    cf = raster_chord_fn(raster, 1.0)                     # work in cell units (cell_size 1)
    pk = shape_pack(prep, cf; line_advance = 1.0, min_chord_width = Float64(min_chord_width))
    cells = Tuple{Int,Int,Char}[]
    for pl in pk.placements
        seg = prep.segments[pl.segment_index]
        seg.kind === :word || continue
        row = round(Int, pl.y)                            # baseline y = band (ascent==1)
        col0 = round(Int, pl.x) + 1                       # left edge → 1-based col
        for (k, ch) in enumerate(seg.str)
            push!(cells, (row, col0 + k - 1, ch))
        end
    end
    return PackedProse(size(raster, 1), size(raster, 2), cells)
end
