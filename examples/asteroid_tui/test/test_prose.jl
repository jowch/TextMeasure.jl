# SPDX-License-Identifier: MIT
using AsteroidTUI: asteroid_prose, PROSE_VARIANTS
using Random
using Test

@testset "prose pool" begin
    @test PROSE_VARIANTS() >= 50
    rng = Xoshiro(7)
    s = asteroid_prose(rng)
    @test s isa String && length(split(s)) >= 6
    # deterministic by seed
    @test asteroid_prose(Xoshiro(1)) == asteroid_prose(Xoshiro(1))
    # variety: 40 draws give many distinct strings
    seen = Set(asteroid_prose(Xoshiro(i)) for i in 1:40)
    @test length(seen) >= 30
    # no global RNG side effects
    Random.seed!(123); a = rand(); Random.seed!(123); asteroid_prose(Xoshiro(9)); b = rand()
    @test a == b
end
