# SPDX-License-Identifier: MIT
#
# compose_cover — the PURE layout core. Computes every text run's absolute baseline,
# the body PackedLayout wrapped around an inset-exclusion chord_fn, the drop-cap
# placement, and pull-quote boxes. NO CairoMakie. All correctness invariants are
# checked against the value it returns, per the issue's "verify at layout time" rule.

# Fixed display metrics (points). Fonts are pinned constants (Cover.jl).
const TITLE_SIZE    = 52.0
const SUBTITLE_SIZE = 18.0
const BYLINE_SIZE   = 11.0
const BODY_SIZE     = 11.0
const PQ_SIZE       = 15.0
const PQ_ATTR_SIZE  = 11.0
const SUBTITLE_GAP  = 7.0
const BYLINE_GAP    = 9.0
const BODY_GAP      = 22.0
const DROPCAP_GAP   = 6.0      # horizontal space after the drop cap
const PQ_RULE_GAP   = 6.0      # gap between a pull-quote and its bracketing rules
const PQ_HOLE_PAD   = 10.0     # extra horizontal clearance so wrap text never touches the callout rules

# WRAP-AROUND (#H ↔ #C2, WIRED): with `fill=:all`, shape_pack packs EVERY disjoint
# interval per band left-to-right, so body text flows on BOTH sides of a centered inset
# (the leftmost interval fills first, then the next). `:widest` would fill only the wider
# side. The invariants (no overlap, baseline alignment) hold either way; two-sided is the
# visual win that C2's kwarg unlocked.
const TWO_SIDED_WRAP = true
const FILL_MODE = TWO_SIDED_WRAP ? :all : :widest

_mk(font, size) = MakieBackend(; font=font, fontsize=size, px_per_unit=1.0)

# AABB overlap with a tiny tolerance (y-down frame).
function _overlap(a::BBox, b::BBox; eps=1e-6)
    (a.left < b.right - eps) && (b.left < a.right - eps) &&
    (a.top  < b.bottom - eps) && (b.top  < a.bottom - eps)
end

"""
    compose_cover(cfg) -> ComposedCover

Pure layout: resolve the page, lay out the masthead, drop cap, body (wrapped around
the inset + drop-cap + pull-quote holes via [`RectExclusionChordFn`](@ref)), and
pull quotes. Coordinates are absolute page points in the block-top frame. Touches no
rendering backend.
"""
function compose_cover(cfg::CoverConfig)::ComposedCover
    W, H = PAGE_SIZES[cfg.page_size]
    m = cfg.margin_px
    content_left  = m
    content_right = W - m
    content_top   = m
    content_bottom = H - m
    content_w = content_right - content_left

    # ---- masthead ----
    masthead = PlacedText[]
    rules = NTuple{4,Float64}[]
    tb = _mk(TITLE_FONT, TITLE_SIZE);     tm = TextMeasure.font_metrics(tb)
    cur = content_top + tm.ascent
    title_w = TextMeasure.measure(tb, cfg.title)
    push!(masthead, PlacedText(cfg.title, content_left + (content_w - title_w)/2, cur, TITLE_SIZE, TITLE_FONT))
    cur += tm.descent
    if !isempty(cfg.subtitle)
        sb = _mk(SUBTITLE_FONT, SUBTITLE_SIZE); sm = TextMeasure.font_metrics(sb)
        cur += SUBTITLE_GAP + sm.ascent
        sw = TextMeasure.measure(sb, cfg.subtitle)
        push!(masthead, PlacedText(cfg.subtitle, content_left + (content_w - sw)/2, cur, SUBTITLE_SIZE, SUBTITLE_FONT))
        cur += sm.descent
    end
    if !isempty(cfg.byline)
        bb = _mk(BYLINE_FONT, BYLINE_SIZE); bm = TextMeasure.font_metrics(bb)
        cur += BYLINE_GAP + bm.ascent
        bw = TextMeasure.measure(bb, cfg.byline)
        # right-align the byline to the rule's right end so it reads as intentional
        push!(masthead, PlacedText(cfg.byline, content_right - bw, cur, BYLINE_SIZE, BYLINE_FONT))
        cur += bm.descent
    end
    # editorial hairline separating the masthead from the body column
    rule_y = cur + BODY_GAP * 0.5
    push!(rules, (content_left, rule_y, content_right, rule_y))
    body_top = cur + BODY_GAP

    # ---- body backend / metrics ----
    body_be = _mk(BODY_FONT, BODY_SIZE)
    bmet = TextMeasure.font_metrics(body_be)
    la = bmet.line_advance

    # ---- drop cap geometry (derived from body metrics) ----
    has_dropcap = !isempty(cfg.body) && cfg.body[1].dropcap && !isempty(cfg.body[1].paragraph)
    D = cfg.dropcap_lines
    dropcap = nothing
    dropcap_baseline = NaN
    dropcap_bbox = nothing
    dropcap_hole = nothing
    paras = [p.paragraph for p in cfg.body]
    capch = ""
    if has_dropcap
        capch = uppercase(string(first(paras[1])))
        paras[1] = paras[1][nextind(paras[1], 1):end]
        # Target ascent to span D lines: the cap top should land at body_top and its
        # baseline at the D-th body line. Derive the drop-cap font size from this target
        # and the DROPCAP font's ascent at a reference size.
        target_ascent = (D - 1) * la + bmet.ascent
        ref = _mk(DROPCAP_FONT, 100.0)
        ref_asc = TextMeasure.font_metrics(ref).ascent
        dc_size = 100.0 * target_ascent / ref_asc
        dc_be  = _mk(DROPCAP_FONT, dc_size)
        dc_met = TextMeasure.font_metrics(dc_be)
        cap_w  = TextMeasure.measure(dc_be, capch)
        # IMPORTANT (cross-check integrity): the baseline is derived from the DROPCAP
        # font's MEASURED ascent at dc_size — NOT from `target_ascent` directly. This
        # routes through dc_size + the drop-cap font's own metrics, a different
        # computation path than shape_pack's body-metric line-D baseline. A wrong dc_size
        # (or a non-linear ascent at small sizes) makes `dc_met.ascent` diverge from
        # `target_ascent`, so `dropcap_baseline_aligned` fires — it is NOT a tautology.
        dropcap_ascent = dc_met.ascent
        dropcap_baseline = body_top + dropcap_ascent
        dropcap = PlacedText(capch, content_left, dropcap_baseline, dc_size, DROPCAP_FONT)
        # Ink box (absolute): top = cap top (baseline − ascent), bottom = baseline. An
        # uppercase drop cap has no descender, so the baseline is the visual bottom; using
        # the font's metric descent here would over-claim and false-overlap line D+1.
        dropcap_bbox = BBox(content_left, dropcap_baseline - dropcap_ascent,
                            content_left + cap_w, dropcap_baseline)
        # hole in body-local frame: x covers cap + gap, y covers the first D lines
        dropcap_hole = BBox(content_left, 0.0, content_left + cap_w + DROPCAP_GAP, D * la)
    end
    body_text = join(paras, "\n")
    body_prep = prepare(body_be, body_text)

    # ---- inset rect (absolute) + svg rings ----
    inset_left = m + cfg.inset.x_px
    inset_top  = m + cfg.inset.y_px
    inset_rect = BBox(inset_left, inset_top, inset_left + cfg.inset.width_px, inset_top + cfg.inset.height_px)
    svg_full   = joinpath(cfg.config_dir, cfg.inset.svg_path)
    inset_rings = isfile(svg_full) ? svg_rings(parse_svg(svg_full), inset_rect) : SvgRing[]

    # ---- pull-quote layout (each is its own text block + bbox) ----
    pq_be = _mk(PQ_FONT, PQ_SIZE);  pqm = TextMeasure.font_metrics(pq_be)
    pqa_be = _mk(PQ_ATTR_FONT, PQ_ATTR_SIZE); pqam = TextMeasure.font_metrics(pqa_be)
    pull_quotes = PullQuotePlaced[]
    pq_holes = BBox[]
    for pq in cfg.pull_quotes
        pql = pq.x_px + m; pqt = pq.y_px + m
        # top hairline of the callout, then the quote text, then a bottom hairline.
        top_rule_y = pqt
        text_top   = top_rule_y + PQ_RULE_GAP
        lay = layout(prepare(pq_be, pq.text); max_width = pq.width_px)
        runs = PlacedText[]
        for ln in lay.lines
            cx = pql + (pq.width_px - ln.width) / 2        # centered callout lines
            push!(runs, PlacedText(ln.str, cx, text_top + ln.baseline, PQ_SIZE, PQ_FONT))
        end
        text_bottom = text_top + lay.size[2]
        if !isempty(pq.attribution)
            ab = text_bottom + PQ_ATTR_SIZE * 0.4 + pqam.ascent
            aw = TextMeasure.measure(pqa_be, pq.attribution)
            push!(runs, PlacedText(pq.attribution, pql + pq.width_px - aw, ab, PQ_ATTR_SIZE, PQ_ATTR_FONT))
            text_bottom = ab + pqam.descent
        end
        bot_rule_y = text_bottom + PQ_RULE_GAP
        push!(rules, (pql, top_rule_y, pql + pq.width_px, top_rule_y))
        push!(rules, (pql, bot_rule_y, pql + pq.width_px, bot_rule_y))
        bbox = BBox(pql, top_rule_y, pql + pq.width_px, bot_rule_y)
        push!(pull_quotes, PullQuotePlaced(runs, bbox))
        # the HOLE is padded horizontally beyond the visible box so wrap text keeps a
        # clear gutter from the callout rules (the visible bbox is what overlap checks use)
        push!(pq_holes, BBox(bbox.left - PQ_HOLE_PAD, bbox.top, bbox.right + PQ_HOLE_PAD, bbox.bottom))
    end

    # ---- assemble holes (body-local frame: subtract body_top from y) ----
    holes = BBox[]
    push!(holes, BBox(inset_rect.left, inset_rect.top - body_top, inset_rect.right, inset_rect.bottom - body_top))
    dropcap_hole !== nothing && push!(holes, dropcap_hole)
    for h in pq_holes
        push!(holes, BBox(h.left, h.top - body_top, h.right, h.bottom - body_top))
    end
    region_bottom = content_bottom - body_top
    chord = RectExclusionChordFn(content_left, content_right, region_bottom, holes, cfg.gutter_px)

    # ---- pack the body ----
    # fill=:all flows body text on BOTH sides of the inset (see FILL_MODE / TWO_SIDED_WRAP).
    packed = shape_pack(body_prep, chord; line_advance = la, min_chord_width = 24.0,
                        fill = FILL_MODE)

    # ---- absolute body runs + bboxes ----
    body_runs = PlacedText[]; body_bboxes = BBox[]
    for p in packed.placements
        seg = body_prep.segments[p.segment_index]
        base = body_top + p.y
        push!(body_runs, PlacedText(seg.str, p.x, base, BODY_SIZE, BODY_FONT))
        push!(body_bboxes, BBox(p.x, base - bmet.ascent, p.x + seg.width, base + bmet.descent))
    end

    return ComposedCover((W,H), masthead, packed, body_top, body_runs, body_bboxes,
                         dropcap, dropcap_baseline, dropcap_bbox, D, inset_rect, inset_rings,
                         pull_quotes, rules)
end

# Distinct body-line baselines (body-local), sorted ascending.
_body_line_ys(c::ComposedCover) = sort(unique(round.([p.y for p in c.body.placements]; digits=6)))

"""
    dropcap_bands_consecutive(c) -> Bool

True when the first `dropcap_lines` body lines sit on CONSECUTIVE bands `1..D`, i.e.
the k-th distinct body baseline equals `(k-1)*line_advance + ascent` for `k = 1..D`.
Guards the drop-cap alignment check against a config where the inset/pull-quote
shrinks a top band below `min_chord_width` and `shape_pack` SKIPS it (which would make
the D-th distinct baseline NOT line D). Vacuously true when there is no drop cap.
"""
function dropcap_bands_consecutive(c::ComposedCover)
    c.dropcap === nothing && return true
    ys = _body_line_ys(c)
    length(ys) < c.dropcap_lines && return false
    la  = c.body.metrics.line_advance
    asc = c.body.metrics.ascent
    for k in 1:c.dropcap_lines
        isapprox(ys[k], (k - 1) * la + asc; atol = 1e-6) || return false
    end
    return true
end

"""
    dropcap_baseline_aligned(c; tol=0.5) -> Bool

True when the drop-cap baseline equals the `dropcap_lines`-th distinct body-line
baseline within `tol` px. The two sides come from DIFFERENT computations: the
drop-cap baseline is `body_top +` the DROPCAP font's measured ascent at the derived
`dc_size` (compose.jl), while the line-D baseline is `body_top + (D-1)·line_advance +`
the BODY font ascent (`shape_pack`'s band geometry). A wrong `dc_size` derivation or a
non-linear drop-cap ascent makes them diverge — so this is a real cross-check, not a
tautology. Requires consecutive top bands (see [`dropcap_bands_consecutive`](@ref)).
Vacuously true when there is no drop cap.
"""
function dropcap_baseline_aligned(c::ComposedCover; tol=0.5)
    c.dropcap === nothing && return true
    dropcap_bands_consecutive(c) || return false
    ys = _body_line_ys(c)
    line_d_abs = c.body_top + ys[c.dropcap_lines]
    return abs(c.dropcap_baseline - line_d_abs) <= tol
end

"""
    bbox_violations(c) -> Vector{Tuple{Symbol,Int,Int}}

Every overlapping pair among: body words vs inset, body words vs the drop-cap ink
box, the drop-cap box vs inset, pull-quote boxes vs inset, pull-quote boxes vs body
words, and pull-quote boxes vs each other. Empty ⇒ the "no overlap" invariant holds.
Tuples are `(:kind, i, j)` for diagnostics. The `:body_dropcap` / `:dropcap_inset`
pairs guard the novel drop-cap geometry (`dc_size → cap_w → hole`): if the cap width
or hole were miscomputed, body text would intrude into the cap box and this would
catch it.
"""
function bbox_violations(c::ComposedCover)
    v = Tuple{Symbol,Int,Int}[]
    for (i, b) in enumerate(c.body_word_bboxes)
        _overlap(b, c.inset_rect) && push!(v, (:body_inset, i, 0))
        c.dropcap_bbox !== nothing && _overlap(b, c.dropcap_bbox) && push!(v, (:body_dropcap, i, 0))
    end
    if c.dropcap_bbox !== nothing
        _overlap(c.dropcap_bbox, c.inset_rect) && push!(v, (:dropcap_inset, 0, 0))
    end
    for (qi, pq) in enumerate(c.pull_quotes)
        _overlap(pq.bbox, c.inset_rect) && push!(v, (:pq_inset, qi, 0))
        for (i, b) in enumerate(c.body_word_bboxes)
            _overlap(pq.bbox, b) && push!(v, (:pq_body, qi, i))
        end
    end
    # pairwise pull-quote overlaps (no single-pull-quote assumption)
    for qi in 1:length(c.pull_quotes), qj in (qi+1):length(c.pull_quotes)
        _overlap(c.pull_quotes[qi].bbox, c.pull_quotes[qj].bbox) && push!(v, (:pq_pq, qi, qj))
    end
    return v
end

"""
    body_wrap_honors_inset(c) -> Bool

True when no body word bbox intersects the inset rect (the wrap respected the inset
at every line). Equivalent to "no `:body_inset` entry in `bbox_violations`".
"""
body_wrap_honors_inset(c::ComposedCover) =
    !any(b -> _overlap(b, c.inset_rect), c.body_word_bboxes)
