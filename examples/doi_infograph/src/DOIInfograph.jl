# SPDX-License-Identifier: MIT
"""
    DOIInfograph

Adaptive, measurement-driven academic-paper infographic generator (demos milestone
#F1–#F3). Fetches DOI metadata (offline-cacheable), composes a single-paper editorial
cover with CairoMakie, and renders a 6-up README-hero grid + Pluto notebook. All tests
and renders run offline from `data/cache/`.

See `docs/superpowers/plans/2026-05-28-demos-F-doi-infograph.md` for the design and the
six PROBE-FIRST deviations from the original issue bodies (notably: SemanticScholar.jl is
unusable alongside CairoMakie, so the S2 client is a thin HTTP wrapper here).
"""
module DOIInfograph

using TextMeasure
# `measure` / `font_metrics` are intentionally NOT exported by TextMeasure (backend
# contract); import them explicitly so bare calls resolve after `using TextMeasure`.
import TextMeasure: measure, font_metrics
using TextMeasureLayouts
import HTTP, JSON3
import TOML
import CairoMakie
const CM = CairoMakie

export AuthorRef, PaperMetadata
export OpenAlexClient, CrossRefClient, SemanticScholarClient
export fetch_doi_metadata, reconstruct_abstract, cache_path, load_cached, canonical_dois
export title_autoshrink, infograph, grid_infograph, export_pdf, export_png

include("data.jl")
include("layout.jl")
include("grid.jl")

end # module
