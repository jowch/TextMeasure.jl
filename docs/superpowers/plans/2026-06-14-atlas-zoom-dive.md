<!-- SPDX-License-Identifier: MIT -->
# The Atlas (zoom dive) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `examples/atlas/` — a recorded, seamless-loop zoom-dive over the California Central Coast whose place-labels are measured by TextMeasure.jl and re-placed collision-free **every frame** by MakieTextRepel.jl as the viewport falls in, plus a golden-frame regression harness and a hero still.

**Architecture:** Mirror the mature `examples/tide/` gallery piece (Julia package with `[sources]` path deps, `src/` module split by responsibility, `build.jl` entry, MonospaceBackend golden harness that hashes a *layout table* never pixels, CairoMakie `record` → ffmpeg MP4). Atlas adds three things Tide doesn't have: a **viewport camera** (geometric zoom + smoothstep), a **level-of-detail gate** with hysteresis, and a **per-frame warm-start placement solve** that drives MakieTextRepel's verified internal `solve_cluster(...; init_state, pin_mask, pinned_offsets)` API, carrying each label's prior offset forward keyed by stable `town_id` so settled labels hold still and only newcomers drop into the gaps.

**Tech Stack:** Julia 1.11+, CairoMakie/Makie, MakieTextRepel.jl (pinned git rev `dc7178205ce4b05e8bd86c4ae10419f0932e14e6`), TextMeasure.jl (`MakieBackend`/`MonospaceBackend`), HouseStyle (palette/fonts/`digest_rows`), GeoJSON.jl + GeoInterface.jl (coastline/land), CSV.jl (towns), FFMPEG (via the same locator Tide uses).

**Source of truth:** `examples/atlas/SPEC.md` (the canonical 19.8 KB spec on this branch). Section references below (§N) point at it.

**Worktree:** all paths are in `/home/jonathanchen/projects/TextMeasure.jl-gallery` (branch `demos-gallery-greenfield`), where Tide / Woven / `_housestyle` live.

---

## Verified facts this plan rests on (do not re-derive)

These were checked against real source on 2026-06-14; copy them verbatim.

**MakieTextRepel.jl** (`/home/jonathanchen/projects/MakieTextRepel.jl`, rev `dc71782`, pushed to `origin/main`):
- `RepelParams` — `Base.@kwdef struct` (`src/params.jl:9`), 13 fields incl. `only_move::Symbol=:both`, `box_padding::Float64=4.0`, `point_padding::Float64=0.0`, `min_segment_length::Float64=2.0`, `max_overlaps::Float64=Inf`, `bounds::Union{Rect2f,Nothing}=nothing`.
- `ProjectionSolver(params::RepelParams)` (`src/solvers/projection.jl:16`) — holds a mutable `stats` ref.
- `solve_cluster(s::ProjectionSolver, anchors::Vector{Point2f}, sizes::Vector{Vec2f}, bounds::Rect2f; init_state::Union{Nothing,Vector{Vec2f}}=nothing, pin_mask::Union{Nothing,BitVector}=nothing, pinned_offsets::Vector{Vec2f}=Vec2f[], obstacles::Vector{Rect2f}=Rect2f[])` (`src/solvers/projection.jl:60`) → **NamedTuple** `(; offsets::Vector{Vec2f}, dropped::BitVector, iter::Int, residual::Float32)`.
- Warm-start contract (`src/solvers/abstract.jl:7`): `init_state===nothing` ⇒ fresh Imhof-seed → side_select → legalize; a given `init_state` ⇒ **relax only** (warm-start).
- `IMHOF_ORDER = (:TR,:R,:T,:BR,:L,:BL,:B,:TL)` (`src/init.jl:4`).
- All of the above are **internal (not exported)**; access via `using MakieTextRepel: ProjectionSolver, RepelParams, solve_cluster`.
- Public surface (exported): recipe `textrepel!` (does a *fresh* solve only, no warm-start), `TextRepelAlgorithm`, `solve_stats(alg) -> (; overlaps, point_overlaps, mean_leader, crossings, iter, residual, dropped)`. `TextRepelAlgorithm`'s `calculate_best_offsets!(...; reset=false)` internally threads prior offsets as `init_state` **and** populates `solve_stats` — a candidate higher-level path (Task 1 decides).

**TextMeasure.jl** (this repo, parent of `examples/`):
- `MakieBackend(; font=Makie.automatic, fontsize=12, px_per_unit=1.0)` (ext `TextMeasureMakieExt.jl`). Use `px_per_unit=1` so measured box == rendered box.
- `prepare(backend, text)::Prepared` with `.segments::Vector{Segment}` (`.str/.width/.kind`) and `.metrics::FontMetrics`.
- `layout(prep; max_width=Inf, align=:left, lineheight=1.0)::Layout` with `.size::NTuple{2,Float64}` (px w,h), `.lines::Vector{Line}`, `.metrics`.
- `font_metrics(backend)::FontMetrics` — `.ascent/.descent/.line_advance` (px).
- `MonospaceBackend(; fontsize)` — deterministic, font-path-independent; the golden backend.

**HouseStyle** (`examples/_housestyle`): `PAPER #F4EFE6`, `INK #1A1714`, `BRASS #9A7B4F`, `BRASS_INK #6E5226`, `GRAY #6B7280`; `RAMP=(caption=9,body=11,subhead=16,title=22,deck=31,display=44)`; `fraunces("9pt-Regular")`, `plexmono("Regular")`, `footer(piece)`, `digest_rows(rows::AbstractVector{<:AbstractString})->hex` (sorts rows, sha256). Water colors `#DCE3E5`/`#9FB2BA` are **Atlas-local** (not in HouseStyle — define in `render.jl`).

**Tide reference patterns to copy** (`examples/tide/`): `[sources]` block for unregistered in-repo deps; `build.jl` is a 2-line driver into `src/loop.jl`; golden harness in `src/golden.jl` builds rows with `MonospaceBackend`, rounds floats to 2dp, hashes via `digest_rows`; `test/test_golden.jl` asserts `length(cs)==64`, regenerates on `ENV["UPDATE_GOLDEN"]=="1"`, then `@test cs == strip(read(path,String))`; ffmpeg via `_ffmpeg_cmd()` (FFMPEG_jll, PATH fallback).

---

## File structure (`examples/atlas/`)

| Path | Responsibility |
|---|---|
| `Project.toml` | Package manifest; `[deps]` + `[sources]` (path deps for in-repo pkgs, pinned git url for MakieTextRepel). |
| `data/coastline.geojson` | Committed NE 1:10m coastline, clipped to bbox (~15–30 KB). |
| `data/land.geojson` | Committed NE 1:10m land polygons, clipped (~15–30 KB). |
| `data/towns.csv` | 8 verbatim NE rows (`source=NE`) + ~12–22 hand-placed (`source=curated`); cols `town_id,name,lon,lat,pop,rank,source`. |
| `data/SOURCE.txt` | Provenance + license statement (NE public domain; curated rows hand-entered). |
| `prep/clip.jl` | One-time, network-touching, bbox-hardcoded. Fetches NE 10m, clips, writes `data/*.geojson`. **Never run by tests.** |
| `src/Atlas.jl` | Module root: includes (in dependency order), exports, `PrecompileTools` workload. |
| `src/data.jl` | Load committed geojson + towns.csv; the `cosφ0` affine into shared `map-units`; `Town`/`Coast` structs. |
| `src/camera.jl` | Geometric (log-width) zoom + per-half smoothstep easing; `view_width(p)`, `view_center(p)`, `camera_rect(p)`. |
| `src/lod.jl` | Eligibility ladder + hysteresis; `active_ids(w, prev_active) -> Vector{Int}` (stable `town_id`s). |
| `src/place.jl` | Measure boxes (`MakieBackend`), project anchors→px, warm-start `solve_cluster`, carry `prev_offset` by `town_id`, `pin_mask` for settled, **deterministic overlap recompute**; returns a `FramePlacement` table. |
| `src/fade.jl` | Per-`town_id` alpha schedule (smoothstep fade-in over 9 frames) + tween bookkeeping for evicted labels. |
| `src/render.jl` | Palette (+water locals); `draw_basemap!`, `draw_labels!`, `draw_chrome!` (masthead, neat-line, cartouche, metrics); `_new_axis`, `_page_size`. |
| `src/loop.jl` | `render_hero` (mid-dive still p≈0.42), `render_loop` (record→ffmpeg MP4), `render_thumb`; `_ffmpeg_cmd` (copy Tide). |
| `src/golden.jl` | `geometry_rows()` over 6 pinned frames (MonospaceBackend, `town_id`+slot/offset, relative-offset 2dp, `alpha_q`, `has_leader`); `atlas_digest()` via `digest_rows`. |
| `test/runtests.jl` | Aggregates the testsets. |
| `test/test_data.jl` | Projection round-trip, vertex counts, town count + unique `town_id`. |
| `test/test_camera.jl` | Loop continuity (position+velocity at seam), monotone zoom, endpoint widths. |
| `test/test_lod.jl` | Ladder thresholds, hysteresis prevents flicker, active-set sizes per phase. |
| `test/test_place.jl` | Per-frame invariants: overlap recompute == 0, `dropped ≤ budget`, active-set == gate, warm-start stability. |
| `test/test_golden.jl` | The digest regression (copy Tide's shape). |
| `test/golden/atlas.sha256` | Committed digest. |
| `test/golden/atlas.rows.txt` | Committed human-diffable table. |
| `README.md` | Overview, engine concept, file map, render instructions, reusable ideas (copy Tide's headings). |
| `SPEC.md` | Already exists (canonical). |

**Decomposition note:** `place.jl` is the load-bearing file. Keep `fade.jl` (alpha/tween, demo-owned) separate from `place.jl` (geometry/solve) so the solve stays pure and unit-testable. `render.jl` consumes both and is exercised only by visual gates, never unit-tested for pixels.

---

## A note on task types

This piece is part deterministic (camera math, LoD, projection, golden harness — these get real unit tests with oracle values) and part craft-tuned (label `box_padding`, camera feel, basemap stroke weights, the hero frame — these get **concrete starting values from the SPEC plus a visual gate**, because no unit test can assert "looks right"). Each task below is labelled **[unit]** or **[visual gate]**. For **[visual gate]** tasks the "test" is: render the artifact, open it, confirm it against the SPEC's described look, and record one line of what you saw. Per the user's standing rule, a green suite is **not** visual sign-off — you must look at the PNG/MP4 yourself.

---

## Task 0: Scaffold the package + resolve dependencies

**Files:**
- Create: `examples/atlas/Project.toml`
- Create: `examples/atlas/src/Atlas.jl`
- Create: `examples/atlas/test/runtests.jl`

- [ ] **Step 1: Write `Project.toml`**

```toml
name = "Atlas"
uuid = "b7e2d1a4-3c5f-4e8a-9b6d-2f1c8a0e4d7b"
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
MakieTextRepel = "9c8a3f21-4b7e-4d6a-8e2f-1a3b5c7d9e0f"
PrecompileTools = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
Printf = "de0858da-6303-5e67-8744-51eda0adfde9"
TextMeasure = "06791c1d-2336-41e1-bd6f-a74c63395da6"

# Unregistered packages — resolve by path/url (Julia 1.11+ [sources]).
[sources]
HouseStyle = { path = "../_housestyle" }
TextMeasure = { path = "../.." }
MakieTextRepel = { url = "https://github.com/jowch/MakieTextRepel.jl", rev = "dc7178205ce4b05e8bd86c4ae10419f0932e14e6" }

[compat]
julia = "1.11"

[extras]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Test"]
```

> **Note on the MakieTextRepel uuid:** copy the real UUID from `/home/jonathanchen/projects/MakieTextRepel.jl/Project.toml` (the placeholder above must be replaced with the actual value before instantiate). Likewise the `Atlas` uuid above is a fresh random v4 — keep it or regenerate, just don't collide with an existing example.

- [ ] **Step 2: Write a minimal `src/Atlas.jl`**

```julia
module Atlas

using TextMeasure
using MakieTextRepel: ProjectionSolver, RepelParams, solve_cluster
import HouseStyle

# includes added task-by-task:
# include("data.jl"); include("camera.jl"); include("lod.jl")
# include("place.jl"); include("fade.jl"); include("render.jl")
# include("loop.jl"); include("golden.jl")

end # module
```

- [ ] **Step 3: Write a placeholder `test/runtests.jl`**

```julia
using Atlas, Test

@testset "Atlas" begin
    @testset "loads" begin
        @test isdefined(Atlas, :solve_cluster)  # MakieTextRepel internal API resolved
    end
    # include("test_data.jl") … added per task
end
```

- [ ] **Step 4: Instantiate + load (the real gate — proves the pinned git dep + internal imports resolve)**

Run:
```bash
cd /home/jonathanchen/projects/TextMeasure.jl-gallery/examples/atlas
julia --project -e 'using Pkg; Pkg.instantiate(); using Atlas; println("ok")'
```
Expected: instantiate clones MakieTextRepel at the pinned rev; prints `ok` with no `UndefVarError` on `solve_cluster`. **If `solve_cluster` is not importable, STOP** — the internal API moved; re-verify against the package before continuing.

- [ ] **Step 5: Commit**

```bash
git add examples/atlas/Project.toml examples/atlas/src/Atlas.jl examples/atlas/test/runtests.jl
git commit -m "feat(atlas): scaffold package + pin MakieTextRepel warm-start dep"
```

---

## Task 1: De-risk spike — per-frame reactive timing + warm-start (the riskiest unknown, §2/§8)

Resolve the two unknowns that decide `place.jl`'s architecture **before** building it: (a) does `update_state_before_display!(fig)` make projected px reflect the current frame's `limits!` *before* we read them, and (b) does warm-start (`init_state = prev_offsets`) actually damp reshuffle vs a fresh solve. Also decide raw `solve_cluster` vs `TextRepelAlgorithm(reset=false)`.

**Files:**
- Create: `examples/atlas/prep/spike_timing.jl` (a throwaway script kept under `prep/` for the record; not part of the package, not tested)

- [ ] **Step 1: Write the 3-frame timing + warm-start probe**

```julia
# prep/spike_timing.jl — run with: julia --project prep/spike_timing.jl
using CairoMakie, Makie
using MakieTextRepel: ProjectionSolver, RepelParams, solve_cluster
using GeometryBasics: Point2f, Vec2f, Rect2f

fig = Figure(); ax = Axis(fig[1,1])
anchors_data = [Point2f(0.2,0.2), Point2f(0.25,0.22), Point2f(0.8,0.8)]
scatter!(ax, anchors_data)

# Probe (a): after limits! + update_state_before_display!, do data->pixel projections track?
function px_of(ax, pts)
    Makie.update_state_before_display!(ax.parent)
    map(p -> Makie.project(ax.scene, p), pts)
end
for lims in [((0.0,0.0),(1.0,1.0)), ((0.1,0.1),(0.5,0.5)), ((0.18,0.18),(0.30,0.30))]
    limits!(ax, lims[1][1], lims[2][1], lims[1][2], lims[2][2])
    px = px_of(ax, anchors_data)
    println("limits=$lims -> px=$px")   # EXPECT: px shifts/zooms each step (frame k reflects frame k)
end

# Probe (b): warm-start vs fresh on a tiny cluster.
params = RepelParams(; box_padding=4.0, point_padding=5.0)
solver = ProjectionSolver(params)
anchors = [Point2f(100,100), Point2f(108,104), Point2f(400,400)]
sizes   = [Vec2f(60,14), Vec2f(50,14), Vec2f(40,14)]
bounds  = Rect2f(0,0,800,600)
fresh = solve_cluster(solver, anchors, sizes, bounds; init_state=nothing)
warm  = solve_cluster(solver, anchors, sizes, bounds; init_state=fresh.offsets)
println("fresh.offsets=", fresh.offsets)
println("warm.offsets =", warm.offsets, "  (EXPECT ~= fresh, i.e. warm-start holds)")
println("fresh.dropped=", fresh.dropped)
```

- [ ] **Step 2: Run it and record findings**

Run:
```bash
cd /home/jonathanchen/projects/TextMeasure.jl-gallery/examples/atlas
julia --project prep/spike_timing.jl 2>&1 | tee /tmp/atlas-spike.log
```
Expected and to **record in the commit message + a comment block at the top of `place.jl` later**:
- Probe (a): projected px change at each `limits!` step (confirms read-after-update is correct). If they lag by one frame, the architecture must call `update_state_before_display!` exactly where the spike does.
- Probe (b): `warm.offsets ≈ fresh.offsets` (warm-start relaxes the given layout rather than re-seeding). If `Makie.project` is not the right data→pixel call on this Makie version, find the correct one (e.g. `Makie.project(ax.scene.camera, …)` / `Makie.shift_project`) and pin it in the note — `place.jl` will reuse exactly this call.

- [ ] **Step 3: Decide the solve path and write the decision note**

Decision rule:
- If `solve_cluster` raw gives us `offsets` + `dropped` and we are content to recompute overlaps ourselves (SPEC §1 default) → use raw `solve_cluster`.
- If `TextRepelAlgorithm(reset=false)` is ergonomic and `solve_stats().overlaps` is trustworthy → prefer it (removes our overlap recompute). Either is acceptable; **record which, and why, at the top of `place.jl`.**

- [ ] **Step 4: Commit the spike + decision**

```bash
git add examples/atlas/prep/spike_timing.jl
git commit -m "spike(atlas): confirm per-frame projection timing + warm-start damping; pin solve path"
```

---

## Task 2: Acquire + commit the basemap data (§6)

**Files:**
- Create: `examples/atlas/prep/clip.jl` (network, bbox-hardcoded, one-time)
- Create (generated, then committed): `examples/atlas/data/coastline.geojson`, `data/land.geojson`
- Create (hand-authored): `examples/atlas/data/towns.csv`, `data/SOURCE.txt`

- [ ] **Step 1: Write `prep/clip.jl`** — download NE 1:10m coastline + land from `nvkelso/natural-earth-vector` (raw GitHub), clip to bbox `lon ∈ [-122.2,-119.6], lat ∈ [34.3,37.0]` (covers Monterey Bay → Pt Conception with margin), write minified GeoJSON to `data/`. Use `Downloads.download`, `GeoJSON.read`, `GeoInterface` to filter features whose bbox intersects, re-serialize. Print vertex counts (assert coastline ≳ 400 verts — the SPEC's 10m-not-50m check).

- [ ] **Step 2: Run the prep once + eyeball vertex counts**

Run:
```bash
cd /home/jonathanchen/projects/TextMeasure.jl-gallery/examples/atlas
julia --project prep/clip.jl
```
Expected: `data/coastline.geojson` and `data/land.geojson` written, total < 65 KB, coastline vertex count in the hundreds (NOT ~4 — that would mean 50m data slipped in).

- [ ] **Step 3: Hand-author `data/towns.csv`** with header `town_id,name,lon,lat,pop,rank,source`. Rows: the 8 in-bbox NE `populated_places` verbatim (`source=NE`, real lon/lat/POP_MAX/SCALERANK), then the hero necklace + supporting towns hand-placed (`source=curated`): San Luis Obispo, Santa Maria, Santa Barbara, Salinas, Monterey (majors); Morro Bay, Pismo Beach, Atascadero, Paso Robles, Lompoc (mid); Cambria, San Simeon, Los Osos, Avila Beach, Cayucos (necklace). `town_id` is a stable small integer (1..N) — **this is the warm-start key; never renumber it.** `rank`/`pop` ordinally correct for LoD priority (§3 ladder).

- [ ] **Step 4: Write `data/SOURCE.txt`** stating: coastline/land = Natural Earth 1:10m (public domain, via nvkelso/natural-earth-vector, no attribution required); towns marked `source=NE` are verbatim NE rows; towns marked `source=curated` are hand-placed with ordinally-correct priority. This text also feeds the caption's "three-layer honesty" line.

- [ ] **Step 5: Commit the committed data subset (NOT a Manifest)**

```bash
git add examples/atlas/prep/clip.jl examples/atlas/data/
git commit -m "data(atlas): commit clipped NE 1:10m basemap + curated towns.csv + SOURCE"
```

---

## Task 3: `data.jl` — load + project into shared map-units (§6) [unit]

**Files:**
- Create: `examples/atlas/src/data.jl`
- Create: `examples/atlas/test/test_data.jl`
- Modify: `examples/atlas/src/Atlas.jl` (uncomment `include("data.jl")`), `test/runtests.jl`

- [ ] **Step 1: Write the failing test** (`test/test_data.jl`)

```julia
using Atlas: load_atlas_data, project_point, PHI0, KX
using Test

@testset "data: projection + load" begin
    # cos φ0 x-correction is a pure affine: x scales by kx, y unchanged.
    x0, y0 = project_point(-121.0, 35.5)
    x1, y1 = project_point(-120.0, 35.5)
    @test y0 == 35.5
    @test isapprox(x1 - x0, KX * 1.0; atol=1e-9)     # 1° lon → kx map-units

    d = load_atlas_data()
    @test length(d.towns) ≥ 20
    @test allunique(t.town_id for t in d.towns)
    @test any(t.name == "San Luis Obispo" for t in d.towns)
    @test count(t -> t.source == "NE", d.towns) == 7   # Fresno excluded (off-subject)
    @test length(d.coastline) ≥ 1 && sum(length, d.coastline) ≥ 400   # 10m, not 50m
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `julia --project -e 'using Pkg; Pkg.test()' 2>&1 | tee test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log` (from `examples/atlas`)
Expected: FAIL — `load_atlas_data` not defined.

- [ ] **Step 3: Implement `src/data.jl`**

```julia
using CSV, GeoJSON, GeoInterface, GeometryBasics
using GeometryBasics: Point2f

const PHI0 = 35.7                       # reference latitude (deg)
const KX   = cosd(PHI0)                 # ≈ 0.812 — x-correction factor

"Pure affine lon/lat → shared map-units (x compressed by cos φ0, y = lat)."
project_point(lon::Real, lat::Real) = (KX * lon, float(lat))

struct Town
    town_id :: Int
    name    :: String
    pos     :: Point2f      # projected map-units
    pop     :: Int
    rank    :: Int
    source  :: String
end

struct AtlasData
    coastline :: Vector{Vector{Point2f}}   # projected polylines
    land      :: Vector{Vector{Point2f}}   # projected rings
    towns     :: Vector{Town}
end

const _DATA_DIR = normpath(joinpath(@__DIR__, "..", "data"))

function _load_lines(path)
    fc = GeoJSON.read(read(path, String))
    out = Vector{Point2f}[]
    for feat in fc
        for ring in GeoInterface.coordinates(GeoInterface.geometry(feat))
            # ring may be nested (MultiLineString/Polygon); flatten one level as needed
            pts = eltype(ring) <: Number ? [ring] : ring
            push!(out, [Point2f(project_point(p[1], p[2])...) for p in pts])
        end
    end
    out
end

function load_atlas_data()
    coastline = _load_lines(joinpath(_DATA_DIR, "coastline.geojson"))
    land      = _load_lines(joinpath(_DATA_DIR, "land.geojson"))
    towns = Town[]
    for r in CSV.File(joinpath(_DATA_DIR, "towns.csv"))
        push!(towns, Town(r.town_id, r.name,
                          Point2f(project_point(r.lon, r.lat)...),
                          r.pop, r.rank, r.source))
    end
    AtlasData(coastline, land, towns)
end
```

> The GeoJSON nesting depth (`coordinates` returns LineString vs MultiLineString vs Polygon rings) depends on the actual NE feature types — adjust `_load_lines`'s flattening to whatever `prep/clip.jl` emitted; the test's `sum(length, d.coastline) ≥ 400` is the guard.

- [ ] **Step 4: Wire includes** — add `include("data.jl")` to `Atlas.jl` (after `using` lines) and `include("test_data.jl")` to `runtests.jl`.

- [ ] **Step 5: Run to verify it passes**

Run: `Pkg.test()` (as above). Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add examples/atlas/src/data.jl examples/atlas/src/Atlas.jl examples/atlas/test/
git commit -m "feat(atlas): load + cosφ0-project basemap and towns into map-units"
```

---

## Task 4: `camera.jl` — geometric zoom + seamless-loop easing (§5) [unit]

**Files:**
- Create: `examples/atlas/src/camera.jl`
- Create: `examples/atlas/test/test_camera.jl`
- Modify: `Atlas.jl`, `runtests.jl`

Constants from §5: `W_WIDE=3.0`, `W_TIGHT=0.30` (degrees of lon, pre-projection); centers `WIDE=(-121.0,35.5)`, `TIGHT=(-120.66,35.30)`; `N_FRAMES=360`, `FPS=30`.

- [ ] **Step 1: Write the failing test**

```julia
using Atlas: view_width, view_center, camera_rect, W_WIDE, W_TIGHT, N_FRAMES
using Test

@testset "camera: geometric zoom + seamless loop" begin
    @test view_width(0.0) ≈ W_WIDE
    @test view_width(0.5) ≈ W_TIGHT          # apex at the loop midpoint
    @test view_width(1.0) ≈ W_WIDE           # loop closes on width
    # geometric (log-linear) on the way down: midpoint of first half is the geo-mean
    @test view_width(0.25) ≈ exp((log(W_WIDE)+log(W_TIGHT))/2) rtol=0.05
    # velocity ~0 at seam and apex (smoothstep dwell) → finite-diff slope tiny
    d(f,p;h=1e-4) = (f(p+h)-f(p-h))/(2h)
    for p in (0.0, 0.5, 1.0)
        @test abs(d(view_width, mod(p,1.0))) < 0.2
    end
    # center pans toward the cluster and returns
    @test view_center(0.5)[1] > view_center(0.0)[1]   # panned east (less negative lon)
    @test view_center(1.0) ≈ view_center(0.0)
end
```

- [ ] **Step 2: Run — expect FAIL** (`view_width` undefined).

- [ ] **Step 3: Implement `src/camera.jl`**

```julia
const W_WIDE   = 3.0
const W_TIGHT  = 0.30
const N_FRAMES = 360
const FPS      = 30
const _CWIDE   = (-121.0, 35.5)
const _CTIGHT  = (-120.66, 35.30)

smoothstep(t) = (t = clamp(t, 0, 1); t*t*(3 - 2t))

"Triangle phase 0→1→0 over the loop, smoothstep-eased per half (vel=0 at 0,½,1)."
function _dive(p)
    p = mod(p, 1.0)
    half = p < 0.5 ? p/0.5 : (1 - p)/0.5      # 0→1 down, 1→0 up
    return smoothstep(half)                    # eased dive fraction in [0,1]
end

"Geometric (log-interpolated) view width at loop phase p∈[0,1)."
view_width(p) = exp((1 - _dive(p))*log(W_WIDE) + _dive(p)*log(W_TIGHT))

"Center pans WIDE→TIGHT→WIDE on the same eased clock."
function view_center(p)
    d = _dive(p)
    ( (1-d)*_CWIDE[1] + d*_CTIGHT[1],
      (1-d)*_CWIDE[2] + d*_CTIGHT[2] )
end

"Axis limits Rect (in projected map-units) for loop phase p; aspect from page (w:h)."
function camera_rect(p; aspect = 16/10)
    w_deg = view_width(p)
    cx, cy = view_center(p)
    # project center + half-extents into map-units (x compressed by KX)
    hx = KX * w_deg / 2
    hy = (w_deg / aspect) / 2
    px = KX * cx
    (px - hx, px + hx, cy - hy, cy + hy)   # (xmin,xmax,ymin,ymax) for limits!
end
```

- [ ] **Step 4: Run — expect PASS.** Wire includes (`camera.jl` after `data.jl`; `test_camera.jl`).

- [ ] **Step 5: Commit** — `feat(atlas): seamless geometric zoom-dive camera (van Wijk easing)`

---

## Task 5: `lod.jl` — level-of-detail gate with hysteresis (§3) [unit]

**Files:**
- Create: `examples/atlas/src/lod.jl`, `examples/atlas/test/test_lod.jl`
- Modify: `Atlas.jl`, `runtests.jl`

Ladder (§3), expressed as per-town **switch-on width** `w_on` derived from `rank`/`pop`; switch-off at `1.08*w_on` (hysteresis).

- [ ] **Step 1: Write the failing test**

```julia
using Atlas: active_ids, w_on_for, load_atlas_data
using Test

@testset "lod: ladder + hysteresis" begin
    d = load_atlas_data()
    byname = Dict(t.name => t for t in d.towns)
    slo   = byname["San Luis Obispo"]
    cambr = byname["Cambria"]
    @test w_on_for(slo)   ≥ 1.5        # a major: eligible while wide
    @test w_on_for(cambr) ≤ 0.7        # a necklace town: only near the floor

    wide = active_ids(d.towns, 2.0, Int[])
    @test slo.town_id in wide
    @test !(cambr.town_id in wide)

    tight = active_ids(d.towns, 0.35, [slo.town_id])
    @test cambr.town_id in tight && slo.town_id in tight

    # hysteresis: a town active at w just below its w_on stays active when w drifts
    # back up slightly (no flicker), but turns off past 1.08*w_on.
    w = w_on_for(cambr)
    on  = active_ids(d.towns, w*0.99, Int[])
    @test cambr.town_id in on
    still = active_ids(d.towns, w*1.05, on)        # within hysteresis band → held
    @test cambr.town_id in still
    off = active_ids(d.towns, w*1.20, on)          # past 1.08×  → dropped
    @test !(cambr.town_id in off)
end
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement `src/lod.jl`**

```julia
"Switch-on view width for a town from its LoD priority (majors appear wide, necklace late)."
function w_on_for(t)::Float64
    t.rank ≤ 5 ? 3.0 :          # majors: visible from the widest establishing shot
    t.rank ≤ 7 ? 1.5 :          # mid-dive band
                 0.7            # necklace: only as the cluster opens
end

const _HYST = 1.08

"Town ids eligible at view width w, with hysteresis vs the previously-active set."
function active_ids(towns, w::Real, prev_active)
    prev = Set(prev_active)
    ids = Int[]
    for t in towns
        won = w_on_for(t)
        thresh = (t.town_id in prev) ? _HYST*won : won   # sticky-off band
        w ≤ thresh && push!(ids, t.town_id)
    end
    ids
end
```

- [ ] **Step 4: Run — expect PASS.** Wire includes.
- [ ] **Step 5: Commit** — `feat(atlas): LoD eligibility ladder with anti-flicker hysteresis`

---

## Task 6: `place.jl` — measure + warm-start solve + deterministic overlap recompute (§1, §2) [unit]

The core. Uses the Task-1 decision (raw `solve_cluster` vs `TextRepelAlgorithm`). Below assumes raw `solve_cluster` (SPEC default); if Task 1 chose the algorithm path, swap the solve call but keep the same `FramePlacement` output and the **own** overlap recompute (needed for the golden invariant regardless).

**Files:**
- Create: `examples/atlas/src/place.jl`, `examples/atlas/test/test_place.jl`
- Modify: `Atlas.jl`, `runtests.jl`

- [ ] **Step 1: Write the failing test**

```julia
using Atlas: measure_boxes, solve_frame, recompute_overlaps, FramePlacement
using Atlas: load_atlas_data
using GeometryBasics: Point2f, Vec2f, Rect2f
using Test

@testset "place: measure + warm-start solve + overlap recompute" begin
    d = load_atlas_data()
    # box sizes are positive and proportional to name length (measured, not guessed)
    sizes = measure_boxes(["SLO", "San Luis Obispo"]; fontsize=11.0)
    @test all(s -> s[1] > 0 && s[2] > 0, sizes)
    @test sizes[2][1] > sizes[1][1]                      # longer string → wider box

    ids     = [t.town_id for t in d.towns][1:6]
    anchors = [Point2f(100i, 100) for i in 1:6]          # forced collisions on a row
    boxes   = [Vec2f(60,14) for _ in 1:6]
    bounds  = Rect2f(0,0,800,400)

    fp = solve_frame(ids, anchors, boxes, bounds; prev=Dict{Int,Vec2f}(), settled=Set{Int}())
    @test fp isa FramePlacement
    @test recompute_overlaps(fp) == 0                    # the headline invariant
    @test length(fp.offsets) == length(ids)

    # warm-start: feeding fp's offsets back yields ~identical placement (damped)
    fp2 = solve_frame(ids, anchors, boxes, bounds;
                      prev=Dict(id => fp.offsets[i] for (i,id) in enumerate(ids)),
                      settled=Set(ids))
    @test recompute_overlaps(fp2) == 0
    @test maximum(maximum(abs.(fp.offsets[i] .- fp2.offsets[i])) for i in 1:6) < 1.0
end
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement `src/place.jl`**

```julia
# DECISION (record from Task 1): using raw `solve_cluster` + own overlap recompute.
# Read-after-update projection call confirmed in prep/spike_timing.jl: <PASTE THE PINNED CALL>.
using Makie, CairoMakie
using MakieTextRepel: ProjectionSolver, RepelParams, solve_cluster
using GeometryBasics: Point2f, Vec2f, Rect2f

const _LABEL_FONT = HouseStyle.plexmono("Regular")

struct FramePlacement
    ids     :: Vector{Int}
    anchors :: Vector{Point2f}
    sizes   :: Vector{Vec2f}
    offsets :: Vector{Vec2f}
    dropped :: BitVector
end

"Measured pixel boxes (w,h) for label strings via TextMeasure MakieBackend (px_per_unit=1)."
function measure_boxes(strings; fontsize=Float64(HouseStyle.RAMP.body), font=_LABEL_FONT)
    b = MakieBackend(; font=font, fontsize=fontsize, px_per_unit=1)
    m = font_metrics(b)
    boxh = m.ascent + m.descent
    [Vec2f(layout(prepare(b, s)).size[1], boxh) for s in strings]
end

const _PARAMS = RepelParams(; only_move=:both, box_padding=4.0,
                            point_padding=5.0, min_segment_length=2.0)
const _SOLVER = ProjectionSolver(_PARAMS)

"One frame's placement. `prev`: town_id→prior offset (warm start). `settled`: ids to pin."
function solve_frame(ids, anchors, sizes, bounds; prev, settled)
    init = any(id -> haskey(prev, id), ids) ?
           Vec2f[get(prev, id, Vec2f(0,0)) for id in ids] : nothing
    pin  = BitVector(id in settled && haskey(prev, id) for id in ids)
    pinned = Vec2f[prev[id] for id in ids if id in settled && haskey(prev, id)]
    r = solve_cluster(_SOLVER, anchors, sizes, bounds;
                      init_state=init, pin_mask=pin, pinned_offsets=pinned)
    FramePlacement(collect(ids), collect(anchors), collect(sizes), r.offsets, r.dropped)
end

"Count hard label-box overlaps deterministically from offsets+sizes (our own, RNG-free)."
function recompute_overlaps(fp::FramePlacement)
    rects = [Rect2f(fp.anchors[i][1]+fp.offsets[i][1] - fp.sizes[i][1]/2,
                    fp.anchors[i][2]+fp.offsets[i][2] - fp.sizes[i][2]/2,
                    fp.sizes[i][1], fp.sizes[i][2])
             for i in eachindex(fp.ids) if !fp.dropped[i]]
    n = 0
    for i in 1:length(rects), j in i+1:length(rects)
        a, b = rects[i], rects[j]
        ox = min(a.origin[1]+a.widths[1], b.origin[1]+b.widths[1]) - max(a.origin[1], b.origin[1])
        oy = min(a.origin[2]+a.widths[2], b.origin[2]+b.widths[2]) - max(a.origin[2], b.origin[2])
        (ox > 0.5 && oy > 0.5) && (n += 1)    # 0.5px slack absorbs legalize float drift
    end
    n
end
```

> If `recompute_overlaps` is occasionally 1 on a pathological forced-collision input, that's a real solver-capacity signal, not a test bug — reduce the test's anchor density or assert `≤ budget`. The **golden** invariant (Task 10) asserts `== 0` on the real frames, which are LoD-capacity-bounded.

- [ ] **Step 4: Run — expect PASS.** Wire includes.
- [ ] **Step 5: Commit** — `feat(atlas): warm-start placement solve + deterministic overlap recompute`

---

## Task 7: `fade.jl` — per-town alpha + sticky/tween state (§3) [unit]

**Files:**
- Create: `examples/atlas/src/fade.jl`, `examples/atlas/test/test_fade.jl`
- Modify: `Atlas.jl`, `runtests.jl`

- [ ] **Step 1: Write the failing test**

```julia
using Atlas: FadeState, update_fade!, alpha_of, FADE_FRAMES
using Test

@testset "fade: smoothstep fade-in keyed by town_id" begin
    fs = FadeState()
    update_fade!(fs, [1, 2], 0)             # both appear at frame 0
    @test alpha_of(fs, 1) == 0.0            # frame 0 of fade → 0
    for f in 1:FADE_FRAMES
        update_fade!(fs, [1, 2], f)
    end
    @test alpha_of(fs, 1) ≈ 1.0             # fully faded in after FADE_FRAMES
    @test alpha_of(fs, 99) == 0.0           # unknown id → invisible
    update_fade!(fs, [1], FADE_FRAMES+1)    # 2 leaves the active set
    @test alpha_of(fs, 2) == 0.0            # dropped → 0 (no lingering ghost)
end
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement `src/fade.jl`**

```julia
const FADE_FRAMES = 9

mutable struct FadeState
    born :: Dict{Int,Int}     # town_id → frame it entered the active set
end
FadeState() = FadeState(Dict{Int,Int}())

"Register the active set for `frame`; record births, forget departures."
function update_fade!(fs::FadeState, active_ids, frame::Int)
    a = Set(active_ids)
    for id in active_ids
        haskey(fs.born, id) || (fs.born[id] = frame)
    end
    for id in collect(keys(fs.born))
        id in a || delete!(fs.born, id)
    end
    fs._last = frame
    fs
end
# add `_last::Int` field (default -1) to FadeState for alpha_of; shown inline:

"smoothstep alpha for a town at the current frame (0 if unknown/departed)."
function alpha_of(fs::FadeState, id::Int)
    haskey(fs.born, id) || return 0.0
    smoothstep((fs._last - fs.born[id]) / FADE_FRAMES)
end
```

> Add `_last::Int` to the struct (init `-1`) so `alpha_of` knows the current frame without re-passing it; the test above calls `update_fade!` before each `alpha_of`. Keep `smoothstep` shared from `camera.jl`.

- [ ] **Step 4: Run — expect PASS.** Wire includes.
- [ ] **Step 5: Commit** — `feat(atlas): per-town smoothstep fade-in/out keyed by town_id`

---

## Task 8: `render.jl` — basemap + labels + chrome (§7) [visual gate]

**Files:**
- Create: `examples/atlas/src/render.jl`
- Modify: `Atlas.jl`

This task has no unit test (pixels). Build it incrementally and **look at the output**.

- [ ] **Step 1: Implement the palette + axis + basemap layers**

```julia
using CairoMakie, Makie
import HouseStyle: PAPER, INK, BRASS, GRAY, RAMP, fraunces, plexmono

const WATER      = Makie.RGBf((0xDC,0xE3,0xE5) ./ 255...)
const WATER_LINE = Makie.RGBf((0x9F,0xB2,0xBA) ./ 255...)

function _new_axis(; pagepx=(1600,1000))
    fig = Figure(; size=pagepx, backgroundcolor=WATER)
    ax  = Axis(fig[1,1]; backgroundcolor=WATER, aspect=DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    fig, ax
end

"Water bg, land paper poly, 0.75px ink coastline, 0.25px brass graticule."
function draw_basemap!(ax, d)
    for ring in d.land
        poly!(ax, ring; color=PAPER, strokewidth=0)
    end
    for line in d.coastline
        lines!(ax, line; color=INK, linewidth=0.75)
    end
    # graticule at whole degrees (projected): brass 0.25px — added in step 2
end
```

- [ ] **Step 2: Implement `draw_labels!`** — for a `FramePlacement` + `FadeState`: `text!(ax, positions; offset=fp.offsets, markerspace=:pixel, color=(INK, α), fontsize, font)`, brass 0.5px leaders via `linesegments!(...; space=:pixel)` only where a label is displaced beyond a snug threshold, `scatter!` markers AFTER (2–4px ink + paper halo; the SLO `town_id` dot in BRASS). Alpha per town from `alpha_of`.

- [ ] **Step 3: Implement `draw_chrome!`** — masthead "THE ATLAS" (Fraunces `RAMP.display`, tracked caps INK) with a brass dateline rule; region "CENTRAL COAST" (Fraunces `RAMP.title`); 1.0px brass neat-line border; corner cartouche with scale bar + the live metrics line (`Printf`): `w 0.55° · 17/17 placed · 2 entering · 1 leader`; `HouseStyle.footer("The Atlas")`.

- [ ] **Step 4: Visual gate** — render one still at the apex and open it:

```bash
cd /home/jonathanchen/projects/TextMeasure.jl-gallery/examples/atlas
julia --project -e 'using Atlas; Atlas._dev_still(0.42, "atlas-dev.png")'   # temp helper
```
Open `atlas-dev.png`. Confirm against §7: paper land on grey-blue water, hairline coast, labels horizontal and **not overlapping**, brass masthead + neat-line, one brass dot at SLO. Record one line of what you saw. **Do not proceed until it reads as the SPEC describes.**

- [ ] **Step 5: Commit** — `feat(atlas): basemap + label + chrome render layer`

---

## Task 9: `loop.jl` — hero still + seamless MP4 + thumb (§5, §8) [visual gate]

**Files:**
- Create: `examples/atlas/src/loop.jl`, `examples/atlas/build.jl`
- Modify: `Atlas.jl`

- [ ] **Step 1: Implement the per-frame driver** — a function `frame!(ax, state, frame)` that: computes `p=frame/N_FRAMES`; `limits!(ax, camera_rect(p)...)`; `update_state_before_display!(fig)` (the Task-1 pin); projects active anchors to px (the pinned projection call); `active_ids` (LoD+hysteresis carrying `prev_active`); `update_fade!`; `solve_frame` (warm-start carrying `prev_offset` by `town_id`); draws via `render.jl`. Maintain `prev_offset`, `prev_active`, `settled` across frames.

- [ ] **Step 2: Implement `render_loop`** (copy Tide's record→ffmpeg shape):

```julia
function render_loop(path = joinpath(@__DIR__, "..", "atlas-dive.mp4");
                     scale=2, fps=FPS, n=N_FRAMES, crf=18)
    d = load_atlas_data(); fig, ax = _new_axis()
    state = _init_state(d)
    record(fig, path, 1:n; framerate=fps) do frame
        frame!(ax, state, mod(frame, n))     # frame n ≡ 0: seamless
    end
    path
end
```

- [ ] **Step 3: Implement `render_hero`** — render the single mid-dive still at `p≈0.42` (§8) at `scale=8` to `atlas-hero.png`; `render_thumb` → small ghosted `atlas-thumb.png`. `build.jl` = `using Atlas; Atlas.render_hero()`.

- [ ] **Step 4: Visual gate** — produce both and open them:

```bash
cd /home/jonathanchen/projects/TextMeasure.jl-gallery/examples/atlas
julia --project build.jl                       # hero
julia --project -e 'using Atlas; Atlas.render_loop()'   # mp4
```
Open `atlas-hero.png` and scrub `atlas-dive.mp4`. Confirm: the dive falls and rises seamlessly (no cut at the loop seam), the Cambria–Morro Bay–SLO–Pismo necklace **fills in town-by-town** as it tightens, settled labels **hold still** (warm-start working), labels never overlap, leaders are rare. Record what you saw. This is the real deliverable — **green tests are not this gate.**

- [ ] **Step 5: Commit** (artifacts are build outputs — confirm they're gitignored like Tide's `tide-loop.mp4`; commit only code + small committed PNGs if the gallery commits heroes):

```bash
git add examples/atlas/src/loop.jl examples/atlas/build.jl examples/atlas/src/Atlas.jl
git commit -m "feat(atlas): seamless zoom-dive loop + hero still + thumbnail"
```

---

## Task 10: `golden.jl` + `test_golden.jl` — placement-table digest (§8) [unit]

Prototype hash stability **first** (SPEC §8: relative offsets, 2dp, not absolute projected px).

**Files:**
- Create: `examples/atlas/src/golden.jl`, `examples/atlas/test/test_golden.jl`, `examples/atlas/test/golden/`
- Modify: `Atlas.jl`, `runtests.jl`

- [ ] **Step 1: Implement `src/golden.jl`** — `geometry_rows()` runs the frame pipeline at the **6 pinned frames** `(0,60,120,180,240,300)` using a deterministic `MonospaceBackend` for box measurement (so the digest is font-path-independent, like Tide/Woven). Each row (sorted by `town_id` within frame): `"frame|town_id|name|slot_or_offx|offy|alpha_q|has_leader"` where offsets are **relative to the anchor**, rounded to 2dp; `alpha_q` rounded to 0.05; `has_leader` a bool. `atlas_digest() = HouseStyle.digest_rows(geometry_rows())`.

```julia
using MakieTextRepel: ProjectionSolver, RepelParams, solve_cluster
import HouseStyle

const GOLDEN_FRAMES = (0, 60, 120, 180, 240, 300)
golden_boxes(strings) = measure_boxes(strings; fontsize=11.0, font="monospace",
                                      backend = MonospaceBackend)   # see note

function geometry_rows()
    d = load_atlas_data()
    rows = String[]
    state = _init_golden_state(d)               # same pipeline, MonospaceBackend boxes
    last = -1
    for f in GOLDEN_FRAMES
        for g in last+1:f                        # advance deterministically frame-by-frame
            _golden_step!(state, d, g)
        end
        last = f
        for (i, id) in enumerate(sort(state.active))
            off = state.offsets[id]
            push!(rows, string(f, "|", id, "|", state.name[id], "|",
                round(off[1]; digits=2), "|", round(off[2]; digits=2), "|",
                round(state.alpha[id]/0.05)*0.05, "|", state.has_leader[id]))
        end
    end
    rows
end
atlas_digest() = HouseStyle.digest_rows(geometry_rows())
```

> `measure_boxes` (Task 6) must accept a backend factory so golden can pass `MonospaceBackend` instead of `MakieBackend` — add a `backend` kwarg defaulting to `MakieBackend`. The golden pipeline must **not** depend on Makie projection (no `_new_axis`): project anchors with the pure `camera_rect`/`project_point` math directly so it's headless and deterministic.

- [ ] **Step 2: Stability pre-check** — run `geometry_rows()` twice in one session and assert identical; if any row differs, the offsets carry non-determinism (chase it before committing a golden). Then `UPDATE_GOLDEN=1` to write `test/golden/atlas.sha256` + `atlas.rows.txt`.

- [ ] **Step 3: Write `test/test_golden.jl`** (mirror Tide):

```julia
using Atlas: geometry_rows, atlas_digest, GOLDEN_FRAMES
using Test
const GOLDEN_DIR = joinpath(@__DIR__, "golden")

@testset "golden: deterministic Atlas placement table (Monospace, no pixels)" begin
    rows = geometry_rows()
    @test !isempty(rows) && length(rows) > 40
    cs = atlas_digest(); @test length(cs) == 64
    # per-frame invariants from §8
    for f in GOLDEN_FRAMES
        @test any(r -> startswith(r, "$f|"), rows)
    end
    path = joinpath(GOLDEN_DIR, "atlas.sha256")
    if get(ENV, "UPDATE_GOLDEN", "") == "1"
        mkpath(GOLDEN_DIR)
        write(path, cs)
        write(joinpath(GOLDEN_DIR, "atlas.rows.txt"), join(rows, "\n"))
    end
    @test isfile(path)
    @test cs == strip(read(path, String))
end
```

- [ ] **Step 4: Add the overlap/LoD invariant test** to `test_place.jl` or here: for each pinned frame, `recompute_overlaps == 0`, `count(dropped) ≤ budget`, and active-set size matches `active_ids` for that frame's width.

- [ ] **Step 5: Run full suite — expect PASS.** Commit:

```bash
git add examples/atlas/src/golden.jl examples/atlas/test/test_golden.jl examples/atlas/test/golden/ examples/atlas/src/place.jl
git commit -m "test(atlas): golden placement-table digest over 6 dive frames + invariants"
```

---

## Task 11: README + caption honesty + reconcile gallery framing (§0, §coherence)

**Files:**
- Create: `examples/atlas/README.md`
- Modify: `examples/README.md` (gallery index, if it lists pieces), `examples/atlas/SPEC.md` (only the "four faces" line — Glyph Wave being dropped)

- [ ] **Step 1: Write `README.md`** copying Tide's section set: title, the engine concept it demonstrates (measure once → re-place every frame, viewport-driven), file map, the per-frame pipeline (camera → LoD → measure → warm-start solve → fade → render), how to render (`build.jl`, `render_loop`), the **three-layer honesty** caption (TextMeasure measures boxes · MakieTextRepel places · demo drives camera/LoD; coastline + major cities verbatim NE, small towns hand-placed; legalize is continuous not fixed-slot — §4), and reusable ideas.

- [ ] **Step 2: Reconcile the dropped Glyph Wave** — the SPEC's closing "Four faces of one instrument" line (and `examples/README.md` if it enumerates pieces) references **The Glyph Wave**, which is being dropped. Update the gallery tagline to the surviving set (Press · Erasure · Atlas, plus whatever replaces Glyph Wave or three-piece framing) so the gallery is internally consistent. Keep it factual; don't invent a replacement piece.

- [ ] **Step 3: Commit** — `docs(atlas): README + three-layer caption; drop Glyph Wave from gallery framing`

---

## Task 12: Full suite + visual sign-off + finish

- [ ] **Step 1: Run the full Atlas suite yourself** (do not trust a reported pass):

```bash
cd /home/jonathanchen/projects/TextMeasure.jl-gallery/examples/atlas
mkdir -p test-logs
julia --project -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"
echo "EXIT: ${PIPESTATUS[0]}"     # must be 0; do not let `| tee` mask it
```
Expected: all testsets pass, `EXIT: 0`.

- [ ] **Step 2: Visual sign-off** — open `atlas-hero.png` and `atlas-dive.mp4` one final time against §7/§8: hero reads as motion frozen (necklace half-revealed, 2 labels mid-fade, ≤1 leader), loop seam invisible, no overlaps anywhere in the dive. Record the confirmation.

- [ ] **Step 3: Invoke `superpowers:finishing-a-development-branch`** to decide merge/PR/cleanup for the Atlas work on `demos-gallery-greenfield`.

---

## Self-review (completed by plan author)

- **Spec coverage:** §0 boundary → Task 11 caption; §1 solve_cluster → Task 1 + 6; §2 warm-start/timing → Task 1 + 6 + 9; §3 LoD/hysteresis/fade → Task 5 + 7; §4 leaders → Task 8; §5 camera → Task 4 + 9; §6 data/projection → Task 2 + 3; §7 aesthetic → Task 8; §8 still/golden/invariants → Task 9 + 10. The "one bold move" (dive itself; diptych demoted to optional inset) → Task 9 is the dive; the inset is intentionally **omitted** (SPEC says "keep it small or drop it" — dropped to avoid the explainer failure mode; revisit only if the cartouche feels empty).
- **Open implementation decisions deferred to a task (not placeholders):** raw `solve_cluster` vs `TextRepelAlgorithm(reset=false)` → Task 1 decides and records; exact GeoJSON nesting → Task 3 adapts to `prep/clip.jl` output (guarded by the vertex-count test); the projection data→pixel call → pinned in Task 1, reused in Task 6/9.
- **Type consistency:** `Town`, `AtlasData`, `FramePlacement`, `FadeState` field names are used consistently across tasks; `town_id` is the warm-start key everywhere (never vector index); `measure_boxes` gains a `backend` kwarg in Task 6 so Task 10 can pass `MonospaceBackend`.
- **Known soft spots flagged for the implementer:** `Makie.project` may not be the exact call on the installed Makie version (Task 1 pins it); `recompute_overlaps` slack (0.5px) absorbs legalize float drift; the `MakieTextRepel` and `Atlas` UUIDs in Task 0 must be set to real values before instantiate.
