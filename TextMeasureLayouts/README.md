<!-- SPDX-License-Identifier: MIT -->
# TextMeasureLayouts

Shared layout utilities that sit on top of TextMeasure. Houses `shape_pack`
— a shape-conforming text-layout consumer — and `knuth_plass`.

A top-level sibling package in this repo (registration target: a registered
`TextMeasureLayouts.jl`). The demos under `examples/` consume it via a path
`[sources]` entry (`path = "../../TextMeasureLayouts"`); external consumers install
it from General once registered.

> The `Manifest.toml` is intentionally **not** committed (per-demo manifests stay
> gitignored). Reproducibility comes from `Pkg.instantiate()` at run/CI time against the
> committed `Project.toml`.

## `shape_pack`

```julia
using TextMeasure, TextMeasureLayouts
prep = prepare(MonospaceBackend(), "…prose…")
pk = shape_pack(prep, polygon_chord_fn(my_polygon); line_advance=prep.metrics.line_advance)
```

`shape_pack(prep, chord_fn; line_advance, min_chord_width=24, overflow_strategy=:widest_row)`
packs the `:word` segments of `prep` into the region described by `chord_fn`, walking
horizontal bands of height `line_advance` from the top down, and returns a `PackedLayout`
of word `Placement`s in reading order. A full-width rectangle chord_fn reproduces
`layout(prep; max_width=w)` (newline-free text).

- **`chord_fn`** — a closure `(y_top, y_bottom) -> Vector{Tuple{Float64,Float64}}` (or an
  `AbstractChordFn`) returning the available, sorted, disjoint intervals in a band. Empty
  ⇒ skip the band; the widest interval is used when several are returned.
- **Overflow strategies** — `:widest_row` (place at the band's left edge + record in
  `overflowed`), `:skip` (drop + record, back-fill the band with later words), `:reject`
  (abort: empty `placements`, offending + later word indices in `overflowed`).
- **Helpers** — `polygon_chord_fn(::Vector{Point2{Float64}})` (scanline of a 2-D polygon)
  and `raster_chord_fn(::BitMatrix, cell_size)` (cell-grid silhouettes).

All coordinates share `chord_fn`'s frame and `prep.metrics` units.

## `knuth_plass`

```julia
using TextMeasure, TextMeasureLayouts
prep = prepare(MonospaceBackend(), "…prose…")
opt = knuth_plass(prep;   max_width=300)        # optimal, badness-minimizing breaks
gdy = greedy_justify(prep; max_width=300)        # greedy baseline (== layout()'s breaks)
@assert opt.total_badness <= gdy.total_badness   # K-P never loses on total badness
```

`knuth_plass(prep; max_width, stretch_ratio=0.5, shrink_ratio=1/3, lineheight=1.0)`
breaks a whole paragraph into lines that **minimize total badness** via the classic
Knuth–Plass dynamic program, and returns a `JustifiedLayout` (`lines::Vector{JustifiedLine}`
+ `total_badness`). It models `:word` segments as boxes, collapsed `:space` runs as
stretch/shrink glue, and `:newline` as forced breaks.

- **Badness** — TeX's `100·|r|³` on the per-line adjustment ratio `r`; an infeasible line
  (overshrink, or an atomic over-wide word) costs `INF_BADNESS + overflow` so the program
  is always solvable. The last line — and any line ending at a forced break — is **ragged**
  (badness 0 when it fits, never stretched to the measure).
- **`greedy_justify`** — the comparison baseline: identical badness/geometry, but breaks
  greedily on **natural** widths exactly like `layout` (its break set equals
  `layout(prep; max_width)`'s). The only variable between the two is break selection.
- **Geometry** — each `JustifiedLine` exposes `word_x`, `gap_centers` (justified inter-word
  gap centers, for river detection), `ratio`, `badness`, and `baseline` (block-top frame,
  matching `layout`).

Justification is **out of TextMeasure's library scope** (see `CLAUDE.md`); `knuth_plass`
lives here as a downstream demo utility, consumed by the gallery pieces (The Tide / Woven).

## Examples

Runnable, zero-dependency demos — they print to the terminal (no graphics backend, using
the deterministic `MonospaceBackend`).

### `shape_pack_ascii.jl`

Pours one paragraph of prose into a triangle (`polygon_chord_fn`) and a circle
(`raster_chord_fn`), flush-justifying each line to its band's margins so the silhouette reads
solid.

```bash
julia --project=TextMeasureLayouts TextMeasureLayouts/examples/shape_pack_ascii.jl
```

```
polygon_chord_fn — justified inside a triangle:

      the
     sea
    kneads
   the  shore
  in slow

raster_chord_fn — justified inside a circle:

    the sea
 kneads    the
shore  in  slow
folds  of  foam
and  salt while
 light  spills
    wide
```

### `optimal_linebreaks.jl`

`knuth_plass` vs `greedy_justify` on one paragraph, shown flush-justified to the measure —
optimal breaks minimize *total* badness across the whole paragraph, not line by line (greedy
strands a short last line; K-P packs six fuller ones).

```bash
julia --project=TextMeasureLayouts TextMeasureLayouts/examples/optimal_linebreaks.jl
```

```
greedy_justify:  (total badness 3512.6)
  | in   the   practice   of  typesetting  a
  | paragraph  reads best when its lines are
  | evenly loose rather than tight here then
  | loose  there  which is exactly the trade
  | the  greedy  rule keeps making while the
  | optimal  program  looks  ahead to spread
  | the slack

knuth_plass:  (total badness 280.9)
  | in the practice of typesetting a paragraph
  | reads best when its lines are evenly loose
  | rather  than tight here then loose there
  | which is exactly the trade the greedy rule
  | keeps  making  while the optimal program
  | looks ahead to spread the slack

✓ knuth_plass total badness ≤ greedy (280.9 ≤ 3512.6)
```

## Run the tests

```bash
julia --project=TextMeasureLayouts TextMeasureLayouts/test/runtests.jl
```
