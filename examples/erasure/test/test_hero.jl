using Erasure: hero, LICENSE_TEXT, KEPT_WORDS
using Test

@testset "hero" begin
    @testset "renders PNG and exposes survivor anchors in reading order" begin
        dir = mktempdir()
        path = joinpath(dir, "erasure-hero.png")
        result = hero(path)
        @test isfile(path)
        @test filesize(path) > 0
        @test read(path, 8) == UInt8[0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]
        # survivor anchors: one per kept word, strictly in reading order (line, then x)
        anchors = result.survivors            # Vector of (line, x0, x1, baseline, str)
        @test length(anchors) == length(KEPT_WORDS)
        for k in 2:length(anchors)
            a, prev = anchors[k], anchors[k-1]
            @test (a.line, a.x0) >= (prev.line, prev.x0)   # reading order monotone
        end
    end
end
