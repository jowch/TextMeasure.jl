# SPDX-License-Identifier: MIT
import Printf
import GeometryBasics as GB

const COL_PROSE  = 0xfa    # 250 grey  — intact asteroid prose
const COL_SHARD  = 0xdf    # 223 warm  — fracture-shard prose (pops against grey)
const COL_SHIP   = 0x33    # 51 cyan   — ship hull
const COL_BEAM   = 0xe2    # 226 yellow— beam + thrust plume
const COL_TAG    = 0xf4    # 244 grey  — callout boxes
const COL_TRAIL  = 0xf3    # 243 grey  — motion trails / targeting leader
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

# --- helpers: write only into empty cells (guarantees no overprint) ----------

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

# Dotted leader from (x0,y0) toward (x1,y1), stopping `stop` cells short of the end.
# Empty-cells-only, so it never overprints prose/boxes.
function _draw_leader!(buf::CellBuffer, x0::Int, y0::Int, x1::Int, y1::Int; fg, stop::Int = 2)
    dx = x1 - x0; dy = y1 - y0
    n = max(abs(dx), abs(dy))
    n == 0 && return buf
    for i in 0:max(0, n - stop)
        t = i / n
        r = round(Int, y0 + dy * t)
        c = round(Int, x0 + dx * t)
        _put_if_empty!(buf, r, c, '·'; fg = fg)
    end
    return buf
end

# --- closed callout box (single-sourced geometry) ----------------------------

_callout_stat(a) = Printf.@sprintf("d:%03dm v:%.2fµ", round(Int, a.radius * 10), hypot(a.vx, a.vy))

# Geometry of an asteroid's closed 3-row callout box centered on the body's x. It
# floats ABOVE the blob when there's room; if that would collide the top frame
# border (tall blob near the top), it FLIPS to below the blob instead. A connector
# (┬ above / ┴ below) plus a short leader joins the box to the blob. `buf_h` is the
# buffer height so the placement rule knows the frame. Returns coords so the drawer
# and the overprint scorer agree exactly.
function _callout_layout(a, pp, buf_h::Int)
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

# All (row,col) cells a callout (box + connector leader) occupies — for the scorer.
function _callout_cells(a, pp, buf_h::Int)
    L = _callout_layout(a, pp, buf_h)
    cells = Tuple{Int,Int}[]
    for c in L.left:(L.left + L.width - 1)
        push!(cells, (L.box_top, c)); push!(cells, (L.box_top + 2, c))
    end
    push!(cells, (L.box_top + 1, L.left)); push!(cells, (L.box_top + 1, L.left + L.width - 1))
    for c in (L.left + 1):(L.left + L.width - 2)
        push!(cells, (L.box_top + 1, c))
    end
    for r in L.leader_from:L.leader_to            # connector leader to the blob
        push!(cells, (r, L.cx))
    end
    return cells
end

function _draw_callout!(buf::CellBuffer, a, pp)
    L = _callout_layout(a, pp, nrows(buf))
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

_pack(a) = pack_prose_into(a.poly, a.prep; scale = max(4.0, 2 * a.radius), min_chord_width = 3.0)

function _draw_asteroid!(buf::CellBuffer, a, debug::Bool)
    pp = _pack(a)
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

# Ship as a focal anchor: a 2-row Arwing wedge + a fading thrust plume below, with
# the charge glyph at the nose when charging. Bold cyan so the eye lands here.
function _draw_ship!(buf::CellBuffer, g)
    ship_visible(g) || return buf
    s = g.ship
    sx = round(Int, s.x); sy = round(Int, s.y)
    put_char!(buf, sy - 1, sx,     '▲'; fg = COL_SHIP, bold = true)   # nose
    put_char!(buf, sy,     sx - 1, '╱'; fg = COL_SHIP, bold = true)   # swept wings
    put_char!(buf, sy,     sx,     '▮'; fg = COL_SHIP, bold = true)   # hull
    put_char!(buf, sy,     sx + 1, '╲'; fg = COL_SHIP, bold = true)
    _put_if_empty!(buf, sy + 1, sx, '┃'; fg = COL_BEAM)               # thrust plume
    _put_if_empty!(buf, sy + 2, sx, '┋'; fg = COL_BEAM)
    if s.charge > 0
        put_char!(buf, sy - 2, sx, CHARGE_GLYPH[s.charge + 1]; fg = COL_BEAM, bold = true)
    end
    return buf
end

function _draw_beam!(buf::CellBuffer, g)
    g.beam.active || return buf
    dirx, diry = sin(g.beam.φ), -cos(g.beam.φ)
    word = "PEW "
    for t in 1:g.beam.length
        ch = word[(t - 1) % length(word) + 1]
        _put_if_empty!(buf, round(Int, g.beam.y + diry * t), round(Int, g.beam.x + dirx * t), ch; fg = COL_BEAM)
    end
    return buf
end

# --- compositor --------------------------------------------------------------

"""
    draw!(buf, g) -> buf

Paint the whole game into `buf` (cleared first). Pure: no terminal I/O. Layer order:
motion trails (under) → asteroid prose + closed callouts → shard prose → targeting
leader → beam → ship → border+footer. Trails/leader/plume write only into empty
cells, so they never overprint prose or callouts.
"""
function draw!(buf::CellBuffer, g::GameState)
    clear!(buf)
    for a in g.asteroids; _draw_trail!(buf, a.x, a.y, a.vx, a.vy, a.radius; fg = COL_TRAIL); end
    for sh in g.shards;   _draw_trail!(buf, sh.x, sh.y, sh.vx, sh.vy, sh.radius; fg = COL_TRAIL); end
    for a in g.asteroids; _draw_asteroid!(buf, a, g.debug); end
    for sh in g.shards;   _draw_shard!(buf, sh, g.debug); end
    # targeting leader: ship → nearest asteroid (dim, empty-cells-only)
    if ship_visible(g) && !isempty(g.asteroids)
        s = g.ship
        ni = argmin([hypot(a.x - s.x, a.y - s.y) for a in g.asteroids])
        a = g.asteroids[ni]
        _draw_leader!(buf, round(Int, s.x), round(Int, s.y) - 2,
                      round(Int, a.x), round(Int, a.y); fg = COL_TRAIL,
                      stop = ceil(Int, a.radius) + 1)
    end
    _draw_beam!(buf, g)
    _draw_ship!(buf, g)
    _draw_border!(buf)
    return buf
end
