# loop.jl — the seamless MP4 loop + sample-frame + ghosted-thumbnail renderers.
#
# All reuse `draw_frame!` from render.jl. The loop bundle grows-to-fit on ALL 6 directions so the
# region (Wpx AND Hpx) is CONSTANT across every frame — the text never jumps to a different region
# size; only WHICH band each word sits on changes as the wall kneads through. Frame N_FRAMES ≡
# frame 0 by construction (`press_at` is periodic), so the loop is seamless with no crossfade.

const LOOP_BODY_FONT = CASLON
const LOOP_FONTSIZE  = 11.0
_loop_backend(font, size) = MakieBackend(; font = font, fontsize = Float64(size), px_per_unit = 1)

# the prep bundle for every artifact (hero, loop, samples, thumb): all-6 grow ⇒ ONE constant box.
_loop_bundle() = prepare_tide(_loop_backend; body_font = LOOP_BODY_FONT,
                              fontsize = LOOP_FONTSIZE, grow_dirs = DIRECTIONS)

# The peak (deepest) frame of a press. The swell crests at u=0.5 (see schedule.jl), i.e. the
# local frame FRAMES_PER_PRESS÷2 within press `p` (0..5), or for a named direction.
peak_frame(p::Int) = p * FRAMES_PER_PRESS + FRAMES_PER_PRESS ÷ 2
peak_frame(dir::Symbol) = peak_frame(findfirst(==(dir), DIRECTIONS) - 1)

# Locate an ffmpeg binary: prefer Makie's vendored FFMPEG_jll, fall back to system PATH.
function _ffmpeg_cmd()
    try
        FFMPEG = Base.require(Base.PkgId(Base.UUID("b22a6f82-2f65-5046-a5b2-351ab43fb4e5"),
                                        "FFMPEG_jll"))
        return Base.invokelatest(FFMPEG.ffmpeg)    # a runnable `Cmd`
    catch
        exe = Sys.which("ffmpeg")
        exe === nothing && return nothing
        return `$exe`
    end
end

"""
    render_loop(path="examples/tide/tide-loop.mp4"; scale=4, fps=60, n=N_FRAMES, crf=18) -> NamedTuple

Render the seamless N_FRAMES-frame loop. ONE `prepare_tide` (all-6 grow ⇒ constant region), then
each `frame in 0:n-1` is drawn with `draw_frame!` and saved as a PNG into a scratch dir; ffmpeg
stitches them into an MP4. (We render each frame from a FRESH figure rather than reuse one Makie
scene via `record` + `empty!` — repeatedly mutating one CairoMakie axis over hundreds of frames
leaks ComputePipeline nodes and grows pathologically slow.) Seamless by construction (frame n ≡ 0,
since `press_at` is periodic). Falls back to GIF if MP4 encode fails; if no ffmpeg is found at
all, leaves the frame PNGs and reports `format=:png_frames`.

ANTI-ALIASING: frames render at `scale=4` (supersampled) and encode at a LOW CRF (~18, near
visually lossless) with `yuv420p` + even dimensions, so the thin coral line + small type don't
shimmer under h264.

Returns `(; path, format, pageW, pageH, scale, fps, crf, n_frames, bytes, Wpx, Hpx)`.
"""
function render_loop(path::String = joinpath(@__DIR__, "..", "tide-loop.mp4");
                     scale::Real = 4, fps::Int = 60, n::Int = N_FRAMES, crf::Int = 18)
    pb = _loop_bundle()
    fl0 = _layout_at(pb, :W, 0.0, 0.0)           # rest frame defines the (constant) page size
    pageW, pageH = _page_size(fl0)

    # render each frame to its own PNG (fresh figure ⇒ no scene-mutation leak).
    tmp = mktempdir()
    for frame in 0:(n - 1)
        fl = frame_layout(pb, frame)
        fig, ax = _new_axis(pageW, pageH)
        draw_frame!(ax, fl, pb; pageH = pageH)
        save(joinpath(tmp, "f$(lpad(frame, 4, '0')).png"), fig; px_per_unit = scale)
    end

    ff = _ffmpeg_cmd()
    if ff === nothing
        @warn "no ffmpeg found; leaving frame PNGs in $tmp"
        return (; path = tmp, format = :png_frames, pageW, pageH, scale, fps, crf,
                n_frames = n, bytes = 0, pb.Wpx, pb.Hpx)
    end

    pat  = joinpath(tmp, "f%04d.png")
    vf   = "scale=trunc(iw/2)*2:trunc(ih/2)*2"      # force even dims (yuv420p needs them)
    format = :mp4
    # H.264, yuv420p (broad player compat), low CRF (high quality), slow preset for crisp edges.
    enc = `$ff -y -framerate $fps -i $pat -c:v libx264 -preset slow -crf $crf -pix_fmt yuv420p -vf $vf -movflags +faststart $path`
    try
        run(pipeline(enc; stdout = devnull, stderr = devnull))
    catch err
        @warn "MP4 encode failed; falling back to GIF" exception = (err,)
        path = replace(path, r"\.mp4$" => ".gif")
        gif = `$ff -y -framerate $fps -i $pat -vf $vf $path`
        run(pipeline(gif; stdout = devnull, stderr = devnull))
        format = :gif
    end
    rm(tmp; recursive = true, force = true)

    bytes = isfile(path) ? filesize(path) : 0
    return (; path, format, pageW, pageH, scale, fps, crf, n_frames = n, bytes, pb.Wpx, pb.Hpx)
end

"""
    render_samples(dir="examples/tide/_frames"; scale=4) -> Vector{NamedTuple}

Render the inspection PNGs — rest + the six press peaks (W, E, SW, NE, SE, NW) — so the wavy
tide-line and the corner kneads can be eye-checked in every direction. Uses the SAME constant-box
loop bundle as `render_loop`/`render_hero`, so these frames are exactly what the MP4 shows.
"""
function render_samples(dir::String = joinpath(@__DIR__, "..", "_frames"); scale::Real = 4)
    mkpath(dir)
    pb = _loop_bundle()
    picks = vcat([(0, "rest")],
                 [(peak_frame(d), "$(d)-peak") for d in DIRECTIONS])
    out = NamedTuple[]
    for (frame, label) in picks
        fl = frame_layout(pb, frame)
        path = joinpath(dir, "frame$(lpad(frame, 3, '0')).png")
        r = _render_still(fl, pb, path; scale = scale)
        push!(out, (; frame, label, fl.dir, depth = round(fl.depth, digits = 3),
                    b = round(fl.b, digits = 2), n_tide = length(fl.tideline_pts),
                    n_placements = length(fl.placements), r.path, r.pageW, r.pageH))
    end
    return out
end

"""
    render_thumb(path="examples/tide/tide-thumb.png"; scale=8) -> NamedTuple

The ghosted long-exposure thumbnail. The solid SW-peak frame stays crisp in front; behind it,
a few earlier SW depths are ghosted as **tide-line trails + the lit "kneads" only** (NOT the full
body paragraph — ghosting the whole block read muddy). So you see the coral waterline fan out from
shallow→deep and the word "kneads" trace its migration path, with the legible solid frame on top.
"""
function render_thumb(path::String = joinpath(@__DIR__, "..", "tide-thumb.png"); scale::Real = 8)
    pb    = _loop_bundle()
    front = frame_layout(pb, peak_frame(:SW))     # solid SW peak (matches the hero)

    # earlier SW depths along the press's loading swell. Back→front: shallow→deep, alpha rising,
    # so the trails fan out toward the solid front. phase = the SW peak's phase (visual match).
    _, _, ph = press_at(peak_frame(:SW))
    ghost_depths = [0.30, 0.55, 0.80]             # back → front
    ghost_alphas = [0.12, 0.16, 0.20]             # rising toward the front

    pageW, pageH = _page_size(front)
    fig, ax = _new_axis(pageW, pageH)

    # GHOST ONLY the tide-line + the lit "kneads" word for each earlier depth (back→front).
    for (d, a) in zip(ghost_depths, ghost_alphas)
        gl = _layout_at(pb, :SW, d, ph)
        _draw_lit_only!(ax, gl, (CORAL, a))       # the migrating "kneads" trail
        draw_tideline!(ax, gl; color = CORAL, linewidth = 1.4, alpha = a)
    end
    # solid front frame (full body + tide-line + caption) on top, crisp.
    draw_frame!(ax, front, pb; pageH = pageH)

    save(path, fig; px_per_unit = scale)
    bytes = isfile(path) ? filesize(path) : 0
    return (; path, pageW, pageH, scale, n_ghosts = length(ghost_depths), bytes,
            front.Wpx, front.Hpx)
end

# draw ONLY the lit "kneads" run(s) of a frame, in `col` (an (color, alpha) tuple) — the
# thumbnail's motion trail. Mirrors draw_body!'s em-dash split but skips every non-lit word.
function _draw_lit_only!(ax, fl, col)
    segs    = fl.segs
    backend = fl.backend
    for i in fl.lit_idx
        p  = fl.placements[i]
        s  = segs[p.segment_index].str
        x0 = fl.region_x + fl.justx[p]
        yb = _Y(fl.region_y + p.y)
        di = findfirst('—', s)
        head = (di !== nothing && startswith(_norm(s), "kneads")) ? s[1:prevind(s, di)] : s
        text!(ax, Point2f(x0, yb); text = head, color = col, font = CASLON,
              fontsize = LOOP_FONTSIZE, align = (:left, :baseline), markerspace = :data)
    end
    return ax
end
