# SPDX-License-Identifier: MIT
using AsteroidTUI
using Test

@testset "AsteroidTUI" begin
    @testset "dependency surface" begin
        # The FIGlet weakdep extension must activate (cell-space measurement).
        @test AsteroidTUI._ext_loaded()
    end
end
