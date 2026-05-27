module TextMeasureMakieExt

using TextMeasure
using Makie
const FTA = Makie.FreeTypeAbstraction   # Makie.NativeFont === FTA.FTFont

function TextMeasure.MakieBackend(; font=Makie.automatic, fontsize=12, px_per_unit=1.0)
    face = Makie.to_font(font)          # resolves to an FTFont (identical to text!'s)
    return TextMeasure.MakieBackend(face, Float64(fontsize), Float64(px_per_unit))
end

_pixel_size(b::TextMeasure.MakieBackend) = b.fontsize * b.px_per_unit

function TextMeasure.measure(b::TextMeasure.MakieBackend, text::AbstractString)
    px = _pixel_size(b)
    w = 0.0
    for c in text
        w += FTA.hadvance(FTA.get_extent(b.face, c))
    end
    return w * px
end

function TextMeasure.font_metrics(b::TextMeasure.MakieBackend)
    px   = _pixel_size(b)
    upem = b.face.units_per_EM
    asc  = FTA.ascender(b.face)  * px
    desc = -FTA.descender(b.face) * px
    h    = b.face.height
    la   = h == 0 ? asc + desc : (h / upem) * px
    return TextMeasure.FontMetrics(asc, desc, la)
end

end # module
