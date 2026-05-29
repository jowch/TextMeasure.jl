# SPDX-License-Identifier: MIT
#
# map_feature — assemble the cartographic feature page (#G). Two-column editorial composition:
# the state silhouette is CENTERED as the visual gutter, and TWO INDEPENDENT real-prose paragraphs
# flow top-to-bottom — the left/west column contour-wrapping the silhouette's western edge, the
# right/east column contour-wrapping its eastern edge. Each column is its OWN `shape_pack` run
# against its OWN side's negative space, so each reads top-to-bottom on its own (NOT per-band
# snaking across the map). House style: docs/superpowers/demos-house-style.md.
#
# Non-overlap by construction, all TESTED (test/test_render_layout.jl): per column, body never
# overlaps the silhouette envelope (carved by complement_chord_fn with a `pad` clearance gutter)
# nor any POI label box (subtracted per band); masthead/sidebar live above the body region; the
# two columns occupy opposite sides of map-center. Rendering is pixel-faithful (campixel! Scene,
# 1 data unit == 1 px) so measured widths render 1:1 and never overrun what they were packed against.

import CairoMakie
const CM = CairoMakie   # re-exports Makie's Scene / campixel! / text! / poly! / RGBAf

# --- House style (docs/superpowers/demos-house-style.md) ---------------------------------------
const SERIF = "Liberation Serif"   # body / titles / masthead
const SANS  = "DejaVu Sans"        # labels / stats / footer
const SZ_DISPLAY = 44.0            # masthead
const SZ_SUBHEAD = 14.0            # stat lines, subtitle, capital label
const SZ_BODY    = 11.0            # column prose (ragged-right)
const SZ_CAPTION = 9.0             # footer
const C_TEXT  = CM.RGBAf(0.10, 0.10, 0.10, 1.0)    # near-black body
const C_GRAY  = CM.RGBAf(0.420, 0.447, 0.502, 1.0) # #6B7280 footer/subtitle
const C_GREEN = CM.RGBAf(0.106, 0.478, 0.239, 1.0) # #1B7A3D silhouette
const C_RED   = CM.RGBAf(0.753, 0.224, 0.169, 1.0) # #C0392B POI markers

# Page geometry (US-letter-ish @ ~96dpi, block-top). 36px outer margins all sides.
const PAGE_W         = 816.0
const PAGE_H         = 1056.0
const MARGIN         = 36.0
const SIDEBAR_BOTTOM = 175.0    # masthead + subtitle + stat glyphs all stay above this y
const REGION_TOP     = 200.0    # body + map region top (gutter below SIDEBAR_BOTTOM)
const FOOTER_CLEAR   = 22.0     # body region stops this far above the footer baseline
const COL_GUTTER     = 10.0     # half-gutter each side of map-center (clean gap in letterbox bands)
const SILHOUETTE_PAD = 6.0      # px clearance the body keeps from the silhouette fill
const PACK_KW = (min_chord_width = 36.0, overflow_strategy = :skip)   # fill defaults :widest

_region_bottom() = PAGE_H - MARGIN - FOOTER_CLEAR

# Marker glyph by role; :feature splits into water (≈) vs peak (▲) so the legend stays consistent.
function _marker_glyph(p::POI)
    p.kind === :capital  && return '★'
    p.kind === :city     && return '●'
    p.kind === :landmark && return '◆'
    occursin(r"lake|river|pond"i, p.name) && return '≈'   # water feature, not a summit
    return '▲'                                            # peak / mountain feature
end

# 643077 -> "643,077"
_commas(n::Integer) = replace(string(n), r"(?<=[0-9])(?=(?:[0-9]{3})+$)" => ",")

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

# One column's chord_fn: the negative space inside `col_bounds` around the silhouette (carved by
# complement_chord_fn, grown by `pad`), minus any POI label box spanning the band. A single usable
# interval per band ⇒ ordinary greedy top-to-bottom flow against the column's irregular inner edge.
function _column_chord_fn(poly_px, col_bounds, label_excl::Vector{NTuple{4,Float64}}; pad::Float64=0.0)
    base = complement_chord_fn(poly_px, col_bounds; pad=pad)
    return function (yt, yb)
        ivs = base(yt, yb)
        @inbounds for (lx0, ly0, lx1, ly1) in label_excl
            (ly0 < yb && yt < ly1) || continue
            ivs = _subtract_interval(ivs, (lx0, lx1))
        end
        return ivs
    end
end

"""
    _compose_layout(state_polygon, pois; dest="EPSG:5070") -> NamedTuple

Pure geometry/layout half of `map_feature`, testable without drawing. Projects geography + POIs,
places POI labels FIRST, then flows TWO independent body paragraphs (`BODY_WEST`, `BODY_EAST`)
top-to-bottom through the negative space on either side of the centered silhouette — each its own
`shape_pack` run. Returns `(; pp, poly_px, anchors, labelboxes, pois, columns, map_region,
map_center, region_top, region_bottom, map_left, map_right)`, where `columns` is a 2-vector of
`(prep, pk, side)` with `side ∈ (:west, :east)`.
"""
function _compose_layout(state_polygon::Vector{Point2{Float64}},
                         pois::Vector{POI};
                         dest::AbstractString="EPSG:5070")
    region_top    = REGION_TOP
    region_bottom = _region_bottom()
    inner         = PAGE_W - 2MARGIN
    map_left      = MARGIN + 0.31 * inner
    map_right     = MARGIN + 0.69 * inner
    map_center    = (map_left + map_right) / 2
    map_region    = (map_left, region_top, map_right, region_bottom)

    pp = PageProjection(state_polygon, map_region; dest=dest, halign=:center)
    poly_px = project_polygon(pp, state_polygon)

    body_backend  = MakieBackend(; font=SERIF, fontsize=SZ_BODY, px_per_unit=1.0)
    label_backend = MakieBackend(; font=SANS,  fontsize=SZ_BODY, px_per_unit=1.0)

    # POI markers + labels placed FIRST (so the body can avoid them); capital label is subhead-sized.
    anchors = [project_point(pp, Point2{Float64}(p.coord[1], p.coord[2])) for p in pois]
    sizes = map(pois) do p
        wscale = p.kind === :capital ? SZ_SUBHEAD / SZ_BODY : 1.0
        (TextMeasure.measure(label_backend, p.name) * wscale + 4.0,
         (p.kind === :capital ? SZ_SUBHEAD + 3.0 : SZ_BODY + 2.0))
    end
    # OUTBOARD labels: pushed to the page side-margins (clear of silhouette AND prose), leader-linked.
    labelboxes = place_margin_labels(anchors, sizes, map_center, MARGIN, PAGE_W - MARGIN,
                                     region_top, region_bottom)

    # Grow placed label boxes into body-exclusion rects (+2px x; ±ascent/descent y for adjacent bands).
    bm = TextMeasure.font_metrics(body_backend)
    asc, desc = bm.ascent, bm.descent
    label_excl = NTuple{4,Float64}[
        (b.x - 2.0, b.y - asc, b.x + b.w + 2.0, b.y + b.h + desc)
        for b in labelboxes if b !== nothing]

    west_bounds = (MARGIN, region_top, map_center - COL_GUTTER, region_bottom)
    east_bounds = (map_center + COL_GUTTER, region_top, PAGE_W - MARGIN, region_bottom)

    columns = map(((BODY_WEST, west_bounds, :west), (BODY_EAST, east_bounds, :east))) do (txt, bounds, side)
        cf   = _column_chord_fn(poly_px, bounds, label_excl; pad=SILHOUETTE_PAD)
        prep = prepare(body_backend, txt)
        pk   = shape_pack(prep, cf; line_advance=prep.metrics.line_advance, PACK_KW...)
        (prep, pk, side)
    end

    return (; pp, poly_px, anchors, labelboxes, pois, columns, map_region, map_center,
            region_top, region_bottom, map_left, map_right)
end

"""
    map_feature(state_polygon, stats, points_of_interest; dest="EPSG:5070") -> CairoMakie.Scene

Render the two-column cartographic feature page. `state_polygon` is a geographic `(lon,lat)` ring
(single outer ring — CONUS/Vermont verified, see `PageProjection`); `stats` a `Dict{Symbol,Any}`
(`:population`,`:median_income_usd`,`:capital`,`:masthead`,`:subtitle`); `points_of_interest` a
`Vector{POI}`. Two real paragraphs flow independently down either side of the centered silhouette.
"""
function map_feature(state_polygon::Vector{Point2{Float64}},
                     stats::Dict{Symbol,Any},
                     points_of_interest::Vector{POI};
                     dest::AbstractString="EPSG:5070")
    L = _compose_layout(state_polygon, points_of_interest; dest=dest)

    scene = CM.Scene(; size=(PAGE_W, PAGE_H), backgroundcolor=:white)
    CM.campixel!(scene)
    flip(y) = PAGE_H - y       # block-top y → pixel-space y-up

    # masthead (serif display) + subtitle (sans subhead, gray)
    CM.text!(scene, MARGIN, flip(MARGIN + 40); text=get(stats, :masthead, "STATE"),
             font=SERIF, fontsize=SZ_DISPLAY, align=(:left, :baseline), color=C_TEXT)
    CM.text!(scene, MARGIN, flip(MARGIN + 60); text=get(stats, :subtitle, ""),
             font=SANS, fontsize=SZ_SUBHEAD, align=(:left, :baseline), color=C_GRAY)

    # stat lines (sans subhead)
    CM.text!(scene, MARGIN, flip(MARGIN + 92); text="POP $(_commas(stats[:population]))",
             font=SANS, fontsize=SZ_SUBHEAD, align=(:left, :baseline), color=C_TEXT)
    CM.text!(scene, MARGIN, flip(MARGIN + 112); text="MEDIAN INCOME \$$(_commas(stats[:median_income_usd]))",
             font=SANS, fontsize=SZ_SUBHEAD, align=(:left, :baseline), color=C_TEXT)
    CM.text!(scene, MARGIN, flip(MARGIN + 132); text="CAPITAL $(stats[:capital])",
             font=SANS, fontsize=SZ_SUBHEAD, align=(:left, :baseline), color=C_TEXT)

    # state silhouette: GREEN fill (alpha for legibility of on-map labels) + solid GREEN stroke
    CM.poly!(scene, [CM.Point2f(p[1], flip(p[2])) for p in L.poly_px];
             color=CM.RGBAf(0.106, 0.478, 0.239, 0.16), strokecolor=C_GREEN, strokewidth=1.5)

    # both columns: real prose, baseline-aligned, ragged-right
    for (prep, pk, _) in L.columns
        for pl in pk.placements
            CM.text!(scene, pl.x, flip(pl.y); text=prep.segments[pl.segment_index].str,
                     font=SERIF, fontsize=SZ_BODY, align=(:left, :baseline), color=C_TEXT)
        end
    end

    # leader lines (1px gray) from each outboard label's inner edge to its on-map dot — drawn first
    leader = CM.RGBAf(0.420, 0.447, 0.502, 0.55)
    for (i, _) in enumerate(points_of_interest)
        b = L.labelboxes[i]; b === nothing && continue
        a = L.anchors[i]
        inner_x = a[1] < L.map_center ? b.x + b.w : b.x        # edge of the box facing the map
        CM.lines!(scene, [inner_x, a[1]], [flip(b.y + b.h/2), flip(a[2])];
                  color=leader, linewidth=1.0)
    end

    # RED markers on the dots, then the outboard labels
    for (i, p) in enumerate(points_of_interest)
        a = L.anchors[i]
        CM.text!(scene, a[1], flip(a[2]); text=string(_marker_glyph(p)),
                 font=SANS, fontsize=(p.kind === :capital ? 16 : 11),
                 align=(:center, :center), color=C_RED)
        b = L.labelboxes[i]; b === nothing && continue
        CM.text!(scene, b.x, flip(b.y + b.h); text=p.name, font=SANS,
                 fontsize=(p.kind === :capital ? SZ_SUBHEAD : SZ_BODY),
                 align=(:left, :baseline), color=C_TEXT)
    end

    # footer (sans caption, gray, baseline on the bottom inner-margin line)
    state_name = titlecase(get(stats, :masthead, "State"))
    CM.text!(scene, MARGIN, flip(PAGE_H - MARGIN); text="TextMeasure.jl · $state_name",
             font=SANS, fontsize=SZ_CAPTION, align=(:left, :baseline), color=C_GRAY)

    return scene
end

"""    render_to_pdf(scene, path) -> path   — export with selectable (embedded) text."""
function render_to_pdf(scene::CM.Scene, path::AbstractString)
    CM.save(path, scene; pt_per_unit=1.0)
    return path
end

# Editorial copy — two genuine, balanced, non-repeating Vermont paragraphs. WEST: land + history;
# EAST: economy + culture + people. Each flows independently down its own column.
const BODY_WEST = """
Vermont is the only New England state without an Atlantic coastline, a landlocked country of \
ridgelines and river valleys whose name comes from the French verts monts, the green mountains. \
Those mountains run the length of the state like a spine, their highest summit Mount Mansfield \
rising to 4,393 feet above the farms and sugar bushes below, with Camel's Hump, Killington Peak, \
and Mount Abraham close behind. Glaciers ground the ranges down and left the valleys broad and \
the soils thin; the rivers that drain them — the Winooski, the White, the Lamoille, the \
Missisquoi — run fast in spring and slow by late summer. To the west, Lake Champlain forms a \
long blue border with New York and drains north toward the St. Lawrence; to the east, the \
Connecticut River traces the entire line with New Hampshire. Nearly three-quarters of the state \
is forested, a second-growth woodland of maple, birch, beech, and spruce that returned after the \
sheep pastures of the nineteenth century were let go. The Abenaki lived in both river valleys \
for thousands of years before European settlement, and their names still mark the water and the \
hills. Samuel de Champlain reached the lake that bears his name in 1609. For much of the \
eighteenth century the land was claimed at once by New Hampshire and New York, and the quarrel \
over those grants gave the territory its first politics. Vermont declared itself an independent \
republic in 1777, minting its own coppers and writing a constitution that was the first in North \
America to prohibit adult slavery and to grant the vote without a property test. Ethan Allen and \
the Green Mountain Boys, first organized to defend the disputed grants, had already taken Fort \
Ticonderoga in 1775. The republic governed itself for fourteen years before Vermont joined the \
Union in 1791 as the fourteenth state, the first admitted after the original thirteen."""

const BODY_EAST = """
The economy was built on what the land gives, and on the discipline of making a little go far. \
Vermont is the leading producer of maple syrup in the United States, drawing sap from the same \
hillsides each spring as the nights freeze and the days thaw, and its dairy herds still supply \
cheese, butter, and milk far beyond its borders. Granite from Barre and marble from Proctor \
built statehouses and headstones across the country, and the quarries ran deep enough to swallow \
a town. In autumn the hardwood forests turn the hills gold and scarlet, and the foliage draws \
travelers along roads that have changed little in a century; in winter the snow brings skiers to \
Stowe, Killington, Sugarbush, and Mad River Glen. The ice-cream makers at Waterbury and the \
cheesemakers of the Champlain Valley sell a version of the same idea — small batches, named \
places, nothing hurried. The state guards its character carefully: billboards are banned along \
every highway, many towns still settle local affairs by a show of hands at March meeting, and \
the working landscape of barn, white steeple, and stone wall is kept as much by habit as by law. \
Burlington, on the lake, is the largest city, a college town of some forty thousand, though \
Montpelier remains the smallest state capital in the country by population, with fewer than eight \
thousand residents and not a single chain restaurant on its main street. Today roughly 650,000 \
people live in Vermont, fewer than in many single cities, spread across a patchwork of small \
towns where the nearest neighbor may be a mountain and the nearest stoplight a county away. It \
is a place that reads, from the air or on the page, as mostly forest — quiet, deliberate, and \
made to its own measure."""
