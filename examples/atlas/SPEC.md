<!-- SPDX-License-Identifier: MIT -->
# SPEC — The Atlas (a zoom dive)

*Gallery piece · register: **place**. A recorded animation that falls from the whole Central
California coast down into a dense town cluster. Place-labels appear by level-of-detail and are
placed — and **re-placed live, every frame** — by MakieTextRepel.jl as the viewport zooms, staying
collision-free the whole way down.*

> **The thesis made visceral: measure once, lay out many — driven by the viewport.** TextMeasure.jl
> measures every label box (render-free, no kerning, pixel-exact to Makie); MakieTextRepel reads
> those boxes each frame and decides where each name lands; the demo drives the camera and chooses
> who is visible.

Status: **refined, pre-plan.** Consolidates three research passes (MakieTextRepel integration,
basemap data + rendering, zoom choreography). Supersedes the earlier static-diptych atlas.

## 0. The boundary (the demo's whole honesty)

| Concern | Owner |
|---|---|
| Exact pixel box of `"San Luis Obispo"` at 11px in this font, render-free | **TextMeasure.jl** (`MakieBackend` → `prepare` → `layout`; plain-string towns) |
| Zero-overlap placement primitives: Imhof seed → side-select → legalize | **MakieTextRepel.jl** internals (`solve_cluster`/`ProjectionSolver`) — the user's own MIT package |
| Per-frame **warm-start** solve (prior offsets as `init_state`) + overlap/dropped recompute | **new demo code** — DRAFTED here against MakieTextRepel internals, to be upstreamed (see API plan) |
| Fade-in alpha + sticky carry-over (keyed by `town_id`) | **new demo code** (`examples/atlas/`) — DEMO-owned, not MakieTextRepel |
| Coastline, water, dots, placed labels → frames → MP4 | **Makie** (`CairoMakie.record`) |
| The zoom path, level-of-detail gating, map rendering, golden harness | **new demo code** (`examples/atlas/`) |

All labels horizontal (Imhof point labels are horizontal by convention) — in contract; no rotation,
curved coast names, justify, or CJK. Say the three-layer split in the caption — it's the honesty.

> **API plan (the load-bearing honesty).** The per-frame warm-start solve is **drafted in the demo
> against MakieTextRepel's internals** — the deterministic `ProjectionSolver`, the Imhof-seeded
> `initial_offsets`/`side_select`, and `solve_cluster(...; init_state, pin_mask, pinned_offsets)`. The
> public `textrepel!` recipe always does a *fresh* solve (it never threads `init_state`), so it can't
> damp reshuffle on its own. Plan: **upstream a warm-start input into MakieTextRepel** (the
> `TextRepelAlgorithm` annotation path already accepts `reset=false` → prior `offsets` as a warm start;
> exposing it on the recipe is the missing piece), then **swap the demo to the public API**. Until
> then the demo computes overlaps/dropped itself — deterministically — rather than reading them off the
> recipe (the recipe surfaces only `computed_offsets`/`computed_dropped`; `solve_stats`/`overlaps`
> live on `TextRepelAlgorithm`, not the recipe). `measure_bounds` is RichText-only and is used only if
> a label is RichText; plain-string town names go through `MakieBackend → prepare → layout`.

## 1. The call — internal `solve_cluster`, warm-start (verified against `/tmp/MakieTextRepel.jl`)

We drive the **deterministic placement primitives directly** so we can warm-start each frame and
compute our own overlap/dropped figures — the public `textrepel!` recipe always does a *fresh* solve
(it never threads `init_state`; see §0 API plan).

```julia
using CairoMakie, MakieTextRepel
using MakieTextRepel: ProjectionSolver, RepelParams, solve_cluster, initial_offsets, side_select

params = RepelParams(; only_move=:both, box_padding=4.0, point_padding=5.0,
                       min_segment_length=2.0)
solver = ProjectionSolver(params)

# per active subset, in pixel space (anchors = projected px, sizes = measured boxes):
r = solve_cluster(solver, anchors, sizes, bounds_px;
                  init_state     = prev_offsets,   # nothing on first appearance ⇒ Imhof seed → side_select
                  pin_mask       = pin_mask,       # labels held at last slot (sticky)
                  pinned_offsets = pinned)         # render-space offsets for pinned labels
offsets, dropped = r.offsets, r.dropped
# WE draw text/leaders/markers (text! + linesegments! + scatter!), pixel space,
# leaders tucked under markers:
text!(ax, data_positions; offset=offsets, markerspace=:pixel, color=INK, fontsize=…, font=…)
linesegments!(ax, build_connectors(anchors, offsets, sizes, dropped, …); space=:pixel,
              color=BRASS, linewidth=0.5)
scatter!(ax, data_positions; markersize=9)      # markers AFTER (leaders tuck under)
```
`solve_cluster` returns `(offsets, dropped, …)`; with `init_state===nothing` it does the fresh
Imhof-seed → `side_select` → crossing-repair → `legalize` pipeline, otherwise it **warm-starts** from
`init_state`. We compute **overlaps and dropped ourselves** (deterministically, from `offsets` +
`sizes`) for both the golden invariant and the live metrics readout — we do **not** read them off a
recipe (the recipe surfaces only `computed_offsets`/`computed_dropped`; `solve_stats`/`overlaps` are
`TextRepelAlgorithm`-only). Marker clearance, leaders, and any background boxes are drawn by demo code
here, mirroring what the recipe does internally.

## 2. Live re-placement on zoom — fresh re-solve is free; damping needs warm-start

A **fresh** re-solve is free: the public `textrepel!` recipe already wires a reactive graph
(`register_projected_positions!` `input_space=:data, output_space=:pixel` → `px_anchors` recomputes
on limit change; `bounds_obs = lift(viewport(...))`; `solved = lift(px_anchors, text, fontsize, …)`
re-runs measure + solve on any input change), so animating `ax`'s limits inside `record()` re-solves
placement every frame for free. "Measure once" holds: measurement keys on (string, font, size) —
unchanged by zoom; only anchor pixel positions change.

**But a free *fresh* solve is not reshuffle-damping.** The recipe **always solves fresh** — it never
threads `init_state` (recipe `solved` lift calls `solve_cluster(ProjectionSolver(params), …)` with no
warm start), so consecutive frames are placed independently and labels can jump. Damping (settled
labels holding their slot) requires the **warm-start solve we are drafting** (§0 API plan): each frame
feed the *prior* frame's offsets in as `init_state`, keyed by stable `town_id`.

```julia
record(fig, "atlas_dive.mp4", 1:360; framerate=30) do frame
    p   = frame/360
    w   = exp(lerp(log(W_WIDE), log(W_TIGHT), z(p)))   # geometric zoom (§5)
    limits!(ax, camera_rect(p, w))                     # set this frame's view
    Makie.update_state_before_display!(fig)            # ensure px_anchors reflect new limits

    ids      = active_ids(w)                            # LoD gate (§3), stable town_ids
    anchors  = px_anchor[id] for id in ids              # projected px for this frame
    init     = [prev_offset[id] for id in ids]          # warm start: prior slot, or nothing if new
    pin_mask = [is_settled(id) for id in ids]           # sticky labels held in place
    r        = solve_cluster(solver, anchors, sizes(ids), bounds_px;
                             init_state = init, pin_mask = pin_mask, pinned_offsets = pinned(ids))
    prev_offset = Dict(id => r.offsets[k] for (k, id) in enumerate(ids))   # carry over by town_id
end
```
The active subset is rebuilt **by `town_id`, not vector index** each frame (the index of a town shifts
as towns enter/leave the LoD set; a vector-index warm-start would mis-pair offsets). On a town's first
appearance its `init_state` entry is `nothing` ⇒ Imhof seed → `side_select` drops it into the gap.
**Riskiest unknown (§8):** confirm on a 3-frame stub that `px_anchors` reflect frame *k*'s limits
before we read them (frame *k* shows frame *k*'s view, not *k−1*'s) — hence the explicit
`update_state_before_display!`.

## 3. Level-of-detail — who is active per zoom level

Gate eligibility by importance (`pop`/`rank`) vs the current view width `w` on a smooth monotone
`log(w)` ladder; feed only the active set to the placer each frame so newcomers drop into the gaps
the majors leave ("filling in").

| View width `w` | Phase | Eligible (rank ≤ / pop ≥) | Towns appearing |
|---|---|---|---|
| 3.0°–1.5° | wide establishing | 5 / 50k | SLO, Santa Maria, Santa Barbara, Salinas, Monterey |
| 1.5°–0.7° | mid-dive | 7 / 12k | + Morro Bay, Pismo, Atascadero, Paso Robles, Lompoc |
| 0.7°–0.30° | cluster fills | 9 / 2k | + Cambria, San Simeon, Los Osos, Avila, Cayucos |

The memorable beat is the last row: falling 0.7°→0.30°, the **Cambria–Morro Bay–SLO–Pismo** necklace
lights up town-by-town and the solver keeps every arrival collision-free.

- **Hysteresis (critical):** a town switches **on** at `w_on`, **off** at `1.08×w_on` — kills
  boundary flicker (the Mapbox `#4558`/`#5776` class of bug) and makes the rise-out self-consistent.
- **Fade, don't pop:** new label fades in over 9 frames (`smoothstep` alpha 0→1); dot + leader + name
  on one clock.
- **Damp the reshuffle (the hard part — needs the warm-start, not free):** the recipe's reactive
  re-solve is *fresh*, so it does **not** damp; damping is the warm-start solve of §2/§0. Sticky/
  incremental placement — settled labels feed their previous offset as `init_state` (pinned via
  `pin_mask`) and **hold** if still clear (zero motion); only newcomers fade in (their `init_state` is
  `nothing` ⇒ fresh Imhof seed), only genuinely-evicted labels **tween** old→new slot over 9 frames.
  Field stays mostly still, with occasional meaningful glides.
- **Clutter ceiling = LoD, not `max_overlaps`:** `max_overlaps` is **inert under the default
  `ProjectionSolver`** (only the non-default `ForceSolver` honours it), so we do **not** rely on it.
  Hold the on-screen count (~24) by feeding the solver only labels we can afford to lose — the LoD gate
  *is* the capacity control. Any drops come from `solve_cluster`'s `dropped` (over-capacity escape
  hatch) plus our own deterministic overlap recompute; that count feeds the metrics line.

## 4. Leaders & the honest placement gap

Leader-free clean placement is the **default**: `connector_for` suppresses the connector when a
label sits snug in a slot; side-select minimizes `(hard_overlaps, leader_length, imhof_rank)` over
in-bounds Imhof slots (`IMHOF_ORDER = TR>R>T>BR>L>BL>B>TL`), so it prefers slot-snug, leader-free,
upper-right placement and only reaches when boxed in. Leaders are brass 0.5px hairlines, rare by
design — their scarcity is the proof. **Honest gap (name it in the caption):** the `legalize` stage
is a *continuous* Dykstra projection — final boxes are Imhof-seeded and leader-minimized but can
drift a few px off the 8 canonical slots; it's not a pure fixed-slot PFLP placer. For the dive this
reads as a feature (labels breathe into free space). Push harder toward leader-free via
`box_padding` + keeping the active set within capacity (LoD does this) + `only_move=:y` on the dense
coastal necklace (stack vertically along the water).

## 5. Choreography — the dive

**A seamless zoom loop (in→out), not a one-way dive with a cut** (the cut is the ugliest moment).

| | Center (lon,lat) | View width | Frame holds |
|---|---|---|---|
| Wide (loop ends) | −121.0°, 35.5° | **3.0°** | whole Central Coast (Monterey Bay → Pt Conception) |
| Tight (loop apex) | −120.66°, 35.30° | **0.30°** (≈22 km) | the Cambria–Morro Bay–SLO–Pismo necklace |

**10× zoom.** Center pans ≈0.5° toward the SLO cluster as it zooms (zoom dominates → a *dive*, not a
*swoop*). **Easing = geometric zoom** (interpolate `log(width)`, constant *perceived* velocity — van
Wijk & Nuij 2003, what Mapbox `flyTo` implements), wrapped in **`smoothstep` ease per half** so
velocity is zero at start / apex / end → the loop closes position- *and* velocity-continuous (the
seam is invisible). **12 s · 30 fps · 360 frames** (frame 360 ≡ 0; render the full mirrored rise, no
ping-pong rewind artifact). Apex hold = 0 (smoothstep already dwells).

## 6. Data, projection & assets

- **Coast/land: Natural Earth 1:**10m** (NOT 50m).** Verified by vertex count: 50m collapses the
  Monterey Peninsula + Morro Bay to ~3–4 facets (unusable zoomed in); 10m ≈494 verts, crisp wide
  *and* tight. Ship one LoD, no runtime switching. `ne_10m_coastline.geojson`, `ne_10m_land.geojson`
  from `nvkelso/natural-earth-vector` (**public domain, no attribution required** — verified).
- **Towns: a curated `towns.csv`** (DECIDED). Verified that NE populated_places has only **8** towns
  in-bbox and **none** of the hero necklace (Carmel, Big Sur, Cambria, Morro Bay, Pismo… are below
  NE's threshold). Ship `towns.csv` = the 8 verbatim NE rows (`source=NE`, exact NAME/lon/lat/
  POP_MAX/SCALERANK) + ~12–22 hand-placed coastal towns (`source=curated`, lon/lat hand-entered,
  `pop`/`rank` ordinally correct for priority). The `source` column keeps us honest; `SOURCE.txt`
  states it; the caption says coastline + major cities are verbatim NE, small towns are hand-placed.
  Placement quality (labels-vs-labels collisions) is independent of point provenance, so this
  doesn't weaken the demo.
- **Projection: plain equirectangular + a `cos φ0` x-correction** (`φ0=35.7°`, `kx≈0.812`) — a pure
  affine applied once at load to every coastline/land/town coordinate so basemap + labels share one
  `map-units` space the zoom animates over. **No GeoMakie** (its `GeoAxis` per-frame PROJ fights the
  manual zoom + the pixel-exact box contract) — plain `Axis` + `GeoJSON.jl`/`GeoInterface.coordinates`
  + `CSV.jl` for towns.
- **Hermetic build:** commit clipped subsets under `examples/atlas/data/` (`coastline.geojson` ~15–30
  KB, `land.geojson` ~15–30 KB, `towns.csv` ~2 KB, `SOURCE.txt`) — total <65 KB, source data belongs
  in git. A one-time `prep/clip.jl` (bbox hardcoded) produces them; the demo only reads committed
  files, never fetches.

## 7. Aesthetic — Swiss / Vignelli-modern, minimal contour

Shared spine: paper + ink + brass, Fraunces × IBM Plex Mono, √2 ramp (9·11·16·22·31·44). Labels at
**constant screen-pixel size** (basemap scales underneath — standard slippy-map behavior; the only
choice legible across 10× zoom). `MakieBackend(px_per_unit=1)` so measured box == rendered box,
pixel-exact, every frame — the property that makes collision-free *actually* collision-free.

| Role | Face | pt | Treatment |
|---|---|---|---|
| "THE ATLAS" masthead | Fraunces 144pt | 44 | tracked caps INK; brass dateline rule under |
| Region ("CENTRAL COAST") | Fraunces 72pt | 22 | tracked caps INK |
| Ocean/bay areal | Plex Mono | 11 | letterspaced caps, water hairline `#9FB2BA`, horizontal (no arc) |
| Major settlements (rank ≤5) | Fraunces text | 16 | INK title-case |
| Necklace towns (**the hero**) | Plex Mono | 11 | INK — fixed-pitch boxes that **kiss edge-to-edge**: the exact measured extent of each name is what buys the tight pack. Make the **gap-perfect lattice** the protagonist (leaders rare by design); the viewer should *see* that measurement is load-bearing, not credit the placer alone |
| Graticule ticks / caption | Plex Mono | 9 | brass / gray, brass middot |

Palette: paper `#F4EFE6`, ink `#1A1714`, brass `#9A7B4F`, water fill `#DCE3E5` / hairline `#9FB2BA`.
Map: water = Axis background; land = paper `poly!`; coastline = 0.75px ink hairline (the only 0.75
line); town dots 2–4px ink + 0.5px paper halo; **one brass hero dot** at San Luis Obispo (the
namesake string); graticule 0.25px brass at whole degrees; 1.0px brass neat-line + corner cartouche
(title, scale bar, live metrics). Stroke vocabulary only 0.25 / 0.5 / 0.75 (+1.0px brass neat-line).

## 8. The still, determinism, difficulty

**Gallery still:** the **mid-dive frame `p≈0.42`** (`w≈0.55°`) with the cluster half-revealed — SLO,
Morro Bay, Pismo placed solid, Cambria + San Simeon mid-fade (α≈0.5), one leader into open water. It
*is* the thesis (labels caught in the act of arriving collision-free); reads as motion frozen.
Metrics line `w 0.55° · 17/17 placed · 2 entering · 1 leader` — "2 entering" is the tell it's a film
frame. (Rejected: trails composite — obscures labels; wide establishing — indistinguishable from a
static map, doesn't promise motion.)

**Determinism / golden:** solver is RNG-free except a seed-pinned Delaunay triangulator → same data +
limits ⇒ same placement. Golden = **hash the per-frame placement table**, not video bytes (video is a
gitignored build artifact). **Hash on stable, machine-robust keys — `town_id` + chosen slot/offset —
not absolute projected px:** raw `box_{x,y}_px` is float-noisy at zoom extremes (projected px carries
accumulated float error), so 2dp absolute-px rounding is machine-sensitive. Table row (sorted by
`town_id`): `town_id, name, slot_index, offset_{x,y}_px (round 2dp, relative to anchor — stabler than
absolute), alpha_q (0.05), has_leader`; sha256 per asserted frame + `.txt` sibling for diff; mirror
`asteroid_tui/frame60.sha256`. **Prototype golden stability early** — confirm the hash agrees across
two machines (or fall back to slot/offset-only hashing) *before* building the harness around it.
Assert **6 frames**: `f000` (wide seam), `f060`, `f120` (cluster opens), `f180` (apex — densest),
`f240`/`f300` (rise-out — catch reshuffle/hysteresis desync first). Per-frame invariants: **our own
deterministic overlap recompute == 0** (not `solve_stats().overlaps` — that's recipe-absent;
`solve_stats` is `TextRepelAlgorithm`-only), `dropped ≤ budget` (from `solve_cluster`'s `dropped` +
our recompute), active-set size matches the LoD gate. **Green ≠ visual sign-off** — open the MP4 +
frames and confirm the fill-in reads.

**Difficulty: M.** Reuse covers measurement (TextMeasure) + the deterministic placement primitives
(MakieTextRepel internals). New code: the warm-start solve wrapper (M — drafted against internals,
later upstreamed; see §0 API plan), camera path (S), LoD gating + fade + sticky placement (M), basemap
render (M), golden harness (S), metrics readout (S). Riskiest unknown = per-frame anchor/solve timing
under `record` (verify on a stub; explicit `update_state_before_display!` removes the ambiguity).

## The one bold move + coherence

**ONE bold move = the dive itself** — the live, collision-free fall into the dense necklace. The
naive-vs-measured comparison is **demoted to an optional small inset** (a thumbnail in the cartouche,
not a half-frame diptych): left a struck-through pile of font-blind overlaps, right the gap-perfect
lattice. Keep it small or drop it — at full diptych size it competes with the dive and tips the piece
into the "explainer" failure mode. The dive alone proves the motion was honest, not staged; the inset
is at most a footnote.

> Four faces of one instrument: **The Glyph Wave** = shape (image) · **The Press** = press (force) ·
> **Erasure** = erase (subtraction) · **The Atlas** = place (place). Measure once, then —
> shape · press · erase · place — many.

## Sources

- MakieTextRepel.jl (verified in source): `github.com/jowch/MakieTextRepel.jl`
- Natural Earth (PD) via `github.com/nvkelso/natural-earth-vector` · `naturalearthdata.com`
- van Wijk & Nuij 2003, *Smooth and efficient zooming and panning*: https://vanwijk.win.tue.nl/zoompan.pdf
- Mapbox label LoD / flicker: https://docs.mapbox.com/help/dive-deeper/optimize-map-label-placement/ · issues #4558, #5776
- Imhof 1975, *Positioning Names on Maps* · Christensen–Marks–Shieber 1995 (PFLP)
- Smoothstep: https://en.wikipedia.org/wiki/Smoothstep
