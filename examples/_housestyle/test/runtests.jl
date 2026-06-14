using HouseStyle, Test

@testset "HouseStyle loads" begin
    @test isdefined(HouseStyle, :PAPER)
end
