# SPDX-License-Identifier: MIT
using Test, MapFeature
import CairoMakie

const GOLDDIR = joinpath(@__DIR__, "goldens")

_have_pdftotext() = !isnothing(Sys.which("pdftotext"))

# normalize: lowercase alphanumeric tokens (len >= 3), sorted-unique
function _tokens(s::AbstractString)
    toks = [lowercase(m.match) for m in eachmatch(r"[A-Za-z0-9]{3,}", s)]
    return sort!(unique!(toks))
end

@testset "PDF export: selectable text (font embedding) + token-floor golden" begin
    if !_have_pdftotext()
        @test_skip "pdftotext not on PATH"
    else
        pois = load_pois(); stats = load_stats()
        fig = map_feature(load_vermont(), stats, pois)
        dir = mktempdir()
        pdf = render_to_pdf(fig, joinpath(dir, "vermont.pdf"))
        @test isfile(pdf) && filesize(pdf) > 0
        txt = read(`pdftotext -layout $pdf -`, String)

        # selectability: input strings survive into extractable text
        @test occursin("Vermont", txt) || occursin("VERMONT", txt)
        # POI labels: simple offset placement may DROP a colliding label (harder repel is out of
        # scope), so assert a FLOOR — most POI names are embedded & selectable — not all of them.
        n_present = count(p -> occursin(split(p.name)[1], txt), pois)
        @test n_present >= length(pois) - 2
        @test occursin("Montpelier", txt)                # capital (sidebar — always rendered)
        @test occursin(string(stats[:population]), txt)  # population big-number (sidebar)

        # token-set FLOOR golden: current extraction must be a SUPERSET of the committed floor
        # (regression floor — never silently lose selectable tokens; floors not hard counts).
        goldfile = joinpath(GOLDDIR, "vermont_tokens.txt")
        @test isfile(goldfile)
        golden  = Set(filter(!isempty, readlines(goldfile)))
        current = Set(_tokens(txt))
        @test isempty(setdiff(golden, current))
    end
end
