"""
    StyledRun

One measured, already-positioned run of text. Internal seam between font-touching
measurement (e.g. the Makie `RichText` walk) and the pure [`bounds`](@ref) union.
Not exported in v1.

Coordinate convention: Makie's — **+y is up**, root baseline `= 0`. This is the
*opposite* of [`Layout`](@ref)/[`Line`](@ref), which use block-top `= 0` increasing
downward. The two paths never share coordinates. `ascent`/`descent` are both ≥ 0
(like [`FontMetrics`](@ref), where `descent` is positive-below-baseline).
"""
struct StyledRun
    x        :: Float64   # left edge (advance origin) on the line, px
    baseline :: Float64   # baseline y; +y up, root baseline = 0
    width    :: Float64   # advance width (sum of glyph advances, no kerning), px
    ascent   :: Float64   # ascent above baseline at this run's resolved size, px (≥ 0)
    descent  :: Float64   # descent below baseline at this run's resolved size, px (≥ 0)
end

"""
    TextBounds

Axis-aligned bounding box of laid-out text. `size = (width, height)` in px is the
field consumers read; `origin = (xmin, ymin)` in the measuring walk's coordinate
space is informational (not position-invariant). Coordinates follow [`StyledRun`](@ref)'s
convention: +y is up, root baseline = 0, so `origin[2]` is the **bottom** of the box.
Treat as read-only.
"""
struct TextBounds
    origin :: NTuple{2,Float64}
    size   :: NTuple{2,Float64}
end

"""
    bounds(runs) -> TextBounds

Pure union of each run's box `[x, x+width] × [baseline-descent, baseline+ascent]`.
Does no measuring — `runs` are already measured. Empty input → zero box. The union
takes only differences of extents, so it is correct regardless of the y sign.

# Examples
```jldoctest
julia> using TextMeasure: StyledRun, bounds

julia> b = bounds([StyledRun(0.0, 0.0, 10.0, 8.0, 2.0)]);  # baseline 0, ascent 8, descent 2

julia> b.size                              # (width, height) in px
(10.0, 10.0)

julia> b.origin                            # +y up → origin[2] is the box bottom
(0.0, -2.0)
```
"""
function bounds(runs::AbstractVector{StyledRun})
    isempty(runs) && return TextBounds((0.0, 0.0), (0.0, 0.0))
    xmin =  Inf; xmax = -Inf; ymin =  Inf; ymax = -Inf
    for r in runs
        xmin = min(xmin, r.x)
        xmax = max(xmax, r.x + r.width)
        ymin = min(ymin, r.baseline - r.descent)
        ymax = max(ymax, r.baseline + r.ascent)
    end
    return TextBounds((xmin, ymin), (xmax - xmin, ymax - ymin))
end
