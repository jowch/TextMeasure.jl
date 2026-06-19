# SPDX-License-Identifier: MIT
using Test, Atlas, TextMeasure, Documenter

# Run the jldoctest blocks in Atlas's docstrings so the worked examples in ?measure_boxes /
# ?project_point / ?town_ground / ?smoothstep stay in lock-step with the code. Only the pure
# functions are doctested (the disk-touching load_atlas_data is documented in prose). The
# internal (non-exported) names are imported into the doctest namespace.
DocMeta.setdocmeta!(Atlas, :DocTestSetup,
    :(using Atlas; using TextMeasure;
      using Atlas: project_point, town_ground, smoothstep, measure_boxes, KX);
    recursive=true)

@testset "doctests" begin
    doctest(Atlas; manual=false)
end
