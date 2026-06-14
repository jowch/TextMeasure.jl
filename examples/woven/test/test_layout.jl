using Woven: placement_table
using TextMeasure: MonospaceBackend, measure
using Test

# THE engine invariant: "measure, then lay out accordingly". Build the deterministic
# (Monospace) placement table for the woven license and prove the justified words TILE — on
# every line they never collide — and that baselines sit on a constant pitch. This is what
# makes the no-overlap claim a tested guarantee rather than a hope.
@testset "layout: no overlaps + constant baseline pitch" begin
    make_backend(_font, size) = MonospaceBackend(fontsize = Float64(size))
    placements, jl, pitch = placement_table(make_backend;
        ghost_color = :ghost, red_color = :red, black_color = :black)

    @test !isempty(placements)
    @test length(jl.lines) > 1

    # measured width of each placed word at its real size (same backend as the table).
    width(p) = measure(make_backend(p.font, p.size), p.str)

    @testset "words tile within each line (no collisions)" begin
        # group placements by baseline (one group per justified line)
        by_line = Dict{Float64,Vector{eltype(placements)}}()
        for p in placements
            push!(get!(by_line, p.baseline, eltype(placements)[]), p)
        end
        @test !isempty(by_line)
        for (_, ps) in by_line
            sort!(ps; by = p -> p.x)
            for k in 2:length(ps)
                cur, nxt = ps[k - 1], ps[k]
                @test nxt.x >= cur.x + width(cur) - 1e-6
            end
        end
    end

    @testset "baselines are a constant pitch apart" begin
        bases = sort!(unique(p.baseline for p in placements))
        @test length(bases) == length(jl.lines)
        for k in 2:length(bases)
            @test isapprox(bases[k] - bases[k - 1], pitch; atol = 1e-6)
        end
    end
end
