# SPDX-License-Identifier: MIT
using AsteroidTUI: new_game, draw!, CellBuffer, checksum, to_text, CellBackend, ship_visible
import TextMeasure
using Random

const GOLDEN_DIR = joinpath(@__DIR__, "golden")

# Curated showcase prose — long enough that the dominant silhouette fills as a real
# shaped-text MASS (the blob fills to the prose's glyph count, so a short blurb would
# spread thin across a large shape). Hand-tuned copy, not the procedural template.
const _HERO_PROSE =
    "Born from the shattering of some long-dead world, this drifting massif of nickel and " *
    "shadowed ice has wandered the cold reaches for an age, its pitted face a record of every " *
    "blow the dark has dealt it, tumbling on without haste or heading through the long night " *
    "between the scattered stars."
const _MED_PROSE =
    "Porous, fast, and faintly glittering, it drifts where the sunlight finally grows too thin " *
    "to warm a stone."

_prep(s) = TextMeasure.prepare(CellBackend(), s)

# The committed showcase scene (design-reviewer pick, FEATURABLE): a single dominant
# rounded text-mass (left-center, the engine shaping ~300 chars of prose into a
# silhouette) + a smaller receding intact asteroid (upper-right) + the ship (▲ nose
# above ▮ hull, 8-way directional glyph). Hand-placed for composition; velocities are
# NONZERO so the stat readouts show the field in motion even in a still frame. The
# silhouette POLYGONS come from `Xoshiro(38)` via `new_game`, so the whole frame is
# deterministic and reproducible. This is a STATIC composed frame (`draw!` only, no
# tick loop): the headless tick-loop / determinism path is covered by test_game.jl,
# and the order-exact fracture glyph-preservation acceptance by test_fracture.jl. This
# golden regenerates ONLY when `draw.jl` visuals change (not on `tick!`/physics changes)
# and is the render-regression anchor for the gallery showcase frame.
function _run_golden()
    g = new_game(Xoshiro(38); width = 116, height = 36, n_asteroids = 2)
    g.ship.x = 58.0; g.ship.y = 31.0; g.ship.φ = 0.0; g.ship.vx = 0.0; g.ship.vy = -0.15
    a1, a2 = g.asteroids
    a1.x = 32.0; a1.y = 18.0; a1.vx =  0.22; a1.vy = 0.10; a1.ω =  0.012; a1.radius = 10.0; a1.prep = _prep(_HERO_PROSE)
    a2.x = 93.0; a2.y = 12.0; a2.vx = -0.18; a2.vy = 0.06; a2.ω = -0.02;  a2.radius =  6.0; a2.prep = _prep(_MED_PROSE)
    buf = CellBuffer(g.height, g.width)
    draw!(buf, g)
    return g, buf
end

@testset "golden showcase frame" begin
    g, buf = _run_golden()
    # Non-vacuous scene assertions (the frame is the gallery showcase, not a fracture).
    @test length(g.asteroids) == 2
    @test ship_visible(g)
    @test count(!=(' '), buf.chars) > 200            # the dominant mass actually fills

    cs = checksum(buf)
    golden_path = joinpath(GOLDEN_DIR, "frame60.sha256")
    if get(ENV, "UPDATE_GOLDEN", "") == "1"
        mkpath(GOLDEN_DIR)
        write(golden_path, cs)
        write(joinpath(GOLDEN_DIR, "frame60.txt"), to_text(buf))
    end
    @test isfile(golden_path)
    @test cs == strip(read(golden_path, String))     # regression anchor

    # NOTE: fracture glyph-preservation (each glyph once, IN ORDER) is enforced
    # non-vacuously in test_fracture.jl; tick-loop determinism in test_game.jl. This
    # golden pins the *rendered showcase frame* only.
end
