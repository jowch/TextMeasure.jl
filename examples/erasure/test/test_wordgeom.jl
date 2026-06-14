using Erasure                                   # for Erasure.LICENSE_TEXT (Step 7 real case)
using Erasure: WordBox, word_boxes
using TextMeasure: prepare, layout, MonospaceBackend
using Test

@testset "wordgeom" begin
    @testset "WordBox shape" begin
        b = MonospaceBackend(fontsize = 11.0)
        prep = prepare(b, "alpha beta")
        boxes = word_boxes(prep; max_width = Inf)
        @test eltype(boxes) == WordBox
        @test boxes[1].seg_index isa Int
        @test boxes[1].line isa Int
        @test boxes[1].x0 isa Float64
        @test boxes[1].x1 isa Float64
        @test boxes[1].baseline isa Float64
    end

    @testset "re-walk agrees with layout(prep).lines (no whitespace drift)" begin
        b = MonospaceBackend(fontsize = 11.0)
        text = "Permission is hereby granted to deal without restriction the Software"
        for mw in (Inf, 200.0, 90.0, 40.0)
            prep = prepare(b, text)
            lay  = layout(prep; max_width = mw, align = :left)
            boxes = word_boxes(prep; max_width = mw)
            # group word strings by re-walk line, in source order
            nlines = maximum(wb.line for wb in boxes)
            @test nlines == length(lay.lines)
            for ln in 1:nlines
                words = [prep.segments[wb.seg_index].str for wb in boxes if wb.line == ln]
                @test join(words, " ") == lay.lines[ln].str
            end
        end

        # REAL case: the full LICENSE at the hero wrap width must reconstruct line-for-line.
        let mw = 422.0   # == HERO_MAX_WIDTH (golden.jl); the production hero width
            prep = prepare(b, Erasure.LICENSE_TEXT)
            lay  = layout(prep; max_width = mw, align = :left)
            boxes = word_boxes(prep; max_width = mw)
            nlines = maximum(wb.line for wb in boxes)
            @test nlines == length(lay.lines)            # same line count as layout
            for ln in 1:nlines
                words = [prep.segments[wb.seg_index].str for wb in boxes if wb.line == ln]
                @test join(words, " ") == lay.lines[ln].str   # same trimmed Line.str
            end
        end
    end
end
