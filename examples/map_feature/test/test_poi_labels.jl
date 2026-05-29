# SPDX-License-Identifier: MIT
using Test, MapFeature
using GeometryBasics: Point2

boxes_overlap(a::LabelBox, b::LabelBox) =
    a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h

@testset "POI struct + kind validation" begin
    p = POI("Burlington", (-73.21, 44.48), :city)
    @test p.name == "Burlington"
    @test p.kind === :city
    @test_throws ArgumentError POI("X", (0.0, 0.0), :ocean)
end

@testset "place_poi_labels: no two placed labels overlap" begin
    anchors = [Point2{Float64}(100.0 + 5i, 100.0) for i in 0:6]   # clustered ⇒ naive would collide
    sizes = [(40.0, 12.0) for _ in anchors]
    boxes = place_poi_labels(anchors, sizes; offset=6.0, margin=2.0)
    placed = LabelBox[b for b in boxes if b !== nothing]
    @test length(placed) >= 1
    for i in 1:length(placed), j in (i+1):length(placed)
        @test !boxes_overlap(placed[i], placed[j])
    end
end

@testset "place_poi_labels: a label sits adjacent to its anchor" begin
    anchors = [Point2{Float64}(200.0, 200.0)]
    boxes = place_poi_labels(anchors, [(30.0, 10.0)]; offset=6.0, margin=2.0)
    b = boxes[1]
    @test b !== nothing
    @test abs(b.x - 200.0) <= 30.0 + 6.0 + 1e-6
    @test abs(b.y - 200.0) <= 10.0 + 6.0 + 1e-6
end
