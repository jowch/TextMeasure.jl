# TextMeasure.jl — Pre-Release Readability & Docstring Audit

## Executive summary

TextMeasure.jl is in good shape for a first release: the code is clean, the prose
docstrings are accurate, and the example READMEs (especially `examples/layouts/` and
`examples/tide/`) teach the conceptual thesis well. The single dominant gap is that
**not one symbol anywhere — `src/`, `ext/`, or the four examples — carries a runnable
`# Examples` block**, even though `MonospaceBackend` is deterministic and explicitly
described as doctestable. A newcomer who types `?prepare`, `?layout`, or `?MonospaceBackend`
sees a correct sentence but never a copy-pasteable call, so the library's headline contract
("measure once via `prepare`, lay out many times via `layout` at different `max_width`") is
stated but never demonstrated. The highest-leverage work is therefore: (1) seed deterministic
jldoctests on the three headline `src/` symbols; (2) add `# Examples` to each example's one
"engine showcase" function; (3) fix the handful of docstrings that leak internal artifacts
(`#E`, "Tachikoma asteroid"), have malformed signature lines, or omit kwargs the function
actually takes. Do the `src/` doctests first (they double as CI guards), then the per-example
showcases, then the readability refactors.

## Highest-leverage changes (ranked)

1. **`src/monospace.jl:1`** — Add a deterministic `jldoctest` to `MonospaceBackend` driving
   the full on-ramp: construct it, show `measure(b, "abc")` and `font_metrics(b)` returning
   exact numbers, then `prepare` + `layout` reading a result field. This is the package's only
   deterministic backend and the documented entry point; one example teaches the API, shows how
   a backend's two methods are consumed, and CI-guards the metric math.
2. **`src/layout.jl:15`** — Add a `jldoctest` that `prepare`s once then calls `layout` twice at
   different `max_width`, reading `lay.size` / `lay.lines[1].str` / `.width`. This makes the
   "measure once, lay out many" thesis — the central idea of the library — copy-paste runnable.
   Also document that `max_width <= 0` or `NaN` is treated as `Inf` (only visible today at line 25).
3. **`src/prepare.jl:16`** — Add a `jldoctest` showing `prepare(MonospaceBackend(fontsize=10),
   "hello world")`, `length(prep.segments)`, and a segment's `.kind`/`.width`; state in prose that
   the result feeds `layout`. This is THE entry point and currently has no runnable example.
4. **`examples/layouts/src/knuth_plass.jl:158` + `shape_pack.jl:130`** — Add `jldoctest`s reusing
   values the test suite already pins: `knuth_plass(prepare(MonospaceBackend(), "xxxxxxx x x
   xxxxxxx"); max_width=79.2).total_badness == 0.0`, and the rectangle `shape_pack == layout`
   equivalence. This is the best-documented example area; converting pinned facts to doctests is
   near-zero-risk and makes the strongest area self-demonstrating.
5. **`examples/atlas/src/place.jl:19`** — Promote `measure_boxes` from a one-line string docstring
   to a full docstring with a `# Examples` showing the bare `layout(prepare(backend, "Morro Bay")).size`
   call and noting `px_per_unit=1` matches Makie. This is the one function in Atlas that exists to
   demonstrate the TextMeasure API, yet it under-documents it.
6. **`examples/tide/src/frame.jl:12` + `:133`** — Add deterministic `# Examples` to `prepare_tide`
   and `frame_layout` using the existing `golden_backend` factory, paired as one prepare-once /
   lay-out-many snippet. Also fix `prepare_tide`'s signature line to include the `grow_dirs` kwarg
   it actually takes (frame.jl:24). This turns the piece's thesis from prose into runnable code.
7. **`examples/woven/src/layout.jl:33`** — Add a `jldoctest` to `placement_table` (the declared
   engine showcase) via `golden_backend`: `placements, jl, pitch = placement_table(golden_backend;
   ghost_color=:ghost, red_color=:red, black_color=:black)` then inspect `placements[1]`.
8. **`ext/TextMeasureFreeTypeExt.jl:7` + `ext/TextMeasureMakieExt.jl:7` + `:163` +
   `ext/TextMeasureFigletExt.jl:48`** — Attach usage-bearing docstrings to the four user-facing
   extension entry points (the three keyword constructors + `measure_bounds(::MakieBackend,
   ::RichText)`), each with a signature line, its load-bearing caveat (font resolution /
   `px_per_unit=1` / cell-vs-pixel units), and a non-doctest `# Examples`. Today `?FreeTypeBackend`
   after `using` shows only the bare positional container.
9. **`src/prepare.jl:44` (`subprep`)** — Replace the internal `#E` issue reference with
   plain-language motivation ("re-layout a sub-range of an already-measured paragraph without
   re-touching the font engine") and add a `jldoctest` of `subprep(prep, 1:3)` then `layout`. A
   public reader cannot resolve `#E`.
10. **Module docstrings** — Add a module-level docstring to `examples/layouts/src/TextMeasureLayouts.jl:2`,
    `examples/woven/src/Woven.jl:2`, and `examples/_housestyle/src/HouseStyle.jl:2`. These are the
    `?ModuleName` REPL on-ramps and currently return nothing; each should name its public surface and
    the end-to-end pipeline.
11. **`src/types.jl:1` (and `:8`, `:15`, `:29`, `:38`)** — Give `FontMetrics`, `Segment`, `Prepared`,
    `Line`, `Layout` idiomatic docstrings: a `    TypeName` signature line in a code fence and per-field
    docs. Readers inspecting `Layout`/`Line` to consume results currently get terse one-liners.
12. **Public-surface reconciliation** — `FigletBackend` is exported (`src/TextMeasure.jl:7`) and
    documented, but CLAUDE.md's "Backends" section lists only FreeType/Makie. Reconcile the docs with
    the export list before release so a reader scanning exports doesn't meet an undocumented-in-architecture
    backend.

## Docstrings

### src core API (`src/`)

| Symbol | Location | State | Fix |
|---|---|---|---|
| `MonospaceBackend` | monospace.jl:1 | no example | Add deterministic `jldoctest` (full on-ramp). **Anchor doctest for the package.** |
| `prepare` | prepare.jl:16 | no example | `jldoctest` of `prepare(...)`, `length(prep.segments)`, a segment's `.kind`/`.width`. |
| `layout` | layout.jl:15 | no example | `jldoctest` calling `layout` twice at different `max_width`; document `max_width<=0`/`NaN` ⇒ `Inf`. |
| `subprep` | prepare.jl:44 | malformed | Drop `#E` reference; plain-language motivation + `jldoctest`. |
| `measure` (Monospace) | monospace.jl:17 | missing | One-line `jldoctest`: `measure(MonospaceBackend(fontsize=10,advance_ratio=1.0), "abc") == 30.0`. |
| `font_metrics` (Monospace) | monospace.jl:20 | missing | Document the fixed 0.8/0.2 ascent/descent split (not a real font) in the `MonospaceBackend` docstring. |
| `line_top` | layout.jl:68 | malformed | Move the signature off the `"""` line onto its own indented line; add a one-line block-top=0 example. |
| `measure_bounds` | backend.jl:23 | no example | State it throws `MethodError` on `MonospaceBackend` (extension-only); cross-ref the providing extension. |
| `FontMetrics`/`Segment`/`Prepared`/`Line`/`Layout` | types.jl:1,8,15,29,38 | malformed | Add signature line + per-field docs. |
| `Prepared` kw ctor | types.jl:21 | malformed | Trim maintainer commentary ("outer method", "auto-generated positional ctor"); one line or drop. |

Public symbols that should get **jldoctest-able** examples (MonospaceBackend deterministic):
`MonospaceBackend`, `prepare`, `layout`, `subprep`, `measure`/`font_metrics` (Monospace methods),
`line_top`.

### Backends + bounds

- `bounds` (bounds.jl:35) — internal, no example: lift the worked numbers already in
  `test/test_bounds.jl` (`StyledRun(0,0,10,8,2)` ⇒ origin `(0,-2)`, size `(10,10)`) into a plain
  `# Examples`. `StyledRun`/`TextBounds` (bounds.jl:1) are already exemplary — no change.
- `FreeTypeBackend`/`MakieBackend`/`FigletBackend` containers (backend_containers.jl) — already good;
  the deterministic doctests belong on `MonospaceBackend`, not here.

### Extensions (`ext/`)

| Symbol | Location | State | Fix |
|---|---|---|---|
| `FreeTypeBackend(; font, fontsize, dpi)` | FreeTypeExt.jl:7 | missing | Method docstring: signature, document `font`/`fontsize`/`dpi`, the missing-font `ArgumentError`, non-doctest example. |
| `MakieBackend(; font, fontsize, px_per_unit)` | MakieExt.jl:7 | missing | Method docstring; surface the `px_per_unit=1` requirement to `?MakieBackend` (today buried in CLAUDE.md). |
| `measure_bounds(::MakieBackend, ::RichText)` | MakieExt.jl:163 | no example | Document supported RichText subset, the `px_per_unit==1` throw, +y-up convention, a `rich("x", superscript("2"))` sketch. |
| `FigletBackend(; font, letter_gap)` | FigletExt.jl:48 | missing | Brief docstring cross-referencing that `measure` returns CELL counts; accept font name or `FIGletFont`. |

All four are font/system-dependent ⇒ **plain `# Examples`, not jldoctests.**

### examples/layouts

| Symbol | Location | Fix |
|---|---|---|
| `TextMeasureLayouts` (module) | TextMeasureLayouts.jl:2 | Module docstring naming `shape_pack`/`knuth_plass`/`greedy_justify` + a ~4-line `prepare`→`shape_pack` example. |
| `knuth_plass` | knuth_plass.jl:158 | `jldoctest` (badness 0.0 on the canonical fixture). **jldoctest-able.** |
| `shape_pack` | shape_pack.jl:130 | `jldoctest` (rectangle `shape_pack == layout`). **jldoctest-able.** |
| `greedy_justify` | knuth_plass.jl:213 | `# Examples` / See-also with the `opt.total_badness <= gdy.total_badness` invariant. |
| `polygon_chord_fn`/`raster_chord_fn` | shape_pack.jl:287 | Tiny `jldoctest` of returned intervals; **remove the "Tachikoma asteroid" in-joke** (line 336) → neutral phrase. |

### examples/atlas

| Symbol | Location | Fix |
|---|---|---|
| `measure_boxes` | place.jl:19 | Promote to full docstring + `# Examples` of the two-phase call (the example's reason to exist). |
| `load_atlas_data` | data.jl:90 | **Missing** — add docstring; it's the only disk-touching phase / the reader's front door. |
| `AtlasData` | data.jl:20 | Missing struct docstring (the projected-map-units bundle). |
| `project_point` | data.jl:9 | One-line `# Examples` + why x is compressed by `cos(phi0)`. |
| `Town` | data.jl:11 | Short docstring naming `rank` as the LoD key. |
| `town_ground` | lod.jl:21 | Malformed: lead with what it returns, tuning prose after. jldoctest candidate. |
| `smoothstep` | camera.jl:9 | Missing one-line docstring (used pervasively in lod.jl). |

`feature_lod` (render.jl:409) and `assemble_frame` (render.jl:453) are model docstrings — use as templates.

### examples/tide

| Symbol | Location | Fix |
|---|---|---|
| `prepare_tide` | frame.jl:12 | `# Examples` via `golden_backend`; **fix signature line to include `grow_dirs`.** jldoctest-able. |
| `frame_layout` | frame.jl:133 | `# Examples` continuing `prepare_tide` (the prepare-once/lay-out-many pair). jldoctest-able. |
| `is_lit`/`has_lit` | text.jl:15 | Add `jldoctest`s (pure string predicates); `has_lit` lacks a docstring entirely. |
| `press_at` | schedule.jl:35 | `jldoctest`: `press_at(0)[2] == 0.0`, `press_at(N_FRAMES) == press_at(0)`. |
| `region_mask` | mask.jl:28 | Replace non-evaluable signature placeholders with concrete defaults; tiny `jldoctest`. |

### examples/woven

| Symbol | Location | Fix |
|---|---|---|
| `Woven` (module) | Woven.jl:2 | Module docstring naming `hero(path)` + `placement_table` + the measure→synthetic-Prepared→knuth_plass pipeline. |
| `placement_table` | layout.jl:33 | `jldoctest` via `golden_backend` (the engine showcase). jldoctest-able. |
| `hero` | hero.jl:25 | `# Examples` of `hero("woven-hero.png")` returning `(; placements, png)` (not doctestable — renders PNG). |
| `save_png` | render.jl:5 | Malformed: signature doesn't reflect the `save_png(path; ...) do ax ... end` do-block form every caller uses; add that example. |

### housestyle

| Symbol | Location | Fix |
|---|---|---|
| `HouseStyle` (module) | HouseStyle.jl:2 | **Missing** module docstring: no-exports/qualified-access contract, public surface, link README. |
| `footer` | HouseStyle.jl:53 | Malformed single-line; promote + `jldoctest`: `footer("Woven") => "TextMeasure.jl · Woven"` (pins the middot). |
| `digest_rows` | HouseStyle.jl:56 | Add `jldoctest` (order-independence + 64-char hex), mirroring the test suite. |
| `plexmono` | HouseStyle.jl:33 | Malformed single-line; promote to signature-line block + example. |
| `fraunces`/`hanken` | HouseStyle.jl:22,36 | Add non-doctest `# Examples` showing the `<size>pt-<weight>` and Black→Bold forms. |
| `PAPER`/`INK`/`BRASS`/`RAMP` | HouseStyle.jl:7 | Docstrings on at least `RAMP`; lower priority once the module docstring links the README. |

`footer` and `digest_rows` are deterministic and already exercised by the test suite ⇒ **jldoctest-able.**

## Readability & simplicity

### src core API

- **layout.jl:34-56** — The line-breaking loop duplicates the `push!(committed, seg);
  committed_w = seg.width; pending = nothing` triplet across the isempty (line 41) and overflow
  (line 46) arms. Extract a `start_line!(committed, seg)` helper; behavior-identical.
- **layout.jl:32** — Add a one-line comment naming the `pending` invariant: "a space held back; it
  only joins the line if the following word also fits."
- **layout.jl:59** — Note that `raw` is non-empty by construction (the final `_emit_line!` always
  pushes one tuple) so the unguarded `maximum` reads as obviously safe.
- **prepare.jl:7-14/33** — `_flush!` returns the `:none` sentinel and line 33 reassigns `bufclass`
  only to be overwritten unconditionally on line 35. Have `_flush!` return `nothing` and reset at the
  call site, or at minimum drop the dead `bufclass =` on line 33.

### Backends + bounds

- **monospace.jl:21** — The 0.8/0.2 ascent/descent literals are unexplained while the sibling ratios
  (`advance_ratio`, `lineheight_ratio`) are named/configurable. Either promote to
  `ascent_ratio=0.8, descent_ratio=0.2` kwargs (most consistent) or comment "nominal 80/20 split;
  models no real font."
- **monospace.jl:14-15** — The `Float64(...)` wrappers are redundant with the `::Float64` fields;
  drop them or add a one-word comment if the intent is to accept `Int`/rational without surprise.

### Extensions

- **FreeTypeExt.jl:15-32 vs MakieExt.jl:14-31** — `measure`/`font_metrics` are near-byte-identical
  (CLAUDE.md flags "keep in sync" — a manual-sync hazard with no compiler help). Extract shared
  `TextMeasure._measure_advances(face, text, px)` and `_face_metrics(face, px)` into `src/`; the only
  real per-backend difference is the pixel-size scalar. **Best simplicity follow-up in the package.**
- **MakieExt.jl:17 vs :122** — Plain `measure` calls `FTA.get_extent(b.face, c)` directly while the
  RichText path resolves via `Makie.find_font_for_char`. A glyph needing fallback is measured
  inconsistently between the two paths. Either route plain `measure` through `find_font_for_char` too,
  or add a comment explaining the deliberate asymmetry.

### examples/layouts

- **shape_pack.jl:209-232** — The band-scanning loop overloads `intervals` (selection criterion +
  fill list) and interleaves the `:widest`/`:all` choice with vertical-termination bookkeeping.
  Extract `_band_intervals(chord_fn, band, la, mcw, fill)` returning one band's fill list.
- **knuth_plass.jl:179** — Rename `bestAfter` → `best_after` (lone camelCase carry-over from the
  pretext.js port; the rest of the package is snake_case).
- **knuth_plass.jl:89** — Reword the "moot for the DP" comment: the forced trailing gap actually feeds
  `_assemble`'s `is_last` and the inner `forced[a] && break`, so "moot" could mislead a maintainer
  into deleting the line.
- **test_shape_pack.jl:174** — Delete the dead `xs = getfield.(pk.placements, :x)` binding.

### examples/atlas

- **place.jl:1-5** — Replace the migration/history lead comment and the stale "used by the loop task,
  NOT here" `Makie.project` snippet with a "place.jl — measure label boxes + place them per frame"
  header. The px-projection snippet belongs to render.jl.
- **Atlas.jl:8** — Replace "includes added task-by-task:" scaffolding with the actual include-order
  contract (data → pois → camera → lod → place → render → loop → golden).
- **loop.jl:74 vs :209** — The per-label warm-start delta computation is duplicated almost verbatim;
  extract `_offset_deltas(prev, fp)` / `_carry_offsets(fp)`.
- **place.jl:62 (`recompute_overlaps`)** — Appears unused on the render/loop/golden path; grep tests —
  if test-only mark it so in the docstring, if dead remove ~14 lines.

### examples/tide

- **frame.jl:23-131 (`prepare_tide`)** — ~110 lines doing five jobs. Extract the two fixed-point
  solvers into `_solve_deep_y(...)` (92-108) and `_grow_height_for_all_dirs(...)` (110-126) so the
  body reads as a short sequence of named setup steps — the "measure once" story the file teaches.
- **frame.jl:215-334** — `_tideline`/`_diag_edge`/`TIDE_*` are RENDER-only but live in the LAYOUT
  file. Move them to render.jl to restore the layout/render split the README promises.
- **mask.jl:81-116 + frame.jl:321-334** — The diagonal-cut math is copied three times. Factor a shared
  `_diag_cut(dir, yy, b, ...)`; golden guards equivalence. Highest-value de-dup in the piece.
- **loop.jl:155-170 + render.jl:59-80** — `_draw_lit_only!`/`draw_body!` duplicate the em-dash split
  (documented as a hand-synced copy). Factor `_lit_split(s)` into render.jl.

### examples/woven

- **layout.jl:108-110** — `body_top_baseline(b) = b` is an identity pass-through never specialized;
  inline `ln.baseline` at layout.jl:100 and delete the helper.
- **hero.jl:21-23** — `_chrome_w` re-spells the `MakieBackend(; ..., px_per_unit=1)` constructor that
  `_make_hero_backend` already builds. Reuse the factory so `px_per_unit=1` lives in one place.
- **hero.jl:67** — Name the bare `1.8` masthead-gap constant (`MASTHEAD_GAP_SPACES`) or comment it.

### housestyle

- **examples/README.md:81 vs spine README §1** — README lists Newsreader as a pinned family but the
  spine README names only Fraunces/Plex Mono/Libre Caslon/Hanken. Reconcile so the pinned-fonts list
  and the documented spine agree (same "if a value disagrees, that is a bug" discipline).
- **_housestyle/README.md:7** — Point readers at `test/runtests.jl` as the executable guard for the
  "if a value disagrees, that is a bug" invariant.
- **_housestyle/README.md:14-21** — Note that the `../_housestyle` `[sources]` path assumes the piece
  lives at `examples/<piece>/`; this is the most copy-pasted block and the relative path is the easy
  thing to get wrong.

## Teaching the reader

The examples teach the *concepts* very well — the layouts and tide READMEs in particular convey
"measure once, then place/justify many" with runnable README snippets, the box/glue model, and
inline invariants (`opt.total_badness <= gdy.total_badness`). What they do **not** do is let a reader
execute the thesis from the docstrings alone: every "engine showcase" function (`measure_boxes`,
`placement_table`, `prepare_tide`/`frame_layout`, `shape_pack`/`knuth_plass`) is described in prose
but never shown being called, so `?function` is prose-only and the README is the sole place a call
appears. The four changes that would most improve newcomer reuse:

1. **A minimal end-to-end jldoctest on `MonospaceBackend`** (src/monospace.jl) — the zero-`using`,
   deterministic backend — driving `prepare` → `layout`. This is the canonical "this is how the
   library works" snippet and the seed every other doctest can reference.
2. **A "measure once, layout many" jldoctest on `layout`** (src/layout.jl) — one `prepare`, two
   `layout` calls at different `max_width` — making the library's central thesis copy-pasteable and
   CI-verified.
3. **`# Examples` on each example's one showcase function**, reusing the deterministic
   `golden_backend`/MonospaceBackend values the test suites already pin (woven `placement_table`,
   tide `prepare_tide`+`frame_layout`, layouts `shape_pack`+`knuth_plass`, atlas `measure_boxes`).
   This converts the four pieces from "prose that describes usage" to "docs that demonstrate usage."
4. **Module docstrings as REPL on-ramps** for `TextMeasureLayouts`, `Woven`, and `HouseStyle`, plus a
   one-sentence bridge in the tide README explaining that `shape_pack` is the region-aware line-breaker
   that replaces `layout` for masked regions (a reader arriving from the core docs meets `shape_pack`
   with no introduction today).

## Suggested sequencing

1. **`src/` doctest seed (do first).** Add the three headline jldoctests (`MonospaceBackend`,
   `prepare`, `layout`) plus the `subprep`/`line_top` fixes and the `#E` cleanup. These are
   self-verifying under `Pkg.test()`/`jldoctest` and unblock cross-referencing from everywhere else.
2. **`src/` type + bounds docstrings.** Signature lines and per-field docs on `FontMetrics`/`Segment`/
   `Prepared`/`Line`/`Layout`; lift the worked `bounds` numbers from `test/test_bounds.jl`.
3. **Extension entry-point docstrings.** The four user-facing constructors + `measure_bounds`, each
   with its load-bearing caveat and a non-doctest example.
4. **Per-example showcase examples + module docstrings.** layouts → atlas → tide → woven →
   housestyle, reusing already-pinned deterministic values. Remove the in-jokes (`#E`, "Tachikoma
   asteroid") and fix the `prepare_tide`/`save_png`/`region_mask` signature lines as you touch them.
5. **Doc/export reconciliation.** `FigletBackend` ↔ CLAUDE.md Backends; Newsreader ↔ spine README;
   README pointers to the test suites as executable guards.
6. **Readability refactors last (behavior-preserving).** Shared extension metric helper; tide
   `prepare_tide` solver extraction + diagonal-cut de-dup + render/layout file split; layouts
   band-interval extraction + `best_after` rename; atlas/woven scaffolding cleanup and dead-helper
   removal. These don't block the release docs and the goldens guard equivalence.
