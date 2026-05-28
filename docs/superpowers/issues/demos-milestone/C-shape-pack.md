# C — `examples/layouts/shape_pack.jl`

> Wave 1 unblocker · shared example utility (most-reused across the demos).

## Scope

Reusable shape-conforming layout. Algorithm: per-band scanline, inspired by pretext.js's `wrap-geometry.ts` but with **different semantics** (see chord_fn contract below). Returns a typed struct, not a bare tuple-vector.

```julia
struct Placement
    segment_index :: Int          # index into the source Prepared.segments
    x             :: Float64
    y             :: Float64       # block-top coord frame (matches `layout`)
end

struct PackedLayout
    placements :: Vector{Placement}
    overflowed :: Vector{Int}      # segment indices wider than any chord at any row
    metrics    :: FontMetrics      # echoed from Prepared
end

shape_pack(prep::Prepared, chord_fn; line_advance, min_chord_width=24,
           overflow_strategy::Symbol=:widest_row) -> PackedLayout
```

### `chord_fn` contract

- `chord_fn(y_top::Real, y_bottom::Real) -> Vector{Tuple{Float64,Float64}}` returns the horizontal intervals **where text can be placed** in the band `[y_top, y_bottom]` (block-top coord frame, matching `layout`).
- **Relationship to pretext.js.** Inspired by pretext's per-band scanline approach, but **the signatures differ**: pretext's `getPolygonIntervalForBand` returns a single envelope `Interval | null` representing an OBSTACLE; pretext subtracts envelopes from the base column via `carveTextLineSlots`. Our `chord_fn` returns available intervals directly — uniform across text-INSIDE-shape (asteroid TUI) and text-AROUND-obstacle (DOIInfograph figure pillar, map feature, cover). Disjoint runs are preserved for concave silhouettes.
- Returned `(left, right)` pairs are **sorted ascending and pairwise disjoint**.
- An empty vector means no chord intersects this band (skip).
- **Multi-interval packing policy:** when a band has multiple disjoint intervals, `shape_pack` packs into the **widest** one and ignores the others; words are never split across disjoint intervals. Bands where the widest interval is below `min_chord_width` are skipped.
- Typed `AbstractChordFn` with dispatched `chord_intervals(shape, y_top, y_bottom)` is the long-term API; a plain closure is acceptable for milestone-1.

### Two `chord_fn` constructors as helpers

- `polygon_chord_fn(polygon::Vector{GeometryBasics.Point2{Float64}}) :: PolygonChordFn` — scanline intersection of a 2-D polygon.
- `raster_chord_fn(raster::BitMatrix, cell_size::Real) :: RasterChordFn` — for cell-grid silhouettes (Tachikoma).

### Overflow strategies

- `:widest_row` (default) — render in the widest available row, accept overflow.
- `:skip` — drop the segment, add to `overflowed`.
- `:reject` — return empty `PackedLayout` with all subsequent segments in `overflowed`.

## Acceptance

- Pack into rectangle of width `w` produces the same line breaks as `layout(prep; max_width=w)`.
- Pack into circle (smoke test on known font + text).
- Pack into concave U-shape; slivers below `min_chord_width` are dropped.
- `overflowed` correctly populated when a word exceeds the widest available chord.
- Coord-frame consistency: `placements[i].y` matches the corresponding `layout` baseline calculation for rectangular packs (within floating tolerance).
- **Relative perf baseline:** packing Vermont's state polygon at 300 DPI (~600 scanlines × ~30 edges) produces a `PackedLayout` and the wall-clock is recorded as a committed timing baseline. Subsequent CI runs flag regressions of >2× against this baseline. Absolute target intentionally unspecified — the baseline is comparative.

## Depends on / Blocks

- **Depends on:** nothing (uses `prep.segments` directly; does not need #A's `subprep`).
- **Blocks:** #E, #F2, #G, #H.

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#C — `examples/layouts/shape_pack.jl`."
- **Pretext.js reference:** `pages/demos/wrap-geometry.ts` in https://github.com/chenglou/pretext — read the source before implementing to understand the inspiration (and the key semantic difference we're choosing).
- **Existing code:**
  - `src/layout.jl` — current rectangle-only `layout()`; `shape_pack` should produce equivalent output for the rectangle case.
  - `src/types.jl` — `Prepared`, `Segment`, `FontMetrics`.
- **Conventions:** `CLAUDE.md` — "Not in scope: rendering, repel/treemap/annotation consumers (downstream)." `shape_pack` is downstream, hence `examples/`.
- **Long-term migration:** flagged for promotion to `TextMeasureLayouts.jl` post-milestone.

## Suggested labels

`demos-milestone` · `wave-1` · `examples` · `shared-utility`
