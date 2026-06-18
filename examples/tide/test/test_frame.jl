# SPDX-License-Identifier: MIT
using Tide
using Tide: prepare_tide, frame_layout, _layout_at, PACK_HOOK, N_FRAMES
using TextMeasure
using TextMeasure: MonospaceBackend, AbstractMeasurementBackend, FontMetrics
using TextMeasureLayouts: shape_pack
using Test

# THE HONESTY TEST. The piece's thesis — "measure once, lay out many times" — is made a tested
# guarantee: `prepare_tide` touches the font engine ONLY at setup, then driving all N_FRAMES
# frames through `frame_layout` calls `shape_pack` EXACTLY N_FRAMES times and `prepare` NOT AT ALL
# (every prepare is setup-time). Every frame also places all words and lights ≥1 "kneads".
#
# `prepare`-count is instrumented via a backend that forwards to MonospaceBackend but counts
# `font_metrics` (which `prepare` calls exactly once per call — see src/prepare.jl). `shape_pack`
# is counted by swapping `Tide.PACK_HOOK` for a counting wrapper around the real `shape_pack`.

# Counting backend: delegates to a wrapped MonospaceBackend; bumps a shared Ref on each
# `font_metrics` call (= one per `prepare`). Deterministic (font-independent).
struct CountingBackend <: AbstractMeasurementBackend
    inner   :: MonospaceBackend
    fm_calls :: Base.RefValue{Int}
end
TextMeasure.measure(b::CountingBackend, s::AbstractString) = TextMeasure.measure(b.inner, s)
function TextMeasure.font_metrics(b::CountingBackend)
    b.fm_calls[] += 1
    return TextMeasure.font_metrics(b.inner)
end

@testset "frame: honesty — 1 prepare, N_FRAMES shape_pack; all placed; ≥1 lit each frame" begin
    fm_calls   = Ref(0)
    pack_calls = Ref(0)
    mk(font, size) = CountingBackend(MonospaceBackend(fontsize = Float64(size)), fm_calls)

    # --- SETUP: prepare_tide touches the font engine. Record its prepare count, then freeze. ---
    pb = prepare_tide(mk; body_font = "monospace", fontsize = 11.0)
    setup_prepares = fm_calls[]
    @test setup_prepares >= 1                      # prepare_tide DID touch the engine at setup

    # install the counting shape_pack wrapper for the per-frame phase only.
    real_pack = shape_pack
    PACK_HOOK[] = function (args...; kwargs...)
        pack_calls[] += 1
        return real_pack(args...; kwargs...)
    end

    try
        loop_prepares_before = fm_calls[]
        n_all_placed = 0
        n_with_lit   = 0
        for f in 0:(N_FRAMES - 1)
            fr = frame_layout(pb, f)
            fr.all_placed && (n_all_placed += 1)
            length(fr.lit_idx) >= 1 && (n_with_lit += 1)
        end

        @testset "exactly N_FRAMES shape_pack over the loop" begin
            @test pack_calls[] == N_FRAMES
        end
        @testset "ZERO prepares during the loop (all font-touching was setup)" begin
            @test fm_calls[] == loop_prepares_before
        end
        @testset "every frame places all words (grow-to-fit, no truncation)" begin
            @test n_all_placed == N_FRAMES
        end
        @testset "every frame lights ≥1 'kneads' placement" begin
            @test n_with_lit == N_FRAMES
        end
    finally
        PACK_HOOK[] = real_pack                     # restore production hook
    end

    @testset "rest frame (0) placement count exceeds a sane threshold" begin
        fr0 = frame_layout(pb, 0)
        @test length(fr0.placements) >= 60          # every word placed at rest; floor sits well below the full count
        @test fr0.dir === :W
        @test fr0.b == 0.0                           # frame 0 is the rest rectangle
    end
end
