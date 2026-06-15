# SPDX-License-Identifier: MIT
module Atlas

using TextMeasure
using MakieTextRepel: ProjectionSolver, RepelParams, solve_cluster
import HouseStyle

# includes added task-by-task:
include("data.jl")
include("pois.jl")
include("camera.jl")
include("lod.jl")
include("place.jl")
include("render.jl")
include("loop.jl")
include("golden.jl")

export render_loop, render_hero, extract_loopframes, warmstart_delta_stats

end # module
