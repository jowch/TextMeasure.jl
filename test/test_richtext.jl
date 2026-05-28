using Test, TextMeasure, Makie

# Validated against Makie 0.24.10. The mirrored constants (0.66, +0.40, −0.25, 20px
# line spacing) live in ext/TextMeasureMakieExt.jl; this test is their guard.
const RT_FONT = "TeX Gyre Heros Makie"
const RT_SIZE = 24.0

# Makie's own pixel bbox (width, height) for a RichText — the correctness oracle.
function makie_wh(rt)
    sc = Scene(; size = (1000, 1000))
    p  = text!(sc, Point2f(0, 0); text = rt, font = RT_FONT, fontsize = RT_SIZE)
    w  = Makie.widths(Makie.boundingbox(p, :pixel))
    return (Float64(w[1]), Float64(w[2]))
end

ours_wh(rt) =
    measure_bounds(MakieBackend(; font = RT_FONT, fontsize = RT_SIZE, px_per_unit = 1.0), rt).size

# assert our (w,h) matches Makie's within tolerance, and is finite
function check(rt)
    o = ours_wh(rt); m = makie_wh(rt)
    @test all(isfinite, o)
    @test o[1] ≈ m[1] rtol = 2e-3 atol = 0.5
    @test o[2] ≈ m[2] rtol = 2e-3 atol = 0.5
end

@testset "RichText measure_bounds vs Makie" begin
    @testset "plain & mixed font/size" begin
        check(Makie.rich("Hello"))
        check(Makie.rich("Hello, world"))
        check(Makie.rich("big ", Makie.rich("small"; fontsize = 12.0)))
        check(Makie.rich("plain ", Makie.rich("other"; font = "TeX Gyre Heros Makie Bold")))
    end
end
