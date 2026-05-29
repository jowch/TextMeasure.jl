# SPDX-License-Identifier: MIT
#
# Knuth–Plass justification comparison exhibit (#K) — the renderable demo.
# Port of pretext.js's `justification-comparison` page. Produces a single PDF with three
# columns of the SAME paragraph:
#   1. greedy `layout`-style breaks at a generous measure  (comfortable baseline)
#   2. greedy breaks at a tight measure (~0.5× col 1)       (where greedy pools rivers)
#   3. Knuth–Plass breaks at the SAME tight measure         (badness-minimization's win)
# River channels (gaps that line up across ≥3 consecutive lines) are overlaid so the eye
# can see what greedy creates and K-P breaks up.
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
const FONTSIZE   = 11.0
const WIDE_PX    = 520.0
const NARROW_PX  = 260.0

# Draw one justified column into `ax` (data units = px; block-top frame via yreversed).
function _draw_column!(ax, prep, lay::JustifiedLayout, colwidth; show_rivers::Bool)
    space_w = prep.segments[2].width
    # measure rule (right edge of the column) for context
    total_h = isempty(lay.lines) ? FONTSIZE :
              lay.lines[end].baseline + prep.metrics.descent
    # river overlays first (under the text)
    if show_rivers
        for r in find_rivers(lay; align_tol=space_w)
            xs = [x for (_, x) in r.points]
            ys = [lay.lines[ln].baseline for (ln, _) in r.points]
            lines!(ax, xs, ys; color=(:tomato, 0.45), linewidth=7)
            scatter!(ax, xs, ys; color=(:tomato, 0.65), markersize=6)
        end
    end
    # words
    xs = Float64[]; ys = Float64[]; strs = String[]
    for l in lay.lines, (j, wi) in enumerate(l.words)
        push!(xs, l.word_x[j]); push!(ys, l.baseline)
        push!(strs, prep.segments[wi].str)
    end
    text!(ax, xs, ys; text=strs, align=(:left, :baseline), font=BODY_FONT,
          fontsize=FONTSIZE, markerspace=:data, color=:black)
    # measure guide
    lines!(ax, [colwidth, colwidth], [0.0, total_h]; color=(:gray, 0.4), linewidth=1,
           linestyle=:dash)
    return total_h
end

function render_comparison(outpath::AbstractString=joinpath(@__DIR__, "comparison.pdf"))
    backend = MakieBackend(; font=BODY_FONT, fontsize=FONTSIZE, px_per_unit=1.0)
    prep = prepare(backend, CANONICAL_PARAGRAPH)

    cols = [
        ("Greedy · wide measure",  greedy_justify(prep; max_width=WIDE_PX),   WIDE_PX,   false),
        ("Greedy · narrow measure", greedy_justify(prep; max_width=NARROW_PX), NARROW_PX, true),
        ("Knuth–Plass · narrow measure", knuth_plass(prep; max_width=NARROW_PX), NARROW_PX, true),
    ]

    # Each column's axis box is fixed to its OWN content size (1 data unit = 1 px), so the
    # text fills the panel with no DataAspect letterboxing / empty bands. Columns are
    # top-aligned (valign=:top), so the wide column's shorter block and the narrow columns'
    # taller blocks read as a deliberate, tightly-framed comparison figure. resize_to_layout!
    # then shrinks the figure to the content.
    fig = Figure(backgroundcolor=:white)
    Label(fig[0, 1:3], "Justification: greedy rivers vs Knuth–Plass";
          font=LABEL_FONT, fontsize=20, padding=(0, 0, 2, 12))
    for (c, (title, lay, w, show_rivers)) in enumerate(cols)
        nr = length(find_rivers(lay; align_tol=prep.segments[2].width))
        full_title = "$(title)\nbadness $(round(lay.total_badness; digits=1)) · $(nr) river(s)"
        total_h = lay.lines[end].baseline + prep.metrics.descent
        xlo, xhi = -8.0, w + 12.0
        ylo, yhi = -0.7 * FONTSIZE, total_h + 0.6 * FONTSIZE
        ax = Axis(fig[1, c]; title=full_title, titlefont=LABEL_FONT, titlesize=14,
                  titlegap=8, backgroundcolor=(:gray90, 0.55), yreversed=true,
                  valign=:top, width=xhi - xlo, height=yhi - ylo)
        hidedecorations!(ax); hidespines!(ax)
        _draw_column!(ax, prep, lay, w; show_rivers=show_rivers)
        limits!(ax, xlo, xhi, ylo, yhi)   # 1:1 with the fixed box ⇒ no letterboxing
    end
    resize_to_layout!(fig)
    save(outpath, fig)
    return abspath(outpath)
end

if abspath(PROGRAM_FILE) == @__FILE__
    p = render_comparison()
    println("wrote comparison PDF: ", p)
end
