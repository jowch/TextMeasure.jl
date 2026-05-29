# SPDX-License-Identifier: MIT
#
# Human-play entry point. Run at a real terminal:  julia --project run.jl
# Controls: arrows / WASD turn & thrust, space charges (release to fire),
#           ? toggles the debug overlay, q / Esc / Ctrl-C quit.
using AsteroidTUI

# The game is interactive: it reads raw-mode keystrokes and quits on `q`. Without a
# TTY there are no keys to read and no quit signal, so a bare `run_game()` would loop
# forever. Refuse to start headless (rather than hang) and point at the headless API.
if !(stdout isa Base.TTY)
    println(stderr, """
        AsteroidTUI needs an interactive terminal (a TTY) to play.
        Run it directly:  julia --project run.jl
        For a bounded, no-TTY run (tests/CI), call:
            AsteroidTUI.run_game(; io = IOBuffer(), max_frames = 60)""")
    exit(1)
end

AsteroidTUI.run_game(; seed = parse(Int, get(ENV, "SEED", "0")))
