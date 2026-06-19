# SPDX-License-Identifier: MIT
using Test, HouseStyle, Documenter

# Run the jldoctest blocks in HouseStyle's docstrings (footer, digest_rows — the
# machine-independent ones; the font-path helpers return absolute paths and aren't doctested).
DocMeta.setdocmeta!(HouseStyle, :DocTestSetup,
                    :(using HouseStyle: footer, digest_rows); recursive=true)

@testset "doctests" begin
    doctest(HouseStyle; manual=false)
end
