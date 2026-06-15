# SPDX-License-Identifier: MIT
# loop.jl — seamless zoom-dive MP4 loop + hero still + loopframe extraction.
#
# HONESTY INVARIANT (preserved every frame):
#   Every label is measured by TextMeasure (via measure_boxes / _unit_box) and
#   placed by MakieTextRepel (solve_cluster, via solve_frame). No position is
#   hand-picked. The warm-start threads solved offsets from frame N into frame N+1
#   so the solver RELAXES rather than re-seeds — this is what makes the video smooth.
#
# Loop structure:
#   Frame 0 and frame N_FRAMES share the same camera_rect (p=0 ≡ p=1 by construction).
#   The camera is a geometric zoom (W_WIDE → W_TIGHT → W_WIDE) with smoothstep easing,
#   so velocity is zero at both ends — no pop at the seam.
#
# Rendering strategy (mirrors examples/tide/src/loop.jl):
#   Each frame is rendered from a FRESH Figure and saved as a PNG into a tmpdir;
#   ffmpeg stitches them. Reusing one CairoMakie axis over hundreds of frames leaks
#   ComputePipeline nodes and grows pathologically slow.

# ── ffmpeg helper ────────────────────────────────────────────────────────────

"Locate an ffmpeg binary: prefer Makie's vendored FFMPEG_jll, fall back to system PATH."
function _ffmpeg_cmd()
    try
        FFMPEG = Base.require(Base.PkgId(Base.UUID("b22a6f82-2f65-5046-a5b2-351ab43fb4e5"),
                                         "FFMPEG_jll"))
        return Base.invokelatest(FFMPEG.ffmpeg)    # a runnable Cmd
    catch
        exe = Sys.which("ffmpeg")
        exe === nothing && return nothing
        return `$exe`
    end
end

# ── Loop driver ──────────────────────────────────────────────────────────────

"""
    render_loop(path; n, fps, scale, crf) -> NamedTuple

Render the seamless N-frame zoom-dive loop to an MP4 (or GIF fallback if MP4 fails;
raw PNGs if no ffmpeg). Each frame is assembled fresh (fresh Figure — no scene-mutation
leak) with warm-start placement: the solved offsets from frame N seed frame N+1's solver
so labels glide rather than jump.

`scale` supersamples the page (default 2 for fast preview; use 4 for delivery).
`crf` controls H.264 quality (18 ≈ near-visually-lossless).

Returns `(; path, format, pagepx, scale, fps, crf, n_frames, bytes,
           warmstart_median_px, warmstart_p95_px)`.
The `warmstart_*` fields are the per-frame, per-label offset-delta statistics across the
dive (median and 95th-pct in px) — low values confirm warm-start is threading correctly.
"""
function render_loop(path::String = joinpath(@__DIR__, "..", "atlas-dive.mp4");
                     n::Int    = N_FRAMES,
                     fps::Int  = FPS,
                     scale::Real = 2,
                     crf::Int  = 18,
                     pagepx    = (1620, 1080))
    d = load_atlas_data()

    tmp = mktempdir()
    prev = Dict{Int,Vec2f}()   # warm-start: feature id → prior offset

    # Accumulate per-frame max offset-delta for the stability report.
    frame_deltas = Float32[]   # one value per frame (the MAX delta over shared labels)

    @info "render_loop: rendering $n frames …" pagepx scale fps crf

    for frame in 0:(n - 1)
        p  = frame / n
        fig, ax, af = assemble_frame(d, p; pagepx, prev)
        fp = af.fp

        # Per-frame warm-start stability: max |offset_new − offset_prev| over shared ids.
        if !isempty(prev) && !isempty(fp.ids)
            shared_deltas = Float32[]
            for (k, id) in enumerate(fp.ids)
                if haskey(prev, id)
                    old = prev[id]; new = fp.offsets[k]
                    push!(shared_deltas, sqrt((new[1]-old[1])^2 + (new[2]-old[2])^2))
                end
            end
            !isempty(shared_deltas) && push!(frame_deltas, maximum(shared_deltas))
        end

        # Carry offsets to the next frame (warm-start). Pin nothing — labels must adapt
        # as the camera zooms and their pixel-space boxes grow.
        prev = Dict{Int,Vec2f}(fp.ids[k] => fp.offsets[k] for k in eachindex(fp.ids))

        # Draw all layers.
        w     = view_width(p)
        n_placed = count(!, fp.dropped)
        metrics  = "w $(round(w; digits=2))° · $(n_placed) placed"

        draw_basemap!(ax, d)
        draw_hydrography!(ax, d, w)
        draw_areals!(ax, af.areals)
        draw_labels!(ax, d, af)
        draw_chrome!(ax, fig, d; metrics, w_deg = w, pagepx)

        save(joinpath(tmp, "f$(lpad(frame, 4, '0')).png"), fig; px_per_unit = scale)
    end

    # Warm-start stability report.
    med95 = if !isempty(frame_deltas)
        sort!(frame_deltas)
        med = frame_deltas[div(length(frame_deltas), 2) + 1]
        p95 = frame_deltas[clamp(round(Int, 0.95 * length(frame_deltas)), 1, end)]
        @info "warm-start offset-delta distribution (px/frame)" median=round(med; digits=1) p95=round(p95; digits=1)
        (med, p95)
    else
        (NaN32, NaN32)
    end

    # ffmpeg stitch.
    ff = _ffmpeg_cmd()
    format = :mp4
    if ff === nothing
        @warn "no ffmpeg found — leaving frame PNGs in $tmp"
        return (; path = tmp, format = :png_frames, pagepx, scale, fps, crf,
                n_frames = n, bytes = 0,
                warmstart_median_px = med95[1], warmstart_p95_px = med95[2])
    end

    pat = joinpath(tmp, "f%04d.png")
    vf  = "scale=trunc(iw/2)*2:trunc(ih/2)*2"   # force even dims for yuv420p
    enc = `$ff -y -framerate $fps -i $pat -c:v libx264 -preset slow -crf $crf
               -pix_fmt yuv420p -vf $vf -movflags +faststart $path`
    try
        run(pipeline(enc; stdout = devnull, stderr = devnull))
    catch err
        @warn "MP4 encode failed; falling back to GIF" exception = (err,)
        path = replace(path, r"\.mp4$" => ".gif")
        gif  = `$ff -y -framerate $fps -i $pat -vf $vf $path`
        run(pipeline(gif; stdout = devnull, stderr = devnull))
        format = :gif
    end
    rm(tmp; recursive = true, force = true)

    bytes = isfile(path) ? filesize(path) : 0
    @info "render_loop done" path format bytes n_frames=n fps scale crf

    return (; path, format, pagepx, scale, fps, crf, n_frames = n, bytes,
            warmstart_median_px = med95[1], warmstart_p95_px = med95[2])
end

# ── Hero still ───────────────────────────────────────────────────────────────

"""
    render_hero(path; p, scale) -> NamedTuple

One high-resolution still at the dense mid-dive phase (default p=0.40 — halfway through
the inward zoom, many labels visible). Cold placement (no warm-start) — fine for a still.

Returns `(; path, pagepx, scale, p, bytes)`.
"""
function render_hero(path::String = joinpath(@__DIR__, "..", "atlas-hero.png");
                     p::Real     = 0.33,
                     scale::Real = 8,
                     pagepx      = (1620, 1080))
    out = _dev_still(p, path; pagepx)
    bytes = isfile(path) ? filesize(path) : 0
    @info "render_hero done" path scale p bytes
    return (; path = out, pagepx, scale, p, bytes)
end

# ── Loopframe extractor ──────────────────────────────────────────────────────

"""
    extract_loopframes(mp4path; n_frames, dir, fps) -> Vector{String}

Extract `n_frames` evenly-spaced frames from `mp4path` as PNGs named
`loopframe-01.png` … `loopframe-NN.png` in `dir`. Uses ffmpeg's `select` filter.
Returns the list of written paths.
"""
function extract_loopframes(mp4path::String;
                            n_frames::Int = 8,
                            dir::String   = dirname(mp4path),
                            fps::Int      = FPS,
                            total::Int    = N_FRAMES)
    ff = _ffmpeg_cmd()
    ff === nothing && error("no ffmpeg — cannot extract loopframes")
    mkpath(dir)
    paths = String[]
    step  = total / n_frames    # even fractional step across all frames
    for i in 1:n_frames
        t   = (i - 1) * step / fps    # time in seconds
        out = joinpath(dir, "loopframe-$(lpad(i, 2, '0')).png")
        cmd = `$ff -y -ss $(round(t; digits=4)) -i $mp4path -vframes 1 $out`
        run(pipeline(cmd; stdout = devnull, stderr = devnull))
        push!(paths, out)
    end
    return paths
end

# ── Warm-start delta probe (test-accessible) ─────────────────────────────────

"""
    warmstart_delta_stats(n_frames; pagepx) -> (median_px, p95_px)

Render `n_frames` consecutive frames (cold→warm), collect the per-label offset-delta
for shared labels between consecutive frames, and return (median, p95) in px.
Exported for the test suite.
"""
function warmstart_delta_stats(n_frames::Int = 3; pagepx = (1620, 1080))
    d    = load_atlas_data()
    prev = Dict{Int,Vec2f}()
    all_deltas = Float32[]
    for frame in 0:(n_frames - 1)
        p = frame / N_FRAMES
        _, _, af = assemble_frame(d, p; pagepx, prev)
        fp = af.fp
        if !isempty(prev)
            for (k, id) in enumerate(fp.ids)
                if haskey(prev, id)
                    old = prev[id]; new = fp.offsets[k]
                    push!(all_deltas, sqrt((new[1]-old[1])^2 + (new[2]-old[2])^2))
                end
            end
        end
        prev = Dict{Int,Vec2f}(fp.ids[k] => fp.offsets[k] for k in eachindex(fp.ids))
    end
    isempty(all_deltas) && return (0.0f0, 0.0f0)
    sort!(all_deltas)
    med = all_deltas[div(length(all_deltas), 2) + 1]
    p95 = all_deltas[clamp(round(Int, 0.95 * length(all_deltas)), 1, length(all_deltas))]
    return (med, p95)
end
