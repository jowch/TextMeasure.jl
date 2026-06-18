# SPDX-License-Identifier: MIT
# build.jl — render the Atlas deliverables.
#
# Run from examples/atlas/:
#   julia --project build.jl
#
# Produces:
#   atlas-dive.mp4     — 360-frame seamless zoom-dive loop (scale=2 default; bump to 4 for delivery)
#   atlas-hero.png     — still at mid-dive (p=0.33)
#   loopframe-01..08.png — 8 evenly-spaced extracted frames for visual inspection

using Atlas

@info "Building Atlas hero still …"
r_hero = Atlas.render_hero()
@info "Hero done" r_hero.path r_hero.bytes

@info "Building Atlas zoom-dive loop (scale=2, 360 frames) …"
r_loop = Atlas.render_loop()
@info "Loop done" r_loop.path r_loop.format r_loop.bytes r_loop.n_frames

if r_loop.format === :mp4
    @info "Extracting 8 loopframes for visual inspection …"
    frames = Atlas.extract_loopframes(r_loop.path)
    @info "Loopframes written" frames
end

@info "All Atlas deliverables done."
