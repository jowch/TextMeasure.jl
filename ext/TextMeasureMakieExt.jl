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

# ---- RichText bounding box -------------------------------------------------
# Mirrors Makie's process_rt_node!/new_glyphstate (src/basic_recipes/text.jl) so the
# box equals what text! will render. Glyph state uses Makie's +y-up convention; the
# constants (0.66, +0.40, −0.25, 20px) are pinned to Makie 0.24.x and guarded by
# test/test_richtext.jl. measure_bounds is called with px_per_unit = 1 (CLAUDE.md).

# Per-span state during the walk. `size` is the resolved fontsize in px.
struct _RTState
    x        :: Float64
    baseline :: Float64
    size     :: Float64
    font                  # FTFont
end

# Child state for a :span node (font/size/offset inheritance; offset is a fraction
# of the span's own fontsize, applied to both x and baseline — matches Makie).
function _rt_child(gs::_RTState, rt::Makie.RichText)
    att = rt.attributes
    rt.type === :span ||
        throw(ArgumentError("unsupported RichText span type: $(rt.type)"))
    size = Float64(get(att, :fontsize, gs.size))
    off  = get(att, :offset, (0.0, 0.0))
    font = haskey(att, :font) ? Makie.to_font(att[:font]) : gs.font
    return _RTState(gs.x + off[1] * size, gs.baseline + off[2] * size, size, font)
end

# Emit StyledRuns for a string leaf; return the advanced state.
function _rt_string!(runs::Vector{TextMeasure.StyledRun}, gs::_RTState, s::AbstractString)
    asc  =  FTA.ascender(gs.font)  * gs.size
    desc = -FTA.descender(gs.font) * gs.size
    x = gs.x; seg_start = gs.x; seg_w = 0.0; nonempty = false
    for ch in s
        bestfont = Makie.find_font_for_char(ch, gs.font)
        adv = FTA.hadvance(FTA.get_extent(bestfont, ch)) * gs.size
        seg_w += adv; x += adv; nonempty = true
    end
    if nonempty
        push!(runs, TextMeasure.StyledRun(seg_start, gs.baseline, seg_w, asc, desc))
    end
    return _RTState(x, gs.baseline, gs.size, gs.font)
end

# Walk a node (String or RichText), pushing StyledRuns; return the advanced state.
function _rt_walk!(runs::Vector{TextMeasure.StyledRun}, gs::_RTState, node)
    node isa AbstractString && return _rt_string!(runs, gs, node)
    rt = node::Makie.RichText
    cur = _rt_child(gs, rt)
    for child in rt.children
        cur = _rt_walk!(runs, cur, child)
    end
    # advance x; restore baseline/size/font to the parent
    return _RTState(cur.x, gs.baseline, gs.size, gs.font)
end

function TextMeasure.measure_bounds(b::TextMeasure.MakieBackend, rt::Makie.RichText)
    runs = TextMeasure.StyledRun[]
    gs0  = _RTState(0.0, 0.0, _pixel_size(b), b.face)
    _rt_walk!(runs, gs0, rt)
    return TextMeasure.bounds(runs)
end

end # module
