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
end
