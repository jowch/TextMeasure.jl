module TextMeasure

using Unicode: graphemes

export prepare, layout, line_top
export Prepared, Layout, Line, FontMetrics
export AbstractMeasurementBackend, MonospaceBackend, FreeTypeBackend, MakieBackend

include("types.jl")
include("backend.jl")
include("monospace.jl")
include("backend_containers.jl")
include("prepare.jl")
include("layout.jl")

end # module
