# SPDX-License-Identifier: MIT
"""
    MapFeature

CairoMakie state map-feature page (#G, demos milestone): a cartographic state
silhouette with editorial prose wrapping around it as an irregular obstacle.
See `docs/superpowers/plans/2026-05-28-G-map-feature.md`.
"""
module MapFeature

using GeometryBasics: Point2
using TextMeasure
using TextMeasureLayouts: shape_pack

export complement_chord_fn
export POI, LabelBox, place_poi_labels
export PageProjection, project_polygon, project_point
export load_vermont, load_state_shapefile, load_pois, load_stats, fetch_state_shapefile
export map_feature, render_to_pdf

include("complement_chord_fn.jl")
include("projection.jl")
include("poi.jl")
include("data.jl")
include("render.jl")

end # module
