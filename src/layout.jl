function _emit_line!(raw::Vector{Tuple{String,Float64}}, committed::Vector{Segment})
    s = join(seg.str for seg in committed)
    w = isempty(committed) ? 0.0 : sum(seg.width for seg in committed)
    push!(raw, (s, w))
    empty!(committed)
    return nothing
end

_align_x(align::Symbol, total::Float64, w::Float64) =
    align === :left   ? 0.0 :
    align === :center ? (total - w) / 2 :
    align === :right  ? (total - w) :
    throw(ArgumentError("align must be :left, :center, or :right; got $(repr(align))"))

"""
    layout(prep; max_width=Inf, align=:left, lineheight=1.0) -> Layout

Pure greedy line-breaking over a [`Prepared`](@ref) — no font engine, just arithmetic over
the cached widths, so call it as many times as you like with different settings. Breaks at
whitespace and `\\n`; words are atomic (an over-wide word overflows its own line).
`lineheight` multiplies `prep.metrics.line_advance`. Leading/trailing whitespace is trimmed
per line. A non-positive or `NaN` `max_width` is treated as `Inf` (no wrapping).

# Examples
Measure once, then lay the same `Prepared` out at several widths:

```jldoctest
julia> prep = prepare(MonospaceBackend(fontsize=10, advance_ratio=1.0), "the quick brown fox");

julia> layout(prep; max_width=100).size    # wraps to 2 lines
(90.0, 22.0)

julia> layout(prep; max_width=60).size     # narrower → 4 lines, same prep
(50.0, 46.0)

julia> layout(prep).size                   # max_width=Inf → one line
(190.0, 10.0)
```
"""
function layout(prep::Prepared; max_width::Real=Inf, align::Symbol=:left, lineheight::Real=1.0)::Layout
    m  = prep.metrics
    la = lineheight * m.line_advance
    mw = (isnan(max_width) || max_width <= 0) ? Inf : Float64(max_width)

    isempty(prep.segments) && return Layout(Line[], (0.0, 0.0), m)

    raw = Tuple{String,Float64}[]
    committed = Segment[]
    committed_w = 0.0
    pending::Union{Nothing,Segment} = nothing   # a trailing space, held back: it only joins
                                                 # the line if the following word also fits.

    for seg in prep.segments
        if seg.kind === :newline
            _emit_line!(raw, committed); committed_w = 0.0; pending = nothing
        elseif seg.kind === :space
            pending = seg
        else  # :word
            if isempty(committed)
                push!(committed, seg); committed_w = seg.width; pending = nothing
            else
                extra = (pending === nothing ? 0.0 : pending.width) + seg.width
                if committed_w + extra > mw
                    _emit_line!(raw, committed)
                    push!(committed, seg); committed_w = seg.width; pending = nothing
                else
                    if pending !== nothing
                        push!(committed, pending); committed_w += pending.width; pending = nothing
                    end
                    push!(committed, seg); committed_w += seg.width
                end
            end
        end
    end
    _emit_line!(raw, committed)   # final line — so `raw` is always non-empty here

    N = length(raw)
    total_w = maximum(t -> t[2], raw)   # safe: the final _emit_line! guarantees ≥ 1 tuple
    height  = m.ascent + (N - 1) * la + m.descent
    lines = Vector{Line}(undef, N)
    for (i, (s, w)) in enumerate(raw)
        lines[i] = Line(s, w, _align_x(align, total_w, w), m.ascent + (i - 1) * la)
    end
    return Layout(lines, (total_w, height), m)
end

"""
    line_top(lay::Layout, ln::Line) -> Float64

Top-left y of line `ln` within the block (block top = 0, y increasing downward); `ln` must
be a line of `lay`. Equals `ln.baseline - lay.metrics.ascent`.

# Examples
```jldoctest
julia> lay = layout(prepare(MonospaceBackend(fontsize=10, advance_ratio=1.0), "a\\nb"));

julia> line_top(lay, lay.lines[1])         # first line's top is the block top
0.0

julia> line_top(lay, lay.lines[2])         # next line down by one line_advance
12.0
```
"""
line_top(lay::Layout, ln::Line) = ln.baseline - lay.metrics.ascent
