# SPDX-License-Identifier: MIT
using Atlas
using Atlas: load_atlas_data, assemble_frame, _data_to_px, _in_rect,
             _COAST_STRIDE, _COAST_BOX, _COAST_MAX, _SIDE_PAD, _FOOTER_H, _MASTHEAD_H,
             atlas_pois
using GeometryBasics: Point2f, Vec2f, Rect2f
using Makie: limits!
import Makie
using Test

# Rebuild the frame's coastline obstacle boxes (mirror assemble_frame) so we can assert
# no drawn label box overlaps the coast, and none extends past the visible map rect.
@testset "clearance: no label touches the coast or crosses the neat-line (12 phases)" begin
    d = load_atlas_data()
    pagepx = (1620, 1080)
    cpw = pagepx[1] - 2 * _SIDE_PAD
    cph = pagepx[2] - _MASTHEAD_H - _FOOTER_H
    map_rect = Rect2f(0, 0, cpw, cph)
    town_by_id = Dict(t.town_id => t for t in d.towns)
    pois = atlas_pois()
    name_of(af, id) = af.kind_of[id] === :town ? town_by_id[id].name : pois[id - 1000].name

    function coast_boxes(ax)
        W, H = Float32.(pagepx); m = 80.0f0
        pr = Rect2f(-m, -m, W + 2m, H + 2m)
        out = Rect2f[]; half = Float32(_COAST_BOX / 2)
        for seg in d.coastline, i in 1:_COAST_STRIDE:length(seg)
            px = _data_to_px(ax, seg[i])
            _in_rect(px, pr) || continue
            push!(out, Rect2f(px[1] - half, px[2] - half, _COAST_BOX, _COAST_BOX))
            length(out) >= _COAST_MAX && return out
        end
        out
    end
    boxes_overlap(a, b) = begin
        ox = min(a.origin[1]+a.widths[1], b.origin[1]+b.widths[1]) - max(a.origin[1], b.origin[1])
        oy = min(a.origin[2]+a.widths[2], b.origin[2]+b.widths[2]) - max(a.origin[2], b.origin[2])
        ox > 0.5 && oy > 0.5
    end
    in_rect(box, R) = (box.origin[1] >= R.origin[1]-0.5 && box.origin[2] >= R.origin[2]-0.5 &&
        box.origin[1]+box.widths[1] <= R.origin[1]+R.widths[1]+0.5 &&
        box.origin[2]+box.widths[2] <= R.origin[2]+R.widths[2]+0.5)

    for p in 0.0:0.09:1.0
        fig, ax, af = assemble_frame(d, p; pagepx)
        cb = coast_boxes(ax); fp = af.fp
        for k in eachindex(fp.ids)
            fp.dropped[k] && continue
            id = fp.ids[k]
            get(af.band, id, 1.0) > 0.02 || continue
            c = fp.anchors[k] .+ fp.offsets[k]; s = fp.sizes[k]
            lb = Rect2f(c[1]-s[1]/2, c[2]-s[2]/2, s[1], s[2])
            # HARD requirement: no drawn label touches the coast barrier…
            @test !any(b -> boxes_overlap(lb, b), cb)
            # …and no drawn label extends past the visible map rect (the neat-line).
            @test in_rect(lb, map_rect)
        end
    end
end
