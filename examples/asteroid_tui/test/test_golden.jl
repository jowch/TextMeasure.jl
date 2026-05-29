# SPDX-License-Identifier: MIT
using AsteroidTUI: new_game, tick!, draw!, Input, ScriptedInput, next_input!, CellBuffer,
                   checksum, to_text
using Random
using Test

const GOLDEN_DIR = joinpath(@__DIR__, "golden")

# Deterministic 60-tick scenario: charge straight up to max, release to fire, then
# drift. The ship starts at the buffer center facing up (φ=0), so the beam travels
# straight up the column; `_run_golden` parks asteroid 1 directly in that column so
# the hit is GUARANTEED and deterministic (exercising voronoi_shatter + subprep).
# MINOR #6: the drift rng is hoisted OUT of the loop so it actually varies tick to
# tick (re-seeding inside would give a constant thrust — deterministic but misleading).
function _scripted_seq()
    seq = Input[]
    drift_rng = Xoshiro(99)
    for _ in 1:10; push!(seq, Input(fire=true));  end          # charge to max (caps at 5)
    push!(seq, Input(fire=false))                              # release → launch beam up
    for _ in 1:49; push!(seq, Input(thrust=(rand(drift_rng) > 0.5))); end
    return seq
end

function _run_golden()
    # Showcase scene tuned to read cleanly as a presentation frame (operator's
    # README-quality bar): 3 asteroids (uncrowded) at seed 45, which is verified to
    # produce ZERO cross-entity glyph collisions and ZERO off-screen clipping at
    # tick 60, so every label is individually legible (no run-together mangling, no
    # orphaned edge fragments). The fracture still happens (shards scatter outward —
    # see fracture_asteroid!), so the frame shows intact prose-asteroids plus a clean
    # exploded-shard cluster.
    g = new_game(Xoshiro(45); width=120, height=40, n_asteroids=3)
    # Park asteroid 1 directly above the ship, stationary, so the straight-up beam
    # reliably intersects it (deterministic fracture). Asteroid is mutable.
    a = g.asteroids[1]
    a.x = g.ship.x; a.y = g.ship.y - 6.0
    a.vx = 0.0; a.vy = 0.0; a.ω = 0.0
    a.radius = max(a.radius, 5.0)
    si = ScriptedInput(_scripted_seq())
    buf = CellBuffer(g.height, g.width)
    for _ in 1:60
        tick!(g, next_input!(si))
    end
    draw!(buf, g)
    return g, buf
end

@testset "golden frame (60 ticks)" begin
    g, buf = _run_golden()
    @test length(g.shards) >= 2                       # a fracture happened in-run
    cs = checksum(buf)
    golden_path = joinpath(GOLDEN_DIR, "frame60.sha256")
    if get(ENV, "UPDATE_GOLDEN", "") == "1"
        mkpath(GOLDEN_DIR)
        write(golden_path, cs)
        write(joinpath(GOLDEN_DIR, "frame60.txt"), to_text(buf))
    end
    @test isfile(golden_path)
    @test cs == strip(read(golden_path, String))      # regression anchor

    # NOTE on glyph preservation: the order-exact "each glyph once, IN ORDER"
    # acceptance is enforced non-vacuously in test_fracture.jl
    # (`rebuilt == original` against the specific shards a fracture produces).
    # We deliberately do NOT re-check glyph order here against the time-evolved
    # shard pool (43 ticks post-fracture, shards drift/expire) — a membership test
    # at this layer would be order-insensitive and weak, so it is omitted by design.
end
