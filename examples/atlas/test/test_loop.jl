# test_loop.jl — warm-start stability + seam-closure tests for the Atlas loop.
#
# These tests are headless (no ffmpeg, no video encode): they exercise the warm-start
# placement pipeline on consecutive mid-dive frames and verify:
#   (a) camera_rect seam is closed: camera_rect(0.0) ≈ camera_rect(1.0)
#   (b) warm-start keeps per-label offset-delta below a sane bound (< 25 px/frame)
#       across consecutive mid-dive frames (where labels are dense and warm-start matters).

using Atlas: camera_rect, warmstart_delta_stats, load_atlas_data, assemble_frame,
             N_FRAMES, FPS
using GeometryBasics: Vec2f
using Test

@testset "loop: camera seam closure" begin
    r0 = camera_rect(0.0)
    r1 = camera_rect(1.0)
    # The loop phase is mod-1 periodic, so p=0 and p=1 must give the SAME window.
    @test r0[1] ≈ r1[1] atol = 1e-5
    @test r0[2] ≈ r1[2] atol = 1e-5
    @test r0[3] ≈ r1[3] atol = 1e-5
    @test r0[4] ≈ r1[4] atol = 1e-5
end

@testset "loop: warm-start offset-delta at mid-dive (3 frames, p95 < 25 px)" begin
    # Test at mid-dive (frame 126..128 out of 360 ≈ p=0.35) where labels are dense
    # and warm-start is actually exercised (many shared ids between consecutive frames).
    d = load_atlas_data()
    let prev = Dict{Int,Vec2f}()
        all_deltas = Float32[]
        for f in 125:128
            p = f / N_FRAMES
            _, _, af = assemble_frame(d, p; pagepx=(1620,1080), prev=prev)
            fp = af.fp
            if !isempty(prev)
                for (k, id) in enumerate(fp.ids)
                    if haskey(prev, id)
                        old = prev[id]; new = fp.offsets[k]
                        push!(all_deltas, sqrt((new[1]-old[1])^2 + (new[2]-old[2])^2))
                    end
                end
            end
            prev = Dict{Int,Vec2f}(fp.ids[k] => fp.offsets[k] for k in eachindex(fp.ids))
        end

        @test !isempty(all_deltas)   # warm-start exercised (shared labels found)
        sort!(all_deltas)
        med = all_deltas[div(length(all_deltas), 2) + 1]
        p95 = all_deltas[clamp(round(Int, 0.95 * length(all_deltas)), 1, length(all_deltas))]
        @info "warm-start delta stats (mid-dive)" median_px=round(med; digits=1) p95_px=round(p95; digits=1)
        # p95 below 25 px/frame: labels glide, they don't jump.
        @test p95 < 25.0f0
    end
end

@testset "loop: N_FRAMES and FPS constants" begin
    @test N_FRAMES == 360
    @test FPS      == 30
end
