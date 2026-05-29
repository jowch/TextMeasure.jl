# SPDX-License-Identifier: MIT
using Test, MapFeature, TextMeasure
using TextMeasureLayouts: shape_pack
using GeometryBasics: Point2

# A 100×100 square obstacle sitting in the right half of a 400-wide page band.
square(x0, y0, s) = Point2{Float64}[(x0,y0),(x0+s,y0),(x0+s,y0+s),(x0,y0+s)]
PB = (0.0, 0.0, 400.0, 300.0)   # (left, top, right, bottom)

@testset "complement: square obstacle on the right ⇒ left + right intervals" begin
    poly = square(250.0, 50.0, 100.0)          # x∈[250,350], y∈[50,150]
    cf = complement_chord_fn(poly, PB)
    iv = cf(95.0, 105.0)                        # band center y=100 crosses the square
    @test iv == [(0.0, 250.0), (350.0, 400.0)]  # negative space L and R of envelope
    @test issorted(iv; by=first)
end

@testset "complement: band above polygon ⇒ full width" begin
    poly = square(250.0, 50.0, 100.0)
    cf = complement_chord_fn(poly, PB)
    @test cf(5.0, 15.0) == [(0.0, 400.0)]       # yc=10 < poly top (50): nothing carved
end

@testset "complement: band outside [top,bottom] ⇒ empty" begin
    poly = square(250.0, 50.0, 100.0)
    cf = complement_chord_fn(poly, PB)
    @test isempty(cf(-15.0, -5.0))              # above page top
    @test isempty(cf(305.0, 315.0))             # below page bottom
end

@testset "complement: obstacle spanning full width ⇒ no negative space" begin
    poly = square(0.0, 50.0, 400.0)             # x∈[0,400] fills the page width
    cf = complement_chord_fn(poly, PB)
    @test isempty(cf(95.0, 105.0))
end

@testset "complement: concave left edge ⇒ text column follows the silhouette" begin
    # Triangle whose left edge moves rightward as y increases ⇒ wider text column lower down.
    tri = Point2{Float64}[(200.0, 50.0), (350.0, 50.0), (350.0, 250.0)]
    cf = complement_chord_fn(tri, PB)
    hi = cf(70.0, 80.0)[1]                       # near top: left edge ≈ 200
    lo = cf(200.0, 210.0)[1]                     # lower: left edge moved right
    @test hi[2] < lo[2]                          # left interval widens with depth
    @test hi[1] == 0.0 && lo[1] == 0.0
end

# --- fix #1: INDEPENDENT non-overlap assertion --------------------------------------------
# The polygon's horizontal envelope at scanline `yc`, computed DIRECTLY from the polygon edges
# (NOT via complement_chord_fn). Returns (min_x, max_x) of all edge crossings at `yc`, or
# `nothing` if the scanline misses the polygon. A buggy complement_chord_fn (e.g. an under-carved
# envelope) would let words pack past `min_x` and this independent check would catch it.
function poly_envelope_at(poly, yc)
    lo = Inf; hi = -Inf; n = length(poly)
    for i in 1:n
        x1, yy1 = poly[i][1], poly[i][2]
        j = i == n ? 1 : i + 1
        x2, yy2 = poly[j][1], poly[j][2]
        if (yy1 <= yc) != (yy2 <= yc)
            x = x1 + (yc - yy1) / (yy2 - yy1) * (x2 - x1)
            lo = min(lo, x); hi = max(hi, x)
        end
    end
    return isfinite(lo) ? (lo, hi) : nothing
end

@testset "complement → shape_pack: placed words never overlap the map envelope (independent)" begin
    poly = square(250.0, 0.0, 120.0)             # obstacle x∈[250,370], y∈[0,120]
    cf = complement_chord_fn(poly, PB)
    b = MonospaceBackend()                       # deterministic widths; all words narrow
    prep = prepare(b, join(("wd$(i)" for i in 1:120), " "))
    la = prep.metrics.line_advance
    asc = prep.metrics.ascent
    pk = shape_pack(prep, cf; line_advance=la, min_chord_width=10.0)

    @test !isempty(pk.placements)
    @test isempty(pk.overflowed)                 # no :widest_row overflow word dumped at L atop the map

    for p in pk.placements
        w = prep.segments[p.segment_index].width
        yc = (p.y - asc) + la / 2                 # the band center this word was packed into
        env = poly_envelope_at(poly, yc)          # independent of cf — directly from the polygon
        env === nothing && continue               # band misses the obstacle ⇒ nothing to overlap
        el, er = env
        @test p.x + w <= el + 1e-6 || p.x >= er - 1e-6   # word lies wholly L or R of the envelope
    end
end
