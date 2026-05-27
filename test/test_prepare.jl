using Test, TextMeasure
import TextMeasure: Segment, prepare

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
