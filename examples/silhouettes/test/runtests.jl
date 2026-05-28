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
end
