# lod.jl — Geographic-scaling level-of-detail.
#
# Labels are sized in GEOGRAPHIC space: each feature has a "ground em" `g` measured in
# degrees of latitude. At a frame whose isotropic scale is `P` pixels per map-unit, its
# on-screen type is `font_px = g * P`. As the camera dives, `view_width` shrinks → `P`
# grows → every label grows. Visibility is then a pixel band: a label shows once its
# type is legible (`font_px ≥ MIN_PX`) and, for coarse features, hides once it outgrows
# the frame (`font_px > max_px`, a hand-off). San Luis Obispo is pinned to a constant
# size and is always visible — the whole field scales around it.
#
# Included after data.jl (uses KX). Replaces the old rank-ladder LoD.

# ── Tunable constants (FIRST GUESSES — nudge these visually) ──────────────────
const MIN_PX  = 15.6    # lower band: a label appears once its type reaches this px height
const SLO_PX  = 24.0    # San Luis Obispo is pinned to this constant px size, always shown
const _BAND_HYST = 0.08 # once shown, widen the band ±8% before hiding (anti-flicker)

const POI_GROUND = 0.00576  # POI ground em (degrees) → landmarks enter last (~w0.65)

"""
Ground em (degrees lat) for a town by census rank. SLO (rank 1) is pinned, not here.
Sizes are 1.2× the original tuning (MIN_PX + every ground scaled together), so each feature
still ENTERS at the SAME view width — just 20% larger on screen. For the [2.0, 0.55]
dive: majors fade in ~w1.6 (0.5-α ~w1.3), the 6–7 band ~w1.1, the 8–9 necklace ~w0.9
(content_px_w≈1588 → font_px = ground·1588/(KX·w)).
"""
function town_ground(rank::Integer)::Float64
    rank ≤ 5 ? 0.0132 :   # majors → fade in ~w1.6
    rank ≤ 7 ? 0.009  :   # ranks 6–7 → enter ~w1.1
               0.00744    # ranks 8–9 → enter ~w0.9
end

# ── Scaling math ──────────────────────────────────────────────────────────────

"Pixels per map-unit at view width `w_deg` for a content area `content_px_w` wide."
pixels_per_unit(w_deg::Real, content_px_w::Real)::Float64 = content_px_w / (KX * w_deg)

"On-screen type height (px) of a feature with ground em `g`° at the current frame."
font_px(ground::Real, w_deg::Real, content_px_w::Real)::Float64 =
    ground * pixels_per_unit(w_deg, content_px_w)

"""
    visible(fpx, max_px, shown_before; min_px=MIN_PX) -> Bool

Pixel-band visibility with hysteresis. A label is shown when its type height `fpx`
sits in `[min_px, max_px]`. Once shown, the band is widened ±`_BAND_HYST` before it
hides, to kill per-frame flicker. `max_px = Inf` ⇒ no upper hand-off (towns/POIs grow
forever); a finite `max_px` ⇒ a coarse feature hands off once it outgrows the frame.
"""
function visible(fpx::Real, max_px::Real, shown_before::Bool; min_px::Real = MIN_PX)::Bool
    lo = shown_before ? min_px * (1 - _BAND_HYST) : min_px
    hi = isfinite(max_px) ? (shown_before ? max_px * (1 + _BAND_HYST) : max_px) : Inf
    lo ≤ fpx ≤ hi
end

"""
    band_alpha(fpx, max_px; min_px=MIN_PX) -> Float64

Smooth opacity for the px focus band — opacity as a function of entering/leaving focus.
A label FADES IN as its type grows past the legibility floor and (for coarse features
with a finite `max_px`) FADES OUT as it outgrows the frame:
- fade in : smoothstep over `[min_px, min_px*1.6]` → 0..1.
- fade out: smoothstep over `[max_px*0.6, max_px]` → 1..0 (only when `max_px` is finite).
- α = min(fade_in, fade_out); 0 below the floor / above max. `visible == (band_alpha>0)`.
"""
function band_alpha(fpx::Real, max_px::Real; min_px::Real = MIN_PX)::Float64
    fin  = smoothstep((fpx - min_px) / (0.6 * min_px))            # 0 at min_px → 1 at 1.6·min_px
    fout = isfinite(max_px) ?
           smoothstep((max_px - fpx) / (0.4 * max_px)) : 1.0      # 1 until 0.6·max → 0 at max_px
    min(fin, fout)
end
