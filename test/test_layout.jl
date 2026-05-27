using Test, TextMeasure
import TextMeasure: Segment, Prepared, layout, line_top

const M = FontMetrics(8.0, 2.0, 12.0)   # ascent 8, descent 2, line_advance 12
W(s, w) = Segment(s, w, :word)
SP(w)   = Segment(" "^max(1,round(Int,w/6)), w, :space)  # str length irrelevant to math
NL()    = Segment("\n", 0.0, :newline)
prep(segs) = Prepared(collect(segs), M)

@testset "single + multi-word, no wrap" begin
    lay = layout(prep([W("ab", 12.0)]))
    @test length(lay.lines) == 1
    @test lay.lines[1].str == "ab"
    @test lay.lines[1].width == 12.0
    @test lay.lines[1].x == 0.0
    @test lay.lines[1].baseline == 8.0          # first baseline = ascent
    @test lay.size == (12.0, 10.0)              # N=1 ⇒ ascent + descent
    @test lay.metrics === M

    lay2 = layout(prep([W("ab",12.0), Segment(" ",6.0,:space), W("cd",12.0)]))
    @test length(lay2.lines) == 1
    @test lay2.lines[1].str == "ab cd"
    @test lay2.lines[1].width == 30.0
    @test lay2.size == (30.0, 10.0)
end

@testset "wrapping + geometry" begin
    segs = [W("ab",12.0), Segment(" ",6.0,:space), W("cd",12.0)]
    lay = layout(prep(segs); max_width=20.0)    # 12+6+12=30 > 20 ⇒ break before "cd"
    @test [l.str for l in lay.lines] == ["ab", "cd"]
    @test [l.width for l in lay.lines] == [12.0, 12.0]
    @test [l.baseline for l in lay.lines] == [8.0, 20.0]   # ascent, ascent+la
    @test lay.size == (12.0, 22.0)              # N=2 ⇒ ascent + 1*la + descent
    # the space at the wrap point is consumed (neither line keeps it)
    @test lay.lines[1].str == "ab" && lay.lines[2].str == "cd"
end

@testset "trailing/leading whitespace trimmed; interior preserved" begin
    # leading + trailing spaces dropped
    lay = layout(prep([Segment(" ",6.0,:space), W("hi",12.0), Segment(" ",6.0,:space)]))
    @test lay.lines[1].str == "hi" && lay.lines[1].width == 12.0
    # interior double space preserved
    lay2 = layout(prep([W("a",6.0), Segment("  ",12.0,:space), W("b",6.0)]))
    @test lay2.lines[1].str == "a  b" && lay2.lines[1].width == 24.0
end

@testset "over-wide token gets its own line; size reports true width" begin
    segs = [W("toolong", 42.0), Segment(" ",6.0,:space), W("x", 6.0)]
    lay = layout(prep(segs); max_width=10.0)
    @test [l.str for l in lay.lines] == ["toolong", "x"]
    @test lay.size[1] == 42.0                   # true overflow width
end

@testset "max_width ≤ 0 or NaN ⇒ no wrap" begin
    segs = [W("a",6.0), Segment(" ",6.0,:space), W("b",6.0)]
    @test length(layout(prep(segs); max_width=0.0).lines)  == 1
    @test length(layout(prep(segs); max_width=NaN).lines)  == 1
    @test length(layout(prep(segs); max_width=-5.0).lines) == 1
end

@testset "line_top helper" begin
    segs = [W("a",6.0), NL(), W("b",6.0)]
    lay = layout(prep(segs))
    @test line_top(lay, lay.lines[1]) == 0.0    # baseline 8 - ascent 8
    @test line_top(lay, lay.lines[2]) == 12.0   # baseline 20 - ascent 8 = la
end
