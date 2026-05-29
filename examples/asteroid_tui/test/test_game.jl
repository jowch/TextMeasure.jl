# SPDX-License-Identifier: MIT
using AsteroidTUI: new_game, tick!, Input, CHARGE_MAX, kill_ship!, ship_visible,
                   aim_heading
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
    tick!(g2, Input(fire=false)); @test !isempty(g2.projectiles) && g2.ship.charge == 0
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
    n0 = length(g.asteroids); d0 = hypot(b.x - a.x, b.y - a.y)
    @test d0 < a.radius + b.radius
    tick!(g, Input())
    @test length(g.asteroids) == n0                       # bounce, not fracture
    a2,b2 = g.asteroids[1], g.asteroids[2]; d1 = hypot(b2.x - a2.x, b2.y - a2.y)
    @test d1 >= d0                                         # pushed apart
    @test all(a -> -a.radius <= a.x <= g.width + a.radius &&
                   -a.radius <= a.y <= g.height + a.radius, g.asteroids)  # push-apart clamps within despawn bounds
end

@testset "high closing speed fractures both" begin
    g = new_game(Xoshiro(3); width=120, height=40, n_asteroids=2)
    a, b = g.asteroids[1], g.asteroids[2]
    a.x=60.0; a.y=20.0; a.vx=2.0; a.vy=0.0
    b.x=60.0+(a.radius+b.radius)*0.5; b.y=20.0; b.vx=-2.0; b.vy=0.0     # head-on, high closing
    shards0 = length(g.shards)
    tick!(g, Input())
    # Both original asteroids fracture into shards; _replenish_field! adds exactly 1 back.
    @test length(g.shards) > shards0
    @test length(g.asteroids) == 1                           # 0 from fracture + 1 from replenish = exactly 1
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

@testset "fire launches a charge-sized burst" begin
    g = new_game(Xoshiro(1); n_asteroids=0)
    for _ in 1:20; tick!(g, Input(fire=true)); end
    @test g.ship.charge == CHARGE_MAX
    tick!(g, Input(fire=false))
    @test g.ship.charge == 0
    @test length(g.projectiles) == 1 + CHARGE_MAX        # burst = 1 + charge
end

@testset "projectile fractures an asteroid it reaches" begin
    g = new_game(Xoshiro(3); width=120, height=40, n_asteroids=1)
    g.ship.invuln = 1_000_000
    a = g.asteroids[1]
    g.ship.x = 60.0; g.ship.y = 30.0; g.ship.φ = 0.0     # firing straight up
    a.x = 60.0; a.y = 5.0; a.vx = 0.0; a.vy = 0.0          # rock near the top, dead ahead
    shards0 = length(g.shards)
    for _ in 1:20; tick!(g, Input(fire=true)); end          # charge to max
    tick!(g, Input(fire=false))                             # launch the burst upward
    for _ in 1:30; tick!(g, Input()); end                   # bullets travel up into the rock
    @test length(g.shards) > shards0                        # it got fractured (shards spawned)
end

@testset "projectiles do not wrap — despawn off-screen" begin
    g = new_game(Xoshiro(3); n_asteroids=0)
    g.ship.x = 60.0; g.ship.y = 20.0; g.ship.φ = 0.0
    tick!(g, Input(fire=true)); tick!(g, Input(fire=false))  # one bullet, heading up
    for _ in 1:60; tick!(g, Input()); end                    # it flies off the top
    @test isempty(g.projectiles)                             # gone, not wrapped to the bottom
end

@testset "field replenish restores count to N" begin
    N = 4
    g = new_game(Xoshiro(3); width=120, height=40, n_asteroids=N)
    g.ship.invuln = 1_000_000                  # keep ship alive; don't perturb the test
    empty!(g.asteroids)
    tick!(g, Input())
    @test length(g.asteroids) == 1             # one spawned per tick
    # _replenish_field! runs LAST in tick! (after _advance_asteroids!), so the just-spawned
    # asteroid is still exactly on its edge this tick — assert it here, before it drifts.
    a = g.asteroids[1]
    @test a.x == 0.0 || a.x == g.width || a.y == 0.0 || a.y == g.height
    for _ in 1:10; tick!(g, Input()); end
    @test length(g.asteroids) == N             # caps at N (g.n_target), never exceeds
end

@testset "asteroids do not wrap — they leave and despawn off-screen" begin
    g = new_game(Xoshiro(3); width=120, height=40, n_asteroids=1)
    g.ship.invuln = 1_000_000        # keep ship out of it
    g.n_target = 0                   # disable replenish so we can observe the despawn
    a = g.asteroids[1]
    a.x = 2.0; a.y = 20.0; a.vx = -1.0; a.vy = 0.0   # heading off the LEFT edge
    for _ in 1:40; tick!(g, Input()); end
    @test isempty(g.asteroids)       # gone — NOT wrapped around to x≈width
end

@testset "shards do not wrap — they leave and despawn" begin
    g = new_game(Xoshiro(3); width=120, height=40, n_asteroids=0)
    g.ship.invuln = 1_000_000; g.n_target = 0
    # hand-make a shard heading off the top edge (use the real Shard constructor field
    # order you read in entities.jl: poly,x,y,vx,vy,prep,ttl,radius)
    a = AsteroidTUI.new_game(Xoshiro(7); n_asteroids=1).asteroids[1]   # borrow a prep+poly
    push!(g.shards, AsteroidTUI.Shard(a.poly, 60.0, 2.0, 0.0, -1.0, a.prep, 1000, 4.0))
    for _ in 1:40; tick!(g, Input()); end
    @test isempty(g.shards)          # despawned off the top, did not wrap to the bottom
end

@testset "ship still wraps" begin
    g = new_game(Xoshiro(3); width=120, height=40, n_asteroids=0)
    g.ship.x = 0.5; g.ship.y = 20.0
    for _ in 1:8; tick!(g, Input(left=true)); end   # strafe left, crosses x=0
    @test 0 <= g.ship.x <= g.width                  # wrapped, stayed in range
end
