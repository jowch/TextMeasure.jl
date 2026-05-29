# SPDX-License-Identifier: MIT
#
# HEADLESS GAME-LOOP SMOKE TEST — proves the ACTUAL run.jl code path runs without a
# TTY. run.jl calls `run_game`, which builds a real game + CellBuffer and drives
# `game_loop!` with terminal-backed poll/present/pace callbacks. This test drives the
# SAME `game_loop!` with headless callbacks (scripted/no input, no-op present, no
# pacing), so the loop logic, input dispatch, tick!, draw!, and the Tachikoma buffer
# drain are all exercised — only the raw-mode keypress capture and escape-code write
# (`_poll_input`/`_present`) and real-time pacing stay TTY-only.
using AsteroidTUI
using AsteroidTUI: GameState, new_game, Input, ScriptedInput, next_input!, CellBuffer,
                   game_loop!, step_frame!, drain_to_tachikoma!, nrows, ncols, ship_visible
import Tachikoma as TK
using Random
using Test

# A valid buffer: right dims, every cell a Char, fg a UInt8, bold a Bool.
function _buffer_valid(cb::CellBuffer, h, w)
    size(cb.chars) == (h, w) || return false
    size(cb.fg)    == (h, w) || return false
    size(cb.bold)  == (h, w) || return false
    all(c -> c isa Char, cb.chars) || return false
    return true
end

@testset "headless game-loop smoke" begin
    W, H = 80, 24

    @testset "scripted input — full input vocabulary, no crash" begin
        # A scripted sequence exercising every Input field: rotate, thrust, charge,
        # release-to-fire, debug toggle, idle. Repeats to fill the run.
        script = Input[
            Input(left=true), Input(left=true), Input(thrust=true), Input(thrust=true),
            Input(right=true), Input(fire=true), Input(fire=true), Input(fire=true),
            Input(fire=false),            # release → launch beam
            Input(debug=true),            # toggle overlay
            Input(),                      # idle
            Input(thrust=true), Input(right=true), Input(fire=true), Input(fire=false),
        ]
        si = ScriptedInput(script)
        g  = new_game(Xoshiro(123); width=W, height=H, n_asteroids=4)
        cb = CellBuffer(H, W)

        # Validate the buffer EVERY frame via the present callback (catches a mid-run
        # crash / bad dims / out-of-bounds the moment it happens).
        bad_frames = Int[]
        frames = game_loop!(g, cb;
            poll    = frame -> next_input!(si),
            present = (buf, frame) -> (_buffer_valid(buf, H, W) || push!(bad_frames, frame)),
            pace    = frame -> nothing,
            max_frames = 120)

        @test frames == 120                      # loop ran to completion, no early crash
        @test isempty(bad_frames)                # every frame produced a valid buffer
        @test g.tick_count == 120                # tick! actually advanced each frame
        # in-bounds invariants after 120 ticks of motion
        @test 0 <= g.ship.x <= W && 0 <= g.ship.y <= H
        @test all(a -> 0 <= a.x <= W && 0 <= a.y <= H, g.asteroids)
    end

    @testset "no-input run — idles cleanly" begin
        g  = new_game(Xoshiro(7); width=W, height=H, n_asteroids=5)
        cb = CellBuffer(H, W)
        ok = true
        frames = game_loop!(g, cb;
            poll    = frame -> Input(),
            present = (buf, frame) -> (ok &= _buffer_valid(buf, H, W)),
            pace    = frame -> nothing,
            max_frames = 90)
        @test frames == 90
        @test ok
        @test g.tick_count == 90
    end

    @testset "quit input stops the loop early" begin
        g  = new_game(Xoshiro(1); width=W, height=H)
        cb = CellBuffer(H, W)
        frames = game_loop!(g, cb;
            poll    = frame -> (frame == 10 ? Input(quit=true) : Input(thrust=true)),
            present = (buf, frame) -> nothing,
            pace    = frame -> nothing,
            max_frames = 1000)
        @test frames == 10                       # stopped at the quit, not max_frames
        @test g.tick_count == 10
    end

    @testset "entities evolve under motion" begin
        g  = new_game(Xoshiro(42); width=W, height=H, n_asteroids=3)
        cb = CellBuffer(H, W)
        x0, y0 = g.ship.x, g.ship.y
        θ0 = g.asteroids[1].θ
        game_loop!(g, cb;
            poll    = frame -> Input(thrust=true, right=true),
            present = (buf, frame) -> nothing,
            pace    = frame -> nothing,
            max_frames = 30)
        @test (g.ship.x, g.ship.y) != (x0, y0)   # ship moved
        @test g.asteroids[1].θ != θ0             # asteroid rotated
    end

    @testset "step_frame! + Tachikoma drain (the real render path, headless)" begin
        # Exercises the SAME drain run_game uses to fill a Tachikoma Buffer — proves
        # the buffer fill works in-memory without a terminal.
        g  = new_game(Xoshiro(5); width=W, height=H, n_asteroids=2)
        cb = CellBuffer(H, W)
        step_frame!(g, cb, Input(thrust=true))
        tbuf = TK.Buffer(TK.Rect(0, 0, W, H))
        @test drain_to_tachikoma!(tbuf, cb) === tbuf   # completes, returns the buffer
    end

    @testset "run_game itself runs headless (bounded, injected io, no TTY)" begin
        # run.jl's EXACT entry point: we call the real `run_game`, not a stand-in.
        # Passing `io=IOBuffer()` builds the Tachikoma Terminal over that buffer with
        # an explicit size, so it never queries a TTY and the headless branch (no
        # keys, real `_present` → `draw!` → flush, no pacing) runs end to end. This is
        # the closest possible proof that `julia run.jl` boots, loops, and renders
        # without crashing. (`_poll_input`'s raw-mode key capture stays TTY-only — the
        # human tier-2/3 check.)
        io = IOBuffer()
        g = run_game(; width=W, height=H, seed=3, max_frames=60, io=io)
        @test g isa GameState
        @test g.tick_count == 60                 # the loop ran every frame
        @test position(io) > 0                   # _present actually flushed bytes to the terminal io
    end
end
