# SPDX-License-Identifier: MIT
# render.jl — CairoMakie render layer: basemap + measured/solved labels + areals + chrome
#
# Depends on: data.jl, pois.jl, camera.jl, lod.jl, place.jl
# `using CairoMakie` lives here deliberately — kept out of place.jl.
#
# HONESTY INVARIANT: every point label (town + POI) is MEASURED by TextMeasure
# (measure_boxes) and PLACED by MakieTextRepel (warm_solve, via solve_frame).
# Rotated region "areals" are likewise MEASURED, and their footprints + sampled
# coastline vertices are fed back in as solver OBSTACLES so the label field stays
# clear of them. The only hand-positioned values anywhere are feature anchors
# (Town.pos / POI.pos / Areal.pos) — never a label's final screen position.

using CairoMakie, Makie
using GeometryBasics: Point2f, Vec2f, Rect2f

# Inline 2-D vector magnitude (avoids LinearAlgebra stdlib dep declaration)
_norm2(v::Vec2f) = sqrt(v[1]^2 + v[2]^2)

"Min-dimension overlap (px) of two boxes; >0 ⇒ they overlap in both axes."
function _box_ovl(a::Rect2f, b::Rect2f)
    ox = min(a.origin[1]+a.widths[1], b.origin[1]+b.widths[1]) - max(a.origin[1], b.origin[1])
    oy = min(a.origin[2]+a.widths[2], b.origin[2]+b.widths[2]) - max(a.origin[2], b.origin[2])
    min(ox, oy)
end

"""
Leader length: distance from the anchor (dot) to the NEAREST point of a label box at offset
`off` with size `sz`. This is the visible gap a leader would span — NOT the centre offset
(which grows with label WIDTH, so wide labels at their natural upper-right rest position have a
large centre offset but a tiny leader). 0 when the box covers the dot.
"""
function _leader_len(off::Vec2f, sz::Vec2f)
    nx = clamp(0f0, off[1]-sz[1]/2, off[1]+sz[1]/2)
    ny = clamp(0f0, off[2]-sz[2]/2, off[2]+sz[2]/2)
    sqrt(nx^2 + ny^2)
end

"Total px the box `a` pokes outside rect `b` (0 when fully inside)."
function _oob(a::Rect2f, b::Rect2f)
    max(0f0, b.origin[1]-a.origin[1]) + max(0f0, b.origin[2]-a.origin[2]) +
    max(0f0, (a.origin[1]+a.widths[1])-(b.origin[1]+b.widths[1])) +
    max(0f0, (a.origin[2]+a.widths[2])-(b.origin[2]+b.widths[2]))
end

"""
Candidate seed offsets in Imhof preference order (best first): the label box placed with its
near corner/edge ~_SEED_PAD off the dot, in 8 compass directions.
"""
function _seed_candidates(sz::Vec2f)
    hw = sz[1]/2 + _SEED_PAD; hh = sz[2]/2 + _SEED_PAD
    (Vec2f(hw, hh), Vec2f(hw, -hh), Vec2f(-hw, hh), Vec2f(-hw, -hh),
     Vec2f(hw, 0f0), Vec2f(-hw, 0f0), Vec2f(0f0, hh), Vec2f(0f0, -hh))
end

"""
    _choose_seed(anchor, sz, obstacles, placed, bounds) -> Vec2f

Geography-aware seed: of the 8 candidate directions, pick the one whose label box least
overlaps the obstacles (coast + areals), the already-placed neighbour labels, and the frame
bounds. This is what makes a coastal feature's label seed to the OPEN-WATER side (away from the
crowded land + the coastline), instead of always upper-right. Imhof order breaks ties toward
the upper-right. The solver then relaxes from this seed.
"""
function _choose_seed(anchor::Point2f, sz::Vec2f, obstacles, placed, bounds::Rect2f)
    hw = sz[1]/2; hh = sz[2]/2
    best = Vec2f(hw+_SEED_PAD, hh+_SEED_PAD); bestscore = Inf32
    for (i, off) in enumerate(_seed_candidates(sz))
        c = anchor .+ off
        box = Rect2f(c[1]-hw, c[2]-hh, sz[1], sz[2])
        s = 0f0
        for o in obstacles; ov = _box_ovl(box, o); ov > 0 && (s += ov); end
        for b in placed;    ov = _box_ovl(box, b); ov > 0 && (s += ov); end
        s += 2f0 * _oob(box, bounds)        # staying on-frame matters more than a little overlap
        s += 0.02f0 * i                     # Imhof tiebreak → prefer upper-right
        s < bestscore && (bestscore = s; best = off)
    end
    best
end

# ── Palette (water colors not in HouseStyle) ────────────────────────────────
const WATER      = Makie.RGBf((0xD2, 0xDC, 0xDF) ./ 255...)   # deeper/cooler sea field
const WATER_LINE = Makie.RGBf((0x9F, 0xB2, 0xBA) ./ 255...)
const WATER_INK  = Makie.RGBf((0x5E, 0x77, 0x85) ./ 255...)   # deeper water ink for italic hydrography

# ── Field-survey type system (faces) ─────────────────────────────────────────
# Land = Hanken Grotesk · Water/hydrography = Newsreader italic · Title = Newsreader
# roman · Mono = Plex Mono (instrument readout only).
const FACE_LAND    = HouseStyle.hanken("Regular")     # settlements, POIs, terrain
const FACE_LAND_SB = HouseStyle.hanken("SemiBold")    # major settlements + region legend
const FACE_WATER   = joinpath(HouseStyle.FONTS_DIR, "Newsreader", "Newsreader-Italic.ttf")  # hydrography
const FACE_TITLE   = joinpath(HouseStyle.FONTS_DIR, "Newsreader", "Newsreader.ttf")          # masthead serif
const FACE_TITLE_IT = FACE_WATER  # Newsreader italic — the serif-italic run of the masthead
const FACE_MONO    = HouseStyle.plexmono("Regular")   # metrics / scale readout ONLY

# Convenience: project a data-space Point2f to pixel coordinates.
# IMPORTANT: call Makie.update_state_before_display!(fig) BEFORE using this.
_data_to_px(ax, p::Point2f) = Point2f(Makie.project(ax.scene, :data, :pixel, p)[Vec(1, 2)])

# ── Feature ids ─────────────────────────────────────────────────────────────
const _SLO_ID  = 5      # "San Luis Obispo" — row 5 in towns.csv (the brass hero)
const _POI_BASE = 1000  # POI synthetic ids = _POI_BASE + index (disjoint from town_ids)

# Pin SLO's label at a fixed offset (see assemble_frame). The A/B confirmed the pin HELPS
# (fewer contested-cluster flips with it on), so it's kept on; the Ref stays as a toggle.
const _PIN_SLO = Ref(true)

# Occlusion cull: a label fades to 0 as a higher-priority box overlaps it by up to this many
# px (min dimension); a smooth ramp so a label sitting on a higher one holds steady, not strobes.
const _CULL_HIDE = 12.0

# ── Page layout constants ────────────────────────────────────────────────────
# Trimmed from the first pass (operator: "frame a bit too big") — less dead margin,
# taller masthead so the title clears the top edge and the neat-line sits below it.
const _MASTHEAD_H  = 100.0  # px reserved above the axis for chrome (taller → big title clears)
const _FOOTER_H    = 14.0   # px reserved below the axis (footer text removed → thin margin)
const _SIDE_PAD    = 16.0   # px left/right margin for chrome text
const _TOP_PAD     = 14.0   # px from the very top edge to the masthead title (top-aligned)

# ── Masthead type sizes (hierarchy: title ≫ region > in-map labels) ───────────
const _TITLE_PX   = 52.0    # "The Atlas" — the emphasis (Newsreader italic serif)
const _IMPRINT_PX = 42.0    # "TextMeasure.jl ·" imprint (Hanken SemiBold) — near the title, not equal
const _REGION_PX  = 24.0    # "CENTRAL COAST" — subordinate, shares the title's CAP centreline
# Cap-top as a fraction of font size, MEASURED per face (FreeType 'H' ink height): used to
# place each run's baseline so the CAPITALS share one centre line. ÷2 = cap centre ÷ baseline.
const _CAP_NEWS   = 0.335f0 # Newsreader italic (cap 0.67)
const _CAP_HANK   = 0.349f0 # Hanken Grotesk   (cap 0.697)

# ── Obstacle tuning ──────────────────────────────────────────────────────────
const _COAST_STRIDE  = 2     # sample every Nth smoothed coastline vertex (dense barrier)
const _COAST_BOX     = 14.0  # px side of each coastline obstacle box (fully overlaps → wall)
const _COAST_MAX     = 400   # cap total coastline obstacle boxes (keeps the solve fast)
const _AREAL_OBSTACLE_STRIDE = 2   # subsample every Nth per-glyph areal box for obstacles

# ── In-map type ceiling (hierarchy: title > region > map labels) ──────────────
# The masthead must read as the largest type on the page. "The Atlas" is display 44;
# "Central Coast" is deck 31; every IN-MAP label is capped here so a deep-zoom town can
# never out-size the chrome. The geographic font_px still drives the FADE (band_alpha on
# the true size); only the DRAWN/solved size is clamped.
const MAX_LABEL_PX = 48.0    # in-map ceiling: labels SCALE with zoom up to here (just under the
                             # title 52), so type grows through the dive instead of flatlining
const MAX_AREAL_PX = 220.0   # high SAFETY ceiling only — areals scale with altitude (clouds);
                             # the wide-shot size is held under the title via per-areal `ground`
const _AREAL_OBSTACLE_ALPHA = 0.5  # areal acts as a solver obstacle only while this opaque

# ── Viewport edge fade (don't draw labels for off-screen features; no edge pop) ──
# A label's opacity ramps to 0 as its anchor nears the neat-line and is 0 outside the
# visible map rect — so features outside the view aren't labelled, and ones crossing the
# edge during the dive fade instead of popping (kills edge flicker).
const _EDGE_RAMP   = 40.0    # px inside the neat-line over which a label fades 0→1
const _OBS_MARGIN  = 48.0    # px beyond the neat-line still sampled for coast/areal obstacles

# ── Leader cap (no long stray wires crossing areals) ──────────────────────────
# If the solver pushes a label's center beyond this from its anchor, the leader reads as a
# stray wire (and tends to cross an areal); drop the label instead. Stable frame-to-frame
# because the camera + warm-start move offsets smoothly, so the same labels drop each frame.
const _LEADER_MAX  = 46.0    # px LEADER length (dot→nearest edge) at which a label is fully gone
const _LEADER_RAMP = 14.0    # px ramp below _LEADER_MAX over which it fades out (no hard pop)
const _LEADER_DRAW = 12.0    # px leader length above which a connector line is actually drawn

# ── Areal recede (regions step back as towns/landmarks take focus) ────────────
# At the wide overview an areal is the subject (full opacity); as the camera dives to town
# scale it recedes to a faint orientation mark. Multiplier by view width (degrees).
const _AREAL_W_HI  = 1.30    # at/above this width: areals at full weight
const _AREAL_W_LO  = 0.75    # at/below this width: areals at the recede floor
const _AREAL_FLOOR = 0.24    # faint cloud floor at depth — present, but towns read over it

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
    _new_axis(; pagepx=(1620, 1080)) -> (fig, ax)

CairoMakie Figure+Axis sized for the page (px, default 5:4). WATER axis background,
all decorations/spines hidden. NO DataAspect — the axis FILLS its bbox; the camera
window (camera_rect) is matched to the content aspect so geography isn't distorted.
Chrome space reserved top/bottom via the bbox inset.
"""
function _new_axis(; pagepx=(1620, 1080))
    W, H = pagepx
    fig = Figure(size = (W, H), backgroundcolor = HouseStyle.PAPER)

    ax = Axis(fig;
        bbox = Makie.BBox(_SIDE_PAD, W - _SIDE_PAD,
                          _FOOTER_H, H - _MASTHEAD_H),
        backgroundcolor = HouseStyle.PAPER,   # LAND is the base; the sea is a polygon (see draw_basemap!)
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

"""
    _edge_alpha(px, cw, ch; ramp=_EDGE_RAMP) -> Float64

Opacity factor from an anchor's position relative to the visible map rect `[0,cw]×[0,ch]`
(axis-scene px, the frame `_data_to_px` returns). 0 outside / on the neat-line, ramping
smoothly to 1 once the anchor is `ramp` px inside. Multiplied into a label's band-opacity
so off-screen features are unlabelled and edge-crossing ones fade instead of popping.
"""
function _edge_alpha(px, cw::Real, ch::Real; ramp::Real = _EDGE_RAMP)
    d = min(px[1], cw - px[1], px[2], ch - px[2])   # signed distance to nearest edge
    d <= 0 ? 0.0 : smoothstep(d / ramp)
end

"""
    _areal_recede(w_deg) -> Float64

Opacity multiplier that lets region areals step back as the camera dives: 1.0 at the wide
overview (`w ≥ _AREAL_W_HI`), easing to `_AREAL_FLOOR` at town scale (`w ≤ _AREAL_W_LO`).
"""
function _areal_recede(w_deg::Real)
    t = smoothstep((w_deg - _AREAL_W_LO) / (_AREAL_W_HI - _AREAL_W_LO))
    _AREAL_FLOOR + (1.0 - _AREAL_FLOOR) * t
end

# ── Per-label type roles + measure-once-then-scale ───────────────────────────
# HONESTY: each label is MEASURED ONCE at a reference size (its actual face), giving a
# unit box; the per-frame box is that unit box scaled by font_px/_REF_PX. We never
# re-measure per size — the box scales linearly with the dynamic geographic font_px,
# and the label is DRAWN at exactly that font_px. (`measure_label` stays for one-offs.)

const _REF_PX = 100.0   # reference size for the single per-label measurement

# Measure-once caches. A label/glyph's reference box depends ONLY on (string, font) at
# _REF_PX — never on font_px, anchor, or frame — yet `assemble_frame` runs per frame
# (×360). Without caching, every town/POI box and every areal glyph advance was re-measured
# on each frame; these caches make "measure once, layout many" literally true. Keys fully
# determine the measurement (fonts are module consts), so there is no staleness hazard.
# SINGLE-THREADED ONLY: bare `Dict` + `get!` is race-free here solely because frame assembly
# is the serial loop in `loop.jl`. Parallelising frames (`Threads.@threads`) would need a
# lock or per-thread caches.
const _UNITBOX_CACHE  = Dict{Tuple{String,String}, Vec2f}()    # (name, font)  → ref box (w,h)
const _CHARADV_CACHE  = Dict{Tuple{Char,String}, Float32}()    # (char, font)  → ref advance
const _SPACEADV_CACHE = Dict{String, Float32}()                # font          → ref space advance

"Measure ONE label string at its actual (font, size) → pixel box (w,h)."
measure_label(name, font, size) = only(measure_boxes([name]; font = font, fontsize = Float64(size)))

"Unit box (w,h px) of `name` in `font`, measured ONCE at _REF_PX (cached). Scale by font_px/_REF_PX."
_unit_box(name, font) = get!(_UNITBOX_CACHE, (String(name), font)) do
    measure_label(name, font, _REF_PX)
end

"Scale a unit box (measured at _REF_PX) to the given on-screen font_px."
_scaled_box(unit::Vec2f, fpx::Real) = Vec2f(unit .* Float32(fpx / _REF_PX))


"Letterspace a caps string the way it's drawn (and therefore measured)."
_letterspace(s) = join(collect(s), " ")

"""
Resolve a point feature (town/POI) to its drawn (face, color_role). Size is now DYNAMIC
(geographic), so it is NOT part of the style — see font_px / lod.jl.
- Major towns (rank ≤ 5): Hanken SemiBold, ink.
- Minor towns: Hanken Regular, ink.
- POIs (landmarks): Hanken Regular, gray.
"""
function _point_style(kind::Symbol, is_major::Bool)
    if kind === :town
        is_major ? (FACE_LAND_SB, :ink) : (FACE_LAND, :ink)
    else  # :poi
        (FACE_LAND, :gray)
    end
end

"""
The drawn string + face for an areal:
- :water → Newsreader italic, TITLE-CASE.
- :range → Hanken, caps (per-glyph `tracking` gives the breathing room; no space hack).
Returns `(drawn_string, font)`.
"""
function _areal_drawn(a::Areal)
    a.kind === :range ? (a.text, FACE_LAND) : (titlecase(a.text), FACE_WATER)
end

"""
True advance (px) of a single space at _REF_PX for `font` — measured by difference, since
a lone `" "` is whitespace-trimmed to width 0 by the layout engine. `adv(\"x x\") − adv(\"xx\")`
recovers the inter-word advance, keeping it TextMeasure-derived (no hand-picked gap).
"""
function _space_advance(font)
    get!(_SPACEADV_CACHE, font) do
        Float32(measure_label("x x", font, _REF_PX)[1] - measure_label("xx", font, _REF_PX)[1])
    end
end

"Reference advance (px) of a single non-space glyph in `font` at _REF_PX (cached): its box width IS \
the advance (no kerning). Spaces never reach here — they use `_space_advance` (difference-of-two)."
_char_ref_advance(c::Char, font) = get!(_CHARADV_CACHE, (c, font)) do
    Float32(measure_label(string(c), font, _REF_PX)[1])
end

"Per-char advance (px) of `s` at `fpx`, measured ONCE at _REF_PX and scaled. No kerning."
function _char_advances(s::AbstractString, font, fpx::Real)
    chars = collect(s)
    scale = Float32(fpx / _REF_PX)
    sp    = _space_advance(font)                  # recovered space advance (lone space → 0)
    # each char's reference advance is measured once and reused; substitute the recovered
    # advance for spaces so words don't collapse together.
    [(c == ' ' ? sp : _char_ref_advance(c, font)) * scale for c in chars]
end

"""
    _areal_glyphs(a, apx, fpx) -> (glyphs, boxes)

Lay areal `a`'s drawn string glyph-by-glyph along a circular arc centered on pixel anchor
`apx`, at on-screen size `fpx`. Each glyph is MEASURED (its advance) by TextMeasure and
single-measure-scaled. `a.sweep` is the signed total bend (deg) across the baseline (0 =
straight), `a.rotation` the base tilt, `a.tracking` extra px (fraction of fpx) per advance.

Returns:
- `glyphs::Vector{(char::Char, pos::Point2f, rot_rad::Float64)}` for drawing;
- `boxes::Vector{Rect2f}` per-glyph footprints (≈ advance × fpx) for solver obstacles.
"""
function _areal_glyphs(a::Areal, apx::Point2f, fpx::Real)
    drawn, font = _areal_drawn(a)
    chars = collect(drawn)
    isempty(chars) && return (Tuple{Char,Point2f,Float64}[], Rect2f[])

    advs = _char_advances(drawn, font, fpx)
    track = Float32(a.tracking * fpx)            # extra px per glyph
    advs = advs .+ track
    L = sum(advs)                                # total baseline length (px)

    # signed arc-length of each glyph CENTER from the baseline midpoint
    cum = 0.0f0
    centers = Vector{Float32}(undef, length(advs))
    for i in eachindex(advs)
        centers[i] = cum + advs[i] / 2 - L / 2
        cum += advs[i]
    end

    base = deg2rad(a.rotation)
    t    = (cos(base), sin(base))                # unit tangent
    θ    = deg2rad(a.sweep)

    glyphs = Vector{Tuple{Char,Point2f,Float64}}(undef, length(chars))
    boxes  = Vector{Rect2f}(undef, length(chars))
    gh     = Float32(fpx)                         # glyph box height ≈ font_px

    if abs(a.sweep) < 0.5                          # STRAIGHT (R → ∞)
        for i in eachindex(chars)
            s = centers[i]
            pos = Point2f(apx[1] + s * t[1], apx[2] + s * t[2])
            glyphs[i] = (chars[i], pos, base)
            boxes[i]  = Rect2f(pos[1] - advs[i]/2, pos[2] - gh/2, advs[i], gh)
        end
    else                                           # ARC of radius R = L/θ
        # Center of curvature sits on the side the text bends TOWARD. For sweep>0 the
        # baseline bows so its ends rise (concave up in the un-tilted frame): center is
        # ABOVE, i.e. along +normal where normal = left of tangent = (−sinθ, cosθ).
        sgn = sign(θ)                              # +1 bends one way, −1 the other
        nrm = (-sin(base), cos(base))              # left-normal of the tangent
        R   = Float32(L / abs(θ))
        # center on the concave side (toward which the text curves)
        Cc  = Point2f(apx[1] + sgn * R * nrm[1], apx[2] + sgn * R * nrm[2])
        # angle from center to the midpoint anchor
        α0  = atan(apx[2] - Cc[2], apx[1] - Cc[1])
        # At the midpoint the CCW tangent equals +sgn*t, so walking +s (rightward along
        # the baseline) advances the circle angle by +sgn*(s/R). Both position and glyph
        # rotation share this step, keeping the string in reading order and upright.
        for i in eachindex(chars)
            dα  = sgn * (centers[i] / R)
            αi  = α0 + dα
            pos = Point2f(Cc[1] + R * cos(αi), Cc[2] + R * sin(αi))
            rot = base + dα                        # base tilt + incremental bend
            glyphs[i] = (chars[i], pos, rot)
            boxes[i]  = Rect2f(pos[1] - advs[i]/2, pos[2] - gh/2, advs[i], gh)
        end
    end

    return (glyphs, boxes)
end

# ── Shared LoD orchestration (single source of truth for the golden) ──────────

"""
    feature_lod(kind, ground, w, content_px_w; is_slo=false, is_river=false, max_px=Inf)
        -> (fpx_geo, fpx, band)

The per-feature LoD/opacity orchestration, shared by `assemble_frame` (the live render path)
and `golden_rows` (the deterministic golden table) so their scaling/fade math CANNOT drift —
the golden mechanically guards this arithmetic. Pure (no Makie, no fonts): just the lod.jl
primitives composed the one canonical way.

- `fpx_geo` — geographic type height `ground·P` (drives the band fade); SLO is pinned to `SLO_PX`.
- `fpx`     — the DRAWN size: `fpx_geo` capped at the per-kind ceiling (`MAX_LABEL_PX` for the
              point kinds `:town`/`:poi`, `MAX_AREAL_PX` for `:areal`).
- `band`    — PRE-EDGE opacity (the legibility/size focus-band fade): `1.0` for SLO,
              `river_alpha(w)` for a `:river` areal, else `band_alpha(fpx_geo, max_px)`.

Callers apply their own viewport factor on top: `assemble_frame` multiplies `band` by its
Makie-projected `_edge_alpha`; `golden_rows` by the affine `_golden_px`-derived edge (point
features only — areals carry no edge factor in either path).
"""
function feature_lod(kind::Symbol, ground::Real, w::Real, content_px_w::Real;
                     is_slo::Bool = false, is_river::Bool = false, max_px::Real = Inf)
    cap     = kind === :areal ? MAX_AREAL_PX : MAX_LABEL_PX
    fpx_geo = is_slo ? SLO_PX : font_px(ground, w, content_px_w)
    band    = is_slo   ? 1.0 :
              is_river ? river_alpha(w) :
                         band_alpha(fpx_geo, max_px)
    fpx     = min(fpx_geo, cap)
    return (fpx_geo, fpx, band)
end

# ── Frame assembly (the honest core) ─────────────────────────────────────────

"Everything render needs for one frame — all label boxes measured + solver-placed."
struct AssembledFrame
    fp        :: FramePlacement                 # ids = towns + POIs, all solved together
    kind_of   :: Dict{Int,Symbol}               # id → :town | :poi
    font_px   :: Dict{Int,Float64}              # id → on-screen type height (px) it's drawn at
    band      :: Dict{Int,Float64}              # id → band-opacity (focus-band fade), SLO pinned 1.0
    # per visible areal: (kind, font_px, band_alpha, glyph layout). glyph = (char, pos px, rot rad).
    areals    :: Vector{Tuple{Symbol,Float64,Float64,Vector{Tuple{Char,Point2f,Float64}}}}
    obstacles :: Vector{Rect2f}                 # coastline + per-glyph areal footprints (px)
    coast_capped :: Bool
end

"""
    assemble_frame(d, p; pagepx, prev, settled) -> (fig, ax, AssembledFrame)

Build a fresh figure for loop phase `p` and place EVERY label honestly:
- point labels (active towns + on-screen POIs) measured via TextMeasure, placed by
  one `warm_solve` call against each other, the sampled coastline, and the areals;
- areals laid out glyph-by-glyph along an arc (each glyph MEASURED), their per-glyph
  boxes added as obstacles.

`prev`: Dict{Int,Vec2f} mapping feature id → prior frame's solved offset (warm-start).
`settled`: Set{Int} of ids to pin (empty for video — labels must adapt as boxes grow).
Both default to empty so `_dev_still` remains cold/unchanged.
"""
function assemble_frame(d::AtlasData, p::Real;
                        pagepx  = (1620, 1080),
                        prev    :: Dict{Int,Vec2f} = Dict{Int,Vec2f}(),
                        settled :: Set{Int}        = Set{Int}())
    fig, ax = _new_axis(; pagepx)
    # camera window matched to the drawable content aspect → fills frame, no distortion
    limits!(ax, camera_rect(p; aspect = _content_aspect(pagepx))...)
    Makie.update_state_before_display!(fig)   # camera matrices now reflect THIS frame

    W, H = Float32.(pagepx)
    content_px_w = W - 2 * _SIDE_PAD                       # drawable width → pixels-per-map-unit
    content_px_h = H - Float32(_MASTHEAD_H) - Float32(_FOOTER_H)  # drawable height
    # `_data_to_px` returns AXIS-SCENE px (origin = axis bottom-left), so the VISIBLE map is
    # [0,content_px_w]×[0,content_px_h]. Labels are clipped/faded to that rect (_edge_alpha);
    # obstacles are sampled a little BEYOND it so the coast/areal walls stay continuous at the
    # frame edge. (The old `page_rect` was in figure space — far too permissive, which is why
    # off-screen features were getting labelled.)
    obs_rect = Rect2f(-Float32(_OBS_MARGIN), -Float32(_OBS_MARGIN),
                      content_px_w + 2Float32(_OBS_MARGIN), content_px_h + 2Float32(_OBS_MARGIN))

    w = view_width(p)                    # degrees of longitude across the frame
    town_by_id = Dict(t.town_id => t for t in d.towns)
    pois = atlas_pois()

    # --- (a) geographic-scaling visibility (px band; SLO pinned) ---
    # For each on-screen feature: font_px = ground * P (SLO pinned to SLO_PX). Show when
    # legible (≥ MIN_PX) and, for coarse features, until it outgrows max_px. Measure once
    # at _REF_PX, scale the unit box to font_px; draw at that font_px.
    ids      = Int[]
    px_anch  = Point2f[]
    sizes    = Vec2f[]                 # scaled box (w,h px) for the solver
    kind_of  = Dict{Int,Symbol}()
    fpx_of   = Dict{Int,Float64}()    # id → font_px it is drawn at
    band_of  = Dict{Int,Float64}()    # id → band-opacity (focus-band fade), SLO pinned 1.0

    for t in d.towns
        px = _data_to_px(ax, t.pos)
        edge = _edge_alpha(px, content_px_w, content_px_h)
        edge > 0.02 || continue                       # off-screen / on the neat-line → unlabelled
        is_slo = t.town_id == _SLO_ID
        # GEOGRAPHIC size drives the band FADE; the DRAWN/solved size is capped at MAX_LABEL_PX
        # so a deep-zoom town can't out-size the masthead. SLO is pinned (already ≤ cap).
        _, fpx, band = feature_lod(:town, town_ground(t.rank), w, content_px_w; is_slo)
        ba = band * edge
        ba > 0.02 || continue
        font, _ = _point_style(:town, t.rank ≤ 5)
        unit = _unit_box(t.name, font)
        push!(ids, t.town_id); push!(px_anch, px); push!(sizes, _scaled_box(unit, fpx))
        kind_of[t.town_id] = :town; fpx_of[t.town_id] = fpx; band_of[t.town_id] = ba
    end
    for (k, poi) in enumerate(pois)
        px = _data_to_px(ax, poi.pos)
        edge = _edge_alpha(px, content_px_w, content_px_h)
        edge > 0.02 || continue
        _, fpx, band = feature_lod(:poi, POI_GROUND, w, content_px_w)
        ba = band * edge
        ba > 0.02 || continue
        pid = _POI_BASE + k
        font, _ = _point_style(:poi, false)
        unit = _unit_box(poi.name, font)
        push!(ids, pid); push!(px_anch, px); push!(sizes, _scaled_box(unit, fpx))
        kind_of[pid] = :poi; fpx_of[pid] = fpx; band_of[pid] = ba
    end

    # --- (b) obstacles in PIXEL space ---
    obstacles = Rect2f[]

    # coastline: project + subsample smoothed vertices, emit small boxes, cap count
    coast_capped = false
    half = Float32(_COAST_BOX / 2)
    for seg in d.coastline
        for i in 1:_COAST_STRIDE:length(seg)
            px = _data_to_px(ax, seg[i])
            _in_rect(px, obs_rect) || continue
            push!(obstacles, Rect2f(px[1] - half, px[2] - half, _COAST_BOX, _COAST_BOX))
            if length(obstacles) >= _COAST_MAX
                coast_capped = true
                break
            end
        end
        coast_capped && break
    end
    coast_capped && @warn "coastline obstacles hit the cap" cap=_COAST_MAX w=w
    n_coast = length(obstacles)   # obstacles[1:n_coast] are the coast wall (areals appended next)

    # areals: geographic-scaling + CURVED. font_px = ground * P; show in [MIN_PX, max_px]
    # (coarse regions hand off when they outgrow the frame). Each areal is laid out
    # glyph-by-glyph along an arc (every glyph MEASURED + single-measure-scaled); its
    # solver obstacle is the UNION OF PER-GLYPH BOXES (subsampled), so town labels dodge
    # only the actual letters — not a giant tilted AABB.
    areals = Tuple{Symbol,Float64,Float64,Vector{Tuple{Char,Point2f,Float64}}}[]
    for a in atlas_areals()
        apx = _data_to_px(ax, a.pos)
        # NO viewport gate on the anchor: a swollen areal's anchor can leave the frame while its
        # glyphs still span it — gating on the anchor made the Range POOF out and back. Opacity
        # (the size hand-off below) decides visibility; Makie clips the off-screen glyphs.
        # GEOGRAPHIC: grows as the camera dives. :river follows the hydrography LoD. Region
        # areals scale with altitude AND hand off smoothly by their OWN size: band_alpha(fpx,
        # max_px) fades each in as it's legible, lets it swell, then fades it OUT as it outgrows
        # the frame (you pass through the cloud). Per-areal, so the big Range is gone by the time
        # the inland towns appear, while the small Estero Bay persists at depth. (No global
        # recede — that made the Range linger.) fpx is capped only at the high MAX_AREAL_PX safety
        # ceiling.
        _, fpx, ba = feature_lod(:areal, a.ground, w, content_px_w;
                                 is_river = a.kind === :river, max_px = a.max_px)
        ba > 0.02 || continue
        glyphs, gboxes = _areal_glyphs(a, apx, fpx)
        # Obstacle only while SUBSTANTIAL (near full opacity at the wide shot). Once an areal
        # recedes to a faint cloud, town labels are free to sit over it — a giant faint glyph
        # shouldn't shove the whole field around.
        if ba > _AREAL_OBSTACLE_ALPHA
            for i in 1:_AREAL_OBSTACLE_STRIDE:length(gboxes)   # subsample glyph footprints
                push!(obstacles, gboxes[i])
            end
        end
        push!(areals, (a.kind, fpx, ba, glyphs))
    end

    # --- (c) ONE solve over all point labels, with obstacles + warm-start ---
    # bounds = the VISIBLE MAP RECT in ax-scene pixel space (where the anchors live, origin
    # = axis bottom-left). Confines label boxes to the drawn map area so none extends past
    # the neat-line.
    bounds = Rect2f(0, 0, content_px_w, content_px_h)

    # Geography-aware seeds: place labels high→low priority; each NEW label seeds to the
    # candidate direction that best avoids the coast/areals + already-placed neighbours (so a
    # coastal feature's label seeds to the OPEN-WATER side, and SLO dodges the range areal it
    # would otherwise sit on). Warm-started ids keep their prior offset for continuity.
    seeds = Dict{Int,Vec2f}()
    let placed = Rect2f[]
        prio_seed(id) = id == _SLO_ID ? -1.0 :
            (get(kind_of, id, :poi) === :town ?
             Float64(haskey(town_by_id, id) ? town_by_id[id].rank : 50) : 100.0 + (id - _POI_BASE))
        for k in sort(collect(eachindex(ids)); by = k -> prio_seed(ids[k]))
            off = haskey(prev, ids[k]) ? prev[ids[k]] :
                  _choose_seed(px_anch[k], sizes[k], obstacles, placed, bounds)
            seeds[ids[k]] = off
            c = px_anch[k] .+ off; s = sizes[k]
            push!(placed, Rect2f(c[1]-s[1]/2, c[2]-s[2]/2, s[1], s[2]))
        end
    end

    # Pin SLO to its (geography-aware) seed — the cluster's deterministic centre, which breaks
    # the symmetric tie with the co-located "Mission San Luis Obispo" POI (the SLO flicker).
    # It's placed first above, so every other label dodges it.
    prev2 = copy(prev); settled2 = copy(settled)
    if _PIN_SLO[] && (_SLO_ID in ids)
        prev2[_SLO_ID] = seeds[_SLO_ID]
        push!(settled2, _SLO_ID)
    end

    fp = if isempty(ids)
        FramePlacement(Int[], Point2f[], Vec2f[], Vec2f[], BitVector())
    else
        solve_frame(ids, px_anch, sizes, bounds;
                    prev = prev2, settled = settled2, obstacles = obstacles, seeds = seeds)
    end

    # We OWN the visibility decision now (we cleared the solver's `dropped`, whose label-label
    # tie-breaks flip frame-to-frame → flash). Two deterministic, stable passes:
    #
    # (1) HARD coast clearance — a label box overlapping the coast wall is dropped outright (a
    #     drawn label must never touch the coast). Same geometry every frame → stable.
    # (2) SMOOTH priority occlusion cull — walk labels high→low priority; a label's opacity
    #     fades by how much it's overlapped by an already-kept higher-priority box. Fixed
    #     priority (rank / list order) ⇒ stable choice; the smooth fade means a label sitting on
    #     a higher one (the Mission on San Luis Obispo) holds steady partial opacity, not strobe.
    if !isempty(fp.ids)
        coast = view(obstacles, 1:n_coast)
        labelbox(k) = (c = fp.anchors[k] .+ fp.offsets[k]; s = fp.sizes[k];
                       Rect2f(c[1]-s[1]/2, c[2]-s[2]/2, s[1], s[2]))
        fill!(fp.dropped, false)
        # (1) coast clearance
        for k in eachindex(fp.ids)
            lb = labelbox(k)
            any(b -> _box_ovl(lb, b) > 0.5, coast) && (fp.dropped[k] = true)
        end
        # (2) priority occlusion cull among the survivors
        prio = function (id)
            id == _SLO_ID                    ? -1.0 :
            get(kind_of, id, :poi) === :town ? Float64(haskey(town_by_id, id) ? town_by_id[id].rank : 50) :
                                               100.0 + (id - _POI_BASE)
        end
        order = sort(collect(eachindex(fp.ids)); by = k -> prio(fp.ids[k]))
        kept = Rect2f[]
        for k in order
            fp.dropped[k] && continue                              # coast-dropped → out
            box = labelbox(k)
            ov = isempty(kept) ? -Inf : maximum(b -> _box_ovl(box, b), kept)
            cull_a = smoothstep((_CULL_HIDE - ov) / _CULL_HIDE)   # 1 (clear) → 0 (ov ≥ hide)
            band_of[fp.ids[k]] *= cull_a
            cull_a < 0.05 && (fp.dropped[k] = true)               # fully occluded → drop
            band_of[fp.ids[k]] > 0.4 && push!(kept, box)          # substantially visible → blocks lower
        end
    end

    # Leader cap: FADE a label out as its LEADER (dot → nearest box edge) grows past
    # _LEADER_MAX — a long leader reads as a stray wire and tends to cross an areal. Uses the
    # leader length, NOT the centre offset (which scales with label width, so wide labels at
    # their natural rest position would be wrongly faded). Smooth ramp so it never pops.
    for k in eachindex(fp.ids)
        fp.dropped[k] && continue
        lf = smoothstep((_LEADER_MAX - _leader_len(fp.offsets[k], fp.sizes[k])) / _LEADER_RAMP)
        band_of[fp.ids[k]] *= lf
    end

    return fig, ax, AssembledFrame(fp, kind_of, fpx_of, band_of, areals, obstacles, coast_capped)
end

# ── Draw functions ────────────────────────────────────────────────────────────

# Far-field box (map-units) well outside any dive view, used to close the sea polygon.
const _OCEAN_FAR_W = Float32(KX * -140.0)
const _OCEAN_FAR_N = 42.0f0
const _OCEAN_FAR_S = 20.0f0

"""
    _ocean_polygon(d) -> Vector{Point2f}

The sea as ONE polygon (map-units): the longest coastline segment, closed around the far
west/south/north. Land is the PAPER axis base; painting this water polygon over everything
seaward of the coast means the clipped mainland ring's interior gaps can never show as
background. Assumes the main coast's first vertex is its northern end (true for our data).
"""
function _ocean_polygon(d::AtlasData)
    isempty(d.coastline) && return Point2f[]
    main = argmax(length, d.coastline)
    isempty(main) && return Point2f[]
    S = main[1]; E = main[end]                       # S = north end, E = south end
    pts = collect(main)
    push!(pts, Point2f(E[1], _OCEAN_FAR_S))          # south from the coast's south end
    push!(pts, Point2f(_OCEAN_FAR_W, _OCEAN_FAR_S))  # far southwest
    push!(pts, Point2f(_OCEAN_FAR_W, _OCEAN_FAR_N))  # far northwest
    push!(pts, Point2f(S[1], _OCEAN_FAR_N))          # north, above the coast's north end
    return pts                                        # poly! closes back to S
end

"""
    draw_basemap!(ax, d::AtlasData)

Land = PAPER axis base · sea = one WATER polygon (coast closed around the far field, so no
land-clip gap can show) · islands repainted PAPER on the sea · coastline hairline (INK
0.75px, the only 0.75 line) · recessive half-degree graticule (translucent BRASS 0.25px).
"""
function draw_basemap!(ax, d::AtlasData)
    # Sea polygon over the PAPER land base.
    ocean = _ocean_polygon(d)
    isempty(ocean) || poly!(ax, ocean; color = WATER, strokewidth = 0, inspectable = false)

    # Islands (small land rings, not the mainland) sit on the sea — repaint as land.
    if !isempty(d.land)
        mainland = argmax(length, d.land)
        for ring in d.land
            (ring === mainland || isempty(ring)) && continue
            poly!(ax, ring; color = HouseStyle.PAPER, strokewidth = 0, inspectable = false)
        end
    end

    lon_min, lon_max, lat_min, lat_max = _data_range(d)
    grat_c = Makie.RGBAf(HouseStyle.BRASS.r, HouseStyle.BRASS.g, HouseStyle.BRASS.b, 0.30)
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
    draw_hydrography!(ax, d, w_deg)

Inland water (lakes as WATER polygons, rivers as WATER_INK centrelines), drawn OVER the
basemap and UNDER the areals/labels, with level-of-detail opacity (`river_alpha`): absent at
the wide ocean overview, fading in as the camera reaches valley scale. The Salinas River is
the on-view feature here; lakes appear only if a reservoir falls inside the view. Honest
Natural-Earth geometry — see data/SOURCE.txt.
"""
function draw_hydrography!(ax, d::AtlasData, w_deg::Real)
    a = river_alpha(w_deg)
    a > 0.02 || return ax
    lake_fill   = Makie.RGBAf(WATER.r, WATER.g, WATER.b, a)
    lake_stroke = Makie.RGBAf(WATER_INK.r, WATER_INK.g, WATER_INK.b, 0.7a)
    river_c     = Makie.RGBAf(WATER_INK.r, WATER_INK.g, WATER_INK.b, 0.72a)
    for ring in d.lakes
        length(ring) ≥ 3 || continue
        poly!(ax, ring; color = lake_fill, strokecolor = lake_stroke,
              strokewidth = 0.5, inspectable = false)
    end
    # River weight grows a touch as you dive (0.7px → 1.1px) so it reads at valley scale.
    rw = Float32(0.7 + 0.4a)
    for seg in d.rivers
        length(seg) ≥ 2 || continue
        lines!(ax, seg; color = river_c, linewidth = rw, inspectable = false)
    end
    return ax
end

"""
    draw_areals!(ax, areals)

Draw each CURVED areal glyph-by-glyph (space=:pixel) along its precomputed arc layout.
Per glyph: `text!` at the glyph's pixel position, rotated to the local tangent, at the
areal's dynamic `font_px`, in the areal face (Newsreader italic for :water / Hanken for
:range) and color (WATER_INK for :water / GRAY for :range). ~10–17 text! calls per areal.
Drawn UNDER the point labels; the solver keeps point labels off these via per-glyph obstacles.
`areals` entries are `(kind, font_px, band_alpha, glyphs)`; each glyph's color alpha is the
band-opacity, so areals fade in past the floor and out past their `max_px` hand-off.
"""
function draw_areals!(ax, areals)
    for (kind, fpx, ba, glyphs) in areals
        font  = kind === :range ? FACE_LAND : FACE_WATER
        base  = kind === :range ? HouseStyle.GRAY : WATER_INK
        col   = Makie.RGBAf(base.r, base.g, base.b, ba)   # band-opacity into the alpha
        for (ch, pos, rot) in glyphs
            text!(ax, pos;
                text        = string(ch),
                rotation    = rot,
                fontsize    = fpx,
                font        = font,
                color       = col,
                align       = (:center, :center),
                space       = :pixel,
                inspectable = false)
        end
    end
    return ax
end

"""
    draw_labels!(ax, d, af::AssembledFrame)

Draw the point-label layer (towns + POIs) for one frame from the solved placement.
Opacity is `af.band[id]` — the single, stateless per-frame value (legibility × framing ×
placement); there is no temporal fade. Each label is drawn at the SAME (face, size) it was
measured at (Field-survey roles): major towns → Hanken SemiBold INK; minor towns → Hanken
Regular INK; POIs → Hanken Regular GRAY (hollow diamond marker). Leaders (BRASS 0.5px) for
far-pushed labels drawn first; town dots (brass SLO hero) with PAPER halo; markers on top.
"""
function draw_labels!(ax, d::AtlasData, af::AssembledFrame)
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
    # ONE straight line from the marker EDGE to the label box's nearest point:
    #   Pℓ = clamp(anchor, box_min, box_max)  (nearest point on the label box to the marker)
    #   d  = normalize(Pℓ − anchor)           (direction from the dot toward the label)
    #   marker-end = anchor + d·r             (r = that feature's dot radius + 1px)
    # so the leader exits the dot's edge in the label's direction (label below ⇒ exits the
    # bottom, not the side) and runs straight to the label's near edge.
    leader_pts = Point2f[]
    for k in eachindex(fp.ids)
        fp.dropped[k] && continue
        id = fp.ids[k]
        get(af.band, id, 1.0) < 0.05 && continue
        off = fp.offsets[k]; anc = fp.anchors[k]; sz = fp.sizes[k]
        _leader_len(off, sz) > _LEADER_DRAW || continue   # only when there's a visible dot→label gap

        c    = anc .+ off                              # label box center (px)
        half = Vec2f(sz[1] / 2, sz[2] / 2)
        near = Point2f(clamp(anc[1], c[1] - half[1], c[1] + half[1]),   # Pℓ: nearest box point
                       clamp(anc[2], c[2] - half[2], c[2] + half[2]))
        toℓ = near .- anc; m2 = _norm2(Vec2f(toℓ...))
        m2 > 1f-3 || continue
        d   = toℓ ./ m2                                 # direction dot → label
        # drawn dot radius + 1px for this feature
        r = if id == _SLO_ID
            7.0f0                                       # SLO hero dot 12px → r≈7
        elseif af.kind_of[id] === :poi
            5.0f0                                       # POI diamond → r≈5
        else
            (town_by_id[id].rank ≤ 5 ? 5.0f0 : 4.5f0)   # major 8px → 5, minor 7px → 4.5
        end
        push!(leader_pts, anc .+ d .* r)                # marker-EDGE end
        push!(leader_pts, near)                          # label near-edge end
    end
    if !isempty(leader_pts)
        linesegments!(ax, leader_pts; space = :pixel,
            color = HouseStyle.BRASS, linewidth = 0.5, inspectable = false)
    end

    # --- collect markers (batched) + per-label text rows ---
    town_halo_pos = Point2f[]; town_halo_c = Makie.RGBAf[]; town_halo_sz = Float32[]
    town_dot_pos  = Point2f[]; town_dot_c  = Makie.RGBAf[]; town_dot_sz  = Float32[]
    poi_pos       = Point2f[]; poi_fill    = Makie.RGBAf[]; poi_stroke   = Makie.RGBAf[]
    # SLO hero dot is drawn SEPARATELY, on top of everything (brass + ink ring).
    slo_pos = Point2f(NaN, NaN); slo_alpha = 0.0
    # text rows drawn one-by-one (each at its own measured face+size)
    text_rows = NamedTuple[]   # (pos, name, off, font, size, color)

    for k in eachindex(fp.ids)
        fp.dropped[k] && continue
        id = fp.ids[k]
        # opacity = the frame's stateless band value (legibility × framing × placement)
        α  = get(af.band, id, 1.0)
        α < 0.01 && continue
        pos, name, kind = feature(id)

        size = af.font_px[id]   # dynamic geographic type height (px) — DRAW at the measured size

        if kind === :town
            is_slo   = id == _SLO_ID
            t        = town_by_id[id]
            is_major = t.rank ≤ 5
            ink_c    = is_slo ? HouseStyle.BRASS : HouseStyle.INK
            dsz      = is_major ? 8.0f0 : 7.0f0          # batched town dot size
            # halo for ALL towns (incl. SLO) — paper ring under the dot
            halo_sz  = is_slo ? 16.0f0 : dsz + 4.0f0     # SLO halo sized to its 12px hero dot
            push!(town_halo_pos, pos)
            push!(town_halo_c, Makie.RGBAf(HouseStyle.PAPER.r, HouseStyle.PAPER.g, HouseStyle.PAPER.b, α))
            push!(town_halo_sz, halo_sz)
            if is_slo
                slo_pos = pos; slo_alpha = α            # drawn separately, on top
            else
                push!(town_dot_pos, pos)
                push!(town_dot_c, Makie.RGBAf(ink_c.r, ink_c.g, ink_c.b, α))
                push!(town_dot_sz, dsz)
            end
            font, _ = _point_style(:town, is_major)
            col = Makie.RGBAf(HouseStyle.INK.r, HouseStyle.INK.g, HouseStyle.INK.b, α)
            push!(text_rows, (pos=pos, name=name, off=fp.offsets[k], font=font, size=size, color=col))
        else  # :poi
            push!(poi_pos, pos)
            push!(poi_fill,   Makie.RGBAf(HouseStyle.PAPER.r, HouseStyle.PAPER.g, HouseStyle.PAPER.b, α))
            push!(poi_stroke, Makie.RGBAf(HouseStyle.INK.r, HouseStyle.INK.g, HouseStyle.INK.b, α))
            font, _ = _point_style(:poi, false)
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

    # SLO hero dot — drawn LAST, on top of everything: BRASS fill, 12px, 1.5px INK ring
    # (the one allowed 1.5 stroke; it's a point marker, not a map line). Its PAPER halo
    # was already drawn in the batch. Pinned alpha (= 1 in the still).
    if slo_alpha > 0.01
        scatter!(ax, [slo_pos];
            marker = :circle, markersize = 12.0f0,
            color = Makie.RGBAf(HouseStyle.BRASS.r, HouseStyle.BRASS.g, HouseStyle.BRASS.b, slo_alpha),
            strokecolor = Makie.RGBAf(HouseStyle.INK.r, HouseStyle.INK.g, HouseStyle.INK.b, slo_alpha),
            strokewidth = 1.5, inspectable = false)
    end

    return ax
end

# ── Cartographic chrome helpers (Plex Mono, BRASS — the instrument-readout face) ──

const _KM_PER_DEG_LAT = 111.0      # 1° latitude ≈ 111 km (used for the scale bar)
const _NICE_KM = (1, 2, 5, 10, 20, 50)   # round scale-bar lengths to choose from

"Format a whole-degree longitude as `NNN°W`/`NNN°E` (our data is western → W)."
_lon_label(lon::Integer) = "$(abs(lon))°$(lon < 0 ? "W" : "E")"
"Format a whole-degree latitude as `NN°N`/`NN°S`."
_lat_label(lat::Integer) = "$(abs(lat))°$(lat < 0 ? "S" : "N")"

"""
    _scale_bar!(ax, w_deg, pagepx)

Dynamic km scale bar, lower-LEFT INSIDE the axis (drawn to `ax` in `space=:pixel`, i.e.
axis-scene-relative coords, since fig.scene content is occluded by the axis). px_per_km
= P/111 where P = content_px_w/(KX·w_deg). Picks the NICE km length whose bar lands
closest to ~120px, draws a 1.0px BRASS bar with end ticks + `0` and `N km` Plex Mono
caption labels. Recomputed every frame (shrinks as you zoom — correct).
"""
function _scale_bar!(ax, w_deg::Real, pagepx)
    W, H = Float32.(pagepx)
    content_px_w = W - 2 * _SIDE_PAD
    px_per_km = (content_px_w / (KX * w_deg)) / _KM_PER_DEG_LAT

    km = argmin(n -> abs(n * px_per_km - 120.0), _NICE_KM)
    bar_px = Float32(km * px_per_km)

    # axis-scene-relative pixels (origin = axis bottom-left): inset from the lower-left.
    x0 = 14.0f0
    y0 = 16.0f0
    x1 = x0 + bar_px
    tick = 4.0f0

    linesegments!(ax,
        [Point2f(x0, y0), Point2f(x1, y0),                 # the bar
         Point2f(x0, y0 - tick), Point2f(x0, y0 + tick),   # left end tick
         Point2f(x1, y0 - tick), Point2f(x1, y0 + tick)];  # right end tick
        color = HouseStyle.BRASS, linewidth = 1.0, space = :pixel, inspectable = false)

    text!(ax, Point2f(x0, y0 + tick + 2.0f0);
        text = "0", fontsize = Float64(HouseStyle.RAMP.caption),
        font = FACE_MONO, color = HouseStyle.BRASS,
        align = (:center, :bottom), space = :pixel, inspectable = false)
    text!(ax, Point2f(x1, y0 + tick + 2.0f0);
        text = "$(km) km", fontsize = Float64(HouseStyle.RAMP.caption),
        font = FACE_MONO, color = HouseStyle.BRASS,
        align = (:center, :bottom), space = :pixel, inspectable = false)

    return km
end

"""
    _graticule_labels!(ax, d, pagepx)

Label the WHOLE-degree grid lines only, drawn to `ax` (axis-scene pixel space, where
`_data_to_px` already lives, so they survive the axis occlusion). Lon labels (`121°W`)
along the BOTTOM edge where each integer meridian crosses; lat labels (`35°N`) along the
LEFT edge where each integer parallel crosses. Only crossings inside the axis are drawn.
Plex Mono caption 9, BRASS, inset from the neat-line. Skips lon labels near the lower-left
so they don't collide with the scale bar.
"""
function _graticule_labels!(ax, d::AtlasData, pagepx)
    W, H = Float32.(pagepx)
    aw = W - 2 * Float32(_SIDE_PAD)               # axis-scene width  (ax-relative right edge)
    ah = H - Float32(_MASTHEAD_H) - Float32(_FOOTER_H)  # axis-scene height (top edge)
    inset = 9.0f0   # inside the inner neat-line (which sits 5px in from the axis edge)
    lon_min, lon_max, lat_min, lat_max = _data_range(d)

    # lon labels along the bottom edge (ax-relative). Skip the lower-left (scale bar) and
    # lower-right (metrics readout) so degree labels don't collide with the cartouche.
    for lon in ceil(Int, lon_min):floor(Int, lon_max)
        px = _data_to_px(ax, Point2f(project_point(lon, (lat_min + lat_max) / 2)))
        (150 < px[1] < aw - 110) || continue
        text!(ax, Point2f(px[1], inset);
            text = _lon_label(lon), fontsize = Float64(HouseStyle.RAMP.caption),
            font = FACE_MONO, color = HouseStyle.BRASS,
            align = (:center, :bottom), space = :pixel, inspectable = false)
    end
    # lat labels along the left edge (ax-relative). Skip low y to clear the scale-bar text.
    for lat in ceil(Int, lat_min):floor(Int, lat_max)
        px = _data_to_px(ax, Point2f(project_point((lon_min + lon_max) / 2, lat)))
        (48 < px[2] < ah - 12) || continue
        text!(ax, Point2f(inset, px[2]);
            text = _lat_label(lat), fontsize = Float64(HouseStyle.RAMP.caption),
            font = FACE_MONO, color = HouseStyle.BRASS,
            align = (:left, :center), space = :pixel, inspectable = false)
    end
    return ax
end

# A closed rectangle as `linesegments!` point pairs (l,b)→(r,b)→(r,t)→(l,t)→close.
_rect_segs(l, b, r, t) =
    [Point2f(l, b), Point2f(r, b), Point2f(r, b), Point2f(r, t),
     Point2f(r, t), Point2f(l, t), Point2f(l, t), Point2f(l, b)]

"""
    draw_chrome!(ax, fig, d; metrics, w_deg, pagepx)

Masthead title "TextMeasure.jl · The Atlas" — a composite line: a light/small "TextMeasure.jl"
imprint in Hanken Regular + brass middot, then "The Atlas" large in Newsreader ITALIC (the
emphasis). The region label "C E N T R A L  C O A S T" (Hanken SemiBold letterspaced caps) is
vertically centred on the title's cap band at the right. A DOUBLE BRASS neat-line frames the
map (both lines in the margin); then graticule degree labels, a dynamic km scale bar
(lower-left), and corner metrics (Plex Mono, lower-right).
"""
function draw_chrome!(ax, fig, d::AtlasData; metrics::AbstractString = "",
                      w_deg::Real = 0.0, pagepx = (1620, 1080))
    W, H = fig.scene.viewport[].widths
    W = Float32(W); H = Float32(H)
    scene = fig.scene

    # Masthead is drawn as SEPARATE plain text! runs (not Makie rich text, whose baseline
    # renders ~0.3·size above its anchor — plain text honours :baseline exactly). The runs are
    # positioned by MEASURED widths (TextMeasure), and every cap-centre is aligned to one line:
    # each run's baseline = center_y − (capTop÷2)·size, with capTop measured per face
    # (Newsreader-italic 0.67, Hanken/Plex 0.70). So "The Atlas" and "CENTRAL COAST" caps share
    # a centre. The "TextMeasure.jl ·" imprint is Hanken SemiBold (the SAME face as CENTRAL
    # COAST), full ink, sized down so the serif-italic "The Atlas" carries the emphasis.
    # VERTICALLY CENTRED: every run's CAP-HEIGHT MIDPOINT sits on the shared center_y. Each
    # run gets its own baseline = center_y − (capTop÷2)·size (capTop measured per face), so the
    # small imprint floats UP to be centred against the big title rather than sharing its
    # baseline. → "TextMeasure.jl", "The Atlas", and "CENTRAL COAST" caps all centre on one line.
    center_y = H - Float32(_MASTHEAD_H) / 2
    title_baseline   = center_y - _CAP_NEWS * Float32(_TITLE_PX)    # The Atlas
    imprint_baseline = center_y - _CAP_HANK * Float32(_IMPRINT_PX)  # TextMeasure.jl (own baseline)
    region_baseline  = center_y - _CAP_HANK * Float32(_REGION_PX)   # CENTRAL COAST

    gap = 0.42f0 * Float32(_IMPRINT_PX)
    w_imp = Float32(measure_label("TextMeasure.jl", FACE_LAND_SB, _IMPRINT_PX)[1])
    w_dot = Float32(measure_label("·",              FACE_LAND_SB, _IMPRINT_PX)[1])
    x_imp = Float32(_SIDE_PAD)
    x_dot = x_imp + w_imp + gap
    x_atlas = x_dot + w_dot + gap

    text!(scene, Point2f(x_imp, imprint_baseline);
        text = "TextMeasure.jl", fontsize = _IMPRINT_PX, font = FACE_LAND_SB,
        color = HouseStyle.INK, align = (:left, :baseline), space = :pixel, inspectable = false)
    text!(scene, Point2f(x_dot, center_y);   # the dot itself centred on the shared line
        text = "·", fontsize = _IMPRINT_PX, font = FACE_LAND_SB,
        color = HouseStyle.BRASS, align = (:left, :center), space = :pixel, inspectable = false)
    text!(scene, Point2f(x_atlas, title_baseline);
        text = "The Atlas", fontsize = _TITLE_PX, font = FACE_TITLE_IT,
        color = HouseStyle.INK, align = (:left, :baseline), space = :pixel, inspectable = false)

    text!(scene, Point2f(W - _SIDE_PAD, region_baseline);
        text = _letterspace("CENTRAL COAST"), fontsize = _REGION_PX,
        font = FACE_LAND_SB, color = HouseStyle.INK,
        align = (:right, :baseline), space = :pixel, inspectable = false)

    # Frame — a DOUBLE BRASS neat-line: inner on the map's edge (the axis bbox), outer one
    # `gap` px OUTSIDE in the PAPER margin. Both lines stay clear of the map content, so the
    # ocean can't occlude/clip them (the earlier double sat inside the axis → got clipped).
    ax_left = Float32(_SIDE_PAD); ax_right = W - Float32(_SIDE_PAD)
    ax_bottom = Float32(_FOOTER_H); ax_top = H - Float32(_MASTHEAD_H)
    gap = 4.0f0
    linesegments!(scene, _rect_segs(ax_left - gap, ax_bottom - gap, ax_right + gap, ax_top + gap);
        color = HouseStyle.BRASS, linewidth = 1.2, space = :pixel, inspectable = false)
    linesegments!(scene, _rect_segs(ax_left, ax_bottom, ax_right, ax_top);
        color = HouseStyle.BRASS, linewidth = 0.6, space = :pixel, inspectable = false)

    # Graticule degree labels (whole-degree only) + scale bar — drawn to the AXIS scene
    # (fig.scene content inside the axis bbox is occluded by the axis).
    _graticule_labels!(ax, d, pagepx)
    w_deg > 0 && _scale_bar!(ax, w_deg, pagepx)

    # Metrics — Plex Mono (the instrument readout), BRASS caption, lower-right of the map.
    if !isempty(metrics)
        text!(scene, Point2f(ax_right - Float32(_SIDE_PAD), ax_bottom + 6.0f0);
            text = metrics, fontsize = Float64(HouseStyle.RAMP.caption),
            font = FACE_MONO, color = HouseStyle.BRASS,
            align = (:right, :bottom), space = :pixel, inspectable = false)
    end

    return fig
end

# ── Dev-still helper ──────────────────────────────────────────────────────────

"""
    _dev_still(p::Real, path::AbstractString; pagepx=(1600, 1000)) -> path

Render a single honest frame at loop phase `p` and save to `path`. Assembles the
measured+solved frame, then draws basemap → hydrography → areals → labels → chrome.
Opacity is the frame's stateless band value — no temporal fade needed for a still.
"""
function _dev_still(p::Real, path::AbstractString; pagepx=(1620, 1080))
    d = load_atlas_data()
    fig, ax, af = assemble_frame(d, p; pagepx)
    fp = af.fp

    # metrics — tightened to the on-screen readout: width + placed count (no dev noise)
    n_placed = count(!, fp.dropped)
    w     = view_width(p)
    w_str = string(round(w; digits=2))
    metrics = "w $(w_str)° · $(n_placed) placed"

    draw_basemap!(ax, d)
    draw_hydrography!(ax, d, w)
    draw_areals!(ax, af.areals)
    draw_labels!(ax, d, af)
    draw_chrome!(ax, fig, d; metrics, w_deg = w, pagepx)

    save(path, fig)
    return path
end
