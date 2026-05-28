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

    @testset "sub/superscript" begin
        check(Makie.rich("x", Makie.superscript("2")))
        check(Makie.rich("H", Makie.subscript("2"), "O"))
        check(Makie.rich("e", Makie.superscript("iπ"), " + 1"))
    end

    @testset "subsup / leftsubsup" begin
        check(Makie.rich("x", Makie.subsup("i", "2")))           # sub="i", super="2"
        check(Makie.rich("M", Makie.left_subsup("a", "b"), "z"))
        # node-level :fontsize / :font on the subsup node itself (must be read from rt.attributes)
        check(Makie.rich("x", Makie.subsup("i", "2"; fontsize = 30.0)))
        check(Makie.rich("x", Makie.subsup("i", "2"; font = "TeX Gyre Heros Makie Bold")))
    end

    @testset "multi-line" begin
        # top-level newlines
        check(Makie.rich("line one\nline two"))
        check(Makie.rich("a\nbb\nccc"))
        check(Makie.rich("top\n", Makie.superscript("x")))
        # newlines nested inside spans — the line drop must persist across the span boundary
        check(Makie.rich(Makie.rich("x\n"), "y"))
        check(Makie.rich(Makie.rich("a\nb"), "c"))
        check(Makie.rich("pre ", Makie.rich("inner\nnext", fontsize = 18.0), " post"))
        # leading newline — exercises the `drop` increment with no preceding glyph
        check(Makie.rich("\nx"))
    end

    @testset "rejects unrenderable inputs" begin
        # Makie itself errors on '\n' inside a subsup child; mirror that so a measure_bounds
        # call fails identically to a text! render attempt.
        b = MakieBackend(; font = RT_FONT, fontsize = RT_SIZE, px_per_unit = 1.0)
        @test_throws ArgumentError measure_bounds(b, Makie.rich("x", Makie.subsup("a\nb", "c")))
        @test_throws ArgumentError measure_bounds(b, Makie.rich("x", Makie.left_subsup("a", "b\n")))
        # px_per_unit != 1 would mix scaled glyphs with the unscaled 20 px line drop.
        @test_throws ArgumentError measure_bounds(
            MakieBackend(; font = RT_FONT, fontsize = RT_SIZE, px_per_unit = 2.0),
            Makie.rich("x"))
    end

    @testset "degenerate inputs" begin
        # rich("") — Makie crashes with a TypeError in GlyphCollection on this version,
        # so we cannot use check(). Assert our own contract: finite (0,0) box.
        let o = ours_wh(Makie.rich(""))
            @test all(isfinite, o)
            @test o == (0.0, 0.0)
        end
        check(Makie.rich(" "))                   # whitespace-only — matches Makie exactly
        check(Makie.rich("a", Makie.rich("")))   # empty nested span — matches Makie exactly
    end
end
