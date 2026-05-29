# Knuth–Plass justification (#K, STRETCH) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:executing-plans (or
> subagent-driven-development) to implement task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Two deliverables.
1. **`examples/layouts/src/knuth_plass.jl`** — port of pretext.js's `kp.ts`. A whole-paragraph
   optimal line-breaker (`knuth_plass`) that consumes the same `Prepared.segments` as `layout` /
   `shape_pack` and minimizes **total badness**, plus a `greedy_justify` baseline (same badness
   model, greedy breaks) for head-to-head comparison. Shipped inside the already-merged
   `TextMeasureLayouts` package (#C).
2. **`examples/justification/`** — a new demo package that consumes `knuth_plass` / `greedy_justify`,
   detects **rivers** (vertical runs of inter-word gaps) in a justified layout, and renders the
   pretext.js `justification-comparison` exhibit: a single 3-column PDF (greedy-wide ‖ greedy-narrow ‖
   K-P-narrow) with river overlays.

**Architecture.** Justification is **out of TextMeasure's library scope** (CLAUDE.md), so every line of
this work lives in `examples/`. The algorithm is the classic Knuth–Plass dynamic program over a
box/glue model: `:word` segments are boxes, runs of `:space` segments are interword glue with
stretch/shrink, `:newline` segments are forced breaks. Per-line *badness* is the TeX
`100·|r|³` formula on the adjustment ratio `r`; the DP minimizes the sum. `greedy_justify` reuses the
identical badness/geometry machinery but selects breaks with `layout`'s greedy rule, so the comparison
isolates exactly one variable: the break-selection algorithm. River detection is pure geometry over
the justified gap centers — demo-specific, so it lives in `examples/justification`, not in the library
utility.

**Tech stack.** Julia 1.11+; `TextMeasure` + `TextMeasureLayouts` (both dev-pathed); `Test` (stdlib).
Demo render uses `CairoMakie` **0.15.10** (pairs with `Makie` 0.24.10, matching `test/Project.toml`'s
`Makie = "0.24"` pin) with **pinned fonts** Liberation Serif (body) + DejaVu Sans (labels), both
confirmed installed via `fc-list`. The render uses TextMeasure's `MakieBackend` (activated when
`using CairoMakie` transitively loads `Makie`) so measured geometry matches what `text!` renders.

---

## Probe results (probe-first, against live installed versions)

- **CairoMakie 0.15.10 / Makie 0.24.10** resolved in the global `v1.12` env; `Makie 0.24` matches the
  repo's existing `test/Project.toml` pin. → demo `[compat] CairoMakie = "0.15"`.
- **Fonts present:** `/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf` and
  `/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf`. Referenced by family name (`"Liberation Serif"`,
  `"DejaVu Sans"`), which `Makie.to_font` resolves via fontconfig — the same resolution `text!` uses.
- **`MakieBackend(; font, fontsize, px_per_unit=1.0)`** (ext) resolves a font face identical to
  `text!`'s; `px_per_unit = 1` per CLAUDE.md. Used only by the render, never by tests.
- **Segment model** (`src/prepare.jl`): `prepare` already collapses consecutive spaces into one
  `:space` segment and emits `:newline` segments with width 0 — clean box/glue input.
- **Greedy rule to match** (`src/layout.jl:34-56`): words atomic; a word joins the line when
  `committed_w + pending_space + word ≤ max_width`; leading/trailing whitespace trimmed per line.

## Issue-body fidelity check / flagged errors

- The issue body names the file `examples/layouts/knuth_plass.jl`; like #C's `shape_pack.jl`, the real
  path is **`examples/layouts/src/knuth_plass.jl`** (package `src/`), wired into
  `examples/layouts/src/TextMeasureLayouts.jl`. Only-path deviation — no behavioral change. **(I own
  the `TextMeasureLayouts.jl` edit this wave; additions are include+export only, no touch to
  `shape_pack`/chord-fn code.)**
- No factual API errors found in the issue body. The "hyphenation-off column → narrow-greedy vs
  narrow-K-P substitution" is honored exactly (see Task 3 columns).

## Decisions & deviations (for the plan gate)

1. **Badness model.** Interword glue natural width = the measured `:space` run width `g`. Stretch
   `= g·stretch_ratio` (default `0.5`), shrink `= g·shrink_ratio` (default `1/3`) — TeX's interword
   ratios. Per-line adjustment ratio `r`: `0` if `nat==target`; `(target−nat)/Σstretch` if underfull;
   `(target−nat)/Σshrink` (negative) if overfull. Badness `= 100·|r|³`, **capped/penalized** at
   `INF_BADNESS = 1e4` (TeX's "infinitely bad") + overflow magnitude when infeasible (`r<−1`, or
   underfull/overfull with zero stretch/shrink such as an atomic over-wide word) so the DP is always
   solvable and ties break toward less overflow. The **last line is ragged**: badness `0` when it fits
   (`nat ≤ target`), else the overfull penalty. Flagged: ratios + `INF_BADNESS` are tunable knobs.
2. **K-P objective = Σ per-line badness (last line free).** `knuth_plass` returns the break set that
   minimizes exactly the quantity the test reports, so "K-P badness < greedy badness" is a crisp,
   non-degenerate inequality (the acceptance criterion: *measurably lower total badness*). Standard
   TeX squares demerits; we minimize the linear badness sum because that is the reported metric and
   keeps the comparison interpretable. Flagged.
3. **Both algorithms share `_build_line` (geometry + badness).** The only difference is break
   selection. Guarantees a fair comparison and identical coordinate frame.
4. **Coordinate frame matches `layout`.** Line `i` (1-based) baseline = `ascent + (i−1)·lineheight·la`;
   block-left = 0. `word_x` are justified left edges; `gap_centers` are interword-gap centers.
5. **River detection lives in the demo** (`examples/justification`), not the library utility, because
   it is a visualization concern over geometry the utility already exposes (`gap_centers`).
6. **Tests use `MonospaceBackend`** (zero-dep, deterministic — every glyph equal width makes river
   geometry exactly reproducible). The render alone uses `MakieBackend` + CairoMakie. The
   `Justification` module does **not** `using CairoMakie`, so `Pkg.test()` never loads it; the render
   is a standalone script (`examples/justification/demo.jl`).
7. **Golden = computed-structure digest, not PDF bytes.** PDFs are nondeterministic (timestamps, font
   subsetting), so the committed golden is a text serialization of the *computed* comparison (break
   indices + per-line badness, rounded) with an SHA-checksum — deterministic and aligned with the
   "assert on COMPUTED structures, not pixels" directive. The PDF is rendered in VERIFY and its path
   attached to the PR message, but no CI gate hashes its bytes.
8. **Regression assertions are floors/ceilings, not hard counts** (per wave-1 conventions): badness
   inequality with a numeric margin; `n_rivers(greedy) ≥ 1` and `n_rivers(kp) < n_rivers(greedy)`.
9. **SPDX MIT header** on every new `.jl`. **Manifest.toml gitignored** (Project.toml only).

## File structure

- **Create** `examples/layouts/src/knuth_plass.jl` — `JustifiedLine`, `JustifiedLayout`,
  `knuth_plass`, `greedy_justify`, badness/geometry internals.
- **Modify** `examples/layouts/src/TextMeasureLayouts.jl` — add `include("knuth_plass.jl")` + exports
  (additive; `#K` already named in the module comment).
- **Create** `examples/layouts/test/test_knuth_plass.jl` — badness model + badness-inequality, wired
  into `runtests.jl`.
- **Modify** `examples/layouts/test/runtests.jl` — add the include.
- **Create** `examples/justification/Project.toml` (+ `.gitignore` for Manifest if no repo-level rule),
  `examples/justification/src/Justification.jl` (`River`, `find_rivers`, paragraph fixture),
  `examples/justification/test/runtests.jl`, `examples/justification/test/test_rivers.jl`,
  `examples/justification/demo.jl` (CairoMakie render), `examples/justification/README.md`,
  `examples/justification/test/comparison_golden.txt` (committed computed digest).
- **Modify** `examples/layouts/README.md` — document `knuth_plass`.

**Test commands** (capture once to the per-session log, then grep — CLAUDE.md):
```bash
mkdir -p test-logs
julia --project=examples/layouts examples/layouts/test/runtests.jl 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"
julia --project=examples/justification -e 'using Pkg; Pkg.test()' 2>&1 | tee -a "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"
```

---

## Task 1: `knuth_plass.jl` — box/glue model, badness, DP, greedy baseline (in `TextMeasureLayouts`)

**Files:** create `examples/layouts/src/knuth_plass.jl`; modify
`examples/layouts/src/TextMeasureLayouts.jl`, `examples/layouts/test/runtests.jl`; test
`examples/layouts/test/test_knuth_plass.jl`.

- [ ] **Step 1 — failing test** (`test_knuth_plass.jl`):
  - `types`: construct `JustifiedLine`/`JustifiedLayout`, field round-trip.
  - `badness model`: a hand-computed single line — pick `target`, words+glue with known `nat`, `Σstretch`;
    assert `ratio` and `badness == 100*r^3` within tol; assert a perfectly-fit line has badness `0`;
    assert the last line is badness `0` when short.
  - `K-P beats greedy (QUANTIFIED)`: canonical paragraph (a fixed ~60–90-word prose string),
    `prep = prepare(MonospaceBackend(), para)`, narrow `target`. Assert
    `knuth_plass(prep; max_width=target).total_badness < greedy_justify(prep; max_width=target).total_badness - MARGIN`
    with a concrete numeric `MARGIN` (tuned during impl; expect a large gap on a deliberately
    river-prone paragraph). Assert K-P is optimal: no single feasible break set has lower total badness
    than the DP result (spot-check by asserting `≤` greedy and `≤` a couple of hand-made break sets).
  - `coordinate frame`: K-P line `i` baseline `== ascent + (i-1)*la`; `word_x[1] == 0`; words
    non-overlapping left-to-right; `gap_centers` strictly increasing and one shorter than `words`.
  - `forced breaks`: paragraph with an embedded `\n` → a line boundary falls exactly at the newline
    in both algorithms.
- [ ] **Step 2 — run, expect FAIL** (`UndefVarError: knuth_plass`).
- [ ] **Step 3 — implement** `knuth_plass.jl`. Sketch:

```julia
# SPDX-License-Identifier: MIT
#
# knuth_plass — optimal whole-paragraph line breaking (#K, demos milestone).
# Port of pretext.js kp.ts. Classic Knuth–Plass box/glue DP minimizing total badness.
# Justification is out of TextMeasure's library scope (CLAUDE.md) — this is a demo utility.

const INF_BADNESS = 1.0e4   # TeX's "infinitely bad"; finite so the DP is always solvable.

"""One justified line. Coordinates share `layout`'s frame (block-left/top = 0)."""
struct JustifiedLine
    words         :: Vector{Int}      # :word segment indices, in order
    word_x        :: Vector{Float64}  # justified left edge of each word
    gap_centers   :: Vector{Float64}  # x center of each interword gap (length == nwords-1)
    natural_width :: Float64
    ratio         :: Float64          # adjustment ratio r
    badness       :: Float64
    baseline      :: Float64
end

"""Result of `knuth_plass`/`greedy_justify`. `total_badness` = Σ line badness. Read-only."""
struct JustifiedLayout
    lines         :: Vector{JustifiedLine}
    total_badness :: Float64
    max_width     :: Float64
    metrics       :: FontMetrics
end

# Box/glue extraction: words (seg idx + width), glue width after each word, forced-break flag.
# Leading spaces before the first word are dropped; trailing/inter-word spaces collapse to glue.
function _boxes_glue(prep) ... end   # -> (segidx::Vector{Int}, w::Vector{Float64},
                                     #     g::Vector{Float64}, forced::Vector{Bool})

# Natural width / total stretch / total shrink for words a..b (interior glue a..b-1).
function _line_metrics(w, g, stretch_ratio, shrink_ratio, a, b) ... end

function _badness(nat, stretch, shrink, target, is_last)
    is_last && nat <= target && return (0.0, 0.0)              # ragged last line
    if nat <= target
        nat == target && return (0.0, 0.0)
        stretch <= 0 && return (Inf, INF_BADNESS + (target - nat))
        r = (target - nat) / stretch
        return (r, 100 * r^3)
    else
        shrink <= 0 && return (-Inf, INF_BADNESS + (nat - target))
        r = (target - nat) / shrink                            # negative
        r < -1 && return (r, INF_BADNESS + (nat - target))
        return (r, 100 * abs(r)^3)
    end
end

# Build a JustifiedLine for words a..b on a given baseline (computes geometry from r).
function _build_line(segidx, w, g, stretch_ratio, shrink_ratio, a, b, target, baseline, is_last) ... end

"""
    knuth_plass(prep; max_width, stretch_ratio=0.5, shrink_ratio=1/3, lineheight=1.0) -> JustifiedLayout

Optimal line breaks minimizing total badness (Knuth–Plass DP). Forced breaks at `:newline`.
"""
function knuth_plass(prep::Prepared; max_width::Real, stretch_ratio=0.5, shrink_ratio=1/3, lineheight=1.0)
    # O(W^2) DP over W words: best[j] = min_i best[i] + badness(line i+1..j); skip (i,j)
    # spanning a forced break. Reconstruct breaks, then _build_line each.
end

"""
    greedy_justify(prep; max_width, ...) -> JustifiedLayout

Same badness/geometry as `knuth_plass`, but breaks greedily (mirrors `src/layout.jl`): a word
joins the current line while it fits; otherwise it starts the next line. Forced breaks at `:newline`.
The comparison baseline.
"""
function greedy_justify(prep::Prepared; max_width::Real, stretch_ratio=0.5, shrink_ratio=1/3, lineheight=1.0)
    ...
end
```

- [ ] **Step 4 — wire module** (`TextMeasureLayouts.jl`): add
  `export JustifiedLine, JustifiedLayout, knuth_plass, greedy_justify` and `include("knuth_plass.jl")`
  **after** the existing `shape_pack` include. Touch nothing else.
- [ ] **Step 5 — wire aggregator** (`runtests.jl`): add `include("test_knuth_plass.jl")`.
- [ ] **Step 6 — run, expect PASS.** Tune `MARGIN` and the canonical paragraph so the inequality holds
  with comfortable headroom (record the observed greedy/K-P badness values in a code comment).
- [ ] **Step 7 — commit** `feat(layouts): knuth_plass optimal justification + greedy baseline (#K)`.

---

## Task 2: `examples/justification` package — river detection (TDD, deterministic)

**Files:** create `examples/justification/Project.toml`, `src/Justification.jl`,
`test/runtests.jl`, `test/test_rivers.jl`.

- [ ] **Step 1 — Project.toml** (Manifest gitignored):

```toml
name = "Justification"
uuid = "<fresh uuidv4>"
version = "0.1.0"
authors = ["TextMeasure.jl contributors"]

[deps]
CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
TextMeasure = "06791c1d-2336-41e1-bd6f-a74c63395da6"
TextMeasureLayouts = "57b0e3ea-cc01-4cc3-9e7e-6e97d1609b9f"

[compat]
CairoMakie = "0.15"
julia = "1.11"

[extras]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Test"]
```

  Then `Pkg.develop(path="../..")` (TextMeasure) and `Pkg.develop(path="../layouts")`
  (TextMeasureLayouts) into the env, and `instantiate`.

- [ ] **Step 2 — failing test** (`test_rivers.jl`, uses `MonospaceBackend`):
  - `find_rivers basics`: a hand-built `JustifiedLayout` with three lines whose middle gap centers are
    within `align_tol` → exactly one `River` of length 3; gaps that don't align → no river.
  - `greedy has rivers K-P avoids (QUANTIFIED FLOOR)`: canonical paragraph + narrow width;
    `g = greedy_justify(prep; max_width=w)`, `k = knuth_plass(prep; max_width=w)`. Assert
    `length(find_rivers(g)) >= 1` and `length(find_rivers(k)) < length(find_rivers(g))`. Paragraph/
    width/`align_tol` tuned during impl so the floor holds deterministically under Monospace.
- [ ] **Step 3 — run, expect FAIL** (module/symbol undefined).
- [ ] **Step 4 — implement** `src/Justification.jl`:

```julia
# SPDX-License-Identifier: MIT
module Justification

using TextMeasure
using TextMeasureLayouts: JustifiedLayout, JustifiedLine, knuth_plass, greedy_justify

export River, find_rivers, CANONICAL_PARAGRAPH

"A vertical run of inter-word gaps aligned across consecutive lines."
struct River
    points :: Vector{Tuple{Int,Float64}}   # (line_index, gap_center_x), consecutive lines
end

"""
    find_rivers(lay; align_tol, min_run=3) -> Vector{River}

Greedy-chain gap centers across consecutive lines: a gap in line L extends a chain to the
nearest unused gap in line L+1 within `align_tol`. Chains of length ≥ `min_run` are rivers.
"""
function find_rivers(lay::JustifiedLayout; align_tol::Real, min_run::Int=3) ... end

const CANONICAL_PARAGRAPH = "…fixed prose chosen to produce a greedy river…"

end
```

- [ ] **Step 5 — aggregator** (`test/runtests.jl`): `@testset "Justification"` includes `test_rivers.jl`.
- [ ] **Step 6 — run, expect PASS.** Tune paragraph/width/`align_tol`/`min_run`.
- [ ] **Step 7 — commit** `feat(justification): river detection + greedy-vs-KP river floor test (#K)`.

---

## Task 3: render `demo.jl` (3-column comparison PDF) + golden digest + READMEs

**Files:** create `examples/justification/demo.jl`, `examples/justification/README.md`,
`examples/justification/test/comparison_golden.txt`; modify `examples/layouts/README.md`.

- [ ] **Step 1 — golden digest test** (append to `test_rivers.jl` or a small `test_golden.jl`):
  serialize the computed comparison deterministically — for each column
  `(algorithm, max_width)`, emit `break word-index list` + per-line `round(badness, digits=3)` — join
  to a string, `bytes2hex(sha256(...))`, compare against a committed
  `comparison_golden.txt`. On first run, write it; thereafter assert equality. Uses `MonospaceBackend`
  (deterministic). This is the committed golden (NOT the PDF bytes).
- [ ] **Step 2 — `demo.jl`** (standalone; `using CairoMakie, TextMeasure, TextMeasureLayouts, Justification`):
  - `const BODY_FONT = "Liberation Serif"`, `const LABEL_FONT = "DejaVu Sans"` (pinned families).
  - `prep = prepare(MakieBackend(; font=BODY_FONT, fontsize=11, px_per_unit=1.0), CANONICAL_PARAGRAPH)`.
  - Three columns: **(1)** `greedy_justify(prep; max_width = WIDE)`, **(2)**
    `greedy_justify(prep; max_width = NARROW)` (`NARROW ≈ 0.5·WIDE`), **(3)**
    `knuth_plass(prep; max_width = NARROW)`.
  - Render each column into one `Axis` of a 1×3 `Figure`: `text!` each word at `(word_x, -baseline)`
    in `BODY_FONT`; draw river overlays from `find_rivers` as translucent vertical poly-lines through
    the gap centers (greedy columns show rivers, K-P column shows the absence). Column titles in
    `LABEL_FONT`. `hidedecorations!`, equal data aspect, `yreversed = true` (block-top frame).
  - `save(joinpath(@__DIR__, "comparison.pdf"), fig)`; print the absolute path.
- [ ] **Step 3 — run** `demo.jl` end-to-end; confirm a non-empty `comparison.pdf` is produced and the
  river overlay is visually present in the greedy-narrow column and absent/reduced in the K-P column.
- [ ] **Step 4 — READMEs.** `examples/justification/README.md`: what the exhibit shows, how to run the
  tests and `demo.jl`, the pinned-fonts + CairoMakie note, Manifest-not-committed note. Append a
  `knuth_plass` section to `examples/layouts/README.md` (signature, badness model, one example).
- [ ] **Step 5 — commit** `feat(justification): CairoMakie 3-column comparison render + golden digest (#K)`.

---

## Task 4: verification, license sweep, final run

- [ ] **Step 1 — license headers:**
  `grep -rL "SPDX-License-Identifier" examples/layouts/src examples/layouts/test examples/justification --include='*.jl'`
  → expect no output.
- [ ] **Step 2 — run both suites once → per-session log → grep** (commands above). Expect both green.
- [ ] **Step 3 — render the PDF** via `demo.jl`; record its absolute path for the PR message.
- [ ] **Step 4 — confirm `git status`** shows only `examples/` + `docs/superpowers/plans/` +
  `examples/layouts/README.md`; **no committed Manifest.toml**; `src/` untouched.
- [ ] **Step 5 — commit** any stragglers; do **not** run finishing-a-development-branch.

---

## Self-review (against the #K issue body)

- **K-P measurably lower total badness than greedy on a canonical paragraph** → Task 1 quantified
  inequality with numeric MARGIN. ✓
- **River overlay identifies greedy rivers K-P avoids** → Task 2 `n_rivers(greedy) ≥ 1`,
  `n_rivers(kp) < n_rivers(greedy)`. ✓
- **Comparison demo renders all three columns as a single PDF** → Task 3 `demo.jl` 1×3 figure,
  greedy-wide ‖ greedy-narrow ‖ K-P-narrow (the issue's hyphenation-substitution columns). ✓
- **Lives entirely in `examples/`** (justification out of library scope) → `examples/layouts` +
  `examples/justification`. ✓
- **Consumes `Prepared.segments`, same input as `layout`/`shape_pack`** → `_boxes_glue(prep)`. ✓
- **Wave-1 conventions:** Manifest gitignored; `examples/justification` gets `[extras] Test` +
  `[targets] test`; SPDX headers; pinned fonts; computed-structure assertions; additive edit to the
  shared `TextMeasureLayouts.jl`. ✓
- **Decoupling from #F/#H:** not load-bearing here — #K ships its own demo; opt-in consumers are out
  of this lane's scope. ✓
