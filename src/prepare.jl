function _measure_checked(backend::AbstractMeasurementBackend, s::AbstractString)
    w = measure(backend, s)
    isnan(w) && throw(ArgumentError("backend measured NaN for run $(repr(s))"))
    return max(0.0, Float64(w))
end

function _flush!(segs::Vector{Segment}, buf::IOBuffer, bufclass::Symbol,
                 backend::AbstractMeasurementBackend)
    if bufclass !== :none
        s = String(take!(buf))
        push!(segs, Segment(s, _measure_checked(backend, s), bufclass))
    end
    return :none
end

"""
    prepare(backend, text) -> Prepared

Tokenize `text` into `:word` / `:space` / `:newline` segments and measure each run once
via `backend`, caching the widths alongside the font metrics. This is the only phase that
touches the font engine; the returned [`Prepared`](@ref) feeds [`layout`](@ref), which you
can then call repeatedly (different `max_width`, `align`, ...) without re-measuring.

# Examples
```jldoctest
julia> prep = prepare(MonospaceBackend(fontsize=10, advance_ratio=1.0), "hi world");

julia> length(prep.segments)               # word, space, word
3

julia> getfield.(prep.segments, :kind)
3-element Vector{Symbol}:
 :word
 :space
 :word

julia> getfield.(prep.segments, :width)    # measured once, reused by every layout
3-element Vector{Float64}:
 20.0
 10.0
 50.0
```
"""
function prepare(backend::AbstractMeasurementBackend, text::AbstractString)::Prepared
    metrics = font_metrics(backend)
    segs = Segment[]
    buf = IOBuffer()
    bufclass = :none
    for c in text
        if c == '\n'
            bufclass = _flush!(segs, buf, bufclass, backend)
            push!(segs, Segment("\n", 0.0, :newline))
        else
            cls = (c == ' ' || c == '\t') ? :space : :word
            if cls !== bufclass
                bufclass = _flush!(segs, buf, bufclass, backend)
                bufclass = cls
            end
            print(buf, c)
        end
    end
    _flush!(segs, buf, bufclass, backend)
    return Prepared(segs, metrics)
end

"""
    subprep(prep::Prepared, r::AbstractUnitRange) -> Prepared

Return a [`Prepared`](@ref) over the segment sub-range `r`, reusing the already-measured
segment widths and echoing `prep.metrics` — no re-measurement. Use it to re-`layout` part
of an already-measured paragraph (e.g. split a measured run and pack each half into its own
column) without touching the font engine again.

# Examples
```jldoctest
julia> prep = prepare(MonospaceBackend(fontsize=10, advance_ratio=1.0), "alpha beta gamma");

julia> sub = subprep(prep, 1:3);           # first word, the space, second word

julia> [ln.str for ln in layout(sub).lines]
1-element Vector{String}:
 "alpha beta"
```
"""
subprep(prep::Prepared, r::AbstractUnitRange) = Prepared(prep.segments[r], prep.metrics)
