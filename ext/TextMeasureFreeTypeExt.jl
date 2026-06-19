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

function TextMeasure.measure(b::TextMeasure.FreeTypeBackend, text::AbstractString)
    px = _pixel_size(b)
    w = 0.0
    for c in text
        w += FTA.hadvance(FTA.get_extent(b.face, c))   # normalized advance, no kerning
    end
    return w * px
end

function TextMeasure.font_metrics(b::TextMeasure.FreeTypeBackend)
    px   = _pixel_size(b)
    upem = b.face.units_per_EM
    asc  = FTA.ascender(b.face)  * px
    desc = -FTA.descender(b.face) * px               # FT descender is negative
    h    = b.face.height
    la   = h == 0 ? asc + desc : (h / upem) * px     # guard rare height==0 fonts
    return TextMeasure.FontMetrics(asc, desc, la)
end

end # module
