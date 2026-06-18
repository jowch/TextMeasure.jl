# SPDX-License-Identifier: MIT
"""
spike_timing.jl — Atlas demo de-risk spike

Answers two questions that dictate place.jl's architecture:

  PROBE (a): After limits!(ax, ...) + update_state_before_display!(fig),
             does project(ax.scene, :data, :pixel, p) reflect the NEW limits
             (i.e. current-frame coords), or does it lag one frame?

  PROBE (b): Does solve_cluster(...; init_state = prev_offsets) RELAX the
             prior layout (warm-start holds), or re-seed from scratch?

Run from examples/atlas/:
    julia --project prep/spike_timing.jl

Source pins:
  - Makie.project(scenelike, :data, :pixel, pos) → Point3f
      /home/jonathanchen/.julia/packages/Makie/kJl0u/src/camera/projection_math.jl:569
      Handles f32_convert, viewport origin, full coordinate-space chain.
      Take [1:2] for 2-D pixel coordinates.
  - solve_cluster warm-start contract:
      /home/jonathanchen/projects/MakieTextRepel.jl/src/solvers/abstract.jl
      init_state === nothing → fresh seed; given → legalize-only (warm-start).
"""

using CairoMakie, Makie
using MakieTextRepel: ProjectionSolver, RepelParams, solve_cluster
using GeometryBasics: Point2f, Vec2f, Rect2f
using LinearAlgebra: norm

# ─────────────────────────────────────────────────────────────────────────────
# PROBE (a): per-frame projection timing
# ─────────────────────────────────────────────────────────────────────────────
println("=" ^ 60)
println("PROBE (a): per-frame projection timing")
println("=" ^ 60)

fig = Figure(size = (800, 600))
ax  = Axis(fig[1, 1])

# Three data points that will shift visibly under different zoom levels.
pts = [Point2f(0.2, 0.2), Point2f(0.25, 0.22), Point2f(0.8, 0.8)]
scatter!(ax, pts)

# Force an initial render so the camera matrices are populated.
Makie.update_state_before_display!(fig)

# The correct data→pixel call for Makie ≥ 0.21 with the space-system API.
# Returns Point3f; [1:2] gives the 2-D pixel position in scene (viewport) space.
data_to_px(ax, p) = Point2f(Makie.project(ax.scene, :data, :pixel, p)[Vec(1, 2)])

let
    prev_px = [data_to_px(ax, p) for p in pts]
    println("Initial pixel positions (before first limits! call):")
    for (i, (p, px)) in enumerate(zip(pts, prev_px))
        println("  pt[$i] data=$p  →  px=$px")
    end
    println()

    limit_sets = [
        (0.0f0, 1.0f0, 0.0f0, 1.0f0),    # wide
        (0.1f0, 0.5f0, 0.1f0, 0.5f0),    # zoom in
        (0.18f0, 0.30f0, 0.18f0, 0.30f0), # tight zoom around pt1/pt2
    ]

    all_lagged = false
    for (step, lims) in enumerate(limit_sets)
        limits!(ax, lims...)
        Makie.update_state_before_display!(fig)
        px = [data_to_px(ax, p) for p in pts]

        println("Step $step: limits=$lims")
        for (i, (p, pxi)) in enumerate(zip(pts, px))
            changed = pxi ≈ prev_px[i] ? " (UNCHANGED — possible lag!)" : ""
            println("  pt[$i] data=$p  →  px=$pxi$changed")
        end

        # Sanity check: pts[1] and pts[2] are close in data space;
        # under tight zoom (step 3) their pixel distance should grow.
        if step == 3
            d_tight = norm(px[1] - px[2])
            d_wide  = norm(prev_px[1] - prev_px[2])
            println("  pixel separation pt[1]–pt[2]: tight=$(round(d_tight, digits=1))px  vs  step-$(step-1)=$(round(d_wide, digits=1))px")
            if d_tight > d_wide
                println("  OK pixel separation grew under zoom → projection reflects CURRENT limits (no lag)")
            else
                println("  FAIL pixel separation did NOT grow — projection may be lagging one frame")
                all_lagged = true
            end
        end
        prev_px = px
        println()
    end

    if all_lagged
        println("RESULT (a): LAGGED — projection does not reflect current limits after update_state_before_display!")
    else
        println("RESULT (a): OK — Makie.project(ax.scene, :data, :pixel, p)[Vec(1,2)] reflects")
        println("           the current frame's limits immediately after update_state_before_display!(fig).")
        println("           This call is safe to use in place.jl's per-frame loop.")
    end
end
println()

# ─────────────────────────────────────────────────────────────────────────────
# PROBE (b): warm-start damping
# ─────────────────────────────────────────────────────────────────────────────
println("=" ^ 60)
println("PROBE (b): warm-start damping")
println("=" ^ 60)

params  = RepelParams(; box_padding = 4.0, point_padding = 5.0,
                        only_move = :both, min_segment_length = 2.0)
solver  = ProjectionSolver(params)
bounds  = Rect2f(0, 0, 800, 600)

# Two nearly-overlapping anchors to force the solver to do real work,
# plus one isolated anchor that should settle quickly.
anchors = [Point2f(100, 100), Point2f(108, 104), Point2f(400, 400)]
sizes   = [Vec2f(60, 14),     Vec2f(50, 14),     Vec2f(40, 14)]

println("Running FRESH solve (init_state = nothing) …")
fresh = solve_cluster(solver, anchors, sizes, bounds; init_state = nothing)
println("  fresh.offsets = ", fresh.offsets)
println("  fresh.dropped = ", fresh.dropped)
println("  fresh.iter    = ", fresh.iter)
println()

println("Running WARM solve (init_state = fresh.offsets) …")
warm = solve_cluster(solver, anchors, sizes, bounds; init_state = fresh.offsets)
println("  warm.offsets  = ", warm.offsets)
println("  warm.dropped  = ", warm.dropped)
println("  warm.iter     = ", warm.iter)
println()

# Compare: a warm-start from an already-solved layout should be near-identical.
max_delta = maximum(norm(w - f) for (w, f) in zip(warm.offsets, fresh.offsets))
println("Max offset delta (warm vs fresh): $(round(max_delta, digits=4)) px")

if max_delta < 2.0
    println("RESULT (b): WARM-START HOLDS — warm.offsets ≈ fresh.offsets (delta < 2 px).")
    println("           Feeding a solved layout back as init_state relaxes rather than re-seeds.")
    println("           Settled labels will hold still between frames as the view pans/zooms.")
else
    println("RESULT (b): WARM-START DIVERGED — max delta = $(round(max_delta, digits=2)) px.")
    println("           This is unexpected; check the solver contract / init_state handling.")
end
println()

# ─────────────────────────────────────────────────────────────────────────────
# DECISION (c): raw solve_cluster vs TextRepelAlgorithm
# (printed summary — see comment below for rationale)
# ─────────────────────────────────────────────────────────────────────────────
println("=" ^ 60)
println("DECISION (c): API recommendation for place.jl")
println("=" ^ 60)
println("""
RECOMMENDATION: raw solve_cluster

Rationale: TextRepelAlgorithm is designed as a plug-in for Makie's annotation!
recipe — it owns the coordinate-space translation (solver-space ↔ render-space
via align_bias), the pin-mask derivation from textpositions_offset, and the
reset=false warm-start bookkeeping. In the Atlas animation loop, place.jl already
owns the pixel-projection step (Probe a) and must compute its own per-frame
overlaps for the golden harness regardless. Bypassing the recipe layer and calling
solve_cluster directly gives us:
  • full control of init_state (warm-start) without the align_bias translation
    that only makes sense for annotation!'s center-vs-align coordinate system;
  • the (offsets, dropped, iter, residual) NamedTuple we need for overlap stats
    without going through solve_stats(alg);
  • no dependency on Makie's compute graph / advance_optimization! machinery,
    which we don't use in a record() loop.
TextRepelAlgorithm adds value only if we want annotation! rendering — we don't.
""")

println("Spike complete.")
