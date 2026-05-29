# SPDX-License-Identifier: MIT
# Render the 6-up README-hero composite from the COMMITTED offline cache (no network).
#
#   julia --project=examples/doi_infograph examples/doi_infograph/render_hero.jl
#
# Writes assets/grid_hero.png (README hero) + assets/grid_hero.pdf (per-panel detail).
using DOIInfograph

const ASSETS = normpath(joinpath(@__DIR__, "assets"))
mkpath(ASSETS)

fig = grid_infograph(canonical_dois(); mailto="demo@example.com")
png = export_png(fig, joinpath(ASSETS, "grid_hero.png"))
pdf = export_pdf(fig, joinpath(ASSETS, "grid_hero.pdf"))
@info "rendered hero" png pdf png_bytes=filesize(png) pdf_bytes=filesize(pdf)
