# SPDX-License-Identifier: MIT
using HouseStyle, Test, Colors

@testset "HouseStyle loads" begin
    @test isdefined(HouseStyle, :PAPER)
end

@testset "palette + ramp (exact, from README.md house style)" begin
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

@testset "font paths + footer" begin
    @test isdir(HouseStyle.FONTS_DIR)
    @test isfile(HouseStyle.fraunces("9pt-Regular"))
    @test isfile(HouseStyle.fraunces("144pt-Black"))
    @test isfile(HouseStyle.plexmono())            # default Regular
    @test isfile(HouseStyle.plexmono("Medium"))
    @test isfile(HouseStyle.hanken("Regular"))
    @test isfile(HouseStyle.hanken("SemiBold"))
    @test isfile(HouseStyle.hanken("Black"))       # mapped to Bold static
    @test endswith(HouseStyle.fraunces("9pt-Regular"), "Fraunces9pt-Regular.ttf")
    @test HouseStyle.footer("Woven") == "TextMeasure.jl · Woven"
end

@testset "digest_rows" begin
    a = ["w1|0.00|12.50", "w2|40.00|12.50"]
    @test HouseStyle.digest_rows(a) isa String
    @test length(HouseStyle.digest_rows(a)) == 64          # sha256 hex
    @test HouseStyle.digest_rows(a) == HouseStyle.digest_rows(reverse(a))  # order-independent
    @test HouseStyle.digest_rows(a) != HouseStyle.digest_rows(["w1|0.01|12.50", "w2|40.00|12.50"])
end
