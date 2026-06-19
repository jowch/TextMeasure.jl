# SPDX-License-Identifier: MIT
using Tide, Test

@testset "Tide" begin
    @testset "loads" begin
        @test isdefined(Tide, :TIDE_TEXT)
        @test Tide.is_lit("kneads")
        @test Tide.is_lit("Kneads,")
        @test !Tide.is_lit("smoothing")
    end
    include("test_schedule.jl")
    include("test_mask.jl")
    include("test_justify.jl")
    include("test_frame.jl")
    include("test_golden.jl")
    include("test_doctests.jl")
end
