# render.jl — CairoMakie render layer: basemap + measured/solved labels + areals + chrome
#
# Depends on: data.jl, pois.jl, camera.jl, lod.jl, place.jl, fade.jl
# `using CairoMakie` lives here deliberately — kept out of place.jl.
#
# HONESTY INVARIANT: every point label (town + POI) is MEASURED by TextMeasure
# (measure_boxes) and PLACED by MakieTextRepel (solve_cluster, via solve_frame).
# Rotated region "areals" are likewise MEASURED, and their footprints + sampled
# coastline vertices are fed back in as solver OBSTACLES so the label field stays
# clear of them. The only hand-positioned values anywhere are feature anchors
# (Town.pos / POI.pos / Areal.pos) — never a label's final screen position.

using CairoMakie, Makie
using GeometryBasics: Point2f, Vec2f, Rect2f

# Inline 2-D vector magnitude (avoids LinearAlgebra stdlib dep declaration)
_norm2(v::Vec2f) = sqrt(v[1]^2 + v[2]^2)

# ── Palette (water colors not in HouseStyle) ────────────────────────────────
const WATER      = Makie.RGBf((0xDC, 0xE3, 0xE5) ./ 255...)
const WATER_LINE = Makie.RGBf((0x9F, 0xB2, 0xBA) ./ 255...)
const WATER_INK  = Makie.RGBf((0x5E, 0x77, 0x85) ./ 255...)   # deeper water ink for italic hydrography

# ── Field-survey type system (faces) ─────────────────────────────────────────
# Land = Hanken Grotesk · Water/hydrography = Newsreader italic · Title = Newsreader
# roman · Mono = Plex Mono (instrument readout only).
const FACE_LAND    = HouseStyle.hanken("Regular")     # settlements, POIs, terrain
const FACE_LAND_SB = HouseStyle.hanken("SemiBold")    # major settlements + region legend
const FACE_WATER   = joinpath(HouseStyle.FONTS_DIR, "Newsreader", "Newsreader-Italic.ttf")  # hydrography
const FACE_TITLE   = joinpath(HouseStyle.FONTS_DIR, "Newsreader", "Newsreader.ttf")          # masthead serif
const FACE_MONO    = HouseStyle.plexmono("Regular")   # metrics / scale readout ONLY

# Convenience: project a data-space Point2f to pixel coordinates.
# IMPORTANT: call Makie.update_state_before_display!(fig) BEFORE using this.
_data_to_px(ax, p::Point2f) = Point2f(Makie.project(ax.scene, :data, :pixel, p)[Vec(1, 2)])

# ── Feature ids ─────────────────────────────────────────────────────────────
const _SLO_ID  = 5      # "San Luis Obispo" — row 5 in towns.csv (the brass hero)
const _POI_BASE = 1000  # POI synthetic ids = _POI_BASE + index (disjoint from town_ids)

# ── Page layout constants ────────────────────────────────────────────────────
# Trimmed from the first pass (operator: "frame a bit too big") — less dead margin,
# taller masthead so the title clears the top edge and the neat-line sits below it.
const _MASTHEAD_H  = 76.0   # px reserved above the axis for chrome
const _FOOTER_H    = 20.0   # px reserved below the axis
const _SIDE_PAD    = 16.0   # px left/right margin for chrome text
const _TOP_PAD     = 10.0   # px from the very top edge to the masthead baseline anchor

# ── Obstacle tuning ──────────────────────────────────────────────────────────
const _COAST_STRIDE  = 5     # sample every Nth smoothed coastline vertex
const _COAST_BOX     = 8.0   # px side of each coastline obstacle box (centered on vertex)
const _COAST_MAX     = 200   # cap total coastline obstacle boxes (keeps the solve fast)

"""
    _content_aspect(pagepx) -> Float64

Aspect (w÷h) of the drawable map area: page minus side pads and masthead/footer.
The camera window is matched to this so the map fills the bbox with no letterbox.
"""
function _content_aspect(pagepx)
    W, H = pagepx
    (W - 2 * _SIDE_PAD) / (H - _MASTHEAD_H - _FOOTER_H)
end

"""
    _new_axis(; pagepx=(1350, 1080)) -> (fig, ax)

CairoMakie Figure+Axis sized for the page (px, default 5:4). WATER axis background,
all decorations/spines hidden. NO DataAspect — the axis FILLS its bbox; the camera
window (camera_rect) is matched to the content aspect so geography isn't distorted.
Chrome space reserved top/bottom via the bbox inset.
"""
function _new_axis(; pagepx=(1350, 1080))
    W, H = pagepx
    fig = Figure(size = (W, H), backgroundcolor = HouseStyle.PAPER)

    ax = Axis(fig;
        bbox = Makie.BBox(_SIDE_PAD, W - _SIDE_PAD,
                          _FOOTER_H, H - _MASTHEAD_H),
        backgroundcolor = WATER,
        xgridvisible    = false, ygridvisible    = false,
        xticksvisible   = false, yticksvisible   = false,
        xlabelvisible   = false, ylabelvisible   = false,
        xticklabelsvisible = false, yticklabelsvisible = false,
        leftspinevisible   = false, rightspinevisible  = false,
        topspinevisible    = false, bottomspinevisible = false,
    )

    return (fig, ax)
end

# ── Helpers ──────────────────────────────────────────────────────────────────

"""Return integer lat/lon range covered by the data, padded by 1 degree."""
function _data_range(d::AtlasData)
    lons = [t.pos[1] / KX for t in d.towns]  # unproject x back to lon
    lats = [t.pos[2]      for t in d.towns]
    lon_min = floor(Int, minimum(lons)) - 1
    lon_max = ceil(Int,  maximum(lons)) + 1
    lat_min = floor(Int, minimum(lats)) - 1
    lat_max = ceil(Int,  maximum(lats)) + 1
    (lon_min, lon_max, lat_min, lat_max)
end

"True when a pixel point sits inside `rect`."
_in_rect(px, rect::Rect2f) =
    px[1] >= rect.origin[1] && px[1] <= rect.origin[1] + rect.widths[1] &&
    px[2] >= rect.origin[2] && px[2] <= rect.origin[2] + rect.widths[2]

# ── Per-label type roles (face + ramp size + color + casing) ─────────────────
# HONESTY: each label is MEASURED at exactly the (font, size) it is DRAWN with.

"Measure ONE label string at its actual (font, size) → pixel box (w,h)."
measure_label(name, font, size) = only(measure_boxes([name]; font = font, fontsize = Float64(size)))

"Letterspace a caps string the way it's drawn (and therefore measured)."
_letterspace(s) = join(collect(s), " ")

"""
Resolve a point feature (town/POI) to its drawn style:
returns `(font, size_pt, color_role)` where color_role ∈ (:ink, :gray).
- Major towns (rank ≤ 5): Hanken SemiBold, subhead 16, ink.
- Minor towns: Hanken Regular, body 11, ink.
- POIs (landmarks): Hanken Regular, caption 9, gray.
"""
function _point_style(kind::Symbol, is_major::Bool)
    if kind === :town
        is_major ? (FACE_LAND_SB, HouseStyle.RAMP.subhead, :ink) :
                   (FACE_LAND,    HouseStyle.RAMP.body,    :ink)
    else  # :poi
        (FACE_LAND, HouseStyle.RAMP.caption, :gray)
    end
end

"""
The drawn string + face for an areal:
- :water → Newsreader italic, TITLE-CASE (not letterspaced).
- :range → Hanken, LETTERSPACED caps.
Returns `(drawn_string, font)`.
"""
function _areal_drawn(a::Areal)
    if a.kind === :water
        (titlecase(a.text), FACE_WATER)
    else
        (_letterspace(a.text), FACE_LAND)
    end
end

"Measure ONE areal at its ACTUAL face + size, using the SAME string it is drawn with."
function _measure_areal_box(a::Areal)
    s, font = _areal_drawn(a)
    only(measure_boxes([s]; fontsize = a.fontsize, font = font))
end

"""
Axis-aligned bounding box (px) of a rotated label of size `box` (w,h) centered at
`center`px, rotated `rot_deg` degrees. Used as a solver obstacle footprint.
"""
function _rotated_aabb(center::Point2f, box::Vec2f, rot_deg::Real)
    θ = deg2rad(rot_deg)
    hw, hh = box[1] / 2, box[2] / 2
    # extents of the rotated rectangle (half-width/height of its AABB)
    ex = abs(hw * cos(θ)) + abs(hh * sin(θ))
    ey = abs(hw * sin(θ)) + abs(hh * cos(θ))
    Rect2f(center[1] - ex, center[2] - ey, 2ex, 2ey)
end

# ── Frame assembly (the honest core) ─────────────────────────────────────────

"Everything render needs for one frame — all label boxes measured + solver-placed."
struct AssembledFrame
    fp        :: FramePlacement                 # ids = towns + POIs, all solved together
    kind_of   :: Dict{Int,Symbol}               # id → :town | :poi
    areals    :: Vector{Tuple{String,Point2f,Float64,Symbol}}  # (text, px anchor, rot, kind)
    obstacles :: Vector{Rect2f}                 # coastline + areal footprints (px)
    coast_capped :: Bool
end

"""
    assemble_frame(d, p; pagepx) -> (fig, ax, AssembledFrame)

Build a fresh figure for loop phase `p` and place EVERY label honestly:
- point labels (active towns + on-screen POIs) measured via TextMeasure, placed by
  one `solve_cluster` call against each other, the sampled coastline, and the areals;
- areals measured via TextMeasure, their rotated AABBs added as obstacles.
Cold start (no warm-state) — suitable for a single still. The loop task can later
thread `prev`/`settled` through `solve_frame`.
"""
function assemble_frame(d::AtlasData, p::Real; pagepx=(1350, 1080))
    fig, ax = _new_axis(; pagepx)
    # camera window matched to the drawable content aspect → fills frame, no distortion
    limits!(ax, camera_rect(p; aspect = _content_aspect(pagepx))...)
    Makie.update_state_before_display!(fig)   # camera matrices now reflect THIS frame

    W, H = Float32.(pagepx)
    margin    = 80.0f0
    page_rect = Rect2f(-margin, -margin, W + 2margin, H + 2margin)

    # --- (a) active towns (LoD) + on-screen POIs ---
    w    = view_width(p)
    tids = active_ids(d.towns, w, Int[])
    town_by_id = Dict(t.town_id => t for t in d.towns)
    pois = atlas_pois()

    ids      = Int[]
    px_anch  = Point2f[]
    names    = String[]
    sizes    = Vec2f[]                 # measured per-label at its OWN (face, size)
    kind_of  = Dict{Int,Symbol}()

    for id in tids
        t  = town_by_id[id]
        px = _data_to_px(ax, t.pos)
        _in_rect(px, page_rect) || continue
        font, size, _ = _point_style(:town, t.rank ≤ 5)
        push!(ids, id); push!(px_anch, px); push!(names, t.name)
        push!(sizes, measure_label(t.name, font, size))   # measured at this label's face+size
        kind_of[id] = :town
    end
    for (k, poi) in enumerate(pois)
        px = _data_to_px(ax, poi.pos)
        _in_rect(px, page_rect) || continue
        pid = _POI_BASE + k
        font, size, _ = _point_style(:poi, false)
        push!(ids, pid); push!(px_anch, px); push!(names, poi.name)
        push!(sizes, measure_label(poi.name, font, size))  # measured at the POI face+size
        kind_of[pid] = :poi
    end

    # --- (c) obstacles in PIXEL space ---
    obstacles = Rect2f[]

    # coastline: project + subsample smoothed vertices, emit small boxes, cap count
    coast_capped = false
    half = Float32(_COAST_BOX / 2)
    for seg in d.coastline
        for i in 1:_COAST_STRIDE:length(seg)
            px = _data_to_px(ax, seg[i])
            _in_rect(px, page_rect) || continue
            push!(obstacles, Rect2f(px[1] - half, px[2] - half, _COAST_BOX, _COAST_BOX))
            if length(obstacles) >= _COAST_MAX
                coast_capped = true
                break
            end
        end
        coast_capped && break
    end

    # areals: zoom-gated (big regions only at wide w), measure each, project its
    # anchor, add its rotated AABB as an obstacle
    areals = Tuple{String,Point2f,Float64,Symbol}[]
    for a in atlas_areals()
        (w >= a.wmin && w <= a.wmax) || continue
        apx = _data_to_px(ax, a.pos)
        box = _measure_areal_box(a)
        push!(obstacles, _rotated_aabb(apx, box, a.rotation))
        push!(areals, (a.text, apx, a.rotation, a.kind))
    end

    # --- (d) ONE solve over all point labels, with obstacles ---
    bounds = Rect2f(0, 0, W, H)
    fp = if isempty(ids)
        FramePlacement(Int[], Point2f[], Vec2f[], Vec2f[], BitVector())
    else
        solve_frame(ids, px_anch, sizes, bounds;
                    prev = Dict{Int,Vec2f}(), settled = Set{Int}(), obstacles = obstacles)
    end

    return fig, ax, AssembledFrame(fp, kind_of, areals, obstacles, coast_capped)
end

# ── Draw functions ────────────────────────────────────────────────────────────

"""
    draw_basemap!(ax, d::AtlasData)

Water (Axis background) · land poly (PAPER, no stroke) · coastline hairline
(INK 0.75px, the only 0.75 line) · recessive half-degree graticule (translucent BRASS 0.25px).
"""
function draw_basemap!(ax, d::AtlasData)
    for ring in d.land
        isempty(ring) && continue
        poly!(ax, ring; color = HouseStyle.PAPER, strokewidth = 0, inspectable = false)
    end

    lon_min, lon_max, lat_min, lat_max = _data_range(d)
    grat_c = Makie.RGBAf(HouseStyle.BRASS.r, HouseStyle.BRASS.g, HouseStyle.BRASS.b, 0.35)
    for lon in lon_min:0.5:lon_max
        pts = [Point2f(project_point(lon, lat)) for lat in range(lat_min, lat_max; length=64)]
        lines!(ax, pts; color = grat_c, linewidth = 0.25, inspectable = false)
    end
    for lat in lat_min:0.5:lat_max
        pts = [Point2f(project_point(lon, lat)) for lon in range(lon_min, lon_max; length=64)]
        lines!(ax, pts; color = grat_c, linewidth = 0.25, inspectable = false)
    end

    for seg in d.coastline
        isempty(seg) && continue
        lines!(ax, seg; color = HouseStyle.INK, linewidth = 0.75, inspectable = false)
    end

    return ax
end

"""
    draw_areals!(ax, areals)

Draw rotated region labels at their PIXEL anchors (space=:pixel), each in the SAME
face/size/string it was MEASURED with:
- :water → Newsreader ITALIC, title-case (not letterspaced), color WATER_INK.
- :range → Hanken, letterspaced caps, color HouseStyle.GRAY.
Drawn UNDER the point labels; the solver keeps point labels off these via obstacles.
`areals` entries are `(raw_text, px_anchor, rotation_deg, kind)`; the raw_text is
re-resolved to its drawn string + face here via the matching `Areal`.
"""
function draw_areals!(ax, areals)
    by_text = Dict(a.text => a for a in atlas_areals())
    for (text, apx, rot, kind) in areals
        a = by_text[text]
        drawn, font = _areal_drawn(a)
        col = kind === :range ? HouseStyle.GRAY : WATER_INK
        text!(ax, apx;
            text        = drawn,
            rotation    = deg2rad(rot),
            fontsize    = a.fontsize,
            font        = font,
            color       = col,
            align       = (:center, :center),
            space       = :pixel,
            inspectable = false)
    end
    return ax
end

"""
    draw_labels!(ax, d, af::AssembledFrame, fs::FadeState)

Draw the point-label layer (towns + POIs) for one frame from the solved placement.
Each label is drawn at the SAME (face, size) it was measured at (Field-survey roles):
- major towns → Hanken SemiBold subhead 16 INK; minor towns → Hanken Regular body 11 INK;
- POIs → Hanken Regular caption 9 GRAY (hollow diamond marker).
Leaders (BRASS 0.5px) for far-pushed labels drawn first; town dots (brass SLO hero)
with PAPER halo; POIs hollow INK diamonds; markers on top.
"""
function draw_labels!(ax, d::AtlasData, af::AssembledFrame, fs::FadeState)
    fp = af.fp
    isempty(fp.ids) && return ax

    town_by_id = Dict(t.town_id => t for t in d.towns)
    pois       = atlas_pois()

    # resolve id → (data anchor pos, display name, kind)
    function feature(id)
        if af.kind_of[id] === :town
            t = town_by_id[id]; return (t.pos, t.name, :town)
        else
            poi = pois[id - _POI_BASE]; return (poi.pos, poi.name, :poi)
        end
    end

    # --- leaders (drawn first so markers sit on top) ---
    leader_pts = Point2f[]
    for k in eachindex(fp.ids)
        fp.dropped[k] && continue
        alpha_of(fs, fp.ids[k]) < 0.01 && continue
        off = fp.offsets[k]; anc = fp.anchors[k]; sz = fp.sizes[k]
        mag = _norm2(off)
        if mag > sz[1] * 0.5
            dir   = off / mag
            push!(leader_pts, anc .+ dir .* 5.0f0)   # anchor end, trimmed by point_padding
            push!(leader_pts, anc .+ off)            # label-center end
        end
    end
    if !isempty(leader_pts)
        linesegments!(ax, leader_pts; space = :pixel,
            color = HouseStyle.BRASS, linewidth = 0.5, inspectable = false)
    end

    # --- collect markers (batched) + per-label text rows ---
    town_halo_pos = Point2f[]; town_halo_c = Makie.RGBAf[]; town_halo_sz = Float32[]
    town_dot_pos  = Point2f[]; town_dot_c  = Makie.RGBAf[]; town_dot_sz  = Float32[]
    poi_pos       = Point2f[]; poi_fill    = Makie.RGBAf[]; poi_stroke   = Makie.RGBAf[]
    # text rows drawn one-by-one (each at its own measured face+size)
    text_rows = NamedTuple[]   # (pos, name, off, font, size, color)

    for k in eachindex(fp.ids)
        fp.dropped[k] && continue
        id = fp.ids[k]
        α  = alpha_of(fs, id)
        α < 0.01 && continue
        pos, name, kind = feature(id)

        if kind === :town
            is_slo   = id == _SLO_ID
            t        = town_by_id[id]
            is_major = t.rank ≤ 5
            ink_c    = is_slo ? HouseStyle.BRASS : HouseStyle.INK
            dsz      = is_slo ? 11.0f0 : (is_major ? 8.0f0 : 7.0f0)
            push!(town_halo_pos, pos)
            push!(town_halo_c, Makie.RGBAf(HouseStyle.PAPER.r, HouseStyle.PAPER.g, HouseStyle.PAPER.b, α))
            push!(town_halo_sz, dsz + 4.0f0)
            push!(town_dot_pos, pos)
            push!(town_dot_c, Makie.RGBAf(ink_c.r, ink_c.g, ink_c.b, α))
            push!(town_dot_sz, dsz)
            font, size, _ = _point_style(:town, is_major)
            col = Makie.RGBAf(HouseStyle.INK.r, HouseStyle.INK.g, HouseStyle.INK.b, α)
            push!(text_rows, (pos=pos, name=name, off=fp.offsets[k], font=font, size=size, color=col))
        else  # :poi
            push!(poi_pos, pos)
            push!(poi_fill,   Makie.RGBAf(HouseStyle.PAPER.r, HouseStyle.PAPER.g, HouseStyle.PAPER.b, α))
            push!(poi_stroke, Makie.RGBAf(HouseStyle.INK.r, HouseStyle.INK.g, HouseStyle.INK.b, α))
            font, size, _ = _point_style(:poi, false)
            col = Makie.RGBAf(HouseStyle.GRAY.r, HouseStyle.GRAY.g, HouseStyle.GRAY.b, α)
            push!(text_rows, (pos=pos, name=name, off=fp.offsets[k], font=font, size=size, color=col))
        end
    end

    # halos first, then labels (per-label face/size), then markers on top
    if !isempty(town_halo_pos)
        scatter!(ax, town_halo_pos; color = town_halo_c, markersize = town_halo_sz,
                 strokewidth = 0, inspectable = false)
    end

    for r in text_rows
        text!(ax, r.pos; text = r.name, offset = r.off, markerspace = :pixel,
              fontsize = Float64(r.size), font = r.font, color = r.color,
              align = (:center, :center), inspectable = false)
    end

    if !isempty(town_dot_pos)
        scatter!(ax, town_dot_pos; color = town_dot_c, markersize = town_dot_sz,
                 strokewidth = 0, inspectable = false)
    end
    # POI hollow diamonds (PAPER fill, INK stroke) — distinct from filled town dots
    if !isempty(poi_pos)
        scatter!(ax, poi_pos; marker = :diamond, markersize = 9.0f0,
                 color = poi_fill, strokecolor = poi_stroke, strokewidth = 1.0,
                 inspectable = false)
    end

    return ax
end

"""
    draw_chrome!(ax, fig, d; metrics::AbstractString="")

Masthead "The Atlas" (Newsreader roman display 44, title-case, top-aligned), brass
dateline rule, region "C E N T R A L  C O A S T" (Hanken SemiBold subhead 16,
letterspaced caps, top-aligned), 1.0px BRASS neat-line, corner metrics (Plex Mono 9),
footer (Plex Mono 9 brass).
"""
function draw_chrome!(ax, fig, d::AtlasData; metrics::AbstractString = "")
    W, H = fig.scene.viewport[].widths
    W = Float32(W); H = Float32(H)
    scene = fig.scene

    title_y = H - Float32(_TOP_PAD)   # anchor near the very top, top-aligned text

    # Masthead — Newsreader roman, title-case, top-left, top-aligned
    text!(scene, Point2f(_SIDE_PAD, title_y);
        text = "The Atlas", fontsize = Float64(HouseStyle.RAMP.display),
        font = FACE_TITLE, color = HouseStyle.INK,
        align = (:left, :top), space = :pixel, inspectable = false)

    # Region label — Hanken SemiBold, letterspaced caps, top-right, top-aligned
    text!(scene, Point2f(W - _SIDE_PAD, title_y);
        text = _letterspace("CENTRAL COAST"), fontsize = Float64(HouseStyle.RAMP.subhead),
        font = FACE_LAND_SB, color = HouseStyle.INK,
        align = (:right, :top), space = :pixel, inspectable = false)

    # Brass dateline rule under the masthead (just above the axis top)
    rule_y = H - Float32(_MASTHEAD_H) + 4.0f0
    linesegments!(scene, [Point2f(_SIDE_PAD, rule_y), Point2f(W - _SIDE_PAD, rule_y)];
        color = HouseStyle.BRASS, linewidth = 0.5, space = :pixel, inspectable = false)

    # Neat-line border around the axis bbox (1.0px brass)
    ax_left = Float32(_SIDE_PAD); ax_right = W - Float32(_SIDE_PAD)
    ax_bottom = Float32(_FOOTER_H); ax_top = H - Float32(_MASTHEAD_H)
    linesegments!(scene,
        [Point2f(ax_left,  ax_bottom), Point2f(ax_right, ax_bottom),
         Point2f(ax_right, ax_bottom), Point2f(ax_right, ax_top),
         Point2f(ax_right, ax_top),    Point2f(ax_left,  ax_top),
         Point2f(ax_left,  ax_top),    Point2f(ax_left,  ax_bottom)];
        color = HouseStyle.BRASS, linewidth = 1.0, space = :pixel, inspectable = false)

    # Metrics + footer — Plex Mono (the instrument readout), BRASS caption 9
    if !isempty(metrics)
        text!(scene, Point2f(ax_right - Float32(_SIDE_PAD), ax_bottom + 6.0f0);
            text = metrics, fontsize = Float64(HouseStyle.RAMP.caption),
            font = FACE_MONO, color = HouseStyle.BRASS,
            align = (:right, :bottom), space = :pixel, inspectable = false)
    end

    text!(scene, Point2f(W / 2.0f0, Float32(_FOOTER_H) / 2.0f0);
        text = HouseStyle.footer("The Atlas"), fontsize = Float64(HouseStyle.RAMP.caption),
        font = FACE_MONO, color = HouseStyle.BRASS,
        align = (:center, :center), space = :pixel, inspectable = false)

    return fig
end

# ── Dev-still helper ──────────────────────────────────────────────────────────

"""
    _dev_still(p::Real, path::AbstractString; pagepx=(1600, 1000)) -> path

Render a single honest frame at loop phase `p` and save to `path`. Assembles the
measured+solved frame, builds a fully-visible FadeState, draws basemap → areals →
labels → chrome.
"""
function _dev_still(p::Real, path::AbstractString; pagepx=(1350, 1080))
    d = load_atlas_data()
    fig, ax, af = assemble_frame(d, p; pagepx)
    fp = af.fp

    # FadeState: register births at frame 0, advance _last to FADE_FRAMES → alpha 1.0.
    fs = FadeState()
    update_fade!(fs, fp.ids, 0)
    fs._last = FADE_FRAMES

    # metrics
    n_placed  = count(!, fp.dropped)
    n_town    = count(id -> af.kind_of[id] === :town, fp.ids)
    n_poi     = count(id -> af.kind_of[id] === :poi,  fp.ids)
    n_leaders = 0
    for k in eachindex(fp.ids)
        fp.dropped[k] && continue
        _norm2(fp.offsets[k]) > fp.sizes[k][1] * 0.5 && (n_leaders += 1)
    end
    w     = view_width(p)
    w_str = string(round(w; digits=2))
    ls    = n_leaders == 1 ? "" : "s"
    metrics = "w $(w_str)° · $(n_placed)/$(length(fp.ids)) placed · $(n_leaders) leader$(ls)"

    draw_basemap!(ax, d)
    draw_areals!(ax, af.areals)
    draw_labels!(ax, d, af, fs)
    draw_chrome!(ax, fig, d; metrics)

    save(path, fig)
    return path
end
