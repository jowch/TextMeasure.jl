# SPDX-License-Identifier: MIT
module Tide

# The Tide — a kinetic-typography gallery piece built on TextMeasure's layout engine.
#
# THE THESIS the piece demonstrates: measure ONCE, lay out MANY. The font engine is touched
# exactly once (`prepare_tide`), caching every glyph-advance width. Every frame is then pure
# arithmetic over those cached widths — one `shape_pack` re-flows the prose into the frame's
# surviving region, and a demo-side justify pass rewrites positions flush to both margins. No
# per-frame measuring; no new engine surface.
#
# WHAT YOU SEE: a justified prose sea-passage on a warm sunset palette. A wavy coral tide-line
# sweeps counterclockwise around the block; each press is a smooth swell that kneads the text by
# re-flowing it into the region the wave leaves behind. Shipped as a seamless 60fps MP4 loop, a
# hero still, and a ghosted thumbnail. See README.md for the full pipeline + the ideas to lift.

using TextMeasure
using TextMeasure: prepare, MakieBackend, MonospaceBackend, Prepared, Segment
using TextMeasureLayouts: shape_pack, raster_chord_fn, chord_intervals, Placement
using HouseStyle: FONTS_DIR, hanken, digest_rows
using CairoMakie, Makie
using Makie: Point2f

# Pipeline, in dependency order (see each file's header for its role):
include("text.jl")          # the prose + the lit-word ("kneads") test
include("schedule.jl")      # DIRECTIONS, N_FRAMES, press_at — the seamless-loop swell schedule
include("mask.jl")          # region_mask — the frame's wavy surviving region as a BitMatrix
include("justify.jl")       # justify_bands — demo-side flush-both-edges justify (rewrites x only)
include("frame.jl")         # prepare_tide (measure once) + frame_layout (one shape_pack/frame)
include("render.jl")        # palette + draw_frame! + render_hero
include("loop.jl")          # render_loop, render_samples, render_thumb
include("golden.jl")        # geometry_rows + tide_digest — the deterministic golden invariant

export render_hero, render_loop, render_samples, render_thumb, tide_digest

end # module Tide
