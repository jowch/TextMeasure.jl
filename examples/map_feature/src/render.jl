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
# Composition: the silhouette is RIGHT-ALIGNED to the page's right margin (PageProjection
# halign=:right), and the editorial column wraps its irregular WESTERN edge — a clean single-side
# feature page. Packing is `:widest` (the wide left/west run per band); the strip east of the
# silhouette is empty (silhouette flush-right) so there is no cramped east column. fill=:all is
# available in shape_pack (impl-C2) for genuinely two-sided layouts, but a thin east strip reads
# as accidental, not deliberate — so #G deliberately keeps the single elegant west wrap.
# overflow_strategy=:skip ⇒ no over-wide word is dumped atop the map.
#
# Rendering is pixel-faithful: a `campixel!` Scene maps 1 data unit → 1 screen px exactly, so the
# measured layout (MakieBackend at px_per_unit=1) is drawn at the same scale — glyph runs occupy
# exactly their measured width and never overrun the silhouette/label boxes they were packed against.

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

# Packing kwargs — `fill` is supplied per-call (default :widest; see NOTE above).
const PACK_KW = (min_chord_width = 36.0, overflow_strategy = :skip)
const SILHOUETTE_PAD = 6.0   # px clearance the body keeps from the silhouette fill

_region_bottom() = PAGE_H - BYLINE_H - MARGIN
# Map-region horizontal box edge at `frac` of the inner content width [MARGIN, PAGE_W-MARGIN].
_map_x(frac)     = MARGIN + frac * (PAGE_W - 2MARGIN)

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

# Body chord_fn: complement around the silhouette, plus two render-level reservations so prose
# never collides with non-text furniture:
#  - the map column is reserved in non-crossing (letterbox) bands so prose can't cross the empty
#    map panel;
#  - each POI **label** box (`label_excl`, already grown for clearance) is subtracted from every
#    band it spans, so body text flows around the labels exactly as it flows around the silhouette.
function _body_chord_fn(poly_px, text_bounds, map_region,
                        label_excl::Vector{NTuple{4,Float64}}; pad::Float64=0.0)
    base = complement_chord_fn(poly_px, text_bounds; pad=pad)
    left, _, right, _ = text_bounds
    mx0, mtop, mx1, mbot = map_region
    return function (yt, yb)
        ivs = base(yt, yb)
        yc = (Float64(yt) + Float64(yb)) / 2
        if mtop <= yc <= mbot && length(ivs) == 1 && ivs[1] == (left, right)
            ivs = _subtract_interval(ivs, (mx0, mx1))   # reserve the map column in letterbox bands
        end
        @inbounds for (lx0, ly0, lx1, ly1) in label_excl
            (ly0 < yb && yt < ly1) || continue          # band overlaps the label vertically
            ivs = _subtract_interval(ivs, (lx0, lx1))
        end
        return ivs
    end
end

"""
    _compose_layout(state_polygon, pois; dest, body_text, fontsize) -> NamedTuple

The pure geometry/layout half of `map_feature`, factored out so the render-level non-overlap
invariants are testable without drawing. Projects geography + POIs, places POI labels FIRST, then
flows the body text through the negative space around BOTH the silhouette and the label boxes.
Returns `(; pp, poly_px, prep, pk, anchors, labelboxes, pois, text_bounds, map_region,
region_top, region_bottom, map_left, map_right)`.
"""
function _compose_layout(state_polygon::Vector{Point2{Float64}},
                         pois::Vector{POI};
                         dest::AbstractString="EPSG:5070",
                         body_text::AbstractString=DEFAULT_BODY,
                         fontsize::Float64=12.0,
                         fill::Symbol=:widest,
                         silhouette_halign::Symbol=:right,
                         map_left_frac::Float64=0.45,
                         map_right_frac::Float64=1.0)
    region_top    = REGION_TOP
    region_bottom = _region_bottom()
    map_left      = _map_x(map_left_frac)
    map_right     = _map_x(map_right_frac)
    map_region    = (map_left, region_top, map_right, region_bottom)

    pp = PageProjection(state_polygon, map_region; dest=dest, halign=silhouette_halign)
    poly_px = project_polygon(pp, state_polygon)

    body_backend = MakieBackend(; font=BODY_FONT, fontsize=fontsize, px_per_unit=1.0)
    label_backend = MakieBackend(; font=DISPLAY_FONT, fontsize=fontsize, px_per_unit=1.0)

    # POI markers + labels placed FIRST (label fonts ⇒ accurate boxes), so the body can avoid them.
    anchors = [project_point(pp, Point2{Float64}(p.coord[1], p.coord[2])) for p in pois]
    sizes = [(TextMeasure.measure(label_backend, p.name) + 4.0,
              (p.kind === :capital ? fontsize + 4.0 : fontsize + 2.0)) for p in pois]
    # keep labels inside the content canvas (right-edge anchors fall through to a left-anchored box)
    canvas = (MARGIN, region_top, PAGE_W - MARGIN, region_bottom)
    labelboxes = place_poi_labels(anchors, sizes; offset=7.0, margin=2.0, bounds=canvas)

    # Grow each placed label box into a body-exclusion rect: +2px x clearance, and vertically by a
    # word's ascent/descent so a body word in an adjacent band can't clip the label either.
    bm = TextMeasure.font_metrics(body_backend)
    asc, desc = bm.ascent, bm.descent
    label_excl = NTuple{4,Float64}[
        (b.x - 2.0, b.y - asc, b.x + b.w + 2.0, b.y + b.h + desc)
        for b in labelboxes if b !== nothing]

    text_bounds = (MARGIN, region_top, PAGE_W - MARGIN, region_bottom)
    cf = _body_chord_fn(poly_px, text_bounds, map_region, label_excl; pad=SILHOUETTE_PAD)
    prep = prepare(body_backend, body_text)
    pk = shape_pack(prep, cf; line_advance=prep.metrics.line_advance, fill=fill, PACK_KW...)

    return (; pp, poly_px, prep, pk, anchors, labelboxes, pois, text_bounds, map_region,
            region_top, region_bottom, map_left, map_right)
end

"""
    map_feature(state_polygon, stats, points_of_interest; dest="EPSG:5070",
                body_text=DEFAULT_BODY, fontsize=12.0) -> CairoMakie.Scene

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
                     fontsize::Float64=12.0,
                     fill::Symbol=:widest,
                     silhouette_halign::Symbol=:right,
                     map_left_frac::Float64=0.45,
                     map_right_frac::Float64=1.0)
    L = _compose_layout(state_polygon, points_of_interest; dest=dest, body_text=body_text,
                        fontsize=fontsize, fill=fill, silhouette_halign=silhouette_halign,
                        map_left_frac=map_left_frac, map_right_frac=map_right_frac)

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

    # POIs: markers + the labels placed in _compose_layout (the SAME boxes the body flowed around)
    for (i, p) in enumerate(points_of_interest)
        a = L.anchors[i]
        CM.text!(scene, a[1], flip(a[2]); text=string(_marker_glyph(p.kind)),
                 font=DISPLAY_FONT, fontsize=(p.kind === :capital ? 18 : 12),
                 align=(:center, :center), color=:firebrick)
        b = L.labelboxes[i]
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

# Editorial copy — genuine, non-repeating Vermont feature prose (geography / history / economy).
const DEFAULT_BODY = """
Vermont is the only New England state without an Atlantic coastline, a landlocked country of \
ridgelines and river valleys that joined the Union in 1791 as the fourteenth state. For \
fourteen years before that it governed itself as an independent republic, minting its own \
coppers and writing, in 1777, the first constitution in North America to prohibit adult \
slavery. The Green Mountains run the length of the state like a spine, their highest summit \
Mount Mansfield rising to 4,393 feet above the dairy farms and sugar bushes below. To the \
west, Lake Champlain forms a long blue border with New York; to the east, the Connecticut \
River traces the line with New Hampshire. Burlington, on the lake, is the largest city, \
though Montpelier remains the smallest state capital in the country by population. The \
economy was built on what the land gives: Vermont is the leading producer of maple syrup in \
the United States, drawing sap from the same hillsides each spring, and its dairy herds \
supply cheese and milk far beyond its borders. In autumn the hardwood forests turn the hills \
gold and scarlet and the foliage draws travelers along roads that have changed little in a \
century; in winter the snow brings skiers to Stowe, Killington, and Mad River Glen. The state \
guards its character carefully — billboards are banned along its highways, many towns still \
settle local affairs by a show of hands at March meeting, and the working landscape of barn, \
steeple, and stone wall is kept as much by habit as by law. The Abenaki lived in the \
Champlain and Connecticut valleys long before European settlement, and their names still mark \
the water and the hills. Ethan Allen and the Green Mountain Boys, first organized to defend \
disputed land grants, seized Fort Ticonderoga in 1775. Today roughly 650,000 people live \
here, fewer than in many single cities, spread across a patchwork of small towns where the \
nearest neighbor may be a mountain — a place that reads, from the air or on the page, as \
mostly forest, nearly three-quarters of it wooded, stitched together by rivers, roads, and \
the slow work of the seasons."""
