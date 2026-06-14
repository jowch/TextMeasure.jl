module HouseStyle
using Colors

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

end # module
