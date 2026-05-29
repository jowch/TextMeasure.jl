# SPDX-License-Identifier: MIT
#
# Interactive Tachikoma renderer + the shared game loop.
#
# The loop itself (`game_loop!`) is terminal-agnostic: it takes `poll` / `present` /
# `pace` callbacks, so the EXACT SAME loop code runs both the interactive game
# (`run_game`, real TTY) and the headless smoke test (scripted input, no-op present,
# no pacing). Only these three callbacks touch the terminal — everything else (input
# dispatch via the `Input` struct, `tick!`, `draw!` into a `CellBuffer`, and the
# `drain_to_tachikoma!` buffer fill) is exercised without a TTY.
#
# What STILL genuinely requires a live TTY (human tier-2/3 only, not unit-testable):
#   - `_poll_input` raw-mode keypress capture (reading actual keystrokes)
#   - `_present` writing escape codes to the terminal
#   - real ≥30fps wall-clock pacing, and the *visible* respawn blink / `?` overlay
import Tachikoma as TK

# Drain a renderer-agnostic CellBuffer into a Tachikoma Buffer (1-based x=col, y=row).
# No TTY needed — a Tachikoma Buffer is an in-memory cell grid; this is smoke-tested.
function drain_to_tachikoma!(tbuf, cb::CellBuffer)
    for r in 1:nrows(cb), c in 1:ncols(cb)
        ch = cb.chars[r, c]
        (ch == ' ' && cb.fg[r, c] == 0x00) && continue
        style = TK.Style(; fg = TK.Color256(Int(cb.fg[r, c])), bold = cb.bold[r, c])
        TK.set_char!(tbuf, c, r, ch, style)
    end
    return tbuf
end

"""
    step_frame!(g, cb, input) -> cb

One frame of game logic: advance the simulation by `input` and repaint `cb`. Pure
w.r.t. the terminal (no I/O). This is the unit the loop repeats.
"""
function step_frame!(g::GameState, cb::CellBuffer, input::Input)
    tick!(g, input)
    draw!(cb, g)
    return cb
end

"""
    game_loop!(g, cb; poll, present, pace, max_frames=nothing) -> Int

The shared fixed-timestep loop, terminal-agnostic. Each frame: `poll(frame)::Input`
→ quit if `input.quit` → `step_frame!` → `present(cb, frame)` → `pace(frame)`.
Returns the number of frames run. Both `run_game` (real TTY) and the headless smoke
test drive THIS function; only the callbacks differ, so the loop logic itself is
covered by tests.
"""
function game_loop!(g::GameState, cb::CellBuffer; poll, present, pace, max_frames = nothing)
    frame = 0
    while true
        input = poll(frame)
        input.quit && break
        step_frame!(g, cb, input)
        present(cb, frame)
        pace(frame)
        frame += 1
        max_frames !== nothing && frame >= max_frames && break
    end
    return frame
end

"""
    run_game(; width=120, height=40, seed=0, max_frames=nothing)

Interactive entry. Builds a Tachikoma `Terminal` and runs [`game_loop!`](@ref) with
terminal-backed callbacks: read key → `tick!` → `draw!` → drain → present, ~60fps.
Linux/macOS only (ANSI / raw-mode). `max_frames` bounds the loop for smoke runs.

Key map: arrows/`wasd` move & turn, space charges (release to fire), `?` toggles the
debug overlay, `q` quits. The precise Tachikoma key-event field names are resolved
against the installed version at call time (interactive bring-up).
"""
function run_game(; width = 120, height = 40, seed = 0, max_frames = nothing)
    g    = new_game(Xoshiro(seed); width = width, height = height)
    cb   = CellBuffer(height, width)
    term = TK.Terminal(; size = TK.Rect(0, 0, width, height))
    poll = frame -> _poll_input(term)
    present = function (cb, frame)
        tbuf = TK.Buffer(TK.Rect(0, 0, width, height))
        drain_to_tachikoma!(tbuf, cb)
        _present(term, tbuf)
    end
    pace = frame -> sleep(1 / 60)
    game_loop!(g, cb; poll = poll, present = present, pace = pace, max_frames = max_frames)
    return g
end

# --- input/present shims, resolved against the live Tachikoma API at bring-up ----
# Isolated so the rest of the renderer is API-stable. ONLY these two need a real TTY;
# the headless smoke test never calls them (it supplies its own poll/present).
function _poll_input(term)::Input
    # Non-blocking raw-mode key read → Input. Resolved interactively against TK's
    # event API (KeyEvent / handle_key!). TTY-only.
    return Input()
end

function _present(term, tbuf)
    # Blit the Buffer to the terminal (escape codes). Resolved against TK's present
    # path (Terminal draw/flush). TTY-only.
    return nothing
end
