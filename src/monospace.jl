"""
    MonospaceBackend(; fontsize=12, advance_ratio=0.6, lineheight_ratio=1.2)

Zero-dependency estimate: each grapheme cluster is `advance_ratio * fontsize` px wide.
Deterministic — also used as the test backend. `lineheight_ratio` sets the natural
`line_advance` (= `lineheight_ratio * fontsize`); distinct from `layout`'s `lineheight`.
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
