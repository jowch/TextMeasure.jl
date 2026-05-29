### A Pluto.jl notebook ###
# v0.20.0

# SPDX-License-Identifier: MIT
using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of
# Pluto, the following 'mock version' of @bind gives bound variables a default value
# (instead of an error).
macro bind(def, element)
    #! format: off
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ 11111111-0000-0000-0000-000000000001
# Activate THIS demo's project so Pluto uses DOIInfograph + its cached responses.
# (Pluto is not a dependency of the demo — it pins HTTP 1.x; see README.)
begin
    import Pkg
    Pkg.activate(@__DIR__)
    using DOIInfograph
    using PlutoUI
end

# ╔═╡ 11111111-0000-0000-0000-000000000002
md"""
# DOIInfograph — interactive demo

Measure once, lay out many times. Paste a DOI, then drag the **page width** slider: the
layout reflows (title autoshrink, author overflow, abstract wrap) without re-fetching.
All six canonical DOIs are cached for offline use.
"""

# ╔═╡ 11111111-0000-0000-0000-000000000003
@bind doi Select(canonical_dois(); default=canonical_dois()[1])

# ╔═╡ 11111111-0000-0000-0000-000000000004
# Fetch + merge ONCE per DOI (cached); only the layout below re-runs on slider change.
meta = fetch_doi_metadata(doi; mailto="demo@example.com")

# ╔═╡ 11111111-0000-0000-0000-000000000005
@bind page_width Slider(300:10:600; default=420, show_value=true)

# ╔═╡ 11111111-0000-0000-0000-000000000006
# Reflow only — re-layout against the cached metadata at the chosen width.
infograph(meta; page=(page_width, round(Int, page_width * 1.414)))

# ╔═╡ 11111111-0000-0000-0000-000000000007
md"""
### Export PDF
"""

# ╔═╡ 11111111-0000-0000-0000-000000000008
@bind do_export CounterButton("Export this infograph to PDF")

# ╔═╡ 11111111-0000-0000-0000-000000000009
let
    do_export
    fig = infograph(meta; page=(page_width, round(Int, page_width * 1.414)))
    path = joinpath(@__DIR__, "infograph_" * replace(doi, r"[^A-Za-z0-9]" => "_") * ".pdf")
    export_pdf(fig, path)
    md"Saved to `$(path)`"
end

# ╔═╡ Cell order:
# ╟─11111111-0000-0000-0000-000000000002
# ╠═11111111-0000-0000-0000-000000000001
# ╠═11111111-0000-0000-0000-000000000003
# ╠═11111111-0000-0000-0000-000000000004
# ╠═11111111-0000-0000-0000-000000000005
# ╠═11111111-0000-0000-0000-000000000006
# ╟─11111111-0000-0000-0000-000000000007
# ╠═11111111-0000-0000-0000-000000000008
# ╠═11111111-0000-0000-0000-000000000009
