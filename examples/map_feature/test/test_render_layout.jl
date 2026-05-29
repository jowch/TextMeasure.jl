# SPDX-License-Identifier: MIT
# Render-level non-overlap invariants on the REAL Vermont TWO-COLUMN layout, via the factored-out
# MapFeature._compose_layout (no drawing). Each column is an independent shape_pack run; both must
# read top-to-bottom on their own side and never overlap the silhouette, the labels, or the chrome.
using Test, MapFeature
using GeometryBasics: Point2

# Polygon horizontal envelope over y ∈ [y0,y1], computed DIRECTLY from the polygon (independent of
# complement_chord_fn), EXACTLY: extremes are at the y0/y1 boundary crossings or interior vertices.
function envelope_over(poly, y0, y1)
    lo = Inf; hi = -Inf; n = length(poly)
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

boxes_overlap(ax, ay, aw, ah, bx, by, bw, bh) =
    ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah

@testset "render layout (Vermont, two independent columns)" begin
    L = MapFeature._compose_layout(load_vermont(), load_pois())
    poly = L.poly_px
    @test length(L.columns) == 2
    labels = [b for b in L.labelboxes if b !== nothing]
    @test !isempty(labels)

    n_west = 0; n_east = 0
    for (prep, pk, side) in L.columns
        asc, desc = prep.metrics.ascent, prep.metrics.descent
        @test !isempty(pk.placements)                       # neither column starves
        placed_idx = Set(p.segment_index for p in pk.placements)
        @test all(si -> !(si in placed_idx), pk.overflowed) # :skip-overflow words are never placed

        for p in pk.placements
            w  = prep.segments[p.segment_index].width
            x0, x1 = p.x, p.x + w
            wtop, wbot = p.y - asc, p.y + desc

            # within inner margins, and below the masthead/stat band
            @test x0 >= MapFeature.MARGIN - 1e-6
            @test x1 <= MapFeature.PAGE_W - MapFeature.MARGIN + 1e-6
            @test wtop >= MapFeature.SIDEBAR_BOTTOM - 1e-6

            # each column stays strictly on its own side of map-center (two real columns)
            if side === :west
                @test x1 <= L.map_center + 1e-6; n_west += 1
            else
                @test x0 >= L.map_center - 1e-6; n_east += 1
            end

            # body-vs-silhouette over the word's full glyph height (faithful, independent envelope)
            env = envelope_over(poly, wtop, wbot)
            if env !== nothing
                el, er = env
                @test x1 <= el + 1e-6 || x0 >= er - 1e-6
            end

            # body-vs-POI-label
            for b in labels
                @test !boxes_overlap(x0, wtop, w, asc + desc, b.x, b.y, b.w, b.h)
            end
        end
    end
    @test n_west > 0 && n_east > 0                           # both columns genuinely populated
end
