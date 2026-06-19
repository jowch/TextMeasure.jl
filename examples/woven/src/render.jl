# SPDX-License-Identifier: MIT
using CairoMakie
using HouseStyle: PAPER

"""
    save_png(scene_fn, path; size=(1200, 1600), px_per_unit=1, yflip=true, bg=HouseStyle.PAPER)

Reusable gallery render plumbing: build a `bg`-backed, decoration-free `Axis` (y down
when `yflip`, matching the engine's block coordinates), invoke `scene_fn(ax)` to draw,
and save a PNG at `px_per_unit`. The shared still-render entry point for the gallery.
`bg` defaults to the house PAPER; a piece with a local palette passes its own background.

Callers use the `do`-block form, where `do ax ... end` IS the `scene_fn`:

# Examples
```julia
using Woven, CairoMakie

save_png("demo.png"; size=(200, 120)) do ax
    scatter!(ax, [1.0, 2.0], [1.0, 2.0])     # draw into the y-down Axis; then it's written
end
```
"""
function save_png(scene_fn, path; size = (1200, 1600), px_per_unit = 1, yflip = true,
                  bg = PAPER)
    fig = Figure(; size = size, backgroundcolor = bg)
    ax  = Axis(fig[1, 1]; backgroundcolor = bg, aspect = DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    yflip && (ax.yreversed = true)        # block-top = 0, increasing downward
    scene_fn(ax)
    save(path, fig; px_per_unit = px_per_unit)
    return path
end
