"""
    FontMetrics(ascent, descent, line_advance)

Vertical metrics of a backend's font, in pixels. Returned by `font_metrics(backend)` and
echoed on every [`Prepared`](@ref) and [`Layout`](@ref).

- `ascent`: baseline to the top of the tallest glyphs.
- `descent`: baseline to the bottom of the deepest glyphs, stored **positive** (a distance,
  not a signed offset).
- `line_advance`: natural baseline-to-baseline distance for single-spaced text.
"""
struct FontMetrics
    ascent       :: Float64
    descent      :: Float64
    line_advance :: Float64   # natural baseline-to-baseline distance
end

"""
    Segment(str, width, kind)

One measured token produced by [`prepare`](@ref).

- `str`: the run's text.
- `width`: advance width in px (`0.0` for a newline).
- `kind`: one of `:word`, `:space`, `:newline`.
"""
struct Segment
    str   :: String
    width :: Float64
    kind  :: Symbol
end

"""
    Prepared(segments, metrics)

Result of [`prepare`](@ref): the text tokenized into measured [`Segment`](@ref)s plus the
backend's [`FontMetrics`](@ref). Every width is measured once here; pass it to
[`layout`](@ref) as often as you like. Treat as read-only.

- `segments`: the measured tokens, in document order.
- `metrics`: the font's vertical metrics.
"""
struct Prepared
    segments :: Vector{Segment}
    metrics  :: FontMetrics
end

"""
    Prepared(; segments, metrics)

Keyword form of the positional constructor.
"""
Prepared(; segments, metrics) = Prepared(segments, metrics)

"""
    Line(str, width, x, baseline)

One laid-out line in a [`Layout`](@ref).

- `str`: the line's text, trimmed of leading/trailing whitespace.
- `width`: advance width of `str` in px.
- `x`: horizontal offset from the block's left edge (the alignment offset).
- `baseline`: baseline y with **block-top = 0**, increasing downward. See [`line_top`](@ref)
  for the line's top-left y.
"""
struct Line
    str      :: String
    width    :: Float64
    x        :: Float64
    baseline :: Float64
end

"""
    Layout(lines, size, metrics)

Result of [`layout`](@ref): the placed lines plus the overall block extent. Pure arithmetic
over a [`Prepared`](@ref), so produce as many as you like. Treat as read-only.

- `lines`: the laid-out [`Line`](@ref)s, top to bottom.
- `size`: the block's `(width, height)` in px.
- `metrics`: the [`FontMetrics`](@ref) carried through from `prepare`.
"""
struct Layout
    lines   :: Vector{Line}
    size    :: NTuple{2,Float64}
    metrics :: FontMetrics
end
