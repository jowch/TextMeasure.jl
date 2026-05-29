# SPDX-License-Identifier: MIT
#
# Interactive Tachikoma renderer + the shared game loop.
#
# The loop itself (`game_loop!`) is terminal-agnostic: it takes `poll` / `present` /
# `pace` callbacks, so the EXACT SAME loop code runs both the interactive game
# (`run_game` on a real TTY) and the headless smoke test. `run_game`'s headless branch
# builds the Tachikoma `Terminal` over an injectable `IOBuffer` (explicit size, no TTY
# query), so the smoke test drives the REAL entry point — boot → loop → tick → draw →
# `_present` (`draw!` → drain → flush) → drain — and asserts bytes were flushed
# (`position(io) > 0`). Input dispatch (`Input` → `tick!`), `draw!` into a `CellBuffer`,
# `drain_to_tachikoma!`, AND `_present` are all exercised without a TTY.
#
# What STILL genuinely requires a live TTY (human tier-2/3 only, not unit-testable):
#   - `_poll_input!` raw-mode keypress + mouse capture (reading actual events)
#   - the visible on-screen render and real ≥30fps wall-clock pacing
#   - the *visible* respawn blink / `?` debug overlay
#
# Twin-stick controls: WASD/arrows STRAFE the ship (direct velocity, no turning), the
# mouse aims (the nose points at the cursor), LMB or Space charges (release to fire).
# Held keys are tracked with a short decay window (key-repeat driven), so motion stays
# smooth across frames without per-key release events.
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
    `enter_tui!`, enables any-motion mouse reporting, polls real key + mouse events each
    frame into a stateful `InputState` (held-key decay + cursor + LMB), presents at
    ~30fps, and ALWAYS restores the terminal (`leave_tui!`) on quit *or* error.
    Linux/macOS (ANSI).
  * **Headless** (no TTY, or an explicit `io`): builds the `Terminal` over an
    `IOBuffer` (or the supplied `io`) with an explicit `size`, so it never queries a
    TTY. It takes no keys (`Input()` each frame), runs the *real* present path
    (`draw!` → drain → flush to `io`), and skips wall-clock pacing. This is the path
    the headless smoke test drives, so the actual entry point + render path are
    exercised without a terminal.

`max_frames` bounds the loop (used by the smoke test and any scripted run).

Key map (interactive): `wasd` / arrows STRAFE (the mouse aims the ship), LMB or space
charges (release to fire), `?` toggles the debug overlay, `q` / `Esc` / `Ctrl-C` quit.
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
        term  = TK.Terminal(; size = (cols = width, rows = height))
        state = InputState()
        TK.enter_tui!(term)                 # alt-screen + raw mode + start_input!
        print(term.io, "\e[?1003h"); flush(term.io)   # any-motion mouse: enter_tui! enables 1000h+1002h+1006h, not 1003h bare-motion
        try
            _run_loop!(g, cb, term; max_frames = max_frames,
                       poll = frame -> _poll_input!(state, term, frame),
                       pace = frame -> sleep(1 / 30))   # ~30fps
        finally
            print(term.io, "\e[?1003l"); flush(term.io)   # restore bare-motion mouse
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

# --- input: stateful twin-stick over the real Tachikoma 2.1.0 API ---------------
# The PURE logic (sweep_stale!, fold_input) needs no terminal and is headless-tested;
# _poll_input! needs a live TK.poll_event and is the human tier-2/3 check.

"""
    InputState()

Per-`run_game` mutable input state threaded across frames: `held` is
`(key,char) => last-seen frame`, `cursor` the last mouse cell (`nothing` until the
first event), `lmb_down` the edge-derived left-button state. Holds no spatial bounds —
the cursor is already terminal-bounded by the mouse events that set it.
"""
mutable struct InputState
    held::Dict{Tuple{Symbol,Char},Int}
    cursor::Union{Nothing,Tuple{Int,Int}}
    lmb_down::Bool
end
InputState() = InputState(Dict{Tuple{Symbol,Char},Int}(), nothing, false)

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
    # A held `?` lingers up to DECAY_WINDOW frames, so a re-tap inside that window won't
    # toggle twice — tick!'s edge-latch still sees debug=true; rapid double-taps coalesce.
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
