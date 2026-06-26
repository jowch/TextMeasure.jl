# SPDX-License-Identifier: MIT
#
# Pour measured text into arbitrary geometry and JUSTIFY each line to the band's margins,
# rendered to ASCII — no graphics backend. Run:
#   julia --project=TextMeasureLayouts TextMeasureLayouts/examples/shape_pack_ascii.jl
#
# `shape_pack` flows a measured `Prepared` into any region a `chord_fn` describes (a vector
# polygon and a raster circle here); the per-band flush-justify below spreads each line to its
# margins so the silhouette reads solid. (Optimal whole-paragraph breaking — `knuth_plass` —
# needs a fixed measure; inside a shape the geometry already fixes the breaks, so justifying
# means filling each band, not re-choosing breaks.)

using TextMeasure, TextMeasureLayouts
using TextMeasure: MonospaceBackend, prepare
using GeometryBasics: Point2

# One monospace glyph == one grid cell (advance = line_advance = 1px).
const CELL = MonospaceBackend(fontsize = 1.0, advance_ratio = 1.0, lineheight_ratio = 1.0)

const PROSE = "the sea kneads the shore in slow folds of foam and salt while light spills wide \
across the wet sand and the long tide leans in once more and again folding the gray water over \
itself in patient sheets that hiss and draw back as the gulls wheel low and the salt wind carries \
far up the empty beach until the slow day softens toward a quiet violet dusk over the dunes"

# Flush-justify `words` across `width` cells by padding the gaps; ragged lines keep natural spacing.
function justify(words, width; ragged = false)
    n = length(words); nat = join(words, " "); slack = width - length(nat)
    (ragged || n < 2 || slack <= 0) && return nat
    base, extra = divrem(slack, n - 1)
    io = IOBuffer()
    for k in 1:n
        print(io, words[k])
        k < n && print(io, ' '^(1 + base + (k <= extra ? 1 : 0)))
    end
    return String(take!(io))
end

# Render a PackedLayout to an H×W grid, justifying each band to its chord interval.
function to_ascii(pk, prep, chord_fn, W, H)
    grid = fill(' ', H, W); asc = prep.metrics.ascent
    bands = Dict{Int,Vector{Any}}()
    for p in pk.placements
        push!(get!(() -> [], bands, round(Int, p.y - asc) + 1), p)
    end
    rows = sort!(collect(keys(bands)))
    for (i, r) in enumerate(rows)
        1 <= r <= H || continue
        words = [prep.segments[p.segment_index].str for p in sort(bands[r]; by = p -> p.x)]
        ivs = chord_intervals(chord_fn, Float64(r - 1), Float64(r))
        isempty(ivs) && continue
        L, R = argmax(iv -> iv[2] - iv[1], ivs)              # widest interval in the band
        line = justify(words, round(Int, R) - round(Int, L); ragged = i == lastindex(rows))
        for (k, ch) in enumerate(line)
            c = round(Int, L) + k
            1 <= c <= W && (grid[r, c] = ch)
        end
    end
    lines = [rstrip(String(@view grid[r, :])) for r in 1:H]
    while !isempty(lines) && isempty(lines[1]); popfirst!(lines); end   # drop blank apex rows
    while !isempty(lines) && isempty(lines[end]); pop!(lines); end
    return join(lines, '\n')
end

prep = prepare(CELL, PROSE)
opts = (; line_advance = 1.0, min_chord_width = 2.0, overflow_strategy = :skip)

# Terminal cells are ~twice as tall as wide, so shapes are built ~2× wider than tall (in cells)
# to look right on screen. `ROWS` sets the height — drop it for even chunkier shapes.
const ROWS = 7

# Vector polygon — a wide, short triangle.
W = 2 * ROWS + 2
triangle = Point2{Float64}[(W / 2, 1), (1, ROWS), (W - 1, ROWS), (W / 2, 1)]
tcfn = polygon_chord_fn(triangle)
println("\npolygon_chord_fn — justified inside a triangle:\n")
println(to_ascii(shape_pack(prep, tcfn; opts...), prep, tcfn, W, ROWS))

# Raster silhouette — an ellipse in cells that reads as a circle on screen.
cols = 2 * ROWS + 1
cy = (ROWS + 1) / 2; cx = (cols + 1) / 2
mask = falses(ROWS, cols)
for i in 1:ROWS, j in 1:cols
    mask[i, j] = ((i - cy) / (ROWS / 2))^2 + ((j - cx) / (cols / 2))^2 <= 1
end
ccfn = raster_chord_fn(mask, 1.0)
println("\nraster_chord_fn — justified inside a circle:\n")
println(to_ascii(shape_pack(prep, ccfn; opts...), prep, ccfn, cols, ROWS))
println()
