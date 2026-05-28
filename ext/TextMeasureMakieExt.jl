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

# Child state for :span/:sup/:sub. For :sup/:sub the default size is 0.66·parent and
# the baseline shifts by +0.40·parent (sup) / −0.25·parent (sub); the span `offset`
# (a fraction of the child's fontsize) applies on top, to both x and baseline.
function _rt_child(gs::_RTState, rt::Makie.RichText)
    att = rt.attributes
    t   = rt.type
    off = get(att, :offset, (0.0, 0.0))
    if t === :span
        size = Float64(get(att, :fontsize, gs.size))
        font = haskey(att, :font) ? Makie.to_font(att[:font]) : gs.font
        return _RTState(gs.x + off[1] * size, gs.baseline + off[2] * size, size, font)
    elseif t === :sup
        size = Float64(get(att, :fontsize, 0.66 * gs.size))
        font = haskey(att, :font) ? Makie.to_font(att[:font]) : gs.font
        return _RTState(gs.x + off[1] * size,
                        gs.baseline + 0.40 * gs.size + off[2] * size, size, font)
    elseif t === :sub
        size = Float64(get(att, :fontsize, 0.66 * gs.size))
        font = haskey(att, :font) ? Makie.to_font(att[:font]) : gs.font
        return _RTState(gs.x + off[1] * size,
                        gs.baseline - 0.25 * gs.size + off[2] * size, size, font)
    else
        throw(ArgumentError("unsupported RichText span type: $t"))
    end
end

# sub/sup child state for subsup children. Reads :fontsize/:font from the SUBSUP NODE's
# own attributes (default 0.66·parent / parent font), matching Makie's new_glyphstate for
# :subsup_sub/:subsup_sup. NOTE: Makie does NOT apply the span `offset` to subsup children
# (unlike :sub/:sup), so none is added here. The baseline shift constants stay parent-based.
function _rt_subsup(gs::_RTState, rt::Makie.RichText, ::Val{:sup})
    att  = rt.attributes
    size = Float64(get(att, :fontsize, 0.66 * gs.size))
    font = haskey(att, :font) ? Makie.to_font(att[:font]) : gs.font
    return _RTState(gs.x, gs.baseline + 0.40 * gs.size, size, font)
end
function _rt_subsup(gs::_RTState, rt::Makie.RichText, ::Val{:sub})
    att  = rt.attributes
    size = Float64(get(att, :fontsize, 0.66 * gs.size))
    font = haskey(att, :font) ? Makie.to_font(att[:font]) : gs.font
    return _RTState(gs.x, gs.baseline - 0.25 * gs.size, size, font)
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
    t  = rt.type
    if t === :subsup || t === :leftsubsup
        length(rt.children) == 2 ||
            throw(ArgumentError("$t requires exactly 2 children (sub, super)"))
        # children laid out from the SAME parent x and baseline (child 1 = sub, 2 = super);
        # subsup node's :fontsize/:font flow to both children via `rt` → _rt_subsup
        e_sub = _rt_walk!(runs, _rt_subsup(gs, rt, Val(:sub)), rt.children[1])
        e_sup = _rt_walk!(runs, _rt_subsup(gs, rt, Val(:sup)), rt.children[2])
        # AABB advances by the wider child; alignment doesn't change the union box
        return _RTState(max(e_sub.x, e_sup.x), gs.baseline, gs.size, gs.font)
    else
        cur = _rt_child(gs, rt)
        for child in rt.children
            cur = _rt_walk!(runs, cur, child)
        end
        # advance x; restore baseline/size/font to the parent
        # (No `\n` handling at this task; Task 5 will introduce a `drop::Ref{Float64}`
        # so that newlines nested in a child persist across this return.)
        return _RTState(cur.x, gs.baseline, gs.size, gs.font)
    end
end

function TextMeasure.measure_bounds(b::TextMeasure.MakieBackend, rt::Makie.RichText)
    runs = TextMeasure.StyledRun[]
    gs0  = _RTState(0.0, 0.0, _pixel_size(b), b.face)
    _rt_walk!(runs, gs0, rt)
    return TextMeasure.bounds(runs)
end

end # module
