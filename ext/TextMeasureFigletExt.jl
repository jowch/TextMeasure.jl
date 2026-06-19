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

# Cross-platform font resolution. FIGlet.jl bundles its .flf files lowercased
# (e.g. `standard.flf`) yet `FIGlet.DEFAULTFONT == "Standard"`, and `getfontpath` is
# case-sensitive — so `readfont("Standard")` (and the default `FigletBackend()`) throws
# `FontNotFoundError` on case-sensitive filesystems (Linux, CI). Retry lowercased so the
# documented default works everywhere; non-name errors (malformed .flf) still propagate.
function _readfont(name::AbstractString)
    s = String(name)
    try
        return FIGlet.readfont(s)
    catch e
        e isa FIGlet.FontNotFoundError || rethrow()
        lower = lowercase(s)
        lower == s && rethrow()                # already lowercase — nothing new to try
        try
            return FIGlet.readfont(lower)
        catch e2
            e2 isa FIGlet.FontNotFoundError || rethrow()
            # report BOTH attempted names so a truly-missing font is diagnosable.
            throw(FIGlet.FontNotFoundError("Cannot find font `$s` (also tried `$lower`)."))
        end
    end
end

# String → _readfont(name); FIGletFont → use directly. FIGlet.readfont(io) already handles
# user-supplied streams, so no separate `font_data` escape hatch is needed.
"""
    FigletBackend(; font="Standard", letter_gap=0)

Keyword constructor for [`FigletBackend`](@ref), available once `using FIGlet`. `font` is a
FIGlet font name (resolved case-insensitively, so the default `"Standard"` works on
case-sensitive filesystems) or a ready `FIGlet.FIGletFont`. `letter_gap` is an integer count
of blank cells inserted between glyphs.

Unlike the pixel backends, `measure` returns widths in **character cells**, not pixels, and
there is no `measure_bounds` (FIGlet text has no styled-run analog).

# Examples
```julia
using TextMeasure, FIGlet

b = FigletBackend(font="Standard")
TextMeasure.measure(b, "Hi")   # width in cells (Int-valued), not pixels
```
"""
function TextMeasure.FigletBackend(; font::Union{AbstractString,FIGlet.FIGletFont}=FIGlet.DEFAULTFONT,
                                   letter_gap::Int=0)
    f = font isa FIGlet.FIGletFont ? font : _readfont(font)
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
    # Iterate per CODEPOINT (Char), not per grapheme cluster (cf. MonospaceBackend, which
    # uses `graphemes`). FIGlet's `font_characters` is a `Dict{Char,FIGletChar}` keyed by
    # single codepoints, so codepoint iteration is the correct lookup granularity; a
    # multi-codepoint cluster looks up each codepoint separately (combining marks, absent
    # from any FIGfont, take the space-cell fallback).
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
