# SPDX-License-Identifier: MIT
import Printf
import GeometryBasics as GB

const COL_PROSE  = 0xfa    # 250 grey  — intact asteroid prose
const COL_SHARD  = 0xdf    # 223 warm  — fracture-shard prose (pops against grey)
const COL_SHIP   = 0x33    # 51 cyan   — ship hull
const COL_BEAM   = 0xe2    # 226 yellow— projectiles + charge indicator
const COL_TAG    = 0xf4    # 244 grey  — callout boxes
const COL_TRAIL  = 0xf3    # 243 grey  — motion trails
const COL_DEBUG  = 0x2d    # 45 cyan   — debug bbox overlay
const COL_BORDER = 0xf0    # 240 dim grey — frame + footer
const CHARGE_GLYPH = (' ', '·', '*', '─', '\\', '✸')  # index = charge+1 (1-based)

# House-style gallery footer (docs/superpowers/demos-house-style.md §3): every demo
# carries `TextMeasure.jl · <demo name>` (middot U+00B7). The print pieces put it
# bottom-left on the inner margin; the TUI analogue reserves the bottom border row.
const FOOTER = "TextMeasure.jl · Asteroid TUI"

# --- border + footer ---------------------------------------------------------

# Box-drawing border on the outermost ring, with the attribution footer inlaid into
# the BOTTOM rule (left-anchored, house-style §3/§4). Drawn LAST in `draw!`, so any
# glyph that drifted to the edge is overwritten — viewport clipping reads as a
# deliberate frame edge, not dangling fragments.
function _draw_border!(buf::CellBuffer)
    nr, nc = nrows(buf), ncols(buf)
    (nr < 2 || nc < 2) && return buf
    put_char!(buf, 1, 1, '┌'; fg = COL_BORDER)
    put_char!(buf, 1, nc, '┐'; fg = COL_BORDER)
    put_char!(buf, nr, 1, '└'; fg = COL_BORDER)
    put_char!(buf, nr, nc, '┘'; fg = COL_BORDER)
    for c in 2:(nc - 1)
        put_char!(buf, 1, c, '─'; fg = COL_BORDER)
        put_char!(buf, nr, c, '─'; fg = COL_BORDER)
    end
    for r in 2:(nr - 1)
        put_char!(buf, r, 1, '│'; fg = COL_BORDER)
        put_char!(buf, r, nc, '│'; fg = COL_BORDER)
    end
    if nc >= length(FOOTER) + 6
        put_string!(buf, nr, 3, " " * FOOTER * " "; fg = COL_BORDER)
    end
    return buf
end

# --- decoration helpers: write only into already-empty cells ------------------
# These (trails) yield to anything already drawn, so
# they never land on top of prose or callouts. They are NOT what keeps the prose
# bodies / callouts / hull / border from colliding — that is z-order + scene
# composition (see `draw!`). These helpers just keep the *decorations* tidy.

_put_if_empty!(buf, r, c, ch; fg) =
    (inbounds(buf, r, c) && buf.chars[r, c] == ' ') ? put_char!(buf, r, c, ch; fg = fg) : buf

# A short receding trail behind a moving body (opposite its velocity). Starts one
# cell OUTSIDE the radius (radius+2..radius+4), leaving a blank gap between the blob
# edge and the innermost dot so the debris reads as separate surface debris, not a
# prefix glued onto the body's prose ("··∘ drifting", never "··∘drifting"). Telegraphs
# motion in a still frame. Empty-cells-only.
function _draw_trail!(buf::CellBuffer, cx::Real, cy::Real, vx::Real, vy::Real, radius::Real; fg)
    speed = hypot(vx, vy)
    speed < 1e-3 && return buf
    ux, uy = vx / speed, vy / speed
    glyphs = ('∘', '·', '·')
    for k in 1:3
        d = radius + 1 + k               # +1 = one blank cell of gap from the blob edge
        r = round(Int, cy - uy * d)      # behind = opposite velocity
        c = round(Int, cx - ux * d)
        _put_if_empty!(buf, r, c, glyphs[k]; fg = fg)
    end
    return buf
end

# --- closed callout box (single-sourced geometry) ----------------------------

_callout_stat(a) = Printf.@sprintf("d:%03dm v:%.2fµ", round(Int, a.radius * 10), hypot(a.vx, a.vy))

# Geometry of an asteroid's closed 3-row callout box centered on the body's x. It
# floats ABOVE the blob when there's room; if that would collide the top frame
# border (tall blob near the top), it FLIPS to below the blob instead. A connector
# (┬ above / ┴ below) plus a short leader joins the box to the blob.
function _callout_layout(a, pp)
    stat  = _callout_stat(a)
    inner = length(stat) + 2          # one space pad each side
    width = inner + 2                 # plus the two │ borders
    cx    = round(Int, a.x)
    left  = cx - width ÷ 2
    blob_top = round(Int, a.y) - pp.rows ÷ 2
    blob_bot = blob_top + pp.rows - 1
    top_above = blob_top - 4          # 3 box rows + 1 leader gap above the blob
    if top_above >= 2                 # fits above the top border (row 1 is border)
        return (; stat, inner, width, cx, left, box_top = top_above,
                  place = :above, leader_from = top_above + 3, leader_to = blob_top - 1)
    else                              # flip below the blob
        box_top = blob_bot + 2        # 1 leader gap then the box
        return (; stat, inner, width, cx, left, box_top,
                  place = :below, leader_from = blob_bot + 1, leader_to = box_top - 1)
    end
end

function _draw_callout!(buf::CellBuffer, a, pp)
    L = _callout_layout(a, pp)
    conn = L.cx - L.left + 1                       # 1-based offset of connector in the box rule
    toprule = collect("┌" * ("─"^L.inner) * "┐")
    botrule = collect("└" * ("─"^L.inner) * "┘")
    # The connector tee points toward the blob: ┴ on the box edge nearest the blob.
    if L.place == :above && 1 <= conn <= length(botrule)
        botrule[conn] = '┴'                       # blob is below the box
    elseif L.place == :below && 1 <= conn <= length(toprule)
        toprule[conn] = '┴'                       # blob is above the box
    end
    mid = "│" * " " * L.stat * " " * "│"
    put_string!(buf, L.box_top,     L.left, String(toprule); fg = COL_TAG)
    put_string!(buf, L.box_top + 1, L.left, mid;             fg = COL_TAG)
    put_string!(buf, L.box_top + 2, L.left, String(botrule); fg = COL_TAG)
    for r in L.leader_from:L.leader_to            # leader (only into empty cells)
        _put_if_empty!(buf, r, L.cx, '│'; fg = COL_TAG)
    end
    return buf
end

# --- bodies ------------------------------------------------------------------

function _blit_packed!(buf::CellBuffer, pp, cx::Real, cy::Real; fg, debug::Bool)
    r0 = round(Int, cy) - pp.rows ÷ 2
    c0 = round(Int, cx) - pp.cols ÷ 2
    for (r, c, ch) in pp.cells
        put_char!(buf, r0 + r - 1, c0 + c - 1, ch; fg = debug ? COL_DEBUG : fg)
    end
    return buf
end

# Rotate a silhouette's vertices by θ (radians) about the origin. θ=0 is an exact
# identity (cos 0 = 1, sin 0 = 0), so unrotated bodies and the golden are byte-stable.
_rotate_poly(poly, θ) = (c = cos(θ); s = sin(θ);
    [GB.Point2{Float64}(c*p[1] - s*p[2], s*p[1] + c*p[2]) for p in poly])

_pack(body, θ = 0.0) = pack_prose_into(_rotate_poly(body.poly, θ), body.prep;
                                       scale = max(4.0, 2 * body.radius), min_chord_width = 3.0)

function _draw_asteroid!(buf::CellBuffer, a, debug::Bool)
    pp = _pack(a, a.θ)
    _blit_packed!(buf, pp, a.x, a.y; fg = COL_PROSE, debug = debug)
    _draw_callout!(buf, a, pp)
    return buf
end

# Shards: warm-colored prose so the explosion pops as distinct from grey asteroids.
function _draw_shard!(buf::CellBuffer, sh, debug::Bool)
    pp = _pack(sh)
    _blit_packed!(buf, pp, sh.x, sh.y; fg = COL_SHARD, debug = debug)
    return buf
end

# Ship: a cyan hull at (sx,sy) with a directional NOSE one cell along heading φ
# (8-way octant table), and — while charging — the charge glyph one cell BEYOND the
# nose along φ. Pure function of g (no RNG/clock): same state ⇒ same cells. At φ=0
# the nose is '▲' (nose-up), matching the golden's pinned pose.
# φ increases CLOCKWISE from up, so the table must run CW: k·45° = N,NE,E,SE,S,SW,W,NW.
# (A CCW table makes the nose point backwards — e.g. '◀' while facing right.)
const SHIP_OCTANT = ('▲', '◥', '▶', '◢', '▼', '◣', '◀', '◤')  # N NE E SE S SW W NW

function _draw_ship!(buf::CellBuffer, g)
    ship_visible(g) || return buf
    s = g.ship
    sx = round(Int, s.x); sy = round(Int, s.y)
    dx, dy = sin(s.φ), -cos(s.φ)
    nose = SHIP_OCTANT[mod(round(Int, s.φ / (π/4)), 8) + 1]   # mod handles negative φ
    put_char!(buf, sy, sx, '▮'; fg = COL_SHIP, bold = true)                              # hull
    put_char!(buf, round(Int, s.y + dy), round(Int, s.x + dx), nose; fg = COL_SHIP, bold = true)  # nose
    if s.charge > 0
        put_char!(buf, round(Int, s.y + 2dy), round(Int, s.x + 2dx),
                  CHARGE_GLYPH[s.charge + 1]; fg = COL_BEAM, bold = true)
    end
    return buf
end

function _draw_projectiles!(buf::CellBuffer, g)
    for p in g.projectiles
        put_char!(buf, round(Int, p.y), round(Int, p.x), '•'; fg = COL_BEAM, bold = true)
    end
    return buf
end

# --- compositor --------------------------------------------------------------

"""
    draw!(buf, g) -> buf

Paint the whole game into `buf` (cleared first). Pure: no terminal I/O.

Non-overlap is guaranteed by **z-order + scene composition**, not by per-write
guards: the scene is hand-composed (and, for the golden, seed-pinned) so the prose
bodies and their callouts don't share cells, and the draw order layers later
elements over earlier ones deliberately. Layer order: motion trails (under) →
asteroid prose + closed callouts → shard prose → projectiles → ship →
border + footer. The decorations (trails) additionally yield
to already-occupied cells (`_put_if_empty!`) so they never land on the prose.
"""
function draw!(buf::CellBuffer, g::GameState)
    clear!(buf)
    for a in g.asteroids; _draw_trail!(buf, a.x, a.y, a.vx, a.vy, a.radius; fg = COL_TRAIL); end
    for sh in g.shards;   _draw_trail!(buf, sh.x, sh.y, sh.vx, sh.vy, sh.radius; fg = COL_TRAIL); end
    for a in g.asteroids; _draw_asteroid!(buf, a, g.debug); end
    for sh in g.shards;   _draw_shard!(buf, sh, g.debug); end
    _draw_projectiles!(buf, g)
    _draw_ship!(buf, g)
    _draw_border!(buf)
    return buf
end
