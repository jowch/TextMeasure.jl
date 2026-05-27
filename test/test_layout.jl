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

@testset "alignment" begin
    # two lines of differing width: "abcd"(24) wraps from "ef"(12) at max_width=24
    segs = [W("abcd",24.0), Segment(" ",6.0,:space), W("ef",12.0)]
    p = prep(segs)

    ll = layout(p; max_width=24.0, align=:left)
    @test [l.x for l in ll.lines] == [0.0, 0.0]

    lc = layout(p; max_width=24.0, align=:center)
    @test lc.size[1] == 24.0
    @test [l.x for l in lc.lines] == [0.0, 6.0]   # (24-24)/2, (24-12)/2

    lr = layout(p; max_width=24.0, align=:right)
    @test [l.x for l in lr.lines] == [0.0, 12.0]  # 24-24, 24-12

    @test_throws ArgumentError layout(p; align=:justify)
end

@testset "newlines and blank lines" begin
    # "a\nb" ⇒ 2 lines
    @test [l.str for l in layout(prep([W("a",6.0), NL(), W("b",6.0)])).lines] == ["a", "b"]

    # trailing newline ⇒ trailing empty line: "a\n" ⇒ ["a", ""]
    l1 = layout(prep([W("a",6.0), NL()]))
    @test [l.str for l in l1.lines] == ["a", ""]
    @test l1.lines[2].width == 0.0
    @test l1.size[2] == 8.0 + 1*12.0 + 2.0       # N=2

    # lone "\n" ⇒ 2 empty lines; "\n\n" ⇒ 3
    @test length(layout(prep([NL()])).lines) == 2
    @test length(layout(prep([NL(), NL()])).lines) == 3
    @test all(l.str == "" for l in layout(prep([NL(), NL()])).lines)
end

@testset "whitespace-only and empty" begin
    # whitespace-only (no newline) ⇒ ONE empty line, width 0, height = ascent+descent
    lws = layout(prep([Segment("   ",18.0,:space)]))
    @test length(lws.lines) == 1
    @test lws.lines[1].str == "" && lws.lines[1].width == 0.0
    @test lws.size == (0.0, 10.0)

    # empty input (no segments) ⇒ ZERO lines, size (0,0); still carries metrics
    le = layout(Prepared(Segment[], M))
    @test isempty(le.lines)
    @test le.size == (0.0, 0.0)
    @test le.metrics === M
end
