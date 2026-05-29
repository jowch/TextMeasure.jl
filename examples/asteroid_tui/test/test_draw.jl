# SPDX-License-Identifier: MIT
using AsteroidTUI: new_game, tick!, Input, draw!, CellBuffer, to_text, ship_visible
using Random
using Test

@testset "draw!" begin
    g = new_game(Xoshiro(21); width=80, height=24, n_asteroids=3)
    for _ in 1:10; tick!(g, Input(up=true)); end
    buf = CellBuffer(g.height, g.width)
    draw!(buf, g)
    txt = to_text(buf)
    @test length(txt) > g.width                  # something was drawn
    @test count(!=(' '), buf.chars) > 0
    # debug overlay recolors prose cells cyan (45)
    g.debug = true
    buf2 = CellBuffer(g.height, g.width); draw!(buf2, g)
    @test count(==(UInt8(45)), buf2.fg) >= count(==(UInt8(45)), buf.fg)
    # determinism: same state ⇒ same buffer
    bufA = CellBuffer(g.height, g.width); draw!(bufA, g)
    bufB = CellBuffer(g.height, g.width); draw!(bufB, g)
    @test bufA.chars == bufB.chars && bufA.fg == bufB.fg
    # single 8-way arrow ship glyph
    g.debug = false
    g.ship.alive = true; g.ship.invuln = 0; g.ship.charge = 0
    empty!(g.asteroids); empty!(g.shards); empty!(g.projectiles)   # isolate the ship
    g.ship.x = 40.0; g.ship.y = 12.0
    sx = round(Int, g.ship.x); sy = round(Int, g.ship.y)
    # single 8-way arrow at the ship cell — no separate hull or nose
    g.ship.φ = 0.0
    b0 = CellBuffer(g.height, g.width); draw!(b0, g)
    @test b0.chars[sy, sx]     == '↑'      # points up at φ=0
    @test b0.chars[sy, sx]     != '▮'      # old hull gone
    @test b0.chars[sy - 1, sx] == ' '      # no separate nose cell above
    @test b0.chars[sy + 1, sx] == ' '      # no hull/plume below
    g.ship.φ = π/2
    b1 = CellBuffer(g.height, g.width); draw!(b1, g)
    @test b1.chars[sy, sx] == '→'          # faces right (catches a CCW table)
    g.ship.φ = π/4
    b2 = CellBuffer(g.height, g.width); draw!(b2, g)
    @test b2.chars[sy, sx] == '↗'          # diagonal
    # charge indicator one cell along φ (up at φ=0)
    g.ship.φ = 0.0; g.ship.charge = 1
    bc = CellBuffer(g.height, g.width); draw!(bc, g)
    @test bc.chars[sy, sx]     == '↑'                 # ship still the arrow
    @test bc.chars[sy - 1, sx] == AsteroidTUI.CHARGE_GLYPH[2]     # charge glyph one cell ahead
    g.ship.charge = 0
end

@testset "callout hugs the asteroid prose (no far-floating box)" begin
    g = new_game(Xoshiro(5); width=100, height=40, n_asteroids=1)
    a = g.asteroids[1]
    a.x = 50.0; a.y = 6.0; a.vx = 0.0; a.vy = 0.0; a.θ = 0.0   # near the top ⇒ callout flips below
    empty!(g.shards); empty!(g.projectiles)
    cb = CellBuffer(40, 100); draw!(cb, g)
    nr, nc = size(cb.chars)
    # Scope to the interior: exclude the frame border (rows/cols 1 & last) and the
    # bottom footer, whose corner glyphs (┌/└) and prose vowels would otherwise be
    # mistaken for the callout box / asteroid prose.
    interior = 2:(nr - 1)
    icols    = 2:(nc - 1)
    proserows = [r for r in interior if any(c -> c == 'a' || c == 'e' || c == 'o' || c == 'i', cb.chars[r, icols])]
    boxrows  = [r for r in interior if any(==('┌'), cb.chars[r, icols]) || any(==('└'), cb.chars[r, icols])]
    @test !isempty(proserows) && !isempty(boxrows)
    # the callout box must sit close to the visible prose, not ~14 rows away
    gap = minimum(abs(br - pr) for br in boxrows, pr in proserows)
    @test gap <= 4
end

@testset "_rotate_poly rotates vertices by θ" begin
    p = [AsteroidTUI.GB.Point2{Float64}(1.0, 0.0)]
    r = AsteroidTUI._rotate_poly(p, π/2)
    @test isapprox(r[1][1], 0.0; atol=1e-9) && isapprox(r[1][2], 1.0; atol=1e-9)  # (1,0)→(0,1)
    @test AsteroidTUI._rotate_poly(p, 0.0)[1] == p[1]                              # θ=0 exact identity
end

@testset "asteroid silhouette rotates with θ (tumbles)" begin
    g = new_game(Xoshiro(7); width=80, height=40, n_asteroids=1)
    a = g.asteroids[1]; a.x = 40.0; a.y = 20.0
    a.θ = 0.0;  b0 = CellBuffer(40, 80); draw!(b0, g)
    a.θ = π/2;  b1 = CellBuffer(40, 80); draw!(b1, g)
    @test b0.chars != b1.chars      # the rendered shape changed — it rotated
end
