"""
    MonospaceBackend(; fontsize=12, advance_ratio=0.6, lineheight_ratio=1.2)

Zero-dependency, built-in measurement backend: each grapheme cluster is
`advance_ratio * fontsize` px wide. Because the geometry is fixed arithmetic (no font
file) it is fully deterministic, which makes it the test backend *and* the simplest way
to learn the API. `lineheight_ratio` sets the natural `line_advance`
(= `lineheight_ratio * fontsize`); that is distinct from `layout`'s `lineheight`, which
scales it further. `font_metrics` reports a nominal 80/20 ascent/descent split — it models
no real font, just a plausible one.

Pass it to [`prepare`](@ref) to measure text once, then [`layout`](@ref) freely.

# Examples
```jldoctest
julia> b = MonospaceBackend(fontsize=10, advance_ratio=1.0);

julia> TextMeasure.measure(b, "abc")       # advance_ratio × fontsize per cluster
30.0

julia> TextMeasure.font_metrics(b)         # ascent, descent (both > 0), line_advance
FontMetrics(8.0, 2.0, 12.0)

julia> lay = layout(prepare(b, "the quick brown fox"); max_width=100);

julia> lay.size                            # (block width, block height) in px
(90.0, 22.0)

julia> [ln.str for ln in lay.lines]
2-element Vector{String}:
 "the quick"
 "brown fox"
```
"""
struct MonospaceBackend <: AbstractMeasurementBackend
    fontsize         :: Float64
    advance_ratio    :: Float64
    lineheight_ratio :: Float64
end

MonospaceBackend(; fontsize=12.0, advance_ratio=0.6, lineheight_ratio=1.2) =
    MonospaceBackend(Float64(fontsize), Float64(advance_ratio), Float64(lineheight_ratio))

measure(b::MonospaceBackend, text::AbstractString) =
    length(graphemes(text)) * b.advance_ratio * b.fontsize

font_metrics(b::MonospaceBackend) =
    FontMetrics(0.8 * b.fontsize, 0.2 * b.fontsize, b.lineheight_ratio * b.fontsize)
