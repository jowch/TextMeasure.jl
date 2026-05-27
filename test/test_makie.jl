using Test, TextMeasure, Makie

@testset "MakieBackend" begin
    b = MakieBackend(; font="TeX Gyre Heros Makie", fontsize=24.0, px_per_unit=1.0)
    @test b isa AbstractMeasurementBackend

    face = Makie.to_font("TeX Gyre Heros Makie")
    for s in ("Mauna Kea", "AVATAR", "fjord", "Aconcagua")
        ours  = TextMeasure.measure(b, s)
        makie = Makie.widths(Makie.text_bb(s, face, 24.0))[1]   # markerspace width
        @test ours ≈ makie rtol=1e-4                            # spike measured 0.0% diff
    end

    @test TextMeasure.measure(b, "") == 0.0

    m = TextMeasure.font_metrics(b)
    @test m.ascent > 0 && m.descent > 0 && m.line_advance > 0

    # px_per_unit scales widths linearly
    b2 = MakieBackend(; font="TeX Gyre Heros Makie", fontsize=24.0, px_per_unit=2.0)
    @test TextMeasure.measure(b2, "AVATAR") ≈ 2 * TextMeasure.measure(b, "AVATAR")
end
