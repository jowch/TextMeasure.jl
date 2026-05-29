# SPDX-License-Identifier: MIT
using Test, DOIInfograph, TextMeasure, CairoMakie, Random
import TextMeasure: measure          # NOT exported by TextMeasure (backend contract)

const _D = DOIInfograph

@testset "F2 layout engine" begin
    @testset "title autoshrink property (100 titles)" begin
        rng = Xoshiro(0xF2)                       # local RNG, no global leak
        box_w = 360.0
        for _ in 1:100
            n = rand(rng, 10:200)
            # build a wrappable title of ~n chars from random short words
            words = String[]; tot = 0
            while tot < n
                w = String(rand(rng, 'a':'z', rand(rng, 2:10)))
                push!(words, w); tot += length(w) + 1
            end
            title = join(words, " ")
            r = title_autoshrink(title; box_width=box_w, fs_min=14.0, fs_max=48.0)
            @test 14.0 <= r.fontsize <= 48.0
            @test r.nlines <= 2                   # contract: always ≤2 lines (clip if needed)
            @test length(r.lines) <= 2
        end
    end

    @testset "autoshrink clip contract (overflowing multi-word title)" begin
        # many words that can't fit in 2 lines even at fs_min in a narrow box → clip path
        huge = join(["lexeme$i" for i in 1:40], " ")
        r = title_autoshrink(huge; box_width=120.0, fs_min=14.0, fs_max=48.0)
        @test r.nlines <= 2
        @test r.fontsize == 14.0 && r.clipped == true
        # clipped 2nd line still fits the box (no overflow) and ends with an ellipsis
        b = _D._backend(_D.SANS, 14.0)
        @test all(ln -> measure(b, ln) <= 120.0 + 1e-6, r.lines)
        @test endswith(r.lines[end], "…")
    end

    @testset "width contract: over-wide unbreakable token is clipped to fit" begin
        # a single ~60-char token with no whitespace cannot wrap (TextMeasure breaks only at
        # whitespace) and is wider than the box even at fs_min → must be char-truncated, not
        # returned over-wide. This is the width half of the M2/M3 contract.
        giant = "Gross"^12                         # 60 chars, no spaces, atomic
        box = 200.0
        r = title_autoshrink(giant; box_width=box, fs_min=14.0, fs_max=48.0)
        @test r.nlines <= 2
        @test r.clipped == true
        @test r.fontsize == 14.0                   # clamped to min, still cannot fit unbroken
        b = _D._backend(_D.SANS, r.fontsize)
        @test all(ln -> measure(b, ln) <= box + 1e-6, r.lines)   # size[1] ≤ box_width
        @test endswith(r.lines[end], "…")
    end

    @testset "M3: slot-4 long title renders ≤2 lines, no overflow" begin
        # the 125-char arXiv title is the declared autoshrink stress; verify the rendered
        # title is ≤2 lines AND every line fits the title box at the chosen fontsize.
        s4  = fetch_doi_metadata(canonical_dois()[4]; mailto="t@e.com")
        @test length(s4.title) >= 80                       # confirm it is the long-title slot
        box = 369.0                                        # ≈ content width at default page
        r = title_autoshrink(s4.title; box_width=box, fs_min=14.0, fs_max=40.0)
        @test r.nlines <= 2
        b = _D._backend(_D.SANS, r.fontsize)
        @test all(ln -> measure(b, ln) <= box + 1e-6, r.lines)   # no horizontal overflow
        @test infograph(s4) isa CairoMakie.Figure
    end

    @testset "comparative: long title shrinks more" begin
        syc  = fetch_doi_metadata("10.1038/s41586-019-1666-5"; mailto="t@e.com")
        attn = fetch_doi_metadata("10.48550/arXiv.1706.03762"; mailto="t@e.com")
        rs = title_autoshrink(syc.title;  box_width=360.0)
        ra = title_autoshrink(attn.title; box_width=360.0)
        @test rs.fontsize < ra.fontsize           # longer Sycamore title renders smaller
    end

    @testset "author overflow" begin
        b = _D._backend(_D.SANS, 11.0)
        many = AuthorRef[AuthorRef("A", "Author$i") for i in 1:60]
        shown, etal = _D.fit_authors(many, b; row_width=300.0)
        @test etal == true && length(shown) < 60
        few = AuthorRef[AuthorRef("A", "Author$i") for i in 1:8]
        shown2, etal2 = _D.fit_authors(few, b; row_width=4000.0)
        @test etal2 == false && length(shown2) == 8

        # real data: Sycamore (77) → et al.; Attention (8) fits
        syc  = fetch_doi_metadata("10.1038/s41586-019-1666-5"; mailto="t@e.com")
        attn = fetch_doi_metadata("10.48550/arXiv.1706.03762"; mailto="t@e.com")
        _, syc_etal  = _D.fit_authors(syc.authors,  b; row_width=300.0)
        _, attn_etal = _D.fit_authors(attn.authors, b; row_width=4000.0)
        @test syc_etal == true
        @test attn_etal == false
    end

    @testset "author overflow boundary (off-by-one guard)" begin
        b = _D._backend(_D.SANS, 11.0)
        names = AuthorRef[AuthorRef("A", "Name$i") for i in 1:20]
        # size the row so exactly the first k fit alongside " et al."
        sep_w  = measure(b, ", ")
        etal_w = measure(b, " et al.")
        k = 5
        used = 0.0
        for i in 1:k
            used += (i == 1 ? 0.0 : sep_w) + measure(b, _D._author_label(names[i]))
        end
        # width that fits k authors + et al., but the (k+1)-th would overflow
        next_w = sep_w + measure(b, _D._author_label(names[k+1]))
        row_w = used + etal_w + next_w/2          # room for k + etal, not for k+1
        shown, etal = _D.fit_authors(names, b; row_width=row_w)
        @test etal == true
        @test length(shown) == k                  # exactly k, no off-by-one
    end

    @testset "tldr autosize bounds (true block height)" begin
        fs = _D.tldr_autosize("Short sentence."; box_width=240.0, box_height=120.0,
                              fs_min=9.0, fs_max=14.0)
        @test fs == 14.0                          # one-liner fits at max → no growth past max
        long = repeat("word ", 400)
        fs2 = _D.tldr_autosize(long; box_width=240.0, box_height=120.0, fs_min=9.0, fs_max=14.0)
        @test 9.0 <= fs2 <= 14.0
    end

    @testset "drop cap offset" begin
        off = _D.dropcap_offset("Quantum supremacy"; dropcap_fontsize=48.0, gutter=4.0)
        capQ = measure(_D._backend(_D.SERIF, 48.0), "Q")
        @test off ≈ capQ + 4.0                    # advance of the initial at cap size + gutter
        @test off > capQ
    end

    @testset "concept pill wrap" begin
        b = _D._backend(_D.SANS, 10.0)
        pills = ["Quantum computer","Qubit","Supremacy","Algorithm","Noise"]
        rows = _D.wrap_pills(pills, b; strip_width=180.0, pad=8.0, gap=6.0)
        @test all(!isempty, rows)
        @test sum(length, rows) == length(pills)  # every pill placed exactly once
    end

    @testset "citation sparkline width match (±1 glyph)" begin
        b = _D._backend(_D.SANS, 10.0)
        cap = "2019—2026"
        spark = _D.citation_sparkline([(2019,10),(2020,40),(2021,80),(2022,60)], b;
                                      target_width=measure(b, cap))
        glyphw = maximum(measure(b, string(c)) for c in "▁▂▃▄▅▆▇█")
        @test abs(measure(b, spark) - measure(b, cap)) <= 1.05 * glyphw
    end

    @testset "infograph composition" begin
        for doi in canonical_dois()
            fig = infograph(doi; mailto="t@e.com")
            @test fig isa CairoMakie.Figure
        end
        m1 = fetch_doi_metadata(canonical_dois()[1]; mailto="t@e.com")
        @test_throws ArgumentError infograph(m1; template=:bogus)
        @test infograph(m1; justification=:knuth_plass) isa CairoMakie.Figure  # warns, falls back
    end
end
