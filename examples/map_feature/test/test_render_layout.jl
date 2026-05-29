# SPDX-License-Identifier: MIT
# Render-level non-overlap invariants (fix #3), asserted on the REAL Vermont layout via the
# factored-out MapFeature._compose_layout — no drawing needed. Each of the four non-overlaps the
# design guarantees by construction is a test here.
using Test, MapFeature
using GeometryBasics: Point2

# Polygon horizontal envelope at scanline yc, computed DIRECTLY from the polygon (independent of
# complement_chord_fn / the render combinator).
function envelope_at(poly, yc)
    lo = Inf; hi = -Inf; n = length(poly)
    for i in 1:n
        x1, y1 = poly[i][1], poly[i][2]
        j = i == n ? 1 : i + 1
        x2, y2 = poly[j][1], poly[j][2]
        if (y1 <= yc) != (y2 <= yc)
            x = x1 + (yc - y1) / (y2 - y1) * (x2 - x1)
            lo = min(lo, x); hi = max(hi, x)
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
    @test isempty(pk.overflowed)                       # no over-wide word dumped at L atop the map

    n_letterbox = 0; n_silhouette = 0
    for p in pk.placements
        w  = prep.segments[p.segment_index].width
        x0, x1 = p.x, p.x + w
        top = p.y - asc                                # word bbox top (block-top frame)
        yc  = top + la / 2                             # band center

        # (a) body never overlaps the masthead/sidebar top band
        @test top >= MapFeature.SIDEBAR_BOTTOM - 1e-6

        # body must stay within the page's inner horizontal margins
        @test x0 >= MapFeature.MARGIN - 1e-6
        @test x1 <= MapFeature.PAGE_W - MapFeature.MARGIN + 1e-6

        env = envelope_at(poly, yc)
        if env === nothing
            # (b) letterbox band (silhouette absent here): body must not enter the map column
            n_letterbox += 1
            @test x1 <= L.map_left + 1e-6 || x0 >= L.map_right - 1e-6
        else
            # (c) crossing band: body must not overlap the silhouette's horizontal envelope
            n_silhouette += 1
            el, er = env
            @test x1 <= el + 1e-6 || x0 >= er - 1e-6
        end
    end
    # Vermont is tall and fills most of the map region, so the prose genuinely wraps the
    # silhouette in many bands (not just a degenerate left rectangle).
    @test n_silhouette > 0
end
