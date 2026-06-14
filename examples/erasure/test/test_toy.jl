using Erasure: new_toy, toggle!, poem_readout, surprise!, KEPT_WORDS
using Test

@testset "toy" begin
    @testset "defaults to the curated poem" begin
        t = new_toy()                                  # no args -> curated hero kept-set
        @test poem_readout(t) == join(KEPT_WORDS, " ")
    end

    @testset "toggle is O(1) over cached geometry (no re-measure)" begin
        t = new_toy()
        before = length(t.boxes)                       # geometry built once
        segi = t.boxes[1].seg_index                    # word #1 ("Permission"), already kept
        toggle!(t, segi)                               # now blacked
        @test !(segi in t.kept)
        @test length(t.boxes) == before                # geometry NOT rebuilt
        toggle!(t, segi)                               # back to kept
        @test segi in t.kept
    end

    @testset "surprise! is opt-in, deterministic under a seed, and never empty" begin
        t = new_toy()
        surprise!(t; seed = 7)
        p1 = poem_readout(t)
        surprise!(t; seed = 7)
        @test poem_readout(t) == p1                    # seeded determinism
        @test !isempty(strip(p1))                      # produces *a* poem
    end
end
