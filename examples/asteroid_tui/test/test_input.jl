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
        st = InputState()
        st.held[(:char,'w')]=0; st.held[(:char,'d')]=0; st.held[(:char,' ')]=0
        inp = fold_input(st, 0)
        @test inp.up && inp.right && !inp.down && !inp.left
        @test inp.fire                       # Space ⇒ fire
        @test inp.aim === nothing            # no cursor yet
        st2 = InputState(); st2.held[(:left,'\0')]=0; st2.held[(:escape,'\0')]=0
        inp2 = fold_input(st2, 0); @test inp2.left && inp2.quit
    end
    @testset "fold_input fire from lmb_down" begin
        st = InputState(); st.lmb_down = true
        @test fold_input(st, 0).fire
    end
    @testset "fold_input emits the cursor as aim (raw, no φ math here)" begin
        st = InputState(); st.cursor = (60, 2)
        @test fold_input(st, 0).aim == (60.0, 2.0)     # passed through; φ is computed in the sim
    end
end
