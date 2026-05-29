# SPDX-License-Identifier: MIT
#
# Interactive Tachikoma renderer. NOT unit-tested — the game core (CellBuffer +
# tick!/draw!) and the golden test do not depend on this file. The interactive
# Done-whens (≥30fps, respawn flash, invuln blink, `?` debug overlay) are verified
# by a human (tier-2/3), not in CI.
import Tachikoma as TK

# Drain a renderer-agnostic CellBuffer into a Tachikoma Buffer (1-based x=col, y=row).
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
    run_game(; width=120, height=40, seed=0, max_frames=nothing)

Interactive entry. Builds a Tachikoma `Terminal`, then runs the fixed-timestep loop:
read key → `tick!` → `draw!` into a `CellBuffer` → drain → present, targeting ~60fps.
Linux/macOS only (ANSI / raw-mode). `max_frames` bounds the loop for smoke runs.

Key map: arrows/`wasd` move & turn, space charges (release to fire), `?` toggles the
debug overlay, `q` quits. The precise Tachikoma key-event field names are resolved
against the installed version at call time (interactive bring-up).
"""
function run_game(; width = 120, height = 40, seed = 0, max_frames = nothing)
    g = new_game(Xoshiro(seed); width = width, height = height)
    cb = CellBuffer(height, width)
    term = TK.Terminal(; size = TK.Rect(0, 0, width, height))
    frame = 0
    quit = false
    while !quit
        in = _poll_input(term)
        in.quit && break
        tick!(g, in)
        draw!(cb, g)
        tbuf = TK.Buffer(TK.Rect(0, 0, width, height))
        drain_to_tachikoma!(tbuf, cb)
        _present(term, tbuf)
        sleep(1 / 60)
        frame += 1
        max_frames !== nothing && frame >= max_frames && (quit = true)
    end
    return g
end

# --- input/present shims, resolved against the live Tachikoma API at bring-up ----
# Kept tiny and isolated so the rest of the renderer is API-stable. The headless
# path (tests) never calls these.
function _poll_input(term)::Input
    # Non-blocking key read → Input. Resolved interactively against TK's event API
    # (KeyEvent / handle_key!); defaults to a no-op so a smoke run advances frames.
    return Input()
end

function _present(term, tbuf)
    # Blit the Buffer to the terminal. Resolved interactively against TK's present
    # path (Terminal draw/flush). No-op-safe for headless smoke.
    return nothing
end
