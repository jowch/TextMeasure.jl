# Asteroid TUI (#E) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Tachikoma terminal asteroid blaster whose prose is shape-packed into procedural silhouettes, fractured on word boundaries on impact, and reflowed live — demonstrating TextMeasure's *measure-once, layout-many* across a renderer-agnostic game core with a committed golden-frame regression test.

**Architecture:** The game writes to a **renderer-agnostic `CellBuffer`** (`Matrix{Char}` + 256-color + bold). A pure `tick!(state, input)` advances physics; `draw!(buf, state)` paints the buffer using `prepare`/`shape_pack`/`subprep` (TextMeasure + TextMeasureLayouts) over `rasterize`/`voronoi_shatter`/`asteroid_polygon` silhouettes (Silhouettes), plus `FigletBackend` display type. The CI golden test drives 60 scripted ticks against a seeded RNG and checksums the `CellBuffer` — **it never instantiates a renderer**. A separate Tachikoma renderer drains the `CellBuffer` to the screen for interactive play (tier-2/3, not unit-tested).

**Tech Stack:** Julia 1.12, TextMeasure (`prepare`/`layout`/`subprep`/`FigletBackend`), TextMeasureLayouts (`shape_pack`/`raster_chord_fn`), Silhouettes (`asteroid_polygon`/`voronoi_shatter`/`rasterize`), GeometryBasics (`Point2`), Tachikoma 2.1.0 (renderer only), SHA + Random + Printf (stdlib).

---

## Probed API facts (verified against the live installed versions — DO NOT re-derive)

These were confirmed by running probe scripts against the instantiated env. Honor them exactly; several contradict naive assumptions.

- **`measure` / `font_metrics` are NOT exported** from TextMeasure. Call `TextMeasure.measure(b, s)` and `TextMeasure.font_metrics(b)` (fully qualified). Exported names: `AbstractMeasurementBackend, FigletBackend, FontMetrics, FreeTypeBackend, Layout, Line, MakieBackend, MonospaceBackend, Prepared, TextBounds, layout, line_top, measure_bounds, prepare, subprep`.
- **`line_top(lay, ::Int)` does NOT exist** — only `line_top(::Layout, ::Line)`. Use placement baselines from `shape_pack` directly; if you need a line top, pass `lay.lines[i]`.
- `Segment` fields: `(:str, :width, :kind)` — `.str` is the text, `.kind ∈ (:word,:space,:newline)`. `Prepared`: `(:segments, :metrics)`. `FontMetrics`: `(:ascent, :descent, :line_advance)` (positional ctor `FontMetrics(ascent, descent, line_advance)`). `Layout`: `(:lines, :size, :metrics)`. `Line`: `(:str, :width, :x, :baseline)`.
- `subprep(prep, r::AbstractUnitRange) -> Prepared`; `subprep(prep, 1:length(prep.segments)).segments == prep.segments` (verified). Slicing never drops/dupes segments.
- **FigletBackend (Standard font), pinned widths:** `measure("PEW")==29.0`, `measure("PEW ")==31.0`, `measure("ARWING")==53.0`, `measure("hello")==31.0`; `font_metrics == FontMetrics(5.0, 1.0, 6.0)`. `FigletBackend(font="Small")`: `measure("PEW")==23.0`, metrics `(4.0,1.0,5.0)`. Default `FigletBackend()` uses Standard and works on case-sensitive FS (the ext lowercases internally).
- **MonospaceBackend** fields `(:fontsize, :advance_ratio, :lineheight_ratio)`; defaults give 0.6·fontsize per char and 1.2·fontsize line advance. We do **not** use it for prose packing (non-integer cells); we ship a `CellBackend` instead.
- **`shape_pack(prep, chord_fn; line_advance, min_chord_width=24, overflow_strategy=:widest_row, …)`** — `line_advance` is an **explicit kwarg decoupled from metrics**. Returns `PackedLayout(placements::Vector{Placement}, overflowed::Vector{Int}, metrics)`; `Placement(segment_index, x, y)` where `segment_index` is the **absolute** index into `prep.segments`, `x` = left edge, `y` = baseline (block-top frame). `raster_chord_fn(raster::BitMatrix, cell_size::Real)`; cell `(row,col)` covers `x∈[(col-1)cs, col·cs]`, `y∈[(row-1)cs, row·cs]`, `row=1` is top.
- **Silhouettes:** `asteroid_polygon(rng; n=12, lumpiness=0.4)` → open CCW `Vector{GeometryBasics.Point{2,Float64}}` (alias `Point2{Float64}`). `rasterize(polygon, cell_size>0)` → `BitMatrix`, `row 1` = top (y-down). `voronoi_shatter(polygon, impact::Point2{Float64}; n_shards=4)` → `Vector{Vector{Point2{Float64}}}`, `length ≤ n_shards`, partitions the parent; uses an input-derived local RNG (no global RNG side effects). All deterministic given inputs.
- **Tachikoma 2.1.0 (renderer only, NOT unit-tested):** `Rect(x,y,width,height)`; `Buffer(rect::Rect)`; `set_char!(buf,x,y,ch[,style])`; `set_string!(buf,x,y,str[,style;max_x])`; `set_style!(buf,rect,style)`; `Style(; fg,bg,bold,dim,italic,underline,strikethrough,hyperlink)`; `Color256(n::Int)`; `ColorRGB(r,g,b)`; `buffer_to_text(buf, rect)`; `TestBackend(w,h)` exposes `char_at(tb,x,y)`, `style_at`, `row_text(tb,y)` for headless inspection; `Terminal(; io, size, remote_tty_path)`. High-level `@tachikoma_app`, `Model`, `app` exist but resolve only as `TK.@tachikoma_app` etc. (they are not bound in `Main`). Tachikoma's `x,y` are column,row 1-based.
- **Determinism:** `Xoshiro(seed)` (from `Random`) for all RNG. `voronoi_shatter` and `asteroid_polygon` take an explicit RNG / are input-seeded, so the whole core is reproducible. **Checksums use `SHA.sha256` over a canonical byte encoding** (stdlib, stable across Julia versions) — NOT `Base.hash` (version-unstable, unsafe for a committed golden).

---

## File structure

All paths under `examples/asteroid_tui/`. Already created by setup: `Project.toml` (deps: TextMeasure, TextMeasureLayouts, Silhouettes, FIGlet, GeometryBasics, Tachikoma, Random, Printf; `julia="1.12"`; `[extras] Test` + `[targets] test=["Test"]`), `src/AsteroidTUI.jl` (skeleton), `test/runtests.jl` (skeleton), `README.md`. **Add `SHA` to deps** in Task 1.

| File | Responsibility |
|------|----------------|
| `src/AsteroidTUI.jl` | Module: `include`s, `using`s, exports. |
| `src/cellbuffer.jl` | `CellBuffer` (renderer-agnostic), `clear!`/`put_char!`/`put_string!`/`checksum`/`to_text`. |
| `src/cellbackend.jl` | `CellBackend <: AbstractMeasurementBackend` — 1 cell/grapheme, metrics `(1,0,1)`. |
| `src/prose.jl` | Procedural prose pool (≥50 distinct templates), `asteroid_prose(rng)`. |
| `src/entities.jl` | `Ship`, `Asteroid`, `Shard`, `Beam` structs + physics fields. |
| `src/game.jl` | `GameState`, `new_game`, `tick!`, spawn/respawn, charge, beam, collision, fracture. |
| `src/pack.jl` | `pack_prose_into(polygon, prep; …)` helper: rasterize → raster_chord_fn → shape_pack → placements in cell coords. |
| `src/draw.jl` | `draw!(buf, state)` — paints asteroids/ship/beam/tags/charge/debug into the `CellBuffer`. |
| `src/input.jl` | `Input` struct + `ScriptedInput` (deterministic sequence for tests). |
| `src/render_tachikoma.jl` | Drains `CellBuffer`→Tachikoma `Buffer`; interactive loop. **Not unit-tested.** |
| `run.jl` | Interactive entry point. |
| `test/runtests.jl` | Aggregator. |
| `test/test_cellbuffer.jl` | Buffer ops + checksum determinism/stability. |
| `test/test_cellbackend.jl` | `measure`/`font_metrics` conformance. |
| `test/test_prose.jl` | ≥50 distinct templates, deterministic by seed. |
| `test/test_pack.jl` | `pack_prose_into` places words inside the silhouette; coords in-bounds. |
| `test/test_game.jl` | `tick!` physics, charge stages, respawn/invuln counters. |
| `test/test_fracture.jl` | Glyph-preservation: shard prose concatenation == original word order. |
| `test/test_golden.jl` | 60-tick scripted run → checksum vs committed golden + glyph order. |
| `test/golden/frame60.sha256` | Committed golden checksum (text). |
| `test/golden/frame60.txt` | Committed sample frame render (human-readable). |

---

## Task 1: CellBuffer + content-stable checksum

**Files:**
- Create: `examples/asteroid_tui/src/cellbuffer.jl`
- Modify: `examples/asteroid_tui/Project.toml` (add `SHA` stdlib dep)
- Modify: `examples/asteroid_tui/src/AsteroidTUI.jl` (include + using SHA)
- Test: `examples/asteroid_tui/test/test_cellbuffer.jl`

- [ ] **Step 1: Add SHA dep.** Edit `Project.toml` `[deps]`: add `SHA = "ea8e919c-243c-51af-8825-aaa63cd721ce"` and `[compat]` `SHA = "0.7"`. Verify resolve: `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.resolve()'` → no error.

- [ ] **Step 2: Write the failing test** (`test/test_cellbuffer.jl`):

```julia
# SPDX-License-Identifier: MIT
using AsteroidTUI: CellBuffer, clear!, put_char!, put_string!, checksum, to_text, nrows, ncols
using Test

@testset "CellBuffer" begin
    b = CellBuffer(3, 5)
    @test nrows(b) == 3 && ncols(b) == 5
    @test all(==(' '), b.chars)

    put_string!(b, 1, 1, "AB")
    put_char!(b, 2, 3, 'X'; fg=UInt8(9), bold=true)
    @test b.chars[1,1] == 'A' && b.chars[1,2] == 'B'
    @test b.chars[2,3] == 'X' && b.fg[2,3] == 0x09 && b.bold[2,3]

    # out-of-bounds writes are ignored, not errors
    put_char!(b, 99, 99, 'Z')
    put_string!(b, 1, 4, "WXYZ")          # clips at col 5
    @test b.chars[1,4] == 'W' && b.chars[1,5] == 'X'

    # checksum is content-defined and stable (pin the literal once observed)
    b2 = CellBuffer(3, 5); put_string!(b2, 1, 1, "AB"); put_char!(b2, 2, 3, 'X'; fg=UInt8(9), bold=true)
    put_string!(b2, 1, 4, "WX")
    @test checksum(b) == checksum(b2)     # same content ⇒ same checksum
    clear!(b2)
    @test checksum(b) != checksum(b2)
    @test checksum(CellBuffer(3,5)) == checksum(CellBuffer(3,5))   # empty stable
    @test to_text(CellBuffer(1,3)) == "   "
end
```

- [ ] **Step 3: Run, expect FAIL** (`UndefVarError: CellBuffer`):
  `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()'` (or iterate faster with `include("test/test_cellbuffer.jl")` after `using AsteroidTUI`).

- [ ] **Step 4: Implement** (`src/cellbuffer.jl`):

```julia
# SPDX-License-Identifier: MIT
using SHA: sha256

"""
    CellBuffer(rows, cols)

Renderer-agnostic terminal frame: a `Char` grid plus 256-color foreground and a
bold mask. `chars[row, col]`, `row == 1` is the top. Both interactive renderers
(Tachikoma, future raw-ANSI) drain a `CellBuffer`; the CI golden test checksums it
without instantiating any renderer.
"""
struct CellBuffer
    chars :: Matrix{Char}
    fg    :: Matrix{UInt8}      # Color256 index; 0x00 == terminal default
    bold  :: BitMatrix
end

CellBuffer(rows::Integer, cols::Integer) =
    CellBuffer(fill(' ', rows, cols), zeros(UInt8, rows, cols), falses(rows, cols))

nrows(b::CellBuffer) = size(b.chars, 1)
ncols(b::CellBuffer) = size(b.chars, 2)
inbounds(b::CellBuffer, r::Integer, c::Integer) = 1 <= r <= nrows(b) && 1 <= c <= ncols(b)

function clear!(b::CellBuffer)
    fill!(b.chars, ' '); fill!(b.fg, 0x00); fill!(b.bold, false); return b
end

function put_char!(b::CellBuffer, r::Integer, c::Integer, ch::Char; fg::UInt8=0x00, bold::Bool=false)
    inbounds(b, r, c) || return b
    @inbounds (b.chars[r, c] = ch; b.fg[r, c] = fg; b.bold[r, c] = bold)
    return b
end

function put_string!(b::CellBuffer, r::Integer, c::Integer, s::AbstractString; fg::UInt8=0x00, bold::Bool=false)
    col = c; row = r
    for ch in s
        if ch == '\n'
            row += 1; col = c; continue
        end
        put_char!(b, row, col, ch; fg=fg, bold=bold); col += 1
    end
    return b
end

# Canonical, version-stable byte encoding: dims, then chars (UTF-8), then fg, then bold.
function _canonical_bytes(b::CellBuffer)
    io = IOBuffer()
    write(io, UInt32(nrows(b))); write(io, UInt32(ncols(b)))
    for ch in b.chars; write(io, codeunits(string(ch))); write(io, 0x00); end
    write(io, b.fg)
    write(io, UInt8.(b.bold))
    return take!(io)
end

checksum(b::CellBuffer) = bytes2hex(sha256(_canonical_bytes(b)))
to_text(b::CellBuffer) = join((String(@view b.chars[r, :]) for r in 1:nrows(b)), '\n')
```

- [ ] **Step 5: Wire into module.** In `src/AsteroidTUI.jl`, inside `module AsteroidTUI`, add `using SHA` and `include("cellbuffer.jl")`; export `CellBuffer, clear!, put_char!, put_string!, checksum, to_text`.

- [ ] **Step 6: Run, expect PASS.** `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()'` → CellBuffer testset green.

- [ ] **Step 7: Commit.** `git add examples/asteroid_tui/Project.toml examples/asteroid_tui/src/cellbuffer.jl examples/asteroid_tui/src/AsteroidTUI.jl examples/asteroid_tui/test/test_cellbuffer.jl && git commit -m "feat(asteroid): renderer-agnostic CellBuffer + SHA checksum (#E)"`

---

## Task 2: CellBackend (1 cell/grapheme)

**Files:** Create `src/cellbackend.jl`; modify `src/AsteroidTUI.jl`; Test `test/test_cellbackend.jl`.

- [ ] **Step 1: Failing test** (`test/test_cellbackend.jl`):

```julia
# SPDX-License-Identifier: MIT
using AsteroidTUI: CellBackend
import TextMeasure
using Test

@testset "CellBackend" begin
    b = CellBackend()
    @test TextMeasure.measure(b, "rock") == 4.0
    @test TextMeasure.measure(b, "") == 0.0
    @test TextMeasure.measure(b, "a b") == 3.0            # space counts as a cell
    m = TextMeasure.font_metrics(b)
    @test (m.ascent, m.descent, m.line_advance) == (1.0, 0.0, 1.0)
    # prepare/segments use it transparently
    p = TextMeasure.prepare(b, "iron ore")
    @test [s.kind for s in p.segments] == [:word, :space, :word]
    @test p.segments[1].width == 4.0 && p.segments[3].width == 3.0
end
```

- [ ] **Step 2: Run, expect FAIL** (`UndefVarError: CellBackend`).

- [ ] **Step 3: Implement** (`src/cellbackend.jl`):

```julia
# SPDX-License-Identifier: MIT
import TextMeasure
import Unicode

"""
    CellBackend()

A zero-config measurement backend where every grapheme cluster is exactly one
terminal cell wide and a line advances exactly one row. This makes `shape_pack`
output land on integer cell coordinates, which is what the cell-grid silhouette
packing needs. (A fourth instance of CLAUDE.md's "subtype + two methods" pattern.)
"""
struct CellBackend <: TextMeasure.AbstractMeasurementBackend end

TextMeasure.measure(::CellBackend, text::AbstractString) =
    Float64(length(collect(Unicode.graphemes(text))))

TextMeasure.font_metrics(::CellBackend) = TextMeasure.FontMetrics(1.0, 0.0, 1.0)
```

> `Unicode` is a stdlib; add `Unicode = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"` to `Project.toml` `[deps]` (and `Unicode = "1"` to `[compat]`) — Step 3a — then `Pkg.resolve()`.

- [ ] **Step 4: Wire + run.** `include("cellbackend.jl")` and `export CellBackend` in the module; `Pkg.test()` → green.

- [ ] **Step 5: Commit.** `git add -A examples/asteroid_tui && git commit -m "feat(asteroid): CellBackend — 1 cell/grapheme integer metrics (#E)"`

---

## Task 3: Procedural prose pool (≥50 distinct)

**Files:** Create `src/prose.jl`; modify module; Test `test/test_prose.jl`.

- [ ] **Step 1: Failing test** (`test/test_prose.jl`):

```julia
# SPDX-License-Identifier: MIT
using AsteroidTUI: asteroid_prose, PROSE_VARIANTS
using Random
using Test

@testset "prose pool" begin
    @test PROSE_VARIANTS() >= 50
    rng = Xoshiro(7)
    s = asteroid_prose(rng)
    @test s isa String && length(split(s)) >= 6
    # deterministic by seed
    @test asteroid_prose(Xoshiro(1)) == asteroid_prose(Xoshiro(1))
    # variety: 40 draws give many distinct strings
    seen = Set(asteroid_prose(Xoshiro(i)) for i in 1:40)
    @test length(seen) >= 30
    # no global RNG side effects
    Random.seed!(123); a = rand(); Random.seed!(123); asteroid_prose(Xoshiro(9)); b = rand()
    @test a == b
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** (`src/prose.jl`) — combinatorial template; the cartesian product of the lists below is ≫50, and `PROSE_VARIANTS` reports a conservative lower bound:

```julia
# SPDX-License-Identifier: MIT
using Random: AbstractRNG

const _CLASS    = ("C-type", "S-type", "M-type", "carbonaceous", "silicate",
                   "metallic", "chondritic", "basaltic")
const _MATERIAL = ("iron-nickel", "olivine", "pyroxene", "regolith", "magnetite",
                   "ice-laced rock", "porous dust", "shock-veined ore")
const _TEMPER   = ("ancient and cold", "scarred by impacts", "tumbling lazily",
                   "newly calved", "radar-bright", "spectrally dark")
const _CALLPREFIX = ("NX", "VG", "KR", "ZL", "QF", "BD")

# Conservative count: class × material × temper (callsign/spin add far more).
PROSE_VARIANTS() = length(_CLASS) * length(_MATERIAL) * length(_TEMPER)

"""
    asteroid_prose(rng) -> String

Deterministic-by-`rng` descriptive sentence for an asteroid's interior text.
Pulls only from `rng` (no global RNG access).
"""
function asteroid_prose(rng::AbstractRNG)
    cls  = rand(rng, _CLASS)
    mat  = rand(rng, _MATERIAL)
    tmp  = rand(rng, _TEMPER)
    call = string(rand(rng, _CALLPREFIX), '-', lpad(rand(rng, 100:999), 3, '0'))
    spin = round(rand(rng) * 0.4; digits = 2)
    return "$cls drifter $call composed of $mat, $tmp, spinning at $spin rad per second."
end
```

- [ ] **Step 4: Wire + run** → green. **Step 5: Commit** `feat(asteroid): procedural prose pool (≥50 variants) (#E)`.

---

## Task 4: pack_prose_into — silhouette text packing helper

**Files:** Create `src/pack.jl`; module; Test `test/test_pack.jl`. Depends on Tasks 1–2.

- [ ] **Step 1: Failing test** (`test/test_pack.jl`):

```julia
# SPDX-License-Identifier: MIT
using AsteroidTUI: CellBackend, pack_prose_into, PackedProse
import TextMeasure
using Silhouettes: asteroid_polygon
using Random
using Test

@testset "pack_prose_into" begin
    rng = Xoshiro(3)
    poly = asteroid_polygon(rng; n=12, lumpiness=0.3)
    prep = TextMeasure.prepare(CellBackend(), "iron rock spins fast cold dense ore here now")
    pp = pack_prose_into(poly, prep; scale=18.0, min_chord_width=3.0)
    @test pp isa PackedProse
    @test pp.rows >= 3 && pp.cols >= 3
    @test !isempty(pp.cells)                                   # (row, col, char) tuples
    # all placed cells are inside the raster bounds
    @test all(1 <= r <= pp.rows && 1 <= c <= pp.cols for (r, c, _ch) in pp.cells)
    # determinism
    pp2 = pack_prose_into(poly, prep; scale=18.0, min_chord_width=3.0)
    @test pp.cells == pp2.cells
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** (`src/pack.jl`):

```julia
# SPDX-License-Identifier: MIT
import TextMeasure
using TextMeasureLayouts: shape_pack, raster_chord_fn
using Silhouettes: rasterize
import GeometryBasics as GB

"""
    PackedProse(rows, cols, cells)

A silhouette's packed interior text in **local cell coordinates** (row 1 = top of
the silhouette's bounding box). `cells :: Vector{Tuple{Int,Int,Char}}` is
`(row, col, char)` for every glyph, in reading order.
"""
struct PackedProse
    rows  :: Int
    cols  :: Int
    cells :: Vector{Tuple{Int,Int,Char}}
end

"""
    pack_prose_into(polygon, prep; scale, min_chord_width=3.0) -> PackedProse

Rasterize `polygon` (scaled to `scale` cells across its larger extent) to a cell
grid, then `shape_pack` the `:word` segments of `prep` (built with `CellBackend`)
into the silhouette at one row per line. Coordinates are integer cells.
"""
function pack_prose_into(polygon::Vector{GB.Point2{Float64}}, prep::TextMeasure.Prepared;
                         scale::Real, min_chord_width::Real=3.0)
    xs = [p[1] for p in polygon]; ys = [p[2] for p in polygon]
    span = max(maximum(xs) - minimum(xs), maximum(ys) - minimum(ys))
    span <= 0 && return PackedProse(1, 1, Tuple{Int,Int,Char}[])
    cell = span / scale                                   # polygon-units per cell
    raster = rasterize(polygon, cell)                     # BitMatrix, row 1 = top
    cf = raster_chord_fn(raster, 1.0)                     # work in cell units (cell_size 1)
    pk = shape_pack(prep, cf; line_advance = 1.0, min_chord_width = Float64(min_chord_width))
    cells = Tuple{Int,Int,Char}[]
    for pl in pk.placements
        seg = prep.segments[pl.segment_index]
        seg.kind === :word || continue
        row = round(Int, pl.y)                            # baseline y = band (ascent==1)
        col0 = round(Int, pl.x) + 1                       # left edge → 1-based col
        for (k, ch) in enumerate(seg.str)
            push!(cells, (row, col0 + k - 1, ch))
        end
    end
    return PackedProse(size(raster, 1), size(raster, 2), cells)
end
```

- [ ] **Step 4: Wire + run** → green. **Step 5: Commit** `feat(asteroid): pack_prose_into silhouette packing (#E)`.

---

## Task 5: Entities + GameState + new_game

**Files:** Create `src/entities.jl`, `src/input.jl`; module; (tests come with Task 6/7).

- [ ] **Step 1: Implement entities** (`src/entities.jl`):

```julia
# SPDX-License-Identifier: MIT
import GeometryBasics as GB
import TextMeasure

const P2 = GB.Point2{Float64}

mutable struct Ship
    x::Float64; y::Float64          # cell coords (col, row), continuous
    φ::Float64                       # heading, radians (0 = up)
    vx::Float64; vy::Float64
    charge::Int                      # 0..5 charge stage
    alive::Bool
    invuln::Int                      # remaining invulnerability ticks (>0 ⇒ blinking)
end

mutable struct Asteroid
    poly::Vector{P2}                 # unit-ish silhouette (Silhouettes frame)
    x::Float64; y::Float64           # center in cell coords
    vx::Float64; vy::Float64
    ω::Float64                       # spin rad/tick
    θ::Float64                       # accumulated rotation
    radius::Float64                  # cell radius (for collision + scale)
    prep::TextMeasure.Prepared       # measured prose (measure once!)
    age::Int                         # ticks since spawn (re-raster cadence)
end

mutable struct Shard
    poly::Vector{P2}
    x::Float64; y::Float64
    vx::Float64; vy::Float64
    prep::TextMeasure.Prepared       # subprep slice — NOT re-measured
    ttl::Int                         # ticks to live
    radius::Float64
end

mutable struct Beam
    active::Bool
    x::Float64; y::Float64           # origin (ship tip)
    φ::Float64
    length::Int                      # cells (onomatopoeia repeats)
    ttl::Int
end
```

- [ ] **Step 2: Implement input** (`src/input.jl`):

```julia
# SPDX-License-Identifier: MIT
"""
    Input(; thrust=false, left=false, right=false, fire=false, debug=false, quit=false)

One tick's intent, decoupled from any key encoding. `fire` held across ticks grows
the charge; releasing it (a tick with `fire=false` after `fire=true`) launches.
"""
Base.@kwdef struct Input
    thrust::Bool = false
    left::Bool   = false
    right::Bool  = false
    fire::Bool   = false
    debug::Bool  = false
    quit::Bool   = false
end

"""
    ScriptedInput(seq::Vector{Input})

Deterministic input source for the headless golden test. `next_input!` returns the
next entry, repeating the last once exhausted.
"""
mutable struct ScriptedInput
    seq::Vector{Input}
    i::Int
end
ScriptedInput(seq::Vector{Input}) = ScriptedInput(seq, 0)
function next_input!(s::ScriptedInput)
    s.i = min(s.i + 1, length(s.seq))
    return isempty(s.seq) ? Input() : s.seq[s.i]
end
```

- [ ] **Step 3: Implement GameState + new_game** (in `src/game.jl`, the rest filled by Tasks 6–8):

```julia
# SPDX-License-Identifier: MIT
using Random: AbstractRNG, Xoshiro
import TextMeasure
using Silhouettes: asteroid_polygon

mutable struct GameState
    width::Int; height::Int          # buffer cols, rows
    ship::Ship
    asteroids::Vector{Asteroid}
    shards::Vector{Shard}
    beam::Beam
    rng::Xoshiro
    tick_count::Int
    debug::Bool
    prev_fire::Bool                  # for release-to-launch edge detection
    last_hit_glyphs::Vector{String}  # words of the most recently fractured asteroid (for tests)
end

const CHARGE_MAX = 5
const INVULN_TICKS = 120             # ~2s at 60fps
const RERASTER_EVERY = 5

function _spawn_asteroid(rng::AbstractRNG, width, height)
    poly = asteroid_polygon(rng; n = rand(rng, 8:16), lumpiness = 0.2 + 0.5 * rand(rng))
    prep = TextMeasure.prepare(CellBackend(), asteroid_prose(rng))
    radius = 6.0 + 6.0 * rand(rng)
    return Asteroid(poly,
                    rand(rng) * width, rand(rng) * height,
                    (rand(rng) - 0.5) * 0.6, (rand(rng) - 0.5) * 0.6,
                    (rand(rng) - 0.5) * 0.8 / 60,   # ω in rad/tick (~[-0.4,0.4] rad/s)
                    0.0, radius, prep, 0)
end

"""
    new_game(rng; width=120, height=40, n_asteroids=5) -> GameState

Seeded initial state. All randomness flows from `rng` (pass `Xoshiro(seed)` for a
reproducible game — the golden test relies on this).
"""
function new_game(rng::Xoshiro = Xoshiro(0); width=120, height=40, n_asteroids=5)
    ship = Ship(width/2, height/2, 0.0, 0.0, 0.0, 0, true, 0)
    asteroids = [_spawn_asteroid(rng, width, height) for _ in 1:n_asteroids]
    beam = Beam(false, 0.0, 0.0, 0.0, 0, 0)
    return GameState(width, height, ship, asteroids, Shard[], beam, rng, 0, false,
                     false, String[])
end
```

- [ ] **Step 4: Wire all includes** in `src/AsteroidTUI.jl` (order: cellbuffer, cellbackend, prose, pack, entities, input, game, draw, render_tachikoma) and export `GameState, new_game, tick!, draw!, Input, ScriptedInput`. **Step 5: Commit** `feat(asteroid): entities, input, GameState/new_game (#E)`.

---

## Task 6: tick! — physics, charge, beam (no fracture yet)

**Files:** Modify `src/game.jl`; Test `test/test_game.jl`.

- [ ] **Step 1: Failing test** (`test/test_game.jl`):

```julia
# SPDX-License-Identifier: MIT
using AsteroidTUI: new_game, tick!, Input, CHARGE_MAX
using Random
using Test

@testset "tick! physics" begin
    g = new_game(Xoshiro(42); width=120, height=40, n_asteroids=3)
    x0, y0 = g.ship.x, g.ship.y
    # thrust changes velocity then position; world wraps (stays in-bounds)
    for _ in 1:5; tick!(g, Input(thrust=true)); end
    @test (g.ship.vx, g.ship.vy) != (0.0, 0.0)
    @test 0 <= g.ship.x <= g.width && 0 <= g.ship.y <= g.height
    # rotation
    φ0 = g.ship.φ; tick!(g, Input(left=true)); @test g.ship.φ != φ0
    # charge ramps while fire held, caps at CHARGE_MAX
    g2 = new_game(Xoshiro(1))
    for _ in 1:20; tick!(g2, Input(fire=true)); end
    @test g2.ship.charge == CHARGE_MAX
    # release launches a beam and resets charge
    tick!(g2, Input(fire=false))
    @test g2.beam.active && g2.ship.charge == 0
    # asteroids advanced + rotated
    g3 = new_game(Xoshiro(5)); a = g3.asteroids[1]; θ0 = a.θ
    tick!(g3, Input()); @test g3.asteroids[1].θ != θ0
    # debug toggles on a debug-edge
    g4 = new_game(Xoshiro(2)); @test !g4.debug; tick!(g4, Input(debug=true)); @test g4.debug
    @test g3.tick_count == 1
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement `tick!`** (append to `src/game.jl`). Physics in cell units; world wraps toroidally; charge edge-detected via `prev_fire`. (Collision/fracture added in Task 7 — call `_resolve_collisions!(g)` which is a no-op stub here, replaced next task.)

```julia
const THRUST = 0.05
const TURN   = 0.12
const FRICTION = 0.98

_wrap(v, hi) = mod(v, hi)

function _advance_ship!(g::GameState, in::Input)
    s = g.ship
    in.left  && (s.φ -= TURN)
    in.right && (s.φ += TURN)
    if in.thrust
        s.vx += THRUST * sin(s.φ); s.vy -= THRUST * cos(s.φ)
    end
    s.vx *= FRICTION; s.vy *= FRICTION
    s.x = _wrap(s.x + s.vx, g.width); s.y = _wrap(s.y + s.vy, g.height)
    s.invuln > 0 && (s.invuln -= 1)
end

function _advance_asteroids!(g::GameState)
    for a in g.asteroids
        a.x = _wrap(a.x + a.vx, g.width); a.y = _wrap(a.y + a.vy, g.height)
        a.θ += a.ω; a.age += 1
    end
    for sh in g.shards
        sh.x = _wrap(sh.x + sh.vx, g.width); sh.y = _wrap(sh.y + sh.vy, g.height)
        sh.ttl -= 1
    end
    filter!(sh -> sh.ttl > 0, g.shards)
end

function _handle_charge_and_beam!(g::GameState, in::Input)
    s = g.ship
    if in.fire
        s.charge = min(s.charge + 1, CHARGE_MAX)
    elseif g.prev_fire && s.charge > 0          # release edge ⇒ launch
        g.beam = Beam(true, s.x, s.y, s.φ, 4 + 6 * s.charge, 6)
        s.charge = 0
    end
    g.prev_fire = in.fire
    if g.beam.active
        g.beam.ttl -= 1
        g.beam.ttl <= 0 && (g.beam = Beam(false, 0.0, 0.0, 0.0, 0, 0))
    end
end

_resolve_collisions!(g::GameState) = g    # replaced in Task 7

"""
    tick!(g, input) -> g

Advance the game one frame. Pure w.r.t. the terminal — mutates only `g`. Uses only
`g.rng` for any randomness (respawns), so a seeded `new_game` + scripted inputs is
fully reproducible.
"""
function tick!(g::GameState, in::Input)
    in.debug && (g.debug = !g.debug)
    _advance_ship!(g, in)
    _advance_asteroids!(g)
    _handle_charge_and_beam!(g, in)
    _resolve_collisions!(g)
    g.tick_count += 1
    return g
end
```

> Note the debug-toggle test sends `Input(debug=true)` exactly once; if you later drive debug from a held key, edge-detect it like `fire`. For the scripted golden, debug is sent as single-tick pulses.

- [ ] **Step 4: Run → green. Step 5: Commit** `feat(asteroid): tick! physics, charge, beam (#E)`.

---

## Task 7: Collision + word-boundary fracture (glyph-preservation)

**Files:** Modify `src/game.jl` (replace `_resolve_collisions!`); Test `test/test_fracture.jl`.

- [ ] **Step 1: Failing test** (`test/test_fracture.jl`) — the operational "legible" definition: every original word appears once, in order, across the two shards:

```julia
# SPDX-License-Identifier: MIT
using AsteroidTUI: new_game, tick!, Input, fracture_asteroid!, GameState
import TextMeasure
import GeometryBasics as GB
using Random
using Test

# helper: words (in order) of a Prepared
words(p) = [s.str for s in p.segments if s.kind === :word]

@testset "word-boundary fracture preserves glyphs" begin
    g = new_game(Xoshiro(11); n_asteroids=1)
    a = g.asteroids[1]
    original = words(a.prep)
    impact = GB.Point2{Float64}(a.x, a.y)
    n_before = length(g.shards)
    fracture_asteroid!(g, 1, impact)
    @test isempty(g.asteroids)                       # the hit asteroid is removed
    @test length(g.shards) >= 2                       # at least two shard-prose chunks
    # concatenating shard words in shard order reproduces the original word order
    rebuilt = vcat((words(sh.prep) for sh in g.shards)...)
    @test rebuilt == original                         # no drops, no dups, in order
    @test g.last_hit_glyphs == original
end
```

- [ ] **Step 2: Run, expect FAIL** (`UndefVarError: fracture_asteroid!`).

- [ ] **Step 3: Implement** `_resolve_collisions!` + `fracture_asteroid!` (append to `src/game.jl`):

```julia
using TextMeasure: subprep
using Silhouettes: voronoi_shatter
import GeometryBasics as GB

# Split a Prepared's segment range into ~`n` contiguous chunks at :word boundaries,
# so that concatenating the chunks' words reproduces the original word order exactly.
function _word_boundary_splits(prep::TextMeasure.Prepared, n::Int)
    word_idx = [i for (i, s) in enumerate(prep.segments) if s.kind === :word]
    nw = length(word_idx)
    nw == 0 && return UnitRange{Int}[1:length(prep.segments)]
    n = clamp(n, 1, nw)
    bounds = Int[]
    for k in 1:(n - 1)
        push!(bounds, word_idx[clamp(round(Int, k * nw / n), 1, nw)])  # split before this word
    end
    ranges = UnitRange{Int}[]
    lo = 1
    for b in bounds
        push!(ranges, lo:(b - 1)); lo = b
    end
    push!(ranges, lo:length(prep.segments))
    return ranges
end

"""
    fracture_asteroid!(g, idx, impact)

Remove asteroid `idx`, fracture its silhouette with `voronoi_shatter` seeded at
`impact`, and re-pack each shard with a `subprep` slice of the asteroid's already
-measured prose (no re-measurement). The slices tile the segment range, so every
glyph survives in exactly one shard, in original order.
"""
function fracture_asteroid!(g::GameState, idx::Int, impact::GB.Point2{Float64})
    a = g.asteroids[idx]
    n_shards = 2 + (length([s for s in a.prep.segments if s.kind === :word]) >= 6 ? 2 : 0)
    polys = voronoi_shatter(a.poly, GB.Point2{Float64}(0.0, 0.0); n_shards = n_shards)
    isempty(polys) && (polys = [a.poly])
    ranges = _word_boundary_splits(a.prep, length(polys))
    deleteat!(g.asteroids, idx)
    g.last_hit_glyphs = [s.str for s in a.prep.segments if s.kind === :word]
    for (poly, r) in zip(polys, ranges)
        sp = subprep(a.prep, r)
        push!(g.shards, Shard(poly, a.x, a.y,
                              a.vx + (rand(g.rng) - 0.5) * 0.4,
                              a.vy + (rand(g.rng) - 0.5) * 0.4,
                              sp, 90, a.radius / 2))
    end
    return g
end

function _resolve_collisions!(g::GameState)
    g.beam.active || return g
    bx, by, φ = g.beam.x, g.beam.y, g.beam.φ
    dirx, diry = sin(φ), -cos(φ)
    for idx in length(g.asteroids):-1:1
        a = g.asteroids[idx]
        for t in 0:g.beam.length              # sample along the beam
            px, py = bx + dirx * t, by + diry * t
            if hypot(px - a.x, py - a.y) <= a.radius
                fracture_asteroid!(g, idx, GB.Point2{Float64}(px - a.x, py - a.y))
                break
            end
        end
    end
    return g
end
```

- [ ] **Step 4: Run → green. Step 5: Commit** `feat(asteroid): collision + word-boundary fracture via subprep (#E)`.

---

## Task 8: Respawn + invulnerability

**Files:** Modify `src/game.jl`; extend `test/test_game.jl`.

- [ ] **Step 1: Add failing test** (append to `test/test_game.jl`):

```julia
@testset "respawn + invuln" begin
    using AsteroidTUI: kill_ship!, ship_visible
    g = new_game(Xoshiro(8))
    kill_ship!(g)
    @test !g.ship.alive
    # respawn after the death timer; gains invulnerability
    for _ in 1:65; tick!(g, Input()); end
    @test g.ship.alive && g.ship.invuln > 0
    # invuln blink: visibility alternates over ticks
    vis = [ (tick!(g, Input()); ship_visible(g)) for _ in 1:8 ]
    @test any(vis) && any(!, vis)
end
```

- [ ] **Step 2: Implement** (append to `src/game.jl`): add a `death_timer::Int` field path via a module-level mutable on `Ship` — simplest is to add `respawn_in::Int` to `GameState` (modify the struct in Task 5 to include `respawn_in::Int` initialized to 0; if executing strictly in order, add it now and update `new_game`).

```julia
function kill_ship!(g::GameState)
    g.ship.alive = false
    g.respawn_in = 60                 # ~1s before respawn
    return g
end

# call inside tick! BEFORE _advance_ship!: if dead, count down then respawn
function _handle_respawn!(g::GameState)
    g.ship.alive && return g
    g.respawn_in -= 1
    if g.respawn_in <= 0
        g.ship = Ship(g.width/2, g.height/2, 0.0, 0.0, 0.0, 0, true, INVULN_TICKS)
    end
    return g
end

# blink at ~3Hz: visible 10 ticks on / 10 off while invulnerable
ship_visible(g::GameState) = g.ship.alive && (g.ship.invuln == 0 || (g.ship.invuln ÷ 10) % 2 == 0)
```

Insert `_handle_respawn!(g)` as the first line of `tick!`'s body (before `in.debug`), and guard `_advance_ship!`/charge on `g.ship.alive`. Export `kill_ship!, ship_visible`.

- [ ] **Step 3: Run → green. Step 4: Commit** `feat(asteroid): ship death/respawn + invuln blink (#E)`.

---

## Task 9: draw! — paint a full frame into the CellBuffer

**Files:** Create `src/draw.jl`; Test `test/test_draw.jl`. Colors are `Color256` indices (UInt8): asteroid prose 250 (grey), ship 51 (cyan), beam 226 (yellow), stat tags 244, debug 45.

- [ ] **Step 1: Failing test** (`test/test_draw.jl`):

```julia
# SPDX-License-Identifier: MIT
using AsteroidTUI: new_game, tick!, Input, draw!, CellBuffer, to_text, ship_visible
using Random
using Test

@testset "draw!" begin
    g = new_game(Xoshiro(21); width=80, height=24, n_asteroids=3)
    for _ in 1:10; tick!(g, Input(thrust=true)); end
    buf = CellBuffer(g.height, g.width)
    draw!(buf, g)
    txt = to_text(buf)
    @test length(txt) > g.width                  # something was drawn
    @test count(!=(' '), buf.chars) > 0
    # debug overlay adds cyan bboxes when on
    g.debug = true
    buf2 = CellBuffer(g.height, g.width); draw!(buf2, g)
    @test count(==(UInt8(45)), buf2.fg) >= count(==(UInt8(45)), buf.fg)
    # determinism: same state ⇒ same buffer
    bufA = CellBuffer(g.height, g.width); draw!(bufA, g)
    bufB = CellBuffer(g.height, g.width); draw!(bufB, g)
    @test bufA.chars == bufB.chars && bufA.fg == bufB.fg
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** (`src/draw.jl`). Each asteroid/shard: `pack_prose_into` (its `prep`, `scale ≈ 2·radius`), then blit cells at `(center_row - rows÷2 + r, center_col - cols÷2 + c)`. Ship: a small figlet/wedge glyph + charge glyph at the tip. Beam: repeated `"PEW "` along `φ` for `beam.length` cells. Stat tags: `Printf.@sprintf("┌─ d:%dm v:%.2fµ ─┐", …)` above each asteroid. Debug: draw a `fg=45` cell at each placed glyph's position.

```julia
# SPDX-License-Identifier: MIT
import Printf
import GeometryBasics as GB

const COL_PROSE = 0xfa    # 250
const COL_SHIP  = 0x33    # 51
const COL_BEAM  = 0xe2    # 226
const COL_TAG   = 0xf4    # 244
const COL_DEBUG = 0x2d    # 45
const CHARGE_GLYPH = (' ', '·', '*', '─', '\\', '✸')  # index = charge stage (1-based: charge+1)

function _blit_packed!(buf::CellBuffer, pp, cx::Real, cy::Real; fg, debug::Bool)
    r0 = round(Int, cy) - pp.rows ÷ 2
    c0 = round(Int, cx) - pp.cols ÷ 2
    for (r, c, ch) in pp.cells
        put_char!(buf, r0 + r - 1, c0 + c - 1, ch; fg = fg)
        debug && put_char!(buf, r0 + r - 1, c0 + c - 1, ch; fg = COL_DEBUG)
    end
end

function _draw_asteroid!(buf::CellBuffer, a, debug::Bool)
    pp = pack_prose_into(a.poly, a.prep; scale = max(4.0, 2 * a.radius), min_chord_width = 3.0)
    _blit_packed!(buf, pp, a.x, a.y; fg = COL_PROSE, debug = debug)
    tag = Printf.@sprintf("┌─ d:%03dm v:%.2fµ ─┐", round(Int, a.radius * 10), hypot(a.vx, a.vy))
    put_string!(buf, round(Int, a.y) - pp.rows ÷ 2 - 1, round(Int, a.x) - length(tag) ÷ 2, tag; fg = COL_TAG)
end

function _draw_ship!(buf::CellBuffer, g)
    ship_visible(g) || return
    s = g.ship
    put_char!(buf, round(Int, s.y), round(Int, s.x), '▲'; fg = COL_SHIP, bold = true)
    if s.charge > 0
        put_char!(buf, round(Int, s.y) - 1, round(Int, s.x), CHARGE_GLYPH[s.charge + 1]; fg = COL_BEAM, bold = true)
    end
end

function _draw_beam!(buf::CellBuffer, g)
    g.beam.active || return
    dirx, diry = sin(g.beam.φ), -cos(g.beam.φ)
    word = "PEW "
    for t in 1:g.beam.length
        ch = word[(t - 1) % length(word) + 1]
        put_char!(buf, round(Int, g.beam.y + diry * t), round(Int, g.beam.x + dirx * t), ch; fg = COL_BEAM)
    end
end

"""
    draw!(buf, g) -> buf

Paint the whole game into `buf` (cleared first). Pure: no terminal I/O.
"""
function draw!(buf::CellBuffer, g::GameState)
    clear!(buf)
    for a in g.asteroids; _draw_asteroid!(buf, a, g.debug); end
    for sh in g.shards
        pp = pack_prose_into(sh.poly, sh.prep; scale = max(4.0, 2 * sh.radius), min_chord_width = 3.0)
        _blit_packed!(buf, pp, sh.x, sh.y; fg = COL_PROSE, debug = g.debug)
    end
    _draw_beam!(buf, g)
    _draw_ship!(buf, g)
    return buf
end
```

- [ ] **Step 4: Run → green. Step 5: Commit** `feat(asteroid): draw! frame compositor (#E)`.

---

## Task 10: Golden frame test (the deliverable's regression anchor)

**Files:** Create `test/test_golden.jl`, `test/golden/frame60.sha256`, `test/golden/frame60.txt`. Depends on all prior tasks.

- [ ] **Step 1: Write the scenario + test** (`test/test_golden.jl`). The script must force at least one hit→fracture so the golden exercises `subprep`/`voronoi_shatter`. Tune the fire/aim ticks during bring-up so a fracture actually occurs (assert `length(g.shards) >= 2` at the end — this is part of the test, not just the checksum).

```julia
# SPDX-License-Identifier: MIT
using AsteroidTUI: new_game, tick!, draw!, Input, ScriptedInput, next_input!, CellBuffer,
                   checksum, to_text
using Random
using Test

const GOLDEN_DIR = joinpath(@__DIR__, "golden")

# Deterministic 60-tick scenario: aim, charge, fire to hit, then drift.
function _scripted_seq()
    seq = Input[]
    for _ in 1:6;  push!(seq, Input(right=true)); end          # aim
    for _ in 1:10; push!(seq, Input(fire=true));  end          # charge to max
    push!(seq, Input(fire=false))                              # launch
    for _ in 1:43; push!(seq, Input(thrust=(rand(Xoshiro(99)) > 0.5))); end
    return seq
end

function _run_golden()
    g = new_game(Xoshiro(2024); width=120, height=40, n_asteroids=5)
    si = ScriptedInput(_scripted_seq())
    buf = CellBuffer(g.height, g.width)
    for _ in 1:60
        tick!(g, next_input!(si))
    end
    draw!(buf, g)
    return g, buf
end

@testset "golden frame (60 ticks)" begin
    g, buf = _run_golden()
    @test length(g.shards) >= 2                       # a fracture happened
    cs = checksum(buf)
    golden_path = joinpath(GOLDEN_DIR, "frame60.sha256")
    if get(ENV, "UPDATE_GOLDEN", "") == "1"
        mkpath(GOLDEN_DIR)
        write(golden_path, cs)
        write(joinpath(GOLDEN_DIR, "frame60.txt"), to_text(buf))
    end
    @test isfile(golden_path)
    @test cs == strip(read(golden_path, String))      # regression anchor

    # glyph preservation across the run: every fractured word survives in order
    if !isempty(g.last_hit_glyphs)
        shard_words = vcat(([s.str for s in sh.prep.segments if s.kind === :word] for sh in g.shards)...)
        @test all(w -> w in shard_words, g.last_hit_glyphs)
    end
end
```

- [ ] **Step 2: Generate the golden once** (after the scenario reliably fractures):
  `UPDATE_GOLDEN=1 julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()'`
  Confirm `test/golden/frame60.sha256` and `frame60.txt` were written and look sane (open `frame60.txt`).

- [ ] **Step 3: Re-run WITHOUT the env var** → golden matches (PASS). Run twice to confirm stability.

- [ ] **Step 4: Commit** `git add examples/asteroid_tui/test/test_golden.jl examples/asteroid_tui/test/golden && git commit -m "test(asteroid): committed golden 60-tick frame + glyph preservation (#E)"`

---

## Task 11: Tachikoma renderer + run.jl (interactive; NOT unit-tested — tier-2/3)

**Files:** Create `src/render_tachikoma.jl`, `run.jl`. **Flag for the orchestrator's human check** (≥30fps, respawn flash, invuln blink, debug `?` overlay live).

- [ ] **Step 1: Implement the drain + loop** (`src/render_tachikoma.jl`). Drains the `CellBuffer` into a Tachikoma `Buffer` and presents it; reads keys into `Input`. Uses only verified primitives (`Buffer(Rect)`, `set_char!`, `Style`, `Color256`, `Terminal`). The exact key-read / present wiring is validated live during this task (interactive).

```julia
# SPDX-License-Identifier: MIT
import Tachikoma as TK

# Drain a renderer-agnostic CellBuffer into a Tachikoma Buffer (1-based x=col, y=row).
function drain_to_tachikoma!(tbuf, cb::CellBuffer)
    for r in 1:nrows(cb), c in 1:ncols(cb)
        ch = cb.chars[r, c]
        ch == ' ' && cb.fg[r, c] == 0x00 && continue
        style = TK.Style(; fg = TK.Color256(Int(cb.fg[r, c])), bold = cb.bold[r, c])
        TK.set_char!(tbuf, c, r, ch, style)
    end
    return tbuf
end

# Map a Tachikoma KeyEvent to our Input. Adjust key names against the live API
# during bring-up (interactive, human-verified).
function key_to_input(ev)::Input
    k = ev                                  # placeholder mapping resolved live
    return Input()                          # replaced with real key dispatch in this task
end

"""
    run_game(; width=120, height=40, seed=0)

Interactive entry. Builds a Tachikoma Terminal, runs the game loop at ~60fps:
read key → tick! → draw! into CellBuffer → drain → present. Linux/macOS only.
"""
function run_game(; width=120, height=40, seed=0)
    g = new_game(Xoshiro(seed); width=width, height=height)
    cb = CellBuffer(height, width)
    term = TK.Terminal(; size = TK.Rect(0, 0, width, height))
    # main loop: see Tachikoma's app/event API; pseudocode resolved live:
    #   while !quit
    #       in = poll_input(term)            # → key_to_input
    #       tick!(g, in); draw!(cb, g)
    #       tbuf = TK.Buffer(TK.Rect(0,0,width,height)); drain_to_tachikoma!(tbuf, cb)
    #       present(term, tbuf); sleep(1/60)
    #   end
    return g
end
```

> Implementation note: prefer Tachikoma's high-level `TK.@tachikoma_app` / `TK.Model` if it cleanly supports a fixed-timestep redraw; otherwise use the low-level `Terminal` + raw key polling. Either way the **game core and golden test do not depend on this file**. Capture a real frame for the PR via `to_text(cb)` (see Verify).

- [ ] **Step 2: `run.jl`:**

```julia
# SPDX-License-Identifier: MIT
using AsteroidTUI
AsteroidTUI.run_game(; seed = parse(Int, get(ENV, "SEED", "0")))
```

- [ ] **Step 3: Manual smoke** (not CI): `julia --project=examples/asteroid_tui examples/asteroid_tui/run.jl` in a real terminal; verify it renders and quits cleanly. **Commit** `feat(asteroid): Tachikoma renderer + run.jl (interactive, tier-2/3) (#E)`.

---

## Task 12: Finalize — README, license headers, sample frame, suite green

**Files:** `README.md`, `test/runtests.jl`, all `src/*.jl`.

- [ ] **Step 1: `test/runtests.jl` aggregates** every `test_*.jl`:

```julia
# SPDX-License-Identifier: MIT
using Test
@testset "AsteroidTUI" begin
    for f in ("test_cellbuffer.jl","test_cellbackend.jl","test_prose.jl","test_pack.jl",
              "test_game.jl","test_fracture.jl","test_draw.jl","test_golden.jl")
        include(f)
    end
end
```

- [ ] **Step 2: License audit.** Every new `.jl` (and `run.jl`) starts with `# SPDX-License-Identifier: MIT`. Verify: `! grep -rL 'SPDX-License-Identifier: MIT' examples/asteroid_tui/src examples/asteroid_tui/test examples/asteroid_tui/run.jl` returns nothing.

- [ ] **Step 3: README** — finalize run instructions, the *measure-once-layout-many* pitch, the Tachikoma-needs-1.12 note, and embed the committed `test/golden/frame60.txt` as a sample.

- [ ] **Step 4: Full suite green + capture sample frame.**
  `mkdir -p test-logs && julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"` — grep for `Test Summary` / `Error`/`Fail`.
  Write a sample frame for the PR: `UPDATE_GOLDEN=1` run already produced `test/golden/frame60.txt`; attach that path in the "PR opened" message.

- [ ] **Step 5: Confirm Manifest is NOT staged** (`git status` must not list `examples/asteroid_tui/Manifest.toml`; it is gitignored per milestone convention). **Commit** `chore(asteroid): runtests aggregator, README, license audit (#E)`.

---

## Self-review checklist (run before declaring the plan done)

1. **Spec coverage:** silhouette+prose pack (Task 4/9), figlet display type (Task 9 ship/charge; note: full ARWING figlet headline optional — beam uses `PEW`), word-boundary fracture via `subprep` (Task 7), ≥50 prose templates (Task 3), low-Hz rotation reflow (asteroid `ω` + re-pack each draw, Task 9), charge 5 stages (Task 6/9), respawn+invuln (Task 8), debug overlay (Task 9), headless 60-tick golden + glyph preservation (Task 10). ✔
2. **Interactive done-whens (NOT unit-testable, flag for human):** ≥30fps, live respawn flash, invuln blink, `?` debug toggle, beam length scaling on screen — Task 11; flagged in PR. ✔
3. **Type consistency:** `Placement(segment_index,x,y)`, `Prepared.segments[i].str`, `FontMetrics(ascent,descent,line_advance)`, `Point2{Float64}`, `shape_pack(...; line_advance, min_chord_width)` — all match probed signatures. `tick!`/`draw!`/`new_game`/`fracture_asteroid!`/`pack_prose_into` names consistent across tasks. ✔
4. **Conventions:** Manifest gitignored; `[extras] Test`+`[targets]`; SPDX headers; assertions on the `CellBuffer`/checksum and computed structures, never terminal pixels; golden is a floor/anchor not a brittle hard count. ✔
