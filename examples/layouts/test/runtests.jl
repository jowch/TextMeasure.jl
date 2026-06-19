# SPDX-License-Identifier: MIT
using Test
@testset "TextMeasureLayouts" begin
    include("test_shape_pack.jl")
    include("test_chord_fns.jl")
    include("test_perf.jl")
    include("test_knuth_plass.jl")
    include("test_doctests.jl")
end
