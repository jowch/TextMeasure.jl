using Test, TextMeasure, FreeTypeAbstraction

@testset "FreeTypeBackend" begin
    b = FreeTypeBackend(; font="DejaVu Sans", fontsize=100.0, dpi=72.0)
    @test b isa AbstractMeasurementBackend

    wA  = TextMeasure.measure(b, "A")
    wB  = TextMeasure.measure(b, "B")
    wAB = TextMeasure.measure(b, "AB")
    @test wA > 0 && isfinite(wA)
    @test wAB ≈ wA + wB                       # no kerning ⇒ runs are additive
    @test TextMeasure.measure(b, "A") == wA   # stable across calls
    @test TextMeasure.measure(b, "") == 0.0

    m = TextMeasure.font_metrics(b)
    @test m.ascent > 0 && m.descent > 0 && m.line_advance > 0
    @test isfinite(m.line_advance)

    # dpi scales linearly: dpi=144 doubles widths vs dpi=72 (guards unit/DPI regressions)
    b2 = FreeTypeBackend(; font="DejaVu Sans", fontsize=100.0, dpi=144.0)
    @test TextMeasure.measure(b2, "A") ≈ 2 * wA

    # golden sanity: catches a gross unit bug (font-units → thousands, em-fractions → <1).
    # "A" in DejaVu Sans at fontsize=100, dpi=72 is ~60–80 px.
    @test 40.0 < wA < 100.0
end
