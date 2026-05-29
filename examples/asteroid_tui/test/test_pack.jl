# SPDX-License-Identifier: MIT
using AsteroidTUI: CellBackend, pack_prose_into, PackedProse
import TextMeasure
using Silhouettes: asteroid_polygon
using Random
using Test

@testset "pack_prose_into" begin
    rng = Xoshiro(3)
    poly = asteroid_polygon(rng; n=12, lumpiness=0.3)
    prep = TextMeasure.prepare(CellBackend(), "iron rock spins fast cold dense ore here now")
    pp = pack_prose_into(poly, prep; scale=18.0, min_chord_width=3.0)
    @test pp isa PackedProse
    @test pp.rows >= 3 && pp.cols >= 3
    @test !isempty(pp.cells)                                   # (row, col, char) tuples
    # all placed cells are inside the raster bounds
    @test all(1 <= r <= pp.rows && 1 <= c <= pp.cols for (r, c, _ch) in pp.cells)
    # determinism
    pp2 = pack_prose_into(poly, prep; scale=18.0, min_chord_width=3.0)
    @test pp.cells == pp2.cells
end
