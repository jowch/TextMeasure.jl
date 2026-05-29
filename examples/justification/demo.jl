# SPDX-License-Identifier: MIT
#
# Knuth–Plass justification comparison exhibit (#K) — the renderable demo.
# Port of pretext.js's `justification-comparison` page. Produces a single PDF with three
# columns of the SAME paragraph:
#   1. greedy `layout`-style breaks at a generous measure  (comfortable baseline)
#   2. greedy breaks at a tight measure (~0.5× col 1)       (where greedy pools rivers)
#   3. Knuth–Plass breaks at the SAME tight measure         (badness-minimization's win)
# River channels (inter-word gaps that line up across ≥3 consecutive lines) are overlaid
# so the eye reads, at a glance, what greedy pools and Knuth–Plass breaks up.
#
# Hyphenation is out of TextMeasure's scope (CLAUDE.md), so — per the #K issue — the
# original demo's "hyphenation-off" column is replaced by narrow-greedy vs narrow-K-P,
# which preserves the point (showing where badness-minimization helps) without inventing
# hyphenation we don't have.
#
# Run:  julia --project=examples/justification examples/justification/demo.jl
# Geometry is measured with TextMeasure's MakieBackend in the SAME pinned font CairoMakie
# renders with, so placement is pixel-faithful. px_per_unit = 1 per CLAUDE.md.

using CairoMakie
using TextMeasure
using TextMeasureLayouts: JustifiedLayout, greedy_justify, knuth_plass
using Justification: find_rivers, CANONICAL_PARAGRAPH

# ---- House style (docs/superpowers/demos-house-style.md) ------------------------------
const BODY_FONT  = "Liberation Serif"   # pinned serif (body / title)
const LABEL_FONT = "DejaVu Sans"        # pinned sans  (subheads / caption / footer)

# Type ramp (pt): body 11, subhead 14, caption 9, display 44 (masthead only). #K is the one
# demo that stays JUSTIFIED (its justified columns are the demo). Body = 11 pt exactly, so
# we render at the base measure (no scaling). Badness is dimensionless and river detection
# scales with geometry, so the computed comparison/badges are identical at any size anyway.
const BODY_PT    = 11.0
const SUBHEAD_PT = 14.0
const CAPTION_PT = 9.0
const DISPLAY_PT = 44.0
const FONTSIZE   = BODY_PT
const WIDE_PX    = 520.0
const NARROW_PX  = 260.0
const LEAD       = 1.25          # render leading (display only; not a layout input)
const MARGIN_PX  = 36.0          # outer margin on all four sides

# Palette — locked (3 accents + 1 gray); background white, body near-black.
const RED   = RGBf(0.753, 0.224, 0.169)   # #C0392B — river overlays
const GREEN = RGBf(0.106, 0.478, 0.239)   # #1B7A3D — K–P "winner" label
const GRAY  = RGBf(0.420, 0.447, 0.502)   # #6B7280 — caption / footer / hairlines
const INK   = RGBf(0.10,  0.10,  0.10)    # #1A1A1A — body text

# Block-top-frame baseline of line i with display leading (y increasing DOWN: line 1 small,
# line N large). We render in Makie's native y-UP axis, so every y is NEGATED at draw time
# (`-b`) — that puts line 1 (smallest baseline) at the visual TOP and the prose reads
# top→bottom. (Using yreversed instead double-flipped the content; see git history.)
_baseline(prep, i) = prep.metrics.ascent + (i - 1) * prep.metrics.line_advance * LEAD

# Draw one justified column into `ax` (data units = px; y negated for Makie's y-up axis).
# Returns the rendered block height.
function _draw_column!(ax, prep, lay::JustifiedLayout; show_rivers::Bool)
    space_w = prep.segments[2].width
    nlines = length(lay.lines)
    total_h = nlines == 0 ? FONTSIZE : _baseline(prep, nlines) + prep.metrics.descent

    # River channels first (under the text): a vertical translucent band spanning the
    # river's lines, plus a crisp center line — so the contrast reads at a glance (the
    # narrow-greedy column pools several channels; K-P leaves the column far calmer).
    if show_rivers
        for r in find_rivers(lay; align_tol=space_w)
            xs = [x for (_, x) in r.points]
            lns = [ln for (ln, _) in r.points]
            xbar = sum(xs) / length(xs)
            # block-top y of the channel's top/bottom, then negate for the y-up axis.
            yb_top = _baseline(prep, minimum(lns)) - prep.metrics.ascent
            yb_bot = _baseline(prep, maximum(lns)) + prep.metrics.descent
            bandw = 0.85 * FONTSIZE          # em-based so the channel reads boldly
            poly!(ax, Rect2f(xbar - bandw / 2, -yb_bot, bandw, yb_bot - yb_top);
                  color=(RED, 0.28))
            lines!(ax, [xbar, xbar], [-yb_top, -yb_bot]; color=(RED, 0.9), linewidth=2.2)
        end
    end

    # Words (y negated ⇒ line 1 at the top, reading top→bottom). Justified — #K's exception.
    xs = Float64[]; ys = Float64[]; strs = String[]
    for (i, l) in enumerate(lay.lines), (j, wi) in enumerate(l.words)
        push!(xs, l.word_x[j]); push!(ys, -_baseline(prep, i))
        push!(strs, prep.segments[wi].str)
    end
    text!(ax, xs, ys; text=strs, align=(:left, :baseline), font=BODY_FONT,
          fontsize=FONTSIZE, markerspace=:data, color=INK)
    return total_h
end

# Configure one fixed-size, decoration-free axis sized 1:1 to its content (no letterboxing).
function _column_axis(cell, prep, lay, w, title, titlecolor)
    total_h = _baseline(prep, length(lay.lines)) + prep.metrics.descent
    xlo, xhi = -6.0, w + 10.0
    ylo, yhi = -(total_h + 0.6 * FONTSIZE), 0.9 * FONTSIZE   # y-up: line 1 near the top
    ax = Axis(cell; title=title, titlefont=LABEL_FONT, titlesize=SUBHEAD_PT, titlegap=6,
              titlealign=:left, titlecolor=titlecolor, backgroundcolor=:white,
              halign=:left, valign=:top, width=xhi - xlo, height=yhi - ylo)
    hidedecorations!(ax); hidespines!(ax)
    limits!(ax, xlo, xhi, ylo, yhi)
    return ax
end

_badge(alg, measure, lay, nr) =
    "$(alg) · $(measure)\nbadness $(round(lay.total_badness; digits=1)) · " *
    "$(nr) river" * (nr == 1 ? "" : "s")

function render_comparison(outpath::AbstractString=joinpath(@__DIR__, "comparison.pdf"))
    backend = MakieBackend(; font=BODY_FONT, fontsize=FONTSIZE, px_per_unit=1.0)
    prep = prepare(backend, CANONICAL_PARAGRAPH)
    space_w = prep.segments[2].width

    A = greedy_justify(prep; max_width=WIDE_PX)     # generous measure — baseline (0 rivers)
    B = greedy_justify(prep; max_width=NARROW_PX)    # tight measure, greedy — pools rivers
    C = knuth_plass(prep;    max_width=NARROW_PX)    # tight measure, K-P — minimizes them
    nA = length(find_rivers(A; align_tol=space_w))
    nB = length(find_rivers(B; align_tol=space_w))
    nC = length(find_rivers(C; align_tol=space_w))
    # Balanced composition (avoids the wide-ribbon aspect of three columns in a row): the
    # generous-measure baseline (A) spans the top full width; the two TIGHT-measure columns
    # — greedy (B) vs Knuth–Plass (C) — sit side by side beneath it (cols 1 & 3, with a
    # hairline gutter in col 2), so the key comparison stays side-by-side at equal height.
    # Each axis box is fixed 1:1 to its content (no DataAspect letterboxing); house-style
    # type ramp / palette / 36 px margin / bottom-left footer; resize_to_layout! trims it.
    fig = Figure(backgroundcolor=:white,
                 figure_padding=(MARGIN_PX, MARGIN_PX, MARGIN_PX, MARGIN_PX))

    Label(fig[1, 1:3], "Greedy vs. Knuth–Plass"; font=BODY_FONT, fontsize=DISPLAY_PT,
          color=INK, halign=:left, padding=(0, 0, 4, 0))

    axA = _column_axis(fig[2, 1:3], prep, A, WIDE_PX, _badge("Greedy", "generous measure", A, nA), INK)
    _draw_column!(axA, prep, A; show_rivers=false)

    axB = _column_axis(fig[3, 1], prep, B, NARROW_PX, _badge("Greedy", "tight measure", B, nB), INK)
    _draw_column!(axB, prep, B; show_rivers=true)

    Box(fig[3, 2]; color=(GRAY, 0.15), strokevisible=false)   # 0.5 px-class hairline gutter
    colsize!(fig.layout, 2, Fixed(1.0))

    axC = _column_axis(fig[3, 3], prep, C, NARROW_PX, _badge("Knuth–Plass", "tight measure", C, nC), GREEN)
    _draw_column!(axC, prep, C; show_rivers=true)

    Label(fig[4, 1:3],
          "Same paragraph, set three ways. A river (red) is a run of inter-word gaps " *
          "aligned across ≥3 lines. At a tight\nmeasure greedy pools them; Knuth–Plass " *
          "minimizes total badness and breaks them up — at roughly half the badness.";
          font=LABEL_FONT, fontsize=CAPTION_PT, color=GRAY, halign=:left,
          justification=:left, lineheight=1.3, padding=(0, 0, 14, 2))

    Label(fig[5, 1:3], "TextMeasure.jl · Knuth–Plass"; font=LABEL_FONT, fontsize=CAPTION_PT,
          color=GRAY, halign=:left, padding=(0, 0, 0, 0))

    rowgap!(fig.layout, 8)
    colgap!(fig.layout, 14)
    resize_to_layout!(fig)
    save(outpath, fig)
    return abspath(outpath)
end

if abspath(PROGRAM_FILE) == @__FILE__
    p = render_comparison()
    println("wrote comparison PDF: ", p)
end
