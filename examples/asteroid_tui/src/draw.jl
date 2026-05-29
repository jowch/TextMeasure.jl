# SPDX-License-Identifier: MIT
import Printf
import GeometryBasics as GB

const COL_PROSE = 0xfa    # 250 grey
const COL_SHIP  = 0x33    # 51 cyan
const COL_BEAM  = 0xe2    # 226 yellow
const COL_TAG   = 0xf4    # 244 grey
const COL_DEBUG = 0x2d    # 45 cyan
const CHARGE_GLYPH = (' ', '·', '*', '─', '\\', '✸')  # index = charge+1 (1-based)

function _blit_packed!(buf::CellBuffer, pp, cx::Real, cy::Real; fg, debug::Bool)
    r0 = round(Int, cy) - pp.rows ÷ 2
    c0 = round(Int, cx) - pp.cols ÷ 2
    for (r, c, ch) in pp.cells
        if debug
            put_char!(buf, r0 + r - 1, c0 + c - 1, ch; fg = COL_DEBUG)
        else
            put_char!(buf, r0 + r - 1, c0 + c - 1, ch; fg = fg)
        end
    end
end

function _draw_asteroid!(buf::CellBuffer, a, debug::Bool)
    pp = pack_prose_into(a.poly, a.prep; scale = max(4.0, 2 * a.radius), min_chord_width = 3.0)
    _blit_packed!(buf, pp, a.x, a.y; fg = COL_PROSE, debug = debug)
    tag = Printf.@sprintf("┌─ d:%03dm v:%.2fµ ─┐", round(Int, a.radius * 10), hypot(a.vx, a.vy))
    put_string!(buf, round(Int, a.y) - pp.rows ÷ 2 - 1, round(Int, a.x) - length(tag) ÷ 2, tag; fg = COL_TAG)
end

function _draw_ship!(buf::CellBuffer, g)
    ship_visible(g) || return
    s = g.ship
    put_char!(buf, round(Int, s.y), round(Int, s.x), '▲'; fg = COL_SHIP, bold = true)
    if s.charge > 0
        put_char!(buf, round(Int, s.y) - 1, round(Int, s.x), CHARGE_GLYPH[s.charge + 1]; fg = COL_BEAM, bold = true)
    end
end

function _draw_beam!(buf::CellBuffer, g)
    g.beam.active || return
    dirx, diry = sin(g.beam.φ), -cos(g.beam.φ)
    word = "PEW "
    for t in 1:g.beam.length
        ch = word[(t - 1) % length(word) + 1]
        put_char!(buf, round(Int, g.beam.y + diry * t), round(Int, g.beam.x + dirx * t), ch; fg = COL_BEAM)
    end
end

"""
    draw!(buf, g) -> buf

Paint the whole game into `buf` (cleared first). Pure: no terminal I/O.
"""
function draw!(buf::CellBuffer, g::GameState)
    clear!(buf)
    for a in g.asteroids; _draw_asteroid!(buf, a, g.debug); end
    for sh in g.shards
        pp = pack_prose_into(sh.poly, sh.prep; scale = max(4.0, 2 * sh.radius), min_chord_width = 3.0)
        _blit_packed!(buf, pp, sh.x, sh.y; fg = COL_PROSE, debug = g.debug)
    end
    _draw_beam!(buf, g)
    _draw_ship!(buf, g)
    return buf
end
