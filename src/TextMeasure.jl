module TextMeasure

using Unicode: graphemes

export prepare, layout, line_top, measure_bounds, subprep
export Prepared, Layout, Line, FontMetrics, TextBounds
export AbstractMeasurementBackend, MonospaceBackend, FreeTypeBackend, MakieBackend, FigletBackend

include("types.jl")
include("backend.jl")
include("bounds.jl")
include("monospace.jl")
include("backend_containers.jl")
include("prepare.jl")
include("layout.jl")

end # module
