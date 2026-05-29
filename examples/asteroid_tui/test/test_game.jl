# SPDX-License-Identifier: MIT
using AsteroidTUI: new_game, tick!, Input, CHARGE_MAX, kill_ship!, ship_visible,
                   _wrap_delta, aim_heading
using Random
using Test

@testset "tick! physics" begin
    g = new_game(Xoshiro(42); width=120, height=40, n_asteroids=3)
    for _ in 1:5; tick!(g, Input(up=true)); end          # strafe imparts velocity, world wraps
    @test (g.ship.vx, g.ship.vy) != (0.0, 0.0)
    @test 0 <= g.ship.x <= g.width && 0 <= g.ship.y <= g.height
    gs = new_game(Xoshiro(42); width=120, height=40, n_asteroids=3); φ0 = gs.ship.φ
    tick!(gs, Input(left=true))
    @test gs.ship.vx != 0.0 && gs.ship.φ == φ0           # `left` STRAFES, does NOT turn
    ga = new_game(Xoshiro(42); width=120, height=40, n_asteroids=3)
    tick!(ga, Input(aim=(80.0, 5.0)))                    # aim is the cursor cell
    @test ga.ship.φ == aim_heading(ga.ship.x, ga.ship.y, 80.0, 5.0)
    φ1 = ga.ship.φ; tick!(ga, Input()); @test ga.ship.φ == φ1   # aim===nothing ⇒ φ held
    g2 = new_game(Xoshiro(1))
    for _ in 1:20; tick!(g2, Input(fire=true)); end
    @test g2.ship.charge == CHARGE_MAX
    tick!(g2, Input(fire=false)); @test g2.beam.active && g2.ship.charge == 0
    g4 = new_game(Xoshiro(2)); @test !g4.debug
    tick!(g4, Input(debug=true)); @test g4.debug         # edge: one press toggles on
    tick!(g4, Input(debug=true)); @test g4.debug         # held ⇒ NOT re-toggled (no strobe)
    tick!(g4, Input(debug=false)); tick!(g4, Input(debug=true)); @test !g4.debug  # next press toggles
end

@testset "spawn protection" begin
    g = new_game(Xoshiro(8))
    @test g.ship.invuln > 0 && ship_visible(g)           # fresh ship invulnerable AND visible at tick 0
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

@testset "asteroid bounce separates overlapping pair (below threshold)" begin
    g = new_game(Xoshiro(3); width=120, height=40, n_asteroids=2)
    a, b = g.asteroids[1], g.asteroids[2]
    a.x=50.0; a.y=20.0; a.vx=0.0; a.vy=0.0
    b.x=50.0+(a.radius+b.radius)*0.5; b.y=20.0; b.vx=-0.05; b.vy=0.0   # low closing speed
    n0 = length(g.asteroids); _,_,d0 = _wrap_delta(a.x,a.y,b.x,b.y,g.width,g.height)
    @test d0 < a.radius + b.radius
    tick!(g, Input())
    @test length(g.asteroids) == n0                       # bounce, not fracture
    a2,b2 = g.asteroids[1], g.asteroids[2]; _,_,d1 = _wrap_delta(a2.x,a2.y,b2.x,b2.y,g.width,g.height)
    @test d1 >= d0                                         # pushed apart
    @test all(a -> 0 <= a.x <= g.width && 0 <= a.y <= g.height, g.asteroids)  # re-wrap holds in-bounds
end

@testset "high closing speed fractures both" begin
    g = new_game(Xoshiro(3); width=120, height=40, n_asteroids=2)
    a, b = g.asteroids[1], g.asteroids[2]
    a.x=60.0; a.y=20.0; a.vx=2.0; a.vy=0.0
    b.x=60.0+(a.radius+b.radius)*0.5; b.y=20.0; b.vx=-2.0; b.vy=0.0     # head-on, high closing
    shards0 = length(g.shards)
    tick!(g, Input())
    @test length(g.asteroids) == 0 && length(g.shards) > shards0
end

@testset "ship dies on asteroid contact" begin
    g = new_game(Xoshiro(3); width=120, height=40, n_asteroids=1)
    g.ship.invuln = 0                                   # drop spawn protection for the test
    a = g.asteroids[1]; a.vx=0.0; a.vy=0.0; a.x=g.ship.x; a.y=g.ship.y
    tick!(g, Input())
    @test !g.ship.alive && length(g.asteroids) == 1     # death; asteroid NOT removed
    # drive until the ship respawns (asteroid pinned to a corner so the fresh,
    # invulnerable ship at centre isn't immediately re-killed). Loop-until-alive is
    # robust to respawn_in / INVULN_TICKS constant changes; 200 is a safety cap.
    for _ in 1:200
        g.asteroids[1].x=0.0; g.asteroids[1].y=0.0; tick!(g, Input())
        g.ship.alive && break
    end
    @test g.ship.alive && g.ship.invuln > 0             # respawned, invulnerable
end

@testset "invulnerable ship survives contact" begin
    g = new_game(Xoshiro(3); n_asteroids=1)             # fresh ship has invuln=INVULN_TICKS>0, so the collision is skipped
    a = g.asteroids[1]; a.vx=0.0; a.vy=0.0; a.x=g.ship.x; a.y=g.ship.y
    tick!(g, Input())
    @test g.ship.alive
end
