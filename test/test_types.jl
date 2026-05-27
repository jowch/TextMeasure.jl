using Test
include("../src/types.jl")

@testset "core types" begin
    m = FontMetrics(8.0, 2.0, 12.0)
    @test m.ascent == 8.0 && m.descent == 2.0 && m.line_advance == 12.0

    s = Segment("ab", 12.0, :word)
    @test s.kind === :word && s.width == 12.0

    p = Prepared([s], m)
    @test length(p.segments) == 1 && p.metrics === m

    ln = Line("ab", 12.0, 0.0, 8.0)
    lay = Layout([ln], (12.0, 10.0), m)
    @test lay.size == (12.0, 10.0) && lay.metrics === m
end
