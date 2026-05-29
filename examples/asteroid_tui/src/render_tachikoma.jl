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
#
# Every write is guarded by `TK.in_bounds`: a CellBuffer may be larger than the
# Tachikoma buffer it's drained into (e.g. a resized terminal), so out-of-range cells
# are skipped rather than throwing. Without this guard `set_char!` raises a
# `BoundsError` and crashes the render loop — caught by the headless game-loop smoke
# test (test_gameloop.jl), which is exactly what that test exists to prevent.
function drain_to_tachikoma!(tbuf, cb::CellBuffer)
    for r in 1:nrows(cb), c in 1:ncols(cb)
        ch = cb.chars[r, c]
        (ch == ' ' && cb.fg[r, c] == 0x00) && continue
        TK.in_bounds(tbuf, c, r) || continue
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
    run_game(; width=120, height=40, seed=0, max_frames=nothing,
               io=nothing, interactive=(io===nothing && stdout isa Base.TTY))

Top-level entry point — the exact code `run.jl` boots. Builds a game + `CellBuffer`,
constructs a Tachikoma `Terminal`, and drives [`game_loop!`](@ref) with
terminal-backed callbacks: poll keys → `tick!` → `draw!` → drain → present.

Two modes, selected by `interactive`:

  * **Interactive** (a real TTY): enters the alternate screen + raw mode via
    `enter_tui!`, polls real keystrokes each frame, presents at ~30fps, and ALWAYS
    restores the terminal (`leave_tui!`) on quit *or* error. Linux/macOS (ANSI).
  * **Headless** (no TTY, or an explicit `io`): builds the `Terminal` over an
    `IOBuffer` (or the supplied `io`) with an explicit `size`, so it never queries a
    TTY. It takes no keys (`Input()` each frame), runs the *real* present path
    (`draw!` → drain → flush to `io`), and skips wall-clock pacing. This is the path
    the headless smoke test drives, so the actual entry point + render path are
    exercised without a terminal.

`max_frames` bounds the loop (used by the smoke test and any scripted run).

Key map (interactive): arrows / `wasd` turn & thrust, space charges (release to
fire), `?` toggles the debug overlay, `q` / `Esc` / `Ctrl-C` quit.
"""
function run_game(; width = 120, height = 40, seed = 0, max_frames = nothing,
                  io::Union{IO,Nothing} = nothing,
                  interactive::Bool = (io === nothing && stdout isa Base.TTY))
    g  = new_game(Xoshiro(seed); width = width, height = height)
    cb = CellBuffer(height, width)

    if interactive
        # `size = (cols, rows)` is the correct kwarg shape (a NamedTuple): the
        # `Terminal(; size)` constructor reads `size.cols`/`size.rows`. Passing a
        # `Rect` here throws `FieldError: Rect has no field cols` — the original bug.
        term = TK.Terminal(; size = (cols = width, rows = height))
        TK.enter_tui!(term)                 # alt-screen + raw mode + start_input!
        try
            _run_loop!(g, cb, term; max_frames = max_frames,
                       poll = frame -> _poll_input(term),
                       pace = frame -> sleep(1 / 30))   # ~30fps
        finally
            TK.leave_tui!(term)             # restore screen + raw mode on quit OR error
        end
    else
        sink = io === nothing ? IOBuffer() : io
        term = TK.Terminal(; io = sink, size = (cols = width, rows = height))
        _run_loop!(g, cb, term; max_frames = max_frames,
                   poll = frame -> Input(),         # no keys without a TTY
                   pace = frame -> nothing)         # no wall-clock pacing
    end
    return g
end

# Wire the terminal-backed callbacks and run the shared loop. `poll`/`pace` differ by
# mode; `present` is the REAL render path in both, so it is covered by the headless
# smoke test (which drives `run_game` over an IOBuffer terminal).
function _run_loop!(g::GameState, cb::CellBuffer, term; max_frames, poll, pace)
    present = (buf, frame) -> _present(term, buf)
    return game_loop!(g, cb; poll = poll, present = present, pace = pace,
                      max_frames = max_frames)
end

# --- input/present: the real Tachikoma 2.1.0 API --------------------------------
# `_present` runs in BOTH modes (real TTY and headless IOBuffer). `_poll_input` reads
# raw-mode keystrokes and is interactive-only (the headless path supplies `Input()`).

"""
    _poll_input(term) -> Input

Drain every key event buffered since the last frame and fold them into one `Input`.
Non-blocking: `poll_event` is called with a tiny timeout and returns as soon as the
input buffer empties, so an idle frame costs ~0.5ms. (`poll_event(0.0)` can't be
used — a zero timeout makes its deadline expire before it reads a byte.)

Momentary keys (thrust/turn) apply for the frame they arrive in; holding `space`
sends key-repeats that keep `fire` true (growing the charge), and the first frame
with no `space` event releases it — the launch edge `tick!` already detects via
`prev_fire`. Key *release* events are ignored (we model hold via repeat, not release).
"""
function _poll_input(term)::Input
    thrust = false; left = false; right = false
    fire = false; debug = false; quit = false
    while true
        evt = TK.poll_event(0.0005)
        evt === nothing && break
        evt isa TK.KeyEvent || continue
        evt.action == TK.key_release && continue
        k = evt.key
        c = evt.char
        if k === :up || (k === :char && (c == 'w' || c == 'W'))
            thrust = true
        elseif k === :left || (k === :char && (c == 'a' || c == 'A'))
            left = true
        elseif k === :right || (k === :char && (c == 'd' || c == 'D'))
            right = true
        elseif k === :char && c == ' '
            fire = true
        elseif k === :char && c == '?'
            debug = true
        elseif k === :char && (c == 'q' || c == 'Q')
            quit = true
        elseif k === :escape || k === :ctrl_c
            quit = true
        end
    end
    return Input(thrust = thrust, left = left, right = right,
                 fire = fire, debug = debug, quit = quit)
end

"""
    _present(term, cb)

Blit the renderer-agnostic `CellBuffer` to the terminal for one frame. `draw!` hands
us the back buffer (holding a stale frame), so we `reset!` it, drain the `CellBuffer`
in, and let `draw!` diff against the front buffer and emit only the changed cells —
then flush to `term.io`. Works on a real TTY and on a headless `IOBuffer` alike.
"""
function _present(term, cb::CellBuffer)
    TK.draw!(term) do f
        TK.reset!(f.buffer)
        drain_to_tachikoma!(f.buffer, cb)
    end
    return nothing
end
