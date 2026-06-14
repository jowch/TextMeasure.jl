using Woven: save_png
using CairoMakie
using Test

@testset "render helper" begin
    @testset "save_png writes a non-empty PNG on PAPER" begin
        path = joinpath(mktempdir(), "smoke.png")
        save_png(path; size = (200, 120), px_per_unit = 1) do ax
            CairoMakie.scatter!(ax, [1.0, 2.0], [1.0, 2.0])
        end
        @test isfile(path)
        @test filesize(path) > 0
        # PNG magic bytes
        @test read(path, 8) == UInt8[0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]
    end
end
