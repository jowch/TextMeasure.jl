using Atlas: atlas_pois, atlas_areals, POI, Areal, measure_boxes
using GeometryBasics: Point2f, Rect2f
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
    @test all(a -> isfinite(a.sweep), areals)         # curvature (deg, 0 = straight)
    @test all(a -> a.tracking >= 0, areals)           # per-glyph breathing fraction

    # every areal's text box is MEASURABLE (positive w,h) — size is dynamic now,
    # so measure at a representative reference size.
    for a in areals
        box = only(measure_boxes([a.text]; fontsize = 44.0))
        @test box[1] > 0 && box[2] > 0
    end
end

@testset "areals: curved per-glyph layout (measured along an arc)" begin
    anchor = Point2f(700, 500)
    fpx    = 80.0
    for a in atlas_areals()
        drawn, _ = Atlas._areal_drawn(a)
        glyphs, boxes = Atlas._areal_glyphs(a, anchor, fpx)

        # one glyph per drawn character; obstacle boxes are subsampled by the stride
        N = length(collect(drawn))
        @test length(glyphs) == N
        @test length(boxes)  == N                         # full per-glyph boxes returned
        @test all(b -> b isa Rect2f, boxes)
        # glyph boxes are positive and ~font_px tall (measured advance × fpx)
        @test all(b -> b.widths[1] > 0 && b.widths[2] ≈ Float32(fpx), boxes)

        # the assembled obstacle list subsamples every _AREAL_OBSTACLE_STRIDE-th glyph,
        # so a frame's areal obstacle count ≈ N / stride (not one big AABB).
        n_sub = length(1:Atlas._AREAL_OBSTACLE_STRIDE:N)
        @test 0 < n_sub <= N
    end

    # a curved areal (sweep≠0) bends: its glyph rotations are NOT all equal,
    # while a straight one (sweep=0) keeps a single rotation.
    curved   = first(filter(a -> abs(a.sweep) >= 0.5, atlas_areals()))
    gly, _   = Atlas._areal_glyphs(curved, anchor, fpx)
    rots     = [g[3] for g in gly]
    @test maximum(rots) - minimum(rots) > 1e-3            # actually curved
end
