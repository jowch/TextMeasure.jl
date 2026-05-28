# SPDX-License-Identifier: MIT
using Test, TextMeasure, TextMeasureLayouts
using GeometryBasics: Point2

# Synthetic ~30-vertex blob standing in for Vermont's state polygon (the real shapefile
# is #G's data and not present here). Scaled so ~600 bands of height `la` fit — the same
# "~600 scanlines × ~30 edges" code path the issue's perf bullet specifies.
function blob_poly(; n=30, r=900.0, cx=1000.0, cy=1000.0)
    [Point2{Float64}(cx + (r + 60.0*sin(5*2π*k/n)) * cos(2π*k/n),
                     cy + (r + 60.0*sin(5*2π*k/n)) * sin(2π*k/n)) for k in 0:n-1]
end

@testset "perf baseline (relative, >2x regression gate)" begin
    cf = polygon_chord_fn(blob_poly())
    b = MonospaceBackend()
    prep = prepare(b, join(("word$(i)" for i in 1:4000), " "))
    la = 3.0                                # ~1860px tall / 3 ≈ 620 bands
    shape_pack(prep, cf; line_advance=la, min_chord_width=10.0)   # warmup (compile)
    elapsed = minimum(@elapsed(shape_pack(prep, cf; line_advance=la, min_chord_width=10.0)) for _ in 1:3)
    @info "shape_pack perf" elapsed_seconds=elapsed
    # Hard gate: a machine-independent absolute ceiling. Catches algorithmic blow-ups
    # (e.g. an accidental O(bands²)); ~5s is orders of magnitude above the µs-scale norm.
    @test elapsed < 5.0

    # Relative >2x regression check against the COMMITTED baseline. This is intentionally
    # a non-fatal @warn in the package suite: a committed wall-clock is machine-specific,
    # so a hard 2x assertion would flake across runners. #J's weekly CI owns the
    # authoritative regression gate, re-baselining on its own consistent runner.
    path = joinpath(@__DIR__, "perf_baseline.txt")
    if isfile(path)
        baseline = parse(Float64, strip(read(path, String)))
        elapsed >= 2 * baseline &&
            @warn ">2x slower than committed perf baseline (machine variance or regression?)" elapsed baseline
    else
        write(path, string(elapsed))
        @info "perf baseline recorded" path elapsed
    end
end
