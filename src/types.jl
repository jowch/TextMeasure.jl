"""Vertical font metrics in pixels. `descent` is positive (distance below baseline)."""
struct FontMetrics
    ascent       :: Float64
    descent      :: Float64
    line_advance :: Float64   # natural baseline-to-baseline distance
end

"""One measured token. `kind ∈ (:word, :space, :newline)`; newline width is 0."""
struct Segment
    str   :: String
    width :: Float64
    kind  :: Symbol
end

"""Result of `prepare`: cached per-segment widths + font metrics. Treat as read-only."""
struct Prepared
    segments :: Vector{Segment}
    metrics  :: FontMetrics
end

"""One laid-out line. `str`/`width` are trimmed of leading/trailing whitespace.
`baseline` y has block-top = 0, increasing downward; `x` is the alignment offset."""
struct Line
    str      :: String
    width    :: Float64
    x        :: Float64
    baseline :: Float64
end

"""Result of `layout`: lines, overall `(width, height)` block extent, echoed `metrics`."""
struct Layout
    lines   :: Vector{Line}
    size    :: NTuple{2,Float64}
    metrics :: FontMetrics
end
