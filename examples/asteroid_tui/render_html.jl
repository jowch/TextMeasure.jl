# SPDX-License-Identifier: MIT
#
# Gallery export: render CellBuffer frames to a colored HTML artifact so the #E
# showcase can be SCORED in its real palette (phosphor field + state accents),
# which the plain-text golden discards. Not part of the test path — a capture tool.
#
#   julia --project=examples/asteroid_tui examples/asteroid_tui/render_html.jl
#
# Emits two files under examples/asteroid_tui/build/:
#   frame_current.html  — the committed golden scene, in color (grade baseline)
#   filmstrip.html      — intact | reflow(rotated) | fracture, the refine direction

using AsteroidTUI
using AsteroidTUI: new_game, draw!, CellBuffer, CellBackend, nrows, ncols, fracture_asteroid!
import TextMeasure
import GeometryBasics as GB
using Random

const FONT = abspath(joinpath(@__DIR__, "..", "fonts", "IBMPlexMono", "IBMPlexMono-Regular.ttf"))

# xterm-256 → hex for exactly the indices draw.jl uses (+ a default ink).
const PALETTE = Dict(
    0x00 => "#d8d8d8",   # terminal default ink (unused on drawn glyphs)
    0xf0 => "#585858",   # 240 border / footer
    0xf3 => "#767676",   # 243 trail
    0xf4 => "#808080",   # 244 callout
    0xfa => "#bcbcbc",   # 250 intact prose
    0xdf => "#ffd7af",   # 223 warm shard prose
    0x33 => "#22d3ee",   # 51  ship hull (cyan)
    0xe2 => "#fbbf24",   # 226 beam (amber)
    0x2d => "#00d7ff",   # 45  debug
    0x89 => "#b5793c",   # 137 brass — house-style signature (footer middot)
)
hexof(fg::UInt8) = get(PALETTE, fg, "#d8d8d8")

esc(c::Char) = c == '<' ? "&lt;" : c == '>' ? "&gt;" : c == '&' ? "&amp;" : string(c)

# One CellBuffer → a <pre> of color spans. Runs of equal (fg,bold) are coalesced.
function cell_pre(buf::CellBuffer)
    io = IOBuffer()
    print(io, "<pre class=\"frame\">")
    for r in 1:nrows(buf)
        fg = nothing; bold = false; open = false
        for c in 1:ncols(buf)
            ch = buf.chars[r, c]; f = buf.fg[r, c]; b = buf.bold[r, c]
            if !open || f != fg || b != bold
                open && print(io, "</span>")
                print(io, "<span style=\"color:", hexof(f), b ? ";font-weight:700" : "", "\">")
                fg = f; bold = b; open = true
            end
            print(io, esc(ch))
        end
        open && print(io, "</span>")
        print(io, '\n')
    end
    print(io, "</pre>")
    return String(take!(io))
end

function page(title, panels)  # panels :: Vector{(label, pre_html)}
    io = IOBuffer()
    print(io, """<!doctype html><meta charset="utf-8"><title>$title</title>
<style>
  @font-face { font-family:"Plex"; src:url("file://$FONT"); }
  :root { --paper:#0a0a0c; }
  html,body { margin:0; background:#000; }
  body { padding:40px; display:inline-flex; gap:28px; align-items:flex-start;
         font-family:"Plex",monospace; }
  .panel { background:var(--paper); padding:14px 16px 12px; border-radius:2px; }
  .frame { margin:0; font-family:"Plex",monospace; font-size:13px; line-height:1.18;
           letter-spacing:0; color:#d8d8d8; white-space:pre; }
  .cap { margin:10px 2px 0; font-family:"Plex",monospace; font-size:11px;
         color:#808080; letter-spacing:.02em; }
  .cap b { color:#b5793c; font-weight:600; }
</style>
<body>""")
    for (label, pre) in panels
        print(io, "<div class=\"panel\">", pre, "<div class=\"cap\">", label, "</div></div>")
    end
    print(io, "</body>")
    return String(take!(io))
end

# ---- scenes -----------------------------------------------------------------

const HERO =
    "Born from the shattering of some long-dead world, this drifting massif of nickel and " *
    "shadowed ice has wandered the cold reaches for an age, its pitted face a record of every " *
    "blow the dark has dealt it, tumbling on without haste or heading through the long night " *
    "between the scattered stars."

_prep(s) = TextMeasure.prepare(CellBackend(), s)

# A single dominant hero asteroid centered in a w×h field; returns (game, hero).
function hero_scene(; w, h, θ, radius = 11.0, seed = 38)
    g = new_game(Xoshiro(seed); width = w, height = h, n_asteroids = 1)
    g.ship.alive = false                      # filmstrip panels focus on the body
    a = g.asteroids[1]
    a.x = w / 2; a.y = h / 2 + 1
    a.vx = 0.20; a.vy = 0.08; a.ω = 0.02; a.θ = θ
    a.radius = radius; a.prep = _prep(HERO)
    return g, a
end

mkpath(joinpath(@__DIR__, "build"))

const MED = "Porous, fast, and faintly glittering, it drifts where the sunlight finally " *
            "grows too thin to warm a stone."

# (1) current committed golden scene, in color (mirrors test/test_golden.jl::_run_golden)
function run_golden()
    g = new_game(Xoshiro(38); width = 116, height = 36, n_asteroids = 2)
    g.ship.x = 58.0; g.ship.y = 31.0; g.ship.φ = 0.0; g.ship.vx = 0.0; g.ship.vy = -0.15
    a1, a2 = g.asteroids
    a1.x = 32.0; a1.y = 18.0; a1.vx =  0.22; a1.vy = 0.10; a1.ω =  0.012; a1.radius = 10.0; a1.prep = _prep(HERO)
    a2.x = 93.0; a2.y = 12.0; a2.vx = -0.18; a2.vy = 0.06; a2.ω = -0.02;  a2.radius =  6.0; a2.prep = _prep(MED)
    buf = CellBuffer(g.height, g.width); draw!(buf, g); return buf
end
_buf = run_golden()
write(joinpath(@__DIR__, "build", "frame_current.html"),
      page("frame_current", [("the committed 116×36 golden, in its real palette", cell_pre(_buf))]))

# (2) filmstrip: intact → reflow(rotated) → fracture
W, H = 54, 30
g0, _ = hero_scene(; w = W, h = H, θ = 0.0)
b0 = CellBuffer(H, W); draw!(b0, g0)

g1, _ = hero_scene(; w = W, h = H, θ = 1.15)
b1 = CellBuffer(H, W); draw!(b1, g1)

g2, a2 = hero_scene(; w = W, h = H, θ = 0.5, radius = 9.0)
fracture_asteroid!(g2, 1, GB.Point2{Float64}(2.0, -1.0))
b2 = CellBuffer(H, W); draw!(b2, g2)

write(joinpath(@__DIR__, "build", "filmstrip.html"),
      page("filmstrip", [
        ("<b>measure once</b> — prose packed into the silhouette", cell_pre(b0)),
        ("<b>reflow live</b> — same cached measurement, body rotated", cell_pre(b1)),
        ("<b>fracture</b> — sliced on word boundaries, no re-measure", cell_pre(b2)),
      ]))

println("wrote build/frame_current.html and build/filmstrip.html")
