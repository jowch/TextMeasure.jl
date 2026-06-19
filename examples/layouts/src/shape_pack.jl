# SPDX-License-Identifier: MIT
#
# shape_pack — shape-conforming text layout (#C, demos milestone).
# Per-band scanline; inspired by pretext.js wrap-geometry.ts but with inverted
# semantics: chord_fn returns AVAILABLE intervals, not obstacle envelopes.

"""
    Placement(segment_index, x, y)

One placed `:word` segment. `segment_index` is the **absolute** index into the source
`Prepared.segments` (counts across `:word`/`:space`/`:newline`). `x` is the segment's
left edge; `y` is its baseline in the block-top frame (block top = 0, increasing down) —
equal to `line_top(lay, ln) + ascent` for the equivalent `layout` line.
"""
struct Placement
    segment_index :: Int
    x             :: Float64
    y             :: Float64
end

"""
    PackedLayout(placements, overflowed, metrics)

Result of `shape_pack`. `placements` are `:word` segments in left-to-right, top-to-bottom
reading order. `metrics` is echoed from the source `Prepared`. Read-only by convention.

`overflowed` holds segment indices flagged as over-wide. The semantics are **local to the
band where greedy flow reached the word**: a word is recorded when its width exceeds the
widest chord interval of that band — *not* the global "wider than any chord at any row".
For a constant-width region (e.g. a rectangle) the two coincide, but for an irregular
shape `shape_pack` does not backtrack to hunt a wider band elsewhere. Whether an entry
also has a `Placement` depends on `overflow_strategy`: `:widest_row` records **and**
places (at the band's left edge); `:skip`/`:reject` record but do **not** place.
"""
struct PackedLayout
    placements :: Vector{Placement}
    overflowed :: Vector{Int}
    metrics    :: FontMetrics
end

"""
    AbstractChordFn

Optional typed supertype for chord functions (the preferred long-term API). Subtypes
implement `chord_intervals(f, y_top, y_bottom)` and are callable with the same signature.
A plain `Function` closure is equally acceptable as a `chord_fn` argument to `shape_pack`.
"""
abstract type AbstractChordFn end

"""
    chord_intervals(f, y_top, y_bottom) -> Vector{Tuple{Float64,Float64}}

Available horizontal intervals in band `[y_top, y_bottom]` (block-top frame), sorted
ascending and pairwise disjoint. An empty vector ⇒ no chord intersects the band.
"""
function chord_intervals end

(f::AbstractChordFn)(y_top::Real, y_bottom::Real) = chord_intervals(f, y_top, y_bottom)

# Pick the widest interval in a band; return (left, right) or nothing if none.
function _widest(intervals)
    isempty(intervals) && return nothing
    best = intervals[1]
    bestw = best[2] - best[1]
    for iv in intervals
        w = iv[2] - iv[1]
        if w > bestw
            best, bestw = iv, w
        end
    end
    return best
end

# Pack ONE line into a single interval [L, R] at baseline `y`, starting at segment
# `si`. Mirrors src/layout.jl's greedy inner loop, scoped to this one interval; both
# the :widest (one interval/band) and :all (each disjoint interval/band) paths reuse
# it so overflow_strategy semantics stay identical and scoped to the interval being
# filled. Mutates `placements`/`overflowed`; returns `(next_si, aborted)`. `aborted`
# is true only for overflow_strategy=:reject hitting an over-wide first word — the
# caller must then empty placements, flag si:n words, and return (global abort).
function _pack_interval!(placements::Vector{Placement}, overflowed::Vector{Int},
                         segs, si::Int, n::Int, L::Float64, R::Float64, y::Float64,
                         overflow_strategy::Symbol)
    W = R - L
    cursor = 0.0                 # advance from L of words+spaces committed on this line
    committed = 0                # words placed in this interval's line
    pending::Union{Nothing,Segment} = nothing
    while si <= n
        seg = segs[si]
        if seg.kind === :newline
            si += 1
            return (si, false)                       # newline ends the line
        elseif seg.kind === :space
            pending = seg; si += 1
        else  # :word
            if committed == 0
                # first word of the line; leading space already trimmed (pending dropped)
                if seg.width > W                     # over-wide for this interval
                    if overflow_strategy === :reject
                        return (si, true)            # signal global abort to caller
                    elseif overflow_strategy === :skip
                        push!(overflowed, si); si += 1; pending = nothing
                        continue                     # back-fill: next word, same interval
                    else  # :widest_row — place at L anyway, accept overflow
                        push!(placements, Placement(si, L, y))
                        push!(overflowed, si); si += 1
                        return (si, false)           # over-wide word occupies its own line
                    end
                else
                    push!(placements, Placement(si, L, y))
                    cursor = seg.width; committed = 1; pending = nothing; si += 1
                end
            else
                extra = (pending === nothing ? 0.0 : pending.width) + seg.width
                if cursor + extra > W
                    return (si, false)               # word starts next line/interval
                else
                    if pending !== nothing
                        cursor += pending.width; pending = nothing
                    end
                    push!(placements, Placement(si, L + cursor, y))
                    cursor += seg.width; committed += 1; si += 1
                end
            end
        end
    end
    return (si, false)
end

"""
    shape_pack(prep, chord_fn; line_advance, min_chord_width=24,
               overflow_strategy=:widest_row, fill=:widest,
               max_empty_bands=1024, max_bands=100_000) -> PackedLayout

Pack the `:word` segments of `prep` into the region described by `chord_fn`, walking
horizontal bands of height `line_advance` from the top (y=0) downward. `:space`/`:newline`
segments steer line breaks exactly as `layout` does (leading/trailing whitespace trimmed
per line/interval) but are never emitted as `Placement`s. Returns word placements in
reading order.

`fill` selects how a band's available intervals are used:
- `:widest` (default) — only the **widest** interval is filled; bands whose widest
  interval is `< min_chord_width` (or empty) are skipped. Back-compatible behavior.
- `:all` — every disjoint interval in the band is filled, in left-to-right order:
  the leftmost interval is greedily filled (same rule as the single-interval path),
  flow then continues into the next interval in the SAME band (same baseline), then
  advances to the next band. Reading order within a band is left-run words, then the
  next-run words, and so on. An individual interval `< min_chord_width` is skipped
  (the rest of the band is still filled); a band with no interval `>= min_chord_width`
  is skipped entirely. This lets text wrap around BOTH sides of a centered obstacle.

`chord_fn` may be a plain closure `(y_top, y_bottom) -> Vector{Tuple{Float64,Float64}}`
or an [`AbstractChordFn`](@ref); both are called identically. Returned intervals must be
sorted ascending and pairwise disjoint; an empty vector skips the band.

A word that is over-wide only mid-line (it fits no remaining room but is not the first
word of the line) is not itself flagged — it simply breaks to the next interval/band,
where it is re-evaluated as that interval's first word and handled by `overflow_strategy`.

`overflow_strategy` controls a word wider than the interval width `W` it is being placed
into (applied when the word is the first word of that interval's line). Under `fill=:all`
the strategy is scoped to the individual interval, not the whole band:
- `:widest_row` (default) — place it at the interval's left edge, record it in
  `overflowed`, and end its line (the over-wide word gets its own line).
- `:skip` — drop the word and record it in `overflowed`, then **continue filling the
  same interval** with the following (narrower) words (back-fill).
- `:reject` — abort: return a `PackedLayout` with empty `placements` and the offending
  word plus every later `:word` index in `overflowed`.

Vertical termination: words exhausted; or, after entering the shape (first usable band),
`max_empty_bands` consecutive skipped bands; or the hard safety cap `max_bands`. Words
still unplaced when scanning stops are simply absent from `placements` (detectable via
count) — they are not forced into `overflowed`, which means horizontal over-width only.

Coordinates share `chord_fn`'s frame and `prep.metrics` units. With
`line_advance = prep.metrics.line_advance` and a full-width rectangle chord_fn, the output
is equivalent to `layout(prep; max_width=w)` for newline-free text.

# Examples
A full-width rectangle reproduces `layout`'s greedy breaks — each `Placement` carries the
source segment index plus its `(x, baseline)`:

```jldoctest
julia> using TextMeasure, TextMeasureLayouts

julia> prep = prepare(MonospaceBackend(fontsize=10, advance_ratio=1.0), "alpha beta gamma");

julia> rect = (y_top, y_bottom) -> [(0.0, 100.0)];   # one 100px-wide column in every band

julia> pk = shape_pack(prep, rect; line_advance=prep.metrics.line_advance, min_chord_width=0.0);

julia> [(p.segment_index, p.x, p.y) for p in pk.placements]
3-element Vector{Tuple{Int64, Float64, Float64}}:
 (1, 0.0, 8.0)
 (3, 60.0, 8.0)
 (5, 0.0, 20.0)
```
"""
function shape_pack(prep::Prepared, chord_fn;
                    line_advance::Real,
                    min_chord_width::Real=24,
                    overflow_strategy::Symbol=:widest_row,
                    fill::Symbol=:widest,
                    max_empty_bands::Int=1024,
                    max_bands::Int=100_000)::PackedLayout
    line_advance > 0 || throw(ArgumentError("line_advance must be > 0; got $line_advance"))
    overflow_strategy in (:widest_row, :skip, :reject) ||
        throw(ArgumentError("overflow_strategy must be :widest_row, :skip or :reject; got $(repr(overflow_strategy))"))
    fill in (:widest, :all) ||
        throw(ArgumentError("fill must be :widest or :all; got $(repr(fill))"))
    la  = Float64(line_advance)
    mcw = Float64(min_chord_width)
    m   = prep.metrics
    segs = prep.segments
    n = length(segs)

    placements = Placement[]
    overflowed = Int[]

    si = 1                       # next segment to consider
    band = 1                     # 1-based band index (vertical line slot)
    entered = false
    empty_run = 0

    while si <= n
        # ---- find next usable band: collect the interval(s) to fill ----
        # `:widest` ⇒ at most the single widest interval (if >= mcw); `:all` ⇒ every
        # interval >= mcw, left-to-right. A band is usable iff that list is non-empty.
        intervals = Tuple{Float64,Float64}[]
        usable = false
        while band <= max_bands
            ivs = chord_fn((band - 1) * la, band * la)
            if fill === :widest
                iv = _widest(ivs)
                if iv !== nothing && (iv[2] - iv[1]) >= mcw
                    intervals = [(Float64(iv[1]), Float64(iv[2]))]
                end
            else  # :all — keep each interval wide enough, in left-to-right order
                intervals = [(Float64(l), Float64(r)) for (l, r) in ivs if (Float64(r) - Float64(l)) >= mcw]
            end
            if !isempty(intervals)
                usable = true
                entered = true
                empty_run = 0
                break
            end
            if entered
                empty_run += 1
                empty_run >= max_empty_bands && break
            end
            band += 1
        end
        usable || break          # shape vertically exhausted (or never entered)

        baseline = (band - 1) * la + m.ascent

        # ---- fill each interval of this band on the same baseline, left-to-right ----
        for (L, R) in intervals
            si > n && break
            si, aborted = _pack_interval!(placements, overflowed, segs, si, n, L, R, baseline, overflow_strategy)
            if aborted                                # overflow_strategy=:reject global abort
                empty!(placements)
                for j in si:n
                    segs[j].kind === :word && push!(overflowed, j)
                end
                return PackedLayout(placements, overflowed, m)
            end
        end
        band += 1                # next line uses the next band
    end

    return PackedLayout(placements, overflowed, m)
end

# Normalize raw inside-runs: drop (near) zero-width runs and merge runs that abut/overlap
# within `eps`. This makes scanline output robust to a polygon vertex landing exactly on
# the sample line (which yields coincident crossings that naive pairing would otherwise
# split into two abutting half-width intervals).
function _normalize_intervals(runs::Vector{Tuple{Float64,Float64}}; eps::Float64=1e-9)
    isempty(runs) && return runs
    sort!(runs; by=first)
    out = Tuple{Float64,Float64}[]
    cl, cr = runs[1]
    for k in 2:length(runs)
        l, r = runs[k]
        if l <= cr + eps          # abuts or overlaps the current run → merge
            cr = max(cr, r)
        else
            push!(out, (cl, cr)); cl, cr = l, r
        end
    end
    push!(out, (cl, cr))
    return [iv for iv in out if (iv[2] - iv[1]) > eps]   # drop point-touch (zero-width) runs
end

"""
    PolygonChordFn(polygon)

`AbstractChordFn` from a closed 2-D polygon (`Vector{Point2{Float64}}`, block-top frame).
Each band's available intervals are the inside-runs of a single scanline at the band's
vertical center, normalized (zero-width point-touches dropped, abutting runs merged).
"""
struct PolygonChordFn <: AbstractChordFn
    polygon :: Vector{Point2{Float64}}
end

"""
    polygon_chord_fn(polygon::Vector{GeometryBasics.Point2{Float64}}) -> PolygonChordFn

Scanline intersection of a 2-D polygon. Returns the inside intervals where text can be
placed in each band.
"""
polygon_chord_fn(polygon::Vector{Point2{Float64}}) = PolygonChordFn(polygon)

function chord_intervals(f::PolygonChordFn, y_top::Real, y_bottom::Real)
    poly = f.polygon
    n = length(poly)
    n < 3 && return Tuple{Float64,Float64}[]
    yc = (Float64(y_top) + Float64(y_bottom)) / 2
    xs = Float64[]
    @inbounds for i in 1:n
        x1, y1 = poly[i][1], poly[i][2]
        j = i == n ? 1 : i + 1
        x2, y2 = poly[j][1], poly[j][2]
        # half-open crossing test avoids double-counting shared vertices
        if (y1 <= yc) != (y2 <= yc)
            t = (yc - y1) / (y2 - y1)
            push!(xs, x1 + t * (x2 - x1))
        end
    end
    sort!(xs)
    runs = Tuple{Float64,Float64}[]
    k = 1
    while k + 1 <= length(xs)
        push!(runs, (xs[k], xs[k+1]))    # inside runs are consecutive crossing pairs
        k += 2
    end
    return _normalize_intervals(runs)
end

"""
    RasterChordFn(raster, cell_size)

`AbstractChordFn` from a cell-grid silhouette. `raster[row, col]` is `true` for cells
inside the shape; `row` indexes y (down), `col` indexes x. Cell `(row,col)` covers
`x ∈ [(col-1)·cell_size, col·cell_size]`, `y ∈ [(row-1)·cell_size, row·cell_size]`.
"""
struct RasterChordFn <: AbstractChordFn
    raster    :: BitMatrix
    cell_size :: Float64
end

"""
    raster_chord_fn(raster::BitMatrix, cell_size::Real) -> RasterChordFn

Chord function for cell-grid silhouettes (e.g. a rasterized glyph or logo). A band's
available intervals are the maximal runs of `true` cells in the row containing the
band's vertical center.
"""
function raster_chord_fn(raster::BitMatrix, cell_size::Real)
    cell_size > 0 || throw(ArgumentError("cell_size must be > 0; got $cell_size"))
    return RasterChordFn(raster, Float64(cell_size))
end

function chord_intervals(f::RasterChordFn, y_top::Real, y_bottom::Real)
    cs = f.cell_size
    yc = (Float64(y_top) + Float64(y_bottom)) / 2
    row = floor(Int, yc / cs) + 1
    (row < 1 || row > size(f.raster, 1)) && return Tuple{Float64,Float64}[]
    out = Tuple{Float64,Float64}[]
    ncol = size(f.raster, 2)
    c = 1
    @inbounds while c <= ncol
        if f.raster[row, c]
            c0 = c
            while c <= ncol && f.raster[row, c]
                c += 1
            end
            push!(out, ((c0 - 1) * cs, (c - 1) * cs))   # cols c0..c-1 ⇒ [(c0-1)cs, (c-1)cs]
        else
            c += 1
        end
    end
    return out
end
