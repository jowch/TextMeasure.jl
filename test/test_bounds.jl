using Test, TextMeasure
using TextMeasure: StyledRun, bounds   # internal seam — not exported

@testset "bounds (pure union)" begin
    # empty → zero box
    @test bounds(StyledRun[]) == TextBounds((0.0, 0.0), (0.0, 0.0))

    # single run: box x∈[0,10], y∈[-2,8] (baseline 0, ascent 8, descent 2)
    r = StyledRun(0.0, 0.0, 10.0, 8.0, 2.0)
    b = bounds([r])
    @test b.size   == (10.0, 10.0)
    @test b.origin == (0.0, -2.0)

    # two runs, same baseline, second narrower/taller and offset in x
    r1 = StyledRun(0.0,  0.0, 10.0,  8.0, 2.0)
    r2 = StyledRun(10.0, 0.0,  6.0, 12.0, 3.0)
    b2 = bounds([r1, r2])
    @test b2.size   == (16.0, 15.0)   # x 0..16, y -3..12
    @test b2.origin == (0.0, -3.0)

    # non-zero x origin: width is the run's width, not the right-edge x
    rx = StyledRun(5.0, 0.0, 10.0, 8.0, 2.0)
    bx = bounds([rx])
    @test bx.size   == (10.0, 10.0)
    @test bx.origin == (5.0, -2.0)

    # multi-line: second line dropped (Makie +y up → more-negative baseline)
    l1 = StyledRun(0.0,   0.0, 10.0, 8.0, 2.0)
    l2 = StyledRun(0.0, -20.0, 14.0, 8.0, 2.0)
    b3 = bounds([l1, l2])
    @test b3.size   == (14.0, 30.0)   # x 0..14, y -22..8
    @test b3.origin == (0.0, -22.0)
end
