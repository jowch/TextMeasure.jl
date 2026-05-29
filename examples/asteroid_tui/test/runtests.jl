# SPDX-License-Identifier: MIT
using AsteroidTUI
using Test

@testset "AsteroidTUI" begin
    # MAJOR #1: retain the weakdep-extension activation regression check — the only
    # assertion that the FIGlet ext (cell-space measurement) actually loaded.
    @testset "dependency surface" begin
        @test AsteroidTUI._ext_loaded()
    end

    for f in ("test_cellbuffer.jl", "test_cellbackend.jl", "test_prose.jl", "test_pack.jl",
              "test_game.jl", "test_fracture.jl", "test_draw.jl", "test_gameloop.jl",
              "test_golden.jl")
        include(f)
    end
end
