using Atlas: active_ids, w_on_for, load_atlas_data
using Test

@testset "lod: ladder + hysteresis" begin
    d = load_atlas_data()
    byname = Dict(t.name => t for t in d.towns)
    slo   = byname["San Luis Obispo"]
    cambr = byname["Cambria"]
    @test w_on_for(slo)   ≥ 1.5        # a major: eligible while wide
    @test w_on_for(cambr) ≤ 0.7        # a necklace town: only near the floor

    wide = active_ids(d.towns, 2.0, Int[])
    @test slo.town_id in wide
    @test !(cambr.town_id in wide)

    tight = active_ids(d.towns, 0.35, [slo.town_id])
    @test cambr.town_id in tight && slo.town_id in tight

    # hysteresis: a town active at w just below its w_on stays active when w drifts
    # back up slightly (no flicker), but turns off past 1.08*w_on.
    w = w_on_for(cambr)
    on  = active_ids(d.towns, w*0.99, Int[])
    @test cambr.town_id in on
    still = active_ids(d.towns, w*1.05, on)        # within hysteresis band → held
    @test cambr.town_id in still
    off = active_ids(d.towns, w*1.20, on)          # past 1.08×  → dropped
    @test !(cambr.town_id in off)
end
