# CI + CompatHelper Prerequisite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the repo its first CI so the upcoming RichText golden test runs on every PR, and add CompatHelper so a future Makie release surfaces any drift in the mirrored constants as a red compat-bump PR.

**Architecture:** Standard `julia-actions` CI matrix running `Pkg.test()`; a CompatHelper workflow managing `[compat]` in **both** the root `Project.toml` and `test/Project.toml` (the test env is the binding constraint, since the golden test runs there). Makie needs a virtual display in headless CI, so tests run under `xvfb`.

**Tech Stack:** GitHub Actions, julia-actions (setup-julia/cache/buildpkg/julia-runtest), CompatHelper.jl, xvfb.

**Why first:** This is repo-wide infrastructure, independent of the measurement feature. Landing it first means the golden test is guarded the moment it exists. See `docs/superpowers/specs/2026-05-27-richtext-measurement-design.md` → "CI and version-drift detection".

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
```

This makes the test-env Makie version explicit and gives CompatHelper something to widen — the test env is what actually exercises the golden test against a new Makie.

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
    tags: ['*']
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
      - name: Install xvfb (Makie needs a display in headless CI)
        run: sudo apt-get update && sudo apt-get install -y xvfb
      - uses: julia-actions/julia-buildpkg@v1
      - uses: julia-actions/julia-runtest@v1
        with:
          prefix: xvfb-run -a
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/CI.yml
git commit -m "ci: add Pkg.test matrix (Julia 1.11 + latest) under xvfb"
```

- [ ] **Step 3: Push the branch and verify CI goes green**

Push the branch and open a PR (or push to a branch CI runs on). Watch the Actions tab.
Expected: both matrix jobs (`1.11`, `1`) run `Pkg.test()` and pass on the existing suite.

> **If a job fails because Makie cannot open a display** even under `xvfb-run`: the existing
> `test_makie.jl` already constructs Makie objects, so this would already be failing locally —
> confirm `julia --project -e 'using Pkg; Pkg.test()'` passes locally first. If it passes
> locally but not in CI, the `xvfb-run -a` prefix is the fix; do not add a rendering backend
> (CairoMakie/GLMakie) unless a test actually renders — the suite only measures.

---

### Task 3: Add the CompatHelper workflow

**Files:**
- Create: `.github/workflows/CompatHelper.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: CompatHelper
on:
  schedule:
    - cron: '0 0 * * *'
  workflow_dispatch:
permissions:
  contents: write
  pull-requests: write
jobs:
  CompatHelper:
    runs-on: ubuntu-latest
    steps:
      - name: Set up Julia
        uses: julia-actions/setup-julia@v2
        with:
          version: '1'
      - name: Add CompatHelper
        run: julia -e 'using Pkg; Pkg.add("CompatHelper")'
      - name: Run CompatHelper (manage root + test subdir)
        run: julia -e 'using CompatHelper; CompatHelper.main(; subdirs=["", "test"])'
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          COMPATHELPER_PRIV: ${{ secrets.DOCUMENTER_KEY }}
```

The `subdirs=["", "test"]` argument is the load-bearing part: it tells CompatHelper to widen
`[compat]` in `test/Project.toml` too, not just the root. Without `"test"`, a new Makie release
would never reach the golden test.

> `COMPATHELPER_PRIV` is optional (only needed if pushing from a private deploy key); the
> default `GITHUB_TOKEN` is sufficient for opening PRs on a public repo. Leaving the line in is
> harmless if the secret is unset.

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/CompatHelper.yml
git commit -m "ci: add CompatHelper managing root + test/ compat"
```

- [ ] **Step 3: Verify the workflow is valid**

In the GitHub Actions tab, trigger CompatHelper via `workflow_dispatch` ("Run workflow").
Expected: the job completes; on first run it may open compat-widening PRs or report "nothing to
do". A successful run (no YAML/parse error, exit 0) is the pass condition.

---

### Task 4 (optional): Weekly latest-Makie canary

**Files:**
- Modify: `.github/workflows/CI.yml`

Only do this if you want early warning of Makie drift *before* a CompatHelper bump. It runs the
suite against the latest Makie ignoring the upper compat bound, and is allowed to fail.

- [ ] **Step 1: Add a non-blocking canary job to `CI.yml`**

Add this job alongside the existing `test` job:

```yaml
  canary-latest-makie:
    name: Canary (latest Makie)
    runs-on: ubuntu-latest
    continue-on-error: true   # early-warning only; never blocks the branch
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with:
          version: '1'
      - uses: julia-actions/cache@v2
      - name: Install xvfb
        run: sudo apt-get update && sudo apt-get install -y xvfb
      - name: Force latest Makie in the test env and run the suite
        run: |
          xvfb-run -a julia --project=test -e '
            using Pkg
            Pkg.develop(PackageSpec(path=pwd()))
            Pkg.update()
            Pkg.test("TextMeasure")'
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/CI.yml
git commit -m "ci: add non-blocking latest-Makie canary"
```

---

## Self-Review

- **Spec coverage:** CI.yml (Task 2), CompatHelper.yml (Task 3), `test/Project.toml` `[compat]`
  (Task 1), optional canary (Task 4) — all four items from the spec's CI section are covered.
- **Placeholder scan:** none — all YAML is complete and runnable.
- **Consistency:** `subdirs=["", "test"]` (Task 3) matches the spec's "manage both root and
  test/" and the "test env is the binding trip-wire" claim. Julia versions `['1.11','1']` match
  the compat floor (`julia = "1.11"`) in the root `Project.toml`.
