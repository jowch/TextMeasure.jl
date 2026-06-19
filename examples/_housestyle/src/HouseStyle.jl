# SPDX-License-Identifier: MIT

"""
    HouseStyle

The gallery's shared house style: the palette (`PAPER`/`INK`/`BRASS` identity colours plus the
data-encode `BLUE`/`GREEN`/`RED`/`GRAY`), the √2 type `RAMP`, pinned font paths
(`fraunces`/`plexmono`/`hanken`), the `footer` string, and the `digest_rows` golden hash.
Nothing is exported — reference everything qualified (`HouseStyle.PAPER`,
`HouseStyle.footer(...)`). See README.md for the design rules; `test/runtests.jl` is the
executable guard (if a pinned value disagrees, that is a bug).
"""
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
fraunces(name::AbstractString) = _checked(joinpath(FONTS_DIR, "Fraunces", "Fraunces$(name).ttf"))

"""
    plexmono(name="Regular") -> String

Absolute path to a pinned IBM Plex Mono static (file form `IBMPlexMono-<name>.ttf`), e.g.
`plexmono("Medium")`; the default is `Regular`.
"""
plexmono(name::AbstractString="Regular") = _checked(joinpath(FONTS_DIR, "IBMPlexMono", "IBMPlexMono-$(name).ttf"))

"""
    hanken(weight) -> String

Absolute path to a pinned Hanken Grotesk static (`Regular` / `SemiBold` / `Bold`).
`"Black"` is mapped to `"Bold"` (the heaviest pinned static), so a poem weight of
`"Black"` resolves to a real file. File form: `HankenGrotesk-<weight>.ttf`.
"""
hanken(weight::AbstractString) =
    _checked(joinpath(FONTS_DIR, "HankenGrotesk", "HankenGrotesk-$(weight == "Black" ? "Bold" : weight).ttf"))

# Surface a bad `name`/`weight` (the footgun the helpers above warn about) at the call site
# with the offending path, instead of letting it fail deep inside the font engine.
_checked(path::AbstractString) =
    isfile(path) ? path :
    error("HouseStyle: no font file at $path — check the name/weight argument (see the \
           fraunces/plexmono/hanken docstrings for the required filename form).")

"""
    footer(piece) -> String

The shared gallery footer `TextMeasure.jl · <piece>` (middot U+00B7).

# Examples
```jldoctest
julia> footer("Woven")
"TextMeasure.jl · Woven"
```
"""
footer(piece::AbstractString) = "TextMeasure.jl · $(piece)"

"""
    digest_rows(rows) -> String

SHA-256 hex of a canonicalized placement/layout table. `rows` is a vector of
pre-formatted strings (each piece builds its own row format, rounding floats to a
fixed precision before formatting). Rows are sorted so the digest is independent of
emission order. This is the gallery's golden invariant — hash the computed table,
never the rendered pixels. Rows must NOT contain newlines: `"\\n"` is the row
separator, so an embedded newline would silently change the digest.

# Examples
```jldoctest
julia> d = digest_rows(["w2|40.00", "w1|0.00"]);

julia> length(d)                                   # SHA-256 hex
64

julia> digest_rows(["w1|0.00", "w2|40.00"]) == d   # rows are sorted ⇒ order-independent
true
```
"""
function digest_rows(rows::AbstractVector{<:AbstractString})
    bytes2hex(sha2_256(join(sort(collect(rows)), "\n")))
end

end # module
