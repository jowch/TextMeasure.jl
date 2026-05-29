# Asteroid TUI — Interactive Controls & Collision Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `examples/asteroid_tui/` genuinely playable — twin-stick controls (WASD strafe + mouse aim), working asteroid/ship collisions with death+respawn, and a self-replenishing field — without regressing the engine showcase or the headless tests.

**Architecture:** Pure `tick!(state, input)` / `draw!(buf, state)` over a renderer-agnostic `CellBuffer` is preserved. Input becomes a stateful twin-stick layer: a held-key map (decayed by a pure `sweep_stale!`) + last-known cursor, folded into one `Input` per frame; the sim turns the cursor into a heading from the live ship position. Collisions use one wrap-aware signed-delta helper.

**Tech Stack:** Julia 1.12, Tachikoma 2.1.0 (terminal/events — internal API, `TK.`-qualified), Silhouettes (`voronoi_shatter`/`asteroid_polygon`), TextMeasure (`subprep`/`prepare`). Demo tests run via `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()'`.

**Spec:** `docs/superpowers/specs/2026-05-29-E-asteroid-tui-interactive-polish-design.md` (converged, 5 review rounds).

**Source of truth on terminal/geometry facts (verified on disk):**
- Convention: `φ=0` is up, clockwise; `dir(φ)=(sin φ, −cos φ)` (`game.jl:63`, `draw.jl:185`).
- Visual-space aim multiplies the **row** delta by ~2 (cell aspect height/width≈2): `atan(dx, −(dy·2))`.
- Tachikoma: `KeyEvent(key::Symbol, char::Char, action)`, actions `key_press/key_repeat/key_release`; `MouseEvent(x,y,button,action,…)`, buttons incl. `mouse_left/mouse_none`, actions `mouse_press/mouse_release/mouse_move/mouse_drag`; held keys arrive as `key_repeat`; raw `TK.poll_event` delivers all actions (no App-framework gating). All `TK.`-qualified (unexported).

---

## Cross-cutting constraint: Julia module compilation

`examples/asteroid_tui/src/AsteroidTUI.jl` compiles as one module on `using AsteroidTUI`. Removing `Input.thrust` simultaneously breaks `input.jl`, `game.jl` (`_advance_ship!`/`tick!`), `render_tachikoma.jl` (`_poll_input`), **and** three test files. There is no smaller compilable step for the contract switch, so **Task 2 is one atomic commit** that changes all of them together. Tasks 1, 4–9 are additive or localized and stay small.

## File structure

| File | Responsibility after this work |
|---|---|
| `src/input.jl` | `Input` value type (twin-stick fields + `aim` cursor) + `ScriptedInput` |
| `src/game.jl` | sim: movement, `aim_heading`, `_wrap_delta`, collisions (asteroid/ship), death/respawn, replenish, fracture frame-conversion, `tick!` |
| `src/render_tachikoma.jl` | `InputState` + pure `sweep_stale!`/`fold_input` + `_poll_input!` + `run_game` wiring + loop |
| `src/draw.jl` | `_draw_ship!` directional glyph; no leader/plume |
| `src/entities.jl` | unchanged (`Ship.φ` already exists) |
| `test/test_input.jl` | **new** — headless unit tests for `sweep_stale!`/`fold_input` (`aim_heading` tested in `test_game.jl`) |
| `test/runtests.jl` | add `"test_input.jl"` to the include tuple |
| `test/test_game.jl`, `test_gameloop.jl`, `test_draw.jl`, `test_fracture.jl` | updated field set + new behavior tests |
| `test/golden/frame60.{sha256,txt}` | regenerated (driven by the `draw.jl` visual changes: glyph + plume + leader cut) |
| `run.jl` | rewrite the player-facing controls banner (`:3-5`) for twin-stick |

---

## Task 0: Environment bootstrap (`[sources]`) + baseline green

This branch predates the #J `[sources]` fix and `Project.toml` has no `[sources]` table, so `Pkg.test()` currently fails at instantiate. Fix it before any TDD.

**Files:**
- Modify: `examples/asteroid_tui/Project.toml`

- [ ] **Step 1: Add a `[sources]` table** (after `[deps]`, before `[compat]`; mirrors the on-main demos):

```toml
# Local-path deps so a plain `Pkg.instantiate()` / `Pkg.test()` works without a
# manual `Pkg.develop` step (Julia 1.11+ [sources] feature).
[sources]
TextMeasure = { path = "../.." }
TextMeasureLayouts = { path = "../layouts" }
Silhouettes = { path = "../silhouettes" }
```

- [ ] **Step 2: Run the suite to establish a green baseline**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.instantiate(); Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: instantiate succeeds; **all existing tests pass** (this is the pre-change baseline). Confirm exit code is 0 (`echo $?`), do not trust a piped tail.

- [ ] **Step 3: Commit**

```bash
git add examples/asteroid_tui/Project.toml
git commit -m "build(#E): add [sources] so asteroid_tui Pkg.test() instantiates"
```

> `examples/asteroid_tui/Manifest.toml` stays **gitignored** — do not stage it.

---

## Task 1: Pure geometry helpers — `_wrap_delta` and `aim_heading`

Additive (no `Input` change yet), so the module stays compilable and these get clean unit tests first.

**Files:**
- Modify: `examples/asteroid_tui/src/game.jl` (insert after `_wrap`, ~line 28)
- Modify: `examples/asteroid_tui/test/test_game.jl` (append a testset)
- Modify: `examples/asteroid_tui/src/AsteroidTUI.jl` is **not** needed (tests import unexported names by `using AsteroidTUI: _wrap_delta, aim_heading`)

- [ ] **Step 1: Write the failing tests.** First **extend `test_game.jl`'s top `using` line** so the helpers are imported before any use anywhere in the file (later tasks call `aim_heading` from the top `tick! physics` testset — a bottom `using` would run too late):

```julia
using AsteroidTUI: new_game, tick!, Input, CHARGE_MAX, kill_ship!, ship_visible,
                   _wrap_delta, aim_heading
```

Then append these testsets (no separate `using`):

```julia
@testset "wrap-aware delta" begin
    W, H = 100.0, 40.0
    dx, dy, dist = _wrap_delta(98.0, 20.0, 2.0, 20.0, W, H)   # straddle right/left edge
    @test dx == 4.0 && dy == 0.0 && dist == 4.0               # short way is +4, not -96
    dx2, dy2, _ = _wrap_delta(10.0, 5.0, 13.0, 9.0, W, H)     # no wrap needed
    @test dx2 == 3.0 && dy2 == 4.0
    _, dyv, _ = _wrap_delta(0.0, 39.0, 0.0, 1.0, W, H)        # vertical wrap
    @test dyv == 2.0
    dxt, _, _ = _wrap_delta(0.0, 0.0, 50.0, 0.0, W, H)        # tie at size/2 ⇒ +50
    @test dxt == 50.0
end

@testset "aim_heading (visual space, up=0 clockwise)" begin
    # ship at (40,12); cells ~2:1 so the row delta is doubled.
    @test isapprox(aim_heading(40.0, 12.0, 40.0, 2.0),  0.0;  atol=1e-9)   # cursor above ⇒ up
    @test isapprox(aim_heading(40.0, 12.0, 60.0, 12.0), pi/2; atol=1e-9)   # right ⇒ +π/2
    @test isapprox(abs(aim_heading(40.0, 12.0, 40.0, 22.0)), pi; atol=1e-9) # below ⇒ ±π
    @test isapprox(aim_heading(40.0, 12.0, 20.0, 12.0), -pi/2; atol=1e-9)  # left ⇒ −π/2
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: FAIL/ERROR — `UndefVarError: _wrap_delta` (and `aim_heading`).

- [ ] **Step 3: Implement the helpers** — insert into `src/game.jl` after `_wrap(v, hi) = mod(v, hi)`:

```julia
# Toroidal signed delta from (ax,ay) to (bx,by) on a width×height torus. Each axis
# takes the minimum-magnitude candidate over {d, d-size, d+size}; at the |d|==size/2
# boundary the tie-break prefers the non-negative candidate so the normal is
# deterministic. Returns (dx, dy, dist=hypot(dx,dy)) — the VECTOR, so collision code
# derives normal/closing-speed/push-apart from one wrapped delta.
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
```

- [ ] **Step 4: Run to verify pass**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: PASS — both new testsets green; all prior tests still pass.

- [ ] **Step 5: Commit**

```bash
git add examples/asteroid_tui/src/game.jl examples/asteroid_tui/test/test_game.jl
git commit -m "feat(#E): wrap-aware delta + visual-space aim_heading helpers"
```

---

## Task 2: The twin-stick `Input` contract switch (atomic)

One commit: new `Input`, the stateful input layer, the strafe/aim movement, edge-triggered debug, spawn protection, and all consumers + tests updated together. The module is uncompilable between the `Input` change and the consumer updates, so do all edits, then run once.

**Files:**
- Modify: `src/input.jl` (Input struct + docstring)
- Modify: `src/game.jl` (constants, `GameState`, `new_game`, `_advance_ship!`, `tick!` debug edge)
- Modify: `src/render_tachikoma.jl` (`InputState`, `sweep_stale!`, `fold_input`, `_poll_input!`, `run_game` wiring, header/docstrings)
- Create: `test/test_input.jl`; Modify: `test/runtests.jl` (include it)
- Modify: `test/test_game.jl`, `test/test_gameloop.jl`, `test/test_draw.jl` (field set + new asserts)

- [ ] **Step 1: Write the failing/updated tests first.**

Create `test/test_input.jl` (headless unit tests for the pure helpers — note `aim` is the **cursor tuple**, not a φ):

```julia
# SPDX-License-Identifier: MIT
using AsteroidTUI: Input, sweep_stale!, fold_input, InputState, DECAY_WINDOW
using Test

@testset "input helpers (headless, no terminal)" begin
    @testset "sweep_stale! evicts only keys older than the window" begin
        held = Dict{Tuple{Symbol,Char},Int}((:char,'w')=>10, (:char,'a')=>4, (:char,'d')=>6)
        ret = sweep_stale!(held, 10, DECAY_WINDOW)   # DECAY_WINDOW == 5
        @test ret === held
        @test haskey(held, (:char,'w')) && haskey(held, (:char,'d'))
        @test !haskey(held, (:char,'a'))             # 10-4==6 > 5 ⇒ evicted
    end
    @testset "sweep_stale! boundary now-last==window is kept" begin
        held = Dict{Tuple{Symbol,Char},Int}((:char,'w')=>5)
        sweep_stale!(held, 10, 5); @test haskey(held, (:char,'w'))   # 5 not > 5
        sweep_stale!(held, 11, 5); @test !haskey(held, (:char,'w'))  # 6 > 5
    end
    @testset "fold_input maps held keys to strafe + Space-fire + quit" begin
        st = InputState(80, 24)
        st.held[(:char,'w')]=0; st.held[(:char,'d')]=0; st.held[(:char,' ')]=0
        inp = fold_input(st, 0)
        @test inp.up && inp.right && !inp.down && !inp.left
        @test inp.fire                       # Space ⇒ fire
        @test inp.aim === nothing            # no cursor yet
        st2 = InputState(80, 24); st2.held[(:left,'\0')]=0; st2.held[(:escape,'\0')]=0
        inp2 = fold_input(st2, 0); @test inp2.left && inp2.quit
    end
    @testset "fold_input fire from lmb_down" begin
        st = InputState(80, 24); st.lmb_down = true
        @test fold_input(st, 0).fire
    end
    @testset "fold_input emits the cursor as aim (raw, no φ math here)" begin
        st = InputState(80, 24); st.cursor = (60, 2)
        @test fold_input(st, 0).aim == (60.0, 2.0)     # passed through; φ is computed in the sim
    end
end
```

Register it in `test/runtests.jl` by adding `"test_input.jl"` **into the existing filename tuple** the file iterates (it does `for f in ("test_cellbuffer.jl", …, "test_golden.jl"); include(f); end` — not standalone `include()` calls). Put it first:

```julia
    for f in ("test_input.jl", "test_cellbuffer.jl", "test_cellbackend.jl", "test_prose.jl",
              "test_pack.jl", "test_game.jl", "test_fracture.jl", "test_draw.jl",
              "test_gameloop.jl", "test_golden.jl")
        include(f)
    end
```

Replace `test/test_game.jl`'s `tick! physics` testset (strafe + aim + edge-debug; keep the `respawn + invuln` testset; add `spawn protection`):

```julia
@testset "tick! physics" begin
    g = new_game(Xoshiro(42); width=120, height=40, n_asteroids=3)
    for _ in 1:5; tick!(g, Input(up=true)); end          # strafe imparts velocity, world wraps
    @test (g.ship.vx, g.ship.vy) != (0.0, 0.0)
    @test 0 <= g.ship.x <= g.width && 0 <= g.ship.y <= g.height
    gs = new_game(Xoshiro(42); width=120, height=40, n_asteroids=3); φ0 = gs.ship.φ
    tick!(gs, Input(left=true))
    @test gs.ship.vx != 0.0 && gs.ship.φ == φ0           # `left` STRAFES, does NOT turn
    ga = new_game(Xoshiro(42); width=120, height=40, n_asteroids=3)
    tick!(ga, Input(aim=(80.0, 5.0)))                    # aim is the cursor cell
    @test ga.ship.φ == aim_heading(ga.ship.x, ga.ship.y, 80.0, 5.0)
    φ1 = ga.ship.φ; tick!(ga, Input()); @test ga.ship.φ == φ1   # aim===nothing ⇒ φ held
    g2 = new_game(Xoshiro(1))
    for _ in 1:20; tick!(g2, Input(fire=true)); end
    @test g2.ship.charge == CHARGE_MAX
    tick!(g2, Input(fire=false)); @test g2.beam.active && g2.ship.charge == 0
    g4 = new_game(Xoshiro(2)); @test !g4.debug
    tick!(g4, Input(debug=true)); @test g4.debug         # edge: one press toggles on
    tick!(g4, Input(debug=true)); @test g4.debug         # held ⇒ NOT re-toggled (no strobe)
    tick!(g4, Input(debug=false)); tick!(g4, Input(debug=true)); @test !g4.debug  # next press toggles
end

@testset "spawn protection" begin
    g = new_game(Xoshiro(8))
    @test g.ship.invuln > 0 && ship_visible(g)           # fresh ship invulnerable AND visible at tick 0
end
```

Update `test/test_gameloop.jl`: the scripted vocabulary (lines ~35-42), the quit poll (line ~82), the entities-evolve subtest (lines ~90-102), and the `step_frame!` subtest (line ~109):

```julia
        # (lines 35-42) scripted vocabulary — strafe + aim, no thrust:
        script = Input[
            Input(left=true), Input(left=true), Input(up=true), Input(up=true),
            Input(right=true), Input(fire=true), Input(fire=true), Input(fire=true),
            Input(fire=false), Input(aim=(10.0, 3.0)), Input(debug=true), Input(),
            Input(down=true), Input(right=true), Input(fire=true), Input(fire=false),
        ]
        # (line ~82) quit subtest:
            poll    = frame -> (frame == 10 ? Input(quit=true) : Input(up=true)),
        # (lines ~90-102) entities-evolve: capture θ as a vector, harden the rotation assert:
        θ0 = [a.θ for a in g.asteroids]
            poll    = frame -> Input(up=true, right=true),
        @test (g.ship.x, g.ship.y) != (x0, y0)
        @test any(((a, t),) -> a.θ != t, zip(g.asteroids, θ0)) || !isempty(g.shards)
        # (line ~109) step_frame! subtest:
        step_frame!(g, cb, Input(up=true))
```

Update `test/test_draw.jl` line 8: `for _ in 1:10; tick!(g, Input(up=true)); end`.

- [ ] **Step 2: Run to verify failure** (compile error first — expected, the consumers aren't updated yet)

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: FAIL — `Input` has no field `thrust` / `UndefVarError: sweep_stale!`/`InputState`. (Once consumers land in Step 3, this turns green.)

- [ ] **Step 3a: Rewrite `src/input.jl`** (struct + docstring):

```julia
# SPDX-License-Identifier: MIT
"""
    Input(; up=false, down=false, left=false, right=false, fire=false,
            aim=nothing, debug=false, quit=false)

One tick's intent, decoupled from key encoding (twin-stick).
  * `up`/`down`/`left`/`right` are **strafe** flags — direct-velocity movement; `left`/`right`
    strafe, they do NOT turn.
  * `fire` held grows the charge; the first `fire=false` after `fire=true` launches.
  * `aim` is the **cursor cell** `(cx, cy)` or `nothing`. The sim turns it into a heading from the
    live ship position; `nothing` ⇒ leave φ unchanged (headless paths stay reproducible).
All fields keyword-only.
"""
Base.@kwdef struct Input
    up::Bool    = false
    down::Bool  = false
    left::Bool  = false
    right::Bool = false
    fire::Bool  = false
    aim::Union{Nothing,Tuple{Float64,Float64}} = nothing
    debug::Bool = false
    quit::Bool  = false
end
```

(Leave `ScriptedInput` and `next_input!` below it unchanged.)

- [ ] **Step 3b: `src/game.jl` constants + `GameState` + `new_game`.** Replace the `THRUST`/`TURN` constants:

```julia
const CHARGE_MAX = 5
const INVULN_TICKS = 120             # ~2s; (120÷10)%2==0 ⇒ ship_visible at tick 0
const MOVE_ACCEL = 0.18              # per-axis velocity added per held strafe key
const FRICTION   = 0.90              # light friction; crisp strafe stop
const SHATTER_CLOSING = 0.9          # asteroid closing-speed: ≥ ⇒ fracture, < ⇒ bounce
```

Add `prev_debug` and `n_target` to `GameState` (between `prev_fire` and `respawn_in`, and after `last_hit_glyphs` respectively — append `n_target` last to minimize churn):

```julia
mutable struct GameState
    width::Int; height::Int
    ship::Ship
    asteroids::Vector{Asteroid}
    shards::Vector{Shard}
    beam::Beam
    rng::Xoshiro
    tick_count::Int
    debug::Bool
    prev_fire::Bool
    prev_debug::Bool                 # edge-triggered debug toggle
    respawn_in::Int
    last_hit_glyphs::Vector{String}
    n_target::Int                    # replenish target (starting n_asteroids)
end
```

`new_game` — spawn invuln, `prev_debug`, and `n_target`:

```julia
function new_game(rng::Xoshiro = Xoshiro(0); width=120, height=40, n_asteroids=5)
    ship = Ship(width/2, height/2, 0.0, 0.0, 0.0, 0, true, INVULN_TICKS)
    asteroids = [_spawn_asteroid(rng, width, height) for _ in 1:n_asteroids]
    beam = Beam(false, 0.0, 0.0, 0.0, 0, 0)
    return GameState(width, height, ship, asteroids, Shard[], beam, rng, 0, false,
                     false, false, 0, String[], n_asteroids)
end
```

- [ ] **Step 3c: `src/game.jl` `_advance_ship!`** — strafe + aim (decoupled from φ):

```julia
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
```

- [ ] **Step 3d: `src/game.jl` `tick!`** — edge-triggered debug (collision/replenish calls come in later tasks; keep the existing `_resolve_collisions!` call for now):

```julia
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
```

- [ ] **Step 3e: `src/render_tachikoma.jl`** — replace the old `_poll_input` (lines ~137-182) with `InputState` + pure helpers + `_poll_input!`. Note `InputState` has **no** `cx/cy` (aim is ship-relative, computed in the sim), and `fold_input` passes the cursor through:

```julia
# --- input: stateful twin-stick over the real Tachikoma 2.1.0 API ---------------
# The PURE logic (sweep_stale!, fold_input) needs no terminal and is headless-tested;
# _poll_input! needs a live TK.poll_event and is the human tier-2/3 check.

"""
    InputState(width, height)

Per-`run_game` mutable input state threaded across frames: `held` is
`(key,char) => last-seen frame`, `cursor` the last mouse cell (`nothing` until the
first event), `lmb_down` the edge-derived left-button state.
"""
mutable struct InputState
    held::Dict{Tuple{Symbol,Char},Int}
    cursor::Union{Nothing,Tuple{Int,Int}}
    lmb_down::Bool
end
InputState(width::Integer, height::Integer) =
    InputState(Dict{Tuple{Symbol,Char},Int}(), nothing, false)

# Decay window in loop frames (~33ms each at sleep(1/30)). Must exceed the worst-case
# inter-repeat interval on the slowest non-kitty autorepeat; tuned at the terminal.
const DECAY_WINDOW = 5

"Evict held keys whose last-seen frame is older than `window` before `now`. Mutates & returns."
function sweep_stale!(held::Dict{Tuple{Symbol,Char},Int}, now::Int, window::Int)
    for (id, last) in held
        now - last > window && delete!(held, id)
    end
    return held
end

_char_held(held, chars) = any(id -> id[1] === :char && id[2] in chars, keys(held))

"""
    fold_input(state, now) -> Input

Pure: fold the held-key map + cursor + fire into one `Input`. WASD/arrows → strafe;
`aim` is the raw cursor cell (the sim computes φ from the live ship position);
`fire = lmb_down || Space-held`.
"""
function fold_input(state::InputState, now::Int)
    held = state.held
    up    = _char_held(held, ('w','W')) || haskey(held, (:up,'\0'))
    down  = _char_held(held, ('s','S')) || haskey(held, (:down,'\0'))
    left  = _char_held(held, ('a','A')) || haskey(held, (:left,'\0'))
    right = _char_held(held, ('d','D')) || haskey(held, (:right,'\0'))
    debug = _char_held(held, ('?',))
    quit  = _char_held(held, ('q','Q')) || haskey(held, (:escape,'\0')) || haskey(held, (:ctrl_c,'\0'))
    fire  = state.lmb_down || haskey(held, (:char,' '))
    aim   = state.cursor === nothing ? nothing :
            (Float64(state.cursor[1]), Float64(state.cursor[2]))
    return Input(up=up, down=down, left=left, right=right, fire=fire, aim=aim,
                 debug=debug, quit=quit)
end

"""
    _poll_input!(state, term, frame) -> Input

Drain events into `state`, decay stale keys, fold to one `Input`. Stamp `frame` on
the held map for `key_press`/`key_repeat`, delete on `key_release`; update cursor on
`mouse_move`/`mouse_drag`; `lmb_down` edge-derived from `mouse_left` press/drag→true,
release→false. Needs live `TK.poll_event` (tier-2/3).
"""
function _poll_input!(state::InputState, term, frame::Int)::Input
    while true
        evt = TK.poll_event(0.0005)
        evt === nothing && break
        if evt isa TK.KeyEvent
            id = (evt.key, evt.char)
            if evt.action == TK.key_press || evt.action == TK.key_repeat
                state.held[id] = frame
            elseif evt.action == TK.key_release
                delete!(state.held, id)
            end
        elseif evt isa TK.MouseEvent
            (evt.action == TK.mouse_move || evt.action == TK.mouse_drag) && (state.cursor = (evt.x, evt.y))
            if evt.button == TK.mouse_left
                evt.action in (TK.mouse_press, TK.mouse_drag) && (state.lmb_down = true)
                evt.action == TK.mouse_release && (state.lmb_down = false)
            end
        end
    end
    sweep_stale!(state.held, frame, DECAY_WINDOW)
    return fold_input(state, frame)
end
```

- [ ] **Step 3f: `src/render_tachikoma.jl` `run_game` interactive branch** — construct `InputState`, thread it, enable/restore `1003h`:

```julia
    if interactive
        term  = TK.Terminal(; size = (cols = width, rows = height))
        state = InputState(width, height)
        TK.enter_tui!(term)                 # alt-screen + raw mode + start_input!
        print(term.io, "\e[?1003h"); flush(term.io)   # any-motion mouse: enter_tui! enables 1000h+1002h+1006h (button-motion + SGR), not 1003h bare-motion
        try
            _run_loop!(g, cb, term; max_frames = max_frames,
                       poll = frame -> _poll_input!(state, term, frame),
                       pace = frame -> sleep(1 / 30))
        finally
            print(term.io, "\e[?1003l"); flush(term.io)   # restore: MOUSE_OFF omits 1003l
            TK.leave_tui!(term)
        end
```

(Leave the headless `else` branch — `poll = frame -> Input()` — unchanged.) Also rewrite the stale prose: the file header (`:1-17`), the `run_game` key-map docstring (`:96-97`) and interactive bullet (`:84-86`), to describe twin-stick + held-key decay (no "turn & thrust", no "momentary"). And rewrite **`run.jl`'s player-facing controls banner** (`run.jl:3-5`) — currently `# Controls: arrows / WASD turn & thrust, space charges (release to fire), …`:

```julia
# Controls: WASD strafe (the mouse aims the ship), LMB or space charges (release to fire),
#           ? toggles the debug overlay, q / Esc / Ctrl-C quit.
```

- [ ] **Step 4: Run to verify pass**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: PASS — `test_input.jl`, the rewritten `test_game.jl`/`test_gameloop.jl`/`test_draw.jl` green; **the golden testset is still GREEN** (no `tick!` or `_draw_ship!` change yet). Confirm exit 0 via `echo $?`.

- [ ] **Step 5: Commit**

```bash
git add examples/asteroid_tui/src/input.jl examples/asteroid_tui/src/game.jl \
        examples/asteroid_tui/src/render_tachikoma.jl examples/asteroid_tui/test/
git commit -m "feat(#E): twin-stick Input — WASD strafe + mouse-aim cursor + stateful poll, edge debug"
```

---

## Task 3: Spawn-velocity rescale (golden-safe)

Bump asteroid speeds so big hits can exceed `SHATTER_CLOSING`. **Rescale an existing `rand` draw — add/remove none** — so `_spawn_asteroid`'s polygon stream (drawn before the velocity rands) is untouched and the golden is unperturbed.

**Files:** Modify `src/game.jl` (`_spawn_asteroid`).

- [ ] **Step 1: Change only the vx/vy coefficient** `0.6 → 1.4`:

```julia
                    (rand(rng) - 0.5) * 1.4, (rand(rng) - 0.5) * 1.4,
```

(Max per-axis speed 0.3→0.7; diagonal head-on closing up to ~1.98 > 0.9, so shatters are reachable; typical closing stays below, so most pairs bounce.)

- [ ] **Step 2: Run — confirm the golden is STILL green** (proves the rescale didn't perturb polygons)

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: PASS including `golden showcase frame` (unchanged hash). If the golden fails here, a draw was added/removed by mistake — revert and rescale only the coefficient.

- [ ] **Step 3: Commit**

```bash
git add examples/asteroid_tui/src/game.jl
git commit -m "feat(#E): bump asteroid spawn velocity (rescale only; golden unperturbed)"
```

---

## Task 4: Fracture frame-conversion (`fracture_asteroid!`)

Honour the `impact` argument by converting the cell-space contact offset into the polygon's unit frame before `voronoi_shatter`. Everything below the conversion (pairing, `@assert`, `deleteat!`, `subprep`, scatter loop) stays byte-identical.

**Files:** Modify `src/game.jl` (`fracture_asteroid!`), `test/test_fracture.jl`.

- [ ] **Step 1: Write the failing off-centre test** — append to `test/test_fracture.jl` (and update the existing centre-hit caller, Step 3):

```julia
@testset "fracture: off-centre rim impact (frame conversion, no truncation)" begin
    g = new_game(Xoshiro(11); n_asteroids=1)
    a = g.asteroids[1]
    original = words(a.prep)
    nword = count(s -> s.kind === :word, a.prep.segments)
    requested = 2 + (nword >= 6 ? 2 : 0)
    impact = GB.Point2{Float64}(a.radius * 0.8, 0.0)     # cell-space offset near the rim
    fracture_asteroid!(g, 1, impact)
    @test isempty(g.asteroids)
    rebuilt = vcat((words(sh.prep) for sh in g.shards)...)
    @test rebuilt == original                            # lossless
    @test g.last_hit_glyphs == original
    @test length(g.shards) == requested                  # seeds landed INSIDE ⇒ no truncation
end
```

- [ ] **Step 2: Run — note both tests already pass (the impact arg is currently IGNORED)**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: **PASS** — this is *not* a red step. The current `fracture_asteroid!` discards `impact` and hardcodes `(0,0)` into `voronoi_shatter` (`game.jl:167`), so seeds land at the centroid and the full shard count is produced regardless of the passed offset. The off-centre test is a **regression guard**: it must stay green after Step 3, and (crucially) would FAIL if `impact` were honoured *without* the frame conversion (raw cell-space ≈7 seeds escape the ~±1 polygon → `voronoi_shatter` collapses to ~1 shard → `length==requested` fails). You can confirm it bites: after Step 3, temporarily drop the `/ a.radius` divisor and re-run — the off-centre `length(g.shards)==requested` assert fails — then restore it.

- [ ] **Step 3: Implement the conversion** — in `fracture_asteroid!` replace the `voronoi_shatter` call (`game.jl:167`) with the conversion + call, and update the docstring's frame contract:

```julia
    # Convert the CELL-space contact offset into the polygon's own (~±1) frame and
    # clamp into the polygon bbox so voronoi_shatter's seeds land inside the parent.
    xs = (p -> p[1]).(a.poly); ys = (p -> p[2]).(a.poly)
    fx = clamp(impact[1] / a.radius, minimum(xs), maximum(xs))
    fy = clamp(impact[2] / a.radius, minimum(ys), maximum(ys))
    polys = voronoi_shatter(a.poly, GB.Point2{Float64}(fx, fy); n_shards = n_shards)
```

Also update the existing centre-hit caller `test_fracture.jl:16` from `GB.Point2(a.x, a.y)` to `GB.Point2{Float64}(0.0, 0.0)` (cell-space zero offset — a centre hit). (Both the old `(a.x,a.y)` and the new `(0.0,0.0)` resolve to the polygon centroid under the conversion — `a.x,a.y` would clamp far into the bbox corner — so use the offset form to honour the new contract.)

- [ ] **Step 4: Run to verify pass**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: PASS — both `test_fracture.jl` testsets green (centre-hit lossless; off-centre lossless **and** `length(g.shards) == requested`).

- [ ] **Step 5: Commit**

```bash
git add examples/asteroid_tui/src/game.jl examples/asteroid_tui/test/test_fracture.jl
git commit -m "fix(#E): fracture_asteroid! honours impact via cell→polygon frame conversion"
```

---

## Task 5: Asteroid↔asteroid collisions (bounce / shatter)

**Files:** Modify `src/game.jl` (add `_resolve_asteroid_collisions!`, wire into `tick!`), `test/test_game.jl`.

- [ ] **Step 1: Write the failing tests** — append to `test/test_game.jl` (`_wrap_delta` is already in the top import from Task 1):

```julia
@testset "asteroid bounce separates overlapping pair (below threshold)" begin
    g = new_game(Xoshiro(3); width=120, height=40, n_asteroids=2)
    a, b = g.asteroids[1], g.asteroids[2]
    a.x=50.0; a.y=20.0; a.vx=0.0; a.vy=0.0
    b.x=50.0+(a.radius+b.radius)*0.5; b.y=20.0; b.vx=-0.05; b.vy=0.0   # low closing speed
    n0 = length(g.asteroids); _,_,d0 = _wrap_delta(a.x,a.y,b.x,b.y,g.width,g.height)
    @test d0 < a.radius + b.radius
    tick!(g, Input())
    @test length(g.asteroids) == n0                       # bounce, not fracture
    a2,b2 = g.asteroids[1], g.asteroids[2]; _,_,d1 = _wrap_delta(a2.x,a2.y,b2.x,b2.y,g.width,g.height)
    @test d1 >= d0                                         # pushed apart
    @test all(a -> 0 <= a.x <= g.width && 0 <= a.y <= g.height, g.asteroids)  # re-wrap holds in-bounds
end

@testset "high closing speed fractures both" begin
    g = new_game(Xoshiro(3); width=120, height=40, n_asteroids=2)
    a, b = g.asteroids[1], g.asteroids[2]
    a.x=60.0; a.y=20.0; a.vx=2.0; a.vy=0.0
    b.x=60.0+(a.radius+b.radius)*0.5; b.y=20.0; b.vx=-2.0; b.vy=0.0     # head-on, high closing
    shards0 = length(g.shards)
    tick!(g, Input())
    @test length(g.asteroids) == 0 && length(g.shards) > shards0
end
```

- [ ] **Step 2: Run to verify failure**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: FAIL — asteroids pass through (count unchanged where fracture expected; no push-apart).

- [ ] **Step 3: Implement `_resolve_asteroid_collisions!`** — insert in `src/game.jl` before `_resolve_collisions!`:

```julia
# Asteroid↔asteroid: bounce below the closing-speed threshold, fracture both above.
# Wrap-aware. Collect fracture pairs and apply them AFTER the sweep so deleteat!
# never invalidates a live index mid-iteration.
function _resolve_asteroid_collisions!(g::GameState)
    n = length(g.asteroids)
    n < 2 && return g
    to_fracture = Tuple{Int,Float64,Float64}[]
    fractured = falses(n)
    for i in 1:(n-1)
        fractured[i] && continue
        a = g.asteroids[i]
        for j in (i+1):n
            fractured[j] && continue
            b = g.asteroids[j]
            dx, dy, dist = _wrap_delta(a.x, a.y, b.x, b.y, g.width, g.height)
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
                overlap = (rsum - dist)/2 + 0.01      # push apart; re-wrap to stay in-bounds
                a.x = _wrap(a.x - nx*overlap, g.width); a.y = _wrap(a.y - ny*overlap, g.height)
                b.x = _wrap(b.x + nx*overlap, g.width); b.y = _wrap(b.y + ny*overlap, g.height)
            end
        end
    end
    for (idx, idx_dx, idx_dy) in sort(to_fracture; by = first, rev = true)
        idx <= length(g.asteroids) || continue
        fracture_asteroid!(g, idx, GB.Point2{Float64}(idx_dx, idx_dy))
    end
    return g
end
```

Wire into `tick!` after `_resolve_collisions!(g)`:

```julia
    _resolve_collisions!(g)              # beam → asteroid
    _resolve_asteroid_collisions!(g)     # asteroid ↔ asteroid
```

- [ ] **Step 4: Run to verify pass**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: PASS — bounce keeps count + separates + in-bounds; high-closing fractures both.

- [ ] **Step 5: Commit**

```bash
git add examples/asteroid_tui/src/game.jl examples/asteroid_tui/test/test_game.jl
git commit -m "feat(#E): asteroid↔asteroid wrap-aware bounce / fracture-both-on-hard-hit"
```

---

## Task 6: Ship↔asteroid death

**Files:** Modify `src/game.jl` (add `_resolve_ship_collision!`, wire into `tick!`), `test/test_game.jl`.

- [ ] **Step 1: Write the failing tests** — append to `test/test_game.jl`:

```julia
@testset "ship dies on asteroid contact" begin
    g = new_game(Xoshiro(3); width=120, height=40, n_asteroids=1)
    g.ship.invuln = 0                                   # drop spawn protection for the test
    a = g.asteroids[1]; a.vx=0.0; a.vy=0.0; a.x=g.ship.x; a.y=g.ship.y
    tick!(g, Input())
    @test !g.ship.alive && length(g.asteroids) == 1     # death; asteroid NOT removed
    for _ in 1:65; g.asteroids[1].x=0.0; g.asteroids[1].y=0.0; tick!(g, Input()); end
    @test g.ship.alive && g.ship.invuln > 0             # respawned, invulnerable
end

@testset "invulnerable ship survives contact" begin
    g = new_game(Xoshiro(3); n_asteroids=1)             # fresh ship is invuln (spawn protection)
    a = g.asteroids[1]; a.vx=0.0; a.vy=0.0; a.x=g.ship.x; a.y=g.ship.y
    tick!(g, Input())
    @test g.ship.alive
end
```

- [ ] **Step 2: Run to verify failure**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: FAIL — ship stays alive on contact (no ship-collision resolver yet).

- [ ] **Step 3: Implement `_resolve_ship_collision!`** — insert in `src/game.jl` before `_resolve_collisions!`:

```julia
# Ship↔asteroid: alive && not invulnerable && wrap-aware distance within the
# asteroid's radius ⇒ kill_ship!. The asteroid is never mutated (it continues).
function _resolve_ship_collision!(g::GameState)
    s = g.ship
    (s.alive && s.invuln == 0) || return g
    for a in g.asteroids
        _, _, dist = _wrap_delta(s.x, s.y, a.x, a.y, g.width, g.height)
        if dist <= a.radius
            kill_ship!(g)
            return g
        end
    end
    return g
end
```

Wire into `tick!` after `_resolve_asteroid_collisions!(g)`:

```julia
    _resolve_ship_collision!(g)          # ship ↔ asteroid (death)
```

- [ ] **Step 4: Run to verify pass**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: PASS — death on contact + asteroid survives + respawn invulnerable; invulnerable ship survives.

- [ ] **Step 5: Commit**

```bash
git add examples/asteroid_tui/src/game.jl examples/asteroid_tui/test/test_game.jl
git commit -m "feat(#E): wire ship↔asteroid death (kill_ship! on wrap-aware contact)"
```

---

## Task 7: Field replenish

**Files:** Modify `src/game.jl` (add `_replenish_field!`, wire into `tick!`), `test/test_game.jl`.

- [ ] **Step 1: Write the failing test** — append to `test/test_game.jl`:

```julia
@testset "field replenish restores count to N" begin
    N = 4
    g = new_game(Xoshiro(3); width=120, height=40, n_asteroids=N)
    g.ship.invuln = 1_000_000                  # keep ship alive; don't perturb the test
    empty!(g.asteroids)
    tick!(g, Input())
    @test length(g.asteroids) == 1             # one spawned per tick
    # _replenish_field! runs LAST in tick! (after _advance_asteroids!), so the just-spawned
    # asteroid is still exactly on its edge this tick — assert it here, before it drifts.
    a = g.asteroids[1]
    @test a.x == 0.0 || a.x == g.width || a.y == 0.0 || a.y == g.height
    for _ in 1:10; tick!(g, Input()); end
    @test length(g.asteroids) == N             # caps at N (g.n_target), never exceeds
end
```

- [ ] **Step 2: Run to verify failure**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: FAIL — count stays 0 after draining (no replenish).

- [ ] **Step 3: Implement `_replenish_field!`** — insert in `src/game.jl` before `tick!`, and wire it in:

```julia
# When the live count drops below the target, spawn ONE asteroid at a screen edge
# from a FIXED number of g.rng draws (no rejection loop) so the RNG stream stays
# predictable. `g.n_target` is the starting n_asteroids (set in new_game).
function _replenish_field!(g::GameState)
    length(g.asteroids) >= g.n_target && return g
    a = _spawn_asteroid(g.rng, g.width, g.height)
    edge = rand(g.rng, 1:4); t = rand(g.rng)        # fixed 2 extra draws
    if     edge == 1; a.x = t*g.width;  a.y = 0.0
    elseif edge == 2; a.x = t*g.width;  a.y = g.height
    elseif edge == 3; a.x = 0.0;        a.y = t*g.height
    else              a.x = g.width;    a.y = t*g.height
    end
    push!(g.asteroids, a)
    return g
end
```

Wire into `tick!` after `_resolve_ship_collision!(g)` (before `g.tick_count += 1`):

```julia
    _replenish_field!(g)                 # top up toward g.n_target (one per tick)
```

- [ ] **Step 4: Run to verify pass**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: PASS — count climbs one-per-tick to N, caps at N, edge-spawned.

- [ ] **Step 5: Commit**

```bash
git add examples/asteroid_tui/src/game.jl examples/asteroid_tui/test/test_game.jl
git commit -m "feat(#E): field replenish — edge-spawn one asteroid per tick toward n_target"
```

---

## Task 8: Directional ship glyph + beam-from-nose + leader cut

**Files:** Modify `src/draw.jl` (`_draw_ship!`, `draw!` body + docstring, comments), `src/game.jl` (`_handle_charge_and_beam!` beam origin), `test/test_draw.jl`.

- [ ] **Step 1: Write the failing φ=0 nose test** — append to `test/test_draw.jl`'s `draw!` testset (the determinism asserts at lines 18-21 stay):

```julia
    g.debug = false
    g.ship.alive = true; g.ship.invuln = 0; g.ship.charge = 0
    g.ship.x = 40.0; g.ship.y = 12.0
    sx = round(Int, g.ship.x); sy = round(Int, g.ship.y)
    # φ=0 ⇒ nose-up; the OLD wings (╱╲) and plume (┃) must be GONE.
    g.ship.φ = 0.0
    b0 = CellBuffer(g.height, g.width); draw!(b0, g)
    @test b0.chars[sy, sx]     == '▮'            # hull at centre
    @test b0.chars[sy - 1, sx] == '▲'            # nose one cell up
    @test b0.chars[sy, sx - 1] != '╱' && b0.chars[sy, sx + 1] != '╲'   # wings removed
    @test b0.chars[sy + 1, sx] != '┃'            # downward plume removed
    # φ=π/2 ⇒ facing RIGHT ⇒ nose '▶' one cell to the right (catches a CCW octant table)
    g.ship.φ = π/2
    b1 = CellBuffer(g.height, g.width); draw!(b1, g)
    @test b1.chars[sy, sx + 1] == '▶'
```

- [ ] **Step 2: Run to verify failure**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: FAIL — the current `_draw_ship!` draws swept wings `╱`/`╲` at `(sy,sx∓1)` and a `┃` plume at `(sy+1,sx)` (so the "removed" asserts fail) and never rotates the glyph (so the `φ=π/2 ⇒ '▶'` assert fails). The φ=0 nose `▲`/hull `▮` asserts already pass against the old glyph — that's expected; the wing/plume/octant asserts are the real red.

- [ ] **Step 3: Rewrite `_draw_ship!`** in `src/draw.jl` (replace lines ~165-181):

```julia
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
```

- [ ] **Step 4: Cut the targeting leader + clean comments + beam origin.**

In `draw!`'s body, delete the `# targeting leader:` comment and the whole `if ship_visible(g) && !isempty(g.asteroids) … _draw_leader! … end` block (lines ~215-223). Update the `draw!` docstring (drop "targeting leader" from the layer order). Update comments: `COL_BEAM` (line 8) `— beam + charge indicator`; the decoration-helpers comment (lines ~47-51) drop "leader"/"thrust plume".

In `src/game.jl` `_handle_charge_and_beam!` (line ~88), set the beam origin to the nose:

```julia
            g.beam = Beam(true, s.x + sin(s.φ), s.y - cos(s.φ), s.φ, 4 + 6 * s.charge, 6)
```

- [ ] **Step 5: Run to verify pass** (golden will now be STALE — that's expected; Task 9 regenerates it)

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: `test_draw.jl` PASS (φ=0 nose `▲`, hull `▮`, wings/plume gone, φ=π/2 nose `▶`, determinism holds); **`golden showcase frame` FAILS the hash compare** (the draw.jl visual changes — glyph, plume, leader — altered the rendered frame). Note it — do NOT regenerate yet; commit the code, regenerate in Task 9.

- [ ] **Step 6: Commit**

```bash
git add examples/asteroid_tui/src/draw.jl examples/asteroid_tui/src/game.jl examples/asteroid_tui/test/test_draw.jl
git commit -m "feat(#E): directional 8-way ship glyph, beam-from-nose, cut targeting leader"
```

---

## Task 9: Regenerate + visually verify the golden

The golden is a static `draw!` (no tick loop), so it is invariant to every `tick!` change; it changes here only from the **Task 8 `draw.jl` visual edits**: the 8-way ship glyph, the removed wings/plume, and the cut targeting-leader (the leader dotted into the golden frame because `_run_golden` has a visible ship + 2 asteroids). A larger-than-just-the-ship diff is expected and correct — no `tick!` change has leaked in.

**Files:** `test/golden/frame60.{sha256,txt}`, `test/test_golden.jl` (comment).

- [ ] **Step 1: Regenerate both golden files**

Run: `UPDATE_GOLDEN=1 julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"`
Expected: writes `frame60.sha256` + `frame60.txt`, re-reads, asserts in the same run → green.

- [ ] **Step 2: VISUALLY INSPECT the rendered frame** (a re-hash is NOT sign-off — project rule)

Open `examples/asteroid_tui/test/golden/frame60.txt` and confirm: (a) the φ=0 ship is a sensible **nose-up** form (`▲` above `▮`); (b) the downward thrust plume (`┃`/`┋`) is **gone**; (c) the dotted auto-targeting leader is **gone**; (d) the two text-mass blobs + stat callouts are still coherent. If anything looks wrong, fix `_draw_ship!`/`draw!` and re-regenerate.

- [ ] **Step 3: Update the stale comment** in `test/test_golden.jl` (block lines ~21-31): drop "with thrust plume"; add that this is a static `draw!` that regenerates only on a `_draw_ship!` change.

- [ ] **Step 4: Re-run WITHOUT the env var and independently confirm exit 0**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()'; echo "EXIT=$?"`
Expected: full suite green, `EXIT=0` (check the code directly, not a piped tail).

- [ ] **Step 5: Commit** (both golden files + comment; never the Manifest)

```bash
git status --short          # confirm Manifest.toml is NOT listed
git add examples/asteroid_tui/test/golden/frame60.sha256 \
        examples/asteroid_tui/test/golden/frame60.txt \
        examples/asteroid_tui/test/test_golden.jl
git commit -m "test(#E): regenerate golden for directional ship glyph (visually verified)"
```

---

## Task 10: Final verification + human tier-2/3 handoff

- [ ] **Step 1: Full suite, independently verified**

Run: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()'; echo "EXIT=$?"`
Expected: all testsets pass, `EXIT=0`.

- [ ] **Step 2: Record the human tier-2/3 checklist** (cannot be unit-tested; verify at a real terminal via `julia --project=examples/asteroid_tui run.jl`, on at least one kitty-class and one non-kitty terminal):
  - WASD feels responsive (crisp on kitty; acceptable past the first-press hitch elsewhere); ship glyph rotates to face the cursor.
  - LMB **and** Space both charge/fire; beam leaves the nose along the cursor direction.
  - Asteroids bounce; hard head-ons occasionally shatter into prose shards.
  - Ship dies on contact, respawns with the ~3 Hz invuln blink; field stays ~N.
  - `?` toggles the debug overlay once per press (no strobe); `q`/`Esc`/`Ctrl-C` quit; terminal is restored on exit.

- [ ] **Step 3:** This plan does **not** invoke finishing-a-development-branch (the orchestrator integrates / opens the PR). Leave the branch ready.

---

## Tuning knobs (magnitudes only — set at a live terminal; none change structure)

- `MOVE_ACCEL` (0.18) / `FRICTION` (0.90) — movement feel.
- `DECAY_WINDOW` (5 frames) — must exceed the worst-case inter-repeat interval (frames) on the slowest non-kitty autorepeat, else held keys stutter.
- `_spawn_asteroid` velocity coefficient (1.4) + `SHATTER_CLOSING` (0.9) — bounce-vs-shatter mix.
- Replenish cadence (one/tick) and `SHIP_OCTANT` glyphs.

## Notes for the implementer
- Asteroid-rotation coverage lives in `test_gameloop.jl`'s hardened "entities evolve" assert (`Xoshiro(42)`, n=3 — verified to have nonzero ω). The old fragile `Xoshiro(5)` index-1 rotation assert in `tick! physics` is removed by the Task 2 rewrite; don't reintroduce it.
- `a.radius > 0` always (`_spawn_asteroid`: `6.0 + 6.0*rand ≥ 6.0`), so `impact / a.radius` needs no divide-by-zero guard.
- Tachikoma's `poll_event`/`enter_tui!`/`leave_tui!` are unexported internals (`TK.`-qualified); the `[compat] Tachikoma = "2.1.0"` pin guards this coupling.
