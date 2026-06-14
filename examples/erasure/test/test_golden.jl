using Erasure: geometry_rows, hero_digest, LICENSE_TEXT
using Test

const GOLDEN_DIR = joinpath(@__DIR__, "golden")

@testset "golden hero geometry" begin
    rows = geometry_rows()
    @test !isempty(rows)
    @test length(rows) > 100                         # the LICENSE has many words
    cs = hero_digest()
    @test length(cs) == 64                           # sha256 hex

    path = joinpath(GOLDEN_DIR, "hero.sha256")
    if get(ENV, "UPDATE_GOLDEN", "") == "1"
        mkpath(GOLDEN_DIR)
        write(path, cs)
        write(joinpath(GOLDEN_DIR, "hero.rows.txt"), join(rows, "\n"))
    end
    @test isfile(path)
    @test cs == strip(read(path, String))            # regression anchor
end
