# SPDX-License-Identifier: MIT
# golden.jl — the DETERMINISTIC golden invariant for The Atlas.
#
# THE GALLERY RULE: hash the COMPUTED layout table, never the rendered pixels. The Atlas table
# is the per-feature LoD/opacity table — and it is PURELY GEOMETRIC, so it needs no font engine
# and no solver: `font_px` comes from each feature's ground-em (degrees), `band` is the
# legibility/size fade (`band_alpha`) times the viewport edge fade (`_edge_alpha`) over a pure
# AFFINE projection that reproduces the Makie camera to ≪0.1px. So the digest is reproducible
# across machines / fonts / Makie versions. This pins the SCALING + FADE behaviour we tune, e.g.
# town growth, the areal cloud hand-off, and the Range dissolving as the inland towns arrive.
#
# RAW solver pixel offsets are still NOT hashed — they flow through Makie's projection, which
# isn't guaranteed bit-stable across Makie versions. Instead `placement_rows`/`atlas_placement_digest`
# golden the solver's DISCRETE decisions — which side each label leans (offset quadrant) + whether
# it's dropped — taken from the real COLD solve. These rows DO still route anchors through Makie's
# projection (via `assemble_frame`), unlike the fully-affine geometric table above, so the digest
# is ROBUST TO sub-pixel projection drift — not Makie-independent — because a quadrant only flips on
# a genuine re-placement. (Offset magnitude / frame-to-frame continuity is covered separately by the
# warm-start delta bound in test_loop.jl.)
#
# Included after lod.jl / pois.jl (uses their constants + atlas_pois/atlas_areals).

using HouseStyle: digest_rows

# Structurally-distinct frames across the [2.0, 0.55] dive (loop phase = frame/360):
#   0   — wide establishing shot (ocean + range full, towns hidden)
#   64  — range near full, still descending
#   104 — hand-off: range fading out as the first inland towns appear
#   128 — town scale (range gone, necklace filling in)
#   180 — apex (deepest zoom; small features persist, towns at max scale)
#   280 — the return leg (re-ascending; mirror of the descent)
const GOLDEN_FRAMES = (0, 64, 104, 128, 180, 280)
const _GOLDEN_N = 360   # loop length the phases are taken against (matches render_loop default)

"Pure affine projection: feature map-units → axis-scene px, reproducing `_data_to_px` for the
linear camera at loop phase `p` (verified ≤0.02px vs Makie). No Makie, no fonts."
function _golden_px(dp, p::Real, pagepx)
    W, H = pagepx
    cpw = W - 2 * _SIDE_PAD
    cph = H - _MASTHEAD_H - _FOOTER_H
    xmin, xmax, ymin, ymax = camera_rect(p; aspect = _content_aspect(pagepx))
    ((dp[1] - xmin) / (xmax - xmin) * cpw, (dp[2] - ymin) / (ymax - ymin) * cph)
end

"""
    golden_rows(; pagepx=(1620,1080)) -> Vector{String}

The canonical deterministic LoD/opacity table across `GOLDEN_FRAMES`. For EVERY town, POI, and
areal at each frame, emit one row `frame|kind|key|fpx|band` where `fpx` is the drawn (capped)
type height and `band` the pre-cull opacity (legibility/size fade × edge fade). Fixed-size table
(every feature every frame), so the digest is independent of any visibility threshold.
Re-derives the per-feature LoD from the same shared primitives `assemble_frame` uses
(`font_px`, `band_alpha`, the `MAX_*_PX` caps) — minus the Makie projection (replaced by the
verified affine `_golden_px`) and the solver/cull (pixel-offset dependent). The orchestration
around those primitives is duplicated here rather than shared, so the two paths are kept in
sync by hand: a regression confined to one would not move the digest. Extracting a single
`feature_lod` both call would make that drift impossible — a worthwhile follow-up.
"""
function golden_rows(; pagepx = (1620, 1080))
    d = load_atlas_data()
    W, H = pagepx
    cpw = W - 2 * _SIDE_PAD
    cph = H - _MASTHEAD_H - _FOOTER_H
    pois = atlas_pois()
    areals = atlas_areals()
    rows = String[]
    rnd(x) = round(Float64(x); digits = 3)
    for frame in GOLDEN_FRAMES
        p = frame / _GOLDEN_N
        w = view_width(p)
        for t in d.towns
            px = _golden_px(t.pos, p, pagepx)
            edge = _edge_alpha(px, cpw, cph)
            is_slo = t.town_id == _SLO_ID
            fpx_geo = is_slo ? SLO_PX : font_px(town_ground(t.rank), w, cpw)
            band = (is_slo ? 1.0 : band_alpha(fpx_geo, Inf)) * edge
            fpx = is_slo ? SLO_PX : min(fpx_geo, MAX_LABEL_PX)
            push!(rows, string(frame, "|town|", t.town_id, "|", rnd(fpx), "|", rnd(band)))
        end
        for (k, poi) in enumerate(pois)
            px = _golden_px(poi.pos, p, pagepx)
            edge = _edge_alpha(px, cpw, cph)
            fpx_geo = font_px(POI_GROUND, w, cpw)
            band = band_alpha(fpx_geo, Inf) * edge
            fpx = min(fpx_geo, MAX_LABEL_PX)
            push!(rows, string(frame, "|poi|", _POI_BASE + k, "|", rnd(fpx), "|", rnd(band)))
        end
        for a in areals
            fpx_geo = font_px(a.ground, w, cpw)
            band = a.kind === :river ? river_alpha(w) : band_alpha(fpx_geo, a.max_px)
            fpx = min(fpx_geo, MAX_AREAL_PX)
            push!(rows, string(frame, "|areal|", a.text, "|", rnd(fpx), "|", rnd(band)))
        end
    end
    return rows
end

"SHA-256 hex of the canonical (geometric, deterministic) Atlas LoD/opacity table."
atlas_digest(; pagepx = (1620, 1080)) = digest_rows(golden_rows(; pagepx))

"""
    placement_rows(; pagepx=(1620,1080)) -> Vector{String}

The solver's DISCRETE placement decisions across `GOLDEN_FRAMES`. For each point label at each
frame (taken from the real COLD solve — `assemble_frame` with no warm-start, so it's deterministic
and frame-independent), emit `frame|id|dropped|sx|sy` where `sx`/`sy` are the SIGN of the label's
offset from its anchor (which quadrant it leans into). Hashing the discrete side, not the pixel
offset, keeps the digest robust to sub-pixel projection noise (it only changes on a genuine
re-placement). It still routes anchors through Makie (via `assemble_frame`), so it is
robust-to-drift, not fully Makie-independent like the affine geometric table above.
"""
function placement_rows(; pagepx = (1620, 1080))
    _PIN_SLO[] = true            # golden reflects production placement (SLO pinned); harden against
                                 # a future test leaving the global Ref `assemble_frame` reads flipped.
    d = load_atlas_data()
    rows = String[]
    sgn(x) = x > 0 ? "+" : x < 0 ? "-" : "0"
    for frame in GOLDEN_FRAMES
        p = frame / _GOLDEN_N
        _, _, af = assemble_frame(d, p; pagepx, prev = Dict{Int,Vec2f}())   # cold = deterministic
        fp = af.fp
        for i in sortperm(fp.ids)                                            # stable order by id
            off = fp.offsets[i]
            push!(rows, string(frame, "|", fp.ids[i], "|", Int(fp.dropped[i]),
                               "|", sgn(off[1]), "|", sgn(off[2])))
        end
    end
    return rows
end

"SHA-256 hex of the Atlas discrete-placement table (robust to sub-pixel projection drift; decisions, not pixels)."
atlas_placement_digest(; pagepx = (1620, 1080)) = digest_rows(placement_rows(; pagepx))
