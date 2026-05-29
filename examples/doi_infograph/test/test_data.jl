# SPDX-License-Identifier: MIT
using Test, DOIInfograph

@testset "F1 data layer" begin
    @testset "structs" begin
        a = AuthorRef("Frank", "Arute", "Google AI Quantum")
        @test a.given == "Frank" && a.family == "Arute"
        @test AuthorRef("Ada", "Lovelace").affiliation === nothing
        m = PaperMetadata(; title="T", authors=[a], doi="10.x/y")
        @test m.title == "T" && m.citation_count == 0
        @test m.abstract === nothing && m.tldr === nothing
        @test m.oa_status === :unknown
    end

    @testset "reconstruct_abstract" begin
        inv = Dict("the"=>[0,4], "cat"=>[1], "sat"=>[2], "on"=>[3], "mat"=>[5])
        @test reconstruct_abstract(inv) == "the cat sat on the mat"
        @test reconstruct_abstract(nothing) === nothing
        @test reconstruct_abstract(Dict{String,Vector{Int}}()) === nothing
        dup = Dict("a"=>[0], "b"=>[0])
        @test reconstruct_abstract(dup) in ("a b", "b a")
    end

    @testset "canonical_dois + cache" begin
        dois = canonical_dois()
        @test dois isa Vector{String}
        @test length(dois) == 6
        @test dois[1] == "10.1038/s41586-019-1666-5"
        p = cache_path(:openalex, dois[1])
        @test endswith(p, ".json") && occursin("cache", p)
        # every slot has at least one cached source (OpenAlex/CrossRef/S2)
        for doi in dois
            present = any(s -> load_cached(s, doi) !== nothing, (:openalex, :crossref, :s2))
            @test present
        end
        # slot-6 has no OpenAlex abstract (deepest degradation slot)
        s6 = load_cached(:openalex, dois[6])
        @test s6 !== nothing
        @test get(s6, :abstract_inverted_index, nothing) === nothing
    end

    @testset "fetch_doi_metadata (offline)" begin
        syc = fetch_doi_metadata("10.1038/s41586-019-1666-5"; mailto="t@e.com")
        @test syc.title == "Quantum supremacy using a programmable superconducting processor"
        @test length(syc.authors) == 77            # exact-from-cache, not live
        @test syc.oa_status === :hybrid
        @test syc.abstract !== nothing && syc.tldr !== nothing
        @test occursin("quantum", lowercase(syc.abstract))      # content-equivalence
        @test occursin("supremacy", lowercase(syc.abstract))
        @test syc.pp !== nothing && occursin("505", syc.pp)
        @test !isempty(syc.citations_by_year)
        @test syc.citation_count > 1000
        @test syc.year == 2019
        @test syc.journal == "Nature"

        # Attention: arXiv DOI absent from OpenAlex/CrossRef → S2 fallback gives 8 authors
        attn = fetch_doi_metadata("10.48550/arXiv.1706.03762"; mailto="t@e.com")
        @test length(attn.authors) == 8
        @test occursin("Attention", attn.title)
        @test attn.oa_status === :green             # arXiv → green default

        # slot-6 graceful: no abstract, no tldr, but title + authors present, no throw
        vasp = fetch_doi_metadata("10.1016/0927-0256(96)00008-0"; mailto="t@e.com")
        @test vasp.abstract === nothing && vasp.tldr === nothing
        @test !isempty(vasp.title) && !isempty(vasp.authors)
    end

    @testset "og:image parse + default off" begin
        html = "<meta property=\"og:image\" content=\"https://x/y.png\"/>"
        @test DOIInfograph._scrape_og_image(html) == "https://x/y.png"
        @test DOIInfograph._scrape_og_image("<html></html>") === nothing
        @test fetch_doi_metadata("10.1038/s41586-019-1666-5"; mailto="t@e.com",
                                 fetch_figure=false).figure_url === nothing
    end
end
