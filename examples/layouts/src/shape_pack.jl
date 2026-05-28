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

"""
    shape_pack(prep, chord_fn; line_advance, min_chord_width=24,
               overflow_strategy=:widest_row, max_empty_bands=1024,
               max_bands=100_000) -> PackedLayout

Pack the `:word` segments of `prep` into the region described by `chord_fn`, walking
horizontal bands of height `line_advance` from the top (y=0) downward. In each band the
**widest** available interval is used; bands whose widest interval is `< min_chord_width`
(or empty) are skipped. `:space`/`:newline` segments steer line breaks exactly as
`layout` does (leading/trailing whitespace trimmed per line) but are never emitted as
`Placement`s. Returns word placements in reading order.

`chord_fn` may be a plain closure `(y_top, y_bottom) -> Vector{Tuple{Float64,Float64}}`
or an [`AbstractChordFn`](@ref); both are called identically. Returned intervals must be
sorted ascending and pairwise disjoint; an empty vector skips the band.

`overflow_strategy` controls a word wider than its band's widest interval `W`:
- `:widest_row` (default) — place it at the interval's left edge, record it in
  `overflowed`, and end its line (the over-wide word gets its own line).
- `:skip` — drop the word and record it in `overflowed`, then **continue filling the
  same band** with the following (narrower) words (back-fill).
- `:reject` — abort: return a `PackedLayout` with empty `placements` and the offending
  word plus every later `:word` index in `overflowed`.

Vertical termination: words exhausted; or, after entering the shape (first usable band),
`max_empty_bands` consecutive skipped bands; or the hard safety cap `max_bands`. Words
still unplaced when scanning stops are simply absent from `placements` (detectable via
count) — they are not forced into `overflowed`, which means horizontal over-width only.

Coordinates share `chord_fn`'s frame and `prep.metrics` units. With
`line_advance = prep.metrics.line_advance` and a full-width rectangle chord_fn, the output
is equivalent to `layout(prep; max_width=w)` for newline-free text.
"""
function shape_pack(prep::Prepared, chord_fn;
                    line_advance::Real,
                    min_chord_width::Real=24,
                    overflow_strategy::Symbol=:widest_row,
                    max_empty_bands::Int=1024,
                    max_bands::Int=100_000)::PackedLayout
    line_advance > 0 || throw(ArgumentError("line_advance must be > 0; got $line_advance"))
    overflow_strategy in (:widest_row, :skip, :reject) ||
        throw(ArgumentError("overflow_strategy must be :widest_row, :skip or :reject; got $(repr(overflow_strategy))"))
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
        # ---- find next usable band ----
        L = R = 0.0
        usable = false
        while band <= max_bands
            iv = _widest(chord_fn((band - 1) * la, band * la))
            if iv !== nothing && (iv[2] - iv[1]) >= mcw
                L, R = Float64(iv[1]), Float64(iv[2])
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
        W = R - L
        cursor = 0.0             # advance from L of words+spaces committed on this line
        committed = 0            # words placed on this line
        pending::Union{Nothing,Segment} = nothing

        # ---- pack one line, mirroring src/layout.jl's greedy inner loop ----
        while si <= n
            seg = segs[si]
            if seg.kind === :newline
                si += 1; break                       # newline ends the line
            elseif seg.kind === :space
                pending = seg; si += 1
            else  # :word
                if committed == 0
                    # first word on the line; leading space already trimmed (pending dropped)
                    if seg.width > W                  # over-wide for this band
                        if overflow_strategy === :reject
                            empty!(placements)
                            for j in si:n
                                segs[j].kind === :word && push!(overflowed, j)
                            end
                            return PackedLayout(placements, overflowed, m)
                        elseif overflow_strategy === :skip
                            push!(overflowed, si); si += 1; pending = nothing
                            continue                  # back-fill: try next word in this same band
                        else  # :widest_row — place at L anyway, accept overflow
                            push!(placements, Placement(si, L, baseline))
                            push!(overflowed, si)
                            cursor = seg.width; committed = 1; pending = nothing; si += 1
                            break                     # over-wide word occupies its own line
                        end
                    else
                        push!(placements, Placement(si, L, baseline))
                        cursor = seg.width; committed = 1; pending = nothing; si += 1
                    end
                else
                    extra = (pending === nothing ? 0.0 : pending.width) + seg.width
                    if cursor + extra > W
                        break                         # word starts next line; trailing space trimmed
                    else
                        if pending !== nothing
                            cursor += pending.width; pending = nothing
                        end
                        push!(placements, Placement(si, L + cursor, baseline))
                        cursor += seg.width; committed += 1; si += 1
                    end
                end
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
