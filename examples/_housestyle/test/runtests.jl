using HouseStyle, Test, Colors

@testset "HouseStyle loads" begin
    @test isdefined(HouseStyle, :PAPER)
end

@testset "palette + ramp (exact, from demos-house-style.md)" begin
    @test HouseStyle.PAPER     == colorant"#F4EFE6"
    @test HouseStyle.INK       == colorant"#1A1714"
    @test HouseStyle.BRASS     == colorant"#9A7B4F"
    @test HouseStyle.BRASS_INK == colorant"#6E5226"
    @test HouseStyle.BLUE      == colorant"#2E5E8C"
    @test HouseStyle.GREEN     == colorant"#3E7A54"
    @test HouseStyle.RED       == colorant"#A33A2A"
    @test HouseStyle.GRAY      == colorant"#6B7280"
    @test HouseStyle.RAMP == (caption=9, body=11, subhead=16, title=22, deck=31, display=44)
end
