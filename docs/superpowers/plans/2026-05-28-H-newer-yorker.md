# #H — CairoMakie "Newer Yorker" correctness exhibit (`examples/cover/`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `examples/cover/` — a develop-able `Cover` package that renders a hand-set editorial cover (display title, drop cap, body text flowing around an SVG illustration inset, pull-quote callouts) to a vector PDF via CairoMakie, where **every offset is measurement-derived** (move the inset 3px → everything re-aligns, no manual layout code change).

**Architecture:** Two-layer split mirroring TextMeasure's own measure/layout philosophy. `compose_cover(config) -> ComposedCover` is **pure arithmetic** over `TextMeasure`/`TextMeasureLayouts` measurements — it produces every text run's absolute baseline, the body `PackedLayout` (wrapped around an inset-exclusion `chord_fn` built here), the drop-cap placement, and pull-quote bounding boxes. `render_cover(composed)` is the **only** layer that touches CairoMakie, replaying the composed placements with `text!`/`poly!`/`lines!` onto a pixel-coordinate `Scene`. All correctness invariants (drop-cap baseline alignment, bbox non-overlap, body-wrap-honors-inset) are asserted on the `ComposedCover` **before** rendering, per the issue's "verify at layout time, not PDF-extraction time" mandate. The SVG inset is parsed by a minimal in-repo parser into primitive rings and drawn as native Makie vector content (`poly!`/`lines!`) — never rasterized.

**Tech Stack:** CairoMakie 0.15.10 (Makie 0.24.10), TextMeasure (develop `../..`), TextMeasureLayouts (develop `../layouts`), GeometryBasics 0.5 (`Point2f`), stdlib `TOML`/`Random`/`SHA`/`Test`. Pinned fonts: **DejaVu Sans** + **Liberation Serif** (system TTFs, resolved by family name via `Makie.to_font`). External tools for tests only: `pdftotext`, `pdffonts`, `pdfimages` (poppler-utils).

---

## Verified API facts (probed against the instantiated env — these GROUND the plan)

All confirmed by running the installed versions in `examples/cover`:

1. **Versions:** `CairoMakie v0.15.10`, `Makie v0.24.10`. `[compat] CairoMakie = "0.15"`.
2. **Font pinning resolves by family name, deterministically, to the system TTFs:** `Makie.to_font("DejaVu Sans") -> DejaVu Sans / Book`, `to_font("Liberation Serif") -> Liberation Serif / Regular`, `to_font("Liberation Serif Bold") -> Liberation Serif / Bold`. The same string passed to **both** `MakieBackend(; font=...)` (which calls `Makie.to_font`) and `text!(...; font=...)` resolves to the identical `FTFont`, so **measured widths match rendered widths exactly** (TextMeasure's whole premise; `measure` sums `hadvance` with no kerning). Fonts are therefore **code constants, not TOML-overridable** — golden reproducibility depends on it.
3. **`MakieBackend` (from `TextMeasureMakieExt`, auto-loaded with CairoMakie) works:** `MakieBackend(; font="DejaVu Sans", fontsize=16, px_per_unit=1.0)`; `TextMeasure.measure(b, s)::Float64`; `TextMeasure.font_metrics(b)::FontMetrics` (e.g. DejaVu Sans @16: asc=14.85, desc=3.77, la=18.63). Ascent/line_advance scale linearly with `fontsize` (used to derive the drop-cap size).
4. **`shape_pack(prep, chord_fn; line_advance, ...)` returns `PackedLayout`** with `placements::Vector{Placement}` (`Placement(segment_index, x, y)`, `y` = baseline in the chord_fn's block-top frame, `x` = left edge), `overflowed::Vector{Int}`, `metrics`. `chord_fn(y_top, y_bottom)` returns **available** (not obstacle) intervals — `Vector{Tuple{Float64,Float64}}`, sorted ascending, pairwise disjoint; empty ⇒ band skipped. First placement of a full-width region sits at `(0.0, ascent)`. (Confirmed live.)
5. **Pixel-coordinate page canvas:** `sc = Makie.Scene(size=(W,H), backgroundcolor=:white); Makie.campixel!(sc)` gives 1 unit = 1 px, origin **bottom-left, y-up**. We work internally in a **block-top frame (y=0 at page top, increasing down)** and flip at render time: `makie_y = H - y`. `Makie.save(path, sc; pt_per_unit=1.0)` writes a PDF where 1 px → 1 pt (so `W,H` are page points: letter = 612×792).
6. **`text!(sc, Point2f(x, makie_y); text=..., font=<string>, fontsize=..., align=(:left, :baseline), color=...)` honors `(:left, :baseline)`** — left edge at `x`, baseline at `makie_y`. Confirmed.
7. **`poly!(sc, Vector{Point2f}; color, strokecolor, strokewidth)` and `lines!(sc, Vector{Point2f}; color, linewidth)`** draw native vector content. Confirmed in PDF.
8. **PDF is correct vector output:** `pdftotext` extracts the placed strings (text is selectable); `pdffonts` shows fonts **embedded** (`emb=yes`), subsetted with a **randomized 6-char subset prefix** (e.g. `QCQIMX+LiberationSerif`). ⇒ **The golden hashes `pdftotext` OUTPUT (text content), never PDF bytes** — byte hashing would be non-reproducible because of the random subset tag. `pdfimages -list` is expected to list **0 images** (proves the SVG inset is vector, not a bitmap).

**Coordinate conventions (locked):**
- **Block-top frame** everywhere in `compose`: `x` rightward from page-left, `y` downward from page-top, units = points.
- **Schema `inset.x_px`/`y_px` are "excl. margin"** (page coords inside the margin): `inset_left = margin + x_px`, `inset_top = margin + y_px`. Same for `pull_quote.x_px`/`y_px`.
- **`shape_pack` runs in a body-LOCAL frame** (`y=0` at `body_top`, the first body line's top). Absolute baseline = `body_top + placement.y`. The chord_fn's holes are expressed in this body-local frame (subtract `body_top` from each hole's `y`); `x` stays absolute (content_left = `margin`).

**Testing posture (per orchestration spec):** assert on the **computed `ComposedCover`**, never on PDF coordinates. Property test over **20 random insets**. Goldens use **floors/ceilings and text-content hashing**, not PDF byte hashes or hard glyph counts. Pinned fonts at golden-gen time == CI-replay time (#J enforces the same DejaVu Sans + Liberation Serif set).

---

## File structure

All under `examples/cover/` (the `Cover` package). Every `.jl`/`.md` gets the MIT SPDX header (`# SPDX-License-Identifier: MIT`) — #J's license gate checks every `examples/` file. `Manifest.toml` is generated by `instantiate` and **gitignored — never committed** (wave-1 operator call; root `.gitignore` matches `Manifest*.toml`).

- `Project.toml` — **already scaffolded** (name `Cover`, deps CairoMakie/GeometryBasics/Random/TOML/TextMeasure/TextMeasureLayouts, `[extras] Test` + `[targets] test`, `[compat]`). Finalized in Task 1.
- `src/Cover.jl` — module: `using`/`import`, exports, `include`s, page-size table + core types (`BBox`, `PlacedText`, `CoverConfig` & sub-structs, `ComposedCover`).
- `src/config.jl` — `load_config(path)::CoverConfig`: TOML → typed config; defaults; validation.
- `src/chord.jl` — `RectExclusionChordFn <: AbstractChordFn` (my own minimal inset-exclusion chord_fn; **does NOT import #G's `complement_chord_fn`**) + `_subtract_interval` interval arithmetic.
- `src/svg.jl` — minimal SVG parser (`parse_svg(path)::SvgDoc`) for `rect/circle/ellipse/line/polyline/polygon/path`(straight-line cmds) + `svg_rings(doc, rect)::Vector{SvgRing}` (viewBox→inset-rect fit).
- `src/compose.jl` — `compose_cover(cfg)::ComposedCover` (pure) + invariant predicates `dropcap_baseline_aligned`, `bbox_violations`, `body_wrap_honors_inset`.
- `src/render.jl` — `render_scene(composed)::Scene` + `render_cover(cfg_path; out)` (compose → render → save PDF). CairoMakie-only.
- `render.jl` (top-level script) — CLI: `julia --project=examples/cover render.jl data/cover-v1.toml [out.pdf]`, also emits a PNG for the human-visual gate.
- `data/cover-v{1,2,3}.toml` — three acceptance fixtures (same `meta`/`body`, **inset block varies**). Committed (content fixtures, not manifests).
- `data/skyline.svg` — hand-authored vector illustration (polygons/rects/lines/circles only). Committed (data asset).
- `test/runtests.jl` — full `@testset`: config, chord arithmetic, SVG parse, compose invariants, **20-inset property test**, golden PDF-text hash, selectability/embedding, no-bitmap.
- `test/golden/cover-v1.pdftext.sha256` + `test/golden/cover-v1.pdftext.txt` — committed golden (text hash + human-readable text).
- `README.md` — what it is + how to run + the "no manual offsets" thesis.

---

### Task 1: Scaffold — module skeleton, types, page table, loadable + empty-green suite

**Files:**
- Modify: `examples/cover/Project.toml`
- Create: `examples/cover/src/Cover.jl`
- Create: `examples/cover/test/runtests.jl`

- [ ] **Step 1: Confirm `Project.toml` final form**

It is already written. Verify it matches (deps + test target + compat):
```toml
name = "Cover"
uuid = "7518d51c-c124-47f8-8f6c-6ff642720d65"
authors = ["Jonathan Chen <jwhc@ucla.edu>"]
version = "0.1.0"

[deps]
CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
GeometryBasics = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
TOML = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
TextMeasure = "06791c1d-2336-41e1-bd6f-a74c63395da6"
TextMeasureLayouts = "57b0e3ea-cc01-4cc3-9e7e-6e97d1609b9f"

[compat]
CairoMakie = "0.15"
GeometryBasics = "0.5"
Random = "1.11"
julia = "1.11"

[extras]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Test"]
```
(`SHA`, `TOML`, `Random` are stdlibs — `SHA` does not need a `[deps]` entry when used only in `test/`; it is added to `[deps]`-free test usage via `using SHA` since it ships with Julia. If `using SHA` fails to resolve in the test env, add `SHA = "ea8e919c-243c-51af-8825-aaa63cd721ce"` to `[extras]` and `"SHA"` to the test target.)

- [ ] **Step 2: Write the module skeleton with core types + stubs**

Create `examples/cover/src/Cover.jl`:
```julia
# SPDX-License-Identifier: MIT
"""
    Cover

"Newer Yorker" editorial-cover demo for TextMeasure.jl (#H). Renders a hand-set
cover — display title, drop cap, body text flowing around an SVG illustration
inset, pull-quote callouts — to a vector PDF via CairoMakie. Every offset is
measurement-derived: `compose_cover` (pure) computes all placements; `render_*`
only replays them. Correctness is asserted on the `ComposedCover`, not the PDF.
"""
module Cover

using TextMeasure: prepare, layout, line_top, MakieBackend, FontMetrics,
                   Prepared, Layout, Line
using TextMeasure                       # for TextMeasure.measure / font_metrics
import TextMeasureLayouts as TML
using TextMeasureLayouts: AbstractChordFn, chord_intervals, shape_pack,
                          PackedLayout, Placement
import TOML

export load_config, compose_cover, ComposedCover, BBox, PlacedText
export RectExclusionChordFn
export dropcap_baseline_aligned, bbox_violations, body_wrap_honors_inset
export parse_svg, svg_rings

# ---- page geometry -------------------------------------------------------
# Page sizes in PostScript points (72 dpi); 1 Scene px -> 1 pt at pt_per_unit=1.
const PAGE_SIZES = Dict{String,Tuple{Float64,Float64}}(
    "letter"  => (612.0, 792.0),
    "a4"      => (595.0, 842.0),
    "tabloid" => (792.0, 1224.0),
)

# Pinned font set (DejaVu Sans + Liberation Serif). NOT TOML-overridable.
const TITLE_FONT    = "Liberation Serif Bold"
const SUBTITLE_FONT = "Liberation Serif"
const BYLINE_FONT   = "DejaVu Sans"
const BODY_FONT     = "Liberation Serif"
const DROPCAP_FONT  = "Liberation Serif Bold"
const PQ_FONT       = "DejaVu Sans"
const PQ_ATTR_FONT  = "DejaVu Sans"

# ---- geometry types ------------------------------------------------------
"""Axis-aligned bbox in the block-top frame (y down). `left<right`, `top<bottom`."""
struct BBox
    left   :: Float64
    top    :: Float64
    right  :: Float64
    bottom :: Float64
end

"""A positioned text run in ABSOLUTE page coords (block-top). `baseline` is the
text baseline y; `x` is the left edge. `font`/`fontsize` are the render+measure font."""
struct PlacedText
    text     :: String
    x        :: Float64
    baseline :: Float64
    fontsize :: Float64
    font     :: String
end

# ---- config types (filled by config.jl) ----------------------------------
struct InsetSpec
    svg_path  :: String
    x_px      :: Float64
    y_px      :: Float64
    width_px  :: Float64
    height_px :: Float64
end

struct BodyPara
    paragraph :: String
    dropcap   :: Bool
end

struct PullQuoteSpec
    text        :: String
    attribution :: String      # "" when absent
    x_px        :: Float64
    y_px        :: Float64
    width_px    :: Float64
end

struct CoverConfig
    title         :: String
    subtitle      :: String     # "" when absent
    byline        :: String     # "" when absent
    page_size     :: String
    margin_px     :: Float64
    dropcap_lines :: Int
    gutter_px     :: Float64
    inset         :: InsetSpec
    body          :: Vector{BodyPara}
    pull_quotes   :: Vector{PullQuoteSpec}
    config_dir    :: String     # dir of the toml, to resolve svg_path
end

# ---- composed result (filled by compose.jl) ------------------------------
struct PullQuotePlaced
    runs :: Vector{PlacedText}
    bbox :: BBox
end

struct ComposedCover
    page_size        :: Tuple{Float64,Float64}
    masthead         :: Vector{PlacedText}
    body             :: PackedLayout
    body_top         :: Float64
    body_runs        :: Vector{PlacedText}
    body_word_bboxes :: Vector{BBox}
    dropcap          :: Union{Nothing,PlacedText}
    dropcap_baseline :: Float64        # NaN when no dropcap
    dropcap_lines    :: Int
    inset_rect       :: BBox
    inset_rings      :: Vector          # Vector{SvgRing} from svg.jl
    pull_quotes      :: Vector{PullQuotePlaced}
end

include("config.jl")
include("chord.jl")
include("svg.jl")
include("compose.jl")
include("render.jl")

end # module
```

- [ ] **Step 3: Write placeholder includes so the module loads**

Create the five include targets as minimal stubs (each replaced in its task). Create `examples/cover/src/config.jl`:
```julia
# SPDX-License-Identifier: MIT
load_config(path::AbstractString)::CoverConfig = error("not implemented")
```
Create `examples/cover/src/chord.jl`:
```julia
# SPDX-License-Identifier: MIT
struct RectExclusionChordFn <: AbstractChordFn end
```
Create `examples/cover/src/svg.jl`:
```julia
# SPDX-License-Identifier: MIT
struct SvgRing end
parse_svg(path::AbstractString) = error("not implemented")
svg_rings(doc, rect::BBox) = error("not implemented")
```
Create `examples/cover/src/compose.jl`:
```julia
# SPDX-License-Identifier: MIT
compose_cover(cfg::CoverConfig)::ComposedCover = error("not implemented")
dropcap_baseline_aligned(c::ComposedCover; tol=0.5) = error("not implemented")
bbox_violations(c::ComposedCover) = error("not implemented")
body_wrap_honors_inset(c::ComposedCover) = error("not implemented")
```
Create `examples/cover/src/render.jl`:
```julia
# SPDX-License-Identifier: MIT
# CairoMakie render layer — implemented in Task 7.
```

- [ ] **Step 4: Write the empty test harness**

Create `examples/cover/test/runtests.jl`:
```julia
# SPDX-License-Identifier: MIT
using Test
using Cover

@testset "Cover.jl" begin
end
```

- [ ] **Step 5: Verify it loads and the empty suite is green**

Run:
```bash
julia --project=examples/cover -e 'using Pkg; Pkg.test()'
```
Expected: precompiles cleanly, `Test Summary: Cover.jl | No tests`, exit 0.

- [ ] **Step 6: Commit**
```bash
git add examples/cover/Project.toml examples/cover/src examples/cover/test/runtests.jl
git commit -m "chore(cover): scaffold Cover package skeleton + core types (#H)"
```

---

### Task 2: `load_config` — TOML → `CoverConfig`

**Files:**
- Modify: `examples/cover/src/config.jl`
- Test: `examples/cover/test/runtests.jl`

- [ ] **Step 1: Write the failing tests**

Insert inside the top-level `@testset` in `runtests.jl` (add `using TOML` to the test preamble is unnecessary — write a temp file with `write`):
```julia
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

        # defaults: subtitle/byline absent, no pull_quotes, dropcap_lines default
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

        # validation: unknown page size throws
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
```

- [ ] **Step 2: Run to verify failure**

Run: `julia --project=examples/cover -e 'using Pkg; Pkg.test()'`
Expected: FAIL — `load_config` errors "not implemented".

- [ ] **Step 3: Implement**

Replace `examples/cover/src/config.jl`:
```julia
# SPDX-License-Identifier: MIT
#
# load_config — parse cover.toml into a typed CoverConfig. Fonts are NOT read from
# the TOML (pinned in Cover.jl for golden reproducibility); only meta/layout/inset/
# body/pull_quote geometry + text come from the file.

_f(x) = Float64(x)

"""
    load_config(path) -> CoverConfig

Parse a `cover.toml` (schema in the issue body) into a [`CoverConfig`](@ref).
`page_size` must be one of `keys(PAGE_SIZES)`. `config_dir` is `dirname(path)`,
used to resolve `inset.svg_path` relative to the TOML file.
"""
function load_config(path::AbstractString)::CoverConfig
    raw = TOML.parsefile(path)
    meta   = get(raw, "meta", Dict{String,Any}())
    layout = get(raw, "layout", Dict{String,Any}())
    inset  = get(raw, "inset", Dict{String,Any}())
    bodies = get(raw, "body", Any[])
    pqs    = get(raw, "pull_quote", Any[])

    page_size = String(get(layout, "page_size", "letter"))
    haskey(PAGE_SIZES, page_size) ||
        throw(ArgumentError("unknown page_size $(repr(page_size)); valid: $(sort(collect(keys(PAGE_SIZES))))"))

    isempty(bodies) && throw(ArgumentError("cover.toml needs at least one [[body]] paragraph"))

    inset_spec = InsetSpec(
        String(inset["svg_path"]),
        _f(inset["x_px"]), _f(inset["y_px"]),
        _f(inset["width_px"]), _f(inset["height_px"]),
    )

    body = BodyPara[BodyPara(String(b["paragraph"]), Bool(get(b, "dropcap", false))) for b in bodies]

    pull_quotes = PullQuoteSpec[
        PullQuoteSpec(String(p["text"]), String(get(p, "attribution", "")),
                      _f(p["x_px"]), _f(p["y_px"]), _f(p["width_px"]))
        for p in pqs
    ]

    return CoverConfig(
        String(get(meta, "title", "")),
        String(get(meta, "subtitle", "")),
        String(get(meta, "byline", "")),
        page_size,
        _f(get(layout, "margin_px", 36)),
        Int(get(layout, "dropcap_lines", 3)),
        _f(get(layout, "gutter_px", 6)),
        inset_spec,
        body,
        pull_quotes,
        dirname(abspath(path)),
    )
end
```
Note: the test's `cfg.config_dir == dir` works because `dirname(abspath(joinpath(dir,"cover.toml"))) == dir` (no trailing slash from `mktempdir`).

- [ ] **Step 4: Run to verify pass**

Run: `julia --project=examples/cover -e 'using Pkg; Pkg.test()'`
Expected: PASS for `load_config`.

- [ ] **Step 5: Commit**
```bash
git add examples/cover/src/config.jl examples/cover/test/runtests.jl
git commit -m "feat(cover): load_config TOML parser (#H)"
```

---

### Task 3: `RectExclusionChordFn` — my own inset-exclusion chord_fn

**Files:**
- Modify: `examples/cover/src/chord.jl`
- Test: `examples/cover/test/runtests.jl`

> Per the runbook: this is a **self-contained** inset-exclusion chord_fn. It does NOT import #G's `complement_chord_fn` and adds nothing to `TextMeasureLayouts` (that dir is #C/#K's; a shared negative-space utility would collide with #K and must instead be flagged to the orchestrator).

- [ ] **Step 1: Write the failing tests**

Insert inside the top-level `@testset` (add `using TextMeasureLayouts: chord_intervals` to the test preamble at top of file):
```julia
    @testset "RectExclusionChordFn" begin
        # content x in [50, 550]; body region 0..400 (body-local y); gutter 0 for exact math.
        # One hole: inset at x[200,300], y[100,200].
        f = RectExclusionChordFn(50.0, 550.0, 400.0,
                                 [BBox(200.0, 100.0, 300.0, 200.0)], 0.0)

        # band above the hole -> full content interval
        @test chord_intervals(f, 0.0, 20.0) == [(50.0, 550.0)]
        # band straddling the hole -> two intervals (left + right of inset)
        @test chord_intervals(f, 120.0, 140.0) == [(50.0, 200.0), (300.0, 550.0)]
        # band below the hole -> full again
        @test chord_intervals(f, 250.0, 270.0) == [(50.0, 550.0)]
        # band beyond region_bottom -> empty (no space)
        @test chord_intervals(f, 400.0, 420.0) == Tuple{Float64,Float64}[]
        # callable form (AbstractChordFn) matches chord_intervals
        @test f(120.0, 140.0) == chord_intervals(f, 120.0, 140.0)

        # gutter expands the hole footprint
        g = RectExclusionChordFn(50.0, 550.0, 400.0,
                                 [BBox(200.0, 100.0, 300.0, 200.0)], 10.0)
        @test g(120.0, 140.0) == [(50.0, 190.0), (310.0, 550.0)]
        # gutter also widens the vertical reach (band at y=92..96 now overlaps top-10)
        @test g(92.0, 96.0) == [(50.0, 190.0), (310.0, 550.0)]

        # hole flush to the left edge -> single right interval
        h = RectExclusionChordFn(50.0, 550.0, 400.0,
                                 [BBox(0.0, 0.0, 120.0, 50.0)], 0.0)
        @test h(10.0, 30.0) == [(120.0, 550.0)]

        # two holes in one band -> three intervals
        k = RectExclusionChordFn(0.0, 600.0, 400.0,
                                 [BBox(100.0, 0.0, 200.0, 100.0),
                                  BBox(400.0, 0.0, 500.0, 100.0)], 0.0)
        @test k(10.0, 30.0) == [(0.0, 100.0), (200.0, 400.0), (500.0, 600.0)]

        # a hole that swallows the whole width -> empty band
        z = RectExclusionChordFn(50.0, 550.0, 400.0,
                                 [BBox(0.0, 0.0, 600.0, 100.0)], 0.0)
        @test z(10.0, 30.0) == Tuple{Float64,Float64}[]
    end
```

- [ ] **Step 2: Run to verify failure**

Run: `julia --project=examples/cover -e 'using Pkg; Pkg.test()'`
Expected: FAIL — `RectExclusionChordFn` has no usable constructor / `chord_intervals` undefined for it.

- [ ] **Step 3: Implement**

Replace `examples/cover/src/chord.jl`:
```julia
# SPDX-License-Identifier: MIT
#
# RectExclusionChordFn — a self-contained inset-exclusion chord function for #H.
# Returns the page content interval MINUS the x-footprints of a set of rectangular
# "holes" (the SVG inset, the drop-cap box, and each pull-quote box) for every band
# they vertically intersect. This is the negative-space chord_fn that makes body text
# flow around the inset with NO manual offsets. Holes are in the body-LOCAL frame
# (y=0 == body_top); content x is absolute page x.
#
# NOTE: deliberately NOT shared via TextMeasureLayouts (that module is #C/#K's; a shared
# negative-space helper would collide with #K). #G builds its own complement separately.

# Available sub-intervals of `full` after removing `holes` (each clamped to full).
# Returns sorted, pairwise-disjoint intervals (the shape_pack chord_fn contract).
function _subtract_interval(full::Tuple{Float64,Float64},
                            holes::Vector{Tuple{Float64,Float64}})
    fl, fr = full
    fr <= fl && return Tuple{Float64,Float64}[]
    hs = Tuple{Float64,Float64}[]
    for (hl, hr) in holes
        l = max(hl, fl); r = min(hr, fr)
        r > l && push!(hs, (l, r))
    end
    isempty(hs) && return [full]
    sort!(hs; by = first)
    # merge overlapping/abutting holes
    merged = Tuple{Float64,Float64}[]
    cl, cr = hs[1]
    for k in 2:length(hs)
        l, r = hs[k]
        if l <= cr
            cr = max(cr, r)
        else
            push!(merged, (cl, cr)); cl, cr = l, r
        end
    end
    push!(merged, (cl, cr))
    # emit the gaps between merged holes within [fl, fr]
    out = Tuple{Float64,Float64}[]
    cursor = fl
    for (hl, hr) in merged
        hl > cursor && push!(out, (cursor, hl))
        cursor = max(cursor, hr)
    end
    cursor < fr && push!(out, (cursor, fr))
    return out
end

"""
    RectExclusionChordFn(content_left, content_right, region_bottom, holes, gutter)

`AbstractChordFn` returning, for each band, the content interval
`[content_left, content_right]` minus the x-footprint of every `hole::BBox` whose
vertical extent (expanded by `gutter` on all sides) intersects the band. Bands at or
below `region_bottom` (body-local y) return `[]` (text stops at the content bottom).
Holes are in the body-local frame; content x is absolute page x. The returned
intervals are sorted ascending and pairwise disjoint.
"""
struct RectExclusionChordFn <: AbstractChordFn
    content_left  :: Float64
    content_right :: Float64
    region_bottom :: Float64
    holes         :: Vector{BBox}
    gutter        :: Float64
end

function chord_intervals(f::RectExclusionChordFn, y_top::Real, y_bottom::Real)
    yt = Float64(y_top); yb = Float64(y_bottom)
    yt >= f.region_bottom && return Tuple{Float64,Float64}[]
    g = f.gutter
    holes = Tuple{Float64,Float64}[]
    for h in f.holes
        if yb > h.top - g && yt < h.bottom + g          # band overlaps the (gutter-expanded) hole
            push!(holes, (h.left - g, h.right + g))
        end
    end
    return _subtract_interval((f.content_left, f.content_right), holes)
end
```

- [ ] **Step 4: Run to verify pass**

Run: `julia --project=examples/cover -e 'using Pkg; Pkg.test()'`
Expected: PASS for `RectExclusionChordFn`.

- [ ] **Step 5: Commit**
```bash
git add examples/cover/src/chord.jl examples/cover/test/runtests.jl
git commit -m "feat(cover): RectExclusionChordFn inset-exclusion chord_fn (#H)"
```

---

### Task 4: Minimal SVG parser → primitive rings

**Files:**
- Modify: `examples/cover/src/svg.jl`
- Test: `examples/cover/test/runtests.jl`

> Scope: a deliberately minimal parser for **straight-line** vector primitives — enough to render a hand-authored editorial illustration as native Makie vector content. Supported elements: `rect`, `circle`, `ellipse`, `line`, `polyline`, `polygon`, `path` (commands `M/L/H/V/Z` and lowercase relatives only — **no béziers/arcs**). Supported style attrs: `fill`, `stroke`, `stroke-width`, `fill-opacity` (named colors from a small table + `#rgb`/`#rrggbb`). `viewBox` sets the source coordinate space; rings are fit into the inset rect with uniform "meet" scaling, centered. Limitations are documented in the docstring and README.

- [ ] **Step 1: Write the failing tests**

Insert inside the top-level `@testset`:
```julia
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

        # fit into an inset rect: viewBox 100x100 -> rect 200x200 at (300,150)
        rect = BBox(300.0, 150.0, 500.0, 350.0)        # square rect, uniform fit, scale=2
        rings = svg_rings(doc, rect)
        @test length(rings) == 4
        # rect prim: closed ring of 4 pts, filled, scaled x2 + offset
        r1 = rings[1]
        @test r1.closed == true
        @test r1.fill !== nothing            # has a fill color
        @test length(r1.points) == 4
        # top-left of the rect (10,20) -> (300 + 10*2, 150 + 20*2) = (320, 190)
        @test r1.points[1][1] ≈ 320.0 atol=1e-6
        @test r1.points[1][2] ≈ 190.0 atol=1e-6
        # circle prim: sampled into a closed polygon (>= 12 pts), stroked-only (no fill)
        rc = rings[4]
        @test rc.closed == true
        @test length(rc.points) >= 12
        @test rc.fill === nothing            # fill="none"
        @test rc.stroke !== nothing
        # line prim: open ring of 2 pts, no fill
        @test rings[3].closed == false
        @test length(rings[3].points) == 2

        # non-square rect -> uniform "meet" fit (scale = min), centered
        wide = BBox(0.0, 0.0, 400.0, 200.0)            # 400x200, viewBox 100x100 -> scale=2, centered x
        rings2 = svg_rings(doc, wide)
        # uniform scale 2 -> drawn content is 200 wide, centered in 400 -> x offset 100
        @test rings2[1].points[1][1] ≈ 100.0 + 10*2 atol=1e-6
    end
```

- [ ] **Step 2: Run to verify failure**

Run: `julia --project=examples/cover -e 'using Pkg; Pkg.test()'`
Expected: FAIL — `parse_svg` errors "not implemented".

- [ ] **Step 3: Implement**

Replace `examples/cover/src/svg.jl`:
```julia
# SPDX-License-Identifier: MIT
#
# Minimal SVG parser for the editorial-inset illustration. STRAIGHT-LINE primitives
# only (rect/circle/ellipse/line/polyline/polygon/path with M/L/H/V/Z) so every shape
# becomes a Makie poly!/lines! ring — guaranteed native vector content, never a bitmap.
# Curves/arcs/transforms/CSS are intentionally unsupported (documented limitation).

using GeometryBasics: Point2f

const _NAMED_COLORS = Dict{String,NTuple{3,Float64}}(
    "black"=>(0,0,0), "white"=>(1,1,1), "red"=>(1,0,0), "green"=>(0,0.5,0),
    "blue"=>(0,0,1), "gray"=>(0.5,0.5,0.5), "grey"=>(0.5,0.5,0.5),
    "orange"=>(1,0.65,0), "gold"=>(1,0.84,0), "navy"=>(0,0,0.5),
    "steelblue"=>(0.27,0.51,0.71), "firebrick"=>(0.7,0.13,0.13),
)

# A parsed style color as an RGB tuple, or nothing for "none"/absent.
function _parse_color(s::Union{Nothing,AbstractString})
    s === nothing && return nothing
    s = strip(lowercase(String(s)))
    (s == "none" || isempty(s)) && return nothing
    if startswith(s, "#")
        hex = s[2:end]
        if length(hex) == 3
            r = parse(Int, hex[1]*hex[1]; base=16)
            g = parse(Int, hex[2]*hex[2]; base=16)
            b = parse(Int, hex[3]*hex[3]; base=16)
            return (r/255, g/255, b/255)
        elseif length(hex) == 6
            return (parse(Int, hex[1:2]; base=16)/255,
                    parse(Int, hex[3:4]; base=16)/255,
                    parse(Int, hex[5:6]; base=16)/255)
        end
        return nothing
    end
    return get(_NAMED_COLORS, s, nothing)
end

# One source-space primitive: a list of (x,y) in viewBox coords + style + closed flag.
struct SvgPrim
    pts          :: Vector{Tuple{Float64,Float64}}
    closed       :: Bool
    fill         :: Union{Nothing,NTuple{3,Float64}}
    fill_opacity :: Float64
    stroke       :: Union{Nothing,NTuple{3,Float64}}
    stroke_width :: Float64
end

struct SvgDoc
    viewbox :: NTuple{4,Float64}     # (minx, miny, width, height)
    prims   :: Vector{SvgPrim}
end

# A fitted ring in ABSOLUTE page coords (block-top), ready for Makie.
struct SvgRing
    points       :: Vector{Point2f}
    closed       :: Bool
    fill         :: Union{Nothing,NTuple{3,Float64}}
    fill_opacity :: Float64
    stroke       :: Union{Nothing,NTuple{3,Float64}}
    stroke_width :: Float64
end

# ---- tiny attribute scraping (regex over a single element's text) ----------
_attr(el, name) = (m = match(Regex("\\b$(name)\\s*=\\s*\"([^\"]*)\""), el)) === nothing ? nothing : m.captures[1]
_attrf(el, name, default) = (v = _attr(el, name)) === nothing ? default : parse(Float64, v)
_nums(s) = [parse(Float64, t) for t in split(s, r"[\s,]+"; keepempty=false)]

function _circle_ring(cx, cy, rx, ry; nseg=48)
    [(cx + rx*cos(2π*k/nseg), cy + ry*sin(2π*k/nseg)) for k in 0:(nseg-1)]
end

# Parse a path's straight-line subset (M/L/H/V/Z + lowercase). Returns (pts, closed).
function _parse_path(d::AbstractString)
    toks = collect(eachmatch(r"([MLHVZmlhvz])|(-?\d*\.?\d+(?:e-?\d+)?)", d))
    pts = Tuple{Float64,Float64}[]; closed = false
    cx = cy = 0.0; cmd = 'M'; i = 1
    nums = Float64[]
    # rebuild as a simple command stream
    stream = Any[]
    for m in toks
        if m.captures[1] !== nothing
            push!(stream, m.captures[1][1])
        else
            push!(stream, parse(Float64, m.match))
        end
    end
    j = 1
    while j <= length(stream)
        t = stream[j]
        if t isa Char
            cmd = t; j += 1
            cmd in ('Z','z') && (closed = true)
            continue
        end
        # t is a number; consume operands per current cmd
        if cmd in ('M','L')
            x = stream[j]; y = stream[j+1]; j += 2
            cx, cy = x, y; push!(pts, (cx, cy)); cmd == 'M' && (cmd = 'L')
        elseif cmd in ('m','l')
            x = stream[j]; y = stream[j+1]; j += 2
            cx += x; cy += y; push!(pts, (cx, cy)); cmd == 'm' && (cmd = 'l')
        elseif cmd == 'H'; cx = stream[j]; j += 1; push!(pts, (cx, cy))
        elseif cmd == 'h'; cx += stream[j]; j += 1; push!(pts, (cx, cy))
        elseif cmd == 'V'; cy = stream[j]; j += 1; push!(pts, (cx, cy))
        elseif cmd == 'v'; cy += stream[j]; j += 1; push!(pts, (cx, cy))
        else; j += 1   # unsupported command operand: skip defensively
        end
    end
    return pts, closed
end

"""
    parse_svg(path) -> SvgDoc

Parse the supported straight-line subset of an SVG file into source-space
primitives. Unsupported features (béziers, arcs, transforms, CSS, gradients) are
ignored. `viewBox` defaults to `(0,0,100,100)` when absent.
"""
function parse_svg(path::AbstractString)::SvgDoc
    s = read(path, String)
    vbm = match(r"viewBox\s*=\s*\"([^\"]*)\"", s)
    vb = vbm === nothing ? (0.0,0.0,100.0,100.0) : (let n=_nums(vbm.captures[1]); (n[1],n[2],n[3],n[4]); end)
    prims = SvgPrim[]
    for m in eachmatch(r"<(rect|circle|ellipse|line|polyline|polygon|path)\b([^>]*)>", s)
        tag = m.captures[1]; el = m.match
        fill   = _parse_color(_attr(el, "fill"))
        stroke = _parse_color(_attr(el, "stroke"))
        fo     = _attrf(el, "fill-opacity", 1.0)
        sw     = _attrf(el, "stroke-width", 1.0)
        if tag == "rect"
            x = _attrf(el,"x",0); y = _attrf(el,"y",0); w = _attrf(el,"width",0); h = _attrf(el,"height",0)
            pts = [(x,y),(x+w,y),(x+w,y+h),(x,y+h)]; closed = true
        elseif tag == "circle"
            cx=_attrf(el,"cx",0); cy=_attrf(el,"cy",0); r=_attrf(el,"r",0)
            pts = _circle_ring(cx,cy,r,r); closed = true
        elseif tag == "ellipse"
            cx=_attrf(el,"cx",0); cy=_attrf(el,"cy",0); rx=_attrf(el,"rx",0); ry=_attrf(el,"ry",0)
            pts = _circle_ring(cx,cy,rx,ry); closed = true
        elseif tag == "line"
            pts = [(_attrf(el,"x1",0),_attrf(el,"y1",0)),(_attrf(el,"x2",0),_attrf(el,"y2",0))]; closed = false
        elseif tag in ("polyline","polygon")
            v = _nums(something(_attr(el,"points"),""))
            pts = [(v[2k-1], v[2k]) for k in 1:(length(v)÷2)]; closed = (tag == "polygon")
        else # path
            pts, closed = _parse_path(something(_attr(el,"d"),""))
        end
        isempty(pts) && continue
        push!(prims, SvgPrim(pts, closed, fill, fo, stroke, sw))
    end
    return SvgDoc(vb, prims)
end

"""
    svg_rings(doc, rect::BBox) -> Vector{SvgRing}

Fit `doc`'s primitives into `rect` (absolute page coords, block-top) with a uniform
"meet" scale (preserve aspect, center). Source y is in SVG's y-down space, which
matches our block-top frame, so no y-flip is applied here (the render layer flips
once, globally). `stroke_width` is scaled by the same uniform factor.
"""
function svg_rings(doc::SvgDoc, rect::BBox)::Vector{SvgRing}
    _, _, vw, vh = doc.viewbox
    minx, miny = doc.viewbox[1], doc.viewbox[2]
    rw = rect.right - rect.left; rh = rect.bottom - rect.top
    (vw <= 0 || vh <= 0) && (vw = max(vw,1); vh = max(vh,1))
    s = min(rw / vw, rh / vh)                       # uniform meet
    offx = rect.left + (rw - s*vw)/2
    offy = rect.top  + (rh - s*vh)/2
    tf((x,y)) = Point2f(offx + s*(x - minx), offy + s*(y - miny))
    return [SvgRing([tf(p) for p in pr.pts], pr.closed, pr.fill, pr.fill_opacity,
                    pr.stroke, s*pr.stroke_width) for pr in doc.prims]
end
```

- [ ] **Step 4: Run to verify pass**

Run: `julia --project=examples/cover -e 'using Pkg; Pkg.test()'`
Expected: PASS for `SVG parse + fit`.

- [ ] **Step 5: Commit**
```bash
git add examples/cover/src/svg.jl examples/cover/test/runtests.jl
git commit -m "feat(cover): minimal straight-line SVG parser + viewBox fit (#H)"
```

---

### Task 5: `compose_cover` — pure layout + invariant predicates

**Files:**
- Modify: `examples/cover/src/compose.jl`
- Test: `examples/cover/test/runtests.jl`

- [ ] **Step 1: Write the failing tests**

Insert inside the top-level `@testset` (uses the same temp-toml + skyline svg helper). Add a small fixture helper at the TOP of `runtests.jl` (after `using`):
```julia
# build a minimal but realistic config in a temp dir, with a tiny svg
function _make_cfg(; inset_x=240.0, inset_y=170.0, inset_w=200.0, inset_h=240.0,
                     pull_quotes=true)
    dir = mktempdir()
    write(joinpath(dir,"skyline.svg"),
        """<svg viewBox="0 0 100 100"><rect x="0" y="40" width="100" height="60" fill="#445"/>
           <polygon points="10,40 20,15 30,40" fill="#778"/></svg>""")
    pq = pull_quotes ? """
        [[pull_quote]]
        text        = "Measurement, not guesswork."
        attribution = "— TM"
        x_px        = 40
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
```
Then the testset:
```julia
    @testset "compose_cover invariants" begin
        cfg = _make_cfg()
        c = compose_cover(cfg)
        @test c.page_size == (612.0, 792.0)
        @test !isempty(c.body_runs)
        @test length(c.body_runs) == length(c.body_word_bboxes)
        @test c.dropcap !== nothing
        @test c.dropcap.text == "T"                      # first letter, uppercased

        # (a) drop-cap baseline aligns with the D-th body line baseline within 0.5px
        @test dropcap_baseline_aligned(c; tol=0.5)

        # drop cap top should sit near body_top (cap spans D lines) — sanity, generous tol
        dc_top = c.dropcap.baseline - 0  # baseline; cap top derived in render; check baseline below body_top
        @test c.dropcap.baseline > c.body_top
        @test c.dropcap.baseline < c.body_top + cfg.dropcap_lines * c.body.metrics.line_advance + 50

        # (b) no bbox overlaps: body words vs inset, pull-quote vs inset, pull-quote vs body
        @test isempty(bbox_violations(c))

        # (c) body wrap honors the inset boundary at every line
        @test body_wrap_honors_inset(c)

        # inset rect derived from margin + x_px
        @test c.inset_rect.left ≈ 54.0 + 240.0 atol=1e-9
        @test c.inset_rect.top  ≈ 54.0 + 170.0 atol=1e-9

        # masthead present (title + subtitle + byline)
        @test length(c.masthead) == 3
        @test c.masthead[1].text == "The Newer Yorker"
        # title is centered: its x > content_left
        @test c.masthead[1].x > 54.0
    end
```

- [ ] **Step 2: Run to verify failure**

Run: `julia --project=examples/cover -e 'using Pkg; Pkg.test()'`
Expected: FAIL — `compose_cover` errors "not implemented".

- [ ] **Step 3: Implement**

Replace `examples/cover/src/compose.jl`:
```julia
# SPDX-License-Identifier: MIT
#
# compose_cover — the PURE layout core. Computes every text run's absolute baseline,
# the body PackedLayout wrapped around an inset-exclusion chord_fn, the drop-cap
# placement, and pull-quote boxes. NO CairoMakie. All correctness invariants are
# checked against the value it returns, per the issue's "verify at layout time" rule.

# Fixed display metrics (points). Fonts are pinned constants (Cover.jl).
const TITLE_SIZE    = 44.0
const SUBTITLE_SIZE = 18.0
const BYLINE_SIZE   = 12.0
const BODY_SIZE     = 11.0
const PQ_SIZE       = 14.0
const PQ_ATTR_SIZE  = 11.0
const SUBTITLE_GAP  = 6.0
const BYLINE_GAP    = 10.0
const BODY_GAP      = 20.0
const DROPCAP_GAP   = 6.0      # horizontal space after the drop cap

_mk(font, size) = MakieBackend(; font=font, fontsize=size, px_per_unit=1.0)

# AABB overlap with a tiny tolerance (y-down frame).
function _overlap(a::BBox, b::BBox; eps=1e-6)
    (a.left < b.right - eps) && (b.left < a.right - eps) &&
    (a.top  < b.bottom - eps) && (b.top  < a.bottom - eps)
end

"""
    compose_cover(cfg) -> ComposedCover

Pure layout: resolve the page, lay out the masthead, drop cap, body (wrapped around
the inset + drop-cap + pull-quote holes via [`RectExclusionChordFn`](@ref)), and
pull quotes. Coordinates are absolute page points in the block-top frame. Touches no
rendering backend.
"""
function compose_cover(cfg::CoverConfig)::ComposedCover
    W, H = PAGE_SIZES[cfg.page_size]
    m = cfg.margin_px
    content_left  = m
    content_right = W - m
    content_top   = m
    content_bottom = H - m
    content_w = content_right - content_left

    # ---- masthead ----
    masthead = PlacedText[]
    tb = _mk(TITLE_FONT, TITLE_SIZE);     tm = TextMeasure.font_metrics(tb)
    cur = content_top + tm.ascent
    title_w = TextMeasure.measure(tb, cfg.title)
    push!(masthead, PlacedText(cfg.title, content_left + (content_w - title_w)/2, cur, TITLE_SIZE, TITLE_FONT))
    cur += tm.descent
    if !isempty(cfg.subtitle)
        sb = _mk(SUBTITLE_FONT, SUBTITLE_SIZE); sm = TextMeasure.font_metrics(sb)
        cur += SUBTITLE_GAP + sm.ascent
        sw = TextMeasure.measure(sb, cfg.subtitle)
        push!(masthead, PlacedText(cfg.subtitle, content_left + (content_w - sw)/2, cur, SUBTITLE_SIZE, SUBTITLE_FONT))
        cur += sm.descent
    end
    if !isempty(cfg.byline)
        bb = _mk(BYLINE_FONT, BYLINE_SIZE); bm = TextMeasure.font_metrics(bb)
        cur += BYLINE_GAP + bm.ascent
        bw = TextMeasure.measure(bb, cfg.byline)
        push!(masthead, PlacedText(cfg.byline, content_left + (content_w - bw)/2, cur, BYLINE_SIZE, BYLINE_FONT))
        cur += bm.descent
    end
    body_top = cur + BODY_GAP

    # ---- body backend / metrics ----
    body_be = _mk(BODY_FONT, BODY_SIZE)
    bmet = TextMeasure.font_metrics(body_be)
    la = bmet.line_advance

    # ---- drop cap geometry (derived from body metrics) ----
    has_dropcap = !isempty(cfg.body) && cfg.body[1].dropcap && !isempty(cfg.body[1].paragraph)
    D = cfg.dropcap_lines
    dropcap = nothing
    dropcap_baseline = NaN
    dropcap_hole = nothing
    # body text = paragraphs joined by '\n', with the first char removed if dropcapping
    paras = [p.paragraph for p in cfg.body]
    capch = ""
    if has_dropcap
        capch = uppercase(string(first(paras[1])))
        paras[1] = paras[1][nextind(paras[1], 1):end]
        # drop-cap target: baseline == D-th body line baseline; ascent spans to body top
        target_ascent = (D - 1) * la + bmet.ascent
        ref = _mk(DROPCAP_FONT, 100.0)
        ref_asc = TextMeasure.font_metrics(ref).ascent
        dc_size = 100.0 * target_ascent / ref_asc
        dc_be = _mk(DROPCAP_FONT, dc_size)
        cap_w = TextMeasure.measure(dc_be, capch)
        dropcap_baseline = body_top + target_ascent
        dropcap = PlacedText(capch, content_left, dropcap_baseline, dc_size, DROPCAP_FONT)
        # hole in body-local frame: x covers cap + gap, y covers the first D lines
        dropcap_hole = BBox(content_left, 0.0, content_left + cap_w + DROPCAP_GAP, D * la)
    end
    body_text = join(paras, "\n")
    body_prep = prepare(body_be, body_text)

    # ---- inset rect (absolute) + svg rings ----
    inset_left = m + cfg.inset.x_px
    inset_top  = m + cfg.inset.y_px
    inset_rect = BBox(inset_left, inset_top, inset_left + cfg.inset.width_px, inset_top + cfg.inset.height_px)
    svg_full   = joinpath(cfg.config_dir, cfg.inset.svg_path)
    inset_rings = isfile(svg_full) ? svg_rings(parse_svg(svg_full), inset_rect) : SvgRing[]

    # ---- pull-quote layout (each is its own text block + bbox) ----
    pq_be = _mk(PQ_FONT, PQ_SIZE);  pqm = TextMeasure.font_metrics(pq_be)
    pqa_be = _mk(PQ_ATTR_FONT, PQ_ATTR_SIZE); pqam = TextMeasure.font_metrics(pqa_be)
    pull_quotes = PullQuotePlaced[]
    pq_holes = BBox[]
    for pq in cfg.pull_quotes
        pql = pq.x_px + m; pqt = pq.y_px + m
        lay = layout(prepare(pq_be, pq.text); max_width = pq.width_px)
        runs = PlacedText[]
        for ln in lay.lines
            push!(runs, PlacedText(ln.str, pql + ln.x, pqt + ln.baseline, PQ_SIZE, PQ_FONT))
        end
        pq_h = lay.size[2]
        if !isempty(pq.attribution)
            ab = pqt + pq_h + PQ_ATTR_SIZE * 0.4 + pqam.ascent
            aw = TextMeasure.measure(pqa_be, pq.attribution)
            push!(runs, PlacedText(pq.attribution, pql + pq.width_px - aw, ab, PQ_ATTR_SIZE, PQ_ATTR_FONT))
            pq_h = (ab + pqam.descent) - pqt
        end
        bbox = BBox(pql, pqt, pql + pq.width_px, pqt + pq_h)
        push!(pull_quotes, PullQuotePlaced(runs, bbox))
        push!(pq_holes, bbox)
    end

    # ---- assemble holes (body-local frame: subtract body_top from y) ----
    holes = BBox[]
    push!(holes, BBox(inset_rect.left, inset_rect.top - body_top, inset_rect.right, inset_rect.bottom - body_top))
    dropcap_hole !== nothing && push!(holes, dropcap_hole)
    for h in pq_holes
        push!(holes, BBox(h.left, h.top - body_top, h.right, h.bottom - body_top))
    end
    region_bottom = content_bottom - body_top
    chord = RectExclusionChordFn(content_left, content_right, region_bottom, holes, cfg.gutter_px)

    # ---- pack the body ----
    packed = shape_pack(body_prep, chord; line_advance = la, min_chord_width = 24.0)

    # ---- absolute body runs + bboxes ----
    body_runs = PlacedText[]; body_bboxes = BBox[]
    for p in packed.placements
        seg = body_prep.segments[p.segment_index]
        base = body_top + p.y
        push!(body_runs, PlacedText(seg.str, p.x, base, BODY_SIZE, BODY_FONT))
        push!(body_bboxes, BBox(p.x, base - bmet.ascent, p.x + seg.width, base + bmet.descent))
    end

    return ComposedCover((W,H), masthead, packed, body_top, body_runs, body_bboxes,
                         dropcap, dropcap_baseline, D, inset_rect, inset_rings, pull_quotes)
end

"""
    dropcap_baseline_aligned(c; tol=0.5) -> Bool

True when the drop-cap baseline equals the `dropcap_lines`-th distinct body-line
baseline within `tol` px (computed from the `PackedLayout`, not the PDF). When there
is no drop cap, returns `true` vacuously.
"""
function dropcap_baseline_aligned(c::ComposedCover; tol=0.5)
    c.dropcap === nothing && return true
    ys = sort(unique(round.([p.y for p in c.body.placements]; digits=6)))
    length(ys) < c.dropcap_lines && return false
    line_d_abs = c.body_top + ys[c.dropcap_lines]
    return abs(c.dropcap_baseline - line_d_abs) <= tol
end

"""
    bbox_violations(c) -> Vector{Tuple{Symbol,Int,Int}}

Every overlapping pair among: body words vs inset, pull-quote boxes vs inset,
pull-quote boxes vs body words. Empty ⇒ the "no overlap" invariant holds. Tuples are
`(:kind, i, j)` for diagnostics.
"""
function bbox_violations(c::ComposedCover)
    v = Tuple{Symbol,Int,Int}[]
    for (i, b) in enumerate(c.body_word_bboxes)
        _overlap(b, c.inset_rect) && push!(v, (:body_inset, i, 0))
    end
    for (qi, pq) in enumerate(c.pull_quotes)
        _overlap(pq.bbox, c.inset_rect) && push!(v, (:pq_inset, qi, 0))
        for (i, b) in enumerate(c.body_word_bboxes)
            _overlap(pq.bbox, b) && push!(v, (:pq_body, qi, i))
        end
    end
    return v
end

"""
    body_wrap_honors_inset(c) -> Bool

True when no body word bbox intersects the inset rect (the wrap respected the inset
at every line). Equivalent to "no `:body_inset` entry in `bbox_violations`".
"""
body_wrap_honors_inset(c::ComposedCover) =
    !any(b -> _overlap(b, c.inset_rect), c.body_word_bboxes)
```

- [ ] **Step 4: Run to verify pass**

Run: `julia --project=examples/cover -e 'using Pkg; Pkg.test()'`
Expected: PASS for `compose_cover invariants`.

- [ ] **Step 5: Commit**
```bash
git add examples/cover/src/compose.jl examples/cover/test/runtests.jl
git commit -m "feat(cover): compose_cover pure layout + invariant predicates (#H)"
```

---

### Task 6: Property test — 20 random insets

**Files:**
- Test: `examples/cover/test/runtests.jl`

> This is the issue's headline acceptance: 20 randomized inset positions/sizes (plus one randomized, rejection-sampled pull quote), all asserted on the computed `ComposedCover`. The random inset is constrained to lie inside the body region and clear of the drop-cap column so there are always ≥ `dropcap_lines` body lines and the cap column is never swallowed.

- [ ] **Step 1: Write the test (no implementation needed — exercises Task 5)**

Add a config-from-params helper at the top of `runtests.jl` (after `_make_cfg`) that writes random insets + a rejection-sampled pull quote:
```julia
using Random

function _make_cfg_raw(; inset_x, inset_y, inset_w, inset_h, pq_x, pq_y, pq_w)
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
    gutter_px = 6
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
```
Then the property testset:
```julia
    @testset "property: 20 random insets" begin
        rng = Xoshiro(20260528)
        W, H = 612.0, 792.0; margin = 54.0
        content_w = W - 2margin
        # body starts well below the masthead; keep inset+pq inside a safe body band.
        # x_px/y_px are excl-margin (0-based at content origin). Reserve a left
        # drop-cap column (~90px) and a top band for the first D lines (~120px).
        dropcap_clear = 95.0
        body_band_top = 150.0
        body_band_bot = content_w  # placeholder not used for y; use H below
        ntrials = 20
        passed = 0
        for t in 1:ntrials
            iw = rand(rng, 130.0:260.0)
            ih = rand(rng, 130.0:320.0)
            ix = rand(rng, dropcap_clear:(content_w - iw - 5))
            iy = rand(rng, body_band_top:(H - 2margin - ih - 120))   # leave bottom room
            # pull quote: rejection-sample to not intersect the inset rect (excl-margin coords)
            local pqx, pqy, pqw
            for _ in 1:200
                pqw = rand(rng, 120.0:170.0)
                pqx = rand(rng, 0.0:(content_w - pqw))
                pqy = rand(rng, body_band_top:(H - 2margin - 120))
                # crude inset overlap test in excl-margin space (pq height ~70)
                no_x = (pqx + pqw < ix) || (ix + iw < pqx)
                no_y = (pqy + 80 < iy) || (iy + ih < pqy)
                (no_x || no_y) && break
            end
            cfg = _make_cfg_raw(; inset_x=ix, inset_y=iy, inset_w=iw, inset_h=ih,
                                  pq_x=pqx, pq_y=pqy, pq_w=pqw)
            c = compose_cover(cfg)
            ok = dropcap_baseline_aligned(c; tol=0.5) &&
                 isempty(bbox_violations(c)) &&
                 body_wrap_honors_inset(c)
            ok || @warn "trial $t failed" ix iy iw ih pqx pqy pqw violations=bbox_violations(c) dca=dropcap_baseline_aligned(c)
            passed += ok
        end
        @test passed == ntrials
    end
```

- [ ] **Step 2: Run to verify pass**

Run: `julia --project=examples/cover -e 'using Pkg; Pkg.test()'`
Expected: PASS — all 20 trials satisfy the three invariants. If any fail, the `@warn` prints the offending params; debug `compose_cover`/chord arithmetic (do NOT relax the invariant — that's the exhibit's whole point). Likely culprits if it fails: gutter sign, body-local hole y conversion, or the pull-quote attribution height bleaking past its declared box (tighten `pq_h`).

- [ ] **Step 3: Commit**
```bash
git add examples/cover/test/runtests.jl
git commit -m "test(cover): 20-random-inset property test for no-manual-offset invariants (#H)"
```

---

### Task 7: Render layer + CLI + SVG asset + three fixtures

**Files:**
- Modify: `examples/cover/src/render.jl`
- Create: `examples/cover/render.jl` (top-level CLI script)
- Create: `examples/cover/data/skyline.svg`
- Create: `examples/cover/data/cover-v1.toml`, `cover-v2.toml`, `cover-v3.toml`

- [ ] **Step 1: Implement the render layer**

Replace `examples/cover/src/render.jl`:
```julia
# SPDX-License-Identifier: MIT
#
# render.jl — the ONLY CairoMakie-touching layer. Replays a ComposedCover onto a
# pixel-coordinate Scene (1 unit = 1 pt). Internal coords are block-top (y down); we
# flip once here: makie_y = H - y. Text via text!(align=(:left,:baseline)); the SVG
# inset via poly!/lines! (native vector — never a bitmap).

import CairoMakie
const MK = CairoMakie.Makie

_rgb(t::NTuple{3,Float64}) = MK.RGBf(t[1], t[2], t[3])

function _draw_text!(sc, H, t::PlacedText)
    MK.text!(sc, MK.Point2f(t.x, H - t.baseline); text = t.text, font = t.font,
             fontsize = t.fontsize, align = (:left, :baseline), color = :black)
end

"""
    render_scene(c::ComposedCover) -> Scene

Build the CairoMakie `Scene` for a composed cover. Pixel coords, white background.
"""
function render_scene(c::ComposedCover)
    W, H = c.page_size
    sc = MK.Scene(size = (W, H), backgroundcolor = :white)
    MK.campixel!(sc)
    # SVG inset (vector)
    for r in c.inset_rings
        pts = [MK.Point2f(p[1], H - p[2]) for p in r.points]
        if r.fill !== nothing && r.closed
            MK.poly!(sc, pts; color = (_rgb(r.fill), r.fill_opacity),
                     strokecolor = r.stroke === nothing ? :transparent : _rgb(r.stroke),
                     strokewidth = r.stroke === nothing ? 0.0 : r.stroke_width)
        elseif r.stroke !== nothing
            seg = r.closed ? vcat(pts, pts[1:1]) : pts
            MK.lines!(sc, seg; color = _rgb(r.stroke), linewidth = r.stroke_width)
        end
    end
    # masthead + body + drop cap + pull quotes
    for t in c.masthead; _draw_text!(sc, H, t); end
    c.dropcap !== nothing && _draw_text!(sc, H, c.dropcap)
    for t in c.body_runs; _draw_text!(sc, H, t); end
    for pq in c.pull_quotes, t in pq.runs; _draw_text!(sc, H, t); end
    return sc
end

"""
    render_cover(cfg_path; out=nothing, png=false) -> String

Compose + render + save. Writes a PDF (vector) next to `cfg_path` unless `out` is
given; if `png`, also writes a sibling `.png` for the human-visual gate. Returns the
PDF path.
"""
function render_cover(cfg_path::AbstractString; out=nothing, png::Bool=false)
    cfg = load_config(cfg_path)
    c = compose_cover(cfg)
    sc = render_scene(c)
    pdf = out === nothing ? replace(cfg_path, r"\.toml$" => ".pdf") : out
    MK.save(pdf, sc; pt_per_unit = 1.0)
    if png
        MK.save(replace(pdf, r"\.pdf$" => ".png"), sc; px_per_unit = 2.0)
    end
    return pdf
end
```
Add to the `export` line in `Cover.jl`: `render_scene`, `render_cover`. Edit `src/Cover.jl`:
```julia
export load_config, compose_cover, ComposedCover, BBox, PlacedText
export RectExclusionChordFn
export dropcap_baseline_aligned, bbox_violations, body_wrap_honors_inset
export parse_svg, svg_rings
export render_scene, render_cover
```

- [ ] **Step 2: Author the SVG illustration asset**

Create `examples/cover/data/skyline.svg` (straight-line primitives only — a stylized skyline):
```svg
<!-- SPDX-License-Identifier: MIT -->
<svg viewBox="0 0 200 280" xmlns="http://www.w3.org/2000/svg">
  <rect x="0" y="210" width="200" height="70" fill="#2b3a55"/>
  <polygon points="20,210 20,120 55,120 55,210" fill="#3d5a80"/>
  <polygon points="65,210 65,70 100,55 135,70 135,210" fill="#577590"/>
  <rect x="150" y="100" width="35" height="110" fill="#3d5a80"/>
  <polygon points="100,55 118,30 118,55" fill="#ee6c4d"/>
  <circle cx="160" cy="45" r="16" fill="#f2cc8f"/>
  <line x1="0" y1="210" x2="200" y2="210" stroke="#293241" stroke-width="2"/>
  <rect x="30" y="140" width="8" height="10" fill="#e0fbfc"/>
  <rect x="42" y="140" width="8" height="10" fill="#e0fbfc"/>
  <rect x="80" y="95" width="8" height="12" fill="#e0fbfc"/>
  <rect x="112" y="95" width="8" height="12" fill="#e0fbfc"/>
</svg>
```

- [ ] **Step 3: Author the three fixtures (same meta/body; inset varies)**

Create `examples/cover/data/cover-v1.toml`:
```toml
# SPDX-License-Identifier: MIT
[meta]
title    = "The Newer Yorker"
subtitle = "A Correctness Exhibit"
byline   = "by TextMeasure.jl"

[layout]
page_size     = "letter"
margin_px     = 54
dropcap_lines = 3
gutter_px     = 7

[inset]
svg_path  = "skyline.svg"
x_px      = 250
y_px      = 150
width_px  = 200
height_px = 260

[[body]]
dropcap   = true
paragraph = """
There are no manual offsets on this page. Every baseline, every wrap point, and the drop cap that opens this column were computed by the measurement pipeline, not nudged by hand. Move the illustration three pixels and re-render: the body text re-flows around its new footprint, the pull quote keeps its clearance, and the drop cap still lands on its line — because nothing here was hardcoded.
"""

[[body]]
paragraph = """
The exhibit measures once and lays out many times. The same prepared paragraph is packed around an inset-exclusion chord function that subtracts the illustration, the drop cap, and the pull quote from each scanline band. Correctness is asserted on the computed layout before a single glyph is drawn.
"""

[[pull_quote]]
text        = "Measure once. Lay out many times. Never nudge."
attribution = "— the thesis"
x_px        = 30
y_px        = 540
width_px    = 170
```
Create `examples/cover/data/cover-v2.toml` — identical except the `[inset]` block (and you may bump `gutter_px`):
```toml
# SPDX-License-Identifier: MIT
[meta]
title    = "The Newer Yorker"
subtitle = "A Correctness Exhibit"
byline   = "by TextMeasure.jl"

[layout]
page_size     = "letter"
margin_px     = 54
dropcap_lines = 3
gutter_px     = 7

[inset]
svg_path  = "skyline.svg"
x_px      = 40
y_px      = 230
width_px  = 240
height_px = 200

[[body]]
dropcap   = true
paragraph = """
There are no manual offsets on this page. Every baseline, every wrap point, and the drop cap that opens this column were computed by the measurement pipeline, not nudged by hand. Move the illustration three pixels and re-render: the body text re-flows around its new footprint, the pull quote keeps its clearance, and the drop cap still lands on its line — because nothing here was hardcoded.
"""

[[body]]
paragraph = """
The exhibit measures once and lays out many times. The same prepared paragraph is packed around an inset-exclusion chord function that subtracts the illustration, the drop cap, and the pull quote from each scanline band. Correctness is asserted on the computed layout before a single glyph is drawn.
"""

[[pull_quote]]
text        = "Measure once. Lay out many times. Never nudge."
attribution = "— the thesis"
x_px        = 330
y_px        = 150
width_px    = 160
```
Create `examples/cover/data/cover-v3.toml` — inset large + centered-ish:
```toml
# SPDX-License-Identifier: MIT
[meta]
title    = "The Newer Yorker"
subtitle = "A Correctness Exhibit"
byline   = "by TextMeasure.jl"

[layout]
page_size     = "letter"
margin_px     = 54
dropcap_lines = 4
gutter_px     = 8

[inset]
svg_path  = "skyline.svg"
x_px      = 150
y_px      = 320
width_px  = 220
height_px = 230

[[body]]
dropcap   = true
paragraph = """
There are no manual offsets on this page. Every baseline, every wrap point, and the drop cap that opens this column were computed by the measurement pipeline, not nudged by hand. Move the illustration three pixels and re-render: the body text re-flows around its new footprint, the pull quote keeps its clearance, and the drop cap still lands on its line — because nothing here was hardcoded.
"""

[[body]]
paragraph = """
The exhibit measures once and lays out many times. The same prepared paragraph is packed around an inset-exclusion chord function that subtracts the illustration, the drop cap, and the pull quote from each scanline band. Correctness is asserted on the computed layout before a single glyph is drawn.
"""

[[pull_quote]]
text        = "Measure once. Lay out many times. Never nudge."
attribution = "— the thesis"
x_px        = 40
y_px        = 150
width_px    = 160
```

- [ ] **Step 4: Write the top-level CLI render script**

Create `examples/cover/render.jl`:
```julia
# SPDX-License-Identifier: MIT
# CLI: render a cover-vN.toml to a vector PDF (+ optional PNG for the visual gate).
#   julia --project=examples/cover examples/cover/render.jl data/cover-v1.toml [out.pdf]
using Cover

function main(args)
    isempty(args) && error("usage: render.jl <cover.toml> [out.pdf]")
    cfg = args[1]
    out = length(args) >= 2 ? args[2] : nothing
    pdf = render_cover(cfg; out = out, png = true)
    println("wrote ", pdf, " and ", replace(pdf, r"\.pdf$" => ".png"))
end

main(ARGS)
```

- [ ] **Step 5: Verify rendering works end-to-end (all three fixtures)**

Run:
```bash
cd examples/cover
for v in 1 2 3; do julia --project=. render.jl data/cover-v$v.toml /tmp/cover-v$v.pdf; done
pdffonts /tmp/cover-v1.pdf | head
pdfimages -list /tmp/cover-v1.pdf
pdftotext /tmp/cover-v1.pdf - | head -5
```
Expected: three PDFs written; `pdffonts` shows embedded (emb=yes) LiberationSerif + DejaVuSans; `pdfimages -list` lists **0 images** (vector inset); `pdftotext` prints the title + body text. If a fixture's body overflows the page bottom, shorten its paragraphs; if a pull quote overlaps the inset, nudge the fixture's `pull_quote.x_px/y_px` (these are authored fixtures — adjusting fixture data is fine; adjusting *code* per-fixture is the failure the exhibit forbids).

- [ ] **Step 6: Commit**
```bash
git add examples/cover/src/render.jl examples/cover/src/Cover.jl examples/cover/render.jl examples/cover/data
git commit -m "feat(cover): CairoMakie render layer, CLI, skyline SVG + 3 fixtures (#H)"
```

---

### Task 8: Golden PDF-text hash + selectability/embedding + no-bitmap tests

**Files:**
- Modify: `examples/cover/test/runtests.jl`
- Create: `examples/cover/test/golden/cover-v1.pdftext.txt`
- Create: `examples/cover/test/golden/cover-v1.pdftext.sha256`

> The golden hashes the **`pdftotext` output** (selectable text content), never PDF bytes (random subset prefixes make bytes non-reproducible — Verified API fact #8). Whitespace is normalized before hashing so trivial spacing jitter can't false-fail. Tests shell out to `pdftotext`/`pdffonts`/`pdfimages`; if those tools are absent the PDF-side tests are **skipped with `@test_skip`** (the `ComposedCover` invariants are the real gate; #J's CI guarantees poppler-utils).

- [ ] **Step 1: Add a render+extract helper to the test preamble**

At the top of `runtests.jl` (after the other helpers), add:
```julia
using SHA

_have(tool) = !isnothing(Sys.which(tool))

# normalize pdftotext output for stable hashing: strip CR, collapse runs of blank
# lines, strip trailing spaces, ensure trailing newline.
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

# render a fixture to a temp PDF and return its path (or "" if CairoMakie save fails)
function _render_fixture(name)
    data = joinpath(@__DIR__, "..", "data", name)
    out = joinpath(mktempdir(), replace(name, ".toml" => ".pdf"))
    return render_cover(data; out = out)
end
```

- [ ] **Step 2: Write the golden + selectability + no-bitmap tests**

Insert inside the top-level `@testset`:
```julia
    @testset "PDF golden + embedding + vector" begin
        pdf = _render_fixture("cover-v1.toml")
        @test isfile(pdf) && filesize(pdf) > 0

        if _have("pdftotext")
            raw = read(`pdftotext $pdf -`, String)
            got = _norm_text(raw)
            golden_txt = joinpath(@__DIR__, "golden", "cover-v1.pdftext.txt")
            golden_sha = joinpath(@__DIR__, "golden", "cover-v1.pdftext.sha256")
            @test isfile(golden_txt)
            @test got == _norm_text(read(golden_txt, String))          # debuggable equality
            @test bytes2hex(sha256(got)) == strip(read(golden_sha, String))  # checksum golden
            # selectable text present: the title survives extraction
            @test occursin("Newer Yorker", got)
        else
            @test_skip "pdftotext not available"
        end

        if _have("pdffonts")
            fonts = read(`pdffonts $pdf`, String)
            @test occursin("LiberationSerif", fonts) || occursin("Liberation", fonts)
            # embedded: the 'emb' column says yes (no 'no' rows among our fonts)
            @test occursin("yes", fonts)
        else
            @test_skip "pdffonts not available"
        end

        if _have("pdfimages")
            # native vector inset -> ZERO raster images in the PDF
            listing = read(`pdfimages -list $pdf`, String)
            # header is 2 lines; any image row would add a 3rd. Count data rows.
            datarows = count(!isempty, filter(l -> occursin(r"^\s*\d", l), split(listing, "\n")))
            @test datarows == 0
        else
            @test_skip "pdfimages not available"
        end
    end
```

- [ ] **Step 3: Generate the golden files (one-time, from the pinned render)**

Run (this WRITES the goldens — only run it intentionally; thereafter the test compares against them):
```bash
cd examples/cover
mkdir -p test/golden
julia --project=. -e '
using Cover, SHA
out = joinpath(tempdir(), "cv1.pdf")
render_cover("data/cover-v1.toml"; out=out)
raw = read(`pdftotext $out -`, String)
# inline the SAME _norm_text used in the test:
function norm(s)
    s = replace(s, "\r"=>"")
    lines = rstrip.(split(s, "\n")); o = String[]
    for ln in lines
        (isempty(ln) && !isempty(o) && isempty(o[end])) && continue
        push!(o, String(ln))
    end
    return strip(join(o, "\n")) * "\n"
end
g = norm(raw)
write("test/golden/cover-v1.pdftext.txt", g)
write("test/golden/cover-v1.pdftext.sha256", bytes2hex(sha256(g)))
println("golden text:\n", g)
'
```
Inspect the printed text — it must read as the real cover copy (title, body, pull quote), in a sane order. If it looks wrong (garbled/empty), fix `render.jl` before trusting the golden.

- [ ] **Step 4: Run to verify pass**

Run: `julia --project=examples/cover -e 'using Pkg; Pkg.test()'`
Expected: PASS for `PDF golden + embedding + vector` (and all earlier sets).

- [ ] **Step 5: Commit**
```bash
git add examples/cover/test/runtests.jl examples/cover/test/golden
git commit -m "test(cover): cover-v1 PDF-text golden + embedding + vector-not-bitmap (#H)"
```

---

### Task 9: README, SPDX sweep, full-suite capture

**Files:**
- Create: `examples/cover/README.md`

- [ ] **Step 1: Write the README**

Create `examples/cover/README.md`:
```markdown
<!-- SPDX-License-Identifier: MIT -->
# Cover — the "Newer Yorker" correctness exhibit (#H)

A hand-set editorial cover rendered to a **vector PDF** with CairoMakie: display
title, drop cap, body text flowing around an SVG illustration inset, and a
pull-quote callout. Its job is to prove TextMeasure.jl is **correct** — the honest
acceptance test is *"no manual offsets"*: move the inset and re-render, and every
other element re-aligns because every offset is measurement-derived.

## How it works

- `compose_cover(config)` is **pure** — it computes every text baseline, the body
  `PackedLayout` (wrapped around an inset-exclusion `chord_fn` built in `chord.jl`),
  the drop-cap placement, and pull-quote boxes. No rendering.
- `render_cover(path)` is the only CairoMakie layer; it replays the composed
  placements with `text!`/`poly!`/`lines!`.
- Correctness is asserted on the computed `ComposedCover` (drop-cap baseline ±0.5px,
  bbox non-overlap, body-wrap-honors-inset), **not** on PDF coordinates — CairoMakie
  PDF coords don't round-trip at sub-pixel precision. The PDF is checked only for
  selectable text + font embedding + zero raster images (vector inset).

## Run it

```bash
julia --project=examples/cover -e 'using Pkg; Pkg.instantiate()'
# render a fixture to PDF (+ PNG):
julia --project=examples/cover examples/cover/render.jl examples/cover/data/cover-v1.toml /tmp/cover-v1.pdf
# tests (invariants + property test + PDF golden):
julia --project=examples/cover -e 'using Pkg; Pkg.test()'
```

The three `data/cover-v{1,2,3}.toml` fixtures share `meta`/`body` and vary only the
`[inset]` block — proving the layout adapts with no code change.

## Pinned fonts

Renders use **DejaVu Sans** + **Liberation Serif** (resolved by family name) so the
exported-PDF-text golden reproduces in CI (#J pins the same set).

## SVG support (intentionally minimal)

`data/skyline.svg` uses only straight-line primitives — `rect`, `circle`, `ellipse`,
`line`, `polyline`, `polygon`, and `path` with `M/L/H/V/Z`. Béziers, arcs, transforms,
gradients, and CSS are **not** supported; each primitive becomes a Makie `poly!`/`lines!`
ring, guaranteeing native vector output (never a bitmap).
```

- [ ] **Step 2: SPDX header sweep**

Run:
```bash
grep -L "SPDX-License-Identifier" \
  examples/cover/src/*.jl examples/cover/test/*.jl examples/cover/render.jl \
  examples/cover/README.md examples/cover/data/*.svg examples/cover/data/*.toml
```
Expected: no output. (`Project.toml`/`Manifest.toml` are exempt — generated/TOML.) The fixture `.toml` and `.svg` carry a comment-style SPDX line (added in Task 7); if any file is listed, add the header.

- [ ] **Step 3: Run the full suite ONCE, capture to the session log, grep green**

Run (from the worktree root):
```bash
mkdir -p test-logs
julia --project=examples/cover -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"
grep -E "Test Summary|Error|FAIL|Fail|Pass|No tests" "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -20
```
Expected: a `Cover.jl` summary line, all passing, no `Error`/`Fail`.

- [ ] **Step 4: Commit**
```bash
git add examples/cover/README.md
git commit -m "docs(cover): README + finalize license headers (#H)"
```

---

## Self-Review

**1. Spec coverage (issue #H Scope + Acceptance):**
- `cover.toml` schema (meta/layout/inset/[[body]]/[[pull_quote]], dropcap on first para, svg_path relative to toml) → Task 2 `load_config`. ✓
- Body text flows around the SVG inset USING `shape_pack` via a **self-built inset-exclusion chord_fn** (page intervals minus inset footprint; also subtracts drop-cap + pull-quote boxes) → Task 3 `RectExclusionChordFn`; does NOT import #G's complement, adds nothing to TextMeasureLayouts. ✓ (runbook constraint honored)
- Drop cap → Task 5 (size derived from body metrics; baseline == D-th line baseline). ✓
- Pull-quote callouts → Task 5 (laid out via `layout`, become holes so body never overlaps them). ✓
- Three `cover-v{1,2,3}.toml` varying inset only → Task 7. ✓
- **Property test, 20 random insets**, asserting (a) drop-cap baseline ±0.5px at computed-layout level, (b) pull-quote ∩ body / inset = ∅ on `PackedLayout`, (c) body wrap honors inset every line → Task 6, using Task-5 predicates `dropcap_baseline_aligned`/`bbox_violations`/`body_wrap_honors_inset`. ✓
- SVG inset rendered as **native CairoMakie vector content, not a bitmap** → Task 7 (`poly!`/`lines!`) + Task 8 (`pdfimages -list` = 0 images). ✓
- PDF text selectable / font embedding → Task 8 (`pdftotext` + `pdffonts`). ✓
- `cover-v1` exported-PDF-text **checksum golden**, rendered against **pinned fonts** → Task 8 (sha256 of normalized `pdftotext` output) + pinned font constants (Task 1). ✓
- Wave-1 conventions: Manifest gitignored (no force-add), `[extras] Test`/`[targets] test` (Task 1), SPDX on every new file (Task 9 sweep), pinned DejaVu Sans + Liberation Serif (Task 1 constants), assertions on computed structures not PDF coords, regression floors not hard counts (`datarows == 0`, `passed == 20`, `occursin` checks). ✓
- Does NOT invoke `finishing-a-development-branch` (per runbook). The plan ends at a green suite + committed golden; PR is a separate runbook step. ✓

**2. Placeholder scan:** No TBD/TODO; every code step shows full code. Forward references resolved: `BBox`/`PlacedText`/`CoverConfig`/`ComposedCover`/`SvgRing` defined in Task 1; `SvgRing` re-`struct`'d fully in Task 4 (the Task-1 `svg.jl` stub is **replaced wholesale**, not appended — no duplicate-struct error). `render_scene`/`render_cover` exported in Task 7 (export line edited there).

**3. Type consistency:** `BBox(left,top,right,bottom)` used identically in chord.jl, compose.jl, render.jl, tests. `PlacedText(text,x,baseline,fontsize,font)` consistent. `chord_intervals(::RectExclusionChordFn, y_top, y_bottom)` matches the `AbstractChordFn` contract probed in `shape_pack`. `shape_pack(prep, chord; line_advance, min_chord_width)` matches Verified API fact #4. `MakieBackend(; font, fontsize, px_per_unit)` matches fact #3. Holes are consistently body-local (y minus `body_top`) in compose.jl and that's exactly the frame `RectExclusionChordFn` documents. Drop-cap baseline formula `(D-1)*la + ascent` is the same in `compose_cover` (constructs it) and `dropcap_baseline_aligned` (reads the D-th distinct placement `y`).

**Decisions flagged for the gate (no issue-body API errors found; these are design choices):**
- **SVG rendering = in-repo minimal straight-line parser → Makie `poly!`/`lines!`**, NOT Rsvg/librsvg. Rationale: guarantees "native vector, not bitmap" by construction, zero external-JLL availability risk, deterministic for the golden. Limitation (no curves/transforms) is documented; the authored `skyline.svg` stays within the subset. If the orchestrator wants true arbitrary-SVG fidelity, that's a follow-up (Rsvg + Cairo-surface injection into CairoMakie is version-fragile).
- **Golden hashes normalized `pdftotext` output, not PDF bytes** — forced by random font-subset prefixes (Verified API fact #8). Matches the issue's "selectable text presence, not coordinate fidelity" intent and the spec's "exported-PDF-text checksum."
- **Fonts are code constants, not TOML fields** — required for golden reproducibility under the pinned-font prerequisite.
- **Drop cap also participates in the negative space** (its box is a chord_fn hole) so the first `dropcap_lines` lines indent past it with no manual offset — same mechanism as the inset, reinforcing the exhibit's thesis.
```
