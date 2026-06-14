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
| Exact pixel box of `"San Luis Obispo"` at 11px in this font, render-free | **TextMeasure.jl** (`MakieBackend`→`measure_bounds`/`prepare`→`layout`) |
| Zero-overlap placement: Imhof seed → side-select → legalize → leaders | **MakieTextRepel.jl** (`textrepel!`) — the user's own MIT package |
| Coastline, water, dots, placed labels → frames → MP4 | **Makie** (`CairoMakie.record`) |
| The zoom path, level-of-detail gating, map rendering, golden harness | **new demo code** (`examples/atlas/`) |

All labels horizontal (Imhof point labels are horizontal by convention) — in contract; no rotation,
curved coast names, justify, or CJK. Say the three-layer split in the caption — it's the honesty.

## 1. The call — `textrepel!` (verified against `/tmp/MakieTextRepel.jl`)

```julia
using CairoMakie, MakieTextRepel
textrepel!(ax, points;            # points::Vector{Point2f}; text 1:1 with points
    text=labels, markersize=9, only_move=:both, box_padding=4.0, point_padding=5.0,
    min_segment_length=2.0, background=false, segments=true,
    segmentcolor=BRASS, linewidth=0.5, color=INK, fontsize=…, font=…)
scatter!(ax, points; markersize=9)     # draw markers AFTER (leaders tuck under)
```
Draws text at anchors with per-label **pixel** offsets, optional background `poly!`, leader
`linesegments!`; draws **no markers**. Per-label offsets exposed as `p.computed_offsets` (for golden
hashing). Use `textrepel!` (not the `TextRepelAlgorithm`/`annotation!` surface) — it owns marker
clearance, background boxes, and over-capacity **dropping**, which the LoD story leans on
(`solve_stats(alg).dropped` feeds the live metrics readout).

## 2. Live re-placement on zoom — ALREADY REACTIVE (the key finding)

`Makie.plot!(p::TextRepel)` wires a reactive graph: `register_projected_positions!`
(`input_space=:data, output_space=:pixel`) → `px_anchors` recomputes when axis limits change;
`bounds_obs = lift(viewport(...))`; `solved = lift(px_anchors, text, fontsize, …, bounds_obs, …)`
re-runs **measure + solve** on any input change. **Consequence: animating `ax`'s limits inside a
`record()` loop re-solves placement every frame, for free.** "Measure once" holds because
measurement keys on (string, font, size) — unchanged by zoom; only anchor pixel positions change.

```julia
record(fig, "atlas_dive.mp4", 1:360; framerate=30) do frame
    p   = frame/360
    w   = exp(lerp(log(W_WIDE), log(W_TIGHT), z(p)))   # geometric zoom (§5)
    update_active!(plot, active_indices(w))            # LoD gate (§3)
    limits!(ax, camera_rect(p, w))                     # ← triggers re-project + re-solve via lift
end
```
**Strategy A (recommended):** feed the active set into one persistent `textrepel!` plot, then
`limits!`; the recipe's `lift` chain re-solves. **Strategy B (fallback):** explicit per-frame
`TextRepelAlgorithm` solve — use only if reactive timing under `record` proves fiddly.
**Riskiest unknown (§8):** confirm on a 3-frame stub that the lifted solve fires *before* CairoMakie
rasterizes each frame (frame *k* shows frame *k*'s limits, not *k−1*'s). Compute graph is synchronous
so it should; if lagged, force `Makie.update_state_before_display!(fig)` in the callback.

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
- **Damp the reshuffle (the hard part):** sticky/incremental placement — settled labels try their
  previous slot first and **hold** if still clear (zero motion); only newcomers fade in, only
  genuinely-evicted labels **tween** old→new slot over 9 frames; add a small inertia penalty so
  greedy prefers continuity. Field stays mostly still, with occasional meaningful glides.
- `max_overlaps` drops lowest-priority labels if a level is over-capacity (clutter ceiling ~24
  on-screen); `dropped` shows in the metrics line.

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

Shared spine: paper + ink + brass, Fraunces × IBM Plex Mono, √2 ramp (8·11·16·22·31·44). Labels at
**constant screen-pixel size** (basemap scales underneath — standard slippy-map behavior; the only
choice legible across 10× zoom). `MakieBackend(px_per_unit=1)` so measured box == rendered box,
pixel-exact, every frame — the property that makes collision-free *actually* collision-free.

| Role | Face | pt | Treatment |
|---|---|---|---|
| "THE ATLAS" masthead | Fraunces 144pt | 44 | tracked caps INK; brass dateline rule under |
| Region ("CENTRAL COAST") | Fraunces 72pt | 22 | tracked caps INK |
| Ocean/bay areal | Plex Mono | 11 | letterspaced caps, water hairline `#9FB2BA`, horizontal (no arc) |
| Major settlements (rank ≤5) | Fraunces text | 16 | INK title-case |
| Necklace towns | Plex Mono | 11 | INK — the fixed-pitch *is* the measure concept, packed tightest |
| Graticule ticks / caption | Plex Mono | 9 | brass / gray, brass middot |

Palette: paper `#FBFAF7`, ink `#1E1C1A`, brass `#B5793C`, water fill `#DCE3E5` / hairline `#9FB2BA`.
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
limits ⇒ same placement to the pixel. Golden = **hash the per-frame placement table**, not video
bytes (video is a gitignored build artifact). Table row (sorted by town id): `town_id, name,
slot_index, box_{x,y,w,h}_px (round 2dp), alpha_q (0.05), has_leader`; sha256 per asserted frame +
`.txt` sibling for diff; mirror `asteroid_tui/frame60.sha256`. Assert **6 frames**: `f000` (wide
seam), `f060`, `f120` (cluster opens), `f180` (apex — densest), `f240`/`f300` (rise-out — catch
reshuffle/hysteresis desync first). Also assert invariants per frame: `solve_stats().overlaps==0`,
`dropped ≤ budget`, active-set size matches the LoD gate. **Green ≠ visual sign-off** — open the MP4
+ frames and confirm the fill-in reads.

**Difficulty: M.** Reuse covers measurement + placement + reactivity (MakieTextRepel). New code:
camera path (S), LoD gating + fade + sticky placement (M), basemap render (M), golden harness (S),
metrics readout (S). Riskiest unknown = the per-frame reactive-solve timing under `record` (verify
on a stub; strategy B removes the ambiguity).

## The one bold move + coherence

At the apex, the still overlays a **naive-vs-measured diptych** on the *same* densest cluster the
camera just placed — left a struck-through pile of font-blind overlaps, right the gap-perfect
lattice — so the frozen frame proves the motion was honest, not staged.

> Four faces of one instrument: **Glyph Wave** measures glyphs to drive an *image*, **The Press**
> measures under *force over time*, **Erasure** measures what *survives subtraction*, **The Atlas**
> measures to *place names live as the world zooms* — measure once, then wave / press / erase /
> **place** many.

## Sources

- MakieTextRepel.jl (verified in source): `github.com/jowch/MakieTextRepel.jl`
- Natural Earth (PD) via `github.com/nvkelso/natural-earth-vector` · `naturalearthdata.com`
- van Wijk & Nuij 2003, *Smooth and efficient zooming and panning*: https://vanwijk.win.tue.nl/zoompan.pdf
- Mapbox label LoD / flicker: https://docs.mapbox.com/help/dive-deeper/optimize-map-label-placement/ · issues #4558, #5776
- Imhof 1975, *Positioning Names on Maps* · Christensen–Marks–Shieber 1995 (PFLP)
- Smoothstep: https://en.wikipedia.org/wiki/Smoothstep
