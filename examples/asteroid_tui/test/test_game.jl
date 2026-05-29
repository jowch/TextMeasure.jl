# SPDX-License-Identifier: MIT
using AsteroidTUI: new_game, tick!, Input, CHARGE_MAX, kill_ship!, ship_visible,
                   _wrap_delta, aim_heading
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

@testset "wrap-aware delta" begin
    W, H = 100.0, 40.0
    dx, dy, dist = _wrap_delta(98.0, 20.0, 2.0, 20.0, W, H)   # straddle right/left edge
    @test dx == 4.0 && dy == 0.0 && dist == 4.0               # short way is +4, not -96
    dx2, dy2, _ = _wrap_delta(10.0, 5.0, 13.0, 9.0, W, H)     # no wrap needed
    @test dx2 == 3.0 && dy2 == 4.0
    _, dyv, _ = _wrap_delta(0.0, 39.0, 0.0, 1.0, W, H)        # vertical wrap
    @test dyv == 2.0
    dxt, _, _ = _wrap_delta(0.0, 0.0, 50.0, 0.0, W, H)        # tie at size/2 ⇒ +50
    @test dxt == 50.0
end

@testset "aim_heading (visual space, up=0 clockwise)" begin
    # ship at (40,12); cells ~2:1 so the row delta is doubled.
    @test isapprox(aim_heading(40.0, 12.0, 40.0, 2.0),  0.0;  atol=1e-9)   # cursor above ⇒ up
    @test isapprox(aim_heading(40.0, 12.0, 60.0, 12.0), pi/2; atol=1e-9)   # right ⇒ +π/2
    @test isapprox(abs(aim_heading(40.0, 12.0, 40.0, 22.0)), pi; atol=1e-9) # below ⇒ ±π
    @test isapprox(aim_heading(40.0, 12.0, 20.0, 12.0), -pi/2; atol=1e-9)  # left ⇒ −π/2
end
