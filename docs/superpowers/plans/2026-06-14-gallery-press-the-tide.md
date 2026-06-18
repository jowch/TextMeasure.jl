# The Tide — Implementation Plan

> Example dir/package: `examples/tide/` (package `Tide`). Footer/name: **The Tide** (was "The Tide").
> Caption is a single line `TextMeasure.jl · The Tide` (the `prepare ×1 · shape_pack ×480 / loop`
> claim line was dropped per operator). Tide-line: ~12–14px gutter, modest symmetric overhang.

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Ship gallery piece 3/5 — a justified prose block kneaded by a wavy coral tide from 8
rotating directions, as a seamless 480-frame MP4 loop + a ghosted long-exposure thumbnail, built on
`shape_pack` with one `prepare`.

**Architecture:** Fold the verified prototype (`examples/tide/proto_still.jl`) into a `Tide`
package. Each frame: build a wavy region mask (BitMatrix) → `shape_pack(prep, raster_chord_fn(mask))`
→ per-band justify → draw. Backend-parameterized: `MakieBackend` for render, `MonospaceBackend` for
the deterministic golden. No new engine surface (per-band justify rewrites `Placement.x` only).

**Design source of truth:** `examples/breathing_column/SPEC.md` `⚑ LOCKED DESIGN` (2026-06-14).
Palette `#F2DFC6`/`#34232C`/coral `#E37C4B`; body Libre Caslon Text 11px; caption Hanken; lit word
`kneads`; wavy tide-line (no fill, ~7px gutter, symmetric overhang, no ticks); 8-axis pendulum
`W→E·SW→NE·S→N·SE→NW`; ease-out + HOLD; 16s@30fps=480 frames.

---

## File structure (`examples/tide/`)

- `Project.toml` — exists (pkg `Tide`, deps mirror Woven: CairoMakie, HouseStyle, Makie,
  TextMeasure, TextMeasureLayouts; `[sources]` → `../_housestyle`, `../..`, `../layouts`). No Manifest.
- `src/Press.jl` — module; `include`s; exports `render_hero`, `render_loop`, `render_thumb`, `hero_digest`.
- `src/text.jl` — the locked prose `const TIDE_TEXT`; `is_lit(word)` (matches "kneads").
- `src/schedule.jl` — `press_at(frame) -> (dir::Symbol, depth::Float64, phase::Float64)`; 8 dirs, ease-out, HOLD, seamless loop.
- `src/mask.jl` — `region_mask(W,H,dir,depth,phase; cell=1.0) -> BitMatrix`; wavy wall per direction; `band_interval(y,x1)` helper; floors (`floor_w`, min-height, grow-to-fit).
- `src/justify.jl` — `justify!(placements, chord_fn, prep) -> placements`; per-band flush-fill; **the no-overlap invariant lives here.**
- `src/frame.jl` — `frame_layout(make_backend, frame; …) -> (placements, tideline_pts, lit_idx, overflowed)`; the core, backend-parameterized; counts: 1 prepare per call-set, 1 `shape_pack` per frame.
- `src/render.jl` — `render_hero(path; frame=HOLD_FRAME)`, the Makie still (sunset palette, coral wavy tide-line, lit kneads, Hanken caption) lifted from `proto_still.jl` (keep the `markerspace=:data` + negated-y upright-glyph fixes); `render_thumb(path)` ghosted long-exposure.
- `src/loop.jl` — `render_loop(path; fps=30, n=480)` via CairoMakie `record`; assert 480 `shape_pack` / 1 `prepare`.
- `src/golden.jl` — `geometry_rows()` (MonospaceBackend, N frames incl ≥1 wavy-diagonal), `hero_digest()=digest_rows(...)`. Mirror `examples/woven/src/golden.jl`.
- `test/runtests.jl` + `test_schedule.jl` / `test_mask.jl` / `test_justify.jl` / `test_frame.jl` / `test_golden.jl`.
- Artifacts: `tide-hero.png` (exists, the hero), `tide-loop.mp4`, `tide-thumb.png`.

---

## Task 1 — Package skeleton + fold prototype into modules; hero still reproduces

**Files:** create `src/Press.jl`, `src/text.jl`, `src/mask.jl`, `src/justify.jl`, `src/frame.jl`,
`src/render.jl`; lift verbatim-working logic from `proto_still.jl`.

- [ ] Split `proto_still.jl` into the modules above with NO behavior change. `render_hero("tide-hero.png")` must reproduce the locked still pixel-for-pixel-equivalent (same layout table).
- [ ] `frame.jl::frame_layout(make_backend, frame)` parameterizes the backend (so golden can pass Monospace). For Task 1 it only needs the single HOLD frame (SW, depth=d_max).
- [ ] Keep the `band_interval(y,x1)` helper and the warm-render fixes.
- [ ] Run `julia --project=examples/press examples/tide/build.jl` (a tiny driver calling `render_hero`); open the PNG and confirm it matches the locked still.
- [ ] Commit.

## Task 2 — `justify.jl` extracted + the NO-OVERLAP invariant test (TDD)

**Files:** `src/justify.jl`, `test/test_justify.jl`.

- [ ] Write the failing test first: build a frame's placements via `frame_layout(MonospaceBackend-factory, HOLD)`, then assert, **per band**: words are non-overlapping and in order — `x[next] ≥ x[cur] + width[cur] − 1e‑6` (re-deriving widths independently from the backend, NOT from the justify output — non-tautological); justified bands have last-word-right ≈ R (flush); the paragraph's final line is ragged (not stretched); a single fixed baseline pitch across bands.
- [ ] Implement `justify!` to pass (lift the proto's per-band logic: group by baseline; `band_interval` for `[L,R]`; distribute slack to gaps; skip last-line/single-word/over-stretch).
- [ ] Run; green. Commit.

## Task 3 — `schedule.jl` 8-axis pendulum + loop-closure tests (TDD)

**Files:** `src/schedule.jl`, `test/test_schedule.jl`.

- [ ] Failing tests: `press_at(0) == press_at(480)` (byte-identical → seamless loop); the 8 directions occur in order `W,E,SW,NE,S,N,SE,NW`; within each 60-frame press, depth follows ease-out (monotone up to HOLD, ~zero-velocity at peak, monotone back); depth ∈ [0, d_max].
- [ ] Implement `press_at`. Commit.

## Task 4 — `mask.jl` all 8 directions (wavy) + floor/closure tests (TDD)

**Files:** `src/mask.jl` (generalize from the SW-only proto), `test/test_mask.jl`.

- [ ] Failing tests: for each direction at d_max, every band's interval ≥ `floor_w`; **≤ 1 interval per band** (the `fill=:widest` invariant) for cardinals AND diagonals AND the wavy edge; grow-to-fit guarantees all words place (no truncation) at the deepest bite.
- [ ] Generalize the mask: cardinal = wavy edge flush to a side; diagonal = wavy-raked triangular corner. Same low-amp sine (`A≈8px`, `λ≈2·line_advance`), phase from `press_at`.
- [ ] Commit.

## Task 5 — `frame.jl` honesty test: 480 shape_pack ↔ 1 prepare (TDD)

**Files:** `src/frame.jl`, `test/test_frame.jl`.

- [ ] Failing test: instrument a counter; running all 480 frames calls `prepare` exactly once and `shape_pack` exactly 480 times; every frame places all words (no truncation); ≥1 lit "kneads" placement each frame.
- [ ] Implement the per-frame driver. Commit.

## Task 6 — `loop.jl` 480-frame MP4 + `render_thumb` ghosted long-exposure

**Files:** `src/loop.jl`, `src/render.jl` (`render_thumb`).

- [ ] `render_loop("tide-loop.mp4")` via CairoMakie `record` over `press_at`; the coral tide-line undulates (phase per frame); seamless (frame 480 ≡ 0). Open the MP4; confirm the knead reads and loops without a seam.
- [ ] `render_thumb("tide-thumb.png")`: the SW-HOLD solid frame + 3–4 earlier real `shape_pack` tide-states ghosted behind (GRAY @ alpha 0.10–0.18 increasing toward front), "kneads" appearing solid (front) and ghosted (back). Open it; confirm it reads as motion-in-a-still.
- [ ] Commit (artifacts are gitignored only if large; commit the PNG hero+thumb, keep MP4 per gallery convention — check `.gitignore`).

## Task 7 — `golden.jl` deterministic digest + test (TDD)

**Files:** `src/golden.jl`, `test/test_golden.jl`, `test/golden/hero.sha256` + `hero.rows.txt`.

- [ ] `geometry_rows()` builds the MonospaceBackend layout table at structurally-distinct frames (rest, an E-cardinal peak, an SW-diagonal peak, the pinch-equivalent), one row per placement `frame|dir|round(x,2)|round(y,2)|lit|str`; `hero_digest()=digest_rows`. Mirror Woven's golden.
- [ ] Test asserts the digest matches the committed sha; placement count > threshold; ≥1 lit index; a diagonal frame is present. Hash the computed table, NEVER pixels.
- [ ] Commit the golden files.

## Task 8 — `test/runtests.jl` aggregate + final review

- [ ] `runtests.jl` includes all `test_*`. Run the suite; green.
- [ ] Final code review (spec compliance + quality). Operator opens `tide-hero.png`, `tide-thumb.png`, and `tide-loop.mp4` for visual sign-off (green ≠ sign-off).
- [ ] `superpowers:finishing-a-development-branch`.

---

## Invariants to hold (call out in every review)
- **No new engine surface** — per-band justify and the wavy mask are demo-side; `shape_pack` used as built.
- **No-overlap** is a *tested* guarantee (Task 2), re-deriving widths independently.
- **1 prepare / 480 shape_pack** is a *tested* honesty claim (Task 5).
- **Golden hashes the Monospace computed table, never pixels** (Cairo/ffmpeg not byte-stable).
- **Grow-to-fit** so a deep bite never silently truncates words; `log`/assert if it would.
- **Original prose is unsourced** — never attribute it.
