# The Glyph Wave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproduce Hokusai's *Great Wave* (Met object 45434, CC0) entirely in measured type — every word run's size/weight/colour is sampled from the tone beneath it — so the painting emerges from continuous, readable Strange-1906 prose flowed through `shape_pack` into the wave silhouette and rendered to PNG by Makie.

**Architecture:** Pure orchestration over the existing engine. The riskiest unknown — flowing a *merged* `Prepared` (per-segment widths drawn from per-word size buckets, but a SINGLE `FontMetrics` whose `line_advance = lineheight × size_max`) through `shape_pack`/`RasterChordFn` — is prototyped FIRST (Task 1) and gates everything. Then: pin 3 missing Fraunces weights (Task 2); image → luminance + summed-area-table + 5-ink CIELAB palette + foam BitMatrix mask (Tasks 3–4); collinear tone-map pre-pass (Task 5); K-bucket prepares → merged `Prepared` → `shape_pack` (Task 6); group-by-weight Makie `text!` → PNG with the `fontsize`-as-vector empirical probe (Task 7); golden = `digest_rows` of the layout table + acceptance gates + the squint-test MERGE GATE (Tasks 8–9). Reading order is preserved by construction; no glyph rotation/warp/justify/CJK.

**Tech Stack:** Julia 1.11+; `TextMeasure` + `TextMeasureLayouts` (`shape_pack`, `RasterChordFn`, path-dep); `HouseStyle` (path-dep, uuid `f1a9b3c2-0d4e-4a6b-9c8d-7e2f1a0b3c4d` — colours/RAMP/fraunces/footer/`digest_rows`); `Makie` + `CairoMakie` (`MakieBackend(px_per_unit=1)`, `space=:pixel`, group-by-weight `text!`, PNG); JuliaImages stack — `FileIO`/`ImageIO`, `Images`/`ImageTransformations` (`imresize`), `Colors` (`Lab`, `colordiff`, `DE_AB`), `IntegralArrays` (`IntegralArray`); `Test` (stdlib). Fonts under `examples/fonts/Fraunces/`.

---

## File structure

- **Create** `examples/glyph_wave/Project.toml` — path-deps (HouseStyle, TextMeasure, TextMeasureLayouts) via `[sources]` + registered deps (Makie/CairoMakie/Images/Colors/ImageTransformations/IntegralArrays/FileIO/GeometryBasics), `[extras]`/`[targets]` Test. Mirrors `examples/layouts/Project.toml` for the path-dep shape. **`Manifest.toml` is intentionally NOT committed** (operator convention 2026-05-28).
- **Create** `examples/glyph_wave/src/GlyphWave.jl` — module entry: `using`/`include`/`export` wiring.
- **Create** `examples/glyph_wave/src/merged_prepared.jl` — `merged_prepared(words_widths, size_max; lineheight)` builds the merged `Prepared` (Task 1).
- **Create** `examples/glyph_wave/src/image_tone.jl` — load → luminance grid → summed-area sampler → palette snap → mask (Tasks 3–4).
- **Create** `examples/glyph_wave/src/tonemap.jl` — per-word (size bucket, weight, colour) assignment + collinearity (Task 5).
- **Create** `examples/glyph_wave/src/pack.jl` — K-bucket prepares → merged `Prepared` → `shape_pack` (Task 6).
- **Create** `examples/glyph_wave/src/render.jl` — group-by-weight `text!` → PNG + layout-table rows (Task 7).
- **Create** `examples/glyph_wave/src/text.jl` — the credo + Strange-1906 bulk-fill corpus (Task 7).
- **Create** `examples/glyph_wave/scripts/fetch_asset.jl` — offline downsample of `primaryImageSmall` → `assets/great_wave.png` (Task 3; NOT run at build/CI).
- **Create** `examples/glyph_wave/assets/great_wave.png` + `assets/SOURCE.txt` (Task 3).
- **Create** `examples/glyph_wave/test/runtests.jl` — aggregator.
- **Create** `examples/glyph_wave/test/test_merged_prepared.jl` (Task 1), `test_image_tone.jl` (Tasks 3–4), `test_tonemap.jl` (Task 5), `test_pack.jl` (Task 6), `test_render.jl` (Task 7), `test_golden.jl` + `test_acceptance.jl` + `test_squint.jl` (Tasks 8–9).
- **Create** `examples/glyph_wave/test/golden/layout_table.sha256` (Task 8) + `test/golden/squint_reference.png` (Task 9).
- **Create** `examples/glyph_wave/README.md` (Task 9).

## Engine facts (do not rebuild — depend on these)

- `prepare(backend, text)::Prepared` (`src/prepare.jl`) tokenizes into `:word`/`:space`/`:newline` `Segment`s; the ONLY phase that touches the font engine.
- `Segment(str::String, width::Float64, kind::Symbol)`; `Prepared(segments::Vector{Segment}, metrics::FontMetrics)` — read-only by convention, keyword ctor `Prepared(; segments, metrics)` exists. `FontMetrics(ascent, descent, line_advance)` all `Float64` px (`src/types.jl`).
- `shape_pack(prep, chord_fn; line_advance, min_chord_width=24, overflow_strategy=:widest_row, fill=:widest, …)::PackedLayout` (`examples/layouts/src/shape_pack.jl`). `PackedLayout(placements::Vector{Placement}, overflowed::Vector{Int}, metrics)`. `Placement(segment_index::Int, x::Float64, y::Float64)` — `segment_index` is the **absolute** index into `prep.segments`; `placements` are `:word` segments in left-to-right, top-to-bottom reading order; `y` is the baseline. `shape_pack` honours ONE `FontMetrics`/`line_advance` for ALL placements — this is exactly why a merged `Prepared` with mixed-size per-segment widths but a single `FontMetrics` works.
- `RasterChordFn(raster::BitMatrix, cell_size::Float64)` / `raster_chord_fn(raster, cell_size)`: `raster[row,col]` true ⇒ inside; `row` indexes y-down, `col` indexes x; cell `(row,col)` covers `x∈[(col-1)cs, col·cs]`, `y∈[(row-1)cs, row·cs]`. A band's intervals are the maximal `true`-runs in the row at the band's vertical center.
- `MakieBackend(; font, fontsize, px_per_unit=1.0)` (`ext/TextMeasureMakieExt.jl`): `measure` sums `FTA.hadvance` × `fontsize·px_per_unit` (no kerning, matches `text!`); `font_metrics` returns face-derived `line_advance`. `font` resolves via `Makie.to_font(path)` to the exact face `text!` uses → pass a static-weight `.ttf` PATH per backend.

---

### Task 1: Merged-`Prepared` round-trip prototype (RISKIEST — gates everything)

The single riskiest unknown: prove that a `Prepared` whose per-**segment** widths come from per-word size buckets, but which carries a **single** `FontMetrics` (`line_advance = lineheight × size_max`), flows through `shape_pack` cleanly and returns `:word` placements in reading order. Prototype on a tiny fixed text + 2 buckets, BEFORE any image/font work.

**Files:**
- Create: `examples/glyph_wave/Project.toml`
- Create: `examples/glyph_wave/src/GlyphWave.jl`
- Create: `examples/glyph_wave/src/merged_prepared.jl`
- Create: `examples/glyph_wave/test/runtests.jl`
- Create: `examples/glyph_wave/test/test_merged_prepared.jl`

- [ ] **Step 1: Write the Project.toml** (mirrors `examples/layouts/Project.toml` path-dep shape; full dep set so later tasks don't re-edit)

Create `examples/glyph_wave/Project.toml`:
```toml
name = "GlyphWave"
uuid = "b2c4d6e8-1a3c-4e5f-8a9b-0c1d2e3f4a5b"
version = "0.1.0"
authors = ["TextMeasure.jl contributors"]

[deps]
CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
Colors = "5ae59095-9a9b-59fe-a467-6f913c188581"
FileIO = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
GeometryBasics = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
HouseStyle = "f1a9b3c2-0d4e-4a6b-9c8d-7e2f1a0b3c4d"
ImageTransformations = "02fcd773-0e25-5acc-982a-7f6622650795"
Images = "916415d5-f1e6-5110-898d-aaa5f9f070e0"
IntegralArrays = "1d092043-8f09-5a30-832f-7509e371ab51"
Makie = "ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a"
TextMeasure = "06791c1d-2336-41e1-bd6f-a74c63395da6"
TextMeasureLayouts = "57b0e3ea-cc01-4cc3-9e7e-6e97d1609b9f"

# Unregistered in-repo packages — resolve by path (Julia 1.11+ [sources]).
[sources]
HouseStyle = { path = "../_housestyle" }
TextMeasure = { path = "../.." }
TextMeasureLayouts = { path = "../layouts" }

[compat]
julia = "1.11"

[extras]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Test"]
```

- [ ] **Step 2: Write the failing test**

Create `examples/glyph_wave/test/test_merged_prepared.jl`:
```julia
# SPDX-License-Identifier: MIT
using GlyphWave, TextMeasure, Test
using TextMeasureLayouts: shape_pack, raster_chord_fn, Placement

@testset "merged_prepared round-trip" begin
    # 5 words; each gets a per-word advance width drawn from its OWN size bucket.
    # Bucket A (small): width 10 per word; Bucket B (big): width 20 per word.
    # A single space width of 5; single FontMetrics; line_advance = 1.0 * size_max.
    words   = ["aa", "bb", "cc", "dd", "ee"]
    widths  = [10.0, 20.0, 10.0, 20.0, 10.0]   # mixed-size per-SEGMENT widths
    size_max = 20.0
    prep = merged_prepared(words, widths; space_width=5.0, lineheight=1.0, size_max=size_max)

    # The single FontMetrics carries the tallest bucket's pitch.
    @test prep.metrics.line_advance == 20.0
    # Interleaved word/space segments preserve reading order; words carry mixed widths.
    word_segs = [s for s in prep.segments if s.kind === :word]
    @test [s.str for s in word_segs] == words
    @test [s.width for s in word_segs] == widths

    # Flow through shape_pack with a full-width rectangle raster (all cells inside).
    # cell_size = line_advance so one band == one raster row.
    raster = trues(8, 12)                       # 12 cols * 20 = 240 px wide region
    chord  = raster_chord_fn(raster, prep.metrics.line_advance)
    packed = shape_pack(prep, chord; line_advance=prep.metrics.line_advance, min_chord_width=10.0)

    # Every word placed, in reading order, none overflowed.
    @test isempty(packed.overflowed)
    placed_idx = [p.segment_index for p in packed.placements]
    @test placed_idx == sort(placed_idx)        # monotone => reading order preserved
    @test [prep.segments[p.segment_index].str for p in packed.placements] == words
    @test length(packed.placements) == 5
    # Baselines lie on the single uniform grid (multiples of line_advance + ascent).
    asc = prep.metrics.ascent
    @test all(p -> isapprox((p.y - asc) % prep.metrics.line_advance, 0.0; atol=1e-9) ||
                   isapprox((p.y - asc) % prep.metrics.line_advance, prep.metrics.line_advance; atol=1e-9),
              packed.placements)
end
```

Create `examples/glyph_wave/test/runtests.jl`:
```julia
# SPDX-License-Identifier: MIT
using Test
@testset "GlyphWave" begin
    include("test_merged_prepared.jl")
end
```

- [ ] **Step 3: Run it to verify it fails**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```
Expected: FAIL — `merged_prepared` not defined (`UndefVarError`).

- [ ] **Step 4: Write the minimal implementation**

Create `examples/glyph_wave/src/merged_prepared.jl`:
```julia
# SPDX-License-Identifier: MIT
using TextMeasure: Segment, Prepared, FontMetrics

"""
    merged_prepared(words, widths; space_width, lineheight=1.0, size_max,
                    ascent_ratio=0.8, descent_ratio=0.2) -> Prepared

Hand-construct a MERGED `Prepared`: per-SEGMENT `:word` widths are `widths[i]`
(each already measured at that word's assigned size bucket), interleaved with
`:space` segments of width `space_width`. A SINGLE `FontMetrics` carries the whole
layout, with `line_advance = lineheight * size_max` so the tallest bucket never
collides and every baseline lands on one uniform grid (the spec's non-negotiable
airy-grid tradeoff). `ascent`/`descent` are derived from `size_max` so the baseline
sits sensibly within the band.
"""
function merged_prepared(words::AbstractVector{<:AbstractString},
                         widths::AbstractVector{<:Real};
                         space_width::Real,
                         lineheight::Real=1.0,
                         size_max::Real,
                         ascent_ratio::Real=0.8,
                         descent_ratio::Real=0.2)
    length(words) == length(widths) ||
        throw(ArgumentError("words and widths must be the same length"))
    segs = Segment[]
    for (i, w) in enumerate(words)
        push!(segs, Segment(String(w), Float64(widths[i]), :word))
        i < length(words) && push!(segs, Segment(" ", Float64(space_width), :space))
    end
    la = Float64(lineheight) * Float64(size_max)
    metrics = FontMetrics(ascent_ratio * size_max, descent_ratio * size_max, la)
    return Prepared(segs, metrics)
end
```

Create `examples/glyph_wave/src/GlyphWave.jl`:
```julia
# SPDX-License-Identifier: MIT
module GlyphWave

using TextMeasure
using TextMeasureLayouts

include("merged_prepared.jl")

export merged_prepared

end # module
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: PASS — "merged_prepared round-trip" green. **This is the gate: if `shape_pack` returns out-of-order or drops words, STOP and re-evaluate before any further task.**

- [ ] **Step 6: Commit**

```bash
git add examples/glyph_wave/Project.toml examples/glyph_wave/src/GlyphWave.jl examples/glyph_wave/src/merged_prepared.jl examples/glyph_wave/test/runtests.jl examples/glyph_wave/test/test_merged_prepared.jl
git commit -m "feat(glyph_wave): merged-Prepared round-trip prototype (riskiest unknown, gates the piece)"
```

---

### Task 2: Add the 3 missing Fraunces 9pt OFL statics (Light, Medium, Bold)

The 6-weight ramp (Light·Regular·Medium·SemiBold·Bold·Black) needs three faces NOT in the pinned set. Light and Bold exist as upstream 9pt statics; **Medium has no 9pt static instance and must be instanced from the variable font** (verified upstream 2026-06-13). Document provenance + OFL with the exact fetch/instance commands + SHA256, verify they load.

**Files:**
- Create: `examples/fonts/Fraunces/Fraunces9pt-Light.ttf`, `Fraunces9pt-Medium.ttf`, `Fraunces9pt-Bold.ttf`
- Create/Modify: `examples/fonts/Fraunces/PROVENANCE.txt`

- [ ] **Step 1: Confirm the 3 statics are absent**

Run:
```bash
ls examples/fonts/Fraunces/Fraunces9pt-{Light,Medium,Bold}.ttf 2>&1 || true
```
Expected: `No such file` for all three (Regular/SemiBold/Black are already pinned by the Foundation plan; the 9pt Light/Medium/Bold are not).

- [ ] **Step 2: Fetch the three statics from the Fraunces OFL family**

The Fraunces variable font ships opsz+wght axes; the gallery uses the **9pt optical-size, named-instance** statics. VERIFIED against the upstream repo (`googlefonts/fraunces`, OFL-1.1) on 2026-06-13:

- **Upstream facts (confirmed via the GitHub contents API):** default branch is **`master`** (NOT `main`); static TTFs live under **`fonts/static/ttf/`** (lowercase `ttf`); naming is **`Fraunces9pt-<weight>.ttf`** (NO `Fraunces_9pt` underscore). The upright 9pt static set is **Thin, Light, Regular, SemiBold, Bold, Black** — there is **NO `Fraunces9pt-Medium.ttf`** named instance. So Light and Bold are fetched directly; **Medium (wght 500) must be INSTANCED from the variable font** at `opsz=9, wght=500`.

Fetch Light + Bold directly (correct branch/dir/name), with raw-blob SHA256:
```bash
cd examples/fonts/Fraunces
for w in Light Bold; do
  curl -fsSL -o "Fraunces9pt-$w.ttf" \
    "https://raw.githubusercontent.com/googlefonts/fraunces/master/fonts/static/ttf/Fraunces9pt-$w.ttf"
done
```
Instance Medium from the variable font at `opsz=9, wght=500` (no static named instance exists):
```bash
# one-time tools env (don't pollute @v1.x): python -m venv /tmp/ftenv && /tmp/ftenv/bin/pip install fonttools
curl -fsSL -o /tmp/Fraunces-var.ttf \
  "https://raw.githubusercontent.com/googlefonts/fraunces/master/fonts/Fraunces%5BSOFT%2CWONK%2Copsz%2Cwght%5D.ttf"
/tmp/ftenv/bin/fonttools varLib.instancer /tmp/Fraunces-var.ttf \
  opsz=9 wght=500 SOFT=0 WONK=0 -o Fraunces9pt-Medium.ttf
ls -la Fraunces9pt-{Light,Medium,Bold}.ttf
sha256sum Fraunces9pt-{Light,Medium,Bold}.ttf   # record these in PROVENANCE.txt (Step 3)
```
Expected: three non-empty `.ttf` files (Light/Bold ~64–65 KB matching upstream blob sizes 64164 / 65384; Medium is the instanced output). Each file must be a 9pt opsz instance to match the existing Regular/SemiBold/Black naming. **Verify the Light/Bold SHA256 against the values recorded in PROVENANCE.txt; for Medium, record the produced SHA256 plus the exact instancer command.**

- [ ] **Step 3: Document provenance + OFL**

Create/append `examples/fonts/Fraunces/PROVENANCE.txt` (fill in the ACTUAL SHA256 sums printed
by `sha256sum` in Step 2 — the values below are placeholders to replace, not invented constants):
```text
Fraunces (OFL-1.1) — https://github.com/googlefonts/fraunces  (default branch: master)
Pinned 9pt optical-size statics. License: examples/fonts/Fraunces/OFL.txt (copied by Foundation).

Added by the Glyph Wave plan (2026-06-13), completing the 6-weight ramp.
Upstream naming is "Fraunces9pt-<weight>.ttf" (NO underscore); statics live under
fonts/static/ttf/ on branch master. Verified 2026-06-13 via the GitHub contents API:
the 9pt upright static set is Thin/Light/Regular/SemiBold/Bold/Black — there is NO
Fraunces9pt-Medium.ttf named instance, so Medium is instanced from the variable font.

  Fraunces9pt-Light.ttf   (wght 300, opsz 9)  — fetched
  Fraunces9pt-Medium.ttf  (wght 500, opsz 9)  — INSTANCED (no upstream static)
  Fraunces9pt-Bold.ttf    (wght 700, opsz 9)  — fetched

Fetch commands (Light, Bold):
  curl -fsSL -o Fraunces9pt-Light.ttf \
    https://raw.githubusercontent.com/googlefonts/fraunces/master/fonts/static/ttf/Fraunces9pt-Light.ttf
  curl -fsSL -o Fraunces9pt-Bold.ttf \
    https://raw.githubusercontent.com/googlefonts/fraunces/master/fonts/static/ttf/Fraunces9pt-Bold.ttf
  (upstream blob sizes at pin time: Light 64164 B, Bold 65384 B)

Instancing command (Medium, from the variable font):
  curl -fsSL -o /tmp/Fraunces-var.ttf \
    "https://raw.githubusercontent.com/googlefonts/fraunces/master/fonts/Fraunces%5BSOFT%2CWONK%2Copsz%2Cwght%5D.ttf"
  fonttools varLib.instancer /tmp/Fraunces-var.ttf opsz=9 wght=500 SOFT=0 WONK=0 -o Fraunces9pt-Medium.ttf

SHA256 (record the ACTUAL output of `sha256sum Fraunces9pt-{Light,Medium,Bold}.ttf`):
  <sha256>  Fraunces9pt-Light.ttf
  <sha256>  Fraunces9pt-Medium.ttf
  <sha256>  Fraunces9pt-Bold.ttf

Already pinned by the Foundation plan: Fraunces9pt-{Regular,SemiBold,Black}.ttf.
```

- [ ] **Step 4: Verify all six 9pt weights load via FreeType (the engine's font path)**

Run:
```bash
julia --project=examples/glyph_wave -e '
using FileIO, FreeTypeAbstraction
dir = "examples/fonts/Fraunces"
for w in ("Light","Regular","Medium","SemiBold","Bold","Black")
    p = joinpath(dir, "Fraunces9pt-$w.ttf")
    f = FreeTypeAbstraction.try_load(p)
    @assert f !== nothing "failed to load $p"
    println("OK  $w  units_per_EM=", f.units_per_EM)
end
println("all 6 Fraunces 9pt weights load")
'
```
Expected: six `OK <weight> units_per_EM=…` lines, then `all 6 Fraunces 9pt weights load`. (FreeTypeAbstraction is a transitive dep of Makie/TextMeasure; if it is not directly resolvable, add it to `[extras]` and run under `--project=examples/glyph_wave` after `Pkg.instantiate()`.)

- [ ] **Step 5: Commit**

```bash
git add examples/fonts/Fraunces/Fraunces9pt-Light.ttf examples/fonts/Fraunces/Fraunces9pt-Medium.ttf examples/fonts/Fraunces/Fraunces9pt-Bold.ttf examples/fonts/Fraunces/PROVENANCE.txt
git commit -m "chore(glyph_wave): pin Fraunces 9pt Light/Medium/Bold OFL statics (complete 6-weight ramp)"
```

---

### Task 3: Commit the Great Wave asset + offline fetch script + image load and luminance

Commit a downsized CC0 master (NOT fetched at build), plus a luminance grid loader.

**Files:**
- Create: `examples/glyph_wave/scripts/fetch_asset.jl`
- Create: `examples/glyph_wave/assets/great_wave.png`
- Create: `examples/glyph_wave/assets/SOURCE.txt`
- Create: `examples/glyph_wave/src/image_tone.jl`
- Create: `examples/glyph_wave/test/test_image_tone.jl`
- Modify: `examples/glyph_wave/src/GlyphWave.jl`
- Modify: `examples/glyph_wave/test/runtests.jl`

- [ ] **Step 1: Write the offline fetch script (run ONCE by hand, never at build/CI)**

Create `examples/glyph_wave/scripts/fetch_asset.jl`:
```julia
# SPDX-License-Identifier: MIT
# OFFLINE ONLY — run by hand to (re)generate assets/great_wave.png. NOT a build step.
# Met object 45434, CC0 / public domain (isPublicDomain: true).
using Downloads, FileIO, Images, ImageTransformations
const URL = "https://images.metmuseum.org/CRDImages/as/web-large/DP130155.jpg"
tmp = Downloads.download(URL)
img = load(tmp)                       # web-large JPEG
small = imresize(img; ratio = 1500 / size(img, 2))   # ~1500 px wide master
save(joinpath(@__DIR__, "..", "assets", "great_wave.png"), small)
println("wrote assets/great_wave.png  ", size(small))
```

- [ ] **Step 2: Generate the asset + SOURCE.txt**

Run the fetch script once, then write provenance:
```bash
julia --project=examples/glyph_wave examples/glyph_wave/scripts/fetch_asset.jl
ls -la examples/glyph_wave/assets/great_wave.png
```
Expected: `assets/great_wave.png` exists, ~150–250 KB, ~1500 px wide.

Create `examples/glyph_wave/assets/SOURCE.txt`:
```text
Katsushika Hokusai, "Under the Wave off Kanagawa" (the Great Wave),
from "Thirty-six Views of Mount Fuji", ca. 1830-32.
The Metropolitan Museum of Art, object 45434.
License: CC0 / Public Domain (Met Open Access; API isPublicDomain: true).
Object page: https://www.metmuseum.org/art/collection/search/45434
Source image: https://images.metmuseum.org/CRDImages/as/web-large/DP130155.jpg
great_wave.png is a downsized (~1500px) copy generated by scripts/fetch_asset.jl.
Do NOT fetch at build/CI; do NOT commit the full-resolution original.
```

- [ ] **Step 3: Write the failing test (luminance grid)**

Create `examples/glyph_wave/test/test_image_tone.jl`:
```julia
# SPDX-License-Identifier: MIT
using GlyphWave, Test

const ASSET = joinpath(@__DIR__, "..", "assets", "great_wave.png")

@testset "luminance grid" begin
    lum = GlyphWave.load_luminance(ASSET)
    @test eltype(lum) == Float64
    @test ndims(lum) == 2
    @test all(0.0 .<= lum .<= 1.0)             # normalized luma
    # The upper-left sky is bright; the deep trough is dark — directional sanity.
    h, w = size(lum)
    sky    = lum[1:h÷5, 1:w÷5]                  # top-left sky region
    trough = lum[h÷2:h, w÷3:2w÷3]              # central dark water
    @test sum(sky)/length(sky) > sum(trough)/length(trough)
end
```

Append to `examples/glyph_wave/test/runtests.jl` inside the `@testset`:
```julia
    include("test_image_tone.jl")
```

- [ ] **Step 4: Run it to verify it fails**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `load_luminance` not defined.

- [ ] **Step 5: Write the minimal implementation**

Create `examples/glyph_wave/src/image_tone.jl`:
```julia
# SPDX-License-Identifier: MIT
using FileIO, Images

"""
    load_luminance(path) -> Matrix{Float64}

Load an image and return its Rec.601 luma as a `[row, col] = [y_down, x]` Float64
grid in `[0,1]` (gamma-encoded sRGB — the perceptual ink/foam map). Arrays index
y-down, matching `line_top`/`RasterChordFn`, so no y-flip is needed downstream.
"""
function load_luminance(path::AbstractString)
    img = load(path)
    return Float64.(Gray.(img))
end
```

Add to `examples/glyph_wave/src/GlyphWave.jl` (after the `using` lines, before the `merged_prepared` include):
```julia
using FileIO
using Images
using Colors
using IntegralArrays

include("image_tone.jl")
```
and add `load_luminance` to the `export` list.

- [ ] **Step 6: Run the test to verify it passes**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: PASS — "luminance grid" green (sky brighter than trough).

- [ ] **Step 7: Commit**

```bash
git add examples/glyph_wave/scripts/fetch_asset.jl examples/glyph_wave/assets/great_wave.png examples/glyph_wave/assets/SOURCE.txt examples/glyph_wave/src/image_tone.jl examples/glyph_wave/src/GlyphWave.jl examples/glyph_wave/test/test_image_tone.jl examples/glyph_wave/test/runtests.jl
git commit -m "feat(glyph_wave): commit CC0 Great Wave asset + offline fetch + luminance grid"
```

---

### Task 4: Summed-area box-mean sampler, 5-ink CIELAB palette snap, foam BitMatrix mask

The O(1) per-run luminance sampler (the cost mitigation), the 5-ink CIELAB colour snap, and the foam mask the wave text flows inside.

**Files:**
- Modify: `examples/glyph_wave/src/image_tone.jl`
- Modify: `examples/glyph_wave/test/test_image_tone.jl`

- [ ] **Step 1: Write the failing tests**

Append to `examples/glyph_wave/test/test_image_tone.jl`:
```julia
@testset "summed-area box mean" begin
    lum = [0.0 1.0; 1.0 0.0]                    # 2x2
    sat = GlyphWave.box_mean_sampler(lum)
    @test isapprox(sat(1, 1, 2, 2), 0.5; atol=1e-9)   # whole image mean
    @test isapprox(sat(1, 1, 1, 1), 0.0; atol=1e-9)   # single cell [1,1]
    @test isapprox(sat(1, 2, 1, 2), 1.0; atol=1e-9)   # single cell [1,2]

    # Non-trivial 4x4 with a distinct INTERIOR box (rows 2..3, cols 2..3) — guards against
    # off-by-one / version-dependent IntegralArray range-indexing before later tasks rely on it.
    g = Float64[ r + 10c for r in 1:4, c in 1:4 ]     # lum[r,c] = r + 10c (all distinct)
    sg = GlyphWave.box_mean_sampler(g)
    @test isapprox(sg(1, 1, 4, 4), sum(g)/16; atol=1e-9)              # full image
    interior = g[2:3, 2:3]
    @test isapprox(sg(2, 2, 3, 3), sum(interior)/4; atol=1e-9)        # 2x2 interior box
    @test isapprox(sg(2, 2, 3, 3), (22.0+23.0+32.0+33.0)/4; atol=1e-9)  # explicit values
    @test isapprox(sg(1, 3, 4, 4), sum(g[1:4, 3:4])/8; atol=1e-9)     # off-corner 4x2 box
end

@testset "palette snap (CIELAB)" begin
    using Colors
    # A near-prussian colour must snap to PRUSSIAN, a near-foam to FOAM.
    near_prussian = Lab(convert(Lab, parse(Colorant, "#1C3B5C")))
    near_foam     = Lab(convert(Lab, parse(Colorant, "#ECE5D5")))
    @test GlyphWave.snap_ink(near_prussian) == GlyphWave.PRUSSIAN
    @test GlyphWave.snap_ink(near_foam)     == GlyphWave.FOAM
    @test length(GlyphWave.INKS) == 5
end

@testset "foam mask BitMatrix" begin
    lum = [0.9 0.9; 0.3 0.3]                    # top row bright (foam/sky), bottom dark (ink)
    mask = GlyphWave.foam_mask(lum; ink_cutoff=0.62)
    @test mask isa BitMatrix
    @test mask == BitMatrix([false false; true true])  # ink (dark) => inside, foam => hole
end
```

- [ ] **Step 2: Run them to verify they fail**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `box_mean_sampler`/`snap_ink`/`foam_mask` not defined.

- [ ] **Step 3: Write the minimal implementation**

Append to `examples/glyph_wave/src/image_tone.jl`:
```julia
using IntegralArrays, Colors

# The 5 hardcoded Hokusai inks (spec §1). Tune against the committed master.
const PRUSSIAN = parse(Colorant, "#1B3A5B")
const FOAM     = parse(Colorant, "#EDE6D6")
const INDIGO   = parse(Colorant, "#5E7A9B")
const SNOW     = parse(Colorant, "#B9C2C9")
const BOAT     = parse(Colorant, "#C8A36B")
const INKS     = (PRUSSIAN, FOAM, INDIGO, SNOW, BOAT)
const _INK_LAB = map(c -> convert(Lab, c), INKS)

"""
    box_mean_sampler(lum) -> (i0,j0,i1,j1) -> Float64

Summed-area table over `lum`; the returned closure gives the O(1) mean luminance of
the inclusive box `rows i0..i1, cols j0..j1`. Makes per-run sampling of thousands of
boxes cheap.
"""
function box_mean_sampler(lum::AbstractMatrix{<:Real})
    iL = IntegralArray(Float64.(lum))
    return function (i0::Integer, j0::Integer, i1::Integer, j1::Integer)
        n = (i1 - i0 + 1) * (j1 - j0 + 1)
        return iL[i0:i1, j0:j1] / n
    end
end

"""
    snap_ink(lab::Lab) -> Colorant

Snap a sampled colour (as `Lab`) to the nearest of the 5 hardcoded inks by ΔE
(`colordiff` with `DE_AB`). Hue and tone are then read from the SAME snapped ink
(the anti-mud rule).
"""
function snap_ink(lab::Lab)
    best, bestd = INKS[1], Inf
    for (ink, inklab) in zip(INKS, _INK_LAB)
        d = colordiff(lab, inklab; metric=DE_AB())
        d < bestd && (best, bestd = ink, d)
    end
    return best
end

"""
    foam_mask(lum; ink_cutoff=0.62) -> BitMatrix

`true` where the image is ink (dark) → text flows there; `false` where it is foam/sky
(bright) → holes. Feeds `RasterChordFn`.
"""
foam_mask(lum::AbstractMatrix{<:Real}; ink_cutoff::Real=0.62) = BitMatrix(lum .< ink_cutoff)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: PASS — summed-area, palette-snap, foam-mask testsets green. (If `IntegralArray` slice-mean indexing differs in the pinned version, compute the mean from the inclusive corner reads it documents and adjust `box_mean_sampler`; the test pins the contract.)

- [ ] **Step 5: Commit**

```bash
git add examples/glyph_wave/src/image_tone.jl examples/glyph_wave/test/test_image_tone.jl
git commit -m "feat(glyph_wave): summed-area sampler + 5-ink CIELAB snap + foam mask"
```

---

### Task 5: Tone-map — per-word (size bucket, weight, colour) with collinearity

The collinear weight/size/colour mapping (γ=0.45 gamma response, snapped-ink luminance), with the no-mud property enforced.

**Files:**
- Create: `examples/glyph_wave/src/tonemap.jl`
- Create: `examples/glyph_wave/test/test_tonemap.jl`
- Modify: `examples/glyph_wave/src/GlyphWave.jl`
- Modify: `examples/glyph_wave/test/runtests.jl`

- [ ] **Step 1: Write the failing test**

Create `examples/glyph_wave/test/test_tonemap.jl`:
```julia
# SPDX-License-Identifier: MIT
using GlyphWave, Test, Colors

@testset "tone ramp constants" begin
    @test length(GlyphWave.WEIGHTS) == 6        # Light..Black
    @test GlyphWave.WEIGHTS[1] == "Light"
    @test GlyphWave.WEIGHTS[end] == "Black"
    @test GlyphWave.SIZE_MIN == 13.0
    @test GlyphWave.SIZE_MAX == 21.0
    @test GlyphWave.NBUCKETS == 4
end

@testset "collinear tone assignment (no-mud)" begin
    # Darkest ink => heaviest weight + biggest size; brightest => lightest + smallest.
    dark  = GlyphWave.assign_tone(0.05)         # very dark ink luminance
    light = GlyphWave.assign_tone(0.95)         # very bright
    @test dark.weight_rank  > light.weight_rank
    @test dark.size_bucket  >= light.size_bucket
    @test GlyphWave.SIZE_MIN <= dark.fontsize <= GlyphWave.SIZE_MAX
    # Collinearity sign rule from the spec: weight and size move together.
    mid = (GlyphWave.NWEIGHTS + 1) / 2
    midb = (GlyphWave.NBUCKETS + 1) / 2
    for L in (0.05, 0.3, 0.5, 0.7, 0.95)
        t = GlyphWave.assign_tone(L)
        @test sign(t.weight_rank - mid) == sign(t.size_bucket - midb) ||
              t.weight_rank == mid || t.size_bucket == midb
    end
end
```

Create `examples/glyph_wave/src/tonemap.jl`:
```julia
# SPDX-License-Identifier: MIT
"""Tone ramp (spec §3). Weight is the primary carrier; size whispers."""
const WEIGHTS  = ("Light", "Regular", "Medium", "SemiBold", "Bold", "Black")
const NWEIGHTS = length(WEIGHTS)
const SIZE_MIN = 13.0
const SIZE_MAX = 21.0
const NBUCKETS = 4
const GAMMA    = 0.45

"One word's typographic assignment, derived collinearly from snapped-ink luminance."
struct Tone
    weight_rank :: Int       # 1..NWEIGHTS (1 = Light)
    weight      :: String    # WEIGHTS[weight_rank]
    size_bucket :: Int       # 1..NBUCKETS
    fontsize    :: Float64
end

"""
    assign_tone(L_snapped) -> Tone

Map a snapped ink's luminance `L∈[0,1]` to (weight, size bucket, fontsize) along a
perceptual response `d = (1-L)^γ` (γ=0.45). Darker ⇒ heavier + larger; collinear by
construction (single `d` drives both axes), so the no-mud property holds.
"""
function assign_tone(L::Real)
    d = (1.0 - clamp(Float64(L), 0.0, 1.0))^GAMMA      # 0 (light) .. 1 (dark)
    wr = clamp(round(Int, 1 + d * (NWEIGHTS - 1)), 1, NWEIGHTS)
    sb = clamp(round(Int, 1 + d * (NBUCKETS - 1)), 1, NBUCKETS)
    fs = SIZE_MIN + (sb - 1) / (NBUCKETS - 1) * (SIZE_MAX - SIZE_MIN)
    return Tone(wr, WEIGHTS[wr], sb, fs)
end
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `assign_tone`/`WEIGHTS` not defined (file not yet wired into the module).

- [ ] **Step 3: Wire the module + aggregator**

Add to `examples/glyph_wave/src/GlyphWave.jl` (after `include("image_tone.jl")`):
```julia
include("tonemap.jl")
```
and add `assign_tone` to the `export` list.

Append to `examples/glyph_wave/test/runtests.jl` inside the `@testset`:
```julia
    include("test_tonemap.jl")
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: PASS — tone-ramp + collinear testsets green.

- [ ] **Step 5: Commit**

```bash
git add examples/glyph_wave/src/tonemap.jl examples/glyph_wave/src/GlyphWave.jl examples/glyph_wave/test/test_tonemap.jl examples/glyph_wave/test/runtests.jl
git commit -m "feat(glyph_wave): collinear tone-map (gamma 0.45, 6 weights x 4 sizes, no-mud)"
```

---

### Task 6: Pack — K-bucket prepares → pre-pass sampling → merged `Prepared` → `shape_pack`

Tie the prototype (Task 1) to real measurement: 4 size-bucket prepares (engine "measure once" honoured), a median-size pre-pass to assign each word its tone, then the real merged-`Prepared` pack into the foam mask. Reading-order preserved.

**Files:**
- Create: `examples/glyph_wave/src/pack.jl`
- Create: `examples/glyph_wave/test/test_pack.jl`
- Modify: `examples/glyph_wave/src/GlyphWave.jl`
- Modify: `examples/glyph_wave/test/runtests.jl`

- [ ] **Step 1: Write the failing test**

Create `examples/glyph_wave/test/test_pack.jl`:
```julia
# SPDX-License-Identifier: MIT
using GlyphWave, TextMeasure, Test
import HouseStyle

@testset "bucket prepares + merged pack" begin
    backend(fs) = MakieBackend(; font=HouseStyle.fraunces("9pt-Regular"), fontsize=fs, px_per_unit=1)
    text = "the great wave rises over the boats off kanagawa as fuji watches"

    # 4 bucket prepares: each word measured at every bucket size (measure once per bucket).
    bucket_preps = GlyphWave.bucket_prepares(text)
    @test length(bucket_preps) == GlyphWave.NBUCKETS
    # A word's advance is larger in a bigger bucket (monotone in fontsize).
    w1 = bucket_preps[1].segments
    w4 = bucket_preps[end].segments
    first_word_idx = findfirst(s -> s.kind === :word, w1)
    @test w4[first_word_idx].width > w1[first_word_idx].width

    # Tiny all-ink raster so every word lands; pre-pass assigns buckets; merged pack flows.
    raster = trues(40, 60)                       # region wide/tall enough for the text
    cell   = GlyphWave.SIZE_MAX                  # one band per raster row
    packed, table = GlyphWave.pack_into(text, raster, cell;
                                        sample = (i0,j0,i1,j1) -> 0.5)   # flat mid-tone
    # Reading order preserved (placements monotone in segment_index), modulo overflow.
    non_overflow = [p for p in packed.placements if !(p.segment_index in packed.overflowed)]
    idx = [p.segment_index for p in non_overflow]
    @test idx == sort(idx)
    # Every placement carries a layout-table row with a real weight + fontsize + colour.
    @test length(table) == length(packed.placements)
    @test all(r -> r.weight in GlyphWave.WEIGHTS, table)
    @test all(r -> GlyphWave.SIZE_MIN <= r.fontsize <= GlyphWave.SIZE_MAX, table)

    # Reconstruction is by ACTUAL segment_index, not assumed dense 1,3,5,… contiguity:
    # every row's word string must equal the source-segment word it claims (no off-by-gap mis-map).
    # (Run.segment_index is the SOURCE segment index si; bucket preps share the same segment vector.)
    @test all(r -> r.str == bucket_preps[1].segments[r.segment_index].str, table)
end

@testset "holey-mask reconstruction (sparse indices, no off-by-gap)" begin
    # A mask with interior holes forces words to drop/skip, so placed merged :word indices are
    # NOT a dense 1,3,5,… run. The table must still map every surviving word to its OWN tone/word.
    text = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi"
    raster = trues(20, 30)
    raster[5:8, 8:20] .= false                   # punch an interior hole
    raster[12:15, 4:12] .= false                 # and another
    packed, table = GlyphWave.pack_into(text, raster, GlyphWave.SIZE_MAX;
                                        sample = (i0,j0,i1,j1) -> 0.5)
    # Placed merged :word segment indices need not be contiguous — prove the map still holds.
    @test all(r -> 1 <= r.segment_index <= length(text), table)  # never indexes out of range
    @test all(r -> r.weight in GlyphWave.WEIGHTS, table)
    @test length(table) == length(packed.placements)
    # The surviving words are exactly the source words at the reconstructed segment indices.
    src = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi"
    srcset = Set(split(src))
    @test all(r -> r.str in srcset, table)
end
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; using GlyphWave, Makie' 2>/dev/null; julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `bucket_prepares`/`pack_into` not defined.

- [ ] **Step 3: Write the minimal implementation**

Create `examples/glyph_wave/src/pack.jl`:
```julia
# SPDX-License-Identifier: MIT
using TextMeasure, Makie
using TextMeasureLayouts: shape_pack, raster_chord_fn
import HouseStyle

# Font path: ALWAYS go through the Foundation helper `HouseStyle.fraunces("9pt-<weight>")`,
# which maps to `Fraunces9pt-<weight>.ttf`. Do NOT introduce a local wrapper that also
# prepends `9pt-` — that double-prefixes into `Fraunces9pt-9pt-<weight>.ttf`. Pass the BARE
# weight (e.g. "Regular", "Black") to the `"9pt-$(weight)"` interpolation at every call site.

"One layout-table row (the golden-test unit; rendered later by Makie)."
struct Run
    segment_index :: Int
    x             :: Float64
    y             :: Float64
    fontsize      :: Float64
    weight        :: String
    colour        :: String     # hex of the snapped ink
    str           :: String
end

"The 4 bucket fontsizes (SIZE_MIN..SIZE_MAX), one per size bucket."
bucket_sizes() = [SIZE_MIN + (b - 1) / (NBUCKETS - 1) * (SIZE_MAX - SIZE_MIN) for b in 1:NBUCKETS]

"""
    bucket_prepares(text) -> Vector{Prepared}

`prepare(MakieBackend(fontsize=size_b), text)` once per size bucket (the engine's
"measure once" honoured — 4 prepares total). Regular weight is used for measurement
(advance is weight-stable enough across statics for bucket selection; the rendered
weight comes from the tone-map).
"""
function bucket_prepares(text::AbstractString)
    map(bucket_sizes()) do fs
        prepare(MakieBackend(; font=HouseStyle.fraunces("9pt-Regular"), fontsize=fs, px_per_unit=1), text)
    end
end

"""
    pack_into(text, raster, cell; sample, ink_cutoff=0.62) -> (PackedLayout, Vector{Run})

Pre-pass (median bucket) → per-word tone via `sample(i0,j0,i1,j1)` luminance over the
word's nominal box → build the merged `Prepared` (per-segment width from each word's
assigned bucket, single FontMetrics, line_advance = SIZE_MAX) → real `shape_pack` into
`raster`. Returns the packed layout and the per-run layout table (golden unit).
"""
function pack_into(text::AbstractString, raster::BitMatrix, cell::Real;
                   sample, ink_cutoff::Real=0.62)
    preps = bucket_prepares(text)
    median_b = (NBUCKETS + 1) ÷ 2
    chord = raster_chord_fn(raster, Float64(cell))

    # --- pre-pass: dry pack at median size to get nominal (x,y) per word ---
    pre = shape_pack(preps[median_b], chord; line_advance=Float64(cell),
                     min_chord_width=Float64(SIZE_MIN), fill=:all)
    # word segment-index -> nominal placement
    nominal = Dict(p.segment_index => p for p in pre.placements)

    # --- assign each word a Tone by sampling luminance at its nominal box ---
    segs = preps[median_b].segments
    tones = Dict{Int,Tone}()
    inks  = Dict{Int,String}()
    for (si, seg) in enumerate(segs)
        seg.kind === :word || continue
        p = get(nominal, si, nothing)
        if p === nothing
            tones[si] = assign_tone(1.0); inks[si] = _hex(snap_ink(convert(Lab, FOAM)))
            continue
        end
        # word box in raster cells (cell == band height; width from median bucket)
        j0 = clamp(floor(Int, p.x / cell) + 1, 1, size(raster, 2))
        j1 = clamp(floor(Int, (p.x + seg.width) / cell) + 1, 1, size(raster, 2))
        i  = clamp(floor(Int, (p.y - preps[median_b].metrics.ascent) / cell) + 1, 1, size(raster, 1))
        L  = sample(i, j0, i, max(j0, j1))
        tones[si] = assign_tone(L)
        inks[si]  = _hex(snap_ink(_lum_to_lab(L)))
    end

    # --- merged Prepared: per-segment width from each word's assigned bucket ---
    words  = String[]; widths = Float64[]; order = Int[]
    space_w = _space_width(preps[median_b])
    for (si, seg) in enumerate(segs)
        seg.kind === :word || continue
        b = tones[si].size_bucket
        push!(words, seg.str)
        push!(widths, preps[b].segments[si].width)   # SAME absolute index across buckets
        push!(order, si)                             # k-th merged word ⇒ source segment `order[k]`
    end
    merged = merged_prepared(words, widths; space_width=space_w, lineheight=1.0, size_max=SIZE_MAX)
    packed = shape_pack(merged, chord; line_advance=Float64(cell),
                        min_chord_width=Float64(SIZE_MIN), fill=:all)

    # --- explicit merged-segment-index ⇒ source-word-index map ---
    # DO NOT assume placed :word indices are a dense 1,3,5,… run. With `fill=:all` into a
    # holey foam mask, words drop/skip, so `(segment_index+1)÷2` mis-maps after the first
    # gap (or indexes out of range). Build the map by walking the ACTUAL merged segments and
    # pairing each :word segment with its source word ordinal, then look up by the placement's
    # real `segment_index`.
    merged_to_src = Dict{Int,Int}()                  # merged seg index ⇒ source segment index (si)
    merged_to_word = Dict{Int,Int}()                 # merged seg index ⇒ word ordinal k
    let k = 0
        for (msi, seg) in enumerate(merged.segments)
            seg.kind === :word || continue
            k += 1
            merged_to_src[msi]  = order[k]
            merged_to_word[msi] = k
        end
    end

    # --- build the layout table (look up tone/colour/word by ACTUAL segment_index) ---
    table = Run[]
    for p in packed.placements
        haskey(merged_to_src, p.segment_index) || continue   # skip any non-word placement defensively
        si = merged_to_src[p.segment_index]
        k  = merged_to_word[p.segment_index]
        t  = tones[si]
        push!(table, Run(si, p.x, p.y, t.fontsize, t.weight, inks[si], words[k]))
    end
    return packed, table
end

_space_width(prep) = let s = findfirst(x -> x.kind === :space, prep.segments)
    s === nothing ? Float64(SIZE_MIN) / 4 : prep.segments[s].width
end
_lum_to_lab(L::Real) = convert(Lab, Gray(clamp(Float64(L), 0.0, 1.0)))
_hex(c) = "#" * uppercase(Colors.hex(c))
```

- [ ] **Step 4: Wire the module + aggregator**

Add to `examples/glyph_wave/src/GlyphWave.jl` (after `include("tonemap.jl")`):
```julia
using Makie
import HouseStyle
include("pack.jl")
```
and add `bucket_prepares, pack_into, Run` to the `export` list. (Font paths go through `HouseStyle.fraunces("9pt-<weight>")` directly — there is no local `fraunces_path` wrapper.) (`MakieBackend` is exported by `TextMeasure`; ensure `Makie` is loaded so its extension is active.)

Append to `examples/glyph_wave/test/runtests.jl` inside the `@testset`:
```julia
    include("test_pack.jl")
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: PASS — "bucket prepares + merged pack" green: monotone advances, reading-order preserved, every run carries a real weight/fontsize/colour.

- [ ] **Step 6: Commit**

```bash
git add examples/glyph_wave/src/pack.jl examples/glyph_wave/src/GlyphWave.jl examples/glyph_wave/test/test_pack.jl examples/glyph_wave/test/runtests.jl
git commit -m "feat(glyph_wave): K-bucket prepares + pre-pass tone sampling + merged-Prepared pack"
```

---

### Task 7: Text corpus, `fontsize`-as-vector probe, group-by-weight Makie render → PNG

The legible credo + Strange-1906 bulk-fill; the empirical `fontsize`-as-vector probe (AFTER the merged-Prepared prototype, per spec); group-by-weight `text!` to a PNG; visually open it.

**Files:**
- Create: `examples/glyph_wave/src/text.jl`
- Create: `examples/glyph_wave/src/render.jl`
- Create: `examples/glyph_wave/test/test_render.jl`
- Modify: `examples/glyph_wave/src/GlyphWave.jl`
- Modify: `examples/glyph_wave/test/runtests.jl`

- [ ] **Step 1: Write the text corpus (PD only)**

Create `examples/glyph_wave/src/text.jl`:
```julia
# SPDX-License-Identifier: MIT
# Hokusai's credo — PD E. F. Strange (1906) translation (translator d. 1929; no notice).
# Verbatim from the spec. Do NOT substitute the in-copyright Smith-1988 wording.
const CREDO = """At the age of six I had a fancy for reproducing form; for fifty years I made many book illustrations, but even at seventy I had little skill. Only when I reached the age of seventy-three did I begin to understand how rightly to represent animals, birds, insects, fish, plants. At ninety I shall be better; at a hundred I shall be sublime; at a hundred and ten I shall give life to every line, to every dot. Let no one mock at these words!"""

# Bulk-fill — E. F. Strange's OWN 1906 prose (PD), never a passage he merely quotes.
# Several sentences of Strange's own descriptive body text about Hokusai's work.
const STRANGE_PROSE = """Hokusai was the most prolific and the most versatile of all the artists of his country. He worked with an industry that never flagged and a curiosity that never tired through the whole of a long life. The range of his subjects was as wide as nature itself, for he drew the mountain and the sea, the bird upon the bough and the fish beneath the wave, the labouring peasant and the strolling player. His line is alive in every stroke, and the smallest of his sketches has the same vitality as the greatest of his prints. He signed himself the old man mad about drawing, and the title was no idle boast, for to the end he sought to draw the very life of things."""

"""
    canvas_text(; min_words=1200) -> String

Full canvas text: the focal credo, then Strange-1906 bulk-fill repeated to fill. Each
repetition is DETERMINISTICALLY rotated by its iteration index (the leading `seed` words
move to the tail) so consecutive copies are not byte-identical — this varies which word
lands on which tone cell across repeats while keeping the prose readable and PD. Pure
function of `seed` (no RNG), so the golden/squint gates stay reproducible.
"""
function canvas_text(; min_words::Int=1200)
    fill_words = split(STRANGE_PROSE)
    parts = String[CREDO]
    n = length(split(CREDO))
    seed = 0
    while n < min_words
        # rotate the fill body left by `seed` words so each repeat differs (no RNG, fully deterministic)
        rot = seed % length(fill_words)
        rotated = vcat(fill_words[rot+1:end], fill_words[1:rot])
        piece = join(rotated, " ")
        push!(parts, piece)
        n += length(rotated)
        seed += 1
    end
    return join(parts, " ")
end
```

- [ ] **Step 2: Write the `fontsize`-as-vector probe + render (failing test)**

Create `examples/glyph_wave/test/test_render.jl`:
```julia
# SPDX-License-Identifier: MIT
using GlyphWave, Test, CairoMakie

@testset "fontsize-as-vector probe (informational)" begin
    ok = GlyphWave.fontsize_vector_supported()
    @test ok isa Bool
    @info "fontsize-as-vector supported in pinned Makie" ok
end

@testset "render produces a PNG" begin
    out = joinpath(mktempdir(), "glyph_wave_smoke.png")
    table = [GlyphWave.Run(1, 10.0, 20.0, 13.0, "Light", "#1B3A5B", "the"),
             GlyphWave.Run(3, 60.0, 20.0, 21.0, "Black", "#1B3A5B", "wave")]
    GlyphWave.render_table(table, out; width=400, height=120)
    @test isfile(out)
    @test filesize(out) > 1000
end
```

- [ ] **Step 3: Run it to verify it fails**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `fontsize_vector_supported`/`render_table` not defined.

- [ ] **Step 4: Write the minimal implementation**

Create `examples/glyph_wave/src/render.jl`:
```julia
# SPDX-License-Identifier: MIT
using Makie, CairoMakie
import HouseStyle

"""
    fontsize_vector_supported() -> Bool

Empirical probe (spec §3/§4, sequenced AFTER the merged-Prepared prototype): does the
pinned Makie HONOUR a per-glyph `fontsize` VECTOR in one `text!` call? We do NOT rely on
Makie throwing when it's unsupported — it may silently broadcast a single value instead.
Instead we assert an OBSERVABLE consequence: render the SAME two-glyph string twice, once
with a uniform small fontsize and once with a `[small, large]` vector, and confirm the
data-limits / bounding box actually GROW when the second glyph is enlarged. If the vector
were ignored (broadcast/dropped), both bboxes would match and we return `false`, so
`render_table` falls back to sub-grouping by (weight × size bucket).
"""
function fontsize_vector_supported()
    try
        # baseline: both glyphs at the small size
        fig0 = Figure(); ax0 = Axis(fig0[1, 1])
        t0 = text!(ax0, [Point2f(0, 0), Point2f(1, 0)]; text=["W", "W"],
                   fontsize=[12.0, 12.0], space=:pixel, markerspace=:pixel)
        # candidate: second glyph asked to be much larger via a vector
        fig1 = Figure(); ax1 = Axis(fig1[1, 1])
        t1 = text!(ax1, [Point2f(0, 0), Point2f(1, 0)]; text=["W", "W"],
                   fontsize=[12.0, 48.0], space=:pixel, markerspace=:pixel)
        h(t) = let bb = Makie.boundingbox(t); Makie.widths(bb)[2] end   # rendered glyph-extent height
        # The per-glyph vector took effect iff the enlarged glyph makes the bbox observably taller.
        return h(t1) > h(t0) * 1.5
    catch
        return false
    end
end

"""
    render_table(table, out; width, height)

Render the layout table to a PNG. Groups runs by weight (one `text!` per weight,
~6 calls), selecting the static face by file PATH (Makie has no variable-axis
selection). If `fontsize_vector_supported()` is false, sub-groups by (weight × size
bucket) so each `text!` gets a scalar fontsize (≤ 6×4 = 24 calls). PNG, never SVG.
"""
function render_table(table::AbstractVector{Run}, out::AbstractString; width::Int, height::Int)
    fig = Figure(size=(width, height); backgroundcolor=parse(Colorant, "#EDE6D6"))
    ax = Axis(fig[1, 1]; backgroundcolor=parse(Colorant, "#EDE6D6"))
    hidedecorations!(ax); hidespines!(ax)
    Makie.xlims!(ax, 0, width); Makie.ylims!(ax, height, 0)   # y-down to match layout frame

    vec_ok = fontsize_vector_supported()
    groups = vec_ok ? _group_by_weight(table) : _group_by_weight_size(table)
    for ((weight, _), runs) in groups
        isempty(runs) && continue
        pts  = [Point2f(r.x, r.y) for r in runs]
        strs = [r.str for r in runs]
        cols = [parse(Colorant, r.colour) for r in runs]
        fss  = vec_ok ? Float64[r.fontsize for r in runs] : runs[1].fontsize
        text!(ax, pts; text=strs, color=cols, fontsize=fss,
              font=HouseStyle.fraunces("9pt-$(weight)"),
              align=(:left, :baseline), space=:pixel, markerspace=:pixel)
    end
    save(out, fig; px_per_unit=1)
    return out
end

# group key (weight, 0) — fontsize handled as a vector within the group
_group_by_weight(table) = _groupby(table, r -> (r.weight, 0))
# group key (weight, size bucket) — scalar fontsize per group
_group_by_weight_size(table) = _groupby(table, r -> (r.weight, round(Int, r.fontsize)))
function _groupby(table, key)
    d = Dict{Any,Vector{Run}}()
    for r in table
        push!(get!(d, key(r), Run[]), r)
    end
    return d
end
```

- [ ] **Step 5: Wire the module + aggregator**

Add to `examples/glyph_wave/src/GlyphWave.jl` (after `include("pack.jl")`):
```julia
using CairoMakie
include("text.jl")
include("render.jl")
```
and add `canvas_text, render_table, fontsize_vector_supported, CREDO` to the `export` list.

Append to `examples/glyph_wave/test/runtests.jl` inside the `@testset`:
```julia
    include("test_render.jl")
```

- [ ] **Step 6: Run the test to verify it passes**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: PASS — probe returns a Bool (logged), smoke PNG written (>1 KB).

- [ ] **Step 7: Render the full piece and OPEN it (visual sign-off, not just green)**

Run:
```bash
julia --project=examples/glyph_wave -e '
using GlyphWave, FileIO
text = GlyphWave.canvas_text()
lum  = GlyphWave.load_luminance(joinpath(pkgdir(GlyphWave), "assets", "great_wave.png"))
# scale image grid to raster cells: 1 cell == SIZE_MAX px on a 3000x2000 canvas
W, H = 3000, 2000
cell = GlyphWave.SIZE_MAX
nrow, ncol = ceil(Int, H/cell), ceil(Int, W/cell)
small = GlyphWave.load_luminance(joinpath(pkgdir(GlyphWave), "assets", "great_wave.png"))
import ImageTransformations
rl = ImageTransformations.imresize(small, (nrow, ncol))
mask = GlyphWave.foam_mask(rl)
sat  = GlyphWave.box_mean_sampler(rl)
packed, table = GlyphWave.pack_into(text, mask, cell; sample=(i0,j0,i1,j1)->sat(i0,j0,i1,j1))
GlyphWave.render_table(table, "/tmp/glyph_wave.png"; width=W, height=H)
println("runs placed: ", length(table), "  overflowed: ", length(packed.overflowed))
'
```
Then OPEN `/tmp/glyph_wave.png` and confirm by eye: the Great Wave silhouette is unmistakable at squint distance; the credo is readable; no baseline jitter; no dark-ink/light-weight mud. (A green test is NOT visual sign-off — per project memory.) If interior tone washes out, invoke the posterize+Bayer 3-tone fallback (spec §3) before proceeding.

- [ ] **Step 8: Commit**

```bash
git add examples/glyph_wave/src/text.jl examples/glyph_wave/src/render.jl examples/glyph_wave/src/GlyphWave.jl examples/glyph_wave/test/test_render.jl examples/glyph_wave/test/runtests.jl
git commit -m "feat(glyph_wave): Strange-1906 corpus + fontsize-vector probe + group-by-weight render"
```

---

### Task 8: Golden test + acceptance gates (reading-order, no-mud, baseline)

The deterministic golden = `digest_rows` of the layout table (NOT the PNG bytes), plus the three non-squint acceptance properties.

**Files:**
- Create: `examples/glyph_wave/test/test_golden.jl`
- Create: `examples/glyph_wave/test/test_acceptance.jl`
- Create: `examples/glyph_wave/test/golden/layout_table.sha256`
- Modify: `examples/glyph_wave/test/runtests.jl`

- [ ] **Step 1: Write the failing golden test**

Create `examples/glyph_wave/test/test_golden.jl`:
```julia
# SPDX-License-Identifier: MIT
using GlyphWave, Test, ImageTransformations
import HouseStyle

# Deterministic fixture: a small fixed text + a fixed tiny raster so the table is stable.
function _fixture_table()
    text = "the great wave rises over the boats off kanagawa as fuji watches the shore"
    small = GlyphWave.load_luminance(joinpath(pkgdir(GlyphWave), "assets", "great_wave.png"))
    rl = imresize(small, (24, 36))
    mask = GlyphWave.foam_mask(rl)
    sat  = GlyphWave.box_mean_sampler(rl)
    _, table = GlyphWave.pack_into(text, mask, GlyphWave.SIZE_MAX;
                                   sample=(i0,j0,i1,j1)->sat(i0,j0,i1,j1))
    return table
end

# Per the Foundation digest contract: each piece formats its own rows, rounding floats.
function _rows(table)
    [string(r.segment_index, "|", round(r.x; digits=2), "|", round(r.y; digits=2), "|",
            round(r.fontsize; digits=2), "|", r.weight, "|", r.colour, "|", r.str)
     for r in table]
end

@testset "golden: layout-table digest" begin
    table = _fixture_table()
    got = HouseStyle.digest_rows(_rows(table))
    goldfile = joinpath(@__DIR__, "golden", "layout_table.sha256")
    @test isfile(goldfile)
    @test got == strip(read(goldfile, String))
end
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `golden/layout_table.sha256` does not exist (`isfile` false).

- [ ] **Step 3: Generate the golden digest from the verified fixture**

Run (writes the digest the fixture currently produces — VERIFY the fixture render looks right first via Task 7 Step 7 before trusting this):
```bash
mkdir -p examples/glyph_wave/test/golden
julia --project=examples/glyph_wave -e '
using GlyphWave, ImageTransformations; import HouseStyle
text = "the great wave rises over the boats off kanagawa as fuji watches the shore"
small = GlyphWave.load_luminance(joinpath(pkgdir(GlyphWave), "assets", "great_wave.png"))
rl = imresize(small, (24, 36)); mask = GlyphWave.foam_mask(rl); sat = GlyphWave.box_mean_sampler(rl)
_, table = GlyphWave.pack_into(text, mask, GlyphWave.SIZE_MAX; sample=(i0,j0,i1,j1)->sat(i0,j0,i1,j1))
rows = [string(r.segment_index,"|",round(r.x;digits=2),"|",round(r.y;digits=2),"|",round(r.fontsize;digits=2),"|",r.weight,"|",r.colour,"|",r.str) for r in table]
write("examples/glyph_wave/test/golden/layout_table.sha256", HouseStyle.digest_rows(rows))
println("wrote golden digest")
'
```
Expected: `wrote golden digest`; the file contains a 64-char hex string.

- [ ] **Step 4: Write the acceptance-property tests**

Create `examples/glyph_wave/test/test_acceptance.jl`:
```julia
# SPDX-License-Identifier: MIT
using GlyphWave, Test, ImageTransformations

function _acceptance_run()
    text = GlyphWave.canvas_text(min_words=400)
    small = GlyphWave.load_luminance(joinpath(pkgdir(GlyphWave), "assets", "great_wave.png"))
    rl = imresize(small, (60, 90)); mask = GlyphWave.foam_mask(rl); sat = GlyphWave.box_mean_sampler(rl)
    packed, table = GlyphWave.pack_into(text, mask, GlyphWave.SIZE_MAX;
                                        sample=(i0,j0,i1,j1)->sat(i0,j0,i1,j1))
    return packed, table
end

@testset "acceptance: reading order (overflow-exempt)" begin
    packed, _ = _acceptance_run()
    ov = Set(packed.overflowed)
    idx = [p.segment_index for p in packed.placements if !(p.segment_index in ov)]
    @test idx == sort(idx)                       # non-overflow runs are in reading order
end

@testset "acceptance: no-mud collinearity" begin
    _, table = _acceptance_run()
    mid  = (GlyphWave.NWEIGHTS + 1) / 2
    midb = (GlyphWave.NBUCKETS + 1) / 2
    for r in table
        wr = findfirst(==(r.weight), GlyphWave.WEIGHTS)
        sb = round(Int, 1 + (r.fontsize - GlyphWave.SIZE_MIN) /
                            (GlyphWave.SIZE_MAX - GlyphWave.SIZE_MIN) * (GlyphWave.NBUCKETS - 1))
        @test sign(wr - mid) == sign(sb - midb) || wr == mid || sb == midb
    end
end

@testset "acceptance: uniform baseline grid" begin
    packed, _ = _acceptance_run()
    la  = packed.metrics.line_advance
    asc = packed.metrics.ascent
    for p in packed.placements
        rem = (p.y - asc) % la
        @test isapprox(rem, 0.0; atol=1e-6) || isapprox(rem, la; atol=1e-6)
    end
end
```

Append to `examples/glyph_wave/test/runtests.jl` inside the `@testset`:
```julia
    include("test_golden.jl")
    include("test_acceptance.jl")
```

- [ ] **Step 5: Run the full suite to verify it passes**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: PASS — golden digest matches; reading-order, no-mud, and baseline-grid acceptance testsets green.

- [ ] **Step 6: Commit**

```bash
git add examples/glyph_wave/test/test_golden.jl examples/glyph_wave/test/test_acceptance.jl examples/glyph_wave/test/golden/layout_table.sha256 examples/glyph_wave/test/runtests.jl
git commit -m "test(glyph_wave): layout-table golden digest + reading-order/no-mud/baseline acceptance gates"
```

---

### Task 9: Squint-test MERGE GATE (silhouette IoU) + README

The HARD merge gate: downsample the render to 64 px + blur, threshold to a silhouette, and assert IoU vs the **real Great Wave `foam_mask`** (the actual painting silhouette) ≥ threshold, with a scrambled-text control run calibrating the threshold (the rendered wave must clear it AND beat the noise control). A second, separate testset is a regression anchor: IoU vs the committed self-rendered reference PNG (catches drift, not correctness). Plus the piece README.

**Files:**
- Create: `examples/glyph_wave/test/test_squint.jl`
- Create: `examples/glyph_wave/test/golden/squint_reference.png`
- Create: `examples/glyph_wave/README.md`
- Modify: `examples/glyph_wave/test/runtests.jl`

- [ ] **Step 1: Write the squint helpers + failing test**

Create `examples/glyph_wave/test/test_squint.jl`:
```julia
# SPDX-License-Identifier: MIT
using GlyphWave, Test, FileIO, Images, ImageTransformations

"Downsample to 64px wide, blur, threshold to a binary silhouette."
function _squint(path::AbstractString)
    img = Float64.(Gray.(load(path)))
    small = imresize(img, (round(Int, 64 * size(img, 1) / size(img, 2)), 64))
    blurred = imfilter(small, Kernel.gaussian(1.5))
    thr = sum(blurred) / length(blurred)         # mean threshold
    return blurred .< thr                        # true = ink (the wave/Fuji silhouette)
end

_iou(a::BitMatrix, b::BitMatrix) = sum(a .& b) / max(1, sum(a .| b))

"Resize a binary mask `b` to match `a`'s shape and re-threshold to a BitMatrix."
_fit(a, b) = BitMatrix(imresize(b, size(a)) .> 0.5)

# Render a piece (given the canvas text) to a temp PNG via the real pipeline.
function _render_piece(out, text)
    small = GlyphWave.load_luminance(joinpath(pkgdir(GlyphWave), "assets", "great_wave.png"))
    W, H = 3000, 2000; cell = GlyphWave.SIZE_MAX
    rl = imresize(small, (ceil(Int, H/cell), ceil(Int, W/cell)))
    mask = GlyphWave.foam_mask(rl); sat = GlyphWave.box_mean_sampler(rl)
    _, table = GlyphWave.pack_into(text, mask, cell; sample=(i0,j0,i1,j1)->sat(i0,j0,i1,j1))
    GlyphWave.render_table(table, out; width=W, height=H)
    return out
end

_render_full(out) = _render_piece(out, GlyphWave.canvas_text())

"The ground-truth Great Wave silhouette: the foam mask itself, run through the 64px squint pipeline."
function _truth_silhouette()
    small = GlyphWave.load_luminance(joinpath(pkgdir(GlyphWave), "assets", "great_wave.png"))
    cell = GlyphWave.SIZE_MAX
    rl = imresize(small, (ceil(Int, 2000/cell), ceil(Int, 3000/cell)))
    mask = GlyphWave.foam_mask(rl)               # true = ink (the wave/Fuji); false = foam/sky
    sm = imresize(Float64.(mask), (round(Int, 64 * size(mask,1) / size(mask,2)), 64))
    blurred = imfilter(sm, Kernel.gaussian(1.5))
    return blurred .> (sum(blurred)/length(blurred))   # true = ink, same polarity as `_squint`
end

@testset "squint test — HARD MERGE GATE: silhouette IoU vs the real Great Wave" begin
    # GATE: the rendered type must reconstruct the ACTUAL painting silhouette (the foam mask),
    # not merely a previously-self-rendered PNG. A self-comparison only catches regressions.
    out = joinpath(mktempdir(), "full.png")
    _render_full(out)
    got   = _squint(out)
    truth = _truth_silhouette()
    iou_truth = _iou(got, _fit(got, truth))
    @info "squint IoU vs real Great Wave foam_mask" iou_truth

    # Calibration control: scrambled reading order should NOT reproduce the wave nearly as well.
    # Its IoU sets the floor the gate must clear (the wave-vs-noise margin), so the threshold is
    # not an arbitrary constant. Use a fixed seed for determinism.
    import Random
    words = split(GlyphWave.canvas_text())
    scrambled = join(Random.shuffle(Random.MersenneTwister(1906), collect(words)), " ")
    sout = joinpath(mktempdir(), "scrambled.png")
    _render_piece(sout, scrambled)
    iou_ctrl = _iou(_squint(sout), _fit(_squint(sout), truth))
    @info "squint IoU control (scrambled text)" iou_ctrl

    # The real-wave IoU must clear the gate AND sit clearly above the scrambled control.
    @test iou_truth >= 0.55                       # MERGE GATE threshold (calibrated below the self-IoU, above the control)
    @test iou_truth > iou_ctrl + 0.05             # wave-vs-noise margin: order/tone carry the silhouette
end

@testset "squint regression anchor: silhouette IoU vs committed reference" begin
    # Regression-only (NOT the gate): drift vs the visually-verified master PNG.
    reffile = joinpath(@__DIR__, "golden", "squint_reference.png")
    @test isfile(reffile)
    out = joinpath(mktempdir(), "full.png")
    _render_full(out)
    got = _squint(out)
    ref = _squint(reffile)
    iou = _iou(got, _fit(got, ref))
    @info "squint IoU vs committed reference (regression anchor)" iou
    @test iou >= 0.90                             # tight: same pipeline vs frozen master ⇒ near-identical
end
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `golden/squint_reference.png` does not exist.

- [ ] **Step 3: Commit the reference silhouette (the VISUALLY-VERIFIED master)**

Render the full piece, **open it and confirm the wave reads at squint distance**, then copy that verified PNG as the reference:
```bash
julia --project=examples/glyph_wave -e '
using GlyphWave, FileIO, Images, ImageTransformations
text = GlyphWave.canvas_text()
small = GlyphWave.load_luminance(joinpath(pkgdir(GlyphWave), "assets", "great_wave.png"))
W,H = 3000,2000; cell = GlyphWave.SIZE_MAX
rl = imresize(small, (ceil(Int,H/cell), ceil(Int,W/cell)))
mask = GlyphWave.foam_mask(rl); sat = GlyphWave.box_mean_sampler(rl)
_, table = GlyphWave.pack_into(text, mask, cell; sample=(i0,j0,i1,j1)->sat(i0,j0,i1,j1))
GlyphWave.render_table(table, "examples/glyph_wave/test/golden/squint_reference.png"; width=W, height=H)
println("wrote squint reference")
'
```
Then OPEN `examples/glyph_wave/test/golden/squint_reference.png` and confirm the Great Wave silhouette is unmistakable. **Only commit it once it visually passes** — the reference IS the squint-gate ground truth, so a bad reference defeats the gate. If it does not read, return to Task 7 tuning (constants / 3-tone fallback) before committing.

- [ ] **Step 4: Run the squint test to verify it passes**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: PASS — `squint IoU vs real Great Wave foam_mask` logged ≥ 0.55 AND comfortably above the logged `squint IoU control (scrambled text)`; the separate regression anchor logs `squint IoU vs committed reference` ≥ 0.90. Tune the `0.55` gate to sit below the wave's real-mask IoU but clearly above the scrambled control's IoU (record both logged values and the chosen threshold if changed). If the scrambled control scores nearly as high as the real run, the silhouette is being carried by the mask alone, not by tone/order — return to Task 7 tuning before committing.

- [ ] **Step 5: Write the README**

Create `examples/glyph_wave/README.md`:
```markdown
# The Glyph Wave

Hokusai's *Great Wave* (Met object 45434, CC0) reproduced entirely in measured type:
each word run's size/weight/colour is sampled from the tone beneath it, so the painting
emerges from continuous, readable Strange-1906 prose flowed through `shape_pack` into the
wave silhouette. Reads as text at arm's length; as the wave across the room.

## Run

    julia --project=examples/glyph_wave -e 'using Pkg; Pkg.instantiate(); Pkg.test()'

Render the full piece (writes a PNG you should open and verify):

    julia --project=examples/glyph_wave -e 'include("examples/glyph_wave/scripts/render.jl")'

## What's engine vs orchestration

Engine (in-contract): `prepare`/`measure` (exact advances, no kerning, matches Makie),
`shape_pack`/`RasterChordFn`, per-run size/weight/colour (Makie paints). Orchestration
(this package): image load + summed-area sampling, the luminance→size/weight + colour-snap
tone-map, the foam mask, and the **merged `Prepared`** (per-segment widths under a single
`FontMetrics`, `line_advance = lineheight × size_max`). No glyph rotation/warp/justify/CJK.

## Gates

- Golden = `HouseStyle.digest_rows` of the layout table (deterministic; NOT the PNG bytes).
- Acceptance: reading-order (overflow-exempt), no-mud collinearity, uniform baseline grid.
- **Squint test = HARD MERGE GATE**: 64px+blur silhouette IoU vs the real Great Wave `foam_mask`,
  calibrated by a scrambled-text control. A separate regression anchor compares vs the committed
  `test/golden/squint_reference.png` (drift only, not the gate).

Asset: CC0, see `assets/SOURCE.txt`. Fonts: Fraunces OFL, see `examples/fonts/Fraunces/`.
```

Append to `examples/glyph_wave/test/runtests.jl` inside the `@testset`:
```julia
    include("test_squint.jl")
```

- [ ] **Step 6: Run the full suite a final time**

Run:
```bash
julia --project=examples/glyph_wave -e 'using Pkg; Pkg.test()'
```
Expected: PASS — every testset green, squint IoU above threshold.

- [ ] **Step 7: Commit**

```bash
git add examples/glyph_wave/test/test_squint.jl examples/glyph_wave/test/golden/squint_reference.png examples/glyph_wave/README.md examples/glyph_wave/test/runtests.jl
git commit -m "test(glyph_wave): squint-test merge gate (silhouette IoU) + README"
```

---

## Self-review notes

**1. Spec coverage:**
- One bold move / merged-`Prepared` round-trip (riskiest, FIRST) → Task 1. ✅ Gates everything.
- Acceptance test 1 (reading order, overflow-exempt) → Task 8 `test_acceptance`. ✅
- Acceptance test 2 (squint, HARD MERGE GATE) → Task 9 `test_squint` (IoU vs the real Great Wave `foam_mask`, calibrated by a scrambled-text control; committed-reference IoU kept as a separate regression anchor). ✅
- Acceptance test 3 (no-mud collinearity) → Tasks 5 + 8. ✅
- Acceptance test 4 (uniform baseline grid) → Task 8. ✅
- Source asset (CC0 object 45434, committed + SOURCE.txt, no build-time fetch) → Task 3. ✅
- Image pipeline: luminance / summed-area table / 5-ink CIELAB snap / foam mask → Tasks 3–4. ✅
- Tone ramp (γ=0.45, 6 weights × 4 sizes, weight-primary) → Task 5. ✅
- 6-step ramp decision → 3 missing Fraunces statics → Task 2. ✅
- Measure-at-chosen-size: K=4 bucket prepares + pre-pass + real merged pack → Task 6. ✅
- Render: group-by-weight `text!`, font-by-path, PNG-not-SVG, 3000×2000, `px_per_unit=1` → Task 7. ✅
- `fontsize`-as-vector probe AFTER the merged-`Prepared` prototype + sub-group fallback → Task 7. ✅
- Golden = hash the layout table (not the PNG) → Task 8 via `HouseStyle.digest_rows`. ✅
- Text: PD Strange-1906 credo verbatim + Strange's OWN prose bulk-fill → Task 7. ✅
- OPEN the PNG / visual sign-off (green ≠ sign-off) → Task 7 Step 7, Task 9 Step 3. ✅
- Posterize+Bayer 3-tone fallback held in reserve → flagged in Task 7 Step 7. ✅

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to Task N". Every code step shows full code; every run step shows the exact command + expected output. The two values an executor MUST verify-then-fill (not invent) are the **golden digest** (Task 8 Step 3 generates it from the verified fixture) and the **squint reference + IoU threshold** (Task 9 Steps 3–4, generated from a visually-confirmed master) — both are computed artifacts, not guessable constants, so they are produced by a documented command rather than hardcoded.

**3. Type consistency:** `merged_prepared(words, widths; space_width, lineheight, size_max)` (Task 1) is reused verbatim in `pack_into` (Task 6). `Run(segment_index, x, y, fontsize, weight, colour, str)` is defined in Task 6 and consumed by `render_table` (Task 7), `test_golden` (Task 8), `test_acceptance` (Task 8). `Tone(weight_rank, weight, size_bucket, fontsize)` (Task 5) feeds `pack_into` (Task 6). `assign_tone`/`WEIGHTS`/`NWEIGHTS`/`SIZE_MIN`/`SIZE_MAX`/`NBUCKETS` are defined in Task 5 and referenced consistently in Tasks 6/8. `HouseStyle.fraunces("9pt-<weight>")` (the Foundation helper, no local wrapper) is the single font-path call, used in `bucket_prepares` (Task 6) and `render_table` (Task 7) with the BARE weight to avoid double-prefixing. `box_mean_sampler`/`snap_ink`/`foam_mask`/`load_luminance` (Tasks 3–4) are used in Tasks 6/8/9. `HouseStyle.digest_rows` (Foundation) is the single golden hasher.

**Flagged risks / things the executor must confirm during build (not blockers, but watch):**
- **Merged-index ↔ source-index mapping** in `pack_into` builds an EXPLICIT `merged_seg_index ⇒ source_word_index` map (`merged_to_src`/`merged_to_word`) by walking the actual merged `:word` segments, and reconstruction looks up tone/colour/word by the placement's ACTUAL `segment_index`. It does NOT assume placed indices are a dense `1,3,5,…` run — under `fill=:all` into a holey foam mask, words drop/skip, which would make a `(seg+1)÷2` shortcut mis-map or index out of range after the first gap. The Task 6 holey-mask test punches interior holes and asserts every surviving row maps to its own source word.
- **`IntegralArray` mean-by-slice** (`iL[i0:i1, j0:j1]/n`) — range-indexing semantics are version-dependent; if the pinned IntegralArrays version exposes box sums via corner indexing instead of slicing, `box_mean_sampler` needs the corner formula. The Task 4 test pins the contract with both a degenerate 2×2 AND a non-trivial 4×4 interior/off-corner box (distinct values), so an off-by-one or differing range convention is caught immediately before later tasks build on the sampler.
- **`fontsize`-as-vector** is probed by an OBSERVABLE bbox round-trip (the enlarged glyph must grow the bounding box), NOT by catching a throw — Makie may silently broadcast instead of erroring (Task 7). The sub-group fallback is wired into `render_table` so a `false` probe still renders.
- **Squint IoU threshold (0.55)** is a starting value the GATE checks against the real Great Wave `foam_mask`; it is calibrated to sit clearly above the scrambled-text control's IoU (the wave-vs-noise margin) and below the regression anchor's tight self-IoU (≥0.90). Documented as tunable in Task 9 Step 4 — record both logged IoUs if the threshold changes.
```