const W_WIDE   = 3.0
const W_TIGHT  = 0.30
const N_FRAMES = 360
const FPS      = 30
const _CWIDE   = (-121.0, 35.5)
const _CTIGHT  = (-120.66, 35.30)

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

"Axis limits Rect (in projected map-units) for loop phase p; aspect from page (w:h)."
function camera_rect(p; aspect = 16/10)
    w_deg = view_width(p)
    cx, cy = view_center(p)
    # project center + half-extents into map-units (x compressed by KX)
    hx = KX * w_deg / 2
    hy = (w_deg / aspect) / 2
    px = KX * cx
    (px - hx, px + hx, cy - hy, cy + hy)   # (xmin,xmax,ymin,ymax) for limits!
end
