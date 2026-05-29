# SPDX-License-Identifier: MIT
# #F2 — DOIInfograph adaptive layout engine.
#
# Every primitive is measurement-driven via MakieBackend(; font, fontsize, px_per_unit=1)
# (CLAUDE.md: px_per_unit=1 to match Makie markerspace). `measure(b, text)` returns px at
# the backend's baked-in fontsize, so fontsize search = constructing a new backend per
# iteration. `measure` is imported at the module top (NOT exported by TextMeasure —
# backend contract).

const SANS  = "DejaVu Sans"        # pinned (CI font-pinning); see #J
const SERIF = "Liberation Serif"

"A px_per_unit=1 MakieBackend at `fs` px in font family `fam`."
_backend(fam::AbstractString, fs::Real) = MakieBackend(; font=fam, fontsize=Float64(fs), px_per_unit=1)

# ---------------------------------------------------------------------------
# Title autoshrink  (M2: fits(fs_min) guard + explicit clip contract)
# ---------------------------------------------------------------------------

# Truncate ONE line to fit `box_width` at `backend`, appending an ellipsis. Works on an
# atomic (space-free) token by dropping trailing characters — TextMeasure only breaks at
# whitespace, so an over-wide single token can only be shortened, not wrapped.
function _fit_line(s::AbstractString, backend, box_width::Real)
    measure(backend, s) <= box_width && return String(s)
    ell = "…"; chars = collect(s)
    for n in (length(chars) - 1):-1:0
        cand = String(chars[1:n]) * ell
        measure(backend, cand) <= box_width && return cand
    end
    return ell
end

# Reduce a layout's lines to ≤2 lines, each ≤ box_width. Returns (lines, clipped).
# Handles BOTH overflow modes: 3+ lines (drop tail into an ellipsized line 2) AND a single
# over-wide atomic token on a line (character-truncate it).
function _clip_lines(lines::Vector{String}, backend, box_width::Real)
    if length(lines) <= 1
        only = isempty(lines) ? "" : lines[1]
        fitted = _fit_line(only, backend, box_width)
        return (String[fitted], fitted != only)
    end
    l1 = lines[1]
    if measure(backend, l1) > box_width            # over-wide token already on line 1
        return (String[_fit_line(l1, backend, box_width)], true)
    end
    ell = "…"
    rest = split(join(lines[2:end], " "))
    acc = String[]
    clipped = length(lines) > 2                    # 3+ lines ⇒ we will drop tail content
    for w in rest
        cand = isempty(acc) ? String(w) : join(vcat(acc, String(w)), " ")
        if measure(backend, cand) > box_width
            clipped = true; break
        end
        push!(acc, String(w))
    end
    l2 = join(acc, " ")
    clipped && (l2 = _fit_line(l2 * ell, backend, box_width))
    return (String[l1, l2], clipped)
end

"""
    title_autoshrink(title; box_width, fs_min=14.0, fs_max=48.0, tol=0.5)
        -> (; fontsize, nlines, lines, clipped, line_advance)

Largest fontsize in `[fs_min, fs_max]` (±`tol`) such that `title` wraps to ≤2 lines whose
max line width fits `box_width`. Contract: the returned `lines` is ALWAYS ≤2 lines and
ALWAYS fits `box_width` — including the pathological case of a single unbreakable token
wider than the box, which is character-truncated with an ellipsis (`clipped=true`). If a
fit is impossible at `fs_max`, the search clamps to `fs_min` and clips. Destructures
positionally as `(fontsize, nlines) = ...` (NamedTuple iterates its values in field order).
"""
function title_autoshrink(title::AbstractString; box_width::Real,
                          fs_min::Real=14.0, fs_max::Real=48.0, tol::Real=0.5,
                          font::AbstractString=SANS)
    lay_at(fs) = layout(prepare(_backend(font, fs), title); max_width=box_width)
    # BOTH halves of the contract: ≤2 lines AND the widest line fits the box. The width
    # check catches an over-wide atomic token (which lays out to 1 line yet overflows).
    fits(lay)  = length(lay.lines) <= 2 && lay.size[1] <= box_width
    lo, hi = Float64(fs_min), Float64(fs_max)

    layhi = lay_at(hi)
    if fits(layhi)                                # already fits at max size
        return (; fontsize=hi, nlines=length(layhi.lines),
                  lines=String[l.str for l in layhi.lines], clipped=false,
                  line_advance=layhi.metrics.line_advance)
    end
    laylo = lay_at(lo)
    if !fits(laylo)                               # impossible to fit → clamp + clip
        lines, clipped = _clip_lines(String[l.str for l in laylo.lines], _backend(font, lo), box_width)
        return (; fontsize=lo, nlines=length(lines), lines=lines, clipped=clipped,
                  line_advance=laylo.metrics.line_advance)
    end
    best = lo                                     # binary search for largest fitting fs
    while hi - lo > tol
        mid = (lo + hi) / 2
        if fits(lay_at(mid)); best = mid; lo = mid else hi = mid end
    end
    lay = lay_at(best)
    return (; fontsize=best, nlines=length(lay.lines),
              lines=String[l.str for l in lay.lines], clipped=false,
              line_advance=lay.metrics.line_advance)
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
`row_width` is advisory: at least one author is always shown, so a single label wider than
`row_width` (plus `et al.`) is kept anyway and will overflow — acceptable for real author
names, which are far narrower than a title box.
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
    wrap_pills(pills, backend; strip_width, pad=8.0, gap=6.0) -> Vector{Vector{String}}

Greedy row-wrap of concept pills (each an atomic segment of width `measure+2·pad`) into
`strip_width`, separated horizontally by `gap`. A pill wider than the strip gets its own row.
"""
function wrap_pills(pills::Vector{<:AbstractString}, backend; strip_width::Real,
                    pad::Real=8.0, gap::Real=6.0)
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
width matches `target_width` to within one block-glyph advance. "One glyph" is the WIDEST
block advance, so the bound holds regardless of which block is added/removed (block advances
can differ; padding uses the lowest block `▁`, the tolerance uses the widest).
"""
function citation_sparkline(by_year::Vector{Tuple{Int,Int}}, backend; target_width::Real)
    isempty(by_year) && return ""
    counts = [c for (_, c) in by_year]
    mx = maximum(counts); mx == 0 && (mx = 1)
    n  = length(_SPARK_BLOCKS)
    chars = [_SPARK_BLOCKS[clamp(ceil(Int, c / mx * n), 1, n)] for c in counts]
    s = String(chars)
    # tolerance = widest block advance, so the ±1-glyph bound holds for any block (the test
    # and docstring agree on this); padding still uses the lowest block (low-citation years).
    glyphw = maximum(measure(backend, string(c)) for c in _SPARK_BLOCKS)
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

# House-style palette (docs/superpowers/demos-house-style.md §2 — locked, 3 accents + 1 gray).
const _INK    = CM.RGBf(0.10, 0.10, 0.10)              # body/near-black #1A1A1A
const _GRAY   = CM.RGBf(0.420, 0.447, 0.502)           # captions/footers/rules #6B7280
const _BLUE   = CM.RGBf(0.169, 0.424, 0.690)           # data: citation bars + tag chips #2B6CB0
const _GREEN  = CM.RGBf(0.106, 0.478, 0.239)           # green-OA label #1B7A3D
const _CHIPBG = CM.RGBAf(0.169, 0.424, 0.690, 0.12)    # tag-chip fill (BLUE @ 0.12)
const _HAIR   = CM.RGBAf(0.420, 0.447, 0.502, 0.15)    # hairline separators (GRAY @ 0.15)
const _BASE   = CM.RGBAf(0.420, 0.447, 0.502, 0.25)    # chart baseline (GRAY @ 0.25)

# Footer string (house-style §3); single middot U+00B7.
const _FOOTER = "TextMeasure.jl · DOI Infographic"
const _FOOTER_MARGIN = 36.0                            # outer margin (px) for the footer baseline
const _FOOTER_BAND   = 44.0                            # reserved bottom band that holds the footer

# OA access label color: GREEN for green-OA (house-style), GRAY otherwise (no off-palette hues).
_oa_color(s::Symbol) = s === :green ? _GREEN : _GRAY

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
    pw, ph = Float64(page[1]), Float64(page[2])
    total_h = ph + _FOOTER_BAND                  # reserve the house-style footer band at the bottom
    fig = CM.Figure(size=(pw, total_h), figure_padding=0)
    sc  = fig.scene
    CM.poly!(sc, CM.Rect2f(0, 0, pw, total_h); color=:white, space=:pixel)
    _draw_infograph!(sc, meta, (0.0, _FOOTER_BAND, pw, ph))   # panel sits above the footer band
    _draw_footer!(sc)
    return fig
end

# House-style §3 footer: "TextMeasure.jl · DOI Infographic", DejaVu Sans 9pt, GRAY,
# bottom-left at the 36px outer margin. Drawn once per print piece (page), not per panel.
function _draw_footer!(sc)
    CM.text!(sc, CM.Point2f(_FOOTER_MARGIN, _FOOTER_BAND / 2 - 4); text=_FOOTER,
             fontsize=9.0, font=SANS, color=_GRAY, align=(:left, :baseline), space=:pixel)
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

    # --- OA badge + journal/year line (caption tier, 9pt sans) ---
    badge = uppercase(string(meta.oa_status))
    _text!(sc, f, M, y + 10, badge; fontsize=9, font=SANS, color=_oa_color(meta.oa_status))
    jline = strip(join(filter(!isempty, String[something(meta.journal, ""),
                       meta.year === nothing ? "" : string(meta.year),
                       something(meta.pp, "")]), " · "))
    isempty(jline) || _text!(sc, f, M + 78, y + 10, jline; fontsize=9, font=SANS, color=_GRAY)
    y += 24

    # --- title: serif (house-style §1), title tier 22pt max, autoshrink ≤2 lines ---
    t = title_autoshrink(meta.title; box_width=cw, fs_min=14.0, fs_max=22.0, font=SERIF)
    tla = t.line_advance                          # baseline-to-baseline (from the autoshrink layout)
    for ln in t.lines
        _text!(sc, f, M, y + t.fontsize, ln; fontsize=t.fontsize, font=SERIF, color=_INK)
        y += tla
    end
    y += 6

    # --- authors byline (sans caption, near-black) ---
    ab = _backend(SANS, 9.0)
    shown, etal = fit_authors(meta.authors, ab; row_width=cw)
    astr = join((_author_label(a) for a in shown), ", ") * (etal ? " et al." : "")
    isempty(astr) || _text!(sc, f, M, y + 10, astr; fontsize=9, font=SANS, color=_INK)
    y += 18

    # rule
    _rect!(sc, f, M, y, cw, 1.0; color=_HAIR)
    y += 12

    # --- region geometry ---
    body_top = y
    body     = meta.abstract === nothing ? meta.tldr : meta.abstract
    has_body = body !== nothing && !isempty(strip(body))
    footer_h = 14.0                                   # DOI provenance line at the very bottom

    figure_w   = 0.34cw
    body_col_w = cw - figure_w - 12

    # concept pills: a small 2-row band beneath the body region (abstract cards only)
    pb_fs = 9.0; pb_step = pb_fs + 12.0
    pb    = _backend(SANS, pb_fs)
    pill_names = isempty(meta.concepts) ? String[] : String[c[1] for c in meta.concepts[1:min(end, 8)]]
    pill_rows  = isempty(pill_names) ? Vector{String}[] :
                 wrap_pills(pill_names, pb; strip_width=cw, pad=8.0, gap=6.0)
    band_rows  = length(pill_rows) > 2 ? pill_rows[1:2] : pill_rows
    band_h     = (has_body && !isempty(band_rows)) ? length(band_rows) * pb_step + 4.0 : 0.0

    body_h = H - body_top - M - footer_h - band_h - 10

    # figure region (right): a REAL citations-per-year chart / stat block — never an empty box.
    _draw_figure_panel!(sc, f, M + cw - figure_w, body_top, figure_w, body_h, meta)

    if has_body
        body_fs = 11.0                            # house-style body tier (serif, ragged-right)
        bb   = _backend(SERIF, body_fs)
        prep = prepare(bb, body)
        la   = prep.metrics.line_advance
        dco  = dropcap_offset(body; body_fontsize=body_fs)
        notch_h = 3 * la
        # chord_fn: left text column with a drop-cap notch in the first 3 lines; empty beyond body_h
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
        # drop cap glyph (baseline ≈ first body line's baseline)
        dcfs = 3 * body_fs
        _text!(sc, f, M, body_top + la + prep.metrics.ascent, string(first(strip(body)));
               fontsize=dcfs, font=SERIF, color=_BLUE, align=(:left, :baseline))
        _draw_pills!(sc, f, pb, band_rows, pb_fs, pb_step, M, body_top + body_h + 8)
    else
        # graceful degradation (slot 6): muted caption + ENLARGED pills fill the left column
        # (no empty whitespace where the abstract would be); figure panel still on the right.
        _text!(sc, f, M, body_top + 16, "abstract unavailable"; fontsize=11, font=SANS, color=_GRAY)
        big_fs = 14.0                             # enlarged tags = subhead tier
        bigpb  = _backend(SANS, big_fs)
        rows6  = isempty(pill_names) ? Vector{String}[] :
                 wrap_pills(pill_names, bigpb; strip_width=body_col_w, pad=9.0, gap=7.0)
        _draw_pills!(sc, f, bigpb, rows6, big_fs, big_fs + 14.0, M, body_top + 36)
    end

    # --- per-panel DOI source caption (house-style §4: 9pt sans, GRAY, left) ---
    _text!(sc, f, M, H - M, "doi:" * meta.doi; fontsize=9, font=SANS, color=_GRAY)
    return sc
end

_commas(n::Integer) = replace(string(n), r"(?<=[0-9])(?=(?:[0-9]{3})+$)" => ",")

# Draw rows of concept pills; top-left of the block at block-top (x0, y0).
function _draw_pills!(sc, f, pb, rows, fs, step, x0, y0)
    py = y0
    for row in rows
        px = x0
        for name in row
            pw = measure(pb, name) + 16
            _rect!(sc, f, px, py, pw, fs + 8; color=_CHIPBG)
            _text!(sc, f, px + 8, py + fs + 1, name; fontsize=fs, color=_BLUE)
            px += pw + 6
        end
        py += step
    end
    return py
end

# The figure region as a real data graphic: a citations-per-year bar chart with the total
# citation count, or — for papers with no citation timeline (e.g. arXiv preprints) — a small
# stat block (count + year + OA). Never an empty placeholder. Uses only `meta`'s real data.
function _draw_figure_panel!(sc, f, x, y, w, h, meta)
    _rect!(sc, f, x, y, w, h; color=CM.RGBf(0.965, 0.97, 0.98))
    pad = 9.0
    _text!(sc, f, x + pad, y + 14, "CITATIONS"; fontsize=9, font=SANS, color=_GRAY)
    _text!(sc, f, x + pad, y + 40, _commas(meta.citation_count); fontsize=22, font=SANS, color=_BLUE)
    yrs = meta.citations_by_year
    if !isempty(yrs)
        cx = x + pad; cwid = w - 2pad
        ctop = y + 52; cbot = y + h - 18
        ch = max(cbot - ctop, 8.0)
        mx = maximum(c for (_, c) in yrs); mx == 0 && (mx = 1)
        n = length(yrs); bw = cwid / n
        for (i, (_, c)) in enumerate(yrs)
            bh = c / mx * ch
            _rect!(sc, f, cx + (i - 1) * bw, cbot - bh, max(bw * 0.7, 1.0), bh; color=_BLUE)
        end
        # 1px baseline rule (GRAY @ 0.25) so the bars read as a chart, not decoration
        _rect!(sc, f, cx, cbot, cwid, 1.0; color=_BASE)
        _text!(sc, f, cx, y + h - 4, string(yrs[1][1]); fontsize=9, font=SANS, color=_GRAY)
        _text!(sc, f, x + w - pad - 22, y + h - 4, string(yrs[end][1]); fontsize=9, font=SANS, color=_GRAY)
    else
        _text!(sc, f, x + pad, y + 56, "total citations"; fontsize=9, font=SANS, color=_GRAY)
        meta.year === nothing ||
            _text!(sc, f, x + pad, y + 74, "published $(meta.year)"; fontsize=9, font=SANS, color=_INK)
        _text!(sc, f, x + pad, y + 90, "OA · $(meta.oa_status)"; fontsize=9, font=SANS, color=_oa_color(meta.oa_status))
    end
end
