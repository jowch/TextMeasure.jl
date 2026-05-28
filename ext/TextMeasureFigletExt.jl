module TextMeasureFigletExt

# === The THIRD example of the canonical weakdep-extension backend pattern. ===
# Mirrors ext/TextMeasureFreeTypeExt.jl and ext/TextMeasureMakieExt.jl: a container
# struct lives in src/ (src/backend_containers.jl), and this gated extension supplies
# the keyword constructor + TextMeasure.measure + TextMeasure.font_metrics, activating
# only when the user runs `using FIGlet`.
#
# TWO DELIBERATE DEPARTURES from the FreeType/Makie backends — NOT bugs:
#   1. NO `fontsize`. FreeType/Makie scale widths by fontsize in pixels. FIGlet glyphs
#      live on a fixed integer cell grid — width/height are intrinsic cell counts, not
#      scalable. `measure` therefore returns widths in CHARACTER CELLS, NOT PIXELS.
#      Downstream consumers (#E asteroid TUI, #C shape_pack with a raster chord fn) work
#      in cell coordinates and treat FontMetrics values as cell counts.
#   2. `letter_gap :: Int` (not Float64): an integer count of cells between glyphs.
#
# Also: NO `measure_bounds` method — Figlet is plain monospace-cell text with no
# styled-text analog (unlike Makie's RichText), so the 2-D bounded primitive doesn't apply.

using TextMeasure
using FIGlet

# String → readfont(name); FIGletFont → use directly. FIGlet.readfont(io) already handles
# user-supplied streams, so no separate `font_data` escape hatch is needed.
function TextMeasure.FigletBackend(; font::Union{AbstractString,FIGlet.FIGletFont}=FIGlet.DEFAULTFONT,
                                   letter_gap::Int=0)
    f = font isa FIGlet.FIGletFont ? font : FIGlet.readfont(String(font))
    return TextMeasure.FigletBackend(f, letter_gap)
end

# Sum per-character cell widths. Missing glyph → fall back to the space cell's width
# (the bundled Standard font's own behavior). NEVER bare-index font_characters[c] — a
# missing key would throw KeyError mid-render. Integer-valued cell count returned as
# Float64 to honor the `measure` return-type contract.
function TextMeasure.measure(b::TextMeasure.FigletBackend, text::AbstractString)
    isempty(text) && return 0.0
    chars = b.font.font_characters
    fallback = get(chars, ' ', nothing)
    w = 0
    for c in text
        glyph = get(chars, c, fallback)
        glyph === nothing && continue          # no glyph and no space fallback → 0-width
        w += size(glyph.thechar, 2)            # thechar is Matrix{Char}(height, width); dim-2 = width
    end
    w += b.letter_gap * (length(text) - 1)
    return Float64(w)
end

# Cell-grid metrics: header.height is the line advance; header.baseline is the ascent;
# descent = height − baseline. All in cell counts, returned as Float64.
function TextMeasure.font_metrics(b::TextMeasure.FigletBackend)
    h  = b.font.header.height
    bl = b.font.header.baseline
    return TextMeasure.FontMetrics(Float64(bl), Float64(h - bl), Float64(h))
end

end # module
