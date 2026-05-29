# Plan: shape_pack multi-interval-per-band packing (#C2)

## Goal

Extend `shape_pack` (in `examples/layouts/src/shape_pack.jl`) so a band offering
multiple disjoint chord intervals can be filled on BOTH sides of an obstacle.
Unblocks demos #G/#H (wrap text around left + right margins of a centered shape).

## Change

Add keyword `fill::Symbol = :widest` to `shape_pack`:

- `:widest` (DEFAULT) — exactly current behavior: pack only `_widest(intervals)`
  per band. ALL existing #C tests must pass unchanged.
- `:all` — per band, pack words greedily into EACH disjoint interval in
  left-to-right order. Fill leftmost interval (greedy, same rule as single-
  interval path), then continue into the next interval in the same band, then
  advance to next band. Reading order within a band: left-run words, then
  right-run words, then next band.

Validation: `fill in (:widest, :all)` else `ArgumentError`.

### Implementation shape

- Validate `fill` alongside `overflow_strategy`.
- Factor the per-interval greedy line-fill into a helper that takes the source
  segment cursor `si`, an interval `(L, R)`, the baseline `y`, and mutates
  `placements`/`overflowed`; returns the advanced `si`. Both `:widest` and
  `:all` reuse it so overflow semantics (`:widest_row`/`:skip`/`:reject`) stay
  identical and scoped to the interval being placed.
- `:widest` path: call helper once with `_widest(intervals)` (band-skip rule:
  widest `< min_chord_width` → skip whole band, unchanged).
- `:all` path: per band, iterate normalized intervals left-to-right; skip an
  individual interval whose width `< min_chord_width` (skip the interval, NOT
  the whole band); call the helper on each remaining interval at the same
  baseline. A band is "usable"/"entered" if it has ≥1 interval ≥ min_chord_width.
- `:reject` inside the helper still empties `placements` and returns early
  (abort) — preserve global-abort semantics.

Placements appended in left-to-right, per-band order; all at the band baseline.

## Tests (TDD, append to `examples/layouts/test/test_shape_pack.jl`)

a. DEFAULT `:widest` unchanged — keep existing rectangle-equivalence + overflow
   tests green (they don't pass `fill`, so default must be byte-identical).
b. `:all`, band with TWO intervals `[(0.0,50.0),(100.0,150.0)]` over a multi-word
   Prepared: words land in BOTH x-ranges, left-then-right reading order, same
   baseline. Assert x ranges + shared baseline + segment_index validity.
c. Concave `polygon_chord_fn` band with two runs (U-shape) fills both prongs
   under `:all`.
d. `min_chord_width` skips a sub-threshold interval but keeps the other in the
   same band (`[(0.0,5.0),(100.0,200.0)]`, mcw=24 → only right filled).
e. `:all` reduces to `:widest` output when every band has exactly one interval
   (rectangle): placements equal.

Assert on `PackedLayout` placements (x-ranges, baselines, segment_index
validity) — regression floors/bounds, not exact pixels.

## Constraints

- Touch ONLY `examples/layouts/src/shape_pack.jl` and
  `examples/layouts/test/test_shape_pack.jl`.
- Do NOT touch `TextMeasureLayouts.jl` (no new exported symbol) or `runtests.jl`.
- SPDX header preserved; Manifest gitignored.

## Verify

`julia --project=examples/layouts -e 'using Pkg; Pkg.test()'` once → existing 135
tests pass + new ones.
