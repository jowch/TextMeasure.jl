# SPDX-License-Identifier: MIT
using Test
@testset "MapFeature.jl" begin
    include("test_complement_chord_fn.jl")
    include("test_projection.jl")
    include("test_poi_labels.jl")
    include("test_data.jl")
    include("test_render_layout.jl")
    include("test_render_pdf.jl")
end
