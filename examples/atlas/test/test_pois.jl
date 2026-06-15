using Atlas: atlas_pois, atlas_areals, POI, Areal, measure_boxes
using GeometryBasics: Point2f
using Test

@testset "pois: anchored landmarks + measurable areals" begin
    pois = atlas_pois()
    @test !isempty(pois)
    @test all(p -> p isa POI, pois)
    @test all(p -> p.pos isa Point2f, pois)
    @test all(p -> p.kind === :landmark, pois)

    areals = atlas_areals()
    @test !isempty(areals)
    @test all(a -> a isa Areal, areals)
    @test all(a -> a.kind in (:water, :range), areals)
    @test all(a -> a.ground > 0, areals)              # geographic em (degrees)
    @test all(a -> a.max_px > 0, areals)              # upper hand-off band

    # every areal's text box is MEASURABLE (positive w,h) — size is dynamic now,
    # so measure at a representative reference size.
    for a in areals
        box = only(measure_boxes([a.text]; fontsize = 44.0))
        @test box[1] > 0 && box[2] > 0
    end
end
