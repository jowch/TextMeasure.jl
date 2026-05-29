# SPDX-License-Identifier: MIT
using AsteroidTUI: new_game, tick!, Input, CHARGE_MAX, kill_ship!, ship_visible
using Random
using Test

@testset "tick! physics" begin
    g = new_game(Xoshiro(42); width=120, height=40, n_asteroids=3)
    # thrust changes velocity then position; world wraps (stays in-bounds)
    for _ in 1:5; tick!(g, Input(thrust=true)); end
    @test (g.ship.vx, g.ship.vy) != (0.0, 0.0)
    @test 0 <= g.ship.x <= g.width && 0 <= g.ship.y <= g.height
    # rotation
    φ0 = g.ship.φ; tick!(g, Input(left=true)); @test g.ship.φ != φ0
    # charge ramps while fire held, caps at CHARGE_MAX
    g2 = new_game(Xoshiro(1))
    for _ in 1:20; tick!(g2, Input(fire=true)); end
    @test g2.ship.charge == CHARGE_MAX
    # release launches a beam and resets charge
    tick!(g2, Input(fire=false))
    @test g2.beam.active && g2.ship.charge == 0
    # asteroids advanced + rotated
    g3 = new_game(Xoshiro(5)); a = g3.asteroids[1]; θ0 = a.θ
    tick!(g3, Input()); @test g3.asteroids[1].θ != θ0
    # debug toggles on a debug-edge
    g4 = new_game(Xoshiro(2)); @test !g4.debug; tick!(g4, Input(debug=true)); @test g4.debug
    @test g3.tick_count == 1
end

@testset "respawn + invuln" begin
    g = new_game(Xoshiro(8))
    kill_ship!(g)
    @test !g.ship.alive
    # respawn after the death timer; gains invulnerability
    for _ in 1:65; tick!(g, Input()); end
    @test g.ship.alive && g.ship.invuln > 0
    # invuln blink: visibility alternates over ticks
    vis = [ (tick!(g, Input()); ship_visible(g)) for _ in 1:8 ]
    @test any(vis) && any(!, vis)
end
