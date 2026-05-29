# SPDX-License-Identifier: MIT
# Vermont quickstart — renders entirely from bundled data (NO network).
#   julia --project=examples/map_feature examples/map_feature/render_vermont.jl
using MapFeature
import CairoMakie
fig = map_feature(load_vermont(), load_stats(), load_pois())
out = get(ENV, "MAPFEATURE_OUT", joinpath(@__DIR__, "vermont"))
CairoMakie.save(out * ".png", fig; px_per_unit=1.0)
render_to_pdf(fig, out * ".pdf")
println("wrote ", out, ".png and ", out, ".pdf")
