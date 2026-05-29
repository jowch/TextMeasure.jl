# TextMeasure.jl

A backend-agnostic text **layout engine**: measure once, lay out many times.
Inspired by [pretext.js](https://github.com/chenglou/pretext), using FreeType/Makie
rather than canvas.

```julia
using TextMeasure
using FreeTypeAbstraction                # enables FreeTypeBackend

b   = FreeTypeBackend(; font="DejaVu Sans", fontsize=14)
prp = prepare(b, "The quick brown fox")  # measures once (touches the font engine)
lay = layout(prp; max_width=120, align=:left)   # pure arithmetic — call freely

lay.size                                  # (width, height) in px
for ln in lay.lines
    @show ln.str, ln.x, line_top(lay, ln) # top-left placement, block-top = 0
end
```

Backends: `MonospaceBackend` (zero-dep, built in), `FreeTypeBackend`
(`using FreeTypeAbstraction`), `MakieBackend` (`using Makie`; measurements match
Makie's `text!` at `px_per_unit = 1`), and `FigletBackend` (`using FIGlet`; install
via `Pkg.add("FIGlet")`) — which measures in **character cells** for FIGlet ASCII-art
fonts rather than pixels.

**Not in scope:** rendering, repel/treemap/annotation consumers (downstream), UAX-#14
line-breaking, CJK, hyphenation, justification, rotation.

## Demos / Gallery

The [`examples/`](examples/) directory is a gallery of measurement-driven layout demos
built on this engine — editorial covers, map feature pages, justification comparisons,
shape-conforming text packing, and an adaptive academic-paper infographic. See
**[examples/README.md](examples/README.md)** for the full index with screenshots and
run instructions for each.

The hero is the **DOIInfograph 6-up grid** (`examples/doi_infograph/`): six very
different papers — short and 125-char titles, 8 to 446 authors, with and without
abstracts — all composed by the *same* measurement-driven template. That uniformity
is the proof of adaptiveness.

[![DOIInfograph 6-up grid](examples/doi_infograph/assets/grid_hero.png)](examples/doi_infograph/assets/grid_hero.pdf)

GitHub shrinks the PNG above; for per-panel detail open the high-resolution vector
composite (selectable text): **[`grid_hero.pdf`](examples/doi_infograph/assets/grid_hero.pdf)**.
