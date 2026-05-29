# SPDX-License-Identifier: MIT
# Render-level invariants on the REAL Vermont TWO-COLUMN layout, via MapFeature._compose_layout
# (no drawing). Each column is an independent shape_pack run reading top-to-bottom on its own side;
# POIs use numbered on-map markers keyed to a bottom-left legend (no labels in prose, no leaders).
using Test, MapFeature
using GeometryBasics: Point2

# Exact polygon horizontal envelope over y ∈ [y0,y1] (independent of complement_chord_fn):
# extremes occur only at the y0/y1 boundary crossings or at interior vertices.
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

            @test x0 >= MapFeature.MARGIN - 1e-6
            @test x1 <= MapFeature.PAGE_W - MapFeature.MARGIN + 1e-6
            @test wtop >= MapFeature.SIDEBAR_BOTTOM - 1e-6   # below the masthead/stat band

            if side === :west
                @test x1 <= L.map_center + 1e-6; n_west += 1
            else
                @test x0 >= L.map_center - 1e-6; n_east += 1
            end

            env = envelope_over(poly, wtop, wbot)            # body never overlaps the silhouette
            if env !== nothing
                el, er = env
                @test x1 <= el + 1e-6 || x0 >= er - 1e-6
            end
        end
    end
    @test n_west > 0 && n_east > 0                           # both columns genuinely populated
end

@testset "numbered legend + on-map numbers: clear of prose; one key entry per POI" begin
    L = MapFeature._compose_layout(load_vermont(), load_pois())
    pois = load_pois()

    # every POI is keyed in the legend, numbered 1..n
    @test length(L.legend.rows) == length(pois)
    @test [r.num for r in L.legend.rows] == collect(1:length(pois))

    # legend box lives in the bottom-left dead space: clear of the silhouette column, in the page box
    bx0, by0, bx1, by1 = L.legend.box
    @test bx0 >= MapFeature.MARGIN - 1e-6
    @test bx1 <= L.map_left + 1e-6
    @test by1 <= L.region_bottom + 1e-6

    # neither prose column overlaps the legend box, nor any on-map number box
    for (prep, pk, _) in L.columns
        asc, desc = prep.metrics.ascent, prep.metrics.descent
        for p in pk.placements
            w = prep.segments[p.segment_index].width
            @test !boxes_overlap(p.x, p.y - asc, w, asc + desc, bx0, by0, bx1 - bx0, by1 - by0)
            for (nx0, ny0, nx1, ny1) in L.number_excl
                @test !boxes_overlap(p.x, p.y - asc, w, asc + desc, nx0, ny0, nx1 - nx0, ny1 - ny0)
            end
        end
    end
end
