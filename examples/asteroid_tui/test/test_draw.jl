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
    # directional ship glyph (φ-nose, 8-way octant)
    g.debug = false
    g.ship.alive = true; g.ship.invuln = 0; g.ship.charge = 0
    g.ship.x = 40.0; g.ship.y = 12.0
    sx = round(Int, g.ship.x); sy = round(Int, g.ship.y)
    # φ=0 ⇒ nose-up; the OLD wings (╱╲) and plume (┃) must be GONE.
    g.ship.φ = 0.0
    b0 = CellBuffer(g.height, g.width); draw!(b0, g)
    @test b0.chars[sy, sx]     == '▮'            # hull at centre
    @test b0.chars[sy - 1, sx] == '▲'            # nose one cell up
    @test b0.chars[sy, sx - 1] != '╱' && b0.chars[sy, sx + 1] != '╲'   # wings removed
    @test b0.chars[sy + 1, sx] != '┃'            # downward plume removed
    # φ=π/2 ⇒ facing RIGHT ⇒ nose '▶' one cell to the right (catches a CCW octant table)
    g.ship.φ = π/2
    b1 = CellBuffer(g.height, g.width); draw!(b1, g)
    @test b1.chars[sy, sx + 1] == '▶'
    # φ=π/4 ⇒ NE ⇒ nose '◥' one cell up-right
    g.ship.φ = π/4
    bne = CellBuffer(g.height, g.width); draw!(bne, g)
    @test bne.chars[sy - 1, sx + 1] == '◥'
    # charge>0 ⇒ the charge glyph sits one cell BEYOND the nose along φ
    g.ship.φ = 0.0; g.ship.charge = 1
    bc = CellBuffer(g.height, g.width); draw!(bc, g)
    @test bc.chars[sy - 2, sx] == AsteroidTUI.CHARGE_GLYPH[2]    # charge 1 ⇒ CHARGE_GLYPH[1+1], two cells up at φ=0
    g.ship.charge = 0                                 # reset so later asserts (if any) aren't perturbed
end
