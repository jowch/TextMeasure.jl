# SPDX-License-Identifier: MIT
#
# map_feature — assemble the cartographic feature page (#G). Pinned fonts: DejaVu Sans (display),
# Liberation Serif (body). Rendered at px_per_unit=1 so measured widths track drawn widths.
#
# Non-overlap by construction (fix #3): masthead + sidebar big-number stats occupy a TOP BAND
# strictly above the body text region, and the body chord_fn reserves the right-hand map column
# in bands that do NOT cross the silhouette (letterbox gaps) — so body text can never sit on the
# masthead, the sidebar, or the empty map panel, while still wrapping the silhouette's facing edge
# in the bands it does cross.
#
# NOTE: until shape_pack's `fill=:all` (impl-C2) merges, packing uses the single widest interval
# per band (left column). Switch `shape_pack(...; fill=:all)` once available to also fill the
# right-hand sliver — see PACK_KW below.

import CairoMakie
const CM = CairoMakie

const BODY_FONT    = "Liberation Serif"
const DISPLAY_FONT = "DejaVu Sans"

# Page geometry (US-letter-ish @ ~96dpi, block-top). Map fills the right ~55%.
const PAGE_W     = 816.0
const PAGE_H     = 1056.0
const MARGIN     = 48.0
const TOP_BAND_H = 150.0     # masthead + sidebar stat strip live here, ABOVE the body
const BYLINE_H   = 36.0

# Packing kwargs — swap to (:fill => :all) when impl-C2 lands (see NOTE above).
const PACK_KW = (min_chord_width = 36.0, overflow_strategy = :skip)

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
    region_top    = MARGIN + TOP_BAND_H
    region_bottom = PAGE_H - BYLINE_H - MARGIN
    map_left      = MARGIN + 0.45 * (PAGE_W - 2MARGIN)
    map_right     = PAGE_W - MARGIN
    map_region    = (map_left, region_top, map_right, region_bottom)

    pp = PageProjection(state_polygon, map_region; dest=dest)
    poly_px = project_polygon(pp, state_polygon)

    # body text region: full inner width, below the masthead/sidebar top band.
    text_bounds = (MARGIN, region_top, PAGE_W - MARGIN, region_bottom)
    cf = _body_chord_fn(poly_px, text_bounds, map_region)
    backend = MakieBackend(; font=BODY_FONT, fontsize=fontsize, px_per_unit=1.0)
    prep = prepare(backend, body_text)
    pk = shape_pack(prep, cf; line_advance=prep.metrics.line_advance, PACK_KW...)

    # --- figure (block-top y → CairoMakie y-up via y' = PAGE_H - y) ---
    fig = CM.Figure(; size=(PAGE_W, PAGE_H), backgroundcolor=:white)
    ax = CM.Axis(fig[1, 1]; aspect=CM.DataAspect())
    CM.hidedecorations!(ax); CM.hidespines!(ax)
    CM.limits!(ax, 0, PAGE_W, 0, PAGE_H)
    flip(y) = PAGE_H - y

    # masthead + subtitle (top band)
    CM.text!(ax, MARGIN, flip(MARGIN + 40); text=get(stats, :masthead, "STATE"),
             font=DISPLAY_FONT, fontsize=54, align=(:left, :baseline), color=:black, space=:data)
    CM.text!(ax, MARGIN, flip(MARGIN + 62); text=get(stats, :subtitle, ""),
             font=BODY_FONT, fontsize=15, align=(:left, :baseline), color=(:black, 0.7), space=:data)

    # sidebar big-number stats (still in the top band, above the body)
    CM.text!(ax, MARGIN, flip(MARGIN + 96); text="POP $(stats[:population])",
             font=DISPLAY_FONT, fontsize=22, align=(:left, :baseline), color=:seagreen, space=:data)
    CM.text!(ax, MARGIN, flip(MARGIN + 120); text="MEDIAN INCOME \$$(stats[:median_income_usd])",
             font=DISPLAY_FONT, fontsize=14, align=(:left, :baseline), color=(:black, 0.8), space=:data)
    CM.text!(ax, MARGIN, flip(MARGIN + 140); text="CAPITAL $(stats[:capital])",
             font=DISPLAY_FONT, fontsize=14, align=(:left, :baseline), color=(:black, 0.8), space=:data)

    # state silhouette fill + outline
    CM.poly!(ax, [CM.Point2f(p[1], flip(p[2])) for p in poly_px];
             color=(:seagreen, 0.18), strokecolor=:seagreen, strokewidth=1.5)

    # body text at each placement (baseline-aligned)
    for pl in pk.placements
        s = prep.segments[pl.segment_index].str
        CM.text!(ax, pl.x, flip(pl.y); text=s, font=BODY_FONT, fontsize=fontsize,
                 align=(:left, :baseline), color=:black, space=:data)
    end

    # POIs: markers + non-overlapping labels
    anchors = [project_point(pp, Point2{Float64}(p.coord[1], p.coord[2])) for p in points_of_interest]
    sizes = [(TextMeasure.measure(backend, p.name) + 4.0, fontsize + 2.0) for p in points_of_interest]
    boxes = place_poi_labels(anchors, sizes; offset=6.0, margin=2.0)
    for (i, p) in enumerate(points_of_interest)
        a = anchors[i]
        CM.text!(ax, a[1], flip(a[2]); text=string(_marker_glyph(p.kind)),
                 font=DISPLAY_FONT, fontsize=(p.kind === :capital ? 18 : 12),
                 align=(:center, :center), color=:firebrick, space=:data)
        b = boxes[i]
        b === nothing && continue
        CM.text!(ax, b.x, flip(b.y + b.h); text=p.name, font=DISPLAY_FONT,
                 fontsize=(p.kind === :capital ? fontsize + 2 : fontsize),
                 align=(:left, :baseline), color=:black, space=:data)
    end

    # byline (bottom)
    CM.text!(ax, MARGIN, flip(PAGE_H - MARGIN + 12); text=get(stats, :byline, ""),
             font=BODY_FONT, fontsize=11, align=(:left, :baseline), color=(:black, 0.7), space=:data)

    return fig
end

"""    render_to_pdf(fig, path) -> path   — export with selectable (embedded) text."""
function render_to_pdf(fig::CM.Figure, path::AbstractString)
    CM.save(path, fig; pt_per_unit=1.0)
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
