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
    _new_axis(; pagepx=(1600, 1000)) -> (fig, ax)

CairoMakie Figure+Axis sized for the page (px). WATER axis background, DataAspect,
all decorations/spines hidden. Chrome space reserved top/bottom via the bbox inset.
"""
function _new_axis(; pagepx=(1600, 1000))
    W, H = pagepx
    fig = Figure(size = (W, H), backgroundcolor = HouseStyle.PAPER)

    ax = Axis(fig;
        bbox = Makie.BBox(_SIDE_PAD, W - _SIDE_PAD,
                          _FOOTER_H, H - _MASTHEAD_H),
        backgroundcolor = WATER,
        aspect = DataAspect(),
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

"Measure ONE areal's text box (w,h) in px via TextMeasure at its own fontsize."
function _measure_areal_box(a::Areal)
    only(measure_boxes([a.text]; fontsize = a.fontsize, font = HouseStyle.plexmono("Regular")))
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
function assemble_frame(d::AtlasData, p::Real; pagepx=(1600, 1000))
    fig, ax = _new_axis(; pagepx)
    limits!(ax, camera_rect(p)...)
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
    kind_of  = Dict{Int,Symbol}()

    for id in tids
        t  = town_by_id[id]
        px = _data_to_px(ax, t.pos)
        _in_rect(px, page_rect) || continue
        push!(ids, id); push!(px_anch, px); push!(names, t.name)
        kind_of[id] = :town
    end
    for (k, poi) in enumerate(pois)
        px = _data_to_px(ax, poi.pos)
        _in_rect(px, page_rect) || continue
        pid = _POI_BASE + k
        push!(ids, pid); push!(px_anch, px); push!(names, poi.name)
        kind_of[pid] = :poi
    end

    # --- (b) MEASURE every point label (TextMeasure) ---
    sizes = isempty(names) ? Vec2f[] : measure_boxes(names)

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

    # areals: measure each, project its anchor, add its rotated AABB as an obstacle
    areals = Tuple{String,Point2f,Float64,Symbol}[]
    for a in atlas_areals()
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

Draw rotated, letterspaced region labels at their PIXEL anchors (space=:pixel) so the
rotation is screen-true. Drawn UNDER the point labels (towns/POIs sit on top); the
solver already keeps point labels off these via obstacle footprints.
Colors: water/bay = WATER_LINE, range = HouseStyle.GRAY.
"""
function draw_areals!(ax, areals)
    for (text, apx, rot, kind) in areals
        col = kind === :range ? HouseStyle.GRAY : WATER_LINE
        spaced = join(collect(text), " ")   # fake letterspacing
        # font size baked into the obstacle measurement is recovered per-areal below
        text!(ax, apx;
            text        = spaced,
            rotation    = deg2rad(rot),
            fontsize    = _areal_fontsize(text),
            font        = HouseStyle.plexmono("Regular"),
            color       = col,
            align       = (:center, :center),
            space       = :pixel,
            inspectable = false)
    end
    return ax
end

# Map an areal's text back to its declared fontsize (single source of truth = atlas_areals()).
function _areal_fontsize(text::AbstractString)
    for a in atlas_areals()
        a.text == text && return a.fontsize
    end
    Float64(HouseStyle.RAMP.subhead)
end

"""
    draw_labels!(ax, d, af::AssembledFrame, fs::FadeState; fontsize=14.0)

Draw the point-label layer (towns + POIs) for one frame from the solved placement:
- leaders (BRASS 0.5px) for labels pushed far from their anchor — drawn first;
- markers: town dots (INK, brass SLO hero) with PAPER halo; POIs a hollow INK
  diamond (PAPER fill, INK stroke) to read distinctly from filled town dots;
- labels: Plex Mono `fontsize`, INK for towns, GRAY for POIs, at the solved offset.
"""
function draw_labels!(ax, d::AtlasData, af::AssembledFrame, fs::FadeState; fontsize = 14.0)
    fp = af.fp
    isempty(fp.ids) && return ax

    town_by_id = Dict(t.town_id => t for t in d.towns)
    pois       = atlas_pois()
    label_font = HouseStyle.plexmono("Regular")

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

    # --- collect per-feature draw data ---
    town_halo_pos = Point2f[]; town_halo_c = Makie.RGBAf[]; town_halo_sz = Float32[]
    town_dot_pos  = Point2f[]; town_dot_c  = Makie.RGBAf[]; town_dot_sz  = Float32[]
    poi_pos       = Point2f[]; poi_fill    = Makie.RGBAf[]; poi_stroke   = Makie.RGBAf[]
    text_pos = Point2f[]; text_str = String[]; text_off = Vec2f[]; text_col = Makie.RGBAf[]

    for k in eachindex(fp.ids)
        fp.dropped[k] && continue
        id = fp.ids[k]
        α  = alpha_of(fs, id)
        α < 0.01 && continue
        pos, name, kind = feature(id)

        if kind === :town
            is_slo  = id == _SLO_ID
            ink_c   = is_slo ? HouseStyle.BRASS : HouseStyle.INK
            t       = town_by_id[id]
            is_major = t.rank ≤ 5
            dsz     = is_slo ? 11.0f0 : (is_major ? 8.0f0 : 7.0f0)
            push!(town_halo_pos, pos)
            push!(town_halo_c, Makie.RGBAf(HouseStyle.PAPER.r, HouseStyle.PAPER.g, HouseStyle.PAPER.b, α))
            push!(town_halo_sz, dsz + 4.0f0)
            push!(town_dot_pos, pos)
            push!(town_dot_c, Makie.RGBAf(ink_c.r, ink_c.g, ink_c.b, α))
            push!(town_dot_sz, dsz)
            push!(text_col, Makie.RGBAf(HouseStyle.INK.r, HouseStyle.INK.g, HouseStyle.INK.b, α))
        else  # :poi
            push!(poi_pos, pos)
            push!(poi_fill,   Makie.RGBAf(HouseStyle.PAPER.r, HouseStyle.PAPER.g, HouseStyle.PAPER.b, α))
            push!(poi_stroke, Makie.RGBAf(HouseStyle.INK.r, HouseStyle.INK.g, HouseStyle.INK.b, α))
            push!(text_col, Makie.RGBAf(HouseStyle.GRAY.r, HouseStyle.GRAY.g, HouseStyle.GRAY.b, α))
        end

        push!(text_pos, pos)               # DATA anchor + solved pixel offset
        push!(text_str, name)
        push!(text_off, fp.offsets[k])
    end

    # halos first, then labels, then markers on top
    if !isempty(town_halo_pos)
        scatter!(ax, town_halo_pos; color = town_halo_c, markersize = town_halo_sz,
                 strokewidth = 0, inspectable = false)
    end

    if !isempty(text_pos)
        text!(ax, text_pos; text = text_str, offset = text_off, markerspace = :pixel,
              fontsize = fontsize, font = label_font, color = text_col,
              align = (:center, :center), inspectable = false)
    end

    # town ink dots
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

Masthead "THE ATLAS" (Fraunces display, top-aligned so it clears the edge), brass
dateline rule, region "CENTRAL COAST" (Fraunces title, top-aligned), 1.0px BRASS
neat-line, corner cartouche/metrics (Plex Mono 9), footer (Plex Mono 9 brass).
"""
function draw_chrome!(ax, fig, d::AtlasData; metrics::AbstractString = "")
    W, H = fig.scene.viewport[].widths
    W = Float32(W); H = Float32(H)
    scene = fig.scene

    title_y = H - Float32(_TOP_PAD)   # anchor near the very top, top-aligned text

    # Masthead — top-left, top-aligned so the cap-line clears the page edge
    text!(scene, Point2f(_SIDE_PAD, title_y);
        text = "THE ATLAS", fontsize = Float64(HouseStyle.RAMP.display),
        font = HouseStyle.fraunces("144pt-Regular"), color = HouseStyle.INK,
        align = (:left, :top), space = :pixel, inspectable = false)

    # Region label — top-right, top-aligned
    text!(scene, Point2f(W - _SIDE_PAD, title_y);
        text = "CENTRAL COAST", fontsize = Float64(HouseStyle.RAMP.title),
        font = HouseStyle.fraunces("144pt-Regular"), color = HouseStyle.INK,
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

    footer_font = HouseStyle.plexmono("Regular")

    if !isempty(metrics)
        text!(scene, Point2f(ax_right - Float32(_SIDE_PAD), ax_bottom + 6.0f0);
            text = metrics, fontsize = Float64(HouseStyle.RAMP.caption),
            font = footer_font, color = HouseStyle.BRASS,
            align = (:right, :bottom), space = :pixel, inspectable = false)
    end

    text!(scene, Point2f(W / 2.0f0, Float32(_FOOTER_H) / 2.0f0);
        text = HouseStyle.footer("The Atlas"), fontsize = Float64(HouseStyle.RAMP.caption),
        font = footer_font, color = HouseStyle.BRASS,
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
function _dev_still(p::Real, path::AbstractString; pagepx=(1600, 1000))
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
    metrics = "w $(w_str)° · $(n_placed)/$(length(fp.ids)) placed · $(n_town)t $(n_poi)p · $(length(af.obstacles)) obs · $(n_leaders) leader$(ls)"

    draw_basemap!(ax, d)
    draw_areals!(ax, af.areals)
    draw_labels!(ax, d, af, fs)
    draw_chrome!(ax, fig, d; metrics)

    save(path, fig)
    return path
end
