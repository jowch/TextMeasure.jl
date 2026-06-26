# SPDX-License-Identifier: MIT
using Test

# Smoke-run the example scripts so they can't silently rot against the public API, and pin the
# figures the README quotes so prose/figure drift fails loudly here. Each script is included
# into its OWN fresh module (they reuse top-level names like `PROSE`/`W`/`justify`) with stdout
# suppressed. Both are MonospaceBackend-deterministic, so the numbers are stable.
@testset "examples" begin
    exdir = joinpath(@__DIR__, "..", "examples")

    @testset "shape_pack_ascii.jl runs" begin
        m = Module()
        redirect_stdout(devnull) do
            Base.include(m, joinpath(exdir, "shape_pack_ascii.jl"))
        end
        @test isdefined(m, :prep)            # reached the end without throwing
    end

    @testset "optimal_linebreaks.jl runs" begin
        m = Module()
        redirect_stdout(devnull) do
            Base.include(m, joinpath(exdir, "optimal_linebreaks.jl"))   # its own @assert fires here
        end
        # The demo's claim: optimal is strictly better than greedy on this paragraph.
        @test m.opt.total_badness < m.gdy.total_badness
        # The exact figures the README quotes — keep them in lock-step with the script.
        @test round(m.opt.total_badness, digits = 1) == 280.9
        @test round(m.gdy.total_badness, digits = 1) == 3512.6
    end
end
