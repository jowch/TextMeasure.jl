using Test, TextMeasure, FIGlet

# Pinned cell-widths for the bundled fonts, discovered empirically (FIGlet fonts are
# deterministic integer cell grids). Standard "hello" = 31 cells; Small = 27.
const PIN_STD_HELLO   = 31.0
const PIN_SMALL_HELLO = 27.0

@testset "FigletBackend (live FIGlet.jl)" begin
    # extension registration: importing FIGlet after TextMeasure activated the ext
    @test Base.get_extension(TextMeasure, :TextMeasureFigletExt) !== nothing

    b = FigletBackend()                              # defaults: Standard font, gap 0
    @test b isa AbstractMeasurementBackend

    # determinism + pinned cell widths (Standard)
    @test TextMeasure.measure(b, "hello") == PIN_STD_HELLO
    @test TextMeasure.measure(b, "hello") == TextMeasure.measure(b, "hello")  # stable
    @test TextMeasure.measure(b, "") == 0.0

    # integer-valued cell counts returned as Float64
    w = TextMeasure.measure(b, "hello")
    @test w isa Float64 && w == round(w)

    # additive across runs with gap 0 (no kerning); cell counts sum exactly
    @test TextMeasure.measure(b, "ab") == TextMeasure.measure(b, "a") + TextMeasure.measure(b, "b")

    # letter_gap adds exactly one inter-glyph gap per adjacent pair. For a 2-char run that
    # is exactly +1 cell — proves the `letter_gap * (length-1)` arithmetic (not vacuous at gap 0).
    bg = FigletBackend(; letter_gap=1)
    @test TextMeasure.measure(bg, "ab") == TextMeasure.measure(b, "a") + TextMeasure.measure(b, "b") + 1
    # and (length-1) gaps for a 5-char run
    @test TextMeasure.measure(bg, "hello") == TextMeasure.measure(b, "hello") + 4

    # second bundled font (Small) — also deterministic
    bs = FigletBackend(; font="Small")
    @test TextMeasure.measure(bs, "hello") == PIN_SMALL_HELLO

    # missing-glyph fallback: a char absent from Standard measures the SPACE-cell width
    # (exercises the get(chars, c, fallback) branch — not a vacuous ≥0 assertion).
    @test !haskey(b.font.font_characters, '☃')       # confirm it is genuinely absent
    @test TextMeasure.measure(b, "☃") == TextMeasure.measure(b, " ")

    # ascent/descent/line_advance — hand-verified pinned numerics for Standard
    # (header height 6, baseline 5 ⇒ ascent 5, descent 1). Concrete, not circular.
    m = TextMeasure.font_metrics(b)
    @test m.ascent       == 5.0
    @test m.descent      == 1.0
    @test m.line_advance == 6.0

    # accept a FIGletFont object directly (not just a name)
    bf = FigletBackend(; font=FIGlet.readfont("standard"))
    @test TextMeasure.measure(bf, "hello") == PIN_STD_HELLO
end
