using Test, TextMeasure
using FreeTypeAbstraction   # exercises the real-backend → prepare → layout path

@testset "integration: prepare → layout (Monospace)" begin
    b = MonospaceBackend(fontsize=10.0, advance_ratio=1.0, lineheight_ratio=1.2)
    # 10 px/char. "one two three" wrapped to 60 px.
    lay = layout(prepare(b, "one two three"); max_width=60.0)
    @test all(l.width ≤ 60.0 || length(split(l.str)) == 1 for l in lay.lines)
    @test join([l.str for l in lay.lines], " ") == "one two three"   # words preserved in order
    @test lay.size[2] ≈ 8.0 + (length(lay.lines)-1)*12.0 + 2.0       # height matches N
end

@testset "integration: prepare → layout (FreeType backend)" begin
    b = FreeTypeBackend(; font="DejaVu Sans", fontsize=14.0)
    lay = layout(prepare(b, "the quick brown fox"); max_width=80.0)
    @test length(lay.lines) ≥ 2                      # wraps at 80 px
    @test all(isfinite(l.baseline) for l in lay.lines)
    @test lay.size[1] > 0 && lay.size[2] > 0
end
