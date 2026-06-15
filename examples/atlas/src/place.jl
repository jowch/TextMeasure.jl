# DECISION (Task 1 spike): raw `solve_cluster` + our own overlap recompute.
# Per-frame data→pixel projection (used by the loop task, NOT here):
#   px = Point2f(Makie.project(ax.scene, :data, :pixel, data_pt)[Vec(1,2)])  # no frame lag after update_state_before_display!
using Makie
using GeometryBasics: Point2f, Vec2f, Rect2f

const _LABEL_FONT = HouseStyle.plexmono("Regular")

struct FramePlacement
    ids     :: Vector{Int}
    anchors :: Vector{Point2f}
    sizes   :: Vector{Vec2f}
    offsets :: Vector{Vec2f}
    dropped :: BitVector
end

"Measured pixel boxes (w,h) for label strings via a TextMeasure backend (px_per_unit=1 for Makie)."
function measure_boxes(strings; fontsize = Float64(HouseStyle.RAMP.body), font = _LABEL_FONT,
                       backend = MakieBackend(; font=font, fontsize=fontsize, px_per_unit=1))
    m = TextMeasure.font_metrics(backend)
    boxh = m.ascent + m.descent
    [Vec2f(layout(prepare(backend, s)).size[1], boxh) for s in strings]
end

const _PARAMS = RepelParams(; only_move=:both, box_padding=5.0,
                            point_padding=5.5, min_segment_length=2.0)
const _SOLVER = ProjectionSolver(_PARAMS)

# Cartographic default: seed an uncontested label to the UPPER-RIGHT of its dot (Imhof's
# preferred position) instead of the solver's bare default (straight below). The seed offset
# puts the label box's lower-left corner ~_SEED_PAD px off the anchor.
const _SEED_PAD = 5.0f0
_seed_offset(sz::Vec2f) = Vec2f(sz[1]/2 + _SEED_PAD, sz[2]/2 + _SEED_PAD)

"""
One frame's placement. `prev`: town_id→prior offset (warm start). `settled`: ids to pin.
`obstacles`: fixed pixel-space `Rect2f` boxes (coastline samples, areal footprints) that
every label box is pushed ≥ point_padding px clear of. Default empty keeps the existing
callers/tests unchanged.
"""
function solve_frame(ids, anchors, sizes, bounds; prev, settled, obstacles::Vector{Rect2f}=Rect2f[],
                     seeds::Dict{Int,Vec2f}=Dict{Int,Vec2f}())
    # Always seed: warm-started ids keep their prior offset (continuity); everyone else starts
    # at their geography-aware seed (caller-supplied) or the upper-right default. The solver
    # then relaxes/legalizes from there.
    init = Vec2f[haskey(prev, ids[i]) ? prev[ids[i]] :
                 get(seeds, ids[i], _seed_offset(sizes[i])) for i in eachindex(ids)]
    pin  = BitVector(id in settled && haskey(prev, id) for id in ids)
    any(pin) || (pin = nothing)   # pass nothing when nothing is pinned (avoid length check)
    # pinned_offsets must be length n when pin_mask is provided (solver contract)
    pinned = pin !== nothing ?
             Vec2f[get(prev, id, Vec2f(0,0)) for id in ids] : Vec2f[]
    r = solve_cluster(_SOLVER, collect(Point2f, anchors), collect(Vec2f, sizes), bounds;
                      init_state=init, pin_mask=pin, pinned_offsets=pinned, obstacles=obstacles)
    FramePlacement(collect(Int, ids), collect(Point2f, anchors), collect(Vec2f, sizes),
                   r.offsets, r.dropped)
end

"Count hard label-box overlaps deterministically from offsets+sizes (our own, RNG-free)."
function recompute_overlaps(fp::FramePlacement)
    rects = [Rect2f(fp.anchors[i][1]+fp.offsets[i][1] - fp.sizes[i][1]/2,
                    fp.anchors[i][2]+fp.offsets[i][2] - fp.sizes[i][2]/2,
                    fp.sizes[i][1], fp.sizes[i][2])
             for i in eachindex(fp.ids) if !fp.dropped[i]]
    n = 0
    for i in 1:length(rects), j in i+1:length(rects)
        a, b = rects[i], rects[j]
        ox = min(a.origin[1]+a.widths[1], b.origin[1]+b.widths[1]) - max(a.origin[1], b.origin[1])
        oy = min(a.origin[2]+a.widths[2], b.origin[2]+b.widths[2]) - max(a.origin[2], b.origin[2])
        (ox > 0.5 && oy > 0.5) && (n += 1)    # 0.5px slack absorbs legalize float drift
    end
    n
end
