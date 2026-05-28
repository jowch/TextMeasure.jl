using Test

@testset "TextMeasure" begin
    include("test_types.jl")
    include("test_monospace.jl")
    include("test_containers.jl")
    include("test_prepare.jl")
    include("test_layout.jl")
    include("test_bounds.jl")
    include("test_integration.jl")
    include("test_freetype.jl")   # extension loads via test/Project.toml deps
    include("test_makie.jl")
    include("test_richtext.jl")
end
