# SPDX-License-Identifier: MIT
using Test, TextMeasure, TextMeasureLayouts, Justification
using SHA: sha256

# Golden = SHA-256 of the COMPUTED comparison (break word-lists + per-line badness),
# NOT the rendered PDF bytes (PDFs are nondeterministic: timestamps, font subsetting).
# Computed under the deterministic MonospaceBackend at the demo's three columns, so this
# locks the algorithm output, not pixels (CLAUDE.md: assert on computed structures).

# px columns for the digest (MonospaceBackend units; the render picks its own serif widths)
const GOLDEN_WIDE   = 300.0
const GOLDEN_NARROW = 150.0

function _serialize(prep, lay)
    io = IOBuffer()
    for l in lay.lines
        words = join((prep.segments[i].str for i in l.words), " ")
        println(io, words, " | b=", round(l.badness; digits=3))
    end
    return String(take!(io))
end

function _digest()
    prep = prepare(MonospaceBackend(), CANONICAL_PARAGRAPH)
    cols = [
        ("greedy", GOLDEN_WIDE,   greedy_justify(prep; max_width=GOLDEN_WIDE)),
        ("greedy", GOLDEN_NARROW, greedy_justify(prep; max_width=GOLDEN_NARROW)),
        ("knuth_plass", GOLDEN_NARROW, knuth_plass(prep; max_width=GOLDEN_NARROW)),
    ]
    io = IOBuffer()
    for (alg, w, lay) in cols
        println(io, "## ", alg, " @ ", w, "  total_badness=", round(lay.total_badness; digits=3))
        print(io, _serialize(prep, lay))
    end
    return bytes2hex(sha256(take!(io)))
end

@testset "comparison golden digest" begin
    path = joinpath(@__DIR__, "comparison_golden.txt")
    digest = _digest()
    if isfile(path)
        @test digest == strip(read(path, String))
    else
        write(path, digest)
        @info "comparison golden recorded" path digest
        @test isfile(path)
    end
end
