# SPDX-License-Identifier: MIT
using AsteroidTUI: new_game, tick!, Input, draw!, CellBuffer, to_text, ship_visible
using Random
using Test

@testset "draw!" begin
    g = new_game(Xoshiro(21); width=80, height=24, n_asteroids=3)
    for _ in 1:10; tick!(g, Input(thrust=true)); end
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
end
