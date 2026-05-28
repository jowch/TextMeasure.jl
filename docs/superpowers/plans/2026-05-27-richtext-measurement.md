# RichText Bounding-Box Measurement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `measure_bounds(::MakieBackend, ::RichText) -> TextBounds` that reproduces, without a render pass, the pixel bounding box Makie will draw for a `RichText`, plus the backend-agnostic core seam it builds on.

**Architecture:** A pure core seam (`StyledRun`, `TextBounds`, `bounds`) in `src/bounds.jl` that unions already-measured, already-positioned runs. A Makie extension method walks the `RichText` tree mirroring Makie's `process_rt_node!`/`new_glyphstate` (per-span font/size/offset inheritance; `0.66` scale; `+0.40`/`−0.25·parent_size` sub/sup shifts; `subsup`/`leftsubsup`; `\n` at Makie's `20`px stub), emits `StyledRun`s, and delegates to `bounds`. The plain-string `Segment`/`Prepared`/`layout` path is untouched. Correctness is pinned by a golden test comparing against live Makie's `boundingbox(plot, :pixel)`.

**Tech Stack:** Julia 1.11+, package extensions, FreeTypeAbstraction (via `Makie.FreeTypeAbstraction`), Makie 0.24 (test + golden oracle), Test.

**Spec:** `docs/superpowers/specs/2026-05-27-richtext-measurement-design.md`. **Prerequisite:** the CI plan (`2026-05-27-ci-prerequisite.md`) should land first so the golden test is guarded.

**Conventions (from CLAUDE.md):** measurement matches Makie by summing glyph advances with **no kerning**; `MakieBackend` is used with `px_per_unit = 1`. Coordinate note: `StyledRun` uses Makie's **+y-up** convention (root baseline = 0), the *opposite* of `Layout`'s y-down — the two paths never share coordinates.

---

## File Structure

- `src/bounds.jl` *(new)* — `StyledRun`, `TextBounds`, `bounds`. Pure, no font engine. One responsibility: union measured runs into a box.
- `src/backend.jl` *(modify)* — add the bare `function measure_bounds end` stub so the extension can add a method.
- `src/TextMeasure.jl` *(modify)* — `include("bounds.jl")`; export `measure_bounds`, `TextBounds`.
- `ext/TextMeasureMakieExt.jl` *(modify)* — the `RichText` walk + `measure_bounds(::MakieBackend, ::RichText)`.
- `test/test_bounds.jl` *(new)* — pure unit tests for `bounds` (no Makie).
- `test/test_richtext.jl` *(new)* — golden test vs live Makie.
- `test/runtests.jl` *(modify)* — register the two new test files.
- `CHANGELOG.md` *(modify)* — note the capability.

---

### Task 1: Core seam — `StyledRun`, `TextBounds`, `bounds` (pure, no Makie)

**Files:**
- Create: `src/bounds.jl`
- Modify: `src/backend.jl` (add stub)
- Modify: `src/TextMeasure.jl` (include + export)
- Test: `test/test_bounds.jl`
- Modify: `test/runtests.jl`

- [ ] **Step 1: Write the failing test**

Create `test/test_bounds.jl`:

```julia
using Test, TextMeasure
using TextMeasure: StyledRun, bounds   # internal seam — not exported

@testset "bounds (pure union)" begin
    # empty → zero box
    @test bounds(StyledRun[]) == TextBounds((0.0, 0.0), (0.0, 0.0))

    # single run: box x∈[0,10], y∈[-2,8] (baseline 0, ascent 8, descent 2)
    r = StyledRun(0.0, 0.0, 10.0, 8.0, 2.0)
    b = bounds([r])
    @test b.size   == (10.0, 10.0)
    @test b.origin == (0.0, -2.0)

    # two runs, same baseline, second narrower/taller and offset in x
    r1 = StyledRun(0.0,  0.0, 10.0,  8.0, 2.0)
    r2 = StyledRun(10.0, 0.0,  6.0, 12.0, 3.0)
    b2 = bounds([r1, r2])
    @test b2.size   == (16.0, 15.0)   # x 0..16, y -3..12
    @test b2.origin == (0.0, -3.0)

    # multi-line: second line dropped (Makie +y up → more-negative baseline)
    l1 = StyledRun(0.0,   0.0, 10.0, 8.0, 2.0)
    l2 = StyledRun(0.0, -20.0, 14.0, 8.0, 2.0)
    b3 = bounds([l1, l2])
    @test b3.size   == (14.0, 30.0)   # x 0..14, y -22..8
    @test b3.origin == (0.0, -22.0)
end
```

- [ ] **Step 2: Register the test and run it to verify it fails**

Add to `test/runtests.jl` inside the `@testset`, after `include("test_layout.jl")`:

```julia
    include("test_bounds.jl")
```

Run: `julia --project=test -e 'using TextMeasure, Test; include("test/test_bounds.jl")'`
Expected: FAIL — `UndefVarError: StyledRun` (or `bounds`/`TextBounds` not defined).

- [ ] **Step 3: Write the core implementation**

Create `src/bounds.jl`:

```julia
"""
    StyledRun

One measured, already-positioned run of text. Internal seam between font-touching
measurement (e.g. the Makie `RichText` walk) and the pure [`bounds`](@ref) union.
Not exported in v1.

Coordinate convention: Makie's — **+y is up**, root baseline `= 0`. This is the
*opposite* of [`Layout`](@ref)/[`Line`](@ref), which use block-top `= 0` increasing
downward. The two paths never share coordinates. `ascent`/`descent` are both ≥ 0
(like [`FontMetrics`](@ref), where `descent` is positive-below-baseline).
"""
struct StyledRun
    x        :: Float64   # left edge (advance origin) on the line, px
    baseline :: Float64   # baseline y; +y up, root baseline = 0
    width    :: Float64   # advance width (sum of glyph advances, no kerning), px
    ascent   :: Float64   # ascent above baseline at this run's resolved size, px (≥ 0)
    descent  :: Float64   # descent below baseline at this run's resolved size, px (≥ 0)
end

"""
    TextBounds

Axis-aligned bounding box of laid-out text. `size = (width, height)` in px is the
field consumers read; `origin = (xmin, ymin)` in the measuring walk's coordinate
space is informational (not position-invariant). Treat as read-only.
"""
struct TextBounds
    origin :: NTuple{2,Float64}
    size   :: NTuple{2,Float64}
end

"""
    bounds(runs) -> TextBounds

Pure union of each run's box `[x, x+width] × [baseline-descent, baseline+ascent]`.
Does no measuring — `runs` are already measured. Empty input → zero box. The union
takes only differences of extents, so it is correct regardless of the y sign.
"""
function bounds(runs::AbstractVector{StyledRun})
    isempty(runs) && return TextBounds((0.0, 0.0), (0.0, 0.0))
    xmin =  Inf; xmax = -Inf; ymin =  Inf; ymax = -Inf
    for r in runs
        xmin = min(xmin, r.x)
        xmax = max(xmax, r.x + r.width)
        ymin = min(ymin, r.baseline - r.descent)
        ymax = max(ymax, r.baseline + r.ascent)
    end
    return TextBounds((xmin, ymin), (xmax - xmin, ymax - ymin))
end
```

Add the stub to `src/backend.jl`, immediately after `function font_metrics end` (line 17):

```julia
# 2D analog of `measure`, implemented by extensions for styled inputs (e.g. RichText).
# Public/exported verb; a method is added by each extension that supports a styled type.
function measure_bounds end
```

Edit `src/TextMeasure.jl` — add the include after `include("backend.jl")` (so the stub is visible) and extend the exports:

```julia
export prepare, layout, line_top, measure_bounds
export Prepared, Layout, Line, FontMetrics, TextBounds
export AbstractMeasurementBackend, MonospaceBackend, FreeTypeBackend, MakieBackend
```

```julia
include("types.jl")
include("backend.jl")
include("bounds.jl")
include("monospace.jl")
include("backend_containers.jl")
include("prepare.jl")
include("layout.jl")
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `julia --project=test -e 'using TextMeasure, Test; include("test/test_bounds.jl")'`
Expected: PASS (all assertions in the `bounds (pure union)` testset).

- [ ] **Step 5: Commit**

```bash
git add src/bounds.jl src/backend.jl src/TextMeasure.jl test/test_bounds.jl test/runtests.jl
git commit -m "feat: add StyledRun/TextBounds/bounds core seam + measure_bounds stub"
```

---

### Task 2: Makie extension — plain & mixed-font/size single-line walk + golden harness

**Files:**
- Modify: `ext/TextMeasureMakieExt.jl`
- Test: `test/test_richtext.jl`
- Modify: `test/runtests.jl`

- [ ] **Step 0: Spike — confirm how to get Makie's pixel bbox headlessly**

Run in a REPL (`julia --project=test`):

```julia
using Makie
sc = Scene(; size = (1000, 1000))
p  = text!(sc, Point2f(0, 0); text = Makie.rich("Hello"),
           font = "TeX Gyre Heros Makie", fontsize = 24.0)
bb = Makie.boundingbox(p, :pixel)
@show Makie.widths(bb)
```

Expected: prints a finite 3-element width vector (e.g. `Float32[~70, ~17, 0]`); no display/backend error.
If it errors with a "no backend"/display error: add `CairoMakie` to `test/Project.toml` `[deps]` and call `CairoMakie.activate!()` at the top of the test, then re-run. Record which path worked — it determines the test harness below. (The existing `test_makie.jl` runs headless via `text_bb`, so the bare-`Scene` path is expected to work.)

- [ ] **Step 1: Write the failing golden test (plain + mixed font/size, single line)**

Create `test/test_richtext.jl`:

```julia
using Test, TextMeasure, Makie

# Validated against Makie 0.24.10. The mirrored constants (0.66, +0.40, −0.25, 20px
# line spacing) live in ext/TextMeasureMakieExt.jl; this test is their guard.
const RT_FONT = "TeX Gyre Heros Makie"
const RT_SIZE = 24.0

# Makie's own pixel bbox (width, height) for a RichText — the correctness oracle.
function makie_wh(rt)
    sc = Scene(; size = (1000, 1000))
    p  = text!(sc, Point2f(0, 0); text = rt, font = RT_FONT, fontsize = RT_SIZE)
    w  = Makie.widths(Makie.boundingbox(p, :pixel))
    return (Float64(w[1]), Float64(w[2]))
end

ours_wh(rt) =
    measure_bounds(MakieBackend(; font = RT_FONT, fontsize = RT_SIZE, px_per_unit = 1.0), rt).size

# assert our (w,h) matches Makie's within tolerance, and is finite
function check(rt)
    o = ours_wh(rt); m = makie_wh(rt)
    @test all(isfinite, o)
    @test o[1] ≈ m[1] rtol = 2e-3 atol = 0.5
    @test o[2] ≈ m[2] rtol = 2e-3 atol = 0.5
end

@testset "RichText measure_bounds vs Makie" begin
    @testset "plain & mixed font/size" begin
        check(Makie.rich("Hello"))
        check(Makie.rich("Hello, world"))
        check(Makie.rich("big ", Makie.rich("small"; fontsize = 12.0)))
        check(Makie.rich("plain ", Makie.rich("other"; font = "TeX Gyre Heros Makie Bold")))
    end
end
```

> If the spike found `"TeX Gyre Heros Makie Bold"` is not an installed font name, substitute any
> second installed font name the spike confirms (the test only needs *a different font* in a span;
> the oracle compares against Makie using the same name).

- [ ] **Step 2: Register the test and run it to verify it fails**

Add to `test/runtests.jl` after `include("test_makie.jl")`:

```julia
    include("test_richtext.jl")
```

Run: `julia --project=test -e 'using TextMeasure, Test, Makie; include("test/test_richtext.jl")'`
Expected: FAIL — `MethodError: no method matching measure_bounds(::MakieBackend, ::RichText)`.

- [ ] **Step 3: Implement the walk skeleton (span + string) + `measure_bounds`**

Add to `ext/TextMeasureMakieExt.jl`, before the final `end # module`:

```julia
# ---- RichText bounding box -------------------------------------------------
# Mirrors Makie's process_rt_node!/new_glyphstate (src/basic_recipes/text.jl) so the
# box equals what text! will render. Glyph state uses Makie's +y-up convention; the
# constants (0.66, +0.40, −0.25, 20px) are pinned to Makie 0.24.x and guarded by
# test/test_richtext.jl. measure_bounds is called with px_per_unit = 1 (CLAUDE.md).

# Per-span state during the walk. `size` is the resolved fontsize in px.
struct _RTState
    x        :: Float64
    baseline :: Float64
    size     :: Float64
    font                  # FTFont
end

# Child state for a :span node (font/size/offset inheritance; offset is a fraction
# of the span's own fontsize, applied to both x and baseline — matches Makie).
function _rt_child(gs::_RTState, rt::Makie.RichText)
    att = rt.attributes
    rt.type === :span ||
        throw(ArgumentError("unsupported RichText span type: $(rt.type)"))
    size = Float64(get(att, :fontsize, gs.size))
    off  = get(att, :offset, (0.0, 0.0))
    font = haskey(att, :font) ? Makie.to_font(att[:font]) : gs.font
    return _RTState(gs.x + off[1] * size, gs.baseline + off[2] * size, size, font)
end

# Emit StyledRuns for a string leaf; return the advanced state.
function _rt_string!(runs::Vector{TextMeasure.StyledRun}, gs::_RTState, s::AbstractString)
    asc  =  FTA.ascender(gs.font)  * gs.size
    desc = -FTA.descender(gs.font) * gs.size
    x = gs.x; seg_start = gs.x; seg_w = 0.0; nonempty = false
    for ch in s
        bestfont = Makie.find_font_for_char(ch, gs.font)
        adv = FTA.hadvance(FTA.get_extent(bestfont, ch)) * gs.size
        seg_w += adv; x += adv; nonempty = true
    end
    if nonempty
        push!(runs, TextMeasure.StyledRun(seg_start, gs.baseline, seg_w, asc, desc))
    end
    return _RTState(x, gs.baseline, gs.size, gs.font)
end

# Walk a node (String or RichText), pushing StyledRuns; return the advanced state.
function _rt_walk!(runs::Vector{TextMeasure.StyledRun}, gs::_RTState, node)
    node isa AbstractString && return _rt_string!(runs, gs, node)
    rt = node::Makie.RichText
    cur = _rt_child(gs, rt)
    for child in rt.children
        cur = _rt_walk!(runs, cur, child)
    end
    # advance x; restore baseline/size/font to the parent
    return _RTState(cur.x, gs.baseline, gs.size, gs.font)
end

function TextMeasure.measure_bounds(b::TextMeasure.MakieBackend, rt::Makie.RichText)
    runs = TextMeasure.StyledRun[]
    gs0  = _RTState(0.0, 0.0, _pixel_size(b), b.face)
    _rt_walk!(runs, gs0, rt)
    return TextMeasure.bounds(runs)
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `julia --project=test -e 'using TextMeasure, Test, Makie; include("test/test_richtext.jl")'`
Expected: PASS for the `plain & mixed font/size` testset (all `check(...)` within tolerance).

> If width matches but height is off by a constant factor, recheck `_pixel_size`/`size` scaling
> against `measure`/`font_metrics` in this same file (lines 12–31). If a mixed-font case fails,
> re-run the spike with that span's font name to confirm `Makie.to_font(name)` agrees with what
> `text!` resolves.

- [ ] **Step 5: Commit**

```bash
git add ext/TextMeasureMakieExt.jl test/test_richtext.jl test/runtests.jl
# If Step 0's spike forced the CairoMakie fallback, also stage the test deps change:
#   git add test/Project.toml
git commit -m "feat: measure_bounds for plain/mixed-font RichText (single line)"
```

---

### Task 3: Subscript & superscript

**Files:**
- Modify: `ext/TextMeasureMakieExt.jl` (extend `_rt_child`)
- Modify: `test/test_richtext.jl` (add golden cases)

- [ ] **Step 1: Write the failing test**

Add inside the outer `@testset` in `test/test_richtext.jl`, after the `plain & mixed font/size` block:

```julia
    @testset "sub/superscript" begin
        check(Makie.rich("x", Makie.superscript("2")))
        check(Makie.rich("H", Makie.subscript("2"), "O"))
        check(Makie.rich("e", Makie.superscript("iπ"), " + 1"))
    end
```

Run: `julia --project=test -e 'using TextMeasure, Test, Makie; include("test/test_richtext.jl")'`
Expected: FAIL — `ArgumentError: unsupported RichText span type: sup` (from `_rt_child`).

- [ ] **Step 2: Extend `_rt_child` to handle `:sup` and `:sub`**

Replace the `_rt_child` function in `ext/TextMeasureMakieExt.jl` with:

```julia
# Child state for :span/:sup/:sub. For :sup/:sub the default size is 0.66·parent and
# the baseline shifts by +0.40·parent (sup) / −0.25·parent (sub); the span `offset`
# (a fraction of the child's fontsize) applies on top, to both x and baseline.
function _rt_child(gs::_RTState, rt::Makie.RichText)
    att = rt.attributes
    t   = rt.type
    off = get(att, :offset, (0.0, 0.0))
    if t === :span
        size = Float64(get(att, :fontsize, gs.size))
        font = haskey(att, :font) ? Makie.to_font(att[:font]) : gs.font
        return _RTState(gs.x + off[1] * size, gs.baseline + off[2] * size, size, font)
    elseif t === :sup
        size = Float64(get(att, :fontsize, 0.66 * gs.size))
        font = haskey(att, :font) ? Makie.to_font(att[:font]) : gs.font
        return _RTState(gs.x + off[1] * size,
                        gs.baseline + 0.40 * gs.size + off[2] * size, size, font)
    elseif t === :sub
        size = Float64(get(att, :fontsize, 0.66 * gs.size))
        font = haskey(att, :font) ? Makie.to_font(att[:font]) : gs.font
        return _RTState(gs.x + off[1] * size,
                        gs.baseline - 0.25 * gs.size + off[2] * size, size, font)
    else
        throw(ArgumentError("unsupported RichText span type: $t"))
    end
end
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `julia --project=test -e 'using TextMeasure, Test, Makie; include("test/test_richtext.jl")'`
Expected: PASS for both `plain & mixed font/size` and `sub/superscript`.

- [ ] **Step 4: Commit**

```bash
git add ext/TextMeasureMakieExt.jl test/test_richtext.jl
git commit -m "feat: RichText sub/superscript measurement (0.66 scale, ±baseline shift)"
```

---

### Task 4: `subsup` / `leftsubsup` (stacked sub+super)

**Files:**
- Modify: `ext/TextMeasureMakieExt.jl` (add subsup branch to `_rt_walk!`, add `_rt_subsup`)
- Modify: `test/test_richtext.jl` (add golden cases)

**Note:** For the AABB, `:subsup` and `:leftsubsup` are expected to be equivalent — both children
occupy the same x-extent of width `max(sub_width, sup_width)`, so left-vs-right alignment shifts
the smaller child *within* that width without changing the union box. The spec, however, records
that `:leftsubsup` aligns by the **ink** right edge (not advance), which could perturb the box by a
side-bearing. Step 0 pre-verifies the equivalence bet before we rely on it.

- [ ] **Step 0: Spike — pre-verify the leftsubsup AABB-invariance bet**

After Task 3 is in place (so `_rt_child` handles sub/sup), but before implementing the subsup
branch, run in a REPL (`julia --project=test`) using the helpers from `test/test_richtext.jl`:

```julia
using Test, TextMeasure, Makie
include("test/test_richtext.jl")   # brings in makie_wh / ours_wh / RT_FONT / RT_SIZE
# subsup currently throws, so check Makie's own numbers for the two variants:
@show makie_wh(Makie.rich("M", Makie.subsup("a", "b"), "z"))
@show makie_wh(Makie.rich("M", Makie.left_subsup("a", "b"), "z"))
```

Expected: the two widths are equal (or differ only by a sub-pixel side-bearing < the test's
`atol = 0.5`). **If they differ by more than the tolerance**, the ink-alignment matters: implement
it in Step 2's `_rt_walk!` leftsubsup branch — measure both children's runs, find the right
child's ink right edge via `FTA.get_extent(font, lastchar).ink_bounding_box`, and shift the
narrower child so their ink right edges coincide — instead of the simple `max(...)` advance. Record
the spike's outcome in the commit message.

- [ ] **Step 1: Write the failing test**

Add inside the outer `@testset` in `test/test_richtext.jl`:

```julia
    @testset "subsup / leftsubsup" begin
        check(Makie.rich("x", Makie.subsup("i", "2")))           # sub="i", super="2"
        check(Makie.rich("M", Makie.left_subsup("a", "b"), "z"))
        # node-level :fontsize / :font on the subsup node itself (must be read from rt.attributes)
        check(Makie.rich("x", Makie.subsup("i", "2"; fontsize = 30.0)))
        check(Makie.rich("x", Makie.subsup("i", "2"; font = "TeX Gyre Heros Makie Bold")))
    end
```

Run: `julia --project=test -e 'using TextMeasure, Test, Makie; include("test/test_richtext.jl")'`
Expected: FAIL — `ArgumentError: unsupported RichText span type: subsup`.

- [ ] **Step 2: Add `_rt_subsup` and a subsup branch in `_rt_walk!`**

Add this helper next to `_rt_child` in `ext/TextMeasureMakieExt.jl`:

```julia
# sub/sup child state for subsup children. Reads :fontsize/:font from the SUBSUP NODE's
# own attributes (default 0.66·parent / parent font), matching Makie's new_glyphstate for
# :subsup_sub/:subsup_sup. NOTE: Makie does NOT apply the span `offset` to subsup children
# (unlike :sub/:sup), so none is added here. The baseline shift constants stay parent-based.
function _rt_subsup(gs::_RTState, rt::Makie.RichText, ::Val{:sup})
    att  = rt.attributes
    size = Float64(get(att, :fontsize, 0.66 * gs.size))
    font = haskey(att, :font) ? Makie.to_font(att[:font]) : gs.font
    return _RTState(gs.x, gs.baseline + 0.40 * gs.size, size, font)
end
function _rt_subsup(gs::_RTState, rt::Makie.RichText, ::Val{:sub})
    att  = rt.attributes
    size = Float64(get(att, :fontsize, 0.66 * gs.size))
    font = haskey(att, :font) ? Makie.to_font(att[:font]) : gs.font
    return _RTState(gs.x, gs.baseline - 0.25 * gs.size, size, font)
end
```

Replace `_rt_walk!` with the version that special-cases the stacked types (passing the
subsup node `rt` into `_rt_subsup` so its `:fontsize`/`:font` attributes flow through):

```julia
function _rt_walk!(runs::Vector{TextMeasure.StyledRun}, gs::_RTState, node)
    node isa AbstractString && return _rt_string!(runs, gs, node)
    rt = node::Makie.RichText
    t  = rt.type
    if t === :subsup || t === :leftsubsup
        length(rt.children) == 2 ||
            throw(ArgumentError("$t requires exactly 2 children (sub, super)"))
        # children laid out from the SAME parent x and baseline (child 1 = sub, 2 = super);
        # subsup node's :fontsize/:font flow to both children via `rt` → _rt_subsup
        e_sub = _rt_walk!(runs, _rt_subsup(gs, rt, Val(:sub)), rt.children[1])
        e_sup = _rt_walk!(runs, _rt_subsup(gs, rt, Val(:sup)), rt.children[2])
        # AABB advances by the wider child; alignment doesn't change the union box
        return _RTState(max(e_sub.x, e_sup.x), gs.baseline, gs.size, gs.font)
    else
        cur = _rt_child(gs, rt)
        for child in rt.children
            cur = _rt_walk!(runs, cur, child)
        end
        # Advance x; restore sub/sup baseline shift + size/font to the parent.
        # (No `\n` handling at this task; Task 5 will introduce a `drop::Ref{Float64}`
        # so that newlines nested in a child persist across this return.)
        return _RTState(cur.x, gs.baseline, gs.size, gs.font)
    end
end
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `julia --project=test -e 'using TextMeasure, Test, Makie; include("test/test_richtext.jl")'`
Expected: PASS for all testsets so far.

> If only `leftsubsup` fails (width slightly off) while `subsup` passes, that is Makie's ink-edge
> `right_align!`. Mirror it: compute each child's runs, find the right child's ink right edge via
> `FTA.get_extent(...).ink_bounding_box`, and shift the shorter child so their ink right edges
> align — but verify this is actually needed before adding the complexity.

- [ ] **Step 4: Commit**

```bash
git add ext/TextMeasureMakieExt.jl test/test_richtext.jl
git commit -m "feat: RichText subsup/leftsubsup measurement"
```

---

### Task 5: Multi-line (`\n`) — including newlines nested inside spans

**Files:**
- Modify: `ext/TextMeasureMakieExt.jl` (rework `_rt_string!`, `_rt_walk!`, `measure_bounds`
  to thread a global line-drop counter)
- Modify: `test/test_richtext.jl` (add golden cases including nested newlines)

**Design note — mirror Makie's two-stage layout.** Makie's `process_rt_node!` does not bake the
line drop into glyph baselines; instead it appends glyphs to a **global `lines` list** (a `\n`
pushes a new bucket), and a separate `apply_lineheight!` pass drops line *i* by `(i−1)·20`. We
mirror that: the per-node `gs.baseline` carries only the sub/sup shift (and is restored on node
return), while a shared `drop::Ref{Float64}` is the **global, monotonic** line-drop counter that
increments on every `\n` and is **never restored** across nested-span boundaries. Each emitted
`StyledRun` gets `baseline = gs.baseline − drop[]`. This makes
`rich(rich("x\n"), "y")` work correctly: the `\n`'s drop persists when the nested span returns,
so `"y"` lands on line 2, not back on line 1.

- [ ] **Step 1: Write the failing test (including nested-newline cases)**

Add inside the outer `@testset` in `test/test_richtext.jl`:

```julia
    @testset "multi-line" begin
        # top-level newlines
        check(Makie.rich("line one\nline two"))
        check(Makie.rich("a\nbb\nccc"))
        check(Makie.rich("top\n", Makie.superscript("x")))
        # newlines nested inside spans — the line drop must persist across the span boundary
        check(Makie.rich(Makie.rich("x\n"), "y"))
        check(Makie.rich(Makie.rich("a\nb"), "c"))
        check(Makie.rich("pre ", Makie.rich("inner\nnext", fontsize = 18.0), " post"))
    end
```

Run: `julia --project=test -e 'using TextMeasure, Test, Makie; include("test/test_richtext.jl")'`
Expected: FAIL — the current `_rt_string!` has no `\n` handling, so the top-level multi-line
cases give too-wide / too-short boxes, and the nested cases additionally collapse the line drop
when the inner span returns.

- [ ] **Step 2: Rework `_rt_string!`, `_rt_walk!`, and `measure_bounds` to thread a global line-drop Ref**

Add the constant and the three replacement functions in `ext/TextMeasureMakieExt.jl`.

```julia
const _RT_LINE_DROP = 20.0   # Makie 0.24.x apply_lineheight! stub: flat 20px/line (# TODO in Makie)

# Emit StyledRuns for a string leaf, splitting at '\n'. On '\n', x resets to 0 and the GLOBAL
# `drop[]` line counter increments — `gs.baseline` (sub/sup shift) is untouched. Each emitted
# run's baseline is `gs.baseline - drop[]`, mirroring Makie's two-stage (process_rt_node! +
# apply_lineheight!) layout.
function _rt_string!(runs::Vector{TextMeasure.StyledRun}, drop::Ref{Float64},
                     gs::_RTState, s::AbstractString)
    asc  =  FTA.ascender(gs.font)  * gs.size
    desc = -FTA.descender(gs.font) * gs.size
    x = gs.x; seg_start = gs.x; seg_w = 0.0; nonempty = false
    for ch in s
        if ch == '\n'
            if nonempty
                push!(runs, TextMeasure.StyledRun(seg_start, gs.baseline - drop[], seg_w, asc, desc))
            end
            drop[] += _RT_LINE_DROP        # global, monotonic — persists across node returns
            x = 0.0; seg_start = 0.0; seg_w = 0.0; nonempty = false
        else
            bestfont = Makie.find_font_for_char(ch, gs.font)
            adv = FTA.hadvance(FTA.get_extent(bestfont, ch)) * gs.size
            seg_w += adv; x += adv; nonempty = true
        end
    end
    if nonempty
        push!(runs, TextMeasure.StyledRun(seg_start, gs.baseline - drop[], seg_w, asc, desc))
    end
    return _RTState(x, gs.baseline, gs.size, gs.font)
end

# Walk threads `drop` through every recursive call. Sub/sup shift restores on node return;
# `drop` does not (it's a Ref — shared across the whole walk).
function _rt_walk!(runs::Vector{TextMeasure.StyledRun}, drop::Ref{Float64},
                   gs::_RTState, node)
    node isa AbstractString && return _rt_string!(runs, drop, gs, node)
    rt = node::Makie.RichText
    t  = rt.type
    if t === :subsup || t === :leftsubsup
        length(rt.children) == 2 ||
            throw(ArgumentError("$t requires exactly 2 children (sub, super)"))
        e_sub = _rt_walk!(runs, drop, _rt_subsup(gs, rt, Val(:sub)), rt.children[1])
        e_sup = _rt_walk!(runs, drop, _rt_subsup(gs, rt, Val(:sup)), rt.children[2])
        return _RTState(max(e_sub.x, e_sup.x), gs.baseline, gs.size, gs.font)
    else
        cur = _rt_child(gs, rt)
        for child in rt.children
            cur = _rt_walk!(runs, drop, cur, child)
        end
        return _RTState(cur.x, gs.baseline, gs.size, gs.font)
    end
end

function TextMeasure.measure_bounds(b::TextMeasure.MakieBackend, rt::Makie.RichText)
    runs = TextMeasure.StyledRun[]
    drop = Ref(0.0)
    gs0  = _RTState(0.0, 0.0, _pixel_size(b), b.face)
    _rt_walk!(runs, drop, gs0, rt)
    return TextMeasure.bounds(runs)
end
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `julia --project=test -e 'using TextMeasure, Test, Makie; include("test/test_richtext.jl")'`
Expected: PASS for all testsets (including the nested-newline cases — the box should match
Makie's bbox exactly, since `drop` persists across the inner span's return).

> If multi-line height is off by a consistent amount, confirm the live Makie version: `using Makie;
> pkgversion(Makie)`. The `20`px constant is for 0.24.x; if Makie changed it, update `_RT_LINE_DROP`
> and the comment, and note the new validated version in `test/test_richtext.jl`.
> If only the *nested* cases fail while the top-level ones pass, the `drop` Ref isn't actually
> being threaded — verify the recursive `_rt_walk!` calls all pass `drop` and that `_rt_walk!` does
> not return a fresh `_RTState` that drops `drop` (it shouldn't; `drop` lives outside the state).

- [ ] **Step 4: Commit**

```bash
git add ext/TextMeasureMakieExt.jl test/test_richtext.jl
git commit -m "feat: multi-line RichText incl. nested newlines (global line-drop Ref)"
```

---

### Task 6: Degenerate inputs — empty & whitespace-only

**Files:**
- Modify: `test/test_richtext.jl` (add golden cases)
- Modify: `ext/TextMeasureMakieExt.jl` only if the spike reveals a NaN/Inf guard is needed

- [ ] **Step 1: Write the test**

Add inside the outer `@testset` in `test/test_richtext.jl`:

```julia
    @testset "degenerate inputs" begin
        # must be finite and match Makie (whatever Makie reports for these)
        check(Makie.rich(""))
        check(Makie.rich(" "))
        check(Makie.rich("a", Makie.rich("")))   # empty nested span
    end
```

- [ ] **Step 2: Run it and observe Makie's behavior**

Run: `julia --project=test -e 'using TextMeasure, Test, Makie; include("test/test_richtext.jl")'`
Expected: PASS — empty `rich("")` produces zero runs → `bounds([]) = (0,0)`; whitespace `rich(" ")`
produces one run of `width = space advance`, `height = ascent+descent`, which equals Makie's box.

> **If Makie returns a non-finite or surprising box for `rich("")`** (e.g. a `Rect` with `Inf`/`NaN`
> widths because empty text has no glyphs): the `check` helper's `@test all(isfinite, o)` still
> guards *our* output (0×0 is finite). If the equality assertion fails because Makie's empty box
> differs from 0×0, adjust the empty-input assertions to match Makie's actual reported box (record
> the observed value as the golden expectation) rather than forcing 0×0 — Makie is the oracle. Add
> an explicit `isfinite` guard in `measure_bounds` only if a real input can produce NaN/Inf
> (it cannot today: advances and metrics are finite, so this is belt-and-suspenders).

- [ ] **Step 3: Commit**

```bash
git add test/test_richtext.jl ext/TextMeasureMakieExt.jl
git commit -m "test: RichText degenerate inputs (empty, whitespace-only)"
```

---

### Task 7: Full suite + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run the full test suite**

```bash
mkdir -p test-logs
julia --project -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"
```

Expected: all testsets pass, including `bounds (pure union)` and `RichText measure_bounds vs Makie`.

- [ ] **Step 2: Update the CHANGELOG**

Add under the unreleased/top section of `CHANGELOG.md`:

```markdown
### Added
- `measure_bounds(::MakieBackend, ::RichText) -> TextBounds`: pixel bounding box of Makie
  `rich` text (per-span fonts/sizes, sub/superscript, `subsup`/`leftsubsup`, multi-line),
  reproduced without a render pass and validated against Makie via a golden test. Plus the
  pure `TextBounds` result type. Mirrors Makie 0.24.x layout constants.
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for RichText measure_bounds"
```

---

## Self-Review

**Spec coverage:**
- Core seam `StyledRun`/`TextBounds`/`bounds` + `measure_bounds` stub → Task 1.
- Per-span font/size/offset inheritance, plain + mixed font → Task 2.
- `0.66`/`+0.40`/`−0.25` sub/superscript → Task 3.
- `subsup`/`leftsubsup` (max-width advance; left/right align noted irrelevant to AABB);
  **`:fontsize`/`:font` set on the subsup node itself, applied to both children via
  `_rt_subsup` reading `rt.attributes`** → Task 4.
- Multi-line `\n` at the `20`px stub, **including newlines nested inside spans —
  persistence across span returns via a global, monotonic `drop::Ref{Float64}` counter
  (mirrors Makie's two-stage `process_rt_node!` + `apply_lineheight!`)** → Task 5.
- Degenerate empty/whitespace inputs + golden samples → Task 6.
- Golden test vs `boundingbox(plot, :pixel)`, sizes only, real Scene, validated-version note → Task 2 (harness) + all tasks.
- Export `measure_bounds` + `TextBounds` only; `StyledRun`/`bounds` internal → Task 1.
- `StyledRun` +y-up vs `Layout` y-down documented → Task 1 docstring.
- Plain path untouched → no task edits `types.jl`/`layout.jl`/`prepare.jl`.
- CI/Dependabot → separate plan (`2026-05-27-ci-prerequisite.md`), not here. ✔ decomposed.

**Placeholder scan:** none — every code step shows complete code; "if it fails" notes are
diagnostic guidance, not deferred work. The one genuinely empirical value (Makie's box for
`rich("")`) is resolved by observation against the oracle in Task 6, with explicit handling.

**Type/signature consistency:** `StyledRun(x, baseline, width, ascent, descent)` and
`TextBounds(origin, size)` are used identically in Task 1's implementation, Task 1's tests, and
the extension (`_rt_string!`, `measure_bounds`). `_RTState(x, baseline, size, font)`,
`_rt_child`, `_rt_subsup`, `_rt_walk!`, `_rt_string!`, `_pixel_size`, and
`measure_bounds(::MakieBackend, ::RichText)` are named consistently across Tasks 2–6. Functions
that get fully replaced (not patched), shown in full to avoid out-of-order drift:
`_rt_child` in Task 3; `_rt_walk!` in Task 4 (subsup branch added); `_rt_subsup` is **added** in
Task 4 and takes the subsup node to read its `:fontsize`/`:font`; in Task 5, **three** functions
are atomically replaced — `_rt_string!`, `_rt_walk!`, and `measure_bounds` — to thread the
`drop::Ref{Float64}` line-drop counter. `_rt_subsup` is unchanged in Task 5 (it constructs a
state, doesn't recurse). Between Task 4's commit and Task 5's, all four functions are
mutually compatible (none takes `drop`); Task 5 swaps the three in one commit.
