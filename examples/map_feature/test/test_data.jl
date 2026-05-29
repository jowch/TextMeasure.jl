# SPDX-License-Identifier: MIT
using Test, MapFeature
using GeometryBasics: Point2

const DATA = joinpath(pkgdir(MapFeature), "data")

@testset "load_vermont: bundled shapefile, no network" begin
    poly = load_vermont()
    @test poly isa Vector{Point2{Float64}}
    @test length(poly) >= 1000                      # VT 500k ring ≈ 1634 pts (floor, not hard count)
    xs = first.(poly); ys = last.(poly)
    @test -74.0 <= minimum(xs) && maximum(xs) <= -71.0    # VT longitude window
    @test 42.0 <= minimum(ys) && maximum(ys) <= 45.5      # VT latitude window
end

@testset "load_pois / load_stats: bundled TOML" begin
    pois = load_pois(joinpath(DATA, "pois.toml"))
    @test 8 <= length(pois) <= 15
    @test count(p -> p.kind === :capital, pois) == 1
    @test any(p -> p.name == "Burlington" && p.kind === :city, pois)
    stats = load_stats(joinpath(DATA, "pois.toml"))
    @test stats[:population] > 100_000
    @test stats[:capital] == "Montpelier"
    @test stats[:masthead] == "VERMONT"
end
