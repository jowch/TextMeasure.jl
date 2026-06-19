# SPDX-License-Identifier: MIT

"""
    Atlas

A geographic label-placement gallery piece: an animated central-coast map whose town and POI
labels are measured by TextMeasure, sized by a level-of-detail ramp, and placed by the
MakieTextRepel solver so they never overlap as the camera dives. It demonstrates driving the
engine from real geographic data — `measure_boxes` is the TextMeasure seam (it measures label
strings into the pixel boxes the solver consumes).

Source files include in dependency order: `data` (projection + load) → `pois` → `camera`
(dive schedule) → `lod` (per-rank sizing) → `place` (measure + solve) → `render` → `loop`
(frame driver) → `golden` (deterministic digest).
"""
module Atlas

using TextMeasure
using MakieTextRepel: warm_solve
import HouseStyle

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
