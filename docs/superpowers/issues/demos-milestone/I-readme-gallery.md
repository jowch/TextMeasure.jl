# I — README hero, gallery, release hygiene

> Wave 3 integration · ships v0.2.0.

## Scope

Cross-cutting integration work:

- README hero: the **6-up DOIInfograph grid PNG** (committed binary). A **high-resolution PDF version of the same grid is linked beside the PNG** so users can inspect per-panel detail that GitHub's PNG rendering may shrink.
- README's "Backends" section updated to include `FigletBackend` — activated by `using FIGlet` (kdheepak's existing FIGlet.jl, install via `Pkg.add("FIGlet")`).
- `examples/README.md` as the gallery index — each demo with one-line pitch, screenshot, run instructions.
- Each `examples/<demo>/README.md` exists with run instructions and a `Project.toml` / `Manifest.toml` ready for `julia --project=. -e 'using Pkg; Pkg.instantiate()'`.
- `CHANGELOG.md` updated with one entry per shipped issue.
- Documenter.jl integration: a `docs/` build (basic — landing page + each public API page + link to the gallery). GitHub Pages deploy workflow optional.
- License headers on every file in `examples/`. Match parent (MIT) unless a sibling package needs a different license.
- Version bump to 0.2.0 with summary in CHANGELOG.

## Acceptance

- README hero PNG loads in GitHub view; high-res PDF link works.
- All `examples/<demo>/README.md` files exist and accurately describe the run flow.
- `CHANGELOG.md` reflects every shipped issue.
- `docs/build/` succeeds locally and in CI.
- License audit passes (every `examples/` file has a header; sibling-package licenses verified).
- Version 0.2.0 tagged after this issue lands.

## Depends on / Blocks

- **Depends on:** all completed demos (#E, #F3, #G, #H).
- **Blocks:** the v0.2.0 release tag.

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#I — README hero, gallery, release hygiene."
- **Existing artifacts:** current `README.md`, `CHANGELOG.md`, `LICENSE`.
- **Conventions:** `CLAUDE.md`.

## Suggested labels

`demos-milestone` · `wave-3` · `infra` · `release`

## Open questions for the planner

- GitHub Pages deploy workflow — add now or defer?
