using Test, TextMeasure

@testset "MonospaceBackend" begin
    b = MonospaceBackend(fontsize=10.0, advance_ratio=0.6, lineheight_ratio=1.2)

    # width = #grapheme-clusters * advance_ratio * fontsize
    @test TextMeasure.measure(b, "ab")  ≈ 2 * 0.6 * 10.0
    @test TextMeasure.measure(b, "")    == 0.0
    @test TextMeasure.measure(b, "2σ")  ≈ 2 * 0.6 * 10.0   # 2 grapheme clusters

    m = TextMeasure.font_metrics(b)
    @test m.ascent       ≈ 0.8 * 10.0
    @test m.descent      ≈ 0.2 * 10.0
    @test m.line_advance ≈ 1.2 * 10.0
    @test m.line_advance ≥ m.ascent + m.descent          # gap is non-negative

    # defaults
    bd = MonospaceBackend()
    @test bd.fontsize == 12.0 && bd.advance_ratio == 0.6 && bd.lineheight_ratio == 1.2
end
