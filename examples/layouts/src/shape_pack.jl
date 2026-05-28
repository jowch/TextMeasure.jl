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
