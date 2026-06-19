# SPDX-License-Identifier: MIT
#
# Shared FreeType metric math for the FreeType and Makie backends. Both extensions bind
# `const FTA = FreeTypeAbstraction` and then `include` this file, so the advance-summing and
# ascent/descent/line-advance logic lives in EXACTLY ONE place — no more "keep the two
# extensions in sync" hazard. The only per-backend difference is the pixel-size scalar, which
# each `measure`/`font_metrics` method passes in.

# Advance width of a run in font units: sum of per-glyph advances, NO kerning (this is what
# makes results match Makie exactly). Multiply by the backend's pixel size to get px.
_advance_units(face, text::AbstractString) =
    sum(c -> FTA.hadvance(FTA.get_extent(face, c)), text; init = 0.0)

# Vertical metrics at pixel size `px`. FreeType's descender is negative (below baseline), so
# negate it to TextMeasure's positive-descent convention; guard the rare height==0 font.
function _face_metrics(face, px::Float64)
    upem = face.units_per_EM
    asc  =  FTA.ascender(face)  * px
    desc = -FTA.descender(face) * px
    h    = face.height
    la   = h == 0 ? asc + desc : (h / upem) * px
    return TextMeasure.FontMetrics(asc, desc, la)
end
