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

@testset "POI labels are OUTBOARD: clear of the silhouette and on the correct side margin" begin
    L = MapFeature._compose_layout(load_vermont(), load_pois())
    poly, mc = L.poly_px, L.map_center
    left_x = MapFeature.MARGIN
    right_x = MapFeature.PAGE_W - MapFeature.MARGIN
    placed = 0
    for (i, p) in enumerate(load_pois())
        b = L.labelboxes[i]; b === nothing && continue
        placed += 1
        a = L.anchors[i]
        # (1) label sits at its side's page margin (outboard), not floating mid-column/on the map
        if a[1] < mc
            @test isapprox(b.x, left_x; atol=1e-6)              # west: left-anchored at the margin
        else
            @test isapprox(b.x + b.w, right_x; atol=1e-6)       # east: right edge on the margin
        end
        # (2) label box is horizontally clear of the silhouette envelope over its whole height
        env = envelope_over(poly, b.y, b.y + b.h)
        if env !== nothing
            el, er = env
            @test b.x + b.w <= el + 1e-6 || b.x >= er - 1e-6
        end
        # (3) within the page content box
        @test b.y >= L.region_top - 1e-6 && b.y + b.h <= L.region_bottom + 1e-6
    end
    @test placed >= length(load_pois()) - 2                     # at most a couple dropped
end
