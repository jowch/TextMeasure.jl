using Erasure, Test

@testset "Erasure" begin
    @testset "loads" begin
        @test isdefined(Erasure, :LICENSE_TEXT)
    end
    include("test_wordgeom.jl")
    include("test_poem.jl")
    include("test_redact.jl")
    include("test_golden.jl")
    include("test_render.jl")
    include("test_hero.jl")
    include("test_toy.jl")
end
