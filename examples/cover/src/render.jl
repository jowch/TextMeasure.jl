# SPDX-License-Identifier: MIT
#
# render.jl — the ONLY CairoMakie-touching layer. Replays a ComposedCover onto a
# pixel-coordinate Scene (1 unit = 1 pt). Internal coords are block-top (y down); we
# flip once here: makie_y = H - y. Text via text!(align=(:left,:baseline)); the SVG
# inset via poly!/lines! (native vector — never a bitmap).

import CairoMakie
const MK = CairoMakie.Makie

_rgb(t::NTuple{3,Float64}) = MK.RGBf(t[1], t[2], t[3])

function _draw_text!(sc, H, t::PlacedText)
    MK.text!(sc, MK.Point2f(t.x, H - t.baseline); text = t.text, font = t.font,
             fontsize = t.fontsize, align = (:left, :baseline), color = :black)
end

"""
    render_scene(c::ComposedCover) -> Scene

Build the CairoMakie `Scene` for a composed cover. Pixel coords, white background.
"""
function render_scene(c::ComposedCover)
    W, H = c.page_size
    sc = MK.Scene(size = (W, H), backgroundcolor = :white)
    MK.campixel!(sc)
    # SVG inset (vector)
    for r in c.inset_rings
        pts = [MK.Point2f(p[1], H - p[2]) for p in r.points]
        if r.fill !== nothing && r.closed
            MK.poly!(sc, pts; color = (_rgb(r.fill), r.fill_opacity),
                     strokecolor = r.stroke === nothing ? :transparent : _rgb(r.stroke),
                     strokewidth = r.stroke === nothing ? 0.0 : r.stroke_width)
        elseif r.stroke !== nothing
            seg = r.closed ? vcat(pts, pts[1:1]) : pts
            MK.lines!(sc, seg; color = _rgb(r.stroke), linewidth = r.stroke_width)
        end
    end
    # editorial hairlines (masthead separator + pull-quote brackets)
    for (x1, y1, x2, y2) in c.rules
        MK.lines!(sc, [MK.Point2f(x1, H - y1), MK.Point2f(x2, H - y2)];
                  color = :black, linewidth = 0.8)
    end
    # masthead + body + drop cap + pull quotes
    for t in c.masthead; _draw_text!(sc, H, t); end
    c.dropcap !== nothing && _draw_text!(sc, H, c.dropcap)
    for t in c.body_runs; _draw_text!(sc, H, t); end
    for pq in c.pull_quotes, t in pq.runs; _draw_text!(sc, H, t); end
    return sc
end

"""
    render_cover(cfg_path; out=nothing, png=false) -> String

Compose + render + save. Writes a PDF (vector) next to `cfg_path` unless `out` is
given; if `png`, also writes a sibling `.png` for the human-visual gate. Returns the
PDF path.
"""
function render_cover(cfg_path::AbstractString; out=nothing, png::Bool=false)
    cfg = load_config(cfg_path)
    c = compose_cover(cfg)
    sc = render_scene(c)
    pdf = out === nothing ? replace(cfg_path, r"\.toml$" => ".pdf") : out
    MK.save(pdf, sc; pt_per_unit = 1.0)
    if png
        MK.save(replace(pdf, r"\.pdf$" => ".png"), sc; px_per_unit = 2.0)
    end
    return pdf
end
