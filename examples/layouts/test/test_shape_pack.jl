# SPDX-License-Identifier: MIT
using Test, TextMeasure, TextMeasureLayouts

@testset "types" begin
    m = FontMetrics(8.0, 2.0, 14.0)
    p = Placement(3, 1.5, 10.0)
    @test p.segment_index == 3
    @test p.x == 1.5
    @test p.y == 10.0
    pl = PackedLayout([p], [7], m)
    @test pl.placements == [p]
    @test pl.overflowed == [7]
    @test pl.metrics === m
end
