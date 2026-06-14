using Tide
using Tide: prepare_tide, frame_layout, _layout_at, TIDE_TEXT
using TextMeasure: MonospaceBackend, measure
using Test

# THE engine invariant made a guarantee: per-band justify never overlaps words, justified
# bands sit flush-right, the paragraph's last line stays ragged, and baselines are a constant
# pitch apart. Built on the deterministic MonospaceBackend (font-independent) so the table is
# reproducible. Word widths are re-derived INDEPENDENTLY from the backend (not read from the
# justify output) so the no-overlap check is non-tautological.
@testset "justify: no overlap + flush-right + ragged last line + constant pitch" begin
    make_backend(font, size) = MonospaceBackend(fontsize = Float64(size))
    # the SW wavy-tide HOLD still (a SW press at depth=1.0, phase=0) — the locked hero layout.
    pb = prepare_tide(make_backend; body_font = "monospace", fontsize = 11.0, grow_dirs = (:SW,))
    fr = _layout_at(pb, :SW, 1.0, 0.0)

    @test !isempty(fr.placements)
    @test length(fr.band_order) > 1
    @test fr.all_placed                                   # grow-to-fit placed every word

    # independent width: measure the word with the SAME MonospaceBackend (NOT justify output).
    mb = make_backend("monospace", 11.0)
    iwidth(p) = measure(mb, fr.segs[p.segment_index].str)

    # group placements by baseline y; each distinct y is one band.
    by_band = Dict{Float64,Vector{eltype(fr.placements)}}()
    for p in fr.placements
        push!(get!(by_band, p.y, eltype(fr.placements)[]), p)
    end
    @test !isempty(by_band)

    @testset "1. no overlap, in reading order (independently-measured widths)" begin
        for (_, ps) in by_band
            sort!(ps; by = p -> fr.justx[p])
            for k in 2:length(ps)
                cur, nxt = ps[k - 1], ps[k]
                @test fr.justx[nxt] >= fr.justx[cur] + iwidth(cur) - 1e-6
            end
        end
    end

    # which bands the justify pass actually stretched: a multi-word band whose first→last
    # justified gaps were widened beyond the natural pack x. We detect "stretched" as: not the
    # final band, multi-word, and last-word right edge ≈ the band's right bound R.
    bo = fr.band_order
    last_band_y = bo[end]

    @testset "2. justified bands are flush-right (last word right ≈ R)" begin
        any_flush = false
        for y in bo
            y == last_band_y && continue                  # final paragraph line is ragged
            ws = sort(by_band[y]; by = p -> fr.justx[p])
            length(ws) < 2 && continue
            L, R = fr.band_interval(y, ws[1].x)
            isnan(R) && continue
            right = fr.justx[ws[end]] + iwidth(ws[end])
            # a band is "stretched" iff its natural right fell short of R but justified right
            # now lands on R. Only assert flushness for those.
            nat_right = ws[end].x + iwidth(ws[end])
            if R - nat_right > 1e-6 && fr.justx[ws[end]] != ws[end].x
                @test isapprox(right, R; atol = 1e-6)
                any_flush = true
            end
        end
        @test any_flush                                   # at least one band was justified
    end

    @testset "3. final paragraph line is ragged (not stretched to R)" begin
        ws = sort(by_band[last_band_y]; by = p -> fr.justx[p])
        # the last band keeps its natural x for every word (no stretch applied).
        for p in ws
            @test fr.justx[p] == p.x
        end
        if length(ws) >= 2
            L, R = fr.band_interval(last_band_y, ws[1].x)
            right = fr.justx[ws[end]] + iwidth(ws[end])
            @test right < R - 1e-6                         # short of the right edge => ragged
        end
    end

    @testset "4. constant baseline pitch across bands" begin
        @test length(bo) >= 2
        pitch = bo[2] - bo[1]
        @test pitch == fr.line_advance
        for k in 2:length(bo)
            @test isapprox(bo[k] - bo[k - 1], pitch; atol = 1e-6)
        end
    end
end
