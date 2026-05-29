# SPDX-License-Identifier: MIT
# #F3 — 6-up grid + export helpers.

"""
    grid_infograph(dois; mailto, page=(420,594), cols=3) -> CairoMakie.Figure

Compose a single `CairoMakie.Figure` holding one infograph panel per DOI in a row-major
grid (default 2×3 for six DOIs). All metadata is fetched via `fetch_doi_metadata` —
offline from `data/cache/` when present. The composite is exported as one page by
`export_pdf` / `export_png`.
"""
function grid_infograph(dois::AbstractVector{<:AbstractString};
                        mailto::AbstractString="demo@example.com",
                        page=(420, 594), cols::Int=3)
    n    = length(dois)
    rows = cld(n, cols)
    pw, ph = Float64(page[1]), Float64(page[2])
    W, H = cols * pw, rows * ph
    fig = CM.Figure(size=(W, H), figure_padding=0)
    sc  = fig.scene
    CM.poly!(sc, CM.Rect2f(0, 0, W, H); color=:white, space=:pixel)
    for (i, doi) in enumerate(dois)
        r = (i - 1) ÷ cols            # 0-based row, 0 = top
        c = (i - 1) % cols            # 0-based col
        x0   = c * pw
        ybot = H - (r + 1) * ph       # scene bottom of this panel
        meta = fetch_doi_metadata(doi; mailto)
        _draw_infograph!(sc, meta, (x0, ybot, pw, ph))
        # panel separator
        CM.poly!(sc, CM.Rect2f(x0, ybot, pw, ph); color=:transparent,
                 strokecolor=_RULE, strokewidth=1.0, space=:pixel)
    end
    return fig
end

"Save `fig` as a single-page PDF (vector, selectable text)."
export_pdf(fig, path::AbstractString) = (CM.save(path, fig); path)

"Save `fig` as a PNG raster (2× for a crisp README hero)."
export_png(fig, path::AbstractString; px_per_unit::Real=2) =
    (CM.save(path, fig; px_per_unit=px_per_unit); path)
