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

end # module
