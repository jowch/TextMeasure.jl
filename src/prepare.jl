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
via `backend`. The only phase that touches the font engine.
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

Return a `Prepared` over the segment sub-range `r`, reusing the already-measured
segment widths and echoing `prep.metrics` — no re-measurement. Motivates #E's
word-boundary fracture (re-pack halves of a measured paragraph). No `Base.getindex`
override: `prep[i]` should still yield a `Segment`, the contained element type.
"""
subprep(prep::Prepared, r::AbstractUnitRange) = Prepared(prep.segments[r], prep.metrics)
