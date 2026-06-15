using Atlas, Test

@testset "Atlas" begin
    @testset "loads" begin
        @test isdefined(Atlas, :solve_cluster)  # MakieTextRepel internal API resolved
    end
    include("test_data.jl")
    include("test_pois.jl")
    include("test_camera.jl")
    include("test_lod.jl")
    include("test_place.jl")
    include("test_fade.jl")
    include("test_clearance.jl")
end
