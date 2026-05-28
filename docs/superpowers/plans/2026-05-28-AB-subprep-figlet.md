# #A `subprep` + #B `FigletBackend` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task, with superpowers:test-driven-development as the inner loop. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `Prepared(; segments, metrics)` kwargs constructor + `subprep` segment-slice helper (#A), and wire `FigletBackend` to the registered `FIGlet.jl` package via the canonical weakdep-extension pattern (#B), on one branch / one PR.

**Architecture:** #A is pure arithmetic over the existing `Prepared` struct — an outer kwargs constructor (preserving the auto-generated positional constructor) plus a one-line slicing helper; no `Base.getindex` override. #B is the *third* instance of the `FreeTypeBackend`/`MakieBackend` weakdep-ext pattern: a parametric container struct in `src/`, methods in a gated `ext/`, FIGlet declared as a weakdep. FIGlet measures in **character cells (not pixels)** and uses an **`Int` `letter_gap`** — two deliberate departures documented in the ext preamble. The FIGlet integration test lives in a **separate CI job** (`ext_tests.yml`), keeping the main `Pkg.test()` suite FIGlet-free and fast.

**Tech Stack:** Julia 1.11+, package extensions (weakdeps), `FIGlet.jl` v0.2.x (`3064a664-84fe-4d92-92c7-ed492f3d8fae`, MIT), `Test`.

**Branch:** `demos-AB-subprep-figlet` (worktree off `main`).

**Ordering:** Do all of Part A (#A), commit, then all of Part B (#B). They overlap only on `src/TextMeasure.jl`'s export list and `CHANGELOG.md`.

**Files touched (decomposition map):**

| File | #A | #B | Responsibility |
|---|---|---|---|
| `src/types.jl` | ✎ | | Add outer kwargs constructor after `Prepared` struct (currently L15-19). |
| `src/prepare.jl` | ✎ | | Add `subprep` helper + docstring. |
| `src/TextMeasure.jl` | ✎ (export `subprep`) | ✎ (export `FigletBackend`) | **Shared overlap** — export list (currently L5-7). |
| `src/backend_containers.jl` | | ✎ | Add `FigletBackend{F}` struct alongside the existing two. |
| `src/backend.jl` | | ✎ | `AbstractMeasurementBackend` docstring cross-references all three exts. |
| `ext/TextMeasureFigletExt.jl` | | ＋ | New ext: keyword ctor + `measure` + `font_metrics` + heavy preamble. |
| `Project.toml` | | ✎ | FIGlet `[weakdeps]` + `[extensions]` + `[compat]`. |
| `test/test_types.jl` | ✎ | | kwargs-ctor round-trip. |
| `test/test_prepare.jl` | ✎ | | `subprep` field-equiv + word-boundary width-sum + cross-newline/space integrity. |
| `test/test_containers.jl` | | ✎ | `FigletBackend` positional construct + keyword-throws-without-ext. |
| `test/figlet/Project.toml` | | ＋ | Isolated env for the FIGlet integration test (FIGlet + Test + TextMeasure). |
| `test/figlet/runtests.jl` | | ＋ | Pinned widths (Standard + Small), `Base.get_extension` registration, conformance. |
| `.github/workflows/ext_tests.yml` | | ＋ | Separate CI job triggered on `ext/` changes; runs `test/figlet`. |
| `CHANGELOG.md` | ✎ | ✎ | **Shared overlap** — one Added entry each. |

---

## Part A — #A `Prepared` segment-slice helper

### Task A1: `Prepared(; segments, metrics)` kwargs constructor

**Files:**
- Modify: `src/types.jl` (after the `Prepared` struct, currently L15-19)
- Test: `test/test_types.jl`

- [ ] **Step 1: Write the failing test**

Append inside the `@testset "core types"` block in `test/test_types.jl` (before its closing `end`):

```julia
    # kwargs constructor (outer method) round-trips to the positional one
    s2 = Segment("cd", 6.0, :word)
    pk = Prepared(; segments=[s2], metrics=m)
    @test pk.segments == [s2] && pk.metrics === m
    # positional constructor still works (auto-generated, not shadowed)
    pp = Prepared([s2], m)
    @test pp.segments == [s2] && pp.metrics === m
```

- [ ] **Step 2: Run test to verify it fails**

Run: `julia --project=test -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | grep -i "test_types\|MethodError\|keyword"`
Expected: FAIL — no method matching `Prepared(; segments, metrics)`.

- [ ] **Step 3: Write minimal implementation**

In `src/types.jl`, immediately after the `Prepared` struct's `end` (L19), add:

```julia

"""
    Prepared(; segments, metrics)

Keyword constructor (outer method) forwarding to the positional
`Prepared(segments, metrics)`. The positional constructor is preserved.
"""
Prepared(; segments, metrics) = Prepared(segments, metrics)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `julia --project=test -e 'using TextMeasure, Test; include("test/test_types.jl")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/types.jl test/test_types.jl
git commit -m "feat(#A): Prepared(; segments, metrics) kwargs constructor"
```

### Task A2: `subprep(prep, r)` helper + export

**Files:**
- Modify: `src/prepare.jl` (append after `prepare`, currently ends L42)
- Modify: `src/TextMeasure.jl:5` (export list)
- Test: `test/test_prepare.jl`

- [ ] **Step 1: Write the failing test**

Append a new `@testset` to `test/test_prepare.jl` (uses `MonospaceBackend`, the deterministic test backend; check the file's existing `using`/backend setup and reuse it):

```julia
@testset "subprep" begin
    b = MonospaceBackend(; fontsize=10.0)        # deterministic test backend
    prep = prepare(b, "the quick\nbrown fox")    # words, spaces, a newline

    # full-range slice is field-equivalent (== may default to identity on mutable fields)
    full = subprep(prep, 1:length(prep.segments))
    @test full.metrics == prep.metrics
    @test length(full.segments) == length(prep.segments)
    @test all(full.segments[i] == prep.segments[i] for i in 1:length(prep.segments))

    # slice at a word boundary, layout both halves, widths sum back.
    # find the index of the first :space segment; split there.
    sp = findfirst(s -> s.kind === :space, prep.segments)
    left  = subprep(prep, 1:sp-1)
    right = subprep(prep, sp+1:length(prep.segments))
    # no segments dropped or duplicated across the split point
    @test length(left.segments) + 1 + length(right.segments) == length(prep.segments)
    # widths of the word segments are preserved verbatim (no re-measure)
    wl = sum(s.width for s in left.segments)
    wr = sum(s.width for s in right.segments)
    worig = sum(s.width for s in prep.segments if s.kind !== :newline)
    @test wl + prep.segments[sp].width + wr ≈ worig

    # slicing across :newline preserves integrity: the segment lands in the indexed side
    nl = findfirst(s -> s.kind === :newline, prep.segments)
    @test subprep(prep, 1:nl).segments[end].kind === :newline
    @test subprep(prep, nl+1:length(prep.segments)).segments[1].kind !== :newline
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `julia --project=test -e 'using TextMeasure, Test; include("test/test_prepare.jl")' 2>&1 | grep -i "subprep\|UndefVar\|not defined"`
Expected: FAIL — `subprep` not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `src/prepare.jl`:

```julia

"""
    subprep(prep::Prepared, r::AbstractUnitRange) -> Prepared

Return a `Prepared` over the segment sub-range `r`, reusing the already-measured
segment widths and echoing `prep.metrics` — no re-measurement. Motivates #E's
word-boundary fracture (re-pack halves of a measured paragraph).
"""
subprep(prep::Prepared, r::AbstractUnitRange) = Prepared(prep.segments[r], prep.metrics)
```

Then in `src/TextMeasure.jl`, extend the line-5 export:

```julia
export prepare, layout, line_top, measure_bounds, subprep
```

- [ ] **Step 4: Run test to verify it passes**

Run: `julia --project=test -e 'using TextMeasure, Test; include("test/test_prepare.jl")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/prepare.jl src/TextMeasure.jl test/test_prepare.jl
git commit -m "feat(#A): subprep segment-slice helper + export"
```

### Task A3: CHANGELOG entry for #A

**Files:**
- Modify: `CHANGELOG.md` (under `## [Unreleased]` → `### Added`)

- [ ] **Step 1: Add entry**

Add to the top of the `### Added` list in `CHANGELOG.md`:

```markdown
- `subprep(prep, r)` + `Prepared(; segments, metrics)` kwargs constructor: slice a
  `Prepared` over a segment sub-range, reusing measured widths (no re-measurement).
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(#A): CHANGELOG entry for subprep"
```

---

## Part B — #B `FigletBackend` weakdep extension on `FIGlet.jl`

### Task B1: `FigletBackend{F}` container struct + container test

**Files:**
- Modify: `src/backend_containers.jl` (append after `MakieBackend`, currently ends L26)
- Test: `test/test_containers.jl`

- [ ] **Step 1: Write the failing test**

Append inside the `@testset "backend container structs"` block in `test/test_containers.jl` (before its closing `end`):

```julia
    # FigletBackend: opaque font, Int letter_gap (deliberate departure — cell counts, not px)
    fig = FigletBackend("FONT", 2)
    @test fig isa AbstractMeasurementBackend
    @test fig.font == "FONT" && fig.letter_gap === 2
    # keyword constructor requires the FIGlet extension; absent it, it errors.
    @test_throws MethodError FigletBackend(; letter_gap=0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `julia --project=test -e 'using TextMeasure, Test; include("test/test_containers.jl")' 2>&1 | grep -i "FigletBackend\|UndefVar\|not defined"`
Expected: FAIL — `FigletBackend` not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `src/backend_containers.jl`:

```julia

"""
    FigletBackend(font, letter_gap)

Container holding an opaque FIGlet font (`font::F`; `FIGlet.FIGletFont` once the ext
loads). The keyword constructor `FigletBackend(; font, letter_gap)` and the
`measure`/`font_metrics` methods are provided by the FIGlet extension —
`using FIGlet` to enable.

Two deliberate departures from `FreeTypeBackend`/`MakieBackend`: there is **no
`fontsize` field** (FIGlet glyphs live on a fixed integer cell grid — `measure`
returns cell counts, not pixels), and `letter_gap` is an **`Int`** (a count of cells
between glyphs), not a `Float64`.
"""
struct FigletBackend{F} <: AbstractMeasurementBackend
    font       :: F
    letter_gap :: Int
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `julia --project=test -e 'using TextMeasure, Test; include("test/test_containers.jl")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/backend_containers.jl test/test_containers.jl
git commit -m "feat(#B): FigletBackend container struct"
```

### Task B2: Export `FigletBackend` + `AbstractMeasurementBackend` docstring cross-ref

**Files:**
- Modify: `src/TextMeasure.jl:7` (export list)
- Modify: `src/backend.jl` (`AbstractMeasurementBackend` docstring, L1-14)

- [ ] **Step 1: Extend the backend export line**

In `src/TextMeasure.jl`, line 7:

```julia
export AbstractMeasurementBackend, MonospaceBackend, FreeTypeBackend, MakieBackend, FigletBackend
```

- [ ] **Step 2: Cross-reference all three exts in the supertype docstring**

In `src/backend.jl`, append a paragraph to the `AbstractMeasurementBackend` docstring (before the closing `"""` on L13):

```julia
The three shipped extension backends are the canonical examples of this pattern:
`FreeTypeBackend` (`ext/TextMeasureFreeTypeExt.jl`), `MakieBackend`
(`ext/TextMeasureMakieExt.jl`), and `FigletBackend` (`ext/TextMeasureFigletExt.jl`).
```

- [ ] **Step 3: Verify it still loads**

Run: `julia --project=test -e 'using TextMeasure; @assert isdefined(TextMeasure, :FigletBackend)'`
Expected: no error.

- [ ] **Step 4: Commit**

```bash
git add src/TextMeasure.jl src/backend.jl
git commit -m "feat(#B): export FigletBackend; cross-ref three exts in supertype docstring"
```

### Task B3: `Project.toml` weakdep + extension + compat

**Files:**
- Modify: `Project.toml` (`[weakdeps]` L9-11, `[extensions]` L13-15, `[compat]` L17-21)

- [ ] **Step 1: Add FIGlet to all three blocks**

`[weakdeps]` — add:
```toml
FIGlet = "3064a664-84fe-4d92-92c7-ed492f3d8fae"
```
`[extensions]` — add:
```toml
TextMeasureFigletExt = "FIGlet"
```
`[compat]` — add (lower bound, current published is 0.2.2):
```toml
FIGlet = "0.2"
```

- [ ] **Step 2: Verify Project.toml parses + package still loads**

Run: `julia --project -e 'using Pkg; Pkg.instantiate(); using TextMeasure'`
Expected: no error (the ext stays inert — FIGlet is not loaded here).

- [ ] **Step 3: Commit**

```bash
git add Project.toml
git commit -m "feat(#B): declare FIGlet weakdep + TextMeasureFigletExt"
```

### Task B4: `ext/TextMeasureFigletExt.jl`

**Files:**
- Create: `ext/TextMeasureFigletExt.jl`

API surface used (verified from the issue body / FIGlet.jl `src/FIGlet.jl`):
`FIGlet.DEFAULTFONT = "Standard"`; `FIGlet.readfont(s::AbstractString)::FIGletFont`;
`FIGletFont` has `header::FIGletHeader` + `font_characters::Dict{Char,FIGletChar}`;
`FIGletHeader` has `height::Int` + `baseline::Int`; `FIGletChar.thechar::Matrix{Char}` is
`Matrix{Char}(undef, height, width)` so **`size(thechar, 2)` is the width in cells**.

- [ ] **Step 1: Create the ext file**

```julia
module TextMeasureFigletExt

# === The THIRD example of the canonical weakdep-extension backend pattern. ===
# Mirrors ext/TextMeasureFreeTypeExt.jl and ext/TextMeasureMakieExt.jl: a container
# struct lives in src/ (src/backend_containers.jl), and this gated extension supplies
# the keyword constructor + TextMeasure.measure + TextMeasure.font_metrics, activating
# only when the user runs `using FIGlet`.
#
# TWO DELIBERATE DEPARTURES from the FreeType/Makie backends — NOT bugs:
#   1. NO `fontsize`. FreeType/Makie scale widths by fontsize in pixels. FIGlet glyphs
#      live on a fixed integer cell grid — width/height are intrinsic cell counts, not
#      scalable. `measure` therefore returns widths in CHARACTER CELLS, NOT PIXELS.
#      Downstream consumers (#E asteroid TUI, #C shape_pack with a raster chord fn) work
#      in cell coordinates and treat FontMetrics values as cell counts.
#   2. `letter_gap :: Int` (not Float64): an integer count of cells between glyphs.
#
# Also: NO `measure_bounds` method — Figlet is plain monospace-cell text with no
# styled-text analog (unlike Makie's RichText), so the 2-D bounded primitive doesn't apply.

using TextMeasure
using FIGlet

# String → readfont(name); FIGletFont → use directly. FIGlet.readfont(io) already handles
# user-supplied streams, so no separate `font_data` escape hatch is needed.
function TextMeasure.FigletBackend(; font::Union{AbstractString,FIGlet.FIGletFont}=FIGlet.DEFAULTFONT,
                                   letter_gap::Int=0)
    f = font isa FIGlet.FIGletFont ? font : FIGlet.readfont(String(font))
    return TextMeasure.FigletBackend(f, letter_gap)
end

# Sum per-character cell widths. Missing glyph → fall back to the space cell's width
# (the bundled Standard font's own behavior). NEVER bare-index font_characters[c] — a
# missing key would throw KeyError mid-render. Integer-valued cell count returned as
# Float64 to honor the `measure` return-type contract.
function TextMeasure.measure(b::TextMeasure.FigletBackend, text::AbstractString)
    isempty(text) && return 0.0
    chars = b.font.font_characters
    fallback = get(chars, ' ', nothing)
    w = 0
    for c in text
        glyph = get(chars, c, fallback)
        glyph === nothing && continue          # no glyph and no space fallback → 0-width
        w += size(glyph.thechar, 2)            # dim-2 is width in cells
    end
    w += b.letter_gap * (length(text) - 1)
    return Float64(w)
end

# Cell-grid metrics: header.height is the line advance; header.baseline is the ascent;
# descent = height − baseline. All in cell counts, returned as Float64.
function TextMeasure.font_metrics(b::TextMeasure.FigletBackend)
    h  = b.font.header.height
    bl = b.font.header.baseline
    return TextMeasure.FontMetrics(Float64(bl), Float64(h - bl), Float64(h))
end

end # module
```

- [ ] **Step 2: Smoke-load the ext in an isolated env**

Run (uses the test/figlet env created in B5 — defer this verification to B5's run; for now just confirm the file parses):
`julia --project -e 'include("ext/TextMeasureFigletExt.jl")' 2>&1 | grep -i "error\|FIGlet" || echo "parse-only OK (FIGlet not in this env)"`
Expected: parse error only if syntax is wrong (a missing-FIGlet `ArgumentError`/`LoadError` at `using FIGlet` is acceptable here — real load happens in B5).

- [ ] **Step 3: Commit**

```bash
git add ext/TextMeasureFigletExt.jl
git commit -m "feat(#B): TextMeasureFigletExt — third weakdep-ext backend example"
```

### Task B5: Isolated FIGlet integration test (separate env, NOT in main suite)

**Files:**
- Create: `test/figlet/Project.toml`
- Create: `test/figlet/runtests.jl`

Rationale: issue #B requires the live-FIGlet integration test to live in a **separate CI
job, NOT in the main `Pkg.test()` suite** (keeps the main suite fast). So FIGlet is *not*
added to `test/Project.toml`; this isolated env carries it. Pinned widths are computed
empirically here (run `measure` once, read the value, hard-pin it — FIGlet fonts are
deterministic). Conformance uses bounds where exact values aren't load-bearing.

- [ ] **Step 1: Create `test/figlet/Project.toml`**

```toml
[deps]
FIGlet = "3064a664-84fe-4d92-92c7-ed492f3d8fae"
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
TextMeasure = "06791c1d-2336-41e1-bd6f-a74c63395da6"

[compat]
FIGlet = "0.2"
Test = "<0.0.1, 1"
julia = "1.11"
```

- [ ] **Step 2: Dev-install TextMeasure into the isolated env + instantiate**

Run:
```bash
julia --project=test/figlet -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'
```
Expected: resolves FIGlet 0.2.x + the local TextMeasure.

- [ ] **Step 3: Discover the pinned widths empirically**

Run:
```bash
julia --project=test/figlet -e 'using TextMeasure, FIGlet;
  for fn in ("Standard","Small");
    b = FigletBackend(; font=fn);
    println(fn, " hello=", TextMeasure.measure(b,"hello"), " A=", TextMeasure.measure(b,"A"));
    m = TextMeasure.font_metrics(b);
    println("   metrics asc=",m.ascent," desc=",m.descent," la=",m.line_advance);
  end'
```
Record the printed `hello`/`A` widths and metrics; substitute them into the test below in Step 4 (replace each `<PIN_*>`).

- [ ] **Step 4: Write the integration test `test/figlet/runtests.jl`**

```julia
using Test, TextMeasure, FIGlet

@testset "FigletBackend (live FIGlet.jl)" begin
    # extension registration: importing FIGlet after TextMeasure activated the ext
    @test Base.get_extension(TextMeasure, :TextMeasureFigletExt) !== nothing

    b = FigletBackend()                              # defaults: Standard font, gap 0
    @test b isa AbstractMeasurementBackend

    # determinism + pinned cell widths (Standard). Values from Step 3.
    @test TextMeasure.measure(b, "hello") == <PIN_STD_HELLO>
    @test TextMeasure.measure(b, "hello") == TextMeasure.measure(b, "hello")  # stable
    @test TextMeasure.measure(b, "") == 0.0

    # integer-valued cell counts returned as Float64
    w = TextMeasure.measure(b, "hello")
    @test w isa Float64 && w == round(w)

    # additive across runs with gap 0 (no kerning); cell counts sum
    @test TextMeasure.measure(b, "ab") == TextMeasure.measure(b, "a") + TextMeasure.measure(b, "b")

    # letter_gap adds (length-1) cells per gap
    bg = FigletBackend(; letter_gap=1)
    @test TextMeasure.measure(bg, "hello") == TextMeasure.measure(b, "hello") + 4

    # second bundled font (Small) — also deterministic
    bs = FigletBackend(; font="Small")
    @test TextMeasure.measure(bs, "hello") == <PIN_SMALL_HELLO>

    # missing-glyph fallback: a char absent from the font does not throw
    @test TextMeasure.measure(b, "☃") ≥ 0.0     # snowman, likely absent → fallback/0

    # ascent/descent/line_advance match FIGletHeader fields (cell counts)
    m = TextMeasure.font_metrics(b)
    @test m.ascent == Float64(b.font.header.baseline)
    @test m.line_advance == Float64(b.font.header.height)
    @test m.descent == Float64(b.font.header.height - b.font.header.baseline)

    # accept a FIGletFont object directly (not just a name)
    bf = FigletBackend(; font=FIGlet.readfont("Standard"))
    @test TextMeasure.measure(bf, "hello") == <PIN_STD_HELLO>
end
```

- [ ] **Step 5: Run the integration test**

Run: `julia --project=test/figlet test/figlet/runtests.jl`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add test/figlet/Project.toml test/figlet/runtests.jl
git commit -m "test(#B): isolated live-FIGlet integration test (separate env)"
```

### Task B6: Separate CI job `ext_tests.yml`

**Files:**
- Create: `.github/workflows/ext_tests.yml`

- [ ] **Step 1: Create the workflow**

```yaml
name: ext-tests
on:
  push:
    branches: [main]
    paths: ['ext/**', 'test/figlet/**', '.github/workflows/ext_tests.yml']
  pull_request:
    paths: ['ext/**', 'test/figlet/**', '.github/workflows/ext_tests.yml']
permissions:
  contents: read
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  figlet-ext:
    name: FIGlet ext - Julia ${{ matrix.version }}
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        version: ['1.11', '1']
    steps:
      - uses: actions/checkout@v6
      - uses: julia-actions/setup-julia@v3
        with:
          version: ${{ matrix.version }}
      - uses: julia-actions/cache@v3
      - name: Run isolated FIGlet integration test
        run: |
          julia --project=test/figlet -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'
          julia --project=test/figlet test/figlet/runtests.jl
```

- [ ] **Step 2: Validate YAML parses**

Run: `julia --project -e 'import Pkg; Pkg.add("YAML")' 2>/dev/null; julia -e 'using YAML; YAML.load_file(".github/workflows/ext_tests.yml"); println("yaml ok")'`
(If installing YAML is undesirable in the shared env, skip — a human/CI lint will catch malformed YAML.)
Expected: `yaml ok` or skipped.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ext_tests.yml
git commit -m "ci(#B): separate ext-tests job for live FIGlet integration"
```

### Task B7: CHANGELOG entry for #B

**Files:**
- Modify: `CHANGELOG.md` (under `## [Unreleased]` → `### Added`)

- [ ] **Step 1: Add entry**

Add to the `### Added` list in `CHANGELOG.md`:

```markdown
- `FigletBackend`: measurement backend for FIGlet ASCII-art fonts, shipped as a weakdep
  extension on `FIGlet.jl` (loaded on `using FIGlet`). Measures in **character cells**
  (not pixels); `letter_gap::Int`. The third example of the canonical weakdep-ext pattern.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(#B): CHANGELOG entry for FigletBackend"
```

---

## Verification (after all tasks)

Per CLAUDE.md + orchestration spec: run the **main** suite ONCE, capture to log, grep — never re-run per grep.

- [ ] Main suite (FIGlet-free; verifies #A + the FigletBackend container test):

```bash
mkdir -p test-logs
julia --project -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"
```
Expected: all testsets pass; `test_types`, `test_prepare`, `test_containers` include the new assertions.

- [ ] Isolated FIGlet integration suite (the #B live half — separate, as it will run in CI):

```bash
julia --project=test/figlet test/figlet/runtests.jl
```
Expected: PASS.

- [ ] Grep the captured log for the new testsets rather than re-running:

```bash
grep -iE "subprep|core types|backend container|Test Summary|Fail|Error" "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"
```

## Self-Review notes

- **Spec coverage #A:** kwargs ctor (A1) ✓; subprep full-range field-equiv (A2) ✓; word-boundary width-sum (A2) ✓; cross-newline/space integrity (A2) ✓; no `Base.getindex` (none added) ✓; outer ctor (A1) ✓; export (A2) ✓; CHANGELOG (A3) ✓.
- **Spec coverage #B:** struct w/ `{F}`, no fontsize, `letter_gap::Int` (B1) ✓; weakdep+ext+compat (B3) ✓; keyword ctor String|FIGletFont (B4) ✓; `measure` cell-width sum + `letter_gap*(n-1)` + missing-glyph fallback (B4) ✓; `font_metrics` from header (B4) ✓; no `measure_bounds` (omitted) ✓; heavy preamble (B4) ✓; supertype docstring cross-ref (B2) ✓; pinned widths Standard+Small (B5) ✓; `Base.get_extension` registration (B5) ✓; conformance int-as-Float64/asc-desc (B5) ✓; compat lower bound (B3) ✓; **separate CI job** (B6) ✓; CHANGELOG (B7) ✓.
- **Type consistency:** `FigletBackend(font, letter_gap)` positional order matches struct field order in B1; keyword ctor forwards in that order (B4); export name `FigletBackend` consistent (B1/B2).
- **Overlap handling:** `src/TextMeasure.jl` export list edited twice (A2 line 5, B2 line 7) and `CHANGELOG.md` twice (A3, B7) — same branch, sequential commits, no conflict.
