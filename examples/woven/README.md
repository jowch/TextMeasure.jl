# WOVEN — two found poems through one license

The project's own MIT `LICENSE` is laid out once by the engine and faded to a Plex Mono
ghost. Two found poems are lit in place through that text:

- **"Without Limitation"** in RED (vermillion), through the grant clause;
- **"As Is"** in BLACK, from the notice paragraph down through the warranty.

Every word is **measured at its real size and weight**, then the whole license is justified
with Knuth–Plass over those mixed-size boxes — so enlarged poem words get room and **nothing
overlaps**. This is the engine showcase: *measure, then lay out accordingly.*

Type roles: **Fraunces** serif carries the poem (the FREE / AS IS pivots + body); **Hanken
Grotesk** sans is the chrome (the two-colour "Free, As Is" masthead, EXHIBIT A, the
"TextMeasure.jl" footer); **IBM Plex Mono** is the faded source. Local type-specimen palette:
paper `#F6F6F4`, ink `#161616`, vermillion `#C8341F`.

## Run

    julia --project=examples/woven -e 'using Pkg; Pkg.instantiate()'
    # hero PNG:
    julia --project=examples/woven -e 'using Woven; Woven.hero("examples/woven/woven-hero.png")'
    # tests (golden over the COMPUTED geometry table, never pixels):
    julia --project=examples/woven -e 'using Pkg; Pkg.test()'

## How it works

`placement_table(make_backend)` measures every license word at its real face/size, builds a
synthetic `Prepared` of MIXED-size boxes (interword glue scaled by the larger neighbour; a
`:newline` at each paragraph break), and justifies it with `knuth_plass` on a constant
pre-calculated pitch. It is parameterized by the backend, so the hero uses `MakieBackend`
(real font widths) and the golden uses the deterministic `MonospaceBackend` through the SAME
pipeline. `test_layout.jl` proves the no-overlap invariant; the golden hashes the computed
table, never the rendered pixels.
