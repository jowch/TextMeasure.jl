# SPDX-License-Identifier: MIT
# The locked sea-prose for The Tide. ONE paragraph, no hard line breaks — it wraps to the
# region and justifies full-time (the paragraph's last line stays ragged, as normal).
#
# "kneads—smoothing" keeps a TIGHT em-dash (no spaces) so it is ONE :word token; at render
# time that token is split at the em-dash so only the "kneads" run glows coral while the
# dash + "smoothing" stay ink, placed flush-adjacent.
#
# Original authored prose — NOT a quotation. Do not attribute a source.
const TIDE_TEXT = "At evening the sea comes in slow and warm, taking its time. Tide after tide it leans gently against the shore and kneads—smoothing the soft sand, folding the gilded edge under, drawing back in a bright hush before it comes again. Nothing it shapes will stay, and nothing needs to. What the low sun gilds, the quiet dusk lets go; and the seam between water and land is traced, and traced again, and left to glow a little while in copper and rose."

# strip punctuation/case (and any em-dash) for the lit-word test
_norm(s) = lowercase(filter(c -> isletter(c) || isdigit(c), s))

"""
    is_lit(word) -> Bool

True when the punctuation-stripped, lowercased `word` equals "kneads". The compound token
"kneads—smoothing" is split at render time; [`has_lit`](@ref) catches that prefix form.

# Examples
```jldoctest
julia> is_lit("kneads")
true

julia> is_lit("Kneads,")     # punctuation stripped, lowercased
true

julia> is_lit("smoothing")
false
```
"""
is_lit(word::AbstractString) = _norm(word) == "kneads"

"""
    has_lit(word) -> Bool

True when `word` IS "kneads" or BEGINS "kneads—" — the tight-em-dash compound
"kneads—smoothing", whose "kneads" run is split out and lit coral at render time.

# Examples
```jldoctest
julia> has_lit("kneads")
true

julia> has_lit("kneads—smoothing")   # the tight em-dash compound is lit-bearing
true

julia> has_lit("smoothing")
false
```
"""
has_lit(word::AbstractString) = is_lit(word) || startswith(_norm(word), "kneads")
