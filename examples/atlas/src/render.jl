# render.jl — CairoMakie render layer: basemap + labels + chrome + dev-still helper
#
# Depends on: data.jl, camera.jl, lod.jl, place.jl, fade.jl (all included first in Atlas.jl)
# `using CairoMakie` lives here deliberately — kept out of place.jl.

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

# ── SLO town_id (the brass hero dot) ───────────────────────────────────────
const _SLO_ID = 5   # "San Luis Obispo" — row 5 in towns.csv

# ── Page layout constants ────────────────────────────────────────────────────
const _MASTHEAD_H  = 60.0   # px reserved above the axis for chrome
const _FOOTER_H    = 22.0   # px reserved below the axis
const _SIDE_PAD    = 24.0   # px left/right margin for chrome text
const _CHROME_FONT = HouseStyle.fraunces("9pt-Regular")   # fallback chrome font

"""
    _new_axis(; pagepx=(1600, 1000)) -> (fig, ax)

Create a CairoMakie Figure+Axis sized for the given page (in pixels).
- Axis background = WATER (the ocean base).
- DataAspect so projected map-units render at correct aspect.
- All axis decorations and spines hidden.
"""
function _new_axis(; pagepx=(1600, 1000))
    W, H = pagepx
    fig = Figure(size = (W, H), backgroundcolor = HouseStyle.PAPER)

    # Reserve chrome at top and bottom by inset-positioning the axis.
    ax = Axis(fig;
        bbox = Makie.BBox(_SIDE_PAD, W - _SIDE_PAD,
                          _FOOTER_H, H - _MASTHEAD_H),
        backgroundcolor = WATER,
        aspect = DataAspect(),
        # Hide all decorations and spines
        xgridvisible    = false,
        ygridvisible    = false,
        xticksvisible   = false,
        yticksvisible   = false,
        xlabelvisible   = false,
        ylabelvisible   = false,
        xticklabelsvisible = false,
        yticklabelsvisible = false,
        leftspinevisible   = false,
        rightspinevisible  = false,
        topspinevisible    = false,
        bottomspinevisible = false,
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

# ── Draw functions ────────────────────────────────────────────────────────────

"""
    draw_basemap!(ax, d::AtlasData)

Draw the static basemap layers onto `ax`:
- Water is the Axis background (already set in `_new_axis`).
- Land polygons filled PAPER (no stroke).
- Coastline hairlines in INK at 0.75px (the only 0.75px line in the piece).
- Graticule in BRASS at 0.25px at whole integer degrees.
"""
function draw_basemap!(ax, d::AtlasData)
    # 1. Land fill (PAPER, no stroke) — drawn under coastline
    for ring in d.land
        isempty(ring) && continue
        poly!(ax, ring; color = HouseStyle.PAPER, strokewidth = 0, inspectable = false)
    end

    # 2. Graticule at whole-degree lat/lon intersections (BRASS, 0.25px)
    lon_min, lon_max, lat_min, lat_max = _data_range(d)
    # — lon lines (vertical)
    for lon in lon_min:lon_max
        pts = [Point2f(project_point(lon, lat)) for lat in range(lat_min, lat_max; length=64)]
        lines!(ax, pts; color = HouseStyle.BRASS, linewidth = 0.25, inspectable = false)
    end
    # — lat lines (horizontal)
    for lat in lat_min:lat_max
        pts = [Point2f(project_point(lon, lat)) for lon in range(lon_min, lon_max; length=64)]
        lines!(ax, pts; color = HouseStyle.BRASS, linewidth = 0.25, inspectable = false)
    end

    # 3. Coastline hairline (INK, 0.75px) — drawn on top of land
    for seg in d.coastline
        isempty(seg) && continue
        lines!(ax, seg; color = HouseStyle.INK, linewidth = 0.75, inspectable = false)
    end

    return ax
end

"""
    draw_labels!(ax, d, fp::FramePlacement, fs::FadeState; fontsize=Float64(HouseStyle.RAMP.body))

Draw the label layer for one frame:
- Town dots: INK 3px with 0.5px PAPER halo; SLO gets a BRASS dot.
- Labels: Plex Mono at `fontsize`, INK, placed at solved pixel offset.
- Leaders: BRASS 0.5px linesegments for offset magnitude > half the label box width.
- Markers drawn AFTER leaders so connectors tuck under dots.

`fp.ids[k]` / `fp.anchors[k]` / `fp.offsets[k]` map to Towns by `town_id`.
"""
function draw_labels!(ax, d::AtlasData, fp::FramePlacement, fs::FadeState;
                      fontsize = Float64(HouseStyle.RAMP.body))
    isempty(fp.ids) && return ax

    # Build a town lookup table
    town_by_id = Dict(t.town_id => t for t in d.towns)

    label_font = HouseStyle.plexmono("Regular")

    # --- Leaders (drawn first so dots sit on top) ---
    leader_pts = Point2f[]
    for k in eachindex(fp.ids)
        fp.dropped[k] && continue
        id  = fp.ids[k]
        anc = fp.anchors[k]
        off = fp.offsets[k]
        sz  = fp.sizes[k]
        α   = alpha_of(fs, id)
        α < 0.01 && continue

        # Draw a leader only when the offset is large relative to the box
        # (label pushed far enough that a connector is meaningful).
        mag = _norm2(off)
        threshold = sz[1] * 0.5
        if mag > threshold
            # Anchor-end: trim point_padding (5px) toward label
            dir   = off / mag
            a_end = anc .+ dir .* 5.0f0
            # Label-end: center of the label box face nearest the anchor
            l_end = anc .+ off   # label center in pixel offset from anchor

            push!(leader_pts, a_end)
            push!(leader_pts, l_end)
        end
    end

    if !isempty(leader_pts)
        linesegments!(ax, leader_pts;
            space      = :pixel,
            color      = HouseStyle.BRASS,
            linewidth  = 0.5,
            inspectable = false)
    end

    # --- Town dots (halo then ink dot) ---
    dot_pos       = Point2f[]
    dot_colors    = Makie.RGBAf[]
    halo_pos      = Point2f[]
    halo_colors   = Makie.RGBAf[]
    dot_markersize = Float32[]
    halo_markersize= Float32[]

    for k in eachindex(fp.ids)
        fp.dropped[k] && continue
        id = fp.ids[k]
        t  = get(town_by_id, id, nothing)
        t === nothing && continue
        α = alpha_of(fs, id)

        ink_c  = id == _SLO_ID ? HouseStyle.BRASS : HouseStyle.INK
        paper_c = HouseStyle.PAPER

        push!(halo_pos, t.pos)
        push!(halo_colors, Makie.RGBAf(paper_c.r, paper_c.g, paper_c.b, α))
        push!(halo_markersize, 4.0f0)   # slightly larger halo

        push!(dot_pos, t.pos)
        push!(dot_colors, Makie.RGBAf(ink_c.r, ink_c.g, ink_c.b, α))
        push!(dot_markersize, 3.0f0)
    end

    # Halo first (paper ring), then ink dot on top
    if !isempty(halo_pos)
        scatter!(ax, halo_pos;
            color       = halo_colors,
            markersize  = halo_markersize,
            strokewidth = 0,
            inspectable = false)
    end

    # --- Labels ---
    text_pos     = Point2f[]
    text_strings = String[]
    text_offsets = Vec2f[]
    text_alphas  = Float32[]

    for k in eachindex(fp.ids)
        fp.dropped[k] && continue
        id = fp.ids[k]
        t  = get(town_by_id, id, nothing)
        t === nothing && continue
        α = alpha_of(fs, id)
        α < 0.01 && continue

        push!(text_pos,     fp.anchors[k])
        push!(text_strings, t.name)
        push!(text_offsets, fp.offsets[k])
        push!(text_alphas,  α)
    end

    if !isempty(text_pos)
        text!(ax, text_pos;
            text        = text_strings,
            offset      = text_offsets,
            markerspace = :pixel,
            fontsize    = fontsize,
            font        = label_font,
            color       = [Makie.RGBAf(HouseStyle.INK.r, HouseStyle.INK.g,
                                        HouseStyle.INK.b, α) for α in text_alphas],
            align       = (:center, :center),
            inspectable = false)
    end

    # Ink dots drawn after labels (on top)
    if !isempty(dot_pos)
        scatter!(ax, dot_pos;
            color       = dot_colors,
            markersize  = dot_markersize,
            strokewidth = 0,
            inspectable = false)
    end

    return ax
end

"""
    draw_chrome!(ax, fig, d; metrics::AbstractString="")

Draw all non-map chrome onto `fig` (in pixel / relative space):
- Masthead: "THE ATLAS" in Fraunces display (44pt), INK, upper-left.
- A brass dateline rule beneath the masthead text.
- Region label: "CENTRAL COAST" in Fraunces title (22pt), INK, upper-right.
- 1.0px BRASS neat-line border around the axis bbox.
- Corner cartouche (lower-right of axis): scale bar label + metrics line in Plex Mono 9.
- Footer: `HouseStyle.footer("The Atlas")` in Plex Mono 9, BRASS, bottom-center.

`metrics` is a short descriptor string, e.g. `"w 0.55° · 17/17 placed · 1 leader"`.
"""
function draw_chrome!(ax, fig, d::AtlasData; metrics::AbstractString = "")
    W, H = fig.scene.viewport[].widths
    W = Float32(W); H = Float32(H)

    scene = fig.scene

    # ── Masthead "THE ATLAS" ──────────────────────────────────────────────────
    text!(scene, Point2f(_SIDE_PAD, H - _MASTHEAD_H * 0.25f0);
        text        = "THE ATLAS",
        fontsize    = Float64(HouseStyle.RAMP.display),
        font        = HouseStyle.fraunces("144pt-Regular"),
        color       = HouseStyle.INK,
        align       = (:left, :center),
        space       = :pixel,
        inspectable = false)

    # Brass dateline rule under masthead
    rule_y = H - _MASTHEAD_H + 2.0f0
    linesegments!(scene,
        [Point2f(_SIDE_PAD, rule_y), Point2f(W - _SIDE_PAD, rule_y)];
        color       = HouseStyle.BRASS,
        linewidth   = 0.5,
        space       = :pixel,
        inspectable = false)

    # ── Region label "CENTRAL COAST" ─────────────────────────────────────────
    text!(scene, Point2f(W - _SIDE_PAD, H - _MASTHEAD_H * 0.25f0);
        text        = "CENTRAL COAST",
        fontsize    = Float64(HouseStyle.RAMP.title),
        font        = HouseStyle.fraunces("144pt-Regular"),
        color       = HouseStyle.INK,
        align       = (:right, :center),
        space       = :pixel,
        inspectable = false)

    # ── Neat-line border around axis ─────────────────────────────────────────
    # The axis bbox (in figure-pixel space, origin = bottom-left of figure)
    ax_left   = Float32(_SIDE_PAD)
    ax_right  = W - Float32(_SIDE_PAD)
    ax_bottom = Float32(_FOOTER_H)
    ax_top    = H - Float32(_MASTHEAD_H)

    linesegments!(scene,
        [Point2f(ax_left,  ax_bottom), Point2f(ax_right, ax_bottom),
         Point2f(ax_right, ax_bottom), Point2f(ax_right, ax_top),
         Point2f(ax_right, ax_top),    Point2f(ax_left,  ax_top),
         Point2f(ax_left,  ax_top),    Point2f(ax_left,  ax_bottom)];
        color       = HouseStyle.BRASS,
        linewidth   = 1.0,
        space       = :pixel,
        inspectable = false)

    # ── Corner cartouche (lower-right inside axis) ────────────────────────────
    cart_x = ax_right  - Float32(_SIDE_PAD)
    cart_y = ax_bottom + 6.0f0
    footer_font = HouseStyle.plexmono("Regular")

    if !isempty(metrics)
        text!(scene, Point2f(cart_x, cart_y);
            text        = metrics,
            fontsize    = Float64(HouseStyle.RAMP.caption),
            font        = footer_font,
            color       = HouseStyle.BRASS,
            align       = (:right, :bottom),
            space       = :pixel,
            inspectable = false)
    end

    # ── Footer ────────────────────────────────────────────────────────────────
    text!(scene, Point2f(W / 2.0f0, Float32(_FOOTER_H) / 2.0f0);
        text        = HouseStyle.footer("The Atlas"),
        fontsize    = Float64(HouseStyle.RAMP.caption),
        font        = footer_font,
        color       = HouseStyle.BRASS,
        align       = (:center, :center),
        space       = :pixel,
        inspectable = false)

    return fig
end

# ── Dev-still helper ──────────────────────────────────────────────────────────

"""
    _dev_still(p::Real, path::AbstractString; pagepx=(1600, 1000)) -> path

Render a single-frame dev still at loop phase `p ∈ [0,1)` and save to `path`.

Steps:
1. Load AtlasData.
2. Create a fresh figure+axis via `_new_axis`.
3. Set limits to `camera_rect(p)` and call `update_state_before_display!`.
4. Project active town anchors to pixel space; filter to those within the
   page rect (expanded by 80px) to avoid wild off-screen projections.
5. Measure label boxes, solve placement (no warm-start, no settled labels).
6. Build a fully-visible FadeState (all active labels registered FADE_FRAMES
   frames in the past so `alpha_of` returns 1.0).
7. Draw basemap → labels → chrome.
8. Save and return the path.
"""
function _dev_still(p::Real, path::AbstractString; pagepx=(1600, 1000))
    d = load_atlas_data()

    fig, ax = _new_axis(; pagepx)

    # Set the camera for this phase
    xmin, xmax, ymin, ymax = camera_rect(p)
    limits!(ax, xmin, xmax, ymin, ymax)

    # Force the camera matrices to update NOW (confirmed by spike_timing.jl)
    Makie.update_state_before_display!(fig)

    W, H = Float32.(pagepx)

    # Page rect (pixel space) expanded by a margin for off-screen filtering
    margin = 80.0f0
    page_rect = Rect2f(-margin, -margin, W + 2margin, H + 2margin)

    # Active town ids at this view width
    w = view_width(p)
    ids = active_ids(d.towns, w, Int[])

    # Project each active town to pixel space and filter to on-screen
    town_by_id = Dict(t.town_id => t for t in d.towns)

    valid_ids    = Int[]
    px_anchors   = Point2f[]

    for id in ids
        t = town_by_id[id]
        px = _data_to_px(ax, t.pos)
        # Filter: reject anchors that project wildly off-screen
        if px[1] >= page_rect.origin[1] &&
           px[1] <= page_rect.origin[1] + page_rect.widths[1] &&
           px[2] >= page_rect.origin[2] &&
           px[2] <= page_rect.origin[2] + page_rect.widths[2]
            push!(valid_ids, id)
            push!(px_anchors, px)
        end
    end

    # Measure label boxes for valid towns
    names = [town_by_id[id].name for id in valid_ids]
    sizes = isempty(names) ? Vec2f[] : measure_boxes(names)

    # Solve placement (cold start — no warm-start for a single still)
    bounds = Rect2f(0, 0, W, H)
    fp = if isempty(valid_ids)
        FramePlacement(Int[], Point2f[], Vec2f[], Vec2f[], BitVector())
    else
        solve_frame(valid_ids, px_anchors, sizes, bounds;
                    prev    = Dict{Int, Vec2f}(),
                    settled = Set{Int}())
    end

    # Build a FadeState with all labels fully visible (born FADE_FRAMES frames ago)
    fs = FadeState()
    update_fade!(fs, valid_ids, FADE_FRAMES)   # frame = FADE_FRAMES → age ≥ FADE_FRAMES → alpha = 1.0

    # Count leaders for metrics string
    n_placed  = count(!, fp.dropped)
    n_leaders = 0
    if !isempty(fp.ids)
        for k in eachindex(fp.ids)
            fp.dropped[k] && continue
            mag = _norm2(fp.offsets[k])
            sz  = fp.sizes[k]
            mag > sz[1] * 0.5 && (n_leaders += 1)
        end
    end

    w_str   = string(round(w; digits=2))
    ls      = n_leaders == 1 ? "" : "s"
    metrics = "w $(w_str)° · $(n_placed)/$(length(valid_ids)) placed · $(n_leaders) leader$(ls)"

    # Draw layers in order
    draw_basemap!(ax, d)
    draw_labels!(ax, d, fp, fs)
    draw_chrome!(ax, fig, d; metrics)

    save(path, fig)
    return path
end
