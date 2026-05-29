<!-- SPDX-License-Identifier: MIT -->
# Justification comparison (`examples/justification`) — #K [STRETCH]

A port of pretext.js's `justification-comparison` exhibit: the **same paragraph** set three
ways, so the cost of greedy line-breaking is visible next to Knuth–Plass's badness-minimized
breaks.

| Column | Algorithm | Measure | Shows |
|---|---|---|---|
| 1 | greedy (`greedy_justify`) | wide | comfortable baseline — few/no rivers |
| 2 | greedy (`greedy_justify`) | narrow (~0.5× wide) | where greedy **pools gaps into rivers** |
| 3 | Knuth–Plass (`knuth_plass`) | narrow (same as col 2) | K-P's win on the same hard constraint |

> Hyphenation is out of TextMeasure's scope (`CLAUDE.md`), so the original demo's
> hyphenation-off column — which would degenerate into a duplicate of greedy here — is
> replaced by **narrow-greedy vs narrow-K-P**. That preserves the demo's point (showing
> where badness-minimization helps) without inventing hyphenation we don't have.

## Rivers

A **river** is a run of inter-word gaps that line up vertically across ≥3 consecutive lines.
`find_rivers(lay::JustifiedLayout; align_tol, min_run=3)` greedy-chains gap centers across
consecutive lines (within `align_tol`; ties broken toward the lower x for reproducibility)
and returns the chains of length ≥ `min_run`. On the canonical paragraph at a narrow measure,
greedy produces rivers that K-P avoids — asserted as a quantified floor in the tests
(`n_rivers(greedy) ≥ 1` and `n_rivers(kp) < n_rivers(greedy)`), deterministically under the
zero-dependency `MonospaceBackend`.

## Render the comparison PDF

```bash
julia --project=examples/justification examples/justification/demo.jl
# → examples/justification/comparison.pdf
```

The render measures with TextMeasure's `MakieBackend` in the **same pinned body font**
CairoMakie draws with (geometry is pixel-faithful; `px_per_unit = 1` per `CLAUDE.md`). Pinned
fonts: **Liberation Serif** (body) + **DejaVu Sans** (labels). River channels are overlaid in
translucent red so the eye can see what greedy creates and K-P breaks up.

## Run the tests

```bash
julia --project=examples/justification -e 'using Pkg; Pkg.test()'
```

Tests use `MonospaceBackend` only (no CairoMakie load), and assert on **computed structures**:
break positions, per-line badness, and river counts. The committed
`test/comparison_golden.txt` is a SHA-256 digest of the *computed* 3-column comparison (break
word-lists + per-line badness) — **not** the PDF bytes, which are nondeterministic.

> The `Manifest.toml` is intentionally **not** committed; run `Pkg.instantiate()` against the
> committed `Project.toml`. Depends on `TextMeasure` and `TextMeasureLayouts` via
> `Pkg.develop(path=…)` (`../..` and `../layouts`).
