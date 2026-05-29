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

const BODY_FONT  = "Liberation Serif"   # pinned body face
const LABEL_FONT = "DejaVu Sans"        # pinned label face

# SCALE multiplies BOTH the font size and the measures together. Badness is dimensionless
# (the adjustment ratio r is slack/stretch), and river detection scales with it, so the
# computed comparison — line breaks, badges, river counts — is identical at every SCALE;
# only the rendered size changes. We render larger than the base measure for a legible,
# print-quality figure.
const SCALE     = 1.7
const FONTSIZE  = 11.0 * SCALE
const WIDE_PX   = 520.0 * SCALE
const NARROW_PX = 260.0 * SCALE
const LEAD      = 1.5            # render leading (visual breathing room; not a layout input)
const RIVER_COL = RGBf(0.86, 0.21, 0.18)   # warm red for river channels

# Block-top-frame baseline of line i with display leading (y increasing DOWN: line 1 small,
# line N large). We render in Makie's native y-UP axis, so every y is NEGATED at draw time
# (`-b`) — that puts line 1 (smallest baseline) at the visual TOP and the prose reads
# top→bottom. (Using yreversed instead double-flipped the content; see git history.)
_baseline(prep, i) = prep.metrics.ascent + (i - 1) * prep.metrics.line_advance * LEAD

# Draw one justified column into `ax` (data units = px; block-top frame via yreversed).
# Returns the rendered block height.
function _draw_column!(ax, prep, lay::JustifiedLayout, colwidth; show_rivers::Bool)
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
                  color=(RIVER_COL, 0.30))
            lines!(ax, [xbar, xbar], [-yb_top, -yb_bot]; color=(RIVER_COL, 0.9),
                   linewidth=2.4 * SCALE)
        end
    end

    # Words (y negated ⇒ line 1 at the top, reading top→bottom).
    xs = Float64[]; ys = Float64[]; strs = String[]
    for (i, l) in enumerate(lay.lines), (j, wi) in enumerate(l.words)
        push!(xs, l.word_x[j]); push!(ys, -_baseline(prep, i))
        push!(strs, prep.segments[wi].str)
    end
    text!(ax, xs, ys; text=strs, align=(:left, :baseline), font=BODY_FONT,
          fontsize=FONTSIZE, markerspace=:data, color=:black)

    # Faint measure rule at the right edge of the column.
    lines!(ax, [colwidth, colwidth], [0.3 * FONTSIZE, -total_h];
           color=(:gray, 0.35), linewidth=1, linestyle=:dash)
    return total_h
end

function render_comparison(outpath::AbstractString=joinpath(@__DIR__, "comparison.pdf"))
    backend = MakieBackend(; font=BODY_FONT, fontsize=FONTSIZE, px_per_unit=1.0)
    prep = prepare(backend, CANONICAL_PARAGRAPH)
    space_w = prep.segments[2].width

    cols = [
        ("Greedy",       "generous measure", greedy_justify(prep; max_width=WIDE_PX),   WIDE_PX,   false),
        ("Greedy",       "tight measure",    greedy_justify(prep; max_width=NARROW_PX), NARROW_PX, true),
        ("Knuth–Plass",  "tight measure",    knuth_plass(prep; max_width=NARROW_PX),    NARROW_PX, true),
    ]

    # Each column's axis box is fixed to its OWN content size (1 data unit = 1 px), so text
    # fills the panel with no DataAspect letterboxing. Top-aligned so the three panels read
    # as a deliberate comparison strip; resize_to_layout! trims the figure to the content.
    fig = Figure(backgroundcolor=:white)
    Label(fig[0, 1:3], "Greedy line-breaking pools rivers; Knuth–Plass minimizes them";
          font=LABEL_FONT, fontsize=14 * SCALE, halign=:center, padding=(0, 0, 2, 6))

    for (c, (alg, measure, lay, w, show_rivers)) in enumerate(cols)
        nr = length(find_rivers(lay; align_tol=space_w))
        title = "$(alg) · $(measure)\nbadness $(round(lay.total_badness; digits=1)) · " *
                "$(nr) river" * (nr == 1 ? "" : "s")
        total_h = _baseline(prep, length(lay.lines)) + prep.metrics.descent
        xlo, xhi = -8.0, w + 14.0
        # y-up axis: top = +0.9·FONTSIZE (just above line-1 baseline), bottom = -(total_h+pad).
        ylo, yhi = -(total_h + 0.7 * FONTSIZE), 0.9 * FONTSIZE
        ax = Axis(fig[1, c]; title=title, titlefont=LABEL_FONT, titlesize=11 * SCALE,
                  titlegap=6, titlecolor=(c == 3 ? RGBf(0.13, 0.40, 0.20) : :black),
                  backgroundcolor=:white, valign=:top,
                  width=xhi - xlo, height=yhi - ylo)
        hidedecorations!(ax); hidespines!(ax)
        _draw_column!(ax, prep, lay, w; show_rivers=show_rivers)
        limits!(ax, xlo, xhi, ylo, yhi)   # 1:1 with the fixed box ⇒ no letterboxing
    end

    Label(fig[2, 1:3],
          "Same paragraph, set three ways. A river (red) is a run of inter-word gaps " *
          "aligned across ≥3 lines.\nAt a tight measure greedy pools them; Knuth–Plass " *
          "minimizes total badness and breaks them up — at roughly half the badness.";
          font=LABEL_FONT, fontsize=9 * SCALE, color=(:black, 0.65), halign=:center,
          justification=:center, padding=(0, 0, 12, 2))

    rowgap!(fig.layout, 6)
    resize_to_layout!(fig)
    save(outpath, fig)
    return abspath(outpath)
end

if abspath(PROGRAM_FILE) == @__FILE__
    p = render_comparison()
    println("wrote comparison PDF: ", p)
end
