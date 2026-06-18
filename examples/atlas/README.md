# The Atlas

<video src="https://github.com/user-attachments/assets/4e82d0a3-eec8-456f-bc18-7044bf49293e" controls muted loop></video>

<sub>▶ inline dive above (renders on GitHub) · [hero still](atlas-hero.png)</sub>

A cartographic gallery piece built on the **TextMeasure** layout engine: a seamless-loop
**zoom-dive** over the California Central Coast whose every place-label is *measured* by
TextMeasure and *placed* collision-free by [MakieTextRepel](https://github.com/jowch/MakieTextRepel.jl) — re-solved on
**every frame** as the viewport descends from a 2° establishing shot to a 0.55° plunge over San
Luis Obispo and back.

Artifacts (rendered into this directory; the hero still and loop mp4 are committed as the
README figures, intermediate dev frames are gitignored):

- `atlas-dive.mp4` — the seamless 30fps zoom-dive loop
- `atlas-hero.png` — the hero still (the Morro Bay–SLO necklace at mid-descent)

## The three honesty layers

Nothing on this map is hand-positioned. The piece holds to three claims, each enforced in code:

1. **Measured.** Every label's box — towns, landmarks, and the curved region "areals" (Pacific
   Ocean, Santa Lucia Range, Estero Bay, Salinas River) — comes from `TextMeasure.measure`, never
   a guessed width. Each label is measured **once** at a reference size; its per-frame box is that
   unit box scaled by `font_px / _REF_PX` (glyph advances scale linearly with size), so the font
   engine is touched once per label and every frame after is arithmetic. *(single-measure-then-scale)*
2. **Placed.** Every point label's screen position is the output of MakieTextRepel's public `warm_solve`
   — one solve per frame over all labels against each other, the sampled coastline, and the areals.
   As the camera dives, the previous frame's offsets warm-start the next, so labels glide rather
   than jump. Placement is then made deterministic by our own two-pass cull (hard coast clearance +
   smooth priority occlusion), so contested clusters never strobe.
3. **Anchored.** The *only* hand-authored values in the whole piece are feature anchors — a lon/lat
   per town/POI/areal (`data/towns.csv`, `src/pois.jl`). A label's final position is never set by
   hand; it is always projected → measured → solved.

## What it demonstrates beyond Tide

- **Geographic scaling.** Labels are sized in *degrees* (a ground-em), so type grows as the camera
  descends — a single measure, scaled. The region areals scale with altitude and hand off smoothly
  by their own size, swelling and dissolving like clouds you fall past.
- **Geography-aware placement.** A label scores eight candidate directions against the coast,
  areals, and its neighbours, so coastal features lean their labels over open water (Morro Rock →
  ocean) instead of colliding inland.

## File map (`src/`)

| File | Role |
|------|------|
| `Atlas.jl` | Module entry — includes the pipeline, exports the render entry points. |
| `data.jl` | Load + cosφ₀ project the Natural Earth basemap (coast, land, lakes, rivers) + towns. |
| `pois.jl` | Hand-authored feature anchors: landmark POIs + the curved region areals (the ONLY hand-placed data). |
| `camera.jl` | The seamless geometric zoom loop (van Wijk & Nuij easing) → `camera_rect(p)`. |
| `lod.jl` | Geographic level-of-detail: `font_px` (ground-em × pixels-per-unit), the `band_alpha` fades, hydrography LoD. |
| `place.jl` | `measure_boxes` (TextMeasure) + `solve_frame` (warm-started `warm_solve`). |
| `render.jl` | The honest per-frame pipeline (`assemble_frame`) + the Makie render layer (basemap, areals, labels, chrome). |
| `loop.jl` | `render_loop` (the MP4) + `render_hero`. |
| `golden.jl` | The deterministic LoD/opacity golden table (geometric, no pixels). |

## The per-frame pipeline (`assemble_frame`)

For each loop phase `p`:

```
camera_rect(p)                  # camera.jl — this frame's view window (geometric zoom)
  → project anchors to px       # the geography lands on screen
    → font_px + band            # lod.jl   — geographic size + legibility/edge/size fades
      → measure → seed → solve  # place.jl — measure boxes, geography-aware seed, warm_solve
        → cull + leader fade    # deterministic visibility (coast clearance + occlusion)
          → draw                # render.jl — basemap → hydrography → areals → labels → chrome
```

Opacity is a **pure, stateless function of the frame's geometry** (legibility × framing ×
placement) — there is no temporal fade timer; continuity comes from the camera and the warm-started
solver moving smoothly, which is why the dive doesn't flicker.

## Determinism

`test/test_golden.jl` hashes the **computed** LoD/opacity table (`src/golden.jl`), never pixels.
That table is purely geometric — `font_px` from ground-ems, `band` from `band_alpha × edge_alpha`
over an affine projection that reproduces the Makie camera to ≤0.02px — so the digest is
reproducible across machines, fonts, and Makie versions. Regenerate with `UPDATE_GOLDEN=1`.

## Data provenance

Basemap (coast, land, lakes, rivers) is Natural Earth 1:10m (public domain); towns are verbatim
Natural Earth populated places plus hand-entered coastal towns. See `data/SOURCE.txt`.
