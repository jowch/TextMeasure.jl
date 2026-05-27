# TextMeasure.jl Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone, backend-agnostic text layout engine in Julia — a `prepare`/`layout` split where measurement is pluggable (Monospace in core; FreeType and Makie as extensions) and layout (line-breaking, wrapping, alignment, bounding boxes) is pure arithmetic.

**Architecture:** Core defines immutable value types (`FontMetrics`, `Segment`, `Prepared`, `Line`, `Layout`), an abstract `AbstractMeasurementBackend` contract (`measure`, `font_metrics`), an in-core `MonospaceBackend`, and the line-breaking engine. `prepare(backend, text)` tokenizes + measures once; `layout(prep; …)` is pure. Accurate backends live in package extensions (Julia ≥1.9 weakdeps).

**Tech Stack:** Julia ≥1.9, `Unicode` stdlib (graphemes), `Test` stdlib. Weak deps: `FreeTypeAbstraction.jl` (0.10), `Makie.jl` (0.24).

> **Design refinement vs. spec:** The spec said backend *structs* live in the extensions. That makes the type name unreachable to users (extensions don't export into the parent namespace). The idiomatic fix used here: the **generic container structs** `FreeTypeBackend{F}` / `MakieBackend{F}` are defined and exported from **core** (they hold an opaque `face::F` and carry no FreeType/Makie code or deps), while their keyword constructors and `measure`/`font_metrics` *methods* live in the extensions. Core stays free of any FreeType/Makie dependency; the names are reachable as `TextMeasure.FreeTypeBackend`.

> **Execution model (full parallel):** Phase 0 is sequential and **freezes the type/Segment contract** every later stream codes against. Phase 1 runs as **three independent streams** (A: prepare, B: layout, C: extensions) — different source files, different test files, no shared state. Phase 2 integrates sequentially. Do **not** start Phase 1 until Phase 0 is committed and green.

---

## Test commands (reference)

- **Pure code** (Phase 0, Streams A & B): the package loads itself under its own project; `Test`/`Unicode` are stdlibs (always on `LOAD_PATH`). Run a single file:
  ```bash
  julia --project=. test/test_layout.jl
  ```
- **Extensions** (Stream C): weak deps are not loadable from `--project=.`. Use a **scratch env** (keeps the shared `@v1.12` clean). One-time setup, then run files:
  ```bash
  # setup once (run from repo root):
  julia --project=@tm-exttest -e 'using Pkg; Pkg.develop(path="."); Pkg.add(["FreeTypeAbstraction","Makie","Test"])'
  # run an extension test file (restart picks up src/ext changes):
  julia --project=@tm-exttest test/test_freetype.jl
  ```
- **Aggregate / CI** (Phase 2): `julia --project=. -e 'using Pkg; Pkg.test()'` (uses `test/Project.toml`).

---

## File structure

| File | Responsibility | Phase |
|------|----------------|-------|
| `Project.toml` | name/uuid, `[deps]` Unicode, `[weakdeps]`+`[extensions]`+`[compat]` | 0 |
| `src/TextMeasure.jl` | module: includes + exports | 0 |
| `src/types.jl` | `FontMetrics`, `Segment`, `Prepared`, `Line`, `Layout` | 0 |
| `src/backend.jl` | `AbstractMeasurementBackend`, `function measure`/`font_metrics` | 0 |
| `src/monospace.jl` | `MonospaceBackend` + methods (test backend) | 0 |
| `src/backend_containers.jl` | `FreeTypeBackend{F}`, `MakieBackend{F}` structs (no behavior) | 0 |
| `src/prepare.jl` | `prepare` tokenizer + `_measure_checked` | 0 stub → 1-A |
| `src/layout.jl` | `layout` engine + `line_top` | 0 stub → 1-B |
| `ext/TextMeasureFreeTypeExt.jl` | `FreeTypeBackend` ctor + methods | 1-C |
| `ext/TextMeasureMakieExt.jl` | `MakieBackend` ctor + methods | 1-C |
| `test/Project.toml` | test deps (Test, FreeTypeAbstraction, Makie) | 0 |
| `test/test_monospace.jl` | Monospace measure/metrics | 0 |
| `test/test_prepare.jl` | tokenization, guards | 1-A |
| `test/test_layout.jl` | wrap/align/geometry/edge cases | 1-B |
| `test/test_freetype.jl` | FreeType ext | 1-C |
| `test/test_makie.jl` | Makie ext (markerspace match) | 1-C |
| `test/test_integration.jl` | end-to-end prepare→layout | 2 |
| `test/runtests.jl` | aggregator | 2 |

---

# PHASE 0 — Foundation (sequential; freezes the contract)

## Task 1: Scaffold project + core types

**Files:**
- Modify: `Project.toml`
- Create: `src/TextMeasure.jl`, `src/types.jl`, `test/Project.toml`, `test/test_types.jl`

- [ ] **Step 1: Write `Project.toml`** (replace the whole file; keep the existing `uuid`)

```toml
name = "TextMeasure"
uuid = "06791c1d-2336-41e1-bd6f-a74c63395da6"
version = "0.1.0"
authors = ["Jonathan Chen <jwhc@ucla.edu>"]

[deps]
Unicode = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[weakdeps]
FreeTypeAbstraction = "663a7486-cb36-511b-a19d-713bb74d65c9"
Makie = "ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a"

[extensions]
TextMeasureFreeTypeExt = "FreeTypeAbstraction"
TextMeasureMakieExt = "Makie"

[compat]
FreeTypeAbstraction = "0.10"
Makie = "0.24"
Unicode = "1"
julia = "1.9"
```

- [ ] **Step 2: Write `src/types.jl`**

```julia
"""Vertical font metrics in pixels. `descent` is positive (distance below baseline)."""
struct FontMetrics
    ascent       :: Float64
    descent      :: Float64
    line_advance :: Float64   # natural baseline-to-baseline distance
end

"""One measured token. `kind ∈ (:word, :space, :newline)`; newline width is 0."""
struct Segment
    str   :: String
    width :: Float64
    kind  :: Symbol
end

"""Result of `prepare`: cached per-segment widths + font metrics. Treat as read-only."""
struct Prepared
    segments :: Vector{Segment}
    metrics  :: FontMetrics
end

"""One laid-out line. `str`/`width` are trimmed of leading/trailing whitespace.
`baseline` y has block-top = 0, increasing downward; `x` is the alignment offset."""
struct Line
    str      :: String
    width    :: Float64
    x        :: Float64
    baseline :: Float64
end

"""Result of `layout`: lines, overall `(width, height)` block extent, echoed `metrics`."""
struct Layout
    lines   :: Vector{Line}
    size    :: NTuple{2,Float64}
    metrics :: FontMetrics
end
```

- [ ] **Step 3: Write `src/TextMeasure.jl`**

```julia
module TextMeasure

using Unicode: graphemes

export prepare, layout, line_top
export Prepared, Layout, Line, FontMetrics
export AbstractMeasurementBackend, MonospaceBackend, FreeTypeBackend, MakieBackend

include("types.jl")
include("backend.jl")
include("monospace.jl")
include("backend_containers.jl")
include("prepare.jl")
include("layout.jl")

end # module
```

> Note: `Segment`, `measure`, and `font_metrics` are intentionally **not** exported (spec).

- [ ] **Step 3b: Create comment-only stubs for every file `TextMeasure.jl` includes but a later task implements**, so the module loads from Task 1 onward. Each later task (2/3/4 in Phase 0; A/B in Phase 1) *overwrites* its own stub.

Create these five files, each containing just a one-line comment:

`src/backend.jl` → `# AbstractMeasurementBackend + contract: implemented in Task 2.`
`src/monospace.jl` → `# MonospaceBackend: implemented in Task 3.`
`src/backend_containers.jl` → `# FreeTypeBackend/MakieBackend structs: implemented in Task 4.`
`src/prepare.jl` → `# prepare(): implemented in Phase 1, Stream A.`
`src/layout.jl` → `# layout() + line_top: implemented in Phase 1, Stream B.`

> Verified: a module that *exports* a name not yet defined loads cleanly in Julia 1.12 —
> the name only errors (`UndefVarError`) when accessed. So these comment stubs let the
> module load while the exported names (`MonospaceBackend`, `prepare`, …) stay undefined
> until their task fills them in. No task after Task 1 edits `src/TextMeasure.jl`.

- [ ] **Step 4: Write `test/Project.toml`**

```toml
[deps]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
FreeTypeAbstraction = "663a7486-cb36-511b-a19d-713bb74d65c9"
Makie = "ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a"
```

- [ ] **Step 5: Write `test/test_types.jl`** (tests types in isolation — doesn't load the not-yet-complete module)

```julia
using Test
include("../src/types.jl")

@testset "core types" begin
    m = FontMetrics(8.0, 2.0, 12.0)
    @test m.ascent == 8.0 && m.descent == 2.0 && m.line_advance == 12.0

    s = Segment("ab", 12.0, :word)
    @test s.kind === :word && s.width == 12.0

    p = Prepared([s], m)
    @test length(p.segments) == 1 && p.metrics === m

    ln = Line("ab", 12.0, 0.0, 8.0)
    lay = Layout([ln], (12.0, 10.0), m)
    @test lay.size == (12.0, 10.0) && lay.metrics === m
end
```

- [ ] **Step 6: Run the test**

Run: `julia test/test_types.jl`
Expected: PASS (`Test Summary: core types | Pass 4` — six conditions, four `@test`s)

- [ ] **Step 7: Commit**

```bash
git add Project.toml src/TextMeasure.jl src/types.jl \
        src/backend.jl src/monospace.jl src/backend_containers.jl src/prepare.jl src/layout.jl \
        test/Project.toml test/test_types.jl
git commit -m "feat: scaffold TextMeasure + core value types"
```

## Task 2: Backend contract

**Files:**
- Overwrite the Phase-0 stub: `src/backend.jl`

- [ ] **Step 1: Write `src/backend.jl`** (overwrite the Phase-0 stub)

```julia
"""
    AbstractMeasurementBackend

Supertype for measurement backends. A backend holds its font configuration and must
implement two methods (neither is exported — define them as `TextMeasure.measure` /
`TextMeasure.font_metrics`):

    measure(backend, text::AbstractString)::Float64   # advance width of ONE run, px
                                                       # (no line breaks; prepare segments)
    font_metrics(backend)::FontMetrics                # ascent/descent/line_advance, px

A run's width is the sum of glyph advances with NO kerning (matches Makie exactly).
"""
abstract type AbstractMeasurementBackend end

function measure end
function font_metrics end
```

- [ ] **Step 2: Verify it loads**

Run: `julia -e 'include("src/types.jl"); include("src/backend.jl"); println(measure isa Function && font_metrics isa Function && AbstractMeasurementBackend isa Type)'`
Expected: `true`

- [ ] **Step 3: Commit**

```bash
git add src/backend.jl
git commit -m "feat: abstract measurement backend contract"
```

## Task 3: MonospaceBackend (the test backend)

**Files:**
- Overwrite the Phase-0 stub: `src/monospace.jl`
- Create: `test/test_monospace.jl`

- [ ] **Step 1: Write `test/test_monospace.jl`**

```julia
using Test, TextMeasure

@testset "MonospaceBackend" begin
    b = MonospaceBackend(fontsize=10.0, advance_ratio=0.6, lineheight_ratio=1.2)

    # width = #grapheme-clusters * advance_ratio * fontsize
    @test TextMeasure.measure(b, "ab")  ≈ 2 * 0.6 * 10.0
    @test TextMeasure.measure(b, "")    == 0.0
    @test TextMeasure.measure(b, "2σ")  ≈ 2 * 0.6 * 10.0   # 2 grapheme clusters

    m = TextMeasure.font_metrics(b)
    @test m.ascent       ≈ 0.8 * 10.0
    @test m.descent      ≈ 0.2 * 10.0
    @test m.line_advance ≈ 1.2 * 10.0
    @test m.line_advance ≥ m.ascent + m.descent          # gap is non-negative

    # defaults
    bd = MonospaceBackend()
    @test bd.fontsize == 12.0 && bd.advance_ratio == 0.6 && bd.lineheight_ratio == 1.2
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `julia --project=. test/test_monospace.jl`
Expected: FAIL — `UndefVarError: MonospaceBackend` (the module loads thanks to the Phase-0 stubs, but `MonospaceBackend` isn't defined yet).

- [ ] **Step 3: Write `src/monospace.jl`**

```julia
"""
    MonospaceBackend(; fontsize=12, advance_ratio=0.6, lineheight_ratio=1.2)

Zero-dependency estimate: each grapheme cluster is `advance_ratio * fontsize` px wide.
Deterministic — also used as the test backend. `lineheight_ratio` sets the natural
`line_advance` (= `lineheight_ratio * fontsize`); distinct from `layout`'s `lineheight`.
"""
struct MonospaceBackend <: AbstractMeasurementBackend
    fontsize         :: Float64
    advance_ratio    :: Float64
    lineheight_ratio :: Float64
end

MonospaceBackend(; fontsize=12.0, advance_ratio=0.6, lineheight_ratio=1.2) =
    MonospaceBackend(Float64(fontsize), Float64(advance_ratio), Float64(lineheight_ratio))

measure(b::MonospaceBackend, text::AbstractString) =
    length(graphemes(text)) * b.advance_ratio * b.fontsize

font_metrics(b::MonospaceBackend) =
    FontMetrics(0.8 * b.fontsize, 0.2 * b.fontsize, b.lineheight_ratio * b.fontsize)
```

- [ ] **Step 4: Run to verify it passes**

Run: `julia --project=. test/test_monospace.jl`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/monospace.jl test/test_monospace.jl
git commit -m "feat: MonospaceBackend (zero-dep test backend)"
```

## Task 4: Backend container structs (freeze the extension contract)

**Files:**
- Overwrite the Phase-0 stub: `src/backend_containers.jl`
- Create: `test/test_containers.jl`

- [ ] **Step 1: Write `test/test_containers.jl`**

```julia
using Test, TextMeasure

@testset "backend container structs" begin
    # Generic container holds an opaque face; constructed positionally without any weak dep.
    ft = FreeTypeBackend("FACE", 12.0, 72.0)
    @test ft isa AbstractMeasurementBackend
    @test ft.face == "FACE" && ft.fontsize == 12.0 && ft.dpi == 72.0

    mk = MakieBackend("FACE", 14.0, 2.0)
    @test mk isa AbstractMeasurementBackend
    @test mk.face == "FACE" && mk.fontsize == 14.0 && mk.px_per_unit == 2.0

    # Keyword constructors require the extension; absent it, they error.
    @test_throws MethodError FreeTypeBackend(; font="Inter")
    @test_throws MethodError MakieBackend(; fontsize=12)
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `julia --project=. test/test_containers.jl`
Expected: FAIL — `UndefVarError: FreeTypeBackend`

- [ ] **Step 3: Write `src/backend_containers.jl`**

```julia
"""
    FreeTypeBackend(face, fontsize, dpi)

Container holding an opaque font face (`face::F`). The accurate keyword constructor
`FreeTypeBackend(; font, fontsize, dpi)` and the `measure`/`font_metrics` methods are
provided by the FreeTypeAbstraction extension — `using FreeTypeAbstraction` to enable.
"""
struct FreeTypeBackend{F} <: AbstractMeasurementBackend
    face     :: F
    fontsize :: Float64
    dpi      :: Float64
end

"""
    MakieBackend(face, fontsize, px_per_unit)

Container holding an opaque font face (`face::F`). The keyword constructor
`MakieBackend(; font, fontsize, px_per_unit)` and the `measure`/`font_metrics` methods are
provided by the Makie extension — `using Makie` to enable. Keep `px_per_unit = 1` to match
Makie's markerspace/scene geometry.
"""
struct MakieBackend{F} <: AbstractMeasurementBackend
    face        :: F
    fontsize    :: Float64
    px_per_unit :: Float64
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `julia --project=. test/test_containers.jl`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/backend_containers.jl test/test_containers.jl
git commit -m "feat: FreeTypeBackend/MakieBackend container structs"
```

**PHASE 0 GATE:** All of `test_types`, `test_monospace`, `test_containers` pass. The types, the `Segment` kind contract (`:word/:space/:newline`), `measure`/`font_metrics` signatures, and the container structs are now frozen. Phase 1 streams may begin in parallel.

---

# PHASE 1 — Parallel streams (A, B, C independent)

> Each stream owns distinct files: Stream A overwrites only `src/prepare.jl` (+ its test), Stream B only `src/layout.jl` (+ its test), Stream C only `ext/*` (+ their tests). `src/TextMeasure.jl` already includes all files (Phase 0), so **no stream edits it** — there is no shared-file merge point between the parallel streams.

## STREAM A — `prepare` (tokenize + measure)

### Task A1: `prepare` tokenizer

**Files:**
- Overwrite the Phase-0 stub: `src/prepare.jl`
- Create: `test/test_prepare.jl`
- (No edit to `src/TextMeasure.jl` — it already includes `prepare.jl`.)

- [ ] **Step 1: Write `test/test_prepare.jl`**

```julia
using Test, TextMeasure
import TextMeasure: Segment, prepare

# advance_ratio = 1.0, fontsize = 10  ⇒  each char is 10 px wide
const B = MonospaceBackend(fontsize=10.0, advance_ratio=1.0, lineheight_ratio=1.2)

kinds(p)  = [s.kind  for s in p.segments]
strs(p)   = [s.str   for s in p.segments]
widths(p) = [s.width for s in p.segments]

# Custom backends for the measurement guards (structs MUST be top-level, not in a @testset)
struct NaNBackend <: TextMeasure.AbstractMeasurementBackend end
TextMeasure.measure(::NaNBackend, ::AbstractString) = NaN
TextMeasure.font_metrics(::NaNBackend) = FontMetrics(1.0, 1.0, 1.0)

struct NegBackend <: TextMeasure.AbstractMeasurementBackend end
TextMeasure.measure(::NegBackend, ::AbstractString) = -5.0
TextMeasure.font_metrics(::NegBackend) = FontMetrics(1.0, 1.0, 1.0)

@testset "prepare tokenization" begin
    p = prepare(B, "ab cd")
    @test kinds(p)  == [:word, :space, :word]
    @test strs(p)   == ["ab", " ", "cd"]
    @test widths(p) == [20.0, 10.0, 20.0]
    @test p.metrics.ascent ≈ 8.0

    # multiple interior spaces are ONE space segment (preserved, not collapsed)
    p2 = prepare(B, "a  b")
    @test kinds(p2) == [:word, :space, :word]
    @test strs(p2)  == ["a", "  ", "b"]

    # each newline is its own segment, width 0
    p3 = prepare(B, "a\nb")
    @test kinds(p3) == [:word, :newline, :word]
    @test widths(p3)[2] == 0.0
    @test prepare(B, "\n\n").segments |> length == 2
    @test all(s.kind === :newline for s in prepare(B, "\n\n").segments)

    # tab counts as space
    @test kinds(prepare(B, "a\tb")) == [:word, :space, :word]

    # empty string ⇒ no segments
    @test isempty(prepare(B, "").segments)
end

@testset "prepare measurement guards" begin
    @test_throws ArgumentError prepare(NaNBackend(), "x")
    @test prepare(NegBackend(), "x").segments[1].width == 0.0   # clamped
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `julia --project=. test/test_prepare.jl`
Expected: FAIL — `UndefVarError: prepare`. (A harmless `WARNING: Imported binding TextMeasure.prepare was undeclared at import time` precedes it — that's the `import` of the not-yet-defined name, not the failure cause.)

- [ ] **Step 3: Write `src/prepare.jl`** (overwrite the Phase-0 stub)

```julia
function _measure_checked(backend::AbstractMeasurementBackend, s::AbstractString)
    w = measure(backend, s)
    isnan(w) && throw(ArgumentError("backend measured NaN for run $(repr(s))"))
    return max(0.0, Float64(w))
end

function _flush!(segs::Vector{Segment}, buf::IOBuffer, bufclass::Symbol,
                 backend::AbstractMeasurementBackend)
    if bufclass !== :none
        s = String(take!(buf))
        push!(segs, Segment(s, _measure_checked(backend, s), bufclass))
    end
    return :none
end

"""
    prepare(backend, text) -> Prepared

Tokenize `text` into `:word` / `:space` / `:newline` segments and measure each run once
via `backend`. The only phase that touches the font engine.
"""
function prepare(backend::AbstractMeasurementBackend, text::AbstractString)::Prepared
    metrics = font_metrics(backend)
    segs = Segment[]
    buf = IOBuffer()
    bufclass = :none
    for c in text
        if c == '\n'
            bufclass = _flush!(segs, buf, bufclass, backend)
            push!(segs, Segment("\n", 0.0, :newline))
        else
            cls = (c == ' ' || c == '\t') ? :space : :word
            if cls !== bufclass
                bufclass = _flush!(segs, buf, bufclass, backend)
                bufclass = cls
            end
            print(buf, c)
        end
    end
    _flush!(segs, buf, bufclass, backend)
    return Prepared(segs, metrics)
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `julia --project=. test/test_prepare.jl`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/prepare.jl test/test_prepare.jl
git commit -m "feat: prepare() tokenizer + measurement guards"
```

## STREAM B — `layout` (pure engine)

### Task B1: layout core — single/multi-word, wrap, over-wide, geometry

**Files:**
- Overwrite the Phase-0 stub: `src/layout.jl`
- Create: `test/test_layout.jl`
- (No edit to `src/TextMeasure.jl` — it already includes `layout.jl`.)

- [ ] **Step 1: Write `test/test_layout.jl`** (Stream B builds `Prepared` by hand — no dependency on `prepare`)

```julia
using Test, TextMeasure
import TextMeasure: Segment, Prepared, layout, line_top

const M = FontMetrics(8.0, 2.0, 12.0)   # ascent 8, descent 2, line_advance 12
W(s, w) = Segment(s, w, :word)
SP(w)   = Segment(" "^max(1,round(Int,w/6)), w, :space)  # str length irrelevant to math
NL()    = Segment("\n", 0.0, :newline)
prep(segs) = Prepared(collect(segs), M)

@testset "single + multi-word, no wrap" begin
    lay = layout(prep([W("ab", 12.0)]))
    @test length(lay.lines) == 1
    @test lay.lines[1].str == "ab"
    @test lay.lines[1].width == 12.0
    @test lay.lines[1].x == 0.0
    @test lay.lines[1].baseline == 8.0          # first baseline = ascent
    @test lay.size == (12.0, 10.0)              # N=1 ⇒ ascent + descent
    @test lay.metrics === M

    lay2 = layout(prep([W("ab",12.0), Segment(" ",6.0,:space), W("cd",12.0)]))
    @test length(lay2.lines) == 1
    @test lay2.lines[1].str == "ab cd"
    @test lay2.lines[1].width == 30.0
    @test lay2.size == (30.0, 10.0)
end

@testset "wrapping + geometry" begin
    segs = [W("ab",12.0), Segment(" ",6.0,:space), W("cd",12.0)]
    lay = layout(prep(segs); max_width=20.0)    # 12+6+12=30 > 20 ⇒ break before "cd"
    @test [l.str for l in lay.lines] == ["ab", "cd"]
    @test [l.width for l in lay.lines] == [12.0, 12.0]
    @test [l.baseline for l in lay.lines] == [8.0, 20.0]   # ascent, ascent+la
    @test lay.size == (12.0, 22.0)              # N=2 ⇒ ascent + 1*la + descent
    # the space at the wrap point is consumed (neither line keeps it)
    @test lay.lines[1].str == "ab" && lay.lines[2].str == "cd"
end

@testset "trailing/leading whitespace trimmed; interior preserved" begin
    # leading + trailing spaces dropped
    lay = layout(prep([Segment(" ",6.0,:space), W("hi",12.0), Segment(" ",6.0,:space)]))
    @test lay.lines[1].str == "hi" && lay.lines[1].width == 12.0
    # interior double space preserved
    lay2 = layout(prep([W("a",6.0), Segment("  ",12.0,:space), W("b",6.0)]))
    @test lay2.lines[1].str == "a  b" && lay2.lines[1].width == 24.0
end

@testset "over-wide token gets its own line; size reports true width" begin
    segs = [W("toolong", 42.0), Segment(" ",6.0,:space), W("x", 6.0)]
    lay = layout(prep(segs); max_width=10.0)
    @test [l.str for l in lay.lines] == ["toolong", "x"]
    @test lay.size[1] == 42.0                   # true overflow width
end

@testset "max_width ≤ 0 or NaN ⇒ no wrap" begin
    segs = [W("a",6.0), Segment(" ",6.0,:space), W("b",6.0)]
    @test length(layout(prep(segs); max_width=0.0).lines)  == 1
    @test length(layout(prep(segs); max_width=NaN).lines)  == 1
    @test length(layout(prep(segs); max_width=-5.0).lines) == 1
end

@testset "line_top helper" begin
    segs = [W("a",6.0), NL(), W("b",6.0)]
    lay = layout(prep(segs))
    @test line_top(lay, lay.lines[1]) == 0.0    # baseline 8 - ascent 8
    @test line_top(lay, lay.lines[2]) == 12.0   # baseline 20 - ascent 8 = la
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `julia --project=. test/test_layout.jl`
Expected: FAIL — `UndefVarError: layout`. (A harmless `WARNING: Imported binding ... was undeclared at import time` precedes it — that's the `import` of the not-yet-defined name, not the failure cause.)

- [ ] **Step 3: Write `src/layout.jl`** (overwrite the Phase-0 stub)

```julia
function _emit_line!(raw::Vector{Tuple{String,Float64}}, committed::Vector{Segment})
    s = join(seg.str for seg in committed)
    w = isempty(committed) ? 0.0 : sum(seg.width for seg in committed)
    push!(raw, (s, w))
    empty!(committed)
    return nothing
end

_align_x(align::Symbol, total::Float64, w::Float64) =
    align === :left   ? 0.0 :
    align === :center ? (total - w) / 2 :
    align === :right  ? (total - w) :
    throw(ArgumentError("align must be :left, :center, or :right; got $(repr(align))"))

"""
    layout(prep; max_width=Inf, align=:left, lineheight=1.0) -> Layout

Pure greedy line-breaking over a `Prepared`. Breaks at whitespace and `\\n`; words are
atomic (an over-wide word overflows its own line). `lineheight` multiplies
`prep.metrics.line_advance`. Trims leading/trailing whitespace per line.
"""
function layout(prep::Prepared; max_width::Real=Inf, align::Symbol=:left, lineheight::Real=1.0)::Layout
    m  = prep.metrics
    la = lineheight * m.line_advance
    mw = (isnan(max_width) || max_width <= 0) ? Inf : Float64(max_width)

    isempty(prep.segments) && return Layout(Line[], (0.0, 0.0), m)

    raw = Tuple{String,Float64}[]
    committed = Segment[]
    committed_w = 0.0
    pending::Union{Nothing,Segment} = nothing

    for seg in prep.segments
        if seg.kind === :newline
            _emit_line!(raw, committed); committed_w = 0.0; pending = nothing
        elseif seg.kind === :space
            pending = seg
        else  # :word
            if isempty(committed)
                push!(committed, seg); committed_w = seg.width; pending = nothing
            else
                extra = (pending === nothing ? 0.0 : pending.width) + seg.width
                if committed_w + extra > mw
                    _emit_line!(raw, committed)
                    push!(committed, seg); committed_w = seg.width; pending = nothing
                else
                    if pending !== nothing
                        push!(committed, pending); committed_w += pending.width; pending = nothing
                    end
                    push!(committed, seg); committed_w += seg.width
                end
            end
        end
    end
    _emit_line!(raw, committed)   # final line

    N = length(raw)
    total_w = maximum(t -> t[2], raw)
    height  = m.ascent + (N - 1) * la + m.descent
    lines = Vector{Line}(undef, N)
    for (i, (s, w)) in enumerate(raw)
        lines[i] = Line(s, w, _align_x(align, total_w, w), m.ascent + (i - 1) * la)
    end
    return Layout(lines, (total_w, height), m)
end

"""    line_top(lay, ln) -> Float64

Top-left y of line `ln` (block top = 0). `ln` must be a line of `lay`."""
line_top(lay::Layout, ln::Line) = ln.baseline - lay.metrics.ascent
```

- [ ] **Step 4: Run to verify it passes**

Run: `julia --project=. test/test_layout.jl`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/layout.jl test/test_layout.jl
git commit -m "feat: layout() core — wrap, geometry, over-wide, line_top"
```

### Task B2: alignment

**Files:**
- Modify: `test/test_layout.jl` (append)

- [ ] **Step 1: Append alignment tests to `test/test_layout.jl`**

```julia
@testset "alignment" begin
    # two lines of differing width: "abcd"(24) wraps from "ef"(12) at max_width=24
    segs = [W("abcd",24.0), Segment(" ",6.0,:space), W("ef",12.0)]
    p = prep(segs)

    ll = layout(p; max_width=24.0, align=:left)
    @test [l.x for l in ll.lines] == [0.0, 0.0]

    lc = layout(p; max_width=24.0, align=:center)
    @test lc.size[1] == 24.0
    @test [l.x for l in lc.lines] == [0.0, 6.0]   # (24-24)/2, (24-12)/2

    lr = layout(p; max_width=24.0, align=:right)
    @test [l.x for l in lr.lines] == [0.0, 12.0]  # 24-24, 24-12

    @test_throws ArgumentError layout(p; align=:justify)
end
```

- [ ] **Step 2: Run** — `julia --project=. test/test_layout.jl` — Expected: PASS (alignment already implemented in B1; this locks it).

- [ ] **Step 3: Commit**

```bash
git add test/test_layout.jl
git commit -m "test: layout alignment (left/center/right + bad-align error)"
```

### Task B3: newlines, blank lines, trailing newline, whitespace-only, empty

**Files:**
- Modify: `test/test_layout.jl` (append)

- [ ] **Step 1: Append edge-case tests to `test/test_layout.jl`**

```julia
@testset "newlines and blank lines" begin
    # "a\nb" ⇒ 2 lines
    @test [l.str for l in layout(prep([W("a",6.0), NL(), W("b",6.0)])).lines] == ["a", "b"]

    # trailing newline ⇒ trailing empty line: "a\n" ⇒ ["a", ""]
    l1 = layout(prep([W("a",6.0), NL()]))
    @test [l.str for l in l1.lines] == ["a", ""]
    @test l1.lines[2].width == 0.0
    @test l1.size[2] == 8.0 + 1*12.0 + 2.0       # N=2

    # lone "\n" ⇒ 2 empty lines; "\n\n" ⇒ 3
    @test length(layout(prep([NL()])).lines) == 2
    @test length(layout(prep([NL(), NL()])).lines) == 3
    @test all(l.str == "" for l in layout(prep([NL(), NL()])).lines)
end

@testset "whitespace-only and empty" begin
    # whitespace-only (no newline) ⇒ ONE empty line, width 0, height = ascent+descent
    lws = layout(prep([Segment("   ",18.0,:space)]))
    @test length(lws.lines) == 1
    @test lws.lines[1].str == "" && lws.lines[1].width == 0.0
    @test lws.size == (0.0, 10.0)

    # empty input (no segments) ⇒ ZERO lines, size (0,0); still carries metrics
    le = layout(Prepared(Segment[], M))
    @test isempty(le.lines)
    @test le.size == (0.0, 0.0)
    @test le.metrics === M
end
```

- [ ] **Step 2: Run** — `julia --project=. test/test_layout.jl` — Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/test_layout.jl
git commit -m "test: layout newlines, blank/trailing/empty edge cases"
```

## STREAM C — Extensions (FreeType + Makie)

> Uses the scratch env from the Test-commands section; the one-time setup in Task C1 Step 1 installs the deps for **both** C1 and C2. Stream C is independent of Streams A and B — its tests assert only backend-specific properties (`measure`/`font_metrics`/additivity/scaling). The real-backend `prepare → layout` end-to-end check lives in Phase 2 (`test_integration.jl`), which runs after A+B+C merge.
>
> **Heads-up:** the first `Pkg.add`/precompile of Makie (and the first `using Makie`) is heavy — expect several minutes. A slow extension step is precompilation, not a hang.

### Task C1: FreeTypeBackend extension

**Files:**
- Create: `ext/TextMeasureFreeTypeExt.jl`, `test/test_freetype.jl`

- [ ] **Step 1: One-time scratch env setup** (from repo root)

```bash
julia --project=@tm-exttest -e 'using Pkg; Pkg.develop(path="."); Pkg.add(["FreeTypeAbstraction","Makie","Test"])'
```

- [ ] **Step 2: Write `test/test_freetype.jl`** (version-independent invariants, not brittle absolute pixels)

```julia
using Test, TextMeasure, FreeTypeAbstraction

@testset "FreeTypeBackend" begin
    b = FreeTypeBackend(; font="DejaVu Sans", fontsize=100.0, dpi=72.0)
    @test b isa AbstractMeasurementBackend

    wA  = TextMeasure.measure(b, "A")
    wB  = TextMeasure.measure(b, "B")
    wAB = TextMeasure.measure(b, "AB")
    @test wA > 0 && isfinite(wA)
    @test wAB ≈ wA + wB                       # no kerning ⇒ runs are additive
    @test TextMeasure.measure(b, "A") == wA   # stable across calls
    @test TextMeasure.measure(b, "") == 0.0

    m = TextMeasure.font_metrics(b)
    @test m.ascent > 0 && m.descent > 0 && m.line_advance > 0
    @test isfinite(m.line_advance)

    # dpi scales linearly: dpi=144 doubles widths vs dpi=72 (guards unit/DPI regressions)
    b2 = FreeTypeBackend(; font="DejaVu Sans", fontsize=100.0, dpi=144.0)
    @test TextMeasure.measure(b2, "A") ≈ 2 * wA

    # golden sanity: catches a gross unit bug (font-units → thousands, em-fractions → <1).
    # "A" in DejaVu Sans at fontsize=100, dpi=72 is ~60–80 px.
    @test 40.0 < wA < 100.0
end
```

- [ ] **Step 3: Run to verify it fails**

Run: `julia --project=@tm-exttest test/test_freetype.jl`
Expected: FAIL — keyword `FreeTypeBackend(; font=...)` has no method yet.

- [ ] **Step 4: Write `ext/TextMeasureFreeTypeExt.jl`**

```julia
module TextMeasureFreeTypeExt

using TextMeasure
using FreeTypeAbstraction
const FTA = FreeTypeAbstraction

function TextMeasure.FreeTypeBackend(; font="Inter", fontsize=12, dpi=72)
    face = FTA.findfont(font)
    face === nothing && throw(ArgumentError("font not found: $(repr(font))"))
    return TextMeasure.FreeTypeBackend(face, Float64(fontsize), Float64(dpi))
end

_pixel_size(b::TextMeasure.FreeTypeBackend) = b.fontsize * b.dpi / 72

function TextMeasure.measure(b::TextMeasure.FreeTypeBackend, text::AbstractString)
    px = _pixel_size(b)
    w = 0.0
    for c in text
        w += FTA.hadvance(FTA.get_extent(b.face, c))   # normalized advance, no kerning
    end
    return w * px
end

function TextMeasure.font_metrics(b::TextMeasure.FreeTypeBackend)
    px   = _pixel_size(b)
    upem = b.face.units_per_EM
    asc  = FTA.ascender(b.face)  * px
    desc = -FTA.descender(b.face) * px               # FT descender is negative
    h    = b.face.height
    la   = h == 0 ? asc + desc : (h / upem) * px     # guard rare height==0 fonts
    return TextMeasure.FontMetrics(asc, desc, la)
end

end # module
```

- [ ] **Step 5: Run to verify it passes**

Run: `julia --project=@tm-exttest test/test_freetype.jl`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add ext/TextMeasureFreeTypeExt.jl test/test_freetype.jl
git commit -m "feat: FreeTypeBackend extension"
```

### Task C2: MakieBackend extension (markerspace match)

**Files:**
- Create: `ext/TextMeasureMakieExt.jl`, `test/test_makie.jl`

- [ ] **Step 1: Write `test/test_makie.jl`** (the key property: matches Makie's own run width at px_per_unit=1)

```julia
using Test, TextMeasure, Makie

@testset "MakieBackend" begin
    b = MakieBackend(; font="TeX Gyre Heros Makie", fontsize=24.0, px_per_unit=1.0)
    @test b isa AbstractMeasurementBackend

    face = Makie.to_font("TeX Gyre Heros Makie")
    for s in ("Mauna Kea", "AVATAR", "fjord", "Aconcagua")
        ours  = TextMeasure.measure(b, s)
        makie = Makie.widths(Makie.text_bb(s, face, 24.0))[1]   # markerspace width
        @test ours ≈ makie rtol=1e-4                            # spike measured 0.0% diff
    end

    @test TextMeasure.measure(b, "") == 0.0

    m = TextMeasure.font_metrics(b)
    @test m.ascent > 0 && m.descent > 0 && m.line_advance > 0

    # px_per_unit scales widths linearly
    b2 = MakieBackend(; font="TeX Gyre Heros Makie", fontsize=24.0, px_per_unit=2.0)
    @test TextMeasure.measure(b2, "AVATAR") ≈ 2 * TextMeasure.measure(b, "AVATAR")
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `julia --project=@tm-exttest test/test_makie.jl`
Expected: FAIL — keyword `MakieBackend(; …)` has no method yet.

- [ ] **Step 3: Write `ext/TextMeasureMakieExt.jl`**

```julia
module TextMeasureMakieExt

using TextMeasure
using Makie
const FTA = Makie.FreeTypeAbstraction   # Makie.NativeFont === FTA.FTFont

function TextMeasure.MakieBackend(; font=Makie.automatic, fontsize=12, px_per_unit=1.0)
    face = Makie.to_font(font)          # resolves to an FTFont (identical to text!'s)
    return TextMeasure.MakieBackend(face, Float64(fontsize), Float64(px_per_unit))
end

_pixel_size(b::TextMeasure.MakieBackend) = b.fontsize * b.px_per_unit

function TextMeasure.measure(b::TextMeasure.MakieBackend, text::AbstractString)
    px = _pixel_size(b)
    w = 0.0
    for c in text
        w += FTA.hadvance(FTA.get_extent(b.face, c))
    end
    return w * px
end

function TextMeasure.font_metrics(b::TextMeasure.MakieBackend)
    px   = _pixel_size(b)
    upem = b.face.units_per_EM
    asc  = FTA.ascender(b.face)  * px
    desc = -FTA.descender(b.face) * px
    h    = b.face.height
    la   = h == 0 ? asc + desc : (h / upem) * px
    return TextMeasure.FontMetrics(asc, desc, la)
end

end # module
```

- [ ] **Step 4: Run to verify it passes**

Run: `julia --project=@tm-exttest test/test_makie.jl`
Expected: PASS (all `ours ≈ makie` at rtol 1e-4)

- [ ] **Step 5: Commit**

```bash
git add ext/TextMeasureMakieExt.jl test/test_makie.jl
git commit -m "feat: MakieBackend extension (markerspace width match)"
```

**PHASE 1 GATE:** Streams A, B, C all committed and green on their own test files.

---

# PHASE 2 — Integration (sequential)

## Task 5: Aggregate test runner + end-to-end

**Files:**
- Create: `test/runtests.jl`, `test/test_integration.jl`

- [ ] **Step 1: Write `test/test_integration.jl`** (prepare → layout through the Monospace path)

```julia
using Test, TextMeasure
using FreeTypeAbstraction   # exercises the real-backend → prepare → layout path

@testset "integration: prepare → layout (Monospace)" begin
    b = MonospaceBackend(fontsize=10.0, advance_ratio=1.0, lineheight_ratio=1.2)
    # 10 px/char. "one two three" wrapped to 60 px.
    lay = layout(prepare(b, "one two three"); max_width=60.0)
    @test all(l.width ≤ 60.0 || length(split(l.str)) == 1 for l in lay.lines)
    @test join([l.str for l in lay.lines], " ") == "one two three"   # words preserved in order
    @test lay.size[2] ≈ 8.0 + (length(lay.lines)-1)*12.0 + 2.0       # height matches N
end

@testset "integration: prepare → layout (FreeType backend)" begin
    b = FreeTypeBackend(; font="DejaVu Sans", fontsize=14.0)
    lay = layout(prepare(b, "the quick brown fox"); max_width=80.0)
    @test length(lay.lines) ≥ 2                      # wraps at 80 px
    @test all(isfinite(l.baseline) for l in lay.lines)
    @test lay.size[1] > 0 && lay.size[2] > 0
end
```

- [ ] **Step 2: Write `test/runtests.jl`**

```julia
using Test

@testset "TextMeasure" begin
    include("test_types.jl")
    include("test_monospace.jl")
    include("test_containers.jl")
    include("test_prepare.jl")
    include("test_layout.jl")
    include("test_integration.jl")
    include("test_freetype.jl")   # extension loads via test/Project.toml deps
    include("test_makie.jl")
end
```

- [ ] **Step 3: Run the full suite**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS — all testsets green (extensions trigger because `test/Project.toml` lists FreeTypeAbstraction + Makie as full deps).

- [ ] **Step 4: Commit**

```bash
git add test/runtests.jl test/test_integration.jl
git commit -m "test: aggregate runner + prepare→layout integration"
```

## Task 6: README + docstrings

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write `README.md`**

````markdown
# TextMeasure.jl

A backend-agnostic text **layout engine**: measure once, lay out many times.
Inspired by [pretext.js](https://github.com/chenglou/pretext), using FreeType/Makie
rather than canvas.

```julia
using TextMeasure
using FreeTypeAbstraction                # enables FreeTypeBackend

b   = FreeTypeBackend(; font="DejaVu Sans", fontsize=14)
prp = prepare(b, "The quick brown fox")  # measures once (touches the font engine)
lay = layout(prp; max_width=120, align=:left)   # pure arithmetic — call freely

lay.size                                  # (width, height) in px
for ln in lay.lines
    @show ln.str, ln.x, line_top(lay, ln) # top-left placement, block-top = 0
end
```

Backends: `MonospaceBackend` (zero-dep, built in), `FreeTypeBackend`
(`using FreeTypeAbstraction`), `MakieBackend` (`using Makie`; measurements match
Makie's `text!` at `px_per_unit = 1`).

**Not in scope:** rendering, repel/treemap/annotation consumers (downstream), UAX-#14
line-breaking, CJK, hyphenation, justification, rotation.
````

- [ ] **Step 2: Verify the README example runs** (in scratch env)

Run:
```bash
julia --project=@tm-exttest -e 'using TextMeasure, FreeTypeAbstraction;
  b=FreeTypeBackend(;font="DejaVu Sans",fontsize=14);
  lay=layout(prepare(b,"The quick brown fox"); max_width=120);
  println(lay.size); println(length(lay.lines))'
```
Expected: prints a `(width, height)` tuple and a line count ≥ 1.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README with usage example"
```

**PHASE 2 GATE / DONE:** `Pkg.test()` green; README example runs.

---

## Self-review notes (for the implementer)

- **Phase 0 stubs:** all five included-but-later files (`backend.jl`, `monospace.jl`, `backend_containers.jl`, `prepare.jl`, `layout.jl`) are created in Task 1 as comment-only stubs so the module loads from Task 1 onward (a module exporting a not-yet-defined name loads fine; the name throws `UndefVarError` only on access). Each later task *overwrites* its own stub — no task after Task 1 touches `src/TextMeasure.jl`, so there is no shared-file merge point between the parallel streams.
- **`measure`/`font_metrics`/`Segment` are not exported** — always qualify (`TextMeasure.measure`) or `import` them in tests.
- **Backend container structs are parametric** (`{F}`) so `face` is type-stable; core never names `FTFont`.
- **Extension tests use the scratch env** (`@tm-exttest`); the aggregate `Pkg.test()` uses `test/Project.toml`. Both must list FreeTypeAbstraction + Makie.
