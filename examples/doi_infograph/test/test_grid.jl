# SPDX-License-Identifier: MIT
using Test, DOIInfograph, CairoMakie, SHA

@testset "F3 grid + export" begin
    @testset "grid renders + exports" begin
        fig = grid_infograph(canonical_dois(); mailto="t@e.com")
        @test fig isa CairoMakie.Figure
        mktempdir() do d
            pdf = joinpath(d, "grid.pdf"); png = joinpath(d, "grid.png")
            export_pdf(fig, pdf); export_png(fig, png)
            @test filesize(pdf) > 0 && filesize(png) > 0
        end
    end

    @testset "slot-6 graceful render" begin
        m = fetch_doi_metadata(canonical_dois()[6]; mailto="t@e.com")
        @test m.abstract === nothing && m.tldr === nothing
        @test infograph(m) isa CairoMakie.Figure        # enlarged pills + muted caption, no throw
    end

    @testset "pdf-text font-embedding golden" begin
        if Sys.which("pdftotext") === nothing
            @test_skip "pdftotext unavailable — cannot verify text embedding"
        else
            fig = grid_infograph(canonical_dois(); mailto="t@e.com")
            mktempdir() do d
                pdf = joinpath(d, "g.pdf"); export_pdf(fig, pdf)
                txt  = read(`pdftotext -enc UTF-8 $pdf -`, String)
                toks = sort(unique(filter(!isempty, split(lowercase(txt), r"\s+"))))
                # HARD asserts: text is embedded + selectable (catches font→outline regressions)
                @test length(toks) >= 50
                @test "quantum" in toks && "supremacy" in toks
                # informational drift signal (NOT a hard gate — token set shifts with reflow)
                gold = joinpath(@__DIR__, "golden", "grid_pdf_text.sha256")
                digest = bytes2hex(sha256(join(toks, " ")))
                if isfile(gold)
                    GOLDEN_MATCH[] = (chomp(read(gold, String)) == digest)
                else
                    mkpath(dirname(gold)); write(gold, digest)
                    GOLDEN_MATCH[] = true
                end
            end
        end
    end
end
