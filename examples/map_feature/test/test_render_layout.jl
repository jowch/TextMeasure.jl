# SPDX-License-Identifier: MIT
# Render-level non-overlap invariants (fix #3), asserted on the REAL Vermont layout via the
# factored-out MapFeature._compose_layout — no drawing needed. Each of the four non-overlaps the
# design guarantees by construction is a test here.
using Test, MapFeature
using GeometryBasics: Point2

# Polygon horizontal envelope over y ∈ [y0,y1], computed DIRECTLY from the polygon (independent of
# complement_chord_fn / the render combinator), sampled densely. Checking a word against the
# envelope over its FULL vertical extent — not just its baseline scanline — is the FAITHFUL test:
# it matches the geometry the render actually draws (the silhouette spans the word's glyph height),
# so it catches a slanted/concave edge poking into the prose that a center-only check would miss.
function envelope_over(poly, y0, y1)
    lo = Inf; hi = -Inf; n = length(poly)
    # exact: extremes are at boundary-crossings of y0/y1 or at vertices strictly inside (y0,y1)
    for ys in (y0, y1), i in 1:n
        x1, y1e = poly[i][1], poly[i][2]
        j = i == n ? 1 : i + 1
        x2, y2e = poly[j][1], poly[j][2]
        if (y1e <= ys) != (y2e <= ys)
            x = x1 + (ys - y1e) / (y2e - y1e) * (x2 - x1)
            lo = min(lo, x); hi = max(hi, x)
        end
    end
    for i in 1:n
        if y0 < poly[i][2] < y1
            xi = poly[i][1]; lo = min(lo, xi); hi = max(hi, xi)
        end
    end
    return isfinite(lo) ? (lo, hi) : nothing
end

@testset "render layout (Vermont): the four non-overlaps hold by construction" begin
    L = MapFeature._compose_layout(load_vermont())
    pk, prep, poly = L.pk, L.prep, L.poly_px
    la = prep.metrics.line_advance
    asc = prep.metrics.ascent
    @test !isempty(pk.placements)
    # overflow_strategy=:skip RECORDS an over-wide word (one too wide for a narrow band's run) but
    # does NOT place it — so it can never sit atop the map. Assert that safety invariant (skipped
    # words have no placement) rather than zero overflow; a long word may be dropped in a tight band.
    placed_idx = Set(p.segment_index for p in pk.placements)
    @test all(si -> !(si in placed_idx), pk.overflowed)

    desc = prep.metrics.descent
    n_letterbox = 0; n_silhouette = 0
    for p in pk.placements
        w  = prep.segments[p.segment_index].width
        x0, x1 = p.x, p.x + w
        wtop, wbot = p.y - asc, p.y + desc             # word bbox full vertical extent

        # (a) body never overlaps the masthead/sidebar top band
        @test wtop >= MapFeature.SIDEBAR_BOTTOM - 1e-6

        # body must stay within the page's inner horizontal margins
        @test x0 >= MapFeature.MARGIN - 1e-6
        @test x1 <= MapFeature.PAGE_W - MapFeature.MARGIN + 1e-6

        # FAITHFUL envelope over the word's full glyph height (matches the rendered geometry)
        env = envelope_over(poly, wtop, wbot)
        if env === nothing
            # (b) letterbox (silhouette absent over the word's rows): body must not enter map column
            n_letterbox += 1
            @test x1 <= L.map_left + 1e-6 || x0 >= L.map_right - 1e-6
        else
            # (c) word must not overlap the silhouette's envelope across its full height
            n_silhouette += 1
            el, er = env
            @test x1 <= el + 1e-6 || x0 >= er - 1e-6
        end
    end
    # Vermont is tall and fills most of the map region, so the prose genuinely wraps the
    # silhouette in many bands (not just a degenerate left rectangle).
    @test n_silhouette > 0
end
