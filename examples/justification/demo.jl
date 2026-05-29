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
    return total_h
end

# Configure one fixed-size, decoration-free axis sized 1:1 to its content (no letterboxing).
function _column_axis(cell, prep, lay, w, title, titlecolor)
    total_h = _baseline(prep, length(lay.lines)) + prep.metrics.descent
    xlo, xhi = -8.0, w + 14.0
    ylo, yhi = -(total_h + 0.6 * FONTSIZE), 0.9 * FONTSIZE   # y-up: line 1 near the top
    ax = Axis(cell; title=title, titlefont=LABEL_FONT, titlesize=11 * SCALE, titlegap=6,
              titlecolor=titlecolor, backgroundcolor=:white, halign=:left, valign=:top,
              width=xhi - xlo, height=yhi - ylo)
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
    green = RGBf(0.13, 0.40, 0.20)

    # Balanced composition (avoids the wide-ribbon aspect of three columns in a row): the
    # generous-measure baseline (A) spans the top full width; the two TIGHT-measure columns
    # — greedy (B) vs Knuth–Plass (C) — sit side by side beneath it, so the key comparison
    # stays side-by-side at equal height. Each axis box is fixed 1:1 to its content (no
    # DataAspect letterboxing); resize_to_layout! trims the figure to the content.
    fig = Figure(backgroundcolor=:white, figure_padding=(10, 10, 8, 8))
    Label(fig[1, 1:2], "Greedy line-breaking pools rivers; Knuth–Plass minimizes them";
          font=LABEL_FONT, fontsize=15 * SCALE, halign=:left, padding=(0, 0, 2, 4))

    axA = _column_axis(fig[2, 1:2], prep, A, WIDE_PX, _badge("Greedy", "generous measure", A, nA), :black)
    _draw_column!(axA, prep, A; show_rivers=false)

    axB = _column_axis(fig[3, 1], prep, B, NARROW_PX, _badge("Greedy", "tight measure", B, nB), :black)
    _draw_column!(axB, prep, B; show_rivers=true)

    axC = _column_axis(fig[3, 2], prep, C, NARROW_PX, _badge("Knuth–Plass", "tight measure", C, nC), green)
    _draw_column!(axC, prep, C; show_rivers=true)

    Label(fig[4, 1:2],
          "Same paragraph, set three ways. A river (red) is a run of inter-word gaps " *
          "aligned across ≥3 lines. At a tight\nmeasure greedy pools them; Knuth–Plass " *
          "minimizes total badness and breaks them up — at roughly half the badness.";
          font=LABEL_FONT, fontsize=9 * SCALE, color=(:black, 0.6), halign=:left,
          justification=:left, padding=(0, 0, 10, 0))

    rowgap!(fig.layout, 8)
    colgap!(fig.layout, 16)
    resize_to_layout!(fig)
    save(outpath, fig)
    return abspath(outpath)
end

if abspath(PROGRAM_FILE) == @__FILE__
    p = render_comparison()
    println("wrote comparison PDF: ", p)
end
