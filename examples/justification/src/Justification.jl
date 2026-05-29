# SPDX-License-Identifier: MIT
module Justification

# Knuth–Plass justification comparison exhibit (#K, demos milestone).
# Port of pretext.js's `justification-comparison` demo. Consumes `knuth_plass` /
# `greedy_justify` from TextMeasureLayouts and detects "rivers" — vertical runs of
# inter-word gaps that line up across consecutive lines, the classic artifact greedy
# line-breaking produces and Knuth–Plass avoids.
#
# Justification is OUT of TextMeasure's library scope (CLAUDE.md); this whole package is
# a downstream demo. River detection is a visualization concern over geometry the layout
# utility already exposes (`JustifiedLine.gap_centers`), so it lives here, not in the
# reusable utility. NOTE: this module deliberately does NOT `using CairoMakie` — the
# render lives in `demo.jl` so `Pkg.test()` stays light and deterministic. Tests use the
# zero-dep `MonospaceBackend`.

using TextMeasureLayouts: JustifiedLayout, JustifiedLine

export River, find_rivers, CANONICAL_PARAGRAPH

"""
    River(points)

A detected river: `points` is a vector of `(line_index, gap_center_x)` for the aligned
inter-word gaps, one per consecutive line, top to bottom.
"""
struct River
    points :: Vector{Tuple{Int,Float64}}
end

"""
    find_rivers(lay::JustifiedLayout; align_tol, min_run=3) -> Vector{River}

Detect rivers in a justified layout. Greedy-chains inter-word gap centers across
consecutive lines: starting from each unclaimed gap in line `L`, extend the chain into
line `L+1` by the nearest unclaimed gap whose center is within `align_tol` of the current
column (**ties broken toward the lower x** for reproducibility under exact arithmetic).
Chains spanning at least `min_run` consecutive lines are returned as `River`s.

`align_tol` is in the layout's x units; a natural choice is one inter-word space width
(gaps that drift by less than a space read as a single vertical channel).
"""
function find_rivers(lay::JustifiedLayout; align_tol::Real, min_run::Int=3)
    tol = Float64(align_tol)
    nlines = length(lay.lines)
    rivers = River[]
    nlines < min_run && return rivers
    # `claimed[L][i]` — gap i of line L already belongs to a river.
    claimed = [falses(length(l.gap_centers)) for l in lay.lines]
    for L in 1:(nlines - 1)
        gaps = lay.lines[L].gap_centers
        for gi in eachindex(gaps)
            claimed[L][gi] && continue
            chain = Tuple{Int,Float64}[(L, gaps[gi])]
            col = gaps[gi]
            ln = L
            while ln + 1 <= nlines
                cand = lay.lines[ln + 1].gap_centers
                best = 0
                bestd = tol
                for j in eachindex(cand)
                    claimed[ln + 1][j] && continue
                    d = abs(cand[j] - col)
                    d > tol && continue
                    # strictly closer, or equally close but lower x (deterministic tie-break)
                    if best == 0 || d < bestd - 1e-12 ||
                       (abs(d - bestd) <= 1e-12 && cand[j] < cand[best])
                        best = j
                        bestd = d
                    end
                end
                best == 0 && break
                claimed[ln + 1][best] = true
                push!(chain, (ln + 1, cand[best]))
                col = cand[best]
                ln += 1
            end
            length(chain) >= min_run && push!(rivers, River(chain))
        end
    end
    return rivers
end

"""
    CANONICAL_PARAGRAPH

The fixed prose paragraph used by the comparison demo and tests. Chosen so that a narrow
measure makes greedy line-breaking pool inter-word gaps into visible rivers that
Knuth–Plass breaks up.
"""
const CANONICAL_PARAGRAPH =
    "The art of justified typesetting asks a deceptively simple question of " *
    "every paragraph it is given to render upon a page: where should each line " *
    "break so that the river of white space running down between the words never " *
    "pools into a distracting channel that draws the eye away from the prose " *
    "itself and toward the empty gaps instead."

end # module
