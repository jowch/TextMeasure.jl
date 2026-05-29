# Asteroid TUI — interactive controls & collision polish — design

**Date:** 2026-05-29
**PR:** #26 — `[WIP] #E — Asteroid TUI demo (interactive polish in progress)`
**Branch:** `demos-E-asteroid-tui`
**Status:** design-converged (brainstorming dialogue 2026-05-29), ready for implementation plan

## Problem

PR #26's game *engine* (the `measure-once-layout-many` showcase: shape-packed prose,
Voronoi fracture into re-packed prose slices, pure `tick!`/`draw!` over a renderer-agnostic
`CellBuffer`, headless golden + smoke tests) works and is well-structured. The **interactive
gameplay layer** — explicitly labelled "tier-2/3, not unit-testable" in the PR and never
validated at a live terminal — is roughly half-finished. Two player-facing things are broken,
plus a cluster of latent bugs that surface the moment the demo is actually played:

1. **Controls don't work.** `_poll_input` treats turn/thrust as *momentary* (true only on the
   frame a keypress byte arrives) and discards every key-release event. Holding a key therefore
   relies on OS autorepeat — one press, a ~500 ms gap, then stuttery repeats. The ship glyph is
   a static nose-up `▲` that never reflects heading `φ`, so even a successful turn gives no
   visual feedback and the beam fires along an invisible direction.

2. **Collision is broken.** `_resolve_collisions!` handles **only** beam→asteroid.
   - **Ship↔asteroid collision does not exist.** `kill_ship!` is defined and exported but
     called *only* from a test — never from the game loop. The whole death / respawn /
     invulnerability / blink machinery is dead code in play; the ship flies through asteroids.
   - **Asteroid↔asteroid collision does not exist.** Asteroids drift on independent velocities
     and pass through each other. `draw!`'s "non-overlap by z-order + scene composition" claim
     holds only for the seed-pinned golden frame; in live play asteroid prose blobs overlap into
     an illegible pile.

Latent bugs found in the same sweep (fixed as part of this work):
- **Ignored impact point.** `_resolve_collisions!` computes the beam's impact offset and passes
  it to `fracture_asteroid!`, which then hardcodes `Point2(0.0, 0.0)` into `voronoi_shatter` —
  fractures always seed at the centroid, never where the hit landed.
- **No toroidal-wrap awareness.** Beam/asteroid distance uses raw `hypot`, blind to the screen
  wrap, so bodies straddling opposite edges never register. Any new collision check inherits
  this unless we add wrap-aware distance.
- **No spawn protection.** `new_game` starts the ship with `invuln = 0` dead-centre where
  asteroids can spawn; harmless today, instant death once ship collision is live.
- **Debug toggle not edge-triggered.** `g.debug = !g.debug` flips every frame the `?` key
  autorepeats, strobing the overlay instead of toggling it.
- **Field drains permanently.** Nothing replenishes asteroids; once all are shattered and shards
  TTL out the screen goes empty — a looping showcase needs replenish.

## Goal

Make the interactive demo genuinely playable at a real terminal — responsive twin-stick
controls, working collisions, a ship that can die and respawn, and a field that keeps the
showcase looping. The pure `tick!`/`draw!` split, the renderer-agnostic `CellBuffer`, and the
*engine* showcase (shape-pack → fracture → re-pack) are preserved; the headless tests keep
covering the loop end-to-end, though individual assertions are rewritten where they asserted the
wrong thing (see Refactoring posture).

## Refactoring posture

This demo was originally built **test-first-to-pass rather than to work**, then patched just enough
to boot. So the existing code and tests are **not** a faithful spec of intended behavior, and this
work has explicit operator latitude to **refactor things that don't make sense and do them
properly** rather than minimally patch around them. Concretely:

- A test that asserts a test-gaming artifact (e.g. `left` *turns* the ship; `draw!` non-overlap "by
  seed-pinned z-order composition") is **rewritten to assert real gameplay**, not preserved.
- Structures that exist only to pass a test or dodge a crash (the momentary-input model, the
  `_poll_input`/`_present` stubs) are replaced outright.
- The bar for removing something is: **verify it isn't load-bearing first** (grep call sites, read
  the test), then refactor — not reverence, but not recklessness either.

## Out of scope

Score/lives UI, sound, menus, multiple weapon types, shard re-fracture, difficulty curves.
This is interactive *polish* of an existing demo, not a ground-up rewrite.

## Control model — twin-stick

Movement and facing are **decoupled** (twin-stick): **WASD strafes**, **the mouse aims**.

### Movement (WASD → direct velocity)

W/A/S/D map to up/left/down/right **direct-velocity** movement (not thrust-along-heading).
Diagonals are normalised so combined keys don't move faster. Light friction smooths starts/stops
and bridges short input gaps. No heading coupling — A/D strafe, they do not turn.

The terminal key-hold problem (the root of "controls don't work") is solved with **one unified
mechanism**, not a per-terminal branch:

- A **held-keys map** where each held key carries a *last-seen tick*.
- The tick is stamped on **`key_press` AND `key_repeat`** (both autorepeat and the kitty protocol
  report a held key's continuations as `key_repeat`, never a fresh `key_press` — so stamping only
  on press would let the decay window evict a key mid-hold; the repeat refresh is essential).
- A key is evicted when **either** a `key_release` event arrives **or** it hasn't been refreshed
  within a short **decay window** (~4–6 ticks; tuned at the terminal).

Tachikoma **probes** for the kitty keyboard protocol in `enter_tui!` (`_detect_kitty_keyboard!`,
`terminal.jl:1302`) and enables `KITTY_FLAGS = 11` (which includes "report event types"; verified
`terminal.jl:16-21`) **only if the terminal answers the `CSI ? u` query**. On terminals that answer
(kitty, ghostty, WezTerm, foot, recent Konsole/Alacritty) `poll_event` then delivers real
**press / repeat / release** (raw `poll_event` has no action gating — `handle_all_key_actions` lives
only in the App/Model framework, which this demo does not use) — the release event evicts instantly
→ crisp hold-to-move,
instant stop; the decay timeout rarely fires. On terminals without the protocol (gnome-terminal/VTE,
xterm, macOS Terminal, most tmux) no release ever arrives, so the decay timeout does the eviction;
autorepeat (reclassified to `key_repeat`) refreshes the timestamp while held. **Same code path
either way** — the release event is just an optional early-exit; `t.kitty_keyboard` is *not*
branched on in the movement logic.

Tachikoma already maintains a module-global `_KEYS_DOWN` set (`events.jl:46-66`) that reclassifies
a repeated press to `key_repeat`; our held-key map sits **on top** of it. We still need our own map
because `_KEYS_DOWN` never times out (it clears only on a real release or `reset_key_state!`), so on
non-kitty terminals only the decay sweep can drop a key — we are not duplicating release tracking we
could get for free.

**Accepted limitation:** on non-kitty terminals the *OS-level* ~500 ms initial-autorepeat delay
(a keyboard/terminal setting, not a Tachikoma behavior) means the *first* press-then-hold has an
inherent hitch before continuous motion begins. No code can manufacture events the terminal
withheld; the decay window is tuned to keep everything *after* that first hitch smooth.

### Aim (mouse → heading `φ`)

The mouse cursor sets the ship's heading `φ` every frame (and thus the beam direction).
`enter_tui!` enables `MOUSE_ON = 1000h + 1002h + 1006h` (`terminal.jl:13`); `1002h` reports motion
only *while a button is held*, and there is no `1003h` (any-motion). So to get **bare cursor
motion** we print `\e[?1003h` to `term.io` after `enter_tui!` and `\e[?1003l` before `leave_tui!`
(`leave_tui!`'s `MOUSE_OFF` does not include `1003l`, so we must restore it ourselves). SGR
decoding (`1006h`) is already on and `1003h` bare-motion reports decode through it as a
`MouseEvent` with `button = mouse_none, action = mouse_move` (verified `events.jl:332-334`).

> Tachikoma's public `toggle_mouse!` is **not** usable here: it flips the whole `1000/1002/1006`
> set and has no `1003` control. And because the `Terminal` constructor sets `mouse_enabled = true`
> (`terminal.jl:77`) while `enter_tui!` only *prints* `MOUSE_ON` without updating that flag, the
> first `toggle_mouse!` would flip `true → false` and emit `MOUSE_OFF`, *disabling* tracking. Raw
> `1003h`/`1003l` to `term.io` is the deliberate, only mechanism in Tachikoma 2.1.0.

`φ` is computed in **visual space**: terminal cells are ~2:1, with **cell aspect = height/width ≈
2** applied as a **multiplier on the row delta** (`φ = atan(dx, -(dy·2))`) so the ship's nose
actually points at the cursor on screen, using the existing convention (up = 0, clockwise, matching
`vy -= cos φ` / `dirx = sin φ`; verified at all four cardinals — multiply, not divide, is the
correct direction). The same `φ` drives facing, the beam, and the rotated ship glyph; the only side
effect (slightly faster geometric turn per visual degree vertically) is imperceptible.

**Aim persists between mouse moves.** With `1003h`, mouse events arrive only *when the cursor
moves*; idle frames carry none. So the input layer remembers the **last-known cursor position**
and re-emits the corresponding `φ` every frame, holding the ship's facing steady until the next
move. This makes `_poll_input` stateful (see Renderer wiring).

### Fire (LMB **or** Space)

`fire = lmb_down || (Space present in the held-key map this frame)`. **Space is just another entry
in the unified held-key map** (set on press/repeat, evicted on release or decay-timeout); `lmb_down`
is the edge-derived mouse flag. Both feed the **same** charge state; the existing
hold-to-charge / release-to-launch edge (`prev_fire`) is preserved, and the beam launches along the
current mouse-aimed `φ`.

One consequence to accept: because Space rides the same decay eviction as movement, on a **non-kitty**
terminal (no release events) a Space *tap* stays "held" for the decay window (~4–6 ticks) before the
launch edge fires — so a tap yields charge ≈ the decay window (capped at `CHARGE_MAX = 5`) and
auto-launches, rather than a crisp charge-1 shot. On a **kitty** terminal the real release fires the
launch edge immediately, giving crisp tap-to-fire. This is the same press/release-vs-decay tradeoff
as movement, deliberately kept on one mechanism rather than special-casing Space; LMB (which always
has reliable press/release events) gives crisp firing on every terminal as the alternative.

### Ship glyph reflects heading

`_draw_ship!` rotates an 8-way directional glyph (and places a heading indicator) according
to `φ`, replacing today's static nose-up `▲`, so facing is always visible. The old downward
thrust plume — meaningless under decoupled strafe movement — is replaced by this heading-aware
indicator.

## Collision model

All collision geometry is **wrap-aware** via a single helper that returns the **toroidal signed
delta vector** `(dx, dy)` — each component chosen as the minimum-magnitude of `{d, d−size, d+size}`
on its axis — with `distance = hypot(dx, dy)`. Returning the *vector* (not just a scalar distance)
is required: the bounce needs the contact **normal** (the unit wrapped delta), the **closing speed**
(relative velocity projected onto that normal), and the **push-apart** direction — all derived from
the same wrapped delta, so an edge-straddling pair separates the short way around the torus, not
across the whole field. Reused by beam→asteroid, asteroid↔asteroid, and ship↔asteroid.

### Asteroid ↔ asteroid — "bounce, but big hits shatter"

On overlap (wrapped `distance` < sum of radii):
- **Below** a **closing-speed** threshold (closing speed = relative velocity · contact normal, not
  raw `‖relvel‖`): **elastic bounce** — reflect relative velocity along the contact normal **and**
  apply a positional push-apart along it so the pair separates and never sticks or overlaps into an
  illegible blob. The push-apart **re-applies `_wrap`** to both bodies (or runs before
  `_advance_asteroids!`'s wrap step) so the "all asteroids in `[0,W]×[0,H]`" invariant
  (`test_gameloop.jl:61`) still holds after a collision mutates position.
- **At/above** the threshold: **fracture both** asteroids via the existing `fracture_asteroid!`,
  seeded at the **actual contact point**. This fixes the ignored-impact-point bug — but honouring
  the `impact` argument is **not** a no-transform passthrough: `voronoi_shatter` places its seeds
  within `min(w,h)/4` of `impact` **in the polygon's own (unit-ish) frame** (`Silhouettes.jl:157-158`),
  whereas the contact point is in **cell space** (magnitude up to `a.radius` ≈ 6–12). So
  `fracture_asteroid!` must **convert the impact into the polygon frame** — divide the cell-space
  contact offset by `a.radius` and clamp it into the polygon bbox — before passing it to
  `voronoi_shatter`. (Today's hardcoded `(0,0)` "works" only because it happens to sit inside the
  polygon.)

  **Precise contract for `fracture_asteroid!(g, idx, impact)`:** `impact` is a **cell-space contact
  offset relative to the asteroid centre** (`px − a.x, py − a.y`; magnitude ≤ `a.radius`). The
  function converts it to the polygon's unit frame (`impact ./ a.radius`, clamped into the polygon
  bbox) before `voronoi_shatter`. The existing `test_fracture.jl:16` passes `GB.Point2(a.x, a.y)` —
  the asteroid's *absolute* position — which only "passes" today because the argument is ignored;
  under the contract that is a wrong-frame input and must change to a small offset (e.g.
  `Point2(0.0, 0.0)` for a centre hit), still asserting lossless glyph preservation.

Asteroid spawn velocities (`_spawn_asteroid`) are **bumped** so relative closing speeds can
actually exceed the shatter threshold (today's per-axis ±0.3 gives a max closing speed of only ≈
0.85 cells/tick on a diagonal head-on, and typical closing speeds are far lower). **The bump must
be a rescale of the existing `rand` draws — not added/removed draws — so the RNG draw order in
`_spawn_asteroid` is unchanged** (see "Determinism & the golden frame": the golden's polygons come
from that RNG stream, and a draw-order change would perturb them). Exact spawn-velocity range and
threshold value are **tuned empirically at the terminal**; the design fixes the *mechanism*, not
the magic numbers.

Shards remain non-colliding and TTL out (unchanged — out of scope to re-fracture).

### Ship ↔ asteroid — death / respawn

When the ship is alive and **not** invulnerable and its (wrap-aware) distance to any asteroid is
within that asteroid's radius, call `kill_ship!`. This activates the **existing** dormant
machinery: `_handle_respawn!` respawns after the timer with `INVULN_TICKS` of invulnerability,
and `ship_visible` blinks the ship at ~3 Hz while invulnerable. Two corollaries make it not feel
broken:
- **Spawn protection:** the ship gets initial invulnerability at `new_game` (not just on respawn),
  and asteroids are kept clear of / pushed off the centre spawn cell so the player can't die on
  frame 1.
- Death never mutates the colliding asteroid (it continues); only the ship reacts.

### Field replenish

When the live asteroid count drops below the target `N` (the `n_asteroids` the game started with),
**respawn one asteroid at a screen edge** (off-centre, away from the ship) so the showcase keeps
looping. Uses `g.rng` only, and derives the edge position from a **fixed number of `g.rng` draws**
(no rejection-sampling loop), so the post-replenish RNG stream stays predictable if a future
headless test ever pins it.

## Input struct & determinism

`Input` (`input.jl`) is extended to express the twin-stick scheme while keeping the **headless
scripted path deterministic**. The exact target struct:

```julia
Base.@kwdef struct Input
    up::Bool    = false
    down::Bool  = false
    left::Bool  = false                 # strafe (NOT turn — turning is gone)
    right::Bool = false                 # strafe
    fire::Bool  = false
    aim::Union{Nothing,Float64} = nothing   # absolute heading φ; nothing ⇒ leave φ unchanged
    debug::Bool = false
    quit::Bool  = false
end
```

- The old `thrust` field is removed; `up`/`down` are added; `left`/`right` are retained as
  identifiers but their **meaning changes from turn to strafe**.
- When `aim === nothing`, `tick!` leaves `φ` unchanged — so the Bool-only scripted golden inputs
  never depend on a mouse and stay fully reproducible. (All call sites use kwargs, so field order
  is not load-bearing.)
- `prev_debug` edge state for the debug toggle lives in **`GameState`** (`game.jl`, alongside the
  existing `prev_fire`), **not** in `entities.jl`. `debug` becomes **edge-triggered** in `tick!`
  (toggles once per press), fixing the strobe.

`ScriptedInput` is structurally unchanged (still a `Vector{Input}`) and the headless `run_game`
path (`poll = Input()`) is unaffected by the mouse field. Test updates for the renamed/repurposed
fields:
- **`test_gameloop.jl`** scripts and **`test_game.jl`** / **`test_draw.jl`** all construct
  `Input(thrust=…)` / `Input(left=…)` etc. — every such call is updated to the new field set.
- **A behavioral assertion changes, not just a name:** `test_game.jl:9` uses the removed
  `Input(thrust=true)` (renamed to the strafe set); `test_game.jl:13` does
  `tick!(g, Input(left=true)); @test g.ship.φ != φ0` — asserting `left` *turns*. Under strafe,
  `left` no longer changes `φ`, so line 13 is **replaced** with a strafe-velocity assertion
  (`left` changes `ship.vx`) plus a **new** assertion that `Input(aim=θ)` sets `ship.φ`.
  `test_game.jl:25`'s single-press debug assertion still passes under edge-triggering (one press
  toggles to `true`), but any *held*-debug test must account for `prev_debug`. Other tests' *intent*
  (loop runs, buffer valid every frame, entities evolve, in-bounds invariants, charge/respawn) is
  preserved.
- If any new symbol must be visible to tests (e.g. an `InputState` helper), add it to the
  `AsteroidTUI.jl` export list (tests import via `using AsteroidTUI: …`).

## Renderer wiring (`render_tachikoma.jl`)

Both the held-keys map and the last-known cursor position must survive across frames, so the
stateless `_poll_input(term) -> Input` becomes **stateful**: a small mutable `InputState` struct
(held-key→last-seen-tick map, last cursor `(x, y)` or `nothing`, and a `lmb_down::Bool` fire flag)
is created once per `run_game` and threaded through the poll callback (`poll = frame ->
_poll_input!(state, term, frame)`). The headless path keeps `poll = frame -> Input()` and never
constructs an `InputState`.

- `_poll_input!` each frame: (a) drains events, stamping the current tick on the held-key map for
  every `KeyEvent` with action `key_press` **or** `key_repeat`, and removing the key on
  `key_release`; (b) on a `MouseEvent`, updates the last-known cursor on **both** `mouse_move`
  (bare motion, `button = mouse_none`) and `mouse_drag` (motion with a button down), and updates
  the fire flag — SGR mouse has no per-frame "held" bit, so `lmb_down` is **edge-derived**: set
  `true` on a `mouse_left` `mouse_press`/`mouse_drag`, set `false` on a `mouse_left`
  `mouse_release`; (c) runs the decay sweep evicting stale held keys; (d) folds the held set +
  last-cursor-derived aim `φ` + `fire = lmb_down || space-held` into one `Input`. Aim is emitted
  from the remembered cursor every frame (held steady between moves); it stays `nothing` until the
  first mouse event.
- **The decay sweep is a pure, separately-tested helper** — e.g. `sweep_stale!(map, now, window)`
  — not buried inside `_poll_input!`. `_poll_input!` itself needs a live `TK.poll_event` and so is
  exercised only by the human tier-2/3 check, but the eviction/refresh *logic* is pure and gets a
  direct headless unit test (call `sweep_stale!` with a scripted map + tick). This is also the
  cleaner structure regardless of testing.
- `run_game`'s interactive branch prints `\e[?1003h` after `enter_tui!` and `\e[?1003l` in the
  `finally` before `leave_tui!`, so any-motion mouse tracking is enabled and always restored.
- The stale prose must all be rewritten for the twin-stick + held-key-decay model: the
  `run_game` / `_poll_input` docstrings (`render_tachikoma.jl:96-97, 141-153`, "arrows / wasd turn &
  thrust", momentary/ignored-release), the **file-header comment** (`render_tachikoma.jl:1-17`,
  which also describes the momentary-capture stubs), and the `poll = frame -> _poll_input(term)`
  callback wiring (`render_tachikoma.jl:113`) which becomes `_poll_input!(state, term, frame)`.
- The headless branch is untouched (`Input()` each frame, no mouse, no pacing) — the smoke test
  continues to drive the real `run_game` over an `IOBuffer`.

## Testing strategy

**Headless (CI, automated):**
- Update `test_gameloop.jl` / `test_game.jl` / `test_draw.jl` to the new `Input` field set; keep
  the existing invariants (loop completes, every frame a valid buffer, `tick_count` advances,
  in-bounds). Replace `test_game.jl:13`'s `left`-turns-the-ship assertion with a strafe-velocity
  assertion + a new aim-sets-`φ` assertion (see Input struct section).
- Add headless unit tests for the new pure logic. Most are driven through `tick!` with scripted
  `Input` (no terminal): aim sets `φ` when provided and leaves it untouched when `nothing`; asteroid
  bounce separates an overlapping pair below threshold; high closing speed fractures both and
  increases shard count; ship dies on asteroid contact and is invulnerable on (re)spawn; replenish
  restores the count to `N` when it drops below. Two are **direct unit tests of pure helpers**, NOT
  through `tick!`: the held-key **`sweep_stale!`** decay/refresh logic (the rest of `_poll_input!`
  needs a live `TK.poll_event`, so only this extracted helper is headless-testable), and the
  wrap-aware **delta helper** (an edge-straddling pair returns the short-way signed delta).
- **Two existing assertions are fragile under live collisions and must be hardened**, not just
  renamed: `test_gameloop.jl:96-101` asserts `g.asteroids[1].θ` rotated after 30 ticks — if
  asteroid 1 shatters (`deleteat!`) or replenish reorders the vector, index 1 is a different body;
  assert "*some* asteroid rotated" or pin that scenario's velocities low enough that no
  shatter/replenish fires. (`test_gameloop.jl:61`'s in-bounds invariant is covered by the
  push-apart re-wrap above.)

**Determinism & the golden frame.** `frame60` is **not** a 60-tick evolution: `_run_golden`
(`test_golden.jl:32-41`) builds `new_game(Xoshiro(38))`, then **overrides** every asteroid's
position/velocity/ω/radius/`prep` and the ship's pose, and calls `draw!` **once** with **no tick
loop**. The only state that survives from the RNG stream is the asteroid **polygons**. Therefore:
- The golden is **invariant to every `tick!` change** in this work (movement, collisions, death,
  replenish, edge-debug) — none of that logic runs in the golden.
- It regenerates for exactly **one** reason: the `_draw_ship!` rewrite (8-way glyph + plume
  removal). The golden's ship is pinned at `φ = 0`, so the regenerated glyph must render a sensible
  **nose-up** form there.
- The spawn-velocity bump is constrained to a **rescale of existing `rand` draws** (no added/removed
  draws); since `_spawn_asteroid` draws the polygon *before* the velocity rands (`game.jl:31` vs
  `:36`), this leaves the polygons — and thus the golden — unperturbed. If the bump ever changes
  the draw count/order, the golden changes for that reason too, which must be called out.

`test/golden/frame60.{sha256,txt}` is regenerated (`UPDATE_GOLDEN=1`). Per project rule
([[feedback-view-rendered-artifacts]]) the regenerated `frame60.txt` is **visually inspected** to
confirm the new ship glyph reads correctly and the scene stays coherent — a re-hash alone is not
sign-off. The merge-gating suite is **run independently** ([[feedback-independently-run-merge-checks]]),
not trusted on report.

**Live terminal (human tier-2/3, not unit-testable):**
- WASD feels responsive (crisp on a kitty-class terminal; acceptable past the initial hitch
  otherwise); ship nose tracks the cursor; LMB and Space both charge/fire; asteroids bounce and
  occasionally shatter on hard hits; ship dies on contact, respawns with the blink; field keeps
  ~N asteroids. Tested on at least one kitty-class and one non-kitty terminal.

## Files touched

| File | Change |
|---|---|
| `src/input.jl` | `Input` fields → `up/down/left/right` strafe + optional `aim::Union{Nothing,Float64}`; remove `thrust`; docstring |
| `src/game.jl` | `GameState` gains `prev_debug` (edge state, beside `prev_fire`); direct-velocity movement; aim→`φ`; wrap-aware **delta** helper; asteroid bounce/shatter; ship↔asteroid death; spawn protection; replenish; honour `impact` (cell→polygon frame conversion) in `fracture_asteroid!`; edge-triggered debug; spawn-velocity rescale |
| `src/entities.jl` | none expected (`Ship.φ` already exists; `prev_debug` lives in `GameState`) |
| `src/draw.jl` | 8-way rotating ship glyph + heading indicator; plume removed; update stale comments (`draw.jl:8` `COL_BEAM` "thrust plume", `draw.jl:48-51, 166`) |
| `src/render_tachikoma.jl` | stateful `InputState` (held-key map + last cursor + `lmb_down`) threaded through `poll`; pure `sweep_stale!` decay helper; `_poll_input!` rewrite (stamp on press/repeat, mouse aim + edge-derived button); `1003h/1003l` enable/restore in `run_game`; rewrite stale prose (`:1-17` header, `:96-97` & `:141-153` docstrings, `:113` poll wiring) |
| `src/AsteroidTUI.jl` | export any new test-visible symbol (e.g. `InputState` / `sweep_stale!`) if tests need it |
| `run.jl` | rewrite the controls banner (`run.jl:4-5`) for twin-stick |
| `test/test_gameloop.jl`, `test/test_game.jl`, `test/test_draw.jl` | new `Input` field set; replace `test_game.jl:13` turn-assertion; harden `test_gameloop.jl:96-101` rotation-identity; new headless collision/death/replenish tests |
| `test/test_fracture.jl` | callers pass `impact` as a cell-space offset (new frame contract); keep lossless-glyph-preservation assertions |
| `test/golden/frame60.{sha256,txt}` | regenerated (driven by the `_draw_ship!` change only) + visually verified |

## Open tuning knobs (resolved at implementation, not design)

- Movement speed and friction coefficient.
- Decay-window length (ticks).
- Visual-space row-scale factor for aim (cell aspect ≈ 2, refined by eye; applied as a multiplier).
- Asteroid spawn-velocity range and the bounce-vs-shatter **closing-speed** threshold.
- Replenish target `N` (defaults to the starting `n_asteroids`).

All five are magnitudes only — none change the structure above (e.g. the spawn-velocity bump is a
rescale of existing draws, not a new distribution), so each is safe to tune at the terminal.
