using Erasure, Test

@testset "Erasure" begin
    @testset "loads" begin
        @test isdefined(Erasure, :LICENSE_TEXT)
    end
    include("test_wordgeom.jl")
end
