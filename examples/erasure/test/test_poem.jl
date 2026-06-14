using Erasure: LICENSE_TEXT, KEPT_WORDS, kept_seg_indices
using TextMeasure: prepare, MonospaceBackend
using Test

@testset "poem" begin
    @testset "every kept word is a real word of the LICENSE, in order" begin
        b = MonospaceBackend(fontsize = 11.0)
        prep = prepare(b, LICENSE_TEXT)
        words = [s.str for s in prep.segments if s.kind === :word]
        idxs  = kept_seg_indices(prep)
        @test length(idxs) == length(KEPT_WORDS)
        @test issorted(idxs)                       # reading order preserved
        @test allunique(idxs)
        for (k, segi) in zip(KEPT_WORDS, idxs)
            @test prep.segments[segi].kind === :word
            @test prep.segments[segi].str == k     # exact word at that segment
        end
    end
end
