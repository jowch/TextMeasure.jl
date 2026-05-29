# SPDX-License-Identifier: MIT
using SHA: sha256

"""
    CellBuffer(rows, cols)

Renderer-agnostic terminal frame: a `Char` grid plus 256-color foreground and a
bold mask. `chars[row, col]`, `row == 1` is the top. Both interactive renderers
(Tachikoma, future raw-ANSI) drain a `CellBuffer`; the CI golden test checksums it
without instantiating any renderer.
"""
struct CellBuffer
    chars :: Matrix{Char}
    fg    :: Matrix{UInt8}      # Color256 index; 0x00 == terminal default
    bold  :: BitMatrix
end

CellBuffer(rows::Integer, cols::Integer) =
    CellBuffer(fill(' ', rows, cols), zeros(UInt8, rows, cols), falses(rows, cols))

nrows(b::CellBuffer) = size(b.chars, 1)
ncols(b::CellBuffer) = size(b.chars, 2)
inbounds(b::CellBuffer, r::Integer, c::Integer) = 1 <= r <= nrows(b) && 1 <= c <= ncols(b)

function clear!(b::CellBuffer)
    fill!(b.chars, ' '); fill!(b.fg, 0x00); fill!(b.bold, false); return b
end

function put_char!(b::CellBuffer, r::Integer, c::Integer, ch::Char; fg::UInt8=0x00, bold::Bool=false)
    inbounds(b, r, c) || return b
    @inbounds (b.chars[r, c] = ch; b.fg[r, c] = fg; b.bold[r, c] = bold)
    return b
end

function put_string!(b::CellBuffer, r::Integer, c::Integer, s::AbstractString; fg::UInt8=0x00, bold::Bool=false)
    col = c; row = r
    for ch in s
        if ch == '\n'
            row += 1; col = c; continue
        end
        put_char!(b, row, col, ch; fg=fg, bold=bold); col += 1
    end
    return b
end

# Canonical, version-stable byte encoding: dims, then chars (UTF-8), then fg, then bold.
function _canonical_bytes(b::CellBuffer)
    io = IOBuffer()
    write(io, UInt32(nrows(b))); write(io, UInt32(ncols(b)))
    for ch in b.chars; write(io, codeunits(string(ch))); write(io, 0x00); end
    write(io, b.fg)
    write(io, UInt8.(b.bold))
    return take!(io)
end

checksum(b::CellBuffer) = bytes2hex(sha256(_canonical_bytes(b)))
to_text(b::CellBuffer) = join((String(@view b.chars[r, :]) for r in 1:nrows(b)), '\n')
