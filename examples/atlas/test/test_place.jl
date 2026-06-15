using Atlas: measure_boxes, solve_frame, recompute_overlaps, FramePlacement
using Atlas: load_atlas_data
using GeometryBasics: Point2f, Vec2f, Rect2f
using Test

@testset "place: measure + warm-start solve + overlap recompute" begin
    # box sizes are positive and proportional to name length (measured, not guessed)
    sizes = measure_boxes(["SLO", "San Luis Obispo"]; fontsize=11.0)
    @test all(s -> s[1] > 0 && s[2] > 0, sizes)
    @test sizes[2][1] > sizes[1][1]                      # longer string → wider box

    d = load_atlas_data()
    ids     = [t.town_id for t in d.towns][1:6]
    anchors = [Point2f(100i, 100) for i in 1:6]          # forced collisions on a row
    boxes   = [Vec2f(60,14) for _ in 1:6]
    bounds  = Rect2f(0,0,800,400)

    fp = solve_frame(ids, anchors, boxes, bounds; prev=Dict{Int,Vec2f}(), settled=Set{Int}())
    @test fp isa FramePlacement
    @test recompute_overlaps(fp) == 0                    # the headline invariant
    @test length(fp.offsets) == length(ids)

    # warm-start: feeding fp's offsets back yields ~identical placement (damped)
    fp2 = solve_frame(ids, anchors, boxes, bounds;
                      prev=Dict(id => fp.offsets[i] for (i,id) in enumerate(ids)),
                      settled=Set(ids))
    @test recompute_overlaps(fp2) == 0
    @test maximum(maximum(abs.(fp.offsets[i] .- fp2.offsets[i])) for i in 1:6) < 1.0
end
