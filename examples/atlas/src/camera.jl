# SPDX-License-Identifier: MIT
const W_WIDE   = 2.0
const W_TIGHT  = 0.55
const N_FRAMES = 360
const FPS      = 30
const _CWIDE   = (-120.90, 35.45)   # central-coast overview
const _CTIGHT  = (-120.74, 35.31)   # Morro Bay–Los Osos–SLO–Pismo cluster centroid

"""
    smoothstep(t) -> Float64

Hermite smoothstep easing: `clamp(t, 0, 1)` then `t²·(3 − 2t)`, with zero velocity at both
endpoints. Used throughout the camera dive and the LoD opacity fades.

# Examples
```jldoctest
julia> smoothstep(0.0), smoothstep(0.5), smoothstep(1.0)
(0.0, 0.5, 1.0)
```
"""
smoothstep(t) = (t = clamp(t, 0, 1); t*t*(3 - 2t))

"Triangle phase 0→1→0 over the loop, smoothstep-eased per half (vel=0 at 0,½,1)."
function _dive(p)
    p = mod(p, 1.0)
    half = p < 0.5 ? p/0.5 : (1 - p)/0.5      # 0→1 down, 1→0 up
    return smoothstep(half)                    # eased dive fraction in [0,1]
end

"Geometric (log-interpolated) view width at loop phase p∈[0,1)."
view_width(p) = exp((1 - _dive(p))*log(W_WIDE) + _dive(p)*log(W_TIGHT))

"Center pans WIDE→TIGHT→WIDE on the same eased clock."
function view_center(p)
    d = _dive(p)
    ( (1-d)*_CWIDE[1] + d*_CTIGHT[1],
      (1-d)*_CWIDE[2] + d*_CTIGHT[2] )
end

"""
    camera_rect(p; aspect)

Axis limits Rect (in projected map-units) for loop phase p. `aspect` is the
**content** aspect (drawable width÷height of the axis bbox in px); the returned
window matches it so the isotropic KX/cosφ0 projection fills the frame WITHOUT
geographic distortion. `view_width` sets the longitudinal half-extent; the
latitudinal half-extent is divided by `aspect`. Default 5:4 (the page default).
"""
function camera_rect(p; aspect = 5/4)
    w_deg = view_width(p)
    cx, cy = view_center(p)
    # project center + half-extents into map-units (x already compressed by KX).
    hx = KX * w_deg / 2          # longitudinal half-extent (map-units)
    hy = hx / aspect             # latitudinal half-extent → window matches content aspect
    px = KX * cx
    (px - hx, px + hx, cy - hy, cy + hy)   # (xmin,xmax,ymin,ymax) for limits!
end
