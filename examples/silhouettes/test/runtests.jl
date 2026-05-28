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
end
