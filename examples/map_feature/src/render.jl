# SPDX-License-Identifier: MIT
#
# map_feature — assemble the cartographic feature page (#G). Pinned fonts: DejaVu Sans (display),
# Liberation Serif (body). Rendered at px_per_unit=1 so measured widths track drawn widths.
#
# Non-overlap by construction (fix #3), each TESTED (see test/test_render_layout.jl):
#   (a) masthead + sidebar big-number stats occupy a TOP BAND whose content stays above
#       SIDEBAR_BOTTOM, a full gutter above the body region (REGION_TOP) → body never touches them;
#   (b) the body chord_fn reserves the right-hand map column in bands that do NOT cross the
#       silhouette (letterbox gaps) → body never crosses the empty map panel;
#   (c) in bands that DO cross the silhouette, complement_chord_fn carves [env_l,env_r] → body
#       wraps the silhouette's facing edge and never sits on it.
#
# Packing uses `fill=:all` (impl-C2): a silhouette-crossing band offers TWO usable runs — the
# left margin AND the strip right of the silhouette before the map's right edge — and both are
# filled, so the prose wraps the state on BOTH sides (most VT bands yield two runs ≥ min_chord_width).
# Letterbox bands (silhouette absent) collapse to the single left region (the map column is
# reserved by the render combinator). overflow_strategy=:skip ⇒ no over-wide word is dumped atop
# the map.
#
# Rendering is pixel-faithful: a `campixel!` Scene maps 1 data unit → 1 screen px exactly, so the
# measured layout (MakieBackend at px_per_unit=1) is drawn at the same scale — glyph runs occupy
# exactly their measured width and never overrun the silhouette envelope they were packed against.

import CairoMakie
const CM = CairoMakie   # re-exports Makie's Scene / campixel! / text! / poly! / scatter!

const BODY_FONT    = "Liberation Serif"
const DISPLAY_FONT = "DejaVu Sans"

# Page geometry (US-letter-ish @ ~96dpi, block-top). Map fills the right ~55%.
const PAGE_W        = 816.0
const PAGE_H        = 1056.0
const MARGIN        = 48.0
const SIDEBAR_BOTTOM = 200.0    # masthead + sidebar glyphs all stay above this y
const REGION_TOP     = 230.0    # body + map region top (a gutter below SIDEBAR_BOTTOM)
const BYLINE_H       = 36.0

# Packing kwargs — see NOTE above.
const PACK_KW = (min_chord_width = 36.0, overflow_strategy = :skip, fill = :all)

_map_left()      = MARGIN + 0.45 * (PAGE_W - 2MARGIN)
_region_bottom() = PAGE_H - BYLINE_H - MARGIN

_marker_glyph(kind::Symbol) = kind === :capital ? '★' :
                              kind === :city     ? '●' :
                              kind === :landmark ? '◆' : '▲'

# Subtract the open interval (a,b) from a sorted-disjoint interval list; keep order/disjointness.
function _subtract_interval(ivs::Vector{Tuple{Float64,Float64}}, (a, b)::Tuple{Float64,Float64})
    out = Tuple{Float64,Float64}[]
    for (l, r) in ivs
        if b <= l || a >= r          # no overlap
            push!(out, (l, r))
        else
            (l < a) && push!(out, (l, a))
            (b < r) && push!(out, (b, r))
        end
    end
    return out
end

# Body chord_fn: complement around the silhouette, with the map column reserved in non-crossing
# (letterbox) bands within the map's y-range so prose never crosses the empty map panel.
function _body_chord_fn(poly_px, text_bounds, map_region)
    base = complement_chord_fn(poly_px, text_bounds)
    left, _, right, _ = text_bounds
    mx0, mtop, mx1, mbot = map_region
    return function (yt, yb)
        ivs = base(yt, yb)
        yc = (Float64(yt) + Float64(yb)) / 2
        if mtop <= yc <= mbot && length(ivs) == 1 && ivs[1] == (left, right)
            ivs = _subtract_interval(ivs, (mx0, mx1))   # reserve the map column in letterbox bands
        end
        return ivs
    end
end

"""
    _compose_layout(state_polygon; dest, body_text, fontsize) -> NamedTuple

The pure geometry/layout half of `map_feature`, factored out so the render-level non-overlap
invariants are testable without drawing. Returns `(; pp, poly_px, prep, pk, text_bounds,
map_region, region_top, region_bottom, map_left, map_right)`.
"""
function _compose_layout(state_polygon::Vector{Point2{Float64}};
                         dest::AbstractString="EPSG:5070",
                         body_text::AbstractString=DEFAULT_BODY,
                         fontsize::Float64=12.0)
    region_top    = REGION_TOP
    region_bottom = _region_bottom()
    map_left      = _map_left()
    map_right     = PAGE_W - MARGIN
    map_region    = (map_left, region_top, map_right, region_bottom)

    pp = PageProjection(state_polygon, map_region; dest=dest)
    poly_px = project_polygon(pp, state_polygon)

    text_bounds = (MARGIN, region_top, PAGE_W - MARGIN, region_bottom)
    cf = _body_chord_fn(poly_px, text_bounds, map_region)
    backend = MakieBackend(; font=BODY_FONT, fontsize=fontsize, px_per_unit=1.0)
    prep = prepare(backend, body_text)
    pk = shape_pack(prep, cf; line_advance=prep.metrics.line_advance, PACK_KW...)

    return (; pp, poly_px, prep, pk, text_bounds, map_region,
            region_top, region_bottom, map_left, map_right)
end

"""
    map_feature(state_polygon, stats, points_of_interest; dest="EPSG:5070",
                body_text=DEFAULT_BODY, fontsize=12.0) -> CairoMakie.Figure

Render the feature page. `state_polygon` is a geographic `(lon,lat)` ring (single outer ring —
CONUS/Vermont verified, see `PageProjection`); `stats` a `Dict{Symbol,Any}`
(`:population`,`:median_income_usd`,`:capital`,`:masthead`,`:subtitle`,`:byline`);
`points_of_interest` a `Vector{POI}`. Geography is projected into the right-hand map region;
editorial `body_text` flows through the negative space on the left, wrapping the silhouette.
"""
function map_feature(state_polygon::Vector{Point2{Float64}},
                     stats::Dict{Symbol,Any},
                     points_of_interest::Vector{POI};
                     dest::AbstractString="EPSG:5070",
                     body_text::AbstractString=DEFAULT_BODY,
                     fontsize::Float64=12.0)
    L = _compose_layout(state_polygon; dest=dest, body_text=body_text, fontsize=fontsize)
    backend = MakieBackend(; font=BODY_FONT, fontsize=fontsize, px_per_unit=1.0)

    # Pixel-space scene: 1 data unit == 1 screen px (campixel!), so measured widths render 1:1.
    scene = CM.Scene(; size=(PAGE_W, PAGE_H), backgroundcolor=:white)
    CM.campixel!(scene)
    flip(y) = PAGE_H - y       # block-top y → pixel-space y-up

    # masthead + subtitle (top band, all glyphs above SIDEBAR_BOTTOM)
    CM.text!(scene, MARGIN, flip(MARGIN + 44); text=get(stats, :masthead, "STATE"),
             font=DISPLAY_FONT, fontsize=54, align=(:left, :baseline), color=:black)
    CM.text!(scene, MARGIN, flip(MARGIN + 66); text=get(stats, :subtitle, ""),
             font=BODY_FONT, fontsize=15, align=(:left, :baseline), color=(:black, 0.7))

    # sidebar big-number stats (still above SIDEBAR_BOTTOM)
    CM.text!(scene, MARGIN, flip(MARGIN + 98); text="POP $(stats[:population])",
             font=DISPLAY_FONT, fontsize=22, align=(:left, :baseline), color=:seagreen)
    CM.text!(scene, MARGIN, flip(MARGIN + 122); text="MEDIAN INCOME \$$(stats[:median_income_usd])",
             font=DISPLAY_FONT, fontsize=14, align=(:left, :baseline), color=(:black, 0.8))
    CM.text!(scene, MARGIN, flip(MARGIN + 144); text="CAPITAL $(stats[:capital])",
             font=DISPLAY_FONT, fontsize=14, align=(:left, :baseline), color=(:black, 0.8))

    # state silhouette fill + outline
    CM.poly!(scene, [CM.Point2f(p[1], flip(p[2])) for p in L.poly_px];
             color=(:seagreen, 0.18), strokecolor=:seagreen, strokewidth=1.5)

    # body text at each placement (baseline-aligned)
    for pl in L.pk.placements
        s = L.prep.segments[pl.segment_index].str
        CM.text!(scene, pl.x, flip(pl.y); text=s, font=BODY_FONT, fontsize=fontsize,
                 align=(:left, :baseline), color=:black)
    end

    # POIs: markers + non-overlapping labels
    anchors = [project_point(L.pp, Point2{Float64}(p.coord[1], p.coord[2])) for p in points_of_interest]
    sizes = [(TextMeasure.measure(backend, p.name) + 4.0, fontsize + 2.0) for p in points_of_interest]
    boxes = place_poi_labels(anchors, sizes; offset=6.0, margin=2.0)
    for (i, p) in enumerate(points_of_interest)
        a = anchors[i]
        CM.text!(scene, a[1], flip(a[2]); text=string(_marker_glyph(p.kind)),
                 font=DISPLAY_FONT, fontsize=(p.kind === :capital ? 18 : 12),
                 align=(:center, :center), color=:firebrick)
        b = boxes[i]
        b === nothing && continue
        CM.text!(scene, b.x, flip(b.y + b.h); text=p.name, font=DISPLAY_FONT,
                 fontsize=(p.kind === :capital ? fontsize + 2 : fontsize),
                 align=(:left, :baseline), color=:black)
    end

    # byline (bottom)
    CM.text!(scene, MARGIN, flip(PAGE_H - MARGIN + 12); text=get(stats, :byline, ""),
             font=BODY_FONT, fontsize=11, align=(:left, :baseline), color=(:black, 0.7))

    return scene
end

"""    render_to_pdf(scene, path) -> path   — export with selectable (embedded) text."""
function render_to_pdf(scene::CM.Scene, path::AbstractString)
    CM.save(path, scene; pt_per_unit=1.0)
    return path
end

# Placeholder editorial copy (the demo's "prose"); tripled to fill the column.
const DEFAULT_BODY = repeat("""
Vermont rises in green folds between the Connecticut River and the broad blue reach of Lake \
Champlain. Its ridgelines run north and south like the grain of old timber, and the towns \
gather in the valleys where the rivers slow. This page is set by measurement: every line of \
this column was placed by flowing words through the white space the map leaves behind, so the \
text wraps the silhouette of the state itself and never crosses into the cartography. Nothing \
here is nudged by hand. The column narrows where the border bulges and opens again where the \
land falls away, a quiet demonstration that type can follow geography when the layout engine \
knows exactly how wide each word will be. """, 3)
