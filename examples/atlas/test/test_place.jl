# SPDX-License-Identifier: MIT
using Atlas: measure_boxes, solve_frame, recompute_overlaps, FramePlacement
using Atlas: load_atlas_data
using Atlas: _unit_box, measure_label, _char_advances, _REF_PX,
             _point_style, _areal_drawn, atlas_pois, atlas_areals,
             _UNITBOX_CACHE, _CHARADV_CACHE, _SPACEADV_CACHE
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

    # partial warm-start (the real per-frame case): first 3 settled, last 3 new
    fp3 = solve_frame(ids, anchors, boxes, bounds;
                      prev    = Dict(ids[i] => fp.offsets[i] for i in 1:3),
                      settled = Set(ids[1:3]))
    @test recompute_overlaps(fp3) == 0
    for i in 1:3                                  # pinned labels keep their prior offset
        @test maximum(abs.(fp3.offsets[i] .- fp.offsets[i])) < 0.5
    end
end

@testset "measure-once cache is transparent (cached == fresh)" begin
    # The per-frame caches must return exactly what an uncached measurement would: text/font
    # fully determine a reference box at _REF_PX. Guards against a cache-keying regression
    # silently feeding wrong box sizes to the solver.
    d = load_atlas_data()
    for t in d.towns
        font, _ = _point_style(:town, t.rank ≤ 5)
        @test _unit_box(t.name, font) == measure_label(t.name, font, _REF_PX)
    end
    for poi in atlas_pois()
        font, _ = _point_style(:poi, false)
        @test _unit_box(poi.name, font) == measure_label(poi.name, font, _REF_PX)
    end
    # areal per-char advances must equal a fully-uncached recompute
    for ar in atlas_areals()
        drawn, font = _areal_drawn(ar)
        fpx, scale  = 37.0, Float32(37.0 / _REF_PX)
        sp   = Float32(measure_label("x x", font, _REF_PX)[1] - measure_label("xx", font, _REF_PX)[1])
        want = [(c == ' ' ? sp : Float32(measure_label(string(c), font, _REF_PX)[1])) * scale for c in collect(drawn)]
        @test _char_advances(drawn, font, fpx) == want
    end

    # perf-regression guard: the transparency checks above pass whether or not caching is live
    # (both sides compute the same value), so assert the caches actually filled — if a future
    # change disables memoization, this fails even though output stays correct.
    @test !isempty(_UNITBOX_CACHE)
    @test !isempty(_CHARADV_CACHE)
    @test !isempty(_SPACEADV_CACHE)
end
