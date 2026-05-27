module TextMeasureFreeTypeExt

using TextMeasure
using FreeTypeAbstraction
const FTA = FreeTypeAbstraction

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
