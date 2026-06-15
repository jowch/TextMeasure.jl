using Atlas: font_px, visible, town_ground, pixels_per_unit,
             MIN_PX, SLO_PX, POI_GROUND, load_atlas_data
using Atlas: atlas_areals
using Test

# content drawable width for the default 5:4 page (1350 - 2*16 side pad)
const _CPW = 1350 - 2 * 16   # 1318 px

@testset "lod: geographic-scaling px band" begin
    d = load_atlas_data()
    byname = Dict(t.name => t for t in d.towns)
    slo   = byname["San Luis Obispo"]
    cambr = byname["Cambria"]                       # a minor (necklace) town

    # font_px grows as the view tightens (P grows): same feature, smaller w → bigger px
    g = town_ground(cambr.rank)
    @test font_px(g, 3.0, _CPW) < font_px(g, 0.6, _CPW)
    @test pixels_per_unit(0.6, _CPW) > pixels_per_unit(3.0, _CPW)

    # a minor town is HIDDEN wide (type too small) and SHOWN once it grows past MIN_PX
    @test !visible(font_px(g, 3.0, _CPW), Inf, false)     # w=3 → ~3.8px < 10 → hidden
    @test  visible(font_px(g, 0.6, _CPW), Inf, false)     # w=0.6 → ~18.9px ≥ 10 → shown

    # Pacific Ocean: shown on the wide establishing shot, HANDS OFF (hidden) once it
    # outgrows its max_px deeper in the dive.
    ocean = only(filter(a -> a.text == "PACIFIC OCEAN", atlas_areals()))
    @test  visible(font_px(ocean.ground, 3.0, _CPW), ocean.max_px, false)  # ~54px in band
    @test !visible(font_px(ocean.ground, 0.8, _CPW), ocean.max_px, false)  # ~203px > 150 → off

    # SLO is pinned to a constant size — its visibility is by-construction always true
    # (assemble_frame pins it); SLO_PX is a fixed legible size, independent of w.
    @test SLO_PX ≥ MIN_PX
    @test font_px(town_ground(2), 3.0, _CPW) isa Float64   # ground table covers majors too

    # hysteresis: a label just below MIN stays shown once it was shown (widened band),
    # but a not-yet-shown label at the same px is still hidden.
    just_under = MIN_PX * 0.95
    @test  visible(just_under, Inf, true)    # shown_before → band widened down 8% → held
    @test !visible(just_under, Inf, false)   # fresh → strict MIN_PX → hidden

    # POIs use POI_GROUND and the same lower band
    @test POI_GROUND > 0
    @test !visible(font_px(POI_GROUND, 3.0, _CPW), Inf, false)  # tiny wide → hidden
end
