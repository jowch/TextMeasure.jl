# SPDX-License-Identifier: MIT
# render.jl — the Makie renderer for The Tide. Draws ANY `frame_layout` result (the hero, every
# loop frame, the samples, the thumbnail) — this is the pure RENDER layer; all layout lives in
# frame.jl. Rendering conventions worth noting for a reader:
#   • `markerspace = :data` so glyphs scale in data coordinates (1 data unit = 1 px here);
#   • a y-up axis with every block-top y NEGATED (`_Y`), which keeps glyphs upright while the
#     text reads top→bottom (a reversed axis would vertically mirror the glyphs instead).

# LOCAL sunset / shore palette (stays local to The Tide).
_hex(s) = Makie.to_color(s)
const FIELD = _hex("#F2DFC6")   # warm dusk peach — field / background
const INK   = _hex("#34232C")   # deep plum-brown — body text
const CORAL = _hex("#E37C4B")   # sunset coral — tide-line + the lit "kneads" word
const GRAY  = _hex("#4A3A42")   # warm plum-gray — caption text (softer than INK)

const CASLON        = joinpath(FONTS_DIR, "LibreCaslonText", "LibreCaslonText-Regular.ttf")
const CASLON_ITALIC = joinpath(FONTS_DIR, "LibreCaslonText", "LibreCaslonText-Italic.ttf")

# Draw a MIXED-FONT caption line: a sequence of (text, font, size, color) runs placed
# flush-adjacent on ONE shared baseline `y`. Each run's x-advance is measured with ITS OWN
# font + size (one-shot MakieBackend per run) so the spacing around the middot and into a
# differently-faced run reads even — no baseline drift (every run align=(:left,:baseline)).
function _caption_runs(ax, x0, y, runs)
    x = Float64(x0)
    for (txt, font, size, col) in runs
        text!(ax, Point2f(x, y); text = txt, color = col, font = font,
              fontsize = size, align = (:left, :baseline), markerspace = :data)
        mb = MakieBackend(; font = font, fontsize = Float64(size), px_per_unit = 1)
        x += TextMeasure.measure(mb, txt)
    end
end

# page size = content bbox (Wpx × Hpx) + balanced margins. The bottom margin (CAP_ROOM) holds the
# caption plus the descent of the deepest bitten line. Shared by every renderer so the composition
# (and the negated-y axis) is consistent across hero / loop / samples / thumb.
const CAP_ROOM = 68.0
_page_size(fl) = (fl.region_x + fl.Wpx + fl.margin, fl.region_y + fl.Hpx + CAP_ROOM)

# Build the standard Tide figure + axis (warm field, hidden decorations, y-up negated axis).
function _new_axis(pageW, pageH)
    fig = Figure(; size = (round(Int, pageW), round(Int, pageH)), backgroundcolor = FIELD)
    ax  = Axis(fig[1, 1]; backgroundcolor = FIELD, aspect = DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    Makie.xlims!(ax, 0, pageW); Makie.ylims!(ax, -pageH, 0)
    return fig, ax
end

# negate a block-top y to the y-up page axis (keeps glyphs upright).
_Y(yd) = -Float64(yd)

"""
    draw_body!(ax, fl, body_font, fontsize; ink=INK, lit=CORAL)

Draw every word of a `frame_layout` result `fl` at its justified position. The
"kneads—smoothing" token is split AT the em-dash: the "kneads" run renders `lit`, the
"—smoothing" run renders `ink` flush-adjacent (measured run width = the gap), so the em-dash
stays tight. `ink`/`lit` are overridable so the thumbnail can draw ghost trails in GRAY.
"""
function draw_body!(ax, fl, body_font, fontsize; ink = INK, lit = CORAL)
    segs    = fl.segs
    backend = fl.backend
    draw_run(x, ybase, txt, col) =
        text!(ax, Point2f(x, ybase); text = txt, color = col, font = body_font,
              fontsize = fontsize, align = (:left, :baseline), markerspace = :data)
    for p in fl.placements
        s  = segs[p.segment_index].str
        x0 = fl.region_x + fl.justx[p]
        yb = _Y(fl.region_y + p.y)
        di = findfirst('—', s)
        if di !== nothing && startswith(_norm(s), "kneads")
            head = s[1:prevind(s, di)]               # "kneads"
            tail = s[di:end]                          # "—smoothing"
            draw_run(x0, yb, head, lit)
            draw_run(x0 + TextMeasure.measure(backend, head), yb, tail, ink)
        else
            draw_run(x0, yb, s, ink)
        end
    end
    return ax
end

"""
    draw_tideline!(ax, fl; color=CORAL, linewidth=1.8, alpha=1.0)

Draw the coral waterline for `fl`'s direction from its precomputed `tideline_pts` (extended
polyline, already in negated-y page coords) using its PER-VERTEX `tideline_alpha`: opaque only
where the wall laps the type, dissolving to transparent past the block edges so its endpoints
sit out in empty space and never visibly pop. `alpha` is a global multiplier (so the thumbnail
can ghost the same faded curve). At rest (depth≈0 ⇒ empty tideline_pts) draws nothing.
"""
function draw_tideline!(ax, fl; color = CORAL, linewidth = 1.8, alpha = 1.0)
    isempty(fl.tideline_pts) && return ax
    base = Makie.to_color(color)
    cols = [Makie.RGBAf(base.r, base.g, base.b, a * alpha) for a in fl.tideline_alpha]
    lines!(ax, fl.tideline_pts; color = cols, linewidth = linewidth,
           linecap = :round, joinstyle = :round)
    return ax
end

"""
    draw_caption!(ax, fl; pageH)

Draw the single bottom-left caption line: `TextMeasure.jl · The Tide`. MIXED FONT — the wordmark
+ coral middot stay Hanken (sans); the title "The Tide" is Libre Caslon Text Italic (a small
editorial signature), bumped a hair (12 vs 11) for serif-italic optical compensation.
"""
function draw_caption!(ax, fl; pageH)
    cap_font   = hanken("Regular")
    cap_size   = 11.0
    title_size = 12.0
    cap_y = pageH - 20.0
    _caption_runs(ax, fl.region_x, _Y(cap_y), [
        ("TextMeasure.jl ", cap_font,      cap_size,   GRAY),
        ("· ",              cap_font,      cap_size,   CORAL),
        ("The Tide",        CASLON_ITALIC, title_size, GRAY),
    ])
    return ax
end

"""
    draw_frame!(ax, fl, pb; pageH, body_font=CASLON, fontsize=11.0, caption=true) -> ax

Draw ONE complete Tide frame from a `frame_layout`/`_layout_at` result `fl`: body glyphs (ink;
"kneads" coral with the tight-em-dash split), the wavy coral tide-line for THAT frame's
direction (rounded caps; rest ⇒ no line), and (optionally) the caption. `pb` is the prep bundle
(unused directly here, accepted so callers can pass it uniformly / future hooks). The page is
the shared `_page_size(fl)` composition; pass its height as `pageH`.
"""
function draw_frame!(ax, fl, pb; pageH, body_font = CASLON, fontsize = 11.0, caption = true)
    draw_body!(ax, fl, body_font, fontsize)
    draw_tideline!(ax, fl)
    caption && draw_caption!(ax, fl; pageH = pageH)
    return ax
end

# One-frame still: new figure, draw_frame!, save. Returns (path, pageW, pageH, fig).
function _render_still(fl, pb, path; scale, caption = true)
    pageW, pageH = _page_size(fl)
    fig, ax = _new_axis(pageW, pageH)
    draw_frame!(ax, fl, pb; pageH = pageH, caption = caption)
    save(path, fig; px_per_unit = scale)
    return (; path, pageW, pageH, fig)
end

"""
    render_hero(path="examples/tide/tide-hero.png"; scale=8) -> NamedTuple

Render the hero still and return frame diagnostics. The hero is a TRUE FRAME of the loop —
`frame_layout(pb, peak_frame(:SW))`, the deep SW knead at its scheduled phase — drawn at the same
constant box as every other frame, so the still matches what the MP4 shows.

GALLERY RENDER-SCALE CONVENTION: stills (hero + thumbnail) use `scale = 8` (~3500px wide); the
MP4 loop uses `scale = 4` at 60fps / CRF 18. `scale` stays a parameter per artifact.
"""
function render_hero(path::String = joinpath(@__DIR__, "..", "tide-hero.png"); scale::Real = 8)
    pb = _loop_bundle()
    fr = frame_layout(pb, peak_frame(:SW))        # the SW peak — the locked deep-knead beat

    out = _render_still(fr, pb, path; scale = scale)
    return (; out.path, fr.n_words, n_placements = length(fr.placements),
            n_bands = length(fr.band_order), fr.all_placed, fr.n_justified, fr.n_ragged,
            lit_count = length(fr.lit_idx), fr.b, fr.Wpx, fr.Hpx, out.pageW, out.pageH)
end
