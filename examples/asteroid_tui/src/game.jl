# SPDX-License-Identifier: MIT
using Random: AbstractRNG, Xoshiro
import TextMeasure
using TextMeasure: subprep
using Silhouettes: asteroid_polygon, voronoi_shatter
import GeometryBasics as GB

mutable struct GameState
    width::Int; height::Int          # buffer cols, rows
    ship::Ship
    asteroids::Vector{Asteroid}
    shards::Vector{Shard}
    beam::Beam
    rng::Xoshiro
    tick_count::Int
    debug::Bool
    prev_fire::Bool                  # for release-to-launch edge detection
    prev_debug::Bool                 # edge-triggered debug toggle
    respawn_in::Int                  # ticks until ship respawns (when dead)
    last_hit_glyphs::Vector{String}  # words of the most recently fractured asteroid (for tests)
    n_target::Int                    # replenish target (starting n_asteroids)
end

const CHARGE_MAX = 5
const INVULN_TICKS = 120             # ~2s; (120÷10)%2==0 ⇒ ship_visible at tick 0
const MOVE_ACCEL = 0.18              # per-axis velocity added per held strafe key
const FRICTION   = 0.90              # light friction; crisp strafe stop
const SHATTER_CLOSING = 0.9          # asteroid closing-speed: ≥ ⇒ fracture, < ⇒ bounce

_wrap(v, hi) = mod(v, hi)

# Toroidal signed delta from (ax,ay) to (bx,by) on a width×height torus. Each axis
# takes the minimum-magnitude candidate over {d, d-size, d+size}; at the exact
# |d|==size/2 boundary (rarely reached with float positions) the tie-break prefers
# the non-negative candidate, so the result stays deterministic. Returns
# (dx, dy, dist=hypot(dx,dy)) — the VECTOR, so collision code derives
# normal/closing-speed/push-apart from one wrapped delta.
function _wrap_axis(d, size)
    cands = (d, d - size, d + size)
    best = cands[1]
    for c in cands
        if abs(c) < abs(best) || (abs(c) == abs(best) && c > best)
            best = c
        end
    end
    return best
end

_wrap_delta(ax, ay, bx, by, width, height) =
    (dx = _wrap_axis(bx - ax, width); dy = _wrap_axis(by - ay, height); (dx, dy, hypot(dx, dy)))

# Visual-space heading from ship (sx,sy) toward cursor (cx,cy). Cells are ~2:1, so
# the row delta is multiplied by 2 (cell aspect) before atan, so the nose points at
# the cursor ON SCREEN. up=0, clockwise (matches dir(φ)=(sin φ, -cos φ)).
aim_heading(sx, sy, cx, cy) = atan(cx - sx, -((cy - sy) * 2.0))

function _spawn_asteroid(rng::AbstractRNG, width, height)
    poly = asteroid_polygon(rng; n = rand(rng, 8:16), lumpiness = 0.2 + 0.5 * rand(rng))
    prep = TextMeasure.prepare(CellBackend(), asteroid_prose(rng))
    radius = 6.0 + 6.0 * rand(rng)
    return Asteroid(poly,
                    rand(rng) * width, rand(rng) * height,
                    (rand(rng) - 0.5) * 0.6, (rand(rng) - 0.5) * 0.6,
                    (rand(rng) - 0.5) * 0.8 / 60,   # ω in rad/tick (~[-0.4,0.4] rad/s)
                    0.0, radius, prep, 0)
end

"""
    new_game(rng; width=120, height=40, n_asteroids=5) -> GameState

Seeded initial state. All randomness flows from `rng` (pass `Xoshiro(seed)` for a
reproducible game — the golden test relies on this).
"""
function new_game(rng::Xoshiro = Xoshiro(0); width=120, height=40, n_asteroids=5)
    ship = Ship(width/2, height/2, 0.0, 0.0, 0.0, 0, true, INVULN_TICKS)
    asteroids = [_spawn_asteroid(rng, width, height) for _ in 1:n_asteroids]
    beam = Beam(false, 0.0, 0.0, 0.0, 0, 0)
    return GameState(width, height, ship, asteroids, Shard[], beam, rng, 0, false,
                     false, false, 0, String[], n_asteroids)
end

# --- physics -----------------------------------------------------------------

function _advance_ship!(g::GameState, in::Input)
    s = g.ship
    s.alive || return
    in.aim !== nothing && (s.φ = aim_heading(s.x, s.y, in.aim[1], in.aim[2]))
    ax = (in.right ? 1.0 : 0.0) - (in.left ? 1.0 : 0.0)
    ay = (in.down  ? 1.0 : 0.0) - (in.up   ? 1.0 : 0.0)
    if ax != 0.0 || ay != 0.0
        inv = 1.0 / hypot(ax, ay)                  # normalise diagonals
        s.vx += MOVE_ACCEL * ax * inv
        s.vy += MOVE_ACCEL * ay * inv
    end
    s.vx *= FRICTION; s.vy *= FRICTION
    s.x = _wrap(s.x + s.vx, g.width); s.y = _wrap(s.y + s.vy, g.height)
    s.invuln > 0 && (s.invuln -= 1)
end

function _advance_asteroids!(g::GameState)
    for a in g.asteroids
        a.x = _wrap(a.x + a.vx, g.width); a.y = _wrap(a.y + a.vy, g.height)
        a.θ += a.ω; a.age += 1
    end
    for sh in g.shards
        sh.x = _wrap(sh.x + sh.vx, g.width); sh.y = _wrap(sh.y + sh.vy, g.height)
        sh.ttl -= 1
    end
    filter!(sh -> sh.ttl > 0, g.shards)
end

function _handle_charge_and_beam!(g::GameState, in::Input)
    s = g.ship
    if s.alive
        if in.fire
            s.charge = min(s.charge + 1, CHARGE_MAX)
        elseif g.prev_fire && s.charge > 0          # release edge ⇒ launch
            g.beam = Beam(true, s.x, s.y, s.φ, 4 + 6 * s.charge, 6)
            s.charge = 0
        end
    end
    g.prev_fire = in.fire
    if g.beam.active
        g.beam.ttl -= 1
        g.beam.ttl <= 0 && (g.beam = Beam(false, 0.0, 0.0, 0.0, 0, 0))
    end
end

# --- death / respawn ---------------------------------------------------------

"""
    kill_ship!(g)

Destroy the ship; schedules a respawn after a short timer.
"""
function kill_ship!(g::GameState)
    g.ship.alive = false
    g.respawn_in = 60                 # ~1s before respawn
    return g
end

function _handle_respawn!(g::GameState)
    g.ship.alive && return g
    g.respawn_in -= 1
    if g.respawn_in <= 0
        g.ship = Ship(g.width/2, g.height/2, 0.0, 0.0, 0.0, 0, true, INVULN_TICKS)
    end
    return g
end

# blink at ~3Hz: visible 10 ticks on / 10 off while invulnerable
ship_visible(g::GameState) = g.ship.alive && (g.ship.invuln == 0 || (g.ship.invuln ÷ 10) % 2 == 0)

# --- fracture ----------------------------------------------------------------

# Split a Prepared's segment range into up to `n` contiguous chunks at :word
# boundaries, so concatenating the chunks' words reproduces the original word order
# exactly. Guarantees (for n ≤ word-count): returns exactly `n` ranges, none empty,
# tiling 1:length(segments) with no gaps/overlaps.
function _word_boundary_splits(prep::TextMeasure.Prepared, n::Int)
    word_idx = [i for (i, s) in enumerate(prep.segments) if s.kind === :word]
    nw = length(word_idx)
    nseg = length(prep.segments)
    (nw == 0 || n <= 1) && return UnitRange{Int}[1:nseg]
    n = clamp(n, 1, nw)
    # Group nw words into n contiguous nonempty groups: chunk i (1-based) covers word
    # ordinals div((i-1)*nw, n)+1 .. div(i*nw, n). Because n ≤ nw, every group has
    # ≥ 1 word and the first-word ordinal strictly increases, so no empty/duplicate
    # boundary can occur. Map each group to a segment range that tiles 1:nseg —
    # chunk 1 starts at segment 1; chunk i>1 starts at its first word's segment; the
    # last chunk ends at nseg (trailing whitespace stays attached to the final chunk).
    starts = Int[1]                            # chunk 1 starts at segment 1
    for i in 2:n
        lo = div((i - 1) * nw, n) + 1          # first word ordinal of chunk i (≥ 2)
        push!(starts, word_idx[lo])            # ⇒ segment index ≥ 3 > 1, strictly increasing
    end
    ranges = UnitRange{Int}[]
    for (j, st) in enumerate(starts)
        stop = j < length(starts) ? starts[j + 1] - 1 : nseg
        push!(ranges, st:stop)
    end
    return ranges
end

"""
    fracture_asteroid!(g, idx, impact)

Remove asteroid `idx`, fracture its silhouette with `voronoi_shatter` seeded at
`impact`, and re-pack each shard with a `subprep` slice of the asteroid's already
-measured prose (no re-measurement). The slices tile the segment range, so every
glyph survives in exactly one shard, in original order.
"""
function fracture_asteroid!(g::GameState, idx::Int, impact::GB.Point2{Float64})
    a = g.asteroids[idx]
    nword = count(s -> s.kind === :word, a.prep.segments)
    n_shards = 2 + (nword >= 6 ? 2 : 0)
    polys = voronoi_shatter(a.poly, GB.Point2{Float64}(0.0, 0.0); n_shards = n_shards)
    isempty(polys) && (polys = [a.poly])
    # MAJOR #3: shatter may return fewer polys than requested (length ≤ n_shards),
    # so split into EXACTLY length(polys) chunks and assert the 1:1 pairing before
    # zip — otherwise zip would silently truncate and drop glyphs.
    ranges = _word_boundary_splits(a.prep, length(polys))
    # If we have more polys than words, drop the wordless extra polys (keep the
    # text-bearing ones) so the pairing stays 1:1 and lossless.
    if length(polys) > length(ranges)
        polys = polys[1:length(ranges)]
    end
    @assert length(ranges) == length(polys) "fracture: $(length(ranges)) ranges vs $(length(polys)) polys"
    deleteat!(g.asteroids, idx)
    g.last_hit_glyphs = [s.str for s in a.prep.segments if s.kind === :word]
    for (poly, r) in zip(polys, ranges)
        sp = subprep(a.prep, r)
        # Scatter shards like an explosion: spawn each at the asteroid center offset
        # toward its own polygon centroid (so it leaves from where it sat in the
        # parent) and give it an OUTWARD velocity along that direction. Without this,
        # all shards spawn at one point and their prose piles into an illegible blob.
        cx = sum(p[1] for p in poly) / length(poly)
        cy = sum(p[2] for p in poly) / length(poly)
        d = hypot(cx, cy)
        ux, uy = d > 1e-9 ? (cx / d, cy / d) : (0.0, 0.0)   # unit outward direction
        spread = a.radius * 0.9                              # spawn offset in cells
        scatter = 0.6                                        # outward speed (cells/tick)
        push!(g.shards, Shard(poly,
                              a.x + ux * spread, a.y + uy * spread,
                              a.vx + ux * scatter + (rand(g.rng) - 0.5) * 0.2,
                              a.vy + uy * scatter + (rand(g.rng) - 0.5) * 0.2,
                              sp, 90, a.radius / 2))
    end
    return g
end

function _resolve_collisions!(g::GameState)
    g.beam.active || return g
    bx, by, φ = g.beam.x, g.beam.y, g.beam.φ
    dirx, diry = sin(φ), -cos(φ)
    for idx in length(g.asteroids):-1:1
        a = g.asteroids[idx]
        for t in 0:g.beam.length              # sample along the beam
            px, py = bx + dirx * t, by + diry * t
            if hypot(px - a.x, py - a.y) <= a.radius
                fracture_asteroid!(g, idx, GB.Point2{Float64}(px - a.x, py - a.y))
                break
            end
        end
    end
    return g
end

# --- tick --------------------------------------------------------------------

"""
    tick!(g, input) -> g

Advance the game one frame. Pure w.r.t. the terminal — mutates only `g`. Uses only
`g.rng` for any randomness (respawns), so a seeded `new_game` + scripted inputs is
fully reproducible.
"""
function tick!(g::GameState, in::Input)
    _handle_respawn!(g)
    in.debug && !g.prev_debug && (g.debug = !g.debug)   # toggle once per press
    g.prev_debug = in.debug
    _advance_ship!(g, in)
    _advance_asteroids!(g)
    _handle_charge_and_beam!(g, in)
    _resolve_collisions!(g)
    g.tick_count += 1
    return g
end
