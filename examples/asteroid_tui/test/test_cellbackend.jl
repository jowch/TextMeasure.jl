# SPDX-License-Identifier: MIT
using AsteroidTUI: CellBackend, pack_prose_into
import TextMeasure
using Test

@testset "CellBackend" begin
    b = CellBackend()
    @test TextMeasure.measure(b, "rock") == 4.0
    @test TextMeasure.measure(b, "") == 0.0
    @test TextMeasure.measure(b, "a b") == 3.0            # space counts as a cell
    m = TextMeasure.font_metrics(b)
    @test (m.ascent, m.descent, m.line_advance) == (1.0, 0.0, 1.0)
    # prepare/segments use it transparently
    p = TextMeasure.prepare(b, "iron ore")
    @test [s.kind for s in p.segments] == [:word, :space, :word]
    @test p.segments[1].width == 4.0 && p.segments[3].width == 3.0

    # MINOR #5: integer-cell property — two stacked lines land on ADJACENT integer
    # rows. This hinges on metrics (1,0,1) + shape_pack line_advance=1.0. Pack a
    # narrow column so the two words wrap to two lines, and assert their baselines
    # differ by exactly 1.
    using TextMeasureLayouts: shape_pack
    p2 = TextMeasure.prepare(b, "iron rock")
    # rectangle chord_fn 4 cells wide ⇒ "iron"(4) fits, "rock"(4) wraps to next line
    rect_cf(yt, yb) = [(0.0, 4.0)]
    pk = shape_pack(p2, rect_cf; line_advance = 1.0, min_chord_width = 3.0)
    word_pls = [pl for pl in pk.placements if p2.segments[pl.segment_index].kind === :word]
    @test length(word_pls) == 2
    ys = sort([pl.y for pl in word_pls])
    @test ys[2] - ys[1] == 1.0                            # adjacent integer rows
    @test all(pl -> pl.y == round(pl.y), word_pls)        # integer baselines
end
