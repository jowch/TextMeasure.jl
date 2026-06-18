# SPDX-License-Identifier: MIT
# justify.jl — the DEMO-SIDE justify pass: spread each line's words flush to both margins.
#
# This is the key "no new engine surface" technique: `shape_pack` does all the line-breaking, and
# this pass only rewrites where each word sits horizontally. Placement is immutable, so we build a
# new x for each placement keyed by object identity via an IdDict and return that lookup — the
# engine never sees it.

"""
    ends_paragraph(segs, si) -> Bool

Is segment `si` the last word of a paragraph? Its segment is the final :word of the text, or
the next NON-space segment is :newline. For single-paragraph prose only the final line of the
block is paragraph-final (so it stays ragged) — every other wrapped line justifies.
"""
function ends_paragraph(segs, si::Int)
    j = si + 1
    while j <= length(segs)
        k = segs[j].kind
        k === :word    && return false
        k === :newline && return true
        j += 1                                  # skip :space
    end
    return true                                 # ran off the end => last word
end

"""
    justify_bands(band_order, bands, band_interval, segs, wwidth, natspace)
        -> (justx, n_justified, n_ragged)

Per-band flush-fill justify. `band_order` is the sorted baseline-y list; `bands[y]` are the
band's placements in reading order; `band_interval(y, x1) -> (L,R)`; `wwidth[segment_index]`
is the cached advance width; `natspace` is the natural space advance (over-stretch guard).

Returns `justx :: IdDict{Placement,Float64}` mapping each placement to its justified x, plus
counts of justified / ragged bands. Bands are kept ragged when: single word, no R interval,
no slack, paragraph-final line, or the stretch per gap would exceed 1.6× the natural space.
"""
function justify_bands(band_order, bands, band_interval, segs, wwidth, natspace)
    justx = IdDict{Placement,Float64}()
    n_justified = 0
    n_ragged    = 0

    for y in band_order
        # `words` are this band's placements in reading order (left→right), as `shape_pack`
        # returns them — the slack spread below keys off position-in-band, so it relies on that.
        words = bands[y]
        k = length(words)
        for w in words; justx[w] = w.x; end     # default: keep natural x

        _, Rsel = band_interval(y, words[1].x)

        widths = [wwidth[w.segment_index] for w in words]
        natural_right = words[k].x + widths[k]
        slack = isnan(Rsel) ? 0.0 : (Rsel - natural_right)

        last_seg = words[k].segment_index
        is_last_para = ends_paragraph(segs, last_seg)
        over_stretch = (k >= 2) && (slack / (k - 1) > 1.6 * natspace)

        if k < 2 || isnan(Rsel) || slack <= 0 || is_last_para || over_stretch
            n_ragged += 1
        else
            for (i, w) in enumerate(words)
                justx[w] = w.x + (i - 1) * slack / (k - 1)
            end
            n_justified += 1
        end
    end
    return justx, n_justified, n_ragged
end
