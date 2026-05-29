# #G — CairoMakie Map Feature Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Inner loop: superpowers:test-driven-development (red → green → refactor, each its own commit).

**Goal:** A `MapFeature` example package that renders a US-state silhouette as a cartographic map (POIs, capital, landmarks) with editorial prose wrapping around the silhouette as an irregular obstacle, exported to a PDF with selectable text — Vermont quickstart fully offline from a bundled shapefile.

**Architecture:** Two-layer split mirroring TextMeasure's own measure/layout discipline. (1) A *pure geometry/layout core* — `complement_chord_fn` (the owned deliverable: per-band horizontal-envelope subtraction yielding the page's negative-space intervals), `PageProjection` (lat/lon → page-pixel space via `Proj`), and POI label placement — all deterministic and unit-tested with no render. (2) A *render layer* (`map_feature`) that projects geography, drives `shape_pack` with `complement_chord_fn`, and draws everything with CairoMakie at `px_per_unit=1` against the pinned fonts, then exports a PDF. Text-around-obstacle non-overlap is **guaranteed by construction** (body words live only in `complement_chord_fn`'s negative space) and asserted as a tier-1 `PackedLayout` invariant; PDF text selectability is verified with `pdftotext`.

**Tech Stack:** Julia 1.12; `TextMeasure` + `TextMeasureLayouts` (dev-path); `Shapefile` 0.13.3 (read bundled fixture + write builder); `Proj` (CRS reprojection); `CairoMakie` 0.15.10 (render + PDF); `CensusACS` 0.1.0 (non-VT shapefile/stats fetch); `GeometryBasics` 0.5.10 / `GeometryOps` 0.1.40 (coordinated #C/#D pins; GeometryOps boolean ops AVOIDED). Pinned fonts: **DejaVu Sans** (display/sans), **Liberation Serif** (body).

---

## Verified API facts (probed against the LIVE installed env — corrections to the issue body)

Probed 2026-05-28 in the worktree's instantiated `examples/map_feature` env.

1. **`CensusACS.get_tiger_shapefile(year::Int, geography::String)`** — `geography ∈ {"state","county"}`. Downloads the **entire-US** `cb_<year>_us_<geography>_500k.zip` via **`curl` over FTP** (`ftp://ftp2.census.gov/...`) **into the current working directory** and returns a **`Bool`** — it does NOT subset to a state, unzip, or return geometry/paths. ⟹ **Issue-body correction:** CensusACS "shapefile download … covers our state-polygon need" *understates* the work — map_feature must itself locate the downloaded zip, unzip, `Shapefile.Table` it, filter to the target state, and convert geometry. Confirmed reachable (HTTP 3.25 MB; FTP works in this env).
2. **`CensusACS.get_acs5(; variables::Vector{String}, geography, year, state, county, output_type::Symbol=:dataframe)`** returns a DataFrame. **Requires `ENV["CENSUS_API_KEY"]`** — `error()`s loudly without it (`api.jl:149`). ⟹ Stats path is gated on BOTH network AND an API key.
3. **`CensusACS.get_acs(...)` is effectively broken in 0.1.0**: its default `output_type::Type{T}=DataFrame` (a *Type*) is forwarded to `get_acs5`, whose `output_type::Symbol=:dataframe` expects a *Symbol* ⟹ `MethodError`. ⟹ **Call `get_acs5(...; output_type=:dataframe)` directly**, never `get_acs`. Variables: `B01003_001E` (total population), `B19013_001E` (median household income).
4. **`Shapefile` 0.13.3 HAS write support** (issue/`Shapefile.jl` is not read-only here): `Shapefile.Writer(geoms, feats_namedtuple, crs)` (crs is the **3rd positional** arg, not a kw — pass `nothing` for no `.prj`) + `Shapefile.write(path, writer; force=true)` writes `.shp`/`.shx`/`.dbf`. ⟹ We author the bundled VT fixture programmatically (no hand-rolled binary).
5. **Shapefile read API:** `tbl = Shapefile.Table(path)`; `Shapefile.shapes(tbl)::Vector{Shapefile.Polygon}`; columns via `tbl.STUSPS` / `tbl.NAME` / `tbl.STATEFP` / `tbl.GEOID`. A `Shapefile.Polygon` has `.points` (each with `.x`,`.y`) and `.parts` (0-based part-start offsets; VT has 1 part, CA/HI have several). Census `cb_2023_us_state_500k` has 56 features; **Vermont** = NAME "Vermont", STATEFP "50", **1634 points, 1 part**, lon ∈ [-73.438, -71.465], lat ∈ [42.727, 45.017].
6. **`Proj.Transformation("EPSG:4326", dest; always_xy=true)`** is callable `(lon, lat) -> (x, y)`; works offline (PROJ artifacts bundled). Verified `EPSG:4326 → EPSG:5070` (CONUS Albers Equal-Area) on a VT vertex. **`always_xy=true` is required** (inputs are lon,lat order). Hawaii: use `EPSG:3759` (NAD83 / Hawaii zone, ~Transverse-Mercator) or a Mercator pixel fit.
7. **`MakieBackend(; font=Makie.automatic, fontsize=12, px_per_unit=1.0)`** (ext constructor); `measure` sums `FTA.hadvance` with NO kerning; use `px_per_unit=1` to match Makie markerspace (per CLAUDE.md). `Segment` fields are **`.str` / `.width` / `.kind`** (word text = `prep.segments[i].str`). Exports: `prepare, layout, line_top, subprep, MakieBackend, MonospaceBackend`.
8. **`shape_pack(prep, chord_fn; line_advance, min_chord_width=24, overflow_strategy=:widest_row, …)`** — `chord_fn` may be a plain closure `(y_top,y_bottom)->Vector{Tuple{Float64,Float64}}`; returned intervals MUST be sorted-ascending & pairwise-disjoint; empty ⇒ band skipped. `Placement(segment_index, x, y)` where `y == (band-1)*line_advance + ascent`. `complement_chord_fn` returns a plain closure (the issue specifies "returns a closure").
9. **Env:** fonts DejaVu Sans + Liberation Serif present (`/usr/share/fonts/...`); `pdftotext` 24.02.0 on PATH; `unzip` present.

### Flagged decisions for the gate
- **GeoMakie dropped from functional deps.** The issue lists `GeoMakie` "for the projection step," but we project to **page-pixel space *before* `shape_pack`** (so a draw-time `GeoAxis` auto-projection doesn't fit the pipeline). `Proj.Transformation` — GeoMakie's own underlying projection engine — does exactly what we need and is leaner. **Plan removes `GeoMakie` from `[deps]` and adds `Proj`.** If the orchestrator wants GeoMakie retained for gallery (#I) consistency, that's a one-line revert. *(Probe left GeoMakie installed; Task 1 removes it.)*
- **Golden = token-set floor, not raw-byte checksum.** Per orchestration spec (pdftotext = embedding/selectability ONLY, "regression floors not hard counts," PDF coords don't round-trip), the committed golden is the sorted set of extracted alphanumeric tokens; the test asserts the current extraction **⊇** the golden (a floor: never silently lose selectable words) AND that every input string (masthead/byline/POI names/stat labels/body) appears. A raw sha256 of the token file is also committed as an informational exact-regression signal (allowed to be updated when Cairo/font versions legitimately change).

---

## File structure

```
examples/map_feature/
├── Project.toml                         # deps + [compat] + [extras]Test + [targets]test  (Task 1)
├── README.md                            # quickstart (Task 11)
├── src/
│   ├── MapFeature.jl                    # module: usings, includes, exports          (Task 2)
│   ├── complement_chord_fn.jl           # OWNED helper — pure interval arithmetic     (Task 3)
│   ├── projection.jl                    # PageProjection, project_polygon             (Task 4)
│   ├── poi.jl                           # POI struct, LabelBox, place_poi_labels      (Task 5)
│   ├── data.jl                          # load_state_shapefile/load_vermont/pois/stats/fetch (Task 6,7)
│   └── render.jl                        # map_feature(...) -> Figure, render_to_pdf   (Task 8)
├── data/
│   ├── vermont.shp / .shx / .dbf        # BUNDLED fixture (committed; built Task 0)
│   ├── pois.toml                        # VT POIs (8–15) + bundled VT stats           (Task 6)
│   └── build_fixture.jl                 # documented one-time network builder (committed, not in CI) (Task 0)
└── test/
    ├── runtests.jl                      # aggregator                                  (Task 2)
    ├── test_complement_chord_fn.jl      # negative-space intervals + bbox non-overlap (Task 3)
    ├── test_projection.jl               # affine fit, aspect, y-flip                  (Task 4)
    ├── test_poi_labels.jl               # pairwise label non-overlap                  (Task 5)
    ├── test_data.jl                     # bundled VT load (offline)                   (Task 6)
    ├── test_render_pdf.jl               # render VT → pdftotext selectability + golden(Task 9)
    └── goldens/
        ├── vermont_tokens.txt           # token-set floor golden                      (Task 9)
        └── vermont_tokens.sha256        # informational exact checksum                (Task 9)
```

Coordinate frame everywhere downstream of projection: **page-pixel, block-top** (y = 0 at page top, increasing downward) — identical to `layout`/`shape_pack`/`FontMetrics`.

---

## Task 0: Bundled Vermont fixture + builder (DONE in probe; formalize)

**Files:**
- Create: `examples/map_feature/data/vermont.shp` / `.shx` / `.dbf` (already built by probe; 26.3 KB total)
- Create: `examples/map_feature/data/build_fixture.jl`

The fixture is already produced by `probe/build_vermont_fixture.jl`. This task moves the builder to a clean committed location and verifies the bundled files.

- [ ] **Step 1: Write `data/build_fixture.jl`** (SPDX header; documented one-time, network-using; NOT run in CI):

```julia
# SPDX-License-Identifier: MIT
# One-time builder for the bundled Vermont fixture. Requires network (Census FTP).
# Run from the package root:  julia --project examples/map_feature/data/build_fixture.jl
# Not invoked by the test suite — the committed data/vermont.{shp,shx,dbf} is the offline source.
using Shapefile

const DATADIR = @__DIR__
tmp = mktempdir()
zip = joinpath(tmp, "states.zip")
run(`curl -s -o $zip ftp://ftp2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_state_500k.zip`)
run(`unzip -o -q $zip -d $tmp`)
tbl = Shapefile.Table(joinpath(tmp, "cb_2023_us_state_500k.shp"))
i = findfirst(==("VT"), tbl.STUSPS)
i === nothing && error("Vermont not found in Census state file")
geom = Shapefile.shapes(tbl)[i]
w = Shapefile.Writer([geom], (NAME=["Vermont"], STUSPS=["VT"], STATEFP=["50"]), nothing)
Shapefile.write(joinpath(DATADIR, "vermont.shp"), w; force=true)
println("wrote vermont.{shp,shx,dbf} (", length(geom.points), " points)")
```

- [ ] **Step 2: Verify the committed fixture round-trips** (no network):

Run: `julia --project=examples/map_feature -e 'using Shapefile; t=Shapefile.Table("examples/map_feature/data/vermont.shp"); g=Shapefile.shapes(t)[1]; println(t.NAME[1], " ", length(g.points))'`
Expected: `Vermont 1634`

- [ ] **Step 3: Commit** (fixture is a DATA fixture — explicitly committed per wave-1 conventions; Manifest stays gitignored):

```bash
git add examples/map_feature/data/vermont.shp examples/map_feature/data/vermont.shx examples/map_feature/data/vermont.dbf examples/map_feature/data/build_fixture.jl
git commit -m "data(map_feature): bundle offline Vermont shapefile fixture + builder (#G)"
```

---

## Task 1: Project.toml — deps, compat, test target, gitignore

**Files:**
- Modify: `examples/map_feature/Project.toml`
- Create: `examples/map_feature/.gitignore`

- [ ] **Step 1: Drop GeoMakie, add Proj, add `[extras]`/`[targets]`.** Final `Project.toml` (UUIDs already resolved by Pkg; keep TextMeasure/TextMeasureLayouts dev-pathed via Manifest):

```toml
name = "MapFeature"
uuid = "29a845f9-a006-4577-a52d-4ea593f1e246"
version = "0.1.0"
authors = ["Jonathan Chen <jwhc@ucla.edu>"]

[deps]
CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
CensusACS = "5cdc1628-db7d-4f1a-9a42-d0831b0d3a5e"
GeometryBasics = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
GeometryOps = "3251bfac-6a57-4b6d-aa61-ac1fef2975ab"
HTTP = "cd3eb016-35fb-5094-929b-558a96fad6f3"
Proj = "c94c279d-25a6-4763-9509-64d165bea63e"
Shapefile = "8e980c4a-a4fe-5da2-b3a7-4b4b0353a2f4"
TOML = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
TextMeasure = "06791c1d-2336-41e1-bd6f-a74c63395da6"
TextMeasureLayouts = "57b0e3ea-cc01-4cc3-9e7e-6e97d1609b9f"

[compat]
CairoMakie = "0.15.10"
CensusACS = "0.1.0"
GeometryBasics = "0.5.10"
GeometryOps = "0.1.40"
HTTP = "1.11.0"
Proj = "1"
Shapefile = "0.13.3"
julia = "1.11"

[extras]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Test"]
```

(Note: `TOML` is a Julia stdlib — add to `[deps]` so `import TOML` resolves; no `[compat]` needed. `GeometryOps` stays a dep for `GeometryBasics.Point2`/orientation only — boolean ops are NOT used. Drop `GeometryOps` if Task 3/4/5/8 end up not importing it; verify at Task 10.)

- [ ] **Step 2: Apply removal + re-resolve:**

Run: `julia --project=examples/map_feature -e 'using Pkg; Pkg.rm("GeoMakie"); Pkg.add("TOML"); Pkg.status()'`
Expected: GeoMakie absent; Proj + TOML present; resolves clean.

- [ ] **Step 3: Write `.gitignore`** (Manifest gitignored per wave-1 conventions; data fixtures are force-added in Task 0 so they survive):

```
Manifest.toml
/probe/
*.pdf
*.png
```

- [ ] **Step 4: Commit:**

```bash
git add examples/map_feature/Project.toml examples/map_feature/.gitignore
git commit -m "build(map_feature): pin deps, drop GeoMakie for Proj, add Test target (#G)"
```

---

## Task 2: Module skeleton + test aggregator

**Files:**
- Create: `examples/map_feature/src/MapFeature.jl`
- Create: `examples/map_feature/test/runtests.jl`

- [ ] **Step 1: Write `src/MapFeature.jl`** (includes added as later tasks create files; start with complement_chord_fn only so it precompiles green):

```julia
# SPDX-License-Identifier: MIT
"""
    MapFeature

CairoMakie state map-feature page (#G, demos milestone): a cartographic state
silhouette with editorial prose wrapping around it as an irregular obstacle.
See `docs/superpowers/plans/2026-05-28-G-map-feature.md`.
"""
module MapFeature

using GeometryBasics: Point2
using TextMeasure
using TextMeasureLayouts: shape_pack, Placement, PackedLayout

export complement_chord_fn
export POI, LabelBox, place_poi_labels
export PageProjection, project_polygon, project_point
export load_vermont, load_state_shapefile, load_pois, load_stats
export map_feature, render_to_pdf

include("complement_chord_fn.jl")
# include("projection.jl")   # Task 4
# include("poi.jl")          # Task 5
# include("data.jl")         # Task 6
# include("render.jl")       # Task 8

end # module
```

- [ ] **Step 2: Write `test/runtests.jl`** (aggregator; add includes as tasks land):

```julia
# SPDX-License-Identifier: MIT
using Test
@testset "MapFeature.jl" begin
    include("test_complement_chord_fn.jl")
    # include("test_projection.jl")   # Task 4
    # include("test_poi_labels.jl")   # Task 5
    # include("test_data.jl")         # Task 6
    # include("test_render_pdf.jl")   # Task 9
end
```

- [ ] **Step 3: Verify it loads** (will fail until Task 3 creates the include target — that's the next task's red):

Run: `julia --project=examples/map_feature -e 'using MapFeature'`
Expected after Task 3: no error.

---

## Task 3: `complement_chord_fn` — the owned negative-space helper (PURE)

**Files:**
- Create: `examples/map_feature/src/complement_chord_fn.jl`
- Test: `examples/map_feature/test/test_complement_chord_fn.jl`

- [ ] **Step 1: Write the failing tests** `test/test_complement_chord_fn.jl`:

```julia
# SPDX-License-Identifier: MIT
using Test, MapFeature, TextMeasure
using TextMeasureLayouts: shape_pack
using GeometryBasics: Point2

# A 100×100 square obstacle sitting in the right half of a 400-wide page band.
square(x0, y0, s) = Point2{Float64}[(x0,y0),(x0+s,y0),(x0+s,y0+s),(x0,y0+s)]
PB = (0.0, 0.0, 400.0, 300.0)   # (left, top, right, bottom)

@testset "complement: square obstacle on the right ⇒ left + right intervals" begin
    poly = square(250.0, 50.0, 100.0)         # x∈[250,350], y∈[50,150]
    cf = complement_chord_fn(poly, PB)
    iv = cf(95.0, 105.0)                       # band center y=100 crosses the square
    @test iv == [(0.0, 250.0), (350.0, 400.0)] # negative space L and R of envelope
    @test issorted(iv; by=first)
end

@testset "complement: band above polygon ⇒ full width" begin
    poly = square(250.0, 50.0, 100.0)
    cf = complement_chord_fn(poly, PB)
    @test cf(5.0, 15.0) == [(0.0, 400.0)]      # yc=10 < poly top (50): nothing carved
end

@testset "complement: band outside [top,bottom] ⇒ empty" begin
    poly = square(250.0, 50.0, 100.0)
    cf = complement_chord_fn(poly, PB)
    @test isempty(cf(-15.0, -5.0))             # above page top
    @test isempty(cf(305.0, 315.0))            # below page bottom
end

@testset "complement: obstacle spanning full width ⇒ no negative space" begin
    poly = square(0.0, 50.0, 400.0)            # x∈[0,400] fills the page width
    cf = complement_chord_fn(poly, PB)
    @test isempty(cf(95.0, 105.0))
end

@testset "complement: concave left edge ⇒ text column follows the silhouette" begin
    # A triangle whose left edge moves rightward as y increases ⇒ wider text column lower down.
    tri = Point2{Float64}[(200.0, 50.0), (350.0, 50.0), (350.0, 250.0)]
    cf = complement_chord_fn(tri, PB)
    hi = cf(70.0, 80.0)[1]                      # near top: left edge ≈ 200
    lo = cf(200.0, 210.0)[1]                    # lower: left edge moved right
    @test hi[2] < lo[2]                         # left interval widens with depth
    @test hi[1] == 0.0 && lo[1] == 0.0
end

@testset "complement: drives shape_pack — body text never overlaps the map envelope" begin
    poly = square(250.0, 0.0, 120.0)            # obstacle x∈[250,370], y∈[0,120]
    cf = complement_chord_fn(poly, PB)
    b = MonospaceBackend()
    prep = prepare(b, join(("word$(i)" for i in 1:120), " "))
    la = prep.metrics.line_advance
    pk = shape_pack(prep, cf; line_advance=la, min_chord_width=10.0)
    @test !isempty(pk.placements)
    # bbox non-overlap invariant: each placed word lies wholly in negative space of its band.
    for p in pk.placements
        w = prep.segments[p.segment_index].width
        yc = (p.y - prep.metrics.ascent) + la/2          # band center for this baseline
        intervals = cf(yc - la/2, yc + la/2)
        # word [p.x, p.x+w] must sit inside one returned interval (⇒ outside the envelope)
        @test any(lo <= p.x && p.x + w <= hi + 1e-6 for (lo, hi) in intervals)
    end
end
```

- [ ] **Step 2: Run to verify red:**

Run: `julia --project=examples/map_feature -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -20`
Expected: FAIL — `complement_chord_fn` not defined / include target missing.

- [ ] **Step 3: Write `src/complement_chord_fn.jl`:**

```julia
# SPDX-License-Identifier: MIT
#
# complement_chord_fn — negative-space chord function for text-AROUND-obstacle layout (#G).
# Inverse of TextMeasureLayouts.polygon_chord_fn (which returns intervals INSIDE the polygon).
# Pure interval arithmetic on the polygon's per-band horizontal projection — deliberately
# AVOIDS GeometryOps boolean ops (0.1.40's intersection/difference are broken; see #D).

"""
    complement_chord_fn(polygon::Vector{Point2{Float64}},
                        page_bounds::NTuple{4,Float64}) -> Function

Build a `shape_pack` `chord_fn` that flows text through the **white space around**
`polygon`. `page_bounds = (left, top, right, bottom)` is the editorial text region in
page-pixel **block-top** coords (y increases downward); `polygon` must already be in that
same frame (project geography first — see [`PageProjection`](@ref)).

Returns a closure `(y_top, y_bottom) -> Vector{Tuple{Float64,Float64}}`. Per band:

- band center `yc ∉ [top, bottom]` ⇒ `[]` (outside the text column; masthead/byline live there);
- `polygon` not crossed at `yc` ⇒ `[(left, right)]` (full-width line, e.g. above/below the map);
- otherwise the polygon's horizontal **envelope** `[env_l, env_r]` (min/max edge-crossing at
  `yc`) is carved out, yielding `[(left, env_l), (env_r, right)]` — each non-empty interval
  emitted, zero-width dropped, sorted ascending & pairwise-disjoint (the `shape_pack` contract).

The envelope (not the exact inside-runs) is used on purpose: text is kept out of the polygon's
full horizontal extent in each band, so concavities on the silhouette's facing edge still steer
the column but text never lands in an interior notch of the map.
"""
function complement_chord_fn(polygon::Vector{Point2{Float64}}, page_bounds::NTuple{4,Float64})
    left, top, right, bottom = Float64.(page_bounds)
    n = length(polygon)
    return function (y_top::Real, y_bottom::Real)
        yc = (Float64(y_top) + Float64(y_bottom)) / 2
        (yc < top || yc > bottom) && return Tuple{Float64,Float64}[]
        env_l = Inf; env_r = -Inf; crossed = false
        if n >= 2
            @inbounds for i in 1:n
                x1 = polygon[i][1]; y1 = polygon[i][2]
                j = i == n ? 1 : i + 1
                x2 = polygon[j][1]; y2 = polygon[j][2]
                if (y1 <= yc) != (y2 <= yc)        # half-open crossing (matches PolygonChordFn)
                    x = x1 + (yc - y1) / (y2 - y1) * (x2 - x1)
                    x < env_l && (env_l = x)
                    x > env_r && (env_r = x)
                    crossed = true
                end
            end
        end
        crossed || return Tuple{Float64,Float64}[(left, right)]
        el = clamp(env_l, left, right)
        er = clamp(env_r, left, right)
        out = Tuple{Float64,Float64}[]
        (el - left) > 0 && push!(out, (left, el))
        (right - er) > 0 && push!(out, (er, right))
        return out
    end
end
```

- [ ] **Step 4: Uncomment the `include`** already present in `src/MapFeature.jl` (it is active from Task 2).

- [ ] **Step 5: Run to verify green:**

Run: `julia --project=examples/map_feature -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -20`
Expected: PASS (all `complement` testsets).

- [ ] **Step 6: Commit:**

```bash
git add examples/map_feature/src/MapFeature.jl examples/map_feature/src/complement_chord_fn.jl examples/map_feature/test/runtests.jl examples/map_feature/test/test_complement_chord_fn.jl
git commit -m "feat(map_feature): complement_chord_fn negative-space chord_fn + bbox non-overlap tests (#G)"
```

---

## Task 4: `PageProjection` — geography → page-pixel space (PURE)

**Files:**
- Create: `examples/map_feature/src/projection.jl`
- Test: `examples/map_feature/test/test_projection.jl`
- Modify: `src/MapFeature.jl` (uncomment `include("projection.jl")`), `test/runtests.jl`

- [ ] **Step 1: Write failing tests** `test/test_projection.jl`:

```julia
# SPDX-License-Identifier: MIT
using Test, MapFeature
using GeometryBasics: Point2

@testset "PageProjection: fits polygon into the map region, preserving aspect, y-flipped" begin
    # geography (lon,lat) — a wide-ish quad
    geo = Point2{Float64}[(-73.4, 42.7), (-71.5, 42.7), (-71.5, 45.0), (-73.4, 45.0)]
    region = (200.0, 40.0, 380.0, 280.0)            # (left, top, right, bottom) on the page
    pp = PageProjection(geo, region; dest="EPSG:5070")
    pts = project_polygon(pp, geo)
    xs = first.(pts); ys = last.(pts)
    @test minimum(xs) >= region[1] - 1e-6
    @test maximum(xs) <= region[3] + 1e-6
    @test minimum(ys) >= region[2] - 1e-6
    @test maximum(ys) <= region[4] + 1e-6
    # touches at least one region edge pair (fit is snug on the binding dimension)
    @test isapprox(minimum(xs), region[1]; atol=1.0) || isapprox(minimum(ys), region[2]; atol=1.0)
    # y-flip: the northernmost geo point (max lat 45.0) maps to the SMALLEST page-y (top).
    north = project_point(pp, Point2{Float64}(-72.5, 45.0))
    south = project_point(pp, Point2{Float64}(-72.5, 42.7))
    @test north[2] < south[2]
end

@testset "PageProjection: aspect ratio preserved (no anisotropic stretch)" begin
    geo = Point2{Float64}[(-73.4, 42.7), (-71.5, 42.7), (-71.5, 45.0), (-73.4, 45.0)]
    region = (0.0, 0.0, 1000.0, 100.0)              # very wide region ⇒ height-bound fit
    pp = PageProjection(geo, region)
    pts = project_polygon(pp, geo)
    w = maximum(first.(pts)) - minimum(first.(pts))
    h = maximum(last.(pts)) - minimum(last.(pts))
    @test h <= 100.0 + 1e-6                          # bound by the short dimension
    @test w < 1000.0                                 # not stretched to fill the wide region
end
```

- [ ] **Step 2: Run to verify red.** Run the suite command from Task 3 Step 2. Expected: FAIL — `PageProjection` undefined.

- [ ] **Step 3: Write `src/projection.jl`:**

```julia
# SPDX-License-Identifier: MIT
#
# PageProjection — reproject geographic (lon,lat) rings to page-pixel block-top space.
# Uses Proj.Transformation (GeoMakie's underlying engine); we project BEFORE shape_pack so
# complement_chord_fn receives page-pixel polygons (per the issue's coordinate-system note).

import Proj

"""
    PageProjection(geo_ref, region; dest="EPSG:5070")

Affine fit of a geographic ring (`Vector{Point2{Float64}}` of `(lon, lat)`) into a page
rectangle `region = (left, top, right, bottom)` (page-pixel, block-top). `geo_ref` defines
the projected bounding box; build once from the state polygon, then apply to that polygon
AND its POIs with the SAME transform via [`project_point`](@ref). `dest` is the target CRS
(`"EPSG:5070"` CONUS Albers; `"EPSG:3759"` for Hawaii). Aspect ratio preserved (uniform
scale = the binding dimension); result is centered in `region`; projected-north → page-top.
"""
struct PageProjection
    trans   :: Proj.Transformation
    scale   :: Float64
    px0     :: Float64    # projected-x of region left after centering
    py0     :: Float64    # projected-y mapped to region top
    left    :: Float64
    top     :: Float64
    pxmin   :: Float64
    pymax   :: Float64
end

function PageProjection(geo_ref::Vector{Point2{Float64}}, region::NTuple{4,Float64};
                        dest::AbstractString="EPSG:5070")
    left, top, right, bottom = Float64.(region)
    trans = Proj.Transformation("EPSG:4326", dest; always_xy=true)
    proj = [trans(p[1], p[2]) for p in geo_ref]      # (x,y) projected meters, y-up
    pxs = first.(proj); pys = last.(proj)
    pxmin, pxmax = extrema(pxs); pymin, pymax = extrema(pys)
    pw = max(pxmax - pxmin, eps()); ph = max(pymax - pymin, eps())
    rw = right - left; rh = bottom - top
    scale = min(rw / pw, rh / ph)                    # uniform ⇒ aspect preserved
    # center the scaled bbox within region
    offx = left + (rw - scale * pw) / 2
    offy = top + (rh - scale * ph) / 2
    return PageProjection(trans, scale, offx, offy, left, top, pxmin, pymax)
end

"""    project_point(pp, geo) -> Point2{Float64}   # (lon,lat) -> page-pixel block-top"""
function project_point(pp::PageProjection, geo::Point2{Float64})
    x, y = pp.trans(geo[1], geo[2])
    px = pp.px0 + (x - pp.pxmin) * pp.scale          # x grows right
    py = pp.py0 + (pp.pymax - y) * pp.scale          # y-flip: north(max y) -> top(min page-y)
    return Point2{Float64}(px, py)
end

"""    project_polygon(pp, ring) -> Vector{Point2{Float64}}"""
project_polygon(pp::PageProjection, ring::Vector{Point2{Float64}}) =
    [project_point(pp, p) for p in ring]
```

- [ ] **Step 4: Uncomment `include("projection.jl")` in `src/MapFeature.jl` and `include("test_projection.jl")` in `test/runtests.jl`.**

- [ ] **Step 5: Run to verify green.** Expected: PASS.

- [ ] **Step 6: Commit:** `git commit -am "feat(map_feature): PageProjection lat/lon→page-pixel via Proj (#G)"`

---

## Task 5: `POI` + label placement (PURE, non-overlap)

**Files:**
- Create: `examples/map_feature/src/poi.jl`
- Test: `examples/map_feature/test/test_poi_labels.jl`
- Modify: `src/MapFeature.jl`, `test/runtests.jl`

- [ ] **Step 1: Write failing tests** `test/test_poi_labels.jl`:

```julia
# SPDX-License-Identifier: MIT
using Test, MapFeature
using GeometryBasics: Point2

overlaps(a::LabelBox, b::LabelBox) =
    a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h

@testset "POI struct" begin
    p = POI("Burlington", (-73.21, 44.48), :city)
    @test p.name == "Burlington"
    @test p.kind === :city
end

@testset "place_poi_labels: no two placed labels overlap" begin
    # anchors deliberately clustered so naive (single-offset) placement would collide
    anchors = [Point2{Float64}(100.0 + 5i, 100.0) for i in 0:6]
    sizes = [(40.0, 12.0) for _ in anchors]          # (w,h) per label
    boxes = place_poi_labels(anchors, sizes; offset=6.0, margin=2.0)
    placed = [b for b in boxes if b !== nothing]
    @test length(placed) >= 1
    for i in 1:length(placed), j in (i+1):length(placed)
        @test !overlaps(placed[i], placed[j])
    end
end

@testset "place_poi_labels: a label sits adjacent to its anchor (within offset+size)" begin
    anchors = [Point2{Float64}(200.0, 200.0)]
    boxes = place_poi_labels(anchors, [(30.0, 10.0)]; offset=6.0, margin=2.0)
    b = boxes[1]
    @test b !== nothing
    @test abs(b.x - 200.0) <= 30.0 + 6.0 + 1e-6
    @test abs(b.y - 200.0) <= 10.0 + 6.0 + 1e-6
end
```

- [ ] **Step 2: Run to verify red.** Expected: FAIL — `POI`/`LabelBox`/`place_poi_labels` undefined.

- [ ] **Step 3: Write `src/poi.jl`:**

```julia
# SPDX-License-Identifier: MIT
#
# POI model + simple offset label placement with greedy de-overlap (#G).
# Hard repel / force-directed placement is out of scope (user's ggrepel-style pkg handles it).

"""
    POI(name, coord, kind)

A point of interest. `coord = (lon, lat)` in geographic degrees; `kind ∈
(:city, :capital, :landmark, :feature)` selects marker glyph + label weight at render.
"""
struct POI
    name  :: String
    coord :: Tuple{Float64,Float64}
    kind  :: Symbol
    function POI(name, coord, kind)
        kind in (:city, :capital, :landmark, :feature) ||
            throw(ArgumentError("POI kind must be :city/:capital/:landmark/:feature, got $(repr(kind))"))
        new(String(name), (Float64(coord[1]), Float64(coord[2])), Symbol(kind))
    end
end

"""    LabelBox(x, y, w, h)  — placed label AABB, page-pixel block-top (top-left origin)."""
struct LabelBox
    x :: Float64
    y :: Float64
    w :: Float64
    h :: Float64
end

_overlaps(a::LabelBox, b::LabelBox) =
    a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h

"""
    place_poi_labels(anchors, sizes; offset=6.0, margin=2.0) -> Vector{Union{LabelBox,Nothing}}

Greedy simple-offset placement. For each anchor (page-pixel marker position) and label
`(w,h)`, try candidate offsets (E, W, N, S, then diagonals) at `offset` px; accept the
first whose box (grown by `margin` for clearance) clears all already-placed boxes. Returns
one entry per anchor (`nothing` if every candidate collides — caller may skip its label).
Placement order is input order (deterministic).
"""
function place_poi_labels(anchors::AbstractVector{<:Point2}, sizes::AbstractVector{<:Tuple};
                          offset::Float64=6.0, margin::Float64=2.0)
    placed = LabelBox[]
    out = Vector{Union{LabelBox,Nothing}}(undef, length(anchors))
    for (i, a) in enumerate(anchors)
        w, h = Float64(sizes[i][1]), Float64(sizes[i][2])
        ax, ay = Float64(a[1]), Float64(a[2])
        candidates = (
            (ax + offset,        ay - h/2),    # E
            (ax - offset - w,    ay - h/2),    # W
            (ax - w/2,           ay - offset - h),  # N
            (ax - w/2,           ay + offset),      # S
            (ax + offset,        ay + offset),      # SE
            (ax - offset - w,    ay - offset - h),  # NW
            (ax + offset,        ay - offset - h),  # NE
            (ax - offset - w,    ay + offset),      # SW
        )
        chosen = nothing
        for (cx, cy) in candidates
            box = LabelBox(cx, cy, w, h)
            grown = LabelBox(cx - margin, cy - margin, w + 2margin, h + 2margin)
            if !any(p -> _overlaps(grown, p), placed)
                chosen = box; break
            end
        end
        out[i] = chosen
        chosen !== nothing && push!(placed, chosen)
    end
    return out
end
```

- [ ] **Step 4: Uncomment includes** in `src/MapFeature.jl` and `test/runtests.jl`.

- [ ] **Step 5: Run to verify green.** Expected: PASS.

- [ ] **Step 6: Commit:** `git commit -am "feat(map_feature): POI model + greedy non-overlapping label placement (#G)"`

---

## Task 6: Data layer — bundled VT load + POI/stats TOML (offline)

**Files:**
- Create: `examples/map_feature/data/pois.toml`
- Create: `examples/map_feature/src/data.jl`
- Test: `examples/map_feature/test/test_data.jl`
- Modify: `src/MapFeature.jl`, `test/runtests.jl`

- [ ] **Step 1: Write `data/pois.toml`** (8–15 VT POIs: 1 capital + cities + landmarks + features, lon/lat hand-curated; plus bundled VT stats so the quickstart needs no `get_acs`):

```toml
# Vermont feature page — POIs (hand-curated from the Vermont Wikipedia article) + ACS stats.
[meta]
state    = "Vermont"
postal   = "VT"
masthead = "VERMONT"
subtitle = "The Green Mountain State"
byline   = "A TextMeasure.jl cartographic feature"

[stats]                       # bundled (2020 census / ACS5 2023); offline quickstart source
population        = 643077
median_income_usd = 74014
capital           = "Montpelier"

[[poi]]
name = "Montpelier"
lon  = -72.5754
lat  = 44.2601
kind = "capital"

[[poi]]
name = "Burlington"
lon  = -73.2121
lat  = 44.4759
kind = "city"

[[poi]]
name = "Rutland"
lon  = -72.9726
lat  = 43.6106
kind = "city"

[[poi]]
name = "Brattleboro"
lon  = -72.5579
lat  = 42.8509
kind = "city"

[[poi]]
name = "St. Johnsbury"
lon  = -72.0151
lat  = 44.4192
kind = "city"

[[poi]]
name = "Mount Mansfield"
lon  = -72.8092
lat  = 44.5438
kind = "feature"

[[poi]]
name = "Camel's Hump"
lon  = -72.8849
lat  = 44.3195
kind = "feature"

[[poi]]
name = "Lake Champlain"
lon  = -73.3318
lat  = 44.5311
kind = "feature"

[[poi]]
name = "Shelburne Museum"
lon  = -73.2293
lat  = 44.3739
kind = "landmark"

[[poi]]
name = "Bennington Battle Monument"
lon  = -73.2057
lat  = 42.8857
kind = "landmark"

[[poi]]
name = "Ben & Jerry's Factory"
lon  = -72.7637
lat  = 44.3520
kind = "landmark"
```

- [ ] **Step 2: Write failing tests** `test/test_data.jl`:

```julia
# SPDX-License-Identifier: MIT
using Test, MapFeature
using GeometryBasics: Point2

const DATA = joinpath(pkgdir(MapFeature), "data")

@testset "load_vermont: bundled shapefile, no network" begin
    poly = load_vermont()
    @test poly isa Vector{Point2{Float64}}
    @test length(poly) >= 1000                      # VT 500k ring ≈ 1634 pts (floor, not hard count)
    xs = first.(poly); ys = last.(poly)
    @test -74.0 <= minimum(xs) && maximum(xs) <= -71.0    # VT longitude window
    @test 42.0 <= minimum(ys) && maximum(ys) <= 45.5      # VT latitude window
end

@testset "load_pois / load_stats: bundled TOML" begin
    pois = load_pois(joinpath(DATA, "pois.toml"))
    @test 8 <= length(pois) <= 15
    @test count(p -> p.kind === :capital, pois) == 1
    @test any(p -> p.name == "Burlington" && p.kind === :city, pois)
    stats = load_stats(joinpath(DATA, "pois.toml"))
    @test stats[:population] > 100_000
    @test stats[:capital] == "Montpelier"
end
```

- [ ] **Step 3: Run to verify red.** Expected: FAIL — loaders undefined.

- [ ] **Step 4: Write `src/data.jl`:**

```julia
# SPDX-License-Identifier: MIT
#
# Data layer: bundled offline Vermont fixture + POI/stats TOML; optional CensusACS fetch for
# other states (network + CENSUS_API_KEY). See verified-API-facts in the plan for CensusACS quirks.

import Shapefile
import TOML

_pkgdata(f) = joinpath(pkgdir(MapFeature), "data", f)

"""    _shape_to_ring(geom) -> Vector{Point2{Float64}}  — outer ring of a Shapefile.Polygon."""
function _shape_to_ring(geom)
    pts = geom.points
    # parts are 0-based start offsets; use the LONGEST part as the outer ring (handles multi-part states)
    parts = geom.parts
    if length(parts) <= 1
        rng = 1:length(pts)
    else
        bounds = vcat(Int.(parts) .+ 1, length(pts) + 1)
        lens = diff(bounds)
        k = argmax(lens)
        rng = bounds[k]:(bounds[k+1] - 1)
    end
    return Point2{Float64}[Point2{Float64}(p.x, p.y) for p in pts[rng]]
end

"""    load_state_shapefile(path; postal=nothing) -> Vector{Point2{Float64}} (lon,lat)

Read a state polygon from a shapefile. If `postal` is given and the file has multiple
features (e.g. the all-US Census file), select the matching `STUSPS` row; otherwise take
the first feature (the single-feature bundled fixture)."""
function load_state_shapefile(path::AbstractString; postal::Union{Nothing,AbstractString}=nothing)
    tbl = Shapefile.Table(path)
    shapes = Shapefile.shapes(tbl)
    idx = if postal === nothing || length(shapes) == 1
        1
    else
        j = findfirst(==(uppercase(postal)), tbl.STUSPS)
        j === nothing && throw(ArgumentError("state $postal not found in $path"))
        j
    end
    return _shape_to_ring(shapes[idx])
end

"""    load_vermont() -> Vector{Point2{Float64}}  — the bundled offline fixture (no network)."""
load_vermont() = load_state_shapefile(_pkgdata("vermont.shp"))

"""    load_pois(path=data/pois.toml) -> Vector{POI}"""
function load_pois(path::AbstractString=_pkgdata("pois.toml"))
    t = TOML.parsefile(path)
    return POI[POI(p["name"], (Float64(p["lon"]), Float64(p["lat"])), Symbol(p["kind"]))
               for p in t["poi"]]
end

"""    load_stats(path=data/pois.toml) -> Dict{Symbol,Any}"""
function load_stats(path::AbstractString=_pkgdata("pois.toml"))
    t = TOML.parsefile(path)
    s = t["stats"]
    return Dict{Symbol,Any}(:population => s["population"],
                            :median_income_usd => s["median_income_usd"],
                            :capital => s["capital"])
end

"""
    fetch_state_shapefile(postal; year=2023, dir=mktempdir()) -> Vector{Point2{Float64}}

Download the all-US Census state file via `CensusACS.get_tiger_shapefile` (FTP/curl), unzip,
and extract `postal`'s ring. REQUIRES NETWORK. For VT prefer [`load_vermont`] (offline).
"""
function fetch_state_shapefile(postal::AbstractString; year::Int=2023, dir::AbstractString=mktempdir())
    cwd = pwd()
    try
        cd(dir)
        CensusACS.get_tiger_shapefile(year, "state") || error("Census download failed")
        zip = joinpath(dir, "cb_$(year)_us_state_500k.zip")
        run(`unzip -o -q $zip -d $dir`)
        return load_state_shapefile(joinpath(dir, "cb_$(year)_us_state_500k.shp"); postal=postal)
    finally
        cd(cwd)
    end
end
```

(Add `import CensusACS` at top of `src/data.jl` only when implementing `fetch_state_shapefile`; keep it lazy-tolerant. `CensusACS` import is cheap once precompiled.)

- [ ] **Step 5: Add `import CensusACS` to `data.jl`, uncomment includes, run to verify green.** Expected: PASS (`load_vermont`/`load_pois`/`load_stats` testsets).

- [ ] **Step 6: Commit:** `git add examples/map_feature/data/pois.toml examples/map_feature/src/data.jl examples/map_feature/test/test_data.jl && git commit -m "feat(map_feature): offline VT data layer + POI/stats TOML + CensusACS fetch (#G)"`

---

## Task 7: `map_feature` render integration — Figure assembly

**Files:**
- Create: `examples/map_feature/src/render.jl`
- Modify: `src/MapFeature.jl` (uncomment `include("render.jl")`)

This task wires geometry → layout → CairoMakie. No new unit test here (render styling is tier-2/3 visual); the tier-1 invariants are covered by Task 3 and the PDF golden by Task 9. Build it so `map_feature(...)` returns a `Figure` and the placements satisfy the same non-overlap invariant.

- [ ] **Step 1: Write `src/render.jl`:**

```julia
# SPDX-License-Identifier: MIT
#
# map_feature — assemble the cartographic feature page (#G). Pinned fonts: DejaVu Sans (display),
# Liberation Serif (body). Render at px_per_unit=1 so measured widths match drawn widths.

import CairoMakie
const CM = CairoMakie

const BODY_FONT    = "Liberation Serif"
const DISPLAY_FONT = "DejaVu Sans"

# Page geometry (US-letter @ 96 dpi-ish, block-top). Map fills the right ~55%.
const PAGE_W = 816.0
const PAGE_H = 1056.0
const MARGIN = 48.0
const MASTHEAD_H = 96.0
const BYLINE_H = 48.0

_marker_glyph(kind::Symbol) = kind === :capital ? '★' :
                              kind === :city     ? '●' :
                              kind === :landmark ? '◆' : '▲'

"""
    map_feature(state_polygon, stats, points_of_interest; dest="EPSG:5070",
                body_text=DEFAULT_BODY, fontsize=12.0) -> CairoMakie.Figure

Render the feature page. `state_polygon` is a geographic `(lon,lat)` ring; `stats` a
`Dict{Symbol,Any}` (`:population`,`:median_income_usd`,`:capital`); `points_of_interest`
a `Vector{POI}`. Geography is projected to the right-hand map region; editorial `body_text`
flows through `complement_chord_fn`'s negative space on the left; masthead/byline/sidebar
are drawn from `stats`. `dest` selects the CRS (`"EPSG:3759"` for Hawaii).
"""
function map_feature(state_polygon::Vector{Point2{Float64}},
                     stats::Dict{Symbol,Any},
                     points_of_interest::Vector{POI};
                     dest::AbstractString="EPSG:5070",
                     body_text::AbstractString=DEFAULT_BODY,
                     fontsize::Float64=12.0)
    # --- map region (right ~55%) ---
    map_left = MARGIN + 0.45 * (PAGE_W - 2MARGIN)
    region = (map_left, MASTHEAD_H + MARGIN, PAGE_W - MARGIN, PAGE_H - BYLINE_H - MARGIN)
    pp = PageProjection(state_polygon, region; dest=dest)
    poly_px = project_polygon(pp, state_polygon)

    # --- editorial text region = full inner column; map envelope carves the right edge ---
    text_bounds = (MARGIN, MASTHEAD_H + MARGIN, PAGE_W - MARGIN, PAGE_H - BYLINE_H - MARGIN)
    cf = complement_chord_fn(poly_px, text_bounds)
    backend = MakieBackend(; font=BODY_FONT, fontsize=fontsize, px_per_unit=1.0)
    prep = prepare(backend, body_text)
    pk = shape_pack(prep, cf; line_advance=prep.metrics.line_advance, min_chord_width=36.0)

    # --- figure (block-top → CairoMakie y-up via y' = PAGE_H - y) ---
    fig = CM.Figure(; size=(PAGE_W, PAGE_H), backgroundcolor=:white)
    ax = CM.Axis(fig[1, 1]; aspect=CM.DataAspect())
    CM.hidedecorations!(ax); CM.hidespines!(ax)
    CM.limits!(ax, 0, PAGE_W, 0, PAGE_H)
    flip(y) = PAGE_H - y

    # masthead + subtitle + byline
    CM.text!(ax, MARGIN, flip(MARGIN + 36); text=get(stats, :masthead, "STATE"),
             font=DISPLAY_FONT, fontsize=54, align=(:left, :baseline), color=:black, space=:data)
    CM.text!(ax, MARGIN, flip(PAGE_H - MARGIN); text=get(stats, :byline, ""),
             font=BODY_FONT, fontsize=11, align=(:left, :baseline), color=(:black, 0.7), space=:data)

    # state silhouette fill + outline
    CM.poly!(ax, [CM.Point2f(p[1], flip(p[2])) for p in poly_px];
             color=(:seagreen, 0.18), strokecolor=:seagreen, strokewidth=1.5)

    # body text at each placement (baseline align)
    for pl in pk.placements
        s = prep.segments[pl.segment_index].str
        CM.text!(ax, pl.x, flip(pl.y); text=s, font=BODY_FONT, fontsize=fontsize,
                 align=(:left, :baseline), color=:black, space=:data)
    end

    # POIs: markers + non-overlapping labels
    anchors = [project_point(pp, Point2{Float64}(p.coord[1], p.coord[2])) for p in points_of_interest]
    sizes = [(measure(backend, p.name) + 4.0, fontsize + 2.0) for p in points_of_interest]
    boxes = place_poi_labels(anchors, sizes; offset=6.0, margin=2.0)
    for (i, p) in enumerate(points_of_interest)
        a = anchors[i]
        CM.text!(ax, a[1], flip(a[2]); text=string(_marker_glyph(p.kind)),
                 font=DISPLAY_FONT, fontsize=p.kind === :capital ? 18 : 12,
                 align=(:center, :center), color=:firebrick, space=:data)
        b = boxes[i]
        b === nothing && continue
        CM.text!(ax, b.x, flip(b.y + b.h); text=p.name, font=DISPLAY_FONT,
                 fontsize=p.kind === :capital ? fontsize + 2 : fontsize,
                 align=(:left, :baseline), color=:black, space=:data)
    end

    # sidebar big-number stats (population / median income / capital)
    sy = MASTHEAD_H + MARGIN
    CM.text!(ax, MARGIN, flip(sy + 16); text="POP $(stats[:population])",
             font=DISPLAY_FONT, fontsize=20, align=(:left, :baseline), color=:seagreen, space=:data)
    CM.text!(ax, MARGIN, flip(sy + 40); text="MEDIAN INCOME \$$(stats[:median_income_usd])",
             font=DISPLAY_FONT, fontsize=14, align=(:left, :baseline), color=(:black, 0.8), space=:data)
    CM.text!(ax, MARGIN, flip(sy + 60); text="CAPITAL $(stats[:capital])",
             font=DISPLAY_FONT, fontsize=14, align=(:left, :baseline), color=(:black, 0.8), space=:data)

    return fig
end

"""    render_to_pdf(fig, path) -> path   — export with selectable (embedded) text."""
function render_to_pdf(fig::CM.Figure, path::AbstractString)
    CM.save(path, fig; pt_per_unit=1.0)
    return path
end

# Placeholder editorial copy (public-domain-style; the demo's "prose").
const DEFAULT_BODY = """
Vermont rises in green folds between the Connecticut River and the broad blue reach of
Lake Champlain. Its ridgelines run north and south like the grain of old timber, and the
towns gather in the valleys where the rivers slow. This page is set by measurement: every
line of this column was placed by flowing words through the white space the map leaves
behind, so the text wraps the silhouette of the state itself, never crossing into the
cartography. Nothing here is nudged by hand. The column narrows where the border bulges
west and opens again where the land falls away to the south, a quiet demonstration that
type can follow geography when the layout engine knows exactly how wide each word will be.
""" ^ 3
```

- [ ] **Step 2: Uncomment `include("render.jl")` in `src/MapFeature.jl`.**

- [ ] **Step 3: Smoke-run the render in the REPL** (no save yet):

Run: `julia --project=examples/map_feature -e 'using MapFeature; fig = map_feature(load_vermont(), load_stats(), load_pois()); println(typeof(fig))'`
Expected: prints `Makie.Figure` (or `CairoMakie`-qualified Figure), no error.

- [ ] **Step 4: Commit:** `git commit -am "feat(map_feature): map_feature render — projection + shape_pack + CairoMakie (#G)"`

---

## Task 8: Quickstart render script + PNG artifact

**Files:**
- Create: `examples/map_feature/render_vermont.jl`

- [ ] **Step 1: Write `render_vermont.jl`** (the offline quickstart; emits PNG + PDF):

```julia
# SPDX-License-Identifier: MIT
# Vermont quickstart — renders entirely from bundled data (NO network).
#   julia --project=examples/map_feature examples/map_feature/render_vermont.jl
using MapFeature
import CairoMakie
fig = map_feature(load_vermont(), load_stats(), load_pois())
out = get(ENV, "MAPFEATURE_OUT", joinpath(@__DIR__, "vermont"))
CairoMakie.save(out * ".png", fig; px_per_unit=1.0)
render_to_pdf(fig, out * ".pdf")
println("wrote ", out, ".png and ", out, ".pdf")
```

- [ ] **Step 2: Run it (offline) and confirm artifacts:**

Run: `julia --project=examples/map_feature examples/map_feature/render_vermont.jl`
Expected: writes `vermont.png` + `vermont.pdf`; PNG non-empty.

- [ ] **Step 3: Commit the script** (PNG/PDF are gitignored): `git add examples/map_feature/render_vermont.jl && git commit -m "feat(map_feature): offline Vermont quickstart render script (#G)"`

---

## Task 9: PDF text-selectability test + committed golden

**Files:**
- Create: `examples/map_feature/test/test_render_pdf.jl`
- Create: `examples/map_feature/test/goldens/vermont_tokens.txt`
- Create: `examples/map_feature/test/goldens/vermont_tokens.sha256`
- Modify: `test/runtests.jl`

- [ ] **Step 1: Write the test** `test/test_render_pdf.jl` (renders VT → PDF → `pdftotext` → assert selectability + token-floor golden):

```julia
# SPDX-License-Identifier: MIT
using Test, MapFeature
import CairoMakie

const GOLDDIR = joinpath(@__DIR__, "goldens")

_have_pdftotext() = !isnothing(Sys.which("pdftotext"))

# normalize: lowercase alphanumeric tokens, length >= 3, sorted-unique
function _tokens(s::AbstractString)
    toks = [lowercase(m.match) for m in eachmatch(r"[A-Za-z0-9]{3,}", s)]
    return sort!(unique!(toks))
end

@testset "PDF export: selectable text (font embedding)" begin
    if !_have_pdftotext()
        @test_skip "pdftotext not on PATH"
    else
        pois = load_pois(); stats = load_stats()
        fig = map_feature(load_vermont(), stats, pois)
        dir = mktempdir()
        pdf = render_to_pdf(fig, joinpath(dir, "vermont.pdf"))
        @test isfile(pdf) && filesize(pdf) > 0
        txt = read(`pdftotext -layout $pdf -`, String)
        # selectability: input strings survive into extractable text
        @test occursin("Vermont", txt) || occursin("VERMONT", txt)
        for p in pois
            # POI names are embedded & selectable (first token of each name)
            first_tok = split(p.name)[1]
            @test occursin(first_tok, txt)
        end
        @test occursin("Montpelier", txt)            # capital from stats sidebar
        @test occursin(string(stats[:population]), txt)

        # token-set floor golden: current extraction must be a SUPERSET of the committed floor.
        goldfile = joinpath(GOLDDIR, "vermont_tokens.txt")
        @test isfile(goldfile)
        golden = Set(readlines(goldfile))
        current = Set(_tokens(txt))
        missing_toks = setdiff(golden, current)
        @test isempty(missing_toks)                  # regression floor: never lose selectable tokens
    end
end
```

- [ ] **Step 2: Run to verify red** (golden file absent). Expected: FAIL on `isfile(goldfile)`.

- [ ] **Step 3: Generate the golden** from the current render (one-time), then re-run:

Run:
```bash
mkdir -p examples/map_feature/test/goldens
julia --project=examples/map_feature -e '
using MapFeature; import CairoMakie
fig = map_feature(load_vermont(), load_stats(), load_pois())
dir = mktempdir(); pdf = render_to_pdf(fig, joinpath(dir,"v.pdf"))
txt = read(`pdftotext -layout $pdf -`, String)
toks = sort!(unique!([lowercase(m.match) for m in eachmatch(r"[A-Za-z0-9]{3,}", txt)]))
open("examples/map_feature/test/goldens/vermont_tokens.txt","w") do io
  for t in toks; println(io, t); end
end
println(length(toks), " golden tokens")'
sha256sum examples/map_feature/test/goldens/vermont_tokens.txt | awk '{print $1}' > examples/map_feature/test/goldens/vermont_tokens.sha256
```
Expected: writes the golden token list + sha256.

- [ ] **Step 4: Uncomment `include("test_render_pdf.jl")` in `test/runtests.jl`; run to verify green.** Expected: PASS.

- [ ] **Step 5: Commit:**

```bash
git add examples/map_feature/test/test_render_pdf.jl examples/map_feature/test/goldens/ examples/map_feature/test/runtests.jl
git commit -m "test(map_feature): PDF selectability + token-floor golden against pinned fonts (#G)"
```

---

## Task 10: Full-suite verification (capture-to-log, grep)

**Files:** none (verification only).

- [ ] **Step 1: Run the FULL suite ONCE, capture to log:**

Run:
```bash
mkdir -p test-logs
julia --project=examples/map_feature -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"
```
Expected: `Testing MapFeature tests passed`.

- [ ] **Step 2: Grep the log (don't re-run) to confirm each testset:**

Run: `grep -E "Test Summary|complement|projection|poi|data|PDF export|Pass|Fail|Error" "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log" | tail -40`
Expected: all green; 0 fails / 0 errors.

- [ ] **Step 3: Confirm `GeometryOps`/`HTTP` are actually used or drop them** (no unused-dep smell): grep the `src/` tree.

Run: `grep -rE "GeometryOps|HTTP|import|using" examples/map_feature/src/`
If `GeometryOps`/`HTTP` are unimported, `Pkg.rm` them and re-run Step 1 once. (HTTP is only listed for a non-CensusACS scrape we don't do — likely droppable; GeometryOps only if `Point2`/orientation isn't needed — we use `GeometryBasics.Point2`, so GeometryOps is likely droppable too. Confirm, then drop, to keep the dep set honest.)

- [ ] **Step 4: Re-instantiate clean + final green capture** after any dep change.

---

## Task 11: README quickstart

**Files:**
- Create: `examples/map_feature/README.md`

- [ ] **Step 1: Write `README.md`** documenting: what it is; the offline Vermont quickstart (`julia --project=examples/map_feature examples/map_feature/render_vermont.jl`); how `complement_chord_fn` flows text in the negative space; the CensusACS path for other states (needs `CENSUS_API_KEY` + network); the verified-API-facts caveats (get_acs bug, FTP download); pinned fonts. Keep ~40 lines.

- [ ] **Step 2: Commit:** `git add examples/map_feature/README.md && git commit -m "docs(map_feature): quickstart README (#G)"`

---

## Self-review checklist (run before the gate)

1. **Spec coverage:** silhouette-as-map ✓ (Task 7), editorial wrap via `complement_chord_fn` ✓ (Task 3/7), masthead/byline/sidebar ✓ (Task 7), POI non-overlap ✓ (Task 5), bundled VT offline ✓ (Task 0/6), other states via CensusACS ✓ (Task 6), PDF selectability + golden ✓ (Task 9), `complement_chord_fn` lives in `examples/map_feature/src/` (NOT in TextMeasureLayouts — avoids #K collision) ✓.
2. **Type consistency:** `POI(name,coord,kind)`, `LabelBox(x,y,w,h)`, `PageProjection`/`project_point`/`project_polygon`, `complement_chord_fn(polygon, page_bounds)` returns a closure, `Placement.segment_index`/`.x`/`.y`, `Segment.str`/`.width` — consistent across Tasks 3–9.
3. **Acceptance harness:** tier-1 bbox non-overlap (Task 3) + POI non-overlap (Task 5) + pdftotext selectability/golden (Task 9); render is tier-2/3 (orchestrator/human visual). Floors not hard counts (Task 6/9). ✓
4. **Conventions:** SPDX header on every `.jl` ✓; Manifest gitignored, `data/vermont.*` force-committed ✓; `[extras]Test`/`[targets]test` ✓; pinned fonts DejaVu Sans + Liberation Serif ✓; no `finishing-a-development-branch` (PR via request-pr-review) ✓.
