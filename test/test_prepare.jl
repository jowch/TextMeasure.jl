using Test, TextMeasure
import TextMeasure: Segment, FontMetrics, prepare

# advance_ratio = 1.0, fontsize = 10  ⇒  each char is 10 px wide
const B = MonospaceBackend(fontsize=10.0, advance_ratio=1.0, lineheight_ratio=1.2)

kinds(p)  = [s.kind  for s in p.segments]
strs(p)   = [s.str   for s in p.segments]
widths(p) = [s.width for s in p.segments]

# Custom backends for the measurement guards (structs MUST be top-level, not in a @testset)
struct NaNBackend <: TextMeasure.AbstractMeasurementBackend end
TextMeasure.measure(::NaNBackend, ::AbstractString) = NaN
TextMeasure.font_metrics(::NaNBackend) = FontMetrics(1.0, 1.0, 1.0)

struct NegBackend <: TextMeasure.AbstractMeasurementBackend end
TextMeasure.measure(::NegBackend, ::AbstractString) = -5.0
TextMeasure.font_metrics(::NegBackend) = FontMetrics(1.0, 1.0, 1.0)

@testset "prepare tokenization" begin
    p = prepare(B, "ab cd")
    @test kinds(p)  == [:word, :space, :word]
    @test strs(p)   == ["ab", " ", "cd"]
    @test widths(p) == [20.0, 10.0, 20.0]
    @test p.metrics.ascent ≈ 8.0

    # multiple interior spaces are ONE space segment (preserved, not collapsed)
    p2 = prepare(B, "a  b")
    @test kinds(p2) == [:word, :space, :word]
    @test strs(p2)  == ["a", "  ", "b"]

    # each newline is its own segment, width 0
    p3 = prepare(B, "a\nb")
    @test kinds(p3) == [:word, :newline, :word]
    @test widths(p3)[2] == 0.0
    @test prepare(B, "\n\n").segments |> length == 2
    @test all(s.kind === :newline for s in prepare(B, "\n\n").segments)

    # tab counts as space
    @test kinds(prepare(B, "a\tb")) == [:word, :space, :word]

    # empty string ⇒ no segments
    @test isempty(prepare(B, "").segments)
end

@testset "prepare measurement guards" begin
    @test_throws ArgumentError prepare(NaNBackend(), "x")
    @test prepare(NegBackend(), "x").segments[1].width == 0.0   # clamped
end

@testset "subprep" begin
    prep = prepare(B, "the quick\nbrown fox")   # the,sp,quick,nl,brown,sp,fox

    # full-range slice is field-equivalent (== may default to identity on mutable fields)
    full = subprep(prep, 1:length(prep.segments))
    @test full.metrics == prep.metrics
    @test length(full.segments) == length(prep.segments)
    @test all(full.segments[i] == prep.segments[i] for i in 1:length(prep.segments))

    # slice at a word boundary; layout both halves; word-widths sum back (no re-measure)
    p2 = prepare(B, "the quick brown")          # the,sp,quick,sp,brown  (1..5)
    sp = findfirst(s -> s.kind === :space, p2.segments)
    left  = subprep(p2, 1:sp-1)                          # the
    right = subprep(p2, sp+1:length(p2.segments))        # quick,sp,brown
    @test length(left.segments) + 1 + length(right.segments) == length(p2.segments)
    ll = layout(left;  max_width=1e6)
    lr = layout(right; max_width=1e6)
    @test !isempty(ll.lines) && !isempty(lr.lines)       # layout runs on both halves
    wsum(p) = sum(s.width for s in p.segments if s.kind === :word)
    @test wsum(left) + wsum(right) == wsum(p2)           # widths preserved verbatim

    # slicing across :newline preserves integrity: segment lands in the indexed side
    nl = findfirst(s -> s.kind === :newline, prep.segments)
    @test subprep(prep, 1:nl).segments[end].kind === :newline
    @test subprep(prep, nl+1:length(prep.segments)).segments[1].kind !== :newline

    # slicing across :space — segment lands in indexed side; no segments dropped or duplicated
    sp2 = findfirst(s -> s.kind === :space, prep.segments)
    @test subprep(prep, 1:sp2).segments[end].kind === :space
    @test all(length(subprep(prep, r).segments) == length(r)
              for r in (1:sp2, sp2+1:length(prep.segments)))
end
