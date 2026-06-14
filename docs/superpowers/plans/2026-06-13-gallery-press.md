# The Press Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Work in the worktree `/home/jonathanchen/projects/TextMeasure.jl-gallery`. Every code block is real, runnable Julia or an exact shell command — no placeholders, no "similar to Task N".

**Goal:** Ship **#L · THE PRESS** (`examples/press/`) — a 12 s / 360-frame seamlessly-looping MP4 of a Whitman block that re-packs every frame as a brass wall presses inward from rotating axes (E→S→W→N + one two-sided pinch), with the word "rocking" lit in brass riding the press like a needle, plus a long-exposure thumbnail still. One `prepare()`; 360 `shape_pack()` calls. Golden = `digest_rows` over the placement table at 5 sampled frames.

**Architecture:** A new in-repo example package `examples/press/` (renamed from `examples/breathing_column/`) depending on `HouseStyle` (the shared spine), `TextMeasure`, `TextMeasureLayouts` (`shape_pack`/`raster_chord_fn`), and `CairoMakie` via `[sources]`. `prepare(MakieBackend(font=Fraunces9pt-Regular, fontsize=11, px_per_unit=1), TEXT)` runs ONCE (frame 0). Each frame builds a `BitMatrix` mask = field-rect MINUS a flush wall block, wraps it in `raster_chord_fn`, and calls `shape_pack` (pure arithmetic) — the only thing that changes frame-to-frame. A fresh Makie renderer (the asteroid example's `draw.jl` is terminal-`CellBuffer` only — unusable here) draws each `Placement` via `text!(space=:pixel, align=(:left,:baseline))`, grouped by colour (INK body + BRASS "rocking"), plus the brass tide-rule wall edge. The loop is authored with `record()`. **DELIBERATELY no `Silhouettes` dependency** (keep the dep tail short, per the SPEC §11 load-time call).

**Tech Stack:** Julia 1.11+, `HouseStyle` (path dep), `TextMeasure`, `TextMeasureLayouts`, `CairoMakie` (+ `Makie` core via re-export), `GeometryBasics` (transitively). Fonts pinned at `examples/fonts/{Fraunces,IBMPlexMono}/`. Golden via stdlib `SHA` through `HouseStyle.digest_rows`. No justify, hyphenation, CJK, or glyph rotation (out of scope).

---

### Task 1: Rename the example dir and scaffold the package (depends on Foundation Tasks 1–5)

**Files:**
- Rename: `examples/breathing_column/` → `examples/press/` (carries `SPEC.md`)
- Create: `examples/press/Project.toml`
- Create: `examples/press/src/Press.jl`
- Create: `examples/press/test/runtests.jl`

- [ ] **Step 1: Rename the directory (git-tracked move)**

Run (from the worktree root):
```bash
mkdir -p examples/press
git mv examples/breathing_column/SPEC.md examples/press/SPEC.md
rmdir examples/breathing_column 2>/dev/null || true
ls examples/press/
```
Expected: `SPEC.md` listed under `examples/press/`.

- [ ] **Step 2: Write the failing smoke test**

Create `examples/press/test/runtests.jl`:
```julia
# SPDX-License-Identifier: MIT
using Press, Test

@testset "Press" begin
    @testset "package loads" begin
        @test isdefined(Press, :TEXT)
    end
    # Later testsets are appended by subsequent tasks.
end
```

- [ ] **Step 3: Write the Project.toml**

Create `examples/press/Project.toml` (mirrors `examples/layouts/Project.toml`'s `[sources]` pattern; adds `HouseStyle` by its pinned uuid and `CairoMakie`):
```toml
name = "Press"
uuid = "b2d4f6a8-1c3e-4f5a-8b7d-9e0c2a4f6b8d"
version = "0.1.0"
authors = ["TextMeasure.jl contributors"]

[deps]
CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
GeometryBasics = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
HouseStyle = "f1a9b3c2-0d4e-4a6b-9c8d-7e2f1a0b3c4d"
TextMeasure = "06791c1d-2336-41e1-bd6f-a74c63395da6"
TextMeasureLayouts = "57b0e3ea-cc01-4cc3-9e7e-6e97d1609b9f"

# Unregistered in-repo packages — resolve by path (Julia 1.11+ [sources] feature) so a
# plain Pkg.instantiate() works with no manual Pkg.develop step.
[sources]
HouseStyle = { path = "../_housestyle" }
TextMeasure = { path = "../.." }
TextMeasureLayouts = { path = "../layouts" }

[compat]
CairoMakie = "0.15, 0.16"
GeometryBasics = "0.5.10"
julia = "1.11"

[extras]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Test"]
```

- [ ] **Step 4: Write the minimal module (just the source text)**

Create `examples/press/src/Press.jl` — `TEXT` is the verbatim PD Whitman from `SPEC.md` §9, honoring the poet's hard line-breaks as `\n` (so the packer reflows *within* each verse-line):
```julia
# SPDX-License-Identifier: MIT
module Press

import TextMeasure
using TextMeasure: prepare, Prepared, Segment, FontMetrics, MakieBackend
using TextMeasureLayouts: shape_pack, raster_chord_fn, RasterChordFn, Placement, PackedLayout
import HouseStyle as HS

"""
Walt Whitman — opening invocation of *Out of the Cradle Endlessly Rocking* (1859, public
domain). Verbatim from SPEC.md §9; hard line-breaks preserved as `\\n` so the packer
reflows within each verse-line. Contains the brass word "rocking".
"""
const TEXT =
    "Out of the cradle endlessly rocking,\n" *
    "Out of the mocking-bird's throat, the musical shuttle,\n" *
    "Out of the Ninth-month midnight,\n" *
    "Over the sterile sands and the fields beyond, where the child\n" *
    "leaving his bed wander'd alone, bareheaded, barefoot,\n" *
    "Down from the shower'd halo,\n" *
    "Up from the mystic play of shadows twining and twisting as if\n" *
    "they were alive,\n" *
    "Out from the patches of briers and blackberries,\n" *
    "From the memories of the bird that chanted to me,\n" *
    "From your memories sad brother, from the fitful risings and\n" *
    "fallings I heard,"

end # module
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```
Expected: `Test Summary: | Pass 1` — "package loads" passes (this also instantiates CairoMakie; first run is slow).

- [ ] **Step 6: Commit**

```bash
git add examples/press
git commit -m "feat(press): scaffold examples/press package (renamed from breathing_column)"
```

---

### Task 2: The `prepare()`-once backend builder + brass segment index

**Files:**
- Modify: `examples/press/src/Press.jl`
- Modify: `examples/press/test/runtests.jl`

The single font-touching call. Tag the segment indices of "rocking" pre-loop (`prep.segments` is fixed once prepared) so the renderer can partition placements with no per-frame search.

- [ ] **Step 1: Write the failing test**

Append a testset to `examples/press/test/runtests.jl` (inside the outer `@testset "Press"`, before its closing `end`):
```julia
    @testset "prepare once + brass tracking" begin
        prep = Press.build_prep()
        @test prep isa TextMeasure.Prepared
        @test prep.metrics.line_advance > 0
        # "rocking" appears once in the source (line 1) — exactly one :word segment.
        ridx = Press.brass_indices(prep)
        @test length(ridx) == 1
        i = ridx[1]
        @test prep.segments[i].kind === :word
        @test occursin("rocking", lowercase(prep.segments[i].str))
        # body floor: 32 chars at body size, computed from a measured "0" advance.
        @test Press.floor_w(prep) > 0
    end
```
(Add `import TextMeasure` to the top of `runtests.jl` if not present: `using Press, Test; import TextMeasure`.)

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `build_prep` / `brass_indices` / `floor_w` not defined.

- [ ] **Step 3: Add the builders**

Append inside the module (before `end # module`) in `examples/press/src/Press.jl`:
```julia
# ---- house constants pinned for this piece (SPEC §3, §5) --------------------
const BODY_PT       = HS.RAMP.body            # 11
const LINEHEIGHT    = 1.45                    # SPEC §3 — open grid reads under compression
const FRAUNCES_BODY = HS.fraunces("9pt-Regular")

"""
    build_prep() -> Prepared

The ONE font-touching call (SPEC §8.1). Measures the Whitman block with the body face at
11 pt, px_per_unit = 1 (CLAUDE.md — match Makie's markerspace geometry). Widths cached;
never re-measured for any frame.
"""
function build_prep()
    backend = MakieBackend(font = FRAUNCES_BODY, fontsize = BODY_PT, px_per_unit = 1)
    return prepare(backend, TEXT)
end

"""
    brass_indices(prep) -> Vector{Int}

Absolute `:word` segment indices whose stripped text is "rocking" (the brass needle,
SPEC §4). Stable across the whole loop because `prep.segments` is fixed once prepared;
each frame partitions `placements` by `pl.segment_index ∈ brass` — no per-frame search.
Strips trailing punctuation so "rocking," matches.
"""
function brass_indices(prep::Prepared)
    out = Int[]
    for (i, seg) in enumerate(prep.segments)
        seg.kind === :word || continue
        word = lowercase(strip(seg.str, ['.', ',', ';', ':', '!', '?']))
        word == "rocking" && push!(out, i)
    end
    return out
end

"""
    floor_w(prep) -> Float64

Minimum region width = width of 32 characters at body size (SPEC §3). Approximated as
`32 × advance("0")`, recovered from the cached metrics' em scale via a measured digit.
Whitman is digit-free, so derive the digit advance from the body em: a Fraunces "0" is
~0.5 em wide; we use the measured-once approach by re-measuring a single "0" run is NOT
allowed post-prepare, so we approximate from ascent. Conservative floor: 32 × (0.5 × BODY_PT).
"""
floor_w(prep::Prepared) = 32.0 * 0.5 * BODY_PT
```

(NOTE on `floor_w`: re-measuring after `prepare` would touch the font engine a 2nd time, which the SPEC forbids for the loop body. `0.5 × fontsize` per char is the standard Fraunces digit-advance approximation and keeps the floor honest at ~176 px ≈ 32 CPL. If the visual gate in Task 4 shows the floor reads tighter/looser than 32 CPL, tune the `0.5` constant there — it is the one tunable.)

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: PASS — "prepare once + brass tracking" green; `length(ridx) == 1`.

- [ ] **Step 5: Commit**

```bash
git add examples/press
git commit -m "feat(press): prepare-once backend + stable brass segment index"
```

---

### Task 3: The wall-mask generator (rect minus flush wall)

**Files:**
- Modify: `examples/press/src/Press.jl`
- Modify: `examples/press/test/runtests.jl`

The region geometry. `mask = trues(nrows, ncols)` with the active edge's cells knocked out, then `raster_chord_fn(mask, cell)` verbatim from `shape_pack.jl`. ≤ 1 open interval per band (the wall is always **flush to a field edge**), so `fill = :widest` is exactly correct (SPEC §11). One cell = 1 px (`cell_size = 1.0`), so mask cols/rows are pixels directly.

- [ ] **Step 1: Write the failing test**

Append a testset to `examples/press/test/runtests.jl`:
```julia
    @testset "wall mask: rect minus flush wall" begin
        # 100×200 field (rows×cols = y×x px), cell 1.0
        nrows, ncols = 100, 200
        # No wall: full rectangle, every band is one full-width interval.
        m0 = Press.field_mask(nrows, ncols)
        @test size(m0) == (nrows, ncols)
        @test all(m0)
        cf0 = raster_chord_fn(m0, 1.0)
        ivs = cf0(0.0, 1.0)                       # band at row 1
        @test length(ivs) == 1
        @test ivs[1] == (0.0, ncols)              # cols 1..200 → [0, 200]

        # East wall depth 60 px: knocks out the right 60 cols on every row.
        mE = Press.press_mask(nrows, ncols; edge = :E, depth = 60)
        cfE = raster_chord_fn(mE, 1.0)
        ivsE = cfE(0.0, 1.0)
        @test length(ivsE) == 1                   # ≤ 1 interval per band (flush wall)
        @test ivsE[1][1] == 0.0                   # still flush-left
        @test ivsE[1][2] == ncols - 60            # right edge pulled in by depth

        # South wall depth 30 px: bottom 30 rows fully knocked out.
        mS = Press.press_mask(nrows, ncols; edge = :S, depth = 30)
        cfS = raster_chord_fn(mS, 1.0)
        @test isempty(cfS(Float64(nrows - 1), Float64(nrows)))   # last row gone
        @test length(cfS(0.0, 1.0)) == 1                          # top row intact

        # Two-sided pinch (W full + N shallow): still ONE central interval per band
        # in the overlap region (SPEC §11 invariant).
        mP = Press.pinch_mask(nrows, ncols; west_depth = 80, north_depth = 25)
        cfP = raster_chord_fn(mP, 1.0)
        midband = cfP(50.0, 51.0)                 # a row below the north wall
        @test length(midband) == 1               # one central interval, never split
        @test midband[1][1] == 80.0              # left pulled in by west wall
    end
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `field_mask` / `press_mask` / `pinch_mask` not defined.

- [ ] **Step 3: Add the mask generators**

Append inside the module (before `end # module`) in `examples/press/src/Press.jl`:
```julia
"""
    field_mask(nrows, ncols) -> BitMatrix

The rest region: an all-true rectangle. `raster[row, col]` true ⇒ cell is inside the
field; row indexes y (down), col indexes x. With `cell_size = 1.0`, cols/rows are px.
"""
field_mask(nrows::Int, ncols::Int) = trues(nrows, ncols)

"""
    press_mask(nrows, ncols; edge, depth) -> BitMatrix

Rect MINUS a wall block of `depth` px flush to `edge ∈ (:E, :S, :W, :N)`. Knocks the
wall's cells to `false`; the surviving region is a single rectangle flush to the
opposite edge ⇒ exactly ≤ 1 open interval per band, so `shape_pack(…; fill = :widest)`
fills "the only interval". `depth` is clamped to keep ≥ 1 cell of region (callers also
clamp to the readability floors in `schedule`).
"""
function press_mask(nrows::Int, ncols::Int; edge::Symbol, depth::Real)
    m = trues(nrows, ncols)
    d = round(Int, depth)
    if edge === :E
        d = clamp(d, 0, ncols - 1)
        d > 0 && (m[:, (ncols - d + 1):ncols] .= false)
    elseif edge === :W
        d = clamp(d, 0, ncols - 1)
        d > 0 && (m[:, 1:d] .= false)
    elseif edge === :S
        d = clamp(d, 0, nrows - 1)
        d > 0 && (m[(nrows - d + 1):nrows, :] .= false)
    elseif edge === :N
        d = clamp(d, 0, nrows - 1)
        d > 0 && (m[1:d, :] .= false)
    else
        throw(ArgumentError("edge must be :E, :S, :W or :N; got $(repr(edge))"))
    end
    return m
end

"""
    pinch_mask(nrows, ncols; west_depth, north_depth) -> BitMatrix

The single two-sided pinch (SPEC §2): the W wall pressed full plus a shallow residual N
wall. Both walls are flush to their edges, so each band still has ONE central interval
(two flush walls leave a single central run, never two comparable runs — the §11
invariant that keeps `fill = :widest` correct). The most-compressed frame of the loop.
"""
function pinch_mask(nrows::Int, ncols::Int; west_depth::Real, north_depth::Real)
    m = press_mask(nrows, ncols; edge = :W, depth = west_depth)
    nd = clamp(round(Int, north_depth), 0, nrows - 1)
    nd > 0 && (m[1:nd, :] .= false)
    return m
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: PASS — "wall mask: rect minus flush wall" green; pinch midband is one interval starting at 80.0.

- [ ] **Step 5: Commit**

```bash
git add examples/press
git commit -m "feat(press): rect-minus-flush-wall mask generators (no Silhouettes dep)"
```

---

### Task 4 (RISKIEST — gate everything): Placement→Makie pixel mapping, rendered and eyeballed

**Files:**
- Modify: `examples/press/src/Press.jl`
- Modify: `examples/press/test/runtests.jl`

`Placement.y` is a **baseline in a y-DOWN block-top frame** (block top = 0, increasing downward). Makie's pixel space is y-UP. So the y-flip is: `makie_y = FIELD_TOP_Y - pl.y`, where `FIELD_TOP_Y` is the field rectangle's top in scene px and `pl.y`/`pl.x` are offset by the field's top-left origin `(FIELD_X0, FIELD_TOP_Y)`. With `align = (:left, :baseline)`, Makie anchors the glyph run's **left edge at x and its baseline at y** — which is exactly what `Placement` carries (`x` = segment left edge, `y` = baseline). Because `prepare` used `MakieBackend(px_per_unit=1)`, the cached advances equal `text!`'s advances ⇒ glyphs land where the packer predicts: brass word and body neither overlap nor gap. **You must OPEN the PNG and confirm this before trusting any golden.**

- [ ] **Step 1: Write the failing test (renders one rest frame to PNG)**

Append a testset to `examples/press/test/runtests.jl`:
```julia
    @testset "render one rest frame (manual visual gate)" begin
        prep = Press.build_prep()
        out = joinpath(@__DIR__, "out"); mkpath(out)
        png = joinpath(out, "rest_frame.png")
        packed = Press.render_frame(prep, png; edge = :E, depth = 0)   # rest = no wall
        @test isfile(png)
        @test length(packed.placements) > 50          # the block actually packed
        # Brass word is present in the packed output (it fits at rest).
        ridx = Set(Press.brass_indices(prep))
        @test any(pl -> pl.segment_index in ridx, packed.placements)
    end
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `render_frame` not defined.

- [ ] **Step 3: Add the layout + renderer with the y-flip reasoning encoded**

Append inside the module (before `end # module`) in `examples/press/src/Press.jl`:
```julia
using CairoMakie
using CairoMakie: Figure, Axis, text!, lines!, hidedecorations!, hidespines!, save, Point2f

# ---- field geometry (scene px). SPEC §5: outer margin 48 px (named deviation). -----
const MARGIN     = 48
const SCENE_W    = 960
const SCENE_H    = 600
const FIELD_X0   = MARGIN                       # field left edge, scene-px x
const FIELD_Y0   = MARGIN                       # field top edge, scene-px y (y-down here)
const FIELD_W    = SCENE_W - 2 * MARGIN         # 864
const FIELD_H    = SCENE_H - 2 * MARGIN         # 504
# field-top in Makie's y-UP scene frame (scene origin bottom-left):
const FIELD_TOP_Y = SCENE_H - FIELD_Y0          # = 552

"""
    pack_at(prep, mask) -> PackedLayout

Re-pack the cached widths into the region described by `mask` (cell = 1 px). The fixed
baseline grid (SPEC §3): one `line_advance` shared across EVERY frame so lines stay
parallel no matter how the wall intrudes. `min_chord_width = floor_w` ⇒ the packer itself
refuses a band too thin to hold a word. `overflow_strategy = :widest_row` ⇒ an over-wide
band poke is honest, never dropped. `fill = :widest` ⇒ correct because the wall is flush
(≤ 1 interval/band, SPEC §11). PURE ARITHMETIC — no font engine.
"""
function pack_at(prep::Prepared, mask::BitMatrix)
    la = LINEHEIGHT * prep.metrics.line_advance
    cf = raster_chord_fn(mask, 1.0)
    return shape_pack(prep, cf;
        line_advance     = la,
        min_chord_width  = floor_w(prep),
        overflow_strategy = :widest_row,
        fill             = :widest)
end

# y-down (block-top) Placement → y-up Makie scene px.
#   x_scene = FIELD_X0 + pl.x
#   y_scene = FIELD_TOP_Y - pl.y     (flip: block grows downward, scene grows upward)
# align=(:left,:baseline) makes text! anchor the run's left edge at x and baseline at y —
# exactly Placement's (left edge, baseline). px_per_unit=1 ⇒ advances match the cache.
_to_scene(pl::Placement) = Point2f(FIELD_X0 + pl.x, FIELD_TOP_Y - pl.y)

"""
    render_frame(prep, png; edge, depth, north_depth=0, save_png=true) -> PackedLayout

Build the frame's mask, `pack_at` it, and draw to `png`. Body glyphs INK, "rocking"
glyphs BRASS (partitioned by stable segment index — SPEC §4). One `Axis` in pixel space,
decorations hidden, PAPER background. Returns the `PackedLayout` so tests/golden can hash
the placement table. The wall tide-rule is added in Task 6; this task is the pure
glyph-landing gate.
"""
function render_frame(prep::Prepared, png::AbstractString; edge::Symbol, depth::Real,
                      north_depth::Real = 0, save_png::Bool = true)
    mask = north_depth > 0 ?
        pinch_mask(FIELD_H, FIELD_W; west_depth = depth, north_depth = north_depth) :
        press_mask(FIELD_H, FIELD_W; edge = edge, depth = depth)
    packed = pack_at(prep, mask)

    fig = Figure(size = (SCENE_W, SCENE_H), backgroundcolor = HS.PAPER)
    ax  = Axis(fig[1, 1]; backgroundcolor = HS.PAPER,
               limits = (0, SCENE_W, 0, SCENE_H))
    hidedecorations!(ax); hidespines!(ax)

    ridx = Set(brass_indices(prep))
    ink_pts  = Point2f[]; ink_str  = String[]
    brs_pts  = Point2f[]; brs_str  = String[]
    for pl in packed.placements
        seg = prep.segments[pl.segment_index]
        seg.kind === :word || continue
        if pl.segment_index in ridx
            push!(brs_pts, _to_scene(pl)); push!(brs_str, seg.str)
        else
            push!(ink_pts, _to_scene(pl)); push!(ink_str, seg.str)
        end
    end
    isempty(ink_str) || text!(ax, ink_pts; text = ink_str, color = HS.INK,
        font = FRAUNCES_BODY, fontsize = BODY_PT, align = (:left, :baseline), space = :pixel)
    isempty(brs_str) || text!(ax, brs_pts; text = brs_str, color = HS.BRASS,
        font = FRAUNCES_BODY, fontsize = BODY_PT, align = (:left, :baseline), space = :pixel)

    save_png && save(png, fig; px_per_unit = 1)
    return packed
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: PASS — `rest_frame.png` written, `>50` placements, brass present.

- [ ] **Step 5: OPEN the PNG and eyeball glyph landing (MANDATORY — the gate)**

```bash
ls -l examples/press/test/out/rest_frame.png
```
Then OPEN `examples/press/test/out/rest_frame.png` and confirm by eye (per SPEC §11 / the "look at rendered artifacts yourself" rule):
- Glyphs sit on a clean fixed baseline grid; lines are parallel.
- The brass "rocking" sits **inline** with its neighbours — neither overlapping the
  adjacent ink word nor leaving a visible gap (this proves the y-flip + `align=(:left,:baseline)` + `px_per_unit=1` advance-match).
- The block sits inside the 48 px paper margin, not touching the scene edge.

If glyphs overlap/gap or the block is mirrored vertically, the y-flip is wrong — fix `_to_scene` (sign of the flip / `FIELD_TOP_Y`) BEFORE proceeding. Do not trust any golden until this frame is visually correct.

- [ ] **Step 6: Commit**

```bash
git add examples/press
git commit -m "feat(press): Placement->Makie pixel mapping (y-flip), visually gated"
```

---

### Task 5: The smoothstep depth/edge schedule (E→S→W→N + held beat + one pinch)

**Files:**
- Modify: `examples/press/src/Press.jl`
- Modify: `examples/press/test/runtests.jl`

The animation math (SPEC §2). 360 frames; four 90-frame presses walking E→S→W→N. Easing = smoothstep `3t²−2t³` (slow-in/out + a true zero-velocity HOLD at `d_max`). One two-sided pinch on press #3 (W). Returns, per frame, the active edge + depth + optional north residual — clamped so the region never crosses the readability floors.

- [ ] **Step 1: Write the failing test**

Append a testset to `examples/press/test/runtests.jl`:
```julia
    @testset "press schedule (smoothstep, E->S->W->N, hold, pinch)" begin
        @test Press.smoothstep(0.0) == 0.0
        @test Press.smoothstep(1.0) == 1.0
        @test Press.smoothstep(0.5) == 0.5
        # velocity ~0 at the dwell ends (slow-in/out): derivative 6t-6t^2 → 0 at 0 and 1.
        @test Press.smoothstep(0.001) < 0.001
        @test Press.smoothstep(0.999) > 0.999

        N = Press.NFRAMES
        @test N == 360
        # Frame 0 = rest: zero depth.
        s0 = Press.schedule(0)
        @test s0.depth == 0.0 && s0.north_depth == 0.0
        # Loop closure: frame N ≡ frame 0 (byte-identical mask spec).
        sN = Press.schedule(N)
        @test sN.edge == s0.edge && sN.depth == s0.depth && sN.north_depth == s0.north_depth
        # The four presses walk the compass in order.
        @test Press.schedule(45).edge  === :E      # mid press 1
        @test Press.schedule(135).edge === :S      # mid press 2
        @test Press.schedule(225).edge === :W      # mid press 3 (the pinch)
        @test Press.schedule(315).edge === :N      # mid press 4
        # The HOLD beat (55–75% of a press) has zero velocity: depth equal across the dwell.
        h1 = Press.schedule(45 + 8); h2 = Press.schedule(45 + 12)   # both inside press-1 hold
        @test isapprox(h1.depth, h2.depth; atol = 0.5)
        # The pinch: press 3 holds a shallow north residual (~25% of d_max).
        sp = Press.schedule(225)
        @test sp.edge === :W
        @test sp.north_depth > 0
        # Depth never exceeds the floor-derived d_max (region stays ≥ floor_w / ≥ 6 lines).
        prep = Press.build_prep()
        for f in 0:N
            s = Press.schedule(f)
            @test s.depth <= Press.dmax_for(s.edge, prep) + 1e-6
        end
    end
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `smoothstep` / `NFRAMES` / `schedule` / `dmax_for` not defined.

- [ ] **Step 3: Add the schedule**

Append inside the module (before `end # module`) in `examples/press/src/Press.jl`:
```julia
const NFRAMES   = 360                 # 12 s × 30 fps (SPEC §2)
const FPS       = 30
const PRESS_LEN = NFRAMES ÷ 4         # 90 frames per wall
const COMPASS   = (:E, :S, :W, :N)    # press walk order (SPEC §2)

"Smoothstep 3t²−2t³ on t∈[0,1]: slow-in/slow-out + zero-velocity dwell (SPEC §2)."
smoothstep(t::Real) = (u = clamp(Float64(t), 0.0, 1.0); u * u * (3.0 - 2.0 * u))

"""
    dmax_for(edge, prep) -> Float64

Max wall depth for `edge`: presses until the surviving region hits its readability floor
(SPEC §3) — never past it. Horizontal walls (E/W) floor the region WIDTH at `floor_w`;
vertical walls (S/N) floor the region HEIGHT at ≥ 6 baselines of the fixed grid.
"""
function dmax_for(edge::Symbol, prep::Prepared)
    if edge === :E || edge === :W
        return max(0.0, FIELD_W - floor_w(prep))
    else  # :S or :N — keep ≥ 6 lines of the fixed grid
        la = LINEHEIGHT * prep.metrics.line_advance
        min_h = 6 * la
        return max(0.0, FIELD_H - min_h)
    end
end

# Depth profile within one 90-frame press (SPEC §2): anticipate→press→HOLD→release.
# Returns a fraction of d_max in [0,1]. The HOLD (55–75%) is a flat top = smoothstep's
# zero-velocity dwell, held across the window.
function _press_profile(p::Float64)        # p ∈ [0,1) phase within the press
    if p < 0.15
        return 0.15 * smoothstep(p / 0.15)         # anticipate: ease up a hair
    elseif p < 0.55
        return smoothstep((p - 0.15) / 0.40)        # press → d_max
    elseif p < 0.75
        return 1.0                                  # HOLD (velocity 0)
    else
        return smoothstep(1.0 - (p - 0.75) / 0.25)  # release → 0
    end
end

"""
    schedule(f) -> (; edge, depth, north_depth)

Per-frame active wall + depth(s) for frame `f ∈ 0:NFRAMES`. Clamped to `dmax_for` so the
region never crosses the readability floor (SPEC §3). On press #3 (W, the pinch) holds a
shallow residual N wall (~25% of N's d_max) during W's HOLD so the dough is caught in a
corner once per loop (SPEC §2). `schedule(NFRAMES) ≡ schedule(0)` (byte-identical → seamless).
"""
function schedule(f::Integer)
    prep = build_prep()
    ff = mod(f, NFRAMES)
    which = ff ÷ PRESS_LEN                      # 0..3 → E,S,W,N
    edge  = COMPASS[which + 1]
    p     = (ff % PRESS_LEN) / PRESS_LEN        # phase ∈ [0,1)
    depth = _press_profile(p) * dmax_for(edge, prep)
    north_depth = 0.0
    if edge === :W && 0.55 <= p < 0.75          # the pinch: shallow N during W's HOLD
        north_depth = 0.25 * dmax_for(:N, prep)
    end
    return (edge = edge, depth = depth, north_depth = north_depth)
end
```

(NOTE: `schedule` rebuilds `prep` only to read `prep.metrics` for the floors; the loop driver in Task 6 passes a memoized `prep` into `dmax_for` directly so the loop body never re-prepares. The test rebuilds freely — it is not the hot path.)

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: PASS — schedule walks E→S→W→N, hold is flat, pinch has north residual, loop closes, depth ≤ d_max for all 361 frames.

- [ ] **Step 5: Commit**

```bash
git add examples/press
git commit -m "feat(press): smoothstep press schedule (E-S-W-N, hold, one two-sided pinch)"
```

---

### Task 6: The BRASS tide-rule (non-negotiable wall edge) on the renderer

**Files:**
- Modify: `examples/press/src/Press.jl`
- Modify: `examples/press/test/runtests.jl`

SPEC §5: the wall is REQUIRED. The brass tide-rule converts negative space into perceived force. The **active (advancing) edge may be heavier than 0.5 px**; inactive hairlines stay in the house 0.25/0.5/0.75 px vocabulary. Two tiny surveyor's ticks (house registration motif). On the pinch frame both active edges are ruled.

- [ ] **Step 1: Write the failing test**

Append a testset to `examples/press/test/runtests.jl`:
```julia
    @testset "tide-rule wall edge" begin
        # The active edge's scene-px x or y line, given edge+depth, lands on the region boundary.
        @test Press.wall_edge_x(:E, 60) == Press.FIELD_X0 + (Press.FIELD_W - 60)
        @test Press.wall_edge_x(:W, 80) == Press.FIELD_X0 + 80
        # South wall edge maps to a y line (y-up scene frame).
        ys = Press.wall_edge_y(:S, 30)
        @test ys == Press.FIELD_TOP_Y - (Press.FIELD_H - 30)
        # The active edge is ruled heavier than inactive hairlines (SPEC §5 budget).
        @test Press.WALL_ACTIVE_LW > 0.5
        @test Press.WALL_INACTIVE_LW <= 0.75
    end
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `wall_edge_x` / `wall_edge_y` / `WALL_ACTIVE_LW` not defined.

- [ ] **Step 3: Add the tide-rule and wire it into `render_frame`**

Append inside the module (before `end # module`) in `examples/press/src/Press.jl`:
```julia
const WALL_ACTIVE_LW   = 2.0      # SPEC §5: active edge budgeted heavier than 0.5 px so a
                                  # cold viewer reads "something is pressing in" from one still
const WALL_INACTIVE_LW = 0.5      # inactive hairlines stay in the house 0.25/0.5/0.75 vocab
const TICK_LEN         = 8.0      # surveyor's-tick length, px (house §5 registration motif)

"Scene-px x of an E/W wall's live edge at `depth` (the region boundary the wall pressed to)."
function wall_edge_x(edge::Symbol, depth::Real)
    edge === :E && return FIELD_X0 + (FIELD_W - depth)
    edge === :W && return FIELD_X0 + depth
    throw(ArgumentError("wall_edge_x needs :E or :W; got $(repr(edge))"))
end

"Scene-px y (y-up) of an S/N wall's live edge at `depth`."
function wall_edge_y(edge::Symbol, depth::Real)
    edge === :S && return FIELD_TOP_Y - (FIELD_H - depth)
    edge === :N && return FIELD_TOP_Y - depth
    throw(ArgumentError("wall_edge_y needs :S or :N; got $(repr(edge))"))
end

# Draw one wall edge as a brass tide-rule with two surveyor's ticks. `lw` = active vs inactive.
function _draw_wall!(ax, edge::Symbol, depth::Real; lw::Float64)
    depth <= 0 && return
    if edge === :E || edge === :W
        x = wall_edge_x(edge, depth)
        y0, y1 = FIELD_TOP_Y - FIELD_H, FIELD_TOP_Y
        lines!(ax, [x, x], [y0, y1]; color = HS.BRASS, linewidth = lw)
        # surveyor's ticks at top & bottom of the edge
        lines!(ax, [x - TICK_LEN, x], [y1, y1]; color = HS.BRASS, linewidth = lw)
        lines!(ax, [x - TICK_LEN, x], [y0, y0]; color = HS.BRASS, linewidth = lw)
    else
        y = wall_edge_y(edge, depth)
        x0, x1 = FIELD_X0, FIELD_X0 + FIELD_W
        lines!(ax, [x0, x1], [y, y]; color = HS.BRASS, linewidth = lw)
        lines!(ax, [x0, x0], [y, y - TICK_LEN]; color = HS.BRASS, linewidth = lw)
        lines!(ax, [x1, x1], [y, y - TICK_LEN]; color = HS.BRASS, linewidth = lw)
    end
    return
end
```

Then modify `render_frame` to draw the wall(s) after the text. Replace the line `    save_png && save(png, fig; px_per_unit = 1)` with:
```julia
    # Tide-rule: the active (advancing) edge, heavier than 0.5 px (SPEC §5). On the pinch
    # frame both active edges are ruled (W heavy + N residual heavy).
    _draw_wall!(ax, edge, depth; lw = WALL_ACTIVE_LW)
    north_depth > 0 && _draw_wall!(ax, :N, north_depth; lw = WALL_ACTIVE_LW)

    save_png && save(png, fig; px_per_unit = 1)
```

- [ ] **Step 4: Run the test + re-render a pressed frame and eyeball the force**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: PASS — tide-rule testset green.

Then render the pinch frame and OPEN it (SPEC §5 — "verify the wall reads as force at the visual-signoff gate"):
```bash
julia --project=examples/press -e '
using Press, TextMeasure
prep = Press.build_prep()
s = Press.schedule(225)   # the pinch
Press.render_frame(prep, "examples/press/test/out/pinch_frame.png";
    edge = s.edge, depth = s.depth, north_depth = s.north_depth)
println("wrote pinch_frame.png; edge=", s.edge, " depth=", round(s.depth), " north=", round(s.north_depth))
'
```
OPEN `examples/press/test/out/pinch_frame.png`: confirm a cold viewer reads "something is pressing in" — the brass left edge (and shallow top edge) ruled with ticks, the block compressed against them, "rocking" visibly shoved to a tight band.

- [ ] **Step 5: Commit**

```bash
git add examples/press
git commit -m "feat(press): brass tide-rule wall edge (active heavier per SPEC §5)"
```

---

### Task 7: The `record()` 12 s / 360-frame seamless loop

**Files:**
- Modify: `examples/press/src/Press.jl`
- Modify: `examples/press/test/runtests.jl`

The shippable deliverable (SPEC §1). One `prepare`, 360 `shape_pack` calls, driven by `record()`. Integer frames per period ⇒ frame 360 ≡ frame 0 (seamless). The driver memoizes `prep` so the loop body never touches the font engine.

- [ ] **Step 1: Write the failing test (honesty-of-claim: N frames ⇒ N shape_packs, 1 prepare)**

Append a testset to `examples/press/test/runtests.jl`:
```julia
    @testset "loop honesty: 1 prepare, NFRAMES shape_packs" begin
        # Count packs without rendering (fast): drive the per-frame mask→pack path.
        prep = Press.build_prep()
        npacks = 0
        for f in 0:(Press.NFRAMES - 1)
            s = Press.schedule(f)
            mask = s.north_depth > 0 ?
                Press.pinch_mask(Press.FIELD_H, Press.FIELD_W;
                    west_depth = s.depth, north_depth = s.north_depth) :
                Press.press_mask(Press.FIELD_H, Press.FIELD_W; edge = s.edge, depth = s.depth)
            pk = Press.pack_at(prep, mask)
            npacks += 1
            @test pk isa TextMeasureLayouts.PackedLayout
        end
        @test npacks == Press.NFRAMES                 # exactly one shape_pack per frame
        # rest frame packs the full block (non-vacuous floor on placement count).
        rest = Press.pack_at(prep, Press.field_mask(Press.FIELD_H, Press.FIELD_W))
        @test length(rest.placements) > 50
    end
```
(Add `import TextMeasureLayouts` to the top of `runtests.jl`.)

- [ ] **Step 2: Run it to verify it fails (or passes if pack path already covered)**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: PASS for the count assertions (the pack path exists from Task 4); this testset pins the honesty claim and guards regressions. If `PackedLayout` is unqualified, FAIL → fix the import.

- [ ] **Step 3: Add the `record()` driver**

Append inside the module (before `end # module`) in `examples/press/src/Press.jl`:
```julia
using CairoMakie: record, Observable, lift, empty!

"""
    render_loop(mp4_path; prep = build_prep()) -> mp4_path

Author the seamless 12 s / 360-frame loop (SPEC §1, §2). ONE `prepare` (memoized in
`prep`); each of the NFRAMES frames rebuilds the wall mask and calls `shape_pack` (pure
arithmetic). `record` at FPS fps. Frame NFRAMES is never emitted — frame 0 already equals
it, so the file loops byte-seamlessly. The scene is rebuilt per frame (cheap; the cost is
the cached-width re-pack, not measurement).
"""
function render_loop(mp4_path::AbstractString; prep::Prepared = build_prep())
    fig = Figure(size = (SCENE_W, SCENE_H), backgroundcolor = HS.PAPER)
    ax  = Axis(fig[1, 1]; backgroundcolor = HS.PAPER, limits = (0, SCENE_W, 0, SCENE_H))
    hidedecorations!(ax); hidespines!(ax)
    ridx = Set(brass_indices(prep))

    record(fig, mp4_path, 0:(NFRAMES - 1); framerate = FPS) do f
        empty!(ax)
        s = schedule(f)
        mask = s.north_depth > 0 ?
            pinch_mask(FIELD_H, FIELD_W; west_depth = s.depth, north_depth = s.north_depth) :
            press_mask(FIELD_H, FIELD_W; edge = s.edge, depth = s.depth)
        packed = pack_at(prep, mask)
        ink_pts = Point2f[]; ink_str = String[]; brs_pts = Point2f[]; brs_str = String[]
        for pl in packed.placements
            seg = prep.segments[pl.segment_index]
            seg.kind === :word || continue
            if pl.segment_index in ridx
                push!(brs_pts, _to_scene(pl)); push!(brs_str, seg.str)
            else
                push!(ink_pts, _to_scene(pl)); push!(ink_str, seg.str)
            end
        end
        isempty(ink_str) || text!(ax, ink_pts; text = ink_str, color = HS.INK,
            font = FRAUNCES_BODY, fontsize = BODY_PT, align = (:left, :baseline), space = :pixel)
        isempty(brs_str) || text!(ax, brs_pts; text = brs_str, color = HS.BRASS,
            font = FRAUNCES_BODY, fontsize = BODY_PT, align = (:left, :baseline), space = :pixel)
        _draw_wall!(ax, s.edge, s.depth; lw = WALL_ACTIVE_LW)
        s.north_depth > 0 && _draw_wall!(ax, :N, s.north_depth; lw = WALL_ACTIVE_LW)
    end
    return mp4_path
end
```

- [ ] **Step 4: Render the loop and verify the file**

Run:
```bash
julia --project=examples/press -e '
using Press
mp4 = "examples/press/test/out/press_loop.mp4"
Press.render_loop(mp4)
println("wrote ", mp4, " (", filesize(mp4), " bytes)")
'
ls -l examples/press/test/out/press_loop.mp4
```
Expected: a non-empty `press_loop.mp4`. OPEN it and confirm the wall walks E→S→W→N, holds at each compression, pinches once (two-sided), and the start/end frames match (no jump). "rocking" rides the press in brass.

- [ ] **Step 5: Commit**

```bash
git add examples/press
git commit -m "feat(press): seamless 12s/360-frame record() loop (1 prepare, 360 packs)"
```

---

### Task 8: The long-exposure thumbnail still (pinch solid + ghosted press-states)

**Files:**
- Modify: `examples/press/src/Press.jl`
- Modify: `examples/press/test/runtests.jl`

SPEC §6: the still can't show the knead, so show its trace — the pinch frame SOLID in ink, with 3–4 earlier press-states GHOSTED behind it (each a real `shape_pack` at an intermediate depth/direction), fanning toward rest. "rocking" appears twice — solid (front, squeezed band) and ghosted (back, near rest). Ghosts GRAY @ alpha 0.10–0.18, increasing toward the front.

- [ ] **Step 1: Write the failing test**

Append a testset to `examples/press/test/runtests.jl`:
```julia
    @testset "long-exposure thumbnail" begin
        prep = Press.build_prep()
        out = joinpath(@__DIR__, "out"); mkpath(out)
        png = joinpath(out, "thumbnail.png")
        # ghost frames = real intermediate frames fanning toward the pinch (frame 225).
        ghosts, solid = Press.render_thumbnail(prep, png)
        @test isfile(png)
        @test 3 <= length(ghosts) <= 4               # SPEC §6: 3–4 ghosts
        @test solid > 50                             # solid pinch frame packed a real block
    end
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `render_thumbnail` not defined.

- [ ] **Step 3: Add the thumbnail compositor**

Append inside the module (before `end # module`) in `examples/press/src/Press.jl`:
```julia
using CairoMakie: RGBAf

const PINCH_FRAME = 225                       # the most-compressed two-sided HOLD frame

"Helper: draw one packed frame's words into `ax` at `color`/`alpha` (no wall)."
function _draw_words!(ax, prep::Prepared, packed::PackedLayout, ridx::Set{Int};
                      color, brass, alpha::Float64)
    ink_pts = Point2f[]; ink_str = String[]; brs_pts = Point2f[]; brs_str = String[]
    for pl in packed.placements
        seg = prep.segments[pl.segment_index]
        seg.kind === :word || continue
        if pl.segment_index in ridx
            push!(brs_pts, _to_scene(pl)); push!(brs_str, seg.str)
        else
            push!(ink_pts, _to_scene(pl)); push!(ink_str, seg.str)
        end
    end
    isempty(ink_str) || text!(ax, ink_pts; text = ink_str, color = (color, alpha),
        font = FRAUNCES_BODY, fontsize = BODY_PT, align = (:left, :baseline), space = :pixel)
    isempty(brs_str) || text!(ax, brs_pts; text = brs_str, color = (brass, alpha),
        font = FRAUNCES_BODY, fontsize = BODY_PT, align = (:left, :baseline), space = :pixel)
    return
end

"""
    render_thumbnail(png; prep=build_prep()) -> (ghost_frames, n_solid_placements)

The gallery STILL (SPEC §6): the pinch frame (225) drawn SOLID in ink, with 3–4 earlier
press-states ghosted behind it (real `shape_pack`s at intermediate depths fanning toward
rest) in GRAY @ alpha 0.10–0.18 increasing toward the front. "rocking" appears twice —
ghosted near rest + solid in its squeezed band. Built from the same `shape_pack` calls as
the loop — the thumbnail IS the loop, sampled and stacked.
"""
function render_thumbnail(prep::Prepared, png::AbstractString)
    fig = Figure(size = (SCENE_W, SCENE_H), backgroundcolor = HS.PAPER)
    ax  = Axis(fig[1, 1]; backgroundcolor = HS.PAPER, limits = (0, SCENE_W, 0, SCENE_H))
    hidedecorations!(ax); hidespines!(ax)
    ridx = Set(brass_indices(prep))

    # 4 ghost frames stepping INTO the pinch (rising W depth), alpha rising toward front.
    ghost_frames = [180, 195, 210, 220]
    alphas       = [0.10, 0.13, 0.16, 0.18]
    for (gf, a) in zip(ghost_frames, alphas)
        s = schedule(gf)
        mask = s.north_depth > 0 ?
            pinch_mask(FIELD_H, FIELD_W; west_depth = s.depth, north_depth = s.north_depth) :
            press_mask(FIELD_H, FIELD_W; edge = s.edge, depth = s.depth)
        gpk = pack_at(prep, mask)
        _draw_words!(ax, prep, gpk, ridx; color = HS.GRAY, brass = HS.BRASS, alpha = a)
        _draw_wall!(ax, s.edge, s.depth; lw = WALL_INACTIVE_LW)   # faint brass ghost rule
    end

    # Solid pinch frame on top.
    s = schedule(PINCH_FRAME)
    mask = pinch_mask(FIELD_H, FIELD_W; west_depth = s.depth, north_depth = s.north_depth)
    solid = pack_at(prep, mask)
    _draw_words!(ax, prep, solid, ridx; color = HS.INK, brass = HS.BRASS, alpha = 1.0)
    _draw_wall!(ax, s.edge, s.depth; lw = WALL_ACTIVE_LW)
    s.north_depth > 0 && _draw_wall!(ax, :N, s.north_depth; lw = WALL_ACTIVE_LW)

    save(png, fig; px_per_unit = 1)
    return ghost_frames, length(solid.placements)
end
```

- [ ] **Step 4: Run the test + OPEN the thumbnail**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: PASS — `thumbnail.png` written, 4 ghosts, solid packed.

OPEN `examples/press/test/out/thumbnail.png`: confirm the solid ink pinch frame reads on top, ghosts fan behind it toward rest, the brass "rocking" reads as a migration path (ghost near rest → solid in its squeezed band), and the press direction is legible from the still.

- [ ] **Step 5: Commit**

```bash
git add examples/press
git commit -m "feat(press): long-exposure ghosted thumbnail still (pinch solid + 4 ghosts)"
```

---

### Task 9: The golden — `digest_rows` over 5 sampled frames + non-vacuous asserts

**Files:**
- Create: `examples/press/test/golden/frames.sha256`
- Modify: `examples/press/test/runtests.jl`

SPEC §11: golden = `digest_rows` of the rounded `(segment_index, x, y)` placement table at 5 structurally distinct frames — `t=0` (rest), N/8, 3N/8 (the **vertical** S/N risky cases), 5N/8, 7N/8 — sha256 via `HouseStyle.digest_rows`. Plus non-vacuous asserts: placement count > threshold at rest, ≥ 1 brass index present, and — **conditionally** — `!isempty(overflowed)` at peak compression. The overflow assert is gated by a pre-check: at `floor_w = 32 ch` Whitman may have NO over-wide word, in which case the assert would fail by correct design (SPEC §11). Pre-check `layout` (or a floor-width pack) and only assert if it genuinely overflows.

- [ ] **Step 1: Add the row-formatter + golden test (write-then-read pattern, like asteroid)**

Append a testset to `examples/press/test/runtests.jl`:
```julia
    @testset "golden: placement table at 5 sampled frames" begin
        prep = Press.build_prep()
        ridx = Set(Press.brass_indices(prep))

        # Format one frame's placement table as canonical rows (rounded to 0.01 px).
        function frame_rows(f)
            s = Press.schedule(f)
            mask = s.north_depth > 0 ?
                Press.pinch_mask(Press.FIELD_H, Press.FIELD_W;
                    west_depth = s.depth, north_depth = s.north_depth) :
                Press.press_mask(Press.FIELD_H, Press.FIELD_W; edge = s.edge, depth = s.depth)
            pk = Press.pack_at(prep, mask)
            return [string(pl.segment_index, "|",
                           round(pl.x; digits = 2), "|",
                           round(pl.y; digits = 2)) for pl in pk.placements], pk
        end

        N = Press.NFRAMES
        sample = (0, N ÷ 8, 3N ÷ 8, 5N ÷ 8, 7N ÷ 8)   # rest + the two vertical peaks + two more
        digests = String[]
        for f in sample
            rows, _ = frame_rows(f)
            push!(digests, HouseStyle.digest_rows(rows))
        end

        # --- non-vacuous scene asserts (SPEC §11) ---
        rest_rows, rest_pk = frame_rows(0)
        @test length(rest_pk.placements) > 50                     # rest packs the full block
        @test any(pl -> pl.segment_index in ridx, rest_pk.placements)  # ≥1 brass placement
        @test length(brass_indices_present(rest_pk, ridx)) >= 1

        # CONDITIONAL overflow assert (SPEC §11): pre-check whether ANY word overflows at
        # the tightest floor_w. Whitman is monster-word-free, so this may legitimately be
        # empty — only assert when the path is genuinely exercised.
        floor_layout = TextMeasure.layout(prep; max_width = Press.floor_w(prep))
        peak_overflows = let
            f = 3N ÷ 8                                            # a vertical peak (risky case)
            _, pk = frame_rows(f)
            pk.overflowed
        end
        longest_word_w = maximum(seg.width for seg in prep.segments if seg.kind === :word)
        if longest_word_w > Press.floor_w(prep)
            @test !isempty(peak_overflows)                       # overflow path genuinely hit
        else
            @info "press golden: no word exceeds floor_w; skipping !isempty(overflowed) assert (correct by design)" longest_word_w floor_w=Press.floor_w(prep)
        end

        # --- regression anchor: digest the 5 frames ---
        golden = joinpath(@__DIR__, "golden", "frames.sha256")
        payload = join(digests, "\n")
        if get(ENV, "UPDATE_GOLDEN", "") == "1"
            mkpath(dirname(golden)); write(golden, payload)
        end
        @test isfile(golden)
        @test payload == strip(read(golden, String))             # 5-frame regression anchor
    end
```
Add the tiny helper (top of `runtests.jl`, after imports):
```julia
brass_indices_present(pk, ridx) = [pl.segment_index for pl in pk.placements if pl.segment_index in ridx]
```

- [ ] **Step 2: Run WITHOUT the golden file to verify the test fails on the missing anchor**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `isfile(golden)` is false (file not yet generated). All other asserts in the testset should already pass.

- [ ] **Step 3: Generate the golden, then re-run to verify it passes**

Run:
```bash
UPDATE_GOLDEN=1 julia --project=examples/press -e 'using Pkg; Pkg.test()'
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: first run writes `examples/press/test/golden/frames.sha256` (5 sha256 lines); second run PASSES the regression anchor (`payload == strip(...)`). Note in the log whether the overflow assert ran or was skipped (the `@info` line tells you which branch fired).

- [ ] **Step 4: Commit (golden file + test)**

```bash
git add examples/press/test/golden/frames.sha256 examples/press/test/runtests.jl
git commit -m "test(press): golden digest at 5 sampled frames + non-vacuous asserts"
```

---

### Task 10: Caption + credit line, and wire the example into the suite

**Files:**
- Modify: `examples/press/src/Press.jl`
- Modify: `examples/press/test/runtests.jl`
- Create: `examples/press/README.md`

SPEC §5: caption (Plex Mono 9 pt, GRAY text, BRASS middot) stating the claim — `prepare ×1 · shape_pack ×360 / loop` — baseline-pinned bottom-left, plus the credit `Walt Whitman · Out of the Cradle Endlessly Rocking · 1859`. Drawn into the loop + thumbnail + frame renderers. No masthead (SPEC §5 restraint).

- [ ] **Step 1: Write the failing test**

Append a testset to `examples/press/test/runtests.jl`:
```julia
    @testset "caption + credit" begin
        @test occursin("prepare", Press.CAPTION)
        @test occursin("shape_pack", Press.CAPTION)
        @test occursin("×360", Press.CAPTION) || occursin("360", Press.CAPTION)
        @test occursin("Whitman", Press.CREDIT)
        @test occursin("Out of the Cradle", Press.CREDIT)
        @test occursin("1859", Press.CREDIT)
    end
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
```
Expected: FAIL — `CAPTION` / `CREDIT` not defined.

- [ ] **Step 3: Add the caption constants + a `_draw_caption!` and call it in the renderers**

Append inside the module (before `end # module`) in `examples/press/src/Press.jl`:
```julia
const PLEX_MONO = HS.plexmono("Regular")
const CAPTION_PT = HS.RAMP.caption                                  # 9
const CAPTION = "prepare ×1 · shape_pack ×360 / loop"               # SPEC §5 — states the claim
const CREDIT  = "Walt Whitman · Out of the Cradle Endlessly Rocking · 1859"  # PD credit

"Draw the two-line mono caption baseline-pinned bottom-left (SPEC §5). GRAY text."
function _draw_caption!(ax)
    x  = FIELD_X0
    y1 = MARGIN + CAPTION_PT + 4          # credit line (lower)
    y2 = y1 + CAPTION_PT + 4              # claim line (above it)
    text!(ax, [Point2f(x, y2)]; text = [CAPTION], color = HS.GRAY,
        font = PLEX_MONO, fontsize = CAPTION_PT, align = (:left, :baseline), space = :pixel)
    text!(ax, [Point2f(x, y1)]; text = [CREDIT], color = HS.GRAY,
        font = PLEX_MONO, fontsize = CAPTION_PT, align = (:left, :baseline), space = :pixel)
    return
end
```

Add `_draw_caption!(ax)` immediately before the `save(...)` / end-of-`record`-callback in each of `render_frame`, `render_loop`, and `render_thumbnail`. In `render_frame`, insert it just before `save_png && save(...)`. In `render_loop`, insert it as the last statement inside the `record` `do f … end` block. In `render_thumbnail`, insert it just before `save(png, fig; px_per_unit = 1)`.

- [ ] **Step 4: Run the test + re-render the thumbnail to confirm the caption draws**

Run:
```bash
julia --project=examples/press -e 'using Pkg; Pkg.test()'
julia --project=examples/press -e 'using Press; prep = Press.build_prep(); Press.render_thumbnail(prep, "examples/press/test/out/thumbnail.png")'
```
Expected: PASS; OPEN `thumbnail.png` and confirm the mono caption + credit sit baseline-pinned bottom-left in GRAY, inside the margin, not overlapping the block.

- [ ] **Step 5: Write the README**

Create `examples/press/README.md`:
```markdown
# #L · THE PRESS

A block of Whitman (*Out of the Cradle Endlessly Rocking*, 1859, PD) that re-packs every
frame as a brass wall presses inward from rotating axes (E→S→W→N + one two-sided pinch).
One `prepare()`; 360 `shape_pack()` calls a loop. The word "rocking" is lit in brass,
riding the press like a needle. Depends on the shared `HouseStyle` spine.

    julia --project=examples/press -e 'using Pkg; Pkg.instantiate()'
    # render the 12 s / 360-frame loop:
    julia --project=examples/press -e 'using Press; Press.render_loop("press_loop.mp4")'
    # render the long-exposure thumbnail still:
    julia --project=examples/press -e 'using Press; p = Press.build_prep(); Press.render_thumbnail(p, "thumbnail.png")'
    # run tests (golden = digest_rows over 5 sampled frames):
    julia --project=examples/press -e 'using Pkg; Pkg.test()'

Engine surface used: `prepare` (once) + `shape_pack(prep, raster_chord_fn(mask, 1.0);
line_advance, min_chord_width = floor_w, overflow_strategy = :widest_row, fill = :widest)`.
No new library surface — region-mask construction, the press schedule, brass tracking, and
ghost compositing are all demo-side orchestration over the engine (SPEC §8).
```

- [ ] **Step 6: Commit**

```bash
git add examples/press
git commit -m "feat(press): mono caption + credit, README; piece complete"
```

---

## Self-review notes

**Spec coverage (every SPEC § mapped to a task):**
- §1 medium = looping MP4 + honesty claim (N packs, 1 prepare) → Task 7 (+ honesty testset).
- §2 choreography (12 s/360 frames, E→S→W→N, smoothstep, HOLD, single pinch, loop closure) → Task 5.
- §3 readability floors (`floor_w` = 32 ch, ≥ 6 baselines, fixed `line_advance`, `min_chord_width = floor_w`, `:widest_row` overflow) → Tasks 2, 4 (`pack_at`), 5 (`dmax_for`).
- §4 brass "rocking" via stable `segment_index`, most visible at the HOLD, pushed to its own band on the W pinch → Tasks 2, 4, 7.
- §5 field (PAPER, 48 px margin), REQUIRED brass tide-rule (active heavier than 0.5 px, surveyor's ticks, both edges on pinch), body Fraunces 11 pt INK, brass lit word, mono caption + credit, no masthead → Tasks 4, 6, 10.
- §6 long-exposure thumbnail (pinch solid + 3–4 ghosts, GRAY α 0.10–0.18, brass twice) → Task 8.
- §8 engine mechanics (one `prepare`, per-frame mask → `shape_pack`, exact kwargs) → Tasks 2, 4, 7.
- §9 verbatim PD source text with `\n` verse-breaks → Task 1.
- §11 build notes: NO `Silhouettes` (Task 1 deps + Task 3 hand-built mask), `fill=:widest` correct because flush walls (Task 3 test asserts ≤ 1 interval/band incl. pinch), stable brass tracking (Task 2), reuse `raster_chord_fn`/`shape_pack` verbatim (Task 4 `pack_at`), golden = layout-table hashes at 5 frames (Task 9), CONDITIONAL `!isempty(overflowed)` gated by a floor-width pre-check (Task 9), alignment eyeballed not just green-tested (Task 4 Step 5, Task 6 Step 4).

**Placeholder scan:** no "similar to Task N", no `...`, no TODO stubs. Every code block is complete and runnable; each command states its expected output. The Whitman `TEXT`, the `[sources]` deps, the `MakieBackend(font=…, fontsize=11, px_per_unit=1)` call, the `shape_pack(…; line_advance, min_chord_width, overflow_strategy=:widest_row, fill=:widest)` signature, the `Placement` fields (`segment_index`, `x`, `y`), and `HouseStyle.digest_rows` are all the REAL signatures verified against `src/`, `examples/layouts/src/shape_pack.jl`, `ext/TextMeasureMakieExt.jl`, and the Foundation plan.

**Type consistency:** `Prepared`/`Segment`/`FontMetrics` from `TextMeasure`; `Placement`/`PackedLayout`/`RasterChordFn`/`raster_chord_fn`/`shape_pack` from `TextMeasureLayouts`; `BitMatrix` masks consumed by `raster_chord_fn(mask, 1.0)`; `Placement.x`/`.y :: Float64` in the y-down block-top frame, flipped to y-up scene px in `_to_scene` (the load-bearing reasoning, Task 4). `HouseStyle.RAMP.body == 11`, `.caption == 9`; colours `HS.PAPER/INK/BRASS/GRAY`; `HS.fraunces("9pt-Regular")`/`HS.plexmono("Regular")`/`HS.digest_rows`. `schedule(f) → (; edge::Symbol, depth::Float64, north_depth::Float64)`. The `MakieBackend` keyword constructor (`font`/`fontsize`/`px_per_unit`) matches `ext/TextMeasureMakieExt.jl` exactly.

**Two flagged risks carried from the spec:** (1) `floor_w` approximates the 32-char width as `32 × 0.5 × fontsize` because re-measuring a "0" post-`prepare` would touch the font engine a second time — the `0.5` is the one tunable, validated at the Task 4 visual gate. (2) The `!isempty(overflowed)` assert is CONDITIONAL on a floor-width pre-check (`longest_word_w > floor_w`); Whitman is monster-word-free, so the assert legitimately skips with an `@info` rather than failing by correct design (SPEC §11).
