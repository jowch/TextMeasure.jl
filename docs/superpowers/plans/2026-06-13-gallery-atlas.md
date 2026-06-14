# The Atlas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Work in the worktree `/home/jonathanchen/projects/TextMeasure.jl-gallery`. Implement tasks in order; **Task 1 gates everything** (it proves the riskiest unknown). Do NOT skip a FAIL run — the failing run is the proof the test is real.

**Goal:** Build "The Atlas" gallery piece (register: **place**) — a recorded, seamless-loop zoom dive from the whole Central California coast into the Cambria–Morro Bay–SLO–Pismo town necklace, where every place-label is *measured* render-free by TextMeasure.jl and *re-placed live every frame* by MakieTextRepel.jl's deterministic `ProjectionSolver`, warm-started by the prior frame's offsets so settled labels hold collision-free. The hero is the gap-perfect fixed-pitch lattice of Plex-Mono necklace labels kissing edge-to-edge.

**Architecture:** A self-contained demo under `examples/atlas/`. Three honest layers (say it in the caption): (1) **TextMeasure.jl** measures each label box (`MakieBackend(px_per_unit=1)` → `prepare` → `layout`, pixel-exact, no kerning); (2) **MakieTextRepel.jl internals** — `solve_cluster(ProjectionSolver(params), anchors, sizes, bounds; init_state, pin_mask, pinned_offsets)` — do zero-overlap placement (Imhof seed → `side_select` → legalize); (3) **new demo code** drafts the per-frame *warm-start* solve (prior offsets fed as `init_state`, keyed by stable `town_id`), computes overlaps/dropped itself (the recipe surfaces only `computed_offsets`/`computed_dropped`; `solve_stats`/overlaps are `TextRepelAlgorithm`-only, off the path), gates labels by level-of-detail with hysteresis, fades newcomers in, drives the geometric-zoom camera, and renders the basemap + labels in the Swiss/Vignelli house style via `CairoMakie.record`. The warm-start input is to be **upstreamed into MakieTextRepel later** (its `TextRepelAlgorithm` already threads `reset=false` → prior offsets as `init_state`; the recipe is the missing surface), then the demo swaps to the public API. No glyph rotation — all labels horizontal (Imhof convention).

**Tech Stack:** Julia 1.11+; `CairoMakie`/`Makie` 0.24 (`record`, `Axis`, `text!`/`linesegments!`/`scatter!`/`poly!`, `markerspace=:pixel`); `MakieTextRepel` (the user's own unregistered MIT package — handled as a `[sources]` path dep, see Task 0); `GeoJSON`/`GeoInterface` + `CSV` for basemap data; `HouseStyle` (shared spine, `examples/_housestyle`) for palette/ramp/fonts/footer/`digest_rows`; `TextMeasure` (this repo, by `[sources]` path). Golden = `digest_rows` over a machine-robust per-frame placement table (`town_id, slot, relative-offset, alpha_q, has_leader`) at 6 sampled frames; the MP4 is a gitignored build artifact.

**Shared foundation (depend, don't rebuild):** `HouseStyle` at `examples/_housestyle` (uuid `f1a9b3c2-0d4e-4a6b-9c8d-7e2f1a0b3c4d`) → `PAPER`/`INK`/`BRASS`/`BRASS_INK`/`BLUE`/`GREEN`/`RED`/`GRAY`, `RAMP` (`caption=9, body=11, subhead=16, title=22, deck=31, display=44`), `fraunces(name)`, `plexmono(name="Regular")`, `footer(piece)`, `digest_rows(rows)`. The two Atlas-only water colours (`WATER_FILL = #DCE3E5`, `WATER_HAIRLINE = #9FB2BA`) are a deviation NOT in HouseStyle — define them **locally** in the Atlas module. Fonts live at `examples/fonts/{Fraunces,IBMPlexMono}/` (pinned by the Foundation plan's Task 1). The Foundation plan (`docs/superpowers/plans/2026-06-13-gallery-foundation.md`) must be implemented first — this plan assumes `examples/_housestyle` and `examples/fonts/` exist.

**Internal MakieTextRepel API (verified against `/tmp/MakieTextRepel.jl/src/`, do NOT invent):**
- `MakieTextRepel.ProjectionSolver(params::RepelParams)` — RNG-free except a seed-pinned Delaunay triangulator; deterministic.
- `MakieTextRepel.RepelParams(; only_move, box_padding, point_padding, min_segment_length, max_overlaps, …)` — `Base.@kwdef`; `point_padding` default `0.0` (primitive surface; user surfaces default `5.0`).
- `MakieTextRepel.solve_cluster(s::ProjectionSolver, anchors::Vector{Point2f}, sizes::Vector{Vec2f}, bounds::Rect2f; init_state::Union{Nothing,Vector{Vec2f}}=nothing, pin_mask::Union{Nothing,BitVector}=nothing, pinned_offsets::Vector{Vec2f}=Vec2f[], obstacles::Vector{Rect2f}=Rect2f[]) -> (; offsets::Vector{Vec2f}, dropped::BitVector, iter::Int, residual::Float32)`. `init_state===nothing` ⇒ FRESH (`initial_offsets` Imhof seed → `side_select` → crossing repair); a given `init_state` ⇒ WARM-START relax (legalize the given layout only).
- `MakieTextRepel.initial_offsets`, `MakieTextRepel.side_select`, `MakieTextRepel.IMHOF_ORDER` (`(:TR,:R,:T,:BR,:L,:BL,:B,:TL)`) — exist if a step needs them directly; the warm-start path goes through `solve_cluster`, which calls them internally.
- Geometry helpers for our OWN overlap recompute (Makie-free, GeometryBasics only, NOT exported — qualify them): `MakieTextRepel.box_at(anchor::Point2f, offset::Vec2f, size::Vec2f)::Rect2f`, `MakieTextRepel.overlap_push(a::Rect2f, b::Rect2f)::Vec2f` (zero iff disjoint), `MakieTextRepel.point_covered(p::Point2f, box::Rect2f, padding)::Bool`.
- Recipe-only (NOT on our path): `computed_offsets`/`computed_dropped` (recipe attrs); `solve_stats(::TextRepelAlgorithm)` / `overlaps` (algorithm-only). We compute overlaps/dropped ourselves from `offsets` + `sizes`.

---

### Task 0: Make MakieTextRepel available as a sibling path dep

**Why first:** MakieTextRepel is the user's own *unregistered* package. Its own `Project.toml` has `[sources] TextMeasure = {path = "../TextMeasure.jl"}` — it expects a TextMeasure checkout as a **sibling**. Our worktree is `TextMeasure.jl-gallery`, so we must (a) clone MakieTextRepel as a sibling of the worktree and (b) point ITS TextMeasure source at our gallery worktree, so MakieTextRepel and the Atlas piece resolve to the *same* TextMeasure. Without this, `Pkg.instantiate()` for `examples/atlas` cannot find MakieTextRepel.

**Files:**
- Clone (sibling of worktree): `/home/jonathanchen/projects/MakieTextRepel.jl/`
- Modify: `/home/jonathanchen/projects/MakieTextRepel.jl/Project.toml` (repoint its TextMeasure `[sources]`)

- [ ] **Step 1: Clone MakieTextRepel as a sibling of the worktree**

Run (from anywhere):
```bash
cd /home/jonathanchen/projects && \
  test -d MakieTextRepel.jl || git clone https://github.com/jowch/MakieTextRepel.jl MakieTextRepel.jl && \
  ls /home/jonathanchen/projects/MakieTextRepel.jl/src/solvers/projection.jl
```
Expected: prints `/home/jonathanchen/projects/MakieTextRepel.jl/src/solvers/projection.jl` (clone present; the internal solver file we depend on exists). If the clone already exists, the `test -d` short-circuits and the `ls` still confirms the file.

- [ ] **Step 2: Repoint MakieTextRepel's TextMeasure source at the gallery worktree**

MakieTextRepel's `[sources]` line is `TextMeasure = {path = "../TextMeasure.jl"}`. The Atlas piece (Task 1) resolves TextMeasure to the gallery worktree `../../` = `/home/jonathanchen/projects/TextMeasure.jl-gallery`. To keep ONE TextMeasure in the dependency graph, edit `/home/jonathanchen/projects/MakieTextRepel.jl/Project.toml` so its source points at the gallery worktree.

Use the Edit tool to change in `/home/jonathanchen/projects/MakieTextRepel.jl/Project.toml`:
```toml
TextMeasure = {path = "../TextMeasure.jl"}
```
to:
```toml
TextMeasure = {path = "../TextMeasure.jl-gallery"}
```

- [ ] **Step 3: Verify the repointed path resolves**

Run:
```bash
grep TextMeasure /home/jonathanchen/projects/MakieTextRepel.jl/Project.toml && \
  ls /home/jonathanchen/projects/TextMeasure.jl-gallery/Project.toml
```
Expected: the `[sources]` line shows `path = "../TextMeasure.jl-gallery"`, and the second `ls` prints the gallery `Project.toml` path (the sibling-relative target exists). NOTE: this edit is to a clone *outside* the worktree — it is NOT committed by this plan; document it in `examples/atlas/README.md` (Task 9) so a fresh machine reproduces it.

---

### Task 1: The warm-start solve stub — the gate (riskiest first)

**Why first:** This proves the three things the whole piece rests on: (a) a **deterministic re-solve** under `record`, (b) **warm-start** via prior offsets keyed by `town_id` so settled labels HOLD (zero motion when still clear), and (c) **golden-table stability** on a machine-robust key (`town_id` + slot/**relative** offset, NOT absolute projected px — projected px carries accumulated float error at zoom extremes and is machine-sensitive). It also resolves the §8 riskiest unknown: that `px_anchors` reflect frame *k*'s limits before we read them (explicit `Makie.update_state_before_display!`). If warm-start does not hold settled labels, we learn it here on a 5-line stub, not after the basemap is built.

This task builds a **standalone stub script** (`examples/atlas/stub_warmstart.jl`) and a test asserting its invariants. The stub solves a tiny fixed cluster across 3 synthetic "frames" (no real camera yet — synthetic anchors that drift slightly), warm-starting each frame from the prior, keyed by `town_id`.

**Files:**
- Create: `examples/atlas/Project.toml`
- Create: `examples/atlas/src/Atlas.jl` (module shell + the warm-start wrapper)
- Create: `examples/atlas/stub_warmstart.jl`
- Create: `examples/atlas/test/runtests.jl`
- Create: `examples/atlas/test/test_warmstart.jl`

- [ ] **Step 1: Write the Atlas Project.toml**

Create `examples/atlas/Project.toml` (mirrors `examples/layouts/Project.toml`'s `[sources]` pattern; HouseStyle + MakieTextRepel + TextMeasure are path deps; the rest are registered):
```toml
name = "TextMeasureAtlas"
uuid = "a71a5c0d-3b2e-4f1a-9c7d-2e6b8f0a14d3"
version = "0.1.0"
authors = ["TextMeasure.jl contributors"]

[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
GeoInterface = "cf35fbd7-0cd7-5166-be24-54bfbe79505f"
GeoJSON = "61d90e0f-e114-555e-ac52-39dfb47a3ef9"
GeometryBasics = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
HouseStyle = "f1a9b3c2-0d4e-4a6b-9c8d-7e2f1a0b3c4d"
Makie = "ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a"
MakieTextRepel = "2348ae4b-e21f-48c0-a77f-52990745b802"
TextMeasure = "06791c1d-2336-41e1-bd6f-a74c63395da6"

# Unregistered in-repo / sibling packages resolved by path (Julia 1.11 [sources]).
[sources]
HouseStyle = { path = "../_housestyle" }
TextMeasure = { path = "../.." }
MakieTextRepel = { path = "../../../MakieTextRepel.jl" }

[compat]
GeometryBasics = "0.5"
Makie = "0.24"
julia = "1.11"

[extras]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Test"]
```
NOTE: `MakieTextRepel` path is `../../../MakieTextRepel.jl` — from `examples/atlas/` that is `examples/atlas → examples → TextMeasure.jl-gallery → projects/MakieTextRepel.jl`, the sibling cloned in Task 0.

- [ ] **Step 2: Write the failing test**

Create `examples/atlas/test/test_warmstart.jl`:
```julia
using Test
using GeometryBasics: Point2f, Vec2f, Rect2f
include(joinpath(@__DIR__, "..", "src", "Atlas.jl"))
using .Atlas

@testset "warm-start solve stub" begin
    # Tiny fixed cluster: 3 towns, stable ids :a :b :c. Sizes are measured boxes (w,h) px.
    ids   = [:a, :b, :c]
    sizes = Dict(:a => Vec2f(60, 12), :b => Vec2f(80, 12), :c => Vec2f(50, 12))
    bounds = Rect2f(0, 0, 400, 300)

    # Frame 0 anchors, and frame 1 = frame 0 shifted by a tiny pan (settled labels should hold).
    anch0 = Dict(:a => Point2f(100, 150), :b => Point2f(200, 150), :c => Point2f(300, 150))
    anch1 = Dict(id => Point2f(p .+ Point2f(1.0, 0.0)) for (id, p) in anch0)  # 1px pan

    # (a) deterministic: same inputs twice ⇒ identical offsets.
    r0a = Atlas.solve_frame(ids, anch0, sizes, bounds; prev=Dict{Symbol,Vec2f}())
    r0b = Atlas.solve_frame(ids, anch0, sizes, bounds; prev=Dict{Symbol,Vec2f}())
    @test r0a.offsets == r0b.offsets

    # (b) warm-start holds: feed frame-0 offsets as prev; offsets must barely move (< 3px each).
    r1 = Atlas.solve_frame(ids, anch1, sizes, bounds; prev=r0a.offsets)
    for id in ids
        @test sum(abs2, r1.offsets[id] .- r0a.offsets[id]) < 9.0   # held within 3px
    end

    # (c) our own overlap recompute is zero (collision-free), and no drops.
    @test Atlas.count_overlaps(ids, anch1, sizes, r1.offsets) == 0
    @test isempty(r1.dropped_ids)

    # (d) golden-table stability: row key is (town_id, slot, RELATIVE offset 2dp, …),
    #     NOT absolute projected px. Same solve ⇒ same digest.
    g0a = Atlas.frame_digest(r0a, ids, sizes)
    g0b = Atlas.frame_digest(r0b, ids, sizes)
    @test g0a == g0b
    @test length(g0a) == 64                       # sha256 hex via HouseStyle.digest_rows
end
```

- [ ] **Step 3: Write the runtests aggregator**

Create `examples/atlas/test/runtests.jl`:
```julia
using Test
@testset "Atlas" begin
    include("test_warmstart.jl")
end
```

- [ ] **Step 4: Write the minimal Atlas module with the warm-start wrapper**

Create `examples/atlas/src/Atlas.jl`. This is the real wrapper, keyed by `town_id`, calling `solve_cluster` with `init_state` built from `prev`; `nothing` per-label when a town is new. Overlap recompute uses `MakieTextRepel.box_at`/`overlap_push`. `frame_digest` uses `HouseStyle.digest_rows` on the machine-robust key. Slot is the nearest Imhof slot to the final relative offset (see `infer_slot`).
```julia
module Atlas

using GeometryBasics: Point2f, Vec2f, Rect2f
using MakieTextRepel: ProjectionSolver, RepelParams, solve_cluster, IMHOF_ORDER
import MakieTextRepel
using HouseStyle: digest_rows

# Atlas-local water colours (deviation NOT in HouseStyle — see SPEC §7).
const WATER_FILL     = "#DCE3E5"
const WATER_HAIRLINE = "#9FB2BA"

const PARAMS = RepelParams(; only_move = :both, box_padding = 4.0,
                             point_padding = 5.0, min_segment_length = 2.0)
const SOLVER = ProjectionSolver(PARAMS)

"""
    solve_frame(ids, anchors, sizes, bounds; prev) -> (; offsets, dropped_ids)

Warm-start solve for one frame. `ids` is a Vector of stable town_ids (Symbols).
`anchors`/`sizes` are `Dict{id => Point2f/Vec2f}` (projected px / measured boxes).
`prev` is `Dict{id => Vec2f}` of the PRIOR frame's offsets — a town absent from
`prev` is new, seeded fresh (its `init_state` entry stays `nothing`).
We key by id, never vector index. `offsets` returned as `Dict{id => Vec2f}`.
"""
function solve_frame(ids::Vector{Symbol},
                     anchors::Dict{Symbol,Point2f},
                     sizes::Dict{Symbol,Vec2f},
                     bounds::Rect2f;
                     prev::Dict{Symbol,Vec2f})
    n = length(ids)
    anch = Point2f[anchors[id] for id in ids]
    sz   = Vec2f[sizes[id] for id in ids]
    # Warm start: prior offset per id, else 0 with a per-label "is new" flag.
    have_prev = all(haskey(prev, id) for id in ids)
    init = have_prev ? Vec2f[prev[id] for id in ids] : nothing
    r = solve_cluster(SOLVER, anch, sz, bounds; init_state = init)
    offs = Dict{Symbol,Vec2f}(id => r.offsets[k] for (k, id) in enumerate(ids))
    dropped_ids = Symbol[ids[k] for k in 1:n if r.dropped[k]]
    return (; offsets = offs, dropped_ids = dropped_ids)
end

"Count label–label box overlaps using MakieTextRepel's own geometry (deterministic)."
function count_overlaps(ids, anchors::Dict, sizes::Dict, offsets::Dict)
    boxes = [MakieTextRepel.box_at(anchors[id], offsets[id], sizes[id]) for id in ids]
    c = 0
    for i in 1:length(boxes), j in (i+1):length(boxes)
        (MakieTextRepel.overlap_push(boxes[i], boxes[j]) != Vec2f(0, 0)) && (c += 1)
    end
    return c
end

"Nearest Imhof slot (index 0..7 over IMHOF_ORDER) to a relative offset — machine-robust key."
function infer_slot(offset::Vec2f)
    # Quadrant/edge classification from the sign + dominance of the offset.
    x, y = offset[1], offset[2]
    ax, ay = abs(x), abs(y)
    slot = if ax < 1 && ay < 1
        :TR
    elseif ax >= ay
        x >= 0 ? (y >= 1 ? :TR : (y <= -1 ? :BR : :R)) : (y >= 1 ? :TL : (y <= -1 ? :BL : :L))
    else
        y >= 0 ? :T : :B
    end
    return findfirst(==(slot), IMHOF_ORDER) - 1
end

"""
    frame_digest(r, ids, sizes) -> 64-char sha256 hex

Golden key = sorted rows of `town_id | slot_index | rel_off_x(2dp) | rel_off_y(2dp)`.
RELATIVE offset (label-center − anchor), NOT absolute projected px — stable across
machines. Delegates hashing to `HouseStyle.digest_rows` (sorts internally).
"""
function frame_digest(r, ids::Vector{Symbol}, sizes::Dict)
    rows = String[]
    for id in ids
        o = r.offsets[id]
        push!(rows, string(id, "|", infer_slot(o), "|",
                           round(o[1]; digits = 2), "|", round(o[2]; digits = 2)))
    end
    return digest_rows(rows)
end

end # module Atlas
```

- [ ] **Step 5: Run the test to verify it FAILS (deps not yet instantiated / stub not exercised under record)**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.instantiate()' 2>&1 | tail -5
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -20
```
Expected on the FIRST authoring pass (before the module is correct): a FAIL/error — e.g. `UndefVarError: solve_frame not defined` or a `DimensionMismatch`/overlap assertion. (If you wrote Step 4 verbatim it may pass immediately; in that case introduce the test FIRST with the module absent to see the `UndefVarError`, then add the module — TDD discipline: the failing run must be observed.)

- [ ] **Step 6: Make it pass**

With the module from Step 4 in place, run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -20
```
Expected: `Test Summary: | Pass 6` (or more) — warm-start holds, deterministic, overlaps==0, digest stable & 64 hex chars.

- [ ] **Step 7: Verify per-frame reactive-solve timing under `record` on the stub**

Create `examples/atlas/stub_warmstart.jl` — a 3-frame `record` over a real `Axis` whose limits change each frame, reading `px_anchors` AFTER `Makie.update_state_before_display!`, proving frame *k* sees frame *k*'s view (the §8 riskiest unknown):
```julia
# Run: julia --project=examples/atlas examples/atlas/stub_warmstart.jl
using CairoMakie, GeometryBasics, Makie
include(joinpath(@__DIR__, "src", "Atlas.jl")); using .Atlas

ids   = [:a, :b, :c]
sizes = Dict(:a => Vec2f(60,12), :b => Vec2f(80,12), :c => Vec2f(50,12))
# Three data anchors; we zoom the axis a little each frame and re-read pixel anchors.
data_pos = Dict(:a => Point2f(-121.0, 35.5), :b => Point2f(-120.8, 35.4), :c => Point2f(-120.6, 35.3))

fig = Figure(size = (640, 480))
ax  = Axis(fig[1,1]); hidedecorations!(ax); hidespines!(ax)
sc  = scatter!(ax, [data_pos[id] for id in ids]; markersize = 8)

prev = Dict{Symbol,Vec2f}()
mktempdir() do dir
    mp4 = joinpath(dir, "stub.mp4")
    widths = [3.0, 1.5, 0.7]
    record(fig, mp4, 1:3; framerate = 1) do frame
        w = widths[frame]
        limits!(ax, -121.0 - w/2, -121.0 + w/2, 35.4 - w/2, 35.4 + w/2)
        Makie.update_state_before_display!(fig)        # px anchors now reflect THIS frame's view
        # project data → pixel for each id, this frame:
        px = Dict(id => Point2f(Makie.project(ax.scene, data_pos[id])) for id in ids)
        bounds = Rect2f(0, 0, 640, 480)
        r = Atlas.solve_frame(ids, px, sizes, bounds; prev = prev)
        global prev = r.offsets
        @assert Atlas.count_overlaps(ids, px, sizes, r.offsets) == 0 "overlap at frame $frame"
        println("frame $frame  w=$w  digest=", Atlas.frame_digest(r, ids, sizes)[1:12])
    end
    @assert isfile(mp4) "record produced no mp4"
    println("OK: 3-frame record, per-frame solve, no overlaps, mp4 written")
end
```
Run:
```bash
julia --project=examples/atlas examples/atlas/stub_warmstart.jl 2>&1 | tail -6
```
Expected: three `frame N w=… digest=…` lines (digests differ as the view zooms, confirming px anchors update per frame) then `OK: 3-frame record, …`. If you see `overlap at frame N`, the timing is wrong — the `update_state_before_display!` placement or the `project` call is reading stale limits; fix before proceeding (this is the gate).

- [ ] **Step 8: Commit**

```bash
git add examples/atlas/Project.toml examples/atlas/src/Atlas.jl examples/atlas/stub_warmstart.jl examples/atlas/test
git commit -m "feat(atlas): warm-start solve stub on MakieTextRepel internals (deterministic, held, golden-stable)"
```

---

### Task 2: Basemap data — clip Natural Earth + curate towns.csv

**Why now:** the solve gate passed; everything downstream needs committed, hermetic data. Ship clipped 10m coast/land (PD) + a source-tagged `towns.csv` + `SOURCE.txt` under `examples/atlas/data/` (<65 KB total). A one-time `prep/clip.jl` produces the geojson; the demo only reads committed files, never fetches.

**Files:**
- Create: `examples/atlas/prep/clip.jl`
- Create (artifacts, committed): `examples/atlas/data/coastline.geojson`, `examples/atlas/data/land.geojson`, `examples/atlas/data/towns.csv`, `examples/atlas/data/SOURCE.txt`
- Create: `examples/atlas/test/test_data.jl`; Modify: `examples/atlas/test/runtests.jl`

- [ ] **Step 1: Write the failing test**

Create `examples/atlas/test/test_data.jl`:
```julia
using Test, CSV, GeoJSON, GeoInterface

const DATA = joinpath(@__DIR__, "..", "data")

@testset "basemap data is committed & well-formed" begin
    @test isfile(joinpath(DATA, "coastline.geojson"))
    @test isfile(joinpath(DATA, "land.geojson"))
    @test isfile(joinpath(DATA, "towns.csv"))
    @test isfile(joinpath(DATA, "SOURCE.txt"))

    coast = GeoJSON.read(read(joinpath(DATA, "coastline.geojson"), String))
    @test GeoInterface.isgeometry(GeoInterface.geometry(first(coast))) ||
          length(coast) >= 1                       # at least one clipped feature

    towns = CSV.File(joinpath(DATA, "towns.csv"))
    names = [r.name for r in towns]
    @test "San Luis Obispo" in names
    @test "Morro Bay" in names
    @test "Cambria" in names
    @test "Pismo Beach" in names
    @test count(r -> r.source == "NE", towns) == 8          # 8 verbatim NE rows
    @test count(r -> r.source == "curated", towns) >= 12    # ~15 hand-placed
    # bbox sanity: all towns inside the Central Coast window
    @test all(-122.0 <= r.lon <= -119.5 for r in towns)
    @test all( 34.5 <= r.lat <=  37.0 for r in towns)
end
```
Append `include("test_data.jl")` to `examples/atlas/test/runtests.jl`'s `@testset`.

- [ ] **Step 2: Run it to verify it FAILS**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -15
```
Expected: FAIL — `coastline.geojson` etc. do not exist (`isfile` false).

- [ ] **Step 3: Write the one-time clip script**

Create `examples/atlas/prep/clip.jl` (hardcoded bbox; fetches NE 10m from the committed-URL or a local NE checkout, clips, writes the small subsets). Document the source URLs inline. Keep it runnable but not part of the demo path:
```julia
# One-time prep: clip NE 1:10m coastline + land to the Central Coast bbox.
# Source: github.com/nvkelso/natural-earth-vector (PUBLIC DOMAIN, no attribution required).
#   ne_10m_coastline.geojson, ne_10m_land.geojson
# Run manually: julia --project=examples/atlas examples/atlas/prep/clip.jl /path/to/ne_10m
# Writes examples/atlas/data/{coastline,land}.geojson (clipped to BBOX).
using GeoJSON, GeoInterface

const BBOX = (lon = (-122.0, -119.5), lat = (34.5, 37.0))   # Central Coast window

# ... read source geojson, keep features intersecting BBOX, re-emit clipped geometry ...
# (Implementation: load via GeoJSON.read; filter rings/linestrings to the bbox;
#  GeoJSON.write the survivors. The exact clipping is a one-time data chore — the
#  demo never runs this. Verify output sizes are 15–30 KB each per SPEC §6.)
```
(The implementing agent fills in the clip body; it runs ONCE, by hand, against a local NE checkout. The committed artifacts are what matter.)

- [ ] **Step 4: Produce the committed artifacts**

Run the clip once (or hand-build the small subsets) so the four files exist under `examples/atlas/data/`. Then hand-author `towns.csv` with header `town_id,name,lon,lat,pop,rank,source` containing: the **8 verbatim NE in-bbox rows** (`source=NE`, exact NAME/lon/lat/POP_MAX/SCALERANK) + **~15 hand-placed coastal towns** (`source=curated`, lon/lat hand-entered, `pop`/`rank` ordinally correct for LoD priority), including the hero necklace San Luis Obispo / Morro Bay / Pismo Beach / Cambria / San Simeon / Los Osos / Avila Beach / Cayucos / Atascadero / Paso Robles / Lompoc / Santa Maria / Santa Barbara / Salinas / Monterey. `town_id` = a stable snake_case slug (e.g. `san_luis_obispo`). Write `SOURCE.txt` stating: coastline + land = NE 1:10m (PD); the 8 NE town rows verbatim; the rest hand-placed (`source` column keeps it honest).

Run a size check:
```bash
du -ch examples/atlas/data/* | tail -1
```
Expected: total `< 65K` (SPEC §6 budget).

- [ ] **Step 5: Run the test to verify it PASSES**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -15
```
Expected: PASS — data files present, 8 NE rows, ≥12 curated, hero towns present, bbox-sane.

- [ ] **Step 6: Commit**

```bash
git add examples/atlas/prep examples/atlas/data examples/atlas/test/test_data.jl examples/atlas/test/runtests.jl
git commit -m "feat(atlas): clip NE 10m basemap + curated source-tagged towns.csv (hermetic, <65KB)"
```

---

### Task 3: Projection + data loading (equirectangular + cosφ0 affine)

**Why now:** turn the committed lon/lat into the single `map-units` space the zoom animates over: plain equirectangular + a `cosφ0` x-correction (`φ0=35.7°`, `kx≈0.812`), applied once at load to coast/land/town coords. No GeoMakie.

**Files:**
- Modify: `examples/atlas/src/Atlas.jl` (add `project_xy`, `load_basemap`, `load_towns`)
- Create: `examples/atlas/test/test_projection.jl`; Modify: `examples/atlas/test/runtests.jl`

- [ ] **Step 1: Write the failing test**

Create `examples/atlas/test/test_projection.jl`:
```julia
using Test
include(joinpath(@__DIR__, "..", "src", "Atlas.jl")); using .Atlas

@testset "projection + loaders" begin
    # cosφ0 affine: x scaled by kx = cos(deg2rad(35.7)) ≈ 0.8121, y = lat passthrough.
    @test Atlas.KX ≈ cos(deg2rad(35.7)) atol = 1e-6
    x, y = Atlas.project_xy(-121.0, 35.5)
    @test x ≈ -121.0 * Atlas.KX atol = 1e-6
    @test y ≈ 35.5 atol = 1e-9
    # loaders return projected, ready-to-draw data
    towns = Atlas.load_towns()
    @test haskey(towns, :san_luis_obispo)
    slo = towns[:san_luis_obispo]
    @test slo.x ≈ slo.lon * Atlas.KX atol = 1e-6           # projected x
    bm = Atlas.load_basemap()
    @test length(bm.coast) >= 1                              # ≥1 projected polyline
    @test all(p -> length(p) == 2, first(bm.coast))         # each vertex is (x,y)
end
```
Append `include("test_projection.jl")` to the runtests `@testset`.

- [ ] **Step 2: Run it to verify it FAILS**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -15
```
Expected: FAIL — `Atlas.KX`/`project_xy`/`load_towns` undefined.

- [ ] **Step 3: Add the projection + loaders**

Add to `examples/atlas/src/Atlas.jl` (inside the module): `using CSV, GeoJSON, GeoInterface`; then:
```julia
const PHI0 = 35.7
const KX   = cos(deg2rad(PHI0))     # ≈ 0.8121 — x-correction

"Equirectangular + cosφ0 affine: lon/lat (deg) → map-units (x,y)."
project_xy(lon::Real, lat::Real) = (lon * KX, float(lat))

const DATA_DIR = normpath(joinpath(@__DIR__, "..", "data"))

"Load towns.csv → Dict{town_id => (; name, lon, lat, x, y, pop, rank, source)} (projected)."
function load_towns()
    out = Dict{Symbol,NamedTuple}()
    for r in CSV.File(joinpath(DATA_DIR, "towns.csv"))
        x, y = project_xy(r.lon, r.lat)
        out[Symbol(r.town_id)] = (; name = String(r.name), lon = float(r.lon), lat = float(r.lat),
                                    x = x, y = y, pop = Int(r.pop), rank = Int(r.rank),
                                    source = String(r.source))
    end
    return out
end

"Load + project coastline & land geojson → (; coast, land) as Vectors of Vector{Tuple{Float64,Float64}}."
function load_basemap()
    rd(file) = begin
        fc = GeoJSON.read(read(joinpath(DATA_DIR, file), String))
        polylines = Vector{Vector{Tuple{Float64,Float64}}}()
        for feat in fc
            geom = GeoInterface.geometry(feat)
            for ring in _rings(geom)
                push!(polylines, [project_xy(c[1], c[2]) for c in ring])
            end
        end
        polylines
    end
    return (; coast = rd("coastline.geojson"), land = rd("land.geojson"))
end

# Flatten any (Multi)LineString/(Multi)Polygon into coordinate rings.
function _rings(geom)
    t = GeoInterface.geomtrait(geom)
    if t isa GeoInterface.LineStringTrait
        return [GeoInterface.coordinates(geom)]
    elseif t isa GeoInterface.PolygonTrait
        return GeoInterface.coordinates(geom)
    else  # Multi*: recurse over sub-geometries
        rs = Vector{Vector}()
        for g in GeoInterface.getgeom(geom); append!(rs, _rings(g)); end
        return rs
    end
end
```
(If `GeoInterface.coordinates` shapes differ for your GeoJSON.jl version, adapt `_rings` to yield `[(lon,lat), …]` rings — the test asserts each projected vertex is a 2-tuple.)

- [ ] **Step 4: Run the test to verify it PASSES**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -15
```
Expected: PASS — KX correct, projected coords correct, loaders return projected data.

- [ ] **Step 5: Commit**

```bash
git add examples/atlas/src/Atlas.jl examples/atlas/test/test_projection.jl examples/atlas/test/runtests.jl
git commit -m "feat(atlas): equirectangular + cosφ0 projection and geojson/csv loaders"
```

---

### Task 4: LoD gating with hysteresis + label measurement

**Why now:** decide WHO is active each frame (importance vs view width `w`, on a `log(w)` ladder) with a hysteresis deadband (on at `w_on`, off at `1.08×w_on`) to kill boundary flicker, and MEASURE each active label's box via TextMeasure (`MakieBackend(px_per_unit=1)`).

**Files:**
- Modify: `examples/atlas/src/Atlas.jl` (`measure_town`, `active_ids` with hysteresis state)
- Create: `examples/atlas/test/test_lod.jl`; Modify: `examples/atlas/test/runtests.jl`

- [ ] **Step 1: Write the failing test**

Create `examples/atlas/test/test_lod.jl`:
```julia
using Test
using GeometryBasics: Vec2f
include(joinpath(@__DIR__, "..", "src", "Atlas.jl")); using .Atlas

@testset "label measurement (TextMeasure, render-free, exact)" begin
    sz = Atlas.measure_town("San Luis Obispo")
    @test sz isa Vec2f
    @test sz[1] > 0 && sz[2] > 0
    # Plex Mono is fixed-pitch: width is proportional to char count (the lattice property).
    w14 = Atlas.measure_town("San Luis Obispo")[1]    # 14 glyphs (incl spaces)
    w7  = Atlas.measure_town("Cambria")[1]            # 7 glyphs
    @test w14 / w7 ≈ 14/7 atol = 0.05                 # fixed-pitch ⇒ ~linear in length
end

@testset "LoD gating + hysteresis" begin
    towns = Atlas.load_towns()
    # Wide view (w=3.0°): only the rank≤5 majors are eligible.
    wide = Atlas.active_ids(towns, 3.0, Set{Symbol}())
    @test :san_luis_obispo in wide
    @test :cambria ∉ wide                              # below threshold when wide
    # Tight view (w=0.30°): the necklace lights up.
    tight = Atlas.active_ids(towns, 0.30, Set{Symbol}())
    @test :cambria in tight
    @test :morro_bay in tight
    # Hysteresis: a town ON at w_on stays ON until 1.08×w_on (deadband, no flicker).
    on_at = Atlas.w_on(towns[:cambria])
    just_above = on_at * 1.05                           # inside the deadband
    @test :cambria in Atlas.active_ids(towns, just_above, Set([:cambria]))   # held ON
    well_above = on_at * 1.20                           # past the deadband
    @test :cambria ∉ Atlas.active_ids(towns, well_above, Set([:cambria]))    # released
end
```
Append both includes to the runtests `@testset`.

- [ ] **Step 2: Run it to verify it FAILS**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -20
```
Expected: FAIL — `measure_town`/`active_ids`/`w_on` undefined.

- [ ] **Step 3: Add measurement + LoD gating**

Add to `examples/atlas/src/Atlas.jl`: `import TextMeasure; using HouseStyle: plexmono`; then:
```julia
const LABEL_FONT = plexmono("Regular")
const LABEL_SIZE = 11.0                         # RAMP.body — the necklace face

"Measure a town label box (px) via TextMeasure, render-free, px_per_unit=1 (pixel-exact)."
function measure_town(name::AbstractString)
    backend = TextMeasure.MakieBackend(; font = LABEL_FONT, fontsize = LABEL_SIZE, px_per_unit = 1.0)
    lay = TextMeasure.layout(TextMeasure.prepare(backend, String(name)))
    return Vec2f(lay.size[1], lay.size[2])
end

"View width (deg) at which a town switches ON — smaller rank / bigger pop ⇒ ON sooner (wider)."
function w_on(t)
    # Monotone log(w) ladder by rank: rank 1 (majors) on at 3.0°, descending to 0.30°.
    # rank ∈ 1..9 → w_on ∈ [3.0, 0.30] geometrically.
    r = clamp(t.rank, 1, 9)
    return exp(((9 - r) / 8) * log(0.30) + ((r - 1) / 8) * log(3.0))
end

"""
    active_ids(towns, w, prev_active) -> Set{Symbol}

Active set at view width `w` with hysteresis: a town is ON when `w <= w_on`; once ON
(in `prev_active`) it stays ON until `w > 1.08 * w_on` (deadband kills flicker).
"""
function active_ids(towns::Dict, w::Real, prev_active::Set{Symbol})
    out = Set{Symbol}()
    for (id, t) in towns
        won = w_on(t)
        was = id in prev_active
        thresh = was ? 1.08 * won : won
        (w <= thresh) && push!(out, id)
    end
    return out
end
```
(Tune the `w_on` ladder constants so the SPEC §3 table holds: SLO/Santa Maria/Santa Barbara/Salinas/Monterey by 1.5°; +Morro Bay/Pismo/Atascadero/Paso Robles/Lompoc by 0.7°; +Cambria/San Simeon/Los Osos/Avila/Cayucos by 0.30°. Set each town's `rank` in towns.csv to land it in the right band.)

- [ ] **Step 4: Run the test to verify it PASSES**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -20
```
Expected: PASS — measurement is fixed-pitch-linear, wide shows only majors, tight lights the necklace, hysteresis deadband holds then releases.

- [ ] **Step 5: Commit**

```bash
git add examples/atlas/src/Atlas.jl examples/atlas/test/test_lod.jl examples/atlas/test/runtests.jl
git commit -m "feat(atlas): TextMeasure label boxes + LoD gating with hysteresis deadband"
```

---

### Task 5: Camera path (geometric zoom + smoothstep ease, seamless loop)

**Why now:** the dive choreography — interpolate `log(width)` (van Wijk constant perceived velocity), wrapped in `smoothstep` per half so velocity is zero at start/apex/end and the loop closes position- *and* velocity-continuous. 12 s · 30 fps · 360 frames; frame 360 ≡ 0.

**Files:**
- Modify: `examples/atlas/src/Atlas.jl` (`camera_at`)
- Create: `examples/atlas/test/test_camera.jl`; Modify: `examples/atlas/test/runtests.jl`

- [ ] **Step 1: Write the failing test**

Create `examples/atlas/test/test_camera.jl`:
```julia
using Test
include(joinpath(@__DIR__, "..", "src", "Atlas.jl")); using .Atlas

@testset "camera path: geometric zoom, smoothstep, seamless loop" begin
    c0   = Atlas.camera_at(0)
    c180 = Atlas.camera_at(180)          # apex
    c360 = Atlas.camera_at(360)          # ≡ frame 0
    @test c0.w ≈ 3.0  atol = 1e-6        # wide ends
    @test c180.w ≈ 0.30 atol = 1e-6      # tight apex
    @test c0.cx ≈ c360.cx atol = 1e-9 && c0.cy ≈ c360.cy atol = 1e-9   # loop closes (position)
    @test c0.w ≈ c360.w atol = 1e-9
    # geometric: midpoint of log(width) between two frames is the log of interpolated width
    # velocity zero at seam: frames 1 and 359 are near-symmetric, tiny |Δw| at the ends.
    d_seam = abs(Atlas.camera_at(1).w - Atlas.camera_at(0).w)
    d_mid  = abs(Atlas.camera_at(91).w - Atlas.camera_at(90).w)
    @test d_seam < d_mid                  # smoothstep ⇒ slow at the seam, fast mid-dive
    # center pans ~0.5° toward the SLO cluster as it tightens (zoom dominates)
    @test c180.cx > c0.cx                  # panned east toward −120.66 from −121.0
end
```
Append the include to runtests.

- [ ] **Step 2: Run it to verify it FAILS**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -15
```
Expected: FAIL — `Atlas.camera_at` undefined.

- [ ] **Step 3: Add the camera path**

Add to `examples/atlas/src/Atlas.jl`:
```julia
const W_WIDE  = 3.0           # deg — loop ends
const W_TIGHT = 0.30          # deg — loop apex
const C_WIDE  = (-121.0, 35.5)
const C_TIGHT = (-120.66, 35.30)
const NFRAMES = 360

smoothstep(t) = (t = clamp(t, 0, 1); t*t*(3 - 2t))

"""
    camera_at(frame) -> (; cx, cy, w)

Seamless in→out loop. `s ∈ [0,1]` goes 0→1→0 (down then up) as frame goes 0→180→360,
smoothstep-eased per half so velocity is 0 at start/apex/end. Width interpolated in
LOG space (geometric zoom = constant perceived velocity). Center lerps wide→tight by
the same eased `s` (zoom dominates ⇒ a dive). frame 360 ≡ frame 0.
"""
function camera_at(frame::Integer)
    half = NFRAMES ÷ 2
    s = frame <= half ? smoothstep(frame / half) :
                        smoothstep((NFRAMES - frame) / half)   # mirror for the rise
    w  = exp((1 - s) * log(W_WIDE) + s * log(W_TIGHT))         # geometric
    cx = (1 - s) * C_WIDE[1] + s * C_TIGHT[1]
    cy = (1 - s) * C_WIDE[2] + s * C_TIGHT[2]
    return (; cx = cx, cy = cy, w = w)
end

"Axis limits (in map-units, projected) for a camera state — square-ish window of width `w`°."
function camera_limits(c)
    xc, yc = project_xy(c.cx, c.cy)
    hw = (c.w * KX) / 2
    hh = c.w / 2
    return (xc - hw, xc + hw, yc - hh, yc + hh)
end
```

- [ ] **Step 4: Run the test to verify it PASSES**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -15
```
Expected: PASS — wide ends at 3.0°, apex at 0.30°, loop closes, seam slower than mid-dive, pans east.

- [ ] **Step 5: Commit**

```bash
git add examples/atlas/src/Atlas.jl examples/atlas/test/test_camera.jl examples/atlas/test/runtests.jl
git commit -m "feat(atlas): geometric-zoom camera path with smoothstep seamless loop"
```

---

### Task 6: Fade-in alpha + sticky carry-over + per-frame placement record

**Why now:** assemble the per-frame *placement record* the renderer and golden harness both consume: warm-start solve (Task 1) over the active set (Task 4), fade-in alpha for newcomers (smoothstep 0→1 over 9 frames), sticky carry-over of offsets keyed by `town_id`, our own overlap/dropped recompute, and `has_leader` per label.

**Files:**
- Modify: `examples/atlas/src/Atlas.jl` (`PlacementState`, `step_frame!`, `placement_rows`)
- Create: `examples/atlas/test/test_placement.jl`; Modify: `examples/atlas/test/runtests.jl`

- [ ] **Step 1: Write the failing test**

Create `examples/atlas/test/test_placement.jl`:
```julia
using Test
include(joinpath(@__DIR__, "..", "src", "Atlas.jl")); using .Atlas

@testset "per-frame placement: fade, sticky, overlaps==0" begin
    towns = Atlas.load_towns()
    st = Atlas.PlacementState()
    # Run the first ~20 frames; collect per-frame records.
    recs = [Atlas.step_frame!(st, towns, f) for f in 0:20]
    r0 = recs[1]
    @test r0.overlaps == 0                                  # collision-free from frame 0
    @test all(0.0 <= a <= 1.0 for a in values(r0.alpha))   # alpha in range
    # a newcomer fades: when a town first becomes active its alpha climbs over ~9 frames.
    # find the first frame cambria is active:
    fc = findfirst(r -> :cambria in keys(r.alpha), recs)
    @test fc !== nothing
    @test recs[fc].alpha[:cambria] < 1.0                    # fades in, not popped
    if fc + 9 <= length(recs)
        @test recs[fc + 9].alpha[:cambria] ≈ 1.0 atol = 0.05  # settled after ~9 frames
    end
    # sticky: a settled town's offset barely changes between consecutive frames.
    settled = :san_luis_obispo
    if haskey(recs[10].offsets, settled) && haskey(recs[11].offsets, settled)
        d = sum(abs2, recs[11].offsets[settled] .- recs[10].offsets[settled])
        @test d < 9.0                                       # held within 3px (warm-start)
    end
    # every asserted frame is collision-free
    @test all(r.overlaps == 0 for r in recs)
end
```
Append the include to runtests.

- [ ] **Step 2: Run it to verify it FAILS**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -20
```
Expected: FAIL — `Atlas.PlacementState`/`step_frame!` undefined.

- [ ] **Step 3: Add the placement state machine**

Add to `examples/atlas/src/Atlas.jl`. `step_frame!` projects anchors via `camera_limits` (in map-units; for tests we compute pixel anchors with a fixed virtual viewport, then under `record` we use `Makie.project` — Task 7 wires the real axis). For the headless test path, provide a pure projection from map-units → a fixed 1280×800 pixel viewport so placement is exercised without a Scene:
```julia
const FADE_FRAMES = 9
const VIEWPORT = Rect2f(0, 0, 1280, 800)     # headless pixel viewport for tests/golden

mutable struct PlacementState
    prev_off::Dict{Symbol,Vec2f}     # prior frame offsets, keyed by town_id (warm start)
    active::Set{Symbol}              # prior active set (hysteresis)
    born::Dict{Symbol,Int}           # frame each active town first appeared (fade clock)
    PlacementState() = new(Dict{Symbol,Vec2f}(), Set{Symbol}(), Dict{Symbol,Int}())
end

"Map-units (x,y) → pixel within VIEWPORT for camera `c` (headless projection mirror)."
function px_of(c, x, y)
    (xlo, xhi, ylo, yhi) = camera_limits(c)
    fx = (x - xlo) / (xhi - xlo); fy = (y - ylo) / (yhi - ylo)
    return Point2f(fx * VIEWPORT.widths[1], fy * VIEWPORT.widths[2])
end

"""
    step_frame!(st, towns, frame; project = px_of) -> (; offsets, alpha, dropped_ids, overlaps, has_leader, active)

Advance the placement one frame. `project(c, x, y) -> Point2f` is injected so the
headless path uses `px_of` and the `record` path (Task 7) passes a Makie projector.
"""
function step_frame!(st::PlacementState, towns::Dict, frame::Integer; project = px_of)
    c   = camera_at(frame)
    act = active_ids(towns, c.w, st.active)
    ids = sort!(collect(act))                       # deterministic order
    # fade clocks: newly active towns are born now; departed towns forget.
    for id in ids; haskey(st.born, id) || (st.born[id] = frame); end
    for id in collect(keys(st.born)); (id in act) || delete!(st.born, id); end

    anchors = Dict(id => project(c, towns[id].x, towns[id].y) for id in ids)
    sizes   = Dict(id => measure_town(towns[id].name) for id in ids)
    prev    = Dict(id => st.prev_off[id] for id in ids if haskey(st.prev_off, id))  # warm start by id
    r       = solve_frame(ids, anchors, sizes, VIEWPORT; prev = prev)

    alpha = Dict(id => smoothstep((frame - st.born[id]) / FADE_FRAMES) for id in ids)
    overlaps = count_overlaps(ids, anchors, sizes, r.offsets)
    has_leader = Dict(id => _has_leader(r.offsets[id], sizes[id]) for id in ids)

    st.prev_off = r.offsets
    st.active   = act
    return (; offsets = r.offsets, alpha = alpha, dropped_ids = r.dropped_ids,
              overlaps = overlaps, has_leader = has_leader, active = act,
              anchors = anchors, sizes = sizes, camera = c)
end

"A leader is needed when the anchor is NOT inside the label box (label can't sit snug)."
function _has_leader(offset::Vec2f, size::Vec2f)
    # anchor at origin relative to box centered at `offset`: covered ⇒ no leader.
    box = MakieTextRepel.box_at(Point2f(0, 0), offset, size)
    return !MakieTextRepel.point_covered(Point2f(0, 0), box, 0.0)
end

"""
    placement_rows(rec, towns) -> Vector{String}

Machine-robust golden rows: `town_id | slot | rel_off_x(2dp) | rel_off_y(2dp) | alpha_q | has_leader`.
RELATIVE offset (not absolute px); alpha quantized to 0.05. Sorted by HouseStyle.digest_rows.
"""
function placement_rows(rec, towns::Dict)
    ids = sort!(collect(keys(rec.offsets)))
    rows = String[]
    for id in ids
        o = rec.offsets[id]
        aq = round(rec.alpha[id] / 0.05) * 0.05
        push!(rows, string(id, "|", infer_slot(o), "|",
                           round(o[1]; digits = 2), "|", round(o[2]; digits = 2), "|",
                           round(aq; digits = 2), "|", rec.has_leader[id] ? 1 : 0))
    end
    return rows
end
```

- [ ] **Step 4: Run the test to verify it PASSES**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -20
```
Expected: PASS — collision-free every frame, fade-in over 9 frames, sticky settled labels.

- [ ] **Step 5: Commit**

```bash
git add examples/atlas/src/Atlas.jl examples/atlas/test/test_placement.jl examples/atlas/test/runtests.jl
git commit -m "feat(atlas): fade-in + sticky carry-over + per-frame placement record (overlaps==0)"
```

---

### Task 7: Render the dive — basemap + labels + cartouche, CairoMakie.record

**Why now:** draw it. Water = Axis background; land = paper `poly!`; coastline = 0.75px ink hairline; town dots 2–4px ink + 0.5px paper halo; one brass hero dot at SLO; graticule 0.25px brass; 1.0px brass neat-line + corner cartouche (title, scale bar, live metrics). Plex-Mono necklace labels via `text!(…; markerspace=:pixel, offset=offsets)`; brass 0.5px leaders under markers. The reactive `record` over `camera_at` re-solves placement each frame (real Makie projector replaces `px_of`).

**Files:**
- Create: `examples/atlas/render.jl` (the `record` driver — the build script, NOT a test)
- Modify: `examples/atlas/src/Atlas.jl` (`draw_basemap!`, `draw_frame!`, `makie_projector`)
- Create: `examples/atlas/test/test_render.jl`; Modify: `examples/atlas/test/runtests.jl`

- [ ] **Step 1: Write the failing test (a cheap 2-frame smoke render to a tempdir)**

Create `examples/atlas/test/test_render.jl`:
```julia
using Test, CairoMakie
include(joinpath(@__DIR__, "..", "src", "Atlas.jl")); using .Atlas

@testset "render smoke: 2 frames write a non-empty mp4" begin
    towns = Atlas.load_towns()
    mktempdir() do dir
        mp4 = joinpath(dir, "smoke.mp4")
        Atlas.render_dive(towns; out = mp4, frames = 0:1, framerate = 1)
        @test isfile(mp4)
        @test filesize(mp4) > 1000                # a real (tiny) video, not empty
    end
end
```
Append the include to runtests.

- [ ] **Step 2: Run it to verify it FAILS**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -20
```
Expected: FAIL — `Atlas.render_dive` undefined.

- [ ] **Step 3: Add the renderer**

Add to `examples/atlas/src/Atlas.jl`: `using CairoMakie; using HouseStyle: PAPER, INK, BRASS, GRAY, fraunces, footer`. Implement:
- `makie_projector(ax)` → a closure `(c, x, y) -> Point2f(Makie.project(ax.scene, Point2f(x, y)))` so `step_frame!` reads real pixel anchors after `Makie.update_state_before_display!(fig)`.
- `draw_basemap!(ax, bm)` → `poly!` each land ring in PAPER; `lines!` each coast polyline 0.75px INK; set `ax.backgroundcolor = WATER_FILL`; graticule `lines!` at whole degrees 0.25px BRASS.
- `draw_frame!(ax, plots, rec, towns)` → update `Observable`s for: dot positions (active anchors) 3px INK with paper halo, brass hero dot at `:san_luis_obispo`, `text!` necklace labels (`markerspace = :pixel`, `offset = [rec.offsets[id] …]`, `color = (INK, alpha)`, `font = LABEL_FONT`, `fontsize = LABEL_SIZE`), brass 0.5px `linesegments!` leaders only where `rec.has_leader[id]`, and the cartouche metrics line `"w $(round(c.w;digits=2))° · N/N placed · K entering · L leader"`.
- `render_dive(towns; out, frames = 0:359, framerate = 30)`:
```julia
function render_dive(towns; out::String, frames = 0:(NFRAMES-1), framerate::Int = 30)
    bm = load_basemap()
    fig = Figure(size = (1280, 800), backgroundcolor = PAPER)
    ax  = Axis(fig[1,1]; aspect = DataAspect()); hidedecorations!(ax); hidespines!(ax)
    ax.backgroundcolor = WATER_FILL
    draw_basemap!(ax, bm)
    plots = init_frame_plots!(ax)                  # empty Observables for dots/labels/leaders
    st = PlacementState()
    proj = makie_projector(ax)
    record(fig, out, frames; framerate = framerate) do frame
        c = camera_at(frame)
        limits!(ax, camera_limits(c)...)
        Makie.update_state_before_display!(fig)    # px anchors reflect THIS frame (§8 fix)
        rec = step_frame!(st, towns, frame; project = proj)
        draw_frame!(ax, plots, rec, towns)
    end
    return out
end
```
(Keep `draw_frame!` mutating pre-created Observables so `record` is efficient. The masthead "THE ATLAS" Fraunces 44 + "CENTRAL COAST" Fraunces 22 + `footer("The Atlas")` are static overlays in a top `Label`/`text!`, drawn once.)

- [ ] **Step 4: Run the test to verify it PASSES**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -20
```
Expected: PASS — 2-frame smoke mp4 written, non-empty.

- [ ] **Step 5: Create the build driver and render the full dive**

Create `examples/atlas/render.jl`:
```julia
# Build the full dive. Run: julia --project=examples/atlas examples/atlas/render.jl
using CairoMakie
include(joinpath(@__DIR__, "src", "Atlas.jl")); using .Atlas
towns = Atlas.load_towns()
out = joinpath(@__DIR__, "atlas_dive.mp4")
Atlas.render_dive(towns; out = out)              # 360 frames @ 30fps = 12s
println("wrote ", out)
```
Run:
```bash
julia --project=examples/atlas examples/atlas/render.jl 2>&1 | tail -3
ls -la examples/atlas/atlas_dive.mp4
```
Expected: `wrote …/atlas_dive.mp4` and a multi-hundred-KB file.

- [ ] **Step 6: OPEN the MP4 and confirm the fill-in reads (green ≠ visual sign-off)**

Extract a few frames to PNG and view them (the `frame_pngs` helper of Task 8, or `ffmpeg`), then use SendUserFile to surface them. Confirm: the necklace lattice kisses edge-to-edge, newcomers fade in (not pop), leaders are rare/brass, the loop seam is invisible, masthead + cartouche read. If the fill-in does not read, iterate on LoD/fade/style before declaring done.

- [ ] **Step 7: Gitignore the video, commit code**

Add `examples/atlas/atlas_dive.mp4` and `examples/atlas/frames/` to `.gitignore` (video is a build artifact, NEVER committed). Then:
```bash
git add .gitignore examples/atlas/src/Atlas.jl examples/atlas/render.jl examples/atlas/test/test_render.jl examples/atlas/test/runtests.jl
git commit -m "feat(atlas): render the dive — basemap + necklace labels + cartouche via CairoMakie.record"
```

---

### Task 8: Golden harness — digest 6 sampled frames + the mid-dive still

**Why now:** lock determinism. Golden = `digest_rows` over `placement_rows` (town_id, slot, relative-offset, alpha_q, has_leader) at frames `f000/f060/f120/f180(apex)/f240/f300`; sha256 + `.txt` sibling per frame (mirror `asteroid_tui/frame60.sha256`). Per-frame invariants: our overlap recompute == 0, dropped ≤ budget, active-set size matches the LoD gate. Also render the gallery still at `p≈0.42` (frame 151).

**Files:**
- Create: `examples/atlas/test/golden/f{000,060,120,180,240,300}.{sha256,txt}`
- Create: `examples/atlas/test/test_golden.jl`; Modify: `examples/atlas/test/runtests.jl`
- Create: `examples/atlas/still.jl` (the mid-dive still build script)

- [ ] **Step 1: Write the failing golden test**

Create `examples/atlas/test/test_golden.jl`:
```julia
using Test
include(joinpath(@__DIR__, "..", "src", "Atlas.jl")); using .Atlas

const GOLDEN = joinpath(@__DIR__, "golden")
const SAMPLES = [0, 60, 120, 180, 240, 300]

"Replay frames 0..f deterministically (headless px_of path) and return frame f's record."
function record_at(towns, f)
    st = Atlas.PlacementState()
    rec = nothing
    for frame in 0:f
        rec = Atlas.step_frame!(st, towns, frame)        # default project = px_of (deterministic)
    end
    return rec
end

@testset "golden: per-frame placement digest is stable & collision-free" begin
    towns = Atlas.load_towns()
    for f in SAMPLES
        rec  = record_at(towns, f)
        rows = Atlas.placement_rows(rec, towns)
        dig  = Atlas.digest_rows(rows)                    # re-export of HouseStyle.digest_rows
        tag  = "f" * lpad(f, 3, '0')
        shaf = joinpath(GOLDEN, tag * ".sha256")
        @test isfile(shaf)                                # golden committed
        @test strip(read(shaf, String)) == dig            # matches
        # invariants
        @test rec.overlaps == 0                           # our own recompute == 0
        @test length(rec.dropped_ids) <= 2                # dropped ≤ budget
        @test length(rec.active) == length(keys(rec.offsets))
    end
end
```
Append the include to runtests.

- [ ] **Step 2: Run it to verify it FAILS**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -20
```
Expected: FAIL — `golden/f000.sha256` etc. do not exist (`isfile` false).

- [ ] **Step 3: Generate the golden files (after inspecting the rows by eye)**

Run a one-off to emit the digest + human-readable `.txt` for each sampled frame:
```bash
julia --project=examples/atlas -e '
include("examples/atlas/src/Atlas.jl"); using .Atlas
towns = Atlas.load_towns()
for f in [0,60,120,180,240,300]
    st = Atlas.PlacementState(); rec = nothing
    for frame in 0:f; rec = Atlas.step_frame!(st, towns, frame); end
    rows = Atlas.placement_rows(rec, towns)
    tag = "f"*lpad(f,3,"0")
    write(joinpath("examples/atlas/test/golden", tag*".txt"), join(rows, "\n"))
    write(joinpath("examples/atlas/test/golden", tag*".sha256"), Atlas.digest_rows(rows))
    println(tag, "  ", length(rows), " labels  ", Atlas.digest_rows(rows)[1:12])
end'
```
Read each `golden/f*.txt` and sanity-check: label counts grow then shrink across the dive (LoD), slots are sensible, alpha_q rises for newcomers. Only then accept the digests as golden.

- [ ] **Step 4: Run the test to verify it PASSES**

Run:
```bash
julia --project=examples/atlas -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -20
```
Expected: PASS — all 6 frames digest-match, overlaps==0, dropped ≤ 2, active-set consistent.

- [ ] **Step 5: Confirm golden stability across a re-run (machine-robustness check)**

Re-run the generator from Step 3 into a tempdir and diff against the committed `.sha256` — the relative-offset/slot key must be byte-identical on re-run (if it is NOT, the key is still float-sensitive; fall back to slot-only hashing per SPEC §8 before building further on it):
```bash
julia --project=examples/atlas -e '
include("examples/atlas/src/Atlas.jl"); using .Atlas
towns = Atlas.load_towns()
for f in [0,60,120,180,240,300]
    st = Atlas.PlacementState(); rec = nothing
    for frame in 0:f; rec = Atlas.step_frame!(st, towns, frame); end
    d = Atlas.digest_rows(Atlas.placement_rows(rec, towns))
    g = strip(read(joinpath("examples/atlas/test/golden","f"*lpad(f,3,"0")*".sha256"), String))
    println("f", lpad(f,3,"0"), d == g ? "  STABLE" : "  DRIFT")
end'
```
Expected: six `STABLE` lines.

- [ ] **Step 6: Build the mid-dive still (p≈0.42, frame 151)**

Create `examples/atlas/still.jl` rendering a single PNG at frame 151 (`p≈0.42`, `w≈0.55°`) with the cluster half-revealed:
```julia
# Run: julia --project=examples/atlas examples/atlas/still.jl
using CairoMakie
include(joinpath(@__DIR__, "src", "Atlas.jl")); using .Atlas
towns = Atlas.load_towns()
out = joinpath(@__DIR__, "atlas_still.png")
Atlas.render_still(towns; frame = 151, out = out)   # one frame to PNG, same draw path
println("wrote ", out)
```
Add `render_still` to `Atlas.jl` (single-frame variant of `render_dive` that `save`s a PNG). Run it, then SendUserFile the PNG and confirm it reads as motion frozen (SLO/Morro Bay/Pismo solid, Cambria + San Simeon mid-fade α≈0.5, one leader into open water). Gitignore `atlas_still.png`.

- [ ] **Step 7: Commit**

```bash
git add examples/atlas/test/golden examples/atlas/test/test_golden.jl examples/atlas/test/runtests.jl examples/atlas/still.jl examples/atlas/src/Atlas.jl .gitignore
git commit -m "feat(atlas): golden harness (6 frames, town_id+slot+rel-offset key) + mid-dive still"
```

---

### Task 9: README — the three-layer honesty, build steps, the MakieTextRepel sibling caveat

**Why now:** the caption IS the honesty (three-layer split; coastline + major cities verbatim NE, small towns hand-placed; warm-start drafted against internals, to be upstreamed). Document the Task-0 sibling-clone + repointed-source step so a fresh machine reproduces the build.

**Files:**
- Create: `examples/atlas/README.md`

- [ ] **Step 1: Write the README**

Create `examples/atlas/README.md` covering: (1) what it is (register: place — the live collision-free dive); (2) the three-layer split (TextMeasure measures · MakieTextRepel places · demo warm-starts/gates/draws) — name it as the honesty; (3) data provenance (NE 1:10m coast/land PD; 8 NE town rows verbatim + ~15 hand-placed `source=curated`; see `data/SOURCE.txt`); (4) the API-plan honesty (warm-start solve drafted against MakieTextRepel internals `solve_cluster(…; init_state, pin_mask, pinned_offsets)`, overlaps/dropped computed in-demo, to be upstreamed then swapped to public API); (5) **build prerequisites — the MakieTextRepel sibling**: clone `github.com/jowch/MakieTextRepel.jl` as a sibling of the gallery worktree at `/home/jonathanchen/projects/MakieTextRepel.jl` and repoint its `[sources] TextMeasure` to `../TextMeasure.jl-gallery` (Task 0); (6) build commands (`render.jl` → `atlas_dive.mp4`, `still.jl` → `atlas_still.png`, both gitignored) and `Pkg.test()` for the golden harness; (7) the one bold move (the dive; naive-vs-measured demoted to an optional cartouche inset).

- [ ] **Step 2: Commit**

```bash
git add examples/atlas/README.md
git commit -m "docs(atlas): three-layer honesty, provenance, build steps, MakieTextRepel sibling caveat"
```

---

## Self-review notes

- **Spec coverage:** Task 1 = the warm-start solve gate (SPEC §1/§2/§8 — deterministic re-solve, warm-start held by `town_id`, golden-stable on slot+relative-offset, `update_state_before_display!` timing); Task 2 = hermetic basemap data (§6); Task 3 = equirectangular + cosφ0 projection (§6); Task 4 = LoD + hysteresis + TextMeasure boxes (§3, §7); Task 5 = geometric-zoom seamless-loop camera (§5); Task 6 = fade + sticky + per-frame record + own overlap/dropped recompute (§3, §8); Task 7 = the Swiss/Vignelli render + `record` (§7) with the mandated MP4 open-and-confirm; Task 8 = golden harness on the machine-robust key + the p≈0.42 still (§8); Task 9 = the three-layer caption honesty + build reproduction (§0, §6).
- **API fidelity:** every MakieTextRepel call is verified against `/tmp/MakieTextRepel.jl/src/`: `solve_cluster(ProjectionSolver(RepelParams(…)), anchors::Vector{Point2f}, sizes::Vector{Vec2f}, bounds::Rect2f; init_state, pin_mask, pinned_offsets, obstacles) -> (; offsets, dropped, iter, residual)`; `init_state===nothing` ⇒ fresh Imhof seed (`initial_offsets`) → `side_select` → repair, else warm-start relax; geometry helpers `box_at`/`overlap_push`/`point_covered` qualified (not exported) for our own deterministic overlap recompute; we never read `solve_stats`/`computed_offsets` (recipe-/algorithm-only, off the path). No invented API.
- **The warm-start nuance (flag):** `solve_cluster`'s warm path *legalizes the given layout only* — it does NOT re-run side-select. So a town that is NEW in a frame where others are warm-started cannot get `init_state=nothing` per-label inside one `solve_cluster` call (init_state is all-or-nothing: a Vector or `nothing`). Task 1's wrapper currently passes `init_state=nothing` whenever ANY active town lacks a prior offset (`have_prev = all(...)`), i.e. it does a FRESH solve on any frame with a newcomer, and a warm relax only on frames where the active set is unchanged. This is correct and deterministic but means "settled labels hold" is exact only on no-newcomer frames; on newcomer frames the whole cluster re-seeds (still collision-free, may shift). If the visual reshuffle on newcomer frames is too strong, the upstream fix (per-label warm/fresh seeding — exactly what `TextRepelAlgorithm`'s `reset=false` + Imhof-fallback-for-new does) is the documented path; the demo wrapper should be upgraded to seed prior offsets for known towns and Imhof-seed new ones in a single `init_state` Vector (feed `initial_offsets`-derived seeds for new ids). **Flagged for the implementer to validate against the rendered MP4 (Task 7 Step 6) and tune.**
- **MakieTextRepel availability (the operator's explicit concern):** it is the user's own **unregistered** package and is **not** resolvable without Task 0. Verified its `Project.toml` has `[sources] TextMeasure = {path = "../TextMeasure.jl"}` — it expects TextMeasure as a sibling. Task 0 clones it to `/home/jonathanchen/projects/MakieTextRepel.jl` (sibling of the worktree) and **repoints its TextMeasure source to `../TextMeasure.jl-gallery`** so one TextMeasure serves both; the Atlas `Project.toml` references it via `[sources] MakieTextRepel = { path = "../../../MakieTextRepel.jl" }`. This clone + repoint lives **outside** the worktree and is therefore NOT committed — Task 9's README documents it so a fresh machine reproduces it. If `github.com/jowch/MakieTextRepel.jl` is private/unreachable on the build machine, fall back to the local `/tmp/MakieTextRepel.jl` checkout already present.
- **Determinism risk:** the golden hashes RELATIVE offset + slot (not absolute projected px) precisely because projected px is float-noisy at zoom extremes; Task 8 Step 5 re-runs to confirm STABLE before trusting it, with the slot-only fallback named. The headless golden path uses `px_of` (a pure projection) rather than `Makie.project`, keeping the golden independent of Cairo/Scene state; the `record` path uses the real projector — the two share `step_frame!` so placement logic is identical, only the projector differs.
