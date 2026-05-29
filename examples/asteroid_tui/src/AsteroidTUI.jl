# SPDX-License-Identifier: MIT
"""
    AsteroidTUI

Tachikoma ASCII Asteroid Blaster (#E, demos milestone) — the headline demo for
TextMeasure.jl's *measure-once-layout-many* primitive in terminal space.

Architecture: a renderer-agnostic [`CellBuffer`](@ref) (a `Char` grid + 256-color
+ bold) is painted by a pure `draw!(buf, state)` over a pure `tick!(state, input)`
game core. The core consumes `prepare`/`subprep`/`FigletBackend` (TextMeasure),
`shape_pack`/`raster_chord_fn` (TextMeasureLayouts), and `asteroid_polygon`/
`voronoi_shatter`/`rasterize` (Silhouettes). The CI golden test checksums the
`CellBuffer` and never instantiates a renderer; the Tachikoma renderer (interactive
only) drains the same buffer to the screen.
"""
module AsteroidTUI

using TextMeasure
using TextMeasureLayouts
using Silhouettes
using FIGlet                  # activates TextMeasureFigletExt
import GeometryBasics as GB
using Random

# Smoke check that the FIGlet extension loaded (cell-space measurement available).
function _ext_loaded()
    return Base.get_extension(TextMeasure, :TextMeasureFigletExt) !== nothing
end

include("cellbuffer.jl")
include("cellbackend.jl")
include("prose.jl")
include("pack.jl")
include("entities.jl")
include("input.jl")
include("game.jl")
include("draw.jl")
include("render_tachikoma.jl")

export CellBuffer, clear!, put_char!, put_string!, checksum, to_text
export CellBackend
export asteroid_prose, PROSE_VARIANTS
export pack_prose_into, PackedProse
export GameState, new_game, tick!, draw!, kill_ship!, ship_visible
export Input, ScriptedInput, next_input!
export run_game, game_loop!, step_frame!, drain_to_tachikoma!

# Precompile the first-frame call graph so it's baked into this package's cache
# instead of JIT-compiled on every fresh `run_game` (~28s TTFX otherwise). The
# headless `run_game(io=IOBuffer())` path drives new_game → tick! (all resolvers) →
# draw! → the Tachikoma render drain — the bulk of that cost. We also force one
# fracture (voronoi_shatter/subprep rarely fire in a few slow-asteroid frames) and
# the aim/strafe/fire input arms. This lengthens THIS package's precompile step,
# but that result is cached and amortised across every launch.
using PrecompileTools: @compile_workload

@compile_workload begin
    g = run_game(; width = 48, height = 20, seed = 0, max_frames = 3, io = IOBuffer())
    isempty(g.asteroids) || fracture_asteroid!(g, 1, GB.Point2{Float64}(0.0, 0.0))
    g2 = new_game(Xoshiro(1); width = 48, height = 20)
    tick!(g2, Input(up = true, aim = (10.0, 3.0)))
    tick!(g2, Input(fire = true)); tick!(g2, Input(fire = false))
end

end # module
