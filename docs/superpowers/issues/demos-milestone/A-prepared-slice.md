# A — `Prepared` segment-slice helper

> Wave 1 unblocker · library addition.

## Scope

Add a kwargs constructor `Prepared(; segments, metrics)` and a named `subprep(prep, r::AbstractUnitRange) -> Prepared` helper. Preserve the existing positional field order `Prepared(segments, metrics)`. **Do not override `Base.getindex`** — that violates collection semantics (`prep[i]` should naturally return a `Segment`, the contained element type, not a sub-`Prepared`).

Motivation: the asteroid demo's word-boundary fracture mechanic (#E) needs sub-`Prepared`s to re-pack halves of an already-measured paragraph without re-measuring. `shape_pack` (#C) consumes `prep.segments` directly and does NOT need `subprep`, so #A does not block #C.

## Acceptance

- `Prepared(; segments=s, metrics=m).segments == s` and `.metrics == m`.
- `subprep(prep, 1:length(prep.segments)) == prep` semantically.
- Slicing at a word boundary, calling `layout` on both halves, confirms widths sum back correctly.
- Slicing across `:newline` or `:space` segments preserves segment integrity (the segments end up in the side they're indexed into; no segments dropped or duplicated).
- Export `subprep` from TextMeasure.
- `CHANGELOG.md` entry under "Added."

## Depends on / Blocks

- **Depends on:** nothing (independent).
- **Blocks:** #E only.

## Context

- **Design spec:** [`docs/superpowers/specs/2026-05-28-demos-milestone-design.md`](../../specs/2026-05-28-demos-milestone-design.md) — see "#A — `Prepared` segment-slice helper."
- **Existing code:**
  - `src/types.jl` — `Prepared` struct definition.
  - `src/prepare.jl` — current `prepare()` implementation.
  - `src/TextMeasure.jl` — export list.
- **Conventions:** `CLAUDE.md`.

## Suggested labels

`demos-milestone` · `wave-1` · `library`
