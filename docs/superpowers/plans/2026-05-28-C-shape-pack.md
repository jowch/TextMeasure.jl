# `shape_pack` (#C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `shape_pack`, a reusable shape-conforming text-layout consumer that packs a measured `Prepared` into arbitrary 2-D regions described by a `chord_fn`, plus two `chord_fn` constructors (`polygon_chord_fn`, `raster_chord_fn`), shipped in the new `examples/layouts/` package (`TextMeasureLayouts`).

**Architecture:** Per-band scanline (inspired by pretext.js `wrap-geometry.ts`, but with **inverted semantics** — our `chord_fn` returns *available* intervals, not obstacle envelopes). `shape_pack` walks horizontal bands of height `line_advance` top-to-bottom, asks `chord_fn` for the available `(left,right)` intervals in each band, packs `:word` segments greedily into the **widest** interval using the *exact same greedy rule as `src/layout.jl`*, and emits a typed `PackedLayout` of word `Placement`s. The rectangle case (`chord_fn` returns `[(0,w)]` for every band) is provably equivalent to `layout(prep; max_width=w)`. Pure arithmetic over cached widths — no font-engine access (that already happened in `prepare`).

**Tech Stack:** Julia 1.11+; `TextMeasure` (dev-pathed); `GeometryBasics` (`Point2{Float64}`); `Test` (stdlib). New package `TextMeasureLayouts` lives at `examples/layouts/`, consumed downstream via `Pkg.develop(path="../layouts")`. Long-term migration target: a registered `TextMeasureLayouts.jl`.

---

## Decisions & deviations (flagged for the plan gate)

1. **File path.** The issue body names the file `examples/layouts/shape_pack.jl`. For the package to be `Pkg.develop`-loadable by downstream demos (#E/#F2/#G/#H), `examples/layouts/` is a real Julia package; the implementation lives at **`examples/layouts/src/shape_pack.jl`** with `examples/layouts/src/TextMeasureLayouts.jl` as the module entry. This is the only path deviation from the issue body's logical name.
2. **`chord_fn` accepts both a plain closure and a typed `AbstractChordFn`.** `AbstractChordFn` is made callable (`(f)(y_top,y_bottom) = chord_intervals(f, …)`), so `shape_pack` just calls `chord_fn(y_top, y_bottom)` uniformly. The helper constructors return typed wrappers (`PolygonChordFn`, `RasterChordFn`) per the issue's "ease the future migration" note; bare closures remain acceptable for milestone-1.
3. **Scanline sampling.** `polygon_chord_fn` / `raster_chord_fn` sample at the **vertical center** of each band (`yc = (y_top+y_bottom)/2`) — the issue says "scanline intersection," i.e. a single scanline per band. Documented in the constructors.
4. **`y`-frame.** Band `b` (1-based) spans `[(b-1)·line_advance, b·line_advance]`; its baseline is `(b-1)·line_advance + ascent`. With `line_advance = prep.metrics.line_advance` this equals `layout`'s line-`b` baseline `ascent + (b-1)·la` (default `lineheight=1.0`), giving exact coord-frame consistency.
5. **`overflowed` semantics.** Realized operationally as: a `:word` is overflowed when, at the band greedy flow reaches it as the first word of a line, its width exceeds that band's widest usable interval `W`. For a constant-width rectangle, "wider than this band" == "wider than any chord at any row," so the issue's global phrasing holds exactly for the rectangle/convex cases. Top-to-bottom flow does not backtrack to hunt a wider band. Documented in the docstring.
6. **`:reject` strategy.** Interpreted literally as "the text does not fit this shape — fail." On the first un-fittable word, `shape_pack` returns a `PackedLayout` with **empty `placements`** and `overflowed` = the offending `:word` index plus every later `:word` index. (Flagged: the issue text "return empty PackedLayout with all subsequent segments in overflowed" is read as empty-placements; the gate should confirm this reading.)
7. **Vertical termination.** `shape_pack` has no explicit y-bound (the shape is only known through the closure). Termination: (a) words exhausted; (b) after **entering** the shape (first usable band), `max_empty_bands` consecutive skipped bands ⇒ shape ended, stop; (c) hard safety cap `max_bands` ⇒ stop (guards a closure that never yields a usable band). Words still unplaced when scanning stops are simply absent from `placements` (detectable via count); they are *not* forced into `overflowed` (which means horizontal over-width only).
8. **Perf baseline polygon.** The real Vermont shapefile belongs to #G and is absent here, so the perf test synthesizes a ~30-vertex blob polygon scaled to span ~600 bands — same `~600 scanlines × ~30 edges` code path. #G can later swap in the real polygon. Baseline committed to `examples/layouts/test/perf_baseline.txt`; test asserts `elapsed < 2 × baseline` (cross-machine caveat noted; #J owns the authoritative CI gate).
9. **License headers.** Every new `.jl` carries `# SPDX-License-Identifier: MIT` (parent license) to satisfy #J's license gate from the start.

## File structure

- **Create** `examples/layouts/src/shape_pack.jl` — types (`Placement`, `PackedLayout`), `AbstractChordFn` + `chord_intervals`, `shape_pack`, `polygon_chord_fn`/`PolygonChordFn`, `raster_chord_fn`/`RasterChordFn`.
- **Modify** `examples/layouts/src/TextMeasureLayouts.jl` — `using`/`include`/`export` wiring (skeleton already created at workspace setup).
- **Create** `examples/layouts/test/runtests.jl` — aggregator.
- **Create** `examples/layouts/test/test_shape_pack.jl` — core (rectangle equivalence, coord-frame, invariants, overflow strategies).
- **Create** `examples/layouts/test/test_chord_fns.jl` — `polygon_chord_fn` (circle, U-shape) + `raster_chord_fn`.
- **Create** `examples/layouts/test/test_perf.jl` — perf baseline.
- **Create** `examples/layouts/test/perf_baseline.txt` — committed baseline seconds (written on first run).
- **Create** `examples/layouts/README.md` — what the package is, run command, migration note.
- Already present (workspace setup): `examples/layouts/Project.toml`, `examples/layouts/Manifest.toml`.

**Test run command** (the project env already has `TextMeasure`, `GeometryBasics`, `TextMeasureLayouts`; `Test` is stdlib):
```bash
julia --project=examples/layouts examples/layouts/test/runtests.jl 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"
```

---

## Task 1: Package types + module wiring

**Files:**
- Create: `examples/layouts/src/shape_pack.jl`
- Modify: `examples/layouts/src/TextMeasureLayouts.jl`
- Create: `examples/layouts/test/runtests.jl`
- Test: `examples/layouts/test/test_shape_pack.jl`

- [ ] **Step 1: Write the failing test** — `examples/layouts/test/test_shape_pack.jl`:

```julia
# SPDX-License-Identifier: MIT
using Test, TextMeasure, TextMeasureLayouts

@testset "types" begin
    m = FontMetrics(8.0, 2.0, 14.0)
    p = Placement(3, 1.5, 10.0)
    @test p.segment_index == 3
    @test p.x == 1.5
    @test p.y == 10.0
    pl = PackedLayout([p], [7], m)
    @test pl.placements == [p]
    @test pl.overflowed == [7]
    @test pl.metrics === m
end
```

- [ ] **Step 2: Create the aggregator** — `examples/layouts/test/runtests.jl`:

```julia
# SPDX-License-Identifier: MIT
using Test
@testset "TextMeasureLayouts" begin
    include("test_shape_pack.jl")
    include("test_chord_fns.jl")
    include("test_perf.jl")
end
```

(`test_chord_fns.jl` / `test_perf.jl` are created in later tasks; comment out their `include`s until then, or create empty stubs. Use empty stubs: create the two files now with just the SPDX header so `runtests.jl` loads.)

- [ ] **Step 3: Run to verify it fails** —
Run: `julia --project=examples/layouts examples/layouts/test/runtests.jl`
Expected: FAIL — `UndefVarError: Placement not defined` (or `PackedLayout`).

- [ ] **Step 4: Write minimal implementation** — `examples/layouts/src/shape_pack.jl` (types + chord-fn abstraction only for now):

```julia
# SPDX-License-Identifier: MIT
#
# shape_pack — shape-conforming text layout (#C, demos milestone).
# Per-band scanline; inspired by pretext.js wrap-geometry.ts but with inverted
# semantics: chord_fn returns AVAILABLE intervals, not obstacle envelopes.

"""
    Placement(segment_index, x, y)

One placed `:word` segment. `segment_index` is the **absolute** index into the source
`Prepared.segments` (counts across `:word`/`:space`/`:newline`). `x` is the segment's
left edge; `y` is its baseline in the block-top frame (block top = 0, increasing down) —
equal to `line_top(lay, ln) + ascent` for the equivalent `layout` line.
"""
struct Placement
    segment_index :: Int
    x             :: Float64
    y             :: Float64
end

"""
    PackedLayout(placements, overflowed, metrics)

Result of `shape_pack`. `placements` are word segments in left-to-right, top-to-bottom
order. `overflowed` holds segment indices wider than the widest chord available where
greedy flow reached them. `metrics` is echoed from the source `Prepared`. Read-only.
"""
struct PackedLayout
    placements :: Vector{Placement}
    overflowed :: Vector{Int}
    metrics    :: FontMetrics
end

"""
    AbstractChordFn

Optional typed supertype for chord functions (the preferred long-term API). Subtypes
implement `chord_intervals(f, y_top, y_bottom)` and are callable with the same signature.
A plain `Function` closure is equally acceptable as a `chord_fn`.
"""
abstract type AbstractChordFn end

"""
    chord_intervals(f, y_top, y_bottom) -> Vector{Tuple{Float64,Float64}}

Available horizontal intervals in band `[y_top, y_bottom]` (block-top frame), sorted
ascending and pairwise disjoint. Empty ⇒ no chord intersects the band.
"""
function chord_intervals end

(f::AbstractChordFn)(y_top::Real, y_bottom::Real) = chord_intervals(f, y_top, y_bottom)
```

- [ ] **Step 5: Wire the module** — replace the body of `examples/layouts/src/TextMeasureLayouts.jl`:

```julia
# SPDX-License-Identifier: MIT
module TextMeasureLayouts

# Shared layout utilities for the TextMeasure.jl demos milestone (#C, #K).
# Consumed by per-demo projects via `Pkg.develop(path="../layouts")`.
# Long-term migration target: a registered `TextMeasureLayouts.jl` sibling package.

using TextMeasure: FontMetrics, Prepared, Segment
using GeometryBasics: Point2

export Placement, PackedLayout
export AbstractChordFn, chord_intervals
export shape_pack
export polygon_chord_fn, PolygonChordFn, raster_chord_fn, RasterChordFn

include("shape_pack.jl")

end # module
```

(`FontMetrics`/`Prepared`/`Segment` are exported by `TextMeasure`; the explicit `using … :` import makes the dependency legible and lets `shape_pack.jl` reference them unqualified.)

- [ ] **Step 6: Run to verify it passes** —
Run: `julia --project=examples/layouts examples/layouts/test/runtests.jl`
Expected: PASS for the `types` testset (other includes are empty stubs).

- [ ] **Step 7: Commit**

```bash
git add examples/layouts/ docs/superpowers/plans/2026-05-28-C-shape-pack.md
git commit -m "feat(layouts): TextMeasureLayouts package skeleton + shape_pack types (#C)"
```

---

## Task 2: `shape_pack` core — rectangle equivalence + coord-frame + invariants

**Files:**
- Modify: `examples/layouts/src/shape_pack.jl` (append `shape_pack`)
- Test: `examples/layouts/test/test_shape_pack.jl`

**Background — the greedy rule to match (`src/layout.jl:34-56`).** Words atomic; break at whitespace/`\n`; a line fills while `committed_w + (pending_space_width + next_word_width) ≤ max_width`; leading/trailing whitespace per line is trimmed (leading space dropped when a line's first word lands; a trailing space is held in `pending` and never committed across a break). `shape_pack` reproduces this per band with `W = right - left` of the band's widest interval.

- [ ] **Step 1: Write the failing tests** — append to `examples/layouts/test/test_shape_pack.jl`:

```julia
# A rectangle of width w: every band offers the single interval (0, w).
rect_chord_fn(w) = (yt, yb) -> [(0.0, Float64(w))]

# Group placements into lines by their baseline y; return (baseline, [words]) sorted.
function _lines_by_baseline(prep, pk)
    byline = Dict{Float64,Vector{Tuple{Float64,String}}}()
    for p in pk.placements
        push!(get!(byline, p.y, Tuple{Float64,String}[]), (p.x, prep.segments[p.segment_index].str))
    end
    [(y, [s for (_, s) in sort(v)]) for (y, v) in sort(collect(byline); by=first)]
end

@testset "rectangle == layout" begin
    b = MonospaceBackend()
    text = "the quick brown fox jumps over the lazy dog and then some more words here"
    prep = prepare(b, text)
    for w in (60.0, 100.0, 180.0, 400.0)
        lay = layout(prep; max_width=w)               # default lineheight=1.0, align=:left
        pk  = shape_pack(prep, rect_chord_fn(w);
                         line_advance=prep.metrics.line_advance, min_chord_width=0.0)
        # Expected: words-per-line and per-line baselines match layout's non-empty lines.
        laywords = [split(ln.str) for ln in lay.lines if !isempty(strip(ln.str))]
        pklines  = _lines_by_baseline(prep, pk)
        @test length(pklines) == length(laywords)
        for (i, (y, words)) in enumerate(pklines)
            @test words == laywords[i]                # same line breaks
            @test isapprox(y, lay.lines[i].baseline; atol=1e-9)   # coord-frame consistency
        end
        # invariants
        @test all(1 .<= getfield.(pk.placements, :segment_index) .<= length(prep.segments))
        @test all(p -> prep.segments[p.segment_index].kind === :word, pk.placements)
        @test isempty(pk.overflowed)                  # nothing over-wide at these widths
    end
end

@testset "placements lie within band chords" begin
    b = MonospaceBackend()
    prep = prepare(b, "alpha beta gamma delta epsilon zeta eta theta iota kappa")
    w = 120.0
    pk = shape_pack(prep, rect_chord_fn(w); line_advance=prep.metrics.line_advance, min_chord_width=0.0)
    for p in pk.placements
        seg = prep.segments[p.segment_index]
        @test p.x >= -1e-9
        @test p.x + seg.width <= w + 1e-9             # word stays inside (0, w)
    end
end

@testset "argument validation" begin
    b = MonospaceBackend(); prep = prepare(b, "hi there")
    @test_throws ArgumentError shape_pack(prep, rect_chord_fn(50); line_advance=0.0)
    @test_throws ArgumentError shape_pack(prep, rect_chord_fn(50);
                                          line_advance=14.0, overflow_strategy=:nope)
end

@testset "empty prepared" begin
    b = MonospaceBackend(); prep = prepare(b, "")
    pk = shape_pack(prep, rect_chord_fn(50); line_advance=prep.metrics.line_advance)
    @test isempty(pk.placements) && isempty(pk.overflowed)
end
```

- [ ] **Step 2: Run to verify it fails** —
Run: `julia --project=examples/layouts examples/layouts/test/runtests.jl`
Expected: FAIL — `UndefVarError: shape_pack not defined`.

- [ ] **Step 3: Write minimal implementation** — append to `examples/layouts/src/shape_pack.jl`:

```julia
# Pick the widest interval in a band; return (left, right) or nothing if none.
function _widest(intervals)
    isempty(intervals) && return nothing
    best = intervals[1]
    bestw = best[2] - best[1]
    for iv in intervals
        w = iv[2] - iv[1]
        if w > bestw
            best, bestw = iv, w
        end
    end
    return best
end

"""
    shape_pack(prep, chord_fn; line_advance, min_chord_width=24,
               overflow_strategy=:widest_row, max_empty_bands=1024,
               max_bands=100_000) -> PackedLayout

Pack the `:word` segments of `prep` into the region described by `chord_fn`, walking
horizontal bands of height `line_advance` from the top (y=0) down. In each band the
**widest** available interval is used; bands whose widest interval is `< min_chord_width`
(or empty) are skipped. `:space`/`:newline` segments steer breaks (exactly as `layout`)
but are never emitted as `Placement`s. Returns word placements in reading order.

`overflow_strategy` controls a word wider than its band's widest interval:
`:widest_row` (place at the interval's left edge, record in `overflowed`),
`:skip` (drop it, record in `overflowed`), `:reject` (abort — empty `placements`,
offending + all later `:word` indices in `overflowed`).

Coordinates share `chord_fn`'s frame and `prep.metrics` units. With
`line_advance = prep.metrics.line_advance` and a full-width rectangle chord_fn, the
output is equivalent to `layout(prep; max_width=w)`.
"""
function shape_pack(prep::Prepared, chord_fn;
                    line_advance::Real,
                    min_chord_width::Real=24,
                    overflow_strategy::Symbol=:widest_row,
                    max_empty_bands::Int=1024,
                    max_bands::Int=100_000)::PackedLayout
    line_advance > 0 || throw(ArgumentError("line_advance must be > 0; got $line_advance"))
    overflow_strategy in (:widest_row, :skip, :reject) ||
        throw(ArgumentError("overflow_strategy must be :widest_row, :skip or :reject; got $(repr(overflow_strategy))"))
    la  = Float64(line_advance)
    mcw = Float64(min_chord_width)
    m   = prep.metrics
    segs = prep.segments
    n = length(segs)

    placements = Placement[]
    overflowed = Int[]

    si = 1                       # next segment to consider
    band = 1                     # 1-based band index (vertical line slot)
    entered = false
    empty_run = 0

    while si <= n
        # ---- find next usable band ----
        L = R = 0.0
        usable = false
        while band <= max_bands
            iv = _widest(chord_fn((band - 1) * la, band * la))
            if iv !== nothing && (iv[2] - iv[1]) >= mcw
                L, R = Float64(iv[1]), Float64(iv[2])
                usable = true
                entered = true
                empty_run = 0
                break
            end
            if entered
                empty_run += 1
                empty_run >= max_empty_bands && break
            end
            band += 1
        end
        usable || break          # shape vertically exhausted (or never entered)

        baseline = (band - 1) * la + m.ascent
        W = R - L
        cursor = 0.0             # advance from L of words+spaces committed on this line
        committed = 0            # words placed on this line
        pending::Union{Nothing,Segment} = nothing

        # ---- pack one line, mirroring src/layout.jl's greedy inner loop ----
        while si <= n
            seg = segs[si]
            if seg.kind === :newline
                si += 1; break                       # newline ends the line
            elseif seg.kind === :space
                pending = seg; si += 1
            else  # :word
                if committed == 0
                    # first word on the line; leading space already trimmed (pending dropped)
                    if seg.width > W                  # over-wide for this band
                        if overflow_strategy === :reject
                            empty!(placements)
                            for j in si:n
                                segs[j].kind === :word && push!(overflowed, j)
                            end
                            return PackedLayout(placements, overflowed, m)
                        elseif overflow_strategy === :skip
                            push!(overflowed, si); si += 1; pending = nothing
                            continue                  # try next word in this same band
                        else  # :widest_row — place at L anyway, accept overflow
                            push!(placements, Placement(si, L, baseline))
                            push!(overflowed, si)
                            cursor = seg.width; committed = 1; pending = nothing; si += 1
                            break                     # over-wide word occupies its own line
                        end
                    else
                        push!(placements, Placement(si, L, baseline))
                        cursor = seg.width; committed = 1; pending = nothing; si += 1
                    end
                else
                    extra = (pending === nothing ? 0.0 : pending.width) + seg.width
                    if cursor + extra > W
                        break                         # word starts next line; trailing space trimmed
                    else
                        if pending !== nothing
                            cursor += pending.width; pending = nothing
                        end
                        push!(placements, Placement(si, L + cursor, baseline))
                        cursor += seg.width; committed += 1; si += 1
                    end
                end
            end
        end
        band += 1                # next line uses the next band
    end

    return PackedLayout(placements, overflowed, m)
end
```

- [ ] **Step 4: Run to verify it passes** —
Run: `julia --project=examples/layouts examples/layouts/test/runtests.jl`
Expected: PASS — rectangle equivalence, coord-frame, within-chord, validation, empty.

- [ ] **Step 5: Commit**

```bash
git add examples/layouts/src/shape_pack.jl examples/layouts/test/test_shape_pack.jl
git commit -m "feat(layouts): shape_pack core + rectangle/layout equivalence (#C)"
```

---

## Task 3: overflow strategies (`:widest_row`, `:skip`, `:reject`) + `min_chord_width` skip

**Files:**
- Test: `examples/layouts/test/test_shape_pack.jl` (append)
- (No implementation change — Task 2's `shape_pack` already branches on `overflow_strategy` and skips narrow bands. These are characterization tests for those branches.)

- [ ] **Step 1: Write the failing tests** — append:

```julia
@testset "overflow: widest_row places + records" begin
    b = MonospaceBackend()                            # advance_ratio*fontsize = 0.6*12 = 7.2 px/char
    prep = prepare(b, "tiny enormousindivisibletoken end")
    big = findfirst(s -> s.str == "enormousindivisibletoken", prep.segments)
    bigw = prep.segments[big].width
    w = bigw - 10.0                                   # narrower than the big token
    pk = shape_pack(prep, rect_chord_fn(w); line_advance=prep.metrics.line_advance, min_chord_width=0.0)
    @test big in pk.overflowed
    @test any(p -> p.segment_index == big && p.x == 0.0, pk.placements)   # still placed at L
    # the non-overflowing words are still placed:
    @test any(p -> prep.segments[p.segment_index].str == "tiny", pk.placements)
    @test any(p -> prep.segments[p.segment_index].str == "end", pk.placements)
end

@testset "overflow: skip drops + records, no placement" begin
    b = MonospaceBackend()
    prep = prepare(b, "tiny enormousindivisibletoken end")
    big = findfirst(s -> s.str == "enormousindivisibletoken", prep.segments)
    w = prep.segments[big].width - 10.0
    pk = shape_pack(prep, rect_chord_fn(w); line_advance=prep.metrics.line_advance,
                    min_chord_width=0.0, overflow_strategy=:skip)
    @test big in pk.overflowed
    @test all(p -> p.segment_index != big, pk.placements)                # never placed
    @test any(p -> prep.segments[p.segment_index].str == "end", pk.placements)
end

@testset "overflow: reject aborts" begin
    b = MonospaceBackend()
    prep = prepare(b, "tiny enormousindivisibletoken end")
    big = findfirst(s -> s.str == "enormousindivisibletoken", prep.segments)
    w = prep.segments[big].width - 10.0
    pk = shape_pack(prep, rect_chord_fn(w); line_advance=prep.metrics.line_advance,
                    min_chord_width=0.0, overflow_strategy=:reject)
    @test isempty(pk.placements)
    @test big in pk.overflowed
    # all later :word indices are in overflowed too
    endidx = findfirst(s -> s.str == "end", prep.segments)
    @test endidx in pk.overflowed
end

@testset "min_chord_width skips narrow bands" begin
    b = MonospaceBackend()
    prep = prepare(b, "aaa bbb ccc ddd eee")
    # chord_fn: even bands wide (100), odd bands a 5px sliver. min_chord_width=24 ⇒ slivers skipped.
    cf = (yt, yb) -> begin
        band = round(Int, yt / prep.metrics.line_advance) + 1
        iseven(band) ? [(0.0, 100.0)] : [(0.0, 5.0)]
    end
    pk = shape_pack(prep, cf; line_advance=prep.metrics.line_advance, min_chord_width=24.0)
    # every placement must sit on an EVEN band's baseline (odd slivers were skipped)
    for p in pk.placements
        band = round(Int, (p.y - prep.metrics.ascent) / prep.metrics.line_advance) + 1
        @test iseven(band)
    end
    @test !isempty(pk.placements)
end
```

- [ ] **Step 2: Run to verify it passes** (no impl change needed; Task 2 already implements these branches) —
Run: `julia --project=examples/layouts examples/layouts/test/runtests.jl`
Expected: PASS. If any fails, fix the corresponding branch in `shape_pack` (do not weaken the test).

- [ ] **Step 3: Commit**

```bash
git add examples/layouts/test/test_shape_pack.jl
git commit -m "test(layouts): overflow strategies + min_chord_width band-skip (#C)"
```

---

## Task 4: `polygon_chord_fn` — circle smoke + concave U-shape

**Files:**
- Modify: `examples/layouts/src/shape_pack.jl` (append `PolygonChordFn` + `polygon_chord_fn`)
- Test: `examples/layouts/test/test_chord_fns.jl` (replace the stub)

- [ ] **Step 1: Write the failing tests** — `examples/layouts/test/test_chord_fns.jl`:

```julia
# SPDX-License-Identifier: MIT
using Test, TextMeasure, TextMeasureLayouts
using GeometryBasics: Point2

# regular n-gon "circle" centered at (cx,cy), radius r, in block-top coords (y down)
function circle_poly(cx, cy, r; n=64)
    [Point2{Float64}(cx + r*cos(2π*k/n), cy + r*sin(2π*k/n)) for k in 0:n-1]
end

@testset "polygon_chord_fn: circle = single interval" begin
    cf = polygon_chord_fn(circle_poly(100.0, 100.0, 80.0))
    @test cf isa AbstractChordFn
    # band through the center: one interval roughly (20,180)
    iv = cf(99.0, 101.0)
    @test length(iv) == 1
    @test isapprox(iv[1][1], 20.0; atol=2.0)
    @test isapprox(iv[1][2], 180.0; atol=2.0)
    # band above the circle: empty
    @test isempty(cf(0.0, 2.0))
    # intervals sorted & disjoint property on a sample band
    @test issorted(iv; by=first)
end

@testset "polygon_chord_fn: concave U has two intervals" begin
    # U opening upward: two vertical prongs + a bottom bar. y increases downward.
    U = Point2{Float64}[
        (0.0, 0.0), (30.0, 0.0), (30.0, 70.0), (70.0, 70.0),
        (70.0, 0.0), (100.0, 0.0), (100.0, 100.0), (0.0, 100.0),
    ]
    cf = polygon_chord_fn(U)
    top = cf(34.0, 36.0)                  # band crossing both prongs (y=35, above the bar at y=70)
    @test length(top) == 2                # two disjoint runs (left prong, right prong)
    bottom = cf(84.0, 86.0)               # band below the bar (y=85): solid
    @test length(bottom) == 1
end

@testset "polygon U-shape: slivers below min_chord_width dropped" begin
    # thin prongs (width 10) + solid base; min_chord_width=24 ⇒ prong bands skipped.
    U = Point2{Float64}[
        (0.0, 0.0), (10.0, 0.0), (10.0, 70.0), (90.0, 70.0),
        (90.0, 0.0), (100.0, 0.0), (100.0, 100.0), (0.0, 100.0),
    ]
    cf = polygon_chord_fn(U)
    b = MonospaceBackend()
    prep = prepare(b, "one two three four five six")
    pk = shape_pack(prep, cf; line_advance=prep.metrics.line_advance, min_chord_width=24.0)
    # all placed words must be in the solid base (y baseline >= 70)
    @test !isempty(pk.placements)
    @test all(p -> p.y >= 70.0, pk.placements)
end
```

- [ ] **Step 2: Run to verify it fails** —
Run: `julia --project=examples/layouts examples/layouts/test/runtests.jl`
Expected: FAIL — `UndefVarError: polygon_chord_fn not defined`.

- [ ] **Step 3: Write minimal implementation** — append to `examples/layouts/src/shape_pack.jl`:

```julia
"""
    PolygonChordFn(polygon)

`AbstractChordFn` from a closed 2-D polygon (`Vector{Point2{Float64}}`, block-top frame).
Each band's available intervals are the inside-runs of a single scanline at the band's
vertical center.
"""
struct PolygonChordFn <: AbstractChordFn
    polygon :: Vector{Point2{Float64}}
end

"""
    polygon_chord_fn(polygon::Vector{GeometryBasics.Point2{Float64}}) -> PolygonChordFn

Scanline intersection of a 2-D polygon. Returns inside intervals where text can be placed.
"""
polygon_chord_fn(polygon::Vector{Point2{Float64}}) = PolygonChordFn(polygon)

function chord_intervals(f::PolygonChordFn, y_top::Real, y_bottom::Real)
    poly = f.polygon
    n = length(poly)
    n < 3 && return Tuple{Float64,Float64}[]
    yc = (Float64(y_top) + Float64(y_bottom)) / 2
    xs = Float64[]
    @inbounds for i in 1:n
        x1, y1 = poly[i][1], poly[i][2]
        j = i == n ? 1 : i + 1
        x2, y2 = poly[j][1], poly[j][2]
        # half-open crossing test avoids double-counting shared vertices
        if (y1 <= yc) != (y2 <= yc)
            t = (yc - y1) / (y2 - y1)
            push!(xs, x1 + t * (x2 - x1))
        end
    end
    sort!(xs)
    out = Tuple{Float64,Float64}[]
    k = 1
    while k + 1 <= length(xs)
        push!(out, (xs[k], xs[k+1]))     # inside runs are consecutive crossing pairs
        k += 2
    end
    return out
end
```

- [ ] **Step 4: Run to verify it passes** —
Run: `julia --project=examples/layouts examples/layouts/test/runtests.jl`
Expected: PASS — circle, U two-interval, U sliver-drop.

- [ ] **Step 5: Commit**

```bash
git add examples/layouts/src/shape_pack.jl examples/layouts/test/test_chord_fns.jl
git commit -m "feat(layouts): polygon_chord_fn scanline + circle/U tests (#C)"
```

---

## Task 5: `raster_chord_fn` — cell-grid silhouettes

**Files:**
- Modify: `examples/layouts/src/shape_pack.jl` (append `RasterChordFn` + `raster_chord_fn`)
- Test: `examples/layouts/test/test_chord_fns.jl` (append)

- [ ] **Step 1: Write the failing tests** — append to `examples/layouts/test/test_chord_fns.jl`:

```julia
@testset "raster_chord_fn: runs from a BitMatrix row" begin
    # rows = y (down), cols = x. cell_size = 10.
    raster = falses(3, 6)
    raster[2, 2:3] .= true            # one run cols 2..3
    raster[2, 5:6] .= true            # second run cols 5..6
    raster[1, :] .= false
    cf = raster_chord_fn(raster, 10.0)
    @test cf isa AbstractChordFn
    iv = cf(10.0, 20.0)               # band center y=15 ⇒ row 2
    @test iv == [(10.0, 30.0), (40.0, 60.0)]   # cols 2..3 -> (10,30); cols 5..6 -> (40,60)
    @test isempty(cf(0.0, 10.0))      # row 1 all false
    @test isempty(cf(100.0, 110.0))   # out of raster range
end

@testset "raster_chord_fn: drives shape_pack" begin
    raster = falses(5, 12)
    raster[2:4, 1:12] .= true         # a solid 3-row band
    cf = raster_chord_fn(raster, 10.0)
    b = MonospaceBackend()
    prep = prepare(b, "aa bb cc dd")
    pk = shape_pack(prep, cf; line_advance=10.0, min_chord_width=0.0)
    @test !isempty(pk.placements)
    @test all(p -> 0.0 <= p.x <= 120.0, pk.placements)
end
```

- [ ] **Step 2: Run to verify it fails** —
Run: `julia --project=examples/layouts examples/layouts/test/runtests.jl`
Expected: FAIL — `UndefVarError: raster_chord_fn not defined`.

- [ ] **Step 3: Write minimal implementation** — append to `examples/layouts/src/shape_pack.jl`:

```julia
"""
    RasterChordFn(raster, cell_size)

`AbstractChordFn` from a cell-grid silhouette. `raster[row, col]` is `true` for cells
inside the shape; `row` indexes y (down), `col` indexes x. Cell `(row,col)` covers
`x ∈ [(col-1)·cell_size, col·cell_size]`, `y ∈ [(row-1)·cell_size, row·cell_size]`.
"""
struct RasterChordFn <: AbstractChordFn
    raster    :: BitMatrix
    cell_size :: Float64
end

"""
    raster_chord_fn(raster::BitMatrix, cell_size::Real) -> RasterChordFn

Chord function for cell-grid silhouettes (e.g. the Tachikoma asteroid). The available
intervals in a band are the maximal runs of `true` cells in the row containing the band's
vertical center.
"""
function raster_chord_fn(raster::BitMatrix, cell_size::Real)
    cell_size > 0 || throw(ArgumentError("cell_size must be > 0; got $cell_size"))
    return RasterChordFn(raster, Float64(cell_size))
end

function chord_intervals(f::RasterChordFn, y_top::Real, y_bottom::Real)
    cs = f.cell_size
    yc = (Float64(y_top) + Float64(y_bottom)) / 2
    row = floor(Int, yc / cs) + 1
    (row < 1 || row > size(f.raster, 1)) && return Tuple{Float64,Float64}[]
    out = Tuple{Float64,Float64}[]
    ncol = size(f.raster, 2)
    c = 1
    @inbounds while c <= ncol
        if f.raster[row, c]
            c0 = c
            while c <= ncol && f.raster[row, c]
                c += 1
            end
            push!(out, ((c0 - 1) * cs, (c - 1) * cs))   # cols c0..c-1 ⇒ [(c0-1)cs, (c-1)cs]
        else
            c += 1
        end
    end
    return out
end
```

- [ ] **Step 4: Run to verify it passes** —
Run: `julia --project=examples/layouts examples/layouts/test/runtests.jl`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add examples/layouts/src/shape_pack.jl examples/layouts/test/test_chord_fns.jl
git commit -m "feat(layouts): raster_chord_fn for cell-grid silhouettes (#C)"
```

---

## Task 6: relative perf baseline

**Files:**
- Test: `examples/layouts/test/test_perf.jl` (replace the stub)
- Create: `examples/layouts/test/perf_baseline.txt` (written on first run)

- [ ] **Step 1: Write the test** — `examples/layouts/test/test_perf.jl`:

```julia
# SPDX-License-Identifier: MIT
using Test, TextMeasure, TextMeasureLayouts
using GeometryBasics: Point2

# Synthetic ~30-vertex blob standing in for Vermont's state polygon (the real shapefile
# is #G's data and not present here). Scaled so ~600 bands of height line_advance fit.
function blob_poly(; n=30, r=900.0, cx=1000.0, cy=1000.0)
    [Point2{Float64}(cx + (r + 60.0*sin(5*2π*k/n)) * cos(2π*k/n),
                     cy + (r + 60.0*sin(5*2π*k/n)) * sin(2π*k/n)) for k in 0:n-1]
end

@testset "perf baseline (relative, >2x regression gate)" begin
    cf = polygon_chord_fn(blob_poly())
    b = MonospaceBackend()
    prep = prepare(b, join(("word$(i)" for i in 1:4000), " "))
    la = 3.0                                # ~ (cy+r - (cy-r)) / la ≈ 1860/3 ≈ 620 bands
    shape_pack(prep, cf; line_advance=la, min_chord_width=10.0)   # warmup (compile)
    elapsed = minimum(@elapsed(shape_pack(prep, cf; line_advance=la, min_chord_width=10.0)) for _ in 1:3)
    @info "shape_pack perf" elapsed_seconds=elapsed
    @test elapsed < 5.0                     # absolute sanity ceiling (machine-independent)

    path = joinpath(@__DIR__, "perf_baseline.txt")
    if isfile(path)
        baseline = parse(Float64, strip(read(path, String)))
        # >2x regression gate (cross-machine caveat: #J owns the authoritative CI gate)
        @test elapsed < 2 * baseline
    else
        write(path, string(elapsed))
        @info "perf baseline recorded" path elapsed
    end
end
```

- [ ] **Step 2: Run twice** — first run records the baseline, second run exercises the regression gate —
Run (×2): `julia --project=examples/layouts examples/layouts/test/runtests.jl`
Expected: PASS both times; first run creates `perf_baseline.txt`.

- [ ] **Step 3: Commit** (commit the recorded baseline)

```bash
git add examples/layouts/test/test_perf.jl examples/layouts/test/perf_baseline.txt
git commit -m "test(layouts): relative perf baseline for shape_pack scanline (#C)"
```

---

## Task 7: README, license-header sweep, final verification

**Files:**
- Create: `examples/layouts/README.md`
- Verify: all `examples/layouts/**/*.jl` carry `# SPDX-License-Identifier: MIT`

- [ ] **Step 1: Write the README** — `examples/layouts/README.md`:

```markdown
# TextMeasureLayouts (`examples/layouts`)

Shared layout utilities for the TextMeasure.jl demos milestone. Houses `shape_pack` (#C)
— a shape-conforming text-layout consumer — and (stretch) `knuth_plass` (#K).

Consumed by per-demo projects via `Pkg.develop(path="../layouts")`. Long-term migration
target: a registered `TextMeasureLayouts.jl` sibling package.

## `shape_pack`

```julia
using TextMeasure, TextMeasureLayouts
prep = prepare(MonospaceBackend(), "…prose…")
pk = shape_pack(prep, polygon_chord_fn(my_polygon); line_advance=prep.metrics.line_advance)
```

`shape_pack(prep, chord_fn; line_advance, min_chord_width=24, overflow_strategy=:widest_row)`
packs `:word` segments into the region described by `chord_fn` and returns a `PackedLayout`
of word `Placement`s (reading order). A full-width rectangle chord_fn reproduces
`layout(prep; max_width=w)`. Helpers: `polygon_chord_fn`, `raster_chord_fn`.

## Run the tests

```bash
julia --project=examples/layouts examples/layouts/test/runtests.jl
```
```

- [ ] **Step 2: Verify license headers** —
Run: `grep -rL "SPDX-License-Identifier" examples/layouts/src examples/layouts/test --include='*.jl'`
Expected: no output (every `.jl` has a header).

- [ ] **Step 3: Run the full examples/layouts suite once, capture to log, and grep** —
Run:
```bash
mkdir -p test-logs
julia --project=examples/layouts examples/layouts/test/runtests.jl 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"
```
Then grep the log for `Test Summary` / `Error` / `Fail`. Expected: all testsets pass, 0 failures.

- [ ] **Step 4: Sanity-check the main TextMeasure suite is untouched** (we only added `examples/`; `src/` is unchanged) — optional confirmatory run:
```bash
julia --project -e 'using Pkg; Pkg.test()' 2>&1 | tee -a "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"
```
Expected: green (no `src/` changes).

- [ ] **Step 5: Commit**

```bash
git add examples/layouts/README.md
git commit -m "docs(layouts): README + license-header sweep for shape_pack (#C)"
```

---

## Self-review (against the #C issue body)

- **Pack into rectangle == `layout` breaks** → Task 2 `rectangle == layout`. ✓
- **Pack into circle (smoke)** → Task 4 circle testset. ✓
- **Concave U-shape; slivers < `min_chord_width` dropped** → Task 4 U two-interval + sliver-drop. ✓
- **`overflowed` populated when a word exceeds the widest chord** → Task 2 (no overflow at safe widths) + Task 3 `:widest_row`/`:skip`/`:reject`. ✓
- **Coord-frame consistency (`placements[i].y` == `layout` baseline)** → Task 2 `isapprox` baseline assertion. ✓
- **Relative perf baseline (~600 scanlines × ~30 edges, >2× gate)** → Task 6. ✓ (synthetic polygon; flagged).
- **`Placement`/`PackedLayout` typed structs** → Task 1. ✓
- **`chord_fn` contract: available intervals, sorted/disjoint, empty=skip, widest-of-multi, typed `AbstractChordFn` + `chord_intervals`** → Tasks 1/4/5. ✓
- **`polygon_chord_fn` / `raster_chord_fn` typed wrappers** → Tasks 4/5. ✓
- **Overflow strategies `:widest_row`/`:skip`/`:reject`** → Tasks 2/3. ✓
- **#J property-test hooks (segment_index ∈ [1,len]; placements within chords; overflowed have no... )** → Task 2 invariant asserts (note: `:skip`/`:reject` overflowed entries have no placement; `:widest_row` deliberately places AND records — documented). ✓
- **Depends on nothing (uses `prep.segments` directly; no `subprep`)** → confirmed; no #A dependency. ✓
```
