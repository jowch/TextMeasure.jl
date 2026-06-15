# SPDX-License-Identifier: MIT
using Tide
using Tide: press_at, DIRECTIONS, N_FRAMES, FRAMES_PER_PRESS, N_PRESSES
using Test

# The 6-press CCW tide sweep drives the loop. These pin its load-bearing properties: a seamless,
# infinitely loopable cycle (frame N ≡ 0), the CCW direction order, normalized depth ∈ [0,1]
# following ONE continuous pulse per press (monotone up on [0,½], a single flat-but-moving crest
# at u=½, monotone down on [½,1] — NO constant plateau), zero-velocity at both troughs (so presses
# join without a jerk), and depth==0 EXACTLY at every trough. All arithmetic — no backend, no font.
@testset "schedule: 6-press CCW sweep, continuous flat-crest pulse, seamless loop" begin
    @testset "seamless loop: press_at(N_FRAMES) == press_at(0); frame 0 is a bare trough" begin
        @test press_at(N_FRAMES) == press_at(0)
        d0, dep0, ph0 = press_at(0)
        @test d0 === :W
        @test dep0 == 0.0                       # frame 0 is a true rest trough
        @test ph0 == 0.0
        # the LAST frame has fully withdrawn (depth 0) so N-1 → 0 is seamless.
        _, depN1, _ = press_at(N_FRAMES - 1)
        @test depN1 < 1e-3
    end

    @testset "6 presses in CCW order W,SW,SE,E,NE,NW; N = presses × frames-per-press" begin
        @test DIRECTIONS == (:W, :SW, :SE, :E, :NE, :NW)
        @test N_PRESSES == 6
        @test length(DIRECTIONS) == N_PRESSES
        @test N_FRAMES == N_PRESSES * FRAMES_PER_PRESS
        for p in 0:(N_PRESSES - 1)
            f = p * FRAMES_PER_PRESS + FRAMES_PER_PRESS ÷ 2     # mid-press (the crest)
            dir, _, _ = press_at(f)
            @test dir === DIRECTIONS[p + 1]
        end
    end

    @testset "depth ∈ [0,1] every frame" begin
        for f in 0:(N_FRAMES - 1)
            _, depth, _ = press_at(f)
            @test 0.0 <= depth <= 1.0 + 1e-9
        end
    end

    @testset "depth==0 EXACTLY at each trough (press boundaries)" begin
        for p in 0:(N_PRESSES - 1)
            _, depth, _ = press_at(p * FRAMES_PER_PRESS)
            @test depth == 0.0
        end
    end

    @testset "continuous pulse: monotone up/down, single crest at u=½, flat-but-moving (no plateau)" begin
        p = 1                                    # the SW press (all share the schedule)
        base = p * FRAMES_PER_PRESS
        depthof(l) = press_at(base + l)[2]
        fpp  = FRAMES_PER_PRESS
        half = fpp ÷ 2                           # crest frame (u = 0.5)

        # MONOTONE UP over [0, half], MONOTONE DOWN over [half, fpp-1].
        for l in 0:(half - 1)
            @test depthof(l + 1) >= depthof(l) - 1e-12
        end
        for l in half:(fpp - 2)
            @test depthof(l + 1) <= depthof(l) + 1e-12
        end

        # SINGLE CREST: depth(½) == 1 exactly, and it is the unique max.
        @test depthof(half) == 1.0
        @test depthof(half) >= maximum(depthof(l) for l in 0:(fpp - 1))

        # NO SUSTAINED PLATEAU: depth is strictly < 1 just off the crest (here u = 0.5 ± 0.05).
        off = round(Int, 0.05 * fpp)
        @test depthof(half - off) < 1.0 - 1e-4
        @test depthof(half + off) < 1.0 - 1e-4

        # FLAT-BUT-MOVING crest: the per-frame velocity near the crest is tiny (almost stopped)
        # yet NON-zero just off the exact peak (it never literally holds).
        @test abs(depthof(half - off) - depthof(half - off - 1)) < 5e-3   # nearly stopped
        @test depthof(half - 1) < 1.0                                     # still moving (< 1)
        @test depthof(half - 1) > depthof(half - off)                     # strictly creeping up

        # ZERO velocity at both troughs (smootheststep is flat there): per-frame Δ ≈ 0.
        @test abs(depthof(1) - depthof(0)) < 1e-3                          # slow-in at the start
        @test abs(depthof(fpp - 1) - depthof(fpp - 2)) < 1e-3             # slow-out at the end
    end

    @testset "phase completes one full cycle (frame N ≡ 0)" begin
        for f in 0:(N_FRAMES - 1)
            _, _, ph = press_at(f)
            @test isapprox(ph, 2π * f / N_FRAMES; atol = 1e-9)
        end
    end
end
