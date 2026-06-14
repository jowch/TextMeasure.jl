import TextMeasure
using TextMeasure: MakieBackend
using TextMeasureLayouts: knuth_plass
using HouseStyle: RAMP, fraunces, plexmono, hanken
using CairoMakie, Makie
using Makie: Point2f

# ---- LOCAL palette (type-specimen; stays local to Woven, NOT in HouseStyle) ----------
_hex(s) = Makie.to_color(s)
const BG    = _hex("#F6F6F4")
const INK   = _hex("#161616")
const RED   = _hex("#C8341F")
const GHOST = Makie.RGBA(Makie.RGB(INK), 0.22)

# Real-font backend factory for the hero: MakieBackend is KEYWORD-ONLY, px_per_unit = 1 to
# match Makie's markerspace geometry. Cached per (font, size) by placement_table.
_make_hero_backend(font, size) =
    MakieBackend(; font = font, fontsize = Float64(size), px_per_unit = 1)

# Masthead chrome face (Hanken sans) + measure helper (own one-shot backend; not cached).
_chrome_w(font, size, txt) =
    TextMeasure.measure(MakieBackend(; font = font, fontsize = Float64(size), px_per_unit = 1), txt)

"""
    hero(path) -> (; placements, png)

Render the locked Woven hero: ONE MIT License laid out by the engine and faded to a Plex
Mono ghost; TWO found poems lit in place (RED grant clause, BLACK notice→warranty), every
word MEASURED at its real face/size then justified with Knuth–Plass so nothing overlaps.
Draws the two-colour "Free, As Is" masthead, EXHIBIT A, the red rule, the ghost + lit body,
and the "TextMeasure.jl" footer in the local palette, then writes the PNG.

Built on `placement_table` with `MakieBackend` (real font widths). Faithful to the locked
prototype (`render_woven.jl`); the look is fixed.
"""
function hero(path)
    placements, jl, pitch = placement_table(_make_hero_backend;
        ghost_color = GHOST, red_color = RED, black_color = INK)

    asc = jl.metrics.ascent
    desc = jl.metrics.descent
    col_w = jl.max_width
    block_h = isempty(jl.lines) ? 0.0 : (jl.lines[end].baseline + desc)

    # ---- page geometry (verbatim from the prototype) -----------------------------------
    ml, mr, mt, mb = 84.0, 84.0, 72.0, 60.0
    masthead_h = 66.0
    body_top   = mt + masthead_h
    page_w     = ml + col_w + mr
    page_h     = body_top + block_h + 30.0 + mb

    scale = 2.4
    fig = Figure(; size = (round(Int, page_w), round(Int, page_h)), backgroundcolor = BG)
    ax = Axis(fig[1, 1]; backgroundcolor = BG, aspect = DataAspect())
    hidedecorations!(ax); hidespines!(ax); ax.yreversed = true
    Makie.xlims!(ax, 0, page_w); Makie.ylims!(ax, page_h, 0)

    # masthead — the title IS the two poems' pivots, colour-keyed (red poem / black poem)
    title_sz   = RAMP.title
    title_font = hanken("Bold")          # chrome is Hanken sans
    ty = mt + 34
    text!(ax, Point2f(ml, ty); text = "Free,", color = RED,
          font = title_font, fontsize = title_sz, align = (:left, :baseline))
    fx = _chrome_w(title_font, title_sz, "Free,") + 1.8 * _chrome_w(title_font, title_sz, " ")
    text!(ax, Point2f(ml + fx, ty); text = "As Is", color = INK,
          font = title_font, fontsize = title_sz, align = (:left, :baseline))
    text!(ax, Point2f(page_w - mr, ty); text = "EXHIBIT A", color = RED,
          font = hanken("SemiBold"), fontsize = RAMP.caption, align = (:right, :baseline))
    ry = mt + masthead_h - 14
    lines!(ax, [Point2f(ml, ry), Point2f(ml + col_w, ry)]; color = RED, linewidth = 1.0)

    # body — every word at its justified position (constant baseline grid)
    for p in placements
        text!(ax, Point2f(ml + p.x, body_top + p.baseline); text = p.str,
              color = p.color, font = p.font, fontsize = p.size, align = (:left, :baseline))
    end

    # footer
    text!(ax, Point2f(ml, page_h - mb + 24); text = "TextMeasure.jl", color = RED,
          font = hanken("Regular"), fontsize = RAMP.caption, align = (:left, :baseline))

    save(path, fig; px_per_unit = scale)
    return (; placements = placements, png = path)
end
