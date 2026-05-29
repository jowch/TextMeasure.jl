# SPDX-License-Identifier: MIT
using Test, TextMeasure, TextMeasureLayouts, Justification

_mkline(gap_centers) = JustifiedLine(Int[], Float64[], gap_centers, 0.0, 0.0, 0.0, 0.0)
_mklayout(gcs) = JustifiedLayout([_mkline(g) for g in gcs], 0.0, 100.0, FontMetrics(9.6, 2.4, 14.4))

@testset "find_rivers: hand-built 3-line fixture (exact count)" begin
    # Only the middle column aligns across all three lines (≈50, within tol=3).
    aligned = _mklayout([[10.0, 50.0, 90.0], [30.0, 51.0, 70.0], [15.0, 49.0, 95.0]])
    rivers = find_rivers(aligned; align_tol=3.0, min_run=3)
    @test length(rivers) == 1
    @test [ln for (ln, _) in rivers[1].points] == [1, 2, 3]      # spans the 3 consecutive lines
    @test all(abs(x - 50.0) <= 3.0 for (_, x) in rivers[1].points)

    # No column aligns across ≥3 lines ⇒ no river.
    scattered = _mklayout([[50.0], [60.0], [50.0]])
    @test isempty(find_rivers(scattered; align_tol=3.0, min_run=3))

    # Two lines can never form a river when min_run=3.
    @test isempty(find_rivers(_mklayout([[50.0], [50.0]]); align_tol=3.0, min_run=3))
end

@testset "greedy has rivers K-P avoids (QUANTIFIED FLOOR)" begin
    prep = prepare(MonospaceBackend(), CANONICAL_PARAGRAPH)
    T = 240.0                                            # narrow measure: the river regime
    space_w = prep.segments[2].width                     # one inter-word space (7.2 px)
    g = greedy_justify(prep; max_width=T)
    k = knuth_plass(prep; max_width=T)
    rg = find_rivers(g; align_tol=space_w)
    rk = find_rivers(k; align_tol=space_w)
    # Observed (locked 2026-05-28): greedy 3 rivers, K-P 0, at align_tol = one space width.
    @test length(rg) >= 1                                # greedy pools gaps into rivers
    @test length(rk) < length(rg)                        # K-P breaks them up
end
