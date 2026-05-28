# SPDX-License-Identifier: MIT
using Test, TextMeasure, TextMeasureLayouts
using GeometryBasics: Point2

# regular n-gon "circle" centered at (cx,cy), radius r, in block-top coords (y down)
function circle_poly(cx, cy, r; n=64)
    [Point2{Float64}(cx + r*cos(2π*k/n), cy + r*sin(2π*k/n)) for k in 0:n-1]
end

@testset "polygon_chord_fn: circle = single interval" begin
    cf = polygon_chord_fn(circle_poly(100.0, 100.0, 80.0))
    @test cf isa AbstractChordFn
    iv = cf(99.0, 101.0)                  # band through the center
    @test length(iv) == 1
    @test isapprox(iv[1][1], 20.0; atol=2.0)
    @test isapprox(iv[1][2], 180.0; atol=2.0)
    @test isempty(cf(0.0, 2.0))           # band above the circle
    @test issorted(iv; by=first)
end

@testset "polygon_chord_fn: concave U has two intervals" begin
    # U opening upward: two prongs + bottom bar (y increases downward).
    U = Point2{Float64}[
        (0.0, 0.0), (30.0, 0.0), (30.0, 70.0), (70.0, 70.0),
        (70.0, 0.0), (100.0, 0.0), (100.0, 100.0), (0.0, 100.0),
    ]
    cf = polygon_chord_fn(U)
    top = cf(34.0, 36.0)                  # band crossing both prongs (y=35)
    @test length(top) == 2                # left prong, right prong
    @test issorted(top; by=first)
    bottom = cf(84.0, 86.0)               # band below the bar (y=85): solid
    @test length(bottom) == 1
end

@testset "polygon_chord_fn: vertex exactly on band center is not split" begin
    # Square [0,100]x[0,100] with a triangular notch cut from the bottom edge up to a
    # tip at (50, 50). At yc=50 the notch is a single point, so the inside run is the
    # FULL width (0,100). The even-odd test fires both edges incident to (50,50),
    # yielding coincident crossings at x=50 that naive pairing would split into
    # (0,50) and (50,100). Robust merge must report ONE interval (0,100).
    poly = Point2{Float64}[
        (0.0, 0.0), (100.0, 0.0), (100.0, 100.0),
        (60.0, 100.0), (50.0, 50.0), (40.0, 100.0), (0.0, 100.0),
    ]
    cf = polygon_chord_fn(poly)
    la = 20.0; band = 3                   # band center = (band-1)*la + la/2 = 50.0 == vertex y
    iv = cf((band - 1) * la, band * la)
    @test length(iv) == 1
    @test isapprox(iv[1][1], 0.0; atol=1e-9)
    @test isapprox(iv[1][2], 100.0; atol=1e-9)
end

@testset "polygon U-shape: slivers below min_chord_width dropped" begin
    # thin prongs (width 10) + solid base; min_chord_width=24 ⇒ prong bands skipped.
    U = Point2{Float64}[
        (0.0, 0.0), (10.0, 0.0), (10.0, 70.0), (90.0, 70.0),
        (90.0, 0.0), (100.0, 0.0), (100.0, 100.0), (0.0, 100.0),
    ]
    cf = polygon_chord_fn(U)
    b = MonospaceBackend()
    prep = prepare(b, "one two three four five six")
    pk = shape_pack(prep, cf; line_advance=prep.metrics.line_advance, min_chord_width=24.0)
    @test !isempty(pk.placements)
    @test all(p -> p.y >= 70.0, pk.placements)   # only the solid base (y>=70) holds text
end
