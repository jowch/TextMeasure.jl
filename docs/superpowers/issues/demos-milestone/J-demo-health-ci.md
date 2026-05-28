# J — Demo health CI + golden snapshots + property tests + license gate

> Wave 3 integration · prevents demos from rotting silently.

## Scope

Cross-cutting CI work addressing the "demos rot silently" failure mode. Without this, the demos drift the moment a dependency moves.

- **Weekly scheduled GitHub Actions workflow** at `.github/workflows/demo_health.yml`. Boots each demo in CI:
  - **#E asteroid:** headless tick-loop, 60 ticks, snapshot cell buffer, checksum vs committed golden.
  - **#F3 DOIInfograph:** render the 6-up grid from cached responses, extract text from exported PDF, checksum.
  - **#G map feature:** render Vermont's page from bundled data (no network), checksum exported PDF text.
  - **#H newer yorker:** render `cover-v1.toml`, checksum exported PDF text.
- **Failure-to-issue plumbing:** the workflow searches for an open issue with a canonical title (e.g., `[demo-health] {demo-name} regression`); reopens or comments on it if found, opens a new one only if missing. **Auto-closes the issue on the next successful run.** Prevents maintainer fatigue from a flaky upstream filing many issues.

  **Concrete mechanism (the workflow `permissions:` block needs `issues: write`):**
  ```yaml
  - name: Report or close demo-health status
    if: always()
    env:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      DEMO: ${{ matrix.demo }}
      OUTCOME: ${{ steps.run-demo.outcome }}  # success | failure
    run: |
      TITLE="[demo-health] ${DEMO} regression"
      ISSUE=$(gh issue list --search "in:title ${TITLE}" --state open --json number --jq '.[0].number // empty')
      if [ "$OUTCOME" = "failure" ]; then
        if [ -n "$ISSUE" ]; then
          gh issue comment "$ISSUE" --body "Re-occurred on $(date -Iseconds) — see run ${GITHUB_RUN_ID}"
        else
          gh issue create --title "$TITLE" --body "First detected on $(date -Iseconds) — see run ${GITHUB_RUN_ID}" --label demo-health,wave-3
        fi
      elif [ -n "$ISSUE" ]; then
        gh issue close "$ISSUE" --comment "Resolved on $(date -Iseconds) — green run ${GITHUB_RUN_ID}"
      fi
  ```

  The job runs `if: always()` so close-on-green fires even after step success. Race condition (two weekly runs overlapping) is handled by `concurrency: { group: demo-health-${{ github.workflow }}, cancel-in-progress: false }` at the workflow level.
- **CI matrix gate** (regular CI, not weekly): Linux and macOS for all demos; Windows for the CairoMakie demos (#F3, #G, #H) only — the asteroid TUI's Linux-and-macOS-only scope is enforced by a CI exclusion. Includes a font-pinning step: install a minimal known font set (`DejaVu Sans`, `Liberation Serif`) on each runner before CI runs the demos that depend on them.
- **Property tests** in regular CI:
  - Autoshrink property test (from #F2): 100 random title lengths all fit.
  - Cover random-inset property test (from #H): 20 random insets all uphold invariants.
  - `shape_pack` invariants (from #C): every `Placement.segment_index ∈ [1, length(prep.segments)]`; placements per band do not exceed band's chord intervals; overflowed segments do not have placements.
- **License audit gate** in regular CI: every file in `examples/` has a license header.

## Acceptance

- Weekly health-check workflow at `.github/workflows/demo_health.yml`; runs successfully against all four demos.
- Workflow correctly dedupes against existing issues; auto-closes on green.
- Property tests added to `test/` and run on every PR.
- CI matrix runs on Linux and macOS; CairoMakie demos additionally tested on Windows (asteroid TUI excluded from Windows).
- Font pinning step succeeds on every runner before demo execution.
- License audit gate fails CI if any `examples/` file lacks a header.

## Depends on / Blocks

- **Depends on:** all completed demos (#E, #F3, #G, #H) — golden snapshots come from each.
- **Blocks:** nothing (final integration).

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#J — Demo health CI + golden snapshots + property tests + license gate."
- **Existing CI:** prior commit 4864098 added first CI; this issue extends it.
- **GitHub Actions pattern:** `gh issue list --search "in:title [demo-health]"` + `gh issue reopen/comment/create/close`.
- **Conventions:** `CLAUDE.md`.

## Suggested labels

`demos-milestone` · `wave-3` · `infra` · `ci`
