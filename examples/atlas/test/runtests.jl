using Atlas, Test

@testset "Atlas" begin
    @testset "loads" begin
        @test isdefined(Atlas, :solve_cluster)  # MakieTextRepel internal API resolved
    end
    include("test_data.jl")
end
