# SPDX-License-Identifier: MIT
using Woven: hero
using Test

@testset "hero" begin
    @testset "renders a valid PNG and places both poems" begin
        dir = mktempdir()
        path = joinpath(dir, "woven-hero.png")
        result = hero(path)
        @test isfile(path)
        @test filesize(path) > 0
        @test read(path, 8) == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]  # PNG magic

        placements = result.placements
        @test !isempty(placements)
        roles = Set(p.role for p in placements)
        @test :red   in roles            # the grant-clause poem is lit
        @test :black in roles            # the notice→warranty poem is lit
        @test :ghost in roles            # the faded source survives around them
    end
end
