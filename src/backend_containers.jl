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
