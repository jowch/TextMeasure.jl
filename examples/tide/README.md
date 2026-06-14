# The Tide

A kinetic-typography gallery piece built on the **TextMeasure** layout engine.

A short original prose passage about the sea working the shore is set as a justified block on a
warm sunset palette. A wavy coral **tide-line** sweeps counterclockwise around the block
(W → SW → SE → E → NE → NW); each press is a smooth swell that *kneads* the text — the layout
engine re-flows the prose into whatever region the wave leaves behind, frame after frame.

Artifacts (rendered into this directory):

- `tide-loop.mp4` — the seamless 60fps loop
- `tide-hero.png` — the hero still (the deep SW knead)
- `tide-thumb.png` — a ghosted long-exposure thumbnail

## The engine concept it demonstrates

**Measure once, lay out many.** The font engine is touched exactly *once* — `prepare_tide` calls
`prepare` on the text and caches every glyph-advance width. After that, **every frame is pure
arithmetic over the cached widths**: one `shape_pack` re-flows the prose into that frame's region,
and a demo-side justify pass nudges word positions. No per-frame measuring, and **no new engine
surface** — the demo only consumes `prepare` / `shape_pack` and rewrites `Placement.x`.

This claim is not just aspirational: `test/test_frame.jl` instruments the backend and asserts
**1 `prepare`, N_FRAMES `shape_pack`** over the whole loop.

## File map (`src/`)

| File | Role |
|------|------|
| `Tide.jl` | Module entry — includes the pipeline, exports the render entry points. |
| `text.jl` | The locked prose + the "is this the lit word (`kneads`)?" test. |
| `schedule.jl` | The seamless-loop swell: `press_at(frame) -> (dir, depth, phase)`. |
| `mask.jl` | `region_mask` — this frame's surviving region as a `BitMatrix` (the wavy tide). |
| `justify.jl` | `justify_bands` — demo-side flush-both-edges justify (rewrites `x` only). |
| `frame.jl` | `prepare_tide` (measure once) + `frame_layout` (one `shape_pack` per frame). |
| `render.jl` | Palette + `draw_frame!` + `render_hero` (the Makie render layer). |
| `loop.jl` | `render_loop`, `render_samples`, `render_thumb`. |

## The per-frame pipeline

Setup (once): `prepare_tide` → caches glyph widths, metrics, the region geometry, and a
constant box that fits the deepest knead in every direction.

Then, for each `frame`:

```
press_at(frame)        # schedule.jl — which direction, how deep (depth∈[0,1]), wave phase
  → region_mask(...)   # mask.jl     — the frame's wavy surviving region as a BitMatrix
    → shape_pack(...)  # ENGINE      — re-flow the cached widths into that region (one call)
      → justify_bands  # justify.jl  — demo-side: rewrite Placement.x flush to both margins
        → draw_frame!  # render.jl   — body glyphs + the faded coral tide-line (+ caption)
```

The loop is **seamless by construction**: `press_at` is periodic, so depth returns to exactly 0
at frame 0 ≡ frame N_FRAMES, with zero velocity at every trough (no crossfade needed).

## How to render

```bash
# the hero still (also the build.jl default)
julia --project=examples/tide examples/tide/build.jl

# or, from a REPL with the project active:
julia --project=examples/tide -e 'using Tide; Tide.render_loop()'     # the MP4 loop
julia --project=examples/tide -e 'using Tide; Tide.render_hero()'     # the hero still
julia --project=examples/tide -e 'using Tide; Tide.render_thumb()'    # the ghosted thumbnail
julia --project=examples/tide -e 'using Tide; Tide.render_samples()'  # rest + 6 press-peak PNGs
```

Scale convention: the **stills** (`render_hero`, `render_thumb`) render at `scale = 8` (~3500px
wide); the **loop** renders at `scale = 4`, 60fps, CRF 18 (supersampled then encoded near
visually-lossless so the thin coral line and small type don't shimmer under h264).

## Reusable ideas a reader can lift

1. **Per-frame region mask → `shape_pack`.** A layout region is just a `BitMatrix` of true/false
   cells; the packer doesn't care what shape it is. Animate the mask and you animate the reflow —
   here it's a wavy tide, but it could be any silhouette.
2. **Demo-side justification.** Full justification is done *outside* the engine in `justify_bands`:
   group placements into lines, then rewrite `Placement.x` to spread the slack. It adds no engine
   surface — `shape_pack` still does all the line-breaking.
3. **Seamless-loop schedule.** `press_at` returns a depth from a high-order smoothstep whose
   velocity vanishes at both ends of every press, so depth hits exactly 0 at the loop boundary —
   periodic and infinitely loopable with no crossfade.
4. **Geometry-driven, edge-faded line.** The tide-line is drawn from the *known* wall geometry (not
   from the placed words) and faded to transparent past the block edges and wherever the wall is
   too shallow to clear the type — so it reads as a long wave that never crosses into the glyphs.
