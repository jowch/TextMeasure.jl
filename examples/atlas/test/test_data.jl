using Atlas: load_atlas_data, project_point, PHI0, KX
using Test

@testset "data: projection + load" begin
    # cos φ0 x-correction is a pure affine: x scales by kx, y unchanged.
    x0, y0 = project_point(-121.0, 35.5)
    x1, y1 = project_point(-120.0, 35.5)
    @test y0 == 35.5
    @test isapprox(x1 - x0, KX * 1.0; atol=1e-9)     # 1° lon → kx map-units

    d = load_atlas_data()
    @test length(d.towns) ≥ 19
    @test allunique(t.town_id for t in d.towns)
    @test any(t.name == "San Luis Obispo" for t in d.towns)
    @test count(t -> t.source == "NE", d.towns) == 7   # Fresno excluded (off-subject)
    @test length(d.coastline) ≥ 1 && sum(length, d.coastline) ≥ 400   # 10m, not 50m
end
