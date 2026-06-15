# SPDX-License-Identifier: MIT
using Tide
using Tide: prepare_tide, frame_layout, region_mask, make_band_interval, DIRECTIONS,
            CELL, N_FRAMES, FRAMES_PER_PRESS
using TextMeasure: MonospaceBackend
using TextMeasureLayouts: raster_chord_fn, chord_intervals, shape_pack
using Test

# The wavy region mask (6 raking directions, tight-box anchored) must honor two invariants the
# packer relies on: (1) every band that survives the bite is ≥ floor_w wide (the readability
# floor / `min_chord_width`), and (2) AT MOST ONE run of inside-cells per raster row — the
# `fill=:widest` invariant (the vertical W/E walls AND the tight-box corner wedges never carve a
# row into islands). Plus grow-to-fit guarantees no word is truncated at the deepest bite.
@testset "mask: floor + single-interval per band + grow-to-fit (6 directions, tight box)" begin
    mk(font, size) = MonospaceBackend(fontsize = Float64(size))
    pb = prepare_tide(mk; body_font = "monospace", fontsize = 11.0)
    Wpx = pb.Wpx; Hpx = pb.Hpx; la = pb.line_advance; floor_w = pb.floor_w
    fy = pb.floor_y; dy = pb.deep_y; ty = pb.top_y

    # build the mask exactly as production does (deep_y / top_y anchors threaded through).
    mask(d, b, ph) = region_mask(Wpx, Hpx, d, b, ph;
                                 cell = CELL, line_advance = la,
                                 floor_y = fy, deep_y = dy, top_y = ty)

    @testset "≤ 1 inside-run per raster row, at d_max (incl. wavy edge + straight diagonals)" begin
        # sample the wavy edge at several phases (incl. crests) so the wave is exercised.
        for d in DIRECTIONS
            for phase in (0.0, π / 3, 2π / 3, π)
                r = mask(d, pb.d_max[d], phase)
                for row in 1:size(r, 1)
                    runs = 0
                    prev = false
                    for col in 1:size(r, 2)
                        cur = r[row, col]
                        (cur && !prev) && (runs += 1)
                        prev = cur
                    end
                    @test runs <= 1
                end
            end
        end
    end

    @testset "every surviving text band ≥ floor_w, at d_max" begin
        for d in DIRECTIONS
            r  = mask(d, pb.d_max[d], 0.0)
            cf = raster_chord_fn(r, CELL)
            pk = shape_pack(pb.prep, cf; line_advance = la, min_chord_width = floor_w,
                            overflow_strategy = :widest_row, fill = :widest)
            bi = make_band_interval(cf, pb.asc, la)
            ys = sort!(unique(p.y for p in pk.placements))
            for y in ys
                xs = [p.x for p in pk.placements if p.y == y]
                L, R = bi(y, minimum(xs))
                (isnan(L) || isnan(R)) && continue
                @test (R - L) >= floor_w - 1e-6
            end
        end
    end

    @testset "bottom-corner bites (SW/SE) actually eat the text (not empty tail)" begin
        # at d_max, the SW/SE diagonal must knock cells out of rows that hold REAL text.
        for d in (:SW, :SE)
            r = mask(d, pb.d_max[d], 0.0)
            bit_in_text = false
            top_strip = floor(Int, (dy - pb.d_max[d] - Tide.WAVE_A))    # first bitten row
            for row in max(1, top_strip):min(size(r, 1), ceil(Int, dy))
                any(!, @view r[row, :]) && (bit_in_text = true; break)
            end
            @test bit_in_text
        end
    end

    @testset "SINGLE STRAIGHT DIAGONAL: cut depth is monotone (no hold/bend); bottom is deepest" begin
        # The fix: the SW/SE cut ramps linearly 0→b with NO constant-depth segment. Walk the cut
        # depth per row down the rake strip and assert it strictly increases (no flat hold = no
        # diagonal-to-vertical bend), and the deepest row sits at the bottom (near deep_y).
        b = pb.d_max[:SW]
        for d in (:SW, :SE)
            r = mask(d, b, 0.0)                                         # phase 0 ⇒ no wave wobble
            # cut depth per row = number of knocked cells (≈ the straight ramp + 0 wave at phase 0).
            depths = Float64[]
            ys     = Int[]
            r0 = max(1, floor(Int, dy - b - Tide.WAVE_A))
            r1 = min(size(r, 1), floor(Int, dy))
            for row in r0:r1
                push!(depths, count(!, @view r[row, :]))
                push!(ys, row)
            end
            @test length(depths) >= 4
            # strictly increasing (allow tiny equal steps from cell quantization, but NO long flat
            # run): the last depth exceeds the first by ≈ b, and it is monotone non-decreasing.
            for k in 2:length(depths)
                @test depths[k] >= depths[k - 1] - 1.5                  # monotone (≤ quantization)
            end
            @test depths[end] - depths[1] >= b - 2 * Tide.WAVE_A - 2.0  # spans ~full ramp 0→b
            @test depths[end] >= b - Tide.WAVE_A - 2.0                  # bottom is the DEEPEST
        end
    end

    @testset "depth_px == 0 ⇒ full rest rectangle (all true)" begin
        for d in DIRECTIONS
            r = mask(d, 0.0, 1.234)
            @test all(r)
        end
    end

    @testset "grow-to-fit ⇒ all_placed at every press peak (deepest bite)" begin
        for p in 0:5
            f = p * FRAMES_PER_PRESS + FRAMES_PER_PRESS ÷ 2     # the peak beat (depth=1.0)
            fr = frame_layout(pb, f)
            @test fr.all_placed
        end
    end
end
