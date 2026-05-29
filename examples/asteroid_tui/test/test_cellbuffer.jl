# SPDX-License-Identifier: MIT
using AsteroidTUI: CellBuffer, clear!, put_char!, put_string!, checksum, to_text, nrows, ncols
using Test

@testset "CellBuffer" begin
    b = CellBuffer(3, 5)
    @test nrows(b) == 3 && ncols(b) == 5
    @test all(==(' '), b.chars)

    put_string!(b, 1, 1, "AB")
    put_char!(b, 2, 3, 'X'; fg=UInt8(9), bold=true)
    @test b.chars[1,1] == 'A' && b.chars[1,2] == 'B'
    @test b.chars[2,3] == 'X' && b.fg[2,3] == 0x09 && b.bold[2,3]

    # out-of-bounds writes are ignored, not errors
    put_char!(b, 99, 99, 'Z')
    put_string!(b, 1, 4, "WXYZ")          # clips at col 5
    @test b.chars[1,4] == 'W' && b.chars[1,5] == 'X'

    # checksum is content-defined and stable
    b2 = CellBuffer(3, 5); put_string!(b2, 1, 1, "AB"); put_char!(b2, 2, 3, 'X'; fg=UInt8(9), bold=true)
    put_string!(b2, 1, 4, "WX")
    @test checksum(b) == checksum(b2)     # same content ⇒ same checksum
    clear!(b2)
    @test checksum(b) != checksum(b2)
    @test checksum(CellBuffer(3,5)) == checksum(CellBuffer(3,5))   # empty stable
    @test to_text(CellBuffer(1,3)) == "   "

    # newline in put_string! advances row, resets col
    b3 = CellBuffer(2, 3); put_string!(b3, 1, 1, "AB\nCD")
    @test b3.chars[1,1] == 'A' && b3.chars[1,2] == 'B'
    @test b3.chars[2,1] == 'C' && b3.chars[2,2] == 'D'
end
