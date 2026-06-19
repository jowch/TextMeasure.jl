# SPDX-License-Identifier: MIT
#
# knuth_plass — optimal whole-paragraph line breaking (#K, demos milestone).
# Port of pretext.js kp.ts. Classic Knuth–Plass box/glue dynamic program minimizing
# total badness. Justification is OUT of TextMeasure's library scope (CLAUDE.md) — this
# is a downstream demo utility living in the examples/layouts package.
#
# Box/glue model over `Prepared.segments`:
#   :word     -> a box (fixed width)
#   :space    -> interword glue (one collapsed run per gap); natural width = measured
#                space width `g`, stretchable by `g·stretch_ratio`, shrinkable by
#                `g·shrink_ratio` (TeX's interword ratios: 0.5 / (1/3) by default).
#   :newline  -> a FORCED break in the gap that follows the preceding word.
#
# Per-line badness is TeX's `100·|r|³` on the adjustment ratio `r`; infeasible lines
# (overshrink `r < -1`, or an atomic over-wide word) cost `INF_BADNESS + overflow` so the
# DP is always solvable and feasible lines always sort below infeasible ones. The last
# line of the paragraph — and any line ending at a forced break — is RAGGED: badness 0
# when it fits (it is not stretched to the measure).

const INF_BADNESS = 1.0e4   # TeX's "infinitely bad"; finite so the DP always has a path.

"""
    JustifiedLine(words, word_x, gap_centers, natural_width, ratio, badness, baseline)

One justified line. Coordinates share `layout`'s frame (block-left = 0, block-top = 0,
y increasing downward).

- `words` — `:word` segment indices (into the source `Prepared.segments`), left to right.
- `word_x` — justified left edge of each word (same length as `words`).
- `gap_centers` — x center of each interword gap after justification (length `nwords - 1`).
- `natural_width` — unjustified line width (boxes + natural glue).
- `ratio` — adjustment ratio `r` (`0` for a ragged line; `±Inf` flags an infeasible line).
- `badness` — this line's contribution to `total_badness`.
- `baseline` — block-top-frame baseline y.
"""
struct JustifiedLine
    words         :: Vector{Int}
    word_x        :: Vector{Float64}
    gap_centers   :: Vector{Float64}
    natural_width :: Float64
    ratio         :: Float64
    badness       :: Float64
    baseline      :: Float64
end

"""
    JustifiedLayout(lines, total_badness, max_width, metrics)

Result of [`knuth_plass`](@ref) / [`greedy_justify`](@ref). `total_badness` is the sum of
per-line `badness`. Read-only by convention.
"""
struct JustifiedLayout
    lines         :: Vector{JustifiedLine}
    total_badness :: Float64
    max_width     :: Float64
    metrics       :: FontMetrics
end

# Extract the box/glue model from a Prepared. Returns:
#   segidx :: Vector{Int}      absolute segment index of each :word (the box)
#   w      :: Vector{Float64}  box widths
#   g      :: Vector{Float64}  natural glue width AFTER word k (0 for the last word)
#   forced :: Vector{Bool}     a forced (:newline) break lies in the gap after word k
# Leading whitespace before the first word is dropped; consecutive spaces collapse to one
# glue width; a :newline sets the forced flag on the gap following the most recent word.
function _boxes_glue(prep::Prepared)
    segs = prep.segments
    segidx = Int[]; w = Float64[]; g = Float64[]; forced = Bool[]
    pending_glue = 0.0
    pending_forced = false
    have_word = false
    for (i, s) in enumerate(segs)
        if s.kind === :word
            if have_word
                g[end] = pending_glue
                forced[end] = pending_forced
            end
            push!(segidx, i); push!(w, s.width); push!(g, 0.0); push!(forced, false)
            have_word = true
            pending_glue = 0.0; pending_forced = false
        elseif s.kind === :space
            pending_glue += s.width
        else # :newline
            pending_forced = true
        end
    end
    # Paragraph end is a forced break. The DP/greedy also special-case `j == W` for the
    # last line, but this flag still feeds `_assemble`'s `is_last` and the
    # `forced[a] && break` guard, so it is load-bearing — don't drop it.
    have_word && (forced[end] = true)
    return segidx, w, g, forced
end

# Adjustment ratio + badness for a line of natural width `nat`, total `stretch`/`shrink`,
# targeting `target`. `is_last` ⇒ ragged (no stretch, badness 0 when it fits).
function _badness(nat::Float64, stretch::Float64, shrink::Float64, target::Float64, is_last::Bool)
    is_last && nat <= target && return (0.0, 0.0)
    if nat <= target
        nat == target && return (0.0, 0.0)
        stretch <= 0 && return (Inf, INF_BADNESS + (target - nat))         # can't stretch
        r = (target - nat) / stretch
        return (r, min(100 * r^3, INF_BADNESS))                            # M3: cap feasible underfull
    else
        shrink <= 0 && return (-Inf, INF_BADNESS + (nat - target))         # atomic over-wide word
        r = (target - nat) / shrink                                        # negative
        r < -1 && return (r, INF_BADNESS + (nat - target))                 # overshrink: infeasible
        return (r, 100 * abs(r)^3)
    end
end

# Per-gap width added by justification (0 for a ragged/infeasible line).
_adjust(r::Float64, gk::Float64, sr::Float64, zr::Float64) =
    !isfinite(r) ? 0.0 : (r >= 0 ? r * gk * sr : r * gk * zr)

# Build a JustifiedLine for words a..b (1-based into the box/glue arrays).
function _build_line(segidx, w, g, sr, zr, a::Int, b::Int, target::Float64,
                     baseline::Float64, is_last::Bool)
    nat = 0.0; gl = 0.0
    @inbounds for k in a:b
        nat += w[k]
        k < b && (gl += g[k])
    end
    nat += gl
    stretch = sr * gl
    shrink  = zr * gl
    r, bad = _badness(nat, stretch, shrink, target, is_last)
    r_used = isfinite(r) ? r : 0.0
    nwords = b - a + 1
    word_x = Vector{Float64}(undef, nwords)
    gap_centers = Float64[]
    x = 0.0
    @inbounds for (j, k) in enumerate(a:b)
        word_x[j] = x
        x += w[k]
        if k < b
            gk = g[k]
            gw = gk + _adjust(r_used, gk, sr, zr)
            push!(gap_centers, x + gw / 2)
            x += gw
        end
    end
    return JustifiedLine(segidx[a:b], word_x, gap_centers, nat, r, bad, baseline)
end

function _assemble(spans::Vector{Tuple{Int,Int}}, segidx, w, g, forced, sr, zr,
                   target::Float64, la::Float64, asc::Float64, W::Int, m::FontMetrics)
    lines = Vector{JustifiedLine}(undef, length(spans))
    total = 0.0
    for (li, (a, b)) in enumerate(spans)
        is_last = forced[b] || b == W
        baseline = asc + (li - 1) * la
        ln = _build_line(segidx, w, g, sr, zr, a, b, target, baseline, is_last)
        lines[li] = ln
        total += ln.badness
    end
    return JustifiedLayout(lines, total, target, m)
end

"""
    knuth_plass(prep; max_width, stretch_ratio=0.5, shrink_ratio=1/3, lineheight=1.0) -> JustifiedLayout

Optimal whole-paragraph line breaks minimizing total badness (the Knuth–Plass dynamic
program). `:newline` segments are forced breaks; the last line and any line ending at a
forced break are set ragged. `max_width` is the target measure; `stretch_ratio` /
`shrink_ratio` scale interword glue elasticity; `lineheight` multiplies
`prep.metrics.line_advance`. Compare [`greedy_justify`](@ref), which uses the same badness
geometry but the greedy break set — `knuth_plass`'s `total_badness` is always ≤ greedy's.

# Examples
```jldoctest
julia> using TextMeasure, TextMeasureLayouts

julia> prep = prepare(MonospaceBackend(), "xxxxxxx x x xxxxxxx");

julia> k = knuth_plass(prep; max_width=79.2);

julia> [[prep.segments[i].str for i in ln.words] for ln in k.lines]
2-element Vector{Vector{String}}:
 ["xxxxxxx", "x", "x"]
 ["xxxxxxx"]

julia> k.total_badness < 1e-6      # the first line fills the measure exactly: optimal
true
```
"""
function knuth_plass(prep::Prepared; max_width::Real, stretch_ratio::Real=0.5,
                     shrink_ratio::Real=1/3, lineheight::Real=1.0)::JustifiedLayout
    max_width > 0 || throw(ArgumentError("max_width must be > 0; got $max_width"))
    m = prep.metrics
    target = Float64(max_width)
    sr = Float64(stretch_ratio); zr = Float64(shrink_ratio)
    la = Float64(lineheight) * m.line_advance
    segidx, w, g, forced = _boxes_glue(prep)
    W = length(w)
    W == 0 && return JustifiedLayout(JustifiedLine[], 0.0, target, m)

    # best_after[k+1] = min total badness for words 1..k with a line ending after word k.
    best_after = fill(Inf, W + 1); best_after[1] = 0.0
    prev = zeros(Int, W + 1)
    for j in 1:W
        is_last = forced[j] || j == W
        nat = 0.0; gl = 0.0
        # Extend the line leftward (a = j, j-1, …); accumulate width incrementally.
        for a in j:-1:1
            @inbounds nat += w[a]
            if a < j
                @inbounds nat += g[a]; gl += g[a]
                # gap after word a is now interior; a forced break there is illegal.
                @inbounds forced[a] && break
            end
            stretch = sr * gl; shrink = zr * gl
            _, bad = _badness(nat, stretch, shrink, target, is_last)
            cand = best_after[a] + bad           # best_after[a] == best ending after word a-1
            if cand < best_after[j + 1]
                best_after[j + 1] = cand
                prev[j + 1] = a - 1
            end
        end
    end

    spans = Tuple{Int,Int}[]
    k = W
    while k > 0
        a = prev[k + 1] + 1
        push!(spans, (a, k))
        k = prev[k + 1]
    end
    reverse!(spans)
    return _assemble(spans, segidx, w, g, forced, sr, zr, target, la, m.ascent, W, m)
end

"""
    greedy_justify(prep; max_width, stretch_ratio=0.5, shrink_ratio=1/3, lineheight=1.0) -> JustifiedLayout

Greedy line breaks (the baseline) justified with the SAME badness/geometry as
[`knuth_plass`](@ref). Break selection mirrors `src/layout.jl` byte-for-byte and uses only
NATURAL widths — a word joins the current line while
`committed_natural + space_natural + word_natural ≤ max_width`, otherwise it starts the
next line; words are atomic; forced breaks at `:newline`. The justified adjustment ratio is
never consulted for the break decision, so the only difference from `knuth_plass` is the
break-selection algorithm.
"""
function greedy_justify(prep::Prepared; max_width::Real, stretch_ratio::Real=0.5,
                        shrink_ratio::Real=1/3, lineheight::Real=1.0)::JustifiedLayout
    max_width > 0 || throw(ArgumentError("max_width must be > 0; got $max_width"))
    m = prep.metrics
    target = Float64(max_width)
    sr = Float64(stretch_ratio); zr = Float64(shrink_ratio)
    la = Float64(lineheight) * m.line_advance
    segidx, w, g, forced = _boxes_glue(prep)
    W = length(w)
    W == 0 && return JustifiedLayout(JustifiedLine[], 0.0, target, m)

    spans = Tuple{Int,Int}[]
    a = 1
    cur = w[1]                                   # natural width committed on the current line
    for nextw in 2:W
        if forced[nextw - 1]                     # forced break after the previous word
            push!(spans, (a, nextw - 1)); a = nextw; cur = w[nextw]
            continue
        end
        add = g[nextw - 1] + w[nextw]            # natural space + natural word (layout.jl:43-44)
        if cur + add > target                    # strictly greater ⇒ break (matches layout)
            push!(spans, (a, nextw - 1)); a = nextw; cur = w[nextw]
        else
            cur += add
        end
    end
    push!(spans, (a, W))
    return _assemble(spans, segidx, w, g, forced, sr, zr, target, la, m.ascent, W, m)
end
