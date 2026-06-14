using Erasure, Test

@testset "Erasure" begin
    @testset "loads" begin
        @test isdefined(Erasure, :LICENSE_TEXT)
    end
    include("test_poem.jl")
    include("test_layout.jl")
    include("test_golden.jl")
    include("test_render.jl")
    include("test_hero.jl")
end
