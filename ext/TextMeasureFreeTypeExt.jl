module TextMeasureFreeTypeExt

using TextMeasure
using FreeTypeAbstraction
const FTA = FreeTypeAbstraction

"""
    FreeTypeBackend(; font="Inter", fontsize=12, dpi=72)

Keyword constructor for [`FreeTypeBackend`](@ref), available once
`using FreeTypeAbstraction`. `font` is a family name or font-file path resolved through
`FreeTypeAbstraction.findfont`; a name it cannot resolve throws `ArgumentError`. Run widths
scale with the pixel size `fontsize * dpi / 72`.

# Examples
```julia
using TextMeasure, FreeTypeAbstraction

b    = FreeTypeBackend(font="Inter", fontsize=14)   # resolved via findfont
prep = prepare(b, "the quick brown fox")            # measure once, against Inter@14px
lay  = layout(prep; max_width=120)                  # lay out; widths come from the font
lay.size                                            # (width, height) in px
```
"""
function TextMeasure.FreeTypeBackend(; font="Inter", fontsize=12, dpi=72)
    face = FTA.findfont(font)
    face === nothing && throw(ArgumentError("font not found: $(repr(font))"))
    return TextMeasure.FreeTypeBackend(face, Float64(fontsize), Float64(dpi))
end

_pixel_size(b::TextMeasure.FreeTypeBackend) = b.fontsize * b.dpi / 72

include("shared_metrics.jl")   # _advance_units / _face_metrics, shared with the Makie backend

TextMeasure.measure(b::TextMeasure.FreeTypeBackend, text::AbstractString) =
    _advance_units(b.face, text) * _pixel_size(b)

TextMeasure.font_metrics(b::TextMeasure.FreeTypeBackend) =
    _face_metrics(b.face, _pixel_size(b))

end # module
