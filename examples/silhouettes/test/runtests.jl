# SPDX-License-Identifier: MIT
using Test
using Silhouettes
using Random
import GeometryOps as GO
import GeometryBasics as GB
const GI = GO.GI
const P2 = GB.Point2{Float64}

@testset "Silhouettes.jl" begin
    @testset "asteroid_polygon" begin
        rng = Xoshiro(20260528)
        p = asteroid_polygon(rng; n=12, lumpiness=0.4)
        @test p isa Vector{P2}
        @test length(p) == 12                                  # open ring, n distinct vertices
        @test allunique(p)
        @test GO.signed_area(GB.Polygon(p)) > 0                # CCW

        # star-shaped about the origin ⇒ simple (no self-intersection), across params
        for seed in (1, 2, 7), n in (6, 12, 32), lump in (0.0, 0.4, 1.0)
            q = asteroid_polygon(Xoshiro(seed); n=n, lumpiness=lump)
            @test length(q) == n
            @test GO.signed_area(GB.Polygon(q)) > 0
            @test GO.contains(GB.Polygon(q), P2(0.0, 0.0))     # origin interior ⇒ star-shaped ⇒ simple
        end

        # lumpiness = 0 ⇒ perfect unit circle (all radii ≈ 1)
        circle = asteroid_polygon(Xoshiro(99); n=24, lumpiness=0.0)
        @test all(v -> isapprox(hypot(v[1], v[2]), 1.0; atol=1e-9), circle)

        # determinism: same seed ⇒ identical output
        @test asteroid_polygon(Xoshiro(5); n=10) == asteroid_polygon(Xoshiro(5); n=10)

        # argument validation
        @test_throws ArgumentError asteroid_polygon(Xoshiro(1); n=5)
        @test_throws ArgumentError asteroid_polygon(Xoshiro(1); n=33)
        @test_throws ArgumentError asteroid_polygon(Xoshiro(1); lumpiness=-0.1)
        @test_throws ArgumentError asteroid_polygon(Xoshiro(1); lumpiness=1.1)
    end

    @testset "rasterize" begin
        unit = P2[(0,0), (1,0), (1,1), (0,1)]
        @test rasterize(unit, 0.5) == trues(2, 2)
        @test rasterize(unit, 0.25) == trues(4, 4)
        @test rasterize(unit, 1.0) == trues(1, 1)
        @test rasterize(unit, 0.5) isa BitMatrix

        # convention test: L-shape with the notch at TOP-RIGHT proves row1=top, col1=left.
        # Bottom strip x∈[0,2] y∈[0,1] full; left column x∈[0,1] y∈[1,2] full; top-right missing.
        L = P2[(0,0), (2,0), (2,1), (1,1), (1,2), (0,2)]
        r = rasterize(L, 0.5)
        @test size(r) == (4, 4)
        expected = BitMatrix([
            1 1 0 0     # row 1 = TOP: notch on the right
            1 1 0 0
            1 1 1 1     # rows 3-4 = bottom strip: full
            1 1 1 1
        ])
        @test r == expected

        @test_throws ArgumentError rasterize(unit, 0.0)
        @test_throws ArgumentError rasterize(unit, -1.0)
    end

    # Close an open ring (first == last) — GeometryOps 0.1.40's boolean ops error on edge-adjacent
    # OPEN rings; closing them makes intersection/difference tolerate adjacency.
    _close(p) = (length(p) > 1 && p[1] == p[end]) ? p : vcat(p, [p[1]])

    # Returns (rel_union_gap, rel_pairwise_max), both / area(parent).
    # rel_union_gap is a robust upper-bound proxy for area(symdiff(⋃shards, parent))/area(parent):
    # `outside` = Σ area(shard ∖ parent) is the spill term; when the (separately asserted) pairwise
    # overlap is ~0 the shards don't double-count, so area(symdiff) == |area(parent) - Σarea(shard)| +
    # 2*outside exactly. We do NOT assume shards ⊆ parent — the +2*outside term captures any spill.
    # Uses GeometryOps union/intersection/difference/area (per the #D acceptance), substituting
    # the difference-based symdiff area since GeometryOps 0.1.40 has no `symmetric_difference`.
    function partition_quality(shards, parent_pts)
        parent = GB.Polygon(_close(parent_pts))
        parea = GO.area(parent)
        polys = [GB.Polygon(_close(s)) for s in shards]
        total = sum(GO.area, polys)
        outside = 0.0
        for p in polys
            d = GO.difference(p, parent; target=GI.PolygonTrait())
            outside += isempty(d) ? 0.0 : sum(GO.area, d)
        end
        union_gap = (abs(parea - total) + 2 * outside) / parea
        pair = 0.0
        for i in 1:length(polys), j in (i + 1):length(polys)
            inter = GO.intersection(polys[i], polys[j]; target=GI.PolygonTrait())
            a = isempty(inter) ? 0.0 : sum(GO.area, inter)
            pair = max(pair, a / parea)
        end
        return (union_gap, pair)
    end

    @testset "voronoi_shatter (n ≥ 3)" begin
        square = P2[(0,0), (10,0), (10,10), (0,10)]
        for n in (3, 4, 5, 8)
            shards = voronoi_shatter(square, P2(5.0, 5.0); n_shards=n)
            @test shards isa Vector{Vector{P2}}
            @test length(shards) == n                          # convex parent ⇒ exact count
            @test all(s -> GO.signed_area(GB.Polygon(s)) > 0, shards)   # every shard open CCW
            ug, pm = partition_quality(shards, square)
            @test ug < 1e-6                                    # union(shards) == parent within tol
            @test pm < 1e-6                                    # pairwise intersections zero-measure
        end

        # default n_shards == 4
        @test length(voronoi_shatter(square, P2(5.0, 5.0))) == 4

        # concave (asteroid) parent: floor on count, partition still exact
        ast = asteroid_polygon(Xoshiro(3); n=14, lumpiness=0.45)
        cx = sum(first, ast) / length(ast); cy = sum(last, ast) / length(ast)
        shards = voronoi_shatter(ast, P2(cx, cy); n_shards=5)
        @test length(shards) >= 5
        @test all(s -> GO.signed_area(GB.Polygon(s)) > 0, shards)   # every shard open CCW
        ug, pm = partition_quality(shards, ast)
        @test ug < 1e-6
        @test pm < 1e-6

        @test_throws ArgumentError voronoi_shatter(square, P2(5.0,5.0); n_shards=1)
        @test_throws ArgumentError voronoi_shatter(square, P2(5.0,5.0); n_shards=9)
    end

    @testset "voronoi_shatter (n == 2)" begin
        square = P2[(0,0), (10,0), (10,10), (0,10)]
        shards = voronoi_shatter(square, P2(5.0, 5.0); n_shards=2)
        @test length(shards) == 2
        @test all(s -> GO.signed_area(GB.Polygon(s)) > 0, shards)   # every shard open CCW
        ug, pm = partition_quality(shards, square)
        @test ug < 1e-6
        @test pm < 1e-6

        ast = asteroid_polygon(Xoshiro(11); n=16, lumpiness=0.5)
        cx = sum(first, ast) / length(ast); cy = sum(last, ast) / length(ast)
        s2 = voronoi_shatter(ast, P2(cx, cy); n_shards=2)
        @test length(s2) >= 2
        @test all(s -> GO.signed_area(GB.Polygon(s)) > 0, s2)       # every shard open CCW
        ug2, pm2 = partition_quality(s2, ast)
        @test ug2 < 1e-6
        @test pm2 < 1e-6
    end
end
