# SPDX-License-Identifier: MIT
"""
    Cover

"Newer Yorker" editorial-cover demo for TextMeasure.jl (#H). Renders a hand-set
cover — display title, drop cap, body text flowing around an SVG illustration
inset, pull-quote callouts — to a vector PDF via CairoMakie. Every offset is
measurement-derived: `compose_cover` (pure) computes all placements; `render_*`
only replays them. Correctness is asserted on the `ComposedCover`, not the PDF.
"""
module Cover

using TextMeasure: prepare, layout, line_top, MakieBackend, FontMetrics,
                   Prepared, Layout, Line
using TextMeasure                       # for TextMeasure.measure / font_metrics
import TextMeasureLayouts as TML
using TextMeasureLayouts: AbstractChordFn, shape_pack, PackedLayout, Placement
import TextMeasureLayouts: chord_intervals   # `import` (not `using`) to extend on RectExclusionChordFn
import TOML

export load_config, compose_cover, ComposedCover, BBox, PlacedText
export RectExclusionChordFn
export dropcap_baseline_aligned, dropcap_bands_consecutive,
       bbox_violations, body_wrap_honors_inset
export parse_svg, svg_rings
export render_scene, render_cover

# ---- page geometry -------------------------------------------------------
# Page sizes in PostScript points (72 dpi); 1 Scene px -> 1 pt at pt_per_unit=1.
const PAGE_SIZES = Dict{String,Tuple{Float64,Float64}}(
    "letter"  => (612.0, 792.0),
    "a4"      => (595.0, 842.0),
    "tabloid" => (792.0, 1224.0),
)

# Pinned font set (DejaVu Sans + Liberation Serif). NOT TOML-overridable.
const TITLE_FONT    = "Liberation Serif Bold"
const SUBTITLE_FONT = "Liberation Serif"
const BYLINE_FONT   = "DejaVu Sans"
const BODY_FONT     = "Liberation Serif"
const DROPCAP_FONT  = "Liberation Serif Bold"
const PQ_FONT       = "DejaVu Sans"
const PQ_ATTR_FONT  = "DejaVu Sans"

# ---- geometry types ------------------------------------------------------
"""Axis-aligned bbox in the block-top frame (y down). `left<right`, `top<bottom`."""
struct BBox
    left   :: Float64
    top    :: Float64
    right  :: Float64
    bottom :: Float64
end

"""A positioned text run in ABSOLUTE page coords (block-top). `baseline` is the
text baseline y; `x` is the left edge. `font`/`fontsize` are the render+measure font."""
struct PlacedText
    text     :: String
    x        :: Float64
    baseline :: Float64
    fontsize :: Float64
    font     :: String
end

# ---- config types (filled by config.jl) ----------------------------------
struct InsetSpec
    svg_path  :: String
    x_px      :: Float64
    y_px      :: Float64
    width_px  :: Float64
    height_px :: Float64
end

struct BodyPara
    paragraph :: String
    dropcap   :: Bool
end

struct PullQuoteSpec
    text        :: String
    attribution :: String      # "" when absent
    x_px        :: Float64
    y_px        :: Float64
    width_px    :: Float64
end

struct CoverConfig
    title         :: String
    subtitle      :: String     # "" when absent
    byline        :: String     # "" when absent
    page_size     :: String
    margin_px     :: Float64
    dropcap_lines :: Int
    gutter_px     :: Float64
    inset         :: InsetSpec
    body          :: Vector{BodyPara}
    pull_quotes   :: Vector{PullQuoteSpec}
    config_dir    :: String     # dir of the toml, to resolve svg_path
end

# ---- composed result (filled by compose.jl) ------------------------------
struct PullQuotePlaced
    runs :: Vector{PlacedText}
    bbox :: BBox
end

struct ComposedCover
    page_size        :: Tuple{Float64,Float64}
    masthead         :: Vector{PlacedText}
    body             :: PackedLayout
    body_top         :: Float64
    body_runs        :: Vector{PlacedText}
    body_word_bboxes :: Vector{BBox}
    dropcap          :: Union{Nothing,PlacedText}
    dropcap_baseline :: Float64        # NaN when no dropcap
    dropcap_bbox     :: Union{Nothing,BBox}   # absolute ink box of the drop cap
    dropcap_lines    :: Int
    inset_rect       :: BBox
    inset_rings      :: Vector          # Vector{SvgRing} from svg.jl
    pull_quotes      :: Vector{PullQuotePlaced}
    rules            :: Vector{NTuple{4,Float64}}   # editorial hairlines (x1,y1,x2,y2), abs
end

include("config.jl")
include("chord.jl")
include("svg.jl")
include("compose.jl")
include("render.jl")

end # module
