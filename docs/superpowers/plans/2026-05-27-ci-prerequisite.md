# CI + Dependabot Prerequisite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the repo its first CI so the upcoming RichText golden test runs on every PR, and add Dependabot so a future Makie release surfaces any drift in the mirrored constants as a red `[compat]`-bump PR.

**Architecture:** Standard `julia-actions` CI matrix running `Pkg.test()`; a Dependabot config (`.github/dependabot.yml`, ecosystem `julia`) widening `[compat]` in **both** the root `Project.toml` and `test/Project.toml` (the test env is the binding constraint, since the golden test runs there — and the root weakdep bound also caps the test env, so both must widen). Dependabot is chosen over CompatHelper because it is the officially-recommended tool today, its PRs **trigger CI natively** (no SSH deploy key), and it is one config file. The suite only *measures* (no rendering), so no display/`xvfb` is needed.

**Tech Stack:** GitHub Actions, julia-actions (setup-julia/cache/buildpkg/julia-runtest), Dependabot (ecosystem `julia`, GA since 2025-12).

**Why first:** This is repo-wide infrastructure, independent of the measurement feature. Landing it first means the golden test is guarded the moment it exists. See `docs/superpowers/specs/2026-05-27-richtext-measurement-design.md` → "CI and version-drift detection".

**One verification checkpoint (Task 3):** Dependabot's `[compat]`-widening for regular `[deps]` is confirmed; its handling of **`[weakdeps]`** (how Makie/FreeTypeAbstraction are declared in the *root* file) is not yet verified. Task 3 includes a check that Dependabot's first run touches the root weakdep bound. If it doesn't, the fallback is to manage the root file with CompatHelper-via-deploy-key (documented in Task 3) — `test/Project.toml` (regular deps) is covered by Dependabot regardless.

---

### Task 1: Add `[compat]` to the test environment

**Files:**
- Modify: `test/Project.toml`

- [ ] **Step 1: Add a `[compat]` section pinning the test deps**

Append to `test/Project.toml` (it currently has only `[deps]`):

```toml
[compat]
FreeTypeAbstraction = "0.10"
Makie = "0.24"
Test = "<0.0.1, 1"
julia = "1.11"
```

This makes the test-env Makie version explicit and gives Dependabot a `[compat]` entry to widen — the test env is what actually exercises the golden test against a new Makie. (`Test`/`julia` entries aid reproducibility; `Test` is an stdlib so its bound is nominal.)

- [ ] **Step 2: Verify the test env still resolves**

Run: `julia --project=test -e 'using Pkg; Pkg.instantiate(); Pkg.status()'`
Expected: resolves without error; Makie shows a `0.24.x` version.

- [ ] **Step 3: Commit**

```bash
git add test/Project.toml
git commit -m "build: pin test-env compat for Makie/FreeTypeAbstraction"
```

---

### Task 2: Add the CI workflow

**Files:**
- Create: `.github/workflows/CI.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  test:
    name: Julia ${{ matrix.version }} - ${{ matrix.os }}
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        version: ['1.11', '1']   # compat floor + latest stable
        os: [ubuntu-latest]
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with:
          version: ${{ matrix.version }}
      - uses: julia-actions/cache@v2
      - uses: julia-actions/julia-buildpkg@v1
      - uses: julia-actions/julia-runtest@v1
```

> **No `xvfb` / rendering backend.** The suite only *measures*: `test_makie.jl` uses `text_bb`
> and the new golden test uses `boundingbox(plot, :pixel)`, both pure CPU glyph-layout math with
> no display. (`julia-actions/julia-runtest` does support a `prefix:` input — e.g.
> `prefix: xvfb-run -a` — if a future test ever renders via a backend; not needed now.)

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/CI.yml
git commit -m "ci: add Pkg.test matrix (Julia 1.11 + latest)"
```

- [ ] **Step 3: Push the branch and verify CI goes green**

Push the branch and open a PR (or push to a branch CI runs on). Watch the Actions tab.
Expected: both matrix jobs (`1.11`, `1`) run `Pkg.test()` and pass on the existing suite.

> **If a job fails because Makie can't initialize headlessly:** confirm `julia --project -e
> 'using Pkg; Pkg.test()'` passes locally first (it should — the suite only measures). If it
> passes locally but not in CI, add `with: {prefix: xvfb-run -a}` to the `julia-runtest` step
> and a preceding `sudo apt-get update && sudo apt-get install -y xvfb` step. Do **not** add a
> rendering backend (CairoMakie/GLMakie) unless a test actually renders.

---

### Task 3: Add Dependabot for `[compat]` drift detection

**Files:**
- Create: `.github/dependabot.yml`
- (Repo setting) enable "Allow GitHub Actions to create and approve pull requests"

Dependabot (ecosystem `julia`, GA 2025-12) widens `[compat]` bounds in `Project.toml` and opens a
PR per update; unlike a `GITHUB_TOKEN`-pushed CompatHelper PR, **Dependabot PRs trigger CI
natively**, so the golden test runs against the new Makie automatically — closing the drift chain
with no deploy key.

- [ ] **Step 1: Write the Dependabot config**

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "julia"
    directories:
      - "/"        # root Project.toml (Makie/FreeTypeAbstraction are [weakdeps] here)
      - "/test"    # test/Project.toml (Makie/FreeTypeAbstraction are regular [deps] here)
    schedule:
      interval: "daily"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

`directories` (plural) lets one config manage both Project.toml locations; Dependabot opens one PR
per dependency per directory. The `github-actions` block keeps the workflow action versions fresh.

- [ ] **Step 2: Enable the repo setting**

Settings → Actions → General → Workflow permissions → check **"Allow GitHub Actions to create and
approve pull requests."** Without it the bot's PR creation 403s. (No secrets/deploy key needed;
the default Dependabot CI-trigger behavior requires no extra auth, and this measurement-only CI
needs no secrets.)

- [ ] **Step 3: Commit**

```bash
git add .github/dependabot.yml
git commit -m "ci: add Dependabot (julia + github-actions) for compat drift detection"
```

- [ ] **Step 4: Verify Dependabot runs AND widens the root weakdep bound**

Push the branch. In Settings → Code security (or Insights → Dependency graph → Dependabot), confirm
Dependabot is enabled and runs without config errors. To force a run now: Insights → Dependency
graph → Dependabot → "Check for updates" on the `julia` ecosystem.

**The load-bearing check:** when Dependabot opens (or would open) a Makie/FreeTypeAbstraction bump,
confirm the PR that targets `/` **edits the `[weakdeps]` dependency's `[compat]` entry in the root
`Project.toml`** (not just the `/test` PR). Dependabot's `[compat]` widening is confirmed for
regular `[deps]`; its `[weakdeps]` handling is unverified, and the root weakdep bound caps the
test-env resolution — so if the root PR does **not** touch the weakdep bound, the golden test would
keep running against old Makie.

> **Fallback if Dependabot does NOT widen the root weakdep bound:** manage only the root
> `Project.toml` with CompatHelper-via-SSH-deploy-key (keep Dependabot for `/test` and
> github-actions). Setup: generate a key (`ssh-keygen -m PEM -N "" -f ch_key`), add `ch_key.pub`
> as a **write-enabled deploy key**, store the **raw PEM** contents of `ch_key` as the
> `COMPATHELPER_PRIV` secret (note: `DocumenterTools.genkeys()` instead emits a **base64** blob —
> use whichever matches how you generated it; CompatHelper accepts both), then add a
> `.github/workflows/CompatHelper.yml` running `CompatHelper.main()` with both
> `GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}` and `COMPATHELPER_PRIV: ${{ secrets.COMPATHELPER_PRIV }}`
> in `env`. Only pursue this if Step 4 proves it necessary.

---

## Self-Review

- **Spec coverage:** test `[compat]` (Task 1), CI.yml (Task 2), Dependabot drift detection
  (Task 3) — covers the spec's CI section. The canary is dropped: Dependabot's PR runs the golden
  test against the new Makie automatically, so a separate "latest-Makie" job is redundant once the
  Task 3 Step 4 weakdep check passes.
- **Placeholder scan:** none — all YAML is complete and runnable; the Task 3 fallback is a real,
  spelled-out contingency, not deferred work.
- **Drift chain integrity:** Dependabot PRs trigger CI natively (no deploy key), so a Makie bump
  PR runs the golden test → red if a mirrored constant changed. The one unverified link
  (does Dependabot widen the **root weakdep** bound?) is an explicit verification step (Task 3
  Step 4) with a CompatHelper-deploy-key fallback if it fails. The root weakdep bound caps the
  test-env resolution, so it must widen for the chain to fire.
- **No xvfb:** the suite only measures (`text_bb` / `boundingbox(plot,:pixel)`), so no display is
  needed; xvfb is documented as a fallback only.
- **Consistency:** `directories: ["/", "/test"]` (Task 3) matches the spec's "manage both root and
  test/". Julia versions `['1.11','1']` (Task 2) match the compat floor (`julia = "1.11"`).
