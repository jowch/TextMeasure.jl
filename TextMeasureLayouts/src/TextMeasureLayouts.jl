# SPDX-License-Identifier: MIT

"""
    TextMeasureLayouts

Reusable line-breaking algorithms built **on top of** TextMeasure — worked examples of
consuming a [`Prepared`](@ref) (its cached `:word`/`:space`/`:newline` widths) without ever
touching the font engine yourself. Two public layout strategies, both pure functions of a
`Prepared`:

- [`knuth_plass`](@ref) / [`greedy_justify`](@ref) — justify a paragraph to a target measure
  via the classic box/glue badness model (optimal whole-paragraph vs. the greedy baseline).
- [`shape_pack`](@ref) — flow text into an arbitrary region described by a `chord_fn`
  ([`polygon_chord_fn`](@ref) / [`raster_chord_fn`](@ref)); a full-width rectangle reproduces
  [`layout`](@ref).

Justification and shape-conforming flow are out of TextMeasure's own scope (see the package
README); this sibling package shows how a downstream consumer adds them.
"""
module TextMeasureLayouts

# A top-level sibling package; demos consume it via a path `[sources]` entry.
# Registration target: a registered `TextMeasureLayouts.jl`.

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
