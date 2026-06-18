# SPDX-License-Identifier: MIT
# schedule.jl — the 6-press CCW tide sweep that drives the loop.
#
# The tide sweeps COUNTERCLOCKWISE around the block: W → SW → SE → E → NE → NW → back to W. Each
# press is ONE continuous smooth pulse — the tide eases almost to its furthest reach, slows to a
# crawl at the crest (so flat it FEELS like lingering) but never literally holds, then recedes,
# all one curve. Presses run BACK-TO-BACK, so the motion reads as relentless wave-after-wave,
# each fully receding before the next swells. Over N_FRAMES the loop returns EXACTLY to a bare-
# rest trough (frame N_FRAMES ≡ frame 0) — seamless and infinitely loopable by construction.

# CCW sweep order around the block.
const DIRECTIONS = (:W, :SW, :SE, :E, :NE, :NW)

const N_PRESSES        = 6
# Frames per press, and total loop length. A tide is LANGUID — run at 60 fps for a smooth,
# shimmer-free stroke. 200 frames/press @ 60 fps ≈ 3.33 s per wave; 6 × 200 = 1200 frames ≈
# 20 s/loop. (Tests key off FRAMES_PER_PRESS / N_FRAMES, not the literal 1200.)
const FRAMES_PER_PRESS = 200
const N_FRAMES         = N_PRESSES * FRAMES_PER_PRESS   # 1200

# --- the depth pulse: ONE continuous symmetric curve over u ∈ [0,1] --------------------------
# depth(u) = S(2·min(u, 1−u)), where S is the 7th-order "smootheststep". The argument ramps 0→1
# over the first half of the press and 1→0 over the second, so depth rises to a single crest at
# u=0.5 then recedes — all one curve, no constant plateau.
#
# Why the septic S (not sin² or quintic): its 1st AND 2nd derivatives both vanish at t=1, giving a
# FLATTER crest, so the tide creeps almost to a stop near the peak (reads as a held swell) while
# still always moving. Its derivatives also vanish at t=0 ⇒ zero velocity at both troughs (u=0,1)
# ⇒ presses chain without a jerk, and depth returns to EXACTLY 0 at every loop boundary.
_smootheststep(t) = (t <= 0.0) ? 0.0 : (t >= 1.0) ? 1.0 :
    t^4 * (35.0 + t * (-84.0 + t * (70.0 - 20.0 * t)))   # 35t⁴ − 84t⁵ + 70t⁶ − 20t⁷

_press_depth(u::Float64) = _smootheststep(2.0 * min(u, 1.0 - u))

"""
    press_at(frame::Int) -> (dir::Symbol, depth::Float64, phase::Float64)

Resolve the press direction, normalized depth ∈ [0,1], and global wave phase for `frame`.

`frame` is taken mod `N_FRAMES`, so `press_at(N_FRAMES) == press_at(0)` (seamless loop). Each
press window is ONE continuous pulse (see `_press_depth`): `depth==0` with zero velocity at the
start of every press (l==0) and again at its end, a single flat-but-moving crest at u=0.5, so
presses chain back-to-back into a relentless tide and frame 0 is a bare-rest trough. `phase =
2π·frame/N_FRAMES` completes one cycle over the loop, so phase at frame N_FRAMES matches frame 0.
"""
function press_at(frame::Int)
    f = mod(frame, N_FRAMES)
    p = fld(f, FRAMES_PER_PRESS)              # 0..5
    dir = DIRECTIONS[p + 1]
    l = f % FRAMES_PER_PRESS                  # 0..199
    u = l / FRAMES_PER_PRESS                  # ∈ [0,1)

    depth = _press_depth(u)
    phase = 2π * f / N_FRAMES
    return (dir, depth, phase)
end
