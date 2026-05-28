"""
    FreeTypeBackend(face, fontsize, dpi)

Container holding an opaque font face (`face::F`). The accurate keyword constructor
`FreeTypeBackend(; font, fontsize, dpi)` and the `measure`/`font_metrics` methods are
provided by the FreeTypeAbstraction extension — `using FreeTypeAbstraction` to enable.
"""
struct FreeTypeBackend{F} <: AbstractMeasurementBackend
    face     :: F
    fontsize :: Float64
    dpi      :: Float64
end

"""
    MakieBackend(face, fontsize, px_per_unit)

Container holding an opaque font face (`face::F`). The keyword constructor
`MakieBackend(; font, fontsize, px_per_unit)` and the `measure`/`font_metrics` methods are
provided by the Makie extension — `using Makie` to enable. Keep `px_per_unit = 1` to match
Makie's markerspace/scene geometry.
"""
struct MakieBackend{F} <: AbstractMeasurementBackend
    face        :: F
    fontsize    :: Float64
    px_per_unit :: Float64
end

"""
    FigletBackend(font, letter_gap)

Container holding an opaque FIGlet font (`font::F`; a `FIGlet.FIGletFont` once the ext
loads). The keyword constructor `FigletBackend(; font, letter_gap)` and the
`measure`/`font_metrics` methods are provided by the FIGlet extension —
`using FIGlet` to enable.

Two deliberate departures from `FreeTypeBackend`/`MakieBackend`: there is **no
`fontsize` field** (FIGlet glyphs live on a fixed integer cell grid — `measure` returns
cell counts, not pixels), and `letter_gap` is an **`Int`** (a count of cells between
glyphs), not a `Float64`.
"""
struct FigletBackend{F} <: AbstractMeasurementBackend
    font       :: F
    letter_gap :: Int
end
