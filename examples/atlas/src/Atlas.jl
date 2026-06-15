module Atlas

using TextMeasure
using MakieTextRepel: ProjectionSolver, RepelParams, solve_cluster
import HouseStyle

# includes added task-by-task:
include("data.jl")
include("camera.jl")
include("lod.jl")
include("place.jl")
include("fade.jl")
include("render.jl")
# include("loop.jl"); include("golden.jl")

end # module
