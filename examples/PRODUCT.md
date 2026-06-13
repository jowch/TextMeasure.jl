<!-- SPDX-License-Identifier: MIT -->
# PRODUCT.md — The TextMeasure.jl Demo Gallery

*Scope: the five-piece demo gallery (#E #F #G #H #K) under `examples/`. Paired with
[`DESIGN.md`](DESIGN.md) (the craft rubric) and
[`docs/superpowers/demos-house-style.md`](../docs/superpowers/demos-house-style.md) (the
locked typographic/colour constants).*

## What the gallery is for

The gallery is the **proof, not the documentation**. The README tells you TextMeasure.jl is
a backend-agnostic *measure-once, layout-many* engine. The gallery makes you *believe* it —
by showing the same measured text doing things an HTML canvas can't, in media an HTML
canvas can't reach: a print magazine, a state silhouette, a live terminal.

A visitor should leave with one sentence: **"It measures text once, then lays it out
anywhere — paper, a shape, a moving terminal — and the geometry is exact."**

## Who reads it

1. **The skeptical Julia/graphics engineer** evaluating the library for a real layout job.
   They will not read source first; they look at the gallery, and if it looks
   hand-assembled and exact, they trust the code. Sloppy kerning or a misaligned baseline
   reads as "the measurement is wrong" — fatal for a *measurement* library.
2. **The design-literate browser** (HN, Julia Discourse, a conference hallway). They judge
   craft in two seconds. The gallery has to survive that glance.

## The one claim each demo must make tangible

Each piece exists to make exactly **one** capability undeniable. If a piece doesn't make
its claim legible at a glance, it has failed regardless of how pretty it is.

| # | Piece | The single claim it must prove |
|---|---|---|
| **#E** | Asteroid TUI | *Measure once, reflow live.* Shape-packed prose tumbles and re-flows inside rotating silhouettes and fractures on word boundaries on impact — all from cached measurements, in a terminal, at frame rate. The headline. |
| **#F** | DOI Infographic | *Exact data-driven typography.* Citation bars and tag chips whose widths are computed from measured text, not guessed — alignment that only holds if measurement is exact. |
| **#G** | California Silhouette | *Text conforms to arbitrary shape.* Prose `shape_pack`ed into a non-rectangular outline, hugging the boundary with no overflow and no re-measure. |
| **#H** | The Newer Yorker | *Editorial fidelity.* A magazine spread ("A Correctness Exhibit") where measured layout matches a print compositor's eye — margins, baselines, and a skyline inset that all line up. |
| **#K** | Knuth–Plass | *Justification done right.* Optimal-fit justified columns whose even rivers and exact line widths are only possible with correct advance widths. The one piece that *is* full-justify. |

## Out of scope (so the gallery stays a gallery)

No rendering engine, no annotation/repel/treemap consumers, no UAX-#14 line-breaking, CJK,
or hyphenation (see `CLAUDE.md`). The gallery demonstrates the *measurement* contract; it
does not grow new library surface to look impressive.

## Definition of a piece that earns its place

A piece stays in the gallery only if it **(a)** makes its one claim legible at a glance and
**(b)** clears every axis of `DESIGN.md` at ≥ 8/10. A piece that is technically interesting
but visually muddled, or pretty but claim-less, gets redesigned or cut. Coherence across the
five is not optional: they share the house-style spine so the gallery reads as *authored by
one hand*, not assembled from five contributors.
