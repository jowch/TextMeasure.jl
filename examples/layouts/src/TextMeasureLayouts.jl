# SPDX-License-Identifier: MIT
module TextMeasureLayouts

# Shared layout utilities for the TextMeasure.jl demos milestone (#C, #K).
# Consumed by per-demo projects via `Pkg.develop(path="../layouts")`.
# Long-term migration target: a registered `TextMeasureLayouts.jl` sibling package.

using TextMeasure: FontMetrics, Prepared, Segment
using GeometryBasics: Point2

export Placement, PackedLayout
export AbstractChordFn, chord_intervals
export shape_pack
export polygon_chord_fn, PolygonChordFn, raster_chord_fn, RasterChordFn
export JustifiedLine, JustifiedLayout, knuth_plass, greedy_justify

include("shape_pack.jl")
include("knuth_plass.jl")

end # module
