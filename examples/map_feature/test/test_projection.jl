# SPDX-License-Identifier: MIT
using Test, MapFeature
using GeometryBasics: Point2

@testset "PageProjection: fits polygon into the map region, preserving aspect, y-flipped" begin
    geo = Point2{Float64}[(-73.4, 42.7), (-71.5, 42.7), (-71.5, 45.0), (-73.4, 45.0)]
    region = (200.0, 40.0, 380.0, 280.0)            # (left, top, right, bottom) on the page
    pp = PageProjection(geo, region; dest="EPSG:5070")
    pts = project_polygon(pp, geo)
    xs = first.(pts); ys = last.(pts)
    @test minimum(xs) >= region[1] - 1e-6
    @test maximum(xs) <= region[3] + 1e-6
    @test minimum(ys) >= region[2] - 1e-6
    @test maximum(ys) <= region[4] + 1e-6
    # snug on the binding dimension (touches a region edge pair)
    @test isapprox(minimum(xs), region[1]; atol=1.0) || isapprox(minimum(ys), region[2]; atol=1.0)
    # y-flip: the northernmost geo point (max lat 45.0) maps to the SMALLEST page-y (top).
    north = project_point(pp, Point2{Float64}(-72.5, 45.0))
    south = project_point(pp, Point2{Float64}(-72.5, 42.7))
    @test north[2] < south[2]
end

@testset "PageProjection: aspect ratio preserved (no anisotropic stretch)" begin
    geo = Point2{Float64}[(-73.4, 42.7), (-71.5, 42.7), (-71.5, 45.0), (-73.4, 45.0)]
    region = (0.0, 0.0, 1000.0, 100.0)              # very wide region ⇒ height-bound fit
    pp = PageProjection(geo, region)
    pts = project_polygon(pp, geo)
    w = maximum(first.(pts)) - minimum(first.(pts))
    h = maximum(last.(pts)) - minimum(last.(pts))
    @test h <= 100.0 + 1e-6                          # bound by the short dimension
    @test w < 1000.0                                 # not stretched to fill the wide region
end
