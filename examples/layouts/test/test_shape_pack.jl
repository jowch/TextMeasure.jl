# SPDX-License-Identifier: MIT
using Test, TextMeasure, TextMeasureLayouts
using GeometryBasics: Point2

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

@testset "overflow: widest_row places + records" begin
    b = MonospaceBackend()
    prep = prepare(b, "tiny enormousindivisibletoken end")
    big = findfirst(s -> s.str == "enormousindivisibletoken", prep.segments)
    bigw = prep.segments[big].width
    w = bigw - 10.0                                   # narrower than the big token
    pk = shape_pack(prep, rect_chord_fn(w); line_advance=prep.metrics.line_advance, min_chord_width=0.0)
    @test big in pk.overflowed
    @test any(p -> p.segment_index == big && p.x == 0.0, pk.placements)   # still placed at L
    @test any(p -> prep.segments[p.segment_index].str == "tiny", pk.placements)
    @test any(p -> prep.segments[p.segment_index].str == "end", pk.placements)
end

@testset "overflow: skip drops + records + back-fills same band" begin
    b = MonospaceBackend()
    # big token is the FIRST word of band 1, so the following fitting word back-fills band 1.
    prep = prepare(b, "enormousindivisibletoken end")
    big = findfirst(s -> s.str == "enormousindivisibletoken", prep.segments)
    w = prep.segments[big].width - 10.0
    pk = shape_pack(prep, rect_chord_fn(w); line_advance=prep.metrics.line_advance,
                    min_chord_width=0.0, overflow_strategy=:skip)
    @test big in pk.overflowed
    @test all(p -> p.segment_index != big, pk.placements)                # never placed
    endp = only(p for p in pk.placements if prep.segments[p.segment_index].str == "end")
    @test endp.y == prep.metrics.ascent                                  # band-1 baseline (back-fill)
end

@testset "overflow: reject aborts" begin
    b = MonospaceBackend()
    prep = prepare(b, "tiny enormousindivisibletoken end")
    big = findfirst(s -> s.str == "enormousindivisibletoken", prep.segments)
    w = prep.segments[big].width - 10.0
    pk = shape_pack(prep, rect_chord_fn(w); line_advance=prep.metrics.line_advance,
                    min_chord_width=0.0, overflow_strategy=:reject)
    @test isempty(pk.placements)
    @test big in pk.overflowed
    endidx = findfirst(s -> s.str == "end", prep.segments)
    @test endidx in pk.overflowed                     # all later :word indices overflowed
end

@testset "min_chord_width skips narrow bands" begin
    b = MonospaceBackend()
    prep = prepare(b, "aaa bbb ccc ddd eee")
    la = prep.metrics.line_advance
    # even bands wide (100), odd bands a 5px sliver. min_chord_width=24 ⇒ slivers skipped.
    cf = (yt, yb) -> begin
        band = round(Int, yt / la) + 1
        iseven(band) ? [(0.0, 100.0)] : [(0.0, 5.0)]
    end
    pk = shape_pack(prep, cf; line_advance=la, min_chord_width=24.0)
    @test !isempty(pk.placements)
    for p in pk.placements
        band = round(Int, (p.y - prep.metrics.ascent) / la) + 1
        @test iseven(band)                            # odd slivers were skipped
    end
end

# ---- fill=:all : pack EVERY disjoint interval per band (left→right) ----------
# Two fixed disjoint intervals in every band; widths chosen so words overflow
# the left run and continue into the right run within the SAME band.
two_iv_chord_fn(l1, r1, l2, r2) =
    (yt, yb) -> [(Float64(l1), Float64(r1)), (Float64(l2), Float64(r2))]

@testset "fill argument validation" begin
    b = MonospaceBackend(); prep = prepare(b, "hi there")
    @test_throws ArgumentError shape_pack(prep, rect_chord_fn(50);
                                          line_advance=14.0, fill=:nope)
end

@testset "fill=:all wraps left run then right run on same baseline" begin
    b = MonospaceBackend()
    # each "aa" = 14.4px, space = 7.2px; left run (0,50) holds aa,bb then overflows
    prep = prepare(b, "aa bb cc dd")
    la = prep.metrics.line_advance
    pk = shape_pack(prep, two_iv_chord_fn(0, 50, 100, 150);
                    line_advance=la, min_chord_width=0.0, fill=:all)
    byidx = Dict(prep.segments[p.segment_index].str => p for p in pk.placements)
    @test all(haskey(byidx, w) for w in ("aa", "bb", "cc", "dd"))
    base = prep.metrics.ascent
    # all four land on band-1 baseline (same band, both runs)
    @test all(isapprox(byidx[w].y, base; atol=1e-9) for w in ("aa","bb","cc","dd"))
    # left run: aa,bb stay inside (0,50)
    for w in ("aa", "bb")
        seg = prep.segments[byidx[w].segment_index]
        @test byidx[w].x >= -1e-9
        @test byidx[w].x + seg.width <= 50.0 + 1e-9
    end
    # continuation: cc overflowed the left run and lands in the RIGHT run (100,150)
    for w in ("cc", "dd")
        seg = prep.segments[byidx[w].segment_index]
        @test byidx[w].x >= 100.0 - 1e-9
        @test byidx[w].x + seg.width <= 150.0 + 1e-9
    end
    @test byidx["cc"].x >= 100.0                       # the word that didn't fit left
    # placements appended left-to-right: every left-run placement precedes right-run
    xs = getfield.(pk.placements, :x)
    band1 = [p.x for p in pk.placements if isapprox(p.y, base; atol=1e-9)]
    leftmost_right = minimum(x for x in band1 if x >= 100.0)
    @test all(x -> x < leftmost_right, (x for x in band1 if x < 50.0))
    @test all(1 .<= getfield.(pk.placements, :segment_index) .<= length(prep.segments))
    @test all(p -> prep.segments[p.segment_index].kind === :word, pk.placements)
end

@testset "fill=:all fills both prongs of a concave (U) polygon band" begin
    b = MonospaceBackend()
    prep = prepare(b, "a b c d e f g h i j k l")
    la = prep.metrics.line_advance
    # U: outer 0..100 box with a top notch x∈[40,60], y∈[0,60].
    # Bands with center y<60 see two prongs (0,40) & (60,100); below, one (0,100).
    poly = Point2{Float64}[(0,0), (40,0), (40,60), (60,60), (60,0),
                           (100,0), (100,100), (0,100)]
    cf = polygon_chord_fn(poly)
    pk = shape_pack(prep, cf; line_advance=la, min_chord_width=10.0, fill=:all)
    base = prep.metrics.ascent                          # band-1 baseline (yc=7.2 < 60)
    band1 = [p for p in pk.placements if isapprox(p.y, base; atol=1e-9)]
    @test any(p -> p.x < 40.0, band1)                   # left prong got words
    @test any(p -> p.x >= 60.0, band1)                  # right prong got words
end

@testset "fill=:all skips a sub-threshold interval, keeps the wide one" begin
    b = MonospaceBackend()
    prep = prepare(b, "aa bb cc dd ee")
    la = prep.metrics.line_advance
    # left run is a 5px sliver (< mcw 24) → skipped; right run (100,200) fills.
    pk = shape_pack(prep, two_iv_chord_fn(0, 5, 100, 200);
                    line_advance=la, min_chord_width=24.0, fill=:all)
    @test !isempty(pk.placements)
    for p in pk.placements
        @test p.x >= 100.0 - 1e-9                        # nothing placed in the sliver
    end
end

@testset "fill=:all == fill=:widest when every band has one interval" begin
    b = MonospaceBackend()
    prep = prepare(b, "the quick brown fox jumps over the lazy dog here we go")
    la = prep.metrics.line_advance
    for w in (60.0, 120.0, 300.0)
        widest = shape_pack(prep, rect_chord_fn(w); line_advance=la,
                            min_chord_width=0.0, fill=:widest)
        allf   = shape_pack(prep, rect_chord_fn(w); line_advance=la,
                            min_chord_width=0.0, fill=:all)
        @test allf.placements == widest.placements
        @test allf.overflowed == widest.overflowed
    end
end

@testset "fill=:widest matches default placements" begin
    b = MonospaceBackend()
    prep = prepare(b, "alpha beta gamma delta epsilon zeta eta theta")
    la = prep.metrics.line_advance
    deflt   = shape_pack(prep, rect_chord_fn(90.0); line_advance=la, min_chord_width=0.0)
    explicit = shape_pack(prep, rect_chord_fn(90.0); line_advance=la,
                          min_chord_width=0.0, fill=:widest)
    @test explicit.placements == deflt.placements
    @test explicit.overflowed == deflt.overflowed
end
