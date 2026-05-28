# Demos Milestone — Orchestrator Runbook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive the 13-issue Demos milestone (#A–#K) to merged `main` via a persistent Agent Team — one implementer member per issue/cluster, a paired author/reviewer loop per PR, human approval at each plan gate and wave-boundary merge.

**Architecture:** This plan is the **orchestrator's** runbook, executed by the root session. It is NOT a per-issue code plan — each implementer member runs its *own* `writing-plans` against its issue body at runbook step 2. The orchestrator owns the shared task list (the DAG), the plan gate, the teammate↔human bridge, the per-PR agent-visual sanity glance, and merge-to-`main` after human approval. Two phases of work that the spec splits: cheap, repeatable orchestration over an expensive-once setup (Wave 0). Acceptance is overwhelmingly deterministic; the human is the authoritative visual check at the merge gate only.

**Tech Stack:** Claude Code Agent Teams (`TeamCreate`, `Agent` with `name`/`team_name`, `SendMessage`, `TaskCreate`/`TaskUpdate`, `Monitor`); superpowers skills (`writing-plans`, `executing-plans`, `test-driven-development`, `verification-before-completion`, `request-pr-review`/`review-pr`, `using-git-worktrees`); `gh` CLI; Julia `Pkg`.

**Source-of-truth bundle** (every member's kit, all on `main`): the issue body (`docs/superpowers/issues/demos-milestone/<X>.md`, the approved spec), the design doc (`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`), the orchestration spec (`docs/superpowers/specs/2026-05-28-demos-milestone-agent-team-orchestration.md`), and `CLAUDE.md`.

---

## File Structure

Concrete artifacts this plan creates (Wave 0) and the runtime state it manages:

- **Create** `.claude/agents/textmeasure-reviewer.md` — the review engine (one responsibility: review a TextMeasure PR/plan against the library's invariants). The `.claude/agents/` directory does not exist yet.
- **Already recorded** — the pinned font-set convention (`DejaVu Sans`, `Liberation Serif`) lives in the orchestration spec's Acceptance-harness section; no new file needed, but each demo's golden-generation and #J's CI must honor it.
- **Runtime (no repo file)** — the persistent team, the shared task list (DAG), per-member worktrees/branches (`demos-<letter>-<slug>`), and PRs. Managed via tools, not committed artifacts.

The orchestration spec (already on `main`) is the design reference; this plan is the executable procedure.

---

## Phase 0 — Wave-0 prerequisites (do once, before any member spawns)

### Task 0.1: Author the `textmeasure-reviewer` subagent

**Files:**
- Create: `.claude/agents/textmeasure-reviewer.md`

- [ ] **Step 1: Create the directory**

Run:
```bash
mkdir -p /home/jonathanchen/projects/TextMeasure.jl/.claude/agents
```

- [ ] **Step 2: Write the subagent definition (full content)**

Create `.claude/agents/textmeasure-reviewer.md` with exactly:

```markdown
---
name: textmeasure-reviewer
description: Reviews a TextMeasure.jl PR diff or implementation plan against the library's measurement/layout invariants. Use as the analysis engine inside review-pr, and at the orchestrator's plan gate.
tools: Glob, Grep, LS, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, KillShell, BashOutput
---

You review TextMeasure.jl changes — either a PR diff or a written implementation plan — for correctness against the library's invariants and conventions. You do NOT write code; you report findings.

## What TextMeasure is

A backend-agnostic text **layout engine**: `prepare` (the only font-touching phase, run once) tokenizes text into `:word`/`:space`/`:newline` `Segment`s and caches per-run widths + `FontMetrics`; `layout` is pure arithmetic over those cached widths (greedy line-breaking, words atomic, per-line whitespace trim). Out of scope per `CLAUDE.md`: rendering, UAX-#14 line-breaking, CJK, hyphenation, justification, rotation.

## Invariants you MUST check (flag any violation)

1. **`measure(backend, text)::Float64`** = advance width of ONE run, summing glyph advances with **NO kerning** — this is exactly what makes results match Makie. No line breaks inside a run. Any kerning, fallback, or multi-run logic in `measure` is a bug.
2. **`font_metrics(backend)::FontMetrics`** returns `ascent` / `descent` (positive, measured below the baseline) / `line_advance` in px.
3. **Phase split**: `prepare` may call the backend; `layout` must NOT — it operates only on already-cached widths. A backend call inside `layout` is a bug.
4. **Backend contract**: a new backend subtypes `AbstractMeasurementBackend` and defines its methods as `TextMeasure.measure` / `TextMeasure.font_metrics` (non-exported). A heavy dep goes in `[weakdeps]` + `[extensions]` in `Project.toml`, with the methods + keyword constructor in a new `ext/` module — mirroring `ext/TextMeasureFreeTypeExt.jl` and `ext/TextMeasureMakieExt.jl` field-for-field. Methods must be inert until the weakdep is loaded.
5. **Makie 0.24.x pinned constants** (in `ext/TextMeasureMakieExt.jl`, guarded by `test/test_richtext.jl`): sup fontsize scale `0.66`, sup baseline offset `+0.40`, sub baseline offset `−0.25`, line drop `_RT_LINE_DROP = 20.0`. A change to any of these without updating the guard test is a bug.
6. **Result structs are read-only by convention.** `Line.str`/`width` are whitespace-trimmed; `Line.baseline`/block geometry use block-top = 0, y increasing downward.

## Test/quality discipline you MUST enforce

- Tests assert on computed structures — `measure()` floats, `Prepared`/`Layout`/`PackedLayout` fields, `CellBuffer` (Matrix{Char}+ANSI) checksums, `GeometryOps` tolerances — **never on rendered pixels or on the contents of an exported PDF's coordinates**. Layout correctness is checked at the `PackedLayout` level; `pdftotext` is only a font-embedding/selectability check.
- Fixture-based assertions use **regression floors/ceilings, not brittle hard counts**.
- The Julia suite is slow: it must be run **once, captured to `test-logs/<session>.log`, and grepped** — flag any plan that re-runs the suite per-grep.
- Each `examples/<demo>/` has its own `Project.toml`/`Manifest.toml`; demo deps must NOT leak into TextMeasure's root `Project.toml`.

## How to report

Group findings by severity: **BLOCKER** (violates an invariant / will break a downstream consumer), **MAJOR** (correctness or contract risk), **MINOR** (convention/clarity). For each: cite `file:line`, state the invariant or convention at stake, and give a concrete fix. If reviewing a plan, additionally confirm every cited symbol/path/line actually exists on `main` (you may be told the orchestrator already grepped them — say so). Be concrete; do not pad with praise.
```

- [ ] **Step 3: Verify the file is well-formed**

Run:
```bash
head -6 /home/jonathanchen/projects/TextMeasure.jl/.claude/agents/textmeasure-reviewer.md
```
Expected: the YAML frontmatter (`---`, `name: textmeasure-reviewer`, `description:`, `tools:`, `---`).

- [ ] **Step 4: Commit**

```bash
cd /home/jonathanchen/projects/TextMeasure.jl
git add .claude/agents/textmeasure-reviewer.md
git commit -m "feat(agents): textmeasure-reviewer subagent for the demos-milestone review loop

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 0.2: Confirm the font-set convention is recorded

- [ ] **Step 1: Verify it is documented**

Run:
```bash
grep -n "DejaVu Sans" /home/jonathanchen/projects/TextMeasure.jl/docs/superpowers/specs/2026-05-28-demos-milestone-agent-team-orchestration.md
```
Expected: the Acceptance-harness "Font-set prerequisite" paragraph (and the Wave-0 table row). No new file is needed — the convention is captured in the spec. Each wave-2 demo's golden-generation and #J's CI must install/honor `DejaVu Sans` + `Liberation Serif`; this is carried into each member's spawn prompt (template below) for the CairoMakie demos (#F3/#G/#H).

### Task 0.3: Create the persistent team

- [ ] **Step 1: Create the team**

Call `TeamCreate` with team name `demos-milestone`. The orchestrator is the root session; members are spawned in later tasks.

- [ ] **Step 2: Verify**

Confirm the team exists (the tool returns the team handle; `TaskList`/team roster shows it empty of members). No commit (runtime state).

### Task 0.4: Seed the shared task list (the DAG)

- [ ] **Step 1: Create one task per issue with dependency edges**

Use `TaskCreate` for each of #A…#K (subject = issue letter + scope), then `TaskUpdate` to set `blockedBy` edges encoding the DAG:

| Task | blockedBy |
|---|---|
| #A, #B, #C, #D | (none — wave 1) |
| #E | #A, #B, #C, #D |
| #F1 | (none) |
| #F2 | #F1, #C |
| #F3 | #F2 |
| #G | #C |
| #H | #C |
| #I | #E, #F3, #G, #H |
| #J | #E, #F3, #G, #H |
| #K (stretch) | #C |

- [ ] **Step 2: Verify**

Run `TaskList` and confirm: #A/#B/#C/#D unblocked; #E blocked by all four wave-1 tasks; #F3 blocked (transitively) by #F1/#F2/#C; #I and #J blocked by the four demos. This list is the orchestrator's source of truth for what may spawn.

---

## The canonical member spawn-prompt template

Every implementer member is spawned with `Agent` (`name=impl-<X>`, `team_name=demos-milestone`, `subagent_type=general-purpose`, `run_in_background=true`) using the prompt below. **`{CURLY}` fields are parameters** filled from the per-wave tables — they are defined values, not placeholders.

```
You are `impl-{LETTER}`, a persistent implementer member of the `demos-milestone` team. You own GitHub issue {ISSUE_TAG} for TextMeasure.jl. Work the runbook below; do NOT skip steps.

Your kit (all on `main`): the issue body `docs/superpowers/issues/demos-milestone/{ISSUE_FILE}` (your approved spec — Context+Scope+Done-when), the design doc `docs/superpowers/specs/2026-05-28-demos-milestone-design.md`, the orchestration spec `docs/superpowers/specs/2026-05-28-demos-milestone-agent-team-orchestration.md`, and `CLAUDE.md`.

1. WORKSPACE — Use the `superpowers:using-git-worktrees` skill (try the `EnterWorktree` native tool) to create branch `demos-{LETTER}-{SLUG}` off current `main`. If your `Write`/`Edit` edits land in the wrong tree, fall back to Bash-heredoc edits with absolute paths in your worktree (report this so the orchestrator knows the pinning state). Then instantiate: `{INSTANTIATE_CMD}`.
2. PLAN — Use `superpowers:writing-plans` against your issue body to produce a bite-sized TDD task list; commit it to your branch. Then STOP and `SendMessage` the orchestrator: "impl-{LETTER}: plan committed, ready for gate." Then idle.
3. (The orchestrator runs the plan gate and will `SendMessage` you "approved" — do not proceed until you receive it.)
4. IMPLEMENT — On "approved", use `superpowers:executing-plans` + `superpowers:test-driven-development`. Test shapes per the orchestration spec: {TEST_SHAPE}. Use regression floors/ceilings, not hard counts. Do NOT invoke `finishing-a-development-branch`. {GOLDEN_NOTE}
5. VERIFY — Use `superpowers:verification-before-completion`. Run the Julia suite ONCE, capture to `test-logs/$CLAUDE_CODE_SESSION_ID.log`, and grep — never re-run per grep. {RENDER_NOTE}
6. PR — Open the PR (`gh pr create`, base `main`), then use `superpowers:request-pr-review` (author half). `SendMessage` the orchestrator: "impl-{LETTER}: PR #<n> opened." Then idle until the orchestrator nudges you with reviewer feedback; address each round, push, and `SendMessage` "impl-{LETTER}: pushed round <k>"; idle again. Repeat until the orchestrator says the PR is human-approved and merged.

You do NOT self-resume — always `SendMessage` the orchestrator before going idle, and wait to be nudged.
```

Per-issue parameter tables (fill the template):

| {LETTER} | {ISSUE_TAG} | {ISSUE_FILE} | {SLUG} | {INSTANTIATE_CMD} |
|---|---|---|---|---|
| AB | #A + #B (one PR) | `A-prepared-slice.md` + `B-figlet-backend.md` | `subprep-figlet` | `julia --project -e 'using Pkg; Pkg.instantiate()'` |
| C | #C | `C-shape-pack.md` | `shape-pack` | `julia --project=examples/layouts -e 'using Pkg; Pkg.instantiate()'` (create the env first) |
| D | #D | `D-silhouettes.md` | `silhouettes` | `julia --project=examples/silhouettes -e 'using Pkg; Pkg.instantiate()'` |
| E | #E | `E-asteroid-tui.md` | `asteroid-tui` | `julia --project=examples/asteroid_tui -e 'using Pkg; Pkg.instantiate()'` |
| F | #F1→#F2→#F3 (serial, one lane, may be 1–3 PRs) | `F1-…`, `F2-…`, `F3-…` | `doi-infograph` | `julia --project=examples/doi_infograph -e 'using Pkg; Pkg.instantiate()'` |
| G | #G | `G-map-feature.md` | `map-feature` | `julia --project=examples/map_feature -e 'using Pkg; Pkg.instantiate()'` |
| H | #H | `H-newer-yorker.md` | `cover` | `julia --project=examples/cover -e 'using Pkg; Pkg.instantiate()'` |
| I | #I | `I-readme-gallery.md` | `readme-gallery` | `julia --project -e 'using Pkg; Pkg.instantiate()'` |
| J | #J | `J-demo-health-ci.md` | `demo-health-ci` | `julia --project -e 'using Pkg; Pkg.instantiate()'` |
| K | #K (stretch) | `K-knuth-plass-stretch.md` | `knuth-plass` | `julia --project=examples/justification -e 'using Pkg; Pkg.instantiate()'` |

| {LETTER} | {TEST_SHAPE} | {GOLDEN_NOTE} | {RENDER_NOTE} |
|---|---|---|---|
| AB | `measure()` determinism + extension-registration (`Base.get_extension`) checks; `subprep` field-equivalence + width-sum-back | — | — |
| C | `PackedLayout` invariants: `Placement.segment_index ∈ [1,len]`, placements within band chords, `overflowed` populated for over-wide words; pack-into-rect == `layout` | — | — |
| D | `GeometryOps` assertions: `voronoi_shatter` area tol <1e-6 + zero-measure pairwise intersection; `rasterize` BitMatrix for known polygon/cell-size | — | — |
| E | deterministic CORE only: headless 60-tick `CellBuffer` (Matrix{Char}+ANSI) golden checksum + glyph-preservation (each glyph once, in order). Interactive Done-whens (≥30fps, respawn/invuln) are NOT testable — flag them for the orchestrator's tier-2/3 check | Commit your `CellBuffer` golden into the PR; #J only wraps it later | Capture a sample frame (write the `CellBuffer` to a text file) and attach its path in your "PR opened" message so the orchestrator can glance at it |
| F | `PackedLayout` invariants + autoshrink (100 random title lengths fit); F1: data-fetch fallback validation (offline path) | F3: commit the exported-PDF-text checksum golden into the PR | F3: export the 6-up PDF+PNG from CACHED responses; attach the PNG path |
| G | `PackedLayout` bbox non-overlap (text in `complement_chord_fn` negative space) + POI-label non-overlap; `pdftotext` font-embedding/selectability (extracted text == input strings) | Commit the exported-PDF-text checksum golden; render goldens against the pinned fonts (`DejaVu Sans`, `Liberation Serif`) | Render the Vermont quickstart from BUNDLED data (no network); attach the PNG path |
| H | property test: 20 random SVG insets — drop-cap baseline ±0.5px, no bbox overlap, body wrap honors inset, all at `PackedLayout` level (NOT PDF coords); `pdftotext` embedding | Commit the `cover-v1` exported-PDF-text checksum golden; pinned fonts | Render `cover-v{1,2,3}.toml`; attach the v1 PNG path |
| I | links resolve; every `examples/<demo>/README.md` exists; `CHANGELOG.md` covers all shipped issues; docs build | — | Generate the README hero PNG; attach its path (human confirms it loads in GitHub at the merge gate) |
| J | property tests (autoshrink, cover-inset, shape_pack invariants) added to `test/` + run on every PR; license-audit gate; demo-health workflow dedupes issues + auto-closes on green; font-pinning step | — | — |
| K | K-P total badness < greedy on a canonical paragraph (quantified); river overlay identifies greedy rivers K-P avoids | Commit the comparison-PDF text checksum if added to health CI | Render the 3-column comparison PDF; attach its path |

---

## Phase 1 — Wave 1 (#A+#B, #C, #D)

### Task 1.1: Spawn wave-1 members

- [ ] **Step 1: Spawn three implementers**

Spawn `impl-AB`, `impl-C`, `impl-D` with the template + their table rows (single message, concurrent). #A+#B are collapsed into one member/branch/PR: `impl-AB` does #A first (commits), then #B (commits), then ONE PR — they overlap only on `src/TextMeasure.jl`'s export list + `CHANGELOG.md`.

- [ ] **Step 2: Verify spawn**

Confirm via team roster that all three are alive with distinct names. `TaskUpdate` #A/#B/#C/#D `owner` to the respective member; set status `in_progress`.

### Task 1.2: Run the plan gate for each member

- [ ] **Step 1: Await "plan committed" messages**

Each member `SendMessage`s "plan committed, ready for gate" then idles. Arm a `Monitor` backstop on member messages.

- [ ] **Step 2: `verify-before-review` the plan**

For each plan: grep the plan's cited symbols/paths/line-numbers against `main` (not a skim — actually run `grep`/`Read` to confirm each exists). Note: for #B the FIGlet weakdep + `ext/TextMeasureFigletExt.jl` are NEW (won't exist yet — that's expected; verify the cited *existing* anchors only).

- [ ] **Step 3: Run `textmeasure-reviewer` on the plan**

Dispatch the `textmeasure-reviewer` subagent on each committed plan. Collect BLOCKER/MAJOR findings.

- [ ] **Step 4: Surface to the human, then approve**

Present each plan + the verify/review result to the human. On human approval, `SendMessage` the member "approved". On change requests, relay them; the member revises and re-commits; re-gate.

### Task 1.3: Drive the per-PR review loop to convergence

- [ ] **Step 1: On "PR opened", spawn the reviewer**

For each PR #n, spawn `rev-<n>` (`Agent`, `name=rev-<n>`, `team_name=demos-milestone`, `subagent_type=general-purpose`) tasked to use `superpowers:review-pr` with `textmeasure-reviewer` as the analysis engine against PR #n. **Fallback:** if `rev-<n>` reports it cannot drive `review-pr`, run `review-pr` yourself in the root session.

- [ ] **Step 2: Relay rounds (event-driven nudge)**

When `rev-<n>` posts a round, `SendMessage` the author "address review round on PR #n". When the author pushes, `SendMessage` `rev-<n>` "re-review PR #n". The two converge through the PR. If >3 rounds are outstanding across lanes, note it for the wave-2 width throttle.

- [ ] **Step 3: Agent-visual sanity glance**

When a PR converges: for any visual artifact path the member attached, `Read` it and confirm no gross breakage (blank/garbled). This is a non-authoritative smoke check (wave 1 has none — #C/#D/#AB are deterministic-only).

### Task 1.4: Merge gate + wave boundary

- [ ] **Step 1: Surface converged PRs to the human for merge approval**

`SendUserFile` any rendered artifacts (none in wave 1). The human approves each merge. Merge in dependency-safe order (no intra-wave deps here; any order). `impl-AB`'s single PR merges #A+#B together.

- [ ] **Step 2: Re-instantiate `main`**

Run:
```bash
cd /home/jonathanchen/projects/TextMeasure.jl
git checkout main && git pull
mkdir -p test-logs
julia --project -e 'using Pkg; Pkg.instantiate()'
julia --project -e 'using Pkg; Pkg.test()' 2>&1 | tee "test-logs/${CLAUDE_CODE_SESSION_ID:-local}.log"
```
Expected: green. If red, HALT and surface to the human.

- [ ] **Step 3: Shut down wave-1 members + update DAG**

`SendMessage` each merged member a shutdown; stop tracking. `TaskUpdate` #A/#B/#C/#D → `completed` (which unblocks #E and the #C-dependent wave-2 tasks). Clean up wave-1 worktrees.

---

## Phase 2 — Wave 2 (#E, #F-chain, #G, #H) + #K decision

### Task 2.1: #K interleave decision

- [ ] **Step 1: Surface the call to the human**

Ask the human: interleave #K into wave 2 (safe — #C merged, #K only adds `examples/layouts/knuth_plass.jl` and `examples/justification/`, no other wave-2 lane touches `examples/layouts/`) or defer. Set #K's task accordingly.

### Task 2.2: Spawn wave-2 members (adaptive width)

- [ ] **Step 1: Spawn up to 3 lanes, then the 4th as a slot frees**

Spawn `impl-E`, `impl-G`, `impl-H` first (3-wide), and `impl-F` (the #F1→#F2→#F3 serial lane); if nudge load is fine, run all 4 — else queue `impl-F` until a lane frees. (Throttle metric: >3 outstanding review rounds → drop to 2.) `impl-F` works #F1, then #F2, then #F3 on one branch; it may open 1 PR (whole chain) or 3 sequential PRs — its choice, reported in its plan.

- [ ] **Step 2: Verify + assign**

Roster shows distinct names; `TaskUpdate` owners + `in_progress`.

### Task 2.3: Plan gate (per member)

- [ ] **Step 1: Repeat Task 1.2** for each wave-2 member (verify-before-review grep + `textmeasure-reviewer` + human approval + "approved" message). For #F, gate #F1, then #F2, then #F3 as the chain progresses.

### Task 2.4: Review loop + agent-visual glance

- [ ] **Step 1: Repeat Task 1.3** per PR (spawn `rev-<n>`, relay rounds, fallback to root session).

- [ ] **Step 2: Agent-visual sanity glance on the attached artifacts**

`Read` the attached PNGs/frames: #E sample frame (glyphs render, not garbled), #F3 6-up PNG (no blank panels), #G Vermont PNG (map + text both present), #H cover PNG (no obvious clipping). Smoke check only.

### Task 2.5: Merge gate + wave boundary

- [ ] **Step 1: Surface to human for authoritative visual sign-off**

`SendUserFile` the #E frame + fps number, #F3 PDF/PNG, #G PDF/PNG, #H PDF — the human judges legibility / interactive feel and approves each merge. Merge order: any (all four demos are mutually independent).

- [ ] **Step 2: Re-instantiate `main`** (repeat Task 1.4 Step 2). HALT if red.

- [ ] **Step 3: Shut down members; `TaskUpdate` #E/#F3/#G/#H → `completed`** (unblocks #I and #J). If #K was interleaved and merged, complete it too. Clean worktrees.

---

## Phase 3 — Wave 3 (#I, then #J last)

### Task 3.1: Spawn #I and #J (J strictly last)

- [ ] **Step 1: Spawn `impl-I` and `impl-J`**

Both depend on all four merged demos. They are file-disjoint (#I: `README.md`/`CHANGELOG.md`/`examples/README.md`; #J: `.github/workflows/demo_health.yml` + `test/`). **#J merges strictly last** so its CI grep-guard can't false-fail in-flight branches — gate/review both, but hold #J's merge until #I is merged.

### Task 3.2: Plan gate + review loop

- [ ] **Step 1: Repeat Task 1.2 (plan gate) and Task 1.3 (review loop)** for #I and #J. #J's golden-snapshot CI consumes the goldens each demo already committed in wave 2 — verify #J does not re-author them, only wraps them + adds property/license/font-pinning gates.

### Task 3.3: Merge gate + finish

- [ ] **Step 1: Human-approve merges — #I first, then #J**

`SendUserFile` the #I README hero PNG; human confirms it loads in GitHub. Merge #I. Then merge #J.

- [ ] **Step 2: Final re-instantiate + full suite**

Repeat Task 1.4 Step 2; confirm green including the new property tests + license gate.

- [ ] **Step 3: Release hygiene + teardown**

Confirm #I tagged v0.2.0 (per its Done-when). Shut down all members; `TeamDelete` `demos-milestone`; `TaskUpdate` all tasks `completed`; clean remaining worktrees.

---

## Self-Review (completed)

**Spec coverage:** Wave 0 (reviewer subagent + font convention + team + DAG) → Task 0.1–0.4. Per-implementer runbook → the spawn template (steps 1–6 map to the spec's runbook). Plan gate → Task 1.2/2.3/3.2. Review loop + fallback → Task 1.3. Acceptance tiers → {TEST_SHAPE}/{RENDER_NOTE} columns + agent-glance (Task 2.4 Step 2) + human merge gate (Task 2.5 Step 1). Golden ownership + font set → {GOLDEN_NOTE} + Task 0.2. Control loop (completion signal, event nudge, thrash, shutdown, wave boundary, K gate, offline acceptance) → spawn template step 6 + Tasks 1.4/2.1/2.2/2.5/3.3. DAG/waves/J-last → Task 0.4 + phase ordering. Worktree-pinning fallback → spawn template step 1. All spec sections map to a task.

**Placeholder scan:** `{CURLY}` fields are defined parameters with value tables, not placeholders. The `textmeasure-reviewer` content and all commands are complete.

**Type/name consistency:** member names `impl-<letter>` / `rev-<PR#>`, branch `demos-<letter>-<slug>`, team `demos-milestone`, task→blockedBy table, and test-shape names (`PackedLayout`, `CellBuffer`, `complement_chord_fn`, `subprep`) are used consistently and match the issue bodies.
