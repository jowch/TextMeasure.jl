# SPDX-License-Identifier: MIT
using Test, Woven, Documenter

# Run the jldoctest blocks in Woven's docstrings so the worked placement_table example stays
# in lock-step with the code. Deterministic via golden_backend (a MonospaceBackend factory),
# which is imported into the doctest namespace alongside Woven's exports.
DocMeta.setdocmeta!(Woven, :DocTestSetup,
                    :(using Woven; using Woven: golden_backend); recursive=true)

@testset "doctests" begin
    doctest(Woven; manual=false)
end
