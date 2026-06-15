using Atlas: font_px, visible, band_alpha, town_ground, pixels_per_unit,
             MIN_PX, SLO_PX, POI_GROUND, load_atlas_data
using Atlas: atlas_areals
using Test

# content drawable width for the 3:2 page (1620 - 2*16 side pad) — matches assemble_frame
const _CPW = 1620 - 2 * 16   # 1588 px

@testset "lod: geographic-scaling px band" begin
    d = load_atlas_data()
    byname = Dict(t.name => t for t in d.towns)
    cambr = byname["Cambria"]                       # a minor (necklace) town

    # font_px grows as the view tightens (P grows): same feature, smaller w → bigger px
    g = town_ground(cambr.rank)
    @test font_px(g, 3.0, _CPW) < font_px(g, 0.6, _CPW)
    @test pixels_per_unit(0.6, _CPW) > pixels_per_unit(3.0, _CPW)

    # a minor town is HIDDEN wide (type too small) and SHOWN once it grows past MIN_PX
    @test !visible(font_px(g, 3.0, _CPW), Inf, false)     # tiny wide → hidden
    @test  visible(font_px(g, 0.6, _CPW), Inf, false)     # grown past floor → shown

    # Pacific Ocean SCALES WITH ALTITUDE: shown on the wide establishing shot and KEEPS growing
    # as the dive tightens — no max_px hand-off any more (render thins it via areal_recede, not by
    # hiding). With the fade-in-only band (max = Inf) it stays visible as it swells, cloud-like.
    ocean = only(filter(a -> a.text == "PACIFIC OCEAN", atlas_areals()))
    @test font_px(ocean.ground, 3.0, _CPW) < font_px(ocean.ground, 0.8, _CPW)  # grows as we dive
    @test visible(font_px(ocean.ground, 3.0, _CPW), Inf, false)                # shown wide
    @test visible(font_px(ocean.ground, 0.8, _CPW), Inf, false)                # STILL shown deeper

    @test SLO_PX ≥ MIN_PX
    @test POI_GROUND > 0
end

@testset "lod: band-opacity ramp" begin
    # fade IN: 0 at the floor, rising to 1 at MIN_PX*1.6 (smoothstep), 0 below.
    @test band_alpha(MIN_PX, Inf)             == 0.0
    @test band_alpha(MIN_PX * 0.9, Inf)       == 0.0          # below floor → 0
    @test band_alpha(MIN_PX * 1.6, Inf)       ≈ 1.0
    @test 0 < band_alpha(MIN_PX * 1.3, Inf) < 1               # mid-rise
    # monotone non-decreasing across the fade-in window
    @test band_alpha(MIN_PX * 1.1, Inf) < band_alpha(MIN_PX * 1.4, Inf)

    # fade OUT (finite max): 1 until 0.6·max, falling to 0 at max_px.
    M = 130.0
    @test band_alpha(0.6 * M, M)  ≈ 1.0
    @test band_alpha(M, M)        == 0.0
    @test band_alpha(M * 1.1, M)  == 0.0                      # above max → 0
    @test 0 < band_alpha(0.85 * M, M) < 1                     # mid-fall
    @test band_alpha(0.75 * M, M) > band_alpha(0.9 * M, M)    # decreasing toward max

    # in the steady middle (well past floor, well below max) opacity is full
    @test band_alpha(0.4 * M, M) ≈ 1.0

    # boolean visible() agrees with band_alpha>0 inside the band and outside it
    # (the closed endpoint fpx==max_px is the one boundary where they differ: visible is
    # inclusive there, band_alpha smoothsteps to exactly 0).
    @test (band_alpha(MIN_PX * 1.2, Inf) > 0) == visible(MIN_PX * 1.2, Inf, false)   # inside
    @test (band_alpha(0.95 * M, M) > 0)       == visible(0.95 * M, M, false)         # inside
    @test (band_alpha(1.2 * M, M) > 0)        == visible(1.2 * M, M, false)          # above max
    @test (band_alpha(MIN_PX * 0.5, Inf) > 0) == visible(MIN_PX * 0.5, Inf, false)   # below floor

    # SLO is pinned: render assigns it α 1.0 regardless of band (see assemble_frame).
    # Sanity: a feature held at SLO_PX with no upper bound is fully opaque.
    @test band_alpha(SLO_PX, Inf) ≥ 0.0                       # SLO_PX itself sits near floor…
    @test band_alpha(SLO_PX * 2, Inf) ≈ 1.0                   # …and any larger pinned size is full
end
