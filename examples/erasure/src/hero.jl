using Makie, CairoMakie
using Makie: Point2f, Rect2f
using HouseStyle: PAPER, INK, BRASS, RAMP, fraunces, plexmono, footer
using TextMeasure: prepare, layout, MakieBackend

# 8% brass underlay fill
_brass_underlay() = Makie.RGBA(Makie.RGB(BRASS), 0.08)

"""
    hero(path) -> (; survivors, png)

Render the curated MIT-License found poem: INK censor bars over blacked words, Fraunces
survivors (subhead 16) on BRASS underlays at their EXACT measured coordinates, a BRASS
reading thread through survivors in reading order. Writes `path` (PNG via `save_png`).
"""
function hero(path)
    # MakieBackend is KEYWORD-ONLY (verified against ext/TextMeasureMakieExt.jl): pass the
    # font PATH via `font=`, never positionally (positional ctor wants a resolved FTFont).
    body = MakieBackend(; font = plexmono("Regular"), fontsize = RAMP.body, px_per_unit = 1)
    prep  = prepare(body, LICENSE_TEXT)
    boxes = word_boxes(prep; max_width = HERO_MAX_WIDTH)
    kept_idx = kept_seg_indices(prep)
    keptset  = Set(kept_idx)
    rects = redaction_rects(boxes, prep, kept_idx; bleed = 1.0)

    # survivor anchors in reading order (kept_seg_indices is already ordered)
    bybox = Dict(wb.seg_index => wb for wb in boxes)
    survivors = [(line = bybox[i].line, x0 = bybox[i].x0, x1 = bybox[i].x1,
                  baseline = bybox[i].baseline, str = prep.segments[i].str)
                 for i in kept_idx]

    pad = 2.0
    save_png(path; size = (1200, 1600), px_per_unit = 1) do ax
        # 1. INK censor bars
        for r in rects
            poly!(ax, Rect2f(r.x0, r.y0, r.x1 - r.x0, r.y1 - r.y0); color = INK)
        end
        # 2. BRASS underlay + Fraunces survivor glyphs
        m = prep.metrics
        for s in survivors
            top = s.baseline - m.ascent
            poly!(ax, Rect2f(s.x0 - pad, top - pad,
                             (s.x1 - s.x0) + 2pad, (m.ascent + m.descent) + 2pad);
                  color = _brass_underlay(), strokecolor = BRASS, strokewidth = 0.75)
            text!(ax, Point2f(s.x0, s.baseline); text = s.str, color = INK,
                  font = fraunces("9pt-SemiBold"), fontsize = RAMP.subhead,
                  align = (:left, :baseline))
        end
        # 3. BRASS reading thread (trailing edge -> leading edge, reading order)
        thread = Point2f[]
        for s in survivors
            push!(thread, Point2f(s.x0, s.baseline))
            push!(thread, Point2f(s.x1, s.baseline))
        end
        lines!(ax, thread; color = BRASS, linewidth = 1.0)
        # 4. footer
        last_base = maximum(s.baseline for s in survivors)
        text!(ax, Point2f(0, last_base + 3 * m.line_advance); text = footer("Erasure"),
              color = BRASS, font = plexmono("Regular"), fontsize = RAMP.caption,
              align = (:left, :baseline))
    end
    return (; survivors = survivors, png = path)
end
