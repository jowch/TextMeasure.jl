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

Pure greedy line-breaking over a `Prepared`. Breaks at whitespace and `\\n`; words are
atomic (an over-wide word overflows its own line). `lineheight` multiplies
`prep.metrics.line_advance`. Trims leading/trailing whitespace per line.
"""
function layout(prep::Prepared; max_width::Real=Inf, align::Symbol=:left, lineheight::Real=1.0)::Layout
    m  = prep.metrics
    la = lineheight * m.line_advance
    mw = (isnan(max_width) || max_width <= 0) ? Inf : Float64(max_width)

    isempty(prep.segments) && return Layout(Line[], (0.0, 0.0), m)

    raw = Tuple{String,Float64}[]
    committed = Segment[]
    committed_w = 0.0
    pending::Union{Nothing,Segment} = nothing

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
    _emit_line!(raw, committed)   # final line

    N = length(raw)
    total_w = maximum(t -> t[2], raw)
    height  = m.ascent + (N - 1) * la + m.descent
    lines = Vector{Line}(undef, N)
    for (i, (s, w)) in enumerate(raw)
        lines[i] = Line(s, w, _align_x(align, total_w, w), m.ascent + (i - 1) * la)
    end
    return Layout(lines, (total_w, height), m)
end

"""    line_top(lay, ln) -> Float64

Top-left y of line `ln` (block top = 0). `ln` must be a line of `lay`."""
line_top(lay::Layout, ln::Line) = ln.baseline - lay.metrics.ascent
