# SPDX-License-Identifier: MIT
# frame.jl — PREPARE-ONCE core, the heart of the piece. The font engine is touched EXACTLY ONCE
# (`prepare_tide`); every one of the N_FRAMES frames is then pure arithmetic over the cached
# widths (`frame_layout`), calling `shape_pack` exactly once per frame. This measure-once /
# lay-out-many split IS the thesis the demo proves — and test_frame.jl makes it a guarantee.

# Test-instrumentable hook for the per-frame pack. Production calls the real `shape_pack`; the
# honesty test (1 prepare / N_FRAMES shape_pack) swaps in a counting wrapper. NOT exported.
const PACK_HOOK = Ref{Any}(shape_pack)
_packcall(args...; kwargs...) = PACK_HOOK[](args...; kwargs...)

"""
    prepare_tide(make_backend; body_font, fontsize=11.0) -> prep_bundle

The ONLY font-touching phase. Calls `prepare` exactly once on `TIDE_TEXT`, then caches
everything the per-frame math needs: the `Prepared`, per-segment advance widths, metrics,
the natural space advance, `floor_w`, the rest region width `Wpx`, `line_advance`, the grown
region height `Hpx`, and the per-direction max depth `d_max`. `make_backend(font, size) ->
backend` is the backend factory (MakieBackend for render, MonospaceBackend for tests).

Returns a NamedTuple `prep_bundle` consumed by `frame_layout`.
"""
function prepare_tide(make_backend; body_font::String, fontsize::Float64 = 11.0,
                      grow_dirs = DIRECTIONS)
    line_advance = round(1.45 * fontsize)        # fixed grid: 16px at 11px body

    # ---- the ONE font-touching prepare (the thesis: measure once). Setup-time only. --------
    backend = make_backend(body_font, fontsize)
    prep    = prepare(backend, TIDE_TEXT)
    segs    = prep.segments
    asc     = prep.metrics.ascent
    desc    = prep.metrics.descent

    # cache per-word advance widths once: segment_index => width. (No per-band measure.)
    wwidth = Dict{Int,Float64}()
    for (i, s) in enumerate(segs)
        s.kind === :word && (wwidth[i] = s.width)
    end
    # natural space advance (over-stretch guard) — from a measured :space segment.
    natspace = 0.0
    for s in segs
        if s.kind === :space; natspace = s.width; break; end
    end

    # floor_w = 32 × advance of "0"; reference char widths for the rest measure. A single-char
    # input tokenizes to one :word segment (`segments[1]`) for any backend's tokenizer.
    zero_w  = prepare(backend, "0").segments[1].width
    floor_w = 32 * zero_w
    nchar_w = prepare(backend, "n").segments[1].width

    # REST width: prose justifies full-time, so pick a comfortable MEASURE (~chars per line).
    target_cpl = 46
    Wpx = max(floor_w + 120.0, ceil(target_cpl * nchar_w))
    # TIGHT, BALANCED margins (~40px all sides). The page is sized to the content bbox + these
    # margins (see _page_size), so the text + tide fill the frame with little dead vertical space.
    region_x, region_y = 40.0, 40.0
    margin = 40.0

    n_words = count(s -> s.kind === :word, segs)

    # PASS 1: pack into the full-width rest rectangle to learn the natural block height. (One
    # extra setup shape_pack — NOT counted against the per-frame honesty budget.)
    probe_rows  = 4000
    rect_raster = trues(probe_rows, ceil(Int, Wpx))
    probe = shape_pack(prep, raster_chord_fn(rect_raster, CELL);
        line_advance = line_advance, min_chord_width = floor_w,
        overflow_strategy = :widest_row, fill = :widest)
    last_y  = isempty(probe.placements) ? line_advance : maximum(p.y for p in probe.placements)
    block_h = last_y + desc

    # floor_y = the rest text's REAL bottom edge (local coords). Threaded through for reference;
    # the bottom-corner diagonals instead anchor their DEEP end to `deep_y` (solved below) so the
    # diagonal reaches max depth at the actual deepest line text occupies — not the rest bottom,
    # which would leave the displaced last lines uncut.
    floor_y = block_h
    top_y   = 0.0                                    # text top (anchor for the NW/NE diagonals)

    # per-direction max depth (d_max). All 6 directions rake along the WIDTH axis (W/E are
    # vertical walls; the four diagonals are corner wedges that eat horizontally), so a single
    # width floor governs every one: leave ≥ floor_w + the wave amplitude + a hair. PRESS DEEP:
    # ~5.5 line-advances in, floor-capped.
    width_cap    = max(0.0, Wpx - floor_w - WAVE_A - 2.0)
    width_target = 5.5 * line_advance
    d = clamp(min(width_target, width_cap), 0.0, Wpx)
    d_max = Dict{Symbol,Float64}(dir => d for dir in DIRECTIONS)

    # `deep_y` anchors the DEEP end of the bottom-corner diagonal — the straight line must reach
    # its MAX depth (b) at the ACTUAL deepest line text occupies, so the last lines stay the most
    # compressed. But the SW bite pushes text DOWN, so the real last line depends on deep_y
    # itself — a fixed point. Solve it: pack an SW@d_max, read the true last baseline+desc, set
    # deep_y to it, re-pack, iterate to a stable value. Setup-time only (not per-frame).
    pack_sw(H, dyc) = shape_pack(prep,
        raster_chord_fn(region_mask(Wpx, H, :SW, d, 0.0;
            cell = CELL, line_advance = line_advance,
            floor_y = floor_y, deep_y = dyc, top_y = top_y), CELL);
        line_advance = line_advance, min_chord_width = floor_w,
        overflow_strategy = :widest_row, fill = :widest)

    Hpx = ceil(block_h + 1.5 * line_advance)         # headroom for the displaced reflow
    deep_y = block_h                                  # seed at the rest text bottom
    for _ in 1:40                                     # fixed-point iteration on deep_y
        pk = pack_sw(Hpx, deep_y)
        isempty(pk.placements) && break
        last_bot = maximum(p.y for p in pk.placements) + desc
        Hpx = max(Hpx, ceil(last_bot + 0.5 * line_advance))   # ensure the box holds it
        abs(last_bot - deep_y) < 0.5 && (deep_y = last_bot; break)
        deep_y = last_bot
    end

    # grow Hpx so EVERY direction at d_max places all words (no truncation) at this deep_y.
    for _ in 1:80                                    # safety cap
        ok = true
        for dir in grow_dirs
            r  = region_mask(Wpx, Hpx, dir, d_max[dir], 0.0;
                             cell = CELL, line_advance = line_advance,
                             floor_y = floor_y, deep_y = deep_y, top_y = top_y)
            pk = shape_pack(prep, raster_chord_fn(r, CELL);
                line_advance = line_advance, min_chord_width = floor_w,
                overflow_strategy = :widest_row, fill = :widest)
            if length(pk.placements) < n_words
                ok = false; break
            end
        end
        ok && break
        Hpx += line_advance
    end

    return (; prep, segs, backend, wwidth, natspace, asc, desc, line_advance,
            floor_w, Wpx, Hpx, floor_y, deep_y, top_y, region_x, region_y, margin, n_words, d_max,
            body_font, fontsize)
end

"""
    frame_layout(prep_bundle, frame::Int) -> NamedTuple

Pure per-frame arithmetic — NO prepare. Resolves `press_at(frame)`, builds the wavy region
mask, packs it with EXACTLY ONE `shape_pack`, runs the demo-side per-band justify, and returns
the placements, justified x, bands, the coral tideline points + per-vertex alpha, lit indices,
overflow list, and geometry. `prep_bundle` comes from `prepare_tide`.

Fields: `placements, justx, band_order, bands, band_interval, tideline_pts, tideline_alpha,
lit_idx, overflowed, segs, backend, asc, desc, line_advance, region_x, region_y, margin, Wpx,
Hpx, b, dir, depth, phase, pad, n_words, all_placed, n_justified, n_ragged`.
"""
function frame_layout(prep_bundle, frame::Int)
    dir, depth, phase = press_at(frame)
    return _layout_at(prep_bundle, dir, depth, phase)
end

# Shared layout body: build the mask for an EXPLICIT (dir, depth, phase) and lay out. Used by
# `frame_layout` for scheduled frames, and called directly for off-schedule layouts — the loop's
# rest frame (page-size probe) and the thumbnail's ghost-trail depths.
function _layout_at(prep_bundle, dir::Symbol, depth::Float64, phase::Float64)
    pb = prep_bundle
    segs = pb.segs; asc = pb.asc; desc = pb.desc
    line_advance = pb.line_advance
    Wpx = pb.Wpx; Hpx = pb.Hpx; floor_w = pb.floor_w
    region_x = pb.region_x; region_y = pb.region_y

    b = depth * pb.d_max[dir]                        # actual depth in px for this frame
    floor_y = pb.floor_y; deep_y = pb.deep_y; top_y = pb.top_y

    # THE per-frame pack — exactly one shape_pack.
    raster   = region_mask(Wpx, Hpx, dir, b, phase;
                           cell = CELL, line_advance = line_advance,
                           floor_y = floor_y, deep_y = deep_y, top_y = top_y)
    chord_fn = raster_chord_fn(raster, CELL)
    packed   = _packcall(pb.prep, chord_fn;
        line_advance = line_advance, min_chord_width = floor_w,
        overflow_strategy = :widest_row, fill = :widest)

    placements = packed.placements
    overflowed = packed.overflowed
    all_placed = length(placements) >= pb.n_words

    # group placements into bands (lines) by baseline y, preserving reading order. `shape_pack`
    # returns flat placements; each distinct y is one line.
    band_order = Float64[]
    bands = Dict{Float64,Vector{Placement}}()
    for p in placements
        if !haskey(bands, p.y)
            bands[p.y] = Placement[]
            push!(band_order, p.y)
        end
        push!(bands[p.y], p)
    end
    sort!(band_order)

    band_interval = make_band_interval(chord_fn, asc, line_advance)

    # DEMO-SIDE justify: rewrite each word's x flush to both margins. This adds NO engine
    # surface — it only rewrites `Placement.x`, returned as the `justx` lookup (see justify.jl).
    justx, n_justified, n_ragged =
        justify_bands(band_order, bands, band_interval, segs, pb.wwidth, pb.natspace)

    # indices (into placements) of the lit "kneads" word(s), so the render can glow them coral.
    lit_idx = [i for (i, p) in enumerate(placements) if has_lit(segs[p.segment_index].str)]

    # tide-line: the coral waterline polyline + per-vertex alpha. Driven by KNOWN wall geometry
    # (not the placed words), faded at the block edges so it reads as a longer wave (see below).
    pad = 13.0                                       # gutter (px) the line sits OUTSIDE the type
    block_bot = isempty(band_order) ? floor_y : (band_order[end] + desc)   # this frame's text bottom
    tideline_pts, tideline_alpha =
        _tideline(dir, b, phase, region_x, region_y, Wpx, Hpx, deep_y, top_y, block_bot,
                  line_advance, pad)

    return (; placements, justx, band_order, bands, band_interval,
            tideline_pts, tideline_alpha,
            lit_idx, overflowed, segs, backend = pb.backend, asc, desc, line_advance,
            region_x, region_y, margin = pb.margin, Wpx, Hpx, b, dir, depth, phase,
            pad, n_words = pb.n_words, all_placed, n_justified, n_ragged)
end

# Trace the coral waterline for the active direction as a LONG, edge-faded wavy polyline driven
# by KNOWN geometry (the wall's extent against the text), NOT by the placed words. Returns
# `(pts, alpha)`:
#   • the line is sampled along local y over an EXTENDED range (past each opaque end) so its true
#     endpoints sit out in empty space and the wave reads as longer than the block — it never
#     visibly pops in or falls short as the depth `b` grows;
#   • `alpha` is a per-vertex opacity that is full only where the line laps the block AND the wall
#     is at least a gutter deep (so the stroke sits strictly OUTSIDE the type), fading to 0 both
#     past the block edges and wherever the wall gets too shallow to clear the text. So the line
#     never crosses into glyphs; it dissolves where there is no real wall to draw. RENDER-only.
const TIDE_FADE_LH = 1.0          # block-edge fade ramp width, in line-heights
const TIDE_EXT_LH  = 3.0          # extend the polyline this many line-heights past each span end
const TIDE_MIN_B   = 0.5          # below this depth (px) the tide-line is not drawn (full recede)

# Opacity tuning for the CARDINAL walls (:W, :E). Their wall has uniform depth and always sits a
# gutter OUTSIDE the reflowed text edge (it never clips the type), so the corner taper-gate would
# wrongly hide them until deep. Instead the whole cardinal line eases in with a smooth depth ramp
# `dfade(b)`: from `TIDE_MIN_B` up to full opacity by `TIDE_CARD_B1`, and — being a pure function
# of `b` — symmetric on the withdraw, so it fades out with no pop. `B1` is small so the tide is
# essentially full opacity BEFORE the text visibly reformats (tide first, then the type feels it).
const TIDE_CARD_B1   = 6.0        # depth (px) at which the cardinal line reaches full opacity
const TIDE_CARD_LEAD = 22.0       # cardinal line's margin offset (px); leads further out than `pad`

# smoothstep ∈ [0,1] (Hermite 3t²−2t³) for a soft, pop-free opacity ramp.
_smoothstep01(t) = (t <= 0.0) ? 0.0 : (t >= 1.0) ? 1.0 : t * t * (3.0 - 2.0 * t)

function _tideline(dir, b, phase, region_x, region_y, Wpx, Hpx, deep_y, top_y, block_bot,
                   line_advance, pad)
    pts   = Point2f[]
    alpha = Float64[]
    # FULL RECEDE: draw NOTHING below a small depth epsilon, so a near-zero withdraw tail (and the
    # exact trough at every loop boundary) leaves a bare rest block with no leftover coral line.
    b <= TIDE_MIN_B && return pts, alpha
    λ   = wave_L(line_advance)
    dy  = Float64(deep_y); ty = Float64(top_y)
    bb  = Float64(block_bot)
    ext  = TIDE_EXT_LH  * line_advance
    fade = TIDE_FADE_LH * line_advance

    # Per direction, define:
    #   xof(yl)       — the line's page-x at local y (cut edge offset OUT by the gutter `pad`);
    #   wdepth(yl)    — how far the wall has advanced into the text at yl (its "depth" there);
    #   yo0, yo1      — the block-edge span over which the line laps the type.
    # The line is OPAQUE only where it's inside [yo0,yo1] AND wdepth ≥ pad (a full gutter clear of
    # the text). It fades over `fade` past the block edges, and fades as the wall shallows below
    # `pad` (so the tapering corner tips dissolve instead of crossing into glyphs).
    local xof, wdepth, yo0, yo1
    if dir === :W
        xof    = yl -> region_x + (b + WAVE_A * sin(2π * yl / λ + phase)) - TIDE_CARD_LEAD
        wdepth = yl -> b                          # vertical wall: uniform full depth
        yo0, yo1 = 0.0, bb
    elseif dir === :E
        xof    = yl -> region_x + (Wpx - b + WAVE_A * sin(2π * yl / λ + phase)) + TIDE_CARD_LEAD
        wdepth = yl -> b
        yo0, yo1 = 0.0, bb
    elseif dir in (:SW, :SE)
        left = dir === :SW
        xof  = yl -> begin
            ex = _diag_edge(dir, yl, b, phase, Wpx, deep_y, top_y, line_advance)
            region_x + ex + (left ? -pad : pad)
        end
        # straight diagonal: depth ramps 0 at (deep_y-b) up to b at deep_y (clamped ≥0).
        wdepth = yl -> max(0.0, yl - (dy - b))
        yo0, yo1 = dy - b - WAVE_A, bb
    else  # :NW, :NE
        left = dir === :NW
        xof  = yl -> begin
            ex = _diag_edge(dir, yl, b, phase, Wpx, deep_y, top_y, line_advance)
            region_x + ex + (left ? -pad : pad)
        end
        # straight diagonal: depth is b at top_y, ramps down to 0 at top_y+b (clamped ≥0).
        wdepth = yl -> max(0.0, b - (yl - ty))
        yo0, yo1 = ty, ty + b + WAVE_A
    end

    # Wall-depth fade `wfade(yl)`:
    #   • the four CORNERS taper, so they fade out where they get shallower than the gutter:
    #     opacity ramps from 0 at wdepth=pad to 1 at wdepth=pad+fade, so the tapering tips
    #     dissolve instead of crossing into glyphs;
    #   • the two CARDINALS (:W,:E) have uniform depth and never clip the type, so they use the
    #     whole-line depth ramp `dfade(b)` instead (see TIDE_CARD_B1 above).
    corner = dir in (:SW, :SE, :NW, :NE)
    dfade  = _smoothstep01((b - TIDE_MIN_B) / (TIDE_CARD_B1 - TIDE_MIN_B))
    wfade(yl) = corner ? clamp((wdepth(yl) - pad) / fade, 0.0, 1.0) : dfade

    # extended sample range, with per-vertex alpha = (block-edge fade) × (wall-depth fade).
    ya  = yo0 - ext
    yb_ = yo1 + ext
    n   = 360
    for yl in range(ya, yb_; length = n)
        aedge = if yl < yo0
            clamp(1.0 - (yo0 - yl) / fade, 0.0, 1.0)
        elseif yl > yo1
            clamp(1.0 - (yl - yo1) / fade, 0.0, 1.0)
        else
            1.0
        end
        push!(pts, Point2f(xof(yl), -(region_y + yl)))
        push!(alpha, aedge * wfade(yl))
    end
    return pts, alpha
end

# local-x edge of a diagonal cut at local y — a single straight diagonal (slope 1) matching
# region_mask exactly, so the coral line traces the bite. Bottom corners (SW/SE) ramp
# from 0 up to b at `deep_y` (the deepest occupied line); top corners (NW/NE) ramp from b at
# `top_y` down to 0. The sine WAVE_A rides on the straight path. Returns the absolute cut x.
function _diag_edge(dir, yl, b, phase, Wpx, deep_y, top_y, line_advance)
    λ = wave_L(line_advance)
    wav(t) = WAVE_A * sin(2π * t / λ + phase)
    dy = Float64(deep_y); ty = Float64(top_y); Wf = Float64(Wpx)
    if dir === :SW
        return (yl - (dy - b)) + wav(yl)                # distance from LEFT, deepest at deep_y
    elseif dir === :SE
        return Wf - ((yl - (dy - b)) + wav(yl))         # x = W - distance from RIGHT
    elseif dir === :NW
        return (b - (yl - ty)) + wav(yl)                # distance from LEFT, deepest at top_y
    else  # :NE
        return Wf - ((b - (yl - ty)) + wav(yl))
    end
end
