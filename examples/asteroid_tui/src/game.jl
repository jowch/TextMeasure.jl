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
    respawn_in::Int                  # ticks until ship respawns (when dead)
    last_hit_glyphs::Vector{String}  # words of the most recently fractured asteroid (for tests)
end

const CHARGE_MAX = 5
const INVULN_TICKS = 120             # ~2s at 60fps
const RERASTER_EVERY = 5
const THRUST = 0.05
const TURN   = 0.12
const FRICTION = 0.98

_wrap(v, hi) = mod(v, hi)

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
    ship = Ship(width/2, height/2, 0.0, 0.0, 0.0, 0, true, 0)
    asteroids = [_spawn_asteroid(rng, width, height) for _ in 1:n_asteroids]
    beam = Beam(false, 0.0, 0.0, 0.0, 0, 0)
    return GameState(width, height, ship, asteroids, Shard[], beam, rng, 0, false,
                     false, 0, String[])
end

# --- physics -----------------------------------------------------------------

function _advance_ship!(g::GameState, in::Input)
    s = g.ship
    s.alive || return
    in.left  && (s.φ -= TURN)
    in.right && (s.φ += TURN)
    if in.thrust
        s.vx += THRUST * sin(s.φ); s.vy -= THRUST * cos(s.φ)
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
        push!(g.shards, Shard(poly, a.x, a.y,
                              a.vx + (rand(g.rng) - 0.5) * 0.4,
                              a.vy + (rand(g.rng) - 0.5) * 0.4,
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
    in.debug && (g.debug = !g.debug)
    _advance_ship!(g, in)
    _advance_asteroids!(g)
    _handle_charge_and_beam!(g, in)
    _resolve_collisions!(g)
    g.tick_count += 1
    return g
end
