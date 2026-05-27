"""
    AbstractMeasurementBackend

Supertype for measurement backends. A backend holds its font configuration and must
implement two methods (neither is exported — define them as `TextMeasure.measure` /
`TextMeasure.font_metrics`):

    measure(backend, text::AbstractString)::Float64   # advance width of ONE run, px
                                                       # (no line breaks; prepare segments)
    font_metrics(backend)::FontMetrics                # ascent/descent/line_advance, px

A run's width is the sum of glyph advances with NO kerning (matches Makie exactly).
"""
abstract type AbstractMeasurementBackend end

function measure end
function font_metrics end
