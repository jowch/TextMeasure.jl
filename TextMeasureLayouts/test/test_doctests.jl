# SPDX-License-Identifier: MIT
using Test, TextMeasure, TextMeasureLayouts, Documenter

# Run the jldoctest blocks in TextMeasureLayouts' docstrings so the worked examples in
# `?knuth_plass` / `?shape_pack` stay in lock-step with the code. Deterministic under
# MonospaceBackend.
DocMeta.setdocmeta!(TextMeasureLayouts, :DocTestSetup,
                    :(using TextMeasure, TextMeasureLayouts); recursive=true)

@testset "doctests" begin
    doctest(TextMeasureLayouts; manual=false)
end
