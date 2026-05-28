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

# A rectangle of width w: every band offers the single interval (0, w).
rect_chord_fn(w) = (yt, yb) -> [(0.0, Float64(w))]

# Group placements into lines by their baseline y; return [(baseline, [words...]), ...].
function _lines_by_baseline(prep, pk)
    byline = Dict{Float64,Vector{Tuple{Float64,String}}}()
    for p in pk.placements
        push!(get!(byline, p.y, Tuple{Float64,String}[]), (p.x, prep.segments[p.segment_index].str))
    end
    [(y, [s for (_, s) in sort(v)]) for (y, v) in sort(collect(byline); by=first)]
end

@testset "rectangle == layout" begin
    # Equivalence is asserted for newline-free text only: shape_pack skips blank bands
    # whereas layout emits empty Lines, so blank-line counts differ harmlessly.
    b = MonospaceBackend()
    text = "the quick brown fox jumps over the lazy dog and then some more words here"
    prep = prepare(b, text)
    for w in (60.0, 100.0, 180.0, 400.0)
        lay = layout(prep; max_width=w)               # default lineheight=1.0, align=:left
        pk  = shape_pack(prep, rect_chord_fn(w);
                         line_advance=prep.metrics.line_advance, min_chord_width=0.0)
        nonblank = [ln for ln in lay.lines if !isempty(strip(ln.str))]
        laywords = [split(ln.str) for ln in nonblank]
        pklines  = _lines_by_baseline(prep, pk)
        @test length(pklines) == length(laywords)
        for (i, (y, words)) in enumerate(pklines)
            @test words == laywords[i]                          # same line breaks
            @test isapprox(y, nonblank[i].baseline; atol=1e-9)  # coord-frame consistency
        end
        # invariants
        @test all(1 .<= getfield.(pk.placements, :segment_index) .<= length(prep.segments))
        @test all(p -> prep.segments[p.segment_index].kind === :word, pk.placements)
        @test isempty(pk.overflowed)                  # nothing over-wide at these widths
    end
end

@testset "placements lie within band chords" begin
    b = MonospaceBackend()
    prep = prepare(b, "alpha beta gamma delta epsilon zeta eta theta iota kappa")
    w = 120.0
    pk = shape_pack(prep, rect_chord_fn(w); line_advance=prep.metrics.line_advance, min_chord_width=0.0)
    for p in pk.placements
        seg = prep.segments[p.segment_index]
        @test p.x >= -1e-9
        @test p.x + seg.width <= w + 1e-9             # word stays inside (0, w)
    end
end

@testset "argument validation" begin
    b = MonospaceBackend(); prep = prepare(b, "hi there")
    @test_throws ArgumentError shape_pack(prep, rect_chord_fn(50); line_advance=0.0)
    @test_throws ArgumentError shape_pack(prep, rect_chord_fn(50);
                                          line_advance=14.0, overflow_strategy=:nope)
end

@testset "empty prepared" begin
    b = MonospaceBackend(); prep = prepare(b, "")
    pk = shape_pack(prep, rect_chord_fn(50); line_advance=prep.metrics.line_advance)
    @test isempty(pk.placements) && isempty(pk.overflowed)
end
