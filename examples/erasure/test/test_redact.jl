using Erasure: word_boxes, redaction_rects, RedactRect
using TextMeasure: prepare, MonospaceBackend
using Test

@testset "redact" begin
    @testset "consecutive blacked words tile into one continuous bar" begin
        b = MonospaceBackend(fontsize = 11.0)
        prep = prepare(b, "alpha beta gamma")     # 3 words, all blacked (kept = empty)
        boxes = word_boxes(prep; max_width = Inf)
        rects = redaction_rects(boxes, prep, Int[]; bleed = 1.0)
        # all three words on one line, no kept words -> one merged bar
        @test length(rects) == 1
        r = rects[1]
        @test r.x0 < boxes[1].x0 + 1e-9                  # bleed at/left of first word
        @test r.x1 > boxes[3].x1 - 1e-9                  # covers through last word
        # spans the full inter-word gaps (no holes): width >= last.x1 - first.x0
        @test r.x1 - r.x0 >= (boxes[3].x1 - boxes[1].x0)
    end

    @testset "a kept word splits the bar and keeps its space paper" begin
        b = MonospaceBackend(fontsize = 11.0)
        prep = prepare(b, "alpha beta gamma")
        boxes = word_boxes(prep; max_width = Inf)
        kept = [boxes[2].seg_index]                       # keep "beta"
        rects = redaction_rects(boxes, prep, kept; bleed = 1.0)
        @test length(rects) == 2                          # bar before + bar after "beta"
        # neither bar overlaps the kept word's run (its adjacent spaces are paper)
        for r in rects
            @test !(r.x0 < boxes[2].x1 && r.x1 > boxes[2].x0)
        end
    end
end
