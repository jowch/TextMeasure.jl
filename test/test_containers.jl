using Test, TextMeasure

@testset "backend container structs" begin
    # Generic container holds an opaque face; constructed positionally without any weak dep.
    ft = FreeTypeBackend("FACE", 12.0, 72.0)
    @test ft isa AbstractMeasurementBackend
    @test ft.face == "FACE" && ft.fontsize == 12.0 && ft.dpi == 72.0

    mk = MakieBackend("FACE", 14.0, 2.0)
    @test mk isa AbstractMeasurementBackend
    @test mk.face == "FACE" && mk.fontsize == 14.0 && mk.px_per_unit == 2.0

    # Keyword constructors require the extension; absent it, they error.
    @test_throws MethodError FreeTypeBackend(; font="Inter")
    @test_throws MethodError MakieBackend(; fontsize=12)

    # FigletBackend: opaque font, Int letter_gap (deliberate departure — cell counts, not px)
    fig = FigletBackend("FONT", 2)
    @test fig isa AbstractMeasurementBackend
    @test fig.font == "FONT" && fig.letter_gap === 2
    # keyword constructor requires the FIGlet extension; absent it, it errors.
    @test_throws MethodError FigletBackend(; letter_gap=0)
end
