using Atlas: FadeState, update_fade!, alpha_of, FADE_FRAMES
using Test

@testset "fade: smoothstep fade-in keyed by town_id" begin
    fs = FadeState()
    update_fade!(fs, [1, 2], 0)             # both appear at frame 0
    @test alpha_of(fs, 1) == 0.0            # frame 0 of fade → 0
    for f in 1:FADE_FRAMES
        update_fade!(fs, [1, 2], f)
    end
    @test alpha_of(fs, 1) ≈ 1.0             # fully faded in after FADE_FRAMES
    @test alpha_of(fs, 99) == 0.0           # unknown id → invisible
    update_fade!(fs, [1], FADE_FRAMES+1)    # 2 leaves the active set
    @test alpha_of(fs, 2) == 0.0            # dropped → 0 (no lingering ghost)
end
