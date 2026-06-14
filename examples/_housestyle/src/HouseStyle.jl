module HouseStyle
using Colors
using SHA

# Identity layer (carries every piece)
const PAPER     = colorant"#F4EFE6"
const INK       = colorant"#1A1714"
const BRASS     = colorant"#9A7B4F"
const BRASS_INK = colorant"#6E5226"
# Data layer (encode ONLY — never identity)
const BLUE  = colorant"#2E5E8C"
const GREEN = colorant"#3E7A54"
const RED   = colorant"#A33A2A"
const GRAY  = colorant"#6B7280"
# √2 type ramp (pt) — pick the tier by role, never an in-between value
const RAMP = (caption=9, body=11, subhead=16, title=22, deck=31, display=44)

# examples/fonts lives two dirs up from this src file: _housestyle/src -> _housestyle -> examples
const FONTS_DIR = normpath(joinpath(@__DIR__, "..", "..", "fonts"))

"""
    fraunces(name) -> String

Absolute path to a pinned Fraunces static. `name` MUST include the point-size
prefix in `<size>pt-<weight>` form, because the Fraunces filenames have no
separator before the size (`Fraunces9pt-Regular.ttf`). So `fraunces("9pt-Regular")`
is correct; `fraunces("Regular")` would silently yield the non-existent path
`FrauncesRegular.ttf`.
"""
fraunces(name::AbstractString) = joinpath(FONTS_DIR, "Fraunces", "Fraunces$(name).ttf")

"Absolute path to a pinned IBM Plex Mono static, e.g. `plexmono(\"Medium\")` (default Regular)."
plexmono(name::AbstractString="Regular") = joinpath(FONTS_DIR, "IBMPlexMono", "IBMPlexMono-$(name).ttf")

"""
    hanken(weight) -> String

Absolute path to a pinned Hanken Grotesk static (`Regular` / `SemiBold` / `Bold`).
`"Black"` is mapped to `"Bold"` (the heaviest pinned static), so a poem weight of
`"Black"` resolves to a real file. File form: `HankenGrotesk-<weight>.ttf`.
"""
hanken(weight::AbstractString) =
    joinpath(FONTS_DIR, "HankenGrotesk", "HankenGrotesk-$(weight == "Black" ? "Bold" : weight).ttf")

"The shared footer string: `TextMeasure.jl · <piece>` (middot U+00B7)."
footer(piece::AbstractString) = "TextMeasure.jl · $(piece)"

"""
    digest_rows(rows) -> String

SHA-256 hex of a canonicalized placement/layout table. `rows` is a vector of
pre-formatted strings (each piece builds its own row format, rounding floats to a
fixed precision before formatting). Rows are sorted so the digest is independent of
emission order. This is the gallery's golden invariant — hash the computed table,
never the rendered pixels. Rows must NOT contain newlines: `"\\n"` is the row
separator, so an embedded newline would silently change the digest.
"""
function digest_rows(rows::AbstractVector{<:AbstractString})
    bytes2hex(sha2_256(join(sort(collect(rows)), "\n")))
end

end # module
