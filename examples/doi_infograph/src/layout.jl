# SPDX-License-Identifier: MIT
# #F2 — DOIInfograph adaptive layout engine.
#
# Every primitive is measurement-driven via MakieBackend(; font, fontsize, px_per_unit=1)
# (CLAUDE.md: px_per_unit=1 to match Makie markerspace). `measure(b, text)` returns px at
# the backend's baked-in fontsize, so fontsize search = constructing a new backend per
# iteration. `measure`/`font_metrics` are imported at the module top (NOT exported by
# TextMeasure — backend contract).

const SANS  = "DejaVu Sans"        # pinned (CI font-pinning); see #J
const SERIF = "Liberation Serif"

"A px_per_unit=1 MakieBackend at `fs` px in font family `fam`."
_backend(fam::AbstractString, fs::Real) = MakieBackend(; font=fam, fontsize=Float64(fs), px_per_unit=1)

# ---------------------------------------------------------------------------
# Title autoshrink  (M2: fits(fs_min) guard + explicit clip contract)
# ---------------------------------------------------------------------------

# Ellipsize `lines` down to ≤2 lines that fit `box_width` at `backend`.
function _clip_to_two(lines::Vector{String}, backend, box_width::Real)
    length(lines) <= 2 && return lines
    first_line = lines[1]
    second = lines[2]
    ell = "…"
    # greedily append following words to the 2nd line, then trim to fit with an ellipsis
    rest = join(lines[2:end], " ")
    words = split(rest)
    acc = String[]
    for w in words
        cand = isempty(acc) ? w : join(vcat(acc, w), " ")
        if measure(backend, cand * ell) > box_width
            break
        end
        push!(acc, String(w))
    end
    second = (isempty(acc) ? "" : join(acc, " ")) * ell
    return [first_line, second]
end

"""
    title_autoshrink(title; box_width, fs_min=14.0, fs_max=48.0, tol=0.5)
        -> (; fontsize, nlines, lines, clipped)

Largest fontsize in `[fs_min, fs_max]` (±`tol`) such that `title` wraps to ≤2 lines in
`box_width`. Contract: the returned `lines` is ALWAYS ≤2 lines and never overflows
`box_width`. If even `fs_min` needs 3+ lines, returns `fs_min` with the 2nd line
ellipsized (`clipped=true`). Destructures positionally as `(fontsize, nlines) = ...`
(NamedTuple iterates its values in field order).
"""
function title_autoshrink(title::AbstractString; box_width::Real,
                          fs_min::Real=14.0, fs_max::Real=48.0, tol::Real=0.5)
    lay_at(fs) = layout(prepare(_backend(SANS, fs), title); max_width=box_width)
    fits(fs)   = length(lay_at(fs).lines) <= 2
    lo, hi = Float64(fs_min), Float64(fs_max)

    if fits(hi)                                   # already fits at max size
        lay = lay_at(hi)
        return (; fontsize=hi, nlines=length(lay.lines),
                  lines=String[l.str for l in lay.lines], clipped=false)
    end
    if !fits(lo)                                  # never fits in ≤2 lines → clamp + clip
        lay  = lay_at(lo)
        kept = _clip_to_two(String[l.str for l in lay.lines], _backend(SANS, lo), box_width)
        return (; fontsize=lo, nlines=length(kept), lines=kept, clipped=true)
    end
    best = lo                                     # binary search for largest fitting fs
    while hi - lo > tol
        mid = (lo + hi) / 2
        if fits(mid); best = mid; lo = mid else hi = mid end
    end
    lay = lay_at(best)
    return (; fontsize=best, nlines=length(lay.lines),
              lines=String[l.str for l in lay.lines], clipped=false)
end

# ---------------------------------------------------------------------------
# Author overflow
# ---------------------------------------------------------------------------

_author_label(a::AuthorRef) =
    isempty(a.given) ? a.family : string(first(a.given), ". ", a.family)

"""
    fit_authors(authors, backend; row_width, sep=", ", etal_str=" et al.") -> (shown, etal)

Greedily fit author labels into `row_width`. If all fit, returns `(authors, false)`.
Otherwise returns the prefix that fits alongside a reserved `et al.` slot, and `true`.
"""
function fit_authors(authors::Vector{AuthorRef}, backend; row_width::Real,
                     sep::AbstractString=", ", etal_str::AbstractString=" et al.")
    isempty(authors) && return (AuthorRef[], false)
    sep_w  = measure(backend, sep)
    etal_w = measure(backend, etal_str)
    # all fit without et al.?
    total = 0.0
    for (i, a) in enumerate(authors)
        total += (i == 1 ? 0.0 : sep_w) + measure(backend, _author_label(a))
    end
    total <= row_width && return (authors, false)
    # fit a prefix, reserving room for " et al."
    shown = AuthorRef[]; used = 0.0
    for a in authors
        addw = (isempty(shown) ? 0.0 : sep_w) + measure(backend, _author_label(a))
        if !isempty(shown) && used + addw + etal_w > row_width
            break
        end
        push!(shown, a); used += addw
    end
    isempty(shown) && (shown = AuthorRef[authors[1]])   # always show at least one
    return (shown, true)
end

# ---------------------------------------------------------------------------
# TLDR autosize  (M1: bound on the TRUE block height layout(...).size[2])
# ---------------------------------------------------------------------------

"""
    tldr_autosize(text; box_width, box_height, fs_min=9.0, fs_max=14.0, tol=0.25) -> fontsize

Largest body fontsize in `[fs_min, fs_max]` where the laid-out block height
(`layout(...).size[2]` = ascent + (N-1)·line_advance + descent) is ≤ `box_height`.
Never grows past `fs_max` even for a one-liner.
"""
function tldr_autosize(text::AbstractString; box_width::Real, box_height::Real,
                       fs_min::Real=9.0, fs_max::Real=14.0, tol::Real=0.25)
    block_h(fs) = layout(prepare(_backend(SERIF, fs), text); max_width=box_width).size[2]
    lo, hi = Float64(fs_min), Float64(fs_max)
    block_h(hi) <= box_height && return hi        # fits at max → no growth past max
    block_h(lo) >  box_height && return lo        # even min overflows → clamp to min
    best = lo
    while hi - lo > tol
        mid = (lo + hi) / 2
        if block_h(mid) <= box_height; best = mid; lo = mid else hi = mid end
    end
    return best
end

# ---------------------------------------------------------------------------
# Drop cap
# ---------------------------------------------------------------------------

"""
    dropcap_offset(first_para; body_fontsize, gutter=4.0) -> Float64

Horizontal wrap offset for a drop cap = advance width of the first non-space character at
`≈3×body_fontsize` (display size) + `gutter` px.
"""
function dropcap_offset(first_para::AbstractString; body_fontsize::Real, gutter::Real=4.0)
    s = strip(first_para)
    isempty(s) && return Float64(gutter)
    db = _backend(SERIF, 3 * body_fontsize)
    return measure(db, string(first(s))) + Float64(gutter)
end

# ---------------------------------------------------------------------------
# Concept pill wrap
# ---------------------------------------------------------------------------

"""
    wrap_pills(pills, backend; strip_width, pad=14.0, gap=6.0) -> Vector{Vector{String}}

Greedy row-wrap of concept pills (each an atomic segment of width `measure+2·pad`) into
`strip_width`, separated horizontally by `gap`. A pill wider than the strip gets its own row.
"""
function wrap_pills(pills::Vector{<:AbstractString}, backend; strip_width::Real,
                    pad::Real=14.0, gap::Real=6.0)
    rows = Vector{String}[]
    cur = String[]; w = 0.0
    for p in pills
        pw = measure(backend, p) + 2pad
        add = (isempty(cur) ? 0.0 : gap) + pw
        if !isempty(cur) && w + add > strip_width
            push!(rows, cur); cur = String[]; w = 0.0
            add = pw
        end
        push!(cur, String(p)); w += add
    end
    isempty(cur) || push!(rows, cur)
    return rows
end

# ---------------------------------------------------------------------------
# Citation sparkline
# ---------------------------------------------------------------------------

const _SPARK_BLOCKS = collect("▁▂▃▄▅▆▇█")

"""
    citation_sparkline(by_year, backend; target_width) -> String

Unicode block-character sparkline of the citation timeline, padded/trimmed so its measured
width matches `target_width` within ±1 glyph.
"""
function citation_sparkline(by_year::Vector{Tuple{Int,Int}}, backend; target_width::Real)
    isempty(by_year) && return ""
    counts = [c for (_, c) in by_year]
    mx = maximum(counts); mx == 0 && (mx = 1)
    n  = length(_SPARK_BLOCKS)
    chars = [_SPARK_BLOCKS[clamp(ceil(Int, c / mx * n), 1, n)] for c in counts]
    s = String(chars)
    glyphw = measure(backend, string(_SPARK_BLOCKS[1]))
    glyphw <= 0 && return s
    while target_width - measure(backend, s) > glyphw            # pad with low blocks
        s *= string(_SPARK_BLOCKS[1])
    end
    while length(s) > 1 && measure(backend, s) - target_width > glyphw   # trim
        s = chop(s)
    end
    return s
end

# ---------------------------------------------------------------------------
# Composition: infograph
# ---------------------------------------------------------------------------

# muted palette
const _INK    = CM.RGBf(0.12, 0.12, 0.14)
const _MUTED  = CM.RGBf(0.45, 0.45, 0.50)
const _ACCENT = CM.RGBf(0.16, 0.32, 0.58)
const _PILLBG = CM.RGBf(0.90, 0.92, 0.96)
const _RULE   = CM.RGBf(0.80, 0.80, 0.84)

_oa_color(s::Symbol) = s === :gold   ? CM.RGBf(0.85, 0.65, 0.10) :
                       s === :green  ? CM.RGBf(0.20, 0.55, 0.30) :
                       s === :hybrid ? CM.RGBf(0.45, 0.35, 0.65) :
                       s === :closed ? _MUTED : _MUTED

# scene-space pixel helpers; panel frame f = (x0, ybot, w, h), block-top local coords.
_sy(f, y) = f[2] + f[4] - y                     # block-top local y → scene y (up)
function _text!(sc, f, x, y, s; fontsize, font=SANS, color=_INK,
                align=(:left, :baseline), rotation=0.0)
    CM.text!(sc, CM.Point2f(f[1] + x, _sy(f, y)); text=String(s), fontsize=Float64(fontsize),
             font=font, color=color, align=align, space=:pixel, rotation=rotation)
end
function _rect!(sc, f, x, y, w, h; color, strokecolor=nothing, strokewidth=0.0)
    r = CM.Rect2f(f[1] + x, _sy(f, y + h), w, h)
    CM.poly!(sc, r; color=color, strokecolor=(strokecolor === nothing ? color : strokecolor),
             strokewidth=strokewidth, space=:pixel)
end

"""
    infograph(meta::PaperMetadata; page=(420,594), template=:editorial,
              justification=:greedy, fetch_figure=false) -> CairoMakie.Figure
    infograph(doi::AbstractString; mailto, kwargs...) -> CairoMakie.Figure

Compose a single-paper editorial infograph. The only valid `template` is `:editorial`.
`justification=:knuth_plass` falls back to greedy with a one-time `@warn` (the #K stretch
`examples/layouts/knuth_plass.jl` is absent). All measurement uses px_per_unit=1.
"""
function infograph(meta::PaperMetadata; page=(420, 594), template::Symbol=:editorial,
                   justification::Symbol=:greedy, fetch_figure::Bool=false)
    template === :editorial ||
        throw(ArgumentError("template must be :editorial; got $(repr(template))"))
    _check_justification(justification)
    fig = CM.Figure(size=page, figure_padding=0)
    sc  = fig.scene
    CM.poly!(sc, CM.Rect2f(0, 0, page[1], page[2]); color=:white, space=:pixel)
    _draw_infograph!(sc, meta, (0.0, 0.0, Float64(page[1]), Float64(page[2])))
    return fig
end

function infograph(doi::AbstractString; mailto::AbstractString, kwargs...)
    meta = fetch_doi_metadata(doi; mailto)
    return infograph(meta; kwargs...)
end

const _WARNED_KP = Ref(false)
function _check_justification(j::Symbol)
    if j === :knuth_plass && !_WARNED_KP[]
        @warn "justification=:knuth_plass unavailable (#K not shipped); falling back to greedy"
        _WARNED_KP[] = true
    elseif j ∉ (:greedy, :knuth_plass)
        throw(ArgumentError("justification must be :greedy or :knuth_plass; got $(repr(j))"))
    end
end

# Draw one infograph into scene `sc` within pixel frame `f = (x0, ybot, w, h)`.
function _draw_infograph!(sc, meta::PaperMetadata, f)
    W, H = f[3], f[4]
    M    = 0.06W                       # margin
    cw   = W - 2M                       # content width
    y    = M                            # running block-top y (down)

    # --- OA badge + journal/year line ---
    badge = uppercase(string(meta.oa_status))
    _text!(sc, f, M, y + 9, badge; fontsize=8, font=SANS, color=_oa_color(meta.oa_status))
    jline = strip(join(filter(!isempty, String[something(meta.journal, ""),
                       meta.year === nothing ? "" : string(meta.year),
                       something(meta.pp, "")]), " · "))
    isempty(jline) || _text!(sc, f, M + 70, y + 9, jline; fontsize=8, color=_MUTED)
    y += 22

    # --- title (autoshrink, ≤2 lines guaranteed) ---
    t = title_autoshrink(meta.title; box_width=cw, fs_min=14.0, fs_max=min(40.0, 0.11H))
    tla = prepare(_backend(SANS, t.fontsize), "M").metrics.line_advance   # baseline-to-baseline
    for ln in t.lines
        _text!(sc, f, M, y + t.fontsize, ln; fontsize=t.fontsize, font=SANS, color=_INK)
        y += tla
    end
    y += 6

    # --- authors row (+ et al.) ---
    ab = _backend(SANS, 9.5)
    shown, etal = fit_authors(meta.authors, ab; row_width=cw)
    astr = join((_author_label(a) for a in shown), ", ") * (etal ? " et al." : "")
    isempty(astr) || _text!(sc, f, M, y + 10, astr; fontsize=9.5, color=_ACCENT)
    y += 18

    # rule
    _rect!(sc, f, M, y, cw, 1.0; color=_RULE)
    y += 12

    # --- body region: abstract (drop-capped, shape_pack) OR tldr OR graceful fallback ---
    body_top    = y
    pills_h     = 0.0
    figure_w    = 0.34cw
    body_col_w  = cw - figure_w - 10
    body_h      = H - body_top - M - 64          # leave room for pills + sparkline footer

    # figure pillar placeholder (right), full body height
    _rect!(sc, f, M + cw - figure_w, body_top, figure_w, body_h; color=CM.RGBf(0.95,0.95,0.97),
           strokecolor=_RULE, strokewidth=1.0)
    _text!(sc, f, M + cw - figure_w + 8, body_top + body_h/2, meta.figure_url === nothing ?
           "figure" : "og:image"; fontsize=8, color=_MUTED)

    body = meta.abstract === nothing ? meta.tldr : meta.abstract
    if body !== nothing && !isempty(strip(body))
        body_fs = tldr_autosize(body; box_width=body_col_w, box_height=body_h, fs_min=9.0, fs_max=12.0)
        bb   = _backend(SERIF, body_fs)
        prep = prepare(bb, body)
        la   = prep.metrics.line_advance
        dco  = dropcap_offset(body; body_fontsize=body_fs)
        notch_h = 3 * la
        # chord_fn: left column with a drop-cap notch in the first 3 lines; empty beyond body_h
        chord = (yt, yb) -> begin
            yt >= body_h && return Tuple{Float64,Float64}[]
            left = yb <= notch_h ? dco : 0.0
            return [(left, body_col_w)]
        end
        packed = shape_pack(prep, chord; line_advance=la, min_chord_width=20.0)
        for p in packed.placements
            seg = prep.segments[p.segment_index]
            _text!(sc, f, M + p.x, body_top + p.y, seg.str; fontsize=body_fs, font=SERIF, color=_INK)
        end
        # drop cap glyph
        dcfs = 3 * body_fs
        _text!(sc, f, M, body_top + la + dcfs*0.0 + (prep.metrics.ascent), string(first(strip(body)));
               fontsize=dcfs, font=SERIF, color=_ACCENT, align=(:left, :baseline))
        y = body_top + body_h + 10
    else
        # graceful degradation (slot 6): enlarged pills + muted "abstract unavailable"
        _text!(sc, f, M, body_top + 14, "abstract unavailable"; fontsize=11, font=SANS, color=_MUTED)
        pills_h = body_h                     # pills get the whole region below
        y = body_top + 24
    end

    # --- concept pills ---
    if !isempty(meta.concepts)
        pill_fs = (meta.abstract === nothing && meta.tldr === nothing) ? 11.0 : 9.0
        pb = _backend(SANS, pill_fs)
        names = String[c[1] for c in meta.concepts[1:min(end, 8)]]
        rows = wrap_pills(names, pb; strip_width=cw, pad=8.0, gap=6.0)
        py = y
        for row in rows
            px = M
            for name in row
                pw = measure(pb, name) + 16
                _rect!(sc, f, px, py, pw, pill_fs + 8; color=_PILLBG)
                _text!(sc, f, px + 8, py + pill_fs + 1, name; fontsize=pill_fs, color=_ACCENT)
                px += pw + 6
            end
            py += pill_fs + 14
        end
        y = py
    end

    # --- citation sparkline footer ---
    if !isempty(meta.citations_by_year)
        cap = "$(meta.citations_by_year[1][1])–$(meta.citations_by_year[end][1])  ·  $(meta.citation_count) cites"
        sb  = _backend(SANS, 9.0)
        spark = citation_sparkline(meta.citations_by_year, sb; target_width=measure(sb, cap))
        fy = H - M
        _text!(sc, f, M, fy - 12, spark; fontsize=9, font=SANS, color=_ACCENT)
        _text!(sc, f, M, fy,      cap;   fontsize=9, font=SANS, color=_MUTED)
    end
    return sc
end
