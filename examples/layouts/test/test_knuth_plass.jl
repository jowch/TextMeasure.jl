# SPDX-License-Identifier: MIT
using Test, TextMeasure, TextMeasureLayouts

# Words-per-line as strings, for asserting on break structure (not pixels).
_wordlines(prep, lay) = [[prep.segments[i].str for i in l.words] for l in lay.lines]

@testset "types" begin
    m = FontMetrics(9.6, 2.4, 14.4)
    ln = JustifiedLine([1, 3], [0.0, 20.0], [15.0], 30.0, 0.5, 12.5, 9.6)
    @test ln.words == [1, 3]
    @test ln.word_x == [0.0, 20.0]
    @test ln.gap_centers == [15.0]
    @test ln.ratio == 0.5
    lay = JustifiedLayout([ln], 12.5, 100.0, m)
    @test lay.lines == [ln]
    @test lay.total_badness == 12.5
    @test lay.max_width == 100.0
    @test lay.metrics === m
end

@testset "argument validation" begin
    prep = prepare(MonospaceBackend(), "hi there")
    @test_throws ArgumentError knuth_plass(prep; max_width=0.0)
    @test_throws ArgumentError greedy_justify(prep; max_width=-5.0)
end

@testset "empty paragraph" begin
    prep = prepare(MonospaceBackend(), "")
    for lay in (knuth_plass(prep; max_width=100.0), greedy_justify(prep; max_width=100.0))
        @test isempty(lay.lines)
        @test lay.total_badness == 0.0
    end
end

# MonospaceBackend defaults: 7.2 px/char, space 7.2 px, ascent 9.6, line_advance 14.4.
@testset "coordinate frame" begin
    prep = prepare(MonospaceBackend(), "one two three four five six seven eight nine ten")
    la = prep.metrics.line_advance
    for lay in (knuth_plass(prep; max_width=80.0), greedy_justify(prep; max_width=80.0))
        @test length(lay.lines) >= 2
        for (i, l) in enumerate(lay.lines)
            @test isapprox(l.baseline, prep.metrics.ascent + (i - 1) * la; atol=1e-9)
            @test l.word_x[1] == 0.0
            @test issorted(l.word_x)                         # words left-to-right
            @test length(l.gap_centers) == length(l.words) - 1
            length(l.gap_centers) >= 2 && @test issorted(l.gap_centers)
        end
    end
end

@testset "badness model: 100*abs(r)^3 (both branches), ragged last line" begin
    prep = prepare(MonospaceBackend(), "one two three four five six seven eight nine ten")
    T = 80.0
    for lay in (greedy_justify(prep; max_width=T), knuth_plass(prep; max_width=T))
        for (i, l) in enumerate(lay.lines)
            is_last = i == length(lay.lines)
            if is_last && l.natural_width <= T
                @test l.badness == 0.0                       # ragged last line
            elseif isfinite(l.ratio) && l.badness < TextMeasureLayouts.INF_BADNESS
                @test isapprox(l.badness, 100 * abs(l.ratio)^3; rtol=1e-9, atol=1e-9)
            end
        end
    end
    # a line filled exactly to the measure has zero badness/ratio.
    p2 = prepare(MonospaceBackend(), "xxxxxxx x x and more")    # first 3 words == 79.2 px
    k = knuth_plass(p2; max_width=79.2)
    @test isapprox(k.lines[1].ratio, 0.0; atol=1e-9)
    @test isapprox(k.lines[1].badness, 0.0; atol=1e-9)
end

@testset "forced break (:newline) ⇒ ragged, NOT stretched (B1)" begin
    # "alpha beta" is forced short by the newline; at a wide measure it must stay ragged
    # (ratio 0, badness 0) — NOT scored as a stretched, underfull interior line.
    prep = prepare(MonospaceBackend(), "alpha beta\ngamma delta epsilon")
    for lay in (greedy_justify(prep; max_width=120.0), knuth_plass(prep; max_width=120.0))
        @test _wordlines(prep, lay)[1] == ["alpha", "beta"]   # break lands at the newline
        @test lay.lines[1].ratio == 0.0
        @test lay.lines[1].badness == 0.0                     # ragged, not stretched
    end
end

@testset "greedy_justify break boundaries == layout() (M1)" begin
    para = "the quick brown fox jumps over the lazy dog and then some more words here too"
    prep = prepare(MonospaceBackend(), para)
    for T in (60.0, 100.0, 180.0, 300.0)
        lay = layout(prep; max_width=T)
        gj  = greedy_justify(prep; max_width=T)
        laywords = [split(ln.str) for ln in lay.lines if !isempty(strip(ln.str))]
        @test _wordlines(prep, gj) == laywords                # same break set as layout()
    end
end

@testset "K-P optimality on a hand-derived fixture (m1)" begin
    # 4 boxes (px): 50.4, 7.2, 7.2, 50.4; glue 7.2 each; stretch_ratio 0.5 ⇒ stretch 3.6/gap.
    # Target 79.2 px. Enumerated feasible full-paragraph breaks:
    #   [1 2 3 | 4]  line1 nat = 50.4+7.2+7.2+7.2+7.2 = 79.2 (exact ⇒ r=0, b=0); line4 ragged ⇒ 0  ⇒ TOTAL 0  (OPTIMAL)
    #   [1 2 | 3 4]  line1 nat = 64.8, slack 14.4, r = 14.4/3.6 = 4 ⇒ b = 100·4³ = 6400          ⇒ greedy's choice
    #   [1 2 3 4]    nat 136.8 > 79.2, overshrink r < −1 ⇒ infeasible.
    # So the unique optimum is [1 2 3 | 4] at total badness 0.
    prep = prepare(MonospaceBackend(), "xxxxxxx x x xxxxxxx")
    k = knuth_plass(prep; max_width=79.2)
    g = greedy_justify(prep; max_width=79.2)
    @test _wordlines(prep, k) == [["xxxxxxx", "x", "x"], ["xxxxxxx"]]   # hand-derived optimum
    @test isapprox(k.total_badness, 0.0; atol=1e-6)
    @test _wordlines(prep, g) == [["xxxxxxx", "x"], ["x", "xxxxxxx"]]   # greedy differs…
    @test isapprox(g.total_badness, 6400.0; atol=1e-6)                 # …and is worse
    @test k.total_badness < g.total_badness
end

@testset "K-P total badness < greedy on the canonical paragraph (QUANTIFIED)" begin
    # Canonical river-prone paragraph; deterministic under MonospaceBackend.
    para = "The art of justified typesetting asks a deceptively simple question of " *
           "every paragraph it is given to render upon a page: where should each line " *
           "break so that the river of white space running down between the words never " *
           "pools into a distracting channel that draws the eye away from the prose " *
           "itself and toward the empty gaps instead."
    prep = prepare(MonospaceBackend(), para)
    T = 300.0
    g = greedy_justify(prep; max_width=T)
    k = knuth_plass(prep; max_width=T)
    # Observed (locked 2026-05-28): greedy 3529.4375, K-P 1255.3371, gap ≈ 2274.1.
    # MARGIN is a LOOSE floor well below the observed gap (not re-derived from the run).
    MARGIN = 1000.0
    @test k.total_badness < g.total_badness - MARGIN
    # both layouts stay in the feasible regime at this comfortable measure (no INF lines).
    @test all(l -> l.badness < TextMeasureLayouts.INF_BADNESS, g.lines)
    @test all(l -> l.badness < TextMeasureLayouts.INF_BADNESS, k.lines)
end
