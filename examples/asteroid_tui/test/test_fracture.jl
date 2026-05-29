# SPDX-License-Identifier: MIT
using AsteroidTUI: new_game, tick!, Input, fracture_asteroid!, GameState,
                   Asteroid, CellBackend, _word_boundary_splits
import TextMeasure
import GeometryBasics as GB
using Random
using Test

# helper: words (in order) of a Prepared
words(p) = [s.str for s in p.segments if s.kind === :word]

@testset "word-boundary fracture preserves glyphs" begin
    g = new_game(Xoshiro(11); n_asteroids=1)
    a = g.asteroids[1]
    original = words(a.prep)
    impact = GB.Point2{Float64}(0.0, 0.0)
    fracture_asteroid!(g, 1, impact)
    @test isempty(g.asteroids)                       # the hit asteroid is removed
    @test length(g.shards) >= 2                       # at least two shard-prose chunks
    # concatenating shard words in shard order reproduces the original word order
    rebuilt = vcat((words(sh.prep) for sh in g.shards)...)
    @test rebuilt == original                         # no drops, no dups, in order
    @test g.last_hit_glyphs == original
end

# MAJOR #3: short prose (few words) + a high requested shard count must NOT produce
# empty/mismatched ranges or silently truncate via zip. Drive the collision path.
@testset "fracture: short prose, high shard count (no silent truncation)" begin
    # _word_boundary_splits invariants directly: 3 words, ask for 4 chunks.
    prep3 = TextMeasure.prepare(CellBackend(), "alpha beta gamma")
    for n in 1:6
        rs = _word_boundary_splits(prep3, n)
        @test all(!isempty, rs)                                  # no empty range
        @test first(first(rs)) == 1                              # tile starts at 1
        @test last(last(rs)) == length(prep3.segments)           # tile ends at last seg
        for j in 2:length(rs)                                    # contiguous, no gaps
            @test first(rs[j]) == last(rs[j-1]) + 1
        end
        rebuilt = vcat(([s.str for s in prep3.segments[r] if s.kind === :word] for r in rs)...)
        @test rebuilt == ["alpha", "beta", "gamma"]              # lossless, in order
    end

    # Full fracture with a deliberately short-prose asteroid and n_shards path.
    g = new_game(Xoshiro(99); n_asteroids=1)
    short_prep = TextMeasure.prepare(CellBackend(), "iron ore here")   # 3 words
    a = g.asteroids[1]
    g.asteroids[1] = Asteroid(a.poly, a.x, a.y, a.vx, a.vy, a.ω, a.θ, a.radius, short_prep, a.age)
    orig = words(g.asteroids[1].prep)
    fracture_asteroid!(g, 1, GB.Point2{Float64}(0.0, 0.0))
    @test !isempty(g.shards)
    rebuilt = vcat((words(sh.prep) for sh in g.shards)...)
    @test rebuilt == orig                                        # every glyph once, in order
end

@testset "fracture: off-centre rim impact (frame conversion, no truncation)" begin
    g = new_game(Xoshiro(11); n_asteroids=1)
    a = g.asteroids[1]
    original = words(a.prep)
    nword = count(s -> s.kind === :word, a.prep.segments)
    requested = 2 + (nword >= 6 ? 2 : 0)
    impact = GB.Point2{Float64}(a.radius * 0.8, 0.0)     # cell-space offset near the rim
    fracture_asteroid!(g, 1, impact)
    @test isempty(g.asteroids)
    rebuilt = vcat((words(sh.prep) for sh in g.shards)...)
    @test rebuilt == original                            # lossless
    @test g.last_hit_glyphs == original
    @test length(g.shards) == requested                  # seeds landed INSIDE ⇒ no truncation
end
