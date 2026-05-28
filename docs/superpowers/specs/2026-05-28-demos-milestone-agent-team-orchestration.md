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

- TUI demos (#D, #E) verify via **cell-buffer golden snapshots / checksums** — no eyeball.
- CairoMakie demos (#F3, #G, #H, #K) verify at the **computed `PackedLayout` level** (bbox
  non-overlap, baseline ±0.5px) plus **`pdftotext` round-trip** for text selectability — no eyeball.
- The genuinely eyeball-only residue ("renders legible / no overlaps", README hero loads, TUI
  looks right) is small, and a coding agent can `Read` a CairoMakie PNG or a captured TUI frame —
  so even that sign-off is an agent step per-PR, with the human as the authoritative check at the
  wave-boundary merge gate.

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
structurally impossible. The only shared-library contention is **#A↔#B** (both edit
`src/backend_containers.jl`, `src/TextMeasure.jl` exports, and `Project.toml`). Each wave is
internally **file-disjoint**; later waves branch fresh off `main` after earlier waves merge, so
cross-wave overlaps resolve by rebase rather than by hand.

| Wave | Members → issues | Files | Ordering rationale |
|---|---|---|---|
| **0** | author `textmeasure-reviewer` | `.claude/agents/textmeasure-reviewer.md` | Review engine must exist before any plan gate or PR review. |
| **1** | `impl-AB` → #A + #B (**one PR**) · `impl-C` → #C · `impl-D` → #D | AB: `src/backend_containers.jl`, `src/TextMeasure.jl`, `Project.toml`, `ext/TextMeasureFigletExt.jl` (new) · C: `examples/layouts/` · D: `examples/silhouettes/` | #A and #B share `src/backend_containers.jl` → **collapsed into one member, one branch, sequential commits, one PR** (the explicit one-responsibility exception). C ⊥ D ⊥ AB (isolated `examples/` dirs). |
| **2** | `impl-E` → #E · `impl-F` → #F1→#F2→#F3 (**serial chain, one lane**) · `impl-G` → #G · `impl-H` → #H | E: `examples/asteroid_tui/` · F: `examples/doi_infograph/` · G: `examples/map_feature/` · H: `examples/cover/` | All four own disjoint `examples/` dirs. E dep A,B,D; F dep C; G dep C; H dep C — all wave-1 deps merged first. **4 natural lanes, run ~3-wide adaptively.** |
| **3** | `impl-I` → #I · `impl-J` → #J | I: `README.md`, `CHANGELOG.md`, `examples/README.md` · J: `.github/workflows/demo-health.yml`, `test/` golden/property/license | Both dep all four demos (#E, #F3, #G, #H). I ⊥ J. **J runs strictly last** so its CI grep-guard can't false-fail in-flight branches. |
| **stretch** | `impl-K` → #K | `src/knuth_plass.jl`, `src/TextMeasure.jl` (export), `examples/knuth_plass_comparison/` | Independent; optional consumer of #F2/#H via kwarg. Interleave into wave 2 if appetite, else defer. Touches `src/` → keep off `main` until a wave-boundary merge. |

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
   project inside it — the repo root for library issues (#A/#B/#K), or `examples/<demo>/Project.toml`
   for demo issues.
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
   - **TUI** (#D, #E): assert on a `CellBuffer` (Matrix{Char} + ANSI metadata) **golden checksum**
     over a scripted headless tick-loop — not on rendered pixels.
   - **CairoMakie** (#F3, #G, #H, #K): assert **`PackedLayout` invariants** (bbox non-overlap,
     baseline ±0.5px, wrap honors inset) at the computed-layout level, plus a **`pdftotext`
     round-trip** for text-selectability where required — not PDF coordinate extraction.
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
   `CellBuffer` golden checksum; `PackedLayout` invariants; `pdftotext` round-trip. No image-diff
   library is needed — TextMeasure works at the measurement/layout layer, not the pixel layer.
2. **Agent-visual** (residual legibility/overlap, owned by the orchestrator per-PR): the orchestrator
   `Read`s the rendered CairoMakie PNG or the captured TUI text frame and judges legibility/overlap.
   A member may **not** mark a visual issue done on a green build alone.
3. **Human-visual** (authoritative, at the wave-boundary merge gate): the orchestrator `SendUserFile`s
   the rendered PNGs/PDF to the human, who eyeballs aesthetics and **approves the merge**. The human
   approves every merge to `main`.

## Inherited mechanics & gotchas

- **Persistent members do NOT self-resume on their own armed Monitors across idle** (Himalaya's
  wave-1 Monitor experiment, **REFUTED**: idle teammates wake on `SendMessage` / task-claims, not on
  their own Monitor stdout). We inherit the conclusion — **the orchestrator-Monitor + `SendMessage`
  nudge is load-bearing for every PR from the start.** Do not design around teammate self-resume.
  Note `request-pr-review`/`review-pr` are effectively root-session-coordinated.
- **Team-member worktree pinning**: spawned members' `Write`/`Edit` tools may pin to a single
  worktree, not each member's own. **Try the `EnterWorktree` native tool first** (this env has it,
  unlike the Himalaya run); if edits still land in the wrong tree, fall back to authoring edits via
  **Bash heredoc with absolute paths** in the correct worktree (`Bash` is not pinned). Consequences:
  (1) do **not** garbage-collect a pinned worktree mid-wave — live members depend on it; (2) TDD
  edits are more fragile under the fallback, so members must be careful. Validate the mechanism on
  wave 1 before leaning on it for wave 2.
- **Distinct member names, never reused** (implementers AND per-PR reviewers); use the `@team` form
  if a bare name risks routing to a dead `agentId`.
- **Re-instantiate `main` after each wave merges** — `Pkg.instantiate` + a capture-to-log `Pkg.test`
  on the `main` checkout before opening the next wave (the Julia analog of Himalaya's stale-`node_modules`
  trap). Next wave branches off this updated `main`.

## Risk → mitigation

| Risk | Mitigation |
|---|---|
| Teammate Monitor doesn't self-resume | Inherited REFUTED result: orchestrator-Monitor + `SendMessage` nudge load-bearing for all PRs from the start. |
| Bare-name `SendMessage` routes to a dead `agentId` | Distinct member names, never reused (implementers AND per-PR reviewers); `@team` form if needed. |
| #A↔#B shared `src/backend_containers.jl` | Collapsed into one member (`impl-AB`) / one branch / one PR — the explicit one-responsibility exception. |
| Team-member `Write`/`Edit` worktree pinning | `EnterWorktree` native tool first; Bash-heredoc absolute-path fallback; don't GC a pinned worktree mid-wave; validate on wave 1. |
| Cross-wave file overlap (lib issues vs later demos) | Wave ordering + branch-off-`main`-after-merge → rebase, not hand-merge. |
| Stale `main` env after worktree instantiates | Pinned gate: after each wave merges, re-run `Pkg.instantiate` + capture-to-log `Pkg.test` on the `main` checkout before opening the next wave. |
| Slow Julia suite thrash across ~7 PRs | Capture-once to `test-logs/<session>.log` + grep; never re-run per grep; reviewers expect a multi-minute suite per review round. |
| Visual Done-whens unverifiable by build/test | Mostly deterministic (cell-buffer checksum / `PackedLayout` invariants / `pdftotext` round-trip); residual = orchestrator agent-`Read` of PNG/frame per-PR + human eyeball at the wave-boundary merge gate. |
| #J's CI grep-guard false-failing in-flight branches | #J scheduled strictly last (wave 3, after all demos merge). |
| #K (stretch) touches `src/` | Keep off `main` until a wave-boundary merge; interleave into wave 2 only if appetite, else defer. |
| Zombie/uncleaned idle teammates accumulating | Orchestrator tracks member liveness; shut down completed members once their PR merges. |

## Open / operator calls (defaults chosen; flip at will)

- **#A+#B**: collapsed into one PR (conflict-safety) vs. serialized as two per-issue PRs
  (A→merge→B, preserves per-issue audit granularity). **Default: collapse.**
- **#K stretch**: interleave into wave 2 vs. defer until #A–#D land. **Default: defer; decide at the
  wave-1→wave-2 boundary.**
- **Fan-out width**: target ~3 lanes/wave, adaptive down to 2 on orchestrator nudge thrash.
