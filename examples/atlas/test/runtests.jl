# SPDX-License-Identifier: MIT
using Atlas, Test

@testset "Atlas" begin
    @testset "loads" begin
        @test isdefined(Atlas, :warm_solve)  # MakieTextRepel public API resolved
    end
    include("test_data.jl")
    include("test_pois.jl")
    include("test_camera.jl")
    include("test_lod.jl")
    include("test_place.jl")
    include("test_clearance.jl")
    include("test_golden.jl")
    include("test_loop.jl")
    include("test_doctests.jl")
end
