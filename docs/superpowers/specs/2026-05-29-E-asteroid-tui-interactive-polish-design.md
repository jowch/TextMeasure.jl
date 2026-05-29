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
showcase looping — **without regressing the engine showcase or the headless test guarantees.**
The pure `tick!`/`draw!` split and the renderer-agnostic `CellBuffer` are preserved; all changes
live in `game.jl`, `entities.jl`, `input.jl`, `render_tachikoma.jl`, and `draw.jl`.

## Out of scope

Score/lives UI, sound, menus, multiple weapon types, shard re-fracture, difficulty curves.
This is interactive *polish* of an existing demo, not a new game.

## Control model — twin-stick

Movement and facing are **decoupled** (twin-stick): **WASD strafes**, **the mouse aims**.

### Movement (WASD → direct velocity)

W/A/S/D map to up/left/down/right **direct-velocity** movement (not thrust-along-heading).
Diagonals are normalised so combined keys don't move faster. Light friction smooths starts/stops
and bridges short input gaps. No heading coupling — A/D strafe, they do not turn.

The terminal key-hold problem (the root of "controls don't work") is solved with **one unified
mechanism**, not a per-terminal branch:

- A **held-keys set** where each key carries a *last-seen tick*.
- A key is evicted when **either** a `key_release` event arrives **or** it hasn't been refreshed
  within a short **decay window** (~4–6 ticks; tuned at the terminal).

Tachikoma enables the **kitty keyboard protocol** at startup (`KITTY_FLAGS = 11`, which includes
"report event types"), so on capable terminals (kitty, ghostty, WezTerm, foot, recent
Konsole/Alacritty) `poll_event` delivers real **press / repeat / release** — the release event
evicts instantly → crisp hold-to-move, instant stop; the decay timeout rarely fires. On terminals
without the protocol (gnome-terminal/VTE, xterm, macOS Terminal, most tmux) no release ever
arrives, so the decay timeout does the eviction; autorepeat refreshes the timestamp while held.
**Same code path either way** — the release event is just an optional early-exit; `t.kitty_keyboard`
is *not* branched on in the movement logic.

**Accepted limitation:** on non-kitty terminals the OS's ~500 ms initial-autorepeat delay means
the *first* press-then-hold has an inherent hitch before continuous motion begins. No code can
manufacture events the terminal withheld; the decay window is tuned to keep everything *after*
that first hitch smooth.

### Aim (mouse → heading `φ`)

The mouse cursor sets the ship's heading `φ` every frame (and thus the beam direction).
`enter_tui!` only enables mouse mode `1002h` (motion reported *while a button is held*), so to get
**bare cursor motion** we print `\e[?1003h` (any-motion tracking) to `term.io` after `enter_tui!`
and `\e[?1003l` before `leave_tui!`. SGR decoding (`1006h`) is already on.

`φ` is computed in **visual space**: terminal cells are ~2:1 (taller than wide), so the row delta
is scaled (×~2) before `atan` so the ship's nose actually points at the cursor on screen, using
the existing convention (up = 0, clockwise, matching `vy -= cos φ` / `dirx = sin φ`). The same `φ`
drives facing, the beam, and the rotated ship glyph; the only side effect (slightly faster
geometric turn per visual degree vertically) is imperceptible.

**Aim persists between mouse moves.** With `1003h`, mouse events arrive only *when the cursor
moves*; idle frames carry none. So the input layer remembers the **last-known cursor position**
and re-emits the corresponding `φ` every frame, holding the ship's facing steady until the next
move. This makes `_poll_input` stateful (see Renderer wiring).

### Fire (LMB **or** Space)

`fire = (left mouse button held) OR (Space held)`. Both feed the **same** charge state; the
existing hold-to-charge / release-to-launch edge (`prev_fire`) is preserved unchanged. A quick
click or tap = charge 1 + immediate launch; holding either source grows charge to `CHARGE_MAX`.
The beam launches along the current mouse-aimed `φ`.

### Ship glyph reflects heading

`_draw_ship!` rotates an 8-way directional glyph (and places a heading indicator) according
to `φ`, replacing today's static nose-up `▲`, so facing is always visible. The old downward
thrust plume — meaningless under decoupled strafe movement — is replaced by this heading-aware
indicator.

## Collision model

All collision distance is **wrap-aware**: a single helper computes the toroidal minimum distance
(min over ±width / ±height) and is reused by beam→asteroid, asteroid↔asteroid, and ship↔asteroid.

### Asteroid ↔ asteroid — "bounce, but big hits shatter"

On overlap (wrap-aware sum-of-radii test):
- **Below** a relative-speed threshold: **elastic bounce** — resolve relative velocity along the
  contact normal **and** apply a positional push-apart so the pair separates and never sticks or
  overlaps into an illegible blob.
- **At/above** the threshold: **fracture both** asteroids via the existing `fracture_asteroid!`,
  seeded at the **actual contact point** (this is where the ignored-impact-point bug is fixed —
  `fracture_asteroid!` is changed to honour its `impact` argument and pass it to
  `voronoi_shatter`).

Asteroid spawn velocities (`_spawn_asteroid`) are **bumped** so relative closing speeds can
actually exceed the shatter threshold (today's ±0.3 cells/tick tops out too low to ever trigger a
"big hit"). Exact spawn-velocity range and the threshold value are **tuned empirically at the
terminal**; the design fixes the *mechanism*, not the magic numbers.

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
looping. Uses `g.rng` only, preserving determinism.

## Input struct & determinism

`Input` (`input.jl`) is extended to express the twin-stick scheme while keeping the **headless
scripted path deterministic**:
- Movement booleans become `up` / `down` / `left` / `right` (strafe), replacing the old
  `thrust` / `left` / `right` turn semantics.
- Mouse aim is an **optional** field (e.g. `aim::Union{Nothing,Float64}` heading, defaulting to
  `nothing`). When `nothing`, `tick!` leaves `φ` unchanged — so the Bool-only scripted golden
  inputs never depend on a mouse and stay fully reproducible.
- `fire` / `debug` / `quit` are unchanged in meaning; `debug` becomes **edge-triggered** in
  `tick!` (toggles once per press via a `prev_debug` edge, mirroring `prev_fire`), fixing the
  strobe.

`ScriptedInput` and the headless `run_game` path (`poll = Input()`) are unaffected by the mouse
field. The scripted-input tests in `test_gameloop.jl` and `test_game.jl` are updated to the new
movement field names; their *intent* (loop runs, buffer valid every frame, entities evolve,
in-bounds invariants, charge/respawn behaviour) is preserved.

## Renderer wiring (`render_tachikoma.jl`)

Both the held-keys set and the last-known cursor position must survive across frames, so the
stateless `_poll_input(term) -> Input` becomes **stateful**: a small mutable `InputState` struct
(held-key→last-seen-tick map, last cursor `(x, y)` or `nothing`, current fire-source flags) is
created once per `run_game` and threaded through the poll callback (`poll = frame ->
_poll_input!(state, term, frame)`). The headless path keeps `poll = frame -> Input()` and never
constructs an `InputState`.

- `_poll_input!` each frame: (a) drains events, updating the held-key map from `KeyEvent`
  press/release and stamping the current tick; (b) on `MouseEvent`, updates last-known cursor and
  mouse-button fire state; (c) runs the decay sweep evicting stale held keys; (d) folds the held
  set + last-cursor-derived aim `φ` + fire source into one `Input`. Aim is emitted from the
  remembered cursor every frame (held steady between moves); it stays `nothing` until the first
  mouse event.
- `run_game`'s interactive branch prints `\e[?1003h` after `enter_tui!` and `\e[?1003l` in the
  `finally` before `leave_tui!`, so any-motion mouse tracking is enabled and always restored.
- The headless branch is untouched (`Input()` each frame, no mouse, no pacing) — the smoke test
  continues to drive the real `run_game` over an `IOBuffer`.

## Testing strategy

**Headless (CI, automated):**
- Update `test_gameloop.jl` / `test_game.jl` to the new `Input` field names; keep the existing
  invariants (loop completes, every frame a valid buffer, `tick_count` advances, in-bounds).
- Add headless unit tests for the new pure logic, all driven through `tick!` with scripted
  `Input` (no terminal): held-key eviction by decay timeout; aim sets `φ` when provided and
  leaves it untouched when `nothing`; wrap-aware distance helper (edge-straddling pair registers);
  asteroid bounce separates an overlapping pair below threshold; high closing speed fractures both
  and increases shard count; ship dies on asteroid contact and is invulnerable on (re)spawn;
  replenish restores the count to `N` when it drops below.
- **Golden regeneration:** the new collision/death/velocity logic changes `tick!`'s 60-tick
  evolution, so `test/golden/frame60.sha256` is regenerated. Per project rule
  ([[feedback-view-rendered-artifacts]]) the regenerated `test/golden/frame60.txt` is
  **visually inspected** to confirm it still reads as a coherent scene — a re-hash alone is not
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
| `src/input.jl` | `Input` fields → `up/down/left/right` strafe + optional `aim`; docs |
| `src/entities.jl` | (if needed) `prev_debug` edge state; no structural ship/asteroid changes expected |
| `src/game.jl` | direct-velocity movement; aim→`φ`; wrap-aware distance; asteroid bounce/shatter; ship↔asteroid death; spawn protection; replenish; honour `impact` in `fracture_asteroid!`; edge-triggered debug; bumped spawn velocities |
| `src/draw.jl` | 8-way rotating ship glyph + heading-aware indicator |
| `src/render_tachikoma.jl` | stateful `InputState` (held-key map + last cursor + fire source) threaded through `poll`; `_poll_input!` rewrite (held-key decay sweep, mouse aim + button read); `1003h/1003l` enable/restore in `run_game` |
| `test/test_gameloop.jl`, `test/test_game.jl` | new `Input` field names; new headless collision/death/replenish/input tests |
| `test/golden/frame60.{sha256,txt}` | regenerated + visually verified |

## Open tuning knobs (resolved at implementation, not design)

- Movement speed and friction coefficient.
- Decay-window length (ticks).
- Visual-space row-scale factor for aim (~2, refined by eye).
- Asteroid spawn-velocity range and the bounce-vs-shatter relative-speed threshold.
- Replenish target `N` (defaults to the starting `n_asteroids`).
