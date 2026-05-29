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
    projectiles::Vector{Projectile}
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
const SHATTER_CLOSING = 0.13         # asteroid closing-speed: ≥ ⇒ fracture, < ⇒ bounce.
                                     # Scaled with the _spawn_asteroid velocity coefficient
                                     # (0.2) so the bounce/shatter MIX is speed-independent:
                                     # halve both to slow the field without changing which
                                     # collisions shatter.
const PROJECTILE_SPEED = 1.2         # cells/tick — fast vs the slow asteroid field
const PROJECTILE_TTL   = 90          # lifetime backstop (off-screen despawn usually fires first)
const BURST_SPREAD     = 0.22        # rad (~12.5°) half-fan for a charged burst

_wrap(v, hi) = mod(v, hi)

# A body is fully off-screen once its centre passes an edge by more than its radius.
_offscreen(b, w, h) = b.x < -b.radius || b.x > w + b.radius || b.y < -b.radius || b.y > h + b.radius

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
                    (rand(rng) - 0.5) * 0.2, (rand(rng) - 0.5) * 0.2,   # ~7× slower than 1.4; see SHATTER_CLOSING
                    (rand(rng) - 0.5) * 0.08,        # ω in rad/tick (~±1.2 rad/s max at 30fps — a visible tumble)
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
    return GameState(width, height, ship, asteroids, Shard[], Projectile[], rng, 0, false,
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
        a.x += a.vx; a.y += a.vy            # no wrap — only the ship wraps
        a.θ += a.ω; a.age += 1
    end
    filter!(a -> !_offscreen(a, g.width, g.height), g.asteroids)
    for sh in g.shards
        sh.x += sh.vx; sh.y += sh.vy
        sh.ttl -= 1
    end
    filter!(sh -> sh.ttl > 0 && !_offscreen(sh, g.width, g.height), g.shards)
end

function _fire_burst!(g::GameState, n::Int)
    s = g.ship
    ox, oy = s.x + sin(s.φ), s.y - cos(s.φ)            # nose
    for k in 1:n
        off = n == 1 ? 0.0 : -BURST_SPREAD + 2*BURST_SPREAD*(k-1)/(n-1)   # even fan
        a = s.φ + off
        push!(g.projectiles, Projectile(ox, oy,
                                        PROJECTILE_SPEED * sin(a),
                                        -PROJECTILE_SPEED * cos(a),
                                        PROJECTILE_TTL))
    end
    return g
end

# Hold `fire` to grow the charge; the first release fires a fan burst of (1 + charge)
# projectiles from the nose. No RNG — deterministic.
function _handle_charge_and_fire!(g::GameState, in::Input)
    s = g.ship
    if s.alive
        if in.fire
            s.charge = min(s.charge + 1, CHARGE_MAX)
        elseif g.prev_fire && s.charge > 0
            _fire_burst!(g, 1 + s.charge)
            s.charge = 0
        end
    end
    g.prev_fire = in.fire
    return g
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
`impact` — a CELL-space offset from the asteroid centre, converted to the polygon's
own (~±1) frame internally — and re-pack each shard with a `subprep` slice of the
asteroid's already-measured prose (no re-measurement). The slices tile the segment
range, so every glyph survives in exactly one shard, in original order.
"""
function fracture_asteroid!(g::GameState, idx::Int, impact::GB.Point2{Float64})
    a = g.asteroids[idx]
    nword = count(s -> s.kind === :word, a.prep.segments)
    n_shards = 2 + (nword >= 6 ? 2 : 0)
    # Convert the CELL-space contact offset into the polygon's own (~±1) frame and
    # clamp into the polygon bbox so voronoi_shatter's seeds land inside the parent.
    fx = clamp(impact[1] / a.radius, minimum(p[1] for p in a.poly), maximum(p[1] for p in a.poly))
    fy = clamp(impact[2] / a.radius, minimum(p[2] for p in a.poly), maximum(p[2] for p in a.poly))
    polys = voronoi_shatter(a.poly, GB.Point2{Float64}(fx, fy); n_shards = n_shards)
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

# Asteroid↔asteroid: bounce below the closing-speed threshold, fracture both above.
# Euclidean — only the ship wraps. Collect fracture pairs and apply them AFTER the
# sweep so deleteat! never invalidates a live index mid-iteration.
function _resolve_asteroid_collisions!(g::GameState)
    n = length(g.asteroids)
    n < 2 && return g
    to_fracture = Tuple{Int,Float64,Float64}[]
    fractured = falses(n)
    # Single-pass O(n²) sweep. The bounce branch mutates a's position/velocity in
    # place, and a's corrected state is intentionally reused for a's remaining j
    # checks this tick. In clusters of 3+ overlapping asteroids one pass may leave
    # residual overlap (resolved on the next tick) — acceptable for a demo.
    for i in 1:(n-1)
        fractured[i] && continue
        a = g.asteroids[i]
        for j in (i+1):n
            fractured[j] && continue
            b = g.asteroids[j]
            dx = b.x - a.x; dy = b.y - a.y; dist = hypot(dx, dy)
            rsum = a.radius + b.radius
            (dist >= rsum || dist < 1e-9) && continue
            nx, ny = dx/dist, dy/dist                 # contact normal a→b
            rvx, rvy = b.vx - a.vx, b.vy - a.vy
            closing = -(rvx*nx + rvy*ny)              # >0 ⇒ approaching
            if closing >= SHATTER_CLOSING
                push!(to_fracture, (i,  nx*a.radius,  ny*a.radius))   # cell-space contact offsets
                push!(to_fracture, (j, -nx*b.radius, -ny*b.radius))
                fractured[i] = true; fractured[j] = true
                break
            else
                p = rvx*nx + rvy*ny                   # elastic, equal-mass reflection
                a.vx += p*nx; a.vy += p*ny
                b.vx -= p*nx; b.vy -= p*ny
                overlap = (rsum - dist)/2 + 0.01      # push the pair apart (no wrap)
                a.x = clamp(a.x - nx*overlap, -a.radius, g.width  + a.radius)
                a.y = clamp(a.y - ny*overlap, -a.radius, g.height + a.radius)
                b.x = clamp(b.x + nx*overlap, -b.radius, g.width  + b.radius)
                b.y = clamp(b.y + ny*overlap, -b.radius, g.height + b.radius)
            end
        end
    end
    for (idx, idx_dx, idx_dy) in sort(to_fracture; by = first, rev = true)
        idx <= length(g.asteroids) || continue
        fracture_asteroid!(g, idx, GB.Point2{Float64}(idx_dx, idx_dy))
    end
    return g
end

# Ship↔asteroid: alive && not invulnerable && Euclidean distance within the
# asteroid's radius ⇒ kill_ship!. Only the ship wraps. The asteroid is never
# mutated (it continues).
function _resolve_ship_collision!(g::GameState)
    s = g.ship
    (s.alive && s.invuln == 0) || return g
    for a in g.asteroids
        dist = hypot(a.x - s.x, a.y - s.y)
        if dist <= a.radius
            kill_ship!(g)
            return g
        end
    end
    return g
end

function _advance_projectiles!(g::GameState)
    for p in g.projectiles
        p.x += p.vx; p.y += p.vy; p.ttl -= 1
    end
    filter!(p -> p.ttl > 0 && 0 <= p.x <= g.width && 0 <= p.y <= g.height, g.projectiles)
    return g
end

# Each projectile fractures the first asteroid whose radius it's inside (Euclidean),
# then is consumed. Asteroids fracture one at a time; we re-read g.asteroids per
# projectile (fracture_asteroid! deleteat!s), and remove spent projectiles after.
function _resolve_projectile_collisions!(g::GameState)
    isempty(g.projectiles) && return g
    spent = falses(length(g.projectiles))
    for (pidx, p) in enumerate(g.projectiles)
        for idx in eachindex(g.asteroids)
            a = g.asteroids[idx]
            if hypot(a.x - p.x, a.y - p.y) <= a.radius
                fracture_asteroid!(g, idx, GB.Point2{Float64}(p.x - a.x, p.y - a.y))
                spent[pidx] = true
                break
            end
        end
    end
    deleteat!(g.projectiles, findall(spent))
    return g
end

# --- tick --------------------------------------------------------------------

# When the live count drops below the target, spawn ONE asteroid at a screen edge
# from a FIXED number of g.rng draws (no rejection loop) so the RNG stream stays
# predictable. `g.n_target` is the starting n_asteroids (set in new_game).
function _replenish_field!(g::GameState)
    length(g.asteroids) >= g.n_target && return g
    a = _spawn_asteroid(g.rng, g.width, g.height)   # x,y,v overwritten below; its draws are kept so the rng stream stays stable
    edge = rand(g.rng, 1:4); t = rand(g.rng)        # fixed 2 extra draws
    sp = hypot(a.vx, a.vy)                           # reuse the drawn speed, point it inward
    if     edge == 1; a.x = t*g.width;   a.y = 0.0;      a.vx = 0.0;  a.vy =  sp   # top  → down
    elseif edge == 2; a.x = t*g.width;   a.y = g.height; a.vx = 0.0;  a.vy = -sp   # bot  → up
    elseif edge == 3; a.x = 0.0;         a.y = t*g.height; a.vx =  sp; a.vy = 0.0  # left → right
    else              a.x = g.width;     a.y = t*g.height; a.vx = -sp; a.vy = 0.0  # right→ left
    end
    push!(g.asteroids, a)
    return g
end

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
    _handle_charge_and_fire!(g, in)
    _advance_projectiles!(g)
    _resolve_projectile_collisions!(g)   # bullets → asteroid
    _resolve_asteroid_collisions!(g)     # asteroid ↔ asteroid
    _resolve_ship_collision!(g)          # ship ↔ asteroid (death)
    _replenish_field!(g)                 # top up toward g.n_target (one per tick)
    g.tick_count += 1
    return g
end
