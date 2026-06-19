# SPDX-License-Identifier: MIT
using Test, TextMeasure, Tide, Documenter

# Run the jldoctest blocks in Tide's docstrings so the worked examples in ?prepare_tide /
# ?frame_layout / ?press_at / ?is_lit / ?region_mask stay in lock-step with the code.
# Deterministic under MonospaceBackend. The internal (non-exported) showcase names are
# imported into the doctest namespace so the examples read like real call sites.
DocMeta.setdocmeta!(Tide, :DocTestSetup,
    :(using TextMeasure; using Tide;
      using Tide: prepare_tide, frame_layout, press_at, is_lit, has_lit,
                  region_mask, DIRECTIONS, N_FRAMES);
    recursive=true)

@testset "doctests" begin
    doctest(Tide; manual=false)
end
