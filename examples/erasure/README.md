# ERASURE — a poem hiding in the MIT License

A blackout / found-poem demo for TextMeasure.jl. The project's own `LICENSE` is laid out
once by the engine; all but ~15 curated words are struck out with one continuous ink
censor field; the survivors — frozen at their EXACT measured coordinates — read as a poem
on a brass reading thread. See `SPEC.md` for the design rationale.

## Run

    julia --project=examples/erasure -e 'using Pkg; Pkg.instantiate()'
    # hero PNG:
    julia --project=examples/erasure -e 'using Erasure; Erasure.hero("examples/erasure/erasure-hero.png")'
    # tests (golden over computed geometry, never pixels):
    julia --project=examples/erasure -e 'using Pkg; Pkg.test()'

## How it works (all in-contract)

`prepare(backend, LICENSE)` measures every run once (no kerning); `word_boxes` re-walks
`prep.segments` with the SAME greedy + whitespace-trim rule `layout` uses to recover a
per-word `(seg_index, line, x0, x1, baseline)` table — exact under `align=:left`. The
re-walk is proven against `layout(prep).lines` (test_wordgeom.jl). Redaction bars + kept
survivors are drawn from ONE geometry pass, so a survivor is by construction in its
original spot. Curation (which words survive) is authoring, not measurement.

## Constraint

The survivor-position guarantee holds for `align=:left` only (the hero is a "document").
The toy defaults to the curated poem; "surprise me" is a labeled non-engine heuristic.
