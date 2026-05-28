# Demos milestone — Agent-Team orchestration design

**Date:** 2026-05-28
**Milestone:** Demos — TextMeasure in action (13 issues #A–#K) — see
[`docs/superpowers/issues/demos-milestone/`](../issues/demos-milestone/) and the converged design doc
[`2026-05-28-demos-milestone-design.md`](./2026-05-28-demos-milestone-design.md).
**Base:** `main` (clean working tree). All implementer worktrees branch off `main`; later waves
re-branch off `main` after earlier waves merge.
**Status:** design approved; rollout = **full milestone, all waves**, with human checkpoints at
each plan gate and each wave-boundary merge.

## Purpose

Parallelize the Demos milestone across a **persistent Agent Team** — one implementer member per
issue (or per file-cluster) — with a paired author/reviewer review loop per PR. This is the
orchestrator's + operator's design record. The orchestrator distributes the runbook + per-issue
kit to each member **in its spawn prompt** (members branch off `main`, which does not carry this
doc).

This adapts the Himalaya.jl "Print finish, round 3" orchestration spec
([source](https://github.com/jowch/Himalaya.jl/blob/main/docs/superpowers/specs/2026-05-28-print-r3-agent-team-orchestration.md))
to TextMeasure's reality. **The single biggest difference: acceptance here is overwhelmingly
deterministic.** Himalaya's dominant complexity was a live-visual harness (dev backend + per-branch
Vite + Playwright screenshots) because React visual Done-whens can't pass on a green build, forcing
the orchestrator to own a human-judgment sign-off on every visual PR. TextMeasure inverts that:

- #D (geometry: silhouette generation / rasterization) and the **deterministic core of #E**
  (headless 60-tick `CellBuffer` checksum + glyph-preservation assertion) verify with no eyeball.
- CairoMakie demos (#F3, #G, #H, #K) verify at the **computed `PackedLayout` level** (bbox
  non-overlap — note "no overlap" is *geometric*, hence deterministic, not visual — and baseline
  ±0.5px) plus a **`pdftotext` font-embedding check** for text selectability — no eyeball.
- The genuine eyeball residue is small but real: #E's *interactive* Done-whens (≥30fps wall-clock,
  respawn-flash/invulnerability), subjective "renders legible," and "README hero loads in GitHub
  view." A coding agent can `Read` a CairoMakie PNG or a captured TUI frame as a best-effort
  *sanity glance*, but the **authoritative** sign-off on these is the human at the wave-boundary
  merge gate.

## Why no per-issue brainstorming

`brainstorming`'s HARD-GATE requires a human-approved, spec-grade design before any implementation
skill fires. That deliverable **already exists upstream**: issue bodies #A–#K were authored from the
converged demos-milestone design doc (8 commits of brainstorming + 4-round reviewer convergence +
deep-verification pass), and each issue body carries Context + Scope + Done-when + `file:line`. We
bypass the per-issue brainstorming *dialogue*, **not** the *gate* — the approved design artifact is
the milestone design doc + the issue bodies. The **#A+#B collapse** (shared `src/backend_containers.jl`)
is the one decomposition call brainstorming would normally own; it is made explicitly here.

## Roles

- **Orchestrator** = root session. Owns the shared task list (= the DAG via `blockedBy` edges).
  Runs the plan gate. Bridges teammate↔human approval. Holds the orchestrator-side **Monitor +
  `SendMessage` nudge** (load-bearing — see inherited experiment). Does the per-PR **agent-visual
  check** (`Read` the rendered PNG / captured TUI frame). Owns **merge-to-`main` after human
  approval** and `SendUserFile`s rendered artifacts to the human at each wave boundary. Tracks
  member liveness and shuts down completed members.
- **Implementer members** (`impl-AB`, `impl-C`, `impl-E`, …) — `general-purpose` agent type (need
  Edit/Write/Bash). One per issue or per file-cluster. **Distinct names, never reused.**
- **Reviewer members** (`rev-<PR#>`) — drive `review-pr`; invoke the **`textmeasure-reviewer`**
  subagent as their analysis engine. **Named per-PR, not reused across waves** (same name-routing
  reason).

### Wave 0 prerequisite — `textmeasure-reviewer` subagent

Before wave 1, author `.claude/agents/textmeasure-reviewer.md`. It is the analysis engine inside
`review-pr` and is also run by the orchestrator at the plan gate. It must encode the library's
invariants so reviews are higher-fidelity than a generic diff read:

- `measure(backend, text)::Float64` = advance width of ONE run, summing glyph advances with **NO
  kerning** (this is what makes results match Makie exactly); no line breaks.
- `font_metrics(backend)::FontMetrics` = `ascent` / `descent` (positive, below baseline) /
  `line_advance` in px.
- The `prepare` (font-touching, once) / `layout` (pure arithmetic, many times) split.
- The weakdep-extension contract (subtype `AbstractMeasurementBackend`, methods defined as
  `TextMeasure.measure` / `TextMeasure.font_metrics` in `ext/`, gated on a `Project.toml` weakdep).
- The Makie-0.24.x pinned RichText constants (0.66 sup scale, +0.40 sup offset, −0.25 sub offset,
  20px lineheight) guarded by `test/test_richtext.jl`.
- Result structs are read-only by convention; `Line.str`/`width` are whitespace-trimmed; block-top
  = 0, y increases downward.

## The dependency DAG (waves)

The 13 issues are **not** independent lanes only at the library layer — nearly every demo owns its
own `examples/<demo>/` directory with an isolated `Project.toml`, so demo-vs-demo file conflict is
structurally impossible. The only shared-library contention is **#A↔#B**: both add an export to
`src/TextMeasure.jl` and an entry to `CHANGELOG.md`. (#A also edits `src/types.jl`; #B alone adds
`src/backend_containers.jl`, `ext/TextMeasureFigletExt.jl`, and the FIGlet `Project.toml` weakdep —
those don't overlap.) Each wave is internally **file-disjoint**; later waves branch fresh off `main`
after earlier waves merge, so cross-wave overlaps resolve by rebase rather than by hand.

| Wave | Members → issues | Files | Ordering rationale |
|---|---|---|---|
| **0** | author `textmeasure-reviewer`; document the pinned font set | `.claude/agents/textmeasure-reviewer.md`; font-set convention (`DejaVu Sans`, `Liberation Serif`) | Review engine must exist before any plan gate or PR review; the font set must be fixed before wave-2 demos generate exported-PDF-text goldens (see Acceptance harness). |
| **1** | `impl-AB` → #A + #B (**one PR**) · `impl-C` → #C · `impl-D` → #D | AB: #A → `src/types.jl`, `src/TextMeasure.jl` (export `subprep`), `CHANGELOG.md`; #B → `src/backend_containers.jl`, `ext/TextMeasureFigletExt.jl` (new), `Project.toml` (FIGlet weakdep), `src/TextMeasure.jl` (export). **Overlap: `src/TextMeasure.jl` export list + `CHANGELOG.md`.** · C: `examples/layouts/` · D: `examples/silhouettes/` | #A and #B both edit `src/TextMeasure.jl`'s export list and `CHANGELOG.md` → **collapsed into one member, one branch, sequential commits, one PR** (the explicit one-responsibility exception). C ⊥ D ⊥ AB (isolated `examples/` dirs). |
| **2** | `impl-E` → #E · `impl-F` → #F1→#F2→#F3 (**serial chain, one lane**) · `impl-G` → #G · `impl-H` → #H | E: `examples/asteroid_tui/` · F: `examples/doi_infograph/` · G: `examples/map_feature/` · H: `examples/cover/` | All four own disjoint `examples/` dirs. E dep A,B,C,D; F dep C (F1→F2→F3 internal); G dep C; H dep C — all wave-1 deps merged first. **4 natural lanes, run ~3-wide adaptively.** |
| **3** | `impl-I` → #I · `impl-J` → #J | I: `README.md`, `CHANGELOG.md`, `examples/README.md` · J: `.github/workflows/demo-health.yml`, `test/` golden/property/license | Both dep all four demos (#E, #F3, #G, #H). I ⊥ J. **J runs strictly last** so its CI grep-guard can't false-fail in-flight branches. |
| **stretch** | `impl-K` → #K | `examples/layouts/knuth_plass.jl`, `examples/justification/` | **Deps #C** (reuses the `examples/layouts/` dir; not independent). Optional consumer of #F2/#H via kwarg. **Lives entirely in `examples/`** — justification is out of the library per `CLAUDE.md`, so **no `src/` touch**. Since #C merges in wave 1, K branches off `main` with `examples/layouts/` already present and adds `knuth_plass.jl`; as the sole wave-2 lane touching `examples/layouts/` it can interleave, else defer. |

**Fan-out width.** Start wider than Himalaya's fixed 2 (our acceptance is lighter — fewer review
rounds, deterministic per-PR gate). Target **~3 implementer lanes active per wave**; the F1→F2→F3
chain counts as a single lane. **Adaptive: throttle to 2 if the orchestrator's per-round nudge
juggling thrashes** (the orchestrator is the serialization point for review-round nudges, so width
is bounded by bridge bandwidth, not file-disjointness alone).

## Per-implementer runbook (plan-then-build)

Distributed to each member in its spawn prompt. The member owns steps 1–2 and 4–6; the orchestrator
owns step 3 (the gate).

1. **Workspace** — `using-git-worktrees` (via the `EnterWorktree` native tool) to create the
   worktree + branch `demos-<letter>-<slug>` off current `main`; then `Pkg.instantiate` the relevant
   project inside it — the repo root for library issues (#A/#B), or `examples/<demo>/Project.toml`
   for demo issues (#C/#D/#E/#F*/#G/#H/#K).
2. **Plan** — `writing-plans`: issue body → implementation plan + bite-sized TDD task list,
   committed to the branch.
3. **Plan gate** — orchestrator runs `verify-before-review` (an explicit pass that **greps the
   plan's cited symbols / paths / line-numbers against `main`** — not a skim) + `textmeasure-reviewer`
   on the plan, then surfaces it to the **human** for approval. Member idles until the orchestrator
   sends "approved" (a discrete `SendMessage`, not an in-context pause — see inherited experiment).
4. **Implement** — execute the plan via `executing-plans` (outer loop: walk the task list,
   stop-when-blocked, review checkpoints) with `test-driven-development` as the inner loop per task
   (red → green → refactor, each step its own commit). The acceptance-test shapes are already
   deterministic:
   - **Geometry** (#D): `GeometryOps` assertions — `voronoi_shatter` area tolerance (<1e-6) +
     pairwise zero-measure intersection, `rasterize` BitMatrix for known polygon/cell-size inputs.
     Deterministic, no render.
   - **TUI** (#E): the *deterministic* core is a `CellBuffer` (Matrix{Char} + ANSI metadata)
     **golden checksum** over a scripted 60-tick headless loop, plus the glyph-preservation
     assertion (every glyph of the fractured prose appears exactly once, in order). The
     *interactive* Done-whens — ≥30fps wall-clock, respawn-flash/invulnerability, debug-overlay
     highlight — are **not** checksum-able and fall to the tier-2/3 checks below; do not claim them
     on a green build.
   - **CairoMakie** (#F3, #G, #H, #K): assert **`PackedLayout` invariants** (bbox non-overlap,
     baseline ±0.5px, wrap honors inset) at the computed-layout level, plus a **`pdftotext`
     font-embedding check** for text selectability — embedding/selectability **only**, NOT
     coordinate verification (CairoMakie PDF coords don't round-trip at sub-pixel precision, so
     layout correctness stays at the `PackedLayout` level, per #H's issue body).
   - **Backends** (#A, #B): `measure()` determinism + extension-registration checks.
   - Use **regression floors/ceilings, not hard counts**, for fixture-based assertions.
   - `executing-plans` would normally hand off to `finishing-a-development-branch` at task-list
     completion; here that terminal handoff is **replaced by step 6's `request-pr-review`** — do
     **not** invoke `finishing-a-development-branch`.
5. **Verify** — `verification-before-completion`. The Julia suite is slow to spin up: run it
   **once, capture to `test-logs/<session>.log`, and grep** (keyed by `$CLAUDE_CODE_SESSION_ID`);
   never re-run per grep. Render the artifact for visual issues. `verification-before-completion`
   certifies only the build/test half — for a visual issue it is necessary but not sufficient (the
   agent-visual + human-visual checks in the harness below complete the gate).
6. **PR + review loop** — open PR → `request-pr-review` (author half; the GitHub review thread is a
   first-class audit-trail deliverable, kept even when the review is trivial) → `rev-<PR#>` drives
   `review-pr` with `textmeasure-reviewer` as the engine → converge through the PR → orchestrator
   runs the agent-visual check → surfaces to the human for merge approval.

## Acceptance harness (Julia, no browser)

Three tiers; most issues stop at tier 1.

1. **Deterministic** (owned by the member's test suite): green capture-to-log demo/library tests;
   `GeometryOps` assertions (#D); `CellBuffer` golden checksum + glyph-preservation (#E core);
   `PackedLayout` invariants incl. **bbox non-overlap** (overlap is geometric, so it lives here, not
   in a visual tier — e.g. #G's "text flows around the silhouette without overlapping" is *guaranteed
   by construction* by placing body text only in `complement_chord_fn`'s negative-space intervals,
   asserted as a tier-1 invariant; whether the spread *looks* like a magazine page is tier-3);
   `pdftotext` font-embedding check. No image-diff library is needed — TextMeasure
   works at the measurement/layout layer, not the pixel layer.
2. **Agent-visual sanity glance** (owned by the orchestrator per-PR, **non-authoritative**): the
   orchestrator `Read`s the rendered CairoMakie PNG or the captured TUI frame to catch gross
   breakage (blank page, garbled glyphs, obvious clipping). This is a smoke check, **not** the gate
   — an agent cannot reliably adjudicate subjective legibility or dynamic GitHub rendering. A member
   may **not** mark a visual issue done on a green build alone.
3. **Human-visual** (**authoritative** for the eyeball residue, at the wave-boundary merge gate): the
   orchestrator `SendUserFile`s the rendered PNGs/PDF (and, for #E, a captured frame + the fps
   number) to the human, who judges legibility / "hero loads in GitHub" / #E's interactive feel and
   **approves the merge**. The human approves every merge to `main`.

**Golden-snapshot ownership (no wave-2↔wave-3 chicken-and-egg):** each demo **commits its own
golden** (e.g. #E's `CellBuffer` checksum, #F3/#G/#H's exported-PDF text checksum) together with the
test that produces it, **inside its own wave-2 PR**. #J (wave 3) does **not** author goldens — it
*wraps* the already-committed goldens in the weekly `demo_health.yml` workflow and adds the property
tests, license gate, and CI matrix. So no demo's wave-2 acceptance depends on #J; #J only depends on
the demos having committed their goldens (which its issue body states: "golden snapshots come from
each").

**Font-set prerequisite (the one ordering subtlety):** reproducible exported-PDF-text goldens
(#F3/#G/#H) require the *same* font set at golden-generation time and at CI-replay time — a different
font changes measured widths, hence wrap points, hence the extracted text order. So the pinned font
set (`DejaVu Sans`, `Liberation Serif` — #J's font-pinning list) is a **shared prerequisite,
documented and installed before wave-2 demos generate their goldens**, not a wave-3 invention. #J's
font-pinning step *enforces* this set in CI; demo authors render their goldens against the identical
set. Establish the font list as a Wave-0 convention alongside `textmeasure-reviewer`.

## Inherited mechanics & gotchas

These team-tool mechanics are **inherited from the operator's active Himalaya arc in this same
environment** — they are in-use, not speculative; we adopt the resolved conclusions rather than
re-running the experiments.

- **Persistent members do NOT self-resume on their own armed Monitors across idle** (Himalaya's
  wave-1 Monitor experiment, **REFUTED**: idle teammates wake on `SendMessage` / task-claims, not on
  their own Monitor stdout). We inherit the conclusion — **the orchestrator-Monitor + `SendMessage`
  nudge is load-bearing for every PR from the start.** Do not design around teammate self-resume.
- **Review-loop coordination**: per the Roles section, per-PR reviewer members (`rev-<PR#>`) drive
  `review-pr` and implementer members run the `request-pr-review` author half. Himalaya's refuted
  note tentatively flagged these *may* be root-session-only; if a spawned member proves unable to
  drive them, the **orchestrator runs the loop directly** — either way the GitHub review thread (the
  audit-trail deliverable) is unchanged. Confirm which holds on the first wave-1 PR.
- **Team-member worktree pinning**: spawned members' `Write`/`Edit` tools may pin to a single
  worktree, not each member's own. **Try the `EnterWorktree` native tool first**; if edits still
  land in the wrong tree, fall back to authoring edits via **Bash heredoc with absolute paths** in
  the correct worktree (`Bash` is not pinned). Consequences: (1) do **not** garbage-collect a pinned
  worktree mid-wave — live members depend on it; (2) TDD edits are more fragile under the fallback,
  so members must be careful. This is the **one genuinely repo-specific unknown** (Julia file edits
  under the team-tools harness) — validate it on the first wave-1 member before leaning on it.
- **Distinct member names, never reused** (implementers AND per-PR reviewers); use the `@team` form
  if a bare name risks routing to a dead `agentId`.
- **Re-instantiate `main` after each wave merges** — `Pkg.instantiate` + a capture-to-log `Pkg.test`
  on the `main` checkout before opening the next wave (the Julia analog of Himalaya's stale-`node_modules`
  trap). Next wave branches off this updated `main`.

## Orchestrator control loop & wave-boundary procedure

Because members don't self-resume, the orchestrator runs an explicit relay loop rather than waiting
on teammate Monitors:

- **Completion signal (how the orchestrator learns a PR/round is ready):** each member, *before going
  idle*, sends the orchestrator a `SendMessage` ("plan committed", "PR #N opened", "review round N
  pushed"). The orchestrator also **arms a Monitor on `gh pr` / `gh pr checks` state** as a backstop
  (CI completion, reviewer posts). It does not poll teammates for liveness.
- **Nudge mechanism + cadence:** nudge on *event*, not on a timer. When `rev-<PR#>` posts a round,
  the orchestrator `SendMessage`s the author to address it; when the author pushes a fix, it
  `SendMessage`s the reviewer to re-review. The orchestrator is the relay; the two halves converge
  through the PR, never talking directly.
- **Thrash metric (the adaptive-width trigger):** if more than ~3 review rounds are outstanding
  across active lanes at once, or the orchestrator can't service all pending nudges within one of its
  turns, **throttle the next wave to 2 lanes**.
- **`review-pr` fallback:** if a spawned `rev-<PR#>` cannot drive `review-pr` (Himalaya's tentative
  root-session-only caveat), the **orchestrator runs `review-pr` itself in the root session** against
  the PR (it holds the skill + `textmeasure-reviewer`). Decide on the first wave-1 PR; the audit-trail
  thread is identical either way.
- **Wave-boundary procedure** (after a wave's PRs are human-approved + merged): orchestrator (1)
  pulls `main`; (2) `Pkg.instantiate`; (3) capture-to-log `Pkg.test`; (4) if red, **halt and surface
  to the human**; (5) if green, spawn the next wave's members, branching off this `main`. Later-wave
  branches **rebase** onto the new `main` rather than hand-merge; a member hitting a rebase conflict
  rebases its own branch and re-runs its suite.
- **Member shutdown:** once a member's PR merges, the orchestrator sends it a shutdown `SendMessage`
  and stops tracking it. Its worktree is **not** GC'd mid-wave (others may depend on the pinned tree)
  — clean up at the wave boundary.
- **#K decision gate:** at the wave-1→wave-2 boundary the orchestrator surfaces the interleave-vs-defer
  call to the human (interleave is safe — #C is merged, K only adds `examples/layouts/knuth_plass.jl`);
  the human replies; the orchestrator sets the task blockers accordingly.
- **Offline acceptance:** demos with network/API deps (#F1 CrossRef/Lens/Claude; #G `CensusACS.jl`)
  are accepted on their **offline/bundled path** (#F1 hardcoded fallback DOIs; #G bundled Vermont
  shapefile) so acceptance is reproducible in the orchestrator's environment.

## Risk → mitigation

| Risk | Mitigation |
|---|---|
| Teammate Monitor doesn't self-resume | Inherited REFUTED result: orchestrator-Monitor + `SendMessage` nudge load-bearing for all PRs from the start. |
| Bare-name `SendMessage` routes to a dead `agentId` | Distinct member names, never reused (implementers AND per-PR reviewers); `@team` form if needed. |
| #A↔#B shared `src/TextMeasure.jl` export list + `CHANGELOG.md` | Collapsed into one member (`impl-AB`) / one branch / one PR — the explicit one-responsibility exception. |
| Team-member `Write`/`Edit` worktree pinning | `EnterWorktree` native tool first; Bash-heredoc absolute-path fallback; don't GC a pinned worktree mid-wave; **validate on the first wave-1 member** (the one repo-specific unknown). |
| Cross-wave file overlap (lib issues vs later demos) | Wave ordering + branch-off-`main`-after-merge → rebase, not hand-merge. |
| Stale `main` env after worktree instantiates | Pinned gate: after each wave merges, re-run `Pkg.instantiate` + capture-to-log `Pkg.test` on the `main` checkout before opening the next wave. |
| Slow Julia suite thrash across ~7 PRs | Capture-once to `test-logs/<session>.log` + grep; never re-run per grep; reviewers expect a multi-minute suite per review round. |
| Visual Done-whens unverifiable by build/test | Mostly deterministic (geometry assertions / cell-buffer checksum / `PackedLayout` bbox-overlap + baseline / `pdftotext` embedding); residual = #E interactive + subjective legibility + "hero loads in GitHub" → agent sanity glance per-PR + **authoritative human eyeball at the wave-boundary merge gate**. |
| Agent-visual tier over-trusted | Tier-2 agent `Read` is a non-authoritative smoke check only; subjective/dynamic judgments are human (tier-3). |
| Demo goldens vs #J ordering (chicken-and-egg) | Each demo commits its own golden + test **in its wave-2 PR**; #J (wave 3) only wraps them in the weekly workflow + adds property/license/matrix gates. No wave-2 acceptance depends on #J. |
| #J's CI grep-guard false-failing in-flight branches | #J scheduled strictly last (wave 3, after all demos merge). |
| #K (stretch) deps #C + shares `examples/layouts/` dir | #C merges in wave 1; K branches off `main` with the dir present and adds `knuth_plass.jl`; sole `examples/layouts/` toucher in its wave. Lives entirely in `examples/` — no `src/` touch. |
| Zombie/uncleaned idle teammates accumulating | Orchestrator tracks member liveness; shut down completed members once their PR merges. |

## Open / operator calls (defaults chosen; flip at will)

- **#A+#B**: collapsed into one PR (conflict-safety) vs. serialized as two per-issue PRs
  (A→merge→B, preserves per-issue audit granularity). **Default: collapse.**
- **#K stretch**: interleave into wave 2 vs. defer until #A–#D land. **Default: defer; decide at the
  wave-1→wave-2 boundary.**
- **Fan-out width**: target ~3 lanes/wave, adaptive down to 2 on orchestrator nudge thrash.
