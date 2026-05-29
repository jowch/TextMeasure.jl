# SPDX-License-Identifier: MIT
using Random: AbstractRNG

const _CLASS    = ("C-type", "S-type", "M-type", "carbonaceous", "silicate",
                   "metallic", "chondritic", "basaltic")
const _MATERIAL = ("iron-nickel", "olivine", "pyroxene", "regolith", "magnetite",
                   "ice-laced rock", "porous dust", "shock-veined ore")
const _TEMPER   = ("ancient and cold", "scarred by impacts", "tumbling lazily",
                   "newly calved", "radar-bright", "spectrally dark")
const _CALLPREFIX = ("NX", "VG", "KR", "ZL", "QF", "BD")

# Conservative count: class × material × temper (callsign/spin add far more).
PROSE_VARIANTS() = length(_CLASS) * length(_MATERIAL) * length(_TEMPER)

"""
    asteroid_prose(rng) -> String

Deterministic-by-`rng` descriptive sentence for an asteroid's interior text.
Pulls only from `rng` (no global RNG access).
"""
function asteroid_prose(rng::AbstractRNG)
    cls  = rand(rng, _CLASS)
    mat  = rand(rng, _MATERIAL)
    tmp  = rand(rng, _TEMPER)
    call = string(rand(rng, _CALLPREFIX), '-', lpad(rand(rng, 100:999), 3, '0'))
    spin = round(rand(rng) * 0.4; digits = 2)
    return "$cls drifter $call composed of $mat, $tmp, spinning at $spin rad per second."
end
