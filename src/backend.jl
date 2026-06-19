"""
    AbstractMeasurementBackend

Supertype for measurement backends. A backend holds its font configuration and must
implement two methods (neither is exported — define them as `TextMeasure.measure` /
`TextMeasure.font_metrics`):

    measure(backend, text::AbstractString)::Float64   # advance width of ONE run, px
                                                       # (no line breaks; prepare segments)
    font_metrics(backend)::FontMetrics                # ascent/descent/line_advance, px

A run's width is the sum of glyph advances with NO kerning (matches Makie exactly).

The three shipped extension backends are the canonical examples of this pattern:
`FreeTypeBackend` (`ext/TextMeasureFreeTypeExt.jl`), `MakieBackend`
(`ext/TextMeasureMakieExt.jl`), and `FigletBackend` (`ext/TextMeasureFigletExt.jl`).
"""
abstract type AbstractMeasurementBackend end

function measure end
function font_metrics end

"""
    measure_bounds(backend, text) -> TextBounds

2-D analog of [`measure`](@ref) for styled text (e.g. Makie's `RichText`). Returns an
axis-aligned [`TextBounds`](@ref) in the backend's coordinate space. Not implemented
in the base package — each extension adds a method for its own styled type, so calling it
on a backend without one (e.g. `MonospaceBackend`) is a `MethodError`. `backend` must be an
[`AbstractMeasurementBackend`](@ref). See the Makie extension's
`measure_bounds(::MakieBackend, ::Makie.RichText)`.
"""
function measure_bounds end
