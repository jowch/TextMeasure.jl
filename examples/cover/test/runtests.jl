# SPDX-License-Identifier: MIT
using Test
using Cover
using Random
using SHA
using TextMeasureLayouts: chord_intervals

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# A realistic config in a temp dir with a tiny svg + (optional) pull quote.
function _make_cfg(; inset_x=240.0, inset_y=200.0, inset_w=200.0, inset_h=240.0,
                     pull_quotes=true)
    dir = mktempdir()
    write(joinpath(dir,"skyline.svg"),
        """<svg viewBox="0 0 100 100"><rect x="0" y="40" width="100" height="60" fill="#445"/>
           <polygon points="10,40 20,15 30,40" fill="#778"/></svg>""")
    pq = pull_quotes ? """
        [[pull_quote]]
        text        = "Measurement, not guesswork."
        attribution = "— TM"
        x_px        = 30
        y_px        = 560
        width_px    = 150
        """ : ""
    body = repeat("The measurement pipeline computes every baseline and wrap point so the layout adapts automatically. ", 6)
    toml = """
    [meta]
    title    = "The Newer Yorker"
    subtitle = "A Correctness Exhibit"
    byline   = "by TextMeasure.jl"
    [layout]
    page_size     = "letter"
    margin_px     = 54
    dropcap_lines = 3
    gutter_px     = 6
    [inset]
    svg_path  = "skyline.svg"
    x_px      = $inset_x
    y_px      = $inset_y
    width_px  = $inset_w
    height_px = $inset_h
    [[body]]
    paragraph = "$body"
    dropcap   = true
    [[body]]
    paragraph = "A second paragraph continues with more measured words to fill the column nicely."
    $pq
    """
    path = joinpath(dir, "cover.toml")
    write(path, toml)
    return load_config(path)
end

# Config from raw inset + single pull-quote params (property test).
function _make_cfg_raw(; inset_x, inset_y, inset_w, inset_h, pq_x, pq_y, pq_w, gutter=6.0)
    dir = mktempdir()
    write(joinpath(dir,"skyline.svg"),
        """<svg viewBox="0 0 100 100"><rect x="0" y="50" width="100" height="50" fill="#445"/></svg>""")
    body = repeat("The measurement pipeline computes every baseline and wrap point so the layout adapts. ", 9)
    toml = """
    [meta]
    title = "The Newer Yorker"
    subtitle = "A Correctness Exhibit"
    byline = "by TextMeasure.jl"
    [layout]
    page_size = "letter"
    margin_px = 54
    dropcap_lines = 3
    gutter_px = $gutter
    [inset]
    svg_path = "skyline.svg"
    x_px = $inset_x
    y_px = $inset_y
    width_px = $inset_w
    height_px = $inset_h
    [[body]]
    paragraph = "$body"
    dropcap = true
    [[pull_quote]]
    text = "Measurement, not guesswork, at every line."
    attribution = "— TM"
    x_px = $pq_x
    y_px = $pq_y
    width_px = $pq_w
    """
    path = joinpath(dir, "cover.toml")
    write(path, toml)
    return load_config(path)
end

_have(tool) = !isnothing(Sys.which(tool))

# normalize pdftotext output for stable hashing: strip CR, collapse blank-line runs,
# strip trailing spaces, ensure trailing newline.
function _norm_text(s::AbstractString)
    s = replace(s, "\r" => "")
    lines = rstrip.(split(s, "\n"))
    out = String[]
    for ln in lines
        (isempty(ln) && !isempty(out) && isempty(out[end])) && continue
        push!(out, String(ln))
    end
    return strip(join(out, "\n")) * "\n"
end

function _render_fixture(name)
    data = joinpath(@__DIR__, "..", "data", name)
    out = joinpath(mktempdir(), replace(name, ".toml" => ".pdf"))
    return render_cover(data; out = out)
end

# every data row of `pdffonts` output must have emb == "yes" (>=1 data row required).
function _all_fonts_embedded(fonts::AbstractString)
    lines = split(fonts, "\n")
    length(lines) < 3 && return false
    header = lines[1]
    rng = findfirst("emb", header)
    rng === nothing && return false
    start = first(rng)
    any_data = false
    for row in lines[3:end]
        isempty(strip(row)) && continue
        length(row) < start && continue
        any_data = true
        field = strip(row[start:min(lastindex(row), start + 3)])
        field == "yes" || return false
    end
    return any_data
end

# ---------------------------------------------------------------------------
@testset "Cover.jl" begin

    @testset "load_config" begin
        dir = mktempdir()
        toml = """
        [meta]
        title    = "The Newer Yorker"
        subtitle = "A Correctness Exhibit"
        byline   = "by TextMeasure.jl"

        [layout]
        page_size     = "letter"
        margin_px     = 54
        dropcap_lines = 3
        gutter_px     = 6

        [inset]
        svg_path  = "skyline.svg"
        x_px      = 240
        y_px      = 150
        width_px  = 200
        height_px = 260

        [[body]]
        paragraph = "First paragraph with enough words to wrap several lines around the inset for testing."
        dropcap   = true

        [[body]]
        paragraph = "Second paragraph continues the story with additional words."

        [[pull_quote]]
        text        = "A pithy callout."
        attribution = "— Editor"
        x_px        = 40
        y_px        = 520
        width_px    = 160
        """
        path = joinpath(dir, "cover.toml")
        write(path, toml)
        cfg = load_config(path)
        @test cfg.title == "The Newer Yorker"
        @test cfg.subtitle == "A Correctness Exhibit"
        @test cfg.byline == "by TextMeasure.jl"
        @test cfg.page_size == "letter"
        @test cfg.margin_px == 54.0
        @test cfg.dropcap_lines == 3
        @test cfg.gutter_px == 6.0
        @test cfg.inset.svg_path == "skyline.svg"
        @test cfg.inset.x_px == 240.0 && cfg.inset.width_px == 200.0
        @test length(cfg.body) == 2
        @test cfg.body[1].dropcap == true
        @test cfg.body[2].dropcap == false          # default
        @test length(cfg.pull_quotes) == 1
        @test cfg.pull_quotes[1].attribution == "— Editor"
        @test cfg.config_dir == dir

        write(path, """
        [meta]
        title = "T"
        [layout]
        page_size = "a4"
        margin_px = 36
        [inset]
        svg_path = "x.svg"
        x_px = 1
        y_px = 1
        width_px = 10
        height_px = 10
        [[body]]
        paragraph = "Hello world."
        """)
        cfg2 = load_config(path)
        @test cfg2.subtitle == "" && cfg2.byline == ""
        @test cfg2.dropcap_lines == 3                # default
        @test cfg2.gutter_px == 6.0                  # default
        @test isempty(cfg2.pull_quotes)
        @test cfg2.body[1].dropcap == false

        write(path, """
        [meta]
        title = "T"
        [layout]
        page_size = "poster"
        margin_px = 36
        [inset]
        svg_path = "x.svg"
        x_px = 1
        y_px = 1
        width_px = 10
        height_px = 10
        [[body]]
        paragraph = "Hi."
        """)
        @test_throws ArgumentError load_config(path)
    end

    @testset "RectExclusionChordFn" begin
        f = RectExclusionChordFn(50.0, 550.0, 400.0,
                                 [BBox(200.0, 100.0, 300.0, 200.0)], 0.0)
        @test chord_intervals(f, 0.0, 20.0) == [(50.0, 550.0)]
        @test chord_intervals(f, 120.0, 140.0) == [(50.0, 200.0), (300.0, 550.0)]
        @test chord_intervals(f, 250.0, 270.0) == [(50.0, 550.0)]
        @test chord_intervals(f, 400.0, 420.0) == Tuple{Float64,Float64}[]
        @test f(120.0, 140.0) == chord_intervals(f, 120.0, 140.0)

        g = RectExclusionChordFn(50.0, 550.0, 400.0,
                                 [BBox(200.0, 100.0, 300.0, 200.0)], 10.0)
        @test g(120.0, 140.0) == [(50.0, 190.0), (310.0, 550.0)]
        @test g(92.0, 96.0) == [(50.0, 190.0), (310.0, 550.0)]

        h = RectExclusionChordFn(50.0, 550.0, 400.0,
                                 [BBox(0.0, 0.0, 120.0, 50.0)], 0.0)
        @test h(10.0, 30.0) == [(120.0, 550.0)]

        k = RectExclusionChordFn(0.0, 600.0, 400.0,
                                 [BBox(100.0, 0.0, 200.0, 100.0),
                                  BBox(400.0, 0.0, 500.0, 100.0)], 0.0)
        @test k(10.0, 30.0) == [(0.0, 100.0), (200.0, 400.0), (500.0, 600.0)]

        z = RectExclusionChordFn(50.0, 550.0, 400.0,
                                 [BBox(0.0, 0.0, 600.0, 100.0)], 0.0)
        @test z(10.0, 30.0) == Tuple{Float64,Float64}[]
    end

    @testset "SVG parse + fit" begin
        dir = mktempdir()
        svg = """
        <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
          <rect x="10" y="20" width="30" height="40" fill="#3366cc"/>
          <polygon points="0,0 100,0 50,100" fill="red" stroke="black" stroke-width="2"/>
          <line x1="0" y1="0" x2="100" y2="100" stroke="#0a0"/>
          <circle cx="50" cy="50" r="10" fill="none" stroke="blue"/>
        </svg>
        """
        path = joinpath(dir, "t.svg")
        write(path, svg)
        doc = parse_svg(path)
        @test doc.viewbox == (0.0, 0.0, 100.0, 100.0)
        @test length(doc.prims) == 4

        rect = BBox(300.0, 150.0, 500.0, 350.0)        # square, uniform fit, scale=2
        rings = svg_rings(doc, rect)
        @test length(rings) == 4
        r1 = rings[1]
        @test r1.closed == true
        @test r1.fill !== nothing
        @test length(r1.points) == 4
        @test r1.points[1][1] ≈ 320.0 atol=1e-4      # (10,20)->(300+10*2,150+20*2)
        @test r1.points[1][2] ≈ 190.0 atol=1e-4
        rc = rings[4]                                  # circle
        @test rc.closed == true
        @test length(rc.points) >= 12
        @test rc.fill === nothing                      # fill="none"
        @test rc.stroke !== nothing
        @test rings[3].closed == false                 # line
        @test length(rings[3].points) == 2

        wide = BBox(0.0, 0.0, 400.0, 200.0)            # 400x200, vb 100x100 -> scale 2, centered x
        rings2 = svg_rings(doc, wide)
        @test rings2[1].points[1][1] ≈ 100.0 + 10*2 atol=1e-4
    end

    @testset "SVG fail-loud (out of subset)" begin
        dir = mktempdir()
        function _wr(name, body)
            p = joinpath(dir, name); write(p, body); p
        end
        @test_throws ArgumentError parse_svg(_wr("curve.svg",
            """<svg viewBox="0 0 10 10"><path d="M0,0 C1,1 2,2 3,3"/></svg>"""))
        @test_throws ArgumentError parse_svg(_wr("arc.svg",
            """<svg viewBox="0 0 10 10"><path d="M0,0 A5,5 0 0 1 5,5"/></svg>"""))
        @test_throws ArgumentError parse_svg(_wr("xform.svg",
            """<svg viewBox="0 0 10 10"><rect x="0" y="0" width="5" height="5" transform="rotate(10)"/></svg>"""))
        @test_throws ArgumentError parse_svg(_wr("group.svg",
            """<svg viewBox="0 0 10 10"><g><rect x="0" y="0" width="5" height="5"/></g></svg>"""))
        @test_throws ArgumentError parse_svg(_wr("use.svg",
            """<svg viewBox="0 0 10 10"><use href="#a"/></svg>"""))
        # in-subset still parses fine
        ok = parse_svg(_wr("ok.svg",
            """<svg viewBox="0 0 10 10"><path d="M0,0 L10,0 L10,10 Z"/></svg>"""))
        @test length(ok.prims) == 1 && ok.prims[1].closed == true
    end

    @testset "compose_cover invariants" begin
        cfg = _make_cfg()
        c = compose_cover(cfg)
        @test c.page_size == (612.0, 792.0)
        @test !isempty(c.body_runs)
        @test length(c.body_runs) == length(c.body_word_bboxes)
        @test c.dropcap !== nothing
        @test c.dropcap.text == "T"

        @test dropcap_bands_consecutive(c)
        @test dropcap_baseline_aligned(c; tol=0.5)
        @test c.dropcap.baseline > c.body_top
        @test c.dropcap.baseline < c.body_top + cfg.dropcap_lines * c.body.metrics.line_advance + 50

        @test isempty(bbox_violations(c))
        @test body_wrap_honors_inset(c)

        @test c.inset_rect.left ≈ 54.0 + 240.0 atol=1e-9
        @test c.inset_rect.top  ≈ 54.0 + 200.0 atol=1e-9

        @test length(c.masthead) == 3
        @test c.masthead[1].text == "The Newer Yorker"
        @test c.masthead[1].x > 54.0                   # centered title

        # no dropcap -> baseline checks vacuously true
        cfg_nd = _make_cfg()
        # build a config with dropcap off on first paragraph
        c2 = compose_cover(load_config(let
            d = mktempdir()
            write(joinpath(d,"skyline.svg"), read(joinpath(cfg.config_dir,"skyline.svg"), String))
            p = joinpath(d, "cover.toml")
            write(p, """
            [meta]
            title = "T"
            [layout]
            page_size = "letter"
            margin_px = 54
            [inset]
            svg_path = "skyline.svg"
            x_px = 250
            y_px = 250
            width_px = 150
            height_px = 150
            [[body]]
            paragraph = "No drop cap here, just plenty of measured body words to wrap around the inset nicely and fill several lines on the page."
            """)
            p
        end))
        @test c2.dropcap === nothing
        @test dropcap_baseline_aligned(c2)
        @test dropcap_bands_consecutive(c2)
    end

    @testset "property: 20 random insets" begin
        # reference compose to get body_top / line_advance (independent of inset).
        ref = compose_cover(_make_cfg_raw(; inset_x=300, inset_y=400, inset_w=150, inset_h=150,
                                            pq_x=30, pq_y=400, pq_w=150))
        body_top = ref.body_top
        la = ref.body.metrics.line_advance
        D = 3
        W, H = 612.0, 792.0; margin = 54.0
        content_w = W - 2margin
        # excl-margin floor so inset/pull-quote never occupy bands 1..D (top D bands stay full-width).
        clear_excl = D * la + (body_top - margin) + 2.0
        bottom_room = 130.0

        rng = Xoshiro(20260528)
        ntrials = 20
        passed = 0
        for t in 1:ntrials
            iw = rand(rng, 130.0:0.5:260.0)
            ih = rand(rng, 130.0:0.5:300.0)
            ix = rand(rng, 0.0:0.5:(content_w - iw - 5))
            iy = rand(rng, clear_excl:0.5:(H - 2margin - ih - bottom_room))
            local pqx, pqy, pqw
            for _ in 1:400
                pqw = rand(rng, 120.0:0.5:170.0)
                pqx = rand(rng, 0.0:0.5:(content_w - pqw))
                pqy = rand(rng, clear_excl:0.5:(H - 2margin - bottom_room))
                no_x = (pqx + pqw < ix) || (ix + iw < pqx)
                no_y = (pqy + 90.0 < iy) || (iy + ih < pqy)
                (no_x || no_y) && break
            end
            # fix #2: trial 1 uses gutter=0 with a mid-band inset top so the vertical
            # _overlap(eps) check is exercised at its tightest (no gutter cushion).
            gutter = t == 1 ? 0.0 : 6.0
            cfg = _make_cfg_raw(; inset_x=ix, inset_y=iy, inset_w=iw, inset_h=ih,
                                  pq_x=pqx, pq_y=pqy, pq_w=pqw, gutter=gutter)
            c = compose_cover(cfg)
            ok = dropcap_bands_consecutive(c) &&
                 dropcap_baseline_aligned(c; tol=0.5) &&
                 isempty(bbox_violations(c)) &&
                 body_wrap_honors_inset(c)
            ok || @warn "trial $t failed" ix iy iw ih pqx pqy pqw gutter violations=bbox_violations(c) cons=dropcap_bands_consecutive(c) aligned=dropcap_baseline_aligned(c)
            passed += ok
        end
        @test passed == ntrials
    end

    @testset "PDF golden + embedding + vector" begin
        pdf = _render_fixture("cover-v1.toml")
        @test isfile(pdf) && filesize(pdf) > 0

        if _have("pdftotext")
            raw = read(`pdftotext $pdf -`, String)
            got = _norm_text(raw)
            golden_txt = joinpath(@__DIR__, "golden", "cover-v1.pdftext.txt")
            golden_sha = joinpath(@__DIR__, "golden", "cover-v1.pdftext.sha256")
            @test isfile(golden_txt)
            @test got == _norm_text(read(golden_txt, String))
            @test bytes2hex(sha256(got)) == strip(read(golden_sha, String))
            @test occursin("Newer Yorker", got)        # selectable text present
        else
            @test_skip "pdftotext not available"
        end

        if _have("pdffonts")
            fonts = read(`pdffonts $pdf`, String)
            @test occursin("Liberation", fonts)
            @test _all_fonts_embedded(fonts)            # NO font row with emb=no
        else
            @test_skip "pdffonts not available"
        end

        if _have("pdfimages")
            listing = read(`pdfimages -list $pdf`, String)
            datarows = count(l -> occursin(r"^\s*\d", l), split(listing, "\n"))
            @test datarows == 0                         # vector inset, zero raster images
        else
            @test_skip "pdfimages not available"
        end
    end

end
