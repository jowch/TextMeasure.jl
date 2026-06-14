using Makie, CairoMakie
using Makie: Point2f, Rect2f
using HouseStyle: PAPER, INK, BRASS, RAMP, fraunces, plexmono, footer
import TextMeasure
using TextMeasure: prepare, layout, MakieBackend
using Random: Xoshiro

# ---- marker palette --------------------------------------------------------
# Translucent ink so adjacent/overlapping marker passes read as a felt-tip stroke; a
# faint, slightly-larger bleed pass behind softens the edges.
_marker_ink()   = Makie.RGBA(Makie.RGB(INK), 0.92)
_marker_bleed() = Makie.RGBA(Makie.RGB(INK), 0.20)
# faint brass tint that anchors each survivor in its hole (sized to the Fraunces extent)
_brass_tint()   = Makie.RGBA(Makie.RGB(BRASS), 0.10)

# Deterministic hand-drawn wobble: a Xoshiro seeded from the bar's integer x so the same
# bar always wobbles the same way (render-only; never touches the golden geometry table).
_wobble_seed(x0, y0) = Xoshiro(round(UInt64, abs(x0) * 131 + abs(y0) * 17) + 0x9e37)

"""
    _marker_polygon(x0, x1, ytop, ybot; samples, jitter, cap) -> Vector{Point2f}

A closed marker-bar outline: a wobbled top edge L→R, a rounded right cap, a wobbled
bottom edge R→L, a rounded left cap. `jitter` px of deterministic vertical noise on the
long edges; `cap` px semicircle radius at each end.
"""
function _marker_polygon(x0, x1, ytop, ybot; samples = 14, jitter = 1.6, cap = nothing)
    rng = _wobble_seed(x0, ytop)
    r   = cap === nothing ? (ybot - ytop) / 2 : cap
    xl, xr = x0 + r, x1 - r            # straight span between the round caps
    pts = Point2f[]
    n = max(2, samples)
    # top edge, left round-corner -> right round-corner
    for k in 0:n
        t = k / n
        x = xl + t * (xr - xl)
        y = ytop + (rand(rng) - 0.5) * 2 * jitter
        push!(pts, Point2f(x, y))
    end
    # right cap (semicircle, top -> bottom), centered at (xr, mid)
    midy = (ytop + ybot) / 2
    for a in range(-pi/2, pi/2; length = 8)
        push!(pts, Point2f(xr + r * cos(a), midy + r * sin(a)))
    end
    # bottom edge, right -> left
    for k in 0:n
        t = k / n
        x = xr - t * (xr - xl)
        y = ybot + (rand(rng) - 0.5) * 2 * jitter
        push!(pts, Point2f(x, y))
    end
    # left cap (semicircle, bottom -> top), centered at (xl, mid)
    for a in range(pi/2, 3pi/2; length = 8)
        push!(pts, Point2f(xl + r * cos(a), midy + r * sin(a)))
    end
    return pts
end

"""
    hero(path) -> (; survivors, png, size)

Render the curated MIT-License found poem as a page-filling redacted document: hand-drawn
marker censor bars (translucent INK, rounded ends, deterministic wobble, line-pitch-tall
so rows stack into a dense block) over blacked words; Fraunces survivors at title-22 in
the paper holes, each on a brass tint sized to its TRUE Fraunces width and underscored by
a short per-word brass underline (no connectors). Canvas is cropped to content. Writes
`path` via `save_png`.
"""
function hero(path)
    # MakieBackend is KEYWORD-ONLY (verified against ext/TextMeasureMakieExt.jl): pass the
    # font PATH via `font=`, never positionally. Redaction is measured in Plex Mono at the
    # subhead scale (coupled with golden_backend / HERO_MAX_WIDTH).
    body = MakieBackend(; font = plexmono("Regular"), fontsize = RAMP.subhead, px_per_unit = 1)
    prep  = prepare(body, LICENSE_TEXT)
    boxes = word_boxes(prep; max_width = HERO_MAX_WIDTH)
    kept_idx = kept_seg_indices(prep)
    rects = redaction_rects(boxes, prep, kept_idx; bleed = 1.0)
    m = prep.metrics

    # Survivors render in Fraunces title; measure each in THAT face so the brass underline
    # and tint match the rendered glyphs (review bug #4 — not the redaction-box width).
    fbk = MakieBackend(; font = fraunces("9pt-SemiBold"), fontsize = RAMP.title, px_per_unit = 1)
    bybox = Dict(wb.seg_index => wb for wb in boxes)
    survivors = map(kept_idx) do i
        wb  = bybox[i]
        str = prep.segments[i].str
        fw  = TextMeasure.measure(fbk, str)          # TRUE rendered Fraunces width
        (line = wb.line, x0 = wb.x0, x1 = wb.x0 + fw, baseline = wb.baseline, str = str)
    end

    # Taller marker band: ~line pitch, centered on the text band, so rows nearly merge.
    band   = 0.96 * m.line_advance
    halfex = (band - (m.ascent + m.descent)) / 2     # extra above/below the text band

    # ---- content bounding box (for the crop) -------------------------------
    maxbase = maximum(s.baseline for s in survivors)
    footer_y = maxbase + 2.2 * m.line_advance
    xs1 = isempty(rects) ? 0.0 : minimum(r.x0 for r in rects)
    xs2 = isempty(rects) ? 0.0 : maximum(r.x1 for r in rects)
    xs2 = max(xs2, maximum(s.x1 for s in survivors))
    ytop = (isempty(rects) ? 0.0 : minimum(r.y0 - halfex for r in rects))
    ybot = footer_y + 0.6 * m.line_advance
    cx0  = min(0.0, xs1)

    # asymmetric editorial margins (landscape-friendly, not equal/1-inch)
    ml, mr, mt, mb = 26.0, 34.0, 30.0, 24.0
    cw = (xs2 - cx0) + ml + mr
    chh = (ybot - ytop) + mt + mb
    scale = 2.6                                       # crisp output
    fig_size = (round(Int, cw * scale), round(Int, chh * scale))

    save_png(path; size = fig_size, px_per_unit = 1) do ax
        # lock data limits to the content box + margins so nothing is cropped/letterboxed
        Makie.xlims!(ax, cx0 - ml, xs2 + mr)
        Makie.ylims!(ax, ybot + mb, ytop - mt)        # y reversed by save_png(yflip)

        # 1. MARKER censor bars: faint wide bleed pass, then the translucent ink stroke.
        for r in rects
            yt = (r.y0 + r.y1) / 2 - band / 2
            yb = (r.y0 + r.y1) / 2 + band / 2
            bleed = _marker_polygon(r.x0 - 2, r.x1 + 2, yt - 1.5, yb + 1.5;
                                    jitter = 2.2, cap = band / 2 + 1.5)
            poly!(ax, bleed; color = _marker_bleed(), strokewidth = 0)
            main = _marker_polygon(r.x0, r.x1, yt, yb; jitter = 1.6, cap = band / 2)
            poly!(ax, main; color = _marker_ink(), strokewidth = 0)
        end

        # 2. Survivors: faint brass tint (Fraunces extent) + Fraunces glyphs + underline.
        for s in survivors
            top = s.baseline - m.ascent
            poly!(ax, Rect2f(s.x0 - 3, top - 2, (s.x1 - s.x0) + 6, (m.ascent + m.descent) + 4);
                  color = _brass_tint(), strokewidth = 0)
            text!(ax, Point2f(s.x0, s.baseline); text = s.str, color = INK,
                  font = fraunces("9pt-SemiBold"), fontsize = RAMP.title,
                  align = (:left, :baseline))
            # short brass underline UNDER this survivor only (no connectors)
            uy = s.baseline + 0.22 * m.descent + 3.0
            lines!(ax, [Point2f(s.x0, uy), Point2f(s.x1, uy)];
                   color = BRASS, linewidth = 1.4, linecap = :round)
        end

        # 3. footer
        text!(ax, Point2f(cx0, footer_y); text = footer("Erasure"),
              color = BRASS, font = plexmono("Regular"), fontsize = RAMP.caption,
              align = (:left, :baseline))
    end
    return (; survivors = survivors, png = path, size = fig_size)
end
