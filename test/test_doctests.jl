using Test, TextMeasure, Documenter

# Run the `jldoctest` blocks in TextMeasure's docstrings as part of the suite, so the
# worked examples a reader copies out of `?prepare` / `?layout` / `?MonospaceBackend`
# stay in lock-step with the code. `manual=false` skips a docs/src manual (we have none);
# only deterministic MonospaceBackend examples are tagged `jldoctest` — extension examples
# are plain ```julia``` blocks and are never executed here.
DocMeta.setdocmeta!(TextMeasure, :DocTestSetup, :(using TextMeasure); recursive=true)

@testset "doctests" begin
    doctest(TextMeasure; manual=false)
end
